---
name: re-review-mr
description: Re-review a previously reviewed MR/PR. Reads review history, checks if previous comments were addressed, and reviews only new changes since last review round.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Bash(curl *), Bash(python3 *), Task
argument-hint: <MR/PR number>
---

# Re-review Merge Request / Pull Request

Re-review MR/PR: $ARGUMENTS

## Instructions

### Step 0: Detect Platform

Detect git platform via `git remote get-url origin`:
- Contains `gitlab` → use `glab` CLI
- Contains `github` → use `gh` CLI

Set the platform prefix: `gl` for GitLab, `gh` for GitHub.

### Step 1: Read Review History

1. Look for `reviews/{gl|gh}-{id}.md` where `{id}` is `$ARGUMENTS`

2. **If the file exists** → parse it:
   a. Parse the YAML frontmatter:
      - Extract `branch`, `target_branch`, `project`, `platform`
      - From the last entry in `rounds[]`: extract `head_commit`, `verdict`, `round` number
   b. Parse the markdown body — collect **all open comments** across all rounds:
      - From each round's Comments table: extract rows with `⏳ open` status
      - From re-review rounds' Resolution tables: extract rows with `⏳ persists` status
      - These become the "previous comments" for resolution checking
      - Comment numbering is global (continues across rounds)

3. **If the file does NOT exist** → attempt to bootstrap from API:
   a. Fetch MR/PR metadata (`glab mr view` / `gh pr view`) to get branch, target, title, diff_refs
   b. Fetch existing review comments from the API:
      - **GitLab:** `glab api "projects/<path>/merge_requests/<iid>/discussions"` — filter for `DiffNote` types
      - **GitHub:** `gh api repos/{owner}/{repo}/pulls/{id}/comments`
   c. **If comments found** → build a Round 0 (bootstrapped) history file:
      - Create `reviews/` dir + `.git/info/exclude` entry if needed
      - Write the history file with:
        - YAML frontmatter with MR metadata + `round: 0` entry (date = now, `head_commit` = current head_sha, `verdict: unknown`, `comments_posted` = count)
        - Markdown body with `## Round 0 — <date> (bootstrapped from API)` and a Comments table built from fetched comments, each marked `⏳ open`
        - Map API comments to the table format: extract emoji/label from the comment body if they follow the skill format, otherwise use `⚪ **imported**` as the label
      - Inform user: review history bootstrapped from existing API comments
      - Continue with the re-review using this bootstrapped history
   d. **If no comments found** → fall back to a full review:
      - Inform user: no history file and no API comments found, performing a full review
      - Execute a full review following `/review-mr` Steps 1–8 (including saving the history file)
      - Stop here — do not continue with re-review steps

### Step 2: Discover Review Conventions

Same as `/review-mr` Step 1 — search for project review guidelines, MR/PR templates, and CLAUDE.md conventions. Use project conventions when found, fall back to built-in defaults.

### Step 3: Checkout MR/PR Branch & Fetch Metadata

1. Save the current branch: `git branch --show-current`
2. Checkout the MR/PR branch:
   - GitLab: `glab mr checkout $ARGUMENTS`
   - GitHub: `gh pr checkout $ARGUMENTS`
3. Fetch current MR/PR metadata: `glab mr view $ARGUMENTS` or `gh pr view $ARGUMENTS`
4. **GitLab:** Fetch current `diff_refs`:
   ```bash
   glab api "projects/<url-encoded-path>/merge_requests/<iid>" | python3 -c "
   import sys, json; mr = json.load(sys.stdin); refs = mr.get('diff_refs', {})
   print('base_sha:', refs.get('base_sha'))
   print('head_sha:', refs.get('head_sha'))
   print('start_sha:', refs.get('start_sha'))
   "
   ```

### Step 4: Compute Delta Diff

1. Get the `head_commit` from the last review round (Step 1)
2. Check if the last reviewed commit exists locally:
   ```bash
   git cat-file -t <last_head_commit> 2>/dev/null
   ```
3. **If commit exists** → compute incremental diff:
   ```bash
   git diff <last_head_commit>..HEAD
   ```
4. **If commit does NOT exist** (force-push / rebase) → warn the user:
   > Previous review head commit `<sha>` not found — MR was likely force-pushed or rebased. Falling back to full diff against target branch.

   Then fall back to:
   ```bash
   git diff <target_branch>...HEAD
   ```
5. **If no changes** in the diff → skip new code review (Step 6), only perform resolution check (Step 5)

### Step 5: Resolution Check

For each comment from the previous round:

1. Read the current state of the file at the referenced line
2. Determine resolution status:
   - **resolved** — the issue was fixed or the suggestion was applied
   - **persists** — the code is unchanged or the problem remains
   - **superseded** — the file/line was removed or significantly refactored (the comment no longer applies)
3. Build a resolution table with visual status indicators:

| Emoji | Status     | Meaning                                       |
|-------|------------|-----------------------------------------------|
| ✅     | resolved   | Issue was fixed or suggestion applied         |
| ⏳     | persists   | Code unchanged or problem remains             |
| 🔄    | superseded | File/line removed or significantly refactored |

```markdown
### Previous Comments Resolution
| # | Status | File | Comment |
|---|--------|------|---------|
| 1 | ✅ resolved | `src/auth.php:42` | Auth middleware added |
| 2 | ⏳ persists | `src/user.php:15` | Still not extracted |
| 3 | 🔄 superseded | `src/old.php:10` | File removed |

> **Resolution: 1/3 resolved, 1 persists, 1 superseded**
```

### Step 6: Review New Changes

If there are new changes (from Step 4):

1. Read all changed files for full context (same as `/review-mr` Step 3)
2. Perform a structured review scoped to the delta diff only (same format as `/review-mr` Step 5):
   - Summary of new changes
   - Issues found in new code
   - Style/conventions
   - Suggestions
   - Verdict (considering both resolution status and new findings)
3. The verdict should account for:
   - Unresolved previous comments that still persist
   - New issues found in the delta
   - If all previous comments are resolved and no new issues → **Approve**

If there are no new changes, determine the verdict based solely on resolution status.

### Step 7: Draft Comments

Draft inline comments for new issues only (same format/labels as `/review-mr` Step 6). Previous comments that persist do NOT get re-posted — they are tracked in the resolution table.

### Step 8: Present for Approval

Present to the user:
1. **Resolution table** from Step 5
2. **New changes summary** from Step 6 (if applicable)
3. **New draft comments** from Step 7 (if any)
4. **Overall verdict**

Wait for user approval before posting.

### Step 9: Post Comments

Follow the same posting procedure as `/review-mr`:
- **GitLab:** Step 7 (2-channel: Discussions API for praise/question/thought, Draft Notes API for issue/suggestion/nitpick/chore, then bulk publish + verdict)
- **GitHub:** Step 7b (Pull Request Review Comments API)

> **⚠️ bulk_publish failure handling (CRITICAL — prevents duplicate comments)**
>
> GitLab's `bulk_publish` may return HTTP 500 yet still publish all drafts server-side. **Never retry or fall back to individual publish without verifying draft state first.**
>
> If `bulk_publish` returns a non-2xx status:
> 1. **Re-fetch the draft notes list** to check actual state
> 2. **If the list is empty** → bulk_publish succeeded despite the error. Continue to verdict.
> 3. **If drafts remain** → publish only the remaining drafts individually via `PUT /draft_notes/:id/publish`
> 4. **After individual publish, verify again** — re-fetch the list to confirm all drafts are gone before proceeding.

### Step 10: Update Review History

1. **Update YAML frontmatter** — append a new entry to the `rounds` array:
   ```yaml
   - round: <N+1>
     date: "<ISO 8601 timestamp>"
     head_commit: "<current head_sha>"
     verdict: "<verdict>"
     comments_posted: <count>
   ```

2. **Append markdown body** for the new round:

```markdown
## Round <N+1> — <YYYY-MM-DD>

### Previous Comments Resolution
| # | Status | File | Comment |
|---|--------|------|---------|
| 1 | ✅ resolved | `src/auth.php:42` | Auth middleware added |
| 2 | ⏳ persists | `src/user.php:15` | Still not extracted |

> **Resolution: 1/2 resolved, 1 persists**

### New Changes Summary
<summary from Step 6, or "No new changes since last review.">

### New Comments
| # | Status | Comment |
|---|--------|---------|
| 3 | ⏳ open | <emoji> **<label>** `<file:line>` — <short description> |
<or "No new comments.">

### Verdict: <Approve / Request Changes / Needs Discussion>
```

3. Return to the original branch: `git checkout <saved-branch>`
4. Inform the user the review history was updated

## Rules

- **NEVER** auto-merge or auto-approve
- Read the actual source files for context, not just the diff
- If unsure about a convention, check existing code before flagging
- **ALWAYS** present resolution table + new comments for user approval before posting
- **ALWAYS** use `curl` (not `glab api`) for posting GitLab inline discussions with suggestions
- When posting comments, verify the note `type` is `DiffNote` (not just `DiscussionNote`) — only `DiffNote` renders the suggestion widget
- Review files (`reviews/` directory) are **internal-use only** — never commit, never reference externally
- **NEVER** add `reviews/` to `.gitignore` — use `.git/info/exclude` instead
- Do NOT re-post previous comments that persist — they are tracked in the resolution table only
- If no history file exists: try bootstrapping from API comments first, fall back to full review only if no comments found either
