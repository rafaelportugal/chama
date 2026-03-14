---
description: Project onboarding — creates .chama.yml, GitHub labels, and project board
---

# Project Onboarding

You are the Chama onboarding assistant. Your goal is to set up a new project for the Chama SDLC workflow.

## Idioma
Read `project.language` from `.chama.yml` if it already exists. Otherwise, ask the user which language to use. Respond in the configured language. Default: pt-BR.

## Pre-check

Check if `.chama.yml` already exists in the project root:
- If yes: ask user if they want to reconfigure or skip.
- If no: proceed with setup.

## Step 1 — Gather project info

Ask the user (batch questions, max 2 rounds):

1. **Project name** (e.g., "MyProject")
2. **GitHub repo** (e.g., "owner/repo-name")
3. **Brief description** (1-2 sentences)
4. **Tech stack summary** (e.g., "Go backend + Next.js frontend")
5. **Components** — for each:
   - Name (e.g., "backend")
   - Path (e.g., "backend/")
   - Quality gate commands (e.g., `cd backend && make test && make lint`)
6. **Personas** — who uses the system? (name + short description)
7. **Business segment** (e.g., "SaaS", "HealthTech", "E-commerce")
8. **Language** — `pt-BR` or `en`
9. **Default branch** — `main`, `dev`, etc. (default: `main`)

## Step 2 — GitHub Project

Ask:
- Create a **new** GitHub Project or use an **existing** one?
- If existing: what is the project number?

If creating new:
```bash
REPO="<owner/repo>"
OWNER="<owner>"
gh project create --owner "$OWNER" --title "<ProjectName> Board"
```

## Step 3 — Create labels

Run the setup script or create labels directly:

```bash
REPO="<owner/repo>"

gh label create "idea"  --repo "$REPO" --color "0E8A16" --description "Idea in brainstorm" 2>/dev/null || true
gh label create "spec"  --repo "$REPO" --color "1D76DB" --description "Spec document" 2>/dev/null || true
gh label create "epic"  --repo "$REPO" --color "D93F0B" --description "Epic grouping phases" 2>/dev/null || true
gh label create "phase" --repo "$REPO" --color "FBCA04" --description "Implementation phase" 2>/dev/null || true
```

## Step 4 — Generate `.chama.yml`

Using the gathered information, create `.chama.yml` in the project root following the template structure:

```yaml
project:
  name: "<name>"
  description: "<description>"
  repo: "<owner/repo>"
  language: "<pt-BR|en>"

github:
  owner: "<owner>"
  project_number: <number>
  default_branch: "<main>"              # "main", "dev", etc.

tech_stack:
  summary: "<summary>"
  components:
    - name: "<component>"
      path: "<path>/"
      quality_gates:
        - "<command>"

artifacts:
  progress_dir: ".chama/progress"
  reviews_dir: ".chama/reviews"

personas:
  - name: "<persona>"
    description: "<description>"

business_segment: "<segment>"
```

## Step 5 — Generate `CLAUDE.md`

If `CLAUDE.md` does not exist in the project root, generate one with:
- Project name and description
- Tech stack overview
- Available Chama commands (`/chama:ideas`, `/chama:architect`, `/chama:code`, `/chama:review-loop`)
- Project structure notes
- Quality gates (from components)
- Coding conventions

If `CLAUDE.md` already exists, suggest adding the Chama workflow section.

## Step 6 — Create artifact directories

```bash
mkdir -p .chama/progress .chama/reviews
echo ".chama/" >> .gitignore  # if not already there
```

## Output

At the end, show:
1. Files created/updated
2. Labels created
3. GitHub Project configured
4. Next step: "Run `/chama:ideas` to start brainstorming your first feature"
