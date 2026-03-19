# Changelog

## [1.4.0] - 2026-03-19

### Added
- **`/chama:new-project`**: Guided bootstrap for new projects — transforms a free-form idea into a complete local foundation (`.chama.yml`, `CLAUDE.md`, `docs/PROJECT_BRIEF.md`, directory structure) (#25)
  - 5-stage flow: discovery → adaptive questions → synthesis → generation → summary
  - 10-field minimum contract for synthesis
  - Merge mode with per-artifact preservation for existing projects
  - Optional post-generation steps: review, commit, remote repo, `/chama:init`
- **`templates/PROJECT_BRIEF.md.template`**: Reference template for project brief generation (#25)
- Pipeline documentation updated with new-project as optional first step (#26)

### Changed
- Plugin description updated: "Bootstrap -> Idea -> Spec -> Code -> Review -> Merge" (#26)
- Command flow in `CLAUDE.md` now shows full pipeline with arrows and local-first note (#26)

### Fixed
- Template discovery aligned with `resolve-spec-template.sh` chain (#28)
- Git remote URL parsed into `owner/repo` format for `project.repo` inference (#28)
- Spec template copy guarded with existence check (#28)
- Conditional `git add` to avoid pathspec errors on missing paths (#28)
- Word-count fallback heuristic for adaptive questions (#28)

## [1.3.0] - 2026-03-16

### Added
- **Auto-close Spec**: Review-loop automatically closes the Spec issue when all phases are completed (#15)
- **Automatic versioning**: `scripts/bump-version.sh` + `versioning` section in `.chama.yml` for lifecycle-tied version bumps (#20)
- **Versioning instructions**: `CLAUDE.md` documents when and how to bump versions (architect → draft, phase done → increment, spec close → stable) (#21)

### Fixed
- PR reviewer prompt now works in headless mode (replaced slash command with full review prompt)
- CI check no longer warns when no checks are configured
- Architect project item lookup uses retry + sleep to handle GitHub API indexing delay

## [1.2.0] - 2026-03-16

### Added
- **Knowledge paths**: `knowledge_paths` in `.chama.yml` feeds domain docs into the architect with progressive limits (≤10/100KB ok, 11-15/200KB warning, >15/>200KB skip) (#10)
- **Customizable Spec template**: `.chama/templates/spec.md` overrides the default; fallback to `templates/spec.md.default` (#9)
- **Unified Spec template**: `scripts/resolve-spec-template.sh` resolves template with fallback chain (#9)
- Init creates `.chama/templates/` directory and shows knowledge_paths tip (#11)
- Knowledge paths support added to `prompt-generate-specs.md`

### Fixed
- Architect uses `--body-file` instead of inline heredoc to avoid shell parse errors
- Architect looks up project items by issue number instead of URL
- `resolve-spec-template.sh` supports self-hosting (running from chama repo itself)
- Absolute path for `resolve-spec-template.sh` calls to avoid CWD issues

## [1.1.0] - 2026-03-16

### Added
- **Configurable board statuses**: `github.board_statuses` in `.chama.yml` with defaults (Todo, In Progress, In Review, Done) (#7)
- **Board sync script**: `scripts/sync-board-statuses.sh` validates board configuration against `.chama.yml` (#7)
- **Pre-flight validation**: `chama-pipeline.sh` checks board statuses and shows pending item count before starting (#7)
- **Self-hosting**: `.chama.yml` for the Chama project itself (#8)

### Changed
- Renamed `run-compose.sh` → `chama-pipeline.sh` (#8)
- Renamed shell alias `chama-compose` → `chama-pipeline`

### Removed
- **Epic concept**: Removed from architect, coder, compose, init, and docs — was created but never consumed by any workflow (#7)

### Fixed
- Standardized casing: `"In progress"` → `"In Progress"` across all skills/workflows
- All status names read from `.chama.yml` via `jq --arg` (safe for special characters)
- All `yq` board_statuses reads have `|| echo 'Default'` fallback
- `sync-board-statuses.sh` accepts config path arg, uses `grep -F` for fixed-string matching
- Plugin discovery supports Claude Code cache paths (`~/.claude/plugins/cache/`)
- Dependency check shows all missing tools at once with install links

## [1.0.0] - 2026-03-14

### Added
- Plugin structure with skills (`/chama:init`, `/chama:ideas`, `/chama:architect`, `/chama:code`, `/chama:review-loop`)
- Marketplace support for CLI installation (`/plugin marketplace add rafaelportugal/chama`)
- Configurable default branch via `github.default_branch` in `.chama.yml`
- Headless compose orchestrator with 5-phase pipeline
- Docker agent for isolated execution
- Multi-language support (pt-BR, en)
- MIT license
