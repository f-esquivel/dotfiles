---
name: cleanup-review-worktrees
description: List and remove review worktrees under ~/.claude/worktrees/reviews/. Filters by age, repo, verdict, and platform MR status (merged/closed). Always confirms before removing.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Bash(git *), Bash(glab *), Bash(gh *), Bash(~/.claude/scripts/*)
argument-hint: [--older-than <days>] [--repo <slug>] [--merged] [--all]
---

# Cleanup Review Worktrees

Manage stale review worktrees created by `/review-mr` and `/re-review-mr`.

Scope: **only** worktrees under `~/.claude/worktrees/reviews/` (identified by their sidecar `.meta.json`). Manual worktrees elsewhere are never touched.

## Arguments

| Flag                  | Effect                                                                              |
|-----------------------|-------------------------------------------------------------------------------------|
| `--older-than <days>` | Only consider worktrees older than N days (by `created_at`)                         |
| `--repo <slug>`       | Only consider worktrees under a specific repo slug                                  |
| `--merged`            | Only consider worktrees whose MR is merged or closed (queried via `glab` / `gh`)    |
| `--all`               | Consider all worktrees, no filter                                                   |
| (none)                | Interactive — list everything and let the user pick                                 |

## Instructions

### Step 1: List all review worktrees

```bash
~/.claude/scripts/review-worktree.sh list --json
```

Parse the JSON. Each entry has:
- `platform_prefix` (`gl`/`gh`)
- `mr_id`
- `repo_slug`
- `main_repo`
- `worktree_path`
- `worktree_exists` (bool — `false` means meta is orphaned)
- `branch`, `title`, `target_branch` (optional)
- `last_verdict`, `rounds` (optional)
- `created_at`, `updated_at`, `age_days`

If the list is empty → inform user "no review worktrees found" and stop.

### Step 2: Apply filters

Walk the list and apply user-supplied filters:

- **`--older-than N`** → keep where `age_days >= N`
- **`--repo <slug>`** → keep where `repo_slug == <slug>`
- **`--merged`** → for each candidate, query the platform:
  - GitLab: `glab mr view <mr_id> --repo <derived from main_repo's remote> --output json` → check `state == "merged" || state == "closed"`
  - GitHub: `gh pr view <mr_id> --repo <derived> --json state` → check `state == "MERGED" || state == "CLOSED"`
  - Skip entries where the query fails (network/auth) — don't assume merged
- **`--all`** → keep everything
- **No flags** → keep everything (interactive mode)

**Always include orphaned entries** (`worktree_exists == false`) regardless of filters — they're safe to delete and have no value.

### Step 3: Present candidates to user

Render a table:

```
| # | Repo            | MR        | Age   | Verdict          | Rounds | Status                |
|---|-----------------|-----------|-------|------------------|--------|-----------------------|
| 1 | alilo-frontend  | gl-676    | 14d   | request_changes  | 2      | exists (MR open)      |
| 2 | api-service     | gh-42     | 30d   | approve          | 1      | exists (MR merged)    |
| 3 | alilo-frontend  | gl-555    | 60d   | -                | -      | orphaned (no worktree)|
```

For each row, briefly show the worktree path and branch.

### Step 4: Confirm removal

Use `AskUserQuestion` to confirm which entries to remove. Options:
- "Remove all listed"
- "Remove orphaned + merged only"
- "Pick individually"
- "Cancel"

If "Pick individually" → loop and ask per-entry (or accept a comma-separated list of indices).

### Step 5: Execute removal

For each confirmed entry:

```bash
~/.claude/scripts/review-worktree.sh remove <platform_prefix> <mr_id>
```

The helper:
- Reads the sidecar to find `main_repo`
- Runs `git -C <main_repo> worktree remove --force <worktree>`
- Runs `git -C <main_repo> worktree prune`
- Deletes the sidecar
- Removes the per-repo slug dir if empty

### Step 6: Final report

Print a summary:
- Number removed
- Number skipped (user choice / filter mismatch)
- Number failed (with the helper's stderr)
- Run `~/.claude/scripts/review-worktree.sh list` one more time to show the final state

## Rules

- **NEVER** remove a worktree without explicit user confirmation (unless the entry is orphaned — no `worktree_path` directory exists)
- **NEVER** touch directories outside `~/.claude/worktrees/reviews/`
- **NEVER** delete a worktree whose meta.json indicates `last_verdict` is unset AND `rounds` is unset AND `age_days < 1` — that's likely an in-progress review; warn the user before removing
- When `--merged` filter is used and a platform query fails, **skip** the entry (don't assume merged status)
- Always run `git worktree prune` in each affected main repo at the end (the helper does this per-removal — no extra action needed)
