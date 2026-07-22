#!/bin/bash

set -euo pipefail

APP_PATH="${VSCODE_INSIDERS_APP:-/Applications/Visual Studio Code - Insiders.app}"
BUNDLE_ID="com.microsoft.VSCodeInsiders"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
QUIT_SCRIPT="$SCRIPT_DIR/quit_vscode_insiders.applescript"
VERSION_FILE="${VSCODE_POST_INSTALL_VERSION_FILE:-$HOME/.vscode_version}"
LOG_FILE="${VSCODE_POST_INSTALL_LOG_FILE:-$HOME/Library/Logs/vscode-post-install.log}"
LAUNCHD_LABEL="${VSCODE_POST_INSTALL_LAUNCHD_LABEL:-com.fprince333.vscode-post-install}"
LAUNCH_AGENT_FILE="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
LOCK_DIRECTORY="${VSCODE_POST_INSTALL_LOCK_DIRECTORY:-$HOME/Library/Caches/vscode-post-install.lock}"
SHUTDOWN_TIMEOUT_SECONDS="${SHUTDOWN_TIMEOUT_SECONDS:-60}"
RELAUNCH_TIMEOUT_SECONDS="${RELAUNCH_TIMEOUT_SECONDS:-30}"
CSS_START_MARKER="/* vscode-post-install:custom-css:start */"
CSS_END_MARKER="/* vscode-post-install:custom-css:end */"
FORCE_RUN=0
DETACH_RUN=0
WORKER_RUN=0
LOCK_ACQUIRED=0
VERSION_TEMP=""
LAUNCH_AGENT_TEMP=""

LOG_DIRECTORY="$(/usr/bin/dirname "$LOG_FILE")"
if ! /bin/mkdir -p "$LOG_DIRECTORY" || ! /usr/bin/touch "$LOG_FILE"; then
    printf 'vscode-post-install: ERROR: Could not create log file at %s.\n' "$LOG_FILE" >&2
    exit 1
fi

write_log_line() {
    printf '%s vscode-post-install: %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

log() {
    local message="$*"
    printf 'vscode-post-install: %s\n' "$message"
    write_log_line "$message"
}

fail() {
    local message="ERROR: $*"
    printf 'vscode-post-install: %s\n' "$message" >&2
    write_log_line "$message"
    exit 1
}

usage() {
    cat <<'EOF'
Usage: vscode-post-install.sh [--force | --detach]

Runs automatically only when the VS Code Insiders build changes. The VS Code
task uses --detach so launchd can finish the quit/relaunch workflow after VS
Code terminates its task shell. Use --force for a direct manual recovery.
EOF
}

cleanup() {
    if [ -n "$LAUNCH_AGENT_TEMP" ] && [ -e "$LAUNCH_AGENT_TEMP" ]; then
        /bin/rm -f "$LAUNCH_AGENT_TEMP"
    fi

    if [ -n "$VERSION_TEMP" ] && [ -e "$VERSION_TEMP" ]; then
        /bin/rm -f "$VERSION_TEMP"
    fi

    if [ "$LOCK_ACQUIRED" -eq 1 ]; then
        /bin/rm -f "$LOCK_DIRECTORY/pid"
        /bin/rmdir "$LOCK_DIRECTORY" 2>/dev/null || true
    fi
}

acquire_lock() {
    local lock_parent
    local existing_pid=""

    lock_parent="$(/usr/bin/dirname "$LOCK_DIRECTORY")"
    /bin/mkdir -p "$lock_parent" || fail "Could not create lock parent directory at $lock_parent."

    if /bin/mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
        LOCK_ACQUIRED=1
        printf '%s\n' "$$" > "$LOCK_DIRECTORY/pid" || fail "Could not write the worker lock PID."
        return
    fi

    if [ -f "$LOCK_DIRECTORY/pid" ]; then
        existing_pid="$(/bin/cat "$LOCK_DIRECTORY/pid" 2>/dev/null || true)"
    fi

    if [[ "$existing_pid" =~ ^[0-9]+$ ]] && /bin/kill -0 "$existing_pid" 2>/dev/null; then
        log "Another post-update worker is already running with PID $existing_pid."
        exit 0
    fi

    /bin/rm -f "$LOCK_DIRECTORY/pid"
    /bin/rmdir "$LOCK_DIRECTORY" 2>/dev/null || fail "Could not clear stale lock at $LOCK_DIRECTORY."
    /bin/mkdir "$LOCK_DIRECTORY" || fail "Could not acquire lock at $LOCK_DIRECTORY."
    LOCK_ACQUIRED=1
    printf '%s\n' "$$" > "$LOCK_DIRECTORY/pid" || fail "Could not write the worker lock PID."
}

plist_insert() {
    /usr/bin/plutil -insert "$@" "$LAUNCH_AGENT_TEMP" \
        || fail "Could not write the LaunchAgent property list."
}

create_launch_agent() {
    LAUNCH_AGENT_TEMP="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/vscode-post-install-launch-agent.XXXXXX")" \
        || fail "Could not create a temporary LaunchAgent property list."

    /usr/bin/plutil -create xml1 "$LAUNCH_AGENT_TEMP" \
        || fail "Could not initialize the LaunchAgent property list."
    plist_insert Label -string "$LAUNCHD_LABEL"
    plist_insert ProgramArguments -array
    plist_insert ProgramArguments.0 -string "$SCRIPT_PATH"
    plist_insert ProgramArguments.1 -string --worker
    plist_insert RunAtLoad -bool false
    plist_insert KeepAlive -bool false
    plist_insert ProcessType -string Background
    plist_insert StandardOutPath -string /dev/null
    plist_insert StandardErrorPath -string /dev/null
    plist_insert EnvironmentVariables -dictionary
    plist_insert EnvironmentVariables.HOME -string "$HOME"
    plist_insert EnvironmentVariables.VSCODE_INSIDERS_APP -string "$APP_PATH"
    plist_insert EnvironmentVariables.VSCODE_POST_INSTALL_VERSION_FILE -string "$VERSION_FILE"
    plist_insert EnvironmentVariables.VSCODE_POST_INSTALL_LOG_FILE -string "$LOG_FILE"
    plist_insert EnvironmentVariables.VSCODE_POST_INSTALL_LAUNCHD_LABEL -string "$LAUNCHD_LABEL"
    plist_insert EnvironmentVariables.VSCODE_POST_INSTALL_LOCK_DIRECTORY -string "$LOCK_DIRECTORY"
    plist_insert EnvironmentVariables.SHUTDOWN_TIMEOUT_SECONDS -string "$SHUTDOWN_TIMEOUT_SECONDS"
    plist_insert EnvironmentVariables.RELAUNCH_TIMEOUT_SECONDS -string "$RELAUNCH_TIMEOUT_SECONDS"

    if [ -n "${CODE_INSIDERS_BIN:-}" ]; then
        plist_insert EnvironmentVariables.CODE_INSIDERS_BIN -string "$CODE_INSIDERS_BIN"
    fi

    if [ -n "${CUSTOM_CSS_FILE:-}" ]; then
        plist_insert EnvironmentVariables.CUSTOM_CSS_FILE -string "$CUSTOM_CSS_FILE"
    fi
}

submit_detached_worker() {
    local launchd_target="gui/$UID/$LAUNCHD_LABEL"
    local job_info=""
    local launch_agent_changed=0

    log "Handing the post-update workflow to launchd before VS Code Insiders quits."

    if job_info="$(/bin/launchctl print "$launchd_target" 2>/dev/null)"; then
        if printf '%s\n' "$job_info" | /usr/bin/grep -q 'state = running'; then
            log "The detached post-update worker is already running. Follow $LOG_FILE for progress."
            return
        fi
    fi

    create_launch_agent
    if [ ! -f "$LAUNCH_AGENT_FILE" ] || ! /usr/bin/cmp -s "$LAUNCH_AGENT_TEMP" "$LAUNCH_AGENT_FILE"; then
        launch_agent_changed=1
    fi

    if [ "$launch_agent_changed" -eq 1 ]; then
        if [ -n "$job_info" ]; then
            /bin/launchctl bootout "$launchd_target" 2>/dev/null || true
            if /bin/launchctl print "$launchd_target" >/dev/null 2>&1; then
                fail "Could not unload stale LaunchAgent $LAUNCHD_LABEL."
            fi
            job_info=""
        fi

        /bin/mkdir -p "$(/usr/bin/dirname "$LAUNCH_AGENT_FILE")" \
            || fail "Could not create the LaunchAgents directory."
        /bin/mv "$LAUNCH_AGENT_TEMP" "$LAUNCH_AGENT_FILE" \
            || fail "Could not install LaunchAgent at $LAUNCH_AGENT_FILE."
        LAUNCH_AGENT_TEMP=""
    else
        /bin/rm -f "$LAUNCH_AGENT_TEMP"
        LAUNCH_AGENT_TEMP=""
    fi

    if ! /bin/launchctl print "$launchd_target" >/dev/null 2>&1; then
        if ! /bin/launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT_FILE" 2>/dev/null \
            && ! /bin/launchctl print "$launchd_target" >/dev/null 2>&1; then
            fail "Could not register LaunchAgent $LAUNCHD_LABEL."
        fi
    fi

    /bin/launchctl kickstart "$launchd_target" || fail "Could not start LaunchAgent $LAUNCHD_LABEL."
    log "Detached one-shot post-update worker started. Follow $LOG_FILE for progress."
}

is_app_running() {
    /usr/bin/pgrep -q -f "^${APP_PATH}/Contents/"
}

wait_for_app_state() {
    local expected_state="$1"
    local timeout_seconds="$2"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout_seconds" ]; do
        if [ "$expected_state" = "stopped" ] && ! is_app_running; then
            return 0
        fi

        if [ "$expected_state" = "running" ] && is_app_running; then
            return 0
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [ "$expected_state" = "stopped" ] && ! is_app_running; then
        return 0
    fi

    if [ "$expected_state" = "running" ] && is_app_running; then
        return 0
    fi

    return 1
}

resolve_custom_css() {
    if [ -n "${CUSTOM_CSS_FILE:-}" ]; then
        printf '%s\n' "$CUSTOM_CSS_FILE"
        return
    fi

    if [ -f "$HOME/source.css" ]; then
        printf '%s/source.css\n' "$HOME"
        return
    fi

    local extension_path
    extension_path="$("$CODE_BIN" --locate-extension robbowen.synthwave-vscode 2>/dev/null || true)"
    [ -n "$extension_path" ] || fail "No custom CSS was found. Create $HOME/source.css, install robbowen.synthwave-vscode, or set CUSTOM_CSS_FILE."
    printf '%s/src/css/editor_chrome.css\n' "$extension_path"
}

resolve_code_bin() {
    if [ -n "${CODE_INSIDERS_BIN:-}" ]; then
        printf '%s\n' "$CODE_INSIDERS_BIN"
        return
    fi

    if command -v code-insiders >/dev/null 2>&1; then
        command -v code-insiders
        return
    fi

    if [ -x "$APP_PATH/Contents/Resources/app/bin/code" ]; then
        printf '%s/Contents/Resources/app/bin/code\n' "$APP_PATH"
        return
    fi

    fail "code-insiders was not found on PATH and the application-bundle fallback is unavailable. Set CODE_INSIDERS_BIN."
}

apply_custom_css() {
    local workbench_css="$1"
    local custom_css="$2"
    local temporary_css
    local source_map_count

    [ -w "$workbench_css" ] || fail "CSS modification requires write access to $workbench_css. Refusing to request a password during the automatic workflow."

    source_map_count="$(/usr/bin/grep -c 'sourceMappingURL=.*workbench\.desktop\.main\.css\.map' "$workbench_css" || true)"
    [ "$source_map_count" -eq 1 ] || fail "CSS modification failed: expected one VS Code workbench source-map footer in $workbench_css, found $source_map_count."

    temporary_css="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/vscode-post-install.XXXXXX")" || fail "Could not create a temporary CSS file."
    trap 'rm -f "$temporary_css"' RETURN

    /usr/bin/awk '
        { print }
        /sourceMappingURL=.*workbench\.desktop\.main\.css\.map/ { exit }
    ' "$workbench_css" > "$temporary_css" || fail "CSS modification failed while reading the VS Code workbench stylesheet."

    {
        printf '\n%s\n' "$CSS_START_MARKER"
        /bin/cat "$custom_css"
        printf '\n%s\n' "$CSS_END_MARKER"
    } >> "$temporary_css" || fail "CSS modification failed while building the customized stylesheet."

    if /usr/bin/cmp -s "$temporary_css" "$workbench_css"; then
        log "Custom CSS is already current; no duplicate block was added."
    else
        /bin/cp "$temporary_css" "$workbench_css" || fail "CSS modification failed while replacing $workbench_css."
        log "Applied custom CSS to the VS Code Insiders workbench."
    fi

    local start_count
    local end_count
    start_count="$(/usr/bin/grep -F -c "$CSS_START_MARKER" "$workbench_css" || true)"
    end_count="$(/usr/bin/grep -F -c "$CSS_END_MARKER" "$workbench_css" || true)"
    [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ] || fail "CSS verification failed: expected exactly one marked custom CSS block."

    trap - RETURN
    /bin/rm -f "$temporary_css"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --force)
            FORCE_RUN=1
            ;;
        --detach)
            DETACH_RUN=1
            ;;
        --worker)
            WORKER_RUN=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "Unknown argument: $1"
            ;;
    esac
    shift
done

[ "$DETACH_RUN" -eq 0 ] || [ "$WORKER_RUN" -eq 0 ] || fail "--detach and --worker cannot be combined."
[ "$DETACH_RUN" -eq 0 ] || [ "$FORCE_RUN" -eq 0 ] || fail "Use --force directly; it cannot be combined with --detach."

if [ "$DETACH_RUN" -eq 1 ]; then
    trap cleanup EXIT
    submit_detached_worker
    exit 0
fi

trap cleanup EXIT
acquire_lock

[ -d "$APP_PATH" ] || fail "VS Code Insiders was not found at $APP_PATH."
[ -f "$QUIT_SCRIPT" ] || fail "Quit helper was not found at $QUIT_SCRIPT. Keep it beside this script."
CODE_BIN="$(resolve_code_bin)"

WORKBENCH_CSS="$APP_PATH/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.css"
[ -f "$WORKBENCH_CSS" ] || fail "Workbench CSS was not found at $WORKBENCH_CSS. The VS Code layout may have changed."

CUSTOM_CSS="$(resolve_custom_css)"
[ -f "$CUSTOM_CSS" ] || fail "Custom CSS was not found at $CUSTOM_CSS."

CURRENT_VERSION="$("$CODE_BIN" --version | /usr/bin/sed -n '2p')"
[ -n "$CURRENT_VERSION" ] || fail "Could not determine the current VS Code Insiders build."
STORED_VERSION=""
if [ -f "$VERSION_FILE" ]; then
    STORED_VERSION="$(/bin/cat "$VERSION_FILE")"
fi

if [ "$FORCE_RUN" -ne 1 ] && [ "$CURRENT_VERSION" = "$STORED_VERSION" ]; then
    log "VS Code Insiders build $CURRENT_VERSION is already customized."
    exit 0
fi

APP_WAS_RUNNING=0
if is_app_running; then
    APP_WAS_RUNNING=1
elif [ "$FORCE_RUN" -ne 1 ]; then
    log "VS Code Insiders is not running; leaving the build marker unchanged."
    exit 0
fi

log "Customizing VS Code Insiders build $CURRENT_VERSION."
apply_custom_css "$WORKBENCH_CSS" "$CUSTOM_CSS"

if [ "$APP_WAS_RUNNING" -eq 1 ]; then
    if ! /usr/bin/osascript "$QUIT_SCRIPT"; then
        fail "Shutdown failed: AppleScript could not ask $BUNDLE_ID to quit."
    fi

    if ! wait_for_app_state stopped "$SHUTDOWN_TIMEOUT_SECONDS"; then
        fail "Shutdown timed out after ${SHUTDOWN_TIMEOUT_SECONDS}s; VS Code Insiders is still running."
    fi
    log "VS Code Insiders terminated."
else
    log "VS Code Insiders is already stopped; continuing forced recovery."
fi

if ! /usr/bin/open -b "$BUNDLE_ID"; then
    fail "Relaunch failed: Launch Services could not open $BUNDLE_ID."
fi

if ! wait_for_app_state running "$RELAUNCH_TIMEOUT_SECONDS"; then
    fail "Relaunch timed out after ${RELAUNCH_TIMEOUT_SECONDS}s; VS Code Insiders did not start."
fi
log "VS Code Insiders reopened through Launch Services."

VERSION_TEMP="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/vscode-post-install-version.XXXXXX")" || fail "Could not create a temporary build marker."
printf '%s\n' "$CURRENT_VERSION" > "$VERSION_TEMP" || fail "Could not write the build marker."
/bin/mv "$VERSION_TEMP" "$VERSION_FILE" || fail "Could not update $VERSION_FILE."
VERSION_TEMP=""

log "Post-update customization completed successfully."
