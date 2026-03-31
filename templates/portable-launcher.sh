#!/bin/zsh
set -euo pipefail

APP_EXEC_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$APP_EXEC_DIR"

DISCORD_APP="/Applications/Discord.app"
INSTALLER_CLI="$RESOURCES_DIR/vencord-installer-cli"
VENCORD_ENTRY="$RESOURCES_DIR/Vencord/dist/patcher.js"
RUNTIME_DIR="$HOME/Library/Application Support/DiscordWithVencordPortable"
LOG_FILE="/tmp/vencord-portable-install.log"

mkdir -p "$RUNTIME_DIR"

if pgrep -x "Discord" >/dev/null 2>&1; then
    osascript -e 'tell application "Discord" to quit' >/dev/null 2>&1 || true
    sleep 2
    pkill -x "Discord" >/dev/null 2>&1 || true
fi

(
    VENCORD_USER_DATA_DIR="$RUNTIME_DIR" \
    VENCORD_DIRECTORY="$VENCORD_ENTRY" \
    VENCORD_DEV_INSTALL=1 \
    "$INSTALLER_CLI" --install --branch stable
) >"$LOG_FILE" 2>&1 || {
    osascript -e 'display alert "Vencord install failed" message "See /tmp/vencord-portable-install.log. macOS may require app-management style permissions." as critical'
    exit 1
}

open -a "$DISCORD_APP"
