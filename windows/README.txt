Discord with Vencord Portable - Windows

Requirements:
- Windows with the official Discord desktop app installed
- Windows PowerShell
- Internet access on first run and when the official installer changes

Usage:
1. Double-click VencordLauncher.cmd.
2. The launcher detects Discord Stable, PTB, or Canary.
3. It downloads the official Vencord Installer CLI and the release checksum.
4. It verifies SHA-256, installs or repairs Vencord, and starts Discord.

The launcher stores its verified installer cache under:
%LOCALAPPDATA%\DiscordWithVencordPortable\cache

Troubleshooting:
- The log is %TEMP%\vencord-portable-install.log
- If Discord files are locked, close Discord completely and try again.
- This package does not include Discord and is not an official Vencord release.
