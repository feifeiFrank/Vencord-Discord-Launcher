# Discord with Vencord Portable

Shareable macOS helper project for re-patching the official Discord app with Vencord before launch.

## What this repo is for

- Run Vencord against `/Applications/Discord.app`
- Rebuild from upstream sources instead of shipping your personal paths
- Generate a portable `.app` bundle for sharing

## What this repo is not

- It is not a zero-permission installer
- It cannot bypass macOS security prompts for another user
- It does not bundle Discord itself

## Requirements

- macOS
- Discord installed at `/Applications/Discord.app`
- `git`
- `node`
- `pnpm`
- `go`

## First run

1. Clone this repo anywhere outside OneDrive or iCloud syncing folders.
2. Double-click [`run.command`](./run.command).
3. If macOS blocks access to app bundles, grant the terminal app the required permission and run again.

## What `run.command` does

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

## Important note for people you share this with

Even if the app bundle is portable, the recipient still needs macOS permission to modify `/Applications/Discord.app`.
