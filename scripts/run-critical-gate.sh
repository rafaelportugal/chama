#!/usr/bin/env bash
set -uo pipefail

# ─── Critical Gate Engine ────────────────────────────────────────────────────
# Analyzes git diffs for destructive/dangerous operations using regex rules.
# Classifies findings by severity and blocks on CRITICAL/HIGH.
#
# Usage:
#   scripts/run-critical-gate.sh [--mode pre-commit|pre-merge|standalone] [--commit <ID>]
#
# Exit codes:
#   0 = clean (no findings, or INFO only)
#   1 = blocked (CRITICAL or HIGH findings)
#   2 = warnings only
#   3 = internal error
# ─────────────────────────────────────────────────────────────────────────────

# ─── Defaults ────────────────────────────────────────────────────────────────

MODE="standalone"
COMMIT_ID=""
CHAMA_YML=".chama.yml"

# ─── Parse arguments ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      if [[ $# -lt 2 ]] || [[ "${2}" == -* ]]; then
        echo "ERROR: --mode requires one of: pre-commit, pre-merge, standalone" >&2
        exit 3
      fi
      case "$2" in
        pre-commit|pre-merge|standalone) MODE="$2" ;;
        *) echo "ERROR: Unsupported mode: $2" >&2; exit 3 ;;
      esac
      shift 2
      ;;
    --commit)
      COMMIT_ID="${2:-}"
      if [[ -z "$COMMIT_ID" ]]; then
        echo "ERROR: --commit requires a commit ID" >&2
        exit 3
      fi
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 3
      ;;
  esac
done

# ─── Check required tools ───────────────────────────────────────────────────

for cmd in git yq grep sed awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: '$cmd' is required but not installed." >&2
    exit 3
  fi
done

# ─── Temp files (cleaned up on exit) ────────────────────────────────────────

TMPDIR_GATE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_GATE"' EXIT

RULES_FILE="$TMPDIR_GATE/rules.txt"
DIFF_FILE="$TMPDIR_GATE/diff_parsed.txt"
FINDINGS_FILE="$TMPDIR_GATE/findings.txt"
touch "$RULES_FILE" "$DIFF_FILE" "$FINDINGS_FILE"

# ─── Resolve chama plugin path ──────────────────────────────────────────────

if [[ -d "chama/templates" ]]; then
  CHAMA_DIR="chama"
elif [[ -d "${HOME}/.claude/plugins/chama/templates" ]]; then
  CHAMA_DIR="${HOME}/.claude/plugins/chama"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CHAMA_DIR="$(dirname "$SCRIPT_DIR")"
fi

DEFAULT_RULES_FILE="${CHAMA_DIR}/templates/critical-gates.yml.default"

# ─── Load configuration from .chama.yml ─────────────────────────────────────

GATE_ENABLED="true"
FAIL_MODE="open"
SEVERITY_BLOCK_LIST="CRITICAL HIGH"
IGNORE_FILES_RAW=""

if [[ -f "$CHAMA_YML" ]]; then
  GATE_ENABLED=$(yq '.critical_gates.enabled // true' "$CHAMA_YML" 2>/dev/null || echo "true")
  FAIL_MODE=$(yq '.critical_gates.fail_mode // "open"' "$CHAMA_YML" 2>/dev/null || echo "open")

  _sev=$(yq '.critical_gates.severity_block // ["CRITICAL","HIGH"] | .[]' "$CHAMA_YML" 2>/dev/null || true)
  if [[ -n "$_sev" ]]; then
    SEVERITY_BLOCK_LIST="$_sev"
  fi

  IGNORE_FILES_RAW=$(yq '.critical_gates.ignore_files // [] | .[]' "$CHAMA_YML" 2>/dev/null || true)
fi

if [[ "$GATE_ENABLED" == "false" ]]; then
  echo "Critical gate is disabled in $CHAMA_YML. Skipping."
  exit 0
fi

# ─── Build ignore patterns ──────────────────────────────────────────────────

IGNORE_PATTERNS=()
if [[ -n "$IGNORE_FILES_RAW" ]]; then
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] && IGNORE_PATTERNS+=("$pattern")
  done <<< "$IGNORE_FILES_RAW"
fi

# ─── Get diff ────────────────────────────────────────────────────────────────

get_diff() {
  case "$MODE" in
    pre-commit)
      git diff --cached -U0
      ;;
    pre-merge)
      local default_branch
      default_branch=$(yq '.github.default_branch // "main"' "$CHAMA_YML" 2>/dev/null || echo "main")
      git diff "$default_branch"...HEAD -U0
      ;;
    standalone)
      if [[ -n "$COMMIT_ID" ]]; then
        if ! git cat-file -e "$COMMIT_ID" 2>/dev/null; then
          echo "ERROR: Invalid commit ID: $COMMIT_ID" >&2
          return 1
        fi
        if git rev-parse --verify "${COMMIT_ID}~1" >/dev/null 2>&1; then
          git diff "${COMMIT_ID}~1" "$COMMIT_ID" -U0
        else
          # Initial commit — diff against empty tree
          git diff "$(git hash-object -t tree /dev/null)" "$COMMIT_ID" -U0
        fi
      else
        git diff -U0
      fi
      ;;
    *)
      echo "ERROR: Unknown mode: $MODE" >&2
      return 1
      ;;
  esac
}

DIFF_OUTPUT=$(get_diff 2>&1)
DIFF_EXIT=$?

if [[ $DIFF_EXIT -ne 0 ]]; then
  echo "ERROR: Failed to get diff: $DIFF_OUTPUT" >&2
  exit 3
fi

if [[ -z "$DIFF_OUTPUT" ]]; then
  echo "✓ Nenhuma operação crítica detectada (diff vazio)"
  exit 0
fi

# ─── Parse diff into structured data ────────────────────────────────────────
# Output: FILE<TAB>LINE<TAB>SCOPE<TAB>CONTENT

parse_diff() {
  local current_file=""
  local old_line=0
  local new_line=0

  while IFS= read -r line; do
    if [[ "$line" =~ ^diff\ --git\ a/(.+)\ b/(.+)$ ]]; then
      current_file="${BASH_REMATCH[2]}"
      old_line=0
      new_line=0
      continue
    fi

    if [[ "$line" =~ ^@@\ -([0-9]+)(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@ ]]; then
      old_line="${BASH_REMATCH[1]}"
      new_line="${BASH_REMATCH[3]}"
      continue
    fi

    if [[ "$line" =~ ^\+[^+] ]] || [[ "$line" =~ ^\+$ ]]; then
      local content="${line:1}"
      printf '%s\t%s\t%s\t%s\n' "$current_file" "$new_line" "added" "$content"
      new_line=$((new_line + 1))
      continue
    fi

    if [[ "$line" =~ ^-[^-] ]] || [[ "$line" =~ ^-$ ]]; then
      local content="${line:1}"
      printf '%s\t%s\t%s\t%s\n' "$current_file" "$old_line" "removed" "$content"
      old_line=$((old_line + 1))
      continue
    fi
  done <<< "$DIFF_OUTPUT"
}

# ─── Load rules from YAML into temp file ────────────────────────────────────
# Format: ID|SEVERITY|SCOPE|FILE_PATTERNS(pipe-sep)|LINE_PATTERN|MESSAGE

load_rules() {
  local rules_source="$1"
  local yq_prefix="$2"  # e.g. ".rules" or ".critical_gates.custom_rules"

  if [[ ! -f "$rules_source" ]]; then
    return 1
  fi

  local rule_count
  rule_count=$(yq "($yq_prefix) | length" "$rules_source" 2>/dev/null || echo "0")

  if [[ -z "$rule_count" ]] || [[ "$rule_count" -eq 0 ]]; then
    return 1
  fi

  for i in $(seq 0 $((rule_count - 1))); do
    local id severity scope line_pattern message fp_raw
    id=$(yq "($yq_prefix)[$i].id" "$rules_source" 2>/dev/null)
    severity=$(yq "($yq_prefix)[$i].severity" "$rules_source" 2>/dev/null)
    scope=$(yq "($yq_prefix)[$i].scope" "$rules_source" 2>/dev/null)
    line_pattern=$(yq "($yq_prefix)[$i].line_pattern" "$rules_source" 2>/dev/null)
    message=$(yq "($yq_prefix)[$i].message" "$rules_source" 2>/dev/null)
    fp_raw=$(yq "($yq_prefix)[$i].file_patterns | .[]" "$rules_source" 2>/dev/null | tr '\n' '|')
    fp_raw="${fp_raw%|}"

    # Use § as field delimiter (pipe is used inside file_patterns)
    printf '%s§%s§%s§%s§%s§%s\n' "$id" "$severity" "$scope" "$fp_raw" "$line_pattern" "$message"
  done
}

# ─── Glob matching helper ────────────────────────────────────────────────────

matches_glob() {
  local file="$1" pat="$2"

  if [[ "$pat" == "**/"* ]]; then
    # **/*.ext or **/dir/** → suffix match
    local suffix="${pat#\*\*/}"
    case "$file" in *${suffix}) return 0 ;; esac
  elif [[ "$pat" == *"/**" ]]; then
    # dir/** → prefix/contains match
    local prefix="${pat%/\*\*}"
    case "$file" in ${prefix}/*|*/${prefix}/*) return 0 ;; esac
  elif [[ "$pat" == "*/"*"/*" ]]; then
    # */dir/* → path containing dir
    local mid="${pat#\*/}"
    mid="${mid%/\*}"
    case "$file" in */${mid}/*|${mid}/*) return 0 ;; esac
  elif [[ "$pat" == \*\.* && "$pat" != *"/"* ]]; then
    # *.ext or prefix*.ext → use bash pattern matching directly
    # Disable pathname expansion for safe case matching
    set -f
    case "$file" in
      */${pat}|${pat}) set +f; return 0 ;;
    esac
    set +f
  else
    set -f
    case "$file" in ${pat}) set +f; return 0 ;; esac
    set +f
  fi

  return 1
}

# ─── Check if file matches ignore patterns ──────────────────────────────────

is_ignored() {
  local file="$1"
  [[ ${#IGNORE_PATTERNS[@]} -eq 0 ]] && return 1

  for pattern in "${IGNORE_PATTERNS[@]}"; do
    matches_glob "$file" "$pattern" && return 0
  done
  return 1
}

# ─── Check if file matches rule's file_patterns ─────────────────────────────

file_matches_patterns() {
  local file="$1" patterns="$2"

  local OLD_IFS="$IFS"
  IFS='|'
  # Disable pathname expansion so globs like *.sql are not expanded
  set -f
  set -- $patterns
  set +f
  IFS="$OLD_IFS"

  for pat in "$@"; do
    matches_glob "$file" "$pat" && return 0
  done
  return 1
}

# ─── Load all rules ─────────────────────────────────────────────────────────

# Load default rules
if [[ -f "$DEFAULT_RULES_FILE" ]]; then
  load_rules "$DEFAULT_RULES_FILE" ".rules" >> "$RULES_FILE" 2>/dev/null || true
else
  echo "WARNING: Default rules file not found: $DEFAULT_RULES_FILE" >&2
  if [[ "$FAIL_MODE" != "open" ]]; then
    echo "ERROR: Fail-closed and no default rules available." >&2
    exit 3
  fi
fi

# Load custom rules — they override defaults by ID
CUSTOM_TMP="$TMPDIR_GATE/custom.txt"
if [[ -f "$CHAMA_YML" ]]; then
  load_rules "$CHAMA_YML" ".critical_gates.custom_rules // []" > "$CUSTOM_TMP" 2>/dev/null || true
  if [[ -s "$CUSTOM_TMP" ]]; then
    # Remove default rules that have the same ID as custom rules
    while IFS= read -r custom_line; do
      custom_id="${custom_line%%§*}"
      # Remove lines starting with this ID from RULES_FILE
      sed -i.bak "/^${custom_id}§/d" "$RULES_FILE" 2>/dev/null || true
      rm -f "${RULES_FILE}.bak" 2>/dev/null
    done < "$CUSTOM_TMP"
    # Append custom rules
    cat "$CUSTOM_TMP" >> "$RULES_FILE"
  fi
fi

# Validate rules loaded
if [[ ! -s "$RULES_FILE" ]]; then
  if [[ "$FAIL_MODE" == "open" ]]; then
    echo "WARNING: No rules loaded. Fail-open: passing." >&2
    exit 0
  else
    echo "ERROR: No rules loaded and fail_mode is not open." >&2
    exit 3
  fi
fi

# ─── Parse diff ─────────────────────────────────────────────────────────────

parse_diff > "$DIFF_FILE"

if [[ ! -s "$DIFF_FILE" ]]; then
  echo "✓ Nenhuma operação crítica detectada"
  exit 0
fi

# ─── Match rules against diff lines ─────────────────────────────────────────

CRITICAL_COUNT=0
HIGH_COUNT=0
WARNING_COUNT=0
INFO_COUNT=0

while IFS='§' read -r r_id r_severity r_scope r_file_patterns r_line_pattern r_message; do
  while IFS=$'\t' read -r file line_num scope content; do
    # Skip ignored files
    if is_ignored "$file"; then
      continue
    fi

    # Check scope match
    case "$r_scope" in
      added)   [[ "$scope" != "added" ]] && continue ;;
      removed) [[ "$scope" != "removed" ]] && continue ;;
      both)    ;; # matches both
      *)       continue ;;
    esac

    # Check file pattern match
    if ! file_matches_patterns "$file" "$r_file_patterns"; then
      continue
    fi

    # Check line pattern match (grep -E for ERE)
    # Strip (?i) from pattern and use grep -i instead (portable across BSD/GNU grep)
    grep_flags="-qE"
    clean_pattern="$r_line_pattern"
    if [[ "$clean_pattern" == *'(?i)'* ]]; then
      grep_flags="-iqE"
      clean_pattern="${clean_pattern//\(\?i\)/}"
    fi
    if echo "$content" | grep $grep_flags "$clean_pattern" 2>/dev/null; then
      printf '%s§%s§%s§%s§%s§%s\n' "$r_severity" "$r_id" "$file" "$line_num" "$r_message" "$content" >> "$FINDINGS_FILE"

      case "$r_severity" in
        CRITICAL) CRITICAL_COUNT=$((CRITICAL_COUNT + 1)) ;;
        HIGH)     HIGH_COUNT=$((HIGH_COUNT + 1)) ;;
        WARNING)  WARNING_COUNT=$((WARNING_COUNT + 1)) ;;
        INFO)     INFO_COUNT=$((INFO_COUNT + 1)) ;;
      esac
    fi
  done < "$DIFF_FILE"
done < "$RULES_FILE"

# ─── Output results ─────────────────────────────────────────────────────────

TOTAL_FINDINGS=$((CRITICAL_COUNT + HIGH_COUNT + WARNING_COUNT + INFO_COUNT))

if [[ $TOTAL_FINDINGS -eq 0 ]]; then
  echo "✓ Nenhuma operação crítica detectada"
  exit 0
fi

# ─── Box-drawing output ─────────────────────────────────────────────────────

echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│  ⚠  CRITICAL GATE — Operações detectadas                    │"
echo "├──────────────────────────────────────────────────────────────┤"
printf "│  CRITICAL: %-3s  HIGH: %-3s  WARNING: %-3s  INFO: %-3s         │\n" \
  "$CRITICAL_COUNT" "$HIGH_COUNT" "$WARNING_COUNT" "$INFO_COUNT"
echo "├──────────────────────────────────────────────────────────────┤"

# Print findings sorted by severity
for sev in CRITICAL HIGH WARNING INFO; do
  while IFS='§' read -r f_sev f_id f_file f_line f_msg f_content; do
    if [[ "$f_sev" == "$sev" ]]; then
      case "$f_sev" in
        CRITICAL) badge="🔴 CRITICAL" ;;
        HIGH)     badge="🟠 HIGH    " ;;
        WARNING)  badge="🟡 WARNING " ;;
        INFO)     badge="🔵 INFO    " ;;
      esac

      echo "│                                                              │"
      printf "│  %s [%s]%*s│\n" "$badge" "$f_id" $((42 - ${#f_id})) ""

      local_ref="${f_file}:${f_line}"
      if [[ ${#local_ref} -gt 56 ]]; then
        local_ref="...${local_ref: -53}"
      fi
      printf "│  📄 %-57s│\n" "$local_ref"

      if [[ ${#f_msg} -gt 57 ]]; then
        f_msg="${f_msg:0:54}..."
      fi
      printf "│  💬 %-57s│\n" "$f_msg"

      local_content=$(echo "$f_content" | sed 's/^[[:space:]]*//' | cut -c1-54)
      printf "│  ┊  %-57s│\n" "$local_content"
    fi
  done < "$FINDINGS_FILE"
done

echo "│                                                              │"
echo "└──────────────────────────────────────────────────────────────┘"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Total: $TOTAL_FINDINGS finding(s)"

# Check if any blocking severity found
HAS_BLOCKING=false
while IFS='§' read -r f_sev _rest; do
  for block_sev in $SEVERITY_BLOCK_LIST; do
    if [[ "$f_sev" == "$block_sev" ]]; then
      HAS_BLOCKING=true
      break 2
    fi
  done
done < "$FINDINGS_FILE"

if [[ "$HAS_BLOCKING" == "true" ]]; then
  echo ""
  echo "❌ Gate BLOQUEADO — findings CRITICAL/HIGH requerem revisão."
  echo ""
  echo "Para fazer override, adicione ao PR body:"
  echo '  <!-- chama:allow RULE_ID: justificativa -->'
  exit 1
fi

if [[ $WARNING_COUNT -gt 0 ]]; then
  echo ""
  echo "⚠ Warnings detectados — revise antes de continuar."
  exit 2
fi

# Only INFO findings
echo ""
echo "ℹ Apenas findings informativos — nenhuma ação necessária."
exit 0
