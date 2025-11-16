# Homebrew Configuration

This directory contains Homebrew package management configuration.

## Files

- **Brewfile** - Main package list (tracked in git)
- **Brewfile.local** - Machine-specific packages (git-ignored)
- **Brewfile.local.template** - Template for local packages

## Quick Commands

```bash
# Install all packages
brew bundle install --file=~/dotfiles/brew/Brewfile

# Install with local packages
brew bundle install --file=~/dotfiles/brew/Brewfile
brew bundle install --file=~/dotfiles/brew/Brewfile.local

# Update Brewfile after installing new packages
brew bundle dump --file=~/dotfiles/brew/Brewfile --force

# Remove packages not in Brewfile
brew bundle cleanup --file=~/dotfiles/brew/Brewfile

# Check what's in Brewfile
brew bundle list --file=~/dotfiles/brew/Brewfile
```

## Package Categories

### CLI Tools & Utilities
- bat, ripgrep, fzf, gh, git, etc.

### Development Tools
- act, go, k6

### Databases
- PostgreSQL, Redis, pgvector

### GUI Applications
- Ghostty, Chrome, Notion, etc.

### VSCode Extensions
- Themes, language support, AI assistants

### Go Packages
- gopls, staticcheck

## Adding New Packages

1. Install the package:
   ```bash
   brew install package-name
   # or
   brew install --cask app-name
   ```

2. Update your Brewfile:
   ```bash
   brew bundle dump --file=~/dotfiles/brew/Brewfile --force
   ```

3. Commit the changes:
   ```bash
   git add brew/Brewfile
   git commit -m "Add package-name to Brewfile"
   ```

## Machine-Specific Packages

For packages that should only be installed on certain machines:

1. Create local Brewfile:
   ```bash
   cp ~/dotfiles/brew/Brewfile.local.template ~/dotfiles/brew/Brewfile.local
   ```

2. Edit and add your packages:
   ```bash
   # brew/Brewfile.local
   brew "work-specific-tool"
   cask "company-vpn"
   ```

3. Install:
   ```bash
   brew bundle install --file=~/dotfiles/brew/Brewfile.local
   ```

## Troubleshooting

### Packages Won't Install

```bash
# Update Homebrew first
brew update

# Try installing again
brew bundle install --file=~/dotfiles/brew/Brewfile

# Check for issues
brew doctor
```

### Clean Up Old Packages

```bash
# Remove packages not in Brewfile (careful!)
brew bundle cleanup --file=~/dotfiles/brew/Brewfile

# Preview what would be removed
brew bundle cleanup --file=~/dotfiles/brew/Brewfile --dry-run
```
