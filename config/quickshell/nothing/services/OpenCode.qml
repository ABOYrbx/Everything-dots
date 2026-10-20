pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Live OpenCode session state.
//
// The "nothing-sessions" OpenCode plugin (~/.config/opencode/plugins/)
// writes ~/.local/state/nothing/opencode-sessions.json once a second. This
// service reads that snapshot and exposes the numbers the pill and the
// Agents view need: which sessions run, how many tokens they used and how
// long they have been going.
Singleton {
    id: root

    property var data: ({ sessions: [] })
    property bool loaded: false
    // Bumped every second so the elapsed timers keep ticking.
    property int tick: 0
    // The ids of the sessions the list shows. The list is only replaced when
    // the sessions themselves change; the values are looked up live by id.
    // Rebuilding it every second threw away the hover state of the row
    // under the mouse.
    property var rowIds: []
    property int rowLimit: 6

    readonly property var sessions: data.sessions ?? []
    // The snapshot is refreshed every second; if it goes stale the plugin is gone.
    readonly property bool fresh: loaded && Date.now() - (data.updatedAt ?? 0) < 15000
    readonly property var running: sessions.filter(s => s.status === "running")
    readonly property int count: running.length
    readonly property int total: sessions.length

    // Tokens of every tracked session (cache reads are counted separately).
    readonly property int tokens: {
        root.tick;
        return sessions.reduce((sum, s) => sum + root.tokenTotal(s), 0);
    }
    readonly property int cache: {
        root.tick;
        return sessions.reduce((sum, s) => sum + root.cacheTotal(s), 0);
    }
    // How long the longest running session has been going.
    readonly property int elapsed: {
        root.tick;
        return running.reduce((max, s) => Math.max(max, root.sessionElapsed(s)), 0);
    }
    // How long the oldest tracked session has been going.
    readonly property int age: {
        root.tick;
        return sessions.reduce((max, s) => Math.max(max, s.created ? Date.now() - s.created : 0), 0);
    }
    // The sessions the list shows, newest/running first.
    readonly property var visible: (Config.get("agents.onlyRunning") ? running : sessions).slice(0, rowLimit)

    // Keep the row ids stable. The list is only replaced when the set of
    // sessions changes, so a row under the mouse keeps its hover state while
    // the numbers next to it keep updating.
    function syncRows(list) {
        const ids = list.map(s => s.id);
        const prev = root.rowIds;
        const same = prev.length === ids.length && ids.every((id, i) => prev[i] === id);
        if (!same)
            root.rowIds = ids;
    }

    function tokenTotal(s) {
        const t = s?.tokens;
        if (!t) return 0;
        return (t.input ?? 0) + (t.output ?? 0) + (t.reasoning ?? 0);
    }

    function cacheTotal(s) {
        const c = s?.tokens?.cache;
        if (!c) return 0;
        return (c.read ?? 0) + (c.write ?? 0);
    }

    // How long this session has been running (0 when it is idle).
    function sessionElapsed(s) {
        if (!s?.runStarted) return 0;
        return Math.max(0, Date.now() - s.runStarted);
    }

    function fmtTokens(n) {
        n = n ?? 0;
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
        if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "k";
        return String(Math.round(n));
    }

    function fmtDuration(ms) {
        const s = Math.max(0, Math.floor((ms ?? 0) / 1000));
        if (s < 60) return s + "s";
        const m = Math.floor(s / 60);
        if (m < 60) return m + "m";
        const h = Math.floor(m / 60);
        return h + "h" + (m % 60 ? " " + (m % 60) + "m" : "");
    }

    // Short label for a session: the tail of its directory.
    function place(s) {
        const dir = s?.directory ?? "";
        if (!dir) return "";
        const parts = dir.split("/").filter(Boolean);
        return parts.length ? parts[parts.length - 1] : dir;
    }

    // Look a session up by id. The list is rebuilt every second, so views
    // that keep their rows alive key them by id instead of by object.
    function byId(id) {
        return sessions.find(s => s.id === id) ?? null;
    }

    FileView {
        id: file
        path: Theme.stateDir + "/opencode-sessions.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text());
            } catch (e) {
                console.warn("nothing: bad opencode-sessions.json", e);
            }
            root.syncRows(root.visible);
            root.loaded = true;
        }
        onLoadFailed: {
            root.syncRows([]);
            root.loaded = true;
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            file.reload();
            root.tick++;
        }
    }

    // The filter can change while the shell runs.
    Connections {
        target: Config
        function onDataChanged() {
            root.syncRows(root.visible);
        }
    }
}
