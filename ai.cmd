:<<"::CMDLITERAL"
@echo off
setlocal DisableDelayedExpansion
set "ARGS=%*"
if "%~1"=="--" set "ARGS=%ARGS:~3%"
set "CHECK_PATH=%cd%%~dp0%TEMP%%TMP%%AI_RECIPE%"
if "%~1"=="export" set "CHECK_PATH=%CHECK_PATH%%~2"
if "%~1"=="--export" set "CHECK_PATH=%CHECK_PATH%%~2"
if "%~1"=="import" set "CHECK_PATH=%CHECK_PATH%%~2"
if "%~1"=="--import" set "CHECK_PATH=%CHECK_PATH%%~2"
set CHECK_PATH | findstr /l /c:"!" >nul && (
    echo [ai] Paths containing exclamation marks are not supported by the Windows launcher. >&2
    exit /b 1
)
setlocal EnableDelayedExpansion
if defined AI_RECIPE (
    if not exist "!AI_RECIPE!" (
        echo [ai] Recipe not readable. >&2
        exit /b 1
    )
    findstr /r /v /c:"^#.*$" /c:"^$" /c:"^[A-Z_][A-Z_]*=[a-zA-Z0-9_ .:/@,+-][a-zA-Z0-9_ .:/@=,+-]*$" /c:"^[A-Z_][A-Z_]*=$" "!AI_RECIPE!" >nul
    if errorlevel 2 exit /b 1
    if not errorlevel 1 (
        echo [ai] Unsupported recipe characters. Use plain KEY=value lines without shell quoting. >&2
        exit /b 1
    )
    for /f "usebackq eol=# tokens=1,* delims==" %%k in ("!AI_RECIPE!") do (
        set "ALLOWED="
        for %%a in (AI_STATE AI_VOLUME AI_IMAGE AI_NETWORK AI_ENV AI_ARGS AI_PROJECT_MODE) do if "%%k"=="%%a" set "ALLOWED=1"
        if not defined ALLOWED (
            echo [ai] Unknown recipe key: %%k >&2
            exit /b 1
        )
        set "%%k=%%l"
        if "%%k"=="AI_STATE" if "%%l"=="" set "AI_STATE=none"
    )
)


set "LAUNCH_TOOL=%~nx1"
if "%~1"=="--" set "LAUNCH_TOOL=%~nx2"
set "DEFAULT_IMAGE=ghcr.io/jjjakob502/ai.cmd:latest"
set "IMAGE=!DEFAULT_IMAGE!"
if defined AI_IMAGE set "IMAGE=!AI_IMAGE!"
set "VOLUME=ai-auth"
if defined AI_VOLUME set "VOLUME=!AI_VOLUME!"
set "AI_UID_SET="
set "AI_GID_SET="
set "AI_CLIS_SET="
if defined AI_UID set "AI_UID_SET=1"
if defined AI_GID set "AI_GID_SET=1"
if defined AI_CLIS set "AI_CLIS_SET=1"
if not defined AI_UID set "AI_UID=10001"
if not defined AI_GID set "AI_GID=10001"
if not defined AI_CLIS set "AI_CLIS=claude codex agy grok pi"
set "BUILD_OPTIONS="
set "AI_SCRIPT_PATH=%~f0"

if "%~1"=="install" goto :sub_install
if "%~1"=="--install" goto :sub_install
if "%~1"=="dockerfile" goto :sub_dockerfile
if "%~1"=="--dockerfile" goto :sub_dockerfile
if "%~1"=="sync" goto :sub_sync
if "%~1"=="--sync" goto :sub_sync
if "%~1"=="export" goto :sub_export
if "%~1"=="--export" goto :sub_export
if "%~1"=="import" goto :sub_import
if "%~1"=="--import" goto :sub_import
if "%~1"=="build" goto :sub_build
if "%~1"=="--build" goto :sub_build
if "%~1"=="update" goto :sub_update
if "%~1"=="--update" goto :sub_update
goto :sub_run

:detect_engine
set "ENGINE_CMD="
set "WORKDIR_PATH=%cd%"
set "SCRIPTDIR_PATH=%~dp0"
if not "%AI_ENGINE%"=="" (
    set "ENGINE_CMD=%AI_ENGINE%"
    exit /b 0
)
where podman >nul 2>nul && (
    set "ENGINE_CMD=podman"
    exit /b 0
)
where docker >nul 2>nul && (
    set "ENGINE_CMD=docker"
    exit /b 0
)
echo Error: install Podman or Docker, or run ./ai.cmd inside WSL. >&2
exit /b 1

:state_options
set "PODMAN_ROOTLESS="
set "STATE_ARGS="
set "ARCHIVE_HOME=/state"
for /f "tokens=*" %%r in ('%ENGINE_CMD% info --format "{{.Host.Security.Rootless}}" 2^>nul') do (
    set "PODMAN_ROOTLESS=%%r"
    if "%%r"=="false" (
        echo [ai] Use rootless Podman or Docker Desktop. >&2
        exit /b 1
    )
    if "%%r"=="true" (
        set "STATE_ARGS=--user 0"
        set "ARCHIVE_HOME=/data"
    )
)
if not "!PODMAN_ROOTLESS!"=="true" (
    set "ENGINE_SECURITY="
    for /f "tokens=*" %%r in ('%ENGINE_CMD% info --format "{{json .SecurityOptions}}" 2^>nul') do set "ENGINE_SECURITY=%%r"
    echo !ENGINE_SECURITY!| findstr /c:"rootless" >nul && (
        echo [ai] Use rootless Podman or Docker Desktop. >&2
        exit /b 1
    )
)
call :select_state
exit /b %errorlevel%

:select_state
set "SELECTED_STATE=!AI_STATE!"
if not defined AI_STATE (
    for %%s in (claude codex agy grok pi gh aws) do if "!LAUNCH_TOOL!"=="%%s" set "SELECTED_STATE=%%s"
    for %%s in (ssh ssh-keygen scp sftp) do if "!LAUNCH_TOOL!"=="%%s" set "SELECTED_STATE=ssh"
    if "!LAUNCH_TOOL!"=="pi-coding-agent" set "SELECTED_STATE=pi"
)
if "!SELECTED_STATE!"=="none" set "SELECTED_STATE="
echo !VOLUME!| findstr /r /x "[a-zA-Z0-9][a-zA-Z0-9_.-]*" >nul || (
    echo [ai] Invalid volume prefix. >&2
    exit /b 1
)
set "STATE_NAMES="
set "STATE_MOUNTS="
set "ARCHIVE_MOUNTS="
set "ARCHIVE_SOURCE_MOUNTS="
set "ARCHIVE_OPTIONS="
set "SOURCE_OPTIONS=:ro"
if "!PODMAN_ROOTLESS!"=="true" (
    set "ARCHIVE_OPTIONS=:nocopy"
    set "SOURCE_OPTIONS=:ro,nocopy"
)
for %%s in (!SELECTED_STATE!) do (
    set "STATE_PATH="
    if "%%s"=="claude" set "STATE_PATH=.claude"
    if "%%s"=="codex" set "STATE_PATH=.codex"
    if "%%s"=="agy" set "STATE_PATH=.gemini"
    if "%%s"=="grok" set "STATE_PATH=.grok"
    if "%%s"=="pi" set "STATE_PATH=.pi/agent"
    if "%%s"=="ssh" set "STATE_PATH=.ssh"
    if "%%s"=="gh" set "STATE_PATH=.config/gh"
    if "%%s"=="aws" set "STATE_PATH=.aws"
    if not defined STATE_PATH (
        echo [ai] Unknown state: %%s >&2
        exit /b 1
    )
    set "SEEN="
    for %%t in (!STATE_NAMES!) do if "%%t"=="%%s" set "SEEN=1"
    if not defined SEEN (
        set "STATE_NAMES=!STATE_NAMES! %%s"
        set "STATE_MOUNTS=!STATE_MOUNTS! -v !VOLUME!-%%s:/home/ai/!STATE_PATH!"
        set "ARCHIVE_MOUNTS=!ARCHIVE_MOUNTS! -v !VOLUME!-%%s:!ARCHIVE_HOME!/%%s!ARCHIVE_OPTIONS!"
        set "ARCHIVE_SOURCE_MOUNTS=!ARCHIVE_SOURCE_MOUNTS! -v !VOLUME!-%%s:!ARCHIVE_HOME!/%%s!SOURCE_OPTIONS!"
    )
)
for %%c in (export --export import --import sync --sync) do if "!LAUNCH_TOOL!"=="%%c" if not defined STATE_NAMES (
    echo [ai] Select state first, for example AI_STATE=claude gh. >&2
    exit /b 1
)
exit /b 0

:check_state_image
if /i "%ENGINE_CMD%"=="echo" exit /b 0
set "STATE_LAYOUT="
for /f "tokens=*" %%l in ('%ENGINE_CMD% image inspect --format "{{index .Config.Labels \"io.ai-cmd.state-layout\"}}" !IMAGE!') do set "STATE_LAYOUT=%%l"
if not "!STATE_LAYOUT!"=="selected-v1" (
    echo [ai] Image predates selected state support. Run ai update or ai build. >&2
    exit /b 1
)
exit /b 0

:require_state
for %%s in (!STATE_NAMES!) do (
    %ENGINE_CMD% volume inspect !VOLUME!-%%s >nul 2>nul || (
        echo [ai] State volume does not exist: !VOLUME!-%%s >&2
        exit /b 1
    )
)
exit /b 0

:private_archive
set "SYNC_FILE="
for /f "tokens=*" %%f in ('powershell -NoProfile -Command "$dir=$env:ARCHIVE_DIR; if (-not $dir) { $dir=[IO.Path]::GetTempPath() }; $p=Join-Path $dir ([IO.Path]::GetRandomFileName()); $f=[IO.File]::Open($p,[IO.FileMode]::CreateNew); $f.Close(); $p"') do set "SYNC_FILE=%%f"
if not defined SYNC_FILE exit /b 1
icacls "!SYNC_FILE!" /inheritance:r /grant:r "%USERNAME%:(F)" >nul || (
    del /q "!SYNC_FILE!" >nul 2>nul
    exit /b 1
)
exit /b 0

:sub_install
set "WINAPPS=%LOCALAPPDATA%\Microsoft\WindowsApps"
if not exist "!WINAPPS!" (
    echo [ai install] Target directory not found: !WINAPPS! >&2
    exit /b 1
)
copy /y "%~f0" "!WINAPPS!\ai.cmd" >nul || (
    echo [ai install] Failed to copy to !WINAPPS!\ai.cmd >&2
    exit /b 1
)
echo [ai install] Installed to !WINAPPS!\ai.cmd
echo [ai install] Success! You can now run 'ai <command>' from any terminal.
exit /b 0

:sub_dockerfile
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $txt = Get-Content -Raw -LiteralPath $env:AI_SCRIPT_PATH; if ($txt -notmatch '(?s)cat << ''EOF_DOCKERFILE''\r?\n(.*?)\r?\nEOF_DOCKERFILE') { throw 'Embedded Dockerfile not found' }; [Console]::Out.Write($matches[1])"
exit /b %errorlevel%

:sub_build
call :detect_engine || exit /b 1
call :build_image
exit /b %errorlevel%

:build_image
if not "!IMAGE:@=!"=="!IMAGE!" (
    echo [ai build] A digest is immutable. Set AI_IMAGE to a tag before building. >&2
    exit /b 1
)
echo !AI_UID!:!AI_GID!| findstr /r /x "[0-9][0-9]*:[0-9][0-9]*" >nul || exit /b 1
echo !AI_CLIS!| findstr /r /x /c:"[a-z ][a-z ]*" >nul || exit /b 1
for %%c in (!AI_CLIS!) do (
    set "KNOWN_CLI="
    for %%a in (claude codex agy grok pi none) do if "%%c"=="%%a" set "KNOWN_CLI=1"
    if not defined KNOWN_CLI (
        echo [ai build] Unknown AI CLI: %%c >&2
        exit /b 1
    )
    if "%%c"=="none" if not "!AI_CLIS!"=="none" exit /b 1
)
echo [ai build] Building !IMAGE!...
set "TMP_DOCKERFILE=%TEMP%\ai-Dockerfile-%RANDOM%.tmp"
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $txt = Get-Content -Raw -LiteralPath $env:AI_SCRIPT_PATH; if ($txt -notmatch '(?s)cat << ''EOF_DOCKERFILE''\r?\n(.*?)\r?\nEOF_DOCKERFILE') { throw 'Embedded Dockerfile not found' }; [IO.File]::WriteAllText($env:TMP_DOCKERFILE, $matches[1])"
if errorlevel 1 exit /b 1
%ENGINE_CMD% build !BUILD_OPTIONS! --label io.ai-cmd.update=build --build-arg "AI_CLIS=!AI_CLIS!" --build-arg "AI_UID=!AI_UID!" --build-arg "AI_GID=!AI_GID!" -t "!IMAGE!" -f "!TMP_DOCKERFILE!" "%SCRIPTDIR_PATH%."
set "BUILD_EXIT=!errorlevel!"
del /q "!TMP_DOCKERFILE!" >nul 2>nul
exit /b !BUILD_EXIT!

:sub_update
call :detect_engine || exit /b 1
echo [ai update] Updating !IMAGE!...
if /i "%ENGINE_CMD%"=="echo" goto :update_pull
if not "!IMAGE:@=!"=="!IMAGE!" goto :update_pull
%ENGINE_CMD% image inspect "!IMAGE!" >nul 2>nul || goto :update_pull
set "UPDATE_POLICY="
for /f "tokens=*" %%p in ('%ENGINE_CMD% image inspect --format "{{index .Config.Labels \"io.ai-cmd.update\"}}" "!IMAGE!"') do set "UPDATE_POLICY=%%p"
if "!UPDATE_POLICY!"=="build" goto :update_build
set "IMAGE_ORIGIN="
for /f "tokens=*" %%p in ('%ENGINE_CMD% image inspect --format "{{if .RepoDigests}}pulled{{else}}local{{end}}" "!IMAGE!"') do set "IMAGE_ORIGIN=%%p"
if not "!IMAGE_ORIGIN!"=="pulled" (
    echo [ai update] Image has no update policy. Run ai build with your original AI_CLIS, or pull explicitly with your engine. >&2
    exit /b 1
)
:update_pull
%ENGINE_CMD% pull !IMAGE!
exit /b %errorlevel%

:update_build
if not defined AI_CLIS_SET (
    set "AI_CLIS="
    for /f "tokens=*" %%c in ('%ENGINE_CMD% image inspect --format "{{index .Config.Labels \"io.ai-cmd.clis\"}}" "!IMAGE!"') do set "AI_CLIS=%%c"
)
if not defined AI_UID_SET (
    set "AI_UID="
    for /f "tokens=*" %%u in ('%ENGINE_CMD% image inspect --format "{{index .Config.Labels \"io.ai-cmd.uid\"}}" "!IMAGE!"') do set "AI_UID=%%u"
)
if not defined AI_GID_SET (
    set "AI_GID="
    for /f "tokens=*" %%g in ('%ENGINE_CMD% image inspect --format "{{index .Config.Labels \"io.ai-cmd.gid\"}}" "!IMAGE!"') do set "AI_GID=%%g"
)
if not defined AI_CLIS exit /b 1
set "BUILD_OPTIONS=--pull --no-cache"
call :build_image
exit /b %errorlevel%

:sub_export
call :detect_engine || exit /b 1
call :state_options || exit /b 1
call :check_state_image || exit /b 1
call :require_state || exit /b 1
set "OUTFILE=%~2"
if not defined OUTFILE set "OUTFILE=ai-state.tar.gz"
for %%f in ("!OUTFILE!") do set "ARCHIVE_DIR=%%~dpf"
call :private_archive || exit /b 1
%ENGINE_CMD% run --rm !STATE_ARGS! !ARCHIVE_SOURCE_MOUNTS! !IMAGE! tar czf - -C !ARCHIVE_HOME! !STATE_NAMES! >"!SYNC_FILE!"
if errorlevel 1 goto :sync_failed
move /y "!SYNC_FILE!" "!OUTFILE!" >nul
if errorlevel 1 goto :sync_failed
icacls "!OUTFILE!" /inheritance:r /grant:r "%USERNAME%:(F)" >nul || exit /b 1
echo [ai export] Created: !OUTFILE!
exit /b 0

:sub_import
call :detect_engine || exit /b 1
call :state_options || exit /b 1
call :check_state_image || exit /b 1
set "INFILE=%~2"
if not defined INFILE (
    echo Usage: ai import ^<filename.tar.gz^> [--overwrite] >&2
    exit /b 1
)
if not exist "!INFILE!" (
    echo [ai import] Archive not found. >&2
    exit /b 1
)
set "IMPORT_OPTIONS=--keep-newer-files"
if not "%~3"=="" if not "%~3"=="--overwrite" (
    echo Usage: ai import ^<filename.tar.gz^> [--overwrite] >&2
    exit /b 1
)
if not "%~4"=="" exit /b 1
if "%~3"=="--overwrite" set "IMPORT_OPTIONS="
%ENGINE_CMD% run --rm !STATE_ARGS! !ARCHIVE_MOUNTS! -i !IMAGE! bsdtar xzf - --no-same-owner !IMPORT_OPTIONS! -C !ARCHIVE_HOME! !STATE_NAMES! <"!INFILE!"
if errorlevel 1 exit /b !errorlevel!
echo [ai import] Import complete.
exit /b 0

:sub_sync
call :detect_engine || exit /b 1
set "ARCHIVE_DIR="
set "ACTION=%~2"
set "TARGET=%~3"
if "%TARGET%"=="" set "TARGET=%AI_SYNC_TARGET%"
if not "%ACTION%"=="push" if not "%ACTION%"=="pull" (
    echo Usage: ai sync [push^|pull] ^<target_ssh_host^> >&2
    exit /b 1
)
if "%TARGET%"=="" (
    echo [ai sync] Target SSH host required. >&2
    exit /b 1
)
call :state_options || exit /b 1
call :check_state_image || exit /b 1
call :require_state || exit /b 1
echo !IMAGE!| findstr /r /x "[a-zA-Z0-9_./:@-][a-zA-Z0-9_./:@-]*" >nul || exit /b 1
if "!TARGET:~0,1!"=="-" exit /b 1
set "REMOTE_ENGINE="
for /f "tokens=*" %%r in ('ssh "%TARGET%" "if command -v podman >/dev/null 2>&1; then echo podman; elif command -v docker >/dev/null 2>&1; then echo docker; fi"') do set "REMOTE_ENGINE=%%r"
if not "!REMOTE_ENGINE!"=="podman" if not "!REMOTE_ENGINE!"=="docker" (
    echo [ai sync] A reachable POSIX SSH host with Podman or Docker is required. Remote Windows is not supported. >&2
    exit /b 1
)
set "REMOTE_LAYOUT="
for /f "tokens=*" %%r in ('ssh "%TARGET%" "!REMOTE_ENGINE! image inspect --format '{{index .Config.Labels \"io.ai-cmd.state-layout\"}}' '!IMAGE!'"') do set "REMOTE_LAYOUT=%%r"
if not "!REMOTE_LAYOUT!"=="selected-v1" (
    echo [ai sync] Remote image needs selective-state support. Run ai build there. >&2
    exit /b 1
)
set "REMOTE_ARGS="
set "REMOTE_HOME=/state"
set "REMOTE_ROOTLESS="
for /f "tokens=*" %%r in ('ssh "%TARGET%" "!REMOTE_ENGINE! info --format '{{.Host.Security.Rootless}}' 2>/dev/null"') do set "REMOTE_ROOTLESS=%%r"
if "!REMOTE_ROOTLESS!"=="false" (
    echo [ai sync] Remote Podman must run rootless. >&2
    exit /b 1
)
if "!REMOTE_ROOTLESS!"=="true" (
    set "REMOTE_ARGS=--user 0"
    set "REMOTE_HOME=/data"
) else (
    set "REMOTE_SECURITY="
    for /f "tokens=*" %%r in ('ssh "%TARGET%" "!REMOTE_ENGINE! info --format '{{json .SecurityOptions}}'"') do set "REMOTE_SECURITY=%%r"
    if "!REMOTE_SECURITY!"=="" exit /b 1
    echo !REMOTE_SECURITY!| findstr /c:"rootless" >nul && (
        echo [ai sync] Remote rootless Docker is not supported; use Podman. >&2
        exit /b 1
    )
)
set "REMOTE_MOUNTS="
set "REMOTE_SOURCE_MOUNTS="
set "REMOTE_OPTIONS="
set "REMOTE_SOURCE_OPTIONS=:ro"
if "!REMOTE_ROOTLESS!"=="true" (
    set "REMOTE_OPTIONS=:nocopy"
    set "REMOTE_SOURCE_OPTIONS=:ro,nocopy"
)
for %%s in (!STATE_NAMES!) do (
    ssh "!TARGET!" "!REMOTE_ENGINE! volume inspect '!VOLUME!-%%s' >/dev/null" || (
        echo [ai sync] Initialize remote state first: %%s >&2
        exit /b 1
    )
    set "REMOTE_MOUNTS=!REMOTE_MOUNTS! -v !VOLUME!-%%s:!REMOTE_HOME!/%%s!REMOTE_OPTIONS!"
    set "REMOTE_SOURCE_MOUNTS=!REMOTE_SOURCE_MOUNTS! -v !VOLUME!-%%s:!REMOTE_HOME!/%%s!REMOTE_SOURCE_OPTIONS!"
)
call :private_archive || exit /b 1
if "%ACTION%"=="push" (
    %ENGINE_CMD% run --rm !STATE_ARGS! !ARCHIVE_SOURCE_MOUNTS! !IMAGE! tar czf - -C !ARCHIVE_HOME! !STATE_NAMES! >"!SYNC_FILE!"
    if errorlevel 1 goto :sync_failed
    ssh "%TARGET%" "!REMOTE_ENGINE! run --rm !REMOTE_ARGS! !REMOTE_MOUNTS! -i '!IMAGE!' bsdtar xzf - --no-same-owner --keep-newer-files -C !REMOTE_HOME! !STATE_NAMES!" <"!SYNC_FILE!"
    if errorlevel 1 goto :sync_failed
) else (
    ssh "%TARGET%" "!REMOTE_ENGINE! run --rm !REMOTE_ARGS! !REMOTE_SOURCE_MOUNTS! '!IMAGE!' tar czf - -C !REMOTE_HOME! !STATE_NAMES!" >"!SYNC_FILE!"
    if errorlevel 1 goto :sync_failed
    %ENGINE_CMD% run --rm !STATE_ARGS! !ARCHIVE_MOUNTS! -i !IMAGE! bsdtar xzf - --no-same-owner --keep-newer-files -C !ARCHIVE_HOME! !STATE_NAMES! <"!SYNC_FILE!"
    if errorlevel 1 goto :sync_failed
)
del /q "!SYNC_FILE!"
echo [ai sync] %ACTION% complete.
exit /b 0

:sync_failed
if defined SYNC_FILE del /q "!SYNC_FILE!" >nul 2>nul
echo [ai sync] Transfer failed. >&2
exit /b 1

:sub_run
call :detect_engine || exit /b 1
call :state_options || exit /b 1
%ENGINE_CMD% image inspect !IMAGE! >nul 2>nul || (
    echo [ai] Pulling !IMAGE!...
    %ENGINE_CMD% pull -q !IMAGE! >nul || (
        if not "!IMAGE!"=="!DEFAULT_IMAGE!" (
            echo [ai] Could not pull the requested image: !IMAGE! >&2
            exit /b 1
        )
        echo [ai] Default image pull failed, building locally...
        call :build_image || exit /b 1
    )
)
call :check_state_image || exit /b 1
set "PROJECT_MODE=!AI_PROJECT_MODE!"
if not defined PROJECT_MODE set "PROJECT_MODE=rw"
if not "!PROJECT_MODE!"=="rw" if not "!PROJECT_MODE!"=="ro" if not "!PROJECT_MODE!"=="none" (
    echo [ai] AI_PROJECT_MODE must be rw, ro, or none. >&2
    exit /b 1
)

if not "!PROJECT_MODE!"=="none" if /i "%cd%"=="%USERPROFILE%" if "%AI_ALLOW_HOME%"=="" (
    echo [ai] Refusing to mount %cd%: it would expose your keys and other secrets. Run from a project folder, or set AI_ALLOW_HOME=1. >&2
    exit /b 1
)
if not "!PROJECT_MODE!"=="none" if "%cd:~1%"==":\" if "%AI_ALLOW_HOME%"=="" (
    echo [ai] Refusing to mount drive root %cd%. Run from a project folder, or set AI_ALLOW_HOME=1. >&2
    exit /b 1
)
set "USERNS_ARGS="
if /i "%ENGINE_CMD%"=="echo" goto :run_args
set "IMAGE_UID="
set "IMAGE_GID="
for /f "tokens=*" %%u in ('%ENGINE_CMD% image inspect --format "{{index .Config.Labels \"io.ai-cmd.uid\"}}" !IMAGE!') do set "IMAGE_UID=%%u"
for /f "tokens=*" %%g in ('%ENGINE_CMD% image inspect --format "{{index .Config.Labels \"io.ai-cmd.gid\"}}" !IMAGE!') do set "IMAGE_GID=%%g"
echo !IMAGE_UID!:!IMAGE_GID!| findstr /r /x "[0-9][0-9]*:[0-9][0-9]*" >nul || (
    echo [ai] Image predates non-root support. Run ai update or ai build. >&2
    exit /b 1
)
if "!PODMAN_ROOTLESS!"=="true" set "USERNS_ARGS=--userns=keep-id:uid=!IMAGE_UID!,gid=!IMAGE_GID!"

:run_args
if not defined AI_NETWORK set "AI_NETWORK=bridge"

if not defined ARGS set "ARGS=/bin/bash"

set "EXTRA_ENV="
if defined AI_ENV for %%v in (!AI_ENV!) do set "EXTRA_ENV=!EXTRA_ENV! -e %%v"

set "PROJECT_PATH=%cd%"
set "PROJECT_PATH=!PROJECT_PATH:\=/!"
set "PROJECT_PATH=!PROJECT_PATH::=!"
set "PROJECT_DIR=/workspace/!PROJECT_PATH!"

set "PROJECT_MOUNT=-v "!WORKDIR_PATH!:!PROJECT_DIR!:!PROJECT_MODE!""
if "!PROJECT_MODE!"=="none" (
    set "PROJECT_MOUNT="
    set "PROJECT_DIR=/home/ai"
)
set "TTY_ARG=-i"
powershell -NoProfile -Command "try { if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { exit 1 }; exit 0 } catch { exit 1 }"
if not errorlevel 1 (
    set "TTY_ARG=-it"
) else (
    (call )
)
%ENGINE_CMD% run --rm !TTY_ARG! !USERNS_ARGS! --cap-drop=ALL --security-opt=no-new-privileges --network !AI_NETWORK! !PROJECT_MOUNT! !STATE_MOUNTS! -w "!PROJECT_DIR!" -e TERM !EXTRA_ENV! !AI_ARGS! !IMAGE! !ARGS!
if /i "%ENGINE_CMD%"=="echo" exit /b 0
exit /b %errorlevel%
::CMDLITERAL

set -eu
set -f

if [ -n "${AI_RECIPE:-}" ]; then
    [ -r "$AI_RECIPE" ] || { echo '[ai] Recipe not readable.' >&2; exit 1; }
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | tr -d '\r')
        case "$line" in ''|\#*) continue ;; esac
        case "$line" in
            *[!a-zA-Z0-9_./:@=,+\ -]*) echo '[ai] Recipes use literal values without quotes or shell metacharacters.' >&2; exit 1 ;;
        esac
        key=${line%%=*}
        case "$key" in
            AI_STATE|AI_VOLUME|AI_IMAGE|AI_NETWORK|AI_ENV|AI_ARGS|AI_PROJECT_MODE)
                [ "$line" != "$key" ] || { echo '[ai] Recipe requires KEY=value lines.' >&2; exit 1; }
                export "$key=${line#*=}" ;;
            *) echo "[ai] Unknown recipe key: $key" >&2; exit 1 ;;
        esac
    done <"$AI_RECIPE"
fi

DEFAULT_IMAGE=ghcr.io/jjjakob502/ai.cmd:latest
IMAGE="${AI_IMAGE:-$DEFAULT_IMAGE}"
VOLUME="${AI_VOLUME:-ai-auth}"
AI_CLIS_SET=${AI_CLIS+x}
AI_CLIS="${AI_CLIS-claude codex agy grok pi}"

TARGET_FILE="$0"
while [ -h "$TARGET_FILE" ]; do
    TARGET_DIR="$(cd -P "$(dirname "$TARGET_FILE")" && pwd)"
    TARGET_FILE="$(readlink "$TARGET_FILE")"
    case "$TARGET_FILE" in /*) ;; *) TARGET_FILE="$TARGET_DIR/$TARGET_FILE" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$TARGET_FILE")" && pwd)"
TARGET_FILE="$SCRIPT_DIR/$(basename "$TARGET_FILE")"

emit_dockerfile() {
cat << 'EOF_DOCKERFILE'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=/bin/bash
LABEL org.opencontainers.image.source="https://github.com/jjjakob502/ai.cmd"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gh \
    openssh-client \
    ripgrep \
    jq \
    less \
    socat \
    netcat-openbsd \
    unzip \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    sudo \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) awscli_arch=x86_64 ;; \
        arm64) awscli_arch=aarch64 ;; \
        *) echo "Unsupported architecture for AWS CLI: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awscli_arch}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

ARG AI_CLIS="claude codex agy grok pi"
LABEL io.ai-cmd.clis="$AI_CLIS"

ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest
ARG GROK_VERSION=latest
ARG PI_CODING_AGENT_VERSION=latest

RUN set -eu; set -f; set -- $AI_CLIS; \
    [ "$#" -gt 0 ] || { echo 'AI_CLIS must contain CLI names or "none".' >&2; exit 1; }; \
    packages=""; agy=false; pi=false; \
    for cli do \
        case "$cli" in \
            claude) packages="$packages @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" ;; \
            codex) packages="$packages @openai/codex@${CODEX_VERSION}" ;; \
            grok) packages="$packages @xai-official/grok@${GROK_VERSION}" ;; \
            pi) packages="$packages @earendil-works/pi-coding-agent@${PI_CODING_AGENT_VERSION}"; pi=true ;; \
            agy) agy=true ;; \
            none) [ "$#" -eq 1 ] || { echo 'Use none by itself.' >&2; exit 1; } ;; \
            *) echo "Unknown AI CLI: $cli" >&2; exit 1 ;; \
        esac; \
    done; \
    if [ -n "$packages" ]; then npm install -g $packages; fi; \
    if "$pi"; then ln -sf "$(command -v pi)" /usr/local/bin/pi-coding-agent; fi; \
    if "$agy"; then \
        curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/install-agy.sh; \
        bash /tmp/install-agy.sh --dir /usr/local/bin; \
        rm /tmp/install-agy.sh; \
    fi

ARG AI_SOURCE_REVISION=local
ARG AI_BUILD_ID=local
RUN mkdir -p /opt/ai \
    && printf '%s\n' \
        'import hashlib, json, os, pathlib, shutil, subprocess, sys' \
        'def output(*cmd): return subprocess.check_output(cmd, text=True).strip()' \
        'packages = json.loads(output("npm", "list", "--global", "--depth=0", "--json"))' \
        'versions = {name: package["version"] for name, package in packages.get("dependencies", {}).items()}' \
        'selected = os.environ["AI_CLIS"].split()' \
        'package_names = {"claude": "@anthropic-ai/claude-code", "codex": "@openai/codex", "grok": "@xai-official/grok", "pi": "@earendil-works/pi-coding-agent"}' \
        'cli_versions = {tool: {"package": package_names[tool], "version": versions[package_names[tool]]} for tool in selected if tool in package_names}' \
        'if "agy" in selected:' \
        '    binary = shutil.which("agy")' \
        '    cli_versions["agy"] = {"version": None, "binary_sha256": (hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest() if binary else None), "note": "The current-release installer does not supply pinned version metadata."}' \
        'data = {"schema_version": 1, "source_revision": os.environ["AI_SOURCE_REVISION"], "build_id": os.environ["AI_BUILD_ID"], "architecture": output("dpkg", "--print-architecture"), "selected_tools": [] if selected == ["none"] else selected, "cli_versions": cli_versions, "global_npm_packages": versions, "toolchain": {"node": output("node", "--version"), "npm": output("npm", "--version"), "python": sys.version.split()[0], "aws": output("aws", "--version")}}' \
        'pathlib.Path("/opt/ai/build-info.json").write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")' \
        | AI_CLIS="$AI_CLIS" AI_SOURCE_REVISION="$AI_SOURCE_REVISION" AI_BUILD_ID="$AI_BUILD_ID" python3

RUN apt-get update && apt-get install -y --no-install-recommends libarchive-tools \
    && rm -rf /var/lib/apt/lists/*

RUN git config --system --add safe.directory '*'

ARG AI_UID=10001
ARG AI_GID=10001
RUN if getent passwd "$AI_UID" >/dev/null; then \
        existing="$(getent passwd "$AI_UID" | cut -d: -f1)"; \
        [ "$existing" = ubuntu ] && userdel ubuntu; \
    fi \
    && if ! getent group "$AI_GID" >/dev/null; then groupadd -g "$AI_GID" ai; fi \
    && useradd -u "$AI_UID" -g "$AI_GID" -m -d /home/ai -s /bin/bash ai
RUN for entry in "claude:.claude" "codex:.codex" "agy:.gemini" "grok:.grok" "pi:.pi/agent" "ssh:.ssh" "gh:.config/gh" "aws:.aws"; do \
        tool="${entry%%:*}"; path="${entry#*:}"; \
        install -d -m 700 -o "$AI_UID" -g "$AI_GID" "/home/ai/$path" "/state/$tool"; \
    done \
    && chown -R "$AI_UID:$AI_GID" /home/ai
ENV HOME=/home/ai
ENV CLAUDE_CONFIG_DIR=/home/ai/.claude
LABEL io.ai-cmd.state-layout="selected-v1"
LABEL io.ai-cmd.uid="$AI_UID" io.ai-cmd.gid="$AI_GID" io.ai-cmd.home="/home/ai"
USER ai

WORKDIR /workspace

CMD ["/bin/bash"]
EOF_DOCKERFILE
}

case "${1:-}" in
    dockerfile|--dockerfile)
        emit_dockerfile
        exit 0
        ;;
    install|--install)
        target_dir="$HOME/.local/bin"
        mkdir -p "$target_dir"
        target_path="$target_dir/ai"
        chmod +x "$TARGET_FILE"
        ln -sf "$TARGET_FILE" "$target_path"
        echo "[ai install] Created symlink: $target_path -> $TARGET_FILE"
        case ":$PATH:" in
            *:"$target_dir":*)
                echo "[ai install] Success! 'ai' is ready in your PATH. Run 'ai <command>'."
                ;;
            *)
                echo "[ai install] Note: $target_dir is not currently in your PATH."
                echo "[ai install] Add it to your ~/.bashrc or ~/.zshrc:"
                echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
                ;;
        esac
        exit 0
        ;;
esac

if [ -n "${AI_ENGINE:-}" ]; then
    ENGINE="$AI_ENGINE"
elif command -v podman >/dev/null 2>&1; then
    ENGINE="podman"
elif command -v docker >/dev/null 2>&1; then
    ENGINE="docker"
else
    echo "Error: neither podman nor docker found in PATH." >&2
    exit 1
fi

ROOTLESS_PODMAN=false
STATE_ARGS=""
ARCHIVE_HOME=/state
PODMAN_ROOTLESS=$("$ENGINE" info --format '{{.Host.Security.Rootless}}' 2>/dev/null || true)
if [ "$PODMAN_ROOTLESS" = true ]; then
    ROOTLESS_PODMAN=true
    STATE_ARGS="--user 0"
    ARCHIVE_HOME=/data
fi
NATIVE_DOCKER=false
BUILD_UID=${AI_UID:-10001}
BUILD_GID=${AI_GID:-10001}
if [ "$ROOTLESS_PODMAN" = false ] && [ "$(uname -s)" = Linux ]; then
    case "$ENGINE" in
        docker|*/docker)
            case "$("$ENGINE" info --format '{{.OperatingSystem}}' 2>/dev/null)" in
                *'Docker Desktop'*) ;;
                *) NATIVE_DOCKER=true; BUILD_UID=${AI_UID:-$(id -u)}; BUILD_GID=${AI_GID:-$(id -g)} ;;
            esac
            ;;
    esac
fi

build_image() {
    case "$IMAGE" in *@*) echo '[ai build] A digest is immutable. Set AI_IMAGE to a tag before building.' >&2; return 1 ;; esac
    for build_id in "$BUILD_UID" "$BUILD_GID"; do
        case "$build_id" in ''|*[!0-9]*) echo '[ai build] UID/GID must be numeric.' >&2; return 1 ;; esac
    done
    validate_clis || return 1
    echo "[ai build] Building $IMAGE using $ENGINE..."
    emit_dockerfile | "$ENGINE" build "$@" --label io.ai-cmd.update=build \
        --build-arg "AI_CLIS=$AI_CLIS" --build-arg "AI_UID=$BUILD_UID" --build-arg "AI_GID=$BUILD_GID" \
        -t "$IMAGE" -f - "$SCRIPT_DIR"
}
validate_clis() {
    set -- $AI_CLIS
    [ $# -gt 0 ] || { echo '[ai build] AI_CLIS must contain CLI names or none.' >&2; return 1; }
    for cli do
        case "$cli" in
            claude|codex|agy|grok|pi) ;;
            none) [ $# -eq 1 ] || { echo '[ai build] Use none by itself.' >&2; return 1; } ;;
            *) echo "[ai build] Unknown AI CLI: $cli" >&2; return 1 ;;
        esac
    done
}
image_label() {
    "$ENGINE" image inspect --format "{{index .Config.Labels \"$1\"}}" "$IMAGE"
}
restore_build_settings() {
    [ "$AI_CLIS_SET" = x ] || AI_CLIS=$(image_label io.ai-cmd.clis)
    [ -n "${AI_UID:-}" ] || BUILD_UID=$(image_label io.ai-cmd.uid)
    [ -n "${AI_GID:-}" ] || BUILD_GID=$(image_label io.ai-cmd.gid)
}

case "${1:-}" in
    build|--build|update|--update) ;;
    *)
        if [ "$ROOTLESS_PODMAN" = false ]; then
            if [ "$PODMAN_ROOTLESS" = false ]; then
                echo '[ai] Use rootless Podman for writable project and state mounts.' >&2
                exit 1
            fi
            case "$("$ENGINE" info --format '{{json .SecurityOptions}}' 2>/dev/null)" in
                *rootless*) echo '[ai] Use rootless Podman for non-root bind mounts: AI_ENGINE=podman' >&2; exit 1 ;;
            esac
        fi
        ;;
esac

SELECTED_STATE=${AI_STATE-}
if [ "${AI_STATE+x}" != x ]; then
    command_name=${1:-}
    [ "$command_name" != -- ] || command_name=${2:-}
    command_name=${command_name##*/}
    case "$command_name" in
        claude|codex|agy|grok|pi|gh|aws) SELECTED_STATE=$command_name ;;
        ssh|ssh-keygen|scp|sftp) SELECTED_STATE=ssh ;;
        pi-coding-agent) SELECTED_STATE=pi ;;
    esac
fi
[ "$SELECTED_STATE" != none ] || SELECTED_STATE=""
case "$VOLUME" in
    ''|[!a-zA-Z0-9]*|*[!a-zA-Z0-9_.-]*) echo '[ai] Invalid volume prefix.' >&2; exit 1 ;;
esac
STATE_MOUNTS=""
ARCHIVE_MOUNTS=""
ARCHIVE_SOURCE_MOUNTS=""
STATE_NAMES=""
STATE_VOLUMES=""
for selected in $SELECTED_STATE; do
    case " $STATE_NAMES " in *" $selected "*) continue ;; esac
    state_path=""
    case "$selected" in
        claude) state_path=".claude" ;;
        codex)  state_path=".codex" ;;
        agy)    state_path=".gemini" ;;
        grok)   state_path=".grok" ;;
        pi)     state_path=".pi/agent" ;;
        ssh)    state_path=".ssh" ;;
        gh)     state_path=".config/gh" ;;
        aws)    state_path=".aws" ;;
        *) echo "[ai] Unknown state: $selected" >&2; exit 1 ;;
    esac
    STATE_NAMES="$STATE_NAMES $selected"
    STATE_VOLUMES="$STATE_VOLUMES $VOLUME-$selected"
    STATE_MOUNTS="$STATE_MOUNTS -v $VOLUME-$selected:/home/ai/$state_path"
    archive_options=""
    [ "$ROOTLESS_PODMAN" != true ] || archive_options=:nocopy
    ARCHIVE_MOUNTS="$ARCHIVE_MOUNTS -v $VOLUME-$selected:$ARCHIVE_HOME/$selected$archive_options"
    source_options=:ro
    [ "$ROOTLESS_PODMAN" != true ] || source_options=:ro,nocopy
    ARCHIVE_SOURCE_MOUNTS="$ARCHIVE_SOURCE_MOUNTS -v $VOLUME-$selected:$ARCHIVE_HOME/$selected$source_options"
done
check_state_image() {
    [ "$ENGINE" != echo ] || return 0
    layout=$("$ENGINE" image inspect --format '{{index .Config.Labels "io.ai-cmd.state-layout"}}' "$IMAGE")
    [ "$layout" = selected-v1 ] || { echo '[ai] Image needs selective-state support. Run ai build.' >&2; return 1; }
}
require_state() {
    check_state_image
    for state_volume in $STATE_VOLUMES; do
        "$ENGINE" volume inspect "$state_volume" >/dev/null 2>&1 || {
            echo "[ai] State volume does not exist: $state_volume" >&2; return 1;
        }
    done
}
case "${1:-}" in
    export|--export|import|--import|sync|--sync)
        [ -n "$STATE_NAMES" ] || { echo '[ai] Select state first, for example AI_STATE="claude gh".' >&2; exit 1; } ;;
esac

case "${1:-}" in
    sync|--sync)
        ACTION="${2:-}"
        TARGET="${3:-${AI_SYNC_TARGET:-}}"
        if [ -z "$ACTION" ] || { [ "$ACTION" != "push" ] && [ "$ACTION" != "pull" ]; }; then
            echo "Usage: ai sync [push|pull] <target_ssh_host>" >&2
            exit 1
        fi
        if [ -z "$TARGET" ]; then
            echo "Error: target SSH host required." >&2
            echo "Usage: ai sync [push|pull] <target_ssh_host>" >&2
            exit 1
        fi
        case "$IMAGE:$VOLUME" in
            *[!a-zA-Z0-9_./:@-]*) echo '[ai sync] Unsupported image or volume name.' >&2; exit 1 ;;
        esac
        case "$TARGET" in -*) echo '[ai sync] Invalid SSH target.' >&2; exit 1 ;; esac
        require_state
        REMOTE_ENGINE=$(ssh "$TARGET" 'if command -v podman >/dev/null 2>&1; then echo podman; elif command -v docker >/dev/null 2>&1; then echo docker; fi') || {
            echo '[ai sync] A reachable POSIX SSH host is required. Remote Windows is not supported.' >&2; exit 1;
        }
        case "$REMOTE_ENGINE" in
            podman|docker) ;;
            *) echo '[ai sync] Remote host needs Podman or Docker and a POSIX shell.' >&2; exit 1 ;;
        esac
        REMOTE_LAYOUT=$(ssh "$TARGET" "$REMOTE_ENGINE image inspect --format '{{index .Config.Labels \"io.ai-cmd.state-layout\"}}' '$IMAGE'")
        [ "$REMOTE_LAYOUT" = selected-v1 ] || { echo '[ai sync] Remote image needs selective-state support. Run ai build there.' >&2; exit 1; }
        REMOTE_ARGS=""
        REMOTE_ROOTLESS=$(ssh "$TARGET" "$REMOTE_ENGINE info --format '{{.Host.Security.Rootless}}' 2>/dev/null || true")
        case "$REMOTE_ROOTLESS" in
            true) REMOTE_ARGS="--user 0" ;;
            false) echo '[ai sync] Remote Podman must run rootless.' >&2; exit 1 ;;
            *)
                REMOTE_SECURITY=$(ssh "$TARGET" "$REMOTE_ENGINE info --format '{{json .SecurityOptions}}'")
                case "$REMOTE_SECURITY" in
                    *rootless*) echo '[ai sync] Remote rootless Docker is not supported; use Podman.' >&2; exit 1 ;;
                esac
                ;;
        esac
        REMOTE_HOME=/state
        [ "$REMOTE_ROOTLESS" != true ] || REMOTE_HOME=/data
        REMOTE_MOUNTS=""
        REMOTE_SOURCE_MOUNTS=""
        for selected in $STATE_NAMES; do
            ssh "$TARGET" "$REMOTE_ENGINE volume inspect '$VOLUME-$selected' >/dev/null" || {
                echo "[ai sync] Initialize remote state first: $selected" >&2; exit 1;
            }
            options=""
            source_options=:ro
            if [ "$REMOTE_ROOTLESS" = true ]; then options=:nocopy; source_options=:ro,nocopy; fi
            REMOTE_MOUNTS="$REMOTE_MOUNTS -v $VOLUME-$selected:$REMOTE_HOME/$selected$options"
            REMOTE_SOURCE_MOUNTS="$REMOTE_SOURCE_MOUNTS -v $VOLUME-$selected:$REMOTE_HOME/$selected$source_options"
        done
        umask 077
        SYNC_FILE=$(mktemp "${TMPDIR:-/tmp}/ai-sync.XXXXXXXX")
        trap 'rm -f "$SYNC_FILE"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        if [ "$ACTION" = push ]; then
            echo "[ai sync] Sending local volume to $TARGET..."
            "$ENGINE" run --rm $STATE_ARGS $ARCHIVE_SOURCE_MOUNTS "$IMAGE" tar czf - -C "$ARCHIVE_HOME" $STATE_NAMES >"$SYNC_FILE"
            ssh "$TARGET" "$REMOTE_ENGINE run --rm $REMOTE_ARGS $REMOTE_MOUNTS -i '$IMAGE' bsdtar xzf - --no-same-owner --keep-newer-files -C $REMOTE_HOME $STATE_NAMES" <"$SYNC_FILE"
        else
            echo "[ai sync] Receiving volume from $TARGET..."
            ssh "$TARGET" "$REMOTE_ENGINE run --rm $REMOTE_ARGS $REMOTE_SOURCE_MOUNTS '$IMAGE' tar czf - -C $REMOTE_HOME $STATE_NAMES" >"$SYNC_FILE"
            "$ENGINE" run --rm $STATE_ARGS $ARCHIVE_MOUNTS -i "$IMAGE" bsdtar xzf - --no-same-owner --keep-newer-files -C "$ARCHIVE_HOME" $STATE_NAMES <"$SYNC_FILE"
        fi
        echo "[ai sync] $ACTION complete."
        exit 0
        ;;

    export|--export)
        OUTFILE="${2:-ai-state.tar.gz}"
        echo "[ai export] Exporting selected state to $OUTFILE. Treat it like a password..."
        OUT_DIR="$(cd "$(dirname "$OUTFILE")" && pwd)"
        OUT_NAME="$(basename "$OUTFILE")"
        require_state
        umask 077
        EXPORT_TMP=$(mktemp "$OUT_DIR/.ai-export.XXXXXXXX")
        trap 'rm -f "$EXPORT_TMP"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        "$ENGINE" run --rm $STATE_ARGS $ARCHIVE_SOURCE_MOUNTS "$IMAGE" tar czf - -C "$ARCHIVE_HOME" $STATE_NAMES >"$EXPORT_TMP"
        mv -f "$EXPORT_TMP" "$OUT_DIR/$OUT_NAME"
        echo "[ai export] Created: $OUT_DIR/$OUT_NAME"
        exit 0
        ;;

    import|--import)
        INFILE="${2:-}"
        if [ -z "$INFILE" ] || [ ! -f "$INFILE" ] || [ $# -gt 3 ]; then
            echo "Usage: ai import <path-to-file.tar.gz> [--overwrite]" >&2
            exit 1
        fi
        case "${3:-}" in
            '') IMPORT_OPTIONS=--keep-newer-files ;;
            --overwrite) IMPORT_OPTIONS="" ;;
            *) echo 'Usage: ai import <path-to-file.tar.gz> [--overwrite]' >&2; exit 1 ;;
        esac
        FULL_PATH="$(cd "$(dirname "$INFILE")" && pwd)/$(basename "$INFILE")"
        FILE_NAME="$(basename "$FULL_PATH")"
        check_state_image
        echo "[ai import] Importing $FILE_NAME into selected state..."
        "$ENGINE" run --rm $STATE_ARGS $ARCHIVE_MOUNTS -i "$IMAGE" bsdtar xzf - --no-same-owner $IMPORT_OPTIONS -C "$ARCHIVE_HOME" $STATE_NAMES <"$FULL_PATH"
        echo "[ai import] Import complete."
        exit 0
        ;;


    build|--build)
        build_image
        echo "[ai build] Build complete."
        exit 0
        ;;

    update|--update)
        echo "[ai update] Updating $IMAGE using $ENGINE..."
        if [ "$ENGINE" = echo ]; then
            "$ENGINE" pull "$IMAGE"
            echo "[ai update] Update complete."
            exit 0
        fi
        UPDATE_POLICY=pull
        case "$IMAGE" in
            *@*) ;; # Digest references retain their exact identity.
            *)
                if "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
                    if [ "$(image_label io.ai-cmd.update)" = build ]; then
                        UPDATE_POLICY=build
                        restore_build_settings
                    elif [ "$("$ENGINE" image inspect --format '{{if .RepoDigests}}pulled{{else}}local{{end}}' "$IMAGE")" != pulled ]; then
                        echo '[ai update] Image has no update policy. Run ai build with your original AI_CLIS, or pull explicitly with your engine.' >&2
                        exit 1
                    fi
                fi
                if [ "$UPDATE_POLICY" = pull ] && [ "$NATIVE_DOCKER" = true ] && [ "$IMAGE" = "$DEFAULT_IMAGE" ]; then
                    UPDATE_POLICY=build
                fi
                ;;
        esac
        if [ "$UPDATE_POLICY" = build ]; then
            build_image --pull --no-cache
        else
            "$ENGINE" pull "$IMAGE"
        fi
        echo "[ai update] Update complete."
        exit 0
        ;;
esac

if [ "${1:-}" = "--" ]; then
    shift
fi

if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
    if [ "$NATIVE_DOCKER" = true ] && [ "$IMAGE" = "$DEFAULT_IMAGE" ]; then
        build_image
    else
        echo "[ai] Pulling $IMAGE..."
        if ! "$ENGINE" pull -q "$IMAGE" >/dev/null; then
            if [ "$IMAGE" != "$DEFAULT_IMAGE" ]; then
                echo "[ai] Could not pull the requested image: $IMAGE" >&2
                exit 1
            fi
            echo '[ai] Default image pull failed, building locally...'
            build_image
        fi
    fi
fi


check_state_image
if [ $# -eq 0 ]; then
    set -- /bin/bash
fi

PROJECT_DIR=$(pwd -P)
PROJECT_MODE=${AI_PROJECT_MODE:-rw}
case "$PROJECT_MODE" in rw|ro|none) ;; *) echo '[ai] AI_PROJECT_MODE must be rw, ro, or none.' >&2; exit 1 ;; esac
if [ "$PROJECT_MODE" != none ]; then
case "$PROJECT_DIR" in
    "$HOME"|/)
        if [ -z "${AI_ALLOW_HOME:-}" ]; then
            echo "[ai] Refusing to mount $(pwd): it would expose your keys and other secrets. Run from a project folder, or set AI_ALLOW_HOME=1." >&2
            exit 1
        fi
        ;;
esac
fi

USERNS_ARGS=""
if [ "$ROOTLESS_PODMAN" = true ]; then
    IMAGE_UID=$("$ENGINE" image inspect --format '{{index .Config.Labels "io.ai-cmd.uid"}}' "$IMAGE")
    IMAGE_GID=$("$ENGINE" image inspect --format '{{index .Config.Labels "io.ai-cmd.gid"}}' "$IMAGE")
    case "$IMAGE_UID:$IMAGE_GID" in
        *[!0-9:]*|:*|*:) echo '[ai] Image predates non-root support. Run ai update or ai build.' >&2; exit 1 ;;
    esac
    USERNS_ARGS="--userns=keep-id:uid=$IMAGE_UID,gid=$IMAGE_GID"
elif [ "$NATIVE_DOCKER" = true ]; then
    IMAGE_UID=$("$ENGINE" image inspect --format '{{index .Config.Labels "io.ai-cmd.uid"}}' "$IMAGE")
    IMAGE_GID=$("$ENGINE" image inspect --format '{{index .Config.Labels "io.ai-cmd.gid"}}' "$IMAGE")
    if [ "$IMAGE_UID:$IMAGE_GID" != "$(id -u):$(id -g)" ]; then
        echo '[ai] Build for this host UID/GID first: AI_ENGINE=docker ai build' >&2
        exit 1
    fi
else
    case "$ENGINE" in
        docker|*/docker)
            IMAGE_HOME=$("$ENGINE" image inspect --format '{{index .Config.Labels "io.ai-cmd.home"}}' "$IMAGE")
            if [ "$IMAGE_HOME" != /home/ai ]; then
                echo '[ai] Incompatible image. Run ai build.' >&2
                exit 1
            fi
            ;;
    esac
fi

TTY_ARG="-i"
if [ -t 0 ] && [ -t 1 ]; then
    TTY_ARG="-it"
fi

EXTRA_ENV=""
for var in ${AI_ENV:-}; do
    case "$var" in
        [0-9]*|*[!a-zA-Z0-9_]*) echo "[ai] Invalid environment variable name: $var" >&2; exit 1 ;;
    esac
    EXTRA_ENV="$EXTRA_ENV -e $var"
done

if [ "$PROJECT_MODE" = none ]; then
    PROJECT_DIR=/home/ai
    set -- "$IMAGE" "$@"
else
    set -- -v "$PROJECT_DIR:$PROJECT_DIR:$PROJECT_MODE" "$IMAGE" "$@"
fi

exec "$ENGINE" run --rm $TTY_ARG $USERNS_ARGS \
    --cap-drop=ALL --security-opt=no-new-privileges \
    --network "${AI_NETWORK:-bridge}" \
    $STATE_MOUNTS \
    -w "$PROJECT_DIR" \
    -e TERM="${TERM:-xterm-256color}" \
    $EXTRA_ENV \
    ${AI_ARGS:-} \
    "$@"
