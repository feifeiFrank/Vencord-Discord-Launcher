#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTABLE="$ROOT_DIR/output/Discord with Vencord Portable.app/Contents/MacOS/DiscordWithVencordPortable"
MODE="${1:---cached}"

case "$MODE" in
    --cached)
        force_update=0
        ;;
    --download)
        force_update=1
        ;;
    *)
        echo "Usage: $0 [--cached|--download]" >&2
        exit 2
        ;;
esac

if [[ ! -x "$EXECUTABLE" ]]; then
    "$ROOT_DIR/scripts/build-share-app.sh"
fi

TEST_ROOT="$(mktemp -d /private/tmp/discord-with-vencord-smoke.XXXXXX)"
cleanup() {
    local test_status=$?
    trap - EXIT
    if (( test_status != 0 )) && [[ -f "$TEST_ROOT/launcher.log" ]]; then
        echo "Launcher log from failed smoke test:" >&2
        sed -n '1,240p' "$TEST_ROOT/launcher.log" >&2
    fi
    rm -rf "$TEST_ROOT"
    exit "$test_status"
}
trap cleanup EXIT

DISCORD_APP="$TEST_ROOT/Discord.app"
DISCORD_RESOURCES="$DISCORD_APP/Contents/Resources"
VENCORD_DATA="$TEST_ROOT/Vencord"
VENCORD_DIST="$VENCORD_DATA/dist"
LOG_PATH="$TEST_ROOT/launcher.log"
ORIGINAL_ASAR="$TEST_ROOT/original-app.asar"

mkdir -p "$DISCORD_RESOURCES" "$VENCORD_DIST"
printf 'unpatched Discord fixture\n' >"$ORIGINAL_ASAR"
cp "$ORIGINAL_ASAR" "$DISCORD_RESOURCES/app.asar"

assets=(
    patcher.js
    patcher.js.map
    patcher.js.LEGAL.txt
    preload.js
    preload.js.map
    renderer.js
    renderer.js.map
    renderer.js.LEGAL.txt
    renderer.css
    renderer.css.map
)

if [[ "$MODE" == "--cached" ]]; then
    for asset in "${assets[@]}"; do
        printf 'fixture for %s\n' "$asset" >"$VENCORD_DIST/$asset"
    done
    printf '{}\n' >"$VENCORD_DIST/package.json"
    printf 'smoke-test cache marker\n' >"$VENCORD_DIST/.last-update-check"
fi

set +e
DISCORD_APP_PATH="$DISCORD_APP" \
VENCORD_USER_DATA_DIR="$VENCORD_DATA" \
DISCORD_WITH_VENCORD_LOG_PATH="$LOG_PATH" \
DISCORD_WITH_VENCORD_HEADLESS=1 \
DISCORD_WITH_VENCORD_SKIP_LAUNCH=1 \
VENCORD_FORCE_UPDATE="$force_update" \
"$EXECUTABLE"
launcher_status=$?
set -e

if (( launcher_status != 0 )); then
    echo "Launcher exited with status $launcher_status" >&2
    sed -n '1,240p' "$LOG_PATH" >&2
    exit "$launcher_status"
fi

cmp "$ORIGINAL_ASAR" "$DISCORD_RESOURCES/_app.asar"
grep -F 'Patching Discord' "$LOG_PATH" >/dev/null
grep -F 'Skipping Discord launch' "$LOG_PATH" >/dev/null

for asset in "${assets[@]}"; do
    [[ -s "$VENCORD_DIST/$asset" ]] || {
        echo "Missing Vencord asset after launcher run: $asset" >&2
        exit 1
    }
done
[[ -s "$VENCORD_DIST/package.json" ]]
[[ -s "$VENCORD_DIST/.last-update-check" ]]

force_update=0
set +e
DISCORD_APP_PATH="$DISCORD_APP" \
VENCORD_USER_DATA_DIR="$VENCORD_DATA" \
DISCORD_WITH_VENCORD_LOG_PATH="$LOG_PATH" \
DISCORD_WITH_VENCORD_HEADLESS=1 \
DISCORD_WITH_VENCORD_SKIP_LAUNCH=1 \
VENCORD_FORCE_UPDATE="$force_update" \
"$EXECUTABLE"
launcher_status=$?
set -e

if (( launcher_status != 0 )); then
    echo "Launcher verification run exited with status $launcher_status" >&2
    sed -n '1,240p' "$LOG_PATH" >&2
    exit "$launcher_status"
fi

cmp "$ORIGINAL_ASAR" "$DISCORD_RESOURCES/_app.asar"
grep -F 'Discord is already patched' "$LOG_PATH" >/dev/null
grep -F 'Skipping Discord launch' "$LOG_PATH" >/dev/null

echo "macOS launcher smoke test passed"
