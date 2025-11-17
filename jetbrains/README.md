# JetBrains Toolbox Configuration

This directory contains configuration for JetBrains Toolbox, the unified installer and updater for JetBrains IDEs.

## Overview

JetBrains Toolbox manages installation and updates for JetBrains IDEs (IntelliJ IDEA, WebStorm, PyCharm, etc.) and can create command-line launchers for these tools.

## Configuration Files

- **`.settings.json`**: Main configuration file (git-tracked)
- **`.settings.json.template`**: Template with all available options

## Shell Scripts Location

The configuration sets the shell scripts location to `/usr/local/bin`, which means JetBrains Toolbox will create command-line launchers in this directory.

**Available commands after installation:**
- `webstorm` - WebStorm IDE
- `idea` - IntelliJ IDEA
- `pycharm` - PyCharm
- `goland` - GoLand
- etc.

**Why `/usr/local/bin`?**
- Already in your `$PATH` by default on macOS
- Standard location for user-installed command-line tools
- No additional PATH configuration needed
- Consistent with Homebrew's approach

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
        "location": "/usr/local/bin"  // Change to custom location if needed
    },
    "statistics": {
        "allow": true                  // Allow usage statistics
    },
    "tools": {
        "update_all_automatically": true  // Auto-update all IDEs
    }
}
```

**Note**: The `jetbrains_account` section is intentionally omitted from the tracked file as it contains your personal account ID. This will be added automatically by JetBrains Toolbox when you sign in.

## Verification

After setup, verify the configuration:

```bash
# Check symlink
ls -la ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json

# Check shell scripts location
cat ~/Library/Application\ Support/JetBrains/Toolbox/.settings.json | grep location

# Test command-line launcher (after installing an IDE)
which webstorm  # Should show /usr/local/bin/webstorm
```

## Troubleshooting

### Shell scripts not created

1. Open JetBrains Toolbox
2. Go to Settings (gear icon)
3. Verify "Shell scripts location" shows `/usr/local/bin`
4. Click "Generate" button if needed

### Permission issues

If `/usr/local/bin` doesn't exist or has permission issues:

```bash
# Create directory if needed
sudo mkdir -p /usr/local/bin

# Fix permissions
sudo chown -R $(whoami) /usr/local/bin
```

### Settings not applying

1. Ensure JetBrains Toolbox is completely quit (not just closed)
2. Verify symlink is correct
3. Restart JetBrains Toolbox
4. Check Settings in the Toolbox UI

## References

- [JetBrains Toolbox Documentation](https://www.jetbrains.com/toolbox-app/)
- [Shell Scripts Documentation](https://www.jetbrains.com/help/idea/working-with-the-ide-features-from-command-line.html)
