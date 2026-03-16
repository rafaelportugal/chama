#!/usr/bin/env bash
# Resolves the Spec template path with fallback chain:
# 1. Project-local override: .chama/templates/spec.md
# 2. Chama plugin default: templates/spec.md.default
# Outputs the template content to stdout.

set -euo pipefail

if [ -f ".chama/templates/spec.md" ]; then
  cat ".chama/templates/spec.md"
else
  # Discover chama plugin path (local or installed)
  if [ -d "chama/templates" ]; then
    CHAMA_PLUGIN_DIR="chama"
  elif [ -d "$HOME/.claude/plugins/chama/templates" ]; then
    CHAMA_PLUGIN_DIR="$HOME/.claude/plugins/chama"
  elif CACHE_DIR=$(find "$HOME/.claude" -maxdepth 3 -type d -name "chama" -path "*/plugins/*" 2>/dev/null | head -1) && [ -n "$CACHE_DIR" ]; then
    CHAMA_PLUGIN_DIR="$CACHE_DIR"
  else
    echo "ERROR: Could not find chama plugin directory" >&2
    exit 1
  fi
  cat "$CHAMA_PLUGIN_DIR/templates/spec.md.default"
fi
