# Discord with Vencord Portable

Shareable helper project for re-patching the official Discord app with Vencord before launch on macOS and Windows.

## What this repo is for

- Run Vencord against the official Discord desktop app
- Rebuild from upstream sources instead of shipping your personal paths
- Generate a portable macOS `.app` bundle for sharing
- Provide a Windows launcher script that installs Vencord and then starts Discord

## What this repo is not

- It is not a zero-permission installer
- It cannot bypass macOS security prompts for another user
- It does not bundle Discord itself

## Platforms

- macOS: supported by `run.command`
- Windows: supported by [`windows/run.cmd`](./windows/run.cmd)

## Requirements

### macOS

- macOS
- Discord installed at `/Applications/Discord.app`
- `git`
- `node`
- `pnpm`
- `go`

### Windows

- Windows
- Official Discord desktop app installed
- `git`
- `node`
- `pnpm`
- `go`

## First run

### macOS

1. Clone this repo anywhere outside OneDrive or iCloud syncing folders.
2. Double-click [`run.command`](./run.command).
3. If macOS blocks access to app bundles, grant the terminal app the required permission and run again.

### Windows

1. Clone this repo anywhere outside OneDrive or cloud-sync folders.
2. Double-click [`windows/run.cmd`](./windows/run.cmd).
3. If Windows asks for permission, allow it and retry if needed.

## What the launchers do

1. Clones or updates `Vencord`
2. Clones or updates `Vencord/Installer`
3. Builds Vencord desktop assets
4. Builds the Installer CLI
5. Re-patches Discord to load the freshly built `patcher.js`
6. Launches Discord

## Build a share bundle

Run:

```bash
./scripts/build-share-app.sh
```

Output goes to `./output/`.

## Push to GitHub

```bash
git init
git add .
git commit -m "Initial commit"
```

Then create a GitHub repo and connect it:

```bash
git remote add origin <your-repo-url>
git push -u origin main
```

## Troubleshooting

- If patching fails, check `/tmp/vencord-portable-install.log`
- If Discord updates and Vencord disappears, run `run.command` again
- If macOS blocks writes to `/Applications/Discord.app`, grant the terminal app the relevant permission and retry
- The generated share app is not a zero-setup installer; recipients may still need to approve permissions on their own Mac
- On Windows, use the official desktop Discord app and rerun `windows/run.cmd` after Discord updates

## Windows note

Windows already has official Vencord installers, including a CLI:

- [Official Vencord download page](https://vencord.dev/download/)

This repo is useful if you specifically want a "install Vencord, then start Discord" launcher workflow.

## Important note for people you share this with

Even if the app bundle is portable, the recipient still needs macOS permission to modify `/Applications/Discord.app`.
