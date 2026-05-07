# Discord with Vencord Portable v0.2.1

This release changes the macOS launcher to follow the official Vencord Installer flow more closely.

## What's new

- macOS app now builds the official Vencord Installer CLI from source, then runs it in `repair` mode
- Vencord files now use the official default path: `~/Library/Application Support/Vencord/dist`
- macOS app no longer uses `VENCORD_DEV_INSTALL` or a private `DiscordWithVencordPortable` Vencord dist path
- macOS app verifies that Discord's wrapper points at the official Vencord dist path before launching Discord
- macOS requirements are simpler: `git` and `go` are required; `node` and `pnpm` are no longer required for the launcher

## Why this changed

The previous macOS launcher built Vencord locally and patched Discord with a custom dev-install path. The official Vencord Installer uses a default Vencord data directory and official release dist files instead. This release matches that official layout to avoid path and runtime differences.

## Notes

- First macOS launch still needs internet access so the Installer CLI can fetch the latest Vencord release files.
- macOS users still need permission to modify `/Applications/Discord.app`.
- If macOS blocks the app because it is not notarized, open `System Settings` -> `Privacy & Security` and choose `Open Anyway`.
- Installer logs are written to `/tmp/vencord-portable-install.log`.
