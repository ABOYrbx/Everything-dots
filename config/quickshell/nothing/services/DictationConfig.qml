pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Reads and writes hyprwhspr's config.json, so the shell's settings can
// change the dictation hotkeys and behaviour.
//
// hyprwhspr reads its config once at startup, so a change needs a restart of
// the service - `apply()` writes the file and restarts it.
Singleton {
    id: root

    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hyprwhspr"
    readonly property string path: configDir + "/config.json"

    property var data: ({})
    property bool loaded: false

    // Is hyprwhspr on the system at all? The launcher script is small, so a
    // FileView is enough to find out.
    property bool installed: false
    // Is the dictation service running right now? The island only ever shows
    // a recording when it is.
    property bool running: false
    property bool checked: false

    function check() {
        probe.running = true;
    }

    // Editable settings
    property string primary: "SUPER+ALT+D"
    property string secondary: ""
    property string cancel: ""
    property string mode: "toggle"
    property string language: "en"
    property bool grabKeys: false
    property bool osd: true

    readonly property var modes: [
        { label: "Push to talk", value: "push_to_talk" },
        { label: "Toggle", value: "toggle" },
        { label: "Auto", value: "auto" },
        { label: "Continuous", value: "continuous" }
    ]

    // The languages the Cohere model supports, in their own script where a
    // font for it is installed (the shell's mono has no CJK glyphs).
    readonly property var languages: [
        { label: "Deutsch", value: "de" },
        { label: "English", value: "en" },
        { label: "Français", value: "fr" },
        { label: "Español", value: "es" },
        { label: "Italiano", value: "it" },
        { label: "Nederlands", value: "nl" },
        { label: "Polski", value: "pl" },
        { label: "Português", value: "pt" },
        { label: "العربية", value: "ar", font: "Noto Kufi Arabic" },
        { label: "Chinese", value: "zh" },
        { label: "Japanese", value: "ja" },
        { label: "Korean", value: "ko" },
        { label: "Ελληνικά", value: "el" }
    ]

    // Pending changes, so the page can show what is not applied yet.
    property bool dirty: false
    function markDirty() { root.dirty = true; }

    // True while hyprwhspl is restarting with the new settings.
    property bool restarting: false
    Timer {
        id: restartTimer
        interval: 9000
        // By now the service is up again - ask it whether it is.
        onTriggered: {
            root.restarting = false;
            root.check();
        }
    }

    // Hyprland combo ("SUPER + ALT + D") -> hyprwhspr combo ("SUPER+ALT+D").
    function fromHyprland(combo) {
        const names = {
            Space: "SPACE", Return: "ENTER", Enter: "ENTER", Escape: "ESCAPE",
            BackSpace: "BACKSPACE", Tab: "TAB", Delete: "DELETE", Insert: "INSERT",
            Home: "HOME", End: "END", Page_Up: "PAGEUP", Page_Down: "PAGEDOWN",
            Left: "LEFT", Right: "RIGHT", Up: "UP", Down: "DOWN",
            Comma: "COMMA", Period: "PERIOD", Slash: "SLASH", Backslash: "BACKSLASH",
            Minus: "MINUS", Equal: "EQUAL", Semicolon: "SEMICOLON",
            Apostrophe: "APOSTROPHE", BracketLeft: "LEFTBRACE",
            BracketRight: "RIGHTBRACE", Grave: "GRAVE", Print: "PRINTSCREEN",
            CapsLock: "CAPSLOCK", NumLock: "NUMLOCK", ScrollLock: "SCROLLLOCK",
            Pause: "PAUSE", Menu: "MENU"
        };
        const mods = [];
        let key = "";
        for (const part of (combo ?? "").split("+")) {
            const p = part.trim();
            if (!p)
                continue;
            const u = p.toUpperCase();
            if (u === "SUPER" || u === "CTRL" || u === "ALT" || u === "SHIFT")
                mods.push(u);
            else
                key = names[p] ?? p;
        }
        if (!key)
            return "";
        return mods.concat([key]).join("+");
    }

    function resetPending() {
        root.primary = data.primary_shortcut ?? "SUPER+ALT+D";
        root.secondary = data.secondary_shortcut ?? "";
        root.cancel = data.cancel_shortcut ?? "";
        // Auto (tap to toggle, hold to talk) is the default.
        root.mode = data.recording_mode ?? "auto";
        root.language = data.language ?? "en";
        root.grabKeys = data.grab_keys === true;
        root.osd = data.mic_osd_enabled !== false;
        root.dirty = false;
    }

    // Re-read the file from disk.
    function reload() {
        file.reload();
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text());
                root.resetPending();
            } catch (e) {
                console.warn("nothing: bad hyprwhspr config", e);
            }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    // The launcher script - its presence means hyprwhspr is installed.
    FileView {
        id: binary
        path: "/usr/bin/hyprwhspr"
        printErrors: false
        onLoaded: root.installed = true
        onLoadFailed: root.installed = false
    }

    // Is the user service up?
    Process {
        id: probe
        command: ["systemctl", "--user", "is-active", "hyprwhspr.service"]
        stdout: Process.SplitByLines
        onExited: (exitCode, exitStatus) => {
            root.running = exitCode === 0;
            root.checked = true;
        }
    }

    // Write the config and restart hyprwhspr so it picks the change up.
    // Called right away on every change: hyprwhspr reads its config only at
    // startup, so a restart is the only way to make a new hotkey live.
    function apply() {
        const d = Object.assign({}, root.data);
        d.primary_shortcut = root.primary.trim() || "SUPER+ALT+D";
        if (root.secondary.trim())
            d.secondary_shortcut = root.secondary.trim();
        else
            delete d.secondary_shortcut;
        if (root.cancel.trim())
            d.cancel_shortcut = root.cancel.trim();
        else
            delete d.cancel_shortcut;
        d.recording_mode = root.mode;
        d.language = root.language;
        d.grab_keys = root.grabKeys;
        d.mic_osd_enabled = root.osd;
        try {
            file.setText(JSON.stringify(d, null, 2) + "\n");
        } catch (e) {
            console.warn("nothing: could not write hyprwhspr config", e);
        }
        root.data = d;
        root.dirty = false;
        root.restarting = true;
        restartTimer.restart();
        restart();
    }

    function restart() {
        root.restarting = true;
        restartTimer.restart();
        Quickshell.execDetached(["systemctl", "--user", "restart", "hyprwhspr"]);
    }
}
