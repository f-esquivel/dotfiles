---
name: evaluate-mr-notes
description: Evaluate unresolved review notes on a GitLab MR against the current codebase, commit valid fixes grouped by file/concern, then — after the user confirms the commits are pushed — reply "Addressed on {sha}" on each addressed inline thread. CodeRabbit summary-note observations (outside-diff/nitpick/duplicate) are fixed but never replied to, since their parent summary discussion doesn't thread. For invalid notes, drafts a reply in the original note language and lets the user post via glab or copy to clipboard.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(git *), Bash(glab *), Bash(python3 *), Bash(jq *), Bash(pbcopy), Bash(mkdir *), Task
argument-hint: <MR id> --reviewer <name> [--force-reevaluate]
---

# Evaluate MR Notes

Evaluate review notes on MR: $ARGUMENTS

## Purpose

Given an MR ID and a reviewer name, this skill:
1. Fetches unresolved review threads from that reviewer
2. Validates each note against the **current codebase HEAD**
3. Presents a verdict table for batch approval
4. Implements + commits accepted fixes (grouped by file/concern)
5. After the user confirms the fixes are pushed, replies `Addressed on {sha}` on **inline** threads whose notes were addressed (CodeRabbit summary-note observations are committed but **never replied to** — their parent summary discussion doesn't thread correctly)
6. For invalid notes, drafts a reply in the original note language and offers to post via `glab` or copy via `pbcopy`

This skill is **GitLab-only**.

## Arguments

- **Positional `<MR id>`** — GitLab MR IID (e.g. `1234`)
- **`--reviewer <name>`** (required) — accepts a known alias (see **Reviewer Aliases** below) or a raw GitLab `username` (e.g. `jdoe`)
- **`--force-reevaluate`** (optional flag) — ignore the sidecar (Step 1b) and re-evaluate every matching note from scratch, including ones marked as previously addressed, replied, or skipped

If `--reviewer` is missing, abort with a usage hint.

### Reviewer Aliases

These aliases are hardcoded for the user's eseplus workspace. When `--reviewer` matches an alias (case-insensitive), use the mapped GitLab `username` for filtering. When it does not, treat the value as a raw username.

| Alias                       | Resolves to                                             | Match strategy                                                |
|-----------------------------|---------------------------------------------------------|---------------------------------------------------------------|
| `coderabbit`, `coderabbitai`| `group_4958916_bot_cdae674d4291a8f0e45956c7c42fa408`    | Exact `author.username` match (eseplus group's CodeRabbit bot)|
| `jose`                      | `joseantonio1`                                          | Exact `author.username` match                                 |
| `kevin`                     | `kevin567`                                              | Exact `author.username` match                                 |
| `tl`                        | Whichever of `joseantonio1` / `kevin567` reviewed       | See below                                                     |

**`tl` resolution.** Only one TL ever reviews a given MR — they don't overlap. Resolution:

1. Fetch unresolved threads as in Step 3.
2. Restrict to threads authored by `joseantonio1` **or** `kevin567`.
3. Identify which TL authored those threads.
4. **If one TL has unresolved threads** → proceed with that TL's notes; report the resolved identity to the user.
5. **If neither has unresolved threads** → abort with a clear message.
6. **If somehow both appear** (unexpected) → treat as an anomaly: report both counts and abort, asking the user to invoke the skill with the specific username instead of `tl`.

Aliases live in this skill only — do **not** import or sync with `/create-mr`'s reviewer list. They share data by convention, not by reference.

## Instructions

### Step 1: Preconditions

1. Detect platform via `git remote get-url origin`. If it does **not** contain `gitlab`, abort with a clear error: this skill is GitLab-only.

2. Parse arguments. Validate MR ID is numeric and `--reviewer` is present.

3. **Branch check** — ensure the working tree is on the MR's source branch:
   ```bash
   MR_BRANCH=$(glab mr view <MR_ID> --output json | python3 -c "import sys,json; print(json.load(sys.stdin)['source_branch'])")
   CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```
   - If `CUR_BRANCH == MR_BRANCH` → continue.
   - Else attempt `glab mr checkout <MR_ID>`. If it fails (dirty working tree, conflicting branch, etc.) **abort** and tell the user exactly why (paste the `glab` stderr). Do not try to stash or force.

4. `git fetch origin` to ensure local refs are current.

### Step 1b: Load Sidecar (if present)

Sidecar path: `$REPO_ROOT/reviews/eval-{mr-id}.md`.

1. If `reviews/` does not exist, create it lazily (only when about to write at the end of Step 10) — do **not** create it on a no-op run.
2. If `reviews/` was just created, append `reviews/` to `.git/info/exclude` (idempotent — skip if already present).
3. If the sidecar file does not exist → start with empty `addressed`, `invalid_replied`, `skipped_uncertain` lists and `runs = []`.
4. If it exists → parse the YAML frontmatter and load those lists into memory.
5. If `--force-reevaluate` is set, **ignore** the sidecar's `addressed` / `invalid_replied` / `skipped_uncertain` lists for filtering purposes — but **preserve** the file so prior `runs[]` history is not lost; the new run still appends to `runs[]` at the end.

The sidecar file is **never committed and never referenced externally** — same rule as `/review-mr` history files.

### Step 2: Resolve Reviewer Identity

1. Look up `--reviewer` in the **Reviewer Aliases** table above.
   - If matched, use the mapped username(s) for filtering.
   - For `tl`, defer disambiguation until after Step 3 fetches discussions (see the alias table for the disambiguation rules).
2. If `--reviewer` is not a known alias, treat the raw value as a GitLab `username` (exact match against `author.username`, case-insensitive).

In all cases, the final filter is an exact match against `author.username` — never display name, never partial match. This avoids false positives on users with similar names.

Resolve the project ID via the helper so subsequent API calls are reliable:
```bash
eval "$(~/.claude/scripts/gl-project-id.sh)"   # exports PROJECT_ID (encoded path or numeric)
```

### Step 3: Fetch Discussions

```bash
glab api --paginate "projects/${PROJECT_ID}/merge_requests/<MR_ID>/discussions" > /tmp/mr-<id>-discussions.json
```

Each discussion has `id`, `notes[]`. For each discussion:
- A thread is **resolvable** if any note has `resolvable: true`.
- A thread is **resolved** if `notes[0].resolved == true` (GitLab marks all notes in a resolved thread).
- Capture the **first note** of each thread as the "review note" (the rest are replies).
- Also retain the **`discussion_id`** of every note authored by the reviewer — for **inline** threads it is the target for `Addressed on {sha}` replies. (Parsed sub-observations from Step 3b are fixed but **not** replied to — see Step 8a.)

### Step 3b: Parse CodeRabbit Summary Notes (only when `--reviewer coderabbit`)

CodeRabbit posts a **single non-resolvable summary note** per review run that contains observations CodeRabbit could not attach as inline diff notes. These appear in collapsible markdown sections inside the note body:

- `<summary>⚠️ Outside diff range comments (N)</summary>` — issues on lines outside the MR diff
- `<summary>🧹 Nitpick comments (N)</summary>` — stylistic / minor suggestions
- `<summary>♻️ Duplicate comments (N)</summary>` — observations re-surfaced from a prior CodeRabbit run on the same MR

All three sections share the same internal structure (file group → per-observation entry). Parse them with the same logic; only the `section` field differs.

For each CodeRabbit-authored note where `resolvable: false`, parse the body and extract every observation in those sections as a **virtual note** with the same shape used elsewhere in the skill.

#### Parsing rules

The relevant body fragment looks like:

```
<details><summary>⚠️ Outside diff range comments (2)</summary><blockquote>
  <details><summary>app/Http/Controllers/LearningExperienceController.php (2)</summary><blockquote>
    `205-220`: _⚠️ Potential issue_ | _🟠 Major_ | _⚡ Quick win_
    **Cache coherency issue: `toggleLxStatus` doesn't invalidate cache.**
    <body paragraphs, proposed diff inside ```diff fences, AI prompt inside another <details>>
    ---
    `255-265`: _⚠️ Potential issue_ | _🟠 Major_ | _⚡ Quick win_
    ...
  </blockquote></details>
</blockquote></details>

<details><summary>🧹 Nitpick comments (3)</summary><blockquote>
  <details><summary>app/Traits/HasTranslations.php (1)</summary><blockquote>
    `17-20`: _⚡ Quick win_
    **Add a fail-fast guard for missing translation model configuration.**
    ...
  </blockquote></details>
  ...
</blockquote></details>
```

For each observation extract:

| Field             | Source                                                                                       |
|-------------------|----------------------------------------------------------------------------------------------|
| `section`         | `outside-diff`, `nitpick`, or `duplicate` (from the outer `<summary>` heading)               |
| `file`            | Inner `<summary>` heading text up to ` (N)` — e.g. `app/Traits/HasTranslations.php`          |
| `line_range`      | The backticked range or single line at the start of the observation (e.g. `17-20`, `24`)    |
| `severity_tags`   | The `_..._` italic tags on the heading line (e.g. `Potential issue`, `Major`, `Quick win`)  |
| `title`           | The first `**...**` bold line right after the heading                                        |
| `body`            | Paragraphs after the title, **excluding** the `<details>` blocks for `🐛 Proposed fix`, `Proposed patch`, `Proposed diff`, and `🤖 Prompt for AI Agents` |
| `proposed_diff`   | The ```diff fenced block inside the proposed-fix `<details>`, if present                     |
| `parent_note_id`  | The CodeRabbit summary note's `id`                                                           |
| `parent_discussion_id` | The `discussion_id` of the discussion that contains the summary note                    |

Treat each parsed observation as a **virtual note** for the rest of the flow (Step 5 evaluation, Step 6 verdict table, Step 7 commits). Virtual notes are **not** replied to in Step 8 — they are committed only.

#### Virtual-note keys

Each virtual note has **two keys**:

- **`primary_key`** — `coderabbit:{note_id}:{section}:{file}:{line_range}` (includes the parent note ID; unique per CodeRabbit run)
- **`secondary_key`** — `coderabbit:{section}:{file}:{line_range}` (note-ID-stripped; stable across CodeRabbit re-runs that produce a fresh summary note with a new ID)

The **secondary key is authoritative for sidecar dedupe** — if a re-posted summary note surfaces the same observation again (commonly via the `♻️ Duplicate comments` section), it is treated as already addressed when the sidecar contains the matching `secondary_key`. Both keys are recorded in the sidecar for traceability.

> **Skip** any section that contains zero observations. Skip the parent note entirely if it has none of the three sections (e.g. it's the CodeRabbit "walkthrough" comment).

> **All three sections count equally.** Outside-diff, nitpick, and duplicate observations are evaluated the same way — the verdict table separates them by `section` so the user can scan quickly, but no auto-skipping or auto-flagging by category.

### Step 4: Filter Notes

Apply these filters in order:

1. **Drop resolved threads.** Skip any discussion where the first note has `resolved: true`.
2. **Reviewer filter.** Keep only threads whose **first note** is authored by the resolved reviewer identity from Step 2.
3. **Diff-note filter.** Keep both `DiffNote` (inline) and `DiscussionNote` (general). Record `position.new_path` and `position.new_line` when present — those are the codebase coordinates.
4. **Virtual notes (CodeRabbit only).** Merge the virtual notes produced by Step 3b into the candidate set. They share the same evaluation pipeline as inline notes; their `file` / `line_range` come from the parsed section, not from a `position` object.
5. **Batch clustering** (for human reviewers only — skip for `coderabbit`):
   - Sort matching threads by `created_at` ascending.
   - Walk the sorted list, starting a new cluster whenever the gap between consecutive `created_at` exceeds **5 minutes**.
   - Keep only the **last cluster** (most recent batch).
   - For `coderabbit`, keep all matching unresolved threads + all virtual notes from the latest CodeRabbit summary note (CodeRabbit posts in one go).

6. **Sidecar dedupe** (skip if `--force-reevaluate`):
   - For inline notes, the dedupe key is `discussion:{discussion_id}`.
   - For virtual notes (Step 3b), use the `secondary_key` (`coderabbit:{section}:{file}:{line_range}`) — this catches re-posted CodeRabbit observations across summary-note IDs (e.g. items appearing in the `♻️ Duplicate comments` section of a later run).
   - Drop any candidate whose key already appears in the sidecar's `addressed`, `invalid_replied`, or `skipped_uncertain` lists.
   - Keep a `carryover` set of dropped candidates so the user-facing report can show what was suppressed.

Report to the user before proceeding:
- Total unresolved threads on the MR
- Threads matching the reviewer
- Threads in the selected batch (with the batch's date range)
- Sidecar suppression count (e.g. "5 candidates suppressed by sidecar: 4 addressed, 1 skipped previously") — or "sidecar bypassed (`--force-reevaluate`)"

### Step 5: Evaluate Each Note Against the Codebase

For each note in the selected batch:

1. If the note has a `position` (inline note), read the current file at `position.new_path` around `position.new_line` (±20 lines).
2. If the note is a general discussion (no position), parse the note body for file/line references; if none, treat as a high-level concern and evaluate against the MR as a whole.
3. Read the actual current code — do **not** rely on the snippet quoted in the note. Code may have moved since the note was posted.
4. Classify the note into one of:
   - **valid** — the issue exists in current code and a concrete fix is feasible.
   - **invalid** — the issue does not apply (already fixed, misread, false positive, out of scope, stylistic disagreement with project conventions).
   - **uncertain** — needs human judgment (architectural call, ambiguous intent, missing context).
5. For **valid** notes, draft a concrete fix plan (file + lines + change summary). Group notes that touch the same file or address the same concern.
6. For **invalid** notes, draft a reply in the **original language of the note** (detect from the note body — if the note is in Spanish, reply in Spanish; if English, reply in English). Keep the reply short, factual, and respectful: state why the suggestion doesn't apply.

### Step 6: Present Verdict Table for Approval

Show a single table for batch approval. Include a `Source` column that flags virtual notes. Prefix `duplicate`-source rows with 🔁 — CodeRabbit is re-asking about something previously declined or re-surfacing across runs, so the user can scrutinize them more carefully:

```markdown
| #  | Source           | Thread / Parent       | File:Line              | Verdict     | Note (summary)                  | Action                            |
|----|------------------|-----------------------|------------------------|-------------|---------------------------------|-----------------------------------|
| 1  | inline           | `abc123...`           | `src/auth.php:42`      | ✅ valid    | Missing null check              | Fix + commit (group: auth)        |
| 2  | inline           | `def456...`           | `src/user.php:15`      | ❌ invalid  | Suggests pattern X              | Draft reply (es): "..."           |
| 3  | outside-diff     | `ghi789...` (CR)      | `src/lx.php:205-220`   | ✅ valid    | Cache coherency                 | Fix + commit (group: lx-cache)    |
| 4  | nitpick          | `ghi789...` (CR)      | `src/trait.php:17-20`  | ❓ uncertain| Fail-fast guard                 | Skip — flag for user              |
| 5  | 🔁 duplicate    | `jkl012...` (CR)      | `src/hook.ts:39-47`    | ❌ invalid  | Composite key for dedupe        | Draft reply (es): "..."           |
```

Also show:
- Proposed **commit groups** (one commit per file/concern) with the threads each commit will address.
- Drafted replies for invalid notes (full text, so the user can review tone/language before posting).

Wait for explicit user approval. Allow the user to override individual verdicts before proceeding.

### Step 7: Implement & Commit Accepted Fixes

For each commit group approved in Step 6:

1. Implement the fix(es) for all threads in the group.
2. Run any project-level lint/type checks if `CLAUDE.md` documents them. Don't add new tooling.
3. Commit using the project's commit convention (this repo uses `type(scope): description`). One commit per group. Do **not** push (global rule).
4. Record the **short SHA** (`git rev-parse --short HEAD`) for each thread the commit addresses.

> If multiple threads share a commit, all of them get the same SHA in their reply.

### Step 8: Reply on Threads

> **Push gate.** Replies that reference a commit SHA must not be posted until those commits exist on the remote. After Step 7 commits, if there are any addressed **inline** replies to post (8a), prompt the user and wait:
>
> > Fixes committed locally. Push them, then confirm so I can post the `Addressed on {sha}` replies.
> > Pushed? (**yes** / **not yet**)
>
> - Wait for an explicit **yes** before posting any 8a reply. Do **not** push on the user's behalf (global rule).
> - If the user says **not yet**, hold and re-prompt when they're ready — do not post.
> - Invalid-note replies (8b) don't reference a SHA, so they need not wait on the push, but still respect the per-reply confirmation below.

#### 8a. Addressed inline threads (valid → committed)

**Inline notes only** (`DiffNote` / `DiscussionNote`). Post a reply on the discussion with body `Addressed on {short-sha}`:

```bash
glab api --method POST \
  "projects/${PROJECT_ID}/merge_requests/<MR_ID>/discussions/<DISCUSSION_ID>/notes" \
  --field "body=Addressed on ${SHORT_SHA}"
```

**Do not post replies for virtual notes** (Step 3b — CodeRabbit outside-diff / nitpick / duplicate observations). Their only reply target is the parent CodeRabbit summary discussion (`parent_discussion_id`), which is a non-threading summary note — a reply there does not surface on the right conversation. These observations are still evaluated, fixed, and committed; they are simply left **unreplied**. List the addressed virtual notes (with their SHAs) in the Step 10 summary so the user keeps the record.

Do **not** resolve the thread — the reviewer resolves on their end.

#### 8b. Invalid threads (drafted reply)

For each invalid-note reply drafted in Step 5, ask the user **per reply** (or batch-confirm if the user prefers):

> Post reply for thread `<id>` via `glab` or copy to clipboard?
> - **Post** → run the `glab api` POST above with the drafted body
> - **Copy** → `printf '%s' "<body>" | pbcopy` and tell the user it's on the clipboard

For **virtual notes**, skip the **Post** option entirely — there is no correctly-threading target on the summary discussion. Offer only **Copy** (or list the draft in the Step 10 summary) so the user can paste it wherever it belongs.

#### 8c. Uncertain threads

Do nothing. List them at the end so the user can decide manually.

### Step 9: Update Sidecar

Write `$REPO_ROOT/reviews/eval-{mr-id}.md`. Create the directory and the `.git/info/exclude` entry on first write (per Step 1b).

Frontmatter shape:

```yaml
---
mr: 42
project: "<group/subgroup/project>"
last_run: "<ISO 8601 timestamp>"
addressed:
  - key: "discussion:<discussion_id>"
    file: "<file>"
    line: <int>
    reviewer: "<username>"
    sha: "<short-sha>"
    run: <N>
  - key: "coderabbit:<note_id>:<section>:<file>:<line_range>"
    secondary_key: "coderabbit:<section>:<file>:<line_range>"
    section: "<outside-diff|nitpick|duplicate>"
    file: "<file>"
    line_range: "<range>"
    reviewer: "coderabbit"
    sha: "<short-sha>"
    run: <N>
invalid_replied:
  - key: "<key>"
    posted_via: "<glab|pbcopy>"
    run: <N>
skipped_uncertain:
  - key: "<key>"
    run: <N>
runs:
  - run: <N>
    date: "<ISO 8601 timestamp>"
    reviewer: "<resolved reviewer>"
    force_reevaluate: <true|false>
    batch_size: <int>
    suppressed_by_sidecar: <int>
    committed: <int>
    replies_posted: <int>
    skipped: <int>
---
```

Body: a **slim** Markdown log — one section per run, no observation bodies. Keep it scannable, not exhaustive:

```markdown
## Run <N> — <YYYY-MM-DD>
**Reviewer:** <name><br>
**Batch size:** <int> (suppressed by sidecar: <int>)<br>
**Outcome:** <int> committed · <int> invalid-replied · <int> skipped

| # | Source       | Key                                | Verdict     | SHA / Reply              |
|---|--------------|------------------------------------|-------------|--------------------------|
| 1 | inline       | `discussion:abc123`                | ✅ valid    | `a1b2c3d`                |
| 2 | outside-diff | `coderabbit:...:lx.php:205-220`    | ✅ valid    | `e4f5g6h`                |
| 3 | 🔁 duplicate | `coderabbit:...:hook.ts:39-47`     | ❌ invalid  | reply posted via `glab`  |
```

Do **not** embed the original observation body, proposed diff, or AI prompt — the frontmatter keys are enough to re-locate them via the GitLab API if needed.

Rules:
- **Append** to `addressed` / `invalid_replied` / `skipped_uncertain`; do not rewrite prior entries.
- Increment `run` by 1 over the max run already in `runs[]`; if no prior runs, start at 1.
- When `--force-reevaluate` is set and a candidate already appeared in a prior list, append a new entry for the new run instead of dropping the old one — keeps the trail intact.

### Step 10: Final Summary

Print:
- Inline threads addressed **and replied** (with commit SHAs)
- CodeRabbit summary-note observations addressed but **left unreplied** (with commit SHAs + `{file}:{line_range}`) — these are the outside-diff / nitpick / duplicate fixes the user can manually mark resolved on CodeRabbit's side
- Invalid replies posted vs copied
- Uncertain threads left for the user
- Sidecar updated at `reviews/eval-{mr-id}.md` (mention path only in-session — never in committed artifacts)
- Reminder: changes are committed locally; `git push` is the user's responsibility

## Rules

- **GitLab only.** Abort if remote is not GitLab.
- **`--reviewer` is required.** No silent defaults.
- **Never push.** Commit only; the user pushes manually.
- **Push gate before addressed replies.** Do not post any `Addressed on {sha}` reply until the user confirms the commits are pushed (Step 8 prompt). The SHA must exist on the remote first.
- **Never reply on CodeRabbit summary-note observations** (outside-diff / nitpick / duplicate virtual notes). Their parent summary discussion doesn't thread, so any reply lands on the wrong conversation. Still evaluate, fix, and commit them — just leave them unreplied and report them in the final summary.
- **Never auto-resolve threads.** Replies only.
- **Respect the original note language** when drafting replies for invalid notes — detect from the note body; do not switch language based on session output.
- **Read current code, not the note's quoted snippet** — notes may be stale.
- **Group commits by file/concern**, not one-per-note. The same SHA can address multiple threads.
- **Skip resolved threads.** Only operate on unresolved ones.
- **For human reviewers**, cluster by `created_at` gap > 5 minutes and pick the latest batch. For `coderabbit`, take all unresolved.
- **Branch enforcement.** If `glab mr checkout` fails, abort with the exact reason — do not stash, reset, or force.
- **Always show the verdict table + drafted invalid replies** before committing or posting anything.
- Follow the project's commit message convention. If unclear, ask before committing.
- **Sidecar (`reviews/eval-{mr-id}.md`) is internal-use only** — never commit, never reference in commit messages / MR comments / external artifacts. Add `reviews/` to `.git/info/exclude` (never `.gitignore`) on first creation.
- **CodeRabbit dedupe uses the `secondary_key`** (`coderabbit:{section}:{file}:{line_range}`). Same observation re-posted under a new summary-note ID — including via the `♻️ Duplicate comments` section — counts as already addressed unless `--force-reevaluate` is set.
- **`--force-reevaluate`** bypasses sidecar filtering but **preserves** the file; the new run appends to `runs[]` and lists like any other run.
