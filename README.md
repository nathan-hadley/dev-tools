# dev-tools

Personal development utilities: shell scripts, aliases, and AI agent rules.

## Structure

```
scripts/        Shell scripts and aliases
env-pool/       Isolated iOS/Android environments for parallel Maestro test development
agent-rules/    Workflow rules for AI coding agents (Claude, Cursor)
```

## Scripts

- **aliases.sh** - Shell aliases and helpers (sourced in `.zshrc`)
- **gh-weekly-prs.sh** - Weekly PR report generator

## env-pool

CLI toolkit for creating on-demand, isolated iOS/Android environments for parallel Maestro test development.

```
env-pool setup                          # One-time initialization
env-pool build [ios|android|all]        # Build .app and .apk artifacts
env-pool create <branch>                # Create a new environment
env-pool run-maestro <id> <flow> [--platform android]
                                        # Run a Maestro test flow
env-pool release <id>                   # Tear down an environment
env-pool gc                             # Clean up leaked environments
env-pool status                         # Show all active environments
```

## Agent Rules

- **workflows.md** - Development workflows (PR process, Jira acceptance criteria)

### Integration

**Claude Code**: Referenced from `~/.claude/CLAUDE.md`

**Cursor**: Duplicated in `~/.cursor/rules/workflows.mdc` with `alwaysApply: true`
