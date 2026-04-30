---
name: update-spec
description: Update an existing spec file — bump status, refresh date, amend requirements, record decisions, or absorb changes discovered during implementation. Preserves structure; never rewrites without confirmation.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Grep, Glob, Bash(git *), Bash(ls *), Bash(find *), Bash(grep *), AskUserQuestion, Skill
argument-hint: [spec name or path] [--status=<value>] [--note "<change>"]
---

# Update Spec

Update the spec identified by: $ARGUMENTS

## Critical Rules

- **NEVER** mention or reference the spec file outside the local boundary (committed Markdown, commit messages, issues, MRs, comments, chat). Hard rule
- **NEVER** commit the spec file
- Preserve the existing structure and section ordering. Only add/modify what the user asked for
- Always show the proposed diff before saving — wait for explicit approval

## Step 1 — Resolve the Spec

Same resolution strategy as `/audit-spec` and `/implement-spec`:

1. Existing path → use it
2. Otherwise search `specs/`, `docs/specs/`, `docs/`, repo root
3. Match by filename, then H1 title
4. Multiple candidates → AskUserQuestion
5. None → ask the user

Read the full file before proposing edits.

## Step 2 — Parse Flags & Intent

From `$ARGUMENTS`:

| Flag                | Effect                                                                |
|---------------------|-----------------------------------------------------------------------|
| `--status=<value>`  | Set `Status:` in the metadata block. Valid: `Draft`, `In Review`, `Approved`, `In Progress`, `Done`, `Blocked` |
| `--note "<change>"` | Append a dated entry to a `## Changelog` section (create if absent) |

If neither flag is given, ask the user what they want to change. Common intents:
- Mark the spec `Done` after implementation
- Add an FR/NFR discovered during build
- Record a design decision that overrode the original plan
- Move an Open Question to Resolved
- Refresh stale claims after codebase changes
- Append a phase to a Refactor's Rollback Plan

## Step 3 — Apply Updates

For every change:

- **Status / Date:** edit the metadata block. Always bump `Date:` to today when status changes
- **Adding a requirement:** allocate the next free FR/NFR ID; do not renumber existing ones
- **Resolving Open Questions:** move the bullet to a new `### Resolved` subsection under `## Open Questions` with the resolution noted
- **Recording a decision:** add to a `## Decisions` section if Refactor/Integration; otherwise append to `## Changelog`
- **Changelog entry format:**

  ```markdown
  ## Changelog

  - **YYYY-MM-DD** — <short description>
  ```

Keep existing wording. Do not "improve" prose unless the user asked.

## Step 4 — Show Diff & Confirm

Show the proposed edit as a diff (old → new). Wait for explicit approval before writing.

## Step 5 — Save

Apply the edits via `Edit`. Confirm the save and print the new metadata block.

## Step 6 — Suggest Next

- If status moved to `Done` → offer to invoke `/audit-spec --report-only` to confirm nothing's stale
- If FRs were added mid-implementation → offer to invoke `/implement-spec` to address the delta
- If Open Questions remain → list them inline and ask whether to resolve now

## Notes

- This skill never authors a spec from scratch — that's `/spec`'s job
- It never audits — that's `/audit-spec`'s job
- It never implements — that's `/implement-spec`'s job
- If the requested update would fundamentally restructure the spec (changing type, splitting into multiple files), suggest `/spec` for a fresh document instead
