import QtQuick
import qs.services
import qs.components

Page {
    title: "Agents"
    subtitle: "Live OpenCode sessions, shown in a small pill next to the island."

    Section {
        title: "Pill"
        CSwitch {
            label: "Show the agents pill"
            sub: "A small capsule right of the island, with the live session numbers"
            path: "agents.pill"
        }
    }

    Section {
        title: "What it shows"
        CSwitch {
            label: "Running agents"
            sub: "How many OpenCode sessions are working right now"
            path: "agents.count"
        }
        CSwitch {
            label: "Token usage"
            sub: "Tokens used by the tracked sessions (cache reads counted separately)"
            path: "agents.tokens"
        }
        CSwitch {
            label: "Elapsed time"
            sub: "How long the longest running session has been going"
            path: "agents.elapsed"
        }
    }

    Section {
        title: "Session list"
        CSwitch {
            label: "Only running sessions"
            sub: "Hide sessions that already finished from the list"
            path: "agents.onlyRunning"
        }
    }
}
