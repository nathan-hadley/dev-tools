#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

BRANCH="${1:?Usage: env-pool create <branch>}"

# Generate env ID
ENV_ID=$(next_env_id)
ENV_STATE_DIR="$STATE_DIR/$ENV_ID"
WORKTREE="$WORKTREE_PATH/$ENV_ID"

info "Creating environment $ENV_ID (branch: $BRANCH)..."

# Track what we've created for cleanup on failure
CREATED_WORKTREE=""
CREATED_STATE=""

cleanup_on_failure() {
    info "Creation failed, cleaning up..."
    [ -n "$METRO_PID" ] && kill "$METRO_PID" 2>/dev/null || true
    [ -n "$CREATED_WORKTREE" ] && git -C "$MOBILE_APP_PATH" worktree remove "$CREATED_WORKTREE" --force 2>/dev/null || true
    [ -n "$CREATED_STATE" ] && rm -rf "$CREATED_STATE" || true
    die "Failed to create environment $ENV_ID"
}
trap cleanup_on_failure ERR

# 1. Create state directory
mkdir -p "$ENV_STATE_DIR"
CREATED_STATE="$ENV_STATE_DIR"

# 2. Create git worktree
info "Creating worktree..."
git -C "$MOBILE_APP_PATH" worktree add "$WORKTREE" "$BRANCH" >&2
CREATED_WORKTREE="$WORKTREE"

# 3. Install dependencies in worktree
info "Installing dependencies..."
(cd "$WORKTREE" && $INSTALL_CMD) >&2

# 4. Create self-symlink for monorepo entry path resolution
# The pre-built app requests ./mobileApp/node_modules/expo-router/entry
# because it was built from a monorepo root. This symlink makes that path
# resolve to ./node_modules/expo-router/entry in the worktree.
ln -sf . "$WORKTREE/mobileApp"

# 5. Find available port and start Metro
PORT=$(find_available_port) || die "No available port in range $METRO_BASE_PORT-$((METRO_BASE_PORT + PORT_SCAN_RANGE))"
info "Starting Metro on port $PORT..."
(cd "$WORKTREE" && npx expo start --port "$PORT") \
    > "$ENV_STATE_DIR/metro.log" 2>&1 &
METRO_PID=$!

# Give Metro a moment to start, then verify it's still alive
sleep 3
pid_alive "$METRO_PID" || die "Metro failed to start. Check $ENV_STATE_DIR/metro.log"

# 6. Write metadata
SIM_NAME=""
SIM_UDID=""
METRO_PORT="$PORT"
CREATED_AT="$(date +%s)"
save_env_meta "$ENV_ID"

# Clear the trap — we succeeded
trap - ERR

info "Environment $ENV_ID ready (worktree-first, port=$PORT)"
echo "$ENV_ID"
