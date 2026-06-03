---
name: load-spec
description: Load a spec into the conversation context. Resolves a loose name to a feature folder, reads the parent business spec and the active (or requested) slice, and reports the slice map and metadata — no audit, no edits, no implementation.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(ls *), Bash(find *), AskUserQuestion
argument-hint: [feature name, folder, or slice path]
---

# Spec Loader

Load the spec identified by: $ARGUMENTS

## Spec Layout

A spec is a **feature folder**, not a single file:

```
specs/<feature-slug>/
├── 00-overview.md      # parent — business spec (the "why"/"what")
├── 01-<slug>.md        # slice — technical spec (the "how")
└── ...
```

The parent (`00-overview.md`) is always a **business** spec. Each slice is a **typed technical** spec.

## Critical Rules

- **NEVER** implement code from the spec — this skill only loads it into context
- **NEVER** edit, audit, or commit the spec
- **NEVER** mention, reference, link, attach, or quote the spec (any file, the folder, its path, or internal IDs like `G1`/`BR1`) in any artifact that leaves the local machine — committed Markdown, commit messages, issues, MRs, PRs, code comments, chat, email. The spec is local-only; this is a hard rule
- After loading, wait for the user's next instruction. Do NOT propose changes, audits, or implementation steps unprompted

## Step 1 — Resolve the Feature

The argument is a loose match. Resolve it:

1. If `$ARGUMENTS` is empty → ask the user for a feature name, folder, or slice path via AskUserQuestion
2. If it is a path to a **folder** under `specs/` → that feature; the target slice is unset (decide in Step 2)
3. If it is a path to a **file** → its parent directory is the feature; remember that file as the slice the user wants loaded (the parent `00-overview.md` always loads too)
4. Otherwise slugify the argument and search for a feature folder:
   - `specs/<slug>/`, `docs/specs/<slug>/`, `docs/<slug>/`
   - Folder-slug exact match, then substring
   - Substring of the parent's H1 title (`00-overview.md`)
5. Multiple candidate folders → use AskUserQuestion to pick one
6. No candidates → ask the user for the path; do NOT guess

**Legacy flat spec:** if the match is a standalone `*.md` spec with no feature folder (an older single-file spec), load that file as-is and skip the parent/slice handling — report it as a legacy flat spec.

## Step 2 — Read Parent + Slice

1. Read `00-overview.md` (the parent) in full.
2. Determine the slices: list the `NN-*.md` files in the folder and cross-check against the parent's `## Slices` map.
3. Choose which slice to load into context:
   - User named a specific slice file (Step 1.3) → load that one
   - Exactly one slice exists → load it
   - Multiple slices, none specified → load the parent only, present the slice map, and ask via AskUserQuestion which slice(s) to pull in (default: the first slice still unchecked in the map, else the highest-numbered)
4. Read the chosen slice(s) in full.

## Step 3 — Detect Types

- Parent → always **Business**.
- Each loaded slice → detect via the slice heuristics:

| Type               | Heuristic                                                                  |
|--------------------|----------------------------------------------------------------------------|
| **Feature**        | Has `Technical Design`, `Implementation Steps`, `QA Criteria`              |
| **Bug/Fix**        | Has `Reproduction Steps`, `Root Cause Analysis`, `Proposed Fix`            |
| **Refactor**       | Has `Motivation`, `Current State`, `Proposed Architecture`, `Rollback`    |
| **Integration**    | Has `Service Overview`, `API Contract`, `Authentication`                   |
| **Infrastructure** | Has `Current Setup`, `Pipeline Changes`, `Rollback Plan`                   |

If ambiguous, pick the closest match and note it.

## Step 4 — Summarize

Print a tight summary so the user can confirm the right spec is loaded:

```markdown
## Spec Loaded — <feature-slug>

**Parent:** `00-overview.md` · Business<br>
**Status:** <Status from parent metadata, or "—"><br>
**Date:** <Date from parent metadata, or "—"><br>
**Author:** <Author from parent metadata, or "—">

### Slices
- [x] 01 — <name> · <type> — **loaded**
- [ ] 02 — <name> · (not yet written / not loaded)

### Loaded into context
- `00-overview.md` (parent)
- `01-<slug>.md` (<type>)
```

Do not repeat the spec bodies — they are already in context via the `Read` calls. Mark which slices exist on disk vs. are only placeholders in the map.

## Step 5 — Stop

Stop here. Wait for the user's next instruction. Do not audit, edit, plan, or implement.
