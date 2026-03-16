# Chama — SDLC Plugin for Claude Code

Chama is a generic SDLC pipeline orchestrator that works with any project via `.chama.yml` + `CLAUDE.md`.

## Architecture

- `skills/` — Slash commands (interactive, invoked by user as `/chama:<skill>`)
- `workflow/` — Headless prompts for compose/automation pipelines
- `agent/` — Docker runtime for isolated AI agent execution
- `templates/` — Templates used by `/chama:init` for project onboarding
- `scripts/` — Utility scripts (GitHub label setup, etc.)

## Key patterns

- All project-specific config comes from `.chama.yml` in the target project root
- GitHub Issues are used as storage for ideas, Specs, and phases (no local files)
- Quality gates are dynamic, read from `.chama.yml` `tech_stack.components[].quality_gates`
- Environment variables (`CHAMA_REPO`, `CHAMA_OWNER`, `CHAMA_PROJECT_NUMBER`) override `.chama.yml`
- Board statuses are configurable via `github.board_statuses` in `.chama.yml` (defaults: Todo, In Progress, In Review, Done)
- Multi-language support via `project.language` in `.chama.yml` (pt-BR or en)

## Command flow

```
/chama:init       -> onboard project (.chama.yml, labels, project)
/chama:ideas      -> brainstorm -> GitHub Issue (label: idea)
/chama:architect  -> idea Issue -> Spec Issue + phase Issues
/chama:code       -> phase Issue (Todo) -> implement -> PR
/chama:review-loop -> PR comments -> fix/respond -> merge
```

## When editing this plugin

- Skills in `skills/` should read config from `.chama.yml`, never hardcode repo/owner/project
- Headless prompts in `workflow/` follow the same pattern
- Scripts discover the chama plugin path dynamically (local `chama/` or `~/.claude/plugins/chama/`)
- All GitHub API calls use `$REPO`, `$OWNER`, `$PROJECT_NUM` variables
