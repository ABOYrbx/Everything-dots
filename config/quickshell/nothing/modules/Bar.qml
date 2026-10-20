import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components
import qs.modules.views

// Top layer holding the island. The window is tall enough for any expanded
// view, but only the pill itself takes input (mask) or reserves space.
PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    readonly property bool here: Hyprland.focusedMonitor?.name === modelData.name
    readonly property string mode: {
        if (Agent.active && here) return "auth";
        if (Dictation.active && here) return "mic";
        if (Ui.view !== "" && here) return Ui.view;
        if (Ui.popup !== "" && here) return Ui.popup;
        return "compact";
    }
    readonly property bool expanded: mode !== "compact" && mode !== "osd" && mode !== "notif" && mode !== "mic"

    visible: Ui.barVisible
    anchors { top: true; left: true; right: true }
    implicitHeight: 820
    exclusiveZone: Theme.margin + Theme.barHeight
    color: "transparent"
    mask: Region {
        item: island
        Region { item: agentsPill.visible ? agentsPill : null }
    }

    WlrLayershell.namespace: "nothing:bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: mode === "auth" ? WlrKeyboardFocus.Exclusive
        : expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Clicking anywhere else collapses the island.
    HyprlandFocusGrab {
        windows: [win]
        active: win.expanded && win.mode !== "auth"
        onCleared: Ui.close()
    }

    Rectangle {
        id: island

        // The pointer entered the island.
        function hoverEnter() {
            state.blocked = false;
            dwell.restart();
        }
        // The pointer moved on the island.
        function hoverMove() {
            if (win.mode === "compact" && !state.blocked)
                dwell.restart();
        }
        // The pointer left the island.
        function hoverLeave() {
            dwell.stop();
        }

        readonly property Item current: {
            for (let i = 0; i < slots.children.length; i++)
                if (slots.children[i].name === win.mode)
                    return slots.children[i];
            return compact;
        }
        readonly property real padX: win.mode === "compact" || win.mode === "osd" || win.mode === "notif" || win.mode === "mic" ? 18 : 22
        // Speaking grows the island into a taller capsule instead of the
        // resting bar, so the state change is a morph, not a swap.
        readonly property real padY: win.mode === "mic" ? 18 : (win.expanded ? 20 : 0)

        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.margin
        width: current.implicitWidth + padX * 2
        height: Math.max(Theme.barHeight, current.implicitHeight + padY * 2)
        radius: Theme.r(Math.min(height / 2, Theme.radius))
        color: Theme.glass
        border.width: Config.get("pill.border") ? 1 : 0
        border.color: Qt.alpha(Theme.faint, 0.5)
        clip: true

        Behavior on width { NumberAnimation { duration: Theme.dur; easing.type: Theme.easing } }
        Behavior on height { NumberAnimation { duration: Theme.dur; easing.type: Theme.easing } }
        Behavior on radius { NumberAnimation { duration: Theme.dur; easing.type: Theme.easing } }

        focus: true
        Keys.onEscapePressed: Ui.close()

        // Right-click on the pill always collapses it.
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: Ui.close()
        }

        // The notch: the glass around the chips. Clicking it opens the menu
        // with every function the shell has, and resting the pointer on the
        // island does the same. The area sits below the slots, so the chips
        // keep their own clicks - and their mouse areas don't take the
        // hover, so the island sees it.
        MouseArea {
            id: notch
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onEntered: island.hoverEnter()
            onExited: island.hoverLeave()
            // Any movement restarts the timer, so the menu only opens when
            // the pointer rests - a quick click on a chip still hits the chip.
            onPositionChanged: island.hoverMove()
            onClicked: {
                if (win.mode === "compact") {
                    if (Config.get("menu.click"))
                        Ui.open("menu");
                } else if (win.mode !== "auth" && win.mode !== "mic" && win.mode !== "osd" && win.mode !== "notif") {
                    Ui.close();
                }
            }
        }

        Timer {
            id: dwell
            interval: Config.get("menu.hoverDelay")
            onTriggered: {
                // Only the island on the screen you're working on opens the
                // menu - the others are just a mirror of the resting bar.
                if (!Config.get("menu.hover") || !here || win.mode !== "compact" || state.blocked)
                    return;
                Ui.open("menu");
            }
        }

        // Keeps the menu from popping open again while the pointer still
        // rests on the island after it was closed.
        QtObject {
            id: state
            property bool blocked: false
            property bool wasMenu: false
        }

        Connections {
            target: Ui
            function onViewChanged() {
                if (state.wasMenu && Ui.view !== "menu")
                    state.blocked = true;
                state.wasMenu = Ui.view === "menu";
            }
        }

        Item {
            id: slots
            anchors.fill: parent

            Slot { id: compact; name: "compact"; Compact { screen: win.modelData } }
            Slot { name: "mic"; lazy: true; Mic {} }
            Slot { name: "osd"; Osd {} }
            Slot { name: "notif"; NotifPopup {} }
            Slot { name: "calendar"; lazy: true; Calendar {} }
            Slot { name: "media"; lazy: true; Media {} }
            Slot { name: "control"; lazy: true; Control {} }
            Slot { name: "wallpaper"; lazy: true; Wallpapers {} }
            Slot { name: "power"; lazy: true; Power {} }
            Slot { name: "weather"; lazy: true; Weather {} }
            Slot { name: "wifi"; lazy: true; Networks {} }
            Slot { name: "bluetooth"; lazy: true; Devices {} }
            Slot { name: "tray"; lazy: true; TrayMenu {} }
            Slot { name: "agents"; lazy: true; Agents {} }
            Slot { name: "capture"; lazy: true; Capture {} }
            Slot { name: "launcher"; Launcher {} } // not lazy: icons stay warm
            Slot { name: "menu"; lazy: true; Menu {} }
            Slot {
                name: "auth"
                lazy: true
                Auth { flow: Agent.flow }
            }
        }
    }

    // A second, smaller pill right of the island: the live OpenCode sessions
    // (how many agents run, how many tokens, for how long). Click opens the
    // agents view in the island.
    Rectangle {
        id: agentsPill

        visible: Config.get("agents.pill") && OpenCode.fresh && OpenCode.total > 0
        height: Theme.barHeight
        radius: Theme.r(height / 2)
        color: Theme.glass
        border.width: Config.get("pill.border") ? 1 : 0
        border.color: Qt.alpha(Theme.faint, 0.5)

        y: Theme.margin
        x: Math.min(island.x + island.width + Theme.margin, win.width - width - Theme.margin)
        width: row.implicitWidth + 30

        Behavior on width { NumberAnimation { duration: Theme.dur; easing.type: Theme.easing } }
        Behavior on x { NumberAnimation { duration: Theme.dur; easing.type: Theme.easing } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 9

            // Live dot: pulses while an agent works.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: Theme.r(3)
                color: OpenCode.count > 0 ? Theme.accent : Theme.faint
                SequentialAnimation on opacity {
                    running: OpenCode.count > 0
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
                }
            }

            Row {
                visible: Config.get("agents.count")
                spacing: 4
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "smart_toy"
                    size: 13
                    color: OpenCode.count > 0 ? Theme.accent : Theme.dim
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(OpenCode.count)
                    font.pixelSize: 12
                }
            }

            Row {
                visible: Config.get("agents.tokens")
                spacing: 4
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "data_usage"
                    size: 13
                    color: Theme.dim
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: OpenCode.fmtTokens(OpenCode.tokens)
                    font.pixelSize: 12
                    color: Theme.dim
                }
            }

            Row {
                visible: Config.get("agents.elapsed")
                spacing: 4
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "schedule"
                    size: 13
                    color: Theme.dim
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: OpenCode.fmtDuration(OpenCode.elapsed)
                    font.pixelSize: 12
                    color: Theme.dim
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: Ui.toggle("agents")
        }
    }

    // A view inside the island. Only the current one is visible; lazy views
    // are only instantiated while shown (plus their fade-out).
    component Slot: Item {
        id: slot

        required property string name
        property bool lazy: false
        default property Component content
        readonly property bool shown: win.mode === name

        // The incoming view waits for the outgoing one to leave, so the island
        // never shows two views at once.
        property bool revealed: false
        // Which way the last change went. `shown` is a binding and still holds
        // its old value when the fade starts, so the direction is latched here.
        property bool leaving: false
        Timer {
            id: reveal
            interval: 120
            onTriggered: slot.revealed = true
        }
        onShownChanged: {
            slot.leaving = !shown;
            if (shown)
                reveal.restart();
            else
                revealed = false;
        }
        Component.onCompleted: if (shown) revealed = true

        implicitWidth: loader.item?.implicitWidth ?? loader.item?.width ?? 0
        implicitHeight: loader.item?.implicitHeight ?? loader.item?.height ?? 0
        width: implicitWidth
        height: implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter
        // The outgoing content lifts away while the new one settles in.
        y: island.padY + (shown ? 0 : -4)

        opacity: (shown && revealed) ? 1 : 0
        visible: opacity > 0
        scale: shown ? 1 : 0.96

        Behavior on opacity {
            NumberAnimation { duration: slot.leaving ? 110 : 340; easing.type: Easing.OutCubic }
        }
        Behavior on scale { NumberAnimation { duration: Theme.dur; easing.type: Theme.easing } }
        Behavior on y { NumberAnimation { duration: Theme.dur; easing.type: Theme.easing } }

        Loader {
            id: loader
            active: !slot.lazy || slot.shown || slot.visible
            sourceComponent: slot.content
        }
    }
}
