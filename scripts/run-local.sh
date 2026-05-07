#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$ROOT_DIR/.cache"
SRC_DIR="$CACHE_DIR/src"
BUILD_DIR="$CACHE_DIR/build"
VENCORD_DATA_DIR="$HOME/Library/Application Support/Vencord"
VENCORD_DIST_DIR="$VENCORD_DATA_DIR/dist"
LOG_FILE="/tmp/vencord-portable-install.log"

INSTALLER_REPO="$SRC_DIR/Installer"
INSTALLER_CLI="$BUILD_DIR/vencord-installer-cli"
DISCORD_APP="/Applications/Discord.app"
DISCORD_RESOURCES="$DISCORD_APP/Contents/Resources"

info() {
    printf '[info] %s\n' "$1"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

clone_or_update() {
    local repo_url="$1"
    local repo_dir="$2"

    if [[ -d "$repo_dir/.git" ]]; then
        git -C "$repo_dir" pull --ff-only
    else
        git clone "$repo_url" "$repo_dir"
    fi
}

is_discord_patched() {
    [[ -f "$DISCORD_RESOURCES/app.asar" && -f "$DISCORD_RESOURCES/_app.asar" ]] || return 1
    grep -Fq "$VENCORD_DIST_DIR/patcher.js" "$DISCORD_RESOURCES/app.asar"
}

need_cmd git
need_cmd go

[[ -d "$DISCORD_APP" ]] || {
    echo "Discord not found at $DISCORD_APP" >&2
    exit 1
}

mkdir -p "$SRC_DIR" "$BUILD_DIR" "$VENCORD_DATA_DIR"

info "Updating Installer sources"
clone_or_update "https://github.com/Vencord/Installer.git" "$INSTALLER_REPO"

info "Building Installer CLI"
cd "$INSTALLER_REPO"
go build --tags cli -o "$INSTALLER_CLI"

if pgrep -x "Discord" >/dev/null 2>&1; then
    osascript -e 'tell application "Discord" to quit' >/dev/null 2>&1 || true
    sleep 2
    pkill -x "Discord" >/dev/null 2>&1 || true
fi

info "Updating Vencord and patching Discord"
(
    VENCORD_USER_DATA_DIR="$VENCORD_DATA_DIR" \
    "$INSTALLER_CLI" --repair --branch stable
) >"$LOG_FILE" 2>&1 || {
    echo "Vencord install failed. See $LOG_FILE" >&2
    exit 1
}

is_discord_patched || {
    echo "Discord was not patched successfully. See $LOG_FILE" >&2
    exit 1
}

info "Launching Discord"
open -a "$DISCORD_APP"
