#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
APP_DIR="$OUTPUT_DIR/Discord with Vencord Portable.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_SOURCE="$ROOT_DIR/Sources/DiscordWithVencordPortable/main.m"
CLANG="$(xcrun --find clang 2>/dev/null || command -v clang)"
STRIP="$(xcrun --find strip 2>/dev/null || command -v strip)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
ARCHIVE_NAME="Discord.with.Vencord.Portable.macOS-arm64.zip"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$ROOT_DIR/templates/Info.plist" "$CONTENTS_DIR/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS_DIR/Info.plist")"
MINIMUM_MACOS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS_DIR/Info.plist")"

"$CLANG" \
    -fobjc-arc \
    -Wall \
    -Wextra \
    -Os \
    -fvisibility=hidden \
    -isysroot "$SDKROOT" \
    -mmacosx-version-min="$MINIMUM_MACOS_VERSION" \
    -arch arm64 \
    -Wl,-dead_strip \
    -framework AppKit \
    -framework Foundation \
    "$APP_SOURCE" \
    -o "$MACOS_DIR/DiscordWithVencordPortable"

"$STRIP" -x "$MACOS_DIR/DiscordWithVencordPortable"
codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP_DIR" >/dev/null

cd "$OUTPUT_DIR"
rm -f \
    "Discord with Vencord Portable.app.zip" \
    "Discord.with.Vencord.Portable.app.zip" \
    "$ARCHIVE_NAME"
COPYFILE_DISABLE=1 /usr/bin/zip -q -r -9 -X -D "$ARCHIVE_NAME" "Discord with Vencord Portable.app"
