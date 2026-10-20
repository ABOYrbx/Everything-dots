import QtQuick
import qs.services
import qs.components

// Hotkey field: click it, then press the combination you want.
//
// The capture reuses the shell's own recorder (Binds), so the compositor is
// put into its capture submap and the keys never reach the focused app. The
// recorded combo is handed over in hyprwhspr's own notation (ALT+SPACE).
//
// Modifier keys are tracked here rather than taken from the key event: the
// compositor can swallow a modifier on the way to the app (a Super press
// that opens the launcher, for example), and then the combo would come out
// without it.
OptRow {
    id: r

    property string value: ""
    property string placeholder: ""
    property bool listening: false
    property var held: ({})
    signal captured(string combo)
    signal cleared

    function isModifier(key) {
        return key === Qt.Key_Super || key === Qt.Key_Meta || key === Qt.Key_Alt
            || key === Qt.Key_Control || key === Qt.Key_Shift;
    }

    function modifierName(key) {
        if (key === Qt.Key_Super || key === Qt.Key_Meta) return "SUPER";
        if (key === Qt.Key_Alt) return "ALT";
        if (key === Qt.Key_Control) return "CTRL";
        if (key === Qt.Key_Shift) return "SHIFT";
        return "";
    }

    // Build the combo: the modifiers of the event plus the ones we saw being
    // pressed, then the key itself.
    function comboFrom(e) {
        const mods = [];
        const m = e.modifiers;
        if (m & Qt.MetaModifier) mods.push("SUPER");
        if (m & Qt.ControlModifier) mods.push("CTRL");
        if (m & Qt.AltModifier) mods.push("ALT");
        if (m & Qt.ShiftModifier) mods.push("SHIFT");
        for (const k of Object.keys(r.held))
            if (!mods.includes(k))
                mods.push(k);
        const key = Binds.keyName(e);
        if (!key)
            return "";
        return mods.join(" + ") + " + " + key;
    }

    Rectangle {
        id: box
        width: 230
        height: 34
        radius: Theme.r(17)
        color: Theme.raised
        border.width: r.listening ? 1 : 0
        border.color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: r.listening ? "press keys…" : (r.value !== "" ? r.value : r.placeholder)
            font.family: Theme.mono
            font.pixelSize: 12
            color: r.listening ? Theme.accent : (r.value !== "" ? Theme.fg : Theme.dim)
        }

        Item {
            id: capture
            anchors.fill: parent
            // Take the focus as soon as the recording starts, so the keys
            // land here even if the click did not focus the window.
            focus: Binds.capturing

            Keys.onPressed: e => {
                if (!Binds.capturing)
                    return;
                e.accepted = true;
                if (e.key === Qt.Key_Escape && e.modifiers === Qt.NoModifier) {
                    r.held = ({});
                    Binds.stopCapture();
                    return;
                }
                if (r.isModifier(e.key)) {
                    r.held[r.modifierName(e.key)] = true;
                    return;
                }
                const c = r.comboFrom(e);
                if (c) {
                    r.captured(DictationConfig.fromHyprland(c));
                    r.held = ({});
                    Binds.stopCapture();
                }
            }

            Keys.onReleased: e => {
                if (!Binds.capturing)
                    return;
                if (r.isModifier(e.key))
                    delete r.held[r.modifierName(e.key)];
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                r.listening = true;
                r.held = ({});
                Binds.startCapture();
                capture.forceActiveFocus();
            }
        }
    }

    // The click focuses the window, so the item needs the focus a moment
    // later - by then the window is the active one and can take it.
    Timer {
        interval: 60
        running: r.listening
        onTriggered: capture.forceActiveFocus()
    }

    // A small cross to empty an optional shortcut.
    Item {
        anchors.left: box.right
        anchors.leftMargin: 8
        anchors.verticalCenter: box.verticalCenter
        width: 24
        height: 24
        visible: r.value !== "" && !r.listening

        Rectangle {
            anchors.fill: parent
            radius: Theme.r(12)
            color: m.containsMouse ? Theme.card : Qt.alpha(Theme.card, 0)
            Text {
                anchors.centerIn: parent
                text: "×"
                font.pixelSize: 14
                color: Theme.dim
            }
            MouseArea {
                id: m
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: r.cleared()
            }
        }
    }

    Connections {
        target: Binds
        function onCapturingChanged() {
            if (!Binds.capturing) {
                r.listening = false;
                r.held = ({});
            }
        }
    }
}
