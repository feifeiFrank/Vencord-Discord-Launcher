[CmdletBinding()]
param(
    [switch]$ForceDownload,
    [switch]$Silent,
    [switch]$Standalone
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$installerFileName = "VencordInstallerCli.exe"
$checksumsFileName = "checksums.sha256"

if ($Standalone) {
    $cacheDir = Join-Path $env:LOCALAPPDATA "DiscordWithVencordPortable\cache"
}
else {
    $rootDir = Split-Path -Parent $PSScriptRoot
    $cacheDir = Join-Path $rootDir ".cache\windows"
}

$runtimeDir = Join-Path $env:APPDATA "DiscordWithVencordPortable"
$installerCli = Join-Path $cacheDir $installerFileName
$checksumsFile = Join-Path $cacheDir $checksumsFileName
$logFile = Join-Path $env:TEMP "vencord-portable-install.log"
$releaseDownloadUrl = "https://github.com/Vencord/Installer/releases/latest/download"
$downloadUrl = "$releaseDownloadUrl/$installerFileName"
$checksumsUrl = "$releaseDownloadUrl/$checksumsFileName"

$discordLaunchers = @(
    @{
        Name = "Discord"
        Branch = "stable"
        UpdateExe = Join-Path $env:LOCALAPPDATA "Discord\Update.exe"
        ProcessName = "Discord"
        ExecutableName = "Discord.exe"
    },
    @{
        Name = "Discord PTB"
        Branch = "ptb"
        UpdateExe = Join-Path $env:LOCALAPPDATA "DiscordPTB\Update.exe"
        ProcessName = "DiscordPTB"
        ExecutableName = "DiscordPTB.exe"
    },
    @{
        Name = "Discord Canary"
        Branch = "canary"
        UpdateExe = Join-Path $env:LOCALAPPDATA "DiscordCanary\Update.exe"
        ProcessName = "DiscordCanary"
        ExecutableName = "DiscordCanary.exe"
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

function Get-ExpectedInstallerHash {
    param(
        [string]$ChecksumsPath,
        [string]$InstallerName
    )

    if (-not (Test-Path -LiteralPath $ChecksumsPath -PathType Leaf)) {
        throw "Checksum file not found: $ChecksumsPath"
    }

    $expectedHashes = @()
    $checksumPattern = '^(?<Hash>[0-9A-Fa-f]{64})[ \t]+\*?(?<Name>.+?)\s*$'

    foreach ($line in Get-Content -LiteralPath $ChecksumsPath) {
        $match = [regex]::Match($line, $checksumPattern)
        if ($match.Success -and $match.Groups["Name"].Value.Trim() -ceq $InstallerName) {
            $expectedHashes += $match.Groups["Hash"].Value.ToLowerInvariant()
        }
    }

    if ($expectedHashes.Count -ne 1) {
        throw "Expected exactly one SHA-256 entry for $InstallerName in $ChecksumsPath; found $($expectedHashes.Count)."
    }

    return $expectedHashes[0]
}

function Assert-InstallerChecksum {
    param(
        [string]$CliPath,
        [string]$ChecksumsPath,
        [string]$InstallerName
    )

    if (-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
        throw "Installer CLI not found: $CliPath"
    }

    $expectedHash = Get-ExpectedInstallerHash -ChecksumsPath $ChecksumsPath -InstallerName $InstallerName
    $actualHash = (Get-FileHash -LiteralPath $CliPath -Algorithm SHA256).Hash.ToLowerInvariant()

    if (-not [string]::Equals($actualHash, $expectedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "SHA-256 verification failed for $InstallerName. Expected $expectedHash but got $actualHash."
    }
}

function Test-InstallerChecksum {
    param(
        [string]$CliPath,
        [string]$ChecksumsPath,
        [string]$InstallerName
    )

    try {
        Assert-InstallerChecksum -CliPath $CliPath -ChecksumsPath $ChecksumsPath -InstallerName $InstallerName
        return $true
    }
    catch {
        Write-Info "Cached installer verification failed: $($_.Exception.Message)"
        return $false
    }
}

function Download-InstallerCli {
    param(
        [string]$Url,
        [string]$ChecksumsUrl,
        [string]$Destination,
        [string]$ChecksumsDestination,
        [string]$InstallerName
    )

    $downloadId = [guid]::NewGuid().ToString("N")
    $destinationDir = Split-Path -Parent $Destination
    $tmpFile = Join-Path $destinationDir "$InstallerName.$downloadId.download"
    $tmpChecksumsFile = Join-Path $destinationDir "checksums.$downloadId.download"

    try {
        Write-Info "Downloading official Vencord Installer CLI and SHA-256 checksums"
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $tmpFile
        Invoke-WebRequest -UseBasicParsing -Uri $ChecksumsUrl -OutFile $tmpChecksumsFile

        Assert-InstallerChecksum -CliPath $tmpFile -ChecksumsPath $tmpChecksumsFile -InstallerName $InstallerName

        Move-Item -LiteralPath $tmpChecksumsFile -Destination $ChecksumsDestination -Force
        Move-Item -LiteralPath $tmpFile -Destination $Destination -Force

        Assert-InstallerChecksum -CliPath $Destination -ChecksumsPath $ChecksumsDestination -InstallerName $InstallerName
        Write-Info "Verified $InstallerName with the official SHA-256 checksum"
    }
    finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpChecksumsFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-InstallerCli {
    param(
        [string]$CliPath,
        [string]$Branch,
        [string]$LogPath,
        [string]$ChecksumsPath,
        [string]$InstallerName
    )

    Assert-InstallerChecksum -CliPath $CliPath -ChecksumsPath $ChecksumsPath -InstallerName $InstallerName

    $stdoutPath = "$LogPath.stdout"
    $stderrPath = "$LogPath.stderr"

    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue

    try {
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

        return $process.ExitCode
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

try {
    Ensure-Directory -Path $cacheDir
    Ensure-Directory -Path $runtimeDir

    $discordInstall = Get-DiscordInstall

    $cachedInstallerIsValid = Test-InstallerChecksum `
        -CliPath $installerCli `
        -ChecksumsPath $checksumsFile `
        -InstallerName $installerFileName

    if ($ForceDownload -or -not $cachedInstallerIsValid) {
        Download-InstallerCli `
            -Url $downloadUrl `
            -ChecksumsUrl $checksumsUrl `
            -Destination $installerCli `
            -ChecksumsDestination $checksumsFile `
            -InstallerName $installerFileName
    }

    Assert-InstallerChecksum -CliPath $installerCli -ChecksumsPath $checksumsFile -InstallerName $installerFileName

    Write-Info "Using $($discordInstall.Name)"
    Write-Info "Closing Discord if it is already running"
    Stop-DiscordProcesses -ProcessNames @($discordInstall.ProcessName)
    Write-Info "Installing or updating Vencord"

    $originalEnv = @{
        VENCORD_USER_DATA_DIR = [Environment]::GetEnvironmentVariable("VENCORD_USER_DATA_DIR", "Process")
    }

    try {
        [Environment]::SetEnvironmentVariable("VENCORD_USER_DATA_DIR", $runtimeDir, "Process")

        $exitCode = Invoke-InstallerCli `
            -CliPath $installerCli `
            -Branch $discordInstall.Branch `
            -LogPath $logFile `
            -ChecksumsPath $checksumsFile `
            -InstallerName $installerFileName

        if ($exitCode -ne 0) {
            throw "Vencord install failed. See $logFile"
        }
    }
    catch {
        if (-not $ForceDownload) {
            if (-not $Silent) {
                Write-Warning "Installer execution failed. Retrying once with a fresh CLI download."
            }
            Download-InstallerCli `
                -Url $downloadUrl `
                -ChecksumsUrl $checksumsUrl `
                -Destination $installerCli `
                -ChecksumsDestination $checksumsFile `
                -InstallerName $installerFileName

            $exitCode = Invoke-InstallerCli `
                -CliPath $installerCli `
                -Branch $discordInstall.Branch `
                -LogPath $logFile `
                -ChecksumsPath $checksumsFile `
                -InstallerName $installerFileName

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
    Start-Process -FilePath $discordInstall.UpdateExe -ArgumentList "--processStart", $discordInstall.ExecutableName | Out-Null
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
