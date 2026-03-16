# Generate Specs from Ideas

Read the idea source (GitHub Issue or file).

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

## Knowledge paths (optional)

Read `knowledge_paths` from `.chama.yml`. If the field is absent or empty, skip this section entirely.

```bash
KNOWLEDGE_PATHS=$(yq '.knowledge_paths[]' .chama.yml 2>/dev/null)
```

For each path in `KNOWLEDGE_PATHS`:

1. **Check existence** — if the path does not exist, skip it silently.
2. **List eligible files** — find files with extensions `.md`, `.yml`, `.yaml`, `.txt`:
```bash
FILES=$(find "$KPATH" -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" -o -name "*.txt" \) 2>/dev/null)
FILE_COUNT=$(echo "$FILES" | grep -c . 2>/dev/null || echo 0)
TOTAL_KB=$(echo "$FILES" | xargs du -k 2>/dev/null | awk '{s+=$1} END {print s+0}')
```
3. **Apply progressive strategy**:
   - **≤10 files AND ≤100KB** → read all files, no alerts.
   - **11–15 files OR 101–200KB** → read all files + emit **WARNING**.
   - **>15 files OR >200KB** → **skip the entire path** + emit **CRITICAL**.
4. **Incorporate content** — use as domain context when filling Spec sections.

## Resolve Spec template

```bash
SPEC_TEMPLATE=$("$ROOT_DIR/scripts/resolve-spec-template.sh")
```

Read the resolved `SPEC_TEMPLATE` content and use it as the structure for each Spec Issue. Fill in each section based on the idea content and knowledge paths context.

## Create Spec Issues

For each idea, create a Spec as a GitHub Issue with label `spec`:

```bash
gh issue create --repo "$REPO" --label "spec" --title "spec: <Title>" --body "$SPEC_BODY"
```

When all ideas have been converted to Specs, stop.
