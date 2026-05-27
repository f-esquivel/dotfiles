---
name: audit-spec-leaks
description: Audit the current branch diff against a base branch (default `develop`) for raw spec list item IDs that leaked into committed code — comments, docblocks, variable/function/class names, log messages, strings. Reports findings and proposes per-finding functional rewrites that preserve intent without exposing the spec ID. Spec files themselves are local-only; their IDs must never reach committed code.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Grep, Glob, Bash(git *), Bash(grep *), Bash(rg *), Bash(awk *), Bash(sed *), Bash(sort *), Bash(uniq *), Bash(wc *), Bash(cat *), Bash(find *), AskUserQuestion, Agent
argument-hint: [base-branch] [--report-only] [--auto-apply] [--include=PATTERN] [--exclude=PATTERN]
---

# Spec Leak Auditor

Audit the diff between the current branch and a base branch for **raw spec list item IDs** (and other spec-internal references) that leaked into committed code. Spec files live only on the local machine — any reference to them in committed artifacts (`FR-7`, `NFR-2`, `SPEC-ALPHA.md`, `specs/sample-feature/spec.md`) is a leak and must be redacted.

Arguments: $ARGUMENTS

## Critical Rules

- **Audit only added/modified lines** of the diff (the `+` side). Removed lines (`-`) are out of scope
- **NEVER** commit changes, push, or amend on the user's behalf
- **NEVER** rewrite code semantics — proposed redactions must be behavior-preserving (rename + comment cleanup only)
- **NEVER** read the spec file's content into the diff or paste spec prose into committed code as a "fix" — the goal is to **remove** the dependency on the spec, not to inline it
- The skill must work with no spec file present — IDs are detected by shape, not by cross-referencing `specs/`

## Step 1 — Parse Arguments

Order-independent. Parse from `$ARGUMENTS`:

| Token              | Meaning                                                                     |
|--------------------|-----------------------------------------------------------------------------|
| First bare word    | Base branch (default: `develop` if it exists, else `main`, else `master`)   |
| `--report-only`    | List findings; do not propose rewrites or edit anything                     |
| `--auto-apply`     | Apply every proposed rewrite without per-finding confirmation (single bulk approval at the end) |
| `--include=GLOB`   | Restrict scan to paths matching GLOB (repeatable)                           |
| `--exclude=GLOB`   | Skip paths matching GLOB (repeatable); always implicitly excludes `specs/`, `reviews/`, `.git/` |

Defaults: per-finding confirmation (`--auto-apply` off), full diff scope.

If the base branch does not exist locally:

```sh
git rev-parse --verify --quiet "<base>" || git rev-parse --verify --quiet "origin/<base>"
```

Fall back to `origin/<base>` if present; otherwise abort and ask the user.

## Step 2 — Collect the Diff

Use a merge-base diff so only **this branch's** additions are scanned:

```sh
BASE=$(git merge-base HEAD "<base>")
git diff --unified=0 --no-color "$BASE"..HEAD -- ':!specs/' ':!reviews/'
```

Apply any `--include`/`--exclude` pathspecs after the implicit `specs/`/`reviews/` exclusion.

From the diff, extract only lines starting with `+` (excluding `+++` headers) and record `file:line` for each — `line` is the new-file line number derived from the hunk header.

If the diff is empty → report "no changes against `<base>`" and exit.

## Step 3 — Detect Leaks

Run all detectors against the `+` lines collected in Step 2. Each match becomes a **finding** with: file, line, column, raw text, detector that fired, surrounding code context (3 lines), kind (`identifier` / `comment` / `string` / `docblock` / `log` / `path`).

### Detectors

| ID    | Pattern (PCRE)                                              | Catches                                                                 |
|-------|-------------------------------------------------------------|-------------------------------------------------------------------------|
| D1    | `\b(FR|NFR|AC|AR|TE|REQ|TASK|STEP|US|UC)-[A-Z]?\d+\b`       | Canonical spec item IDs: `FR-7`, `NFR-2`, `AC-3`, `FR-X12`              |
| D2    | `\bSPEC-[A-Z0-9_]+(?:\.md)?\b`                              | Spec file references: `SPEC-ALPHA`, `SPEC-ALPHA.md`                     |
| D3    | `(?<![/\w])specs?/[\w./-]+\.md\b`                            | Spec paths: `specs/sample-feature/spec.md`                              |
| D4    | `\bPhase \d+\b` *inside comments/strings/docblocks only*    | Spec phasing language: `// Phase 2 — sample-step`                       |
| D5    | `\b[A-Z]{2,5}-\d{1,4}\b` *inside comments/strings only*     | Generic spec-shaped IDs not caught by D1 (lower confidence — **warning** not **blocker**) |
| D6    | `(?i)\b(see|per|implements?|fulfills?|tracked by)\s+(FR|NFR|AC|SPEC)[- ]` | Prose references: `// per FR-7`, `// see SPEC-ALPHA`                  |

**Filtering rules:**

- D1/D2/D3/D6 → always flagged regardless of code context (identifier, comment, string, anywhere)
- D4/D5 → flag only when the match is inside a comment, string literal, or docblock. In identifiers they are too noisy (false positives like `HTTP-2`, `UTF-8`)
- Skip matches inside file paths that look like third-party / vendor / lock files (`vendor/`, `node_modules/`, `*.lock`, `*.min.*`, `dist/`, `build/`)
- Skip matches inside Markdown files under `docs/` only if the surrounding section header is "Glossary" or "References" — otherwise flag (docs commits leak too)

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

Group findings by file, sort by line. **Every detection is a blocker** — there is no `warning` tier. A spec ID in committed code is always a leak; the only question is how to redact it.

Report format (always inline, even with many findings — this is interactive):

````markdown
## Spec Leak Audit — <branch> vs <base>

**Findings:** <N leaks><br>
**Files affected:** <N><br>
**Detectors fired:** D1×<n>, D2×<n>, ...

### <relative/file/path>:<line>

- **[L1] D1 · comment** — raw text: `// per FR-7, gate processing on parent activation`
  ```<lang>
  <3 lines of context, leak line marked with →>
  ```
  **Why it leaks:** `FR-7` is a spec item ID; the comment depends on the spec file to be meaningful
  **Proposed rewrite (functional):**
  ```<lang>
  // Only process when the parent record is active (activation gate)
  ```

- **[L2] D1 · identifier** — raw text: `function applyFR7Gate(...)`
  **Proposed rewrite:** `applyActivationGate`
  Call sites to update: `<N>` (listed below)
````

If no findings → print `✓ No spec leaks detected against <base>.` and stop.

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

### Per-finding mode (default)

For each finding, in file/line order, use `AskUserQuestion` with options:

- **Apply proposed rewrite** — run `Edit` with the proposal
- **Edit before applying** — ask the user for the replacement text, then apply
- **Skip** — leave the line untouched
- **Skip all remaining in this file** — exit the loop for this file
- **Abort** — stop the skill entirely

Track applied/skipped/aborted counts.

### Bulk mode (`--auto-apply`)

Print the full proposed-rewrite list as a single preview, then one `AskUserQuestion`: **Apply all / Cancel**. Apply via `Edit` in file/line order.

After edits, re-run Step 2–3 silently and confirm the diff is clean. If any finding remains (e.g., a rename missed a call site), report it as **leftover** and ask whether to re-enter per-finding mode.

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

### 5b.3 Scan the diff with the agent's inventory

The agent's return payload is the only spec content that enters the main session. For each item across `ids`, `phases`, `spec_coined_names`, `sibling_specs`, `glossary_terms`, `section_anchors`:

- Write the inventory items to a temp file (one per line) to avoid argv-length issues:
  ```sh
  printf '%s\n' "${inventory_items[@]}" > /tmp/spec-inventory.$$
  git diff --unified=0 "$BASE"..HEAD -- ':!specs/' ':!reviews/' \
    | grep -E '^\+' | grep -v '^\+\+\+' \
    | grep -nFf /tmp/spec-inventory.$$
  ```
- Map matches back to `file:line` using the hunk headers captured in Step 2 (do not re-run the diff once per item)

Apply the same context filters as Step 3 — skip vendor/lock paths. For `glossary_terms` and `section_anchors`, only flag matches **inside comments or strings** (raw identifiers like `overview` are too generic). `spec_coined_names` from the agent are already filtered against pre-existing codebase symbols, so they're flagged unconditionally.

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
**Applied:** <N>  ·  **Skipped:** <N>  ·  **Leftover:** <N>

Next steps:
- Review the changes with `git diff`
- Re-run tests for renamed symbols
- Re-run this skill after staging more changes
```

Do **not** commit. Do **not** push.

## Notes

- The skill is intentionally lossy: it favors false positives over false negatives. A warning the user dismisses is cheap; an `FR-7` reaching `main` is expensive
- For monorepos, pass `--include=apps/foo/**` to scope the scan
- Spec file content is **not** read by this skill — IDs are detected by shape. This keeps the skill usable on machines where the spec is not checked out, and prevents accidentally widening the leak by quoting the spec into the rewrite
