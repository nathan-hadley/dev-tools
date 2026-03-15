# dev-tools

Personal development utilities: shell scripts, aliases, and AI agent rules.

## Structure

```
scripts/        Shell scripts and aliases
env-pool/       Isolated iOS/Android environments for Maestro test authoring
agent-rules/    Workflow rules for AI coding agents (Claude, Cursor)
```

## Scripts

- **aliases.sh** - Shell aliases and helpers (sourced in `.zshrc`)
- **gh-weekly-prs.sh** - Weekly PR report generator

## env-pool

CLI toolkit for creating on-demand, isolated iOS/Android environments for Maestro
test authoring. The long-term direction is to keep drafting and app exploration
parallelizable while treating actual flow execution as a serialized verification
step.

```
env-pool setup                          # One-time initialization
env-pool build [ios|android|all]        # Build .app and .apk artifacts
env-pool create <branch>                # Create a new environment
env-pool preview <id>                   # Boot/connect iOS simulator for inspection
env-pool verify <id> <flow> [--platform android]
                                        # Run a serialized Maestro verification
env-pool release <id>                   # Tear down an environment
env-pool gc                             # Clean up leaked environments
env-pool status                         # Show all active environments
```

For agent-driven test development, prefer this mental model:

- Use `create` for isolated worktree + Metro setup.
- Use `preview` plus the iOS simulator MCP for accessibility-tree inspection and
  manual feature walkthroughs.
- Use preview for one-time session setup too: connect to Metro, dismiss Expo UI,
  and log in with the existing repo test creds.
- Use `verify` only when you want a real Maestro run.
- Avoid spending `verify` on login/bootstrap unless login itself is what the test
  is actually about.
- Treat actual Maestro execution as the expensive/shared step, not the main discovery
  loop.

## Agent Rules

- **workflows.md** - Development workflows (PR process, Jira acceptance criteria)

### Integration

**Claude Code**: Referenced from `~/.claude/CLAUDE.md`

**Cursor**: Duplicated in `~/.cursor/rules/workflows.mdc` with `alwaysApply: true`
