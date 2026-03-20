---
description: Execute next Todo task with quality gates
---

# Execute Next Task

You are an experienced executor agent. Your goal is to complete **a single task per iteration**, always based on the next `Todo` issue from the Project.

## Idioma
Read `project.language` from `.chama.yml`. Respond in the configured language. Default: pt-BR.

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
OWNER="${CHAMA_OWNER:-$(yq '.github.owner' .chama.yml 2>/dev/null)}"
PROJECT_NUM="${CHAMA_PROJECT_NUMBER:-$(yq '.github.project_number' .chama.yml 2>/dev/null)}"
PROGRESS_DIR="${CHAMA_PROGRESS_DIR:-$(yq '.artifacts.progress_dir' .chama.yml 2>/dev/null || echo '.chama/progress')}"
REVIEWS_DIR="${CHAMA_REVIEWS_DIR:-$(yq '.artifacts.reviews_dir' .chama.yml 2>/dev/null || echo '.chama/reviews')}"
DEFAULT_BRANCH="${CHAMA_DEFAULT_BRANCH:-$(yq '.github.default_branch' .chama.yml 2>/dev/null || echo 'main')}"

# Board statuses (configurable via .chama.yml, with defaults)
STATUS_TODO=$(yq '.github.board_statuses.todo // "Todo"' .chama.yml 2>/dev/null || echo 'Todo')
STATUS_IN_PROGRESS=$(yq '.github.board_statuses.in_progress // "In Progress"' .chama.yml 2>/dev/null || echo 'In Progress')
STATUS_IN_REVIEW=$(yq '.github.board_statuses.in_review // "In Review"' .chama.yml 2>/dev/null || echo 'In Review')
```

## References
- `.chama.yml` (project config, tech stack, quality gates)
- `CLAUDE.md` (root and per-component — auto-loaded)
- Spec: extracted from the issue body (section `## Spec`)

## Operational Rules
- Execute **only 1 issue** per iteration.
- Do not skip steps: identify -> setup -> implement -> validate -> PR -> CI/CD -> finalize.
- Respect `CLAUDE.md` of each changed component.
- Small, descriptive commits aligned to the issue checklist.
- If validation fails, fix and re-validate.

## 0) Pre-check

```bash
gh auth status
jq --version
git status --short
```

If `gh auth status` fails, stop and request authentication.

## 1) Identify Next Task

Select `Todo` issue from the Project, ordering by `priority` and then by number.

```bash
ISSUE_NUMBER=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json \
  | jq -r --arg status "$STATUS_TODO" '
    [.items[]
      | select(.content)
      | select(.content.type == "Issue")
      | select(.status == $status)
      | {
          number: .content.number,
          priority_rank: (
            if (.priority // "") | test("^P[0-9]+$") then
              ((.priority | ltrimstr("P")) | tonumber)
            else
              999
            end
          )
        }
    ]
    | sort_by(.priority_rank, .number)
    | .[0].number // empty')

[ -z "$ISSUE_NUMBER" ] && echo "No eligible issue with Todo status." && exit 0

gh issue view "$ISSUE_NUMBER" --repo "$REPO"
```

Extract Spec from the issue body:

```bash
ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json body --jq '.body')

# Extract Spec issue number from body
SPEC_NUMBER=$(printf '%s\n' "$ISSUE_BODY" \
  | grep -oP '#\K\d+' \
  | head -1)

# Read Spec issue if referenced
if [ -n "$SPEC_NUMBER" ]; then
  gh issue view "$SPEC_NUMBER" --repo "$REPO"
fi
```

Read the Spec before implementing.

## 2) Setup

Create branch and move item to `$STATUS_IN_PROGRESS`.

```bash
BRANCH_NAME="feat/issue-$ISSUE_NUMBER"
git checkout -b "$BRANCH_NAME"

PROJECT_ID=$(gh project list --owner "$OWNER" --format json | jq -r ".projects[] | select(.number == $PROJECT_NUM) | .id")
ITEM_ID=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r ".items[] | select(.content.number == $ISSUE_NUMBER) | .id")
FIELD_ID=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r '.fields[] | select(.name == "Status") | .id')
OPTION_ID_IN_PROGRESS=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r --arg status "$STATUS_IN_PROGRESS" '.fields[] | select(.name == "Status") | .options[] | select(.name == $status) | .id')

gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID_IN_PROGRESS"
```

Verify the task is in `$STATUS_IN_PROGRESS`. If not, STOP and show the error.

## 3) Implement

- Follow the issue checklist + Spec requirements and acceptance criteria.
- Do not expand scope without registering in the progress file.
- Commit per logical block.
- After each commit, trigger automatic commit review in parallel.

Before committing, run `/simplify` to simplify and refine the code.

### 3.1) Critical Gate (pre-commit)

Stage files first, then run the Critical Gate (which inspects `git diff --cached`):

```bash
git add <files>
```

```bash
# Discover chama plugin path
if [ -d "chama/scripts" ]; then
  GATE_SCRIPT="chama/scripts/run-critical-gate.sh"
elif [ -d "${HOME}/.claude/plugins/chama/scripts" ]; then
  GATE_SCRIPT="${HOME}/.claude/plugins/chama/scripts/run-critical-gate.sh"
else
  GATE_SCRIPT="scripts/run-critical-gate.sh"
fi

bash "$GATE_SCRIPT" --mode pre-commit
GATE_EXIT=$?
```

**Handle exit codes:**
- `0` (clean): proceed normally with the commit.
- `1` (CRITICAL/HIGH): **STOP**. Do NOT commit. Unstage with `git reset HEAD` and show the findings to the user. Instruct the user to fix the flagged issues before retrying the commit.
- `2` (warnings): show the warnings and ask for user confirmation before proceeding with the commit.
- `3` (error): warn the user about the gate error but allow the commit to proceed (fail-open).

```bash
git commit -m "feat: <objective description>"
```

## 4) Validate

Run quality gates dynamically from `.chama.yml`:

```bash
# Read quality gates from config
COMPONENTS=$(yq '.tech_stack.components[].name' .chama.yml 2>/dev/null)

for COMPONENT in $COMPONENTS; do
  COMPONENT_PATH=$(yq ".tech_stack.components[] | select(.name == \"$COMPONENT\") | .path" .chama.yml 2>/dev/null)

  # Check if any files were changed in this component
  if git diff "$DEFAULT_BRANCH" --name-only | grep -q "^$COMPONENT_PATH"; then
    echo "Running quality gates for $COMPONENT..."
    GATES=$(yq ".tech_stack.components[] | select(.name == \"$COMPONENT\") | .quality_gates[]" .chama.yml 2>/dev/null)
    while IFS= read -r gate; do
      echo "  Running: $gate"
      eval "$gate"
    done <<< "$GATES"
  fi
done
```

If any command fails: fix -> repeat step 4.

## 5) Create PR

With local validations ok:

```bash
mkdir -p "$PROGRESS_DIR"
PROGRESS_FILE="$PROGRESS_DIR/$(date +%Y%m%d-%H%M)-${BRANCH_NAME//\//-}.txt"

git push -u origin "$BRANCH_NAME"

gh pr create --title "feat: [Issue #$ISSUE_NUMBER] <title>" \
  --body "Closes #$ISSUE_NUMBER

## Spec
- #$SPEC_NUMBER

## Summary
<objective description>

## Checklist
<completed items>"

PR_NUMBER=$(gh pr view --json number --jq '.number')

# Move item to "In Review"
OPTION_ID_IN_REVIEW=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r --arg status "$STATUS_IN_REVIEW" '.fields[] | select(.name == "Status") | .options[] | select(.name == $status) | .id')
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID_IN_REVIEW"
```

## 6) Verify CI/CD

```bash
gh pr checks --watch
```

If it fails: fix -> commit/push -> watch again.

## 7) Finalize

After CI/CD green and reviews approved:

```bash
gh pr view "$PR_NUMBER" --comments
gh api "repos/$REPO/pulls/$PR_NUMBER/reviews"
gh api "repos/$REPO/pulls/$PR_NUMBER/comments"
```

For post-review comment handling, use:
- `/chama:review-loop`

## 8) Stop
Do not advance to the next issue in this iteration.
