#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

info "Setting up env-pool..."

# 1. Create template iOS simulator
TEMPLATE_NAME="env-pool-template"
existing_udid=$(sim_udid_by_name "$TEMPLATE_NAME")

if [ -n "$existing_udid" ]; then
    info "iOS template simulator already exists (UDID: $existing_udid)"
else
    info "Creating iOS template simulator ($TEMPLATE_NAME)..."
    udid=$(xcrun simctl create "$TEMPLATE_NAME" "$IOS_DEVICE_TYPE" "$IOS_RUNTIME")
    info "Created iOS template simulator (UDID: $udid)"
fi

# 2. Verify Android AVD exists
if [ -n "$ANDROID_AVD" ]; then
    avd_list=$("${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator" -list-avds 2>/dev/null)
    if echo "$avd_list" | grep -q "^${ANDROID_AVD}$"; then
        info "Android AVD '$ANDROID_AVD' found"
    else
        die "Android AVD '$ANDROID_AVD' not found. Available: $avd_list"
    fi
fi

# 3. Ensure directories exist
mkdir -p "$BUILDS_DIR" "$STATE_DIR" "$WORKTREE_PATH"
info "Directories ready: .builds/, .state/, $WORKTREE_DIR"

info "Setup complete."
