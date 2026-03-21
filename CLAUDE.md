# Chama — SDLC Plugin for Claude Code

Chama is a generic SDLC pipeline orchestrator that works with any project via `.chama.yml` + `CLAUDE.md`.

## Architecture

- `skills/` — Slash commands (interactive, invoked by user as `/chama:<skill>`)
- `workflow/` — Headless prompts for compose/automation pipelines
- `agent/` — Docker runtime for isolated AI agent execution
- `templates/` — Templates used by `/chama:init` and `/chama:new-project` for project onboarding and bootstrap
- `scripts/` — Utility scripts (GitHub label setup, etc.)

## Key patterns

- All project-specific config comes from `.chama.yml` in the target project root
- GitHub Issues are used as storage for ideas, Specs, and phases (no local files)
- Quality gates are dynamic, read from `.chama.yml` `tech_stack.components[].quality_gates`
- Environment variables (`CHAMA_REPO`, `CHAMA_OWNER`, `CHAMA_PROJECT_NUMBER`) override `.chama.yml`
- Board statuses are configurable via `github.board_statuses` in `.chama.yml` (defaults: Todo, In Progress, In Review, Done)
- Multi-language support via `project.language` in `.chama.yml` (pt-BR or en)
- `knowledge_paths` in `.chama.yml` feeds domain docs (`.md`, `.yml`, `.yaml`, `.txt`) into the architect with progressive limits
- Spec template is customizable: `.chama/templates/spec.md` overrides the default `templates/spec.md.default`

## Command flow

```
/chama:new-project -> guided bootstrap: idea -> synthesis -> local foundation (.chama.yml, CLAUDE.md, docs/, structure)
       ↓ (optional)
/chama:init        -> onboard project (GitHub labels, board, project number, .chama/templates/)
       ↓
/chama:ideas       -> brainstorm -> GitHub Issue (label: idea)
       ↓
/chama:architect   -> idea Issue -> Spec Issue + phase Issues (reads knowledge_paths + spec template)
       ↓
/chama:code        -> phase Issue (Todo) -> implement -> PR
       ↓
/chama:review-loop -> PR comments -> fix/respond -> merge
```

**Note:** `/chama:new-project` is local-first — it generates project foundation on the local filesystem without requiring GitHub. It composes with `/chama:init` (which handles GitHub setup) but does not depend on it. Projects can start with either command depending on whether the project already exists.

## Versioning

**Schema:** `MAJOR.MINOR.PATCH` (standard semver).

Version bumps are manual and controlled by the developer via `make bump-version`. Multiple Specs can run in parallel without version conflicts.

### How to bump

Run `make bump-version`. The command will:
1. Show current version and commits since last bump
2. Generate a categorized changelog via LLM (`claude --print`)
3. Ask for bump type (patch/minor/major)
4. Ask for confirmation
5. Update version files + CHANGELOG.md + commit

If the `claude` CLI is not available, falls back to a plain commit list.

### Script reference

- `make bump-version` — interactive bump with LLM changelog (entry point)
- `scripts/bump-version.sh <version> [--changelog "message"]` — low-level: updates version files from `.chama.yml`, optionally prepends CHANGELOG.md entry, creates commit. Idempotent (skips if version already matches and changelog entry already exists).

## When editing this plugin

- Skills in `skills/` should read config from `.chama.yml`, never hardcode repo/owner/project
- Headless prompts in `workflow/` follow the same pattern
- Scripts discover the chama plugin path dynamically (local `chama/` or `~/.claude/plugins/chama/`)
- All GitHub API calls use `$REPO`, `$OWNER`, `$PROJECT_NUM` variables
