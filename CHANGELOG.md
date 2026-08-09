# Changelog

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

- [0.3.0](./release-v0.3.0.md) - Native AppKit macOS launcher
- [0.2.3](./release-v0.2.3.md) - Avoid unnecessary macOS repatching
- [0.2.2](./release-v0.2.2.md) - Pin the macOS installer build
- [0.2.1](./release-v0.2.1.md) - Match the official Vencord installer layout
- [0.2.0](./release-v0.2.0.md) - Self-updating Vencord runtime
- [0.1.0](./release-v0.1.0.md) - First packaged release
