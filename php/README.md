# PHP Configuration Management

This directory manages PHP configuration and PECL extensions in a way that **survives Homebrew updates**.

## The Problem

When you update PHP via Homebrew (`brew upgrade php`), you typically lose:
- ✗ Custom `php.ini` settings
- ✗ Installed PECL extensions (redis, imagick, xdebug, etc.)
- ✗ Performance tuning
- ✗ Development-specific configurations

> **Note:** This solution works with any PHP version installed via Homebrew (8.1, 8.2, 8.3, 8.4, etc.)

## The Solution

This setup uses **two complementary approaches**:

1. **Custom `.ini` files** - Symlinked to PHP's `conf.d/` directory (survives updates)
2. **Extension tracking** - List-based PECL extension management with easy reinstall

---

## Directory Structure

```
php/
├── README.md                    # This file
├── conf.d/                      # Custom INI files
│   ├── custom.ini               # Main custom PHP settings (git-tracked)
│   ├── custom.ini.template      # Template for local overrides
│   └── custom.ini.local         # Machine-specific settings (git-ignored)
├── extensions.list              # PECL extensions to install/track
└── scripts/                     # (in ~/dotfiles/scripts/)
    ├── php-setup.sh             # Symlink configuration files
    └── php-extensions.sh        # Manage PECL extensions
```

---

## Quick Start

### Initial Setup (automatically done during install)

```bash
# Run the main installation
~/dotfiles/install.sh

# Or set up PHP manually
~/dotfiles/scripts/php-setup.sh

# Restart PHP to apply changes
brew services restart php
```

### After PHP Upgrade

When you run `brew upgrade php` and lose your extensions:

```bash
# Reinstall all PECL extensions from your tracked list
~/dotfiles/scripts/php-extensions.sh reinstall

# Restart PHP (use your PHP version)
brew services restart php

# Verify configuration
php --ini
```

---

## Configuration Management

### Editing PHP Settings

Your custom PHP configuration is stored in `conf.d/custom.ini`:

```bash
# Edit main custom configuration
vim ~/dotfiles/php/conf.d/custom.ini

# Restart PHP to apply changes
brew services restart php

# Verify settings were loaded
php --ini
php -i | grep memory_limit  # Example: check specific setting
```

**Current settings in `custom.ini`:**
- Memory limit: 512M
- Max execution time: 300s
- File upload size: 128M
- Error reporting: Full (development mode)
- OPcache: Enabled with optimizations
- Timezone: America/El_Salvador

### Machine-Specific Settings

For settings that differ between machines (dev vs prod, laptop vs desktop):

```bash
# Create local override file from template
cp ~/dotfiles/php/conf.d/custom.ini.template ~/dotfiles/php/conf.d/custom.ini.local

# Edit with machine-specific settings
vim ~/dotfiles/php/conf.d/custom.ini.local

# Example: Higher memory for powerful desktop
# memory_limit = 2048M

# Re-run setup to symlink local file
~/dotfiles/scripts/php-setup.sh

# Restart PHP
brew services restart php
```

**Loading order:**
1. PHP's default `php.ini`
2. `conf.d/99-custom.ini` (your shared settings)
3. `conf.d/99-custom-local.ini` (machine-specific overrides)

> **Tip:** To find your PHP version: `php -v` or `brew list | grep php`

---

## PECL Extension Management

### Listing Current Extensions

```bash
# List installed PECL extensions
~/dotfiles/scripts/php-extensions.sh list

# Or use PECL directly
pecl list
```

### Tracking Your Extensions

Before upgrading PHP, backup your current extensions:

```bash
# Backup current extensions to extensions.list
~/dotfiles/scripts/php-extensions.sh backup

# Commit to dotfiles
cd ~/dotfiles
git add php/extensions.list
git commit -m "feat(php): update extension list"
git push
```

### Installing Extensions

```bash
# Edit the extensions list
vim ~/dotfiles/php/extensions.list

# Add extensions (one per line):
# redis
# imagick
# xdebug@3.2.0  # Can specify version

# Install all extensions from list
~/dotfiles/scripts/php-extensions.sh install

# Restart PHP
brew services restart php
```

### After PHP Upgrade

```bash
# Reinstall all extensions (useful after PHP upgrade)
~/dotfiles/scripts/php-extensions.sh reinstall

# This will:
# 1. Read extensions from extensions.list
# 2. Uninstall each extension (if exists)
# 3. Reinstall fresh version
# 4. Report success/failures

# Restart PHP
brew services restart php
```

---

## Common Workflows

### Fresh Machine Setup

```bash
# 1. Clone and install dotfiles
git clone https://github.com/your-repo.git ~/.dotfiles
~/.dotfiles/install.sh

# 2. PHP configuration is automatically set up

# 3. Install PECL extensions
~/.dotfiles/scripts/php-extensions.sh install

# 4. Restart PHP
brew services restart php
```

### After `brew upgrade php`

```bash
# 1. Configuration files are still linked ✓
#    (no action needed)

# 2. Reinstall PECL extensions
~/dotfiles/scripts/php-extensions.sh reinstall

# 3. Restart PHP
brew services restart php

# 4. Verify
php --ini
pecl list
```

### Switching PHP Versions

If you need to switch between PHP versions:

```bash
# 1. Unlink current version
brew unlink php  # or brew unlink php@8.2

# 2. Install and link new version
brew install php@8.3
brew link php@8.3 --force --overwrite

# 3. Verify new version
php -v

# 4. Re-run PHP setup (detects new version automatically)
~/dotfiles/scripts/php-setup.sh

# 5. Reinstall extensions
~/dotfiles/scripts/php-extensions.sh reinstall

# 6. Update Brewfile to track the new version
cd ~/dotfiles
vim brew/Brewfile
# Change: brew "php@X.Y" to your new version

# 7. Restart PHP with new version
brew services restart php@8.3
```

> **Note:** The setup scripts auto-detect your active PHP version, so you don't need to modify any dotfiles configuration when switching versions.

---

## How It Works

### Configuration Files

PHP loads `.ini` files from multiple locations in this order:

1. **Main php.ini**: `$(brew --prefix)/etc/php/X.Y/php.ini`
2. **Additional configs**: `$(brew --prefix)/etc/php/X.Y/conf.d/*.ini` (sorted alphabetically)

Our approach:
- We **don't modify** the main `php.ini` (gets overwritten on updates)
- We **symlink** custom `.ini` files into `conf.d/`
- Files are prefixed with `99-` to load last (override defaults)

```
~/.dotfiles/php/conf.d/custom.ini
  ↓ symlink
$(brew --prefix)/etc/php/X.Y/conf.d/99-custom.ini
  ↑ loaded by PHP automatically
```

> **Note:** `X.Y` represents your PHP version (e.g., 8.2, 8.3, 8.4). The scripts auto-detect your current version.

**Why this works:**
- Homebrew updates replace `php.ini` but preserve `conf.d/` symlinks
- Settings in `conf.d/*.ini` override main `php.ini`
- Dotfiles remain version-controlled and portable

### Extension Tracking

PECL extensions are installed **per PHP version** and must be reinstalled after upgrades.

Our approach:
- Track desired extensions in `extensions.list` (version-controlled)
- Provide scripts to batch install/reinstall extensions
- Automatic backup before changes

```
extensions.list (git-tracked)
  ↓ read by script
php-extensions.sh
  ↓ uses pecl
Installed extensions
```

---

## Scripts Reference

### php-setup.sh

Manages symlinking custom `.ini` files to PHP's `conf.d` directory.

```bash
# Set up PHP configuration
~/dotfiles/scripts/php-setup.sh

# Preview changes without making them
~/dotfiles/scripts/php-setup.sh --dry-run

# Remove symlinks
~/dotfiles/scripts/php-setup.sh --uninstall

# Show help
~/dotfiles/scripts/php-setup.sh --help
```

**What it does:**
- Detects current PHP version
- Creates symlinks from dotfiles to `conf.d/`
- Backs up existing files before replacing
- Supports both shared and local configuration files

### php-extensions.sh

Manages PECL extensions based on `extensions.list`.

```bash
# List currently installed extensions
~/dotfiles/scripts/php-extensions.sh list

# Backup current extensions to list
~/dotfiles/scripts/php-extensions.sh backup

# Install extensions from list
~/dotfiles/scripts/php-extensions.sh install

# Reinstall all extensions (after PHP upgrade)
~/dotfiles/scripts/php-extensions.sh reinstall

# Show help
~/dotfiles/scripts/php-extensions.sh --help
```

**What it does:**
- Reads `extensions.list` (ignores comments and empty lines)
- Installs/reinstalls PECL extensions
- Handles version-pinned extensions (`redis@5.3.7`)
- Creates backups before modifying extensions list

---

## Troubleshooting

### Configuration not loading

```bash
# Check which php.ini files are loaded
php --ini

# You should see:
# Configuration File (php.ini) Path: /opt/homebrew/etc/php/X.Y
# Loaded Configuration File:         /opt/homebrew/etc/php/X.Y/php.ini
# Scan for additional .ini files in: /opt/homebrew/etc/php/X.Y/conf.d
# Additional .ini files parsed:      /opt/homebrew/etc/php/X.Y/conf.d/99-custom.ini

# If 99-custom.ini is missing, re-run setup
~/dotfiles/scripts/php-setup.sh
```

### Settings not applying

```bash
# Restart PHP-FPM service
brew services restart php

# Or restart manually
brew services stop php
brew services start php

# Check specific setting
php -i | grep memory_limit
```

### Extensions not found after upgrade

```bash
# List currently installed extensions
pecl list

# If empty, reinstall from tracked list
~/dotfiles/scripts/php-extensions.sh reinstall

# If reinstall fails, check PHP development tools
brew list | grep php
brew reinstall php  # Ensure development headers are present

# Restart PHP
brew services restart php
```

### Symlink already exists

```bash
# Get your PHP version
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')

# Check what the symlink points to
ls -la $(brew --prefix)/etc/php/$PHP_VER/conf.d/99-custom.ini

# If it points to wrong location, re-run setup
~/dotfiles/scripts/php-setup.sh

# It will backup and recreate the symlink
```

### PECL command not found

```bash
# PECL comes with PHP, verify PHP installation
brew list | grep php
php --version

# Reinstall PHP if needed
brew reinstall php

# Add PHP to PATH (should be in .zprofile via Homebrew)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
```

---

## Advanced Usage

### Xdebug Configuration

For debugging PHP applications:

```bash
# Add xdebug to extensions.list
echo "xdebug" >> ~/dotfiles/php/extensions.list

# Install it
~/dotfiles/scripts/php-extensions.sh install

# Configure in custom.ini.local
echo "; Xdebug configuration
xdebug.mode = debug
xdebug.start_with_request = yes
xdebug.client_host = localhost
xdebug.client_port = 9003
xdebug.idekey = VSCODE" >> ~/dotfiles/php/conf.d/custom.ini.local

# Re-run setup
~/dotfiles/scripts/php-setup.sh

# Restart PHP
brew services restart php

# Verify
php -v  # Should show "with Xdebug"
```

### Multiple PHP Versions

Run different PHP versions side-by-side:

```bash
# Install multiple versions
brew install php@8.1 php@8.2 php@8.3

# Switch between versions
brew unlink php@8.2 && brew link php@8.3 --force --overwrite

# Verify active version
php -v

# Re-run setup for new version (auto-detects active version)
~/dotfiles/scripts/php-setup.sh

# Reinstall extensions
~/dotfiles/scripts/php-extensions.sh reinstall

# Or use specific versions directly
/opt/homebrew/opt/php@8.2/bin/php -v
/opt/homebrew/opt/php@8.3/bin/php -v
```

### Production vs Development Settings

Use `custom.ini.local` for environment-specific settings:

**Development machine:**
```ini
; custom.ini.local (development)
display_errors = On
error_reporting = E_ALL
xdebug.mode = debug
memory_limit = 2048M
```

**Production machine:**
```ini
; custom.ini.local (production)
display_errors = Off
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
opcache.validate_timestamps = 0
memory_limit = 512M
```

---

## Files Summary

### Git-Tracked Files (shared across machines)

- `php/conf.d/custom.ini` - Main PHP configuration
- `php/conf.d/custom.ini.template` - Template for local overrides
- `php/extensions.list` - PECL extensions to install
- `scripts/php-setup.sh` - Configuration setup script
- `scripts/php-extensions.sh` - Extension management script

### Git-Ignored Files (machine-specific)

- `php/conf.d/custom.ini.local` - Local machine overrides
- `php/extensions.list.backup.*` - Extension list backups

### Symlinks (created automatically)

- `$(brew --prefix)/etc/php/X.Y/conf.d/99-custom.ini` → `~/dotfiles/php/conf.d/custom.ini`
- `$(brew --prefix)/etc/php/X.Y/conf.d/99-custom-local.ini` → `~/dotfiles/php/conf.d/custom.ini.local`

Where `X.Y` is your current PHP version (e.g., 8.2, 8.3, 8.4)

---

## Integration with Dotfiles

### Automatic Setup

PHP configuration is automatically set up during `install.sh`:

```bash
# install.sh includes:
setup_php() {
    if command -v php &> /dev/null; then
        ~/dotfiles/scripts/php-setup.sh
    fi
}
```

### Manual Setup

If you skip it during installation or install PHP later:

```bash
# Install PHP (latest version or specific version)
brew install php          # Latest
# or
brew install php@8.3      # Specific version

# Set up configuration
~/dotfiles/scripts/php-setup.sh

# Install extensions
~/dotfiles/scripts/php-extensions.sh install

# Restart PHP
brew services restart php
```

---

## Best Practices

1. **Always backup before upgrading:**
   ```bash
   ~/dotfiles/scripts/php-extensions.sh backup
   git commit -am "feat(php): backup extensions before upgrade"
   ```

2. **Test configuration changes:**
   ```bash
   php -i | grep memory_limit  # Verify specific setting
   php --ini                   # Check loaded files
   ```

3. **Use version control:**
   ```bash
   # Track changes to custom.ini
   git diff php/conf.d/custom.ini
   git commit -m "feat(php): increase memory limit"
   ```

4. **Document machine-specific settings:**
   Add comments to `custom.ini.local` explaining why settings differ.

5. **Restart after changes:**
   Always restart PHP after modifying configuration:
   ```bash
   brew services restart php
   ```

---

## See Also

- [Homebrew PHP Documentation](https://formulae.brew.sh/formula/php)
- [PHP Configuration Documentation](https://www.php.net/manual/en/configuration.file.php)
- [PECL Package Repository](https://pecl.php.net/)
- Main README: `~/dotfiles/README.md`
- Brewfile management: `~/dotfiles/brew/README.md`
