---
name: create-mr
description: Create a merge request or pull request from the current branch with draft preview before submission.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *)
argument-hint: [target-branch]
---

# Create Merge Request / Pull Request

$ARGUMENTS

## Instructions

### Step 0: Detect Platform

Detect git platform via `git remote get-url origin`:
- Contains `gitlab` → prefer MCP tools (`mcp__gitlab__*`) when available, fall back to `glab` CLI if not
- Contains `github` → use `gh` CLI

### Step 1: Analyze Current Branch

1. Get current branch: `git rev-parse --abbrev-ref HEAD`
2. Determine target branch:
   - If `$ARGUMENTS` provided → use as target
   - Else check if `develop` exists: `git rev-parse --verify develop`
   - Fall back to `main` or `master`
3. Get all commits on this branch: `git log <target>..HEAD --oneline`
4. Get full diff: `git diff <target>...HEAD --stat`
5. Read changed files for context

### Step 2: Check for MR/PR Templates

Look for existing templates in the repo:
- GitLab: `.gitlab/merge_request_templates/`
- GitHub: `.github/PULL_REQUEST_TEMPLATE.md` or `.github/PULL_REQUEST_TEMPLATE/`

If multiple templates found, pick the most appropriate for the change type. If unsure, ask the user which template to use.

If a template exists, fill it in. If not, use the default structure in Step 3.

### Step 3: Draft Preview

Show a preview to the user with ALL of the following:

```
=== MR/PR Draft Preview ===

Title: <type>(scope): description
Target: <target-branch> <- <current-branch>
Assignee: @me
Reviewers: <see platform defaults below>
Labels: <see platform defaults below>

Description:
<filled template or default structure>
```

**Default description structure** (when no template found):

```markdown
## Summary
- Bullet points of what changed and why

## Changes
- File-by-file or module-by-module breakdown

## QA Checklist
- [ ] Relevant tests added/updated
- [ ] Linting passes
- [ ] No breaking changes (or documented)
```

**Wait for user approval before proceeding.**

### Step 4: Create MR/PR (only after approval)

For GitLab:
```bash
glab mr create --title "<title>" --description "<description>" --target-branch <target> --label "<labels>" --assignee "franklin.ese.plus" --reviewer "<reviewers>"
```

For GitHub:
```bash
gh pr create --title "<title>" --body "<description>" --base <target> --label "<labels>" --assignee "@me" --reviewer "<reviewers>"
```

### Step 5: Post-Creation

- Display the MR/PR URL

## GitLab Defaults

### Labels

Always apply:
- `squad::[Δ] delta`
- `development::code review`

### Assignee

Always assign to `@me` (franklin.ese.plus)

### Reviewers

Choose based on change type:
- **Application code** (features, fixes, refactors, tests) → `joseantonio1` and `kevin567` (Tech Leads)
- **CI/CD or DevOps changes** (pipelines, infra, Docker, GCP) → `victorsalmeron` (DevOps)
- **Production release MR** (merging to `main`) → `j.avilemus` only (General PM)

## GitHub Defaults

### Templates

If multiple PR templates found, pick the most appropriate or ask user.

### Assignee

Always assign to `@me`

## Rules

- **NEVER** create the MR/PR without showing the draft preview first
- **NEVER** auto-merge or auto-approve
- Follow commitlint conventions for the MR title (lowercase, valid type/scope)
- If the branch has messy commits, suggest squashing before MR creation
- Always use existing repo templates when available
