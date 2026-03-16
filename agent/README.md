# Chama Agent (Claude & Amp)

Isolated Docker runtime for executing AI agents (`claude` and `amp`) with elevated permissions and persistent authentication.

## Overview

- Runs `claude` and `amp` via Docker
- Authentication done once inside the container
- Credentials persisted in Docker volume
- Shell functions for easy usage
- Fully isolated from the project's own docker-compose

## Structure

    chama/
    ├── agent/
    │   ├── Dockerfile
    │   ├── docker-compose.yml
    │   └── README.md
    └── workflow/
        ├── prompt-compose-coder.md
        ├── prompt-compose-simplify.md
        └── scripts/
            └── chama-pipeline.sh

## Setup

### Build and start the container

```bash
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f chama/agent/docker-compose.yml up -d --build
```

> Container runs with your UID/GID for correct file permissions.

## Authentication

### Option A — PAT via `gh auth login` (interactive)

```bash
docker compose -f chama/agent/docker-compose.yml exec agent-container bash
```

Inside the container:

```bash
claude login
amp login
gh auth login
exit
```

Credentials are persisted in the `agent-home` Docker volume.

### Option B — GitHub App (automatic, headless)

Ideal for `chama-pipeline.sh` executions without manual intervention.

1. Create a GitHub App with permissions: `contents: write`, `issues: write`, `pull_requests: write`, `projects: read+write`
2. Install the app on your repo
3. Save the private key as `chama/agent/.gh-app-key.pem` (already in `.gitignore`)
4. Set `GITHUB_APP_ID` in the environment

The `chama-pipeline.sh` script auto-detects the configuration and generates a `GH_TOKEN` via `gh-token`.

### Comparison

| Aspect | PAT (`gh auth login`) | GitHub App (`gh-token`) |
|--------|----------------------|------------------------|
| Validity | Indefinite | 1 hour (auto-expires) |
| Scope | Broad (all user orgs) | Restricted (app permissions) |
| Setup | Simple — interactive login | Medium — create app + private key |
| Best for | Local dev, personal use | Headless automation (`chama-pipeline.sh`) |

## Shell configuration (bash / zsh)

Add to `~/.zshrc` or `~/.bashrc`:

```bash
CHAMA_AGENT_COMPOSE="chama/agent/docker-compose.yml"
CHAMA_AGENT_SERVICE="chama-agent"

# Exec with TTY
chama-agent() {
  docker compose -f "$CHAMA_AGENT_COMPOSE" exec "$CHAMA_AGENT_SERVICE" bash
}

# Exec without TTY (for piping)
chama-agentp() {
  docker compose -f "$CHAMA_AGENT_COMPOSE" exec -T "$CHAMA_AGENT_SERVICE" "$@"
}

chama-claude() {
  local prompt_file="${1:-chama/workflow/prompt-compose-coder.md}"
  if [ ! -f "$prompt_file" ]; then
    echo "Prompt not found: $prompt_file"
    return 1
  fi
  chama-agent claude -p "$(cat "$prompt_file")" --allow-dangerously-skip-permissions
}

chama-amp() {
  local prompt_file="${1:-chama/workflow/prompt-compose-coder.md}"
  if [ ! -f "$prompt_file" ]; then
    echo "Prompt not found: $prompt_file"
    return 1
  fi
  cat "$prompt_file" | chama-agentp amp --dangerously-allow-all
}

chama-pipeline() {
  local compose_script="chama/workflow/scripts/chama-pipeline.sh"
  if [ ! -f "$compose_script" ]; then
    echo "Compose script not found: $compose_script"
    return 1
  fi
  MAX_TASKS="${MAX_TASKS:-3}" \
  MAX_REVIEW_ROUNDS="${MAX_REVIEW_ROUNDS:-4}" \
  STOP_ON_REVIEW_FAILURE="${STOP_ON_REVIEW_FAILURE:-true}" \
    bash "$compose_script"
}
```

## Usage

```bash
chama-claude
chama-amp
```

With custom prompt:

```bash
chama-claude chama/workflow/prompt-compose-coder.md
```

## Advanced

```bash
chama-agent bash
chama-agent claude --help
chama-agent amp --help
```

## Notes

- Compose isolated from the main project
- Dangerous flags encapsulated
- Volume persists authentication
