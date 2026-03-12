#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

has_envs=false

for env_dir in "$STATE_DIR"/env-*/; do
    [ -d "$env_dir" ] || continue
    has_envs=true

    env_id=$(basename "$env_dir")
    meta_file="$env_dir/meta"

    if [ ! -f "$meta_file" ]; then
        echo "$env_id  status=NO_METADATA"
        continue
    fi

    source "$meta_file"

    # Check Metro
    if [ -n "$METRO_PID" ] && pid_alive "$METRO_PID"; then
        metro_status="RUNNING"
    else
        metro_status="DEAD"
    fi

    # Check simulator
    if [ -n "$SIM_UDID" ] && sim_is_booted "$SIM_UDID"; then
        sim_status="BOOTED"
    else
        sim_status="DOWN"
    fi

    # Calculate uptime
    if [ -n "$CREATED_AT" ]; then
        age=$(( $(date +%s) - CREATED_AT ))
        if [ "$age" -ge 3600 ]; then
            uptime="$((age / 3600))h$((age % 3600 / 60))m"
        else
            uptime="$((age / 60))m"
        fi
    else
        uptime="unknown"
    fi

    echo "$env_id  branch=$BRANCH  port=$METRO_PORT  sim=$sim_status  metro=$metro_status  uptime=$uptime"
done

# Android status
if [ -n "$ANDROID_AVD" ]; then
    android_running=$("${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb" devices 2>/dev/null | grep -c "emulator" || true)
    if [ "$android_running" -gt 0 ]; then
        android_status="RUNNING"
    else
        android_status="OFF"
    fi

    if [ -d "$STATE_DIR/android.lock" ]; then
        lock_status="LOCKED"
    else
        lock_status="FREE"
    fi

    echo "android  emulator=$ANDROID_AVD  status=$android_status  lock=$lock_status"
fi

if [ "$has_envs" = false ]; then
    info "No active environments."
fi
