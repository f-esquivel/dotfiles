---
name: commit
description: Interactive Git commit with auto-generated conventional commit messages and SRP enforcement.
disable-model-invocation: true
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash(git *)
argument-hint: [file filter - path, filename, pattern, or partial match]
---

# Interactive Git Commit

Streamlined commit workflow with auto-generated conventional commit messages.

## Arguments

$ARGUMENTS - Optional file filter (file path, filename, pattern, or partial match)

## Critical Rules

- **NEVER** add `Co-authored-by`, `Co-Authored-By`, or any AI attribution signatures
- **NEVER** add `🤖 Generated with Claude Code` or similar footers
- Commit messages must contain ONLY the generated title and body (if applicable)

---

## Single Responsibility Principle (SRP)

> **ONE commit = ONE purpose.** If you need "and" to describe it, split it.

### The Rule

One commit must do exactly ONE of these:
- Add ONE feature
- Fix ONE bug
- Refactor ONE thing
- Update ONE dependency group
- Change ONE configuration

### Cross-Scope Exception

Cross-scope commits allowed when ALL changes serve a **single unified purpose**:
- Same transformation applied everywhere (lint fixes, formatting)
- Splitting would create broken intermediate states
- Shared component change requiring consumer updates

```bash
# Valid cross-scope
style(lint): apply object-shorthand rule across codebase
refactor(ui): rename Button onClick signature and update consumers
deps(deps): upgrade react-router to v7 with migration fixes
```

### Self-Check

Before committing, ask:
1. Can I describe this with ONE verb? (add, fix, refactor, update)
2. Do all changes serve ONE purpose?
3. If reverted, will it undo exactly ONE logical thing?

If any answer is "no" → split the commit.

---

## Multi-Session Awareness

> Multiple Claude Code sessions may work on the same project simultaneously, modifying overlapping files. The commit skill must stage ONLY changes belonging to the current session.

### Principles

- **Session context is your guide** — use the conversation history to know which files and changes were produced in this session
- **When in doubt, leave it out** — if you cannot confidently attribute a change to this session, do NOT stage it
- **Preserve others' work** — unstaged changes from other sessions must remain untouched in the working tree

### Identifying Session-Relevant Changes

- Files you created, modified, or discussed during this conversation → **this session**
- Changes that align with the task/goal of this conversation → **likely this session**
- Changes with no connection to this session's work → **skip**
- Ambiguous changes → ask the user before staging

---

## Instructions

### Step 0: Load Project Conventions (Silent)

Before proceeding, silently load project-specific rules (do NOT ask user):

1. **Find commitlint config** — check in order (stop at first match):
   - Node.js: `commitlint.config.js`, `commitlint.config.ts`, `.commitlintrc.js`, `.commitlintrc.json`, `.commitlintrc.yml`
   - Go: `.commitlint.yaml`, `.commitlint.yml`

2. **Read the config file** and extract these rules verbatim:
   - **`type-enum`** → allowed types list (ONLY use these types, ignore defaults)
   - **`scope-enum`** → allowed scopes list (ONLY use these scopes, ignore path-based detection)
   - **`scope-empty`** → whether scope is required (`never` = required)
   - **`subject-case`** → casing rule (typically `lower-case`)
   - **`subject-max-length`** / **`header-max-length`** → length constraints

3. **Read project docs** for additional conventions:
   - `CLAUDE.md` → git conventions
   - `docs/WORKFLOWS.md` → "Git Commit" or "Commit Guidelines" section
   - `CONTRIBUTING.md` → commit conventions

4. **Apply project rules strictly:**
   - If `scope-enum` exists → **ONLY** use scopes from the list. NEVER infer scopes from file paths
   - If `type-enum` exists → **ONLY** use types from the list
   - If `subject-case` is `lower-case` → **entire description must be lowercase**, including acronyms (write `ci` not `CI`, `api` not `API`, `mr` not `MR`)
   - No config found → use defaults below (Types, Scope Detection, Constraints)

5. **Detect commitlint engine** to avoid syntax incompatibilities:
   - Go commitlint (`.commitlint.yaml`) → **do NOT use `!` breaking change indicator** in the header (use `BREAKING CHANGE:` footer instead). The Go parser does not support `type(scope)!:` syntax
   - Node.js commitlint → `!` syntax is safe to use

### Step 1: Review & Stage Files (Session-Aware)

1. Run `git status --porcelain` and `git diff --cached --name-only`
2. Run `git diff` to review all unstaged changes
3. **If changes are already staged:** verify all staged changes are session-relevant. Unstage anything unrelated with `git reset HEAD -- <file>`
4. **Cross-reference changes with session context** — classify each changed file as:
   - **Session-owned:** all changes are from this session → `git add <file>`
   - **Mixed:** some hunks from this session, some not → use hunk-level staging (see below)
   - **Unrelated:** no changes from this session → skip entirely, do NOT stage
5. **If `$ARGUMENTS` provided:** further filter to files matching the argument
6. If nothing session-relevant to commit, inform user and stop

#### Hunk-Level Staging (Mixed Files)

When a file contains changes from both this session and other sessions:

1. Run `git diff -- <file>` to see all hunks
2. Identify which hunks belong to this session's work
3. Construct a patch containing ONLY session-relevant hunks (preserve diff file headers and hunk context lines)
4. Apply to staging area:
   ```bash
   git apply --cached <<'PATCH'
   <filtered patch content>
   PATCH
   ```
5. Verify with `git diff --cached -- <file>` that only intended changes were staged

### Step 2: SRP Check

1. Analyze staged changes for single responsibility
2. **If changes serve multiple purposes:** Stop and inform user to split
3. Proceed only if all changes serve ONE unified purpose

### Step 3: Generate Commit Message

1. Run `git diff --cached` to analyze staged changes
2. Auto-generate the best commit message:
   - **Type:** Use project `type-enum` if loaded (Step 0), otherwise infer from change nature (see Types)
   - **Scope:** Use project `scope-enum` if loaded (Step 0), otherwise infer from file paths (see Scope Detection). Pick the closest matching scope from the allowed list — never invent scopes not in the list
   - **Description:** Concise, imperative mood. Apply `subject-case` rule from Step 0 (default: lowercase). **Never use uppercase acronyms** (CI, MR, API, URL, etc.) when the project enforces lowercase — write them in lowercase instead
   - **Breaking:** Use `BREAKING CHANGE:` footer for Go commitlint projects (Step 0). Use `!` after scope only when Node.js commitlint or no config
3. **Body decision:** Auto-include body ONLY when:
   - Breaking changes (include BREAKING CHANGE footer)
   - Database migrations
   - Performance changes (include before/after metrics if available)
   - Security fixes
   - Complex refactors needing context
4. Skip body for single-purpose, self-explanatory changes

### Step 4: Execute Commit

Run the commit directly (permission system handles confirmation):
```bash
git commit -m "<title>" -m "<body>"  # if body needed
git commit -m "<title>"              # if no body
```

Display commit hash on success.

---

## Conventional Commit Format

```
type(scope): description

[optional body - explain context if not obvious]

[BREAKING CHANGE: description if applicable]
```

### Types

| Type       | Use Case                                 |
|------------|------------------------------------------|
| `feat`     | New feature                              |
| `fix`      | Bug fix                                  |
| `hotfix`   | Critical production fix                  |
| `refactor` | Code restructuring (no behavior change)  |
| `perf`     | Performance improvement                  |
| `style`    | Formatting, whitespace (no code change)  |
| `docs`     | Documentation only                       |
| `test`     | Adding or updating tests                 |
| `build`    | Build system changes                     |
| `ci`       | CI/CD pipeline changes                   |
| `dx`       | Developer experience improvements        |
| `deps`     | Dependency updates                       |
| `security` | Security fix or improvement              |
| `chore`    | Maintenance (use sparingly)              |

### Scope Detection

#### Laravel APIs
| Path Pattern                  | Scope               |
|-------------------------------|---------------------|
| `app/Http/Controllers/*`      | controller/resource |
| `app/Models/*`                | model name          |
| `app/Services/*`              | service name        |
| `database/migrations/*`       | `migration` or `db` |
| `routes/*`                    | `routes`            |
| `config/*`                    | `config`            |
| `app/Jobs/*`                  | `jobs` or job name  |
| `app/Events/*`, `Listeners/*` | `events`            |

#### NestJS APIs
| Path Pattern             | Scope            |
|--------------------------|------------------|
| `src/modules/<name>/*`   | module name      |
| `src/common/*`           | `common`         |
| `src/integrations/*`     | integration name |
| `prisma/*`               | `prisma` or `db` |
| `src/guards/*`           | `auth`           |

#### React/Vite WebApps
| Path Pattern                  | Scope          |
|-------------------------------|----------------|
| `src/components/*`            | component name |
| `src/pages/*`, `src/views/*`  | page/view name |
| `src/hooks/*`                 | `hooks`        |
| `src/store/*`, `src/redux/*`  | `store`        |
| `src/api/*`, `src/services/*` | `api`          |

#### Universal Patterns
| Path Pattern                         | Scope    |
|--------------------------------------|----------|
| `package.json`, `composer.json`      | `deps`   |
| `.env*` files                        | `config` |
| `docker*`, `Dockerfile`              | `docker` |
| `.github/*`, `.gitlab-ci.yml`        | `ci`     |
| `README*`, `docs/*`                  | `docs`   |
| `tests/*`, `__tests__/*`, `*.spec.*` | `test`   |

---

## Constraints

These are defaults — project commitlint config (Step 0) overrides them.

- **Description:** Max 75 characters
- **Header (full line):** Max 100 characters
- **Body lines:** Max 100 characters
- **Mood:** Imperative ("add" not "added")
- **Header ending:** No period
- **Case:** Lowercase after colon. When project enforces `subject-case: lower-case`, ALL words must be lowercase — no uppercase acronyms (`ci` not `CI`, `api` not `API`, `mr` not `MR`, `url` not `URL`)
- **Spacing:** Blank line between header and body
- **Scopes:** When project defines `scope-enum`, only use listed scopes — never invent new ones

---

## Filter Examples

| Command           | Matches                         |
|-------------------|---------------------------------|
| `/commit auth`    | Files containing "auth" in path |
| `/commit src/api` | Files under src/api             |
| `/commit .ts`     | All TypeScript files            |
| `/commit`         | All staged/tracked files        |
