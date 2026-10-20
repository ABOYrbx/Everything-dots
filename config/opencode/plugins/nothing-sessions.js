// Nothing shell integration: live OpenCode session state for the "nothing" pill.
//
// The plugin runs inside the OpenCode server. Once a second it reads the
// session list and the set of running sessions from the server API and writes
// a small snapshot to ~/.local/state/nothing/opencode-sessions.json, which the
// shell's OpenCode service picks up. The event stream is mirrored as well: it
// knows exactly when a run started, which the API does not report.

import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const stateHome = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state")
const STATE_DIR = join(stateHome, "nothing")
const OUT_FILE = join(STATE_DIR, "opencode-sessions.json")
const SERVICE_FILE = join(stateHome, "opencode", "service.json")

const POLL_MS = 1000
// Idle sessions stay in the list for a while, so a session that just finished
// does not blink out of the pill.
const RECENT_MS = 15 * 60 * 1000

// session id -> { runStarted, agent, model }
const runs = new Map()
// session id -> Session.Info, filled from ctx.session.get() when the server
// API is not reachable (a standalone server has its own port).
const seen = new Map()

let ctxRef = null
let lastBody = ""
let lastWrite = 0

function service() {
  try {
    const info = JSON.parse(readFileSync(SERVICE_FILE, "utf8"))
    // The registered background service can be queried directly. A standalone
    // server (--standalone) listens somewhere else, so it is tracked with the
    // event stream alone.
    if (!info.url || !info.password || info.pid !== process.pid) return null
    return {
      url: info.url,
      auth: "Basic " + Buffer.from("opencode:" + info.password).toString("base64"),
    }
  } catch {
    return null
  }
}

async function api(svc, path) {
  const res = await fetch(svc.url + path, { headers: { Authorization: svc.auth } })
  if (!res.ok) throw new Error("HTTP " + res.status)
  const body = await res.json()
  return body?.data
}

function emptyTokens() {
  return { input: 0, output: 0, reasoning: 0, cache: { read: 0, write: 0 } }
}

function sessionEntry(info, running, now) {
  const run = runs.get(info.id)
  const updated = info.time?.updated ?? 0
  return {
    id: info.id,
    title: info.title || "Untitled session",
    directory: info.location?.directory ?? "",
    agent: info.agent ?? run?.agent ?? "",
    model: info.model?.id ?? run?.model ?? "",
    status: running ? "running" : "idle",
    parent: info.parentID ?? null,
    tokens: info.tokens ?? emptyTokens(),
    cost: info.cost ?? 0,
    created: info.time?.created ?? 0,
    updated,
    // When the current run started. The API only says "running", so a run that
    // was already going when the plugin loaded falls back to the last idle
    // time of the session.
    runStarted: running ? (run?.runStarted ?? info.time?.idle ?? updated) : 0,
  }
}

function build(infos, active, now) {
  const out = []
  for (const info of infos) {
    const running = Boolean(active?.[info.id])
    const updated = info.time?.updated ?? 0
    if (!running && now - updated > RECENT_MS) continue
    out.push(sessionEntry(info, running, now))
  }
  // Running first, then the newest.
  out.sort((a, b) => Number(b.status === "running") - Number(a.status === "running") || b.updated - a.updated)
  return out
}

function write(sessions) {
  const now = Date.now()
  const payload = JSON.stringify({ sessions })
  // Rewrite when something changed, otherwise keep the timestamp alive every
  // few seconds so the shell can tell that the plugin is still there.
  if (payload === lastBody && now - lastWrite < 10000) return
  lastBody = payload
  lastWrite = now
  const body = JSON.stringify({ updatedAt: now, sessions })
  try {
    mkdirSync(STATE_DIR, { recursive: true })
    const tmp = OUT_FILE + ".tmp"
    writeFileSync(tmp, body)
    renameSync(tmp, OUT_FILE)
  } catch (e) {
    console.error("nothing-sessions: cannot write snapshot:", e)
  }
}

// The server API knows every session; the plugin only knows the ones it has
// seen. This fills the gap for sessions that were already running.
async function refreshSeen() {
  if (!ctxRef) return
  for (const id of runs.keys()) {
    if (seen.has(id)) continue
    try {
      const info = await ctxRef.session.get({ sessionID: id })
      if (info) seen.set(id, info)
    } catch {
      // The session may be gone already.
    }
  }
}

async function refresh() {
  const now = Date.now()
  const svc = service()
  if (svc) {
    try {
      const [list, active] = await Promise.all([
        api(svc, "/api/session?limit=50"),
        api(svc, "/api/session/active"),
      ])
      write(build(Array.isArray(list) ? list : [], active ?? {}, now))
      return
    } catch (e) {
      console.error("nothing-sessions: api failed:", e)
    }
  }
  // No API (standalone server): fall back to the sessions seen in the stream.
  await refreshSeen()
  const active = {}
  for (const id of runs.keys()) active[id] = { type: "running" }
  write(build([...seen.values()], active, now))
}

function handleEvent(event) {
  const type = event?.type
  const data = event?.data
  const id = data?.sessionID
  if (!type || !id) return
  switch (type) {
    case "session.step.started":
      runs.set(id, {
        runStarted: data.started ?? Date.now(),
        agent: data.agent ?? runs.get(id)?.agent,
        model: data.model?.id ?? runs.get(id)?.model,
      })
      break
    case "session.execution.succeeded":
    case "session.execution.failed":
    case "session.execution.interrupted":
    case "session.idle":
      runs.delete(id)
      break
    case "session.deleted":
      runs.delete(id)
      seen.delete(id)
      break
    case "session.status": {
      const kind = typeof data.status === "string" ? data.status : data.status?.type
      if (kind === "running" || kind === "busy" || kind === "active") {
        if (!runs.has(id)) runs.set(id, { runStarted: Date.now() })
      } else if (kind === "idle") {
        runs.delete(id)
      }
      break
    }
  }
}

export default {
  id: "nothing.sessions",
  setup(ctx) {
    ctxRef = ctx
    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          handleEvent(event)
        }
      } catch (e) {
        console.error("nothing-sessions: event stream ended:", e)
      }
    })()
    const timer = setInterval(() => {
      void refresh()
    }, POLL_MS)
    void refresh()
    return () => {
      clearInterval(timer)
      controller.abort()
    }
  },
}
