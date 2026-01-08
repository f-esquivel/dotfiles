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
# ✅ Valid cross-scope
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

## Instructions

### Step 0: Load Project Conventions (Silent)

Before proceeding, silently load project-specific rules (do NOT ask user):

1. **Commitlint config** (enforced rules):
   - `commitlint.config.js`, `.commitlintrc.js`, `.commitlintrc.json`
   - Extract: allowed types, scope rules, length constraints

2. **Project docs** (conventions):
   - `docs/WORKFLOWS.md` → "Git Commit" or "Commit Guidelines" section
   - `CONTRIBUTING.md` → commit conventions
   - `CLAUDE.md` → git conventions

3. **Apply project rules over defaults:**
   - Project types → override default types
   - Project scopes → override scope detection
   - Project constraints → override default constraints
   - No project rules found → use defaults below

### Step 1: Stage Files

1. Run `git status --porcelain` and `git diff --cached --name-only`
2. **If nothing staged:** Auto-run `git add -u` (tracked files only)
3. **If `$ARGUMENTS` provided:** Filter to files matching the argument
4. If still nothing to commit, inform user and stop

### Step 2: SRP Check

1. Analyze staged changes for single responsibility
2. **If changes serve multiple purposes:** Stop and inform user to split
3. Proceed only if all changes serve ONE unified purpose

### Step 3: Generate Commit Message

1. Run `git diff --cached` to analyze staged changes
2. Auto-generate the best commit message:
   - **Type:** Infer from change nature (see Types)
   - **Scope:** Infer from file paths (see Scope Detection)
   - **Description:** Concise, imperative mood, max 75 chars
   - **Breaking:** Add `!` after scope if breaking change
3. **Body decision:** Auto-include body ONLY when:
   - Breaking changes (with `BREAKING CHANGE:` footer)
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

- **Description:** Max 75 characters
- **Header (full line):** Max 100 characters
- **Body lines:** Max 100 characters
- **Mood:** Imperative ("add" not "added")
- **Header ending:** No period
- **Case:** Lowercase after colon
- **Spacing:** Blank line between header and body

---

## Filter Examples

| Command           | Matches                         |
|-------------------|---------------------------------|
| `/commit auth`    | Files containing "auth" in path |
| `/commit src/api` | Files under src/api             |
| `/commit .ts`     | All TypeScript files            |
| `/commit`         | All staged/tracked files        |
