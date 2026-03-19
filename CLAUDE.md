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

This project uses automatic versioning tied to the Spec lifecycle. The version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` always reflects the current pipeline state.

**Schema:** `MAJOR.MINOR.PATCH-draft.N` (semver + draft suffix). Draft versions indicate work-in-progress; stable versions (no suffix) indicate a completed Spec.

**Constraint:** Only one Spec may be active at a time. Do not start a new Spec while another has draft versions in progress.

### When to bump

#### 1. Architect creates a Spec (`/chama:architect`)

1. Read the current stable version (ignore any `-draft.*` suffix) from `.claude-plugin/plugin.json`.
2. Increment the minor: if stable is `1.2.0`, next minor is `1.3.0`.
3. Add the field `**Version:** X.Y.x` (e.g., `**Version:** 1.3.x`) to the Spec issue body.
4. Run: `scripts/bump-version.sh X.Y.0-draft.0` (e.g., `scripts/bump-version.sh 1.3.0-draft.0`).

#### 2. Phase completed (`/chama:review-loop`)

When a phase is moved to Done:

1. Count the total number of closed/Done phases for this Spec (N).
2. Run: `scripts/bump-version.sh X.Y.0-draft.N` (e.g., if 2 phases are done: `scripts/bump-version.sh 1.3.0-draft.2`).

#### 3. Spec closed (last phase completed)

When the last phase of a Spec is completed and the Spec is auto-closed:

1. Run: `scripts/bump-version.sh X.Y.0` (e.g., `scripts/bump-version.sh 1.3.0`) — no draft suffix.

### Calculation rules

- The **minor** is always based on the latest stable version (without `-draft.*` suffix). To find it: read the version from `plugin.json`, strip any `-draft.*` suffix, then increment minor.
- The **draft count** (N) equals the number of phases with status Done for the current Spec.
- The **patch** is always `0` (patch bumps are not used in the Spec lifecycle).
- Rollback: reopening a phase does not decrement the version.

### Script reference

`scripts/bump-version.sh <version>` — reads `versioning.files` from `.chama.yml`, updates the `version` field in each configured JSON file, and creates a commit (`chore: bump version to <version>`). The script is idempotent: running it twice with the same version produces no error and no duplicate commit.

## When editing this plugin

- Skills in `skills/` should read config from `.chama.yml`, never hardcode repo/owner/project
- Headless prompts in `workflow/` follow the same pattern
- Scripts discover the chama plugin path dynamically (local `chama/` or `~/.claude/plugins/chama/`)
- All GitHub API calls use `$REPO`, `$OWNER`, `$PROJECT_NUM` variables
