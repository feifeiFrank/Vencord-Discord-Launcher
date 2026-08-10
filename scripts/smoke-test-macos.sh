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
lock_holder_pid=""
cleanup() {
    local test_status=$?
    trap - EXIT
    if [[ -n "$lock_holder_pid" ]]; then
        kill "$lock_holder_pid" 2>/dev/null || true
        wait "$lock_holder_pid" 2>/dev/null || true
    fi
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
grep -F 'Checking the Discord installation' "$LOG_PATH" >/dev/null
grep -F 'Applying the Vencord patch' "$LOG_PATH" >/dev/null
if [[ "$MODE" == "--cached" ]]; then
    grep -F 'Using recently checked Vencord files' "$LOG_PATH" >/dev/null
else
    grep -F 'Downloading Vencord (1 of 10)' "$LOG_PATH" >/dev/null
    grep -F 'Activating the verified Vencord update' "$LOG_PATH" >/dev/null
fi

for asset in "${assets[@]}"; do
    [[ -s "$VENCORD_DIST/$asset" ]] || {
        echo "Missing Vencord asset after launcher run: $asset" >&2
        exit 1
    }
done
[[ -s "$VENCORD_DIST/package.json" ]]
[[ -s "$VENCORD_DIST/.last-update-check" ]]

if [[ "$MODE" == "--download" ]]; then
    force_update=1
else
    force_update=0
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
    echo "Launcher verification run exited with status $launcher_status" >&2
    sed -n '1,240p' "$LOG_PATH" >&2
    exit "$launcher_status"
fi

cmp "$ORIGINAL_ASAR" "$DISCORD_RESOURCES/_app.asar"
grep -F 'Discord is already patched' "$LOG_PATH" >/dev/null
grep -F 'Skipping Discord launch' "$LOG_PATH" >/dev/null
grep -F 'Discord already has Vencord installed' "$LOG_PATH" >/dev/null
grep -F 'Vencord is ready' "$LOG_PATH" >/dev/null
if [[ "$MODE" == "--download" ]]; then
    grep -F 'Restarting Discord to load the Vencord update' "$LOG_PATH" >/dev/null
fi

LOCK_LOG_PATH="$TEST_ROOT/existing-launch.log"
LOCK_STDERR_PATH="$TEST_ROOT/lock-stderr.log"
LOCK_HOLDER_STDERR_PATH="$TEST_ROOT/lock-holder-stderr.log"
LOCK_READY_PATH="$TEST_ROOT/lock-ready"
touch "$VENCORD_DATA/launcher.lock"
printf 'existing launcher log\n' >"$LOCK_LOG_PATH"
setopt no_bg_nice
(
    zmodload zsh/system
    integer held_lock_fd
    zsystem flock -f held_lock_fd "$VENCORD_DATA/launcher.lock"
    printf 'ready\n' >"$LOCK_READY_PATH"
    sleep 30
) 2>"$LOCK_HOLDER_STDERR_PATH" &
lock_holder_pid=$!

for attempt in {1..100}; do
    [[ -f "$LOCK_READY_PATH" ]] && break
    sleep 0.02
done
[[ -f "$LOCK_READY_PATH" ]] || {
    echo "Could not acquire the smoke-test launcher lock" >&2
    sed -n '1,80p' "$LOCK_HOLDER_STDERR_PATH" >&2
    exit 1
}

set +e
DISCORD_APP_PATH="$DISCORD_APP" \
VENCORD_USER_DATA_DIR="$VENCORD_DATA" \
DISCORD_WITH_VENCORD_LOG_PATH="$LOCK_LOG_PATH" \
DISCORD_WITH_VENCORD_HEADLESS=1 \
DISCORD_WITH_VENCORD_SKIP_LAUNCH=1 \
"$EXECUTABLE" 2>"$LOCK_STDERR_PATH"
lock_status=$?
set -e

kill "$lock_holder_pid" 2>/dev/null || true
wait "$lock_holder_pid" 2>/dev/null || true
lock_holder_pid=""

(( lock_status != 0 )) || {
    echo "Concurrent launcher unexpectedly acquired an existing lock" >&2
    exit 1
}
grep -F 'already in progress' "$LOCK_STDERR_PATH" >/dev/null
[[ "$(<"$LOCK_LOG_PATH")" == "existing launcher log" ]] || {
    echo "Concurrent launcher modified the existing launch log" >&2
    exit 1
}

echo "macOS launcher smoke test passed"
