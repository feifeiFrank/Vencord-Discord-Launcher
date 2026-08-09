#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
APP_DIR="$OUTPUT_DIR/Discord with Vencord Portable.app"
CONTENTS_DIR="$APP_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MACOS_DIR="$CONTENTS_DIR/MacOS"
APP_SOURCE="$ROOT_DIR/Sources/DiscordWithVencordPortable/main.m"
CLANG="$(xcrun --find clang 2>/dev/null || command -v clang)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP_DIR"
mkdir -p "$RESOURCES_DIR" "$MACOS_DIR"

cp "$ROOT_DIR/templates/Info.plist" "$CONTENTS_DIR/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS_DIR/Info.plist")"
MINIMUM_MACOS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS_DIR/Info.plist")"

"$CLANG" \
    -fobjc-arc \
    -Wall \
    -Wextra \
    -isysroot "$SDKROOT" \
    -mmacosx-version-min="$MINIMUM_MACOS_VERSION" \
    -arch arm64 \
    -arch x86_64 \
    -framework AppKit \
    -framework Foundation \
    "$APP_SOURCE" \
    -o "$MACOS_DIR/DiscordWithVencordPortable"

codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP_DIR" >/dev/null

cd "$OUTPUT_DIR"
rm -f "Discord with Vencord Portable.app.zip" "Discord.with.Vencord.Portable.app.zip"
ditto -c -k --sequesterRsrc --keepParent "Discord with Vencord Portable.app" "Discord.with.Vencord.Portable.app.zip"
