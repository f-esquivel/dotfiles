---
name: sync-branch
description: Sync the current branch with its base (develop/main). Fetches the latest base, reports divergence, previews conflicts, and applies rebase or merge after explicit user choice. Never pushes.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Bash(git *), Bash(glab *), Bash(gh *), AskUserQuestion, Skill
argument-hint: [base-branch] [--rebase|--merge] [--dry-run]
---

# Sync Branch

Bring the current branch up to date with its base.

## Critical Rules

- **NEVER** push (`git push` is globally blocked) — the user pushes manually
- **NEVER** run destructive operations (`git reset --hard`, `git rebase --abort` without consent, force-anything) without explicit user approval. If a sync goes wrong, stop and ask
- **NEVER** sync a branch with uncommitted changes silently — stash with confirmation, or stop
- This skill never edits source files; it only manipulates git state

## Step 0 — Parse Arguments

`$ARGUMENTS` may contain:

- A branch name (any token not starting with `--`) → base branch override
- `--rebase` xor `--merge` → strategy override (skip Step 5 prompt)
- `--dry-run` → print commands without executing

If both `--rebase` and `--merge` are passed, prefer `--merge` (safer) and warn the user.

## Step 1 — Pre-flight

Run in parallel:

```bash
git rev-parse --abbrev-ref HEAD                                   # current branch
git status --porcelain                                            # clean tree?
git rev-parse --verify develop 2>/dev/null                        # local develop?
git rev-parse --verify main 2>/dev/null                           # local main?
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null  # upstream
test -d .git/rebase-merge -o -d .git/rebase-apply && echo REBASE_IN_PROGRESS
test -f .git/MERGE_HEAD && echo MERGE_IN_PROGRESS
test -f .git/CHERRY_PICK_HEAD && echo CHERRY_PICK_IN_PROGRESS
test -f .gitmodules && echo HAS_SUBMODULES
git config user.email                                             # for author filtering later
```

Stop early if:

- Current branch IS the base branch (`develop` or `main`) → tell the user; do not sync a base into itself
- Detached HEAD → tell the user; abort
- Any in-progress rebase/merge/cherry-pick → tell the user; abort (let them finish or abort it explicitly)
- Working tree dirty → list the dirty paths and use AskUserQuestion to choose: **stash and continue**, **commit first**, or **abort**. If "stash", run `git stash push -u -m "sync-branch auto-stash $(date +%s)"` and remember to pop at the end

If `HAS_SUBMODULES`, note it; offer to run `git submodule update --init --recursive` after sync.

## Step 2 — Resolve Base Branch and Remote

**Base branch** resolution order:

1. Branch name passed in `$ARGUMENTS` → use it
2. Else: prefer `develop` if it exists locally or on any remote
3. Else: fall back to `main` (or `master`)
4. If none exist → ask the user via AskUserQuestion

Confirm the resolved base **only if** ambiguous (both `develop` and `main` exist AND the current branch was created from neither's tip — show the merge-base of each and ask).

**Remote** resolution order:

1. `git config branch.<base>.remote` (the base's tracking remote)
2. Else: `git config branch.<current>.remote` (current branch's tracking remote)
3. Else: if exactly one remote exists → use it
4. Else: ask the user via AskUserQuestion

Bind the result as `<remote>` for the rest of the skill. Do not assume `origin`.

## Step 3 — Fetch & Report Divergence

```bash
git fetch <remote> <base> --prune
```

Then compute (use `<remote>/<base>` consistently — local `<base>` is irrelevant to the sync):

```bash
git rev-list --count <remote>/<base>..HEAD   # unique commits on this branch
git rev-list --count HEAD..<remote>/<base>   # new commits on base since branch-point
```

Report inline:

```
Branch:   <current>
Base:     <remote>/<base>
Ahead:    M unique commits on this branch
Behind:   K new commits on base since branch-point
```

If `behind == 0` → branch is already up to date. Stop and report; offer to pop the stash if one was created.

## Step 4 — Preview Conflicts

Predict conflicts before touching the working tree:

```bash
git merge-tree --write-tree <remote>/<base> HEAD
```

Exit code 1 or output containing `<<<<<<<` markers → list conflicting paths inline. (Requires git ≥ 2.38 for the `--write-tree` form. If the command is unsupported, skip the preview and note it.)

## Step 5 — Choose Strategy

If `--rebase` or `--merge` was passed in Step 0 → use it.
Otherwise use AskUserQuestion with these options:

| Option                | When                                                                  |
|-----------------------|-----------------------------------------------------------------------|
| **Rebase**            | Feature branch, history not yet shared, want a linear log             |
| **Merge**             | Branch already pushed and shared, others may have based work on it    |
| **Fast-forward only** | `ahead == 0` — just advance the branch pointer; no rebase or merge    |
| **Cancel**            | Don't sync — restore stash if any                                     |

**Recommend rebase** when:

- No upstream (branch not yet pushed), OR
- Upstream exists but `git log <remote>/<base>..HEAD --format='%ae' | sort -u` contains only the user's own email (from `git config user.email`, plus any `.mailmap` aliases)

**Recommend merge** when:

- Other authors appear in the commit list, OR
- The branch has an open MR/PR with review activity (`glab mr view` / `gh pr view --json reviews`), OR
- The branch is a long-lived shared branch (release branch, hotfix branch, etc.) — surface this even if the author heuristic says rebase

Always show the recommendation **and the reason** before asking.

If commits are GPG-signed (`git log -1 --format=%G? HEAD` returns `G`/`U`), warn the user that rebase will re-sign each commit and may prompt for a passphrase.

## Step 6 — Execute

### Dry run

If `--dry-run` was passed, print the exact command(s) that would run and the expected outcome, then exit.

### Rebase

```bash
git rebase <remote>/<base>
```

If conflicts arise:
1. Stop. Do NOT auto-resolve
2. Print `git status` so the user sees the conflicted files
3. Tell the user: "Resolve conflicts, run `git add <file>` for each, then `git rebase --continue`. Or `git rebase --abort` to undo."
4. Do not proceed further; the user drives the resolution

### Merge

```bash
git merge --no-ff <remote>/<base>
```

If conflicts arise: same protocol as rebase — stop, report, hand control to the user.

### Fast-forward only

```bash
git merge --ff-only <remote>/<base>
```

If the FF fails (unique commits exist), stop and report — the user picked the wrong strategy.

## Step 7 — Post-sync

After a clean sync:

1. Print the new state: `git log --oneline <remote>/<base>..HEAD | head -10`
2. If a stash was created in Step 1, pop it: `git stash pop`. If pop conflicts, stop and report — **the stash is preserved on the stash list**; user can resolve and `git stash drop` when done
3. **Force-push warning** — if strategy was `rebase` AND upstream exists, warn the user that the next push will need `--force-with-lease` (history was rewritten). Print the exact command. **Do not push.**
4. If `HAS_SUBMODULES` was detected, offer: `git submodule update --init --recursive`
5. Offer follow-ups:
   - CI status: `glab ci status` / `gh run list --branch <current>`
   - Open MR/PR URL if one exists

## Notes

- This skill is intentionally cautious. The cost of a bad rebase is high; the cost of asking is one extra prompt
- This skill operates on `<remote>/<base>` directly. Local `<base>` is never modified
