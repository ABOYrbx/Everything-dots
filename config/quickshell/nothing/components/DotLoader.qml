import QtQuick
import qs.services
import qs.components

// Dot-matrix loading scanner: a lit band sweeping across, in the same dot
// language as the clock and the level meter. It is drawn at the size of the
// live matrix, so the island does not change shape while it waits.
DotMatrix {
    id: root

    property int count: 32   // columns
    property int lines: 7    // rows
    property int phase: 0
    property color color: Theme.accent
    property real offOpacity: 0.05
    property bool glow: false

    rows: {
        const out = [];
        for (let r = 0; r < root.lines; r++) {
            let row = "";
            for (let c = 0; c < root.count; c++) {
                const d = Math.abs(c - (root.phase % root.count));
                row += (d <= 1) ? "#" : ".";
            }
            out.push(row);
        }
        return out;
    }

    Timer {
        interval: 70
        running: true
        repeat: true
        onTriggered: root.phase = (root.phase + 1) % root.count
    }
}
