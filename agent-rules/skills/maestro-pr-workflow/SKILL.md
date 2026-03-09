---
name: maestro-pr-workflow
description: Use when maestro test work involves both app code changes (testIDs, components) and maestro-only changes (flows, page objects, API scripts, utils). Splits work into stacked PRs.
---

# Maestro PR Workflow

## Overview

Maestro test work often touches both app code (testIDs, components) and maestro test infrastructure (flows, page
objects, API scripts). These must be split into two stacked PRs: app changes first, maestro changes on top.

## When to Use

- Adding or modifying Maestro flows that require app code changes (new testIDs, component fixes)
- Any work that touches files both inside and outside `maestro/`

## Workflow

### 1. Branch and Stage App Changes

Create a feature branch. Stage only non-maestro files:

- `components/`, `screens/`, `app/`, etc.
- Commit and push

### 2. Create App PR (Draft)

```bash
gh pr create --draft --base main --title "..." --body "..."
```

- Follow `.github/pull_request_template.md`
- Testing instructions: "N/A" for testID-only changes
- Link Jira tickets in Context section

### 3. Create Maestro Branch (Stacked)

From the app branch, create a new branch with `-maestro` suffix:

```bash
git checkout -b <app-branch-name>-maestro
```

Stage all maestro files and commit.

### 4. Create Maestro PR (Draft, Stacked)

```bash
gh pr create --draft --base <app-branch-name> --title "..." --body "..."
```

- Base branch = app branch (not main) — this stacks the PR
- Testing instructions: list the maestro flows to run
- Note "Stacked on #<app-pr-number>" in the body
- Link same Jira tickets

## PR Body Format

```markdown
# Context

[TICKET-ID](https://limble.atlassian.net/browse/TICKET-ID) - Description.

## What Changed

- Bullet points, to the point

## Screenshots/Videos

N/A

## Testing Instructions

<!-- App PR: "N/A" for testID-only changes -->
<!-- Maestro PR: list flows to run -->

### Reminders

- Submitter - By submitting this PR you are communicating that you have manually tested the changes
    - [x] 
        - Do you add loading states?
- Reviewer - Please test the code locally via simulator or physical device (physical is preferred)
```
