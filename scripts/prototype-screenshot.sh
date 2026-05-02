#!/usr/bin/env bash
set -euo pipefail

# ─── Prototype Screenshot Capture ─────────────────────────────────────────────
# Captures screenshots of HTML files using Playwright.
# Usage: prototype-screenshot.sh <html-file-or-dir> <output-dir> [width] [height]
#
# If <html-file-or-dir> is a directory, captures all .html files in it.
# If it's a single file, captures just that file.
# ──────────────────────────────────────────────────────────────────────────────

INPUT="${1:?Usage: prototype-screenshot.sh <html-file-or-dir> <output-dir> [width] [height]}"
OUTPUT_DIR="${2:?Usage: prototype-screenshot.sh <html-file-or-dir> <output-dir> [width] [height]}"
WIDTH="${3:-1440}"
HEIGHT="${4:-900}"

# ─── Validate Playwright ─────────────────────────────────────────────────────

if ! command -v npx >/dev/null 2>&1; then
  echo "ERROR: npx not found. Install Node.js first." >&2
  exit 1
fi

if ! npx playwright --version >/dev/null 2>&1; then
  echo "ERROR: Playwright not found." >&2
  echo "Install: npm install -D playwright && npx playwright install chromium" >&2
  exit 1
fi

# ─── Collect HTML files ──────────────────────────────────────────────────────

HTML_FILES=()

if [ -d "$INPUT" ]; then
  while IFS= read -r -d '' f; do
    HTML_FILES+=("$f")
  done < <(find "$INPUT" -maxdepth 1 -name "*.html" -print0 | sort -z)
elif [ -f "$INPUT" ]; then
  HTML_FILES+=("$INPUT")
else
  echo "ERROR: '$INPUT' is not a file or directory." >&2
  exit 1
fi

if [ ${#HTML_FILES[@]} -eq 0 ]; then
  echo "ERROR: No .html files found in '$INPUT'." >&2
  exit 1
fi

# ─── Capture screenshots ─────────────────────────────────────────────────────

mkdir -p "$OUTPUT_DIR"
COUNT=0

for html_file in "${HTML_FILES[@]}"; do
  COUNT=$((COUNT + 1))
  filename=$(basename "$html_file" .html)
  output_file="$OUTPUT_DIR/$(printf '%02d' $COUNT)-${filename}.png"
  file_url="file://$(cd "$(dirname "$html_file")" && pwd)/$(basename "$html_file")"

  echo "Capturing: $html_file -> $output_file"

  npx playwright screenshot \
    --viewport-size="${WIDTH},${HEIGHT}" \
    --full-page \
    "$file_url" \
    "$output_file" 2>/dev/null

  if [ -f "$output_file" ]; then
    echo "  OK: $output_file"
  else
    echo "  WARNING: Failed to capture $html_file" >&2
  fi
done

echo ""
echo "Screenshots captured: $COUNT"
echo "Output directory: $OUTPUT_DIR"
