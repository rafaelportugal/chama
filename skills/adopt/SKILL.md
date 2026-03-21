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

# Node / JavaScript / TypeScript
if [ -f "package.json" ]; then
  STACK="node"
  DEPS=$(cat package.json | jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' 2>/dev/null)
  echo "$DEPS" | grep -qx "next" && FRAMEWORK="nextjs"
  echo "$DEPS" | grep -qx "react" && [ -z "$FRAMEWORK" ] && FRAMEWORK="react"
  echo "$DEPS" | grep -qx "express" && FRAMEWORK="express"
  echo "$DEPS" | grep -qx "fastify" && FRAMEWORK="fastify"
  echo "$DEPS" | grep -qx "@nestjs/core" && FRAMEWORK="nestjs"
fi

# Python
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  STACK="python"
  if [ -f "requirements.txt" ]; then
    grep -qi "fastapi" requirements.txt && FRAMEWORK="fastapi"
    grep -qi "django" requirements.txt && FRAMEWORK="django"
    grep -qi "flask" requirements.txt && FRAMEWORK="flask"
  fi
  if [ -f "pyproject.toml" ]; then
    grep -qi "fastapi" pyproject.toml && FRAMEWORK="fastapi"
    grep -qi "django" pyproject.toml && FRAMEWORK="django"
  fi
fi

# Go
if [ -f "go.mod" ]; then
  STACK="go"
  grep -q "github.com/gin-gonic/gin" go.mod && FRAMEWORK="gin"
  grep -q "github.com/gofiber/fiber" go.mod && FRAMEWORK="fiber"
  grep -q "github.com/labstack/echo" go.mod && FRAMEWORK="echo"
  grep -q "google.golang.org/grpc" go.mod && FRAMEWORK="grpc"
fi

# C# / .NET
if ls *.csproj 2>/dev/null | head -1 > /dev/null || [ -f "*.sln" ]; then
  STACK="dotnet"
  grep -qi "Microsoft.AspNetCore" *.csproj 2>/dev/null && FRAMEWORK="aspnet"
fi

# Rust
if [ -f "Cargo.toml" ]; then
  STACK="rust"
  grep -q "axum" Cargo.toml && FRAMEWORK="axum"
  grep -q "actix" Cargo.toml && FRAMEWORK="actix"
fi

# Java / Spring
if [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
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
# Detect monorepo structure
COMPONENTS=()
for dir in */; do
  if [ -f "${dir}package.json" ] || [ -f "${dir}go.mod" ] || [ -f "${dir}requirements.txt" ] || [ -f "${dir}Cargo.toml" ] || ls "${dir}"*.csproj 2>/dev/null | head -1 > /dev/null || [ -f "${dir}pom.xml" ]; then
    COMPONENTS+=("$dir")
  fi
done

if [ ${#COMPONENTS[@]} -gt 1 ]; then
  echo "MONOREPO detected: ${COMPONENTS[*]}"
  echo "Each component will be analyzed separately."
fi
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
    [ -f "jest.config.js" ] || [ -f "jest.config.ts" ] || [ -f "jest.config.mjs" ] && TEST_FRAMEWORK="jest"
    echo "$DEPS" | grep -qx "jest" && TEST_FRAMEWORK="jest"
    echo "$DEPS" | grep -qx "vitest" && TEST_FRAMEWORK="vitest"
    echo "$DEPS" | grep -qx "mocha" && TEST_FRAMEWORK="mocha"
    # E2E
    echo "$DEPS" | grep -qx "@playwright/test" && HAS_E2E=true
    echo "$DEPS" | grep -qx "cypress" && HAS_E2E=true
    # Count test files
    TEST_FILES=$(find . -name "*.test.*" -o -name "*.spec.*" -o -name "__tests__" | grep -c . 2>/dev/null || echo 0)
    ;;
  python)
    [ -f "pytest.ini" ] || [ -f "setup.cfg" ] || [ -f "pyproject.toml" ] && grep -qi "pytest" pyproject.toml 2>/dev/null && TEST_FRAMEWORK="pytest"
    command -v pytest >/dev/null 2>&1 && TEST_FRAMEWORK="pytest"
    TEST_FILES=$(find . -name "test_*.py" -o -name "*_test.py" | grep -c . 2>/dev/null || echo 0)
    ;;
  go)
    TEST_FRAMEWORK="go-test" # Built-in
    TEST_FILES=$(find . -name "*_test.go" | grep -c . 2>/dev/null || echo 0)
    ;;
  dotnet)
    ls *Tests*/*.csproj 2>/dev/null && TEST_FRAMEWORK="xunit-or-nunit"
    TEST_FILES=$(find . -name "*Tests.cs" -o -name "*Test.cs" | grep -c . 2>/dev/null || echo 0)
    ;;
  rust)
    TEST_FRAMEWORK="cargo-test" # Built-in
    # Rust tests are inline, count files with #[test]
    TEST_FILES=$(grep -rl "#\[test\]" --include="*.rs" . 2>/dev/null | wc -l || echo 0)
    ;;
  java)
    [ -d "src/test" ] && TEST_FRAMEWORK="junit"
    TEST_FILES=$(find . -path "*/test/*" -name "*Test.java" -o -name "*Tests.java" | grep -c . 2>/dev/null || echo 0)
    ;;
esac

echo "Test framework: ${TEST_FRAMEWORK:-none}"
echo "Test files: $TEST_FILES"
echo "E2E configured: $HAS_E2E"
```

Try to measure current coverage (best-effort):
```bash
case "$STACK" in
  node)
    npx jest --coverage --coverageReporters=text-summary 2>/dev/null | grep "Statements" || echo "Coverage: unknown"
    ;;
  python)
    pytest --cov --cov-report=term-summary -q 2>/dev/null | grep "TOTAL" || echo "Coverage: unknown"
    ;;
  go)
    go test -cover ./... 2>/dev/null | grep "coverage" || echo "Coverage: unknown"
    ;;
esac
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
if [ -f "scripts/run-critical-gate.sh" ]; then
  bash scripts/run-critical-gate.sh --mode standalone 2>/dev/null
elif [ -f "${HOME}/.claude/plugins/chama/scripts/run-critical-gate.sh" ]; then
  bash "${HOME}/.claude/plugins/chama/scripts/run-critical-gate.sh" --mode standalone 2>/dev/null
else
  CACHE_GATE=$(find "$HOME/.claude/plugins/cache/chama" -name "run-critical-gate.sh" 2>/dev/null | head -1)
  [ -n "$CACHE_GATE" ] && bash "$CACHE_GATE" --mode standalone 2>/dev/null || echo "INFO: gate-check not available for analysis"
fi
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

# Check PR patterns
echo "Recent PR base branches:"
gh pr list --repo "$REPO" --state merged --limit 10 --json baseRefName --jq '.[].baseRefName' 2>/dev/null | sort | uniq -c | sort -rn
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

**STOP here for Phase 1 of the Spec.** Tool recommendations and adaptation execution are handled by subsequent Spec phases.
