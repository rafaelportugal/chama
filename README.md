# Chama

**SDLC pipeline orchestrator for Claude Code** — Idea -> Spec -> Code -> Review -> Merge.

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

### 2. Initialize your project

```
/chama:init
```

This will:
- Ask project details (name, repo, tech stack, components, quality gates)
- Create `.chama.yml` in your project root
- Generate `CLAUDE.md` if it doesn't exist
- Set up GitHub labels (`idea`, `spec`, `phase`)
- Configure GitHub Project

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
| `/chama:init` | Project onboarding — creates `.chama.yml`, labels, project |
| `/chama:ideas` | Ideas studio — brainstorm with Product Lead + Designer personas |
| `/chama:architect` | Idea -> Spec + phases (all as GitHub Issues) |
| `/chama:code` | Execute next Todo task with quality gates |
| `/chama:review-loop` | Handle PR comments in loop, scoped by Spec |

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
  default_branch: "main"             # "main", "dev", etc.
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

business_segment: "SaaS"
```

### Environment variable overrides

```bash
CHAMA_REPO="owner/repo"
CHAMA_OWNER="owner"
CHAMA_PROJECT_NUMBER="1"
CHAMA_DEFAULT_BRANCH="main"
```

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
```

## Headless / Compose Mode

For automated execution without manual intervention.

### Setup

Add the `chama-compose` function to your `~/.zshrc` (or `~/.bashrc`):

```bash
# ─── Chama SDLC Pipeline ─────────────────────────────────────────────────────
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
│   ├── init/SKILL.md
│   ├── ideas/SKILL.md
│   ├── architect/SKILL.md
│   ├── code/SKILL.md
│   └── review-loop/SKILL.md
├── workflow/                    # Headless prompts + scripts
│   ├── prompt-compose-coder.md
│   ├── prompt-compose-simplify.md
│   ├── prompt-commit-reviewer.md
│   ├── prompt-pr-reviewer.md
│   ├── prompt-generate-specs.md
│   └── scripts/
├── agent/                       # Docker runtime
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── README.md
├── templates/                   # Templates for /chama:init
│   ├── chama.yml.template
│   └── CLAUDE.md.template
├── scripts/
│   └── setup-github-project.sh
└── LICENSE
```

## Multi-language Support

Set `project.language` in `.chama.yml` to `pt-BR` or `en`. All commands respond in the configured language. Default: `pt-BR`.

## License

[MIT](LICENSE)
