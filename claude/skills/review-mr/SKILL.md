---
name: review-mr
description: Review an existing merge request or pull request by ID. Fetches diff, analyzes changes, and provides structured code review.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Task
argument-hint: <MR/PR number>
---

# Review Merge Request / Pull Request

Review MR/PR: $ARGUMENTS

## Instructions

### Step 0: Detect Platform

Detect git platform via `git remote get-url origin`:
- Contains `gitlab` → use `glab` CLI
- Contains `github` → use `gh` CLI

### Step 1: Fetch MR/PR Details

1. Fetch MR/PR metadata: `glab mr view <id>` or `gh pr view <id>`
2. Fetch the diff: `glab mr diff <id>` or `gh pr diff <id>`
3. Read changed files for full context — don't review blindly from diff alone

### Step 2: Fetch Related Issue

Extract the related issue from the MR/PR:
- Check MR/PR description for issue references (`#123`, `Closes #123`, `Relates to #123`)
- Check branch name for issue ID patterns (`feature/gl-123-*`, `fix/gh-456-*`)
- GitLab: `glab issue view <id>`
- GitHub: `gh issue view <id>`

Use the issue's description and acceptance criteria as context for the review — verify the implementation actually satisfies the requirements. If no related issue is found, proceed without it.

### Step 3: Structured Review

Provide a review covering:

- **Summary:** What the MR does in 2-3 sentences
- **Requirements coverage:** If related issue found — does the implementation satisfy the acceptance criteria? Call out any missing or partially covered criteria
- **Scope check:** Does the MR do one thing or is it too broad?
- **Issues found:** Bugs, logic errors, security concerns
- **Style/conventions:** Does it follow project patterns?
- **Suggestions:** Improvements or alternatives
- **Verdict:** Approve / Request changes / Needs discussion

### Step 4: Post Comments

Ask if the user wants to post review comments via CLI.

## Rules

- **NEVER** auto-merge or auto-approve
- Read the actual source files for context, not just the diff
- If unsure about a convention, check existing code before flagging
