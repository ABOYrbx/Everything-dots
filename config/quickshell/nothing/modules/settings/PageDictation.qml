import QtQuick
import qs.services
import qs.components

// hyprwhspr settings: the dictation hotkeys and how the island behaves.
// Every change is written and applied right away - hyprwhspr reads its
// config only at startup, so the service restarts with the new settings.
Page {
    title: "Dictation"
    subtitle: "hyprwhspr dictates into the focused window. Changes are saved and applied immediately."

    Section {
        title: "Shortcuts"

        HotkeyField {
            label: "Dictate"
            sub: "Hold to talk, release to insert. Click the field, then press the keys"
            value: DictationConfig.primary
            placeholder: "SUPER+ALT+D"
            onCaptured: c => { DictationConfig.primary = c; DictationConfig.apply(); }
        }

        HotkeyField {
            label: "Second language"
            sub: "Optional. Dictates in another language while held"
            value: DictationConfig.secondary
            placeholder: "SUPER+ALT+I"
            onCaptured: c => { DictationConfig.secondary = c; DictationConfig.apply(); }
            onCleared: { DictationConfig.secondary = ""; DictationConfig.apply(); }
        }

        HotkeyField {
            label: "Cancel"
            sub: "Optional. Throws the recording away"
            value: DictationConfig.cancel
            placeholder: "SUPER+ESCAPE"
            onCaptured: c => { DictationConfig.cancel = c; DictationConfig.apply(); }
            onCleared: { DictationConfig.cancel = ""; DictationConfig.apply(); }
        }
    }

    Section {
        title: "Behaviour"

        OptChoice {
            label: "Mode"
            sub: "Push to talk records while the key is held"
            options: DictationConfig.modes
            current: DictationConfig.mode
            onPicked: v => { DictationConfig.mode = v; DictationConfig.apply(); }
        }

        OptDropdown {
            label: "Language"
            sub: "The model cannot detect the language on its own"
            options: DictationConfig.languages
            current: DictationConfig.language
            onPicked: v => { DictationConfig.language = v; DictationConfig.apply(); }
        }

        OptSwitch {
            label: "Exclusive grab"
            sub: "Swallows the shortcut so apps never see it. Needs a keyboard with a grabbable node"
            checked: DictationConfig.grabKeys
            onToggled: on => { DictationConfig.grabKeys = on; DictationConfig.apply(); }
        }

        OptSwitch {
            label: "Desktop overlay"
            sub: "The separate microphone window. The island already shows the recording"
            checked: DictationConfig.osd
            onToggled: on => { DictationConfig.osd = on; DictationConfig.apply(); }
        }
    }

    Section {
        title: "Status"

        OptRow {
            label: "hyprwhspr"
            sub: "The service loads its settings at startup, so it restarts after every change. The model is reloaded meanwhile."

            Row {
                spacing: 10

                OptButton {
                    text: "Run setup"
                    icon: "settings_suggest"
                    onClicked: Quickshell.execDetached(["kitty", "-1", "--instance-group", "nothing", "--", "hyprwhspr", "setup"])
                }

                OptButton {
                    text: "Restart"
                    icon: "restart_alt"
                    onClicked: DictationConfig.restart()
                }

                OptButton {
                    text: "Revert"
                    icon: "undo"
                    onClicked: DictationConfig.reload()
                }
            }
        }

        Caption {
            width: parent.width
            wrapMode: Text.Wrap
            color: DictationConfig.restarting ? Theme.accent : Theme.dim
            text: DictationConfig.restarting
                ? "Saved. hyprwhspr is restarting — the new hotkey works in a few seconds."
                : "Saved. Config: ~/.config/hyprwhspr/config.json"
        }

        // What is still missing, if anything.
        Caption {
            width: parent.width
            wrapMode: Text.Wrap
            color: DictationConfig.installed && DictationConfig.setUp ? Theme.dim : Theme.error
            text: !DictationConfig.installed
                ? "hyprwhspr is not installed. Install it with: yay -S hyprwhspr"
                : !DictationConfig.setUp
                    ? "hyprwhspr still needs its setup. 'Run setup' adds the API key and the model."
                    : !DictationConfig.running
                        ? "hyprwhspr is installed, but not running. Start it with: systemctl --user enable --now hyprwhspr"
                        : "hyprwhspr is running."
        }
    }
}
