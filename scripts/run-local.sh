#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/output/Discord with Vencord Portable.app"

"$ROOT_DIR/scripts/build-share-app.sh"
/usr/bin/open -n -W "$APP_DIR"
