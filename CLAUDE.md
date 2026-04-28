# Dotfiles Repository

Personal macOS dotfiles for bootstrapping and maintaining a development environment. Manages shell config, packages, SSH, Git, terminal, and game settings.

## Directory Structure

```
dotfiles/
├── install.sh              # Main installation orchestrator
├── brew/Brewfile           # Homebrew packages (organized by category)
├── zsh/                    # Shell: .zshrc, .zshrc.user, .zshrc.secrets
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
| `claude/skills/`       | Global skills: `/commit`, `/spec`, `/create-issue`, `/create-mr`, `/review-mr`, `/re-review-mr` |
| `claude/hooks/`        | Hook scripts (commit validation)                                                                |
| `claude/scripts/`      | Helper scripts (GitLab review posting)                                                          |
| `claude/statusline.sh` | Custom status bar                                                                               |

### Review History (per-project, never committed)

Created by `/review-mr` and `/re-review-mr`:
- `reviews/{gl|gh}-{id}.md` — Review rounds with YAML frontmatter + markdown body
- Auto-excluded via `.git/info/exclude`

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
4. `.zshrc.secrets` — API keys and tokens (git-ignored)

NVM is lazy-loaded via `utils/.lazy-nvm.sh` to avoid ~2s shell startup penalty.

### Zim Auto-Bootstrap

On first shell start, `.zshrc` downloads `zimfw.zsh` from GitHub if missing, then runs `zimfw init -q` to install modules listed in `.zimrc`. The Zim version is **pinned** (see `ZIM_VERSION` in `.zshrc`) — bump it deliberately after reviewing the changelog rather than tracking `latest`.
