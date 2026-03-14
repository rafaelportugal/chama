#!/usr/bin/env bash
set -euo pipefail

# ─── Setup GitHub Project Labels for Chama ──────────────────────────────────
# Creates the standard labels used by chama commands.
# Usage: bash scripts/setup-github-project.sh [owner/repo]
# ─────────────────────────────────────────────────────────────────────────────

REPO="${1:-}"

if [[ -z "$REPO" ]]; then
  if command -v yq >/dev/null 2>&1 && [[ -f ".chama.yml" ]]; then
    REPO=$(yq '.project.repo' .chama.yml 2>/dev/null)
  fi
  if [[ -z "$REPO" || "$REPO" == "null" ]]; then
    REPO="${CHAMA_REPO:-}"
  fi
fi

if [[ -z "$REPO" ]]; then
  echo "Usage: $0 <owner/repo>" >&2
  echo "Or set CHAMA_REPO or configure .chama.yml" >&2
  exit 1
fi

echo "Setting up Chama labels for $REPO..."

create_label() {
  local name="$1" color="$2" description="$3"
  if gh label create "$name" --repo "$REPO" --color "$color" --description "$description" 2>/dev/null; then
    echo "  Created: $name"
  else
    gh label edit "$name" --repo "$REPO" --color "$color" --description "$description" 2>/dev/null || true
    echo "  Updated: $name"
  fi
}

create_label "idea"  "0E8A16" "Idea in brainstorm"
create_label "rfc"   "1D76DB" "RFC document"
create_label "epic"  "D93F0B" "Epic grouping phases"
create_label "phase" "FBCA04" "Implementation phase"

echo "Done. Labels ready for $REPO."
