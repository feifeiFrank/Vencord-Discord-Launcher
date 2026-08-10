#!/bin/zsh
set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly root_dir="$(cd "$script_dir/.." && pwd)"
readonly source_plist="$root_dir/templates/Info.plist"
readonly build_script="$root_dir/scripts/build-share-app.sh"
readonly smoke_test_script="$root_dir/scripts/smoke-test-macos.sh"
readonly windows_generator_script="$root_dir/scripts/generate-windows-launcher.sh"
readonly app_path="$root_dir/output/Discord with Vencord Portable.app"
readonly app_plist="$app_path/Contents/Info.plist"
readonly zip_path="$root_dir/output/Discord.with.Vencord.Portable.macOS-arm64.zip"
readonly expected_minimum_system_version="12.0"
readonly expected_bundle_version="0.4.0"
readonly expected_build_version="7"
readonly maximum_executable_size_bytes=$((100 * 1024))
readonly maximum_zip_size_bytes=$((24 * 1024))

extraction_dir=""

log() {
    print -r -- "==> $*"
}

pass() {
    print -r -- "PASS: $*"
}

fail() {
    print -u2 -r -- "ERROR: $*"
    exit 1
}

cleanup() {
    if [[ -n "$extraction_dir" && -d "$extraction_dir" ]]; then
        /bin/rm -rf -- "$extraction_dir"
    fi
}
trap cleanup EXIT

require_executable() {
    local executable_path="$1"
    local display_name="$2"
    [[ -x "$executable_path" ]] || fail "$display_name is required at $executable_path. Install the macOS Command Line Tools and try again."
}

read_plist_value() {
    local plist_path="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null
}

version_is_lte() {
    local candidate_version="$1"
    local maximum_version="$2"

    /usr/bin/awk -v candidate="$candidate_version" -v maximum="$maximum_version" '
        BEGIN {
            if (candidate !~ /^[0-9]+([.][0-9]+)*$/ || maximum !~ /^[0-9]+([.][0-9]+)*$/) {
                exit 2
            }

            candidate_count = split(candidate, candidate_parts, ".")
            maximum_count = split(maximum, maximum_parts, ".")
            part_count = candidate_count > maximum_count ? candidate_count : maximum_count

            for (part_index = 1; part_index <= part_count; part_index++) {
                candidate_part = candidate_parts[part_index] + 0
                maximum_part = maximum_parts[part_index] + 0
                if (candidate_part < maximum_part) {
                    exit 0
                }
                if (candidate_part > maximum_part) {
                    exit 1
                }
            }
            exit 0
        }
    '
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail "This validation builds a macOS app and must run on macOS."

require_executable /bin/zsh "zsh"
require_executable /usr/bin/plutil "plutil"
require_executable /usr/bin/xcrun "xcrun"
require_executable /usr/bin/codesign "codesign"
require_executable /usr/bin/ditto "ditto"
require_executable /usr/bin/unzip "unzip"
require_executable /usr/bin/otool "otool"
require_executable /usr/bin/lipo "lipo"
require_executable /usr/bin/file "file"
require_executable /usr/bin/awk "awk"
require_executable /usr/bin/grep "grep"
require_executable /usr/bin/mktemp "mktemp"
require_executable /usr/bin/stat "stat"
require_executable /usr/bin/zip "zip"
require_executable /usr/libexec/PlistBuddy "PlistBuddy"

if ! /usr/bin/xcrun --find clang >/dev/null 2>&1; then
    fail "clang was not found. Install the macOS Command Line Tools and try again."
fi
if ! /usr/bin/xcrun --find strip >/dev/null 2>&1; then
    fail "strip was not found. Install the macOS Command Line Tools and try again."
fi
if ! /usr/bin/xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
    fail "The macOS SDK was not found. Install the macOS Command Line Tools and try again."
fi

log "Checking zsh syntax"
syntax_files=("$root_dir"/scripts/*.sh(N) "$root_dir"/*.command(N))
(( ${#syntax_files[@]} > 0 )) || fail "No zsh scripts were found to validate."
for syntax_file in "${syntax_files[@]}"; do
    if ! /bin/zsh -n -o no_bg_nice "$syntax_file"; then
        fail "zsh syntax validation failed for ${syntax_file#$root_dir/}."
    fi
    pass "zsh syntax: ${syntax_file#$root_dir/}"
done

[[ -x "$windows_generator_script" ]] || \
    fail "Windows launcher generator is missing or not executable: ${windows_generator_script#$root_dir/}."
log "Checking generated Windows launcher"
if ! "$windows_generator_script" --check; then
    fail "windows/VencordLauncher.cmd is out of sync. Run scripts/generate-windows-launcher.sh --write and commit both files."
fi
pass "Windows standalone launcher is in sync"

log "Validating source Info.plist"
if ! /usr/bin/plutil -lint "$source_plist"; then
    fail "Source plist validation failed: ${source_plist#$root_dir/}."
fi

source_minimum_system_version="$(read_plist_value "$source_plist" LSMinimumSystemVersion)" || \
    fail "LSMinimumSystemVersion is missing from ${source_plist#$root_dir/}."
[[ "$source_minimum_system_version" == "$expected_minimum_system_version" ]] || \
    fail "LSMinimumSystemVersion must be $expected_minimum_system_version, but ${source_plist#$root_dir/} declares $source_minimum_system_version."
pass "source LSMinimumSystemVersion is $source_minimum_system_version"

source_bundle_version="$(read_plist_value "$source_plist" CFBundleShortVersionString)" || \
    fail "CFBundleShortVersionString is missing from ${source_plist#$root_dir/}."
source_build_version="$(read_plist_value "$source_plist" CFBundleVersion)" || \
    fail "CFBundleVersion is missing from ${source_plist#$root_dir/}."
[[ "$source_bundle_version" == "$expected_bundle_version" ]] || \
    fail "Bundle version must be $expected_bundle_version, but found $source_bundle_version."
[[ "$source_build_version" == "$expected_build_version" ]] || \
    fail "Build version must be $expected_build_version, but found $source_build_version."
pass "source bundle version is $source_bundle_version ($source_build_version)"

[[ -x "$build_script" ]] || fail "Build script is not executable: ${build_script#$root_dir/}."
log "Building the share app"
if ! "$build_script"; then
    fail "Share app build failed. Review the compiler or signing output above."
fi

[[ -d "$app_path" ]] || fail "Build did not create $app_path."
[[ -f "$app_plist" ]] || fail "Built app is missing Contents/Info.plist."
[[ -f "$zip_path" ]] || fail "Build did not create $zip_path."
[[ ! -e "$app_path/Contents/Resources" ]] || \
    fail "Built app contains an unexpected empty Contents/Resources directory."

[[ -x "$smoke_test_script" ]] || fail "macOS smoke test is missing or not executable: ${smoke_test_script#$root_dir/}."
log "Running the macOS smoke test"
if ! "$smoke_test_script"; then
    fail "macOS smoke test failed. Review its output above."
fi
pass "macOS smoke test"

log "Validating the built app"
if ! /usr/bin/plutil -lint "$app_plist"; then
    fail "Built app plist validation failed."
fi

built_minimum_system_version="$(read_plist_value "$app_plist" LSMinimumSystemVersion)" || \
    fail "The built app is missing LSMinimumSystemVersion."
[[ "$built_minimum_system_version" == "$expected_minimum_system_version" ]] || \
    fail "Built LSMinimumSystemVersion must be $expected_minimum_system_version, but found $built_minimum_system_version."

built_bundle_version="$(read_plist_value "$app_plist" CFBundleShortVersionString)" || \
    fail "The built app is missing CFBundleShortVersionString."
built_build_version="$(read_plist_value "$app_plist" CFBundleVersion)" || \
    fail "The built app is missing CFBundleVersion."
[[ "$built_bundle_version" == "$expected_bundle_version" && "$built_build_version" == "$expected_build_version" ]] || \
    fail "Built bundle version must be $expected_bundle_version ($expected_build_version), but found $built_bundle_version ($built_build_version)."
pass "built bundle version is $built_bundle_version ($built_build_version)"

bundle_executable="$(read_plist_value "$app_plist" CFBundleExecutable)" || \
    fail "The built app is missing CFBundleExecutable."
executable_path="$app_path/Contents/MacOS/$bundle_executable"
[[ -x "$executable_path" ]] || fail "Built app executable is missing or not executable: $executable_path."

file_description="$(/usr/bin/file -b "$executable_path")"
[[ "$file_description" == *"Mach-O"* ]] || \
    fail "Expected a Mach-O executable at $executable_path, but file reported: $file_description"

architectures=" $(/usr/bin/lipo -archs "$executable_path") "
[[ "$architectures" == " arm64 " ]] || \
    fail "Expected an arm64-only executable, but lipo reported:$architectures"
pass "built app contains only the arm64 slice"

executable_size_bytes="$(/usr/bin/stat -f '%z' "$executable_path")"
(( executable_size_bytes <= maximum_executable_size_bytes )) || \
    fail "Mach-O is $executable_size_bytes bytes; ceiling is $maximum_executable_size_bytes bytes."
pass "Mach-O size is $executable_size_bytes bytes (ceiling: $maximum_executable_size_bytes)"

if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"; then
    fail "Code-signature verification failed for the built app."
fi
pass "built app has a valid code signature"

log "Checking Mach-O deployment target"
deployment_targets="$(
    /usr/bin/otool -l "$executable_path" | /usr/bin/awk '
        $1 == "cmd" && $2 == "LC_BUILD_VERSION" {
            reading_build_version = 1
            reading_legacy_version = 0
            next
        }
        reading_build_version && $1 == "minos" {
            print $2
            reading_build_version = 0
            next
        }
        $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" {
            reading_legacy_version = 1
            reading_build_version = 0
            next
        }
        reading_legacy_version && $1 == "version" {
            print $2
            reading_legacy_version = 0
        }
    '
)"
[[ -n "$deployment_targets" ]] || \
    fail "Could not read a macOS deployment target from $executable_path."

while IFS= read -r deployment_target; do
    if version_is_lte "$deployment_target" "$built_minimum_system_version"; then
        pass "Mach-O deployment target $deployment_target <= LSMinimumSystemVersion $built_minimum_system_version"
    else
        comparison_status=$?
        if (( comparison_status == 2 )); then
            fail "Could not compare malformed version values: Mach-O '$deployment_target', plist '$built_minimum_system_version'."
        fi
        fail "Mach-O deployment target $deployment_target exceeds LSMinimumSystemVersion $built_minimum_system_version. Compile with -mmacosx-version-min=$built_minimum_system_version."
    fi
done <<< "$deployment_targets"

log "Testing ZIP integrity"
zip_size_bytes="$(/usr/bin/stat -f '%z' "$zip_path")"
(( zip_size_bytes <= maximum_zip_size_bytes )) || \
    fail "macOS ZIP is $zip_size_bytes bytes; ceiling is $maximum_zip_size_bytes bytes."
pass "macOS ZIP size is $zip_size_bytes bytes (ceiling: $maximum_zip_size_bytes)"

if ! /usr/bin/unzip -tq "$zip_path"; then
    fail "ZIP integrity check failed: $zip_path."
fi
archive_entries="$(/usr/bin/unzip -Z1 "$zip_path")" || \
    fail "Could not list ZIP entries: $zip_path."
if /usr/bin/grep -Eq '(^|/)__MACOSX/|(^|/)\._' <<< "$archive_entries"; then
    fail "ZIP contains AppleDouble or __MACOSX metadata entries."
fi
pass "ZIP contains no AppleDouble or __MACOSX metadata"

extraction_dir="$(/usr/bin/mktemp -d -t discord-vencord-check)" || \
    fail "Could not create a temporary directory for ZIP verification."
if ! /usr/bin/ditto -x -k "$zip_path" "$extraction_dir"; then
    fail "Could not extract the ZIP with ditto: $zip_path."
fi

extracted_app="$extraction_dir/Discord with Vencord Portable.app"
[[ -d "$extracted_app" ]] || fail "ZIP does not contain Discord with Vencord Portable.app at its root."
[[ ! -e "$extracted_app/Contents/Resources" ]] || \
    fail "Extracted app contains an unexpected empty Contents/Resources directory."
if ! /usr/bin/plutil -lint "$extracted_app/Contents/Info.plist"; then
    fail "The app plist is invalid after ZIP extraction."
fi
extracted_executable="$extracted_app/Contents/MacOS/$bundle_executable"
[[ -x "$extracted_executable" ]] || \
    fail "ZIP extraction did not preserve the executable bit on $bundle_executable."
extracted_architectures=" $(/usr/bin/lipo -archs "$extracted_executable") "
[[ "$extracted_architectures" == " arm64 " ]] || \
    fail "Extracted app is not arm64-only; lipo reported:$extracted_architectures"
if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$extracted_app"; then
    fail "The app signature is invalid after ZIP extraction."
fi
pass "ZIP preserves the arm64 executable bit and signed app bundle"

print -r -- ""
print -r -- "All validation checks passed."
