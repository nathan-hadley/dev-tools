# maestro-runner Refactor Design

## Problem

Stock Maestro uses a hardcoded XCTest HTTP port (22087), so only one iOS Maestro run can happen at a time. Additionally, Maestro's `clearState` (uninstall + reinstall) wipes the Expo dev client's saved server URL from UserDefaults, causing the dev launcher to reappear showing all discoverable Metro servers. This breaks env-pool's multi-environment model where each env has its own Metro on a different port.

## Solution

Replace stock `maestro` with `maestro-runner` (devicelab-dev/maestro-runner) for test execution. maestro-runner uses dynamic port allocation per device via WDA, enabling true parallel iOS Maestro runs. Since each device gets its own driver instance, `clearState` no longer causes cross-env conflicts.

maestro-runner is a drop-in replacement — existing flow YAML and JS files work without modification.

**Important constraint:** maestro-runner is for dev-time test execution only. Stock `maestro` remains the tool for CI/production test runs (where `startRecording`, `takeScreenshot` work reliably). maestro-runner v1.0.9 has a known bug (#33) with `startRecording`/`takeScreenshot`.

## Changes

### `run-maestro.sh`

**`run_ios()` — simplify dramatically:**
- Use `maestro-runner --platform ios --device $SIM_UDID test -e METRO_PORT=$METRO_PORT <flow>`
- Remove: iOS Maestro lock (maestro-runner handles parallel execution)
- Remove: selective app data clearing (preserve Library/Preferences hack)
- Remove: `simctl openurl` deep link + `sleep 5`
- Remove: `--no-clear` flag and `CLEAR_STATE` variable/parsing

**`run_android()` — swap command, keep lock:**
- Use `maestro-runner --platform android --device $emulator_id test <flow>`
- Keep: Android lock (single shared emulator)

**`acquire_lock()` — keep** (still used by Android)

### `create.sh`

- Remove: keychain reset after simulator boot (`clearState` in flows handles state)

### `config.sh`

- Remove: `MAESTRO_LOCK_TIMEOUT` (iOS lock gone)
- Rename: `LOCK_RETRY_INTERVAL` back to `ANDROID_LOCK_RETRY_INTERVAL` (Android-only)

### No changes needed

- `build.sh` — shared builds still work (no per-env builds needed)
- `common.sh`, `gc.sh`, `release.sh`, `setup.sh`, `status.sh` — unchanged
- Flow YAML files — zero migration, `clearState` works normally
- JS page objects — no changes
