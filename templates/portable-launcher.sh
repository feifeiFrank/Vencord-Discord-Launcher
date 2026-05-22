#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

DISCORD_APP="/Applications/Discord.app"
CACHE_DIR="$HOME/Library/Caches/DiscordWithVencordPortable"
SRC_DIR="$CACHE_DIR/src"
BUILD_DIR="$CACHE_DIR/build"
VENCORD_DATA_DIR="$HOME/Library/Application Support/Vencord"
VENCORD_DIST_DIR="$VENCORD_DATA_DIR/dist"
LOG_FILE="/tmp/vencord-portable-install.log"

INSTALLER_REPO="$SRC_DIR/Installer"
INSTALLER_CLI="$BUILD_DIR/vencord-installer-cli"
INSTALLER_TAG="${VENCORD_INSTALLER_TAG:-v1.4.0}"
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
    osascript -e 'display alert "Vencord install failed" message "See /tmp/vencord-portable-install.log. Make sure git and go are installed. If macOS asks for administrator permission, approve it so Discord can be patched." as critical' >/dev/null 2>&1 || true
}

checkout_installer_source() {
    local repo_url="$1"
    local repo_dir="$2"
    local repo_name="$3"

    if [[ -d "$repo_dir/.git" ]]; then
        info "Updating $repo_name tags"
        if ! git -C "$repo_dir" fetch --tags --force origin; then
            info "Could not refresh $repo_name tags; using cached source"
        fi
    elif [[ -e "$repo_dir" ]]; then
        echo "$repo_dir exists but is not a git repository" >&2
        return 1
    else
        info "Cloning $repo_name"
        git clone "$repo_url" "$repo_dir"
    fi

    info "Using $repo_name $INSTALLER_TAG"
    git -C "$repo_dir" -c advice.detachedHead=false checkout --force "$INSTALLER_TAG"
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
    grep -Fq "$VENCORD_DIST_DIR/patcher.js" "$DISCORD_RESOURCES/app.asar"
}

is_vencord_wrapper() {
    [[ -f "$DISCORD_RESOURCES/app.asar" ]] || return 1
    grep -Fq "patcher.js" "$DISCORD_RESOURCES/app.asar"
}

download_vencord_dist() {
    local download_base="https://github.com/Vendicated/Vencord/releases/latest/download"
    local tmp_dir="$BUILD_DIR/vencord-dist-download"
    local -a assets=(
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

    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir" "$VENCORD_DIST_DIR"

    info "Downloading latest Vencord files"
    for asset in "${assets[@]}"; do
        if ! curl -fsSL --retry 2 --connect-timeout 15 --max-time 120 \
            "$download_base/$asset" \
            -o "$tmp_dir/$asset"; then
            rm -rf "$tmp_dir"
            if [[ -f "$VENCORD_DIST_DIR/patcher.js" ]]; then
                info "Could not update Vencord files; using cached dist"
                return 0
            fi
            echo "Could not download Vencord files and no cached dist exists" >&2
            return 1
        fi
    done

    printf '{}\n' >"$tmp_dir/package.json"
    mv "$tmp_dir"/* "$VENCORD_DIST_DIR"/
    rm -rf "$tmp_dir"
}

prepare_discord_for_patch() {
    if [[ -f "$DISCORD_RESOURCES/_app.asar" ]] && ! is_vencord_wrapper; then
        local stale_backup="$DISCORD_RESOURCES/_app.asar.stale.$(date +%Y%m%d%H%M%S)"
        info "Moving stale _app.asar backup to $(basename "$stale_backup")"
        mv "$DISCORD_RESOURCES/_app.asar" "$stale_backup"
    fi
}

run_patch() {
    VENCORD_USER_DATA_DIR="$VENCORD_DATA_DIR" \
    "$INSTALLER_CLI" --repair --branch stable
}

run_patch_with_admin() {
    local user_name
    local user_group
    user_name="$(id -un)"
    user_group="$(id -gn)"

    cat >"$ADMIN_PATCH_SCRIPT" <<EOF
#!/bin/zsh
set -euo pipefail

export VENCORD_USER_DATA_DIR="$VENCORD_DATA_DIR"
"$INSTALLER_CLI" --repair --branch stable
chown -R "$user_name:$user_group" "$VENCORD_DATA_DIR" >/dev/null 2>&1 || true
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

    need_cmd curl

    [[ -d "$DISCORD_APP" ]] || {
        echo "Discord not found at $DISCORD_APP" >&2
        return 1
    }

    mkdir -p "$SRC_DIR" "$BUILD_DIR" "$VENCORD_DATA_DIR"

    notify

    download_vencord_dist

    if ! is_discord_patched; then
        need_cmd git
        need_cmd go

        checkout_installer_source "https://github.com/Vencord/Installer.git" "$INSTALLER_REPO" "Vencord Installer"

        info "Building Installer CLI"
        cd "$INSTALLER_REPO"
        go build --tags cli -o "$INSTALLER_CLI"

        [[ -x "$INSTALLER_CLI" ]] || {
            echo "Installer CLI was not created at $INSTALLER_CLI" >&2
            return 1
        }

        close_discord
        prepare_discord_for_patch

        info "Patching Discord"
        run_patch || true

        if ! is_discord_patched; then
            info "Normal patch did not complete; requesting administrator permission"
            run_patch_with_admin
        fi
    else
        info "Discord is already patched"
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
