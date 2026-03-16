#!/usr/bin/env bash
set -euo pipefail

# ─── Bump Version ────────────────────────────────────────────────────────────
# Updates the version field in all files listed in .chama.yml versioning.files.
# Usage: scripts/bump-version.sh <new-version>
# ─────────────────────────────────────────────────────────────────────────────

NEW_VERSION="${1:-}"

if [[ -z "$NEW_VERSION" ]]; then
  echo "Usage: $0 <new-version>" >&2
  echo "Example: $0 1.3.0-draft.0" >&2
  exit 1
fi

# Check required tools
for cmd in jq yq git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

# Check .chama.yml exists and has versioning section
if [[ ! -f ".chama.yml" ]]; then
  echo "ERROR: .chama.yml not found in current directory." >&2
  exit 1
fi

ENABLED=$(yq '.versioning.enabled // false' .chama.yml 2>/dev/null)
if [[ "$ENABLED" != "true" ]]; then
  echo "ERROR: versioning is not enabled in .chama.yml." >&2
  exit 1
fi

FILE_COUNT=$(yq '.versioning.files | length' .chama.yml 2>/dev/null)
if [[ "$FILE_COUNT" -eq 0 ]]; then
  echo "ERROR: No files configured in versioning.files." >&2
  exit 1
fi

# Validate all files exist before making any changes
for i in $(seq 0 $((FILE_COUNT - 1))); do
  FILE_PATH=$(yq ".versioning.files[$i].path" .chama.yml)
  if [[ ! -f "$FILE_PATH" ]]; then
    echo "ERROR: File not found: $FILE_PATH" >&2
    exit 1
  fi
done

# Track whether any file was actually changed
CHANGED=false

for i in $(seq 0 $((FILE_COUNT - 1))); do
  FILE_PATH=$(yq ".versioning.files[$i].path" .chama.yml)
  JQ_FILTER=$(yq ".versioning.files[$i].jq_filter" .chama.yml)

  # Validate the version field exists
  CURRENT_VERSION=$(jq -r "$JQ_FILTER // empty" "$FILE_PATH")
  if [[ -z "$CURRENT_VERSION" ]]; then
    echo "ERROR: Version field not found in $FILE_PATH (filter: $JQ_FILTER)" >&2
    exit 1
  fi

  # Skip if already at target version
  if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo "  $FILE_PATH already at $NEW_VERSION, skipping."
    continue
  fi

  # Update the version
  TMP_FILE=$(mktemp)
  jq "$JQ_FILTER = \"$NEW_VERSION\"" "$FILE_PATH" > "$TMP_FILE"
  mv "$TMP_FILE" "$FILE_PATH"
  echo "  Updated $FILE_PATH: $CURRENT_VERSION -> $NEW_VERSION"
  CHANGED=true
done

if [[ "$CHANGED" == "true" ]]; then
  # Stage and commit only the versioned files
  for i in $(seq 0 $((FILE_COUNT - 1))); do
    FILE_PATH=$(yq ".versioning.files[$i].path" .chama.yml)
    git add "$FILE_PATH"
  done
  git commit -m "chore: bump version to $NEW_VERSION"
  echo "Committed: chore: bump version to $NEW_VERSION"
else
  echo "No changes needed. All files already at $NEW_VERSION."
fi
