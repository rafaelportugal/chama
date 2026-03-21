#!/usr/bin/env bash
set -euo pipefail

# ─── Make Bump Version ──────────────────────────────────────────────────────
# Interactive version bump with LLM-generated changelog.
# Called by: make bump-version
#
# Flow: collect commits → generate changelog via LLM → confirm → bump
# ─────────────────────────────────────────────────────────────────────────────

# ─── Pre-checks ──────────────────────────────────────────────────────────────

for cmd in jq yq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

if [[ ! -f ".chama.yml" ]]; then
  echo "ERROR: .chama.yml not found in current directory." >&2
  exit 1
fi

ENABLED=$(yq '.versioning.enabled // false' .chama.yml 2>/dev/null)
if [[ "$ENABLED" != "true" ]]; then
  echo "ERROR: versioning is not enabled in .chama.yml." >&2
  exit 1
fi

# ─── Read current version ───────────────────────────────────────────────────

VERSION_FILE=$(yq '.versioning.files[0].path' .chama.yml 2>/dev/null)
VERSION_FILTER=$(yq '.versioning.files[0].jq_filter' .chama.yml 2>/dev/null)
CURRENT_VERSION=$(jq -r "$VERSION_FILTER // empty" "$VERSION_FILE" 2>/dev/null)

if [[ -z "$CURRENT_VERSION" ]]; then
  echo "ERROR: Could not read current version from $VERSION_FILE" >&2
  exit 1
fi

echo ""
echo "Current version: $CURRENT_VERSION"
echo ""

# ─── Collect commits since last bump ────────────────────────────────────────

# Find last stable version bump (ignore draft bumps for migration)
LAST_BUMP_COMMIT=$(git log --first-parent --grep="chore: bump version to [0-9]*\.[0-9]*\.[0-9]*$" --extended-regexp -1 --format="%H" 2>/dev/null || true)

# Fallback: any bump commit if no stable found
if [[ -z "$LAST_BUMP_COMMIT" ]]; then
  LAST_BUMP_COMMIT=$(git log --first-parent --grep="chore: bump version" -1 --format="%H" 2>/dev/null || true)
fi

if [[ -n "$LAST_BUMP_COMMIT" ]]; then
  COMMITS=$(git log --oneline "${LAST_BUMP_COMMIT}..HEAD" 2>/dev/null || true)
else
  COMMITS=$(git log --oneline 2>/dev/null || true)
fi

if [[ -z "$COMMITS" ]]; then
  echo "No changes since last version bump. Nothing to do."
  exit 0
fi

echo "Commits since last bump:"
echo "$COMMITS" | sed 's/^/  /'
echo ""

# ─── Generate changelog via LLM ─────────────────────────────────────────────

LANG_CONFIG=$(yq '.project.language // "pt-BR"' .chama.yml 2>/dev/null)

BUMP_RULES="After the changelog, on a NEW line, output EXACTLY one of these tags:
BUMP_RECOMMENDATION: patch
BUMP_RECOMMENDATION: minor
BUMP_RECOMMENDATION: major

Rules for recommendation:
- patch: only bug fixes, docs, chore, refactoring — no new user-facing functionality
- minor: new features, new commands, new configuration options, new files/templates
- major: breaking changes in public API, config format changes that break existing users, removal of features

This project is a CLI plugin (SDLC orchestrator). Treat new commands, new skill files, and new templates as minor. Treat changes to existing prompt/skill files that don't add features as patch."

if [[ "$LANG_CONFIG" == "pt-BR" ]]; then
  LLM_PROMPT="Analise os commits abaixo e gere um changelog no formato Keep a Changelog (https://keepachangelog.com).
Categorias: Added, Changed, Fixed, Removed (use apenas as que se aplicam).
Escreva em português (pt-BR).
Seja descritivo mas conciso — cada item em 1-2 linhas.
Agrupe itens relacionados.
NÃO inclua o header ## [version] - date, apenas as categorias e itens.
NÃO inclua explicações ou comentários, apenas o changelog.

$BUMP_RULES

Commits:
$COMMITS"
else
  LLM_PROMPT="Analyze the commits below and generate a changelog in Keep a Changelog format (https://keepachangelog.com).
Categories: Added, Changed, Fixed, Removed (use only applicable ones).
Write in English.
Be descriptive but concise — each item in 1-2 lines.
Group related items.
Do NOT include the header ## [version] - date, only categories and items.
Do NOT include explanations or comments, only the changelog.

$BUMP_RULES

Commits:
$COMMITS"
fi

fallback_changelog() {
  printf '%s' "$COMMITS" | sed 's/^[a-f0-9]* /- /'
}

if command -v claude >/dev/null 2>&1; then
  echo "Generating changelog via LLM..."
  echo ""
  LLM_ERR=$(mktemp)
  CHANGELOG=$(printf '%s' "$LLM_PROMPT" | claude --print 2>"$LLM_ERR" || true)

  if [[ -z "$CHANGELOG" ]]; then
    echo "WARNING: LLM generation failed. Using commit list as fallback."
    [[ -s "$LLM_ERR" ]] && echo "  Reason: $(cat "$LLM_ERR")"
    CHANGELOG=$(fallback_changelog)
  fi
  rm -f "$LLM_ERR"
else
  echo "claude CLI not found. Using commit list as fallback."
  CHANGELOG=$(fallback_changelog)
fi

# ─── Parse LLM recommendation ────────────────────────────────────────────────

RECOMMENDED_BUMP=$(echo "$CHANGELOG" | grep -oP 'BUMP_RECOMMENDATION:\s*\K(patch|minor|major)' | head -1 || true)
# Remove the recommendation line from changelog
CHANGELOG=$(echo "$CHANGELOG" | grep -v 'BUMP_RECOMMENDATION:')
# Trim trailing blank lines
CHANGELOG=$(echo "$CHANGELOG" | sed -e :a -e '/^$/{ $d; N; ba; }')

echo "Generated changelog:"
echo "─────────────────────────────────────────"
echo "$CHANGELOG"
echo "─────────────────────────────────────────"
echo ""

# ─── Verify interactive terminal ─────────────────────────────────────────────

if [[ ! -t 0 ]]; then
  echo "ERROR: This script requires an interactive terminal." >&2
  exit 1
fi

# ─── Ask for bump type ───────────────────────────────────────────────────────

CLEAN_VERSION=$(echo "$CURRENT_VERSION" | sed 's/-draft\..*//')
MAJOR=$(echo "$CLEAN_VERSION" | cut -d. -f1)
MINOR=$(echo "$CLEAN_VERSION" | cut -d. -f2)
PATCH=$(echo "$CLEAN_VERSION" | cut -d. -f3)

# Map recommendation to option number
REC_LABEL=""
case "$RECOMMENDED_BUMP" in
  patch) REC_LABEL="1" ;;
  minor) REC_LABEL="2" ;;
  major) REC_LABEL="3" ;;
esac

echo "Bump type:"
if [[ "$REC_LABEL" == "1" ]]; then
  echo "  1) patch → $MAJOR.$MINOR.$((PATCH + 1))  ← recommended"
else
  echo "  1) patch → $MAJOR.$MINOR.$((PATCH + 1))"
fi
if [[ "$REC_LABEL" == "2" ]]; then
  echo "  2) minor → $MAJOR.$((MINOR + 1)).0  ← recommended"
else
  echo "  2) minor → $MAJOR.$((MINOR + 1)).0"
fi
if [[ "$REC_LABEL" == "3" ]]; then
  echo "  3) major → $((MAJOR + 1)).0.0  ← recommended"
else
  echo "  3) major → $((MAJOR + 1)).0.0"
fi
echo "  4) custom version"
echo ""

DEFAULT_CHOICE="${REC_LABEL:-2}"
read -r -p "Choose [1/2/3/4] (default: $DEFAULT_CHOICE): " BUMP_CHOICE
BUMP_CHOICE="${BUMP_CHOICE:-$DEFAULT_CHOICE}"

case "$BUMP_CHOICE" in
  1) NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  2) NEW_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
  3) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
  4)
    read -r -p "Enter version: " NEW_VERSION
    if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Invalid version format. Expected: X.Y.Z"
      exit 1
    fi
    ;;
  *)
    echo "Invalid choice. Aborting."
    exit 1
    ;;
esac

echo ""
echo "Will bump: $CURRENT_VERSION → $NEW_VERSION"
read -r -p "Confirm? [Y/n]: " CONFIRM

if [[ "$CONFIRM" =~ ^[Nn] ]]; then
  echo "Bump cancelled. No changes made."
  exit 0
fi

# ─── Execute bump ───────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/bump-version.sh" "$NEW_VERSION" --changelog "$CHANGELOG"

echo ""
echo "Done! Run 'git push' to publish."
