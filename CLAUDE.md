# Claude Code Configuration Guide for Dotfiles Repository

## Overview

This is a personal macOS dotfiles repository designed to bootstrap and maintain a complete development environment. It manages shell configuration, package management, SSH setup, Git settings, terminal configuration, and game settings in a unified, git-tracked way.

**Repository**: Personal dotfiles for macOS development environment
**Location**: Can be cloned to `~/dotfiles`, `~/.dotfiles`, `~/.dots`, or any custom path
**Primary Language**: Bash (installation/maintenance scripts), Zsh (shell config)
**Latest Commits**: Focused on Claude integration, Zsh fixes, Homebrew configuration

---

## 1. High-Level Architecture

### Core Design Principles

1. **Declarative Configuration**: All configurations are version-controlled and reproducible across machines
2. **Flexible Location**: Scripts auto-detect dotfiles directory regardless of clone location
3. **Machine-Specific Overrides**: Sensitive/local data in git-ignored `.local` and `.secrets` files
4. **Modular Organization**: Each tool/service has its own directory with documentation and templates
5. **Safe Installation**: Dry-run mode, interactive mode, automatic backups, and symlink management

### Directory Structure

```
dotfiles/
├── install.sh                      # Main installation orchestrator
├── README.md                        # User-facing documentation
├── INSTALL_GUIDE.md                # Setup guide for flexible locations
├── CLAUDE.md                        # This file
├── .gitignore                       # Git ignore patterns (sensitive data)
│
├── .claude/                         # Claude Code integration
│   ├── commands/
│   │   └── brewfile-organize.md    # Custom command for Brewfile management
│   └── settings.local.json         # Claude Code permissions config
│
├── brew/                            # Homebrew package management
│   ├── Brewfile                     # Main package list (git-tracked)
│   ├── Brewfile.local.template      # Template for machine-specific packages
│   └── README.md                    # Homebrew documentation
│
├── zsh/                             # Zsh shell configuration
│   ├── .zshrc                       # Main Zsh config (auto-loads user settings)
│   ├── .zshrc.user                  # User-specific aliases, paths, env vars
│   ├── .zshrc.secrets.template      # Template for API keys/tokens (git-ignored)
│   ├── .zshrc.secrets               # API keys and sensitive data (git-ignored)
│   ├── .zprofile                    # Login shell initialization (Homebrew path)
│   └── .zimrc                       # Zim plugin manager configuration
│
├── ssh/                             # SSH configuration
│   ├── config                       # Main SSH config (git-tracked)
│   ├── config.local                 # Machine-specific SSH keys (git-ignored)
│   ├── config.local.template        # Template for config.local
│   └── README.md                    # SSH setup documentation
│
├── git/                             # Git configuration
│   ├── .gitconfig                   # Git aliases, settings, conditional includes
│   ├── .gitconfig.context.template  # Template for creating Git contexts
│   └── README.md                    # Git setup and context documentation
│
├── ghostty/                         # Ghostty terminal emulator config
│   └── config                       # Theme and font configuration
│
├── jetbrains/                       # JetBrains Toolbox configuration
│   ├── .settings.json               # Main settings (git-tracked)
│   ├── .settings.json.template      # Template with all options
│   └── README.md                    # JetBrains setup documentation
│
├── php/                             # PHP configuration management
│   ├── README.md                    # PHP setup documentation
│   ├── conf.d/                      # Custom INI files
│   │   ├── custom.ini               # Main PHP settings (git-tracked)
│   │   ├── custom.ini.template      # Template for local overrides
│   │   └── custom.ini.local         # Machine-specific settings (git-ignored)
│   └── extensions.list              # PECL extensions to track/install
│
├── utils/                           # Utility scripts and configs
│   ├── .lazy-nvm.sh                 # Lazy-loading NVM wrapper
│   ├── .npmrc                       # NPM configuration
│   └── .hushlogin                   # Suppress login message
│
├── games/lol/                       # League of Legends config sync
│   ├── README.md                    # LoL setup documentation
│   ├── PersistedSettings.json       # Keybindings and game settings
│   ├── game.cfg                     # Graphics and performance settings
│   ├── input.ini                    # Input and camera settings
│   ├── ItemSets.json                # Item set configurations
│   ├── LCUAccountPreferences.yaml    # League Client preferences
│   ├── PerksPreferences.yaml         # Rune page preferences
│   └── export-info.txt              # Metadata about export
│
└── scripts/                         # Maintenance and utility scripts
    ├── install.sh (root)            # See above
    ├── update.sh                    # Updates all components
    ├── php-setup.sh                 # Set up PHP configuration symlinks
    ├── php-extensions.sh            # Manage PECL extensions
    ├── postgres-extensions.sh       # Build PostgreSQL extensions from source
    ├── lol-export.sh                # Export LoL settings from game
    ├── lol-import.sh                # Import LoL settings to game
    └── macos-defaults.sh            # macOS system preferences
```

### Component Relationships

```
┌─────────────────────────────────────────────────────────┐
│                   install.sh (orchestrator)              │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ├─► Homebrew                                            │
│  │   ├─► brew/Brewfile (packages + taps)               │
│  │   └─► brew/Brewfile.local (machine-specific)        │
│  │                                                       │
│  ├─► NVM Setup                                           │
│  │   └─► ~/.nvm/ directory (for Node versions)         │
│  │                                                       │
│  ├─► Zsh Configuration                                  │
│  │   ├─► .zshrc (Zim + user config loading)            │
│  │   ├─► .zshrc.user (aliases, paths, env vars)        │
│  │   ├─► .zshrc.secrets (API keys - git-ignored)       │
│  │   ├─► .zprofile (login shell setup)                 │
│  │   └─► .zimrc (plugin manager modules)               │
│  │                                                       │
│  ├─► SSH Configuration                                  │
│  │   ├─► ssh/config (host configs)                     │
│  │   └─► ssh/config.local (IdentityFiles - git-ignored)│
│  │                                                       │
│  ├─► Git Configuration                                  │
│  │   ├─► .gitconfig (aliases, settings, includes)      │
│  │   └─► .gitconfig.* (directory-based identities)     │
│  │                                                       │
│  ├─► PHP Configuration                                  │
│  │   ├─► php/conf.d/custom.ini (survives upgrades)     │
│  │   ├─► php/extensions.list (PECL tracking)           │
│  │   └─► scripts/php-*.sh (setup & management)         │
│  │                                                       │
│  ├─► Terminal Configuration                             │
│  │   ├─► ghostty/config (theme, fonts)                 │
│  │   └─► utils/ (npmrc, hushlogin, lazy-nvm)          │
│  │                                                       │
│  ├─► JetBrains Toolbox Configuration                    │
│  │   └─► jetbrains/.settings.json (shell scripts)      │
│  │                                                       │
│  ├─► Zim Plugin Manager                                 │
│  │   └─► ~/.zim/ (installed at runtime)                │
│  │                                                       │
│  ├─► Node.js Runtime                                     │
│  │   └─► LTS version (via NVM, auto-installed)         │
│  │                                                       │
│  └─► Games (Optional)                                   │
│      └─► League of Legends config sync                 │
│
└─────────────────────────────────────────────────────────┘
```

### Key Technologies & Tools

- **Shell**: Zsh with Zim plugin manager
- **Package Manager**: Homebrew + VSCode extensions
- **Terminal**: Ghostty (modern terminal emulator)
- **Version Control**: Git with custom aliases
- **Node Runtime**: NVM (lazy-loaded for performance) + Node.js LTS (auto-installed)
- **Development**: Go, PHP (version-agnostic), Bun, act (GitHub Actions locally)
- **Databases**: PostgreSQL 15, Redis, pgvector
- **CLI Tools**: fzf, ripgrep, bat, gh (GitHub CLI), nvm, git
- **Code Editor**: Visual Studio Code with curated extensions

---

## 2. Common Commands and Workflows

### Initial Setup (New Machine)

```bash
# Clone the repository (flexible location)
git clone https://github.com/your-repo.git ~/.dotfiles
cd ~/.dotfiles

# Dry-run to preview (safe, no changes)
./install.sh --dry-run

# Interactive installation (asks for confirmations)
./install.sh --interactive

# Or automatic installation (uses backups)
./install.sh

# Next steps after installation:
# 1. Edit .zshrc.secrets with API keys
vim zsh/.zshrc.secrets

# 2. Edit ssh/config.local with SSH key paths
vim ssh/config.local

# 3. (Optional) Create Brewfile.local for machine-specific packages
cp brew/Brewfile.local.template brew/Brewfile.local
vim brew/Brewfile.local

# 4. Restart terminal
exec zsh

# 5. Verify Node.js installation (auto-installed during setup)
node --version
npm --version
```

### Regular Maintenance

```bash
# Update everything at once
~/dotfiles/scripts/update.sh

# Update specific components
~/dotfiles/scripts/update.sh --skip-brew       # Skip Homebrew
~/dotfiles/scripts/update.sh --skip-zim        # Skip Zim plugins
~/dotfiles/scripts/update.sh --skip-macos      # Skip system updates

# Or update components individually:

# Update Homebrew packages
brew update && brew upgrade
brew upgrade --cask --greedy    # Cask updates with greedy flag

# Update Zim and plugins
zimfw update
zimfw upgrade

# Update global NPM packages
npm update -g

# Update dotfiles repository
cd ~/.dotfiles
git pull --rebase
```

### Package Management (Homebrew)

```bash
# Install all packages from Brewfile
brew bundle install --file=~/dotfiles/brew/Brewfile

# Install machine-specific packages
brew bundle install --file=~/dotfiles/brew/Brewfile.local

# After installing new package, update Brewfile
brew install <package-name>
brew bundle dump --file=~/dotfiles/brew/Brewfile --force

# List packages in Brewfile
brew bundle list --file=~/dotfiles/brew/Brewfile

# Verify Brewfile integrity
brew bundle check --file=~/dotfiles/brew/Brewfile

# Remove packages not in Brewfile (careful!)
brew bundle cleanup --file=~/dotfiles/brew/Brewfile --dry-run  # Preview first
brew bundle cleanup --file=~/dotfiles/brew/Brewfile
```

### PHP Configuration Management

The repository includes PHP configuration that **survives Homebrew updates**:

```bash
# Initial setup (automatic during install.sh)
~/dotfiles/scripts/php-setup.sh

# Edit PHP settings (survives upgrades)
vim ~/dotfiles/php/conf.d/custom.ini
brew services restart php

# Backup current PECL extensions
~/dotfiles/scripts/php-extensions.sh backup

# After PHP upgrade, reinstall extensions
brew upgrade php
~/dotfiles/scripts/php-extensions.sh reinstall
brew services restart php

# Track extensions in version control
vim ~/dotfiles/php/extensions.list
# Add: redis, imagick, xdebug, etc.

# Install all tracked extensions
~/dotfiles/scripts/php-extensions.sh install
```

**How it works:**
- Custom `.ini` files are symlinked to PHP's `conf.d/` directory
- Homebrew preserves `conf.d/` symlinks during updates
- PECL extensions tracked in `extensions.list` for easy reinstall
- Scripts auto-detect your active PHP version (works with 8.1, 8.2, 8.3, 8.4, etc.)

See `php/README.md` for comprehensive documentation.

### Configuration Customization

```bash
# Add new shell alias
echo 'alias myalias="command"' >> ~/dotfiles/zsh/.zshrc.user
source ~/.zshrc

# Add environment variable
echo 'export MY_VAR="value"' >> ~/dotfiles/zsh/.zshrc.user

# Add API key (secrets)
echo 'export API_KEY="secret-key"' >> ~/dotfiles/zsh/.zshrc.secrets

# Add SSH host
# 1. Edit config (public parts)
echo 'Host myserver
  HostName server.example.com
  User myusername' >> ~/dotfiles/ssh/config

# 2. Edit config.local (private key path)
echo 'Host myserver
  IdentityFile ~/.ssh/id_myserver' >> ~/dotfiles/ssh/config.local

# Reload shell configuration
alias rzsh="source $DOTFILES_DIR/zsh/.zshrc.user"
rzsh  # or: source ~/.zshrc
```

### Git Workflows

```bash
# Commit changes to dotfiles
cd ~/.dotfiles
git add <changed-files>
git commit -m "feat(component): description of change"
git push

# Common commit patterns:
# feat(zsh): added new alias
# fix(brew): removed outdated package
# docs(ssh): updated SSH setup guide
# refactor(scripts): simplified installation logic

# Useful git aliases available in this config:
git l       # Pretty commit log with graph
git s       # Short status
git d       # Diff against HEAD
git go      # Switch/create branch
git tags    # List tags
git branches # List all branches
git dm      # Delete merged branches
git whoami  # Show current user email
```

### Git Context Configuration (Directory-Based Identities)

The repository supports directory-based Git identities using Git's conditional includes feature.

```bash
# Create a new context (e.g., for work projects)
cd ~/.dotfiles/git
cp .gitconfig.context.template .gitconfig.work
vim .gitconfig.work
# Update name and email for this context

# Add the conditional include to main .gitconfig
vim .gitconfig
# Uncomment and modify one of the examples:
# [includeIf "gitdir:~/Documents/Dev/work/"]
#     path = ~/.dotfiles/git/.gitconfig.work

# Test the configuration
cd ~/Documents/Dev/work/some-project
git config user.email  # Should show work email

cd ~/Documents/random-project
git config user.email  # Should show default email

# Create multiple contexts as needed
cp .gitconfig.context.template .gitconfig.client
cp .gitconfig.context.template .gitconfig.personal
cp .gitconfig.context.template .gitconfig.opensource
```

**Key Points:**
- Context files (`.gitconfig.*`) are git-ignored to prevent committing work/client information
- Use the template as a starting point for new contexts
- Patterns ending with `/` match all subdirectories recursively
- See `git/README.md` for comprehensive documentation

### LoL Config Management (Gaming)

```bash
# Export your League of Legends settings
~/dotfiles/scripts/lol-export.sh

# This will:
# 1. Find LoL installation
# 2. Copy config files to games/lol/
# 3. Backup existing configs
# 4. Create export-info.txt metadata

# Commit the changes
cd ~/.dotfiles
git add games/lol/
git commit -m "Update LoL configs"
git push

# Import settings on new machine (after dotfiles install)
# Dry-run first to see what will change
~/dotfiles/scripts/lol-import.sh --dry-run

# Actually import
~/dotfiles/scripts/lol-import.sh

# This will:
# 1. Find LoL installation
# 2. Backup existing configs
# 3. Copy configs from dotfiles/games/lol/ to LoL directory
```

### Shell Features & Aliases

```bash
# NVM is lazy-loaded (loads on first use, not at shell startup)
# These commands trigger NVM load: nvm, npm, node, npx, yarn, etc.
nvm list
npm install package

# Custom shell aliases
rzsh         # Reload .zshrc.user without restarting terminal

# Standard aliases from Zim
g            # Git prefix for Zim aliases
l            # List files (with colors)
grep         # Has colors by default

# Git aliases from .gitconfig
git l        # Pretty log
git s        # Status
git d        # Diff
git go       # Switch/create branch
```

---

## 3. Key Configuration Patterns and Conventions

### 1. Modular Configuration Strategy

Each component follows this pattern:

```
component/
├── README.md                    # Setup and usage documentation
├── config                       # Main config file (git-tracked, public)
└── config.local                 # Machine-specific secrets (git-ignored)
```

**Why**: Allows sharing public configuration while keeping sensitive data local.

### 2. Template-Based Setup

Components use templates for initial setup:

```bash
# Template pattern:
~/dotfiles/component/file.template        # Template (git-tracked)
~/dotfiles/component/file.local            # User copy (git-ignored after creation)

# User creates local version from template:
cp ~/dotfiles/component/file.template ~/dotfiles/component/file.local
# Edit with machine-specific values
vim ~/dotfiles/component/file.local
```

**Components using templates**:
- `zsh/.zshrc.secrets.template` → `zsh/.zshrc.secrets`
- `ssh/config.local.template` → `ssh/config.local`
- `brew/Brewfile.local.template` → `brew/Brewfile.local`

### 3. Git-Ignore Strategy

```bash
# .gitignore patterns:
*.local                           # All .local files (machine-specific)
*/.zshrc.secrets                  # Zsh secrets (except templates)
!*.secrets.template               # But keep templates
ssh/config.local                  # SSH local config
brew/Brewfile.local               # Homebrew local packages
games/**/backup-*                 # Game backups (only latest configs)
```

**Convention**: Sensitive files end with `.local` or `.secrets`, tracked in git-ignore, have `.template` versions.

### 4. Auto-Detection Pattern

Components support flexible installation paths:

```bash
# Zsh .zshrc detects DOTFILES_DIR in this order:
# 1. Already set environment variable
# 2. ~/dotfiles/
# 3. ~/.dotfiles/
# 4. ~/.dots/
# 5. Fallback to ~/dotfiles

# Install scripts use ${BASH_SOURCE[0]} to find themselves:
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SSH config includes multiple possible locations:
Include ~/dotfiles/ssh/config.local
Include ~/.dotfiles/ssh/config.local
Include ~/.dots/ssh/config.local
```

**Why**: Users can clone to any directory name/location.

### 5. Symlink Strategy

Installation creates symlinks to dotfiles:

```bash
# Configuration files are symlinked, not copied:
~/.zshrc                → ~/dotfiles/zsh/.zshrc
~/.gitconfig            → ~/dotfiles/git/.gitconfig
~/.ssh/config           → ~/dotfiles/ssh/config
~/.config/ghostty/config → ~/dotfiles/ghostty/config

# Benefits:
# - Single source of truth (dotfiles dir)
# - Updates apply immediately
# - Easy to revert (just delete symlink)
# - Git tracks changes in one location
```

### 6. Backup Strategy

Installation creates timestamped backups:

```bash
# Backups before replacing existing files:
~/.dotfiles_backup/20241116_143022/
├── .zshrc
├── .gitconfig
└── .ssh/config

# Pattern: ~/.dotfiles_backup/YYYYMMDD_HHMMSS/
# Allows multiple backup sets without conflicts
```

### 7. Safety Features in Scripts

```bash
# Installation script patterns:
set -e                           # Exit on first error
DRY_RUN=false                    # Dry-run by default option
INTERACTIVE=false                # Ask before overwriting
SKIP_BACKUP=false                # Create backups by default

# Helper functions with color output:
info()    # Blue info messages (ℹ️)
success() # Green success messages (✅)
warn()    # Yellow warnings (⚠️)
error()   # Red errors (❌)

# Symlink safety:
is_our_symlink()    # Check if already linked correctly
safe_symlink()      # Link with backup and interactive prompt
backup_file()       # Backup before overwriting
```

### 8. Environment Variable Convention

```bash
# Main env var: $DOTFILES_DIR
# Set by install.sh or auto-detected in .zshrc.user
export DOTFILES_DIR="$HOME/.dotfiles"

# Used in:
# - All shell sourcing: source "$DOTFILES_DIR/..."
# - Scripts: "$DOTFILES_DIR/scripts/..."
# - User alias: alias rzsh="source $DOTFILES_DIR/zsh/.zshrc.user"

# Allows safe relative path references
```

### 9. Configuration Loading Order

**Zsh startup sequence**:
1. `.zprofile` (login shell) → Homebrew path setup
2. `.zshrc` (interactive shell)
   - Zim manager initialization
   - Plugin loading (syntax highlighting, autosuggestions, etc.)
3. `.zshrc.user` (custom user settings)
   - PATH adjustments
   - Aliases
   - Environment variables
4. `.zshrc.secrets` (sensitive data - git-ignored)
   - API keys
   - Tokens
   - Private environment variables

### 10. Package Organization (Brewfile)

Packages organized by category in specific order:

```
1. Taps (third-party repositories)
2. CLI Tools & Utilities
3. Development Tools
4. Databases & Data Tools
5. PHP & Composer
6. Runtime Environments
7. GUI Applications (Casks) - with subsections
8. VSCode Extensions - with subsections
9. Go Packages
10. Other
```

**Pattern**: Each package has an inline comment explaining what it does.

---

## 4. Important Files and Their Purposes

### Installation & Orchestration

| File | Purpose | Type |
|------|---------|------|
| `install.sh` | Main installation orchestrator; bootstraps entire system | Bash script |
| `scripts/update.sh` | Updates all components (brew, zim, npm, dotfiles, macos) | Bash script |
| `INSTALL_GUIDE.md` | Setup guide for flexible repository locations | Documentation |

### Zsh Shell Configuration

| File | Purpose | Tracked? |
|------|---------|----------|
| `zsh/.zshrc` | Main Zsh config; loads Zim and user settings | Yes |
| `zsh/.zshrc.user` | User aliases, paths, environment variables | Yes |
| `zsh/.zshrc.secrets.template` | Template for API keys | Yes |
| `zsh/.zshrc.secrets` | API keys and tokens (created from template) | No (git-ignored) |
| `zsh/.zprofile` | Login shell setup (Homebrew paths) | Yes |
| `zsh/.zimrc` | Zim plugin manager module configuration | Yes |

### Package Management

| File | Purpose | Tracked? |
|------|---------|----------|
| `brew/Brewfile` | Main package list (universal packages) | Yes |
| `brew/Brewfile.local.template` | Template for machine-specific packages | Yes |
| `brew/Brewfile.local` | Machine-specific packages (created from template) | No (git-ignored) |
| `brew/README.md` | Homebrew documentation and commands | Yes |

### SSH Configuration

| File | Purpose | Tracked? |
|------|---------|----------|
| `ssh/config` | SSH host configurations (public host details) | Yes |
| `ssh/config.local.template` | Template for SSH key paths | Yes |
| `ssh/config.local` | Machine-specific IdentityFile paths (created from template) | No (git-ignored) |
| `ssh/README.md` | SSH setup documentation | Yes |
| `ssh/config.template` | Alternative full config template | Yes |

### Version Control & Code

| File | Purpose | Tracked? |
|------|---------|----------|
| `git/.gitconfig` | Git aliases, user configuration, and conditional includes | Yes |
| `git/.gitconfig.context.template` | Template for creating new Git contexts | Yes |
| `git/.gitconfig.*` | Context-specific Git identities (work, client, etc.) | No (git-ignored) |
| `git/README.md` | Git setup and context documentation | Yes |
| `README.md` | Main repository documentation | Yes |
| `.gitignore` | Git ignore patterns (secrets, locals, system files) | Yes |

### Terminal & Utilities

| File | Purpose | Tracked? |
|------|---------|----------|
| `ghostty/config` | Ghostty terminal theme and font settings | Yes |
| `utils/.lazy-nvm.sh` | Lazy-loading NVM wrapper (performance optimization) | Yes |
| `utils/.npmrc` | NPM configuration (save-exact, audit, etc.) | Yes |
| `utils/.hushlogin` | Suppress login shell message | Yes |

### JetBrains Toolbox

| File | Purpose | Tracked? |
|------|---------|----------|
| `jetbrains/.settings.json` | JetBrains Toolbox settings with account ID (created from template) | No (git-ignored) |
| `jetbrains/.settings.json.template` | Template with portable settings (shell scripts location) | Yes |
| `jetbrains/README.md` | JetBrains Toolbox setup documentation | Yes |

### PHP Configuration

| File | Purpose | Tracked? |
|------|---------|----------|
| `php/README.md` | PHP setup and extension management documentation | Yes |
| `php/conf.d/custom.ini` | Main PHP configuration (survives Homebrew updates) | Yes |
| `php/conf.d/custom.ini.template` | Template for local PHP overrides | Yes |
| `php/conf.d/custom.ini.local` | Machine-specific PHP settings | No (git-ignored) |
| `php/extensions.list` | PECL extensions to track and install | Yes |
| `scripts/php-setup.sh` | Symlink PHP configuration to conf.d directory | Bash script |
| `scripts/php-extensions.sh` | Manage PECL extensions (install/backup/reinstall) | Bash script |

### Games Configuration

| File | Purpose | Tracked? |
|------|---------|----------|
| `games/lol/README.md` | LoL config sync documentation | Yes |
| `games/lol/PersistedSettings.json` | Keybindings and game settings | Yes |
| `games/lol/game.cfg` | Graphics and performance settings | Yes |
| `games/lol/input.ini` | Input and camera settings | Yes |
| `games/lol/*.json/.yaml` | League Client preferences and rune pages | Yes |

### Claude Code Integration

| File | Purpose | Tracked? |
|------|---------|----------|
| `.claude/commands/brewfile-organize.md` | Custom Claude command for Brewfile management | Yes |
| `.claude/settings.local.json` | Claude Code permissions and settings | No (local) |

---

## 5. Existing Documentation to Incorporate

The repository has comprehensive existing documentation:

- **README.md**: Main user guide with quick start, installation options, manual setup for each component, customization guide, troubleshooting
- **INSTALL_GUIDE.md**: Installation guide covering flexible repository locations and auto-detection
- **brew/README.md**: Homebrew-specific commands, package categories, adding packages, troubleshooting
- **ssh/README.md**: SSH setup documentation, host configuration patterns, current hosts
- **games/lol/README.md**: League of Legends config export/import workflows, backup restoration, version compatibility notes

---

## 6. Development Workflows

### Adding a New Shell Alias

```bash
# 1. Edit user configuration
vim ~/dotfiles/zsh/.zshrc.user

# 2. Add alias
alias mycommand="actual command"

# 3. Reload without restarting terminal
rzsh  # Uses the alias defined in .zshrc.user

# 4. Commit if permanent
cd ~/dotfiles
git add zsh/.zshrc.user
git commit -m "alias(zsh): add mycommand alias"
git push
```

### Adding a New NPM/Node Package

```bash
# 1. Install the package
npm install -g package-name

# 2. This loads NVM automatically (lazy-loading)

# 3. To make it permanent (in case you reinstall):
# Add to notes or Brewfile if it's a system tool
```

### Adding a Homebrew Package

```bash
# 1. Install with brew
brew install package-name
# OR for casks
brew install --cask app-name

# 2. Update Brewfile to reflect current state
brew bundle dump --file=~/dotfiles/brew/Brewfile --force

# 3. Review changes (manual organization recommended)
git diff brew/Brewfile

# 4. Commit changes
git add brew/Brewfile
git commit -m "feat(brew): add package-name package"
git push
```

### Adding a New SSH Host

```bash
# 1. Add public configuration to config
vim ~/dotfiles/ssh/config

# 2. Add host block (without IdentityFile)
Host myhost
  HostName server.example.com
  User username

# 3. Add private key path to config.local
vim ~/dotfiles/ssh/config.local

# 4. Add host block with IdentityFile
Host myhost
  IdentityFile ~/.ssh/id_myhost

# 5. Test SSH connection
ssh -G myhost  # Shows effective configuration
ssh myhost     # Test connection

# 6. Commit (only config, not config.local)
git add ssh/config
git commit -m "feat(ssh): add myhost configuration"
```

### Adding a New Git Context

```bash
# 1. Create context from template
cd ~/dotfiles/git
cp .gitconfig.context.template .gitconfig.work
vim .gitconfig.work

# 2. Set the identity for this context
[user]
    name = Your Name
    email = work@company.com

# 3. Add conditional include to main .gitconfig
vim ~/dotfiles/git/.gitconfig

# 4. Add or uncomment the includeIf directive
[includeIf "gitdir:~/Documents/Dev/work/"]
    path = ~/.dotfiles/git/.gitconfig.work

# 5. Test the configuration
cd ~/Documents/Dev/work/some-project
git config user.email  # Should show: work@company.com

cd ~/Documents/other-project
git config user.email  # Should show: default email

# 6. Commit (only .gitconfig, not context files)
# Context files are git-ignored to keep sensitive data private
git add git/.gitconfig
git commit -m "feat(git): add work directory context"
```

### Setting Up JetBrains Toolbox Shell Scripts

```bash
# After installation, JetBrains Toolbox will create shell scripts in ~/.local/bin
# This allows you to launch IDEs from the command line

# Examples of available commands (after installing IDEs):
webstorm .           # Open current directory in WebStorm
idea ~/project       # Open project in IntelliJ IDEA
pycharm script.py    # Open file in PyCharm

# Verify shell scripts location
cat ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json

# Should show:
# {
#     "shell_scripts": {
#         "location": "~/.local/bin"
#     }
# }

# If settings don't apply:
# 1. Completely quit JetBrains Toolbox
# 2. Verify symlink exists
ls -la ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json

# 3. Restart JetBrains Toolbox
# 4. Open Toolbox Settings > Tools > Shell scripts
# 5. Click "Generate" if needed
```

### Managing PHP Configuration and Extensions

```bash
# Initial setup (done automatically via install.sh)
~/dotfiles/scripts/php-setup.sh

# Editing PHP configuration
# 1. Edit shared configuration
vim ~/dotfiles/php/conf.d/custom.ini

# 2. Create machine-specific overrides (optional)
cp ~/dotfiles/php/conf.d/custom.ini.template ~/dotfiles/php/conf.d/custom.ini.local
vim ~/dotfiles/php/conf.d/custom.ini.local

# 3. Re-run setup to create symlinks
~/dotfiles/scripts/php-setup.sh

# 4. Restart PHP
brew services restart php

# 5. Verify settings loaded
php --ini
php -i | grep memory_limit

# Managing PECL Extensions
# 1. Backup current extensions before making changes
~/dotfiles/scripts/php-extensions.sh backup

# 2. Review backup
cat ~/dotfiles/php/extensions.list

# 3. Edit to add/remove extensions
vim ~/dotfiles/php/extensions.list
# Add lines like: redis, imagick, xdebug

# 4. Install all listed extensions
~/dotfiles/scripts/php-extensions.sh install

# 5. Restart PHP
brew services restart php

# After PHP Upgrade Workflow
# 1. Upgrade PHP via Homebrew
brew upgrade php

# 2. Configuration files are preserved automatically ✓

# 3. Reinstall PECL extensions
~/dotfiles/scripts/php-extensions.sh reinstall

# 4. Restart PHP
brew services restart php

# 5. Verify everything works
php --version
php --ini
pecl list

# Commit changes to dotfiles
cd ~/dotfiles
git add php/
git commit -m "feat(php): update configuration and extensions"
git push
```

### Updating League of Legends Settings

```bash
# 1. Make changes in-game (keybinds, settings, etc.)
# 2. Exit game completely
# 3. Export current settings
~/dotfiles/scripts/lol-export.sh

# 4. Review what was exported
ls -la ~/dotfiles/games/lol/

# 5. Commit and push
cd ~/dotfiles
git add games/lol/
git commit -m "Update LoL configs - new keybinds"
git push

# 6. On another machine
cd ~/dotfiles
git pull
~/dotfiles/scripts/lol-import.sh --dry-run  # Preview
~/dotfiles/scripts/lol-import.sh             # Import
```

---

## 7. Dependencies and Important Tools

### System Requirements
- macOS (uses Homebrew, mkcert, macOS-specific paths)
- Bash 4+ (for install script)
- Zsh 5.0+ (for shell configuration)
- Git (version control)

### Core Package Categories (from Brewfile)

**CLI Tools**: bat, curl, fastfetch, fzf, gh, git, make, mkcert, nvm, ripgrep

**Development**: act (GitHub Actions locally), go (programming language)

**Databases**: PostgreSQL 15, Redis, pgvector (vector similarity for PostgreSQL)

**Runtimes**: Node.js (via nvm), Bun (fast JS runtime), PHP (version-agnostic)

**Databases & Libraries**: freetds, libpq, composer

**Terminal**: Ghostty (modern terminal emulator)

**Applications**: VSCode, gcloud-cli, ngrok, The Unarchiver

**Fonts**: Fira Code, Iosevka, JetBrains Mono

**VSCode Extensions**: 
- AI: Geminai Code Assist, CodeRabbit, OpenCode
- Themes: Catppuccin, Bongocat
- Language Support: Go, TypeScript, YAML, Kubernetes
- Tools: ESLint, Prettier, Path Intellisense, Harper (grammar)

### Key Shell Modules (Zim)

- `environment`: Zsh built-in settings
- `git`: Git aliases and functions
- `input`: Keybindings and input events
- `termtitle`: Custom terminal title
- `utility`: Colors for ls, grep, less
- `duration-info`: Show command execution time
- `git-info`: Git status for prompts
- `asciiship`: ASCII-only prompt/theme
- `zsh-completions`: Additional completions
- `completion`: Tab completion system
- `zsh-syntax-highlighting`: Syntax highlighting
- `zsh-history-substring-search`: Search history with arrow keys
- `zsh-autosuggestions`: Fish-like suggestions
- `prompt-pwd`: Smart pwd display
- `gitster`: Git-aware prompt theme

---

## 8. Git Commit Message Conventions

The project uses conventional commits with these prefixes:

```
feat(component):   New feature
fix(component):    Bug fix
docs(component):   Documentation
refactor(component): Code refactoring
perf(component):   Performance improvement
test(component):   Test additions/updates
chore(component):  Maintenance tasks

Component examples: zsh, brew, ssh, git, lol, scripts
```

**Examples from git log**:
- `feat(claude): adds managing script`
- `fix(zsh): adds ZIM_HOME missing var`
- `fix(brew): adds vscode cask as default app`
- `feat(lol): Adds scripts to handle LOL exports/imports`

---

## 9. Safety and Best Practices

### Backup Strategy
- Every file replacement creates a timestamped backup in `~/.dotfiles_backup/`
- Backups persist across multiple runs (each gets its own timestamp)
- Can be disabled with `--skip-backup` flag (not recommended)

### Dry-Run Mode
- Always test changes with `./install.sh --dry-run` first
- Shows exactly what would happen without making changes
- Safe way to preview file replacements

### Interactive Mode
- Use `./install.sh --interactive` to confirm each change
- Prompts before overwriting existing files
- Useful on machines with custom configurations

### Secrets Management
```bash
# Never commit secrets to git
# Use .local and .secrets files (git-ignored by default)
# Use .template files as setup guides
# Review .gitignore before committing

# Sensitive file patterns:
*.local                 # Machine-specific configs
*/.zshrc.secrets        # API keys
ssh/config.local        # SSH key paths
brew/Brewfile.local     # Machine-specific packages
```

### Version Control Best Practices
```bash
# Always test before pushing
./install.sh --dry-run

# Commit small, focused changes
git add specific-files
git commit -m "meaningful message"

# Use pull-rebase to avoid merge commits
git pull --rebase

# Review diffs before committing
git diff --cached
```

---

## 10. Troubleshooting & Common Issues

### Installation Issues

**Problem**: `install.sh` not found
```bash
# Ensure you're in the dotfiles directory
cd ~/dotfiles
chmod +x install.sh  # Make it executable
./install.sh
```

**Problem**: Symlinks point to wrong location
```bash
# Verify symlinks
ls -la ~/.zshrc ~/.gitconfig ~/.ssh/config

# If wrong, regenerate
./install.sh --interactive  # Will ask to overwrite
```

**Problem**: Homebrew packages won't install
```bash
brew update
brew doctor  # Check for issues
brew bundle install --file=~/dotfiles/brew/Brewfile
```

### Shell Configuration Issues

**Problem**: New aliases not working
```bash
# Reload user config
rzsh

# Or reload entire shell
exec zsh

# Or source directly
source ~/.zshrc
```

**Problem**: NVM not found
```bash
# NVM loads lazily - it should load on first use of: nvm, npm, node, npx, yarn
# The install script automatically creates ~/.nvm directory

# If still not working, check:
echo $NVM_DIR              # Should be /Users/username/.nvm
ls -la ~/.nvm/             # Should exist and have nvm.sh symlink

# Check if NVM is installed via Homebrew
brew list nvm
ls -la "$(brew --prefix nvm)/nvm.sh"

# Reload shell configuration
exec zsh

# Try NVM command (triggers lazy-load)
nvm --version

# If still having issues, manually source NVM
export NVM_DIR="$HOME/.nvm"
source "$(brew --prefix nvm)/nvm.sh"
nvm --version
```

**Problem**: Environment variables not set
```bash
# Check if variable is set
echo $MY_VAR

# If not, verify it's in .zshrc.user or .zshrc.secrets
grep MY_VAR ~/dotfiles/zsh/.zshrc.user
grep MY_VAR ~/dotfiles/zsh/.zshrc.secrets

# Then reload
rzsh  # or exec zsh
```

### SSH Issues

**Problem**: SSH keys not found
```bash
# Verify SSH config
ssh -G github.com  # Shows effective configuration

# Check key paths in config.local
cat ~/dotfiles/ssh/config.local

# Verify key files exist
ls -la ~/.ssh/id_*
```

**Problem**: SSH config syntax error
```bash
# Check syntax
ssh -G github.com  # Will show error if syntax is wrong

# Or test connection
ssh -vvv github.com  # Verbose output
```

### LoL Configuration Issues

**Problem**: LoL not found during export/import
```bash
# Ensure LoL is installed and has been run at least once
# Check standard paths:
~/Library/Application\ Support/Riot\ Games/League\ of\ Legends/Config/

# Or try script with verbose output
bash -x ~/dotfiles/scripts/lol-export.sh
```

**Problem**: Settings not applying after import
```bash
# Ensure LoL is completely closed (not just minimized)
# Verify import succeeded
~/dotfiles/scripts/lol-import.sh --dry-run  # Preview first

# Restart LoL
# Settings should apply on launch
```

---

## 11. Extension Points and Customization

### Adding New Components

To add a new tool configuration:

1. **Create directory structure**:
   ```
   new-tool/
   ├── config                    # Main config
   ├── config.local.template     # Template
   └── README.md                 # Documentation
   ```

2. **Create template**:
   ```bash
   cp new-tool/config new-tool/config.local.template
   ```

3. **Update install.sh**:
   ```bash
   # Add function
   setup_new_tool() {
       info "Setting up new tool..."
       safe_symlink "$DOTFILES_DIR/new-tool/config" "$HOME/.config/new-tool/config" "new-tool config"
   }
   
   # Call in main() function
   ```

4. **Update .gitignore**:
   ```bash
   # Add to .gitignore
   new-tool/config.local
   ```

5. **Document**:
   - Add README.md with setup instructions
   - Update main README.md
   - Add to CLAUDE.md

### Environment-Specific Configuration

Use machine-specific Brewfile.local:
```bash
cp brew/Brewfile.local.template brew/Brewfile.local
# Edit with machine-specific tools
```

Or override DOTFILES_DIR:
```bash
export DOTFILES_DIR="/custom/path/to/dotfiles"
source ~/.zshrc
```

---

## 12. Integration Points for Claude Code

### Available Commands

**Brewfile Organization** (`.claude/commands/brewfile-organize.md`):
- Automatically organizes Brewfile with new packages
- Maintains section structure and comments
- Safe workflow with preview before changes
- Run: `@brewfile-organize`

### Permissions Configuration

Claude Code respects permissions in `.claude/settings.local.json`:
```json
{
  "permissions": {
    "allow": ["Bash(find:*)"],
    "deny": [],
    "ask": []
  }
}
```

### Using Claude for Dotfiles

Common tasks Claude can help with:
- Creating new shell functions or aliases
- Updating package lists intelligently
- Writing documentation
- Automating repetitive setup tasks
- Analyzing configuration patterns
- Generating commit messages

---

## Summary

This dotfiles repository follows a **clean architecture** with:

1. **Modular design**: Each tool/service is independent with clear interfaces
2. **Safe by default**: Dry-run, backups, interactive confirmation
3. **Flexible**: Works from any directory, supports machine-specific overrides
4. **Maintainable**: Clear documentation, conventional commits, organized structure
5. **Reproducible**: Version-controlled configurations, deterministic installation
6. **Extensible**: Easy to add new components or customize existing ones

The repository effectively manages a complete macOS development environment with shell configuration, package management, terminal settings, SSH/Git setup, and even gaming configuration - all version-controlled, shareable, and reproducible across machines.
