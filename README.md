# Dotfiles

Personal macOS dotfiles for development environment setup.

## Quick Start

```bash
# Clone the repository
git clone <your-repo-url> ~/dotfiles

# Preview what would be installed (safe, no changes made)
cd ~/dotfiles
./install.sh --dry-run

# Run the installation script
# This will install Homebrew packages, configure shell, and install Node.js LTS
./install.sh

# Or run interactively (asks before overwriting)
./install.sh --interactive

# Restart your shell
exec zsh

# Verify installation
node --version
npm --version
```

## Installation Options

```bash
./install.sh [OPTIONS]

Options:
  --dry-run         Preview changes without making them
  --interactive, -i Ask before overwriting existing files
  --skip-backup     Don't create backups (not recommended)
  --help, -h        Show help message
```

## What's Included

### Configurations

- **Zsh** - Shell configuration with Zim plugin manager
- **Git** - Git aliases, settings, and directory-based identities
- **SSH** - SSH host configurations
- **Ghostty** - Terminal emulator config
- **Homebrew** - Package management via Brewfile
- **Node.js** - Node.js LTS automatically installed via NVM (lazy-loaded)
- **PHP** - Custom php.ini overrides and PECL extension management
- **Claude Code** - Global settings, skills, hooks, and MCP servers
- **JetBrains** - Toolbox settings sync
- **Husky** - NVM initialization for git hooks
- **League of Legends** - Game settings export/import

### Directory Structure

```
dotfiles/
├── install.sh              # Main installation script
├── .gitignore              # Files to ignore in git
├── brew/
│   ├── Brewfile            # Homebrew packages (organized by category)
│   └── Brewfile.local.template # Template for machine-specific packages
├── zsh/
│   ├── .zshrc              # Main Zsh config
│   ├── .zshrc.user         # User-specific settings
│   ├── .zshrc.secrets      # API keys (git-ignored)
│   ├── .zprofile           # Zsh login shell config
│   └── .zimrc              # Zim plugin configuration
├── git/
│   ├── .gitconfig          # Git configuration
│   ├── .gitconfig.context.template # Template for new Git contexts
│   └── README.md           # Git setup documentation
├── ssh/
│   ├── config              # SSH host configurations
│   ├── config.local        # Machine-specific SSH keys (git-ignored)
│   └── README.md           # SSH setup documentation
├── ghostty/
│   └── config              # Ghostty terminal config
├── php/
│   ├── conf.d/custom.ini   # PHP config overrides
│   └── extensions.list     # PECL extensions to install
├── utils/
│   ├── .lazy-nvm.sh        # Lazy-loading NVM wrapper
│   ├── .npmrc              # npm configuration
│   ├── .hushlogin          # Suppress login banner
│   └── gcp-sql-proxy.sh    # GCP Cloud SQL proxy helper
├── claude/                 # Global Claude Code config (symlinked to ~/.claude/)
│   ├── settings.json       # Global settings
│   ├── CLAUDE.md           # Global instructions
│   ├── skills/             # Skills (/commit, /spec, /create-issue, /create-mr, /review-mr)
│   ├── hooks/              # Hook scripts (commit validation)
│   └── statusline.sh       # Custom status bar
├── husky/
│   └── init.sh             # NVM init for git hooks
├── jetbrains/
│   └── .settings.json      # JetBrains Toolbox settings
├── games/lol/              # League of Legends config sync
└── scripts/
    ├── update.sh           # Update all components
    ├── php-setup.sh        # Symlink PHP config
    ├── php-extensions.sh   # Manage PECL extensions
    ├── macos-defaults.sh   # macOS system defaults
    ├── kc-redirect-uri.sh  # Keycloak redirect URI manager
    ├── lol-export.sh       # Export LoL settings
    └── lol-import.sh       # Import LoL settings
```

## Manual Setup

If you prefer to set up components individually:

### 1. Homebrew Packages

```bash
# Install all packages from Brewfile
brew bundle install --file=~/dotfiles/brew/Brewfile

# Install machine-specific packages (if you have Brewfile.local)
brew bundle install --file=~/dotfiles/brew/Brewfile.local

# After installing new packages, manually add them to Brewfile
# Do NOT use `brew bundle dump --force` — it destroys the organized category structure

# Remove packages not in Brewfile
brew bundle cleanup --file=~/dotfiles/brew/Brewfile
```

### 2. Zsh Configuration

```bash
# Symlink configs
ln -sf ~/dotfiles/zsh/.zshrc ~/.zshrc
ln -sf ~/dotfiles/zsh/.zprofile ~/.zprofile
ln -sf ~/dotfiles/zsh/.zimrc ~/.zimrc

# Create secrets file from template
cp ~/dotfiles/zsh/.zshrc.secrets.template ~/dotfiles/zsh/.zshrc.secrets

# Edit with your API keys
vim ~/dotfiles/zsh/.zshrc.secrets

# Install Zim
curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh

# Reload shell
source ~/.zshrc
```

### 3. SSH Configuration

```bash
# Symlink SSH config
ln -sf ~/dotfiles/ssh/config ~/.ssh/config

# Create local config from template
cp ~/dotfiles/ssh/config.local.template ~/dotfiles/ssh/config.local

# Edit with your SSH key paths
vim ~/dotfiles/ssh/config.local
```

### 4. Git Configuration

```bash
# Symlink git config
ln -sf ~/dotfiles/git/.gitconfig ~/.gitconfig

# (Optional) Set up directory-based Git identities
# Create a context for work projects
cp ~/dotfiles/git/.gitconfig.context.template ~/dotfiles/git/.gitconfig.work
vim ~/dotfiles/git/.gitconfig.work

# Add the conditional include to main .gitconfig
# Uncomment and modify one of the examples in the Conditional Includes section

# See git/README.md for full documentation on Git contexts
```

### 5. Ghostty Terminal

```bash
# Create config directory
mkdir -p ~/.config/ghostty

# Symlink config
ln -sf ~/dotfiles/ghostty/config ~/.config/ghostty/config
```

### 6. PHP (Optional)

```bash
# Symlink PHP config
./scripts/php-setup.sh

# Install PECL extensions from the list
./scripts/php-extensions.sh install
```

### 7. Claude Code

```bash
# Symlink global config to ~/.claude/
ln -sf ~/dotfiles/claude/settings.json ~/.claude/settings.json
ln -sf ~/dotfiles/claude/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/dotfiles/claude/skills ~/.claude/skills
ln -sf ~/dotfiles/claude/hooks ~/.claude/hooks
ln -sf ~/dotfiles/claude/statusline.sh ~/.claude/statusline.sh

# Register MCP servers (handled by install.sh)
# See setup_claude_code() in install.sh for current registrations
```

## Configuration Files

### Tracked in Git (Safe to Share)

- Main configuration files (`.zshrc`, `.gitconfig`, `ssh/config`)
- Brewfile with package lists
- Templates for local configurations

### Not Tracked (Machine-Specific)

- `zsh/.zshrc.secrets` - API keys and tokens
- `ssh/config.local` - SSH key paths
- `brew/Brewfile.local` - Machine-specific packages
- `git/.gitconfig.*` - Git context configurations (work/client emails)
- `*.local` files

## Customization

### Adding New Packages

```bash
# Install the package
brew install package-name

# Manually add it to the Brewfile in the correct category with an inline comment
# Do NOT use `brew bundle dump --force` — it destroys the organized category structure
vim ~/dotfiles/brew/Brewfile
```

### Adding Environment Variables

Edit `~/dotfiles/zsh/.zshrc.user` for non-sensitive variables or `~/dotfiles/zsh/.zshrc.secrets` for API keys.

### Adding Aliases

Edit `~/dotfiles/zsh/.zshrc.user`:

```bash
alias myalias="command"
```

### Adding SSH Hosts

1. Edit `~/dotfiles/ssh/config` for the host configuration
2. Edit `~/dotfiles/ssh/config.local` for the IdentityFile path

### Configuring Git Contexts (Directory-Based Identities)

Use different Git identities (name, email, signing keys) for different project directories:

```bash
# 1. Create a new context for work projects
cp ~/dotfiles/git/.gitconfig.context.template ~/dotfiles/git/.gitconfig.work
vim ~/dotfiles/git/.gitconfig.work
# Set your work name and email

# 2. Add the conditional include to main .gitconfig
vim ~/dotfiles/git/.gitconfig
# Uncomment and modify one of the examples:
# [includeIf "gitdir:~/Documents/Dev/work/"]
#     path = ~/.dotfiles/git/.gitconfig.work

# 3. Create additional contexts as needed
cp ~/dotfiles/git/.gitconfig.context.template ~/dotfiles/git/.gitconfig.client
vim ~/dotfiles/git/.gitconfig.client

# 4. Test it works
cd ~/Documents/Dev/work/some-project
git config user.email  # Should show your work email

cd ~/Documents/random-project
git config user.email  # Should show your default email
```

**See `git/README.md` for comprehensive documentation on Git contexts.**

## Setting Up on a New Machine

1. Clone the dotfiles repository
2. Preview changes: `./install.sh --dry-run`
3. Run installation: `./install.sh` (or `./install.sh --interactive` for confirmations)
4. Edit `zsh/.zshrc.secrets` with your API keys
5. Edit `ssh/config.local` with your SSH key paths
6. (Optional) Create Git context configs for work/client projects (see `git/README.md`)
7. (Optional) Create `brew/Brewfile.local` for machine-specific packages
8. (Optional) Run `./scripts/php-setup.sh` for PHP configuration
9. Restart your terminal

## Safety Features

### Automatic Backups

The `install` script automatically backs up existing configurations before replacing them:

```
~/.dotfiles_backup/
└── 20241116_143022/
    ├── .zshrc
    ├── .gitconfig
    └── .ssh/
        └── config
```

Backups are timestamped, so you can run the installer multiple times without losing previous backups.

### Dry Run Mode

Test the installation without making any changes:

```bash
./install.sh --dry-run
```

This shows you exactly what would be installed, linked, and backed up.

### Interactive Mode

Get prompted before overwriting existing files:

```bash
./install.sh --interactive
```

The script will ask for confirmation before replacing any existing configuration.

## Maintenance

### Update Homebrew Packages

```bash
brew update && brew upgrade
```

### Update Brewfile After Installing New Packages

Manually add the package to `brew/Brewfile` in the correct category with an inline comment.
Do **not** use `brew bundle dump --force` — it destroys the organized category structure.

If you're using Claude Code, the project-local `/brewfile-organize` skill (`.claude/commands/brewfile-organize.md`) helps re-organize a freshly dumped Brewfile back into the canonical category order.

### Update Zim Plugins

```bash
zimfw update
zimfw upgrade
```

## Tips

- Keep sensitive data in `.secrets` or `.local` files
- Use templates for machine-specific configurations
- Document custom configurations in this README
- Commit and push changes regularly

## Troubleshooting

### Zsh Not Loading Configuration

```bash
# Check if symlinks are correct
ls -la ~/.zshrc ~/.zprofile ~/.zimrc

# Reload shell
exec zsh
```

### SSH Config Not Working

```bash
# Verify SSH config syntax
ssh -G github.com

# Check file permissions
chmod 600 ~/.ssh/config
```

### Homebrew Issues

```bash
# Run diagnostics
brew doctor

# Update Homebrew
brew update
```

### Restoring from Backup

`install.sh` saves any file it would overwrite into a timestamped directory under `~/.dotfiles_backup/`. To restore a previous config:

```bash
ls ~/.dotfiles_backup/
cp ~/.dotfiles_backup/<timestamp>/<file> <original-location>
```

### Partial Install (install.sh failed midway)

`install.sh` is idempotent — re-running it picks up where it left off. Symlinks already in place are detected and skipped, so it's safe to re-run after fixing the underlying issue (e.g. missing tool, network failure).

### NVM Commands Not Found

NVM is **lazy-loaded** — the `nvm`, `node`, `npm`, `yarn`, `pnpm`, etc. commands are wrapper functions that load NVM on first invocation. If a command isn't recognized:

```bash
# Verify NVM is installed
ls ~/.nvm/nvm.sh

# Force-load NVM in the current shell
source ~/.nvm/nvm.sh

# Reload shell config
exec zsh
```

If `node` resolves to a system binary instead of an NVM-managed one, ensure `~/.zshrc.user` is sourced (it's what registers the lazy wrappers via `utils/.lazy-nvm.sh`).

### Verify All Symlinks

```bash
# Check that key symlinks resolve to the dotfiles repo
for f in ~/.zshrc ~/.zprofile ~/.gitconfig ~/.ssh/config ~/.claude/settings.json; do
    printf '%-30s -> %s\n' "$f" "$(readlink "$f" 2>/dev/null || echo 'NOT A SYMLINK')"
done
```

## License

MIT
