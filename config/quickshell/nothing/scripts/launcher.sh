#!/usr/bin/env bash
# One entry point for the launcher, clipboard and emoji pickers.
#   launcher.sh apps | clipboard | emoji
# Apps always open the pill's own launcher. Clipboard and emoji use fuzzel.
set -uo pipefail
what="${1:-apps}"

# The pill launcher lives in the shell, so it opens instantly. fuzzel is only
# a last resort for when the shell isn't running.
if [ "$what" = "apps" ]; then
    pkill -x fuzzel 2>/dev/null
    qs -c nothing ipc call shell toggle launcher 2>/dev/null || exec fuzzel
    exit 0
fi

pkill -x fuzzel && exit 0 # a second press closes the fallback picker
case "$what" in
    clipboard) cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy ;;
    emoji) exec "$HOME/.config/hypr/hyprland/scripts/fuzzel-emoji.sh" copy ;;
esac
