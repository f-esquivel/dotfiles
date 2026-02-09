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
├── utils/                  # .lazy-nvm.sh, .npmrc, .hushlogin
├── claude/                 # Global Claude Code config (symlinked to ~/.claude/)
├── .claude/                # Project-local Claude Code config
├── jetbrains/              # JetBrains Toolbox settings
├── games/lol/              # League of Legends config sync
└── scripts/                # Maintenance scripts
```

## Key Conventions

### File Patterns
- `*.local` → Machine-specific, git-ignored (e.g., `ssh/config.local`)
- `*.secrets` → Sensitive data, git-ignored (e.g., `.zshrc.secrets`)
- `*.template` → Git-tracked templates for local files

### Symlink Strategy
Files are symlinked from dotfiles dir to home:
- `~/.zshrc` → `dotfiles/zsh/.zshrc`
- `~/.gitconfig` → `dotfiles/git/.gitconfig`
- `~/.ssh/config` → `dotfiles/ssh/config`

### Environment Variable
`$DOTFILES_DIR` points to the repo location (auto-detected or set in `.zshrc.user`).

## Commit Message Format

```
type(scope): description

Types: feat, fix, refactor, docs, chore, test, perf
Scopes: zsh, brew, ssh, git, php, scripts, claude, lol
```

Examples:
- `feat(zsh): add new alias`
- `fix(brew): remove outdated package`
- `chore(scripts): update install logic`

## Brewfile Organization

Packages in `brew/Brewfile` are organized by category:
1. Taps
2. CLI Tools & Utilities
3. Development Tools
4. Databases & Data Tools
5. PHP & Composer
6. Runtime Environments
7. GUI Applications (Casks)
8. VSCode Extensions
9. Go Packages

Each package has an inline comment explaining what it does.

## Claude Code Setup

**Global configs** (symlinked to `~/.claude/`):
- `claude/settings.json` - Global settings (permissions, hooks, model, plugins)
- `claude/CLAUDE.md` - Global instructions (workflow rules, git platform detection)
- `claude/commands/` - Global slash commands (`/commit`)
- `claude/skills/` - Global skills (`/spec`, `/review-mr`)
- `claude/hooks/` - Hook scripts (commit validation)
- `claude/statusline.sh` - Custom status bar

**Project-local configs** (NOT symlinked):
- `.claude/settings.local.json` - Project permissions
- `.claude/commands/` - Project-specific commands

## Important Rules

1. **Never commit secrets** - Use `.local` or `.secrets` files
2. **Use templates** - Copy `.template` files for local setup
3. **Test with dry-run** - Run `./install.sh --dry-run` before install
4. **Preserve organization** - Don't run `brew bundle dump --force` on Brewfile directly
5. **Backup exists** - Timestamped backups in `~/.dotfiles_backup/`

## Key Scripts

| Script                      | Purpose                 |
|-----------------------------|-------------------------|
| `install.sh`                | Bootstrap entire system |
| `scripts/update.sh`         | Update all components   |
| `scripts/php-setup.sh`      | Symlink PHP config      |
| `scripts/php-extensions.sh` | Manage PECL extensions  |
| `scripts/lol-export.sh`     | Export LoL settings     |
| `scripts/lol-import.sh`     | Import LoL settings     |

## Shell Configuration

Loading order:
1. `.zprofile` - Login shell (Homebrew path)
2. `.zshrc` - Zim plugins
3. `.zshrc.user` - Aliases, paths, env vars
4. `.zshrc.secrets` - API keys (git-ignored)

NVM is lazy-loaded via `utils/.lazy-nvm.sh` for faster shell startup.
