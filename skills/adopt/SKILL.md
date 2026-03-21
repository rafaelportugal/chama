---
description: Adopt existing repo — analyze, plan, and transform to Chama standard
---

# Adopt Existing Repository

You are a transformation agent that brings existing repositories into the Chama SDLC standard. Your goal is to **analyze, plan, and adapt** — never to modify application code.

## Idioma
Read `project.language` from `.chama.yml` if it already exists. Otherwise, ask the user which language to use. Respond in the configured language. Default: pt-BR.

## Golden Rule — Zero impact on application code

> **This skill NEVER modifies application code.** No changes to `src/`, controllers, models, services, routes, migrations, or any file in the application's main workflow.
>
> This skill works **exclusively** with:
> - **Documentation**: `.chama.yml`, `CLAUDE.md`, `README.md`, `docs/PROJECT_BRIEF.md`
> - **Test stack**: framework installation, configuration, test file creation
> - **Quality gates**: linters, formatters, type checkers configuration
> - **CI infra**: test scripts, coverage configuration
> - **Adoption report**: `.chama/adopt-report.md`
>
> If a test needs a mock, fixture, or helper, it goes in the test directory — never in application code. The goal is to **observe and validate** what exists, not **modify** what works.

## Configuration

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"
OWNER="${CHAMA_OWNER:-$(yq '.github.owner' .chama.yml 2>/dev/null)}"
PROJECT_NUM="${CHAMA_PROJECT_NUMBER:-$(yq '.github.project_number' .chama.yml 2>/dev/null)}"
DEFAULT_BRANCH="${CHAMA_DEFAULT_BRANCH:-$(yq '.github.default_branch' .chama.yml 2>/dev/null || echo 'main')}"
```

## Overview

The adoption flow has 2 macro-phases:
1. **Discovery & Planning** — analyze the repo, generate diagnosis and transformation plan (this phase)
2. **Adaptation** — execute phases to bring the repo to Chama standard (phases 2 and 3 of the Spec)

## Phase 1: Discovery & Planning

### 1.1 Stack Detection

Detect the primary stack by analyzing project files:

```bash
STACK=""
FRAMEWORK=""

# Detect primary stack (elif prevents polyglot override)
if [ -f "package.json" ]; then
  STACK="node"
  DEPS=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' package.json 2>/dev/null)
  echo "$DEPS" | grep -qx "next" && FRAMEWORK="nextjs"
  echo "$DEPS" | grep -qx "react" && [ -z "$FRAMEWORK" ] && FRAMEWORK="react"
  echo "$DEPS" | grep -qx "express" && [ -z "$FRAMEWORK" ] && FRAMEWORK="express"
  echo "$DEPS" | grep -qx "fastify" && [ -z "$FRAMEWORK" ] && FRAMEWORK="fastify"
  echo "$DEPS" | grep -qx "@nestjs/core" && [ -z "$FRAMEWORK" ] && FRAMEWORK="nestjs"
elif [ -f "go.mod" ]; then
  STACK="go"
  grep -q "github.com/gin-gonic/gin" go.mod && FRAMEWORK="gin"
  grep -q "github.com/gofiber/fiber" go.mod && FRAMEWORK="fiber"
  grep -q "github.com/labstack/echo" go.mod && FRAMEWORK="echo"
  grep -q "google.golang.org/grpc" go.mod && FRAMEWORK="grpc"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  STACK="python"
  for pyfile in requirements.txt pyproject.toml; do
    if [ -f "$pyfile" ]; then
      grep -qi "fastapi" "$pyfile" && FRAMEWORK="fastapi"
      grep -qi "django" "$pyfile" && FRAMEWORK="django"
      grep -qi "flask" "$pyfile" && FRAMEWORK="flask"
    fi
  done
elif ls *.csproj *.sln 2>/dev/null | head -1 > /dev/null; then
  STACK="dotnet"
  grep -qi "Microsoft.AspNetCore" *.csproj 2>/dev/null && FRAMEWORK="aspnet"
elif [ -f "Cargo.toml" ]; then
  STACK="rust"
  grep -q "axum" Cargo.toml && FRAMEWORK="axum"
  grep -q "actix" Cargo.toml && FRAMEWORK="actix"
elif [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  STACK="java"
  grep -qi "spring-boot" pom.xml 2>/dev/null && FRAMEWORK="spring-boot"
  grep -qi "spring-boot" build.gradle 2>/dev/null && FRAMEWORK="spring-boot"
  grep -qi "spring-boot" build.gradle.kts 2>/dev/null && FRAMEWORK="spring-boot"
fi

echo "Stack: $STACK"
echo "Framework: ${FRAMEWORK:-generic}"
```

For **monorepos**, check for multiple stack files in subdirectories:
```bash
# Detect monorepo structure (checks 2 levels deep, excludes common non-project dirs)
COMPONENTS=()
for dir in */ */*/; do
  [ -d "$dir" ] || continue
  # Skip common non-project directories
  case "$dir" in
    node_modules/*|.git/*|vendor/*|target/*|dist/*|build/*) continue ;;
  esac
  if [ -f "${dir}package.json" ] || [ -f "${dir}go.mod" ] || [ -f "${dir}requirements.txt" ] || \
     [ -f "${dir}pyproject.toml" ] || [ -f "${dir}Cargo.toml" ] || [ -f "${dir}pom.xml" ] || \
     [ -f "${dir}build.gradle" ] || [ -f "${dir}build.gradle.kts" ] || \
     ls "${dir}"*.csproj 2>/dev/null | head -1 > /dev/null; then
    COMPONENTS+=("$dir")
  fi
done

if [ ${#COMPONENTS[@]} -gt 1 ]; then
  echo "MONOREPO detected: ${COMPONENTS[*]}"
  echo "Each component will be analyzed separately."
fi

# Also check for workspace-based monorepos
[ -f "package.json" ] && jq -e '.workspaces' package.json >/dev/null 2>&1 && echo "NPM/Yarn workspaces detected"
[ -f "Cargo.toml" ] && grep -q '\[workspace\]' Cargo.toml 2>/dev/null && echo "Cargo workspace detected"
[ -f "go.work" ] && echo "Go workspace detected"
```

If the stack cannot be detected, ask the developer:
```
Stack não detectada automaticamente.
Qual a stack principal do projeto? (ex: node, python, go, dotnet, rust, java)
```

### 1.2 Test Assessment

Evaluate the current test state:

```bash
# Check for test frameworks and files
TEST_FRAMEWORK=""
TEST_FILES=0
HAS_E2E=false

case "$STACK" in
  node)
    # Jest
    if [ -f "jest.config.js" ] || [ -f "jest.config.ts" ] || [ -f "jest.config.mjs" ]; then
      TEST_FRAMEWORK="jest"
    fi
    echo "$DEPS" | grep -qx "jest" && TEST_FRAMEWORK="jest"
    echo "$DEPS" | grep -qx "vitest" && TEST_FRAMEWORK="vitest"
    echo "$DEPS" | grep -qx "mocha" && TEST_FRAMEWORK="mocha"
    # E2E
    echo "$DEPS" | grep -qx "@playwright/test" && HAS_E2E=true
    echo "$DEPS" | grep -qx "cypress" && HAS_E2E=true
    # Count test files (exclude node_modules, dist, build)
    TEST_FILES=$(find . -not -path "*/node_modules/*" -not -path "*/dist/*" -not -path "*/.git/*" \( -name "*.test.*" -o -name "*.spec.*" \) | grep -c . 2>/dev/null || echo 0)
    ;;
  python)
    # Check for pytest in any config file
    [ -f "pytest.ini" ] && TEST_FRAMEWORK="pytest"
    [ -f "setup.cfg" ] && grep -qi "pytest" setup.cfg 2>/dev/null && TEST_FRAMEWORK="pytest"
    [ -f "pyproject.toml" ] && grep -qi "pytest" pyproject.toml 2>/dev/null && TEST_FRAMEWORK="pytest"
    TEST_FILES=$(find . -not -path "*/.git/*" -not -path "*/__pycache__/*" -not -path "*/.venv/*" \( -name "test_*.py" -o -name "*_test.py" \) | grep -c . 2>/dev/null || echo 0)
    ;;
  go)
    TEST_FRAMEWORK="go-test" # Built-in
    TEST_FILES=$(find . -not -path "*/.git/*" -not -path "*/vendor/*" -name "*_test.go" | grep -c . 2>/dev/null || echo 0)
    ;;
  dotnet)
    ls *Tests*/*.csproj >/dev/null 2>&1 && TEST_FRAMEWORK="xunit-or-nunit"
    TEST_FILES=$(find . -not -path "*/.git/*" -not -path "*/bin/*" -not -path "*/obj/*" \( -name "*Tests.cs" -o -name "*Test.cs" \) | grep -c . 2>/dev/null || echo 0)
    ;;
  rust)
    TEST_FRAMEWORK="cargo-test" # Built-in
    TEST_FILES=$(grep -rl "#\[test\]" --include="*.rs" --exclude-dir=target --exclude-dir=.git . 2>/dev/null | wc -l || echo 0)
    ;;
  java)
    [ -d "src/test" ] && TEST_FRAMEWORK="junit"
    TEST_FILES=$(find . -not -path "*/.git/*" -not -path "*/target/*" -path "*/test/*" \( -name "*Test.java" -o -name "*Tests.java" \) | grep -c . 2>/dev/null || echo 0)
    ;;
esac

echo "Test framework: ${TEST_FRAMEWORK:-none}"
echo "Test files: $TEST_FILES"
echo "E2E configured: $HAS_E2E"
```

Estimate coverage from test file count (do NOT run test suites during discovery — tests can have side effects):
```bash
# Check for existing coverage reports (read-only)
COVERAGE="unknown"
[ -f "coverage/coverage-summary.json" ] && COVERAGE=$(jq -r '.total.statements.pct // "unknown"' coverage/coverage-summary.json 2>/dev/null)
[ -f "htmlcov/index.html" ] && COVERAGE="report exists (check htmlcov/)"
[ -f ".coverage" ] && COVERAGE="report exists (run: coverage report)"

echo "Coverage: $COVERAGE"
echo "Test files found: $TEST_FILES"
if [ "$TEST_FILES" -eq 0 ] 2>/dev/null; then
  echo "Estimated coverage: 0% (no test files)"
fi
```

### 1.3 Docs Assessment

```bash
echo "=== Docs Assessment ==="
[ -f "README.md" ] && echo "✓ README.md" || echo "❌ README.md missing"
[ -f "CLAUDE.md" ] && echo "✓ CLAUDE.md" || echo "❌ CLAUDE.md missing"
[ -f ".chama.yml" ] && echo "✓ .chama.yml" || echo "❌ .chama.yml missing"
[ -f "docs/PROJECT_BRIEF.md" ] && echo "✓ docs/PROJECT_BRIEF.md" || echo "❌ docs/PROJECT_BRIEF.md missing"
[ -f "LICENSE" ] && echo "✓ LICENSE" || echo "❌ LICENSE missing"
[ -d ".chama/templates" ] && [ -f ".chama/templates/spec.md" ] && echo "✓ .chama/templates/spec.md" || echo "❌ spec template missing"
```

### 1.4 CI/CD Assessment

```bash
echo "=== CI/CD Assessment ==="
[ -d ".github/workflows" ] && echo "✓ GitHub Actions detected" && ls .github/workflows/
[ -f ".gitlab-ci.yml" ] && echo "✓ GitLab CI detected"
[ -f "Jenkinsfile" ] && echo "✓ Jenkins detected"
[ -f ".circleci/config.yml" ] && echo "✓ CircleCI detected"

# Check if tests run in CI
if [ -d ".github/workflows" ]; then
  grep -rl "test" .github/workflows/ 2>/dev/null && echo "✓ Test step found in CI" || echo "⚠️ No test step in CI"
fi
```

### 1.5 Code Quality Analysis

Run gate-check in standalone mode (informational only):

```bash
# Standard gate-check discovery (consistent with code, review-loop, gate-check skills)
if [ -d "chama/scripts" ]; then
  GATE_SCRIPT="chama/scripts/run-critical-gate.sh"
elif [ -d "${HOME}/.claude/plugins/chama/scripts" ]; then
  GATE_SCRIPT="${HOME}/.claude/plugins/chama/scripts/run-critical-gate.sh"
else
  GATE_SCRIPT="scripts/run-critical-gate.sh"
fi

bash "$GATE_SCRIPT" --mode standalone 2>/dev/null || echo "INFO: gate-check not available for analysis"
```

### 1.6 Branch Strategy Detection

```bash
echo "=== Branch Strategy ==="
DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$DEFAULT" ] && DEFAULT="main"
echo "Default branch: $DEFAULT"

# Check for intermediate branch (develop, staging, etc.)
git branch -r 2>/dev/null | grep -q "origin/develop" && echo "Intermediate branch: develop"
git branch -r 2>/dev/null | grep -q "origin/staging" && echo "Intermediate branch: staging"

# Check PR patterns (REPO may be empty if .chama.yml doesn't exist yet)
echo "Recent PR base branches:"
if [ -n "$REPO" ] && [ "$REPO" != "null" ]; then
  gh pr list --repo "$REPO" --state merged --limit 10 --json baseRefName --jq '.[].baseRefName' 2>/dev/null | sort | uniq -c | sort -rn
else
  gh pr list --state merged --limit 10 --json baseRefName --jq '.[].baseRefName' 2>/dev/null | sort | uniq -c | sort -rn
fi
```

**Always confirm with the developer before proceeding:**

```
Branch strategy detected:
  - Default branch: main
  - Intermediate branch: develop

Base branch for adoption: develop
Confirm? [Y/change]:
```

If no intermediate branch is found, use the default branch. The developer can always override.

### 1.7 Present Discovery Results

After running all assessments, present results in two sections:

**Highlights** — what's already good:
```
✓ Pontos positivos encontrados:
  - CI/CD configurado com GitHub Actions
  - README.md presente com documentação básica
  - TypeScript strict mode ativo
  - Estrutura de pastas organizada (src/, lib/, etc.)
  - <other positive findings>
```

**Diagnosis** — gaps found:
```
Gaps encontrados:
  ❌ Zero testes (0% coverage)
  ❌ Sem CLAUDE.md
  ❌ Sem .chama.yml
  ❌ Sem docs/PROJECT_BRIEF.md
  ⚠️ README.md básico sem Quick Start
  ⚠️ Sem quality gates configurados
  ⚠️ Sem E2E tests
```

### 1.8 Generate Transformation Plan

Based on the diagnosis, generate a prioritized plan:

```
─────────────────────────────────────────
Transformation Plan:

  Phase 1: Config & Docs                          [S]
    - Create .chama.yml, CLAUDE.md, PROJECT_BRIEF.md
    - Update README.md with Quick Start
    - Install recommended plugins

  Phase 2: Test Infrastructure                     [M]
    - Configure <test-framework> for <stack>
    - Install and configure <e2e-framework> for frontend
    (skip if test infrastructure already exists)

  Phase 3: Minimum Test Coverage (target: ≥10%)    [L]
    - <specific test targets based on stack>
    (skip if coverage already ≥10%)

  Phase 4: Quality Gates & Hardening               [M]
    - Run gate-check, fix CRITICAL findings
    - Run simplify on complex modules (analysis only)
    - Configure quality gates in .chama.yml

Confirm plan? [Y/adjust/cancel]:
```

**Rules:**
- If test infrastructure exists and coverage ≥10%: skip Phases 2 and 3
- If docs are complete: skip relevant items in Phase 1
- Developer can adjust (remove phases, change order, add custom phases)
- "cancel" stops immediately — no artifacts created

### 1.9 Persist Plan as GitHub Issue

After approval, create a GitHub Issue with label `adopt`:

```bash
REPO="${CHAMA_REPO:-$(yq '.project.repo' .chama.yml 2>/dev/null)}"

# If .chama.yml doesn't exist yet, ask for repo
if [ -z "$REPO" ] || [ "$REPO" = "null" ]; then
  # Try to infer from git remote
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
  REPO=$(echo "$REMOTE_URL" | sed -E 's#^.*(github\.com[:/])##; s#\.git$##')
fi
```

Create the issue:

```bash
gh issue create \
  --repo "$REPO" \
  --label "adopt" \
  --title "adopt: Transformation Plan — <Project Name>" \
  --body-file /tmp/chama-adopt-plan.md
```

The issue body should contain:
- Discovery summary (stack, framework, test state, docs state)
- Highlights and Diagnosis
- Transformation phases with checkboxes
- Tools recommended
- Branch strategy

### 1.10 Initialize Adoption Report

Create `.chama/adopt-report.md` with Discovery results:

```bash
mkdir -p .chama
```

The report starts with:

```markdown
# Adoption Report — <Project Name>

**Date:** <today>
**Adopted by:** /chama:adopt
**Stack:** <stack> (<framework>)
**Base branch:** <confirmed branch>

## Highlights
<positive findings from Discovery>

## Diagnosis
<gaps found from Discovery>

## Phases Executed
(to be filled incrementally as phases complete)
```

### 1.11 Completion

After the plan is persisted and the report initialized:

1. Show the GitHub Issue URL
2. Show the adopt-report.md path
3. Announce: "Discovery completo. Plano de transformação criado."
4. Show next step: "Execute `/chama:adopt` novamente para iniciar a adaptação (Phase 2 da Spec), ou rode `/chama:code <issue-number>` para as phases individuais."

---

## Phase 2: Tool Recommendations + Config & Docs Adaptation

### 2.1 Tool Recommendations

After Discovery, present tool recommendations based on the detected stack. The developer chooses what to install.

**Base comum (toda stack):**
- Plugin LSP da linguagem (obrigatório para code intelligence)
- GitHub ou GitLab (integração com repositório)
- Context7 (docs versionadas)

#### Curadoria por stack

##### Node / React / Next

| Recorte | Plugins & Skills sugeridos | Quality gates |
|---|---|---|
| **Frontend (React/Next)** | `typescript-lsp`, `frontend-design`, `vercel-react-best-practices`, `playwright-best-practices`, `context7` | rápido: `npm run lint && npm run typecheck && npm test` · completo: `npm run build && npx playwright test` |
| **Next.js App Router / RSC** | `typescript-lsp`, `next-best-practices`, `vercel-react-best-practices`, `context7` | rápido: `npm run lint && npm run typecheck` · completo: `npm run build && npx playwright test` |
| **Node backend (Express/Fastify/NestJS)** | `typescript-lsp`, `nodejs-backend-patterns`, `api-design-principles`, `context7` | rápido: `npm run lint && npm run typecheck && npm test` · completo: `npm run build && npm run test:integration` |

##### Python

| Recorte | Plugins & Skills sugeridos | Quality gates |
|---|---|---|
| **FastAPI** | `pyright-lsp`, `fastapi-expert`, `python-performance-optimization`, `context7` | rápido: `ruff check . && mypy . && pytest -q` · completo: `pytest -q --cov && pytest -m integration` |
| **Django / DRF** | `pyright-lsp`, `django-expert`, `context7` | rápido: `ruff check . && mypy . && pytest -q` · completo: `pytest --reuse-db && python manage.py check --deploy` |
| **Flask** | `pyright-lsp`, `python-performance-optimization`, `context7` | rápido: `ruff check . && mypy . && pytest -q` · completo: `pytest -q --cov` |
| **Workers / data pipeline** | `pyright-lsp`, `python-performance-optimization` | rápido: `ruff check . && mypy . && pytest -q` · completo: `pytest --cov` |

##### Go

| Recorte | Plugins & Skills sugeridos | Quality gates |
|---|---|---|
| **Go service** | `gopls-lsp`, `context7` | rápido: `go test ./... && golangci-lint run` · completo: `go vet ./... && go test -race ./...` |
| **Go with Gin/Fiber/Echo/gRPC** | `gopls-lsp` | rápido: `go test ./... && golangci-lint run` · completo: `go test -race ./...` + smoke tests |

##### C# / .NET

| Recorte | Plugins & Skills sugeridos | Quality gates |
|---|---|---|
| **ASP.NET Core** | `csharp-lsp`, `dotnet-skills`, `context7` | rápido: `dotnet format --verify-no-changes && dotnet build -warnaserror && dotnet test` · completo: `dotnet test --collect:"XPlat Code Coverage"` |
| **.NET enterprise / EF Core** | `csharp-lsp`, `dotnet-skills` | rápido: gates base + arch tests · completo: coverage + integration |

##### Rust

| Recorte | Plugins & Skills sugeridos | Quality gates |
|---|---|---|
| **Rust web / backend** | `rust-analyzer-lsp`, `rust-skills`, `context7` | rápido: `cargo fmt --check && cargo clippy -- -D warnings && cargo test` · completo: `cargo test --workspace && cargo audit` |
| **Rust CLI / libs** | `rust-analyzer-lsp`, `rust-skills` | rápido: `cargo fmt --check && cargo clippy -- -D warnings && cargo test` · completo: `cargo test --workspace && cargo doc --no-deps` |

##### Java / Spring

| Recorte | Plugins & Skills sugeridos | Quality gates |
|---|---|---|
| **Spring Boot MVC / Data JPA** | `jdtls-lsp`, `spring-boot-engineer`, `context7` | rápido: `./mvnw test && ./mvnw checkstyle:check` · completo: `./mvnw verify` |
| **Spring WebFlux / Cloud** | `jdtls-lsp`, `spring-boot-engineer` | rápido: `./mvnw test && ./mvnw checkstyle:check` · completo: `./mvnw verify` + reactive tests |

### 2.2 Recommendation UX

Present recommendations and let the developer choose:

```text
📦 Recommended tools for your stack (<STACK> + <FRAMEWORK>):

  Plugins (Claude Code):
    ✓ <lsp-plugin> (LSP — code intelligence)
    ✓ context7 (docs versionadas)
    ○ <plugin-1> (<description>)
    ○ <plugin-2> (<description>)

  Skills (best practices):
    ○ <skill-1>
    ○ <skill-2>

  Quality gates for .chama.yml:
    Quick: <quick gates>
    Full:  <full gates>

Install selected plugins? [Y/n/select]:
```

**Rules:**
- `Y` — install all recommended plugins
- `n` — skip plugin installation entirely
- `select` — present numbered list, developer picks which ones
- Quality gates are always suggested for `.chama.yml` regardless of plugin choice

### 2.3 Branch Setup

Create the base branch for adoption:

```bash
BASE_BRANCH="<confirmed branch from Discovery>"
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"

# Check if chama-adopt branch already exists
if git branch --list chama-adopt | grep -q chama-adopt || git branch -r --list origin/chama-adopt | grep -q chama-adopt; then
  echo "Branch chama-adopt already exists."
  echo "Options: [reuse] existing / [reset] from $BASE_BRANCH / [cancel]"
  # Ask developer — if reuse: checkout; if reset: delete and recreate; if cancel: stop
fi

git checkout -b chama-adopt 2>/dev/null || git checkout chama-adopt
git push -u origin chama-adopt
```

For the Config & Docs phase, create a phase branch:

```bash
git checkout -b chama-adopt-phase1 2>/dev/null || git checkout chama-adopt-phase1
```

### 2.4 Adaptation Phase 1: Config & Docs

Generate all Chama configuration and documentation artifacts. This follows the same patterns as `/chama:new-project` but adapted for existing repos.

#### Locate Chama templates

Use the same discovery chain as `/chama:new-project` Step 4:

```bash
ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHAMA_TEMPLATES=""
if [ -d "$ROOT_DIR/templates" ] && [ -f "$ROOT_DIR/templates/chama.yml.template" ]; then
  CHAMA_TEMPLATES="$ROOT_DIR/templates"
elif [ -d "chama/templates" ]; then
  CHAMA_TEMPLATES="chama/templates"
elif [ -d "$HOME/.claude/plugins/chama/templates" ]; then
  CHAMA_TEMPLATES="$HOME/.claude/plugins/chama/templates"
elif CACHE_HIT=$(find "$HOME/.claude/plugins/cache/chama" -maxdepth 4 -name "chama.yml.template" -printf '%h' 2>/dev/null | head -1) && [ -n "$CACHE_HIT" ]; then
  CHAMA_TEMPLATES="$CACHE_HIT"
fi
```

Read templates as structural reference (if found): `chama.yml.template`, `CLAUDE.md.template`, `PROJECT_BRIEF.md.template`, `README.md.template`.

**Golden Rule reminder:** Do NOT modify any application code. Only create/update documentation and configuration files.

#### 2.4.1 Generate `.chama.yml`

Create `.chama.yml` using the Discovery results:
- `project.name`, `project.description`, `project.repo` — from repo metadata
- `tech_stack.summary` — from stack detection
- `tech_stack.components[]` — from monorepo detection or single component
- Quality gates — from the curadoria table matching the detected stack (quick gates)
- `personas`, `business_segment` — ask the developer if not inferrable
- `critical_gates` — include default configuration

If `.chama.yml` already exists: **merge mode** — read existing, propose only additions/updates, ask for confirmation.

#### 2.4.2 Generate `CLAUDE.md`

Create a contextual `CLAUDE.md` following the same rules as `/chama:new-project` Step 4.2:
- Project name, description, tech stack
- Project structure based on actual directory tree
- Quality gates from `.chama.yml`
- Development workflow with Chama commands
- Coding conventions appropriate to the detected stack

If `CLAUDE.md` already exists: **merge mode** — compare sections, propose adding only new information.

#### 2.4.3 Generate `README.md`

Create/update `README.md` following the same rules as `/chama:new-project` Step 4.7:
- Quick Start with real commands based on the stack
- Stack section
- Project structure
- Development section with Chama workflow

If `README.md` already exists: **merge mode** — compare sections, propose adding only new sections.

#### 2.4.4 Generate `docs/PROJECT_BRIEF.md`

```bash
mkdir -p docs
```

Create `docs/PROJECT_BRIEF.md` with synthesis fields derived from Discovery results.

If already exists: **merge mode** — show diff, ask to keep or replace.

#### 2.4.5 Generate `LICENSE`

If `LICENSE` does not exist, ask the developer for license preference (same 5 options as `/chama:new-project`):

1. **MIT** — permissiva, uso livre
2. **Apache 2.0** — permissiva + patentes
3. **GPL v3** — copyleft
4. **Proprietary** — all rights reserved
5. **Nenhuma** — não criar

If `LICENSE` already exists: skip.

#### 2.4.6 Update `.gitignore`

Follow the same rules as `/chama:new-project` Step 4.6:
- If `.gitignore` does not exist: generate one appropriate to the detected stack, always including `.chama/progress/` and `.chama/reviews/`
- If `.gitignore` already exists: append only `.chama/` entries if not already present

#### 2.4.7 Copy spec template

```bash
mkdir -p .chama/templates
```

Copy the default spec template if `.chama/templates/spec.md` does not exist (same logic as `/chama:new-project` Step 4.4).

#### 2.4.8 Install accepted plugins

Install plugins that the developer accepted in Step 2.2:

```bash
# For each accepted plugin, suggest installation command
# The developer must run these manually as plugin installation requires interactive confirmation
echo "Install the following plugins:"
echo "  /plugin install <plugin-name>"
```

Note: Plugin installation is interactive — the skill cannot install them automatically. Present the commands for the developer to run.

### 2.5 Commit, PR, and Update Report

After all Config & Docs artifacts are generated:

```bash
# Stage only documentation and config files (Golden Rule)
for f in .chama.yml CLAUDE.md README.md docs/PROJECT_BRIEF.md LICENSE .chama/ .gitignore; do
  [ -e "$f" ] && git add "$f"
done

git commit -m "chore: adopt phase 1 — config & docs"
git push -u origin chama-adopt-phase1
```

Create PR for this phase:

```bash
gh pr create \
  --base chama-adopt \
  --title "adopt: Phase 1 — Config & Docs" \
  --body "## Adoption Phase 1: Config & Docs

Part of the adoption plan: #<adopt-issue-number>

### Created/Updated
- .chama.yml (with quality gates)
- CLAUDE.md
- README.md
- docs/PROJECT_BRIEF.md
- LICENSE (if chosen)
- .chama/templates/spec.md

### Plugins Recommended
<list of recommended plugins with install commands>"
```

Update the adoption report:

```markdown
### Phase 1: Config & Docs
- Created: <list of files>
- Updated: <list of updated files>
- Quality gates configured: <quick + full>
- Plugins recommended: <list>
- License: <chosen license or "none">
```

### 2.6 Completion

After the PR is created:

1. Show the PR URL
2. Show updated adopt-report.md
3. Announce: "Adoption Phase 1 (Config & Docs) concluída. PR aberto para chama-adopt."
4. Show next step: "Rode `/chama:review-loop <pr-number>` para revisar e mergear este PR. Depois, rode `/chama:adopt` novamente para executar as próximas phases (Test Infrastructure, Minimum Tests, Quality Gates)."

**STOP here.** The remaining adoption phases (Test Infrastructure, Minimum Tests, Quality Gates & Hardening) will be added to this skill in a future update.
