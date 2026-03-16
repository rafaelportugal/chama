#!/usr/bin/env bash
set -euo pipefail

# ─── Chama Pipeline ─────────────────────────────────────────────────────────
# Orchestrates the full SDLC cycle: coder → simplify → PR → pr-reviewer → review-loop
# Usage: MAX_TASKS=3 MAX_REVIEW_ROUNDS=4 STOP_ON_REVIEW_FAILURE=true bash chama-pipeline.sh
# ─────────────────────────────────────────────────────────────────────────────

ROOT_DIR="$(git rev-parse --show-toplevel)"
MAX_TASKS="${MAX_TASKS:-3}"
MAX_REVIEW_ROUNDS="${MAX_REVIEW_ROUNDS:-4}"
STOP_ON_REVIEW_FAILURE="${STOP_ON_REVIEW_FAILURE:-true}"

# ─── Discover chama plugin path ─────────────────────────────────────────────
# Check for local chama/ directory first, then global plugin
if [[ -d "$ROOT_DIR/chama/workflow" ]]; then
  CHAMA_DIR="$ROOT_DIR/chama"
elif [[ -d "$HOME/.claude/plugins/chama/workflow" ]]; then
  CHAMA_DIR="$HOME/.claude/plugins/chama"
else
  echo "ERROR: chama plugin not found (local or global)." >&2
  exit 1
fi

PROMPT_DIR="$CHAMA_DIR/workflow"
CODER_PROMPT="$PROMPT_DIR/prompt-compose-coder.md"
SIMPLIFY_PROMPT="$PROMPT_DIR/prompt-compose-simplify.md"
PR_REVIEWER_PROMPT="$PROMPT_DIR/prompt-pr-reviewer.md"
REVIEW_LOOP_PROMPT="$PROMPT_DIR/prompt-review-loop.md"

# ─── Read config from .chama.yml ────────────────────────────────────────────
REPO="${CHAMA_REPO:-$(yq '.project.repo' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo '')}"
OWNER="${CHAMA_OWNER:-$(yq '.github.owner' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo '')}"
PROJECT_NUM="${CHAMA_PROJECT_NUMBER:-$(yq '.github.project_number' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo '1')}"
PROGRESS_DIR="${CHAMA_PROGRESS_DIR:-$(yq '.artifacts.progress_dir' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo '.chama/progress')}"
REVIEWS_DIR="${CHAMA_REVIEWS_DIR:-$(yq '.artifacts.reviews_dir' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo '.chama/reviews')}"
DEFAULT_BRANCH="${CHAMA_DEFAULT_BRANCH:-$(yq '.github.default_branch' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo 'main')}"

# Board statuses (configurable via .chama.yml, with defaults)
STATUS_TODO=$(yq '.github.board_statuses.todo // "Todo"' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo 'Todo')
STATUS_IN_REVIEW=$(yq '.github.board_statuses.in_review // "In Review"' "$ROOT_DIR/.chama.yml" 2>/dev/null || echo 'In Review')

LOG_DIR="$ROOT_DIR/$PROGRESS_DIR"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
COMPOSE_LOG="$LOG_DIR/compose-${RUN_ID}.txt"

mkdir -p "$LOG_DIR" "$ROOT_DIR/$REVIEWS_DIR"

# ─── Helpers ─────────────────────────────────────────────────────────────────

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$COMPOSE_LOG"
}

run_claude() {
  local prompt_file="$1"
  local phase_log="$2"

  log "  Output: $phase_log"

  if command -v claude >/dev/null 2>&1; then
    cat "$prompt_file" | claude -p --dangerously-skip-permissions 2>&1 | tee "$phase_log"
    return "${PIPESTATUS[1]}"
  fi

  if [[ -f "$CHAMA_DIR/agent/docker-compose.yml" ]] && command -v docker >/dev/null 2>&1; then
    docker compose -f "$CHAMA_DIR/agent/docker-compose.yml" exec -T agent-container \
      bash -c "cat '$prompt_file' | claude -p --dangerously-skip-permissions" 2>&1 | tee "$phase_log"
    return "${PIPESTATUS[0]}"
  fi

  log "ERROR: claude not found (local or container)."
  return 127
}

has_todo_items() {
  local count
  count=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json \
    | jq --arg status "$STATUS_TODO" '[.items[]
        | select(.content)
        | select(.content.type == "Issue")
        | select(.status == $status)
      ] | length')
  [[ "$count" -gt 0 ]]
}

# ─── Phase: PR (pure shell) ─────────────────────────────────────────────────

create_pr() {
  local issue_number="$1"
  local branch_name="$2"
  local phase_log="$3"

  log "  Output: $phase_log"
  {
    set -euo pipefail

    # Extract Spec reference from issue body
    local issue_body
    issue_body=$(gh issue view "$issue_number" --repo "$REPO" --json body --jq '.body')

    local spec_ref
    spec_ref=$(printf '%s\n' "$issue_body" | grep -oP '#\K\d+' | head -1 || echo "")

    # Extract issue title
    local issue_title
    issue_title=$(gh issue view "$issue_number" --repo "$REPO" --json title --jq '.title')

    # Build commit summary from branch commits
    local commit_summary
    commit_summary=$(git log "$DEFAULT_BRANCH"..HEAD --pretty=format:'- %s' 2>/dev/null || echo "- implementation commits")

    # Progress file
    local progress_file="$LOG_DIR/$(date +%Y%m%d-%H%M)-${branch_name//\//-}.txt"
    {
      echo "Date: $(date '+%Y-%m-%d %H:%M')"
      echo "Issue: #$issue_number"
      echo "Branch: $branch_name"
      echo "Spec: ${spec_ref:+#$spec_ref}"
      echo ""
      echo "Commits:"
      git log "$DEFAULT_BRANCH"..HEAD --pretty=format:'  %h %s' 2>/dev/null || true
    } > "$progress_file"
    echo "Progress file: $progress_file"

    # Push
    echo "Pushing branch $branch_name..."
    git push -u origin "$branch_name"

    # Create PR
    echo "Creating PR..."
    gh pr create \
      --title "feat: [Issue #$issue_number] $issue_title" \
      --body "$(cat <<EOF
Closes #$issue_number

## Spec
- ${spec_ref:+#$spec_ref}

## Summary
$commit_summary

## Checklist
- [x] Implementation
- [x] Quality gates (local)
- [ ] CI/CD
- [ ] Review
EOF
)"

    local pr_number
    pr_number=$(gh pr view --json number --jq '.number')
    echo "PR #$pr_number created."

    # Request Copilot review (ignore errors — may not be available)
    gh copilot-review "$pr_number" 2>/dev/null || true

    # Move to In Review
    echo "Moving issue to $STATUS_IN_REVIEW..."
    local project_id item_id field_id option_id
    project_id=$(gh project list --owner "$OWNER" --format json | jq -r ".projects[] | select(.number == $PROJECT_NUM) | .id")
    item_id=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r ".items[] | select(.content.number == $issue_number) | .id")
    field_id=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r '.fields[] | select(.name == "Status") | .id')
    option_id=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r --arg status "$STATUS_IN_REVIEW" '.fields[] | select(.name == "Status") | .options[] | select(.name == $status) | .id')
    gh project item-edit --project-id "$project_id" --id "$item_id" --field-id "$field_id" --single-select-option-id "$option_id"
    echo "Issue #$issue_number moved to $STATUS_IN_REVIEW."

    # Wait for CI
    echo "Waiting for CI checks..."
    if ! gh pr checks "$pr_number" --watch; then
      echo "WARNING: Some CI checks failed for PR #$pr_number."
    fi

    echo "PR_NUMBER=$pr_number"
  } 2>&1 | tee "$phase_log"
}

# ─── Pre-flight checks ──────────────────────────────────────────────────────

for f in "$CODER_PROMPT" "$SIMPLIFY_PROMPT" "$PR_REVIEWER_PROMPT" "$REVIEW_LOOP_PROMPT"; do
  if [[ ! -f "$f" ]]; then
    echo "Prompt not found: $f" >&2
    exit 1
  fi
done

for cmd in gh jq yq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd not found." >&2
    exit 1
  fi
done

if [[ -z "$REPO" || "$REPO" == "null" ]]; then
  echo "ERROR: project.repo not configured. Run /init or set CHAMA_REPO." >&2
  exit 1
fi

# ─── GitHub auth (App token if configured) ─────────────────────────────────
if [[ -n "${GITHUB_APP_ID:-}" ]] && [[ -f "${GITHUB_APP_PRIVATE_KEY:-}" ]]; then
  if command -v gh-token >/dev/null 2>&1; then
    log "Generating GH_TOKEN via GitHub App (app-id=$GITHUB_APP_ID)..."
    export GH_TOKEN
    GH_TOKEN=$(gh-token generate \
      --app-id "$GITHUB_APP_ID" \
      --private-key "$GITHUB_APP_PRIVATE_KEY" \
      --install-id "$(gh-token installations --app-id "$GITHUB_APP_ID" --private-key "$GITHUB_APP_PRIVATE_KEY" | jq -r '.[0].id')" \
      | jq -r '.token')
    log "GH_TOKEN generated (expires in ~1h)."
  else
    log "WARNING: GITHUB_APP_ID set but gh-token not found. Using existing auth."
  fi
fi

# Validate gh auth
gh auth status >/dev/null 2>&1 || { log "ERROR: gh not authenticated. Use 'gh auth login' or configure GITHUB_APP_ID."; exit 1; }

# ─── Board readiness check ──────────────────────────────────────────────────
log "Checking board status configuration..."

SYNC_SCRIPT="$CHAMA_DIR/scripts/sync-board-statuses.sh"
if [[ -f "$SYNC_SCRIPT" ]]; then
  SYNC_RESULT=$(bash "$SYNC_SCRIPT" "$OWNER" "$PROJECT_NUM" "$ROOT_DIR/.chama.yml" 2>&1) || {
    log "ERROR: Board is not properly configured."
    echo "$SYNC_RESULT" | while IFS= read -r line; do log "  $line"; done
    log "Fix the board before running compose. See the link above."
    exit 1
  }
  log "Board statuses: OK"
else
  log "WARNING: sync-board-statuses.sh not found at $SYNC_SCRIPT. Skipping board check."
fi

# ─── Pending items summary ──────────────────────────────────────────────────
TODO_COUNT=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json \
  | jq --arg status "$STATUS_TODO" '[.items[]
      | select(.content)
      | select(.content.type == "Issue")
      | select(.status == $status)
    ] | length' 2>/dev/null || echo "?")

log "Pending $STATUS_TODO items: $TODO_COUNT (will process up to $MAX_TASKS)"

if [[ "$TODO_COUNT" == "0" ]]; then
  log "No $STATUS_TODO items found. Nothing to do."
  exit 0
fi

log "=== Compose started: MAX_TASKS=$MAX_TASKS MAX_REVIEW_ROUNDS=$MAX_REVIEW_ROUNDS STOP_ON_REVIEW_FAILURE=$STOP_ON_REVIEW_FAILURE ==="
log "  Log dir: $LOG_DIR"
log "  Run ID: $RUN_ID"
log "  Repo: $REPO | Owner: $OWNER | Project: $PROJECT_NUM"

# ─── Main loop ───────────────────────────────────────────────────────────────

for TASK_NUM in $(seq 1 "$MAX_TASKS"); do
  TASK_START="$(date +%s)"
  log "--- Task $TASK_NUM/$MAX_TASKS ---"

  # 1. Check for items with status $STATUS_TODO
  if ! has_todo_items; then
    log "No $STATUS_TODO issues found. Finishing successfully."
    break
  fi

  # 2. Prepare workspace
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    log "ERROR: workspace has uncommitted changes. Stopping."
    exit 1
  fi

  git checkout "$DEFAULT_BRANCH"
  git pull --rebase origin "$DEFAULT_BRANCH"

  # ── Phase 1: CODER (Claude) ──────────────────────────────────────────────
  log "[Phase 1/5] CODER started..."
  CODER_LOG="$LOG_DIR/compose-${RUN_ID}-task${TASK_NUM}-1-coder.log"

  CODER_EXIT=0
  run_claude "$CODER_PROMPT" "$CODER_LOG" || CODER_EXIT=$?

  if [[ "$CODER_EXIT" -ne 0 ]]; then
    log "ERROR: CODER failed (exit $CODER_EXIT). See: $CODER_LOG"
    exit 1
  fi

  # Validate: must have commits and be on a feature branch
  BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
  COMMIT_COUNT=$(git rev-list "$DEFAULT_BRANCH"..HEAD --count 2>/dev/null || echo "0")

  if [[ "$BRANCH_NAME" == "$DEFAULT_BRANCH" ]]; then
    log "ERROR: CODER did not create feature branch. See: $CODER_LOG"
    exit 1
  fi

  if [[ "$COMMIT_COUNT" -eq 0 ]]; then
    log "ERROR: CODER made no commits. See: $CODER_LOG"
    exit 1
  fi

  # Extract issue number from branch name (feat/issue-NNN)
  ISSUE_NUMBER=$(echo "$BRANCH_NAME" | grep -oP 'issue-\K\d+' || true)
  log "[Phase 1/5] CODER completed. Branch: $BRANCH_NAME, Commits: $COMMIT_COUNT, Issue: #${ISSUE_NUMBER:-?}"

  # ── Phase 2: SIMPLIFY (Claude) ───────────────────────────────────────────
  log "[Phase 2/5] SIMPLIFY started..."
  SIMPLIFY_LOG="$LOG_DIR/compose-${RUN_ID}-task${TASK_NUM}-2-simplify.log"

  SIMPLIFY_EXIT=0
  run_claude "$SIMPLIFY_PROMPT" "$SIMPLIFY_LOG" || SIMPLIFY_EXIT=$?

  if [[ "$SIMPLIFY_EXIT" -ne 0 ]]; then
    log "WARNING: SIMPLIFY returned error (exit $SIMPLIFY_EXIT). Continuing. See: $SIMPLIFY_LOG"
  else
    log "[Phase 2/5] SIMPLIFY completed. See: $SIMPLIFY_LOG"
  fi

  # ── Phase 3: PR (pure shell) ─────────────────────────────────────────────
  log "[Phase 3/5] PR started..."
  PR_LOG="$LOG_DIR/compose-${RUN_ID}-task${TASK_NUM}-3-pr.log"

  PR_EXIT=0
  create_pr "${ISSUE_NUMBER:-0}" "$BRANCH_NAME" "$PR_LOG" || PR_EXIT=$?

  if [[ "$PR_EXIT" -ne 0 ]]; then
    log "ERROR: PR failed (exit $PR_EXIT). See: $PR_LOG"
    exit 1
  fi

  # Extract PR number from phase log
  PR_NUMBER=$(grep -oP 'PR_NUMBER=\K\d+' "$PR_LOG" | tail -1 || true)
  if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER=$(gh pr view --json number --jq '.number' 2>/dev/null || true)
  fi

  if [[ -z "$PR_NUMBER" ]]; then
    log "ERROR: no PR found after PR phase. See: $PR_LOG"
    exit 1
  fi

  log "[Phase 3/5] PR #$PR_NUMBER created (Issue #${ISSUE_NUMBER:-?})"

  # ── Phase 4: PR REVIEWER (Claude) ────────────────────────────────────────
  log "[Phase 4/5] PR-REVIEWER started (PR #$PR_NUMBER)..."
  PR_REVIEWER_LOG="$LOG_DIR/compose-${RUN_ID}-task${TASK_NUM}-4-pr-reviewer.log"

  TMP_PR_REVIEWER_PROMPT="$(mktemp)"
  sed "s/__PR_NUMBER__/${PR_NUMBER}/g" "$PR_REVIEWER_PROMPT" > "$TMP_PR_REVIEWER_PROMPT"

  PR_REVIEWER_EXIT=0
  run_claude "$TMP_PR_REVIEWER_PROMPT" "$PR_REVIEWER_LOG" || PR_REVIEWER_EXIT=$?
  rm -f "$TMP_PR_REVIEWER_PROMPT"

  if [[ "$PR_REVIEWER_EXIT" -ne 0 ]]; then
    log "WARNING: PR-REVIEWER returned error (exit $PR_REVIEWER_EXIT). Continuing. See: $PR_REVIEWER_LOG"
  else
    log "[Phase 4/5] PR-REVIEWER completed. See: $PR_REVIEWER_LOG"
  fi

  # ── Phase 5: REVIEW-LOOP (Claude) ────────────────────────────────────────
  log "[Phase 5/5] REVIEW-LOOP started (PR #$PR_NUMBER)..."
  REVIEW_LOG="$LOG_DIR/compose-${RUN_ID}-task${TASK_NUM}-5-review.log"

  TMP_REVIEW_PROMPT="$(mktemp)"
  {
    echo "PR_NUMBER=$PR_NUMBER"
    echo "MAX_ROUNDS=$MAX_REVIEW_ROUNDS"
    echo ""
    cat "$REVIEW_LOOP_PROMPT"
  } > "$TMP_REVIEW_PROMPT"

  REVIEW_EXIT=0
  run_claude "$TMP_REVIEW_PROMPT" "$REVIEW_LOG" || REVIEW_EXIT=$?
  rm -f "$TMP_REVIEW_PROMPT"

  if [[ "$REVIEW_EXIT" -ne 0 ]]; then
    log "WARNING: REVIEW-LOOP returned error (exit $REVIEW_EXIT). See: $REVIEW_LOG"
  else
    log "[Phase 5/5] REVIEW-LOOP completed. See: $REVIEW_LOG"
  fi

  # ── Verify result ────────────────────────────────────────────────────────
  PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
  TASK_END="$(date +%s)"
  DURATION=$(( TASK_END - TASK_START ))

  if [[ "$PR_STATE" == "MERGED" ]]; then
    log "Task $TASK_NUM | Issue #${ISSUE_NUMBER:-?} | PR #$PR_NUMBER | MERGED | ${DURATION}s"
    git checkout "$DEFAULT_BRANCH"
    git pull --rebase origin "$DEFAULT_BRANCH"
  else
    log "Task $TASK_NUM | Issue #${ISSUE_NUMBER:-?} | PR #$PR_NUMBER | $PR_STATE | ${DURATION}s"

    if [[ "$STOP_ON_REVIEW_FAILURE" == "true" ]]; then
      log "STOP_ON_REVIEW_FAILURE=true — stopping."
      exit 1
    fi

    log "STOP_ON_REVIEW_FAILURE=false — cleaning up and continuing..."
    git checkout "$DEFAULT_BRANCH"
    git pull --rebase origin "$DEFAULT_BRANCH"
  fi
done

log "=== Compose finished ==="
log "Logs for this run:"
log "  Compose: $COMPOSE_LOG"
ls "$LOG_DIR"/compose-${RUN_ID}-*.log 2>/dev/null | while read -r f; do
  log "  $(basename "$f"): $f"
done
