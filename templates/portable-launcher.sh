#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

DISCORD_APP="/Applications/Discord.app"
CACHE_DIR="$HOME/Library/Caches/DiscordWithVencordPortable"
SRC_DIR="$CACHE_DIR/src"
BUILD_DIR="$CACHE_DIR/build"
RUNTIME_DIR="$HOME/Library/Application Support/DiscordWithVencordPortable"
LOG_FILE="/tmp/vencord-portable-install.log"

VENCORD_REPO="$SRC_DIR/Vencord"
INSTALLER_REPO="$SRC_DIR/Installer"
PATCHER_JS="$VENCORD_REPO/dist/patcher.js"
INSTALLER_CLI="$BUILD_DIR/vencord-installer-cli"
DISCORD_RESOURCES="$DISCORD_APP/Contents/Resources"
ADMIN_PATCH_SCRIPT="$BUILD_DIR/admin-patch.sh"

info() {
    printf '[info] %s\n' "$1"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        return 1
    }
}

notify() {
    osascript -e 'display notification "Updating Vencord before launching Discord." with title "Discord with Vencord Portable"' >/dev/null 2>&1 || true
}

show_failure_alert() {
    osascript -e 'display alert "Vencord install failed" message "See /tmp/vencord-portable-install.log. Make sure git, node, pnpm, and go are installed. If macOS asks for administrator permission, approve it so Discord can be patched." as critical' >/dev/null 2>&1 || true
}

clone_or_update() {
    local repo_url="$1"
    local repo_dir="$2"
    local repo_name="$3"

    if [[ -d "$repo_dir/.git" ]]; then
        info "Updating $repo_name"
        if ! git -C "$repo_dir" pull --ff-only; then
            info "Could not update $repo_name; using cached source"
        fi
    elif [[ -e "$repo_dir" ]]; then
        echo "$repo_dir exists but is not a git repository" >&2
        return 1
    else
        info "Cloning $repo_name"
        git clone "$repo_url" "$repo_dir"
    fi
}

close_discord() {
    if pgrep -x "Discord" >/dev/null 2>&1; then
        osascript -e 'tell application "Discord" to quit' >/dev/null 2>&1 || true
        sleep 2
        pkill -x "Discord" >/dev/null 2>&1 || true
    fi
}

is_discord_patched() {
    [[ -f "$DISCORD_RESOURCES/app.asar" && -f "$DISCORD_RESOURCES/_app.asar" ]] || return 1
    grep -Fq "$PATCHER_JS" "$DISCORD_RESOURCES/app.asar"
}

run_patch() {
    VENCORD_USER_DATA_DIR="$RUNTIME_DIR" \
    VENCORD_DIRECTORY="$PATCHER_JS" \
    VENCORD_DEV_INSTALL=1 \
    "$INSTALLER_CLI" --install --branch stable
}

run_patch_with_admin() {
    cat >"$ADMIN_PATCH_SCRIPT" <<EOF
#!/bin/zsh
set -euo pipefail

VENCORD_USER_DATA_DIR="$RUNTIME_DIR" \\
VENCORD_DIRECTORY="$PATCHER_JS" \\
VENCORD_DEV_INSTALL=1 \\
"$INSTALLER_CLI" --install --branch stable
EOF

    chmod +x "$ADMIN_PATCH_SCRIPT"

    osascript - "$ADMIN_PATCH_SCRIPT" <<'OSA'
on run argv
    do shell script quoted form of (item 1 of argv) with administrator privileges
end run
OSA
}

main() {
    info "Starting at $(date)"

    need_cmd git
    need_cmd node
    need_cmd pnpm
    need_cmd go

    [[ -d "$DISCORD_APP" ]] || {
        echo "Discord not found at $DISCORD_APP" >&2
        return 1
    }

    mkdir -p "$SRC_DIR" "$BUILD_DIR" "$RUNTIME_DIR"

    notify

    clone_or_update "https://github.com/Vendicated/Vencord.git" "$VENCORD_REPO" "Vencord"
    clone_or_update "https://github.com/Vencord/Installer.git" "$INSTALLER_REPO" "Vencord Installer"

    info "Installing Vencord dependencies"
    cd "$VENCORD_REPO"
    pnpm install

    info "Building Vencord desktop assets"
    pnpm build

    [[ -f "$PATCHER_JS" ]] || {
        echo "Vencord build did not create $PATCHER_JS" >&2
        return 1
    }

    info "Building Installer CLI"
    cd "$INSTALLER_REPO"
    go build --tags cli -o "$INSTALLER_CLI"

    [[ -x "$INSTALLER_CLI" ]] || {
        echo "Installer CLI was not created at $INSTALLER_CLI" >&2
        return 1
    }

    close_discord

    info "Patching Discord"
    run_patch || true

    if ! is_discord_patched; then
        info "Normal patch did not complete; requesting administrator permission"
        run_patch_with_admin
    fi

    is_discord_patched || {
        echo "Discord was not patched successfully" >&2
        return 1
    }

    info "Launching Discord"
    open -a "$DISCORD_APP"
}

if ! main >"$LOG_FILE" 2>&1; then
    show_failure_alert
    exit 1
fi
