# Install Vencord Then Start Discord

Portable launcher project for installing or re-patching Vencord before starting the official Discord desktop app on macOS and Windows.

Keywords: Vencord, Discord, install Vencord, start Discord, macOS, Windows, portable launcher.

## What this repo is for

- Run Vencord against the official Discord desktop app
- Generate a native portable macOS `.app` bundle that refreshes Vencord before launch
- Provide a Windows launcher script that installs or updates Vencord and then starts Discord

## Search-friendly summary

This repository is for people who want a launcher that installs Vencord, re-patches Discord after Discord updates, and then starts Discord automatically.

It is especially useful if you were searching for terms like:

- install Vencord then start Discord
- Vencord auto install before Discord launch
- Discord update removed Vencord
- Vencord launcher for macOS
- Vencord launcher for Windows

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
- Internet access for the first launch and for future Vencord updates
- Apple Command Line Tools only if you build the macOS share app from source

### Windows

- Windows
- Official Discord desktop app installed
- PowerShell
- Internet access to download the official `VencordInstallerCli.exe`

## First run

### macOS

1. Clone this repo anywhere outside OneDrive or iCloud syncing folders.
2. Double-click [`run.command`](./run.command).
3. The first run downloads the latest Vencord release files.
4. If macOS says the app cannot be opened because Apple cannot verify it:
5. Open `System Settings` -> `Privacy & Security`
6. Scroll to the Security section
7. Click `Open Anyway` for the blocked app
8. Run the app again and confirm the second prompt if macOS asks again
9. If macOS blocks writes to Discord, grant the generated app `App Management` permission and run it again.

### Windows

1. Clone this repo anywhere outside OneDrive or cloud-sync folders.
2. Double-click [`windows/run.vbs`](./windows/run.vbs) for the app-like launcher, or [`windows/run.cmd`](./windows/run.cmd) if you want to see logs in a terminal.
3. The launcher downloads the official `VencordInstallerCli.exe` on first run.
4. If Windows asks for permission, allow it and retry if needed.

### Windows single-file share

- Use [`windows/VencordLauncher.cmd`](./windows/VencordLauncher.cmd) if you want one file you can send to other people.
- The single-file launcher still downloads the official `VencordInstallerCli.exe` on first run.
- It stores the downloaded CLI under `%LOCALAPPDATA%\DiscordWithVencordPortable\cache`.

## What the launchers do

### macOS

1. Finds the installed official Discord desktop app
2. Downloads the latest Vencord release `dist` files under `~/Library/Application Support/Vencord/dist`
3. Checks whether Discord's `app.asar` wrapper already points at that Vencord dist path
4. If Discord is already patched, starts Discord without modifying `/Applications/Discord.app`
5. If Discord needs patching, quits Discord, moves `app.asar` to `_app.asar`, and writes a small Vencord wrapper `app.asar`
6. Verifies Discord was patched with the official Vencord data path before launching Discord

The generated macOS share app uses a native AppKit executable instead of a shell, Python, or AppleScript patch path. This keeps macOS App Management attribution on the launcher app itself.

The generated macOS share app follows the official Vencord Installer wrapper layout. It does not bundle a fixed `Vencord/dist` folder and it does not use a private dev-install path. This avoids the old problem where a stale bundled build or personal absolute path could stop working after Discord or Vencord changed.

After the first successful run, Vencord release files are cached under:

```text
~/Library/Application Support/Vencord/dist
```

If the Vencord dist update fails later because the Mac is offline, the launcher keeps using the cached dist as long as `patcher.js` already exists.

### Windows

1. Finds the installed official Discord desktop app
2. Downloads the latest official `VencordInstallerCli.exe` if needed
3. Runs the Vencord installer CLI against Discord
4. Launches Discord

## Build a share bundle

Run:

```bash
./scripts/build-share-app.sh
```

Output goes to `./output/`.

The generated release zip is:

```text
./output/Discord.with.Vencord.Portable.app.zip
```

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
- If the macOS share app fails to build from source, check that Apple Command Line Tools are installed
- If macOS blocks patching, open `System Settings` -> `Privacy & Security` -> `App Management` and enable `Discord with Vencord Portable`
- If you want to force a clean macOS rebuild, delete `~/Library/Caches/DiscordWithVencordPortable` and run the app again
- If Discord updates and Vencord disappears, run `run.command` or the generated macOS share app again
- If macOS shows "Apple could not verify ... is free of malware", go to `System Settings` -> `Privacy & Security` and click `Open Anyway`
- If macOS blocks writes to `/Applications/Discord.app`, grant the generated app `App Management` permission and retry
- The generated share app is not a zero-setup installer; recipients may still need to approve permissions on their own Mac
- On Windows, use the official desktop Discord app and rerun `windows/run.cmd` after Discord updates
- On Windows, installer logs are written to `%TEMP%\vencord-portable-install.log`
- On Windows, [`windows/run.vbs`](./windows/run.vbs) runs the launcher without leaving a terminal window open
- On Windows, [`windows/VencordLauncher.cmd`](./windows/VencordLauncher.cmd) is the portable single-file option

## Windows note

Windows already has official Vencord installers, including a CLI:

- [Official Vencord download page](https://vencord.dev/download/)

This repo is useful if you specifically want a "install Vencord, then start Discord" launcher workflow.

## Important note for people you share this with

Even if the app bundle is portable, the recipient still needs macOS permission to modify `/Applications/Discord.app`.
