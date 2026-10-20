import QtQuick
import Quickshell
import qs.services
import qs.components

// The island menu: every function the shell has, one tile each, with the
// live value of that function right on the tile. Clicking a tile opens it.
//
// The tiles are declared once (icon, name, view); the value is looked up by
// key so the tiles stay in place and only their text refreshes.
Column {
    id: root

    width: 640
    spacing: 14

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property string weatherIcon: {
        switch (Forecast.kind) {
        case "clear": return "wb_sunny";
        case "partly": return "partly_cloudy_day";
        case "cloudy": return "cloud";
        case "fog": return "foggy";
        case "rain": return "grain";
        case "snow": return "ac_unit";
        case "storm": return "thunderstorm";
        case "night": return "nightlight";
        }
        return "cloud";
    }

    readonly property var items: [
        { icon: "calendar_month", label: "Clock & Calendar", view: "calendar", key: "clock" },
        { icon: weatherIcon, label: "Weather", view: "weather", key: "weather" },
        { icon: "music_note", label: "Media", view: "media", key: "media" },
        { icon: "apps", label: "Apps", view: "launcher", key: "apps" },
        { icon: Net.wifiIcon, label: "Wi-Fi", view: "wifi", key: "wifi" },
        { icon: Net.btOn ? "bluetooth" : "bluetooth_disabled", label: "Bluetooth", view: "bluetooth", key: "bt" },
        { icon: "wallpaper", label: "Wallpaper", view: "wallpaper", key: "wallpaper" },
        { icon: "screenshot_region", label: "Capture", view: "capture", key: "capture" },
        { icon: "smart_toy", label: "Agents", view: "agents", key: "agents" },
        { icon: "tune", label: "Quick settings", view: "control", key: "control" },
        { icon: "power_settings_new", label: "Power menu", view: "power", key: "power" },
        { icon: "settings", label: "Settings", action: "settings", key: "settings" }
    ]

    function valueOf(key) {
        switch (key) {
        case "clock": return Qt.formatDateTime(clock.date, "HH:mm");
        case "weather": return Forecast.ready ? Forecast.temp + "° · " + Forecast.desc : "—";
        case "media": return Player.title !== "" ? Player.title : "Nothing";
        case "apps": return Apps.byUse.length + " Apps";
        case "wifi": return !Net.wifiOn ? "Off" : Net.active ? Net.active.name : "Not connected";
        case "bt": return !Net.btOn ? "Off" : Net.btConnected.length > 0 ? Net.btConnected[0].name : "No device";
        case "wallpaper": return Appearance.wallpaper !== "" ? Appearance.wallpaper.split("/").pop() : "No image";
        case "capture": return Toggles.recording ? "Recording" : "Screenshot";
        case "agents": return OpenCode.fresh ? OpenCode.count + " active" : "no data";
        case "control": return "Sliders · Tiles";
        case "power": return "Standby · Log out";
        case "settings": return "Appearance · Keys";
        }
        return "";
    }

    function open(item) {
        if (item.action === "settings") {
            Ui.close();
            Ui.openSettings("appearance");
            return;
        }
        Ui.open(item.view);
    }

    // Header
    Row {
        width: parent.width
        spacing: 12

        CircleButton {
            size: 32
            icon: "arrow_back"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: Ui.close()
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32 - 12 - 110
            spacing: 2
            Overline { text: "Menu" }
            Heading {
                width: parent.width
                text: Dates.longDate(clock.date)
                font.pixelSize: 22
            }
        }
        Text {
            id: clockText
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.family: Theme.serif
            font.pixelSize: 34
            color: Theme.fg
        }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.faint }

    // The functions
    Grid {
        id: grid
        width: parent.width
        columns: 4
        spacing: 8
        readonly property real tileW: (width - spacing * (columns - 1)) / columns

        Repeater {
            model: root.items

            MenuTile {
                required property var modelData
                width: grid.tileW
                icon: modelData.icon
                label: modelData.label
                value: root.valueOf(modelData.key)
                accent: (modelData.key === "agents" && OpenCode.count > 0)
                    || (modelData.key === "media" && Player.playing)
                    || (modelData.key === "capture" && Toggles.recording)
                onClicked: root.open(modelData)
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 18
        Repeater {
            model: ["esc to close", "click a tile"]
            Caption {
                required property string modelData
                text: modelData
                color: Theme.faint
            }
        }
    }
}
