---
name: implement-spec
description: Implement a spec file end-to-end, driving from its Implementation Steps and QA Criteria. Loads the spec, plans the work as tasks, executes them, and refuses to drift outside the spec's scope.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git *), Bash(glab *), Bash(gh *), Bash(ls *), Bash(find *), Bash(grep *), Agent, AskUserQuestion, Skill, TaskCreate, TaskUpdate, TaskList
argument-hint: [spec name or path]
---

# Implement Spec

Implement the spec identified by: $ARGUMENTS

## Critical Rules

- **NEVER** mention, reference, link, or quote the spec file in any artifact that leaves the local machine — committed code, commit messages, issues, MRs, PRs, code comments, or chat. The spec is local-only; this is a hard rule
- **NEVER** commit the spec file
- **NEVER** push (`git push` is globally blocked); the user pushes manually
- Stay inside the spec's stated scope. If something outside scope is needed, **stop and ask** — do not silently expand the work
- If a requirement, design decision, or QA criterion is ambiguous, **ask** via AskUserQuestion before guessing

## Step 1 — Resolve & Load the Spec

Use the same resolution strategy as `/audit-spec`:

1. If `$ARGUMENTS` is an existing file path → use it
2. Otherwise search `specs/`, `docs/specs/`, `docs/`, repo root for `*.md` matching the name
3. Match by exact filename, substring of filename, then substring of H1 title
4. Multiple candidates → AskUserQuestion to pick one
5. No candidates → ask the user for the path; do not guess

Read the full file. Identify:
- Spec **type** (Feature / Bug / Refactor / Integration / Infrastructure)
- Spec **status** in the metadata block — if `Done` or `Blocked`, stop and confirm before proceeding
- Implementation Steps (or equivalent: Migration phases, Proposed Fix, Deployment Strategy)
- QA Criteria / Acceptance Criteria
- Out of Scope / Non-goals (treat these as hard fences)
- Open Questions — surface them to the user **before** starting; resolve or accept the risk

## Step 2 — Pre-flight Audit (recommended)

Before implementing, optionally invoke `/audit-spec --report-only <spec>` via the Skill tool. If the audit returns blockers, stop and ask the user whether to fix the spec first or proceed regardless. Skipping the audit is fine for trivial bugs; default to running it for Feature, Refactor, Integration, and Infrastructure specs.

## Step 3 — Plan as Tasks

Convert each Implementation Step into a task via TaskCreate. Include a final task per QA Criterion: each acceptance/QA item becomes its own verification task.

Order tasks to match the spec's order. Mark the first as `in_progress` only when starting work.

## Step 4 — Execute

For each task:
1. Mark it `in_progress`
2. Make the change (code, config, migration, test) following the project's conventions — read `CLAUDE.md`, existing patterns, and related modules first
3. Run the project's checks where they exist (typecheck, lint, tests) — do not invent commands; ask if unclear
4. Mark the task `completed` only when the change is in and verified

If a task reveals the spec is wrong (file path doesn't exist, design assumes a function that isn't there, requirement contradicts existing code), **stop**:
- Pause the task
- Report the conflict to the user with file:line and the specific mismatch
- Ask whether to amend the spec (use `/update-spec`) or adjust the implementation
- Do not silently rewrite the spec or guess

## Step 5 — Verify QA Criteria

Walk every QA / Acceptance Criterion explicitly. For each:
- State how it was verified (test name, manual check, log inspection)
- If it cannot be verified locally (UI golden path, prod-only behavior), say so plainly — do not claim success

If any criterion fails, do not mark the spec done. Report the failure and ask for direction.

## Step 6 — Wrap Up

1. Summarize what changed (file-level, no spec references)
2. Offer to invoke `/update-spec` to mark the spec `Status: Done` and record the resulting commits/MR
3. Offer to invoke `/commit` (or `/create-mr` if the branch is push-ready)
4. **Never** mention the spec file in commit messages, MR descriptions, or comments — the spec content informs the message; the spec path does not appear

## Notes

- For Bug specs: implementation = the Proposed Fix; QA = "Original bug no longer reproducible" + regression test
- For Refactor specs: walk the Rollback Plan phase by phase; treat each phase's rollback note as a real fallback path, not decoration
- For Integration specs: stub external calls in tests; verify auth, error handling, and fallback paths before declaring done
- For Infrastructure specs: prefer dry-run / preview commands first; surface every state-changing command for explicit user approval before running
