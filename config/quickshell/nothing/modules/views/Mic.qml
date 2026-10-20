import QtQuick
import qs.services
import qs.components

// Dictation indicator. While hyprwhspr records, the island swaps its resting
// content for this: a pulsing dot, the state in dot-matrix, and a live
// dot-matrix level meter. When the key is released the meter turns into a
// loading scanner and stays until the text has actually been inserted.
//
// The island grows into a taller capsule for this state, so the matrix is
// drawn large enough to fill it.
Row {
    id: root

    spacing: 14
    height: 27

    // Recording is a signal, so it gets the one accent colour.
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 8
        height: 8
        radius: Theme.r(4)
        color: Dictation.state === "error" ? Theme.error : Theme.accent
        SequentialAnimation on opacity {
            running: Dictation.active
            loops: Animation.Infinite
            NumberAnimation { to: 0.2; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
    }

    DotText {
        anchors.verticalCenter: parent.verticalCenter
        text: Dictation.label
        dot: 2.6
        gap: 1.2
        color: Dictation.state === "error" ? Theme.error : Theme.fg
        glow: false
    }

    // Live level while talking, a scanner while the text is being made. Both
    // are drawn the same size, so the island keeps its shape.
    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(wave.width, loader.width)
        height: Math.max(wave.height, loader.height)

        DotWave {
            id: wave
            anchors.verticalCenter: parent.verticalCenter
            visible: !Dictation.processing
            columns: Dictation.columns
            lines: 7
            dot: 2.4
            gap: 1.1
            source: Dictation.levels
            color: Theme.accent
            offOpacity: 0.12
            glow: false
            fade: 180
        }

        DotLoader {
            id: loader
            anchors.verticalCenter: parent.verticalCenter
            visible: Dictation.processing
            count: Dictation.columns
            lines: 7
            dot: 2.4
            gap: 1.1
            color: Theme.accent
        }
    }
}
