# Discord with Vencord Portable v0.2.0

This release updates the macOS portable app so it no longer depends on a bundled Vencord `dist` folder.

## What's new

- macOS app now clones or updates upstream Vencord source code when it starts
- macOS app now clones or updates the official Vencord Installer source code when it starts
- macOS app builds the latest Vencord desktop assets and Installer CLI locally before patching Discord
- The release zip no longer ships a stale Vencord `dist`, reducing breakage after Discord or Vencord updates
- If updating fails after the first successful run, the app can continue using the cached source
- The macOS app now includes common Homebrew paths so Finder-launched apps can find `node`, `pnpm`, and `go`
- The macOS app now verifies that Discord was actually patched before launching
- If macOS blocks the normal patch attempt, the app can request administrator permission and retry

## Notes

- First macOS launch can take a few minutes because it downloads dependencies and builds from source.
- macOS users still need `git`, `node`, `pnpm`, `go`, and permission to modify `/Applications/Discord.app`.
- If macOS asks for administrator permission during patching, approve it.
- If macOS blocks the app because it is not notarized, open `System Settings` -> `Privacy & Security` and choose `Open Anyway`.
- Installer logs are written to `/tmp/vencord-portable-install.log`.
