# Global Claude Code Instructions

* When building plans, commit messages and interactions with the user sacrifice grammar for the sake of concision (DO
  NOT APPLY THIS WHEN GENERATING CODE OR TECHNICAL SOLUTIONS)
* List any unresolved questions at the end, if any
* Ask more questions until you have enough context to give an accurate & confident answer
* Promote the usage of AskUserQuestionTool to clarify any input/petition from the user
* When receiving input/context in Spanish don't turn your output, ALWAYS STAY IN ENGLISH, at least the user indicates another output

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

Spec files (`specs/` directory) are **internal-use only** — they exist to improve DX, never leave the local machine.

* **NEVER** commit spec files or add them to `.gitignore` (use `.git/info/exclude` instead)
* **NEVER** reference spec files in issues, MRs, PRs, or any external documentation
* When creating a `specs/` directory in a project for the first time, automatically add `specs/` to `.git/info/exclude`
* Spec content can inform issues and MRs, but the spec file itself must not be linked, attached, or mentioned

## Workflow Rules

* When asked for a spec, plan, or design document — produce ONLY the document. Do NOT implement code or enter plan mode unless explicitly told to proceed
* Before proposing new patterns, configs, or test utilities — explore existing project conventions first (check .env files, base classes, established patterns)
* When unsure about commit scope or conventions — ask before committing
* Follow SRP for both code and commits — split by concern, don't merge unrelated changes

## GitLab/GitHub Workflow

* Before creating MRs/PRs via CLI — always show a draft preview of title, description, and labels for approval first
* Before executing any destructive or state-changing CLI command (close issue, merge MR, apply labels) — show the exact command and explain what it does
