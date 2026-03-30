---
name: code-review
description: Use when asked to review a pull request by number, URL, or owner/repo#number reference. Fetches the PR diff, gathers context (Jira, Figma, ephemeral env, repo structure), generates conventional comments, previews them for approval, and posts via the GitHub Reviews API.
---

# Code Review

## Overview

Review a pull request using conventional comments. The skill gathers full context (PR metadata, Jira ticket, Figma designs, ephemeral environment, repo structure, existing reviews), generates line-level feedback with conventional comment labels, previews all comments for user approval, and posts the review via the GitHub Reviews API.

The review is posted only after explicit user approval. Nothing is sent to GitHub until you say so.

## Input

The user provides a PR reference in one of these formats:

- PR number: `#4461` or `4461`
- URL: `https://github.com/LimbleCMMS/monorepo/pull/4461`
- Owner/repo format: `LimbleCMMS/monorepo#4461`

**Parse the input to extract:**

- `owner` and `repo` — from the URL or `owner/repo#` format. If only a number is given, detect from the current repo:
  ```bash
  gh repo view --json owner,name --jq '{owner: .owner.login, repo: .name}'
  ```
- `pr_number` — the PR number

**Validate the PR exists:**

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number} --jq '.number'
```

If the PR does not exist or is not accessible, stop and tell the user.

---

## Phase 1: Context Gathering

Gather all necessary context before generating any review comments. Run independent API calls in parallel where possible.

### 1.1 PR Metadata

Fetch the PR title, description, author, base branch, head branch, head SHA, and linked issues:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number} \
  --jq '{title: .title, body: .body, author: .user.login, base: .base.ref, head: .head.ref, head_sha: .head.sha}'
```

Save the `head_sha` — it is needed in Phase 4 when posting the review.

### 1.2 Diff and Changed Files

Fetch the full diff with file-level details:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/files --paginate \
  --jq '.[] | {filename: .filename, status: .status, patch: .patch, additions: .additions, deletions: .deletions}'
```

### 1.3 Full File Contents

For each changed file, read the full file contents (not just the diff hunk) to understand surrounding context. This is essential for judging whether changes fit the existing code.

**For large PRs:** If a file is larger than ~500 lines, read only the changed hunks plus 50 lines of surrounding context. If the PR touches more than 20 files, prioritize files with substantive logic changes over configuration, generated, or lock files.

- If the PR branch is checked out locally, use the Read tool on local files.
- Otherwise, fetch via the API:
  ```bash
  gh api repos/{owner}/{repo}/contents/{path}?ref={head_branch} --jq '.content' | base64 -d
  ```

### 1.4 Jira Ticket

Scan the PR title, description, and branch name for Jira ticket IDs (pattern: `[A-Z]+-\d+`). If a ticket ID is found:

- Fetch the ticket via Jira MCP: `mcp__jira__jira_get_issue`
- Extract: summary, description, acceptance criteria, and any Figma links in the description or attachments

If no ticket ID is found, skip this step silently.

### 1.5 Figma Designs (Conditional)

This step runs only when BOTH conditions are true:

1. The Jira ticket (from step 1.4) contains Figma links
2. The PR modifies UI files (`.tsx`, `.css`, `.scss`, `.html`, or files in component/view directories)

**If both conditions are met:**

- Check if Figma MCP tools are available
- If available: use Figma MCP to examine the relevant designs and extract expected UI behavior, layout, and component specifications
- If NOT available: **STOP and notify the user** with this message:

  > This PR has UI changes and the Jira ticket links to Figma designs, but the Figma MCP is not available. Would you like to continue without Figma context, or set up the Figma MCP first?

  Wait for the user's response before proceeding.

**If either condition is false, skip this step silently.**

### 1.6 Ephemeral Environment (Conditional)

This step runs only when the PR modifies UI files.

**Search PR comments for an automated preview/deploy URL:**

```bash
gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
  --jq '.[] | select(.body | test("https://.*\\.vercel\\.app|https://.*\\.netlify\\.app|https://.*preview.*")) | .body'
```

**If a preview URL is found:**

- Check if Playwright MCP tools are available
- If available: use Playwright MCP to navigate to the preview URL, take screenshots of relevant pages, and verify UI behavior
- If NOT available: **STOP and notify the user** with this message:

  > This PR has a preview environment at {url}, but the Playwright MCP is not available. Would you like to continue without visual inspection, or set up the Playwright MCP first?

  Wait for the user's response before proceeding.

**If no preview URL is found or the PR does not modify UI files, skip this step silently.**

### 1.7 Repo Structure

Build a mental model of the codebase architecture to assess whether changed code is in the right place:

- Check for `CLAUDE.md` at the repo root and in directories containing changed files
- Check for `README.md` in relevant directories
- If no docs exist, auto-discover: list top-level directories, inspect `package.json`, `tsconfig.json`, folder naming conventions, and module boundaries
- Use this understanding to evaluate architectural fit during the review phase

### 1.8 Existing Reviews

Fetch existing review comments to avoid duplicating feedback that has already been given:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews --paginate \
  --jq '.[] | {user: .user.login, state: .state, body: .body}'
```

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate \
  --jq '.[] | {user: .user.login, path: .path, line: .line, body: .body}'
```

If another reviewer has already raised a point, do not repeat it. You may reference or build on existing feedback if you have something to add.

### Parallelization

Run independent calls in parallel:

- Steps 1.1, 1.2, 1.7, and 1.8 have no dependencies — run them all in parallel.
- Step 1.3 depends on 1.2 (needs the file list).
- Step 1.4 depends on 1.1 (needs the PR body/title for ticket ID extraction).
- Step 1.5 depends on 1.4 (needs Jira for Figma links) and 1.2 (needs diff to know if UI files changed).
- Step 1.6 depends on 1.2 (needs diff to know if UI files changed).

---

## Phase 2: Review

With all context gathered, review the diff file by file. Generate comments using conventional comment labels.

### Review Areas

Examine every changed file for:

- **Correctness** — logic errors, off-by-one, race conditions, null/undefined handling, unhandled edge cases
- **Security** — injection vulnerabilities, auth bypass, secrets in code, OWASP top 10 concerns
- **Type safety** — proper typing, no unnecessary `any`, correct generic constraints, exhaustive checks
- **Acceptance criteria** — does the code satisfy the requirements from the Jira ticket? Are any criteria missed?
- **Design fidelity** — does the UI match the Figma designs? (only if Figma context was gathered in Phase 1)
- **UI behavior** — does the ephemeral environment look and behave correctly? (only if ephemeral env was inspected in Phase 1)
- **Architectural fit** — is the code in the right place? Does it follow the repo's module boundaries and conventions?
- **Code cleanliness and structure** — single responsibility, appropriate abstractions, no god functions, sensible decomposition
- **Readability** — clear naming, logical flow, no unnecessary complexity, comments where non-obvious
- **Naming and duplication** — consistent naming conventions, DRY where appropriate (but not over-abstracted)
- **Framework best practices** — flag outdated or unnecessary patterns per the guidelines below
- **Test coverage** — are new behaviors tested? Are edge cases covered? Are test assertions meaningful?

#### Framework-Specific Best Practices

**React:**
- Do NOT use `useMemo` or `useCallback` — the React 19 compiler handles memoization; this is team policy
- `useEffect` is for externalities outside the React ecosystem and should be very rare — flag any that can be replaced by derived state, event handlers, or computed values during render
- Don't store computed values in state — store the simplest state possible and compute on each render
- Don't duplicate state between `useState` and `useRef` — pick one based on whether the component needs to re-render
- Use Apollo `useQuery`/`useSuspenseQuery` hoisting over prop drilling — pass IDs down and let child components declare their own data needs via Apollo's normalized cache
- Keep components small and focused — if a component's logic is too complex to decompose, it needs to be rethought
- Use named exports, not default exports
- File naming: PascalCase for components and component folders, camelCase for everything else

**GraphQL Schema & Resolvers:**
- All feature work begins with thoughtful schema design — the schema represents how we *want* to consume data, not the current database structure
- Zero tolerance for technical debt in the GraphQL layer — don't propagate database mess (e.g., opaque field names, ambiguous types) to GraphQL; create translation layers in the ORM or mappers
- Don't prefix entity fields with the type name — use `id` not `assetId`, `address` not `locationAddress`
- Always use `ID!` type for primary keys — never `Int` or `String`
- Use camelCase everywhere — properties, inputs, entities, return types
- Use purpose-built, single-responsibility resolvers — `updateAssetReportProblemUserId` not a generic `updateAsset`
- Return the mutated object from mutations (not booleans or void) — this lets Apollo's normalized cache update the UI automatically without refetching
- Use Input types for mutations with more than two properties — ID as a separate required param, input fields optional
- Use `"""Description"""` schema comments (not `#`) — focus on "why", these surface in GraphQL explorers
- Move business logic to the backend — if the frontend needs multiple queries or calculations to determine display data, it belongs in a resolver

**Apollo Client:**
- Leverage the normalized cache as state management — components should query for their own data via Apollo rather than receiving it as props
- Define reusable queries and mutations in `lib/graphql/src/operations/{domain}/` — if a query is only used by one component, inline `gql()` in the component file is fine; if it's shared, centralize it to stay DRY
- Prefer cache eviction (`cache.evict` + `cache.gc()`) or `update` functions over `refetchQueries` for post-mutation cache consistency
- Flag missing `loading`/`error` handling on `useQuery`/`useMutation` (less relevant for `useSuspenseQuery` where Suspense/ErrorBoundary handle this)
- Load as little data as possible to render the current screen — "how little data can I get away with?"
- Never load more than 1000 of any entity at a time — do filtering, sorting, and paging in the API, always search via the API
- Flag queries that fetch fields not used by the requesting component (over-fetching)
- Always name operations — anonymous queries break caching, codegen, and debugging

### Conventional Comment Labels

Every comment MUST begin with one of these labels:

| Label | Blocking | When to Use |
|-------|----------|-------------|
| `praise:` | n/a | Something done well — be genuine and specific |
| `nit (non-blocking):` | `(non-blocking)` | Trivial preference — formatting, naming style |
| `suggestion (non-blocking):` | `(non-blocking)` unless stated otherwise | A concrete improvement the author can consider |
| `issue:` | blocking | Something genuinely broken, insecure, or incorrect |
| `question (non-blocking):` | `(non-blocking)` | Asking for clarification or the reasoning behind a choice |
| `thought (non-blocking):` | `(non-blocking)` | Thinking out loud — a consideration, not a demand |
| `chore (non-blocking):` | `(non-blocking)` | Cleanup or maintenance task |

### Comment Philosophy

- **Trust the author.** Assume good intent and give latitude. Use `question:`, `suggestion:`, and `thought:` to open a dialogue rather than dictating. Reserve `issue:` for things that are genuinely broken, insecure, or incorrect.
- **Ask "why" before asserting "wrong."** If something looks off but you are not certain it is a bug, use `question:` to ask about the intent rather than `issue:` to declare it wrong.
- **Always clarify blocking status** on non-issue comments by including `(non-blocking)` between the label and the colon, e.g. `suggestion (non-blocking):`.
- **Be specific and actionable.** Explain what the problem is, why it matters, and what to do about it. Do not leave vague comments like "this could be improved."
- **Praise genuinely.** When something is done well — a clean abstraction, thorough error handling, good test coverage — say so with a `praise:` comment. Be specific about what is good.
- **Don't pile on.** If the same pattern appears in multiple places, comment once and note "same pattern appears in {N} other locations" rather than leaving duplicate comments.
- **Check existing reviews.** Do not repeat feedback that another reviewer has already given. Build on it if you have something to add.

### Code Suggestion Blocks

When a `nit:` or `suggestion:` comment has a concrete fix, include a GitHub suggestion block so the author can apply it with one click:

````
suggestion (non-blocking): consider extracting this into a named constant for clarity

```suggestion
const MAX_RETRY_COUNT = 3;
```
````

Only include suggestion blocks when the fix is unambiguous and self-contained. Do not use suggestion blocks for changes that span multiple files or require broader refactoring.

### Comment Structure

Each comment follows this structure:

```
{label} {(non-blocking) if applicable}: {description}

{optional: explanation, context, rationale, or suggestion block}
```

Examples:

```
issue: this fetch call has no error handling — a network failure will crash the component

Consider wrapping in a try/catch and setting an error state.
```

```
question (non-blocking): is this intentionally using a loose equality check here?

Strict equality (`===`) is used everywhere else in this file. If this is intentional, a comment explaining why would help future readers.
```

```
praise: clean separation of the validation logic into its own pure function — makes this very testable
```

---

## Phase 3: Preview & Approval

Before posting anything to GitHub, present ALL comments to the user for review. Nothing is posted without explicit approval.

### Present the Review

Display the full review in this format:

```
## Review Preview

**Verdict: {Approve | Request Changes}** ({N} comments: {X} blocking, {Y} non-blocking)

---

### 1. {label} ({blocking status}) — `{file_path}:{line}`

{comment body, including suggestion blocks if any}

---

### 2. {label} ({blocking status}) — `{file_path}:{line}`

{comment body}

---
(repeat for all comments)
---

### Top-Level Summary

{The summary that will be posted as the review body. Praise first, then numbered remaining items, blockers called out explicitly.}
```

### Verdict Logic

- **Approve** — if there are zero `issue:` comments
- **Request Changes** — if there are one or more `issue:` comments

### User Options

After presenting the preview, ask:

> Review ready. You can:
> 1. **Approve** — post as shown
> 2. **Edit** — tell me which comments to change, remove, or relabel
> 3. **Change verdict** — override the suggested verdict
> 4. **Cancel** — discard the review entirely
>
> What would you like to do?

If the user chooses to edit, apply their changes and re-display the updated preview. Iterate until the user explicitly approves. Do NOT post until you receive explicit approval.

---

## Phase 4: Post Review

Once the user approves, post the review using the GitHub Reviews API.

### Step 1: Get the Commit SHA

Use the `head_sha` captured during Phase 1 step 1.1. If for any reason it was not captured, fetch it:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number} --jq '.head.sha'
```

### Step 2: Map Comment Lines to Diff Positions

For each comment, determine the correct `line` and `side` values:

- `path` — the file path relative to the repo root
- `line` — the line number in the file (right side of diff for new/modified lines)
- `side` — `RIGHT` for lines that exist in the new version of the file, `LEFT` for lines that only exist in the old version (deleted lines)

For multi-line suggestions, also include `start_line` and `start_side` to define the range.

### Step 3: Build the Comments JSON

Write the complete review request body to a temporary file. Include `commit_id`, `event`, `body`, and `comments` all in one JSON object — do NOT mix `--input` with `-f` flags, as they can conflict.

```bash
cat > /tmp/review-comments.json << 'COMMENTS_EOF'
{
  "commit_id": "{sha}",
  "event": "{APPROVE|REQUEST_CHANGES}",
  "body": "{top-level summary}",
  "comments": [
    {
      "path": "src/foo.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "suggestion (non-blocking): consider using a named constant\n\n```suggestion\nconst MAX_RETRY_COUNT = 3;\n```"
    }
  ]
}
COMMENTS_EOF
```

### Step 4: Create and Submit the Review

Post the review with all inline comments in a single API call:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --input /tmp/review-comments.json
```

The `event` field maps to the verdict:

- `Approve` -> `APPROVE`
- `Request Changes` -> `REQUEST_CHANGES`

### Step 5: Confirm Success

After posting, confirm to the user:

> Review posted: {verdict} with {N} inline comments on {owner}/{repo}#{pr_number}

If the API call fails, show the full error and offer to:

1. Retry the request
2. Save the review as a local JSON file for manual posting later

### Fallback: Pending Review Workflow

If the user asks for a dry run or wants to test without posting a visible review:

1. Create the review without the `event` field (creates a PENDING review, invisible to other users). Build the JSON file the same way as Step 3, but omit the `event` field:
   ```bash
   gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
     --input /tmp/review-comments.json
   ```

2. Report the review ID to the user.

3. Offer to submit or delete:
   - **Submit:**
     ```bash
     gh api -X POST repos/{owner}/{repo}/pulls/{pr_number}/reviews/{review_id}/events \
       -f event="{APPROVE|REQUEST_CHANGES}"
     ```
   - **Delete:**
     ```bash
     gh api -X DELETE repos/{owner}/{repo}/pulls/{pr_number}/reviews/{review_id}
     ```

### Cleanup

After successful posting (or cancellation), remove the temporary file:

```bash
rm -f /tmp/review-comments.json
```
