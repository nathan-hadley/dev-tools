---
name: standup
description: Generate a high-level summary of GitHub activity since last standup for use in daily standup meetings.
---

# Standup Summary

Generate a concise GitHub activity summary for daily standup.

## Determine Time Range

- Default: since the last weekday morning (e.g., on Monday, look back to Friday; on Tuesday, look back to Monday).
- If the user specifies a different range, use that instead.
- Format the date as `YYYY-MM-DD` for the GitHub API queries.

## Gather Activity

Run these queries in parallel using `gh api`:

**PRs authored:**
```bash
gh api search/issues --method GET \
  -f q="author:@me updated:>=$DATE type:pr" \
  -f per_page=50 \
  --jq '.items[] | "- **\(.repository_url | split("/") | .[-1])#\(.number)**: \(.title) [\(.state)] (updated \(.updated_at | split("T")[0]))"'
```

**PRs reviewed or commented on:**
```bash
gh api search/issues --method GET \
  -f q="commenter:@me updated:>=$DATE type:pr -author:@me" \
  -f per_page=50 \
  --jq '.items[] | "- **\(.repository_url | split("/") | .[-1])#\(.number)**: \(.title) [\(.state)]"'
```

**Issues authored or commented on:**
```bash
gh api search/issues --method GET \
  -f q="involves:@me updated:>=$DATE type:issue" \
  -f per_page=50 \
  --jq '.items[] | "- **\(.repository_url | split("/") | .[-1])#\(.number)**: \(.title) [\(.state)]"'
```

**Commits pushed (across all orgs):**
```bash
gh api search/commits --method GET \
  -f q="author:@me committer-date:>=$DATE" \
  -f per_page=50 \
  --jq '.items[] | "- **\(.repository.name)**: \(.commit.message | split("\n")[0])"'
```

## Present Summary

Summarize the activity in 2-4 concise bullet points suitable for a standup update:

- Group related work thematically (e.g., "auth fixes", "test stability")
- Note what was merged/closed vs. still open
- Mention review activity with approximate count and repos
- Keep it brief. This is for speaking aloud, not a written report
