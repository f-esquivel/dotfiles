---
name: update-spec
description: Update an existing spec — bump status, refresh date, amend goals/rules, record decisions, tick the slice map, or absorb changes found during implementation. Routes each edit to the right tier (parent vs slice). Preserves structure; never rewrites without confirmation.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Edit, Grep, Glob, Bash(git *), Bash(ls *), Bash(find *), Bash(grep *), AskUserQuestion, Skill
argument-hint: [feature name, folder, or slice path] [--status=<value>] [--note "<change>"]
---

# Update Spec

Update the spec identified by: $ARGUMENTS

## Spec Layout

A spec is a **feature folder**: parent business spec (`00-overview.md`) + typed technical slices (`NN-<slug>.md`). The core job of this skill is routing each edit to the **right tier**:

| Edit                                                        | Tier              |
|-------------------------------------------------------------|-------------------|
| Add/change a Goal (`G#`) or Business Rule (`BR#`)           | Parent            |
| Change Proposal, Context, Out of Scope, Technical Constraints | Parent          |
| Tick/refresh the `## Slices` map                            | Parent            |
| Status/Date on the whole feature                            | Parent            |
| Status/Date on one slice                                    | That slice        |
| Technical design, validations, QA, guardrail mechanism      | That slice        |
| A slice's `Serves` back-reference                           | That slice        |
| A brand-new slice                                           | Not here → `/spec` |

## Critical Rules

- **NEVER** mention or reference any spec file, the folder, its path, or internal IDs (`G1`/`BR1`) outside the local boundary (committed Markdown, commit messages, issues, MRs, comments, chat). Hard rule
- **NEVER** commit the spec
- Preserve existing structure and section ordering. Only add/modify what the user asked for
- Always show the proposed diff before saving — wait for explicit approval

## Step 1 — Resolve the Feature

Same strategy as `/audit-spec` and `/implement-spec`:

1. Folder path → that feature; slice path → that slice (and its parent)
2. Otherwise slugify and search `specs/<slug>/`, `docs/specs/<slug>/`, `docs/<slug>/` by folder slug then parent H1
3. Multiple candidates → AskUserQuestion; none → ask the user

Read the parent and any relevant slice before proposing edits.

**Legacy flat spec:** a standalone single-file spec is edited in place — no tier routing.

## Step 2 — Parse Flags & Intent

From `$ARGUMENTS`:

| Flag                | Effect                                                                |
|---------------------|-----------------------------------------------------------------------|
| `--status=<value>`  | Set `Status:`. Valid: `Draft`, `In Review`, `Approved`, `In Progress`, `Done`, `Blocked`. Ask whether it targets the parent (whole feature) or a specific slice |
| `--note "<change>"` | Append a dated entry to a `## Changelog` section (create if absent) on the targeted file |

If neither flag is given, ask the user what they want to change. Common intents and where they land:

- Mark a **slice** `Done` after building it → slice status + **tick the parent's `## Slices` map**
- Mark the **whole feature** `Done` → parent status (only once every slice is checked)
- Add a Goal or Business Rule discovered during build → parent (`G#`/`BR#`)
- Record a technical decision that overrode the plan → the relevant slice
- Move an Open Question to Resolved → whichever file holds it
- Refresh a stale "Currently X does Y" claim → the slice that made it
- Refine the slice map (rename/re-order foreseen slices) → parent

## Step 3 — Determine the Target Tier

For each requested change, decide parent vs slice using the routing table above. If a change is genuinely cross-tier (e.g. a new Business Rule that also needs enforcement), split it: the rule goes to the parent, and the enforcement note goes to the owning slice — show both edits. If the user asks for something that is really a **new slice**, stop and point them to `/spec` (next-slice run); this skill never authors a slice.

## Step 4 — Apply Updates

For every change:

- **Status / Date** — edit the targeted file's metadata block. Always bump `Date:` to today when status changes
- **Adding a Goal / Business Rule** — allocate the next free `G#` / `BR#` on the parent; do not renumber existing ones
- **Ticking the slice map** — change `- [ ] NN — …` to `- [x] NN — …` in the parent's `## Slices`; keep the file reference intact
- **Adding a slice's technical detail** — edit that slice only; if it introduces a new `Serves` target, confirm the referenced `G#`/`BR#` exists in the parent (if not, add the parent rule first)
- **Resolving Open Questions** — move the bullet to a `### Resolved` subsection under `## Open Questions` on the same file, with the resolution noted
- **Recording a decision** — add to the slice's `## Decisions & Tradeoffs`; if it is a business-level decision, append to a parent `## Changelog`
- **Changelog entry format:**

  ```markdown
  ## Changelog

  - **YYYY-MM-DD** — <short description>
  ```

Keep existing wording. Do not "improve" prose unless asked.

## Step 5 — Show Diff & Confirm

Show every proposed edit as a diff (old → new), labelled by file (`00-overview.md` / `NN-<slug>.md`). Wait for explicit approval before writing.

## Step 6 — Save

Apply the edits via `Edit`. Confirm the save and print the new metadata block(s) and any changed map line.

## Step 7 — Suggest Next

- Slice moved to `Done` and the parent map still has unchecked slices → mention the next slice and that `/spec` scaffolds it
- Every slice now `Done` → offer to set the **parent** status to `Done`, then `/audit-spec --report-only` to confirm nothing's stale
- A Goal/Rule was added mid-build → offer `/implement-spec` to address the delta (or `/spec` if it needs a new slice)
- Open Questions remain → list them inline and ask whether to resolve now

## Notes

- This skill never authors a spec or a slice from scratch — that's `/spec`'s job
- It never audits — that's `/audit-spec`'s job
- It never implements — that's `/implement-spec`'s job
- If an update would fundamentally restructure the feature (changing a slice's type, splitting one slice into several), suggest `/spec` for the new slice(s) instead of force-fitting it here
