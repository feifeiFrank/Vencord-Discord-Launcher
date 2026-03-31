@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$source = Get-Content -LiteralPath '%~f0' -Raw; $marker = '# POWERSHELL-BEGIN'; $index = $source.LastIndexOf($marker); if ($index -lt 0) { throw 'Launcher payload missing.' }; $payload = $source.Substring($index + $marker.Length); $tmp = Join-Path $env:TEMP ('vencord-launcher-' + [guid]::NewGuid().ToString() + '.ps1'); Set-Content -LiteralPath $tmp -Value $payload -Encoding UTF8; try { & $tmp -Silent; exit $LASTEXITCODE } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }"
exit /b %ERRORLEVEL%
# POWERSHELL-BEGIN
[CmdletBinding()]
param(
    [switch]$ForceDownload,
    [switch]$Silent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$cacheDir = Join-Path $env:LOCALAPPDATA "DiscordWithVencordPortable\cache"
$runtimeDir = Join-Path $env:APPDATA "DiscordWithVencordPortable"
$installerCli = Join-Path $cacheDir "VencordInstallerCli.exe"
$logFile = Join-Path $env:TEMP "vencord-portable-install.log"
$downloadUrl = "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe"

$discordLaunchers = @(
    @{
        Name = "Discord"
        Branch = "stable"
        UpdateExe = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
        ProcessName = "Discord.exe"
    },
    @{
        Name = "Discord PTB"
        Branch = "ptb"
        UpdateExe = Join-Path $env:LOCALAPPDATA "DiscordPTB\Update.exe"
        ProcessName = "DiscordPTB.exe"
    },
    @{
        Name = "Discord Canary"
        Branch = "canary"
        UpdateExe = Join-Path $env:LOCALAPPDATA "DiscordCanary\Update.exe"
        ProcessName = "DiscordCanary.exe"
    }
)

function Write-Info {
    param([string]$Message)

    if (-not $Silent) {
        Write-Host "[info] $Message"
    }
}

function Show-LauncherMessage {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet("Info", "Error")]
        [string]$Kind = "Info"
    )

    Add-Type -AssemblyName PresentationFramework

    $image = [System.Windows.MessageBoxImage]::Information
    if ($Kind -eq "Error") {
        $image = [System.Windows.MessageBoxImage]::Error
    }

    [System.Windows.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::OK,
        $image
    ) | Out-Null
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-DiscordInstall {
    foreach ($launcher in $discordLaunchers) {
        if (Test-Path -LiteralPath $launcher.UpdateExe) {
            return $launcher
        }
    }

    throw "Discord launcher not found under $env:LOCALAPPDATA. Install the official Discord desktop app first."
}

function Stop-DiscordProcesses {
    param(
        [string[]]$ProcessNames
    )

    foreach ($name in $ProcessNames) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
}

function Download-InstallerCli {
    param(
        [string]$Url,
        [string]$Destination
    )

    $tmpFile = "$Destination.download"
    if (Test-Path -LiteralPath $tmpFile) {
        Remove-Item -LiteralPath $tmpFile -Force
    }

    Write-Info "Downloading official Vencord Installer CLI"
    Invoke-WebRequest -Uri $Url -OutFile $tmpFile
    Move-Item -LiteralPath $tmpFile -Destination $Destination -Force
}

function Invoke-InstallerCli {
    param(
        [string]$CliPath,
        [string]$Branch,
        [string]$LogPath
    )

    $stdoutPath = "$LogPath.stdout"
    $stderrPath = "$LogPath.stderr"

    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue

    $process = Start-Process -FilePath $CliPath `
        -ArgumentList "--install", "--branch", $Branch `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $stdout = @()
    $stderr = @()

    if (Test-Path -LiteralPath $stdoutPath) {
        $stdout = Get-Content -LiteralPath $stdoutPath
    }

    if (Test-Path -LiteralPath $stderrPath) {
        $stderr = Get-Content -LiteralPath $stderrPath
    }

    $combined = @($stdout) + @($stderr)
    Set-Content -LiteralPath $LogPath -Value $combined

    if (-not $Silent) {
        foreach ($line in $combined) {
            Write-Host $line
        }
    }

    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue

    return $process.ExitCode
}

try {
    Ensure-Directory -Path $cacheDir
    Ensure-Directory -Path $runtimeDir

    $discordInstall = Get-DiscordInstall

    if ($ForceDownload -or -not (Test-Path -LiteralPath $installerCli)) {
        Download-InstallerCli -Url $downloadUrl -Destination $installerCli
    }

    if (-not (Test-Path -LiteralPath $installerCli)) {
        throw "VencordInstallerCli.exe was not downloaded successfully."
    }

    Write-Info "Using $($discordInstall.Name)"
    Write-Info "Closing Discord if it is already running"
    Stop-DiscordProcesses -ProcessNames @("Discord", "DiscordPTB", "DiscordCanary")
    Write-Info "Installing or updating Vencord"

    $originalEnv = @{
        VENCORD_USER_DATA_DIR = [Environment]::GetEnvironmentVariable("VENCORD_USER_DATA_DIR", "Process")
    }

    try {
        [Environment]::SetEnvironmentVariable("VENCORD_USER_DATA_DIR", $runtimeDir, "Process")

        $exitCode = Invoke-InstallerCli -CliPath $installerCli -Branch $discordInstall.Branch -LogPath $logFile

        if ($exitCode -ne 0) {
            throw "Vencord install failed. See $logFile"
        }
    }
    catch {
        if (-not $ForceDownload) {
            if (-not $Silent) {
                Write-Warning "Installer execution failed. Retrying once with a fresh CLI download."
            }
            Download-InstallerCli -Url $downloadUrl -Destination $installerCli

            $exitCode = Invoke-InstallerCli -CliPath $installerCli -Branch $discordInstall.Branch -LogPath $logFile

            if ($exitCode -ne 0) {
                throw "Vencord install failed after retry. See $logFile"
            }
        }
        else {
            throw
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable("VENCORD_USER_DATA_DIR", $originalEnv.VENCORD_USER_DATA_DIR, "Process")
    }

    Write-Info "Launching $($discordInstall.Name)"
    Start-Process -FilePath $discordInstall.UpdateExe -ArgumentList "--processStart", $discordInstall.ProcessName | Out-Null
}
catch {
    $message = $_.Exception.Message
    if (Test-Path -LiteralPath $logFile) {
        $logContent = Get-Content -LiteralPath $logFile -Raw
        if ($logContent -match "files are used by a different process") {
            $message = "Discord is still running or another process is locking Discord files. Close Discord completely and try again.`n`nSee log:`n$logFile"
        }
    }

    if ($message -notmatch [regex]::Escape($logFile)) {
        $message = "$message`n`nSee log:`n$logFile"
    }

    if ($Silent) {
        Show-LauncherMessage -Title "Vencord launcher failed" -Message $message -Kind Error
    }
    else {
        Write-Error $message
    }

    exit 1
}
