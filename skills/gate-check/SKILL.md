---
description: Run Critical Gate analysis on working tree or specific commit
---

# Critical Gate Check (Standalone)

Run the Critical Gate engine to analyze diffs for destructive/dangerous operations. This is an **informational** mode — it reports findings but does not block operations.

## Idioma
Read `project.language` from `.chama.yml`. Respond in the configured language. Default: pt-BR.

## Usage

- Without arguments: analyzes the current working tree diff (`git diff`)
- With `--commit <commitID>`: analyzes the diff of a specific commit vs its predecessor

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
```

## Execution

### Resolve gate script path

```bash
if [ -d "chama/scripts" ]; then
  GATE_SCRIPT="chama/scripts/run-critical-gate.sh"
elif [ -d "${HOME}/.claude/plugins/chama/scripts" ]; then
  GATE_SCRIPT="${HOME}/.claude/plugins/chama/scripts/run-critical-gate.sh"
else
  GATE_SCRIPT="scripts/run-critical-gate.sh"
fi
```

### Run the gate

If the user provided a `--commit <commitID>` argument:

```bash
bash "$GATE_SCRIPT" --mode standalone --commit <commitID>
GATE_EXIT=$?
```

If no argument was provided (working tree diff):

```bash
bash "$GATE_SCRIPT" --mode standalone
GATE_EXIT=$?
```

### Interpret results

Present the gate output to the user with context:

- `0` (clean): report that no critical operations were detected.
- `1` (CRITICAL/HIGH findings): show all findings with severity, rule ID, file, line, and message. Explain what each finding means and suggest how to address it.
- `2` (warnings only): show warnings and explain their nature. Note that these are non-blocking.
- `3` (error): report the error and suggest troubleshooting steps (e.g., check `.chama.yml` configuration, verify `yq` is installed).

### Important

- This skill is **informational only** — it does not block commits or merges.
- Exit codes are returned for automation purposes but the skill itself does not enforce blocking.
- The user can use this to pre-check changes before committing or to audit a specific commit.
