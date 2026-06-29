---
name: review-branch
description: Review a local branch's committed changes against a base branch (default develop). Computes the diff, analyzes changes, prints a structured code review with inline diff comments, and saves review history. No MR/PR, no remote posting — fully local.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Bash(mkdir *)
argument-hint: "[branch] [--base <branch>]"
---

# Review Local Branch

Review local branch changes: $ARGUMENTS

Reviews the **committed** changes on a branch against a base branch — entirely local. No MR/PR is fetched, nothing is posted to GitLab/GitHub. Output is a structured review in the console plus a saved `reviews/` history file.

## Arguments

`$ARGUMENTS` is optional and free-form:

- **(empty)** → review the current branch against the default base
- **`<branch>`** → review `<branch>` against the default base
- **`--base <branch>`** → override the base branch (combine with a branch name, any order)

Examples: `` (current vs develop) · `feature/gl-123-foo` · `feature/gl-123-foo --base main` · `--base release/2.0`

## Instructions

### Step 1: Resolve Branch and Base

1. **Target branch** — the branch under review:
   - If a branch name was passed in `$ARGUMENTS`, use it.
   - Else use the current branch: `git branch --show-current`.

2. **Base branch** — what to diff against (first match wins):
   - If `--base <branch>` was passed, use it.
   - Else prefer `develop` if it exists: `git rev-parse --verify --quiet develop || git rev-parse --verify --quiet origin/develop`
   - Else fall back to the repo's default branch (`main`, then `master`).
   - State the chosen base explicitly to the user; if it had to fall back, say so.

3. **Validate** both refs resolve. If the target equals the base, or the base can't be found, stop and ask the user which base to use (`AskUserQuestion`).

4. **Compute the diff range** using the merge-base so only changes that actually belong to the branch are reviewed (not unrelated commits already on base):
   ```bash
   MERGE_BASE="$(git merge-base "<base>" "<target>")"
   git diff --stat "$MERGE_BASE".."<target>"   # overview
   git diff "$MERGE_BASE".."<target>"          # full diff
   git log --oneline "$MERGE_BASE".."<target>" # commits under review
   ```
   This reviews **committed** changes only. Uncommitted working-tree changes are out of scope.

5. If the diff is empty, report that the branch has no changes versus the base and stop.

> **No checkout, no worktree.** The review reads the diff and files in place via `git diff` / `git show`. The user's working tree is never touched — no `git checkout`, no worktree, no sidecar.

### Step 2: Discover Review Conventions

Before reviewing, search the project for existing code review guidelines (stop at first match):

1. Convention docs: `CONTRIBUTING.md`, `docs/CONTRIBUTING.md`, `CODE_REVIEW.md`, `docs/code_review.md`, `docs/review_guidelines.md`, or `CLAUDE.md` / `README.md` sections mentioning review/PR/MR conventions.
2. MR/PR templates: `.gitlab/merge_request_templates/`, `.github/PULL_REQUEST_TEMPLATE.md`.

If conventions are found → adopt them for review structure, comment format, and severity labels. The built-in defaults (Steps 4–5) are **fallbacks only**. If none found → use the defaults.

### Step 3: Gather Context

1. **Read changed files for full context** — not just the diff. Read the surrounding code so observations are accurate.
2. **Related issue (optional, context only)** — try to extract an issue ID from the branch name:
   ```bash
   echo "<target>" | grep -oE '(gl|gh)-[0-9]+' | grep -oE '[0-9]+'
   ```
   If found and a platform CLI is available (detect via `git remote get-url origin`), read the issue for acceptance-criteria context — **read only, never label or post**:
   - GitLab (`gitlab` remote): `glab issue view <id>`
   - GitHub (`github` remote): `gh issue view <id>`
   If no issue is found or no CLI is available, proceed without it.

### Step 4: Structured Review

Provide a review covering:

- **Summary:** What the branch does in 2–3 sentences (lean on the commit log + diff).
- **Requirements coverage:** If a related issue was found — does the implementation satisfy its acceptance criteria? Call out missing or partial coverage.
- **Scope check:** Does the branch do one thing, or is it too broad?
- **Issues found:** Bugs, logic errors, security concerns.
- **Style/conventions:** Does it follow project patterns?
- **Suggestions:** Improvements or alternatives.
- **Verdict:** Approve / Request changes / Needs discussion.

### Step 5: Draft Inline Comments

After the structured review, draft inline comments. If project conventions were found in Step 2, use those instead.

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
- **File path** and **line number** (new-side line in the diff).
- **Body text** in the language requested by the user (code examples always in English).
- **Suggestion block** only when a direct code replacement applies — verbal observations, questions, thoughts, and praise should NOT include one. Use a fenced ` ```suggestion ` block with the replacement code:

  ````
  🟠 **issue**: Off-by-one — the loop skips the last element.
  ```suggestion
  for ($i = 0; $i < count($items); $i++) {
  ```
  ````

**Line number verification:** Cross-reference each target line against the actual diff output — the source-file line number may differ from the diff's new-side line due to additions/removals in earlier hunks.

Present the structured review and all drafted comments to the user. Since nothing is posted, this is the final deliverable — there is no approval-to-post step.

### Step 6: Save Review History

Save a review history file in the repo.

1. **Determine file path:** `reviews/local-<branch-slug>.md`
   - `<branch-slug>` = target branch with `/` replaced by `-` (e.g. `feature/gl-123-foo` → `feature-gl-123-foo`).
2. **Create `reviews/` directory** if missing, and exclude it (never `.gitignore`):
   ```bash
   mkdir -p reviews
   grep -qxF 'reviews/' .git/info/exclude 2>/dev/null || echo 'reviews/' >> .git/info/exclude
   ```
3. **Rounds:** If `reviews/local-<branch-slug>.md` already exists, append a new `## Round N` section and add a row to the frontmatter `rounds:` list (increment N). Otherwise create it fresh at Round 1.
4. **Write the file** with this structure:

```markdown
---
type: local-branch
branch: "<target>"
base_branch: "<base>"
merge_base: "<merge-base sha>"
primary_issue: <issue_id or null>
rounds:
  - round: 1
    date: "<ISO 8601 timestamp>"
    head_commit: "<target HEAD sha>"
    verdict: "<approve|request_changes|needs_discussion>"
    comments: <count>
---

## Round 1 — <YYYY-MM-DD>

### Summary
<2-3 sentence summary from Step 4>

### Verdict: <Approve / Request Changes / Needs Discussion>

### Comments
| # | Status | Comment |
|---|--------|---------|
| 1 | ⏳ open | <emoji> **<label>** `<file:line>` — <short description> |
| 2 | ⏳ open | ... |
```

   Get the timestamp with `date -u +%Y-%m-%dT%H:%M:%SZ` and the head sha with `git rev-parse "<target>"`.

5. Inform the user the review was saved to `reviews/local-<branch-slug>.md`.

## Rules

- **Local only** — never post to GitLab/GitHub, never approve/merge, never label issues. Reading an issue for context is allowed; writing anything to the platform is not.
- Review **committed** changes on the branch against the base via merge-base — uncommitted working-tree changes are out of scope.
- Read the actual source files for context, not just the diff.
- If unsure about a convention, check existing code before flagging.
- Default base is `develop` (then the repo default branch); always state which base was used.
- No worktree, no `git checkout` — the review runs in place against the user's current working tree.
- Review files (`reviews/` directory) are **internal-use only** — never commit, never reference externally.
- **NEVER** add `reviews/` to `.gitignore` — use `.git/info/exclude` instead.
- When creating `reviews/` for the first time, automatically add it to `.git/info/exclude`.
