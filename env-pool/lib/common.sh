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
