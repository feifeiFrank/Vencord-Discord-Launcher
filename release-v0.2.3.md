# Discord with Vencord Portable v0.2.3

This release makes the macOS launcher avoid unnecessary Discord app rewrites.

## Changes

- macOS launcher now downloads the latest Vencord dist files directly before launch
- If Discord is already patched, the launcher starts Discord without running Installer `repair`
- Official Vencord Installer CLI is now built only when Discord actually needs patching
- Stale `_app.asar` backups are moved aside before a fresh patch so Discord updates do not confuse the Installer
- `curl` is now required for macOS dist updates; `git` and `go` are only needed when patching Discord

## Why

The previous macOS launcher ran the official Installer `repair` flow on every launch. On macOS this modifies `/Applications/Discord.app`, and recent App Management / TCC restrictions can block that rewrite even when Vencord is already installed.

The new flow only touches `/Applications/Discord.app` after Discord updates or the wrapper is missing. Normal launches update Vencord's user-level files and then start Discord.

## Notes

- First macOS launch still needs internet access.
- macOS users may still need permission to modify `/Applications/Discord.app` when Discord actually needs patching.
- Installer logs are written to `/tmp/vencord-portable-install.log`.
