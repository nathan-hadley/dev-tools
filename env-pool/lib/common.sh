#!/bin/bash
# Shared helpers for env-pool scripts

# Resolve SCRIPT_DIR and ENV_POOL_DIR (use builtin cd to avoid zoxide/shell overrides)
SCRIPT_DIR="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_POOL_DIR="$(builtin cd "$SCRIPT_DIR/.." && pwd)"

# Source config
source "$ENV_POOL_DIR/config.sh"

# Resolve relative paths from ENV_POOL_DIR
MOBILE_APP_PATH="$(builtin cd "$ENV_POOL_DIR/$MOBILE_APP_REPO" && pwd)"
WORKTREE_PATH="$(builtin cd "$ENV_POOL_DIR" && mkdir -p "$WORKTREE_DIR" && builtin cd "$WORKTREE_DIR" && pwd)"
STATE_DIR="$ENV_POOL_DIR/.state"
BUILDS_DIR="$ENV_POOL_DIR/.builds"
IOS_APP_ARTIFACT="$BUILDS_DIR/Limble.app"
ANDROID_APK_ARTIFACT="$BUILDS_DIR/app-debug.apk"

# Ensure state and builds dirs exist
mkdir -p "$STATE_DIR" "$BUILDS_DIR"

# Print an error message to stderr and exit
die() {
    echo "env-pool: error: $*" >&2
    exit 1
}

# Print an info message to stderr (stdout is reserved for machine-readable output)
info() {
    echo "env-pool: $*" >&2
}

# Generate the next env ID by scanning .state/ for existing env-NNN dirs
next_env_id() {
    local max=0
    for dir in "$STATE_DIR"/env-*/; do
        [ -d "$dir" ] || continue
        local num="${dir%/}"
        num="${num##*env-}"
        if [ "$num" -gt "$max" ] 2>/dev/null; then
            max="$num"
        fi
    done
    printf "env-%03d" $((max + 1))
}

# Find an available port starting from METRO_BASE_PORT
find_available_port() {
    local port=$METRO_BASE_PORT
    local max_port=$((METRO_BASE_PORT + PORT_SCAN_RANGE))
    while [ "$port" -lt "$max_port" ]; do
        if ! lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    return 1
}

# Get simulator UDID by name using simctl JSON output
sim_udid_by_name() {
    local name="$1"
    xcrun simctl list devices --json | \
        jq -r --arg name "$name" \
        '.devices[][] | select(.name == $name) | .udid' | head -1
}

# Check if a simulator is booted
sim_is_booted() {
    local udid="$1"
    xcrun simctl list devices --json | \
        jq -r --arg udid "$udid" \
        '.devices[][] | select(.udid == $udid) | .state' | grep -q "Booted"
}

# Check if a PID is alive
pid_alive() {
    kill -0 "$1" 2>/dev/null
}

# Read an env's metadata file into shell variables
load_env_meta() {
    local env_id="$1"
    local meta_file="$STATE_DIR/$env_id/meta"
    [ -f "$meta_file" ] || die "no metadata for $env_id"
    source "$meta_file"
}

require_ios_build() {
    [ -d "$IOS_APP_ARTIFACT" ] || die "No iOS build found. Run 'env-pool build ios' first."
}

require_android_build() {
    [ -f "$ANDROID_APK_ARTIFACT" ] || die "No Android build found. Run 'env-pool build android' first."
}

default_sim_name() {
    local env_id="$1"
    echo "env-pool-$env_id"
}

save_env_meta() {
    local env_id="$1"
    local meta_file="$STATE_DIR/$env_id/meta"

    cat > "$meta_file" <<EOF
ENV_ID=$ENV_ID
BRANCH=$BRANCH
WORKTREE=$WORKTREE
SIM_NAME=${SIM_NAME:-}
SIM_UDID=${SIM_UDID:-}
METRO_PORT=$METRO_PORT
METRO_PID=$METRO_PID
CREATED_AT=$CREATED_AT
EOF
}

sim_has_app() {
    local udid="$1"
    xcrun simctl get_app_container "$udid" "$IOS_BUNDLE_ID" >/dev/null 2>&1
}

ensure_sim_booted() {
    local udid="$1"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
}

grant_ios_permissions() {
    local udid="$1"

    for svc in camera microphone photos contacts calendar reminders location; do
        xcrun simctl privacy "$udid" grant "$svc" "$IOS_BUNDLE_ID" 2>/dev/null || true
    done

    local tcc_db="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/TCC/TCC.db"
    sqlite3 "$tcc_db" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, flags, indirect_object_identifier, boot_uuid) VALUES ('kTCCServiceUserNotification', '$IOS_BUNDLE_ID', 0, 2, 4, 1, 0, 'UNUSED', 'UNUSED');" 2>/dev/null || true
}

ensure_env_simulator() {
    local env_id="$1"
    local desired_name existing_udid template_udid

    desired_name="${SIM_NAME:-$(default_sim_name "$env_id")}"
    existing_udid="${SIM_UDID:-}"

    if [ -z "$existing_udid" ]; then
        existing_udid="$(sim_udid_by_name "$desired_name")"
    fi

    if [ -z "$existing_udid" ]; then
        template_udid="$(sim_udid_by_name "env-pool-template")"
        [ -n "$template_udid" ] || die "template simulator missing. Run 'env-pool setup' first."
        info "Cloning simulator for $env_id..."
        xcrun simctl clone "env-pool-template" "$desired_name" >&2
        existing_udid="$(sim_udid_by_name "$desired_name")"
        [ -n "$existing_udid" ] || die "Could not find UDID for cloned simulator $desired_name"
    fi

    SIM_NAME="$desired_name"
    SIM_UDID="$existing_udid"
    save_env_meta "$env_id"
}

connect_ios_dev_client() {
    local udid="$1"
    local metro_url="$2"
    local encoded_url dev_client_url

    encoded_url="${metro_url//:/%3A}"
    encoded_url="${encoded_url//\//%2F}"
    dev_client_url="$IOS_DEV_CLIENT_SCHEME://expo-development-client/?url=$encoded_url"

    xcrun simctl openurl "$udid" "$dev_client_url" >/dev/null 2>&1 || \
        die "Failed to point simulator at $metro_url"
}

prepare_ios_preview() {
    local env_id="$1"
    local metro_url

    ensure_ios_app_ready "$env_id"

    metro_url="http://localhost:$METRO_PORT"
    info "Pointing simulator at Metro on port $METRO_PORT..."
    connect_ios_dev_client "$SIM_UDID" "$metro_url"
}

ensure_ios_app_ready() {
    local env_id="$1"

    require_ios_build
    ensure_env_simulator "$env_id"
    ensure_sim_booted "$SIM_UDID"

    if ! sim_has_app "$SIM_UDID"; then
        info "Installing iOS app..."
        xcrun simctl install "$SIM_UDID" "$IOS_APP_ARTIFACT" >&2
    fi

    info "Granting iOS permissions..."
    grant_ios_permissions "$SIM_UDID"
}

acquire_lock() {
    local name="$1"
    local lock_dir="$2"
    local timeout="$3"
    local retry_interval="$4"
    local waited=0
    local lock_info="$lock_dir/info"

    # Clean up stale locks left by dead processes
    if [ -d "$lock_dir" ] && [ -f "$lock_info" ]; then
        local lock_pid
        lock_pid=$(grep '^PID=' "$lock_info" 2>/dev/null | cut -d= -f2)
        if [ -n "$lock_pid" ] && ! pid_alive "$lock_pid"; then
            info "$name lock held by dead process (pid=$lock_pid), reclaiming..."
            rm -f "$lock_info" 2>/dev/null || true
            rmdir "$lock_dir" 2>/dev/null || true
        fi
    fi

    while ! mkdir "$lock_dir" 2>/dev/null; do
        if [ "$waited" -ge "$timeout" ]; then
            die "Timed out waiting for $name after ${waited}s"
        fi

        info "$name busy, waiting... (${waited}s/${timeout}s)"
        sleep "$retry_interval"
        waited=$((waited + retry_interval))
    done
}
