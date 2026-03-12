#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Check for stale builds first
for artifact in "$BUILDS_DIR"/Limble.app "$BUILDS_DIR"/app-debug.apk; do
    if [ -e "$artifact" ]; then
        age=$(( $(date +%s) - $(stat -f %m "$artifact") ))
        if [ "$age" -gt "$BUILD_WARN_AGE" ]; then
            info "warning: $(basename "$artifact") is $(( age / 86400 )) days old"
        fi
    fi
done

PLATFORM="${1:-all}"

build_ios() {
    info "Building iOS app..."
    (cd "$MOBILE_APP_PATH" && npx expo run:ios --no-install --configuration Debug)

    # Find the built .app in DerivedData
    local app_path
    app_path=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug-iphonesimulator/Limble.app" -type d 2>/dev/null | head -1)
    [ -n "$app_path" ] || die "Could not find built .app in DerivedData"

    # Copy to .builds/
    rm -rf "$BUILDS_DIR/Limble.app"
    cp -R "$app_path" "$BUILDS_DIR/Limble.app"
    info "iOS artifact: $BUILDS_DIR/Limble.app"
}

build_android() {
    info "Building Android app..."
    (cd "$MOBILE_APP_PATH" && npx expo run:android --variant debug --no-install)

    # Copy APK to .builds/
    local apk_path="$MOBILE_APP_PATH/android/app/build/outputs/apk/debug/app-debug.apk"
    [ -f "$apk_path" ] || die "Could not find built .apk at $apk_path"

    cp "$apk_path" "$BUILDS_DIR/app-debug.apk"
    info "Android artifact: $BUILDS_DIR/app-debug.apk"
}

case "$PLATFORM" in
    ios)     build_ios ;;
    android) build_android ;;
    all)     build_ios; build_android ;;
    *)       die "Unknown platform: $PLATFORM. Use: ios, android, all" ;;
esac

info "Build complete."
