:<<"::CMDLITERAL"
@echo off
setlocal enabledelayedexpansion

set "IMAGE=ghcr.io/jjjakob502/ai.cmd:latest"
if not "%AI_IMAGE%"=="" set "IMAGE=%AI_IMAGE%"
set "VOLUME=ai-auth"
if not defined AI_CLIS set "AI_CLIS=claude codex agy grok pi"

if "%~1"=="sync" goto :sub_sync
if "%~1"=="--sync" goto :sub_sync
if "%~1"=="export" goto :sub_export
if "%~1"=="--export" goto :sub_export
if "%~1"=="import" goto :sub_import
if "%~1"=="--import" goto :sub_import
if "%~1"=="build" goto :sub_build
if "%~1"=="--build" goto :sub_build
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
where wsl.exe >nul 2>nul && (
    set "ENGINE_CMD=wsl.exe -d Ubuntu -u root -- podman"
    for /f "tokens=*" %%i in ('wsl.exe -d Ubuntu -u root wslpath -u "%cd%" 2^>nul') do set "WORKDIR_PATH=%%i"
    for /f "tokens=*" %%i in ('wsl.exe -d Ubuntu -u root wslpath -u "%~dp0" 2^>nul') do set "SCRIPTDIR_PATH=%%i"
    exit /b 0
)
echo Error: neither podman nor docker found in PATH. >&2
exit /b 1

:sub_build
call :detect_engine || exit /b 1
echo [ai build] Building %IMAGE%...
%ENGINE_CMD% build --build-arg "AI_CLIS=%AI_CLIS%" -t %IMAGE% "%SCRIPTDIR_PATH%"
exit /b %errorlevel%

:sub_export
call :detect_engine || exit /b 1
set "OUTFILE=%~2"
set "MODE=%~3"
if "%OUTFILE%"=="" set "OUTFILE=ai-session-backup.tar.gz"
if "%OUTFILE%"=="--clean" (
    set "OUTFILE=ai-sessions-clean.tar.gz"
    set "MODE=--clean"
)
set "EXCLUDE_ARGS=--exclude=.cache --exclude=.npm --exclude=._* --exclude=*.lock"
if "%MODE%"=="--clean" (
    echo [ai export] Exporting sessions without credentials to %OUTFILE%...
    set "EXCLUDE_ARGS=!EXCLUDE_ARGS! --exclude=*claude.json* --exclude=*auth*.json* --exclude=*backup* --exclude=.gemini/config --exclude=antigravity_state.pbtxt --exclude=*.key* --exclude=*credential* --exclude=*token* --exclude=hosts.yml --exclude=.netrc --exclude=.env*"
) else (
    echo [ai export] Exporting volume to %OUTFILE%...
)
%ENGINE_CMD% run --rm -v %VOLUME%:/data -v "%WORKDIR_PATH%:/out" %IMAGE% sh -c "tar czf /out/%OUTFILE% !EXCLUDE_ARGS! -C /data ."
echo [ai export] Created: %OUTFILE%
exit /b %errorlevel%

:sub_import
call :detect_engine || exit /b 1
set "INFILE=%~2"
if "%INFILE%"=="" (
    echo Usage: ai import ^<filename.tar.gz^> >&2
    exit /b 1
)
echo [ai import] Importing %INFILE% into volume...
%ENGINE_CMD% run --rm -v %VOLUME%:/data -v "%WORKDIR_PATH%:/in" %IMAGE% sh -c "tar xzf /in/%INFILE% -C /data"
echo [ai import] Import complete.
exit /b %errorlevel%

:sub_sync
call :detect_engine || exit /b 1
set "ACTION=%~2"
set "TARGET=%~3"
if "%ACTION%"=="" (
    echo Usage: ai sync [push^|pull] ^<target_ssh_host^> >&2
    exit /b 1
)
if "%TARGET%"=="" set "TARGET=%AI_SYNC_TARGET%"
if "%TARGET%"=="" (
    echo [ai sync] Target SSH host required. >&2
    echo Usage: ai sync [push^|pull] ^<target_ssh_host^> >&2
    exit /b 1
)
if /i "%ACTION%"=="push" (
    echo [ai sync] Streaming local volume to %TARGET%...
    %ENGINE_CMD% run --rm -v %VOLUME%:/data %IMAGE% tar czf - -C /data . | ssh %TARGET% "docker run --rm -i -v %VOLUME%:/data %IMAGE% tar xzf - -C /data 2>/dev/null || podman run --rm -i -v %VOLUME%:/data %IMAGE% tar xzf - -C /data 2>/dev/null"
    echo [ai sync] Push complete.
    exit /b 0
)
if /i "%ACTION%"=="pull" (
    echo [ai sync] Pulling volume from %TARGET%...
    ssh %TARGET% "docker run --rm -v %VOLUME%:/data %IMAGE% tar czf - -C /data . 2>/dev/null || podman run --rm -v %VOLUME%:/data %IMAGE% tar czf - -C /data . 2>/dev/null" | %ENGINE_CMD% run --rm -i -v %VOLUME%:/data %IMAGE% tar xzf - -C /data
    echo [ai sync] Pull complete.
    exit /b 0
)
echo Unknown sync action: %ACTION%. Use push or pull. >&2
exit /b 1

:sub_run
call :detect_engine || exit /b 1
%ENGINE_CMD% image inspect %IMAGE% >nul 2>nul || (
    echo [ai] Pulling %IMAGE%...
    %ENGINE_CMD% pull %IMAGE% >nul 2>nul || (
        echo [ai] Pull failed or offline, building locally...
        %ENGINE_CMD% build --build-arg "AI_CLIS=%AI_CLIS%" -t %IMAGE% "%SCRIPTDIR_PATH%"
    )
)
%ENGINE_CMD% volume inspect %VOLUME% >nul 2>nul || %ENGINE_CMD% volume create %VOLUME% >nul

set "ARGS=%*"
if "%~1"=="--" (
    for /f "tokens=1* delims= " %%a in ("%*") do set "ARGS=%%b"
)
if "!ARGS!"=="" set "ARGS=/bin/bash"

%ENGINE_CMD% run --rm -it --network host -v "%WORKDIR_PATH%:/workspace" -v %VOLUME%:/root -w /workspace -e TERM -e ANTHROPIC_API_KEY -e OPENAI_API_KEY -e GEMINI_API_KEY -e GROK_API_KEY -e XAI_API_KEY -e GITHUB_TOKEN -e GH_TOKEN %IMAGE% !ARGS!
exit /b %errorlevel%
::CMDLITERAL

set -eu

IMAGE="${AI_IMAGE:-ghcr.io/jjjakob502/ai.cmd:latest}"
VOLUME="ai-auth"
AI_CLIS="${AI_CLIS-claude codex agy grok pi}"

TARGET_FILE="$0"
while [ -h "$TARGET_FILE" ]; do
    TARGET_DIR="$(cd -P "$(dirname "$TARGET_FILE")" && pwd)"
    TARGET_FILE="$(readlink "$TARGET_FILE")"
    case "$TARGET_FILE" in /*) ;; *) TARGET_FILE="$TARGET_DIR/$TARGET_FILE" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$TARGET_FILE")" && pwd)"

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
        REMOTE_OS=$(ssh "$TARGET" 'uname 2>/dev/null || echo Windows' 2>/dev/null | tr -d '\r\n')
        if [ "$REMOTE_OS" = "Windows" ]; then
            REMOTE_RECEIVE="docker run --rm -i -v ai-auth:/data $IMAGE tar xzf - -C /data 2>nul || podman run --rm -i -v ai-auth:/data $IMAGE tar xzf - -C /data 2>nul || wsl.exe -d Ubuntu -u root -- podman run --rm -i -v ai-auth:/data $IMAGE tar xzf - -C /data"
            REMOTE_STREAM="docker run --rm -v ai-auth:/data $IMAGE tar czf - -C /data . 2>nul || podman run --rm -v ai-auth:/data $IMAGE tar czf - -C /data . 2>nul || wsl.exe -d Ubuntu -u root -- podman run --rm -v ai-auth:/data $IMAGE tar czf - -C /data ."
        else
            REMOTE_RECEIVE="docker run --rm -i -v ai-auth:/data $IMAGE tar xzf - -C /data 2>/dev/null || podman run --rm -i -v ai-auth:/data $IMAGE tar xzf - -C /data"
            REMOTE_STREAM="docker run --rm -v ai-auth:/data $IMAGE tar czf - -C /data . 2>/dev/null || podman run --rm -v ai-auth:/data $IMAGE tar czf - -C /data ."
        fi

        if [ "$ACTION" = "push" ]; then
            echo "[ai sync] Streaming local volume to $TARGET ($REMOTE_OS)..."
            # shellcheck disable=SC2029
            "$ENGINE" run --rm -v "$VOLUME:/data" "$IMAGE" tar czf - -C /data . | ssh "$TARGET" "$REMOTE_RECEIVE"
            echo "[ai sync] Push complete."
        elif [ "$ACTION" = "pull" ]; then
            echo "[ai sync] Pulling volume from $TARGET ($REMOTE_OS)..."
            # shellcheck disable=SC2029
            ssh "$TARGET" "$REMOTE_STREAM" | "$ENGINE" run --rm -i -v "$VOLUME:/data" "$IMAGE" tar xzf - -C /data
            echo "[ai sync] Pull complete."
        fi
        exit 0
        ;;

    export|--export)
        ARG2="${2:-}"
        ARG3="${3:-}"
        OUTFILE="ai-session-backup.tar.gz"
        MODE=""
        if [ "$ARG2" = "--clean" ]; then
            OUTFILE="ai-sessions-clean.tar.gz"
            MODE="--clean"
        elif [ -n "$ARG2" ]; then
            OUTFILE="$ARG2"
            if [ "$ARG3" = "--clean" ]; then
                MODE="--clean"
            fi
        fi

        EXCLUDE_ARGS="--exclude=.cache --exclude=.npm --exclude=._* --exclude=*.lock"
        if [ "$MODE" = "--clean" ]; then
            echo "[ai export] Exporting sessions without credentials to $OUTFILE..."
            EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude=*claude.json* --exclude=*auth*.json* --exclude=*backup* --exclude=.gemini/config --exclude=antigravity_state.pbtxt --exclude=*.key* --exclude=*credential* --exclude=*token* --exclude=hosts.yml --exclude=.netrc --exclude=.env*"
        else
            echo "[ai export] Exporting volume to $OUTFILE..."
        fi

        "$ENGINE" run --rm -v "$VOLUME:/data" -v "$(pwd):/out" "$IMAGE" sh -c "tar czf \"/out/$OUTFILE\" $EXCLUDE_ARGS -C /data ."
        echo "[ai export] Created: $(pwd)/$OUTFILE"
        exit 0
        ;;

    import|--import)
        INFILE="${2:-}"
        if [ -z "$INFILE" ] || [ ! -f "$INFILE" ]; then
            echo "Usage: ai import <path-to-file.tar.gz>" >&2
            exit 1
        fi
        FULL_PATH="$(cd "$(dirname "$INFILE")" && pwd)/$(basename "$INFILE")"
        DIR_PATH="$(dirname "$FULL_PATH")"
        FILE_NAME="$(basename "$FULL_PATH")"
        echo "[ai import] Importing $FILE_NAME into volume..."
        "$ENGINE" run --rm -v "$VOLUME:/data" -v "$DIR_PATH:/in" "$IMAGE" tar xzf "/in/$FILE_NAME" -C /data
        echo "[ai import] Import complete."
        exit 0
        ;;

    build|--build)
        echo "[ai build] Building $IMAGE using $ENGINE..."
        "$ENGINE" build --build-arg "AI_CLIS=$AI_CLIS" -t "$IMAGE" "$SCRIPT_DIR"
        echo "[ai build] Build complete."
        exit 0
        ;;
esac

if [ "${1:-}" = "--" ]; then
    shift
fi

if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[ai] Pulling $IMAGE..."
    if ! "$ENGINE" pull "$IMAGE" 2>/dev/null; then
        echo "[ai] Pull failed or offline, building locally..."
        "$ENGINE" build --build-arg "AI_CLIS=$AI_CLIS" -t "$IMAGE" "$SCRIPT_DIR"
    fi
fi

"$ENGINE" volume inspect "$VOLUME" >/dev/null 2>&1 || "$ENGINE" volume create "$VOLUME" >/dev/null

if [ $# -eq 0 ]; then
    set -- /bin/bash
fi

TTY_ARG="-i"
if [ -t 0 ] && [ -t 1 ]; then
    TTY_ARG="-it"
fi

exec "$ENGINE" run --rm $TTY_ARG \
    --network host \
    -v "$(pwd):/workspace" \
    -v "$VOLUME:/root" \
    -w /workspace \
    -e TERM="${TERM:-xterm-256color}" \
    -e ANTHROPIC_API_KEY \
    -e OPENAI_API_KEY \
    -e GEMINI_API_KEY \
    -e GROK_API_KEY \
    -e XAI_API_KEY \
    -e GITHUB_TOKEN \
    -e GH_TOKEN \
    "$IMAGE" \
    "$@"
