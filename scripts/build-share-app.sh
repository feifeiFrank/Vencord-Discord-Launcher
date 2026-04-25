#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
APP_DIR="$OUTPUT_DIR/Discord with Vencord Portable.app"
CONTENTS_DIR="$APP_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$RESOURCES_DIR" "$MACOS_DIR"

cp "$ROOT_DIR/templates/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/templates/AppExec" "$MACOS_DIR/DiscordWithVencordPortable"
chmod +x "$MACOS_DIR/DiscordWithVencordPortable"

cp "$ROOT_DIR/templates/portable-launcher.sh" "$RESOURCES_DIR/portable-launcher.sh"
chmod +x "$RESOURCES_DIR/portable-launcher.sh"

cd "$OUTPUT_DIR"
rm -f "Discord with Vencord Portable.app.zip" "Discord.with.Vencord.Portable.app.zip"
ditto -c -k --sequesterRsrc --keepParent "Discord with Vencord Portable.app" "Discord.with.Vencord.Portable.app.zip"
