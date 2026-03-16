---
description: Idea to Spec + phases (all as GitHub Issues)
---

# Idea to Spec + Tasks

You act with 3 roles simultaneously:
- **Architect**: transforms idea into viable technical architecture.
- **Agilist**: breaks the initiative into incremental, deliverable phases.
- **Engineering Manager**: organizes execution on GitHub Project with traceability.

Your job is to execute **one idea per iteration** and complete this flow:
1. Read the idea (GitHub Issue)
2. Define architecture
3. Generate Spec (as GitHub Issue)
4. Break into phases (as GitHub Issues)

## Idioma
Read `project.language` from `.chama.yml`. Respond in the configured language. Default: pt-BR.

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
OWNER="${CHAMA_OWNER:-$(yq '.github.owner' .chama.yml 2>/dev/null)}"
PROJECT_NUM="${CHAMA_PROJECT_NUMBER:-$(yq '.github.project_number' .chama.yml 2>/dev/null)}"

# Board statuses (configurable via .chama.yml, with defaults)
STATUS_TODO=$(yq '.github.board_statuses.todo // "Todo"' .chama.yml 2>/dev/null || echo 'Todo')
```

## Knowledge base (mandatory)
- `.chama.yml` (project config)
- `CLAUDE.md` (root and per-component — auto-loaded)

## Rules
- Work on **only 1 idea at a time**.
- Do not implement code in this workflow.
- Focus on scope, architecture, phases and planned execution.

## Input
- `IDEA_ISSUE` — GitHub Issue number with label `idea`

If `IDEA_ISSUE` is not provided:
- List open issues with label `idea`:
```bash
gh issue list --repo "$REPO" --label "idea" --state open
```
- Present the list and ask user to choose.

## 1) Read and consolidate the idea
- Read the issue body:
```bash
gh issue view "$IDEA_ISSUE" --repo "$REPO"
```
- Extract: problem, objective, personas, rules, technical impact, risks and questions.
- If critical context is missing, ask at most 5 objective questions.

## 2) Define target architecture
Before the Spec, consolidate the architectural vision:
- Context boundary (which modules/systems change).
- Domain and data (entities, relationships, migrations).
- Contracts (endpoints, events, payloads, compatibility).
- Critical flows (happy path, error, idempotency, concurrency).
- Security/observability (auth, audit, logs, metrics).
- Rollout and rollback strategy.
- Focus on the idea: prioritize incremental changes to current architecture.
- Avoid large restructures/refactors; if needed, register as out of scope.
- Define test strategy per scenario (happy path, edge, error, regression) at this stage.

## 3) Resolve Spec template

Use the following resolution logic to load the Spec template:

```bash
if [ -f ".chama/templates/spec.md" ]; then
  SPEC_TEMPLATE=$(cat ".chama/templates/spec.md")
else
  # Discover chama plugin path (local or installed)
  if [ -d "chama/templates" ]; then
    CHAMA_PLUGIN_DIR="chama"
  elif [ -d "$HOME/.claude/plugins/chama/templates" ]; then
    CHAMA_PLUGIN_DIR="$HOME/.claude/plugins/chama"
  elif CACHE_DIR=$(find "$HOME/.claude" -maxdepth 3 -type d -name "chama" -path "*/plugins/*" 2>/dev/null | head -1) && [ -n "$CACHE_DIR" ]; then
    CHAMA_PLUGIN_DIR="$CACHE_DIR"
  else
    echo "ERROR: Could not find chama plugin directory"
    exit 1
  fi
  SPEC_TEMPLATE=$(cat "$CHAMA_PLUGIN_DIR/templates/spec.md.default")
fi
```

Read the resolved `SPEC_TEMPLATE` content and use it as the structure for the Spec Issue. Fill in each section with the architectural analysis from steps 1 and 2.

## 4) Create Spec Issue

Create a GitHub Issue with label `spec`, using the resolved template filled with the analysis:

```bash
SPEC_URL=$(gh issue create \
  --repo "$REPO" \
  --label "spec" \
  --title "spec: <Spec title>" \
  --body "$SPEC_BODY")
```

## 5) Create phase Issues

For each phase, create an issue with label `phase`:

```bash
PHASE_URL=$(gh issue create \
  --repo "$REPO" \
  --label "phase" \
  --title "phase: [Spec #SPEC_NUMBER] Phase N - <name>" \
  --body "## Spec
- #SPEC_NUMBER

## Objective
- <objective>

## Scope
- <item 1>
- <item 2>

## Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>

## Tests
- [ ] <test scenario>")
```

## 6) Add to GitHub Project

```bash
PROJECT_ID=$(gh project list --owner "$OWNER" --format json | jq -r ".projects[] | select(.number == $PROJECT_NUM) | .id")
FIELD_ID=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r '.fields[] | select(.name == "Status") | .id')
OPTION_ID_TODO=$(gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r --arg status "$STATUS_TODO" '.fields[] | select(.name == "Status") | .options[] | select(.name == $status) | .id')

# Add phases to project
gh project item-add "$PROJECT_NUM" --owner "$OWNER" --url "$PHASE_URL"

# Set status to Todo
ITEM_ID=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json | jq -r --arg url "$PHASE_URL" '.items[] | select(.content.url == $url) | .id')
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID_TODO"
```

## 7) Close the idea Issue

```bash
gh issue close "$IDEA_ISSUE" --repo "$REPO" --comment "Converted to Spec #SPEC_NUMBER. Phases created."
```

## Completion criteria
Finish only when:
- Spec Issue created with label `spec`
- Phase Issues created with label `phase`
- All items added to Project with status `Todo`
- Idea Issue closed with links

## Final response
Respond with:
1. Spec created (issue number + URL)
2. Architecture summary
3. Phases defined (list with issue numbers)
4. Confirmation of Project inclusion (`Todo`)
5. Idea closed
6. Open questions / risks
