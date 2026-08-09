# Discord with Vencord Portable v0.3.1

This compatibility and reliability release fixes the macOS deployment target, speeds up repeat launches, hardens runtime updates, and restores a verified Windows release package.

## Changes

### macOS

- Fixed the compiled Mach-O minimum from the build host's macOS 26 default to the advertised macOS 12 target.
- The app is now universal and contains both Apple Silicon (`arm64`) and Intel (`x86_64`) slices.
- A complete Vencord dist is reused for one hour before another update check, avoiding ten downloads on every Discord launch.
- Each refresh resolves one GitHub Release snapshot, downloads its immutable asset IDs, and verifies the published size and SHA-256 digest for all ten files.
- New Vencord files are staged beside the active dist and exchanged atomically; a failed or concurrent download cannot leave a mixed runtime.
- A launcher lock serializes simultaneous app instances across both the update and Discord patch steps.
- Offline fallback now requires every runtime asset instead of checking only `patcher.js`.
- Wrapper detection refuses to load or scan an unexpectedly large Discord ASAR.
- Added isolated headless smoke coverage for first-time patching and the already-patched fast path.

### Windows

- Downloads the official `checksums.sha256` release asset and verifies `VencordInstallerCli.exe` before every execution.
- Stops only the Discord Stable, PTB, or Canary process that was actually selected.
- Generates the portable single-file CMD from `windows/run.ps1`, eliminating duplicated PowerShell logic.
- Restored a Windows zip release asset with the standalone launcher and usage notes.

### Build and release quality

- Added a local validation suite and GitHub Actions workflow.
- Validation checks zsh and Windows PowerShell syntax, embedded/generated-file drift, plist validity, both Mach-O deployment targets, the ad-hoc signature, smoke behavior, and zip integrity.
- Release builds now produce `SHA256SUMS.txt` for the macOS and Windows archives.

## Assets

- `Discord.with.Vencord.Portable.app.zip` - universal macOS 12+ app
- `Discord.with.Vencord.Portable.Windows.zip` - Windows standalone launcher and instructions
- `SHA256SUMS.txt` - SHA-256 checksums for both archives

## Notes

- Discord itself is not included.
- Internet access is required for the first Vencord download.
- The macOS app is ad-hoc signed, so another Mac may require **System Settings > Privacy & Security > Open Anyway** and App Management permission.
- Set `VENCORD_FORCE_UPDATE=1` to bypass the one-hour macOS update cache.
- macOS logs are written to `/tmp/vencord-portable-install.log`; Windows logs are written to `%TEMP%\vencord-portable-install.log`.
