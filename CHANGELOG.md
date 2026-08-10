# Changelog

## 0.4.0 - 2026-08-10

- Focus the macOS release on Apple Silicon and remove the Intel `x86_64` slice. Intel users should remain on the v0.3.1 universal release.
- Reduce the macOS release ZIP from 53,370 bytes to 20,948 bytes, a 60.7% decrease.
- Compile for size, remove dead code and local symbols, omit the empty Resources directory, and package without AppleDouble metadata.
- Show a native progress window with clear checking, download, verification, patch, and launch stages.
- Show a completion summary that distinguishes updated files, recently checked cache, offline fallback, patch status, and Discord launch status.
- Present an informational message for concurrent launches and an actionable App Management button for permission failures.
- Restart an already-patched running Discord after a Vencord runtime refresh so the new files are loaded before success is reported.
- Move interactive work off the AppKit main thread so the progress interface stays responsive; keep headless validation non-interactive.
- Add smoke coverage for visible stage reporting and launcher-lock behavior, including protection against truncating another launch's log.
- Pin macOS CI to an Apple Silicon runner and enforce arm64-only, executable-size, ZIP-size, metadata, permission, signature, and deployment-target checks.

## 0.3.1 - 2026-08-09

- Fix the macOS executable deployment target so the app actually runs on the advertised macOS 12 minimum.
- Ship one universal macOS app for Apple Silicon and Intel Macs.
- Reuse a complete Vencord runtime cache for one hour, pin every refresh to one Release snapshot, verify asset digests, and activate updates atomically.
- Serialize simultaneous macOS launcher instances so concurrent updates cannot race while replacing the runtime or patching Discord.
- Avoid scanning a full Discord ASAR when identifying the small Vencord wrapper.
- Verify the Windows Installer CLI against Vencord's published SHA-256 checksum before every execution.
- Close only the selected Discord channel on Windows.
- Generate the standalone Windows launcher from `run.ps1` to prevent its embedded payload from drifting.
- Add repeatable macOS build, package, signature, deployment-target, smoke, and generated-file validation in CI.
- Restore a Windows release archive and publish SHA-256 checksums for both platform archives.

## Previous releases

- [0.3.1](./release-v0.3.1.md) - Universal compatibility and verified updates
- [0.3.0](./release-v0.3.0.md) - Native AppKit macOS launcher
- [0.2.3](./release-v0.2.3.md) - Avoid unnecessary macOS repatching
- [0.2.2](./release-v0.2.2.md) - Pin the macOS installer build
- [0.2.1](./release-v0.2.1.md) - Match the official Vencord installer layout
- [0.2.0](./release-v0.2.0.md) - Self-updating Vencord runtime
- [0.1.0](./release-v0.1.0.md) - First packaged release
