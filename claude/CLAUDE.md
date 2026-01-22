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
