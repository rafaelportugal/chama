# Generate Specs from Ideas

Read the idea source (GitHub Issue or file).

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
```

## Resolve Spec template

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

Read the resolved `SPEC_TEMPLATE` content and use it as the structure for each Spec Issue. Fill in each section based on the idea content.

## Create Spec Issues

For each idea, create a Spec as a GitHub Issue with label `spec`:

```bash
gh issue create --repo "$REPO" --label "spec" --title "spec: <Title>" --body "$SPEC_BODY"
```

When all ideas have been converted to Specs, stop.
