# Global Claude Code Instructions

* When building plans, commit messages and interactions with the user sacrifice grammar for the sake of concision (DO
  NOT APPLY THIS WHEN GENERATING CODE OR TECHNICAL SOLUTIONS)
* List any unresolved questions at the end, if any
* Ask more questions until you have enough context to give an accurate & confident answer
* Promote the usage of AskUserQuestionTool to clarify any input/petition from the user
* When receiving input/context in Spanish don't turn your output, ALWAYS STAY IN ENGLISH, at least the user indicates another output

## Markdown Formatting

### Line Breaks

Use `<br>` to force line breaks between consecutive bold metadata lines — standard Markdown collapses them into a single line.

```markdown
**Date:** 2026-02-15<br>
**Status:** In Progress<br>
**Author:** Frank
```

### Diagrams

Use Mermaid (```` ```mermaid ````) instead of ASCII art when the diagram involves branching, complex relationships, or would require manual alignment. ASCII art is fine for simple linear flows or small illustrations.

**Use Mermaid for:** flowcharts, sequence diagrams, entity relationships, state machines, git graphs<br>
**Use ASCII for:** simple directory trees, single linear flows, small inline illustrations

### Tables

Pad table cells with spaces so column borders align vertically in raw Markdown. The raw source should be readable without rendering.

Good:
```markdown
| Script                       | Purpose                 |
|------------------------------|-------------------------|
| `install.sh`                 | Bootstrap entire system |
| `scripts/update.sh`          | Update all components   |
```

Bad:
```markdown
| Script | Purpose |
|---|---|
| `install.sh` | Bootstrap entire system |
| `scripts/update.sh` | Update all components |
```

## MCP Tools

### Context7

Always use Context7 MCP when needing library/API documentation, code generation, setup or configuration steps — no explicit request required.

* **Prefer Context7 over WebSearch/WebFetch** for library and API docs — returns structured, version-aware content without scraping
* **Skip `resolve-library-id`** when you already know the Context7 library ID (e.g. `/vercel/next.js`, `/mongodb/docs`) — call `query-docs` directly
* **Version-aware queries** — include specific version numbers in the query so Context7 returns matching documentation
* **Trigger keyword** — append `use context7` to any prompt as a lightweight way to activate doc retrieval
* **Scope** — use Context7 for library/framework docs; use WebSearch for general info, blog posts, or non-library topics

## Git Platform Detection

Detect platform via: `git remote get-url origin`

### GitLab repos (remote contains `gitlab`) → use `glab`
- MRs: `glab mr list`, `glab mr view <id>`, `glab mr create`
- Issues: `glab issue list`, `glab issue view <id>`, `glab issue create`
- CI: `glab ci status`, `glab ci view`
- Repo: `glab repo view`

### GitHub repos (remote contains `github`) → use `gh`
- PRs: `gh pr list`, `gh pr view <id>`, `gh pr create`
- Issues: `gh issue list`, `gh issue view <id>`, `gh issue create`
- Actions: `gh run list`, `gh run view`
- Repo: `gh repo view`

## Spec Files

Spec files (`specs/` directory) are **internal-use only** — they exist to improve DX and **must never leave the local machine**. This is a hard rule, no exceptions.

* **NEVER** commit spec files or add them to `.gitignore` (use `.git/info/exclude` instead)
* **NEVER** mention, reference, link, attach, paste, or quote spec files in any artifact that leaves the local machine. This includes — but is not limited to:
  - Committed Markdown files (READMEs, design docs, ADRs, runbooks, in-repo `docs/`)
  - Git commit messages and tags
  - GitLab/GitHub issues, MRs, PRs (titles, descriptions, comments, review threads)
  - Code comments in committed source files
  - External chat, email, tickets, or shared documents
* The path, filename, or existence of a spec file must not appear anywhere outside `specs/` and the local conversation
* Spec **content** can inform issues, MRs, and committed docs — but the file itself, its path, and its name must not be referenced
* When creating a `specs/` directory in a project for the first time, automatically add `specs/` to `.git/info/exclude`

## Review Files

Review files (`reviews/` directory) are **internal-use only** — they exist to track review history and **must never leave the local machine**. This is a hard rule, no exceptions.

* **NEVER** commit review files or add them to `.gitignore` (use `.git/info/exclude` instead)
* **NEVER** mention, reference, link, attach, paste, or quote review files in any artifact that leaves the local machine — committed Markdown, commit messages, issues, MRs, PRs, code comments, chat, email, or external docs
* The path, filename, or existence of a review file must not appear anywhere outside `reviews/` and the local conversation
* Review **content** can inform inline MR/PR comments — but the file itself, its path, and its name must not be referenced
* When creating a `reviews/` directory in a project for the first time, automatically add `reviews/` to `.git/info/exclude`

## Git Rules

* `git push` is **blocked** globally — never attempt to push. The user will push manually when ready

## Workflow Rules

* When asked for a spec, plan, or design document — produce ONLY the document. Do NOT implement code or enter plan mode unless explicitly told to proceed
* Before proposing new patterns, configs, or test utilities — explore existing project conventions first (check .env files, base classes, established patterns)
* When unsure about commit scope or conventions — ask before committing
* Follow SRP for both code and commits — split by concern, don't merge unrelated changes

## GitLab/GitHub Workflow

* Before creating MRs/PRs via CLI — always show a draft preview of title, description, and labels for approval first
* Before executing any destructive or state-changing CLI command (close issue, merge MR, apply labels) — show the exact command and explain what it does
