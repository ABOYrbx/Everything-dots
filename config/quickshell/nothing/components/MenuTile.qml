import QtQuick
import qs.services

// One entry of the island menu: an icon, a name and the live value of
// whatever it points at. Clicking it opens that view.
Rectangle {
    id: root

    property string icon
    property string label
    property string value: ""
    property bool accent: false
    signal clicked

    implicitHeight: 78
    radius: Theme.radius
    color: hover.containsMouse ? Theme.raised : Theme.card
    Behavior on color { ColorAnimation { duration: 150 } }
    scale: hover.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 120 } }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Icon {
        id: ico
        x: 13
        y: 12
        text: root.icon
        size: 19
        color: root.accent ? Theme.accent : Theme.fg
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 13
        anchors.rightMargin: 13
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 11
        spacing: 2

        Label {
            width: parent.width
            text: root.label
            font.pixelSize: 12
            font.weight: Font.Medium
        }
        Caption {
            width: parent.width
            visible: text !== ""
            text: root.value
            font.pixelSize: 9
            elide: Text.ElideRight
        }
    }
}
