---
name: implement-spec
description: Implement one slice of a spec end-to-end. Reads the parent business spec for context, drives from the chosen slice's Implementation Steps and QA Criteria, ticks the parent's slice map on completion, and refuses to drift outside the slice's scope.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Bash(ls *), Bash(find *), Bash(grep *), Agent, AskUserQuestion, Skill, TaskCreate, TaskUpdate, TaskList
argument-hint: [feature name, folder, or slice path]
---

# Implement Spec

Implement the spec slice identified by: $ARGUMENTS

## Spec Layout

A spec is a **feature folder**: a parent business spec (`00-overview.md`, the "why"/"what") plus one technical spec per vertical slice (`NN-<slug>.md`, the "how"). **This skill implements exactly one slice per run** — the parent is read-only context.

## Critical Rules

- **NEVER** mention, reference, link, or quote any spec file, the folder, its path, or internal IDs (`G1`, `BR1`, slice numbers) in any artifact that leaves the local machine — committed code, commit messages, issues, MRs, PRs, code comments, or chat. The spec is local-only; this is a hard rule
- **NEVER** commit the spec
- **NEVER** push (`git push` is globally blocked); the user pushes manually
- Stay inside the chosen slice's scope. If something outside the slice (or outside the parent's stated goals) is needed, **stop and ask** — do not silently expand the work or wander into another slice
- If a requirement, design decision, or QA criterion is ambiguous, **ask** via AskUserQuestion before guessing

## Step 1 — Resolve the Feature & Slice

Resolve the feature folder, same strategy as `/load-spec`:

1. Existing folder path → that feature; existing file path → that file's folder (and that file is the target slice)
2. Otherwise slugify and search `specs/<slug>/`, `docs/specs/<slug>/`, `docs/<slug>/` by folder slug then parent H1
3. Multiple candidates → AskUserQuestion; none → ask the user (do not guess)

Then pick the slice to implement:
- A specific slice was named → use it
- Otherwise read the parent's `## Slices` map and choose the **first unchecked slice that has a written `NN-<slug>.md` file**
- If the next slice in the map has no file yet → stop and tell the user to scaffold it with `/spec` first (this skill does not author specs)
- Multiple plausible slices → AskUserQuestion

**Legacy flat spec:** if resolution finds a standalone single-file spec (no folder), implement that file directly — there is no parent/slice split.

## Step 2 — Load Context

Read, in order:
1. **Parent `00-overview.md`** — for the business intent: Goals (`G#`), Business Rules (`BR#`), flagged Technical Constraints, Out of Scope. These are hard fences; the implementation must satisfy them and must not violate any `BR#`.
2. **The target slice** — identify:
   - Slice **type** (Feature / Bug / Refactor / Integration / Infrastructure)
   - **Serves** block — confirm the goals/rules/constraints this slice is accountable for
   - Slice **status** — if `Done` or `Blocked`, stop and confirm before proceeding
   - Implementation Steps (or equivalent: Proposed Fix, Rollback phases, Deployment Strategy)
   - Guardrail Enforcement — the mechanisms for any constraint the slice owns
   - QA Criteria / Acceptance Criteria
   - Open Questions — surface to the user **before** starting; resolve or accept the risk

## Step 3 — Pre-flight Audit (recommended)

Optionally invoke `/audit-spec --report-only <feature>` via the Skill tool. If it returns blockers (including parent↔slice inconsistencies, e.g. the slice serves no stated goal), stop and ask whether to fix the spec first or proceed. Skipping is fine for trivial bug slices; default to running it for Feature, Refactor, Integration, and Infrastructure slices.

## Step 4 — Plan as Tasks

Convert each Implementation Step into a task via TaskCreate. Add a final verification task per QA Criterion, plus one task per Guardrail Enforcement item ("enforce <constraint>"). Order to match the slice; mark the first `in_progress` only when starting.

## Step 5 — Execute

For each task:
1. Mark it `in_progress`
2. Make the change (code, config, migration, test) following project conventions — read `CLAUDE.md`, existing patterns, and related modules first
3. Run the project's checks where they exist (typecheck, lint, tests) — do not invent commands; ask if unclear
4. Mark `completed` only when the change is in and verified

If a task reveals the slice or parent is wrong (path doesn't exist, design assumes a missing function, a step contradicts a `BR#` or existing code), **stop**:
- Pause the task
- Report the conflict with file:line and the specific mismatch
- Ask whether to amend the spec (`/update-spec`) or adjust the implementation
- Do not silently rewrite the spec or guess

## Step 6 — Verify QA Criteria

Walk every QA / Acceptance Criterion explicitly. For each:
- State how it was verified (test name, manual check, log inspection)
- For each guardrail the slice owns, confirm enforcement actually holds
- If something cannot be verified locally (UI golden path, prod-only behavior), say so plainly — do not claim success

If any criterion fails, do not mark the slice done. Report the failure and ask for direction.

## Step 7 — Wrap Up

1. Summarize what changed (file-level, no spec references)
2. Offer to invoke `/update-spec` to:
   - mark the slice `Status: Done`
   - **tick this slice's entry in the parent's `## Slices` map**
3. Offer to invoke `/commit` (or `/create-mr` if the branch is push-ready)
4. If the parent's map still has unchecked slices, mention the next one and that `/spec` scaffolds it (next-slice run)
5. **Never** mention any spec file, path, or internal ID in commit messages, MR descriptions, or comments — spec content informs the message; the spec itself does not appear

## Notes

- One run = one slice. Resist implementing "just the next slice too" — small batches are the point
- For Bug slices: implementation = the Proposed Fix; QA = "Original bug no longer reproducible" + regression test
- For Refactor slices: walk the Rollback Plan phase by phase; each phase's rollback note is a real fallback, not decoration
- For Integration slices: stub external calls in tests; verify auth, error handling, and fallback before declaring done
- For Infrastructure slices: prefer dry-run / preview commands first; surface every state-changing command for explicit user approval before running
