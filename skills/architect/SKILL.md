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

## Knowledge paths (optional)

Read `knowledge_paths` from `.chama.yml`. If the field is absent or empty, skip this section entirely (backward compatible).

```bash
KNOWLEDGE_PATHS=$(yq '.knowledge_paths[]' .chama.yml 2>/dev/null)
```

For each path in `KNOWLEDGE_PATHS`:

1. **Check existence** — if the path does not exist, skip it silently and move to the next.
2. **List eligible files** — find files with extensions `.md`, `.yml`, `.yaml`, `.txt`:
```bash
FILES=$(find "$KPATH" -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" -o -name "*.txt" \) 2>/dev/null)
FILE_COUNT=$(echo "$FILES" | grep -c . 2>/dev/null || echo 0)
TOTAL_KB=$(echo "$FILES" | xargs du -k 2>/dev/null | tail -1 | awk '{print $1}')
# For individual files, sum their sizes:
TOTAL_KB=$(echo "$FILES" | xargs du -k 2>/dev/null | awk '{s+=$1} END {print s+0}')
```
3. **Apply progressive strategy**:
   - **≤10 files AND ≤100KB** → read all files, no alerts.
   - **11–15 files OR 101–200KB** → read all files + emit **WARNING**: `"⚠️ WARNING: Knowledge path '<path>' has <N> files (<X>KB). Consider using more specific paths to reduce context size."`
   - **>15 files OR >200KB** → **skip the entire path** + emit **CRITICAL**: `"🚫 CRITICAL: Knowledge path '<path>' ignored (<N> files, <X>KB). Exceeds limits (max 15 files or 200KB). Reorganize into more specific paths."`
4. **Incorporate content** — for approved paths, read each file and incorporate its content as domain context. This context informs architectural decisions in steps 1 and 2.

Present a summary of knowledge paths processing before proceeding:
```
Knowledge paths summary:
  - docs/architecture/ → 5 files (32KB) ✅
  - docs/domain/ → 12 files (150KB) ⚠️ WARNING
  - docs/all/ → 25 files (500KB) 🚫 SKIPPED
```

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

```bash
SPEC_TEMPLATE=$(scripts/resolve-spec-template.sh)
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
