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
1. **Discovery & Planning** — analyze the repo, generate diagnosis and transformation plan
2. **Adaptation** — execute phases to bring the repo to Chama standard

## Entry Point — Retomada Detection

Before starting Discovery, check if an adoption is already in progress:

```bash
ADOPT_BRANCH_EXISTS=false
if git branch --list chama-adopt | grep -q chama-adopt 2>/dev/null || git branch -r --list origin/chama-adopt | grep -q chama-adopt 2>/dev/null; then
  ADOPT_BRANCH_EXISTS=true
fi

if [ "$ADOPT_BRANCH_EXISTS" = "true" ]; then
  # Read last completed phase from adopt-report
  LAST_PHASE=""
  if [ -f ".chama/adopt-report.md" ]; then
    LAST_PHASE=$(grep -oP '### Phase \K\d+' .chama/adopt-report.md 2>/dev/null | tail -1)
  elif git show origin/chama-adopt:.chama/adopt-report.md >/dev/null 2>&1; then
    LAST_PHASE=$(git show origin/chama-adopt:.chama/adopt-report.md 2>/dev/null | grep -oP '### Phase \K\d+' | tail -1)
  fi

  echo ""
  echo "⚡ Existing adoption detected!"
  echo "  Branch: chama-adopt"
  if [ -n "$LAST_PHASE" ]; then
    echo "  Last completed phase: Phase $LAST_PHASE"
    NEXT_PHASE=$((LAST_PHASE + 1))
    echo "  Next: Phase $NEXT_PHASE"
  else
    echo "  Status: branch exists but no phases completed"
    NEXT_PHASE=1
  fi
  echo ""
  echo "  [resume] Continue from Phase $NEXT_PHASE"
  echo "  [restart] Start over (delete chama-adopt branch)"
  echo "  [cancel] Do nothing"
  echo ""
fi
```

**Rules:**
- `resume` → checkout `chama-adopt`, skip to the next pending phase
- `restart` → ask for confirmation, delete `chama-adopt` branch (local + remote), start fresh from Discovery
- `cancel` → exit immediately, no changes
- If no `chama-adopt` branch exists → proceed normally with Discovery

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

Run gate-check in **full-scan mode** to analyze all tracked files in the repository (not just the diff):

```bash
# Standard gate-check discovery (consistent with code, review-loop, gate-check skills)
if [ -d "chama/scripts" ]; then
  GATE_SCRIPT="chama/scripts/run-critical-gate.sh"
elif [ -d "${HOME}/.claude/plugins/chama/scripts" ]; then
  GATE_SCRIPT="${HOME}/.claude/plugins/chama/scripts/run-critical-gate.sh"
else
  GATE_SCRIPT="scripts/run-critical-gate.sh"
fi

bash "$GATE_SCRIPT" --mode standalone --commit --full-scan 2>/dev/null || echo "INFO: gate-check not available for analysis"
```

This scans the entire codebase against the Chama critical gate rules, giving a complete baseline of findings for the adoption report.
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
elif CACHE_HIT=$(find "$HOME/.claude/plugins/cache/chama" -maxdepth 4 -name "chama.yml.template" -printf '%h\n' 2>/dev/null | sort -V | tail -1) && [ -n "$CACHE_HIT" ]; then
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

---

## Phase 3: Test Infrastructure + Minimum Tests + Quality Gates + Finalization

### 3.1 Check if phases should be skipped

Before executing, evaluate what the Discovery already found:

```bash
# Skip test infra if framework already configured
if [ -n "$TEST_FRAMEWORK" ] && [ "$TEST_FRAMEWORK" != "none" ]; then
  echo "Test framework already configured: $TEST_FRAMEWORK — skipping Phase 2 (Test Infrastructure)"
  SKIP_TEST_INFRA=true
fi

# Skip minimum tests if coverage ≥10%
if [ "$TEST_FILES" -gt 0 ] 2>/dev/null; then
  echo "Test files found: $TEST_FILES — evaluating if minimum coverage is met"
  # If existing coverage reports show ≥10%, skip
fi
```

### 3.2 Adaptation Phase 2: Test Infrastructure

**Skip if test framework already exists.**

Create a new phase branch:

```bash
git checkout chama-adopt
git pull origin chama-adopt
git checkout -b chama-adopt-phase2
```

Install and configure test framework based on the detected stack:

**Golden Rule reminder:** Only install test dependencies and create test configuration files. Do NOT modify application code.

| Stack | Test Framework | Install | Config |
|---|---|---|---|
| Node | Jest | `npm install --save-dev jest @types/jest ts-jest` | Create `jest.config.ts` |
| Node | Vitest | `npm install --save-dev vitest` | Create `vitest.config.ts` |
| Node (frontend) | Playwright | `npm install --save-dev @playwright/test && npx playwright install` | Create `playwright.config.ts` |
| Python | pytest | `pip install pytest pytest-cov` (or add to requirements-dev.txt) | Create `pytest.ini` or `pyproject.toml [tool.pytest]` |
| Go | go test | Built-in — no installation needed | — |
| C# | xUnit | `dotnet add <test-project> package xunit xunit.runner.visualstudio` | Create test project if needed |
| Rust | cargo test | Built-in — no installation needed | — |
| Java | JUnit 5 | Already included via Spring Boot Starter Test | Verify `src/test/` exists |

After installation:
- Add test scripts to the project (e.g., `"test": "jest"` in package.json)
- Verify the test runner works: run a basic sanity test

Commit and PR:

```bash
# Stage only test config and dependency files (Golden Rule: never stage src/)
for f in jest.config.* vitest.config.* playwright.config.* pytest.ini pyproject.toml setup.cfg \
         package.json package-lock.json requirements-dev.txt Makefile .gitignore; do
  [ -e "$f" ] && git add "$f"
done
[ -d "tests/" ] && git add tests/
[ -d "e2e/" ] && git add e2e/
[ -d "__tests__/" ] && git add __tests__/
git commit -m "chore: adopt phase 2 — test infrastructure"
git push -u origin chama-adopt-phase2

gh pr create \
  --base chama-adopt \
  --title "adopt: Phase 2 — Test Infrastructure" \
  --body "## Adoption Phase 2: Test Infrastructure

Part of the adoption plan: #<adopt-issue-number>

### Installed/Configured
- Test framework: <framework>
- E2E framework: <if applicable>
- Test scripts: <commands added>"
```

Update adopt-report:

```markdown
### Phase 2: Test Infrastructure
- Framework: <installed framework>
- E2E: <if installed>
- Config files: <list>
```

### 3.3 Adaptation Phase 3: Minimum Tests (Coverage Loop)

#### Read coverage target

```bash
COVERAGE_TARGET=$(yq '.adopt.coverage_target // 10' .chama.yml 2>/dev/null)
echo "Coverage target: ${COVERAGE_TARGET}%"
```

#### Measure current coverage

Parse real coverage from reports (do NOT run test suites to measure — use existing reports or run with coverage flag):

```bash
measure_coverage() {
  case "$STACK" in
    node)
      # Run tests with coverage, then parse
      npm test -- --coverage --coverageReporters=json-summary 2>/dev/null
      jq -r '.total.statements.pct // 0' coverage/coverage-summary.json 2>/dev/null || echo "0"
      ;;
    python)
      pytest --cov --cov-report=term -q 2>/dev/null | grep -oP 'TOTAL.*\s(\d+)%' | grep -oP '\d+(?=%)' || echo "0"
      ;;
    go)
      go test -cover ./... 2>/dev/null | grep -oP '\d+\.\d+(?=%)' | awk '{s+=$1; n++} END {if(n>0) print s/n; else print 0}'
      ;;
    dotnet)
      dotnet test --collect:"XPlat Code Coverage" 2>/dev/null
      python3 -c "import xml.etree.ElementTree as ET; t=ET.parse('TestResults/coverage.cobertura.xml'); print(round(float(t.getroot().get('line-rate','0'))*100,1))" 2>/dev/null || echo "0"
      ;;
    rust)
      cargo tarpaulin --out json 2>/dev/null | jq -r '.coverage_percent // 0' || echo "0"
      ;;
    java)
      ./mvnw test jacoco:report 2>/dev/null
      python3 -c "import xml.etree.ElementTree as ET; r=ET.parse('target/site/jacoco/jacoco.xml').getroot(); c=r.find('.//counter[@type=\"LINE\"]'); print(round(int(c.get('covered'))/(int(c.get('covered'))+int(c.get('missed')))*100,1))" 2>/dev/null || echo "0"
      ;;
    *) echo "0" ;;
  esac
}
```

#### Skip check

```bash
CURRENT_COVERAGE=$(measure_coverage)
if (( $(echo "$CURRENT_COVERAGE >= $COVERAGE_TARGET" | bc -l 2>/dev/null || echo 0) )); then
  echo "✓ Coverage already at ${CURRENT_COVERAGE}% (target: ${COVERAGE_TARGET}%). Skipping Phase 3."
  # Skip to Phase 4
fi
```

#### Coverage loop

Create phase branch:

```bash
git checkout chama-adopt
git pull origin chama-adopt
git checkout -b chama-adopt-phase3
```

Execute the coverage loop (max 5 iterations):

```
MAX_ITERATIONS=5
ITERATION=1

while [ $ITERATION -le $MAX_ITERATIONS ]; do
  CURRENT_COVERAGE=$(measure_coverage)
  echo ""
  echo "Coverage loop iteration $ITERATION:"
  echo "  Current: ${CURRENT_COVERAGE}% | Target: ${COVERAGE_TARGET}%"

  if (( $(echo "$CURRENT_COVERAGE >= $COVERAGE_TARGET" | bc -l) )); then
    echo "  ✓ Target reached: ${CURRENT_COVERAGE}% >= ${COVERAGE_TARGET}%"
    break
  fi

  # 1. Identify uncovered modules (files with 0% or lowest coverage)
  # 2. Generate tests for the highest-impact uncovered modules
  # 3. Run tests and handle failures

  ITERATION=$((ITERATION + 1))
done

if (( $(echo "$CURRENT_COVERAGE < $COVERAGE_TARGET" | bc -l) )); then
  echo "⚠️ Target not reached after $MAX_ITERATIONS iterations."
  echo "  Current: ${CURRENT_COVERAGE}% | Target: ${COVERAGE_TARGET}%"
  echo "  Adding to Improvement Backlog in adopt-report."
fi
```

#### Test creation strategy (per iteration)

Generate tests by priority layer. **Golden Rule: do NOT modify application source code.** Test file placement follows stack conventions:
- **Node/Python/C#**: test files go in dedicated test directories (`tests/`, `__tests__/`, `*.Tests/`)
- **Go**: `*_test.go` files go next to the source files they test (Go convention)
- **Rust**: `#[test]` modules are inline (Rust convention) or in `tests/` directory
- **Java**: test files go in `src/test/java/` (Maven/Gradle convention)

**Priority order per iteration:**
1. **Unit tests** — pure functions, validators, business logic (highest coverage impact)
2. **Integration tests** — API endpoints, service interactions
3. **E2E tests** — main user flows (if frontend exists)

Focus each iteration on the **uncovered modules with the most lines of code** — these give the most coverage per test.

#### Per-stack test patterns

| Stack | Unit test location | Integration test location | E2E location |
|---|---|---|---|
| Node | `__tests__/` or `*.test.ts` next to source | `tests/integration/` | `e2e/` or `tests/e2e/` |
| Python | `tests/unit/` or `test_*.py` | `tests/integration/` | `tests/e2e/` |
| Go | `*_test.go` next to source | `*_test.go` with build tags | — |
| C# | `*.Tests/` project | `*.IntegrationTests/` project | — |
| Rust | `#[test]` inline or `tests/` | `tests/` | — |
| Java | `src/test/java/` | `src/test/java/` with `@SpringBootTest` | — |

#### Handling test failures

After creating tests in each iteration, run **unit tests only** (skip integration/E2E):

```bash
case "$STACK" in
  node) npm test -- --testPathPattern="unit|__tests__" 2>/dev/null || npm test ;;
  python) pytest -q -m "not integration and not e2e" 2>/dev/null || pytest -q ;;
  go) go test -short ./... ;;
  dotnet) dotnet test --filter "Category!=Integration" 2>/dev/null || dotnet test ;;
  rust) cargo test --lib ;;
  java) ./mvnw test -Dgroups="!integration" 2>/dev/null || ./mvnw test ;;
esac
```

**If a test fails:**
1. **COMMENT OUT** the failing test (do NOT delete it, do NOT modify src/)
2. Add a comment: `// ADOPT: commented — <reason why it fails without src/ changes>`
3. Document in adopt-report: test name, file, reason
4. Generate a **different test** that passes to compensate the coverage
5. Continue the loop — commented tests do NOT count toward coverage

**If a test fails due to missing infrastructure** (database, API not running):
1. Comment out with: `// ADOPT: commented — requires <service> infrastructure`
2. Tag with appropriate marker (e.g., `@pytest.mark.integration`, `//go:build integration`)
3. Compensate with unit tests that don't need infrastructure

#### Monorepo handling

For monorepos, run the coverage loop **per component**:
- Each component must reach the coverage target individually
- Run: `cd <component> && measure_coverage && <loop>`
- Report coverage per component in adopt-report

#### Commit and PR

After the loop completes (target reached or max iterations):

```bash
# Stage only test files (Golden Rule: never stage src/ application code)
git add tests/ e2e/ __tests__/ 2>/dev/null || true
find . -name "*_test.go" -not -path "*/vendor/*" -exec git add {} \; 2>/dev/null || true
[ -d "tests/" ] && git add tests/
[ -d "src/test/" ] && git add src/test/
git commit -m "chore: adopt phase 3 — minimum tests (coverage: ${CURRENT_COVERAGE}%)"
git push -u origin chama-adopt-phase3

gh pr create \
  --base chama-adopt \
  --title "adopt: Phase 3 — Minimum Tests (coverage: ${CURRENT_COVERAGE}%)" \
  --body "## Adoption Phase 3: Minimum Tests

Part of the adoption plan: #<adopt-issue-number>

### Coverage
- Target: ${COVERAGE_TARGET}%
- Achieved: ${CURRENT_COVERAGE}%
- Iterations: $ITERATION

### Tests Created
- Unit: <count>
- Integration: <count>
- E2E: <count>

### Commented Tests (failures)
<list of commented tests with reasons>"
```

#### Update adopt-report

```markdown
### Phase 3: Minimum Tests (Coverage Loop)
- Coverage target: <target>%
- Coverage achieved: <achieved>%
- Iterations: <count>
- Tests created: <unit> unit, <integration> integration, <e2e> E2E
- Tests commented (failures): <count>
  - <test-name>: <reason>
```

### 3.4 Adaptation Phase 4: Quality Gates & Hardening

Create phase branch:

```bash
git checkout chama-adopt
git pull origin chama-adopt
git checkout -b chama-adopt-phase4
```

#### 3.4.1 Run gate-check

```bash
# Standard gate-check discovery
if [ -d "chama/scripts" ]; then
  GATE_SCRIPT="chama/scripts/run-critical-gate.sh"
elif [ -d "${HOME}/.claude/plugins/chama/scripts" ]; then
  GATE_SCRIPT="${HOME}/.claude/plugins/chama/scripts/run-critical-gate.sh"
else
  GATE_SCRIPT="scripts/run-critical-gate.sh"
fi

bash "$GATE_SCRIPT" --mode standalone
```

If CRITICAL/HIGH findings exist:
- Address only findings that can be resolved **without modifying application code** (e.g., config issues, exposed secrets in config files, missing security headers in test configs)
- For findings that require src/ changes: add to Improvement Backlog in adopt-report
- Do NOT modify application code to fix gate-check findings

#### 3.4.2 Run simplify (analysis only)

Run `/simplify` in analysis mode on the most complex modules. Report findings but do NOT apply changes to src/ — add recommendations to the Improvement Backlog.

#### 3.4.3 Verify quality gates

Verify that the quality gates configured in `.chama.yml` pass:

```bash
# Read and run quality gates
COMPONENTS=$(yq '.tech_stack.components[].name' .chama.yml 2>/dev/null)
for COMPONENT in $COMPONENTS; do
  GATES=$(yq ".tech_stack.components[] | select(.name == \"$COMPONENT\") | .quality_gates[]" .chama.yml 2>/dev/null)
  while IFS= read -r gate; do
    echo "Running: $gate"
    eval "$gate" || echo "WARN: Gate failed: $gate — adding to Improvement Backlog"
  done <<< "$GATES"
done
```

If gates fail: note in adopt-report Improvement Backlog. Do NOT modify src/ to make gates pass.

Commit and PR:

```bash
# Stage only config/gate changes (Golden Rule: never stage src/)
git add .chama.yml .chama/ 2>/dev/null || true
git commit -m "chore: adopt phase 4 — quality gates & hardening"
git push -u origin chama-adopt-phase4

gh pr create \
  --base chama-adopt \
  --title "adopt: Phase 4 — Quality Gates & Hardening" \
  --body "## Adoption Phase 4: Quality Gates & Hardening

Part of the adoption plan: #<adopt-issue-number>

### Gate-check Results
- CRITICAL: <count resolved> / <count found>
- Findings requiring src/ changes: added to Improvement Backlog

### Quality Gates Status
- <gate>: <pass/fail>"
```

Update adopt-report:

```markdown
### Phase 4: Quality Gates & Hardening
- Gate-check: <findings summary>
- Quality gates: <pass/fail per gate>
- Findings deferred to Improvement Backlog: <count>
```

### 3.5 Finalization

After all phases are completed:

#### 3.5.1 Complete the Adoption Report

Update `.chama/adopt-report.md` with final sections:

```markdown
## Executive Summary

Adoption completed on <date>. The project <name> has been brought to Chama standard with:
- Documentation: .chama.yml, CLAUDE.md, README.md, PROJECT_BRIEF.md
- Test coverage: <before>% → <after>%
- Quality gates: <status>
- Plugins installed: <list>

## Metrics

| Metric | Before | After |
|--------|--------|-------|
| Test coverage | <before>% | <after>% |
| Test files | <before> | <after> |
| Gate-check CRITICAL | <before> | <after> |
| Docs completeness | <before>/6 | <after>/6 |

## Improvement Backlog

Recommended improvements that were out of scope for the adoption (require application code changes):

- [ ] <improvement 1>
- [ ] <improvement 2>
- [ ] <improvement 3>
```

Commit the final report:

```bash
git checkout chama-adopt
git pull origin chama-adopt
git add .chama/adopt-report.md
git commit -m "docs: complete adoption report with executive summary and metrics"
git push origin chama-adopt
```

#### 3.5.2 Open final PR

```bash
BASE_BRANCH="<confirmed branch from Discovery>"

gh pr create \
  --base "$BASE_BRANCH" \
  --head chama-adopt \
  --title "adopt: Complete Chama adoption — <Project Name>" \
  --body "## Chama Adoption Complete

This PR brings the project to Chama SDLC standard.

### What was done
- **Config & Docs**: .chama.yml, CLAUDE.md, README.md, PROJECT_BRIEF.md, LICENSE
- **Test Infrastructure**: <framework> configured
- **Minimum Tests**: <count> tests, <coverage>% coverage
- **Quality Gates**: <status>

### Adoption Report
See \`.chama/adopt-report.md\` for the full report including highlights, metrics, and improvement backlog.

### Next Steps
1. Run \`/chama:init\` to set up GitHub labels, board, and project number
2. Run \`/chama:ideas\` to start using the Chama pipeline
3. Address items in the Improvement Backlog as needed"
```

#### 3.5.3 Suggest next steps

1. Show the final PR URL
2. Show the adoption report summary
3. Announce: "Adoption completa! PR final aberto para <base-branch>."
4. Suggest: "Após mergear, rode `/chama:init` para configurar labels, board e project number no GitHub."
5. Suggest: "Depois, rode `/chama:ideas` para começar a usar o pipeline Chama."
