#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
PR_NUMBER="${1:-}"
MODE="${2:-foreground}" # foreground | --background

if [[ -z "$PR_NUMBER" ]]; then
  echo "Usage: $0 <PR_NUMBER> [--background]" >&2
  exit 1
fi

# Discover chama plugin path
if [[ -d "$ROOT_DIR/chama/workflow" ]]; then
  CHAMA_DIR="$ROOT_DIR/chama"
elif [[ -d "$HOME/.claude/plugins/chama/workflow" ]]; then
  CHAMA_DIR="$HOME/.claude/plugins/chama"
else
  echo "ERROR: chama plugin not found." >&2
  exit 1
fi

PROMPT_TEMPLATE="$CHAMA_DIR/workflow/prompt-pr-reviewer.md"
REVIEWS_DIR="${CHAMA_REVIEWS_DIR:-$(yq '.artifacts.reviews_dir' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo '.chama/reviews')}"
OUT_DIR="$ROOT_DIR/$REVIEWS_DIR"
mkdir -p "$OUT_DIR"

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "Prompt not found: $PROMPT_TEMPLATE" >&2
  exit 1
fi

TMP_PROMPT="$(mktemp)"
trap 'rm -f "$TMP_PROMPT"' EXIT

sed "s/__PR_NUMBER__/${PR_NUMBER}/g" "$PROMPT_TEMPLATE" >"$TMP_PROMPT"

run_reviewer() {
  if command -v claude >/dev/null 2>&1; then
    claude -p "$(cat "$TMP_PROMPT")" --dangerously-skip-permissions
    return 0
  fi

  if [[ -f "$CHAMA_DIR/agent/docker-compose.yml" ]] && command -v docker >/dev/null 2>&1; then
    docker compose -f "$CHAMA_DIR/agent/docker-compose.yml" exec -T agent-container \
      claude -p "$(cat "$TMP_PROMPT")" --dangerously-skip-permissions
    return 0
  fi

  echo "Cannot run PR reviewer: claude not found (local or container)." >&2
  return 127
}

TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$OUT_DIR/pr-${PR_NUMBER}-${TS}.md"

if [[ "$MODE" == "--background" ]]; then
  PID_FILE="$OUT_DIR/pr-${PR_NUMBER}-${TS}.pid"

  (
    if run_reviewer >"$LOG_FILE" 2>&1; then
      echo "status=ok" >"$OUT_DIR/pr-${PR_NUMBER}-${TS}.status"
    else
      echo "status=error" >"$OUT_DIR/pr-${PR_NUMBER}-${TS}.status"
    fi
  ) &

  echo "$!" >"$PID_FILE"
  echo "PR reviewer started in background for PR #$PR_NUMBER (pid $(cat "$PID_FILE"))."
  echo "Output: $LOG_FILE"
  exit 0
fi

run_reviewer | tee "$LOG_FILE"
echo "Review saved at: $LOG_FILE"
