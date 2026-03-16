# Workflow — Headless Prompts & Scripts

This directory contains headless prompts and automation scripts for the Chama SDLC pipeline. These are used by the compose orchestrator and can be run independently.

Interactive commands live in `skills/` and are invoked as `/chama:init`, `/chama:ideas`, `/chama:architect`, `/chama:code`, `/chama:review-loop`.

## Prompts (compose — headless)

- `prompt-compose-coder.md`: Coder adapted for `-p` mode (steps 0-4, no PR, no push).
- `prompt-compose-simplify.md`: Code simplification adapted for `-p` mode.
- `prompt-commit-reviewer.md`: Review of a specific commit.
- `prompt-pr-reviewer.md`: PR review via `/code-review`.
- `prompt-generate-specs.md`: Batch Spec generation from ideas.

## Scripts

- `scripts/install-hooks.sh`: Install local git hooks.
- `scripts/run-commit-reviewer.sh`: Trigger commit reviewer (foreground/background).
- `scripts/run-pr-reviewer.sh`: Trigger PR reviewer (foreground/background).
- `scripts/chama-pipeline.sh`: Orchestrate the full 5-phase cycle.

## Compose orchestration

After ideas and architecture are done, run compose to process multiple tasks:

```bash
# Process up to 3 tasks (default)
chama-pipeline

# Process up to 5 tasks, with up to 6 review rounds each
MAX_TASKS=5 MAX_REVIEW_ROUNDS=6 chama-pipeline

# Continue even if review fails on a task
STOP_ON_REVIEW_FAILURE=false chama-pipeline
```

The compose orchestrates 5 phases per task:
1. **Coder** (Claude) — identifies task, creates branch, implements, validates, commits
2. **Simplify** (Claude) — reviews and simplifies changed code
3. **PR** (shell) — push, create PR, move to In Review, wait for CI
4. **PR Reviewer** (Claude) — structured PR review
5. **Review-loop** (Claude) — handles comments, merge, move to Done

## Useful commands

### Install hooks (once per clone)
```bash
chama/workflow/scripts/install-hooks.sh
```

### Run commit reviewer manually
```bash
chama/workflow/scripts/run-commit-reviewer.sh "$(git rev-parse HEAD)" --background
```

### Run PR reviewer manually
```bash
chama/workflow/scripts/run-pr-reviewer.sh "<PR_NUMBER>" --background
```

### Inspect reviews in terminal
```bash
REPO=$(yq '.project.repo' .chama.yml)
gh pr view "<PR_NUMBER>" --comments
gh api "repos/$REPO/pulls/<PR_NUMBER>/reviews"
gh api "repos/$REPO/pulls/<PR_NUMBER>/comments"
```

## Artifacts

All artifacts are stored under directories configured in `.chama.yml`:
- Progress logs: `artifacts.progress_dir` (default: `.chama/progress`)
- Reviews: `artifacts.reviews_dir` (default: `.chama/reviews`)

## Knowledge paths

Projects can configure `knowledge_paths` in `.chama.yml` to feed domain documentation into the architect:

```yaml
knowledge_paths:
  - "docs/architecture/"
  - "docs/domain/"
  - "specs/"
```

The architect reads files with extensions `.md`, `.yml`, `.yaml`, `.txt` from each path, applying progressive limits:

| Condition | Behavior |
|-----------|----------|
| ≤10 files **and** ≤100KB | Read normally |
| 11-15 files **or** 100-200KB | Read with **WARNING** suggesting more specific paths |
| >15 files **or** >200KB | **Skip path entirely** with **CRITICAL** alert |

- Paths that don't exist are ignored silently.
- Paths are relative to the project root; `../` is not supported.

## Spec template resolution

The architect and generate-specs workflows resolve the Spec template with a fallback chain:

1. **Project override**: `.chama/templates/spec.md` (if it exists)
2. **Default template**: `templates/spec.md.default` (in the Chama plugin)

To customize the Spec template for your project, copy `templates/spec.md.default` to `.chama/templates/spec.md` and edit it. The resolution logic lives in `scripts/resolve-spec-template.sh`.

## Scope rules

- Implementation must follow the Spec.
- Comments outside the Spec: respond with justification and don't implement.
- Avoid broad refactoring in execution routines.
- Always register pending scope items, risks and trade-offs.
