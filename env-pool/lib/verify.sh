#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

COMMAND_NAME="verify"

# Parse arguments
ENV_ID=""
FLOW_PATH=""
PLATFORM="ios"
VERIFY_LOCK_DIR="$STATE_DIR/verify.lock"
VERIFY_LOCK_INFO="$VERIFY_LOCK_DIR/info"

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

[ -n "$ENV_ID" ] || die "Usage: env-pool $COMMAND_NAME <env-id> <flow-path> [--platform android]"
[ -n "$FLOW_PATH" ] || die "Usage: env-pool $COMMAND_NAME <env-id> <flow-path> [--platform android]"

load_env_meta "$ENV_ID"

if [ ! -f "$FLOW_PATH" ] && [ -f "$WORKTREE/$FLOW_PATH" ]; then
    FLOW_PATH="$WORKTREE/$FLOW_PATH"
fi
[ -f "$FLOW_PATH" ] || die "Flow file not found: $FLOW_PATH"

cleanup() {
    rm -f "$VERIFY_LOCK_INFO" 2>/dev/null || true
    rmdir "$VERIFY_LOCK_DIR" 2>/dev/null || true
}

write_lock_info() {
    cat > "$VERIFY_LOCK_INFO" <<EOF
PID=$$
ENV_ID=$ENV_ID
PLATFORM=$PLATFORM
FLOW_PATH=$FLOW_PATH
STARTED_AT=$(date +%s)
EOF
}

run_ios() {
    ensure_ios_app_ready "$ENV_ID"

    info "Running Maestro on iOS (env=$ENV_ID, sim=$SIM_UDID)..."
    maestro test --device "$SIM_UDID" -e METRO_PORT="$METRO_PORT" "$FLOW_PATH"
}

run_android() {
    local adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
    local emulator="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"

    if ! "$adb" devices 2>/dev/null | grep -q "emulator"; then
        info "Booting Android emulator ($ANDROID_AVD)..."
        "$emulator" -avd "$ANDROID_AVD" -no-window -no-audio -no-boot-anim &
        "$adb" wait-for-device
        "$adb" shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done'
        info "Android emulator booted."
    fi

    require_android_build
    info "Installing APK..."
    "$adb" install -r "$ANDROID_APK_ARTIFACT" >/dev/null

    "$adb" reverse tcp:8081 tcp:"$METRO_PORT"

    info "Running Maestro on Android (env=$ENV_ID)..."
    local emulator_id
    emulator_id=$("$adb" devices | grep "emulator" | head -1 | awk '{print $1}')
    maestro test --device "$emulator_id" -e METRO_PORT="$METRO_PORT" "$FLOW_PATH"
}

acquire_lock "Verification lane" "$VERIFY_LOCK_DIR" "$VERIFY_LOCK_TIMEOUT" "$VERIFY_LOCK_RETRY_INTERVAL"
write_lock_info
trap cleanup EXIT

case "$PLATFORM" in
    ios)     run_ios ;;
    android) run_android ;;
    *)       die "Unknown platform: $PLATFORM. Use: ios, android" ;;
esac
