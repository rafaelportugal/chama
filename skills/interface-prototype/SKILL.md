---
description: Generate high-fidelity UI prototypes using project design system components
---

# Interface Prototype

You are a frontend prototyping agent. Your goal is to generate **functional code** using real design system components from the project, and optionally capture **high-fidelity screenshots** via Playwright.

## Idioma
Read `project.language` from `.chama.yml`. Respond in the configured language. Default: pt-BR.

## Input
- Free text describing the screen(s)/flow(s) to prototype, OR
- An issue number (e.g., `#37`) from which to extract the flow/mockups.

## 0) Read Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
DS_PATH=$(yq '.prototype.design_system_path' .chama.yml 2>/dev/null)
FRAMEWORK=$(yq '.prototype.framework // ""' .chama.yml 2>/dev/null)
OUTPUT_DIR=$(yq '.prototype.output_dir // ".chama/prototypes"' .chama.yml 2>/dev/null)
VIEWPORT_W=$(yq '.prototype.viewport.width // 1440' .chama.yml 2>/dev/null)
VIEWPORT_H=$(yq '.prototype.viewport.height // 900' .chama.yml 2>/dev/null)
```

## 1) Validate Prerequisites

Run all validations before proceeding. Stop on any blocking error.

### 1.1) Design system path configured

```bash
if [ -z "$DS_PATH" ] || [ "$DS_PATH" = "null" ]; then
  echo "ERROR: Configure 'prototype.design_system_path' no .chama.yml." >&2
  echo "" >&2
  echo "Exemplo:" >&2
  echo "  prototype:" >&2
  echo "    design_system_path: \"src/components\"" >&2
  exit 1
fi
```

### 1.2) Design system path exists

```bash
if [ ! -d "$DS_PATH" ]; then
  echo "ERROR: Nenhum componente encontrado em '$DS_PATH'." >&2
  echo "Verifique se o path está correto no .chama.yml (prototype.design_system_path)." >&2
  exit 1
fi
```

### 1.3) Project is web/app

Check that `tech_stack.components` contains at least one frontend-related component. Look for paths or names indicating frontend: `src/`, `app/`, `pages/`, `components/`, `web/`, `frontend/`, or frameworks like `react`, `vue`, `angular`, `next`, `nuxt`, `svelte`.

```bash
COMPONENTS=$(yq '.tech_stack.components[].path' .chama.yml 2>/dev/null)
TECH_SUMMARY=$(yq '.tech_stack.summary' .chama.yml 2>/dev/null)

# Check if any component path or tech summary suggests frontend/web/app
HAS_FRONTEND=false
for pattern in src/ app/ pages/ components/ web/ frontend/; do
  if echo "$COMPONENTS" | grep -qi "$pattern"; then
    HAS_FRONTEND=true
    break
  fi
done

if [ "$HAS_FRONTEND" = "false" ]; then
  if echo "$TECH_SUMMARY" | grep -qiE 'react|vue|angular|next|nuxt|svelte|frontend|web|app'; then
    HAS_FRONTEND=true
  fi
fi

if [ "$HAS_FRONTEND" = "false" ]; then
  echo "ERROR: Este skill funciona apenas com projetos web/app." >&2
  echo "Tech stack detectada: $TECH_SUMMARY" >&2
  echo "Componentes: $COMPONENTS" >&2
  exit 1
fi
```

### 1.4) Playwright availability (non-blocking)

```bash
PLAYWRIGHT_AVAILABLE=false
if command -v npx >/dev/null 2>&1 && npx playwright --version >/dev/null 2>&1; then
  PLAYWRIGHT_AVAILABLE=true
else
  echo "AVISO: Playwright não encontrado. Screenshots não serão gerados." >&2
  echo "Para instalar: npm install -D playwright && npx playwright install chromium" >&2
  echo "Continuando apenas com geração de código..." >&2
fi
```

## 2) Inventory Design System

Read components from the design system path and build an inventory for context.

### Auto-detect framework (if not configured)

```bash
if [ -z "$FRAMEWORK" ] || [ "$FRAMEWORK" = "null" ]; then
  if find "$DS_PATH" -name "*.tsx" -o -name "*.jsx" | head -1 | grep -q .; then
    FRAMEWORK="react"
  elif find "$DS_PATH" -name "*.vue" | head -1 | grep -q .; then
    FRAMEWORK="vue"
  elif find "$DS_PATH" -name "*.svelte" | head -1 | grep -q .; then
    FRAMEWORK="svelte"
  else
    FRAMEWORK="html"
  fi
fi
```

### Read component inventory

Based on the detected framework:

**React** (`*.tsx`, `*.jsx`):
- List all exported component names from files in `$DS_PATH`
- Read export lines: `export default`, `export const`, `export function`
- Capture component names and file paths

**Vue** (`*.vue`):
- List all `.vue` SFC filenames in `$DS_PATH`
- Component name = filename without extension

**Svelte** (`*.svelte`):
- List all `.svelte` filenames in `$DS_PATH`
- Component name = filename without extension

**HTML/CSS** (fallback):
- List all `.html` and `.css` files in `$DS_PATH`
- Infer component names from filenames

Limit inventory to the **50 most relevant files** (sorted by name). For each component, capture:
- File path (relative to project root)
- Component name
- Exported props/interface (if available from TypeScript types)

Present the inventory to the user before generating code.

## 3) Extract Input

### If input is an issue number:

```bash
ISSUE_BODY=$(gh issue view "$INPUT_NUMBER" --repo "$REPO" --json body --jq '.body')
ISSUE_TITLE=$(gh issue view "$INPUT_NUMBER" --repo "$REPO" --json title --jq '.title')
```

Extract flow descriptions, ASCII mockups, and screen states from the issue body.

### If input is free text:
Use the text directly as the prototype specification.

## 4) Generate Functional Code

Using the design system inventory as context:

1. Generate code in the detected framework using **real components** from the DS.
2. Create one file per screen/state described in the input.
3. Create an `index.html` entry point that wraps/renders the components.
4. Save all files to `$OUTPUT_DIR/<YYYYMMDD-HHmmss>/`.

Rules:
- Use only components that exist in the inventory. Do not invent components.
- If a needed component doesn't exist, use plain HTML/CSS as fallback and note it.
- Keep the code functional but minimal — this is a prototype, not production code.
- Include inline comments marking which DS components are used.
- Maximum 5 screens per invocation.

## 5) Capture Screenshots (if Playwright available)

```bash
if [ "$PLAYWRIGHT_AVAILABLE" = "true" ]; then
  PROTO_DIR="$OUTPUT_DIR/<timestamp>"
  SCREENSHOT_DIR="$PROTO_DIR/screenshots"
  mkdir -p "$SCREENSHOT_DIR"

  for html_file in "$PROTO_DIR"/*.html; do
    filename=$(basename "$html_file" .html)
    npx playwright screenshot \
      --viewport-size="${VIEWPORT_W},${VIEWPORT_H}" \
      --full-page \
      "file://$(cd "$(dirname "$html_file")" && pwd)/$(basename "$html_file")" \
      "$SCREENSHOT_DIR/${filename}.png"
  done
fi
```

## 6) Present Results

Show the user:

1. **Inventory summary**: components found and framework detected
2. **Generated files**: paths of all created files
3. **Screenshots**: paths of captured screenshots (if any)
4. **Browser command**: `open $OUTPUT_DIR/<timestamp>/index.html` (or equivalent)
5. **Next actions**:
   - Iterate: re-run with refined input
   - Commit: add prototype to the repo
   - Discard: `rm -rf $OUTPUT_DIR/<timestamp>/`

## Quality Rules

- Use only real components from the design system — never invent fake components.
- Keep prototypes minimal and focused on the described flow.
- Maximum 5 screens per invocation.
- Always show which DS components were used vs plain HTML fallbacks.
- Never modify existing project code — prototypes are isolated in the output directory.
