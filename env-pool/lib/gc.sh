#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

info "Running garbage collection..."

now=$(date +%s)
cleaned=0

for env_dir in "$STATE_DIR"/env-*/; do
    [ -d "$env_dir" ] || continue

    env_id=$(basename "$env_dir")
    meta_file="$env_dir/meta"

    if [ ! -f "$meta_file" ]; then
        info "$env_id: no metadata, releasing..."
        "$ENV_POOL_DIR/env-pool" release "$env_id"
        cleaned=$((cleaned + 1))
        continue
    fi

    source "$meta_file"

    # Check if Metro PID is dead
    if [ -n "$METRO_PID" ] && ! pid_alive "$METRO_PID"; then
        info "$env_id: Metro process dead (PID $METRO_PID), releasing..."
        "$ENV_POOL_DIR/env-pool" release "$env_id"
        cleaned=$((cleaned + 1))
        continue
    fi

    # Check TTL
    if [ -n "$CREATED_AT" ]; then
        age=$((now - CREATED_AT))
        if [ "$age" -gt "$ENV_TTL_SECONDS" ]; then
            info "$env_id: expired (age: $((age / 60))m, TTL: $((ENV_TTL_SECONDS / 60))m), releasing..."
            "$ENV_POOL_DIR/env-pool" release "$env_id"
            cleaned=$((cleaned + 1))
            continue
        fi
    fi
done

if [ "$cleaned" -eq 0 ]; then
    info "Nothing to clean up."
else
    info "Cleaned up $cleaned environment(s)."
fi
