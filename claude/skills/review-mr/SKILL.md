---
name: review-mr
description: Review an existing merge request or pull request by ID. Fetches diff, analyzes changes, and provides structured code review with inline diff comments.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Write, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Bash(curl *), Bash(python3 *), Bash(~/.claude/scripts/*), Task
argument-hint: <MR/PR number>
---

# Review Merge Request / Pull Request

Review MR/PR: $ARGUMENTS

## Instructions

### Step 0: Detect Platform

Detect git platform via `git remote get-url origin`:
- Contains `gitlab` → use `glab` CLI
- Contains `github` → use `gh` CLI

### Step 1: Discover Review Conventions

Before reviewing, search the project for existing code review guidelines:

1. Check for convention docs (stop at first match):
   - `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`
   - `CODE_REVIEW.md`, `docs/code_review.md`, `docs/review_guidelines.md`
   - `CLAUDE.md` or `README.md` sections mentioning review, PR, or MR conventions
2. Check for MR/PR templates:
   - `.gitlab/merge_request_templates/`
   - `.github/PULL_REQUEST_TEMPLATE.md`

If project conventions are found → adopt them for review structure, comment format, severity labels, and any project-specific expectations. The skill's built-in defaults (Steps 5–6) are **fallbacks only**.

If no conventions found → proceed with the built-in defaults below.

### Step 2: Checkout MR/PR Branch

1. Save the current branch: `git branch --show-current`
2. Checkout the MR/PR branch locally:
   - GitLab: `glab mr checkout <id>`
   - GitHub: `gh pr checkout <id>`
3. After the review is complete (all steps done), return to the original branch: `git checkout <saved-branch>`

### Step 3: Fetch MR/PR Details

1. Fetch MR/PR metadata: `glab mr view <id>` or `gh pr view <id>`
2. Fetch the diff: `glab mr diff <id>` or `gh pr diff <id>`
3. Read changed files for full context — now on the correct branch
4. **GitLab:** Fetch `diff_refs` for later use when posting inline comments via the helper script (resolves project from git remote, validates SHAs, fails loud on errors):
   ```bash
   eval "$(~/.claude/scripts/gl-mr-diff-refs.sh <iid>)"
   # Exports: BASE_SHA, HEAD_SHA, START_SHA
   ```
   For machine-readable output: `~/.claude/scripts/gl-mr-diff-refs.sh <iid> --format=json`.
   Exit codes: `0` ok, `1` bad usage, `2` glab call failed, `3` response missing/invalid `diff_refs`.

### Step 4: Fetch Related Issues

#### Primary issue

Extract the **single directly related issue** from the MR/PR. This is the issue that will receive labels on verdict (Step 7). Evaluate in order (first match wins):

1. **Branch name** — extract issue ID from patterns like `feature/gl-123-*`, `fix/gh-456-*`:
   ```bash
   git branch --show-current | grep -oE '(gl|gh)-[0-9]+' | grep -oE '[0-9]+'
   ```
2. **MR/PR description** — look for `Relates to #123`, `Closes #123`, or bare `#123` references

Read the primary issue for context:
- GitLab: `glab issue view <id>`
- GitHub: `gh issue view <id>`

> **Important:** Only the primary issue receives verdict labels (`development::done` / `development::rejected`). Linked items (below) are for context only.

#### Linked items

Fetch additional linked issues for full context:

- **GitLab:** Use the issue links API to get the "Linked items" section:
  ```bash
  glab api "projects/<url-encoded-path>/issues/<id>/links"
  ```
  Read each linked issue with `glab issue view <id>` — pay attention to the `link_type` (`relates_to`, `blocks`, `is_blocked_by`) to understand dependencies.

- **GitHub:** Check for linked issues via timeline events:
  ```bash
  gh api repos/{owner}/{repo}/issues/{id}/timeline --jq '.[] | select(.event=="cross-referenced")'
  ```

#### How to use this context

- **Primary issue** → verify the implementation satisfies its acceptance criteria. This is the only issue that receives verdict labels
- **Linked issues** → context only (dependencies, related bugs, broader feature). Never label linked issues
- Call out in the review if the MR partially addresses a linked issue or misses a dependency
- If no related issues are found, proceed without them

### Step 5: Structured Review

Provide a review covering:

- **Summary:** What the MR does in 2-3 sentences
- **Requirements coverage:** If related issue found — does the implementation satisfy the acceptance criteria? Call out any missing or partially covered criteria
- **Scope check:** Does the MR do one thing or is it too broad?
- **Issues found:** Bugs, logic errors, security concerns
- **Style/conventions:** Does it follow project patterns?
- **Suggestions:** Improvements or alternatives
- **Verdict:** Approve / Request changes / Needs discussion

### Step 6: Draft Review Comments

After presenting the structured review, draft inline comments using the format below. If project conventions were found in Step 1, use those instead.

#### Comment Format

Each comment uses: `{emoji} **{label}**: {message}` or `{emoji} **{label}** (blocking/non-blocking): {message}`

**Severity** (visual urgency):

| Emoji | Severity | Meaning                               |
|-------|----------|---------------------------------------|
| 🔴    | Critical | Security, data loss, production crash |
| 🟠    | Warning  | Bugs, logic errors, missing checks    |
| 🔵    | Minor    | Style, conventions, cleanup           |
| 💚    | Praise   | Positive reinforcement                |
| ⚪     | Neutral  | Questions, thoughts                   |

**Labels** (intent — what response is expected):

| Label            | Typical severity | Purpose                                    |
|------------------|------------------|--------------------------------------------|
| **`issue`**      | 🔴 🟠            | Concrete problem that needs fixing         |
| **`suggestion`** | 🟠 🔵            | Improvement proposal — code or verbal      |
| **`nitpick`**    | 🔵               | Trivial fix, non-blocking by default       |
| **`chore`**      | 🔵               | Cleanup, maintenance, dead code            |
| **`question`**   | ⚪                | Asks for clarification, no assumption      |
| **`thought`**    | ⚪                | Opens discussion, explicitly non-directive |
| **`praise`**     | 💚               | Highlights something done well             |

Append `(blocking)` or `(non-blocking)` after the label when the default isn't obvious.

#### Comment structure

Each comment must specify:
- **File path** and **line number** (new_line in the diff)
- **Body text** in the language requested by the user (code examples always in English)
- **Suggestion block** only when a direct code replacement applies (see Step 7 syntax) — verbal observations, questions, thoughts, and praise should NOT include suggestion blocks

#### Examples

````
🔴 **issue**: This endpoint has no auth middleware — any unauthenticated
   user can delete records.

🟠 **issue**: Off-by-one error — the loop skips the last element.
   ```suggestion:-0+0
   for ($i = 0; $i <= count($items) - 1; $i++) {
   ```

🟠 **suggestion**: Extract this into a scope to avoid the N+1.

🔵 **nitpick**: Trailing comma missing.
   ```suggestion:-0+0
       'cache_ttl' => 3600,
   ```

🔵 **chore** (non-blocking): This TODO references a closed ticket — safe to remove.

⚪ **question**: Is the fallback to en_US intentional, or should it
   respect the user's locale?

⚪ **thought**: This service might benefit from being split in a follow-up.

💚 **praise**: Clean separation of concerns here.
````

Present all drafted comments to the user for approval before posting.

### Step 7: Post Inline Comments (GitLab)

Use `~/.claude/scripts/gl-post-review.sh` to post all comments. The script handles 2-channel routing, bulk publish with failure recovery, and verdict actions.

#### Build Review JSON

Create a temporary JSON file with all review data using Python:

```python
import json, tempfile

review_data = {
    "gitlab_url": "<gitlab_url>",           # e.g. "https://gitlab.com"
    "project_id": "<url_encoded_path>",      # e.g. "group%2Fproject"
    "mr_iid": <mr_iid>,
    "diff_refs": {
        "base_sha": "<base_sha>",
        "head_sha": "<head_sha>",
        "start_sha": "<start_sha>"
    },
    "comments": [ ... ],                     # see channel assignment below
    "verdict": "<verdict>",                  # "approve", "request_changes", "comment", "needs_discussion"
    "issue_id": <issue_id>                   # primary issue ID, or omit if none
}

path = tempfile.mktemp(suffix=".json")
with open(path, 'w') as f:
    json.dump(review_data, f, indent=2)
print(path)
```

#### Channel Assignment

Each comment object must specify a `channel` and the correct text field:

| Channel    | Labels                                  | Text field | Behavior                     |
|------------|-----------------------------------------|------------|------------------------------|
| `"direct"` | praise, question, thought               | `"body"`   | Immediate (Discussions API)  |
| `"draft"`  | issue, suggestion, nitpick, chore       | `"note"`   | Batched (Draft Notes API)    |

```json
{
    "channel": "direct",
    "body": "💚 **praise**: Clean separation of concerns.",
    "old_path": "src/auth.php",
    "new_path": "src/auth.php",
    "new_line": 42,
    "old_line": null
}
```

```json
{
    "channel": "draft",
    "note": "🟠 **issue**: Off-by-one error.\n\n```suggestion:-0+0\nfor ($i = 0; $i <= count($items) - 1; $i++) {\n```",
    "old_path": "src/user.php",
    "new_path": "src/user.php",
    "new_line": 15,
    "old_line": null
}
```

#### GitLab Suggestion Syntax

To render the interactive **"Suggested change"** widget, use this markdown inside the comment body:

````
```suggestion:-N+M
replacement code here
```
````

Where:
- `-N` = lines **above** the commented line to include in replacement
- `+M` = lines **below** the commented line to include in replacement
- The commented line itself is always included → total replaced = `N + 1 + M`

| Syntax            | Replaces                                |
|-------------------|-----------------------------------------|
| `suggestion:-0+0` | Only the commented line (1 line)        |
| `suggestion:-0+2` | Commented line + 2 below (3 lines)      |
| `suggestion:-1+1` | 1 above + commented + 1 below (3 lines) |

If the comment is observational (no direct replacement), omit the suggestion block entirely.

#### Position Parameters

| Line type                  | Set                            | Description                     |
|----------------------------|--------------------------------|---------------------------------|
| **Added line** (green `+`) | `new_line` only                | Line exists only in new version |
| **Removed line** (red `-`) | `old_line` only                | Line exists only in old version |
| **Context line** (white)   | Both `old_line` AND `new_line` | Line exists in both versions    |

Suggestions work on added and context lines. Avoid placing suggestions on removed-only lines. Use `null` for line fields that should be omitted.

**CRITICAL — Context line positioning:** Comments on context lines (unchanged lines visible in the diff hunk) **MUST** set both `old_line` and `new_line`. Setting only `new_line` with `old_line: null` will silently fail — the draft note is created but cannot be published. To find the correct `old_line` for a context line, parse the diff hunk header (`@@ -old_start,old_count +new_start,new_count @@`) and count lines, skipping `+` lines for the old counter and `-` lines for the new counter. If a comment targets a line **outside any diff hunk**, it cannot be placed as a DiffNote — post it as a general MR discussion instead.

**Line number verification:** Always cross-reference the target line number against the actual diff output. The line number in the source file may differ from the line number in the diff's new-side due to additions/removals in earlier hunks.

#### Run Posting Script

```bash
~/.claude/scripts/gl-post-review.sh "$REVIEW_JSON"
```

The script handles:
1. Token extraction from `glab auth status`
2. Channel A: POST direct comments via Discussions API
3. Channel B: POST draft notes via Draft Notes API
4. Bulk publish drafts (with failure recovery — re-fetch, individual publish, re-verify)
5. Verdict: approve → `glab mr approve` + `development::done` labels; request_changes → `development::rejected` labels

**Exit codes:** 0 = success, 1 = partial failure, 2 = total failure

Clean up the temp file after the script completes: `rm "$REVIEW_JSON"`

#### Post-Publish Verification

After the script completes (especially if it reported warnings or non-zero exit), verify that no duplicate comments were created:

```bash
glab api "projects/<path>/merge_requests/<iid>/discussions" | python3 -c "
import sys, json
discussions = json.load(sys.stdin)
seen = {}
dupes = []
for d in discussions:
    for n in d.get('notes', []):
        if n.get('author', {}).get('username') == '<your_username>' and n.get('type') == 'DiffNote':
            key = (n.get('position', {}).get('new_path'), n.get('position', {}).get('new_line'), n['body'][:80])
            if key in seen:
                dupes.append((d['id'], n['id'], key))
            else:
                seen[key] = (d['id'], n['id'])
print(f'{len(dupes)} duplicate(s) found')
for d_id, n_id, key in dupes:
    print(f'  DELETE discussion={d_id} note={n_id} file={key[0]}:{key[1]}')
"
```

If duplicates are found, delete them:
```bash
glab api --method DELETE "projects/<path>/merge_requests/<iid>/discussions/<discussion_id>/notes/<note_id>"
```

**For "Request changes" verdict:** The script labels MR and issue with `development::rejected`. Provide the user with manual instructions:

> **Manual action required — "Submit your review" in GitLab UI:**
> 1. Click **"Your review"** button on the MR
> 2. Select: **Request changes**
> 3. Summary: `{paste the review summary from Step 5}`
> 4. Click **"Submit review"**

#### Managing Notes

**Delete a draft note** (before publishing):
```
DELETE /projects/:id/merge_requests/:iid/draft_notes/:draft_note_id
```

**Delete a published note:**
```
DELETE /projects/:id/merge_requests/:iid/discussions/:discussion_id/notes/:note_id
```

**Update a published note:**
```
PUT /projects/:id/merge_requests/:iid/discussions/:discussion_id/notes/:note_id
```

**Warning:** Updating an inline note preserves its position but may break suggestion rendering. Prefer deleting + recreating when the suggestion block needs changes.

Find discussion/note IDs:
```bash
glab api "projects/<path>/merge_requests/<iid>/discussions"
```

### Step 7b: Post Inline Comments (GitHub)

Use the `gh api` with the Pull Request Review Comments API:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  -f body="comment" \
  -f path="file.js" \
  -f line=42 \
  -f commit_id="<head_sha>"
```

GitHub suggestion syntax is the same:
````
```suggestion
replacement
```
````

### Step 8: Save Review History

After posting comments and before returning to the original branch, save a review history file.

1. **Determine file path:** `reviews/{gl|gh}-{mr_id}.md`
   - Use `gl` for GitLab, `gh` for GitHub
   - `mr_id` is the MR/PR number from `$ARGUMENTS`
2. **Create `reviews/` directory** if it doesn't exist:
   - `mkdir -p reviews`
   - Add `reviews/` to `.git/info/exclude` if not already present (same pattern as `specs/`)
3. **Write the review history file** with this structure:

```markdown
---
mr_id: <id>
platform: gitlab  # or github
project: "<group/project>"
branch: "<source-branch>"
target_branch: <target>
title: "<MR/PR title>"
primary_issue: <issue_id or null>
rounds:
  - round: 1
    date: "<ISO 8601 timestamp>"
    head_commit: "<head_sha from diff_refs>"
    verdict: "<approve|request_changes|needs_discussion>"
    comments_posted: <count>
---

## Round 1 — <YYYY-MM-DD>

### Summary
<2-3 sentence summary from Step 5>

### Verdict: <Approve / Request Changes / Needs Discussion>

### Comments
| # | Status | Comment |
|---|--------|---------|
| 1 | ⏳ open | <emoji> **<label>** `<file:line>` — <short description> |
| 2 | ⏳ open | ... |
```

4. Inform the user the review was saved to `reviews/{gl|gh}-{mr_id}.md`

## Rules

- **NEVER** auto-merge or auto-approve
- Read the actual source files for context, not just the diff
- If unsure about a convention, check existing code before flagging
- **ALWAYS** draft and present all comments for user approval before posting
- **ALWAYS** use `curl` (not `glab api`) for posting GitLab inline discussions with suggestions
- When posting comments, verify the note `type` is `DiffNote` (not just `DiscussionNote`) — only `DiffNote` renders the suggestion widget
- Review files (`reviews/` directory) are **internal-use only** — never commit, never reference externally
- **NEVER** add `reviews/` to `.gitignore` — use `.git/info/exclude` instead
- When creating `reviews/` for the first time, automatically add it to `.git/info/exclude`
