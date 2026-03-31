# Discord with Vencord Portable v0.1.0

This is the first packaged release for the macOS portable launcher.

## Included asset

- `Discord with Vencord Portable.app.zip`

## What it does

- Re-patches the official Discord app with Vencord before launch
- Uses bundled Vencord build output and bundled Installer CLI
- Launches `/Applications/Discord.app` after patching

## Requirements

- macOS
- Discord installed at `/Applications/Discord.app`
- Apple Silicon (`arm64`) Mac

## Important notes

- This is not a zero-setup installer
- macOS may ask for permission before the app can modify `/Applications/Discord.app`
- If the app is blocked, the user may need to allow the app or their terminal-equivalent app to manage app bundles
- This release does not include Discord itself

## Troubleshooting

- If patching fails, check `/tmp/vencord-portable-install.log`
- If Discord updates and Vencord disappears, run the app again
