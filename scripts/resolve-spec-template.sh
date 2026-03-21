#!/usr/bin/env bash
# Resolves the Spec template path with fallback chain:
# 1. Project-local override: .chama/templates/spec.md
# 2. Chama plugin default: templates/spec.md.default
# Outputs the template content to stdout.

set -euo pipefail

if [ -f ".chama/templates/spec.md" ]; then
  cat ".chama/templates/spec.md"
else
  # Discover chama plugin path: 1) self-hosting (chama repo), 2) local subdir, 3) legacy global, 4) cache
  ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  if [ -f "$ROOT_DIR/templates/spec.md.default" ]; then
    CHAMA_PLUGIN_DIR="$ROOT_DIR"
  elif [ -d "chama/templates" ]; then
    CHAMA_PLUGIN_DIR="chama"
  elif [ -d "$HOME/.claude/plugins/chama/templates" ]; then
    CHAMA_PLUGIN_DIR="$HOME/.claude/plugins/chama"
  elif CACHE_HIT=$(find "$HOME/.claude/plugins/cache/chama" -maxdepth 4 -name "spec.md.default" -printf '%h\n' 2>/dev/null | sort -V | tail -1) && [ -n "$CACHE_HIT" ]; then
    CHAMA_PLUGIN_DIR="${CACHE_HIT%/templates}"
  else
    echo "ERROR: Could not find chama plugin directory" >&2
    exit 1
  fi
  cat "$CHAMA_PLUGIN_DIR/templates/spec.md.default"
fi
