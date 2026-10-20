import QtQuick
import qs.services
import qs.components

// Dropdown: a pill that opens a list of options below the control.
//
// The list sits below the row as its own block, so the page grows by exactly
// the height of the list - the label keeps its place and nothing is ever
// drawn over the content.
Column {
    id: r

    property string label: ""
    property string sub: ""
    property var options: []   // [{ label, value }]
    property var current
    property bool open: false
    property int menuWidth: 200
    property int maxListHeight: 250
    signal picked(var value)

    width: parent ? parent.width : 400
    spacing: 4

    function labelOf(value) {
        for (const o of r.options)
            if (o.value === value)
                return o.label;
        return value ?? "";
    }

    OptRow {
        id: row
        width: parent.width
        label: r.label
        sub: r.sub

        Item {
            id: ctrl
            width: r.menuWidth
            height: 34

            Rectangle {
                id: btn
                width: parent.width
                height: parent.height
                radius: Theme.r(height / 2)
                color: m.containsMouse ? Theme.raised : Qt.alpha(Theme.raised, 0)
                border.width: 1
                border.color: r.open ? Theme.accent : Theme.faint
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Label {
                        text: r.labelOf(r.current)
                        font.pixelSize: 12
                        color: Theme.fg
                    }
                    Icon {
                        text: "expand_more"
                        size: 14
                        color: Theme.dim
                    }
                }

                MouseArea {
                    id: m
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: r.open = !r.open
                }
            }
        }
    }

    Rectangle {
        id: list
        visible: r.open
        anchors.right: parent.right
        anchors.rightMargin: 22
        width: r.menuWidth
        // The list never grows past a screenful - it scrolls instead.
        height: Math.min(r.maxListHeight, col.implicitHeight + 8)
        radius: Theme.r(Theme.radius)
        color: Theme.card
        border.width: 1
        border.color: Theme.faint
        clip: true

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 4
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: flick.width

                Repeater {
                    model: r.options

                    Rectangle {
                        required property var modelData
                        width: col.width
                        height: 30
                        radius: Theme.r(8)
                        color: h.containsMouse ? Theme.fg : Qt.alpha(Theme.fg, 0)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            text: parent.modelData.label
                            font.family: parent.modelData.font ?? Theme.mono
                            font.pixelSize: 12
                            color: h.containsMouse ? Theme.bg : Theme.fg
                            elide: Text.ElideRight
                            width: parent.width - 20
                        }

                        MouseArea {
                            id: h
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                r.current = parent.modelData.value;
                                r.open = false;
                                r.picked(parent.modelData.value);
                            }
                        }
                    }
                }
            }
        }

        // Thin scroll indicator, same as the page has.
        Rectangle {
            visible: flick.contentHeight > flick.height
            x: flick.width - width
            y: flick.contentY * (flick.height / flick.contentHeight)
            width: 3
            height: Math.max(30, flick.height * (flick.height / flick.contentHeight))
            radius: Theme.r(1.5)
            color: Theme.faint
            opacity: 0.6
        }
    }
}
