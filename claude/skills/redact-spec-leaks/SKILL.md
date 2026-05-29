---
name: redact-spec-leaks
description: Light, zero-prompt companion to audit-spec-leaks. Scans ONLY the unstaged working-tree changes (`git diff`, no `--cached`) for raw spec/review-internal references — spec list item IDs, spec/review file paths, and prose references that leaked into comments, docblocks, identifiers, log messages, or strings — and redacts every finding in place with a behavior-preserving rewrite, no per-finding confirmation. Prints a summary diff of what changed. For ambiguous findings it consults the matching spec to inform the rewrite, and only asks the user when even the spec doesn't resolve the doubt. Spec and review files are local-only; their IDs and paths must never reach committed artifacts.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Grep, Glob, Bash(git *), Bash(grep *), Bash(rg *), Bash(awk *), Bash(sed *), Bash(sort *), Bash(uniq *), Bash(wc *), Bash(find *), Bash(printf *), AskUserQuestion, Agent
argument-hint: [--dry-run] [--include=PATTERN] [--exclude=PATTERN]
---

# Spec Leak Redactor (light)

A fast, hands-off sibling of `/audit-spec-leaks`. Where the full auditor scans three sources (branch diff, staged index, commit messages) and walks the user through each finding, this skill does **one job**: sweep the **unstaged working-tree changes** and silently redact any spec/review leak it finds.

| Aspect          | `/audit-spec-leaks`                              | `/redact-spec-leaks` (this skill)        |
|-----------------|--------------------------------------------------|------------------------------------------|
| Source          | branch diff + staged + commit messages           | **unstaged working tree only** (`git diff`) |
| Interaction     | per-finding confirmation (or bulk)               | **zero prompts** — redact, then summarize |
| Commit messages | reported (user rewords manually)                 | out of scope                             |
| Deep-scan       | always (subagent inventory)                      | only as the ambiguity fallback           |
| Use case        | pre-push / pre-MR full audit                      | quick local sweep while still editing    |

Use this when you're mid-edit and want leaks scrubbed out of your working tree before you stage anything. Run the full `/audit-spec-leaks` before pushing.

Arguments: $ARGUMENTS

## Critical Rules

- **Scope is `git diff` only** — working tree vs index. Never scan `--cached`, never scan committed history, never touch commit messages.
- **Audit only added/modified lines** (the `+` side of the diff). Removed lines (`-`) are out of scope.
- **NEVER** stage, commit, push, amend, or rebase. After redacting, the changes stay unstaged for the user to review and stage themselves.
- **NEVER** rewrite code semantics — every redaction must be behavior-preserving (rename + comment cleanup only).
- **NEVER** inline spec prose as a "fix" — the goal is to **remove** the dependency on the spec, not paste it into the code.
- The skill works with no spec file present — IDs are detected by shape. The spec is read only as the ambiguity fallback (Step 3b).
- Treat `reviews/` exactly like `specs/` — both are local-only and leak the same way.

## Step 1 — Parse Arguments

Order-independent. Parse from `$ARGUMENTS`:

| Token            | Meaning                                                                           |
|------------------|-----------------------------------------------------------------------------------|
| `--dry-run`      | Report findings only; do not edit anything (turns this into a read-only preview)  |
| `--include=GLOB` | Restrict scan to paths matching GLOB (repeatable)                                 |
| `--exclude=GLOB` | Skip paths matching GLOB (repeatable); always implicitly excludes `specs/`, `reviews/`, `.git/` |

Default: redact in place, full working-tree scope.

## Step 2 — Collect & Detect

### 2a — Collect the unstaged diff

```sh
git diff --unified=0 --no-color -- ':!specs/' ':!reviews/'
```

Apply any `--include`/`--exclude` pathspecs after the implicit `specs/`/`reviews/` exclusion. Extract only lines starting with `+` (excluding `+++` headers); record `<path>:<line>` for each (`line` is the new-file line number from the hunk header).

If the diff is empty → print `✓ No unstaged changes to scan.` and exit.

### 2b — Run detectors

Run every detector against the `+` lines. Each match becomes a finding with: location, raw text, detector ID, surrounding context (3 lines), and kind (`identifier` / `comment` / `string` / `docblock` / `log` / `path`).

| ID  | Pattern (PCRE)                                                          | Catches                                                         |
|-----|-------------------------------------------------------------------------|----------------------------------------------------------------|
| D1  | `\b(FR\|NFR\|AC\|AR\|TE\|REQ\|TASK\|STEP\|US\|UC)-[A-Z]?\d+\b`           | Canonical spec item IDs: `FR-7`, `NFR-2`, `AC-3`, `FR-X12`      |
| D2  | `\bSPEC-[A-Z0-9_]+(?:\.md)?\b`                                          | Spec file references: `SPEC-ALPHA`, `SPEC-ALPHA.md`            |
| D3  | `(?<![/\w])specs?/[\w./-]+\.md\b`                                        | Spec paths: `specs/sample-feature/spec.md`                     |
| D3b | `(?<![/\w])reviews/[\w./-]+\.md\b`                                       | Review paths: `reviews/gh-42.md`, `reviews/gl-7.md`            |
| D4  | `\bPhase \d+\b` *inside comments/strings/docblocks only*                | Spec phasing language: `// Phase 2 — sample-step`              |
| D5  | `\b[A-Z]{2,5}-\d{1,4}\b` *inside comments/strings only*                  | Generic spec-shaped IDs not caught by D1 (lower confidence)    |
| D6  | `(?i)\b(see\|per\|implements?\|fulfills?\|tracked by\|refs?\|closes?\|fixes?)\s+(FR\|NFR\|AC\|SPEC)[- ]` | Prose references: `// per FR-7`, `closes FR-3` |

**Filtering rules:**

- D1/D2/D3/D3b/D6 → always flagged.
- D4/D5 → flag only when the match is inside a comment, string literal, or docblock (raw identifiers are too noisy: `HTTP-2`, `UTF-8`).
- Skip matches inside vendor/lock/build paths (`vendor/`, `node_modules/`, `*.lock`, `*.min.*`, `dist/`, `build/`).
- Skip matches inside Markdown under `docs/` only if the surrounding section header is "Glossary" or "References" — otherwise flag.

Detect comment/string context by language with simple line-based heuristics (no AST):

| Language family              | Comment markers | String quotes     |
|------------------------------|-----------------|-------------------|
| C/C++/Java/JS/TS/PHP/Go/Rust | `//`, `/* */`   | `"`, `'`, `` ` `` |
| Python/Ruby/Shell/YAML       | `#`             | `"`, `'`          |
| HTML/XML                     | `<!-- -->`      | `"`, `'`          |
| SQL                          | `--`, `/* */`   | `'`               |
| Markdown                     | always-comment  | n/a               |

A leak after a comment marker → kind `comment`. A leak between matched quotes on the same line → kind `string`. Anything else → kind `identifier`.

**Every detection is a blocker.** There is no warning tier.

## Step 3 — Redact in Place (zero prompts)

Skip editing if `--dry-run` (jump to the summary, marking each finding as `would redact`).

For each finding, in file/line order, craft a behavior-preserving rewrite and apply it with `Edit`. **Do not ask per finding.**

### Crafting the rewrite (the "functional approach")

1. **Describe behavior, not provenance.** "Process when parent active" beats "Implements FR-7".
2. **Reuse names already in the surrounding code.** Look at neighboring symbols, props, columns, routes. Prefer the codebase's term over the spec's term.
3. **Preserve scope.** Renaming a symbol → update every call site **within the unstaged diff**. If a call site lives outside the working-tree changes, do NOT touch it (that would create new unstaged edits the user didn't ask for) — instead note it as leftover in the summary.
4. **Drop noise comments.** A comment that only paraphrases the symbol name → delete it instead of rewriting.
5. **String literals** (logs, errors, copy) → replace the ID with a short noun phrase meaningful to a reader who never saw the spec.
6. **Never inline spec prose.** If the only honest rewrite copies a spec paragraph, delete the reference and let the code speak.

### 3b — Ambiguity fallback (consult the spec, then ask only if still unclear)

A finding is **ambiguous** when the ID-bearing line carries intent not recoverable from the surrounding code (e.g. `// FR-12` on a bare branch with no descriptive neighbors). For these:

1. **If a spec is already loaded in this conversation**, use that knowledge to write the rewrite directly.
2. **Otherwise, read the matching spec to understand the intent** — then redact based on that understanding. Keep spec content out of the working tree; use it only to phrase a behavior-describing rewrite.
   - Locate candidates: `find specs -type f -name '*.md' -not -path '*/.audits/*'`.
   - Pick the spec whose path/filename/headings best match the changed files and current branch. If a parent dir under `specs/` holds ≥2 `*.md` files, treat the directory as a bundle and consider its members together.
   - **If the spec set is large (multiple files / >~400 lines), delegate the read to a `general-purpose` subagent** so spec prose never crowds the main session. Ask the agent only for: "given finding `<raw line>` at `<file:line>` referencing `<ID>`, what behavior does that ID describe, in one neutral phrase that does not quote spec prose?" Use the returned phrase to craft the rewrite.
3. **If even the spec doesn't resolve the doubt** (no matching spec, ID absent from it, or genuinely conflicting intent), do NOT guess. Leave the line untouched and use `AskUserQuestion` to ask the user how to redact it — offer: apply a proposed neutral rewrite, provide custom text, or skip.

## Step 4 — Verify & Summarize

After edits (skip if `--dry-run`), re-run Step 2 silently and confirm the unstaged diff is clean. Any finding still present (e.g. a rename whose call site was outside the diff) is reported as **leftover**.

Render the summary inline. Use ` ```diff ` fences so the terminal colorizes `-`/`+` lines.

```markdown
╔══════════════════════════════════════════════════════════════╗
║  Spec Leak Redactor — unstaged working tree                   ║
╚══════════════════════════════════════════════════════════════╝

**Findings:** 🔴 <N>  ·  **Redacted:** <N>  ·  **Asked user:** <N>  ·  **Leftover:** <N>
**Files touched:** <N>   ·   **Detectors fired:** `D1`×<n> · `D2`×<n> · …

### 📄 `<relative/file/path>`

#### 🔴 `D1` · comment — `<file>:<line>`

​```diff
-   // per FR-7, gate processing on parent activation
+   // Only process when the parent record is active (activation gate)
​```
```

Rendering rules: pair `-`/`+` tightly (≤1 context line each side, two-space prefix for context); keep blocks under 8 lines; show only the `-` line for deletions and add `**Proposed fix:** delete this line.`; truncate long lines at 100 cols with `…`.

If nothing was found:

```
✓ No spec leaks in the unstaged working tree.
```

Closing reminders:

```markdown
Next steps:
- Review the rewrites with `git diff`
- Stage when satisfied (`git add <path>`) — the skill left everything unstaged on purpose
- Run `/audit-spec-leaks` before pushing for the full branch + staged + commit-message sweep
```

Do **not** stage. Do **not** commit. Do **not** push.

## Notes

- Companion to `/audit-spec-leaks` — same detectors, opposite ergonomics. This one trades the careful prompts for speed and scopes itself to the one source the full auditor doesn't cover (unstaged working tree).
- Working-tree edits are fully `git`-reversible (`git checkout -- <file>` / `git restore <file>`), which is why zero-prompt redaction is safe here but not for commit history.
- Intentionally lossy: favors false positives over false negatives. A dismissed rewrite is cheap; an `FR-7` reaching a commit is not — and this skill is the last gate before you stage.
- Use `--dry-run` to preview redactions without editing when you want to eyeball them first.
