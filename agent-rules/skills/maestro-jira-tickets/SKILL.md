---
name: maestro-jira-tickets
description: Use when creating Jira tickets for new maestro test automation work under the maestro epic.
---

# Maestro Jira Tickets

## Overview

Maestro automation tickets live in the QE project under epic QE-757 ("Implement Maestro Test Cases for Mobile App").
They use issue type "Test" and follow a specific four-section description format.

## When to Use

- Creating new Jira tickets for maestro test cases
- Updating existing maestro automation tickets

## Ticket Structure

- **Project:** QE
- **Issue type:** Test
- **Parent:** QE-757
- **Assignee:** Nathan Hadley (`712020:0475fc9d-6d24-4ab1-bb30- Oa36b82b36b8d`)
- **Priority:** Medium (default)

## Description Format

Four sections, each a short paragraph. No steps, no bullet lists in the description — keep it prose-like and concise.

```
*Purpose*
What capability is being validated. One sentence.

*Business Value*
Why this matters for users/technicians. One sentence.

*Risk Covered*
What regressions this prevents and the user impact if they occur. One sentence.

*Outcome*
What the automation continuously validates, summarizing the key behaviors covered. One to two sentences.
```

## Example (QE-981)

```
*Purpose*
Ensure that users can apply multiple filter criteria on the task list to narrow down tasks by priority, status, assignment, asset, and date range.

*Business Value*
This automation validates that technicians can efficiently locate relevant tasks using combined filters, supporting faster response times and better workload prioritization.

*Risk Covered*
Prevents regressions where filter criteria fail to apply correctly, return incorrect results, or lose state when combined — leading to users missing critical tasks.

*Outcome*
Provides continuous validation that task list filtering works end-to-end with multiple combined criteria (high priority, assigned to self, open/in progress statuses, specific asset, created in last 7 days) and returns only matching tasks.
```
