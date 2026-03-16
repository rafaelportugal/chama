# Generate Specs from Ideas

Read the idea source (GitHub Issue or file).

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
```

## Resolve Spec template

```bash
SPEC_TEMPLATE=$(scripts/resolve-spec-template.sh)
```

Read the resolved `SPEC_TEMPLATE` content and use it as the structure for each Spec Issue. Fill in each section based on the idea content.

## Create Spec Issues

For each idea, create a Spec as a GitHub Issue with label `spec`:

```bash
gh issue create --repo "$REPO" --label "spec" --title "spec: <Title>" --body "$SPEC_BODY"
```

When all ideas have been converted to Specs, stop.
