# Discord with Vencord Portable v0.4.0

This release focuses the macOS launcher on Apple Silicon, cuts the download size by 60.7%, and replaces the previous silent workflow with a responsive native progress interface and an explicit completion summary.

## Compatibility change

- The macOS app now supports Apple Silicon (`arm64`) only.
- macOS 12 remains the minimum supported system version.
- Intel Mac users should continue using the [v0.3.1 universal release](https://github.com/feifeiFrank/Vencord-Discord-Launcher/releases/tag/v0.3.1).
- Windows support is unchanged.

[Apple has announced](https://developer.apple.com/documentation/Apple-Silicon/about-the-rosetta-translation-environment) that macOS Tahoe 26 is the final major release for Intel-based Macs and that general-purpose Rosetta support ends after macOS 27. Version 0.4.0 therefore prioritizes a smaller native Apple Silicon build.

## Size reduction

| macOS component | v0.3.1 | v0.4.0 | Reduction |
| --- | ---: | ---: | ---: |
| Mach-O executable | 178,320 bytes | 88,464 bytes | 50.4% |
| App files | 181,540 bytes | 91,684 bytes | 49.5% |
| Release ZIP | 53,370 bytes | 20,948 bytes | 60.7% |

The build now uses a single arm64 slice, compiler size optimization, dead-code stripping, local-symbol stripping, no empty Resources directory, and a ZIP without AppleDouble metadata. The archive contains only the executable, Info.plist, and code-signature resources.

## Visible macOS status

- A native AppKit window appears immediately instead of performing the operation silently.
- The progress bar reports Discord checks, Vencord update checks, all ten downloads, verification, activation, patching, and launch.
- Work runs on a background queue so the status window remains responsive.
- The final message explains whether Vencord was updated or already current, whether a cached fallback was used, whether Discord needed patching, and whether Discord launched.
- If new Vencord files were installed while an already-patched Discord was running, the launcher restarts Discord so the update is loaded before reporting success.
- A second simultaneous launch now receives a dedicated informational message.
- Permission failures offer an `Open App Management` button instead of opening System Settings without asking.
- Headless smoke tests remain window-free and non-blocking.

## Validation

- Confirmed the executable contains only `arm64` and has a macOS 12 deployment target.
- Verified the ad-hoc signature before and after ZIP extraction.
- Verified the ZIP preserves the executable bit and contains no `__MACOSX`, AppleDouble, or empty Resources entries.
- Added CI size ceilings of 100 KiB for the executable and 24 KiB for the macOS ZIP.
- Exercised cached, first-download, already-patched, and concurrent-lock headless paths.
- Visually verified the native progress window and completion summary.
- Verified both release archives against `SHA256SUMS.txt`.

## Assets

- `Discord.with.Vencord.Portable.macOS-arm64.zip` - Apple Silicon macOS 12+ app
- `Discord.with.Vencord.Portable.Windows.zip` - Windows standalone launcher and instructions
- `SHA256SUMS.txt` - SHA-256 checksums for both archives

## Notes

- Discord itself is not included.
- Internet access is required for the first Vencord download.
- The macOS app is ad-hoc signed, so another Mac may require **System Settings > Privacy & Security > Open Anyway** and App Management permission.
- Set `VENCORD_FORCE_UPDATE=1` to bypass the one-hour macOS update cache.
- macOS logs are written to `/tmp/vencord-portable-install.log`; Windows logs are written to `%TEMP%\vencord-portable-install.log`.
