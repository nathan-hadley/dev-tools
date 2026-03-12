---
name: maestro-pr-workflow
description: Use when creating PRs for any maestro test work — whether maestro-only or combined with app code changes.
---

# Maestro PR Workflow

## Overview

Use this skill for **all** maestro test PRs. The workflow depends on whether app code was changed:

- **Maestro-only changes** (flows, page objects, API scripts, utils) → Single PR against main
- **App + maestro changes** (testIDs, components + flows) → Two stacked PRs

## When to Use

- Creating a PR for any work involving maestro files
- Adding or modifying Maestro flows (with or without app code changes)
- Any work that touches files inside `maestro/`

## Determine PR Strategy

Check if any files outside `maestro/` were changed:

```bash
git diff main --name-only | grep -v '^maestro/'
```

- **No results** → Maestro-only. Follow the Single PR workflow.
- **Has results** → Mixed changes. Follow the Stacked PR workflow.

## Single PR Workflow (Maestro-Only)

### 1. Commit and Push

Stage all maestro files, commit, and push to the feature branch.

### 2. Create PR

```bash
gh pr create --base main --title "..." --body "..."
```

- Use the PR Body Format below
- Testing instructions: list the maestro flows to run
- Link Jira tickets in Context section

---

## Stacked PR Workflow (App + Maestro)

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
    - [x] Do you add loading states?
- Reviewer - Please test the code locally via simulator or physical device (physical is preferred)
```
