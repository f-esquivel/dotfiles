---
name: audit-spec
description: Load a spec file into a fresh session and audit it for quality — structure, content, codebase grounding, consistency, and hygiene. Fixes trivial issues; reports the rest.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Bash(ls *), Bash(find *), Task, AskUserQuestion
argument-hint: [spec name or path] [--no-grounding] [--fix-only] [--report-only]
---

# Spec Auditor

Load and audit the spec identified by: $ARGUMENTS

## Critical Rules

- **NEVER** implement code from the spec — this skill only audits
- **NEVER** commit the spec, the audit report, or anything else
- **NEVER** add `specs/` to `.gitignore` — use `.git/info/exclude`
- Trivial fixes are applied directly to the spec file; everything else is reported

## Flags

Parse from `$ARGUMENTS` (order-independent, strip before resolving the spec name):

| Flag              | Effect                                                                 |
|-------------------|------------------------------------------------------------------------|
| `--no-grounding`  | Skip group C (codebase grounding). Faster, lower signal               |
| `--fix-only`      | Apply auto-fixes; suppress the findings report (still print fix list) |
| `--report-only`   | Run all checks, report findings, do NOT modify the spec file          |

`--fix-only` and `--report-only` are mutually exclusive — if both passed, prefer `--report-only` and warn the user.

## Step 1 — Resolve the Spec File

The argument is a loose match. Resolve it:

1. If `$ARGUMENTS` is an existing file path → use it
2. Otherwise search common locations in this order:
   - `specs/`
   - `docs/specs/`
   - `docs/`
   - Repo root for any `*.md` matching the name
3. Match strategy:
   - Exact filename (case-insensitive)
   - Substring of filename
   - Substring of the spec's H1 title
4. If multiple candidates → use AskUserQuestion to pick one
5. If no candidates → ask the user for the path; do NOT guess

Read the full file before continuing. If it is not a spec (no recognizable structure), abort and report.

## Step 2 — Detect Spec Type

Match against the templates from the `/spec` skill:

| Type               | Heuristic                                                                  |
|--------------------|----------------------------------------------------------------------------|
| **Feature**        | Has `User Stories`, `Functional Requirements`, `Implementation Steps`      |
| **Bug/Fix**        | Has `Reproduction Steps`, `Root Cause Analysis`, `Proposed Fix`            |
| **Refactor**       | Has `Motivation`, `Current State`, `Proposed Architecture`, `Migration`    |
| **Integration**    | Has `Service Overview`, `API Contract`, `Authentication`                   |
| **Infrastructure** | Has `Current Setup`, `Pipeline Changes`, `Rollback Plan`                   |

If ambiguous, pick the closest match and note it as a finding.

## Step 3 — Run Quality Checks

Run all check groups. Each finding has a severity: **blocker**, **warning**, **nit**.

### A. Structural

- All required sections for the detected type are present (missing → **warning**)
- Unknown top-level sections (extra → **nit**, surface in case it's drift)
- Heading hierarchy is well-formed: no skipped levels, no H3 directly under H1 (**nit**)
- Metadata block present and uses `<br>` between bold lines per global Markdown rules (**nit**, auto-fix)
- FR/NFR/AC items have unique stable IDs (e.g., `FR-1`, `AC-3`) — duplicates or gaps → **warning**

### B. Content Quality

- **Ambiguity scan** — flag occurrences of: `TBD`, `TODO`, `???`, `<placeholder>`, `XXX`, `FIXME`, `maybe`, `should probably`, `etc.`, `and so on` (**warning** for TBD/TODO/FIXME, **nit** for the rest)
- **Untestable acceptance criteria** — items in `QA Criteria` / `Acceptance Criteria` without measurable verbs (no "verify", "returns", "equals", "renders", etc.) → **warning**
- **Orphan requirements** — FRs/NFRs not referenced anywhere in `Technical Design` / `Implementation Steps` / `QA Criteria` → **warning**
- **Orphan design** — items in `Technical Design` not traceable to a requirement → **nit** (possible scope creep)
- **Missing critical sections by type:**
  - Feature/Refactor → must have **Out of Scope** / **Non-goals** (**warning** if absent)
  - Refactor/Infrastructure → must have **Rollback Plan** and **Migration Strategy** (**blocker** if absent)
  - Integration → must have **Fallback & Resilience** and **Error Handling** (**warning** if absent)
  - Bug → must have **Reproduction Steps** and **Root Cause Analysis** (**blocker** if absent)
- **Risks section** — any risk row with empty `Mitigation` → **warning**

### C. Codebase Grounding (ON by default)

For every code reference in the spec:

- **File paths** mentioned (`src/foo/bar.ts`, `app/Models/User.php`) — verify with `Glob` / `ls`. Missing → **warning**
- **Symbols** — class names, function names, route names referenced in prose. `Grep` for definitions. Missing → **warning**
- **Env vars / config keys** mentioned — search `.env*`, `config/`, `*.yml`. Missing → **nit** (could be new)
- **External services** mentioned in Integration specs — confirm referenced in repo (config, deps) → **nit** if not
- **Issue/MR references** (`#123`, `!456`, `GH-789`) — resolve via `gh issue view` / `glab issue view` / `glab mr view`. Unresolvable → **warning**
- **"Currently X does Y" claims** — spot-check at least the top 3 by reading the referenced code. Mismatch → **blocker**

If `--no-grounding` appears in `$ARGUMENTS`, skip group C and note it in the report.

### D. Cross-references & Links

- All Markdown links `[text](url)` — internal paths must exist; fragment links (`#section`) must point to a real heading in the same file (**warning**)
- Mermaid blocks — basic syntax check (matching `graph`/`sequenceDiagram`/etc. opener, balanced brackets) (**warning**)
- Sibling spec links resolve (**warning**)

### E. Consistency

- **Terminology drift** — detect synonyms used interchangeably for the same concept (e.g., "user" vs "account" vs "customer", "endpoint" vs "route"). Report top offenders → **nit**
- **Tense/voice mixing** — present vs future for proposed behavior (**nit**)
- **Naming** — camelCase vs snake_case for the same identifier across sections → **warning**

### F. Markdown Hygiene (mostly auto-fix)

- **Table cell padding** per global rule — auto-fix
- **`<br>` between bold metadata lines** — auto-fix
- **Trailing whitespace, mixed tab/space indentation in lists** — auto-fix
- **Inconsistent list markers** (`-` vs `*` mixed) within the same list — auto-fix to `-`
- **Code fences without language** — **nit**, do not auto-fix

### G. Hygiene & Safety

- Spec file is excluded via `.git/info/exclude` (NOT `.gitignore`). If `specs/` is in `.gitignore` → **blocker**. If not in `.git/info/exclude` → **warning**, offer to add it
- **Secrets scan** — match against patterns: `AKIA[0-9A-Z]{16}`, `ghp_[A-Za-z0-9]{36}`, `glpat-[A-Za-z0-9_-]{20}`, `Bearer [A-Za-z0-9._-]{20,}`, `-----BEGIN .* PRIVATE KEY-----`, `password\s*=\s*["'][^"']{4,}` → **blocker**
- **Internal hostnames / IPs** — `*.internal`, `*.corp`, `10.*`, `192.168.*` → **warning**

### H. Sanity

- **Stale dates** — `Date:` metadata older than 90 days with `Status: In Progress` → **nit**
- **Status field** present and one of: `Draft`, `In Review`, `Approved`, `In Progress`, `Done`, `Blocked` → **nit** if missing

### I. LLM / Agent Ergonomics — File Length & Splitting

Specs are read by coding agents alongside source files; oversized specs crowd out the surrounding context the agent needs to reason. Optimize for one spec = one concern that fits comfortably in a single read with budget left over.

**Length thresholds** (lines of Markdown, excluding fenced code/diagrams which are cheap to skim):

| Bucket            | Lines      | H2 sections | Verdict                                                              |
|-------------------|------------|-------------|----------------------------------------------------------------------|
| Optimal           | ≤ 300      | ≤ 5         | No action                                                            |
| Healthy           | 301–500    | 6–7         | No action                                                            |
| Soft warn         | 501–800    | 8–10        | **warning** — recommend split, propose plan                          |
| Hard warn         | > 800      | > 10        | **blocker** — strongly recommend split, propose plan                 |
| Section overflow  | any single H2 > 150 lines | —          | **warning** — extract that section into its own spec or appendix     |

Rationale: a 300-line spec is ~4–5k tokens; a coding agent reading the spec plus 3–4 relevant source files stays well within a healthy working budget. Past ~800 lines the spec alone consumes the context an agent needs for the actual code.

**Splitting signals** (any one → propose split, even under the line threshold):

- **Multiple spec types in one file** — e.g. a feature spec that also contains a full infrastructure migration plan. Each type has its own template; mixing them dilutes both
- **Multiple independent FR clusters** — FR groups that share no requirements, no design surface, and no QA criteria → split per cluster
- **Phased migration with self-contained phases** — each phase has its own goals, risks, rollback → one spec per phase, plus a thin index spec
- **Multiple integrations bundled** — one external service per spec
- **Disjoint audiences** — sections aimed at different readers (eng vs. ops vs. product) → split by audience
- **High edit churn in one section** — if `git log -p <spec>` shows >70% of recent changes touching one H2, that section is its own concern

**Proposing a split**

When length or signals trigger a split, do NOT auto-split. Propose a plan in the report:

```markdown
### Suggested split

Current: `specs/payments-overhaul.md` (1,142 lines, 13 H2)

Proposed:
- `specs/payments-overhaul.md` — index + shared context (~150 lines)
- `specs/payments-overhaul-checkout.md` — Feature: checkout flow (FR-1..FR-8)
- `specs/payments-overhaul-refunds.md` — Feature: refunds (FR-9..FR-14)
- `specs/payments-overhaul-stripe-migration.md` — Infrastructure: Stripe migration

Rationale: three independent FR clusters, mixed feature + infra concerns,
checkout section alone is 320 lines.
```

Use AskUserQuestion to confirm the split plan before doing anything. If approved, the user runs `/spec` for each new file (this skill does not author specs).

## Step 4 — Apply Trivial Fixes

Apply auto-fixes from groups A and F directly to the spec file using `Edit`. Track every fix and list them in the report under "Auto-fixed".

Do NOT auto-fix anything that changes meaning, ordering, or content semantics — only formatting.

## Step 5 — Report

**Threshold:** if total findings (excluding auto-fixed nits) ≤ 15 → inline summary. Otherwise → write `specs/<spec-basename>.audit.md` and show only the top-line counts inline.

### Inline summary format

```markdown
## Spec Audit — <spec filename>

**Type:** <detected type><br>
**Findings:** <N blockers> · <N warnings> · <N nits><br>
**Auto-fixed:** <N items>

### Blockers
- [B1] <section> — <description>

### Warnings
- [W1] <section> — <description>

### Nits
- [N1] <section> — <description>

### Auto-fixed
- <file>:<line> — <what changed>

### Suggested next steps
- ...
```

### Audit file format (when threshold exceeded)

Same structure as inline, written to `specs/<spec-basename>.audit.md`. Ensure `specs/` is in `.git/info/exclude` (per Step 6).

## Step 6 — Exclusion Hygiene

After writing any audit file, ensure `specs/` is in `.git/info/exclude`:

1. `grep -qx 'specs/' .git/info/exclude` — if missing, append it
2. Never touch `.gitignore`

## Notes

- This skill is read-mostly: it only writes formatting fixes to the spec, plus an optional audit report
- Codebase grounding is the highest-signal check — never skip it unless `--no-grounding` is passed
- When the spec lives in a monorepo, scope `Grep`/`Glob` to the relevant package if obvious from context; otherwise search the whole repo
