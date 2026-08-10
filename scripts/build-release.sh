#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
MACOS_ARCHIVE="$OUTPUT_DIR/Discord.with.Vencord.Portable.macOS-arm64.zip"
WINDOWS_ARCHIVE="$OUTPUT_DIR/Discord.with.Vencord.Portable.Windows.zip"
CHECKSUMS_FILE="$OUTPUT_DIR/SHA256SUMS.txt"
STAGING_ROOT="$(mktemp -d /private/tmp/discord-vencord-release.XXXXXX)"
WINDOWS_DIR="$STAGING_ROOT/Discord with Vencord Portable Windows"

cleanup() {
    local build_status=$?
    trap - EXIT
    rm -rf "$STAGING_ROOT"
    exit "$build_status"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/check.sh"

mkdir -p "$WINDOWS_DIR"
cp "$ROOT_DIR/windows/VencordLauncher.cmd" "$WINDOWS_DIR/VencordLauncher.cmd"
cp "$ROOT_DIR/windows/README.txt" "$WINDOWS_DIR/README.txt"

rm -f "$WINDOWS_ARCHIVE" "$CHECKSUMS_FILE"
(
    cd "$STAGING_ROOT"
    COPYFILE_DISABLE=1 /usr/bin/zip -q -r "$WINDOWS_ARCHIVE" "Discord with Vencord Portable Windows"
)

(
    cd "$OUTPUT_DIR"
    /usr/bin/shasum -a 256 \
        "${MACOS_ARCHIVE:t}" \
        "Discord.with.Vencord.Portable.Windows.zip" \
        >"SHA256SUMS.txt"
)

/usr/bin/unzip -tq "$WINDOWS_ARCHIVE"
(
    cd "$OUTPUT_DIR"
    /usr/bin/shasum -a 256 -c "SHA256SUMS.txt"
)
echo "Release artifacts are ready in $OUTPUT_DIR"
