# Dotfiles Repository

Personal macOS dotfiles for bootstrapping and maintaining a development environment. Manages shell config, packages, SSH, Git, terminal, and game settings.

## Directory Structure

```
dotfiles/
├── install.sh              # Main installation orchestrator
├── brew/Brewfile           # Homebrew packages (organized by category)
├── zsh/                    # Shell: .zshrc, .zshrc.user, .zshrc.claude, .zshrc.secrets
├── ssh/                    # SSH: config, config.local
├── git/                    # Git: .gitconfig, context templates
├── ghostty/config          # Terminal emulator
├── php/                    # PHP config and extensions
├── utils/                  # .lazy-nvm.sh, .npmrc, .hushlogin, gcp-sql-proxy.sh
├── claude/                 # Global Claude Code config (symlinked to ~/.claude/)
├── .claude/                # Project-local Claude Code config
├── husky/                  # Git hook helpers (NVM init)
├── jetbrains/              # JetBrains Toolbox settings
├── games/lol/              # League of Legends config sync
└── scripts/                # Maintenance scripts
```

## Key Conventions

### File Patterns

Suffix determines visibility and tracking:

| Suffix       | Purpose                          | Git-tracked | Example                 |
|--------------|----------------------------------|-------------|-------------------------|
| `*.local`    | Machine-specific overrides       | No          | `ssh/config.local`      |
| `*.secrets`  | Sensitive data (API keys, creds) | No          | `.zshrc.secrets`        |
| `*.template` | Scaffolds for local files        | Yes         | `config.local.template` |

### Symlink Strategy

`install.sh` symlinks config files from this repo into `$HOME` so changes here propagate immediately. Note that `~/.claude/` is **not** a single directory symlink — individual files and subdirectories are linked so that runtime data Claude Code writes into `~/.claude/` (projects, transcripts, etc.) stays out of the repo.

| Source                          | Target                  |
|---------------------------------|-------------------------|
| `dotfiles/zsh/.zshrc`           | `~/.zshrc`              |
| `dotfiles/git/.gitconfig`       | `~/.gitconfig`          |
| `dotfiles/ssh/config`           | `~/.ssh/config`         |
| `dotfiles/claude/settings.json` | `~/.claude/settings.json` |
| `dotfiles/claude/CLAUDE.md`     | `~/.claude/CLAUDE.md`   |
| `dotfiles/claude/skills/`       | `~/.claude/skills`      |
| `dotfiles/claude/agents/`       | `~/.claude/agents`      |
| `dotfiles/claude/hooks/`        | `~/.claude/hooks`       |
| `dotfiles/claude/scripts/`      | `~/.claude/scripts`     |
| `dotfiles/claude/statusline.sh` | `~/.claude/statusline.sh` |

### Environment Variable

`$DOTFILES_DIR` points to the repo location (auto-detected in `.zshrc`, overridable in `.zshrc.user`).

## Commit Message Format

```
type(scope): description
```

**Types:** `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `perf`<br>
**Scopes:** `zsh`, `brew`, `ssh`, `git`, `ghostty`, `php`, `husky`, `scripts`, `claude`, `jetbrains`, `lol`, `config`, `docs`

Examples:
- `feat(zsh): add new alias`
- `fix(brew): remove outdated package`
- `chore(scripts): update install logic`

## Brewfile Organization

Packages in `brew/Brewfile` are grouped by category and must stay in this order. Each package includes an inline comment explaining what it does.

1. Taps
2. CLI Tools & Utilities
3. Development Tools
4. Databases & Data Tools
5. PHP & Composer
6. Runtime Environments
7. GUI Applications (Casks)
8. VSCode Extensions
9. Go Packages

Do NOT run `brew bundle dump --force` — it destroys the manual organization.

## Claude Code Setup

### Global Configs (symlinked to `~/.claude/`)

| Path                   | Purpose                                                                                         |
|------------------------|-------------------------------------------------------------------------------------------------|
| `claude/settings.json` | Global settings (permissions, hooks, model, plugins)                                            |
| `claude/CLAUDE.md`     | Global instructions (workflow rules, git platform detection)                                    |
| `claude/commands/`     | Global slash commands (currently empty — migrated to skills)                                    |
| `claude/skills/`       | Global slash-command skills — one dir each, self-documented via `SKILL.md` frontmatter (`/commit`, `/spec`, `/review-mr`, …)            |
| `claude/agents/`       | Subagent definitions — `.md` with frontmatter (`oidc-token`, `db-agent`)                         |
| `claude/hooks/`        | Hook scripts (commit validation, `oidc-guard`, `db-guard`, `secret-guard` — guards log every block) |
| `claude/scripts/`      | Helper scripts (GitLab review posting, review-worktree, `oidc-token.sh`, `db-agent.sh`, `log-lib.sh`) |
| `claude/statusline.sh` | Custom status bar                                                                               |

### Review History (per-project, never committed)

Created by `/review-mr` and `/re-review-mr`:
- `reviews/{gl|gh}-{id}.md` — Review rounds with YAML frontmatter + markdown body
- Auto-excluded via `.git/info/exclude`

### Review Worktrees (user-scoped, never committed)

`/review-mr` and `/re-review-mr` run inside isolated git worktrees so the user's main working tree is never disturbed:

- **Layout:** `~/.claude/worktrees/reviews/<repo-slug>/<gl|gh>-<id>/`
- **Sidecar:** `~/.claude/worktrees/reviews/<repo-slug>/<gl|gh>-<id>.meta.json` records branch, title, rounds, last verdict, main repo path
- **Auto-cleanup:** worktree removed only when verdict is `approve`. Other verdicts keep the worktree for the next round
- **Manual cleanup:** `/cleanup-review-worktrees` (interactive, supports `--older-than N`, `--repo <slug>`, `--merged`)
- **Helper script:** `claude/scripts/review-worktree.sh` (subcommands: `init`, `write-meta`, `list`, `remove`, `remove-path`)

### Agent Logs (runtime, never committed)

The `db-agent` and `oidc-token` agents (and their guards) write a shared,
structured audit trail under `~/.claude/logs/` — runtime data outside the repo,
so there is nothing to commit or exclude. One JSON object per line (JSONL).

- **Files:** `logs/db.log` (db-agent + db-guard), `logs/oidc.log` (oidc-token + oidc-curl + oidc-guard), `logs/secret.log` (secret-guard). Auto-created `chmod 700`/`600`.
- **Writer:** `claude/scripts/log-lib.sh` — the single `log_event <level> <op> [k=v…]` helper sourced by `db-lib.sh`, `oidc-lib.sh`, and both guards, so every surface emits the same line shape.
- **Core keys:** `ts, agent, script, level (error|denied|info), op, rid`, plus context (`alias`/`tenant`/`client`/`grant`/`user`/`host`/`exit`/`http`).
- **HTTP errors** (oidc-curl non-2xx) also carry `reason` (canonical status phrase) and `detail` (short reason from the body — JSON error field or HTML `<title>`, truncated + token-scrubbed). Raw bodies are never logged.
- **`rid`** correlates a single invocation across processes — e.g. `oidc-curl` exports it so its delegated `oidc-token` mint shares the id.
- **Scope:** db-agent logs every operation (`info` reads/writes + `denied`); oidc logs **errors and denials only** (no successful-mint lines). Secrets/tokens/response bodies are never logged.
- **Query:** `jq -c 'select(.level=="error")' ~/.claude/logs/oidc.log` · `jq -c 'select(.rid=="<id>")' ~/.claude/logs/*.log`

### Project-Local Configs (NOT symlinked)

| Path                          | Purpose                                          |
|-------------------------------|--------------------------------------------------|
| `.claude/settings.local.json` | Project-specific permissions                     |
| `.claude/commands/`           | Project-specific commands (`/brewfile-organize`) |

## Important Rules

1. **Never commit secrets** — use `.local` or `.secrets` files for anything sensitive
2. **Use templates** — copy `.template` files for machine-specific setup, never edit templates directly
3. **Dry-run first** — run `./install.sh --dry-run` before running install to preview what will change
4. **Preserve Brewfile order** — never run `brew bundle dump --force`, it destroys manual categorization
5. **Backups are automatic** — `install.sh` creates timestamped backups in `~/.dotfiles_backup/` before overwriting

## Key Scripts

| Script                       | Purpose                                       |
|------------------------------|-----------------------------------------------|
| `install.sh`                 | Bootstrap entire system (symlinks, packages)  |
| `scripts/update.sh`          | Update Homebrew, Zim, and all managed tools   |
| `scripts/php-setup.sh`       | Symlink PHP config to Homebrew PHP dir        |
| `scripts/php-extensions.sh`  | Install/manage PECL extensions                |
| `scripts/lol-export.sh`      | Export League of Legends settings to repo     |
| `scripts/lol-import.sh`      | Import League of Legends settings from repo   |
| `scripts/kc-redirect-uri.sh` | Manage Keycloak redirect URIs                 |
| `scripts/macos-defaults.sh`  | Apply macOS system preferences via `defaults` |

## Shell Configuration

Zsh files load in this order — each layer adds to the previous:

1. `.zprofile` — Login shell setup (Homebrew PATH)
2. `.zshrc` — Zim framework and plugins
3. `.zshrc.user` — Aliases, paths, environment variables
4. `.zshrc.claude` — Claude Code aliases + agent-tooling wrappers (sourced by `.zshrc.user`)
5. `.zshrc.secrets` — API keys and tokens (git-ignored)

NVM is lazy-loaded via `utils/.lazy-nvm.sh` to avoid ~2s shell startup penalty.

### Zim Auto-Bootstrap

On first shell start, `.zshrc` downloads `zimfw.zsh` from GitHub if missing, then runs `zimfw init -q` to install modules listed in `.zimrc`. The Zim version is **pinned** (see `ZIM_VERSION` in `.zshrc`) — bump it deliberately after reviewing the changelog rather than tracking `latest`.
