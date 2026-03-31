@echo off
setlocal

set "ROOT_DIR=%~dp0.."
set "CACHE_DIR=%ROOT_DIR%\.cache"
set "SRC_DIR=%CACHE_DIR%\src"
set "BUILD_DIR=%CACHE_DIR%\build"
set "RUNTIME_DIR=%APPDATA%\DiscordWithVencordPortable"

set "VENCORD_REPO=%SRC_DIR%\Vencord"
set "INSTALLER_REPO=%SRC_DIR%\Installer"
set "INSTALLER_CLI=%BUILD_DIR%\VencordInstallerCli.exe"
set "PATCHER_JS=%BUILD_DIR%\Vencord\dist\patcher.js"
set "LOG_FILE=%TEMP%\vencord-portable-install.log"

where git >nul 2>nul || goto :missing_git
where node >nul 2>nul || goto :missing_node
where pnpm >nul 2>nul || goto :missing_pnpm
where go >nul 2>nul || goto :missing_go

if not exist "%SRC_DIR%" mkdir "%SRC_DIR%"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%RUNTIME_DIR%" mkdir "%RUNTIME_DIR%"

call :info Updating Vencord sources
if exist "%VENCORD_REPO%\.git" (
  git -C "%VENCORD_REPO%" pull --ff-only || exit /b 1
) else (
  git clone https://github.com/Vendicated/Vencord.git "%VENCORD_REPO%" || exit /b 1
)

call :info Updating Installer sources
if exist "%INSTALLER_REPO%\.git" (
  git -C "%INSTALLER_REPO%" pull --ff-only || exit /b 1
) else (
  git clone https://github.com/Vencord/Installer.git "%INSTALLER_REPO%" || exit /b 1
)

call :info Installing Vencord dependencies
pushd "%VENCORD_REPO%"
call pnpm install || exit /b 1

call :info Building Vencord desktop assets
call pnpm build || exit /b 1
popd

if exist "%BUILD_DIR%\Vencord" rmdir /s /q "%BUILD_DIR%\Vencord"
mkdir "%BUILD_DIR%\Vencord"
xcopy "%VENCORD_REPO%\dist" "%BUILD_DIR%\Vencord\dist\" /E /I /Y >nul || exit /b 1

call :info Building Installer CLI
pushd "%INSTALLER_REPO%"
call go build --tags cli -o "%INSTALLER_CLI%" || exit /b 1
popd

taskkill /IM Discord.exe /F >nul 2>nul
taskkill /IM DiscordCanary.exe /F >nul 2>nul
taskkill /IM DiscordPTB.exe /F >nul 2>nul

call :info Patching Discord
set "VENCORD_USER_DATA_DIR=%RUNTIME_DIR%"
set "VENCORD_DIRECTORY=%PATCHER_JS%"
set "VENCORD_DEV_INSTALL=1"
"%INSTALLER_CLI%" --install --branch stable > "%LOG_FILE%" 2>&1 || goto :patch_failed

call :info Launching Discord
if exist "%LOCALAPPDATA%\Discord\Update.exe" (
  start "" "%LOCALAPPDATA%\Discord\Update.exe" --processStart Discord.exe
  exit /b 0
)

if exist "%LOCALAPPDATA%\DiscordCanary\Update.exe" (
  start "" "%LOCALAPPDATA%\DiscordCanary\Update.exe" --processStart DiscordCanary.exe
  exit /b 0
)

if exist "%LOCALAPPDATA%\DiscordPTB\Update.exe" (
  start "" "%LOCALAPPDATA%\DiscordPTB\Update.exe" --processStart DiscordPTB.exe
  exit /b 0
)

echo Discord launcher not found in %%LOCALAPPDATA%%.
exit /b 1

:patch_failed
echo Vencord install failed. See "%LOG_FILE%"
exit /b 1

:missing_git
echo Missing required command: git
exit /b 1

:missing_node
echo Missing required command: node
exit /b 1

:missing_pnpm
echo Missing required command: pnpm
exit /b 1

:missing_go
echo Missing required command: go
exit /b 1

:info
echo [info] %*
exit /b 0
