import QtQuick
import qs.services

// Round button: outlined by default, solid accent when `active`.
Rectangle {
    id: root

    property string icon
    property bool active: false
    property real size: 40
    signal clicked

    implicitWidth: size
    implicitHeight: size
    radius: Theme.r(size / 2)
    color: "transparent"
    border.width: active ? 0 : 1
    border.color: Theme.faint

    // The fill is its own layer and only its alpha moves. Animating the
    // colour of the button itself would fade it through black.
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.border.width
        radius: root.radius
        color: root.active ? Theme.active : Theme.raised
        opacity: root.active ? 1 : (mouse.containsMouse ? 1 : 0)
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    Icon {
        anchors.centerIn: parent
        text: root.icon
        size: root.size * 0.48
        filled: root.active
        color: root.active ? Theme.activeFg : Theme.fg
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    scale: mouse.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 120 } }
}
