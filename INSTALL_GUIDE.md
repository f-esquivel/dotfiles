# Installation Guide

This guide covers installing your dotfiles regardless of where you clone the repository.

## Flexible Repository Location

Your dotfiles work from any directory name:
- `~/dotfiles` (default)
- `~/.dotfiles`
- `~/.dots`
- `~/my-config`
- Or any custom path!

The scripts automatically detect the directory location.

## Quick Install

```bash
# Clone to any location you prefer
git clone <your-repo-url> ~/dotfiles
# OR
git clone <your-repo-url> ~/.dotfiles
# OR
git clone <your-repo-url> ~/.dots

# Run the installer (it will auto-detect the directory)
cd <your-dotfiles-directory>
./install.sh
```

## How Auto-Detection Works

### Install Script
The `install.sh` script uses `${BASH_SOURCE[0]}` to detect its own location:
```bash
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

### Zsh Configuration
The `.zshrc` checks common locations in order:
1. `$DOTFILES_DIR` if already set
2. `~/dotfiles`
3. `~/.dotfiles`
4. `~/.dots`
5. Attempts to detect from file location

### SSH Configuration
SSH config includes multiple paths since it doesn't support environment variables:
```ssh-config
Include ~/dotfiles/ssh/config.local
Include ~/.dotfiles/ssh/config.local
Include ~/.dots/ssh/config.local
```

## Manual Path Override

If you use a custom directory name, you can set it explicitly:

```bash
# In your .zshrc.user or shell profile
export DOTFILES_DIR="$HOME/my-custom-dotfiles"
```

## Symlink Verification

After installation, verify symlinks point to the correct location:

```bash
ls -la ~/.zshrc ~/.ssh/config ~/.gitconfig
```

You should see them pointing to your dotfiles directory, regardless of its name.

## Troubleshooting

### Scripts Can't Find Dotfiles Directory

If auto-detection fails, manually set the path:

```bash
export DOTFILES_DIR="/path/to/your/dotfiles"
source ~/.zshrc
```

### SSH Config Not Loading

Make sure at least one of these exists:
- `~/dotfiles/ssh/config.local`
- `~/.dotfiles/ssh/config.local`
- `~/.dots/ssh/config.local`

The SSH config will try all common locations.

## Supported Directory Names

The auto-detection supports these common names out of the box:
- `dotfiles`
- `.dotfiles`
- `.dots`

For other names, set `$DOTFILES_DIR` explicitly.
