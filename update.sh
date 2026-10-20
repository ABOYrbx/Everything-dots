#!/usr/bin/env bash
# Everything-dots auto-updater (run by everything-dots-update.timer).
# Fast-forwards the repo and re-links configs. If a Hyprland session is
# running it reloads it and restarts the shell *inside* that session; in any
# other desktop (Plasma, niri, ...) it only updates files.
set -uo pipefail
DOTS="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$DOTS" || exit 1
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
notify() { command -v notify-send >/dev/null && notify-send -a Everything-dots "$@" 2>/dev/null; }

# A live Hyprland instance of ours (stale runtime dirs are ignored).
hypr_sig() {
    local d
    for d in $(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null); do
        HYPRLAND_INSTANCE_SIGNATURE="$d" hyprctl version >/dev/null 2>&1 && { echo "$d"; return 0; }
    done
    return 1
}

# Pull updates from upstream, push goes to the fork (remote.pushDefault).
# Both remotes are fetched: upstream carries the new commits, origin is the
# fork this repo pushes to.
UPSTREAM_REF="upstream/main"
git fetch --quiet origin || exit 0
git fetch --quiet upstream || exit 0
git rev-parse --verify --quiet "$UPSTREAM_REF" >/dev/null || exit 0
[[ "$(git rev-parse @)" == "$(git rev-parse "$UPSTREAM_REF")" ]] && exit 0
if ! git diff --quiet || ! git diff --cached --quiet; then
    notify "Update available" "Skipped: you have local changes in ${DOTS/#$HOME/~}"
    exit 0
fi
before=$(git rev-parse --short @)
# Fast-forward when possible, merge when this branch has commits of its own.
git merge --ff-only --quiet "$UPSTREAM_REF" 2>/dev/null \
    || git merge --no-edit --quiet "$UPSTREAM_REF" \
    || { notify "Update failed" "couldn't merge ${UPSTREAM_REF}"; exit 1; }
"$DOTS/install.sh" --link-only --quiet

if git diff --name-only "$before" @ | grep -qx install.sh; then
    notify "Everything-dots updated" "The installer changed - run ~/Projekte/Everything-dots/install.sh to pick up new packages"
fi

if sig=$(hypr_sig); then
    export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    hyprctl reload >/dev/null 2>&1
    # run inside Hyprland so the shell gets the session's environment;
    # restart.sh itself refuses while the screen is locked
    hyprctl dispatch 'hl.dsp.exec_cmd("~/.config/quickshell/nothing/scripts/restart.sh")' >/dev/null 2>&1
fi
notify "Everything-dots updated" "$(git log -1 --format=%s)"
