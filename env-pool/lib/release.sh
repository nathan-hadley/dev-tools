#!/bin/bash
# Intentionally no set -e — release must be defensive
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ENV_ID="${1:?Usage: env-pool release <env-id>}"
ENV_STATE_DIR="$STATE_DIR/$ENV_ID"

[ -d "$ENV_STATE_DIR" ] || die "No environment found: $ENV_ID"

info "Releasing environment $ENV_ID..."

# Load metadata (may fail if meta is missing, that's ok)
if [ -f "$ENV_STATE_DIR/meta" ]; then
    source "$ENV_STATE_DIR/meta"
fi

SIM_TARGET="${SIM_UDID:-$SIM_NAME}"

# 1. Kill Metro
if [ -n "$METRO_PID" ] && pid_alive "$METRO_PID"; then
    info "Stopping Metro (PID $METRO_PID)..."
    kill "$METRO_PID" 2>/dev/null || true
    # Wait briefly for clean shutdown
    sleep 1
    kill -9 "$METRO_PID" 2>/dev/null || true
fi

# 2. Shutdown simulator
if [ -n "$SIM_TARGET" ]; then
    info "Shutting down simulator ${SIM_NAME:-$SIM_UDID}..."
    xcrun simctl shutdown "$SIM_TARGET" 2>/dev/null || true
fi

# 3. Delete simulator
if [ -n "$SIM_TARGET" ]; then
    info "Deleting simulator ${SIM_NAME:-$SIM_UDID}..."
    xcrun simctl delete "$SIM_TARGET" 2>/dev/null || true
fi

# 4. Remove worktree
if [ -n "$WORKTREE" ] && [ -d "$WORKTREE" ]; then
    info "Removing worktree $WORKTREE..."
    git -C "$MOBILE_APP_PATH" worktree remove "$WORKTREE" --force 2>/dev/null || true
fi

# 5. Remove state
info "Removing state..."
rm -rf "$ENV_STATE_DIR"

info "Environment $ENV_ID released."
