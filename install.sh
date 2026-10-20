#!/usr/bin/env bash
# Everything-dots installer — Hyprland + the "nothing" Quickshell shell.
# Arch Linux and derivatives (CachyOS, EndeavourOS, Garuda, Manjaro…).
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/SambuddhaRoy/Everything-dots/main/install.sh)
#
# Options
#   --yes            don't ask, assume yes
#   --link-only      only (re)link the config files (used by the auto-updater)
#   --no-packages    skip pacman/AUR installs
#   --no-autoupdate  don't install the auto-update timer
#   --quiet          less output
#
# What it does
#   1. installs packages (official repos first, AUR as a fallback via paru/yay)
#   2. installs the Instrument Serif + Space Mono fonts (OFL, from google/fonts)
#   3. clones the repo to ~/Everything-dots and symlinks every config file into
#      ~/.config (anything it replaces is backed up first)
#   4. enables NetworkManager + Bluetooth, makes a wallpaper folder (with a
#      default dot-matrix wallpaper if it's empty) and generates the theme
#   5. installs a systemd user timer that keeps the dots up to date
set -euo pipefail

REPO_URL="https://github.com/SambuddhaRoy/Everything-dots.git"
DOTS="${EVERYTHING_DOTS:-$HOME/Everything-dots}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config/everything-dots-backup/$STAMP"

YES=0 LINK_ONLY=0 NO_PKGS=0 NO_UPDATE=0 QUIET=0
for a in "$@"; do
    case "$a" in
        --yes|-y) YES=1 ;;
        --link-only) LINK_ONLY=1 ;;
        --no-packages) NO_PKGS=1 ;;
        --no-autoupdate) NO_UPDATE=1 ;;
        --quiet|-q) QUIET=1 ;;
        -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------- helpers
c_dim=$'\033[2m' c_b=$'\033[1m' c_red=$'\033[31m' c_off=$'\033[0m'
say()  { [[ $QUIET == 1 ]] || printf '%s●%s %s\n' "$c_b" "$c_off" "$*"; }
note() { [[ $QUIET == 1 ]] || printf '  %s%s%s\n' "$c_dim" "$*" "$c_off"; }
die()  { printf '%s● %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }
ask()  { [[ $YES == 1 ]] && return 0; read -rp "  $1 [Y/n] " r </dev/tty; [[ -z "$r" || "$r" =~ ^[Yy] ]]; }

NOCONFIRM=(); [[ $YES == 1 ]] && NOCONFIRM=(--noconfirm)

[[ $EUID -ne 0 ]] || die "Run this as your normal user, not root (it uses sudo when needed)."
command -v pacman >/dev/null || die "This installer is for Arch Linux and derivatives (pacman not found)."

# ---------------------------------------------------------------- repo
get_repo() {
    # Running from a checkout? Use it.
    local here
    here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}")")" 2>/dev/null && pwd || true)"
    if [[ -n "$here" && -d "$here/config/quickshell/nothing" ]]; then
        DOTS="$here"
    elif [[ -d "$DOTS/.git" ]]; then
        say "Updating $DOTS"
        git -C "$DOTS" pull --ff-only --quiet || note "couldn't fast-forward; using what's there"
    else
        command -v git >/dev/null || sudo pacman -S --needed --noconfirm git
        say "Cloning Everything-dots to $DOTS"
        git clone --depth 1 "$REPO_URL" "$DOTS"
    fi
}

# ---------------------------------------------------------------- packages
REPO_PKGS=(
    hyprland hypridle hyprlock hyprsunset hyprpicker hyprshot xdg-desktop-portal-hyprland
    grim slurp wl-clipboard cliphist wf-recorder swappy
    kitty fuzzel
    pipewire pipewire-pulse wireplumber playerctl brightnessctl cava
    networkmanager bluez bluez-utils upower
    polkit gnome-keyring libnotify xdg-user-dirs gtk3
    jq curl git python imagemagick libqalculate
    qt6-5compat qt6-svg qt6-wayland qt6-multimedia qt6-imageformats
    ttf-jetbrains-mono-nerd papirus-icon-theme noto-fonts noto-fonts-emoji
)
# name in the official repos | AUR fallback
FLEX_PKGS=(
    "quickshell|quickshell-git"
    "matugen|matugen-bin"
    "ttf-material-symbols-variable|ttf-material-symbols-variable-git"
    "bibata-cursor-theme|bibata-cursor-theme-bin"
)

aur_helper() {
    for h in paru yay; do command -v "$h" >/dev/null && { echo "$h"; return; }; done
    # everything but the final name goes to stderr: callers capture stdout
    say "Installing yay (AUR helper)" >&2
    sudo pacman -S --needed --noconfirm base-devel git >&2
    local tmp; tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" >&2
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm) >&2
    rm -rf "$tmp"
    echo yay
}

install_packages() {
    say "Checking packages"
    local repo=() aur=() missing
    # pacman -T understands "provides", so e.g. quickshell-git satisfies quickshell
    local skip=()
    # PulseAudio setups (older Plasma installs): pipewire-pulse would ask to
    # remove it. Leave audio alone; the shell's volume/waveform need PipeWire.
    if pacman -Qq pulseaudio >/dev/null 2>&1; then
        skip+=(pipewire-pulse wireplumber)
        note "PulseAudio is installed - leaving your audio stack alone (volume controls need PipeWire)"
    fi
    for p in "${REPO_PKGS[@]}"; do
        [[ " ${skip[*]} " == *" $p "* ]] && continue
        pacman -T "$p" >/dev/null 2>&1 || repo+=("$p")
    done
    for pair in "${FLEX_PKGS[@]}"; do
        local name="${pair%%|*}" alt="${pair##*|}"
        pacman -T "$name" >/dev/null 2>&1 && continue
        pacman -T "$alt" >/dev/null 2>&1 && continue
        # any package that ships the cursor theme will do
        [[ "$name" == bibata-cursor-theme && ( -d /usr/share/icons/Bibata-Modern-Classic || -d "$HOME/.local/share/icons/Bibata-Modern-Classic" ) ]] && continue
        if pacman -Si "$name" >/dev/null 2>&1; then repo+=("$name"); else aur+=("$alt"); fi
    done
    if ((${#repo[@]})); then
        note "from the repos: ${repo[*]}"
        ask "Install ${#repo[@]} package(s) with pacman?" && sudo pacman -S --needed "${NOCONFIRM[@]}" "${repo[@]}"
    fi
    if ((${#aur[@]})); then
        note "from the AUR: ${aur[*]}"
        if ask "Install ${#aur[@]} AUR package(s)?"; then
            local h; h="$(aur_helper)"
            "$h" -S --needed "${NOCONFIRM[@]}" "${aur[@]}"
        fi
    fi
    ((${#repo[@]} + ${#aur[@]})) || note "everything's already installed"
}

install_fonts() {
    local dir="$HOME/.local/share/fonts/everything-dots" base="https://raw.githubusercontent.com/google/fonts/main/ofl"
    local fams; fams="$(fc-list : family 2>/dev/null)" # (grep -q on a pipe trips pipefail)
    if grep -q "Instrument Serif" <<<"$fams" && grep -q "Space Mono" <<<"$fams"; then return; fi
    say "Installing fonts (Instrument Serif, Space Mono — OFL)"
    mkdir -p "$dir"
    # Regular/Bold only: Qt picks Space Mono's italic face otherwise.
    for f in instrumentserif/InstrumentSerif-Regular.ttf spacemono/SpaceMono-Regular.ttf spacemono/SpaceMono-Bold.ttf \
             instrumentserif/OFL.txt; do
        curl -fsSL "$base/$f" -o "$dir/$(basename "$f" | sed 's/^OFL.txt$/OFL-InstrumentSerif.txt/')"
    done
    fc-cache -f "$dir" >/dev/null
}

# ---------------------------------------------------------------- configs
# A Hyprland config that isn't ours is moved aside whole (not merged file by
# file), so leftovers can't clash. Nothing outside ~/.config/hypr and
# ~/.config/quickshell/nothing is ever touched: Plasma, niri, other
# Quickshell configs, kitty, GTK and matugen setups are left as they are.
adopt_dir() {
    local dir="$HOME/.config/$1"
    [[ -d "$dir" && ! -L "$dir" ]] || return 0
    find "$dir" -type l -lname "$DOTS/*" -print -quit | grep -q . && return 0 # already ours
    [[ -z "$(ls -A "$dir")" ]] && return 0
    mkdir -p "$BACKUP"
    mv "$dir" "$BACKUP/$1"
    note "moved your existing ~/.config/$1 to ${BACKUP/#$HOME/~}/$1"
}

link_configs() {
    say "Linking configs into ~/.config"
    local src rel dst n=0
    adopt_dir hypr
    adopt_dir quickshell/nothing
    while IFS= read -r -d '' src; do
        rel="${src#"$DOTS/config/"}"
        dst="$HOME/.config/$rel"
        if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then continue; fi
        if [[ -e "$dst" || -L "$dst" ]]; then
            mkdir -p "$(dirname "$BACKUP/$rel")"
            mv "$dst" "$BACKUP/$rel"
        fi
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        n=$((n + 1))
    done < <(find "$DOTS/config" -type f -print0)
    # links left behind by files that were removed upstream
    while IFS= read -r -d '' l; do
        [[ "$(readlink "$l")" == "$DOTS/config/"* && ! -e "$l" ]] && rm -f "$l"
    done < <(find "$HOME/.config/hypr" "$HOME/.config/quickshell/nothing" -type l -print0 2>/dev/null)
    chmod +x "$DOTS"/config/quickshell/nothing/scripts/*.sh "$DOTS"/config/quickshell/nothing/scripts/*.py \
             "$DOTS"/config/quickshell/nothing/bin/* "$DOTS"/config/hypr/hyprland/scripts/*.sh 2>/dev/null || true
    ((n)) && note "$n file(s) linked" || note "already linked"
    [[ -d "$BACKUP" ]] && note "replaced files backed up to ${BACKUP/#$HOME/~}"
    return 0
}

# ---------------------------------------------------------------- system
enable_services() {
    local s todo=()
    # Don't fight another network daemon (systemd-networkd, iwd, connman...).
    local other=""
    for s in systemd-networkd iwd connman dhcpcd netctl; do
        systemctl is-active --quiet "$s" 2>/dev/null && other="$s"
    done
    if systemctl is-enabled NetworkManager >/dev/null 2>&1; then :
    elif [[ -n "$other" ]]; then note "$other manages your network - not enabling NetworkManager (the Wi-Fi panel needs it)"
    else todo+=(NetworkManager); fi
    systemctl is-enabled bluetooth >/dev/null 2>&1 || todo+=(bluetooth)
    ((${#todo[@]})) || return 0
    say "Enabling ${todo[*]}"
    ask "Enable and start ${todo[*]}?" && sudo systemctl enable --now "${todo[@]}"
}

wallpaper() {
    local dir; dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpapers"
    mkdir -p "$dir"
    if [[ -z "$(find "$dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) -print -quit)" ]]; then
        say "Making a default wallpaper (browse more in Settings › Wallhaven)"
        local tmp; tmp="$(mktemp -d)"
        magick -size 36x36 xc:'#050505' -fill '#1b1b1b' -draw 'circle 18,18 18,20.5' "$tmp/dot.png"
        magick -size 3840x2160 tile:"$tmp/dot.png" -fill '#d71921' -draw 'circle 2880,1440 2880,1462' \
            "$dir/everything-dots-default.png"
        rm -rf "$tmp"
    fi
}

first_run() {
    say "Generating theme"
    local shell="$HOME/.config/quickshell/nothing"
    "$shell/scripts/theme.sh" >/dev/null 2>&1 || note "theme will be generated on first login"
    "$shell/scripts/look.sh" >/dev/null 2>&1 || true
    [[ -e "$HOME/.config/hypr/hypridle.conf" && ! -L "$HOME/.config/hypr/hypridle.conf" ]] || "$shell/scripts/idle.sh" >/dev/null 2>&1 || true
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        hyprctl reload >/dev/null 2>&1 || true
        "$shell/scripts/restart.sh" >/dev/null 2>&1 || true
    fi
}

autoupdate() {
    say "Installing the auto-updater (systemd user timer)"
    local u="$HOME/.config/systemd/user"
    mkdir -p "$u"
    cat > "$u/everything-dots-update.service" <<EOF
[Unit]
Description=Update Everything-dots
After=network-online.target

[Service]
Type=oneshot
ExecStart=$DOTS/update.sh
EOF
    cat > "$u/everything-dots-update.timer" <<EOF
[Unit]
Description=Update Everything-dots every few hours

[Timer]
OnBootSec=10min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now everything-dots-update.timer >/dev/null
    note "check with: systemctl --user list-timers everything-dots-update.timer"
}

# ---------------------------------------------------------------- main
get_repo
if [[ $LINK_ONLY == 1 ]]; then
    link_configs
    exit 0
fi

printf '\n  %sEverything-dots%s — Hyprland + the nothing shell\n\n' "$c_b" "$c_off"
[[ $NO_PKGS == 1 ]] || install_packages
install_fonts
link_configs
enable_services
wallpaper
first_run
[[ $NO_UPDATE == 1 ]] || autoupdate

cat <<EOF

  ${c_b}Done.${c_off}
  Log into the Hyprland session (or run ${c_b}hyprctl reload${c_off} if you're in it).
  Tap Super for the launcher, Super+I for Settings, Super+Print to capture.
  Your dots live in ${DOTS/#$HOME/~} and update themselves.
  Other desktops (Plasma, niri, ...) are untouched - pick Hyprland at login.

EOF
