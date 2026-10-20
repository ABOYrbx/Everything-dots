import QtQuick
import qs.services
import qs.components

// OpenCode sessions: what is running right now, how many tokens it used and
// for how long. Filled by the "nothing-sessions" OpenCode plugin.
Column {
    id: root

    width: 420
    spacing: 12

    readonly property var list: OpenCode.rowIds

    // Header
    Row {
        width: parent.width
        CircleButton {
            size: 32
            icon: "arrow_back"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: Ui.close()
        }
        Overline {
            leftPadding: 10
            width: parent.width - 32 - head.width
            anchors.verticalCenter: parent.verticalCenter
            text: "OpenCode"
        }
        Caption {
            id: head
            anchors.verticalCenter: parent.verticalCenter
            text: OpenCode.fresh ? OpenCode.count + " running" : "no data"
            color: OpenCode.count > 0 ? Theme.accent : Theme.dim
        }
    }

    // Totals
    Card {
        width: parent.width
        height: totals.height + 12

        Row {
            id: totals
            x: 14
            y: 6
            width: parent.width - 28
            spacing: 16

            Column {
                width: (totals.width - 32) / 3
                spacing: 2
                Overline { text: "Agents" }
                Label { text: String(OpenCode.count); font.pixelSize: 20; color: OpenCode.count > 0 ? Theme.accent : Theme.fg }
            }
            Column {
                width: (totals.width - 32) / 3
                spacing: 2
                Overline { text: "Tokens" }
                Label { text: OpenCode.fmtTokens(OpenCode.tokens); font.pixelSize: 20 }
            }
            Column {
                width: (totals.width - 32) / 3
                spacing: 2
                Overline { text: "Running for" }
                Label { text: OpenCode.fmtDuration(OpenCode.elapsed); font.pixelSize: 20 }
            }
        }
    }

    // Sessions
    Card {
        width: parent.width
        height: list.length === 0 ? 64 : Math.min(list.length, 6) * 48 + 12

        Column {
            id: sessionList
            x: 6
            y: 6
            width: parent.width - 12

            Caption {
                visible: root.list.length === 0
                width: parent.width
                height: 52
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: OpenCode.fresh ? "No OpenCode sessions" : "Waiting for the OpenCode plugin…"
            }

            Repeater {
                model: root.list

                Item {
                    id: entry
                    required property var modelData
                    // The session behind the id, looked up live so the numbers
                    // keep updating without the row being rebuilt.
                    readonly property var s: {
                        OpenCode.sessions;
                        return OpenCode.byId(modelData) ?? {};
                    }
                    width: sessionList.width
                    height: 48

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        radius: Theme.radius
                        // Only the alpha moves, like every other list row in
                        // the shell. A colour animation here (and especially a
                        // NumberAnimation on a colour property) ended up on
                        // solid black and stayed there.
                        color: Theme.raised
                        opacity: hover.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    // Running dot
                    Rectangle {
                        id: dot
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: Theme.r(3.5)
                        color: entry.s.status === "running" ? Theme.accent : Theme.faint
                        SequentialAnimation on opacity {
                            running: entry.s.status === "running"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 28
                        width: parent.width - 28 - 150
                        spacing: 2
                        Label {
                            width: parent.width
                            text: entry.s.title || "Untitled session"
                            font.weight: Font.Medium
                        }
                        Caption {
                            width: parent.width
                            text: [OpenCode.place(entry.s), entry.s.model].filter(x => x).join(" · ")
                        }
                    }

                    // Tokens + time
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        spacing: 2
                        Label {
                            anchors.right: parent.right
                            text: OpenCode.fmtTokens(OpenCode.tokenTotal(entry.s))
                            color: Theme.fg
                        }
                        Caption {
                            anchors.right: parent.right
                            text: {
                                // The tick keeps the running time counting even
                                // though the row itself is never rebuilt.
                                OpenCode.tick;
                                return entry.s.status === "running"
                                    ? OpenCode.fmtDuration(OpenCode.sessionElapsed(entry.s))
                                    : OpenCode.fmtDuration(entry.s.updated ? Date.now() - entry.s.updated : 0) + " ago";
                            }
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }
    }
}
