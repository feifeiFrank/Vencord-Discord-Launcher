# Discord with Vencord Portable v0.1.0

This is the first packaged release for the portable launcher project.

## Included asset

- `Discord with Vencord Portable.app.zip`
- `Discord with Vencord Portable Windows.zip`

## What it does

- Re-patches the official Discord app with Vencord before launch
- On macOS, uses bundled Vencord build output and bundled Installer CLI
- On Windows, ships a single-file launcher that downloads the official Installer CLI on first run
- Launches Discord after patching

## Requirements

- macOS or Windows
- Discord installed locally
- Apple Silicon (`arm64`) Mac for the macOS app bundle
- Official Discord desktop app for Windows when using the Windows package

## Important notes

- This is not a zero-setup installer
- macOS may ask for permission before the app can modify `/Applications/Discord.app`
- If the app is blocked, the user may need to allow the app or their terminal-equivalent app to manage app bundles
- On Windows, the release contains a single launcher file
- On Windows, the launcher downloads the official `VencordInstallerCli.exe` on first run
- This release does not include Discord itself

## Troubleshooting

- If patching fails, check `/tmp/vencord-portable-install.log`
- If Discord updates and Vencord disappears, run the app again
- On Windows, the log file is `%TEMP%\vencord-portable-install.log`
