#!/usr/bin/env bash
set -euo pipefail

# ─── Sync GitHub Project Board Statuses for Chama ────────────────────────────
# Ensures the project board has all status columns required by Chama workflows.
# Reads expected statuses from .chama.yml (with defaults), compares with the
# board's current configuration, and reports missing ones.
#
# Usage: bash scripts/sync-board-statuses.sh [owner] [project_number]
# ──────────────────────────────────────────────────────────────────────────────

# ─── Resolve config ──────────────────────────────────────────────────────────

OWNER="${1:-}"
PROJECT_NUM="${2:-}"

if [[ -z "$OWNER" ]] || [[ -z "$PROJECT_NUM" ]]; then
  if command -v yq >/dev/null 2>&1 && [[ -f ".chama.yml" ]]; then
    [[ -z "$OWNER" ]] && OWNER=$(yq '.github.owner' .chama.yml 2>/dev/null)
    [[ -z "$PROJECT_NUM" ]] && PROJECT_NUM=$(yq '.github.project_number' .chama.yml 2>/dev/null)
  fi
  [[ -z "$OWNER" || "$OWNER" == "null" ]] && OWNER="${CHAMA_OWNER:-}"
  [[ -z "$PROJECT_NUM" || "$PROJECT_NUM" == "null" ]] && PROJECT_NUM="${CHAMA_PROJECT_NUMBER:-}"
fi

if [[ -z "$OWNER" ]] || [[ -z "$PROJECT_NUM" ]]; then
  echo "Usage: $0 <owner> <project_number>" >&2
  echo "Or configure .chama.yml or set CHAMA_OWNER + CHAMA_PROJECT_NUMBER" >&2
  exit 1
fi

# ─── Read expected statuses from .chama.yml (with defaults) ──────────────────

if command -v yq >/dev/null 2>&1 && [[ -f ".chama.yml" ]]; then
  STATUS_TODO=$(yq '.github.board_statuses.todo // "Todo"' .chama.yml 2>/dev/null)
  STATUS_IN_PROGRESS=$(yq '.github.board_statuses.in_progress // "In Progress"' .chama.yml 2>/dev/null)
  STATUS_IN_REVIEW=$(yq '.github.board_statuses.in_review // "In Review"' .chama.yml 2>/dev/null)
  STATUS_DONE=$(yq '.github.board_statuses.done // "Done"' .chama.yml 2>/dev/null)
else
  STATUS_TODO="Todo"
  STATUS_IN_PROGRESS="In Progress"
  STATUS_IN_REVIEW="In Review"
  STATUS_DONE="Done"
fi

EXPECTED_STATUSES=("$STATUS_TODO" "$STATUS_IN_PROGRESS" "$STATUS_IN_REVIEW" "$STATUS_DONE")

echo "Syncing board statuses for project #$PROJECT_NUM (owner: $OWNER)..."
echo ""

# ─── Fetch current statuses ──────────────────────────────────────────────────

FIELD_JSON=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json)
STATUS_FIELD=$(echo "$FIELD_JSON" | jq -r '.fields[] | select(.name == "Status")')

if [[ -z "$STATUS_FIELD" ]]; then
  echo "ERROR: No 'Status' field found in project #$PROJECT_NUM." >&2
  exit 1
fi

CURRENT_STATUSES=$(echo "$STATUS_FIELD" | jq -r '.options[].name')

# ─── Compare and report ──────────────────────────────────────────────────────

MISSING=()
OK=()

for expected in "${EXPECTED_STATUSES[@]}"; do
  if echo "$CURRENT_STATUSES" | grep -qx "$expected"; then
    OK+=("$expected")
  else
    MISSING+=("$expected")
  fi
done

echo "Current statuses in board:"
while IFS= read -r status; do
  echo "  - $status"
done <<< "$CURRENT_STATUSES"
echo ""

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "All expected statuses are present. Board is in sync."
  exit 0
fi

echo "Expected by Chama (from .chama.yml):"
for s in "${EXPECTED_STATUSES[@]}"; do
  echo "  - $s"
done
echo ""

echo "Missing statuses:"
for s in "${MISSING[@]}"; do
  echo "  - $s"
done
echo ""

# ─── Guidance ─────────────────────────────────────────────────────────────────

echo "GitHub Projects v2 does not support adding status options via CLI."
echo "Please add the missing statuses manually:"
echo ""
echo "  1. Open: https://github.com/users/$OWNER/projects/$PROJECT_NUM/settings"
echo "  2. Click on the 'Status' field"
echo "  3. Add the missing options listed above"
echo ""
echo "Or configure custom status names in .chama.yml:"
echo ""
echo "  github:"
echo "    board_statuses:"
echo "      todo: \"Todo\""
echo "      in_progress: \"In Progress\""
echo "      in_review: \"In Review\""
echo "      done: \"Done\""
echo ""

# ─── Casing check ────────────────────────────────────────────────────────────

echo "Casing check (Chama workflows are case-sensitive):"
CASING_OK=true
for expected in "${EXPECTED_STATUSES[@]}"; do
  if echo "$CURRENT_STATUSES" | grep -qix "$expected" && ! echo "$CURRENT_STATUSES" | grep -qx "$expected"; then
    ACTUAL=$(echo "$CURRENT_STATUSES" | grep -ix "$expected")
    echo "  WARNING: Found '$ACTUAL' but .chama.yml expects '$expected'"
    CASING_OK=false
  fi
done

if $CASING_OK; then
  echo "  All casings match."
fi

exit 1
