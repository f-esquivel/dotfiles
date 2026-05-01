---
name: load-spec
description: Load a spec file into the conversation context. Resolves a loose name to a path, reads the full file, and reports detected type and metadata — no audit, no edits, no implementation.
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(ls *), Bash(find *), AskUserQuestion
argument-hint: [spec name or path]
---

# Spec Loader

Load the spec identified by: $ARGUMENTS

## Critical Rules

- **NEVER** implement code from the spec — this skill only loads it into context
- **NEVER** edit, audit, or commit the spec
- **NEVER** mention, reference, link, attach, or quote the spec in any artifact that leaves the local machine — committed Markdown, commit messages, issues, MRs, PRs, code comments, chat, email. The spec is local-only; this is a hard rule
- After loading, wait for the user's next instruction. Do NOT propose changes, audits, or implementation steps unprompted

## Step 1 — Resolve the Spec File

The argument is a loose match. Resolve it:

1. If `$ARGUMENTS` is empty → ask the user for a spec name or path via AskUserQuestion
2. If `$ARGUMENTS` is an existing file path → use it
3. Otherwise search common locations in this order:
   - `specs/`
   - `docs/specs/`
   - `docs/`
   - Repo root for any `*.md` matching the name
4. Match strategy:
   - Exact filename (case-insensitive)
   - Substring of filename
   - Substring of the spec's H1 title
5. If multiple candidates → use AskUserQuestion to pick one
6. If no candidates → ask the user for the path; do NOT guess

## Step 2 — Read the File

Read the full file with `Read`. If it is not a spec (no recognizable structure, no H1, no metadata block), report that fact but still surface the contents so the user can decide.

## Step 3 — Detect Spec Type

Match against the templates from the `/spec` skill:

| Type               | Heuristic                                                                  |
|--------------------|----------------------------------------------------------------------------|
| **Feature**        | Has `User Stories`, `Functional Requirements`, `Implementation Steps`      |
| **Bug/Fix**        | Has `Reproduction Steps`, `Root Cause Analysis`, `Proposed Fix`            |
| **Refactor**       | Has `Motivation`, `Current State`, `Proposed Architecture`, `Migration`    |
| **Integration**    | Has `Service Overview`, `API Contract`, `Authentication`                   |
| **Infrastructure** | Has `Current Setup`, `Pipeline Changes`, `Rollback Plan`                   |

If ambiguous, pick the closest match and note it in the summary.

## Step 4 — Summarize

Print a short summary so the user can confirm the right spec is loaded:

```markdown
## Spec Loaded — <filename>

**Path:** `<resolved path>`<br>
**Type:** <detected type><br>
**Status:** <Status from metadata, or "—"><br>
**Date:** <Date from metadata, or "—"><br>
**Author:** <Author from metadata, or "—"><br>
**Length:** <N lines>, <M H2 sections>

### Sections
- <H2 #1>
- <H2 #2>
- ...
```

Keep the summary tight. Do not repeat the spec body — it is already in context via the `Read` call.

## Step 5 — Stop

Stop here. Wait for the user's next instruction. Do not audit, edit, plan, or implement.
