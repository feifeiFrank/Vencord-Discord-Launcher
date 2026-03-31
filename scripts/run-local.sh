#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$ROOT_DIR/.cache"
SRC_DIR="$CACHE_DIR/src"
BUILD_DIR="$CACHE_DIR/build"
RUNTIME_DIR="$HOME/Library/Application Support/DiscordWithVencordPortable"

VENCORD_REPO="$SRC_DIR/Vencord"
INSTALLER_REPO="$SRC_DIR/Installer"
INSTALLER_CLI="$BUILD_DIR/vencord-installer-cli"
PATCHER_JS="$BUILD_DIR/Vencord/dist/patcher.js"
LOG_FILE="/tmp/vencord-portable-install.log"

DISCORD_APP="/Applications/Discord.app"

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

need_cmd git
need_cmd node
need_cmd pnpm
need_cmd go

[[ -d "$DISCORD_APP" ]] || {
    echo "Discord not found at $DISCORD_APP" >&2
    exit 1
}

mkdir -p "$SRC_DIR" "$BUILD_DIR" "$RUNTIME_DIR"

info "Updating Vencord sources"
clone_or_update "https://github.com/Vendicated/Vencord.git" "$VENCORD_REPO"
info "Updating Installer sources"
clone_or_update "https://github.com/Vencord/Installer.git" "$INSTALLER_REPO"

info "Installing Vencord dependencies"
cd "$VENCORD_REPO"
pnpm install

info "Building Vencord desktop assets"
pnpm build

rm -rf "$BUILD_DIR/Vencord"
mkdir -p "$BUILD_DIR/Vencord"
cp -R "$VENCORD_REPO/dist" "$BUILD_DIR/Vencord/"

info "Building Installer CLI"
cd "$INSTALLER_REPO"
go build --tags cli -o "$INSTALLER_CLI"

if pgrep -x "Discord" >/dev/null 2>&1; then
    osascript -e 'tell application "Discord" to quit' >/dev/null 2>&1 || true
    sleep 2
    pkill -x "Discord" >/dev/null 2>&1 || true
fi

info "Patching Discord"
(
    VENCORD_USER_DATA_DIR="$RUNTIME_DIR" \
    VENCORD_DIRECTORY="$PATCHER_JS" \
    VENCORD_DEV_INSTALL=1 \
    "$INSTALLER_CLI" --install --branch stable
) >"$LOG_FILE" 2>&1 || {
    echo "Vencord install failed. See $LOG_FILE" >&2
    exit 1
}

info "Launching Discord"
open -a "$DISCORD_APP"
