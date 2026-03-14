#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
COMMIT_SHA="${1:-$(git rev-parse HEAD)}"
MODE="${2:-foreground}" # foreground | --background

# Discover chama plugin path
if [[ -d "$ROOT_DIR/chama/workflow" ]]; then
  CHAMA_DIR="$ROOT_DIR/chama"
elif [[ -d "$HOME/.claude/plugins/chama/workflow" ]]; then
  CHAMA_DIR="$HOME/.claude/plugins/chama"
else
  echo "ERROR: chama plugin not found." >&2
  exit 1
fi

PROMPT_TEMPLATE="$CHAMA_DIR/workflow/prompt-commit-reviewer.md"
REVIEWS_DIR="${CHAMA_REVIEWS_DIR:-$(yq '.artifacts.reviews_dir' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo '.chama/reviews')}"
OUT_DIR="$ROOT_DIR/$REVIEWS_DIR"
mkdir -p "$OUT_DIR"

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "Prompt not found: $PROMPT_TEMPLATE" >&2
  exit 1
fi

TMP_PROMPT="$(mktemp)"
trap 'rm -f "$TMP_PROMPT"' EXIT

sed "s/__COMMIT_SHA__/${COMMIT_SHA}/g" "$PROMPT_TEMPLATE" >"$TMP_PROMPT"

run_reviewer() {
  if command -v claude >/dev/null 2>&1; then
    claude -p "$(cat "$TMP_PROMPT")" --allow-dangerously-skip-permissions
    return 0
  fi

  if [[ -f "$CHAMA_DIR/agent/docker-compose.yml" ]] && command -v docker >/dev/null 2>&1; then
    docker compose -f "$CHAMA_DIR/agent/docker-compose.yml" exec -T agent-container \
      claude -p "$(cat "$TMP_PROMPT")" --allow-dangerously-skip-permissions
    return 0
  fi

  echo "Cannot run reviewer: claude not found (local or container)." >&2
  return 127
}

if [[ "$MODE" == "--background" ]]; then
  LOG_FILE="$OUT_DIR/${COMMIT_SHA}.md"
  PID_FILE="$OUT_DIR/${COMMIT_SHA}.pid"

  (
    if run_reviewer >"$LOG_FILE" 2>&1; then
      echo "status=ok" >"$OUT_DIR/${COMMIT_SHA}.status"
    else
      echo "status=error" >"$OUT_DIR/${COMMIT_SHA}.status"
    fi
  ) &

  echo "$!" >"$PID_FILE"
  echo "Reviewer started in background for $COMMIT_SHA (pid $(cat "$PID_FILE"))."
  echo "Output: $LOG_FILE"
  exit 0
fi

LOG_FILE="$OUT_DIR/${COMMIT_SHA}.md"
run_reviewer | tee "$LOG_FILE"
echo "Review saved at: $LOG_FILE"
