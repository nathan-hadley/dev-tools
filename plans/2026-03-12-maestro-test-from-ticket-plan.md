# Maestro Test From Ticket — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a skill that takes a Jira ticket ID and autonomously creates, validates, and PRs a maestro E2E test using env-pool for isolation.

**Architecture:** Single SKILL.md file that guides a sequential agent through: Jira read → env-pool setup → code discovery → test authoring → iOS validation → Android validation → PR creation → cleanup prompt. Composes the existing maestro-pr-workflow skill for PR creation.

**Tech Stack:** Claude Code skills (SKILL.md), env-pool CLI, iOS simulator MCP, Maestro, Jira MCP

---

### Task 1: Create the skill directory and SKILL.md

**Files:**
- Create: `/Users/nathan/dev/limble/dev-tools/agent-rules/skills/maestro-test-from-ticket/SKILL.md`

**Step 1: Create the skill file**

Write the SKILL.md with the following structure. The skill must be detailed enough that an agent with zero codebase context can follow it end-to-end.

```markdown
---
name: maestro-test-from-ticket
description: Use when given a Jira ticket ID to autonomously create a maestro E2E test — sets up isolated env-pool environment, discovers app structure, writes and validates tests on iOS and Android, then creates PRs.
---

# Maestro Test From Ticket

## Overview

Takes a Jira ticket ID and creates a complete maestro E2E test. Uses env-pool for an isolated worktree environment, reads app code for discovery, validates on iOS then Android, and creates PRs via the maestro-pr-workflow skill.

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

1. Create an env-pool environment from main:
   ```bash
   /Users/nathan/dev/limble/dev-tools/env-pool/env-pool create main
   ```
2. Capture the env ID printed to stdout (e.g., `env-001`)
3. Read the environment metadata:
   ```bash
   cat /Users/nathan/dev/limble/dev-tools/env-pool/.state/<env-id>/meta
   ```
4. Note these values — you'll need them throughout:
   - `WORKTREE` — all file edits happen here, NEVER in the main repo
   - `SIM_UDID` — for iOS simulator MCP targeting
   - `METRO_PORT` — the Metro server for this environment

**CRITICAL: From this point forward, all file reads and edits use paths under the WORKTREE directory, not `/Users/nathan/dev/limble/mobileApp/`.**

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

5. **Understand API needs for setup/teardown:**
   - Check what test data needs to be created/deleted
   - Look at existing API scripts in `<WORKTREE>/maestro/api/` — reuse where possible
   - For new API calls, reference `<WORKTREE>/api/` for endpoints, request shapes, and types
   - If the mobile app doesn't have the needed API client, check:
     - `/Users/nathan/dev/limble/webApp` — web app has all features mobile has plus more
     - `/Users/nathan/dev/limble/flannel` — Node API
     - `/Users/nathan/dev/limble/monorepo` — shared services
   - Reference `<WORKTREE>/maestro/api/constants.js` for stable test environment IDs (customer, users, priorities, locations, etc.)

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

### Flow YAML

Follow this structure:
```yaml
appId: com.limblecmms.mobileApp
---
# Setup: load helpers and create test data
- runScript: <relative path to client.js>
- runScript: <relative path to auth.js>
- runScript: <relative path to constants.js>
# ... additional setup scripts

# Load page objects
- runScript: <relative path to page object>

# Login if needed
- runFlow:
    file: <relative path to login.yaml>
    env:
      CLEAR_STATE: "false"

# Test steps
- startRecording: <test-name>
# ... UI interactions and assertions
- stopRecording
```

Use `onFlowStart`/`onFlowComplete` for setup/teardown when the test creates data that must be cleaned up regardless of pass/fail.

### Assertion style

- Prefer `assertVisible` over `extendedWaitUntil` unless explicitly told otherwise
- Use testID-based selectors (e.g., `id: "task-field.name"`) over text matching when possible

## Phase 5: Validate on iOS

1. Run the test:
   ```bash
   /Users/nathan/dev/limble/dev-tools/env-pool/env-pool run-maestro <env-id> <flow-path>
   ```
   Where `<flow-path>` is relative to the worktree's maestro directory or an absolute path.

2. **If the test fails:**
   - Read the maestro output carefully to understand the failure
   - If the failure is a selector mismatch or unclear screen state, use iOS simulator MCP to inspect:
     - `mcp__ios-simulator__ui_describe_all` — get accessibility tree
     - `mcp__ios-simulator__screenshot` — see current screen
     - `mcp__ios-simulator__ui_tap` / `mcp__ios-simulator__ui_swipe` — navigate to the right screen
   - Fix the issue (flow YAML, page objects, testIDs, or API scripts)
   - Re-run

3. **Guardrail:** If the test fails 5 times consecutively, STOP and ask the user for guidance. Do not loop indefinitely.

4. Once the test passes on iOS, proceed to Android.

## Phase 6: Validate on Android

1. Run the test on Android:
   ```bash
   /Users/nathan/dev/limble/dev-tools/env-pool/env-pool run-maestro <env-id> <flow-path> --platform android
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
   - **After any change, re-run on BOTH platforms** to confirm no regression
   - Re-run on Android

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

> "Tests pass on both platforms and PRs are created. Want me to release the env-pool environment (`<env-id>`), or leave it running so you can inspect?"

- If release: `env-pool release <env-id>` from `/Users/nathan/dev/limble/dev-tools/env-pool/`
- If keep: Print the env ID and simulator name for reference
```

**Step 2: Verify the file was created**

```bash
cat /Users/nathan/dev/limble/dev-tools/agent-rules/skills/maestro-test-from-ticket/SKILL.md | head -5
```

**Step 3: Commit**

```bash
cd /Users/nathan/dev/limble/dev-tools
git add agent-rules/skills/maestro-test-from-ticket/SKILL.md
git commit -m "feat: add maestro-test-from-ticket skill"
```

---

### Task 2: Symlink the skill into Claude's skills directory

**Files:**
- Create: `/Users/nathan/.claude/skills/maestro-test-from-ticket` (symlink)

**Step 1: Create the symlink**

```bash
ln -s /Users/nathan/dev/limble/dev-tools/agent-rules/skills/maestro-test-from-ticket /Users/nathan/.claude/skills/maestro-test-from-ticket
```

**Step 2: Verify the symlink resolves**

```bash
ls -la /Users/nathan/.claude/skills/maestro-test-from-ticket
cat /Users/nathan/.claude/skills/maestro-test-from-ticket/SKILL.md | head -5
```

---

### Task 3: Register the skill in the mobileApp project settings

**Files:**
- Modify: `/Users/nathan/dev/limble/mobileApp/.claude/settings.local.json`

**Step 1: Check current settings**

Read the file and find the skills or permissions section. Add the new skill to the allow list if skills need explicit permission.

**Step 2: Verify**

Start a new Claude Code session in the mobileApp directory and confirm the skill appears in the available skills list.

---

### Task 4: Test the skill end-to-end

**Step 1: Pick a simple existing Jira ticket**

Choose a QE ticket that already has a maestro test, so you can compare the agent's output against the known-good test.

**Step 2: Run the skill**

In a new Claude Code session in the mobileApp:
```
Create a maestro test for QE-<ticket-id>
```

**Step 3: Verify each phase executes correctly**

- Jira ticket is read
- env-pool environment is created
- Discovery finds the right screens/components
- Test is authored following conventions
- iOS validation runs and passes
- Android validation runs and passes
- PR(s) are created correctly
- Cleanup prompt appears

**Step 4: Compare output against existing test**

Verify the generated test follows the same patterns and covers similar scenarios.
