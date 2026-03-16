---
description: Handle PR comments in loop, scoped by Spec
---

# PR Review Loop (Spec-Scoped)

You are an execution agent focused on **handling PR comments in a loop**.
Your goal is to reduce actionable comments without leaving the Spec scope.

## Idioma
Read `project.language` from `.chama.yml`. Respond in the configured language. Default: pt-BR.

## Mandatory principles
- Fix **only** comments that make technical sense and are in scope.
- Do not leave the Spec.
- Do not do large unsolicited refactors.
- If a comment is invalid or out of Spec scope, respond with objective justification.

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
OWNER="${CHAMA_OWNER:-$(yq '.github.owner' .chama.yml 2>/dev/null)}"
PROJECT_NUM="${CHAMA_PROJECT_NUMBER:-$(yq '.github.project_number' .chama.yml 2>/dev/null)}"
REVIEWS_DIR="${CHAMA_REVIEWS_DIR:-$(yq '.artifacts.reviews_dir' .chama.yml 2>/dev/null || echo '.chama/reviews')}"

# Board statuses (configurable via .chama.yml, with defaults)
STATUS_DONE=$(yq '.github.board_statuses.done // "Done"' .chama.yml 2>/dev/null || echo 'Done')
```

## Inputs
- `PR_NUMBER` (required)
- `MAX_ROUNDS` (optional, default: `4`)
- `QUIET_ROUNDS_TO_STOP` (optional, default: `2`)
  How many consecutive rounds without new actionable comments to stop.

## References
- Spec from the PR (extracted from PR body or linked issue)

## 0) Quick setup

```bash
PR_NUMBER="${PR_NUMBER:-<define>}"
MAX_ROUNDS="${MAX_ROUNDS:-4}"
QUIET_ROUNDS_TO_STOP="${QUIET_ROUNDS_TO_STOP:-2}"

[ -z "$PR_NUMBER" ] && echo "PR_NUMBER required" && exit 1

mkdir -p "$REVIEWS_DIR"
STATE_FILE="$REVIEWS_DIR/pr-${PR_NUMBER}-handled-comments.txt"
touch "$STATE_FILE"
```

## 1) Discover Spec and lock scope
1. Extract Spec from PR body.
2. If not found in PR, search linked issues.
3. If still not found, stop and ask for human confirmation.

```bash
PR_BODY=$(gh pr view "$PR_NUMBER" --json body --jq '.body')
SPEC_NUMBER=$(printf '%s\n' "$PR_BODY" | grep -oP '#\K\d+' | head -1)

if [ -n "$SPEC_NUMBER" ]; then
  gh issue view "$SPEC_NUMBER" --repo "$REPO"
fi
```

Rule:
- Everything not aligned with the Spec is **out of scope** in this iteration.

## 2) Review loop
Execute from `ROUND=1` to `MAX_ROUNDS`.

In each round:

### 2.1 Collect comments (3 sources)
```bash
gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" > "$REVIEWS_DIR/pr-${PR_NUMBER}-reviews.json"
gh api "repos/$REPO/pulls/$PR_NUMBER/comments" > "$REVIEWS_DIR/pr-${PR_NUMBER}-pull-comments.json"
gh api "repos/$REPO/issues/$PR_NUMBER/comments" > "$REVIEWS_DIR/pr-${PR_NUMBER}-issue-comments.json"
```

### 2.2 Identify only new comments
- Consider new comments by `id` not yet in `STATE_FILE`.
- Ignore author's own comments when they are not change requests.

### 2.3 Classify A/B/C
- `A` Mandatory: bug, regression, contract break, real risk.
- `B` Valid small: safe improvement within the Spec.
- `C` Do not apply: outside Spec, outdated, or without evidence.

### 2.4 Act per class
- `A/B`: fix with small, traceable commits.
- `C`: respond in the comment explaining objectively why it won't be applied.

### 2.5 Scope guardrail (Spec)
Before each fix, validate:
- Is the change covered in the Spec?
- Does it not introduce broad restructuring?
- Does it maintain Spec acceptance criteria?

If not, don't implement; respond as `C`.

### 2.6 Validate and push
- Run relevant quality gates from `.chama.yml`.
- Commit/push fixes.
- Respond in the comment with the commit hash.

### 2.7 Wait and reassess
- Wait briefly (e.g., 2-5 min) for new comments.
- Repeat collection.

## 3) Stop criteria
Stop when one of:
1. No new actionable comments for `QUIET_ROUNDS_TO_STOP` consecutive rounds.
2. Reached `MAX_ROUNDS`.
3. All checks green and PR ready to merge before `MAX_ROUNDS`.

## 4) Closure

### 4.1 If completed before MAX_ROUNDS (success)
Condition:
- No new actionable comments.
- CI/checks green.
- PR mergeable.

Execute:
```bash
gh pr checks "$PR_NUMBER" --watch
gh pr merge "$PR_NUMBER" --squash --delete-branch
```

Move item to `Done` in Project:
```bash
ISSUE_NUMBER=$(gh pr view "$PR_NUMBER" --json body --jq '.body' \
  | grep -oP 'Closes #\K\d+' | head -1)
if [ -n "$ISSUE_NUMBER" ]; then
  PROJECT_ID=$(gh project list --owner "$OWNER" --format json \
    | jq -r ".projects[] | select(.number == $PROJECT_NUM) | .id")
  ITEM_ID=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json \
    | jq -r ".items[] | select(.content.number == $ISSUE_NUMBER) | .id")
  FIELD_ID=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json \
    | jq -r '.fields[] | select(.name == "Status") | .id')
  OPTION_ID_DONE=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json \
    | jq -r --arg status "$STATUS_DONE" '.fields[] | select(.name == "Status") | .options[] | select(.name == $status) | .id')
  gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" \
    --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID_DONE"
fi
```

### 4.2 If not completed (stopped by limit or blocker)
Register in progress file:
- PR and final round
- Comments handled (A/B/C)
- What was fixed (commits)
- What remains pending and why
- If pending item is out of Spec scope

If stopped by `MAX_ROUNDS` and there are still pending items:
- Leave a comment on the PR with pending items, risk and proposed next step (new issue/task).

## Expected result
- PR with actionable comments reduced.
- Scope preserved by the Spec.
- Loop executed with transparency and traceability.
