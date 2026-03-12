# iOS Simulator Environment Pool — Implementation Plan

## Goal

Build a small shell script toolkit that manages a pool of isolated iOS development
environments. Each environment consists of a git worktree, a dedicated simulator,
and a running Metro dev server. Environments can be claimed, prepared, inspected,
and released. The toolkit is test-runner agnostic — it only produces environments,
it does not run tests.

---

## Repository Layout

Create the following structure at the root of the project:

```
env-pool/
  config.sh        # User-editable config (pool size, device type, bundle ID, etc.)
  setup.sh         # One-time setup: creates simulators, lock dir
  claim.sh         # Atomically claims an available slot, prints slot number
  prepare.sh       # Prepares a claimed slot (worktree, install, build, metro)
  info.sh          # Prints environment variables describing a ready slot
  release.sh       # Tears down a slot (kills metro, shuts down sim, removes worktree)
  status.sh        # Prints current state of all slots (for debugging)
```

All scripts should be executable (`chmod +x`) and safe to run from any working
directory. They should use the directory of the script itself to locate `config.sh`.

---

## config.sh

This is the only file a user ever needs to edit. It should export:

```bash
POOL_SIZE=3                          # Number of concurrent environments
BASE_DEVICE="iPhone 15 Pro"          # Simulator device type
IOS_VERSION="iOS 17.5"               # iOS runtime
APP_BUNDLE_ID="com.example.app"      # App bundle identifier
METRO_BASE_PORT=8081                 # Slot 0 gets this port, slot 1 gets +1, etc.
LOCK_DIR="/tmp/env-pool-locks"       # Where slot lock files live
WORKTREE_BASE="../env-pool-worktrees" # Parent dir for worktrees (relative to repo root)
```

---

## setup.sh

**Purpose:** One-time initialization. Safe to re-run (idempotent).

Steps:
1. Source `config.sh`
2. Create `LOCK_DIR` if it doesn't exist
3. Create `WORKTREE_BASE` directory if it doesn't exist
4. For each slot 0..POOL_SIZE-1:
   - Check if a simulator named `env-pool-$SLOT` already exists via `xcrun simctl list devices`
   - If not, create it: `xcrun simctl create "env-pool-$SLOT" "$BASE_DEVICE" "$IOS_VERSION"`
   - If yes, print that it already exists and skip
5. Print a summary of created simulators

---

## claim.sh

**Purpose:** Atomically acquire an available slot. Prints the slot number to stdout.
Exits non-zero if no slots are available.

Steps:
1. Source `config.sh`
2. Iterate slots 0..POOL_SIZE-1
3. For each slot, attempt `mkdir "$LOCK_DIR/slot-$i.lock"` — this is atomic on
   POSIX systems
4. On success, print the slot number and exit 0
5. If no slot is available after iterating all, print an error to stderr and exit 1

The lock directory (`slot-$i.lock`) represents a claimed slot. It persists until
`release.sh` removes it.

---

## prepare.sh

**Purpose:** Fully prepare a claimed slot for use. Takes slot number and branch name
as arguments.

Usage: `./prepare.sh <slot> <branch>`

Steps:
1. Source `config.sh`
2. Validate that the slot lock exists (fail if not — slot must be claimed first)
3. Derive variables:
   - `WORKTREE="$WORKTREE_BASE/env-pool-$SLOT"`
   - `PORT=$(( METRO_BASE_PORT + SLOT ))`
   - `SIM_NAME="env-pool-$SLOT"`
4. Create git worktree: `git worktree add "$WORKTREE" -b "env-pool-$SLOT-work" origin/$BRANCH`
   - If the worktree already exists, remove and recreate it
5. Run `npm install` inside the worktree
6. Run `npx expo prebuild` inside the worktree (if applicable — make this optional
   via a config flag `USE_EXPO_PREBUILD=true`)
7. Boot the simulator: `xcrun simctl boot "$SIM_NAME"`
   - Ignore the error if it's already booted
8. Build and install the app onto the simulator using
   `npx expo run:ios --device "$SIM_NAME"` from within the worktree
9. Start Metro in the background on the derived port:
   `npx expo start --port $PORT &`
   Save the PID to `"$LOCK_DIR/slot-$SLOT.lock/metro.pid"`
10. Write all environment info to `"$LOCK_DIR/slot-$SLOT.lock/env"`:
    ```
    SLOT=$SLOT
    WORKTREE=$WORKTREE
    BRANCH=$BRANCH
    SIM_NAME=$SIM_NAME
    SIM_UDID=$(xcrun simctl list devices | grep "$SIM_NAME" | awk -F'[()]' '{print $2}' | head -1)
    METRO_PORT=$PORT
    METRO_PID=$PID
    APP_BUNDLE_ID=$APP_BUNDLE_ID
    ```
11. Print "Slot $SLOT ready" and exit 0

---

## info.sh

**Purpose:** Print the environment variables for a prepared slot. Callers can source
this output to get everything they need.

Usage: `./info.sh <slot>`

Steps:
1. Source `config.sh`
2. Validate that the slot lock and env file exist
3. `cat "$LOCK_DIR/slot-$SLOT.lock/env"`
4. Exit 0

Example output:
```
SLOT=1
WORKTREE=/Users/nathan/projects/../env-pool-worktrees/env-pool-1
BRANCH=feature/my-branch
SIM_NAME=env-pool-1
SIM_UDID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
METRO_PORT=8082
METRO_PID=48291
APP_BUNDLE_ID=com.example.app
```

A test runner would use this as: `eval $(./env-pool/info.sh 1)` and then reference
`$SIM_UDID`, `$METRO_PORT`, etc.

---

## release.sh

**Purpose:** Tear down a slot completely and free it for reuse.

Usage: `./release.sh <slot>`

Steps:
1. Source `config.sh`
2. Read env file if it exists
3. Kill Metro process using stored PID (ignore errors if already dead)
4. Shut down simulator: `xcrun simctl shutdown "$SIM_NAME"`
5. Remove git worktree: `git worktree remove "$WORKTREE" --force`
6. Delete the branch created for this slot: `git branch -D "env-pool-$SLOT-work"`
7. Remove the lock directory: `rm -rf "$LOCK_DIR/slot-$SLOT.lock"`
8. Print "Slot $SLOT released"

This should always succeed even if some steps fail (use `|| true` defensively).

---

## status.sh

**Purpose:** Human-readable overview of all slots. Useful for debugging.

Steps:
1. Source `config.sh`
2. For each slot 0..POOL_SIZE-1:
   - Check if lock exists → "claimed" or "available"
   - If claimed and env file exists, print BRANCH, SIM_NAME, METRO_PORT
   - If claimed and env file missing, print "claimed but not yet prepared"
   - Check if simulator is actually booted via `xcrun simctl list devices`
   - Check if Metro PID is alive via `kill -0 $PID`

Example output:
```
Slot 0: AVAILABLE
Slot 1: READY  branch=feature/login  sim=env-pool-1  port=8082  metro=RUNNING  sim=BOOTED
Slot 2: CLAIMED (preparing...)
```

---

## Error Handling Principles

- Every script exits non-zero on any meaningful failure
- `prepare.sh` should clean up partially-prepared state if it fails midway
  (shut down sim, remove worktree, release lock) so the slot returns to available
- `release.sh` is defensive — it should complete fully even if individual steps fail
- Scripts validate their inputs at the top (correct number of args, slot in range,
  lock exists where expected) and print clear error messages to stderr

---

## Usage Example (for a test runner or agent)

```bash
# 1. Claim a slot
SLOT=$(./env-pool/claim.sh) || { echo "No slots available"; exit 1; }

# 2. Prepare it
./env-pool/prepare.sh $SLOT my-feature-branch || { ./env-pool/release.sh $SLOT; exit 1; }

# 3. Get environment info
eval $(./env-pool/info.sh $SLOT)

# 4. Run whatever tests you want using $SIM_UDID, $METRO_PORT, $WORKTREE, etc.
# e.g. maestro --device $SIM_UDID test flows/my-flow.yaml

# 5. Release
./env-pool/release.sh $SLOT
```

---

## Notes for the Implementing Agent

- All scripts should use `#!/bin/bash` and `set -e` at the top
- Use `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` to locate
  `config.sh` reliably regardless of where scripts are called from
- The `WORKTREE_BASE` path in config should be resolved relative to the repo root,
  not relative to the `env-pool/` directory
- Test idempotency: running `setup.sh` twice should produce no errors and no
  duplicate simulators
- The `xcrun simctl list devices` grep for UDID extraction is fragile — prefer
  `xcrun simctl list devices --json` and parse with `jq` if available
- Metro stdout/stderr should be redirected to a log file in the lock directory
  (e.g. `metro.log`) so it doesn't pollute script output and is available for
  debugging
