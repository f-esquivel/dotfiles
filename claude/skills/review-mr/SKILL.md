---
name: review-mr
description: Review an existing merge request or pull request by ID. Fetches diff, analyzes changes, and provides structured code review with inline diff comments.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Bash(curl *), Bash(python3 *), Task
argument-hint: <MR/PR number>
---

# Review Merge Request / Pull Request

Review MR/PR: $ARGUMENTS

## Instructions

### Step 0: Detect Platform

Detect git platform via `git remote get-url origin`:
- Contains `gitlab` → prefer MCP tools (`mcp__gitlab__*`) when available, fall back to `glab` CLI if not
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
4. **GitLab:** Fetch `diff_refs` for later use when posting inline comments:
   ```bash
   glab api "projects/<url-encoded-path>/merge_requests/<iid>" | python3 -c "
   import sys, json; mr = json.load(sys.stdin); refs = mr.get('diff_refs', {})
   print('base_sha:', refs.get('base_sha'))
   print('head_sha:', refs.get('head_sha'))
   print('start_sha:', refs.get('start_sha'))
   "
   ```

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

Comments are split into two channels based on intent:

| Channel             | Labels                                                 | API             | Why                                          |
|---------------------|--------------------------------------------------------|-----------------|----------------------------------------------|
| **Direct comments** | `praise:`, `question:`, `thought:`, discussion replies | Discussions API | Conversational, immediate visibility         |
| **Review notes**    | `issue:`, `suggestion:`, `nitpick:`, `chore:`          | Draft Notes API | Batched, atomic publish, single notification |

#### Auth Token

Extract the token from glab's auth status:
```bash
glab auth status -t 2>&1 | awk '/Token/{print $NF}'
```

#### Why `curl` and not `glab api` CLI

`glab api -f` sends form data — nested objects like `position` do **not** serialize correctly. Always use `curl` with `Content-Type: application/json` and a proper JSON body for both APIs.

> **MCP note:** `mcp__gitlab__glab_api` only returns pagination metadata (not the full API response), so you cannot verify note types or extract IDs. Use `curl` for posting where response verification matters.

#### GitLab Suggestion Syntax

To render the interactive **"Suggested change"** widget (with "Apply suggestion" button), use this markdown inside the comment body:

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

The `position` object determines where the comment anchors on the diff:

| Line type                  | Set                            | Description                     |
|----------------------------|--------------------------------|---------------------------------|
| **Added line** (green `+`) | `new_line` only                | Line exists only in new version |
| **Removed line** (red `-`) | `old_line` only                | Line exists only in old version |
| **Context line** (white)   | Both `old_line` AND `new_line` | Line exists in both versions    |

Suggestions work on added and context lines. Avoid placing suggestions on removed-only lines.

#### Channel A: Direct Comments (Discussions API)

For `praise:`, `question:`, `thought:`, and discussion replies. These appear immediately.

**Endpoint:** `POST /projects/:id/merge_requests/:iid/discussions`

```python
payload = {
    "body": "💚 praise: Clean separation of concerns here.",
    "position": {
        "position_type": "text",
        "base_sha": "<base_sha>",
        "head_sha": "<head_sha>",
        "start_sha": "<start_sha>",
        "old_path": "path/to/file.php",
        "new_path": "path/to/file.php",
        "new_line": 42
    }
}
```

#### Channel B: Review Notes (Draft Notes API)

For `issue:`, `suggestion:`, `nitpick:`, `chore:`. These accumulate as pending drafts visible only to the author, then publish atomically.

**Step 1 — Create draft notes** (one per comment):

`POST /projects/:id/merge_requests/:iid/draft_notes`

```python
payload = {
    "note": "🟠 issue: Off-by-one error.\n\n```suggestion:-0+0\nfor ($i = 0; $i <= count($items) - 1; $i++) {\n```",
    "position": {
        "base_sha": "<base_sha>",
        "head_sha": "<head_sha>",
        "start_sha": "<start_sha>",
        "position_type": "text",
        "old_path": "path/to/file.php",
        "new_path": "path/to/file.php",
        "new_line": 42
    }
}
```

> **Note:** The Draft Notes API uses `note` (not `body`) as the field name for the comment text.

**Step 2 — Bulk publish all drafts** (submits the review as "Comment"):

```bash
curl -s -X POST \
  -H "PRIVATE-TOKEN: $TOKEN" \
  "https://gitlab.com/api/v4/projects/$PROJECT/merge_requests/$MR_IID/draft_notes/bulk_publish"
```

**Step 3 — Submit review verdict:**

| Verdict             | API action                                       | Automated?     |
|---------------------|--------------------------------------------------|----------------|
| **Comment**         | `bulk_publish` (done in Step 2)                  | ✅ Automatic    |
| **Approve**         | `POST /projects/:id/merge_requests/:iid/approve` | ✅ Automatic    |
| **Request changes** | Not available via API, CLI, or MCP               | ⚠️ Manual only |

Based on the review verdict from Step 5:
- **Approve:** Run `glab mr approve <id>` after bulk publish. Label MR and related issue with `development::done`:
  ```bash
  glab mr update <id> --label "development::done"
  glab issue update <issue_id> --label "development::done"
  ```
- **Request changes:** Not available via API/CLI/MCP (`reviewer_state` is internal to GitLab's web controller). Label MR and related issue with `development::rejected`, then provide the user with the form data to submit manually:
  ```bash
  glab mr update <id> --label "development::rejected"
  glab issue update <issue_id> --label "development::rejected"
  ```
  > **Manual action required — "Submit your review" in GitLab UI:**
  > 1. Click **"Your review"** button on the MR
  > 2. Select: **Request changes**
  > 3. Summary: `{paste the review summary from Step 5}`
  > 4. Click **"Submit review"**
- **Needs discussion / Comment:** No additional action needed after bulk publish

#### Posting script

Write all payloads with Python for proper escaping, then POST with curl. Process in order:
1. Post all direct comments (Channel A) first
2. Create all draft notes (Channel B)
3. Bulk publish drafts
4. If verdict is "Approve" → run `glab mr approve <id>` + label MR and issue `development::done`
5. If verdict is "Request changes" → label MR and issue `development::rejected` + notify user to submit manually in GitLab UI

Report progress as `N/total OK` or `N/total FAIL` for each channel.

#### Managing notes

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

## Rules

- **NEVER** auto-merge or auto-approve
- Read the actual source files for context, not just the diff
- If unsure about a convention, check existing code before flagging
- **ALWAYS** draft and present all comments for user approval before posting
- **ALWAYS** use `curl` (not `glab api`) for posting GitLab inline discussions with suggestions
- When posting comments, verify the note `type` is `DiffNote` (not just `DiscussionNote`) — only `DiffNote` renders the suggestion widget
