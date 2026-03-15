---
name: maestro-test-from-ticket
description: Use when given a Jira ticket ID to autonomously create a maestro E2E test — sets up an isolated env-pool environment, inspects the app with iOS MCP, writes the test, validates it, and creates PRs.
---

# Maestro Test From Ticket

## Overview

Takes a Jira ticket ID and creates a complete maestro E2E test. Uses env-pool for an isolated worktree environment,
reads app code for discovery, uses iOS MCP to inspect the live app and accessibility tree, validates on iOS then
Android, and creates PRs via the maestro-pr-workflow skill.

## When to Use

- User provides a Jira ticket ID and asks you to create a maestro test for it
- User says something like "write a maestro test for QE-123"

## Prerequisites

Before starting, verify:

1. env-pool is operational:
   ```bash
   /Users/nathan/dev/limble/dev-tools/env-pool/env-pool status
   ```
2. A recent iOS build exists:
   ```bash
   ls -la /Users/nathan/dev/limble/dev-tools/env-pool/.builds/Limble.app
   ```
   If missing or stale (>1 week), tell the user to run `env-pool build ios` first.

## Phase 1: Understand the Ticket

1. Read the Jira ticket:
   ```
   mcp__jira__jira_get_issue with issue key
   ```
2. Extract from the ticket:
    - **What feature/flow** is being tested
    - **Testing steps** described in the ticket
    - **Acceptance criteria** if present
3. Summarize your understanding to the user before proceeding. Get confirmation.

## Phase 2: Create Isolated Environment

1. Create an env-pool environment. **Important:** Do NOT use a branch name like `main` if it's already checked out (the
   main repo or another worktree uses it). Instead, use the commit hash:
   ```bash
   # Get current main commit hash
   git -C /Users/nathan/dev/limble/mobileApp rev-parse HEAD
   # Create env from commit hash (avoids "already used by worktree" error)
   /Users/nathan/dev/limble/dev-tools/env-pool/env-pool create <commit-hash>
   ```
2. Capture the env ID printed to stdout (e.g., `env-001`)
3. Boot/connect the iOS preview simulator for inspection:
   ```bash
   /Users/nathan/dev/limble/dev-tools/env-pool/env-pool preview <env-id>
   ```
4. Read the environment metadata:
   ```bash
   cat /Users/nathan/dev/limble/dev-tools/env-pool/.state/<env-id>/meta
   ```
5. Note these values — you'll need them throughout:
    - `WORKTREE` — all file edits happen here, NEVER in the main repo
    - `SIM_UDID` — the preview simulator for iOS MCP targeting
    - `METRO_PORT` — the Metro server for this environment

**CRITICAL: From this point forward, all file reads and edits use paths under the WORKTREE directory,
not `/Users/nathan/dev/limble/mobileApp/`.** Exception: when discovering API endpoints not available in the mobile app,
you may read (but never edit) sibling repos like `webApp`, `flannel`, and `monorepo`.

## Phase 3: Discovery — Understand the App Code

**Goal:** Build a mental map of screens, components, testIDs, and APIs relevant to the test.

1. **Search for relevant screens** in the worktree:
    - Look in `<WORKTREE>/screens/` and `<WORKTREE>/app/` for screens matching the feature
    - Read the screen components to understand the UI structure

2. **Find existing testIDs:**
    - Search for `testID` props in relevant components
    - Check existing page objects in `<WORKTREE>/maestro/pages/` for already-mapped selectors

3. **Identify missing testIDs:**
    - Determine which UI elements the test needs to interact with
    - Note which ones lack testIDs

4. **Add missing testIDs** to components in the worktree:
    - Follow existing naming convention: hierarchical dot notation (e.g., `task-field.name`, `asset.hierarchy.item`)
    - Look at nearby testIDs in the same component for naming patterns
    - Metro hot reload picks up changes — no native rebuild needed

5. **Inspect the live UI with iOS MCP before spending a Maestro run:**
    - Use the simulator that `env-pool preview` booted for the environment
    - Walk the feature manually with iOS MCP and confirm the controls you plan to target are actually exposed
    - Perform one-time session setup here instead of in verification:
        - connect to the correct Metro server
        - dismiss Expo/developer UI
        - log in with the existing test credentials already present in the mobile app repo
    - Preferred MCP tools:
        - `mcp__ios-simulator__get_booted_sim_id` — confirm the active simulator
        - `mcp__ios-simulator__ui_describe_all` — inspect the current accessibility tree
        - `mcp__ios-simulator__screenshot` — confirm the visible UI
        - `mcp__ios-simulator__ui_tap` / `mcp__ios-simulator__ui_swipe` — navigate manually
    - Use this to validate that new or existing `testID`s make sense before writing selectors into the flow

6. **Understand API needs for setup/teardown:**
    - Check what test data needs to be created/deleted
    - Look at existing API scripts in `<WORKTREE>/maestro/api/` — reuse where possible
    - For new API calls, reference `<WORKTREE>/api/` for endpoints, request shapes, and types
    - If the mobile app doesn't have the needed API client, check:
        - `/Users/nathan/dev/limble/webApp` — web app has all features mobile has plus more
        - `/Users/nathan/dev/limble/flannel` — Node API
        - `/Users/nathan/dev/limble/monorepo` — shared services
    - Reference `<WORKTREE>/maestro/api/constants.js` for stable test environment IDs (customer, users, priorities,
      locations, etc.)

## Phase 4: Write the Maestro Test

**Study existing tests first.** Read 2-3 existing flows in `<WORKTREE>/maestro/flows/` to match conventions exactly.

### File organization

- Place flows in the appropriate domain subfolder under `maestro/flows/` (e.g., `tasks/`, `assets/`, `parts/`)
- Create a subdirectory for the test if it has multiple files (flow + setup script)

### API setup/teardown scripts

If the test needs data created/deleted:

1. Create setup script(s) in `<WORKTREE>/maestro/api/` or alongside the flow
2. Follow patterns from existing scripts like `maestro/api/tasks/createTask.js`:
    - Use `client.js` for HTTP utilities
    - Use `auth.js` for authentication
    - Use `constants.js` for stable IDs
    - Export results via `output.*` for use in the flow
3. Create teardown scripts to clean up test data in `onFlowComplete`

### Page objects

- Update existing page objects in `<WORKTREE>/maestro/pages/` if adding selectors to known screens
- Create new page object files for new screens, following the `output.<PageName>` export pattern

### Development Constraints (serialized verification workflow)

- Prefer code reading plus iOS MCP inspection before spending a real Maestro run.
- Treat login as setup, not as the thing being verified, unless the ticket is specifically about login behavior.
- Prefer flows with `CLEAR_STATE: "false"` during authoring after the preview session is already connected and logged in.
- `env-pool verify` is serialized. Draft more before verifying.
- Normal Maestro flow features like `clearState`, `startRecording`, and `stopRecording` are allowed again.
- Use conditional login checks (e.g., `when: visible:`) when they make the flow more resilient, not because of a
  runner-specific limitation.

### Flow YAML

When the test creates data that must be cleaned up regardless of pass/fail (most tests), use `onFlowStart`/
`onFlowComplete`:

```yaml
appId: com.limblecmms.mobileApp
---
onFlowStart:
  - runScript: <relative path to client.js>
  - runScript: <relative path to auth.js>
  - runScript: <relative path to constants.js>
  # ... additional setup scripts (e.g., createTask.js)

onFlowComplete:
  - runScript: <relative path to client.js>
  - runScript: <relative path to auth.js>
  # ... teardown scripts (e.g., deleteTask.js)

# Load page objects
- runScript: <relative path to page object>

# Login if needed
- runFlow:
  file: <relative path to login.yaml>
  env:
  CLEAR_STATE: "false"

# Test steps — add startRecording/stopRecording only when committing for CI
# ... UI interactions and assertions
```

This is the standard pattern used by existing flows (e.g., `open-task-search.yaml`). The `onFlowComplete` block runs
even if the test fails, ensuring test data is always cleaned up.

### Assertion style

- **Never use `extendedWaitUntil`** — `assertVisible` waits 7 seconds by default, which is sufficient. There is no valid
  reason to use `extendedWaitUntil`.
- Use testID-based selectors (e.g., `id: "task-field.name"`) over text matching when possible

## Phase 5: Validate on iOS

1. Before the first Maestro run for a non-trivial flow, manually walk the path once with iOS MCP:
   - Confirm the screen hierarchy matches your expectations
   - Confirm the controls you want to target are accessible
   - Confirm any newly added `testID`s appear where expected
   - If needed, complete one-time login setup in preview so the verify run can focus on the feature flow

2. Run the test:
   ```bash
   /Users/nathan/dev/limble/dev-tools/env-pool/env-pool verify <env-id> <flow-path>
   ```
   Where `<flow-path>` is relative to the worktree's maestro directory or an absolute path.

3. **If the test fails:**
    - Read the maestro output carefully to understand the failure
    - If the failure is a selector mismatch or unclear screen state, use iOS simulator MCP to inspect.
      First, get the booted simulator ID:
        - `mcp__ios-simulator__get_booted_sim_id` — confirm the right simulator is targeted
        - `mcp__ios-simulator__ui_describe_all` — get accessibility tree of current screen
        - `mcp__ios-simulator__screenshot` — see current screen visually
        - `mcp__ios-simulator__ui_tap` / `mcp__ios-simulator__ui_swipe` — navigate to the right screen
    - Fix the issue (flow YAML, page objects, testIDs, or API scripts)
    - Re-run

4. **Guardrail:** If the test fails 5 times consecutively, STOP and ask the user for guidance. Do not loop indefinitely.

5. **Signin guardrail:** If you hit signin/login issues during flow execution, STOP immediately and ask the user for
   help. Do not attempt to debug signin problems yourself.

6. Once the test passes on iOS, proceed to Android.

## Phase 6: Validate on Android

1. Run the test on Android:
   ```bash
   /Users/nathan/dev/limble/dev-tools/env-pool/env-pool verify <env-id> <flow-path> --platform android
   ```

2. **If the test fails:**
    - Read the output to diagnose — common issues:
        - Platform-specific selector differences
        - Layout/scroll differences (elements off-screen on Android)
        - Timing differences
    - Fix the issue — use Maestro platform conditionals if behavior must differ:
      ```yaml
      - runFlow:
          when:
            platform: Android
          file: android-specific-step.yaml
      ```
    - **After any change, re-run iOS first** (`env-pool verify <env-id> <flow-path>`), then re-run Android — this
      confirms the fix didn't break iOS

3. **Same guardrail:** 5 consecutive Android failures → stop and ask the user.

4. Once both iOS and Android pass, proceed to PR creation.

## Phase 7: PR Creation

1. Invoke the `maestro-pr-workflow` skill to handle PR creation.
2. The skill will determine the correct workflow:
    - **testIDs were added** (files changed outside `maestro/`) → stacked PR workflow
    - **Maestro-only changes** → single PR workflow
3. Link the original Jira ticket ID in the PR body.

## Phase 8: Environment Cleanup

Ask the user:

> "Tests pass on both platforms and PRs are created. Want me to release the env-pool environment (`<env-id>`), or leave
> it running so you can inspect?"

- If release: `env-pool release <env-id>` from `/Users/nathan/dev/limble/dev-tools/env-pool/`
- If keep: Print the env ID and simulator name for reference

## env-pool CLI Reference

All commands run from `/Users/nathan/dev/limble/dev-tools/env-pool/`:

```bash
env-pool create <commit-hash>                     # Create isolated worktree + Metro env
env-pool preview <env-id>                         # Provision iOS simulator for MCP inspection
env-pool verify <env-id> <flow>                   # Run serialized iOS verification
env-pool verify <env-id> <flow> --platform android # Run serialized Android verification
env-pool release <env-id>                         # Tear down environment
env-pool status                                   # Show active environments
```
