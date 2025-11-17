# JetBrains Toolbox Configuration

This directory contains configuration for JetBrains Toolbox, the unified installer and updater for JetBrains IDEs.

## Overview

JetBrains Toolbox manages installation and updates for JetBrains IDEs (IntelliJ IDEA, WebStorm, PyCharm, etc.) and can create command-line launchers for these tools.

## Configuration Files

- **`.settings.json`**: Main configuration file (git-ignored, contains your account ID)
- **`.settings.json.template`**: Template with portable settings (git-tracked)

## Shell Scripts Location

The configuration sets the shell scripts location to `~/.local/bin`, which means JetBrains Toolbox will create command-line launchers in this directory.

**Available commands after installation:**
- `webstorm` - WebStorm IDE
- `idea` - IntelliJ IDEA
- `pycharm` - PyCharm
- `goland` - GoLand
- etc.

**Why `~/.local/bin`?**
- User-owned directory (no sudo required)
- Follows XDG Base Directory specification
- Works consistently across all machines
- Automatically created by install script
- Added to `$PATH` in `.zshrc.user`

## Setup

### Automatic (via install.sh)

The installation script automatically symlinks this configuration:

```bash
~/.settings.json -> ~/Library/Application Support/JetBrains/Toolbox/.settings.json
```

### Manual Setup

If you need to set up manually:

```bash
# Backup existing settings (if any)
cp ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json \
   ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json.backup

# Create symlink
ln -sf ~/dotfiles/jetbrains/.settings.json \
   ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json

# Restart JetBrains Toolbox for changes to take effect
```

## Customization

To customize settings, edit `jetbrains/.settings.json`:

```json
{
    "shell_scripts": {
        "location": "~/.local/bin"  // Change to custom location if needed
    },
    "statistics": {
        "allow": true                  // Allow usage statistics
    },
    "tools": {
        "update_all_automatically": true  // Auto-update all IDEs
    }
}
```

**Note**: The `jetbrains_account` section is intentionally omitted from the template. JetBrains Toolbox will automatically add your account information to `.settings.json` when you sign in. Since `.settings.json` is git-ignored, your account ID stays private.

## Verification

After setup, verify the configuration:

```bash
# Check symlink
ls -la ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json

# Check shell scripts location
cat ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json | grep location

# Test command-line launcher (after installing an IDE)
which webstorm  # Should show /Users/frank/.local/bin/webstorm
```

## Troubleshooting

### Shell scripts not created

1. Open JetBrains Toolbox
2. Go to Settings (gear icon)
3. Verify "Shell scripts location" shows `~/.local/bin`
4. Click "Generate" button if needed

### Directory not writable

If you see "directory not writable" error:

```bash
# Verify directory exists and is owned by you
ls -ld ~/.local/bin

# Create if needed
mkdir -p ~/.local/bin

# Verify it's in your PATH
echo $PATH | grep -o "$HOME/.local/bin"
```

### Settings not applying

1. Ensure JetBrains Toolbox is completely quit (not just closed)
2. Verify symlink is correct
3. Restart JetBrains Toolbox
4. Check Settings in the Toolbox UI

## References

- [JetBrains Toolbox Documentation](https://www.jetbrains.com/toolbox-app/)
- [Shell Scripts Documentation](https://www.jetbrains.com/help/idea/working-with-the-ide-features-from-command-line.html)
