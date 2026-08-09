#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_PATH="$ROOT_DIR/windows/run.ps1"
OUTPUT_PATH="$ROOT_DIR/windows/VencordLauncher.cmd"
MODE="${1:---write}"
TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/vencord-launcher.XXXXXX")"

cleanup() {
    rm -f "$TMP_FILE"
}
trap cleanup EXIT

{
    cat <<'HEADER'
@echo off
setlocal DisableDelayedExpansion
set "VENCORD_LAUNCHER_SOURCE=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$source = Get-Content -LiteralPath $env:VENCORD_LAUNCHER_SOURCE -Raw; $marker = '# POWERSHELL-BEGIN'; $index = $source.LastIndexOf($marker); if ($index -lt 0) { throw 'Launcher payload missing.' }; $payload = $source.Substring($index + $marker.Length); $tmp = Join-Path $env:TEMP ('vencord-launcher-' + [guid]::NewGuid().ToString() + '.ps1'); try { Set-Content -LiteralPath $tmp -Value $payload -Encoding UTF8; & $tmp -Silent -Standalone; exit $LASTEXITCODE } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }"
exit /b %ERRORLEVEL%
# POWERSHELL-BEGIN
HEADER
    cat "$SOURCE_PATH"
} > "$TMP_FILE"

case "$MODE" in
    --check)
        if ! cmp -s "$TMP_FILE" "$OUTPUT_PATH"; then
            print -u2 "windows/VencordLauncher.cmd is out of sync with windows/run.ps1"
            diff -u "$OUTPUT_PATH" "$TMP_FILE" || true
            exit 1
        fi
        ;;
    --write)
        mv "$TMP_FILE" "$OUTPUT_PATH"
        chmod 0644 "$OUTPUT_PATH"
        trap - EXIT
        ;;
    *)
        print -u2 "Usage: $0 [--write|--check]"
        exit 2
        ;;
esac
