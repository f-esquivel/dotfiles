---
name: create-issue
description: Create a GitLab or GitHub issue with platform-specific defaults. GitLab issues in Latin American Spanish, GitHub issues in English.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *)
argument-hint: <issue title or description>
---

# Create Issue

$ARGUMENTS

## Instructions

### Step 0: Detect Platform

Detect git platform via `git remote get-url origin`:
- Contains `gitlab` → write issue in **Latin American Spanish**
- Contains `github` → write issue in **English**

For GitLab: use `glab` CLI.
For GitHub: use `gh` CLI.

### Step 1: Understand the Requirement

1. Read the user's description or referenced spec
2. Classify the requirement:
   - **Functional** — user-facing behavior, QA-testable (UI flows, business rules, integrations visible to end users)
   - **Technical** — backend-only, infra, CI/CD, API endpoints without UI, DevOps tasks

### Step 2: Draft the Issue

**Target audience:** PMs, POs, CEOs — non-technical stakeholders. Use clear, business-oriented language. Avoid jargon, class names, or implementation details unless the requirement is purely technical.

#### Issue Structure — GitLab (Latin American Spanish)

```markdown
## Descripción
[Descripción clara del requerimiento en términos de negocio]

## Criterios de Aceptación
[See acceptance criteria rules below]
```

#### Issue Structure — GitHub (English)

```markdown
## Description
[Clear description of the requirement in business terms]

## Acceptance Criteria
[See acceptance criteria rules below]
```

#### Acceptance Criteria Rules

**If Functional (QA-testable):**
- Write acceptance criteria as functional evaluations from the user's perspective
- Focus on observable behavior, NOT technical implementation
- GitLab format: `- [ ] Dado [contexto], cuando [acción], entonces [resultado esperado]`
- GitHub format: `- [ ] Given [context], when [action], then [expected result]`
- Never mention endpoints, classes, database tables, or technical components

**If Technical (BE-only, infra, CI/CD, API endpoints, etc.):**
- Write acceptance criteria with a technical focus
- Reference specific systems, configs, or pipelines as needed
- OR skip acceptance criteria entirely if the task is self-evident (e.g., "update CI variable")

**If unclear whether it's QA-testable → ask the user before proceeding.**

### Step 3: Show Draft Preview

Display the full issue draft for user approval before creating.

### Step 4: Create Issue

For GitLab:
```bash
glab issue create \
  --title "<title>" \
  --description "<description>" \
  --label "squad::[Δ] delta" \
  --label "<additional-labels>" \
  --assignee "franklin.ese.plus"
```

For GitHub:
```bash
gh issue create \
  --title "<title>" \
  --body "<description>" \
  --assignee "@me"
```

### Step 5: Post-Creation

- Display the issue URL
- Ask if user wants to add to a milestone or link to other issues

### Step 6: Offer Branch Checkout

Ask the user if they want to check out a branch to start the implementation.

If yes:

1. **Determine branch type** from the issue nature (conventional branching):
   - `feature/` — new feature or enhancement
   - `fix/` — bug fix
   - `hotfix/` — critical production fix
   - `chore/` — maintenance, deps, tooling
   - `refactor/` — code restructuring without behavior change
   - `docs/` — documentation only
   - `test/` — test-only changes

2. **Build the branch name**:
   - **GitLab:** `<type>/gl-<issue-id>-<description-slug>`
   - **GitHub:** `<type>/<description-slug>` (omit the issue id)

   The `<description-slug>` is a kebab-cased, lowercased, ASCII-only summary of the issue title (drop articles/punctuation, keep it short — ~3-6 words).

3. **Confirm the proposed branch name** with the user, then create it from the current base:

   ```bash
   git checkout -b <branch-name>
   ```

   If unsure which base branch to branch from (e.g., `develop` vs `main`), ask the user.

## GitLab Defaults

### Language

All issue content in **Latin American Spanish**.

### Labels

Always apply:
- `squad::[Δ] delta`
- `workflow::ready for dev`

Conditionally apply:
- `no QA` → if it's a backend-only task OR genuinely not QA-testable. **If not clear, confirm with user before adding.**

### Assignee

Always assign to `@me` (franklin.ese.plus)

## GitHub Defaults

### Language

All issue content in **English**.

### Assignee

Always assign to `@me`

## Rules

- **NEVER** use technical language in functional requirements
- **NEVER** add `no QA` label without being certain or confirming with user
- Respect the platform language rule: GitLab → Spanish, GitHub → English
