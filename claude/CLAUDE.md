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

Pick the format by **render target** first, then by **complexity**:

* **Markdown files only** — use Mermaid (```` ```mermaid ````) when the diagram involves branching, complex relationships, or would require manual alignment. Mermaid renders in Markdown viewers but is unreadable as raw text.
* **Console output** (anything shown in the terminal, never written to an `.md`) — always use ASCII. The terminal can't render Mermaid, so a Mermaid block there is just noise.
* **Simple and direct graphics** — use ASCII regardless of target. If the picture is a short linear flow, a small tree, or a handful of boxes, ASCII is clearer and cheaper than Mermaid even inside a Markdown file.

**Use Mermaid for:** flowcharts, sequence diagrams, entity relationships, state machines, git graphs — **and only in Markdown files**<br>
**Use ASCII for:** all console/terminal output, plus simple directory trees, single linear flows, and small inline illustrations anywhere

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
* **Never write the reference in the first place** — this is the priority. Do not put spec item IDs (`G3`, `BR2`, slice numbers), spec paths, or provenance prose (`per G3`, `enforces BR2`) into code, identifiers, comments, docblocks, log messages, strings, or commit messages. Describe the behavior, not the spec it came from. Scrubbing a leak after it is written is damage control, not the workflow

## Review Files

Review files (`reviews/` directory) are **internal-use only** — they exist to track review history and **must never leave the local machine**. This is a hard rule, no exceptions.

* **NEVER** commit review files or add them to `.gitignore` (use `.git/info/exclude` instead)
* **NEVER** mention, reference, link, attach, paste, or quote review files in any artifact that leaves the local machine — committed Markdown, commit messages, issues, MRs, PRs, code comments, chat, email, or external docs
* The path, filename, or existence of a review file must not appear anywhere outside `reviews/` and the local conversation
* Review **content** can inform inline MR/PR comments — but the file itself, its path, and its name must not be referenced
* When creating a `reviews/` directory in a project for the first time, automatically add `reviews/` to `.git/info/exclude`
* **Never write the reference in the first place** — same priority as specs: keep review paths (`reviews/gh-42.md`) and review-internal references out of code, comments, and commit messages from the start, rather than relying on scrubbing them out later

## Knowledge Graph (graphify)

The `/graphify` skill builds a queryable knowledge graph from any folder of files. Its outputs are **generated, internal-only artifacts** — same hygiene class as specs and reviews.

* **NEVER** commit `graphify-out/` (graph.json, HTML, `GRAPH_REPORT.md`, intermediate `.graphify_*` files) or any Obsidian vault graphify writes — and never add them to `.gitignore` (use `.git/info/exclude` instead)
* When `graphify-out/` is first created in a project, automatically add `graphify-out/` to `.git/info/exclude`
* **Prefer the existing graph** — when the user asks a natural-language question about the codebase AND `graphify-out/graph.json` exists, answer via `graphify query "<question>"` rather than manual grep/exploration. Reserve fresh extraction for explicit rebuilds (`--update`, `--cluster-only`, a bare path/URL)

## Custom Agents

Prefer dispatching the matching subagent over hand-rolling the operation — the agents route through guarded resolvers (Keychain-backed secrets, audit logging, safety deny-lists) that ad-hoc commands bypass.

* **DB work** — Postgres/MySQL audits, queries, schema introspection, executions against a locally-reachable database → dispatch `db-agent`. Never hand-roll `psql`/`mysql` for this; the `db-guard` hook blocks raw clients aimed at non-loopback hosts regardless. Targets are aliases in the global registry (`db-agent list`); writes roll back unless the user explicitly asks to persist.
* **OIDC tokens** — minting an M2M token or impersonating a user (password grant) for manual API testing, calling an API as that identity, or exploring a tenant's Keycloak realm → dispatch `oidc-token`. Never print tokens into context; the `oidc-guard` hook blocks the raw-token printer. `oidc-curl` reaches loopback by default, the tenant's own issuer with `--inspect`, and hosts pre-registered for that tenant with `--remote`. Authorizing a host (`oidc-token tenant add-host`) is **yours alone** — it needs a real terminal and the guard blocks agents from it, so an agent can never widen where a live token may be sent.

## Secret Hygiene

Never read secret material into context — not via Read, Grep, Bash, or any interpreter (python/node/etc.). This is enforced by the `secret-guard` hook + `permissions.deny` rules, but the rule holds even on paths the guard can't see: do not work around it.

* **Do NOT read** `.env` (and `.env.<env>`), `*.secrets`, `*.local`, SSH keys, `*.pem`/`*.key`, `.netrc`, `.pgpass`, `.aws/credentials`, or files named `secrets.*`/`credentials.*`
* **Do NOT search for or print secret values** — no `grep`/`rg` for `*_SECRET`, `*_TOKEN`, `*_PASSWORD`, `*_API_KEY`, etc.; no `printenv`/`env` dumps; no `echo $SOME_SECRET`
* **Reading scaffolds is fine — but via `cat`, not Read** — `cat .env.example` / `.env.template` / `.env.sample` is allowed by the hook. The Read *tool* is denied for the whole `.env.*` family (a blunt safety net — `permissions.deny` can't carve a per-file exception), so reach scaffolds with `cat` (Bash)
* **Need non-secret config from a blocked file** (e.g. `PORT`, `NODE_ENV`, a base URL in `.env`) — the guard is all-or-nothing per file, so do NOT try to extract single keys (`grep PORT .env` is blocked too). Instead, in order:
  1. `cat` the scaffold (`cat .env.example`) — usually lists every var name + non-secret defaults
  2. Read the committed config that *consumes* the env — config loaders, `docker-compose.yml`, `config/*`
  3. Ask the user to run `! grep VAR .env` (or `! cat .env`) themselves — the `!` prefix executes in their session and lands the output in context by their choice
* **Never circumvent the block** — if a secret value is genuinely needed, ask the user to inspect it in their own terminal. For tokens/DB access use the `oidc-token` / `db-agent` agents, which handle secrets without exposing them in context

## Git Rules

* `git push` is **blocked** globally — never attempt to push. The user will push manually when ready

## Workflow Rules

* When asked for a spec, plan, or design document — produce ONLY the document. Do NOT implement code or enter plan mode unless explicitly told to proceed
* Before proposing new patterns, configs, or test utilities — explore existing project conventions first (check .env files, base classes, established patterns)
* When unsure about commit scope or conventions — ask before committing
* Follow SRP for both code and commits — split by concern, don't merge unrelated changes

## Code Quality

* **A paragraph-long comment defending a workaround means the code is wrong — fix the code.** If correctness rests on prose the reader must absorb before touching the code, the design has leaked its complexity into the comment. Fold the reasoning back into the structure — better names, a guard clause, an extracted function, the right type — so the invariant is enforced by the code, not promised by a note. A short comment on genuine external constraints (an API quirk, a browser bug, a spec footnote) is fine; a long apology for the code's own shape is not.

## GitLab/GitHub Workflow

* Before creating MRs/PRs via CLI — always show a draft preview of title, description, and labels for approval first
* Before executing any destructive or state-changing CLI command (close issue, merge MR, apply labels) — show the exact command and explain what it does
