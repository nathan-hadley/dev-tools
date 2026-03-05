# dev-tools

Personal development utilities: shell scripts, aliases, and AI agent rules.

## Structure

```
scripts/        Shell scripts and aliases
agent-rules/    Workflow rules for AI coding agents (Claude, Cursor)
```

## Scripts

- **aliases.sh** - Shell aliases and helpers (sourced in `.zshrc`)
- **wtree.sh** - Git worktree creation helper
- **wtmerge.sh** - Git worktree merge and cleanup
- **gh-weekly-prs.sh** - Weekly PR report generator

## Agent Rules

- **workflows.md** - Development workflows (PR process, Jira acceptance criteria)

### Integration

**Claude Code**: Referenced from `~/.claude/CLAUDE.md`

**Cursor**: Duplicated in `~/.cursor/rules/workflows.mdc` with `alwaysApply: true`
