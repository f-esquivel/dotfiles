---
name: audit-spec-leaks
description: Audit the current branch for spec/review leaks across three sources — branch commits (vs a base branch, default `develop`), staged changes (`git diff --cached`), and commit messages on the branch. Flags raw spec list item IDs, spec/review file paths, and prose references that leaked into comments, docblocks, identifiers, log messages, strings, or commit subjects/bodies. Reports findings and proposes per-finding functional rewrites that preserve intent without exposing the spec ID. Spec and review files are local-only; their IDs and paths must never reach committed artifacts.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Grep, Glob, Bash(git *), Bash(grep *), Bash(rg *), Bash(awk *), Bash(sed *), Bash(sort *), Bash(uniq *), Bash(wc *), Bash(cat *), Bash(find *), Bash(printf *), AskUserQuestion, Agent
argument-hint: [base-branch] [--report-only] [--auto-apply] [--include=PATTERN] [--exclude=PATTERN] [--no-staged] [--no-commits] [--no-branch] [--staged-only] [--commits-only]
---

# Spec Leak Auditor

Audit the current branch for **raw spec list item IDs** (and other spec/review-internal references) that leaked into committed or about-to-be-committed artifacts. Spec files (`specs/`) and review files (`reviews/`) live only on the local machine — any reference to them in committed code, staged code, or commit messages (`FR-7`, `NFR-2`, `SPEC-ALPHA.md`, `specs/sample-feature/spec.md`, `reviews/gh-42.md`) is a leak and must be redacted.

The skill scans **three sources** in a single run (any subset can be disabled via flags):

| Source            | What it covers                                                              | Default |
|-------------------|-----------------------------------------------------------------------------|---------|
| Branch diff       | Added/modified lines on this branch vs the base branch (`BASE..HEAD`)       | On      |
| Staged changes    | Lines added in the index (`git diff --cached`) — not yet committed          | On      |
| Commit messages   | Subjects and bodies of commits on this branch (`git log BASE..HEAD`)        | On      |

Arguments: $ARGUMENTS

## Critical Rules

- **Audit only added/modified lines** of any diff (the `+` side). Removed lines (`-`) are out of scope
- **NEVER** commit changes, push, amend, or rebase on the user's behalf. Commit-message findings are **report-only** — the user fixes them manually (interactive rebase or `git commit --amend`)
- **NEVER** rewrite code semantics — proposed redactions must be behavior-preserving (rename + comment cleanup only)
- **NEVER** read the spec file's content into the diff or paste spec prose into committed code as a "fix" — the goal is to **remove** the dependency on the spec, not to inline it
- The skill must work with no spec file present — IDs are detected by shape, not by cross-referencing `specs/`
- Treat `reviews/` exactly like `specs/` — both are local-only and both leak the same way

## Step 1 — Parse Arguments

Order-independent. Parse from `$ARGUMENTS`:

| Token              | Meaning                                                                     |
|--------------------|-----------------------------------------------------------------------------|
| First bare word    | Base branch (default: `develop` if it exists, else `main`, else `master`)   |
| `--report-only`    | List findings; do not propose rewrites or edit anything                     |
| `--auto-apply`     | Apply every proposed rewrite without per-finding confirmation (single bulk approval at the end) |
| `--include=GLOB`   | Restrict scan to paths matching GLOB (repeatable)                           |
| `--exclude=GLOB`   | Skip paths matching GLOB (repeatable); always implicitly excludes `specs/`, `reviews/`, `.git/` |
| `--no-branch`      | Skip the branch-vs-base diff scan                                           |
| `--no-staged`      | Skip the staged (`git diff --cached`) scan                                  |
| `--no-commits`     | Skip the commit-message scan                                                |
| `--staged-only`    | Equivalent to `--no-branch --no-commits` (useful as a pre-commit gate)      |
| `--commits-only`   | Equivalent to `--no-branch --no-staged`                                     |

Defaults: per-finding confirmation (`--auto-apply` off), full scope (all three sources scanned). `--include`/`--exclude` apply to the branch-diff and staged-diff scans only — commit messages are not paths.

If the base branch does not exist locally:

```sh
git rev-parse --verify --quiet "<base>" || git rev-parse --verify --quiet "origin/<base>"
```

Fall back to `origin/<base>` if present; otherwise abort and ask the user.

## Step 2 — Collect Scan Inputs

Gather up to three independent inputs (skip any disabled by flags). Each input produces its own list of `(source, location, raw_text)` tuples that feed Step 3.

### 2a — Branch diff (source: `branch`)

Use a merge-base diff so only **this branch's** additions are scanned:

```sh
BASE=$(git merge-base HEAD "<base>")
git diff --unified=0 --no-color "$BASE"..HEAD -- ':!specs/' ':!reviews/'
```

Apply any `--include`/`--exclude` pathspecs after the implicit `specs/`/`reviews/` exclusion.

From the diff, extract only lines starting with `+` (excluding `+++` headers) and record `file:line` for each — `line` is the new-file line number derived from the hunk header. Location format: `<path>:<line>`.

### 2b — Staged changes (source: `staged`)

```sh
git diff --cached --unified=0 --no-color -- ':!specs/' ':!reviews/'
```

Apply the same `--include`/`--exclude` filters. Extract `+` lines the same way. Location format: `<path>:<line> (staged)`.

Note: a staged hunk may overlap a branch-diff hunk if the change is already part of an earlier commit on the branch and then re-edited. That is fine — each source is scanned independently; the same leak surfacing in both lists is reported in each source's section, deduped by `(file, line, raw_text)` only within a source.

### 2c — Commit messages (source: `commits`)

```sh
git log --format='%H%x00%s%x00%b%x1e' "$BASE"..HEAD
```

Records are NUL-separated `hash\0subject\0body` and record-separated by `\x1e`. For each commit, scan subject and body lines independently. Location format: `<short-sha> subject` or `<short-sha> body:<line-in-body>`.

If any commit is a merge commit (`git log --merges`), include it but tag its source as `commits (merge)` — leaks in merge commits are often inherited from earlier branches and may need attention upstream.

### Empty inputs

If **all three** enabled inputs are empty → report `no changes to scan against <base>` and exit. If only some are empty, note them in the summary (`Staged: empty`) and continue with the rest.

## Step 3 — Detect Leaks

Run all detectors against the `+` lines (for `branch`/`staged`) and the message lines (for `commits`) collected in Step 2. Each match becomes a **finding** with: source (`branch`/`staged`/`commits`), location, raw text, detector that fired, surrounding context (3 lines for code, ±1 line for commit bodies), kind (`identifier` / `comment` / `string` / `docblock` / `log` / `path` / `commit-subject` / `commit-body` / `commit-trailer`).

### Detectors

| ID    | Pattern (PCRE)                                              | Catches                                                                 |
|-------|-------------------------------------------------------------|-------------------------------------------------------------------------|
| D1    | `\b(FR|NFR|AC|AR|TE|REQ|TASK|STEP|US|UC)-[A-Z]?\d+\b`       | Canonical spec item IDs: `FR-7`, `NFR-2`, `AC-3`, `FR-X12`              |
| D2    | `\bSPEC-[A-Z0-9_]+(?:\.md)?\b`                              | Spec file references: `SPEC-ALPHA`, `SPEC-ALPHA.md`                     |
| D3    | `(?<![/\w])specs?/[\w./-]+\.md\b`                            | Spec paths: `specs/sample-feature/spec.md`                              |
| D3b   | `(?<![/\w])reviews/[\w./-]+\.md\b`                           | Review paths: `reviews/gh-42.md`, `reviews/gl-7.md`                     |
| D4    | `\bPhase \d+\b` *inside comments/strings/docblocks/commit messages only* | Spec phasing language: `// Phase 2 — sample-step`           |
| D5    | `\b[A-Z]{2,5}-\d{1,4}\b` *inside comments/strings/commit messages only* | Generic spec-shaped IDs not caught by D1 (lower confidence — still **blocker**) |
| D6    | `(?i)\b(see|per|implements?|fulfills?|tracked by|refs?|closes?|fixes?)\s+(FR|NFR|AC|SPEC)[- ]` | Prose references: `// per FR-7`, `closes FR-3`     |
| D7    | `(?i)^(Spec|Specs|Spec-Ref|Spec-File|Refs-Spec|Implements-Spec):\s*\S` *commit-trailer kind only* | Git trailers leaking spec metadata: `Spec: specs/foo/spec.md` |

**Filtering rules:**

- D1/D2/D3/D3b/D6/D7 → always flagged regardless of context
- D4/D5 → for `branch`/`staged` sources, flag only when the match is inside a comment, string literal, or docblock (identifiers are too noisy: false positives like `HTTP-2`, `UTF-8`). For the `commits` source, treat the entire message as comment-equivalent and flag unconditionally
- D7 → only meaningful in `commits` source (`commit-trailer` kind). Skip in `branch`/`staged`
- Skip matches inside file paths that look like third-party / vendor / lock files (`vendor/`, `node_modules/`, `*.lock`, `*.min.*`, `dist/`, `build/`)
- Skip matches inside Markdown files under `docs/` only if the surrounding section header is "Glossary" or "References" — otherwise flag (docs commits leak too)
- Auto-generated commit trailers from common tools (`Co-authored-by:`, `Signed-off-by:`, `Change-Id:`) are not spec metadata and are not flagged by D7

Detect comment/string context by language using simple heuristics (line-based, no AST):

| Language family             | Comment markers       | String quotes       |
|-----------------------------|-----------------------|---------------------|
| C/C++/Java/JS/TS/PHP/Go/Rust| `//`, `/* */`         | `"`, `'`, `` ` ``   |
| Python/Ruby/Shell/YAML      | `#`                   | `"`, `'`            |
| HTML/XML                    | `<!-- -->`            | `"`, `'`            |
| SQL                         | `--`, `/* */`         | `'`                 |
| Markdown                    | always-comment        | n/a                 |

A line with the leak after a comment marker → kind `comment`. A leak between matched quotes on the same line → kind `string`. Anything else on the `+` line → kind `identifier` (function/variable/class name, route name, log key, etc.).

## Step 4 — Group and Report

Group findings by **source first** (`branch` → `staged` → `commits`), then by file/commit, then by line. **Every detection is a blocker** — there is no `warning` tier. A spec ID in committed or about-to-be-committed artifacts is always a leak; the only question is how to redact it.

Report format (always inline, even with many findings — this is interactive). Render diff hunks in fenced ` ```diff ` blocks so the terminal syntax-highlights `+` lines green and `-` lines red. Use Unicode glyphs and emoji for visual separation; keep the structure scannable.

### Visual conventions

| Element            | Style                                                                        |
|--------------------|------------------------------------------------------------------------------|
| Section header     | `═══` rule above source, emoji-prefixed (`🌿 Branch`, `📥 Staged`, `📜 Commits`) |
| Finding ID         | `[L1]` (branch), `[S1]` (staged), `[C1]` (commits) — bold, monospace          |
| Severity tag       | 🔴 always (every finding is a blocker)                                       |
| Detector tag       | `` `D1` `` in monospace, dot-separated from kind                              |
| Diff block         | ` ```diff ` fence with `-` (current/leaking) and `+` (proposed) lines        |
| Leak highlight     | Inline `**FR-7**` bold around the offending substring inside the raw text    |
| File/commit anchor | `📄 path/to/file.ts:42` or `🔖 abc1234 subject`                              |
| Rewrite arrow      | `→` between old and new for single-token renames                              |

### Template

````markdown
╔══════════════════════════════════════════════════════════════╗
║  Spec Leak Audit — <branch> vs <base>                        ║
╚══════════════════════════════════════════════════════════════╝

**Sources scanned:** 🌿 branch ✓ · 📥 staged ✓ · 📜 commits ✓  (`skipped` per flag)<br>
**Findings:** 🔴 <N> total — 🌿 <n> · 📥 <n> · 📜 <n><br>
**Files affected:** <N>  ·  **Commits affected:** <N><br>
**Detectors fired:** `D1`×<n> · `D2`×<n> · …

───────────────────────────────────────────────────────────────
## 🌿 Branch  (vs `<base>`)
───────────────────────────────────────────────────────────────

### 📄 `<relative/file/path>`

#### **[L1]** 🔴 `D1` · comment   —   📄 `<file>:<line>`

> raw: `// per **FR-7**, gate processing on parent activation`

```diff
  function processChild(record) {
-   // per FR-7, gate processing on parent activation
+   // Only process when the parent record is active (activation gate)
    if (!record.parent?.active) return;
```

**Why it leaks:** `FR-7` is a spec item ID; the comment depends on the spec file to be meaningful.

---

#### **[L2]** 🔴 `D1` · identifier   —   📄 `<file>:<line>`

> raw: `function apply**FR7**Gate(...)`

```diff
- function applyFR7Gate(record) {
+ function applyActivationGate(record) {
```

**Rename:** `applyFR7Gate` → `applyActivationGate`<br>
**Call sites to update:** `<N>` (listed below) — `<file>:<line>`, `<file>:<line>`, …

───────────────────────────────────────────────────────────────
## 📥 Staged
───────────────────────────────────────────────────────────────

(Same structure as Branch. Anchor reads `📄 <file>:<line> (staged)`. After applying rewrites the user re-stages with `git add <file>`.)

───────────────────────────────────────────────────────────────
## 📜 Commit Messages
───────────────────────────────────────────────────────────────

#### **[C1]** 🔴 `D1` · commit-subject   —   🔖 `abc1234`

```diff
- feat(foo): implement FR-7 gating
+ feat(foo): gate processing on parent activation
```

**How to apply:** latest commit → `git commit --amend`. Older → `git rebase -i <base>` and mark `reword`.

---

#### **[C2]** 🔴 `D7` · commit-trailer   —   🔖 `def5678` body line 5

```diff
  Co-authored-by: Alice <alice@example.com>
- Spec: specs/sample-feature/spec.md
```

**Proposed fix:** delete the trailer entirely. Spec paths must never appear in commit metadata.
````

### Rendering rules

- **Diff fences must use ` ```diff `** (lowercase) so terminals colorize. Never use generic ` ``` ` for the before/after block
- **Pair `-`/`+` lines tightly** — show the leaking line as `-` and the proposed line as `+`, with at most one line of unchanged context above and below (prefix with two spaces — diff syntax for context). Keep blocks under 8 lines total
- **Bold the leaking substring** with `**…**` inside the `raw:` line; do NOT bold inside the diff block (diff syntax doesn't render Markdown)
- **Use horizontal rules (`---`)** between findings within the same file/commit. Use the box-drawing `───` rule (63 chars) only as a major section break between sources
- **Identifier-only renames** still get a diff block — single-line `-`/`+` is fine. It reads better than prose
- **Deletions** (e.g., a comment to remove entirely) show only the `-` line in the diff block, no `+`. Add a one-line note: `**Proposed fix:** delete this line.`
- **Truncate long lines** at 100 cols with `…` on the right; never wrap inside a diff fence (breaks highlighting)

If no findings → print:

```
✓ No spec leaks detected.
   🌿 branch: clean   📥 staged: clean   📜 commits: clean
```

### Crafting the rewrite (the "functional approach")

For each finding, the proposed rewrite must:

1. **Describe behavior, not provenance.** "Process when parent active" beats "Implements FR-7"
2. **Use names already established in the surrounding code.** Look at neighboring symbols, prop names, table/column names, route names. If the spec calls something an "activation gate" but the codebase calls it `parentActiveOnly`, prefer the codebase term
3. **Preserve scope.** Renaming a function → update every call site in the diff (and warn about call sites outside the diff). Renaming a class → update imports too
4. **Keep comments only if they add non-obvious WHY.** A comment that just paraphrases the function name is noise — propose deletion instead of rewrite
5. **Never inline spec prose verbatim.** If the only honest rewrite would be to copy a paragraph from the spec, the right answer is usually "delete the reference; let the code speak"
6. **For string literals** (log messages, error messages, user-facing copy): replace the ID with a short noun phrase that conveys the same meaning to a reader who has never seen the spec

When the redaction is non-obvious (e.g., the ID-bearing comment carries information not encoded in the symbol), surface the ambiguity and ask the user via `AskUserQuestion` rather than guessing.

## Step 5 — Apply Rewrites

Skip this step if `--report-only`.

### 5.1 — Branch & staged findings

For findings in the `branch` and `staged` sources, edits go to files in the working tree (the same edit fixes both sources if a line appears in both).

**Per-finding mode (default).** For each finding, in source → file/line order, use `AskUserQuestion` with options:

- **Apply proposed rewrite** — run `Edit` with the proposal
- **Edit before applying** — ask the user for the replacement text, then apply
- **Skip** — leave the line untouched
- **Skip all remaining in this file** — exit the loop for this file
- **Abort** — stop the skill entirely

Track applied/skipped/aborted counts. After staged-source edits, remind the user to re-run `git add <file>` for the updated lines.

**Bulk mode (`--auto-apply`).** Print the full proposed-rewrite list as a single preview, then one `AskUserQuestion`: **Apply all / Cancel**. Apply via `Edit` in source → file/line order.

After edits, re-run Step 2a–2b + 3 silently and confirm both diffs are clean. If any finding remains (e.g., a rename missed a call site), report it as **leftover** and ask whether to re-enter per-finding mode.

### 5.2 — Commit-message findings

**The skill never amends or rebases on the user's behalf.** Commit history rewrites are destructive and must be driven by the user.

For each commit with findings, present:

1. Original message (current text)
2. Proposed message (with all detected leaks redacted, applying the same functional-rewrite rules as code: describe behavior, not provenance)
3. Exact command(s) for the user to apply it themselves, picked from:

   - **Latest commit only:** `git commit --amend` and replace the message with the proposed one
   - **Older commit (or multiple):** `git rebase -i <base>` with `reword` markers on the affected SHAs
   - **Trailer-only fix:** `git commit --amend` (latest) or `git filter-branch --msg-filter` / `git rebase -i` with `reword`

Use `AskUserQuestion` with options per commit:

- **Copy proposed message to clipboard** (via `pbcopy` on macOS) and print the command
- **Print proposed message + command, I'll handle it**
- **Skip this commit**
- **Skip all commit findings**

**Never** run `git commit --amend`, `git rebase`, `git filter-branch`, or `git filter-repo` from the skill. Do not stage or unstage anything tied to a history rewrite.

After the user signals they've reworded, offer to re-run Step 2c + 3 to verify history is clean.

## Step 5b — Targeted Spec Deep-Scan (Only When Step 3 Found Nothing)

**Run this step only if Step 3 produced zero findings.** The shape-based detectors are intentionally lossy and may miss IDs that diverge from the canonical patterns (custom prefixes, lowercased forms, embedded numerics, paraphrased references). This step is a second-pass safety net that compares the diff against the **actual ID inventory of one specific spec** picked to match the change.

Skip this step entirely if `--report-only` is set with `--no-deep-scan`, or if no `specs/` directory exists in the repo (or at the user-configured spec root).

### 5b.1 + 5b.2 Delegate spec selection and inventory extraction to a subagent

**Do not read spec files in the main session.** Spec files are typically 500–2,000 lines each and multiple may exist — reading them inline would crowd out the diff, the source files being audited, and the rewrite proposals that come next. Delegate the whole "pick a spec and inventory its IDs" sub-task to a subagent so the spec content stays in the agent's context, not the skill's.

**Use `subagent_type: "general-purpose"`, not `Explore`.** Explore reads excerpts and may miss IDs past its read window. The inventory step requires full reads of every targeted spec file, so general-purpose is the safer pick. The agent is still cheap because its return payload is constrained to a small JSON object.

**Handling split specs (spec bundles).** A single logical spec is often split across multiple files in a shared directory — e.g.:

```
specs/sample-feature/
  README.md                        # index, cross-references
  SPEC-ALPHA.md                    # FR-1..FR-N, NFR-1..NFR-M
  SPEC-BETA.md                     # FR-A series
  SPEC-GAMMA.md                    # FR-B series
  SPEC-DELTA.md                    # FR-C series
```

These files share an ID namespace and cross-reference each other; treating any one of them as "the spec" in isolation would miss leaks from its siblings. **Detect bundles** by this heuristic: if the candidate's parent directory under `specs/` contains **two or more `*.md` files** (excluding `.audits/`), the candidate is part of a bundle, and the bundle is the unit of selection and inventory.

Bundle handling:

- **Selection:** score at the bundle level. A bundle's score = the **max** score across its member files (so a single strongly-matching member promotes the whole bundle). Report the bundle directory as the winner, not an individual file
- **Inventory:** the agent reads **every** `*.md` file in the bundle (full reads, not excerpts) and merges the inventories into one payload. Deduplicate across files. The `selected` field returns the bundle directory path; an extra `members` field lists the files actually read
- **`README.md` in a bundle** counts as part of the bundle (it usually carries cross-cutting IDs and references) — read it like the others. **Outside a bundle**, a bare `specs/README.md` is unlikely to be a spec and should be skipped unless it's the only candidate

If the parent directory contains only one `*.md` file → not a bundle; treat as a single-file spec.

First, gather the cheap inputs the agent needs (in the main session — these are small):

```sh
git rev-parse --abbrev-ref HEAD                       # current branch
git log --format=%s "$BASE"..HEAD                     # commit subjects
git diff --name-only "$BASE"..HEAD                    # changed files
find specs -type f -name '*.md' -not -path '*/.audits/*'  # candidate specs
```

If the spec list is empty → skip Step 5b entirely.
If exactly one spec exists → still delegate to the agent, but tell it to skip scoring and go straight to inventory.

Then launch one `Agent` call with `subagent_type: "general-purpose"`. The prompt must be self-contained (the agent has no conversation history) and must instruct the agent to return **only a structured payload**, not narration. Template:

> **Task: pick one spec (or spec bundle) and inventory its identifiers — do not read source code, do not propose changes.**
>
> Inputs:
> - Current branch: `<branch>`
> - Commit subjects on this branch: `<list>`
> - Files changed on this branch: `<list>`
> - Candidate spec files: `<list of paths>`
>
> **Step A — Detect bundles, then pick one.** Group candidates by parent directory under `specs/`. If a parent directory contains ≥2 `*.md` files (excluding `.audits/`), treat the directory as a **bundle** — the unit of selection is the directory, and the bundle's score is the max score across its members. Otherwise the candidate file itself is the unit.
>
> Score each unit (file or bundle) against these signals. To score cheaply, you may read only the file's headings (H1–H3) and metadata block — do NOT full-read at this stage:
>
> | Signal              | Weight | How                                                                 |
> |---------------------|--------|---------------------------------------------------------------------|
> | Branch name match   | 3      | Tokenize branch on `/`, `-`, `_` (min length 3); count tokens appearing in unit path or member filenames |
> | Commit subject match| 2      | Tokenize subjects; count overlap with unit path, member filenames, H1 titles |
> | Diff path match     | 2      | For each changed file, score the unit if any member mentions the path in `Technical Design` / `Implementation Steps` (`grep -l`) |
> | Recency tiebreak    | 1      | Most recently modified member wins ties (`git log -1 --format=%ct` or `stat`) |
>
> Pick the highest-scoring unit. If top score is 0, return `{"selected": null, "candidates": [top 4 paths with scores]}` so the main session can ask the user.
>
> **Step B — Inventory the winner. Read every member file in full** (use `Read` without `offset`/`limit`; if a file exceeds the default 2000-line cap, page through it with explicit offsets until EOF — every line must be inspected). For a bundle, this means reading **all** `*.md` files in the directory, including `README.md`. Merge the per-file results and deduplicate. Harvest:
>
> - List-item IDs: any `**XXX-N**:` or `- **XXX-N**` (case-sensitive prefix, any digits)
> - Phase labels: every `### Phase N` heading including the trailing dash-separated name
> - Section anchors: every H2/H3/H4 heading, slugified
> - Sibling spec filenames: every `SPEC-*.md` reference inside any spec member, **including bundle-structure mentions** (e.g., a "Members" / "Files" section in `README.md` that lists the bundle's filenames). Do NOT filter out within-bundle references — leaking the bundle's internal structure into committed code is still a leak
> - Step labels: explicit IDs in Implementation Steps (`- **S1.2**`, `- 1.2`)
> - Spec-coined names: code-fenced identifiers defined in `Technical Design` / `Data Model Changes` / `Architecture` sections (enums, action classes, services the spec proposes). For each candidate name, run `grep -rl <name> --exclude-dir=specs --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor` and **drop the name if it already exists in the codebase** — those are pre-existing, not spec-coined
> - Glossary terms: bolded terms inside an explicit `Glossary` / `Terminology` section, if present
>
> Deduplicate, sort by length descending.
>
> **Return format (JSON only, no prose):**
>
> ```json
> {
>   "selected": "specs/sample-feature",
>   "kind": "bundle",
>   "members": ["README.md", "SPEC-ALPHA.md", "SPEC-BETA.md", "SPEC-GAMMA.md", "SPEC-DELTA.md"],
>   "score_breakdown": {"branch": 3, "commits": 2, "paths": 4, "recency": 0},
>   "alternatives": [{"path": "...", "kind": "file|bundle", "score": N}, ...],
>   "inventory": {
>     "ids": ["FR-7", "FR-A1", "FR-B3", "NFR-2", "..."],
>     "phases": ["Phase 1 — Foundations", "..."],
>     "section_anchors": ["state-machines", "..."],
>     "spec_coined_names": ["SampleProcessor", "SampleStatus", "..."],
>     "sibling_specs": ["SPEC-BETA.md", "..."],
>     "glossary_terms": ["..."]
>   },
>   "counts": {"ids": 78, "phases": 8, "anchors": 54, "names": 6, "siblings": 4, "glossary": 0},
>   "per_member_counts": {"SPEC-ALPHA.md": {"ids": 54, "...": "..."}, "SPEC-BETA.md": {"ids": 12, "...": "..."}}
> }
> ```
>
> For single-file selection, `kind` is `"file"`, `members` is a one-element list, and `per_member_counts` may be omitted.
>
> Do not include the spec's prose, requirements, or reasoning in the return. Only the JSON above. Be terse.

When the agent returns, the main session:

1. Parses the JSON payload (single object — small and bounded)
2. If `selected` is `null`, uses `AskUserQuestion` with the `alternatives` list (plus an "Abort deep-scan" option) to let the user pick. If the user picks one, re-launch the agent with `selected_override: <path>` and ask only for Step B (inventory).
3. Prints a one-line confirmation: `Deep-scan target: <path> (score: branch=2 commits=1 paths=3 recency=0; alternatives: …)` plus the inventory counts. Does **not** print the full inventory unless the user asks.

### 5b.3 Scan all enabled sources with the agent's inventory

The agent's return payload is the only spec content that enters the main session. For each item across `ids`, `phases`, `spec_coined_names`, `sibling_specs`, `glossary_terms`, `section_anchors`, scan **each enabled source** (`branch`, `staged`, `commits`):

- Write the inventory items to a temp file (one per line) to avoid argv-length issues:
  ```sh
  printf '%s\n' "${inventory_items[@]}" > /tmp/spec-inventory.$$

  # Branch diff
  git diff --unified=0 "$BASE"..HEAD -- ':!specs/' ':!reviews/' \
    | grep -E '^\+' | grep -v '^\+\+\+' \
    | grep -nFf /tmp/spec-inventory.$$

  # Staged
  git diff --cached --unified=0 -- ':!specs/' ':!reviews/' \
    | grep -E '^\+' | grep -v '^\+\+\+' \
    | grep -nFf /tmp/spec-inventory.$$

  # Commit messages
  git log --format='%H%n%s%n%b%n---' "$BASE"..HEAD \
    | grep -nFf /tmp/spec-inventory.$$
  ```
- Map matches back to `file:line` (for `branch`/`staged`) using the hunk headers captured in Step 2, or to `<sha> subject|body:<line>` (for `commits`) using the log records captured in Step 2c — do not re-run the diff/log once per item

Apply the same context filters as Step 3 — skip vendor/lock paths. For `glossary_terms` and `section_anchors`, only flag matches **inside comments, strings, or commit messages** (raw identifiers like `overview` are too generic). `spec_coined_names` from the agent are already filtered against pre-existing codebase symbols, so they're flagged unconditionally.

### 5b.4 Report and route

If the deep-scan finds zero leaks → print:

```
✓ Deep-scan against <SPEC-NAME.md> found no additional leaks.
  Branch is clean against both shape-based detectors and the spec's actual ID inventory.
```

If it finds leaks → present them in the same report format as Step 4 (tagged `[D1]`, `[D2]`, ... to distinguish from Step 3 `[L*]` findings), then route into Step 5 (rewrite proposals + apply loop). When the deep-scan loop completes, do **not** re-run 5b — one pass is enough.

## Step 6 — Final Summary

```markdown
## Spec Leak Audit — Summary

**Base:** <base>  ·  **Branch:** <branch>
**Sources:** branch ✓ · staged ✓ · commits ✓
**Code findings:** applied <N> · skipped <N> · leftover <N>
**Commit-message findings:** <N> total · <N> need user reword (latest: `--amend`; older: `rebase -i`)

Next steps:
- Review the changes with `git diff` (and `git diff --cached` for staged fixes)
- Re-stage any modified files (`git add <path>`) before committing
- Reword any flagged commits yourself — the skill does not amend or rebase
- Re-run tests for renamed symbols
- Re-run this skill after rewording or staging more changes
```

Do **not** commit. Do **not** push. Do **not** amend or rebase.

## Notes

- The skill is intentionally lossy: it favors false positives over false negatives. A warning the user dismisses is cheap; an `FR-7` reaching `main` is expensive
- For monorepos, pass `--include=apps/foo/**` to scope the scan (applies to branch/staged sources only)
- Spec file content is **not** read by this skill in Step 3 — IDs are detected by shape. Only Step 5b's targeted deep-scan loads inventory, and it does so via a subagent so the spec content never enters the main session
- Pre-commit usage: `--staged-only --auto-apply` makes a good pre-commit hook — scans only what's about to be committed and applies safe rewrites without prompting per finding
- Pre-push usage: full default run (all three sources) before pushing catches leaks in earlier commits that escaped per-commit gating
