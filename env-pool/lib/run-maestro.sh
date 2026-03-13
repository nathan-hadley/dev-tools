#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Parse arguments
ENV_ID=""
FLOW_PATH=""
PLATFORM="ios"

while [ $# -gt 0 ]; do
    case "$1" in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        *)
            if [ -z "$ENV_ID" ]; then
                ENV_ID="$1"
            elif [ -z "$FLOW_PATH" ]; then
                FLOW_PATH="$1"
            else
                die "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

[ -n "$ENV_ID" ] || die "Usage: env-pool run-maestro <env-id> <flow-path> [--platform android]"
[ -n "$FLOW_PATH" ] || die "Usage: env-pool run-maestro <env-id> <flow-path> [--platform android]"

# Load environment metadata
load_env_meta "$ENV_ID"

# Resolve flow path relative to the worktree
if [ ! -f "$FLOW_PATH" ] && [ -f "$WORKTREE/$FLOW_PATH" ]; then
    FLOW_PATH="$WORKTREE/$FLOW_PATH"
fi
[ -f "$FLOW_PATH" ] || die "Flow file not found: $FLOW_PATH"

# Strip unsupported commands from flow files for maestro-runner compatibility.
# - startRecording/stopRecording: not supported on iOS (GitHub issue #33)
# - clearState: kills WDA session, maestro-runner can't recover
# Uses Python for YAML-aware block removal (grep can't handle multi-line blocks).
# Creates a temp copy next to the original so relative paths still resolve.
strip_unsupported() {
    local src="$1"
    local dir tmp
    dir=$(dirname "$src")
    tmp=$(mktemp "$dir/.maestro-runner-XXXXXX.yaml")
    python3 -c "
import sys
lines = open(sys.argv[1]).read().split('\n')
result = []
skip_block = False
skip_indent = 0
for i, line in enumerate(lines):
    s = line.strip()
    if s.startswith('- startRecording') or s.startswith('- stopRecording'):
        continue
    if 'shouldClearState' in line and 'evalScript' in line:
        continue
    if s == '- runFlow:':
        has_clear = any('clearState' in lines[j] for j in range(i+1, min(i+10, len(lines)))
                        if lines[j].strip() and not (lines[j].strip().startswith('- ') and len(lines[j]) - len(lines[j].lstrip()) <= len(line) - len(line.lstrip())))
        if has_clear:
            skip_block = True
            skip_indent = len(line) - len(line.lstrip())
            continue
    if skip_block:
        ci = len(line) - len(line.lstrip()) if s else skip_indent + 1
        if ci > skip_indent or not s:
            continue
        skip_block = False
    result.append(line)
print('\n'.join(result))
" "$src" > "$tmp"
    echo "$tmp"
}

# acquire_lock <name> <lock-dir> <timeout>
# Blocks until mkdir succeeds or timeout is reached. Sets EXIT trap to release.
acquire_lock() {
    local name="$1" lock_dir="$2" timeout="$3"
    local waited=0

    while ! mkdir "$lock_dir" 2>/dev/null; do
        if [ "$waited" -ge "$timeout" ]; then
            die "Timed out waiting for $name lock after ${waited}s"
        fi
        info "$name busy, waiting... (${waited}s/${timeout}s)"
        sleep "$ANDROID_LOCK_RETRY_INTERVAL"
        waited=$((waited + ANDROID_LOCK_RETRY_INTERVAL))
    done

    trap "rmdir '$lock_dir' 2>/dev/null || true" EXIT
}

run_ios() {
    info "Running Maestro on iOS (env=$ENV_ID, sim=$SIM_UDID)..."

    local flow
    flow=$(strip_unsupported "$FLOW_PATH")
    trap "rm -f '$flow'" EXIT

    # maestro-runner uses dynamic WDA port allocation per device, enabling
    # parallel iOS Maestro runs (stock maestro conflicts on hardcoded port 22087).
    # --app-file omitted: app is already installed by 'env-pool create'.
    # Including it would reinstall every run, resetting the Expo dev launcher.
    ~/.maestro-runner/bin/maestro-runner \
        --platform ios --device "$SIM_UDID" \
        test -e METRO_PORT="$METRO_PORT" "$flow"
}

run_android() {
    acquire_lock "Android" "$STATE_DIR/android.lock" "$ANDROID_LOCK_TIMEOUT"

    # Boot emulator if not running
    local adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
    local emulator="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"

    if ! "$adb" devices 2>/dev/null | grep -q "emulator"; then
        info "Booting Android emulator ($ANDROID_AVD)..."
        "$emulator" -avd "$ANDROID_AVD" -no-window -no-audio -no-boot-anim &
        "$adb" wait-for-device
        # Wait for boot to complete
        "$adb" shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done'
        info "Android emulator booted."
    fi

    # Install APK
    local apk="$BUILDS_DIR/app-debug.apk"
    [ -f "$apk" ] || die "No Android build found. Run 'env-pool build android' first."
    info "Installing APK..."
    "$adb" install -r "$apk" >/dev/null

    # Point emulator at this env's Metro port
    "$adb" reverse tcp:8081 tcp:"$METRO_PORT"

    info "Running Maestro on Android (env=$ENV_ID)..."
    local emulator_id
    emulator_id=$("$adb" devices | grep "emulator" | head -1 | awk '{print $1}')
    ~/.maestro-runner/bin/maestro-runner --platform android --device "$emulator_id" \
        test "$FLOW_PATH"
}

case "$PLATFORM" in
    ios)     run_ios ;;
    android) run_android ;;
    *)       die "Unknown platform: $PLATFORM. Use: ios, android" ;;
esac
