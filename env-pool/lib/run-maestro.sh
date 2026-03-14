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

    maestro --device "$SIM_UDID" test -e METRO_PORT="$METRO_PORT" "$FLOW_PATH"
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
    maestro --device "$emulator_id" test "$FLOW_PATH"
}

case "$PLATFORM" in
    ios)     run_ios ;;
    android) run_android ;;
    *)       die "Unknown platform: $PLATFORM. Use: ios, android" ;;
esac
