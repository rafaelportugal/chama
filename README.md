# Chama

**SDLC pipeline orchestrator for Claude Code** — Bootstrap -> Idea -> Spec -> Code -> Review -> Merge.

Chama is a Claude Code plugin that brings a full development lifecycle workflow to any project. Configure once with `.chama.yml` and `CLAUDE.md`, then use slash commands to drive your development.

The name "chama" combines fire with the act of "calling/invoking" — perfect for a CLI of commands.

## Quick Start

### 1. Install

```bash
# Add the marketplace
/plugin marketplace add rafaelportugal/chama

# Install the plugin
/plugin install chama@chama
```

### 2. Bootstrap or onboard your project

```
# Option A: Create a new project from scratch (local-first)
/chama:new-project

# Option B: Onboard an existing project (GitHub setup)
/chama:init
```

### 3. Start building

```
/chama:ideas        # Brainstorm and create structured ideas
/chama:architect N  # Transform idea #N into Spec + phases
/chama:code         # Execute next task from backlog
/chama:review-loop  # Process PR review comments
```

## Commands

| Command | Description |
|---------|-------------|
| `/chama:new-project` | Guided bootstrap — idea -> synthesis -> local foundation (`.chama.yml`, `CLAUDE.md`, `README.md`, `LICENSE`, `docs/`) |
| `/chama:adopt` | Adopt existing repo — analyze stack, generate diagnosis and transformation plan |
| `/chama:init` | Project onboarding — creates `.chama.yml`, GitHub labels, project board |
| `/chama:ideas` | Ideas studio — brainstorm with Product Lead + Designer personas |
| `/chama:architect` | Idea -> Spec + phases (all as GitHub Issues) |
| `/chama:code` | Execute next Todo task with quality gates |
| `/chama:review-loop` | Handle PR comments in loop, scoped by Spec |
| `/chama:gate-check` | Run Critical Gate analysis on working tree or specific commit |

## Command Flow

```
/chama:new-project -> guided bootstrap: idea -> synthesis -> local foundation
       | (optional)
/chama:init        -> onboard project (GitHub labels, board, project number)
       |
/chama:ideas       -> brainstorm -> GitHub Issue (label: idea)
       |
/chama:architect   -> idea Issue -> Spec Issue + phase Issues
       |
/chama:code        -> phase Issue (Todo) -> implement -> PR
       |
/chama:review-loop -> PR comments -> fix/respond -> merge
```

**Note:** `/chama:new-project` is local-first — it generates project foundation on the local filesystem without requiring GitHub. It composes with `/chama:init` (which handles GitHub setup) but does not depend on it.

## Configuration

### `.chama.yml`

Per-project configuration file:

```yaml
project:
  name: "MyProject"
  description: "Brief description"
  repo: "owner/repo-name"
  language: "pt-BR"              # or "en"

github:
  owner: "owner"
  project_number: 1
  default_branch: "main"
  board_statuses:                    # optional — customize to match your board
    todo: "Todo"
    in_progress: "In Progress"
    in_review: "In Review"
    done: "Done"

tech_stack:
  summary: "Go backend + Next.js frontend"
  components:
    - name: "backend"
      path: "backend/"
      quality_gates:
        - "cd backend && make test"
        - "cd backend && make lint"
    - name: "frontend"
      path: "frontend/"
      quality_gates:
        - "cd frontend && npm run typecheck"
        - "cd frontend && npm run lint"

artifacts:
  progress_dir: ".chama/progress"
  reviews_dir: ".chama/reviews"

personas:
  - name: "Admin"
    description: "System administrator"

# knowledge_paths:                  # optional — feeds domain docs into /chama:architect
#   - "docs/"

critical_gates:
  enabled: true
  fail_mode: open
  severity_block:
    - CRITICAL
    - HIGH
  scan_points:
    - pre_commit
    - pre_merge

versioning:
  enabled: true
  strategy: "spec-lifecycle"
  files:
    - path: ".claude-plugin/plugin.json"
      jq_filter: ".version"

business_segment: "SaaS"
```

### Environment variable overrides

```bash
CHAMA_REPO="owner/repo"
CHAMA_OWNER="owner"
CHAMA_PROJECT_NUMBER="1"
CHAMA_DEFAULT_BRANCH="main"
```

## Features

### Knowledge Paths

Add `knowledge_paths` to `.chama.yml` to feed domain docs (`.md`, `.yml`, `.yaml`, `.txt`) into the architect. Progressive limits apply:
- **10 files / 100KB**: read all, no alerts
- **11-15 files / 101-200KB**: read all + warning
- **>15 files / >200KB**: skip with error

### Custom Spec Template

Override the default spec template by placing your own at `.chama/templates/spec.md`. The architect will use it instead of the built-in default.

### Critical Gate

Pre-commit and pre-merge safety checks for destructive operations. Scans diffs for database drops, secret exposure, infra changes, and ~40 built-in rules across 6 domains. Run standalone with `/chama:gate-check`.

### Versioning

Manual bump with LLM-generated changelog:

```bash
make bump-version
```

Shows commits since last bump, generates a categorized changelog via `claude --print`, asks for bump type (patch/minor/major), and commits.

## GitHub Issues as Storage

Instead of local `.md` files, ideas and Specs live as GitHub Issues:

| Label | Color | Description |
|-------|-------|-------------|
| `idea` | `#0E8A16` | Idea in brainstorm |
| `spec` | `#1D76DB` | Spec document |
| `phase` | `#FBCA04` | Implementation phase |

### Flow
```
/chama:ideas      -> creates Issue label:idea
/chama:architect  -> reads idea Issue -> creates spec + phase Issues
/chama:code       -> finds phase Issue status:Todo -> implements, creates PR
/chama:review-loop -> handles PR comments -> merges -> moves to Done
```

## Headless / Compose Mode

For automated execution without manual intervention.

### Setup

Add the `chama-compose` function to your `~/.zshrc` (or `~/.bashrc`):

```bash
# --- Chama SDLC Pipeline ---
_chama_find_plugin() {
  local root_dir
  root_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  # 1) Running from chama repo itself
  if [[ -d "$root_dir/workflow" && -f "$root_dir/.claude-plugin/plugin.json" ]]; then
    echo "$root_dir"; return 0
  fi

  # 2) Local chama/ subdir in project
  if [[ -d "$root_dir/chama/workflow" ]]; then
    echo "$root_dir/chama"; return 0
  fi

  # 3) Global plugin cache (versioned — pick latest)
  local cache_dir="$HOME/.claude/plugins/cache/chama/chama"
  if [[ -d "$cache_dir" ]]; then
    local latest
    latest=$(ls -d "$cache_dir"/*/ 2>/dev/null | sort -V | tail -1)
    if [[ -n "$latest" && -d "${latest}workflow" ]]; then
      echo "${latest%/}"; return 0
    fi
  fi

  # 4) Legacy global path
  if [[ -d "$HOME/.claude/plugins/chama/workflow" ]]; then
    echo "$HOME/.claude/plugins/chama"; return 0
  fi

  echo "ERROR: chama plugin not found." >&2
  return 1
}

chama-compose() {
  local chama_dir
  chama_dir=$(_chama_find_plugin) || return 1
  echo "Using chama plugin: $chama_dir"
  bash "$chama_dir/workflow/scripts/chama-pipeline.sh" "$@"
}
```

Then reload your shell:

```bash
source ~/.zshrc
```

The function resolves the plugin path automatically:
1. **Chama repo itself** — if you're inside the chama project
2. **Local `chama/` subdir** — if the project has a local copy
3. **Global plugin cache** — `~/.claude/plugins/cache/chama/chama/<version>/` (picks latest)
4. **Legacy global** — `~/.claude/plugins/chama/`

### Usage

```bash
# Run from any project with .chama.yml
chama-compose

# Limit to 1 task
MAX_TASKS=1 chama-compose

# Custom review rounds and failure behavior
MAX_TASKS=3 MAX_REVIEW_ROUNDS=4 STOP_ON_REVIEW_FAILURE=true chama-compose
```

### Pipeline phases

The compose orchestrator runs 5 phases per task:
1. **Coder** — identify task, create branch, implement, validate, commit
2. **Simplify** — review and simplify changed code
3. **PR** — push, create PR, move to In Review, wait CI
4. **PR Reviewer** — structured PR review
5. **Review-loop** — handle comments, merge, move to Done

## Project Structure

```
chama/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace definition
├── skills/                      # Slash commands (interactive)
│   ├── new-project/SKILL.md     # Guided project bootstrap
│   ├── adopt/SKILL.md           # Adopt existing repo
│   ├── init/SKILL.md            # Project onboarding
│   ├── ideas/SKILL.md           # Ideas studio
│   ├── architect/SKILL.md       # Idea -> Spec + phases
│   ├── code/SKILL.md            # Task executor
│   ├── review-loop/SKILL.md     # PR comment handler
│   └── gate-check/SKILL.md      # Critical Gate standalone
├── workflow/                    # Headless prompts + scripts
│   ├── prompt-compose-coder.md
│   ├── prompt-compose-simplify.md
│   ├── prompt-commit-reviewer.md
│   ├── prompt-pr-reviewer.md
│   ├── prompt-review-loop.md
│   └── scripts/
├── agent/                       # Docker runtime
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── README.md
├── templates/                   # Templates for bootstrap/init
│   ├── chama.yml.template
│   ├── CLAUDE.md.template
│   ├── PROJECT_BRIEF.md.template
│   ├── README.md.template
│   ├── spec.md.default
│   └── critical-gates.yml.default
├── scripts/
│   ├── bump-version.sh          # Version bump engine
│   ├── make-bump-version.sh     # Interactive bump with LLM changelog
│   ├── run-critical-gate.sh     # Critical Gate engine
│   ├── resolve-spec-template.sh # Spec template resolver
│   ├── sync-board-statuses.sh   # Board status validator
│   └── setup-github-project.sh  # GitHub project setup
├── Makefile                     # make bump-version
└── LICENSE
```

## Multi-language Support

Set `project.language` in `.chama.yml` to `pt-BR` or `en`. All commands respond in the configured language. Default: `pt-BR`.

## License

[MIT](LICENSE)
