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

If project conventions are found → adopt them for review structure, comment format, severity labels, and any project-specific expectations. The skill's built-in defaults (Steps 4–5) are **fallbacks only**.

If no conventions found → proceed with the built-in defaults below.

### Step 2: Fetch MR/PR Details

1. Fetch MR/PR metadata: `glab mr view <id>` or `gh pr view <id>`
2. Fetch the diff: `glab mr diff <id>` or `gh pr diff <id>`
3. Read changed files for full context — don't review blindly from diff alone
4. **GitLab:** Fetch `diff_refs` for later use when posting inline comments:
   ```bash
   glab api "projects/<url-encoded-path>/merge_requests/<iid>" | python3 -c "
   import sys, json; mr = json.load(sys.stdin); refs = mr.get('diff_refs', {})
   print('base_sha:', refs.get('base_sha'))
   print('head_sha:', refs.get('head_sha'))
   print('start_sha:', refs.get('start_sha'))
   "
   ```

### Step 3: Fetch Related Issue

Extract the related issue from the MR/PR:
- Check MR/PR description for issue references (`#123`, `Closes #123`, `Relates to #123`)
- Check branch name for issue ID patterns (`feature/gl-123-*`, `fix/gh-456-*`)
- GitLab: `glab issue view <id>`
- GitHub: `gh issue view <id>`

Use the issue's description and acceptance criteria as context for the review — verify the implementation actually satisfies the requirements. If no related issue is found, proceed without it.

### Step 4: Structured Review

Provide a review covering:

- **Summary:** What the MR does in 2-3 sentences
- **Requirements coverage:** If related issue found — does the implementation satisfy the acceptance criteria? Call out any missing or partially covered criteria
- **Scope check:** Does the MR do one thing or is it too broad?
- **Issues found:** Bugs, logic errors, security concerns
- **Style/conventions:** Does it follow project patterns?
- **Suggestions:** Improvements or alternatives
- **Verdict:** Approve / Request changes / Needs discussion

### Step 5: Draft Review Comments

After presenting the structured review, draft inline comments using the format below. If project conventions were found in Step 1, use those instead.

#### Comment Format

Each comment uses: `{severity emoji} {label}: {message}`

**Severity** (visual urgency):

| Emoji | Severity | Meaning                               |
|-------|----------|---------------------------------------|
| 🔴    | Critical | Security, data loss, production crash |
| 🟠    | Warning  | Bugs, logic errors, missing checks    |
| 🔵    | Minor    | Style, conventions, cleanup           |
| 💚    | Praise   | Positive reinforcement                |
| ⚪     | Neutral  | Questions, thoughts                   |

**Labels** (intent — what response is expected):

| Label         | Typical severity | Purpose                                    |
|---------------|------------------|--------------------------------------------|
| `issue:`      | 🔴 🟠            | Concrete problem that needs fixing         |
| `suggestion:` | 🟠 🔵            | Improvement proposal — code or verbal      |
| `nitpick:`    | 🔵               | Trivial fix, non-blocking by default       |
| `chore:`      | 🔵               | Cleanup, maintenance, dead code            |
| `question:`   | ⚪                | Asks for clarification, no assumption      |
| `thought:`    | ⚪                | Opens discussion, explicitly non-directive |
| `praise:`     | 💚               | Highlights something done well             |

Append `(blocking)` or `(non-blocking)` when the default isn't obvious.

#### Comment structure

Each comment must specify:
- **File path** and **line number** (new_line in the diff)
- **Body text** in the language requested by the user (code examples always in English)
- **Suggestion block** only when a direct code replacement applies (see Step 6 syntax) — verbal observations, questions, thoughts, and praise should NOT include suggestion blocks

#### Examples

````
🔴 issue: This endpoint has no auth middleware — any unauthenticated
   user can delete records.

🟠 issue: Off-by-one error — the loop skips the last element.
   ```suggestion:-0+0
   for ($i = 0; $i <= count($items) - 1; $i++) {
   ```

🟠 suggestion: Extract this into a scope to avoid the N+1.

🔵 nitpick: Trailing comma missing.
   ```suggestion:-0+0
       'cache_ttl' => 3600,
   ```

🔵 chore: This TODO references a closed ticket — safe to remove.

⚪ question: Is the fallback to en_US intentional, or should it
   respect the user's locale?

⚪ thought: This service might benefit from being split in a follow-up.

💚 praise: Clean separation of concerns here.
````

Present all drafted comments to the user for approval before posting.

### Step 6: Post Inline Comments (GitLab)

#### Why `curl` and not `glab api` CLI

`glab api -f` sends form data — nested objects like `position` do **not** serialize correctly. Always use `curl` with `Content-Type: application/json` and a proper JSON body for the Discussions API.

> **MCP alternative:** `mcp__gitlab__glab_api` with `flags: {"method": "POST", "header": ["Content-Type: application/json"], "input": "/path/to/payload.json"}` also works for posting inline `DiffNote` comments with suggestions. However, the MCP wrapper only returns pagination metadata (not the full API response), so you **cannot verify** the note type or extract IDs from the response. Use MCP for simple operations (GETs, deletes) and `curl` for posting where response verification matters.

#### Auth Token

Extract the token from glab's auth status:
```bash
glab auth status -t 2>&1
```

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

#### Posting via curl

Write JSON payloads with Python for proper escaping, then POST with curl:

```python
import json, subprocess

payload = {
    "body": "Comment text\n\n```suggestion:-0+0\nreplacement line\n```",
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

with open('/tmp/gl_comment.json', 'w') as f:
    json.dump(payload, f, ensure_ascii=False)

subprocess.run([
    "curl", "-s", "-X", "POST",
    "-H", f"PRIVATE-TOKEN: {token}",
    "-H", "Content-Type: application/json",
    "-d", "@/tmp/gl_comment.json",
    f"https://gitlab.com/api/v4/projects/{project}/merge_requests/{mr_iid}/discussions"
])
```

#### Batch posting

For multiple comments, build a list of payloads and iterate — post all in a single Python script for efficiency. Report progress as `N/total OK` or `N/total FAIL`.

#### Updating a note

```
PUT /projects/:id/merge_requests/:iid/discussions/:discussion_id/notes/:note_id
```

**Warning:** Updating the body of an inline note preserves its position but may break suggestion rendering. Prefer deleting + recreating over updating when the suggestion block needs changes.

#### Deleting a note

```
DELETE /projects/:id/merge_requests/:iid/discussions/:discussion_id/notes/:note_id
```

Find discussion/note IDs by listing discussions:
```bash
glab api "projects/<path>/merge_requests/<iid>/discussions"
```

### Step 6b: Post Inline Comments (GitHub)

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
