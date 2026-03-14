# Simplify Agent — Compose Mode (Headless)

Review the changed code on the current branch for clarity, consistency and maintainability, preserving **all** existing functionality.

## Scope
- Focus **only** on files changed in this branch compared to `main`.
- Respect the patterns of each component as defined in `CLAUDE.md` files.

## What to check
1. **Reuse**: duplicated code that can be consolidated within the branch scope.
2. **Quality**: clear names, cohesive functions, no introduced dead code.
3. **Efficiency**: N+1 queries, unnecessary loops, avoidable allocations.
4. **Consistency**: project patterns (error handling, naming, imports).
5. **Tests**: adequate coverage for new/changed code.

## What NOT to do
- Don't change functionality.
- Don't add features or expand scope.
- Don't refactor pre-existing code that wasn't touched in the branch.
- Don't move files or rename packages unnecessarily.

## Headless Mode
- **DO NOT** use slash commands (`/simplify`, `/commit`, etc).
- **DO NOT** push.
- If there's nothing to simplify, say "No simplification needed" and stop.

## Steps

1. List changed files:
```bash
git diff main --name-only
```

2. Review each changed file, applying the checks above.

3. After changes, run quality gates from `.chama.yml` for affected components:
```bash
COMPONENTS=$(yq '.tech_stack.components[].name' .chama.yml 2>/dev/null)

for COMPONENT in $COMPONENTS; do
  COMPONENT_PATH=$(yq ".tech_stack.components[] | select(.name == \"$COMPONENT\") | .path" .chama.yml 2>/dev/null)

  if git diff main --name-only | grep -q "^$COMPONENT_PATH"; then
    echo "Running quality gates for $COMPONENT..."
    GATES=$(yq ".tech_stack.components[] | select(.name == \"$COMPONENT\") | .quality_gates[]" .chama.yml 2>/dev/null)
    while IFS= read -r gate; do
      eval "$gate"
    done <<< "$GATES"
  fi
done
```

4. Commit simplifications separately:
```bash
git add <files>
git commit -m "refactor: simplify <description>"
```

If quality gates fail after simplification: fix and repeat.
