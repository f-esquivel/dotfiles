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
- Contains `gitlab` → use `glab` CLI → write issue in **Latin American Spanish**
- Contains `github` → use `gh` CLI → write issue in **English**

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
