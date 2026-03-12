#!/bin/bash
# env-pool configuration — edit these values for your setup

# Paths (relative to env-pool/ directory)
MOBILE_APP_REPO="../../mobileApp"
WORKTREE_DIR="../../env-pool-worktrees"

# iOS
IOS_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16e"
IOS_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-18-4"
IOS_BUNDLE_ID="com.limblecmms.mobileApp"

# Android
ANDROID_AVD="Small_Phone"
ANDROID_BUNDLE_ID="com.limblecmms.mobileApp"

# Dependencies — command run in worktree before starting Metro
# Use hoisted node-linker to avoid pnpm symlink issues with Metro
INSTALL_CMD="pnpm install --frozen-lockfile --config.node-linker=hoisted"

# Metro
METRO_BASE_PORT=8082
PORT_SCAN_RANGE=50

# Garbage collection
ENV_TTL_SECONDS=7200

# Android lock
ANDROID_LOCK_RETRY_INTERVAL=5
ANDROID_LOCK_TIMEOUT=300

# Build staleness warning (seconds)
BUILD_WARN_AGE=604800  # 1 week
