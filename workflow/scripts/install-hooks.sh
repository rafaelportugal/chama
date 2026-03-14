#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"

# Discover chama plugin path
if [[ -d "$ROOT_DIR/chama/workflow" ]]; then
  CHAMA_DIR="$ROOT_DIR/chama"
elif [[ -d "$HOME/.claude/plugins/chama/workflow" ]]; then
  CHAMA_DIR="$HOME/.claude/plugins/chama"
else
  echo "ERROR: chama plugin not found." >&2
  exit 1
fi

git config core.hooksPath "$ROOT_DIR/.githooks"
chmod +x "$ROOT_DIR/.githooks/post-commit" 2>/dev/null || true
chmod +x "$CHAMA_DIR/workflow/scripts/run-commit-reviewer.sh"
chmod +x "$CHAMA_DIR/workflow/scripts/run-pr-reviewer.sh"

echo "Hooks installed successfully."
echo "core.hooksPath=$(git config --get core.hooksPath)"
echo "To temporarily disable: ENABLE_COMMIT_REVIEWER=0 git commit ..."
