# maestro-runner Refactor — Implementation Plan

Design: `plans/2026-03-12-maestro-runner-refactor-design.md`

## Task 1: Simplify `run-maestro.sh` — remove dead iOS code

**Files:** `env-pool/lib/run-maestro.sh`

1. Remove `CLEAR_STATE=true` variable declaration
2. Remove `--no-clear)` case from argument parser
3. In `run_ios()`: remove the entire `if [ "$CLEAR_STATE" = true ]` block (selective clearing, keychain reset, and the else branch)
4. Remove `simctl openurl` deep link + `sleep 5`
5. Remove the `acquire_lock` call from `run_ios()` (iOS lock no longer needed)
6. Replace `maestro --device "$SIM_UDID"` with `maestro-runner --platform ios --device "$SIM_UDID"`

**Verify:** `bash -n env-pool/lib/run-maestro.sh` (syntax check)

## Task 2: Update `run_android()` to use maestro-runner

**Files:** `env-pool/lib/run-maestro.sh`

1. Replace `maestro --device "$emulator_id"` with `maestro-runner --platform android --device "$emulator_id"`

**Verify:** `bash -n env-pool/lib/run-maestro.sh`

## Task 3: Clean up `config.sh`

**Files:** `env-pool/config.sh`

1. Remove `MAESTRO_LOCK_TIMEOUT=600`
2. Rename `LOCK_RETRY_INTERVAL` to `ANDROID_LOCK_RETRY_INTERVAL`
3. Update the comment block (remove iOS Maestro lock explanation)

**Verify:** `bash -n env-pool/config.sh`

## Task 4: Update lock references

**Files:** `env-pool/lib/run-maestro.sh`

1. In `acquire_lock()`: rename `$LOCK_RETRY_INTERVAL` to `$ANDROID_LOCK_RETRY_INTERVAL`
2. Since `acquire_lock` is now Android-only, consider inlining it back into `run_android()` or renaming. Recommendation: keep as `acquire_lock` for clarity but update the variable reference.

**Verify:** `bash -n env-pool/lib/run-maestro.sh`

## Task 5: Remove keychain reset from `create.sh`

**Files:** `env-pool/lib/create.sh`

1. Remove `xcrun simctl keychain "$SIM_UDID" reset 2>/dev/null || true` from step 4
2. Update the step 4 comment to just say "Boot simulator"

**Verify:** `bash -n env-pool/lib/create.sh`

## Task 6: Final review

1. Run `bash -n` on all modified files
2. Verify no remaining references to dead code (`grep` for `CLEAR_STATE`, `MAESTRO_LOCK_TIMEOUT`, `LOCK_RETRY_INTERVAL`, `simctl openurl`, `simctl keychain`)
