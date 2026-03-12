# iOS/Android Environment Pool — Design

## Goal

A CLI toolkit (`env-pool`) that creates on-demand, isolated mobile development
environments. Each environment consists of a git worktree, a cloned iOS simulator,
and a Metro dev server. Environments are ephemeral — created when needed, destroyed
when done. Android uses a single shared emulator with lock-based queuing.

Primary use case: letting Claude Code agents build and run Maestro tests in parallel,
with future support for human feature/bugfix work alongside agents.

---

## Location

`~/dev/limble/dev-tools/env-pool/` — sibling to `~/dev/limble/mobileApp/`.

(Requires moving dev-tools from `~/dev/dev-tools/` to `~/dev/limble/dev-tools/`.)

---

## File Structure

```
env-pool/
  env-pool              # Main entry point, dispatches subcommands
  config.sh             # User-editable defaults
  lib/
    setup.sh
    build.sh
    create.sh
    run-maestro.sh
    release.sh
    gc.sh
    status.sh
    common.sh           # Shared helpers (port scanning, UDID lookup, etc.)
  .builds/              # Pre-built .app/.apk artifacts (gitignored)
  .state/               # Active environment metadata (gitignored)
```

---

## Config

`config.sh` — the only file a user edits:

```bash
# Paths
MOBILE_APP_REPO="../mobileApp"
WORKTREE_DIR="../env-pool-worktrees"

# iOS
IOS_DEVICE_TYPE="iPhone 16e"
IOS_VERSION="iOS 18.4"
IOS_BUNDLE_ID="com.limblecmms.mobileApp"

# Android
ANDROID_AVD="Small_Phone"
ANDROID_BUNDLE_ID="com.limblecmms.mobileApp"

# Metro
METRO_BASE_PORT=8082              # 8081 left free for manual dev
PORT_SCAN_RANGE=50

# Garbage collection
ENV_TTL_SECONDS=7200              # 2 hours

# Android lock
ANDROID_LOCK_RETRY_INTERVAL=5    # Seconds between retries
ANDROID_LOCK_TIMEOUT=300          # Give up after 5 minutes
```

---

## CLI Commands

### `env-pool setup`

One-time initialization. Idempotent.

1. Create a template iOS simulator named `env-pool-template` (iPhone 16e, iOS 18.4)
   - Skip if it already exists
2. Verify the `Small_Phone` Android AVD exists
3. Create `.builds/` and `.state/` directories
4. Create `WORKTREE_DIR` if it doesn't exist

### `env-pool build`

Build app artifacts and store in `.builds/`.

1. Build iOS `.app` via `expo run:ios` from the mobileApp repo
2. Build Android `.apk` via `expo run:android` from the mobileApp repo
3. Store artifacts in `.builds/` with timestamps
4. Warn if existing artifacts are older than 1 week (informational only)

### `env-pool create <branch>`

Create a full environment. Prints env ID to stdout.

1. Generate unique env ID (e.g., `env-001`, incrementing based on `.state/` contents)
2. Clone template simulator: `xcrun simctl clone env-pool-template env-pool-<id>`
3. Create git worktree: `git -C ../mobileApp worktree add <worktree-path> <branch>`
4. Boot the cloned simulator
5. Install pre-built `.app`: `xcrun simctl install <udid> <path-to-.app>`
6. Scan for available port starting at `METRO_BASE_PORT`
7. Start Metro on that port from the worktree, redirect output to `.state/env-<id>/metro.log`
8. Write metadata to `.state/env-<id>/meta`:
   ```
   ENV_ID=env-001
   BRANCH=feature/foo
   WORKTREE=/path/to/worktree
   SIM_NAME=env-pool-001
   SIM_UDID=XXXXXXXX-...
   METRO_PORT=8082
   METRO_PID=12345
   CREATED_AT=1710000000
   ```
9. Print the env ID

**Failure handling:** If any step fails after partial setup, clean up everything
(delete sim clone, remove worktree, remove state dir). Caller gets a non-zero exit
code and no env ID.

### `env-pool run-maestro <env-id> <flow-path> [--platform android]`

Run a Maestro test against an existing environment.

**iOS (default):**
- Read env metadata to get UDID and Metro port
- Run: `maestro --device <udid> test <flow-path>`
- Return maestro's exit code

**Android:**
- Acquire lock (`.state/android.lock`) — wait/retry if busy, fail after timeout
- Boot `Small_Phone` emulator if not already running
- Install `.apk` if needed
- Point emulator at the environment's Metro port for JS bundle
- Run: `maestro --device <emulator-id> test <flow-path>`
- Release lock
- Return maestro's exit code

### `env-pool release <env-id>`

Tear down an environment. Defensive — completes even if individual steps fail.

1. Kill Metro via stored PID (`|| true`)
2. Shutdown simulator: `xcrun simctl shutdown env-pool-<id>` (`|| true`)
3. Delete simulator: `xcrun simctl delete env-pool-<id>` (`|| true`)
4. Remove git worktree (`|| true`)
5. Delete `.state/env-<id>/`

### `env-pool gc`

Clean up leaked/expired environments.

1. Scan `.state/` for all environments
2. For each, check:
   - Is the Metro PID still alive? (`kill -0 $PID`)
   - Has `CREATED_AT` exceeded `ENV_TTL_SECONDS`?
3. Run `release` on any environment that fails either check

### `env-pool status`

Human-readable overview of all active environments.

For each environment in `.state/`:
- ID, branch, Metro port, simulator state (booted/shutdown), uptime
- Whether Metro PID is alive

Example:
```
env-001  branch=feature/login  port=8082  sim=BOOTED  metro=RUNNING  uptime=45m
env-002  branch=fix/bug-123    port=8083  sim=BOOTED  metro=RUNNING  uptime=12m
android  emulator=Small_Phone  status=RUNNING  lock=FREE
```

---

## iOS Strategy

- **Template simulator** created once via `setup`, cloned per environment
- Cloning is near-instant vs creating from scratch
- **Pre-built `.app`** installed via `xcrun simctl install` — no per-environment native build
- Each environment gets its own simulator clone (full isolation for parallel runs)

## Android Strategy

- **Single shared emulator** (`Small_Phone` AVD) — no pooling
- **Lock-based queue** for exclusive access during test runs
- Emulator stays running between runs to avoid cold boot penalty
- Each environment's Metro serves JS to the emulator when it's that env's turn
- Agents install `.apk` once, then reuse

---

## Environment Lifecycle

**Agent building Maestro tests (primary use case):**
```bash
# Start of session
ENV=$(env-pool create my-feature-branch)

# Iterate: write test, run, fix, run again
env-pool run-maestro $ENV maestro/flows/my-test.yaml
# ... edit the test ...
env-pool run-maestro $ENV maestro/flows/my-test.yaml
# ... also verify on Android ...
env-pool run-maestro $ENV maestro/flows/my-test.yaml --platform android

# Done
env-pool release $ENV
```

**Parallel agents:**
```bash
# Agent A                                    # Agent B
ENV_A=$(env-pool create branch-a)            ENV_B=$(env-pool create branch-b)
env-pool run-maestro $ENV_A flow.yaml        env-pool run-maestro $ENV_B flow.yaml
env-pool release $ENV_A                      env-pool release $ENV_B
```

**Safety net:**
```bash
# Before starting work, clean up any leaked environments
env-pool gc
```

---

## Error Handling

- **`create` is atomic:** full environment or nothing. Partial state is cleaned up on failure.
- **`release` is defensive:** every step uses `|| true`. Always removes state directory.
- **Agent crashes:** `gc` catches via dead Metro PID or TTL expiry.
- **Port conflicts:** scanner skips in-use ports. Fails with clear error if range exhausted.
- **Android emulator not running:** `run-maestro --platform android` boots it automatically.
- **Stale builds:** Informational warning if `.app`/`.apk` older than 1 week. No auto-rebuild.

---

## Decisions & Rationale

| Decision | Rationale |
|----------|-----------|
| Ephemeral over persistent pools | Simpler lifecycle, no stale state, no leaked slots |
| Clone simulators vs create fresh | Near-instant, reuses template config |
| Pre-build .app, install per env | Avoids expensive native build per environment |
| Single Android emulator + queue | Emulators are resource-heavy; only need pass/fail verification |
| Metro base port 8082 | Leaves 8081 free for manual development |
| Lock file for Android queue | Simple, sufficient for low contention |
| 1-week build staleness warning | Native code changes infrequently |
| No Makefile | Commands take arguments; CLI subcommands are more natural |

---

## Future Considerations

- MCP server wrapper for native agent tool integration
- Hash-based automatic rebuild detection (Podfile.lock, app.config.ts changes)
- CI/CD integration for running Maestro tests on merge
