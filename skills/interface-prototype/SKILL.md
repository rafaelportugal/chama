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

### If input is an issue number (e.g., `#37` or `37`):

```bash
INPUT_NUMBER=$(echo "$INPUT" | grep -oP '\d+')
ISSUE_BODY=$(gh issue view "$INPUT_NUMBER" --repo "$REPO" --json body --jq '.body')
ISSUE_TITLE=$(gh issue view "$INPUT_NUMBER" --repo "$REPO" --json title --jq '.title')
```

Extract from the issue body:
- Flow descriptions and step sequences
- ASCII mockups (text between ` ```text ` or ` ``` ` blocks)
- Screen states mentioned (empty, loading, error, success)
- UI elements and interactions described

Combine into a structured prototype specification:
- **Title**: from issue title
- **Screens**: each distinct screen/state described
- **Components needed**: UI elements mentioned (buttons, forms, tables, cards, etc.)

### If input is free text:
Use the text directly as the prototype specification. Parse it for:
- Screen names/titles
- UI elements described
- States and flows

## 4) Generate Functional Code

Create the output directory:

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROTO_DIR="$OUTPUT_DIR/$TIMESTAMP"
mkdir -p "$PROTO_DIR"
```

### 4.1) Code generation per framework

**React projects** (`FRAMEWORK=react`):
- Generate standalone `.html` files that load React via CDN (no build step needed)
- Use Babel standalone for JSX transformation in-browser
- Import DS component styles/tokens as inline CSS approximation
- Create one HTML file per screen: `01-<screen-name>.html`, `02-<screen-name>.html`, etc.
- Each file is self-contained and renderable in a browser

**Vue projects** (`FRAMEWORK=vue`):
- Generate standalone `.html` files that load Vue via CDN
- Component templates inline in the HTML
- One file per screen with the same naming convention

**HTML/CSS projects** (`FRAMEWORK=html`):
- Generate plain `.html` files with inline CSS
- Reference DS class names and patterns from the inventory
- One file per screen

### 4.2) Code generation rules

- **Use real components**: reference actual component names, class names, and patterns from the inventory.
- **Fallback**: if a needed component doesn't exist in the DS, use plain HTML/CSS and add a comment: `<!-- FALLBACK: no DS component for [description] -->`.
- **Self-contained**: each HTML file must render independently in a browser (no build step).
- **Prototype quality**: functional and visually representative, but not production code.
- **Maximum 5 screens** per invocation.
- **Include inline comments** marking which DS components are used.

### 4.3) Create index.html

Generate an `index.html` that links to all screen files:

```html
<!DOCTYPE html>
<html>
<head>
  <title>Prototype: [title]</title>
  <style>
    body { font-family: system-ui; max-width: 800px; margin: 40px auto; padding: 0 20px; }
    a { display: block; padding: 12px; margin: 8px 0; background: #f5f5f5; border-radius: 8px; text-decoration: none; color: #333; }
    a:hover { background: #e8e8e8; }
    .meta { color: #666; font-size: 14px; }
  </style>
</head>
<body>
  <h1>Prototype: [title]</h1>
  <p class="meta">Generated: [timestamp] | Framework: [framework] | DS: [ds_path]</p>
  <h2>Screens</h2>
  <!-- links to each screen file -->
</body>
</html>
```

### 4.4) Create README.md

Save the original input and metadata:

```markdown
# Prototype: [title]

**Generated:** YYYY-MM-DD HH:MM:SS
**Framework:** [framework]
**Design System:** [ds_path]
**Input source:** [free text / issue #N]

## Original Input
[full input text or issue body]

## Screens Generated
1. `01-screen-name.html` — [description]
2. `02-screen-name.html` — [description]

## DS Components Used
- ComponentA (from ds_path/ComponentA.tsx)
- ComponentB (from ds_path/ComponentB.tsx)

## Fallbacks
- [description] — no DS component available, used plain HTML/CSS
```

## 5) Capture Screenshots

Discover the screenshot script path:

```bash
if [ -d "chama/scripts" ]; then
  SCREENSHOT_SCRIPT="chama/scripts/prototype-screenshot.sh"
elif [ -d "${HOME}/.claude/plugins/chama/scripts" ]; then
  SCREENSHOT_SCRIPT="${HOME}/.claude/plugins/chama/scripts/prototype-screenshot.sh"
else
  SCREENSHOT_SCRIPT="scripts/prototype-screenshot.sh"
fi
```

If Playwright is available, capture screenshots:

```bash
if [ "$PLAYWRIGHT_AVAILABLE" = "true" ]; then
  SCREENSHOT_DIR="$PROTO_DIR/screenshots"
  bash "$SCREENSHOT_SCRIPT" "$PROTO_DIR" "$SCREENSHOT_DIR" "$VIEWPORT_W" "$VIEWPORT_H"
fi
```

If Playwright is NOT available:
- Show a warning but do NOT fail
- The prototype is still usable — the user can open HTML files in a browser manually

## 6) Present Results

Show the user a structured summary:

```
=== Prototype Generated ===

Framework: [react/vue/html]
Design System: [ds_path] ([N] components found)
Output: [proto_dir]/

Files:
  - index.html (screen index)
  - 01-login.html
  - 02-dashboard.html
  - README.md

Screenshots: [if captured]
  - screenshots/01-login.png
  - screenshots/02-dashboard.png

Open in browser:
  open [proto_dir]/index.html

DS Components used: [list]
Fallbacks used: [list or "none"]

Next actions:
  1. Iterate → re-run /chama:interface-prototype with refined input
  2. Commit → git add [proto_dir]
  3. Discard → rm -rf [proto_dir]
```

## Quality Rules

- Use only real components from the design system — never invent fake components.
- Keep prototypes minimal and focused on the described flow.
- Maximum 5 screens per invocation.
- Always show which DS components were used vs plain HTML fallbacks.
- Never modify existing project code — prototypes are isolated in the output directory.
- Each HTML file must be self-contained and openable in any browser without a build step.
