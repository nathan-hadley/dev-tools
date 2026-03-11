# Personal Agent Rules

## Workflows

### Opening a Pull Request

1. Check the `.github/` directory for a pull request template
2. If a template exists, follow it exactly when writing the PR description
3. Link the relevant Jira ticket in the PR, if applicable
4. Ensure all acceptance criteria from the Jira ticket are met before opening the PR

### Jira Acceptance Criteria

Before starting work and before marking work as complete, always verify acceptance criteria:

- If you have access to the Jira ticket, read the ticket and double-check the acceptance criteria for the task at hand.
- If you do not have access to the Jira ticket, ask the user to provide the acceptance criteria so you can verify your work against them.

## Maestro

- In Maestro flows, prefer regular visibility assertions such as `assertVisible` instead of `extendedWaitUntil` unless the user explicitly asks for `extendedWaitUntil`.
