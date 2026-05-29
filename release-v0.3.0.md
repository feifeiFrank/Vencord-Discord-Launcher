# Discord with Vencord Portable v0.3.0

This release replaces the macOS shell launcher with a native AppKit launcher.

## Changes

- macOS share app now builds a native arm64 Mach-O executable from `Sources/DiscordWithVencordPortable/main.m`
- Removed the shell wrapper executable and `portable-launcher.sh` from the generated app bundle
- macOS patching now downloads Vencord dist files directly with Foundation networking
- Discord patching now happens inside the launcher process by moving `app.asar` to `_app.asar` and writing the Vencord wrapper `app.asar`
- The generated app is ad-hoc signed with a stable designated requirement based on the bundle identifier
- Added `NSSystemAdministrationUsageDescription`, `LSMinimumSystemVersion`, and `NSPrincipalClass` to the macOS app Info.plist
- Local `run.command` now builds and opens the same generated app path used for sharing

## Why

The previous macOS flow used shell, Python, AppleScript, or the Vencord Installer CLI to touch `/Applications/Discord.app`. On newer macOS versions, App Management attribution can land on those helper binaries instead of the launcher app, causing repeated administrator prompts or direct TCC denial.

The native launcher keeps App Management attribution on `Discord with Vencord Portable.app` itself. Users may still need to allow the app in `System Settings` -> `Privacy & Security` -> `App Management`, but the app no longer relies on `osascript` administrator prompts.

## Notes

- First macOS launch still needs internet access.
- macOS users may still need App Management permission to modify `/Applications/Discord.app`.
- Installer logs are written to `/tmp/vencord-portable-install.log`.
