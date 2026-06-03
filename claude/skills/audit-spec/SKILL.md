---
name: audit-spec
description: Load a spec feature folder and audit it for quality — parent/slice structure, two-tier consistency, codebase grounding, naming hygiene, and safety. Fixes trivial issues; reports the rest.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Bash(ls *), Bash(find *), Bash(grep *), Task, AskUserQuestion
argument-hint: [feature name, folder, or slice path] [--no-grounding] [--fix-only] [--report-only]
---

# Spec Auditor

Load and audit the spec identified by: $ARGUMENTS

## Spec Layout

A spec is a **feature folder**:

```
specs/<feature-slug>/
├── 00-overview.md      # parent — business spec (Context, Proposal, Goals G#, Business Rules BR#, Slices map)
├── 01-<slug>.md        # slice — typed technical spec, opens with ## Serves
└── ...
```

The parent is always **business** (no mechanism); each slice is a **typed technical** spec that back-references the parent via `## Serves`. The audit checks both tiers and the links between them.

## Critical Rules

- **NEVER** implement code from the spec — this skill only audits
- **NEVER** commit the spec, the audit report, or anything else
- **NEVER** add `specs/` to `.gitignore` — use `.git/info/exclude`
- **NEVER** mention, reference, link, attach, or quote the spec or audit file (or internal IDs like `G1`/`BR1`) in any artifact that leaves the local machine. The spec is local-only; this is a hard rule
- Trivial fixes are applied directly to the spec files; everything else is reported

## Flags

Parse from `$ARGUMENTS` (order-independent, strip before resolving the name):

| Flag              | Effect                                                                 |
|-------------------|------------------------------------------------------------------------|
| `--no-grounding`  | Skip the codebase-grounding group. Faster, lower signal                |
| `--fix-only`      | Apply auto-fixes; suppress the findings report (still print fix list)  |
| `--report-only`   | Run all checks, report findings, do NOT modify any spec file           |

`--fix-only` and `--report-only` are mutually exclusive — if both passed, prefer `--report-only` and warn the user.

## Step 1 — Resolve the Feature

1. If `$ARGUMENTS` is a path to a folder under `specs/` → that feature; audit the parent + all slices
2. If it is a path to a slice file → audit that slice + its parent (for Serves validation); note the scope is one slice
3. Otherwise slugify and search `specs/<slug>/`, `docs/specs/<slug>/`, `docs/<slug>/` by folder slug then parent H1 title
4. Multiple candidates → AskUserQuestion to pick one
5. No candidates → ask the user; do NOT guess

Read the parent and every in-scope slice in full before continuing. If the folder has no `00-overview.md`, that is a **blocker** (Step 3, group C).

**Legacy flat spec:** a standalone single-file spec (no folder) is audited as a parent-only document — skip the slice-specific and two-tier groups and add a **nit** recommending migration to the folder model.

## Step 2 — Detect Types

- Parent → always **Business**.
- Each slice → detect via heuristics:

| Type               | Heuristic                                                                  |
|--------------------|----------------------------------------------------------------------------|
| **Feature**        | Has `Technical Design`, `Implementation Steps`, `QA Criteria`              |
| **Bug/Fix**        | Has `Reproduction Steps`, `Root Cause Analysis`, `Proposed Fix`            |
| **Refactor**       | Has `Motivation`, `Current State`, `Proposed Architecture`, `Rollback`    |
| **Integration**    | Has `Service Overview`, `API Contract`, `Authentication`                   |
| **Infrastructure** | Has `Current Setup`, `Pipeline Changes`, `Rollback Plan`                   |

If ambiguous, pick the closest match and note it as a finding.

## Step 3 — Run Quality Checks

Run all groups. Each finding has a severity: **blocker**, **warning**, **nit**. Tag each finding with the file it belongs to (`00-overview.md`, `01-<slug>.md`, …).

### A. Parent Structure (`00-overview.md`)

- Required sections present: `Context`, `Proposal`, `Goals & Success Criteria`, `Business Rules & Invariants`, `Slices` (missing → **warning**)
- **Metadata block mandatory** — immediately under H1, contains `Date`/`Status`/`Author`, `<br>` between bold lines. Absent/incomplete → **warning**; wrong `<br>` → **nit** (auto-fix)
- Goals carry stable IDs (`G1`, `G2`…) and Business Rules carry stable IDs (`BR1`, `BR2`…); duplicates or gaps → **warning**
- **Parent stays business-level** — flag mechanism leaking into the parent: code identifiers, file paths, library/framework names, API signatures, SQL, algorithm names anywhere outside the `Technical Constraints` table → **warning** (the parent is the plain-language tier)
- `Technical Constraints` rows, if present, name a business-visible concern + a slice reference, not an implementation detail → **nit** if a row describes mechanism

### B. Slice Structure (`NN-<slug>.md`)

- Each slice opens with a `## Serves` block → absent → **warning**
- Required sections for the detected slice type are present (missing → **warning**):
  - Feature → `Technical Design`, `Implementation Steps`, `QA Criteria`
  - Bug → `Reproduction Steps`, `Root Cause Analysis`, `Proposed Fix` (absent → **blocker**)
  - Refactor → `Proposed Architecture`, `Rollback Plan`
  - Integration → `API Contract`, `Authentication`, `Fallback & Resilience`, `Error Handling`
  - Infrastructure → `Proposed Changes`, `Rollback Plan`, `Monitoring & Validation`
- Metadata block present (same rule as parent)
- Heading hierarchy well-formed: no skipped levels, no H3 directly under H1 (**nit**)
- A slice that owns a flagged constraint has a `Guardrail Enforcement` section describing the mechanism (**warning** if the constraint is referenced in `Serves` but never enforced)

### C. Two-Tier Consistency

- **Parent exists** — no `00-overview.md` in the folder → **blocker**
- **Serves references resolve** — every `G#`/`BR#`/constraint named in a slice's `Serves` exists in the parent → dangling reference → **blocker**
- **Every slice serves something** — a slice whose `Serves` cites no parent goal or rule → **warning** (why does this slice exist?)
- **Goal coverage** — a parent `Goal` not served by any written slice and not deferred in the map → **nit** (may be a not-yet-written slice; **warning** if all slices are written and the goal is still orphaned)
- **Map ↔ files match:**
  - A `## Slices` map entry whose file does not exist → fine if marked "(not yet written)", else → **warning**
  - A slice file on disk that is absent from the map → **warning**
  - Map ordering/numbering matches the `NN-` file prefixes → **nit** if out of sync
- **Constraint routing** — a `Technical Constraints` row in the parent points at a slice; that slice's `Serves` lists the constraint and a `Guardrail Enforcement` section covers it → **warning** if the chain is broken

### D. Naming & Layout Hygiene

- Folder name and every file name are **pure slugs** (lowercase, hyphen-separated). Any SCREAMING_CASE, leading underscore, or `spec-` prefix → **warning** (renaming changes meaning — report with the corrected name, do NOT auto-rename)
- Parent is exactly `00-overview.md` → **warning** if the business spec uses any other name
- Slices use zero-padded numeric prefix + slug (`01-intake.md`) → **nit** if unpadded or non-sequential

### E. Content Quality (per file)

- **Ambiguity scan** — flag `TBD`, `TODO`, `???`, `<placeholder>`, `XXX`, `FIXME`, `maybe`, `should probably`, `etc.`, `and so on` (**warning** for TBD/TODO/FIXME, **nit** for the rest)
- **Untestable acceptance criteria** — `QA Criteria` items without measurable verbs ("verify", "returns", "equals", "renders", …) → **warning**
- **Risks** — any risk row with empty `Mitigation` → **warning**
- **Empty sections** — a template section left with no content → **nit** (scaling depth down is fine; an empty `Open Questions` is not a finding)

### F. Codebase Grounding (ON by default, slices only)

The parent is business-level and not grounded. For every code reference in a **slice**:

- **File paths** (`src/foo/bar.ts`, `app/Models/User.php`) — verify with `Glob`/`ls`. Missing → **warning**
- **Symbols** — class/function/route names in prose. `Grep` for definitions. Missing → **warning**
- **Env vars / config keys** — search `.env*`, `config/`, `*.yml`. Missing → **nit** (could be new)
- **External services** in Integration slices — confirm referenced in repo (config, deps) → **nit** if not
- **Issue/MR references** (`#123`, `!456`, `GH-789`) — resolve via `gh`/`glab`. Unresolvable → **warning**
- **"Currently X does Y" claims** — spot-check at least the top 3 by reading the referenced code. Mismatch → **blocker**

If `--no-grounding` is set, skip this group. **Grounding is the highest-signal check in the audit.** When skipped, print a banner at the top of the report and list it as a **warning**:

```
⚠️  GROUNDING SKIPPED — slice claims are NOT verified against the codebase.
    Re-run without --no-grounding before considering the spec audited.
```

### G. Cross-references & Links

- Markdown links `[text](url)` — internal paths must exist; fragment links (`#section`) must point to a real heading in the same file (**warning**)
- Sibling links between parent and slices resolve (**warning**)
- Mermaid blocks — basic syntax check (matching opener, balanced brackets) (**warning**)

### H. Consistency

- **Terminology drift** — synonyms used interchangeably for one concept ("user" vs "account" vs "customer"). Top offenders → **nit**
- **Tense/voice mixing** — present vs future for proposed behavior (**nit**)
- **Naming** — camelCase vs snake_case for the same identifier across sections → **warning**

### I. Markdown Hygiene (mostly auto-fix)

- **Table cell padding** per global rule — auto-fix
- **`<br>` between bold metadata lines** — auto-fix
- **Trailing whitespace, mixed tab/space indentation in lists** — auto-fix
- **Inconsistent list markers** (`-` vs `*`) within one list — auto-fix to `-`
- **Code fences without language** — **nit**, do not auto-fix

### J. Hygiene & Safety

- Feature folder excluded via `.git/info/exclude` (NOT `.gitignore`). If `specs/` is in `.gitignore` → **blocker**. If not in `.git/info/exclude` → **warning**, offer to add it
- **External leak scan.** No spec file, the folder, its path, or internal IDs may be referenced outside `specs/`. Search the repo (excluding `specs/`, `.git/`, audit reports) for: any slice/parent basename, the literal `specs/`, and the feature-slug. Matches in:
  - committed Markdown (`*.md` outside `specs/`)
  - any tracked source file (code comments)
  - `git log` commit messages on the current branch (including unpushed commits)
  → **blocker** with exact file:line. If `gh`/`glab` are available and the branch has an open MR/PR, scan its title/description/comments too → **blocker** if found
- **Secrets scan** — `AKIA[0-9A-Z]{16}`, `ghp_[A-Za-z0-9]{36}`, `glpat-[A-Za-z0-9_-]{20}`, `Bearer [A-Za-z0-9._-]{20,}`, `-----BEGIN .* PRIVATE KEY-----`, `password\s*=\s*["'][^"']{4,}` → **blocker**
- **Internal hostnames / IPs** — `*.internal`, `*.corp`, `10.*`, `192.168.*` → **warning**

### K. Sanity (per file)

- **Stale dates** — `Date:` older than 90 days with `Status: In Progress` → **nit**
- **Status** present and one of `Draft`, `In Review`, `Approved`, `In Progress`, `Done`, `Blocked` → **warning** if missing/invalid
- **Author** present → **warning** if missing
- **Date** present and ISO (`YYYY-MM-DD`) → **warning** if missing/malformed

### L. File Length & Splitting

Specs are read by coding agents alongside source files; oversized files crowd out the context the agent needs. The folder model already splits by slice — so length findings push work onto **more/thinner slices**, not bigger files.

**Per-file thresholds** (lines of Markdown, excluding fenced code/diagrams):

| Bucket           | Lines                     | Verdict                                                        |
|------------------|---------------------------|---------------------------------------------------------------|
| Optimal          | ≤ 300                     | No action                                                     |
| Healthy          | 301–500                   | No action                                                     |
| Soft warn        | 501–800                   | **warning** — recommend splitting the slice                  |
| Hard warn        | > 800                     | **blocker** — strongly recommend splitting the slice         |
| Section overflow | any single H2 > 150 lines | **warning** — extract or split                               |

- **Parent over ~200 lines** → **warning**: the business spec should stay thin; push detail down into slices.

**Split signals** (any one → propose, even under threshold):

- **A slice mixes types** — e.g. a feature slice that also contains a full infra migration → it is really two slices
- **A slice spans multiple independent goals** with disjoint design and QA → split per goal
- **A slice is not vertically thin** — it reads as a horizontal layer ("the whole API") rather than an end-to-end increment → re-slice vertically

**Proposing a split** — do NOT auto-split. Propose in the report and confirm via AskUserQuestion. If approved, the user runs `/spec` (next-slice) to scaffold the new slice(s); this skill never authors specs.

```markdown
### Suggested re-slice

`02-checkout.md` (842 lines) mixes a feature flow + a Stripe migration.

Proposed:
- `02-checkout.md` — Feature: checkout flow (serves G2, BR3)
- `03-stripe-migration.md` — Infrastructure: Stripe migration (serves G2)

Rationale: two types in one slice; checkout section alone is 410 lines.
```

## Step 4 — Apply Trivial Fixes

Apply auto-fixes from groups I (and `<br>` fixes from A/B) directly to the relevant file using `Edit`. Track every fix; list them under "Auto-fixed". Do NOT auto-fix anything that changes meaning, ordering, semantics, or file names — only formatting.

## Step 5 — Report

**Threshold:** if total findings (excluding auto-fixed nits) ≤ 15 → inline summary. Otherwise → write `specs/<feature-slug>/.audit.md` and show only top-line counts inline.

### Inline summary format

```markdown
## Spec Audit — <feature-slug>

**Parent:** Business · <Status><br>
**Slices:** <N> (<types>)<br>
**Findings:** <N blockers> · <N warnings> · <N nits><br>
**Auto-fixed:** <N items>

### Blockers
- [B1] `<file>` · <section> — <description>

### Warnings
- [W1] `<file>` · <section> — <description>

### Nits
- [N1] `<file>` · <section> — <description>

### Auto-fixed
- `<file>`:<line> — <what changed>

### Suggested next steps
- ...
```

### Audit file format (when threshold exceeded)

Same structure, written to `specs/<feature-slug>/.audit.md`. Ensure `specs/` is in `.git/info/exclude` (Step 6).

## Step 6 — Exclusion Hygiene

After writing any audit file, ensure `specs/` is in `.git/info/exclude`:

1. `grep -qx 'specs/' .git/info/exclude` — if missing, append it
2. Never touch `.gitignore`

## Notes

- Read-mostly: only formatting fixes to spec files, plus an optional audit report
- Two-tier consistency (group C) and grounding (group F) are the highest-signal checks — a slice that serves no goal, or a dangling `Serves` ref, defeats the whole point of the model
- The parent is never grounded against code — it is intentionally jargon-free; flag the reverse (mechanism leaking up into the parent)
- In a monorepo, scope `Grep`/`Glob` to the relevant package when obvious; otherwise search the whole repo
