# Interactive Git Commit

Guided interactive commit workflow with conventional commit message generation.

## Arguments

$ARGUMENTS - Optional file filter (file path, filename, pattern, or partial match)

## Critical Rules

- **NEVER** add `Co-authored-by`, `Co-Authored-By`, or any AI attribution signatures
- **NEVER** add `🤖 Generated with Claude Code` or similar footers
- **NEVER** add any signature, footer, or metadata beyond the user's chosen title and body
- Commit messages must contain ONLY what the user explicitly approves

## Instructions

Execute each step using the **AskUserQuestion** tool for all user interactions.

### Step 1: Check Staged Files

1. Run `git status --porcelain` to check repository state
2. Run `git diff --cached --name-only` to get staged files
3. **If nothing is staged:**
   - Use **AskUserQuestion** to ask: "No files are staged. What would you like to do?"
     - "Stage all changes" → Run `git add -A`
     - "Stage tracked files only" → Run `git add -u`
     - "Cancel" → Stop execution with message
4. **If `$ARGUMENTS` provided:** Filter files matching the argument (partial match, case-insensitive)

### Step 2: Analyze Changes

1. Run `git diff --cached` to analyze staged changes
2. Identify the nature of changes (feature, fix, refactor, etc.)
3. Determine appropriate scope from file paths (see Scope Detection below)
4. Assess if a body is needed (see Body Criteria below)

### Step 3: Select Commit Title

1. Generate 3-4 conventional commit title options
2. Use **AskUserQuestion** to present options:
   - Display each title option with brief rationale
   - Include "Regenerate options" choice
   - Include "Write custom title" choice
3. If "Regenerate" selected: Generate new options and repeat
4. If "Custom" selected: Ask user to provide their title

### Step 4: Body Recommendation

1. **Evaluate if body is needed** based on the selected title and changes:
   - Is the title self-explanatory for the scope of changes?
   - Does it meet any Body Criteria listed below?
   - Consider: number of files changed, complexity, breaking changes, migrations

2. **Present your recommendation** via **AskUserQuestion**:
   - Show the selected title
   - State your recommendation with reasoning, e.g.:
     - "✓ Recommend: No body needed - the title clearly describes this single-file bug fix"
     - "⚠ Recommend: Add body - this migration adds 3 new tables that should be documented"
   - Options: "Accept recommendation" / "Add body anyway" / "Skip body anyway"

3. **If user wants a body** (either following recommendation or overriding):
   - Generate 2-3 body options based on the actual changes
   - Use **AskUserQuestion** to present options:
     - Each body option with bullet points
     - "Regenerate options"
     - "Write custom body"
   - Iterate until user selects or writes a body

### Step 5: Preview & Confirm

1. Display full commit message preview in a code block:
   ```
   type(scope): description

   - Body line 1 (if applicable)
   - Body line 2 (if applicable)
   ```
2. Use **AskUserQuestion**: "Confirm this commit message?"
   - "Yes, commit" → Proceed to Step 6
   - "Edit title" → Return to Step 3
   - "Edit body" → Return to Step 4
   - "Cancel" → Stop execution

### Step 6: Execute Commit

1. Run the git commit command:
   ```bash
   git commit -m "<full message>"
   ```
   - For multi-line messages, use:
   ```bash
   git commit -m "<title>" -m "<body>"
   ```
2. Verify commit succeeded by checking exit code
3. Display commit hash and summary

### Step 7: Push Option

1. Run `git branch --show-current` to get current branch
2. **If branch is `main` or `master`:**
   - Use **AskUserQuestion** with warning: "⚠️ You're on the `{branch}` branch. Push to remote?"
     - "Yes, push to {branch}"
     - "No, stay local"
3. **If other branch:**
   - Use **AskUserQuestion**: "Push commit to remote?"
     - "Yes, push"
     - "No, stay local"
4. **If push selected:**
   - Check if upstream exists: `git rev-parse --abbrev-ref @{upstream}`
   - If no upstream: `git push -u origin {branch}`
   - If upstream exists: `git push`
5. Confirm push result

---

## Conventional Commit Format

### Structure
```
type(scope): description

- Detail 1 (optional)
- Detail 2 (optional)
```

### Types
| Type       | Use Case                                    |
|------------|---------------------------------------------|
| `feat`     | New feature                                 |
| `fix`      | Bug fix                                     |
| `refactor` | Code restructuring without behavior change  |
| `docs`     | Documentation only                          |
| `chore`    | Maintenance, dependencies, configs          |
| `test`     | Adding or updating tests                    |
| `perf`     | Performance improvements                    |
| `style`    | Formatting, whitespace, semicolons          |
| `ci`       | CI/CD pipeline changes                      |
| `build`    | Build system, dependencies                  |

### Scope Detection by Stack

Infer scope from file paths and project structure:

#### Laravel APIs
| Path Pattern                  | Suggested Scope              |
|-------------------------------|------------------------------|
| `app/Http/Controllers/*`      | controller/resource name     |
| `app/Models/*`                | model name                   |
| `app/Services/*`              | service name                 |
| `database/migrations/*`       | `migration` or `db`          |
| `routes/*`                    | `routes`                     |
| `config/*`                    | `config`                     |
| `app/Jobs/*`                  | `jobs` or job name           |
| `app/Events/*`, `Listeners/*` | `events`                     |
| `app/Policies/*`              | `auth` or policy name        |

#### NestJS APIs
| Path Pattern             | Suggested Scope       |
|--------------------------|-----------------------|
| `src/modules/<name>/*`   | module name           |
| `src/common/*`           | `common`              |
| `src/integrations/*`     | integration name      |
| `prisma/*`               | `prisma` or `db`      |
| `src/guards/*`           | `auth` or guard name  |
| `src/pipes/*`            | `validation`          |
| `src/interceptors/*`     | `interceptors`        |

#### Node/Express APIs
| Path Pattern           | Suggested Scope     |
|------------------------|---------------------|
| `src/routes/*`         | route name          |
| `src/controllers/*`    | controller name     |
| `src/middleware/*`     | `middleware`        |
| `src/models/*`         | model name          |
| `src/services/*`       | service name        |
| `lib/*`                | library name        |

#### React/Vite WebApps
| Path Pattern                    | Suggested Scope     |
|---------------------------------|---------------------|
| `src/components/*`              | component name      |
| `src/pages/*`, `src/views/*`    | page/view name      |
| `src/hooks/*`                   | `hooks`             |
| `src/store/*`, `src/redux/*`    | `store`             |
| `src/context/*`                 | `context`           |
| `src/api/*`, `src/services/*`   | `api`               |
| `src/utils/*`                   | `utils`             |
| `src/styles/*`                  | `styles`            |

#### Universal Patterns
| Path Pattern                          | Suggested Scope |
|---------------------------------------|-----------------|
| `package.json`, `composer.json`       | `deps`          |
| `.env*` files                         | `config`        |
| `docker*`, `Dockerfile`               | `docker`        |
| `.github/*`, `.gitlab-ci.yml`         | `ci`            |
| `README*`, `docs/*`                   | `docs`          |
| `tests/*`, `__tests__/*`, `*.spec.*`  | `test`          |
| `*.config.js`, `*.config.ts`          | `config`        |

---

## Body Criteria

### Add Body When

| Scenario                     | Reason                                              |
|------------------------------|-----------------------------------------------------|
| **Breaking changes**         | Document what breaks and migration path             |
| **Database migrations**      | List schema changes (tables, columns, relations)    |
| **Multiple related changes** | Summarize distinct changes in one logical unit      |
| **Complex features**         | Explain the "why" when not obvious from title       |
| **Security fixes**           | Document vulnerability (without exposing details)   |
| **Deprecations**             | Note what's deprecated and alternatives             |
| **API changes**              | Document endpoint/contract modifications            |

### Skip Body When

- Single-purpose, self-explanatory change
- Simple bug fix with obvious context
- Minor refactoring
- Documentation updates
- Dependency version bumps

---

## Constraints

- **Header:** Max 72 characters
- **Body lines:** Max 100 characters
- **Mood:** Imperative ("add" not "added")
- **Header ending:** No period
- **Case:** Lowercase after colon
- **Spacing:** Blank line between header and body

---

## Filter Examples

| Command             | Matches                          |
|---------------------|----------------------------------|
| `/commit auth`      | Files containing "auth" in path  |
| `/commit user`      | Files matching "user"            |
| `/commit src/api`   | Files under src/api              |
| `/commit .ts`       | All TypeScript files             |
| `/commit .php`      | All PHP files                    |
| `/commit`           | All staged files (no filter)     |
