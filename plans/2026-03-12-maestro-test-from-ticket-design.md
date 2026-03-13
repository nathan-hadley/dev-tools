# Maestro Test From Ticket — Skill Design

## Overview

A skill that takes a Jira ticket ID and autonomously creates a maestro E2E test for the described feature/flow. Uses env-pool for isolated environments, reads app code for discovery, validates on iOS then Android, and creates PRs via the maestro-pr-workflow skill.

## Trigger

User provides a Jira ticket ID (e.g., `QE-988`). The skill reads the ticket and drives the full lifecycle.

## Approach

Single sequential agent. Full context stays in one conversation — simplest to get right, debug, and iterate on.

## Lifecycle

### 1. Input & Preconditions

- Read Jira ticket via `mcp__jira__jira_get_issue` — extract summary, description, testing steps
- Verify env-pool is operational (`env-pool status`)
- Verify a recent iOS build exists (`.builds/Limble.app`)

### 2. Environment Setup

- Always create from main: `env-pool create main`
- Capture env ID from stdout
- Read `.state/<env-id>/meta` for `WORKTREE`, `SIM_UDID`, `METRO_PORT`
- All file edits happen in the worktree — main repo is never modified

### 3. App Exploration & Discovery

- Read Jira ticket to understand the user flow being tested
- Search the **worktree** codebase for relevant screens, components, and existing testIDs
- Identify missing testIDs, add them to components in the worktree
  - Follow existing naming conventions (hierarchical dot notation, e.g., `task-field.name`)
  - Metro hot reload picks up changes — no native rebuild needed
- Reserve iOS simulator MCP for debugging only (when tests fail and screen state is unclear)

### 4. Test Authoring

- Study existing maestro tests to match conventions:
  - Flow structure (YAML, `onFlowStart`/`onFlowComplete`)
  - Page object pattern (JS files exporting `output.<PageName>`)
  - API setup/teardown scripts (auth, create/delete test data)
  - File organization within `maestro/flows/`
- Create files: page objects, API scripts, flow YAML
- For API setup/teardown:
  - Reuse existing `maestro/api/` scripts where possible
  - For new API calls, reference `mobileApp/api/` for endpoints and types
  - If the mobile app lacks the needed API client, check `../webApp` (has all features mobile has + more)
  - Also check `../flannel` and `../monorepo` for backend services
- Use `maestro/api/constants.js` for stable test environment IDs
- Create per-test data via API scripts, don't rely on pre-existing state

### 5. iOS Validation Loop

- Run `env-pool run-maestro <env-id> <flow-path>`
- On failure: read output, fix YAML/page objects/testIDs/API scripts, re-run
- If selector issues are unclear from output, use iOS MCP (`ui_describe_all`, `screenshot`) to inspect
- **Guardrail:** Stop after 5 consecutive failures, ask user for guidance

### 6. Android Validation

- Run `env-pool run-maestro <env-id> <flow-path> --platform android`
- On failure: diagnose, fix (platform conditionals if needed), re-run
- After any cross-platform fix, re-run on iOS to confirm no regression
- **Same guardrail:** 5 consecutive failures → ask user
- Note: Android uses shared emulator with lock queue, may block briefly

### 7. PR Creation & Cleanup

- Invoke `maestro-pr-workflow` skill:
  - testIDs added → stacked PR (app PR + maestro PR)
  - Maestro-only → single PR
- Link original Jira ticket in PR body
- Ask user: release the environment or leave it running?
  - Release → `env-pool release <env-id>`
  - Keep → print env ID and simulator name

## Key Constraints

- Main repo is never modified — all work happens in env-pool worktree
- Always branch from main
- No native rebuilds — testIDs are JS-side, Metro hot reload is sufficient
- Code reading preferred over MCP exploration for discovery
- Composes maestro-pr-workflow skill for PR creation
- Does NOT create Jira tickets (that's a separate human-in-the-loop process)

## env-pool CLI Reference

All commands run from `/Users/nathan/dev/limble/dev-tools/env-pool/`:

```
env-pool create main              # Create isolated env, returns env ID
env-pool run-maestro <id> <flow>  # Run test on iOS (default)
env-pool run-maestro <id> <flow> --platform android  # Run on Android
env-pool release <id>             # Tear down environment
env-pool status                   # Show active environments
```
