#!/usr/bin/env bash
# =============================================================================
# PHP Configuration Setup
# =============================================================================
# Sets up PHP custom configuration that survives Homebrew updates
# Creates symlinks from dotfiles to PHP's conf.d directory
#
# Usage:
#   ./php-setup.sh                # Set up PHP configuration
#   ./php-setup.sh --dry-run      # Preview changes without making them
#   ./php-setup.sh --uninstall    # Remove symlinks
# =============================================================================

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Emojis
INFO="ℹ️"
SUCCESS="✅"
WARNING="⚠️"
ERROR="❌"

# Configuration
DRY_RUN=false
UNINSTALL=false

# Determine dotfiles directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
PHP_CONF_DIR="$DOTFILES_DIR/php/conf.d"

# Helper functions
info() {
    echo -e "${BLUE}${INFO} $1${NC}"
}

success() {
    echo -e "${GREEN}${SUCCESS} $1${NC}"
}

warn() {
    echo -e "${YELLOW}${WARNING} $1${NC}"
}

error() {
    echo -e "${RED}${ERROR} $1${NC}"
}

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --help|-h)
            cat << EOF
PHP Configuration Setup

Usage:
    $(basename "$0") [options]

Options:
    --dry-run       Preview changes without making them
    --uninstall     Remove symlinks and restore original state
    --help, -h      Show this help message

Description:
    This script manages PHP custom configuration that survives Homebrew updates
    by symlinking custom .ini files to PHP's conf.d directory.

Files:
    Source:      $PHP_CONF_DIR/custom.ini
    Destination: \$(brew --prefix)/etc/php/X.Y/conf.d/99-custom.ini
                 (where X.Y is your PHP version, auto-detected)

After Setup:
    - Edit: $PHP_CONF_DIR/custom.ini
    - Restart PHP: brew services restart php
    - View config: php --ini

EOF
            exit 0
            ;;
        *)
            error "Unknown option: $arg"
            exit 1
            ;;
    esac
done

if $DRY_RUN; then
    warn "DRY RUN MODE - No changes will be made"
    echo ""
fi

# Detect PHP version and conf.d directory
detect_php() {
    if ! command -v php &> /dev/null; then
        error "PHP not found. Please install PHP first:"
        echo "  brew install php          # Latest version"
        echo "  brew install php@8.3      # Specific version"
        exit 1
    fi

    local php_version=$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')
    local brew_prefix=$(brew --prefix)
    local php_confd="$brew_prefix/etc/php/$php_version/conf.d"

    if [[ ! -d "$php_confd" ]]; then
        error "PHP conf.d directory not found: $php_confd"
        exit 1
    fi

    echo "$php_confd"
}

# Create symlink for custom ini file
setup_custom_ini() {
    local php_confd=$(detect_php)
    local source_file="$PHP_CONF_DIR/custom.ini"
    local dest_file="$php_confd/99-custom.ini"

    info "Setting up custom PHP configuration"
    echo "  Source: $source_file"
    echo "  Destination: $dest_file"
    echo ""

    if [[ ! -f "$source_file" ]]; then
        error "Source file not found: $source_file"
        exit 1
    fi

    # Check if destination already exists
    if [[ -e "$dest_file" ]]; then
        if [[ -L "$dest_file" ]]; then
            local current_target=$(readlink "$dest_file")
            if [[ "$current_target" == "$source_file" ]]; then
                success "Symlink already correctly set up"
                return 0
            else
                warn "Symlink exists but points to: $current_target"
                if $DRY_RUN; then
                    info "Would remove and recreate symlink"
                else
                    rm "$dest_file"
                    info "Removed old symlink"
                fi
            fi
        else
            warn "File exists and is not a symlink"
            if $DRY_RUN; then
                info "Would backup and replace: $dest_file"
            else
                local backup="$dest_file.backup.$(date +%Y%m%d_%H%M%S)"
                mv "$dest_file" "$backup"
                info "Backed up to: $backup"
            fi
        fi
    fi

    # Create symlink
    if $DRY_RUN; then
        info "Would create symlink: $dest_file -> $source_file"
    else
        ln -s "$source_file" "$dest_file"
        success "Created symlink: $dest_file -> $source_file"
    fi
}

# Setup local custom ini if it exists
setup_local_ini() {
    local php_confd=$(detect_php)
    local source_file="$PHP_CONF_DIR/custom.ini.local"
    local dest_file="$php_confd/99-custom-local.ini"

    if [[ ! -f "$source_file" ]]; then
        info "No custom.ini.local found (this is optional)"
        return 0
    fi

    info "Setting up local custom PHP configuration"
    echo "  Source: $source_file"
    echo "  Destination: $dest_file"
    echo ""

    # Check if destination already exists
    if [[ -e "$dest_file" ]]; then
        if [[ -L "$dest_file" ]]; then
            local current_target=$(readlink "$dest_file")
            if [[ "$current_target" == "$source_file" ]]; then
                success "Local symlink already correctly set up"
                return 0
            else
                if $DRY_RUN; then
                    info "Would remove and recreate local symlink"
                else
                    rm "$dest_file"
                fi
            fi
        else
            if $DRY_RUN; then
                info "Would backup and replace: $dest_file"
            else
                local backup="$dest_file.backup.$(date +%Y%m%d_%H%M%S)"
                mv "$dest_file" "$backup"
                info "Backed up to: $backup"
            fi
        fi
    fi

    # Create symlink
    if $DRY_RUN; then
        info "Would create local symlink: $dest_file -> $source_file"
    else
        ln -s "$source_file" "$dest_file"
        success "Created local symlink: $dest_file -> $source_file"
    fi
}

# Uninstall - remove symlinks
uninstall() {
    local php_confd=$(detect_php)
    local files=("$php_confd/99-custom.ini" "$php_confd/99-custom-local.ini")

    info "Uninstalling PHP custom configuration"
    echo ""

    for file in "${files[@]}"; do
        if [[ -L "$file" ]]; then
            if $DRY_RUN; then
                info "Would remove symlink: $file"
            else
                rm "$file"
                success "Removed symlink: $file"
            fi
        elif [[ -e "$file" ]]; then
            warn "File exists but is not a symlink (skipping): $file"
        fi
    done

    success "Uninstallation complete"
}

# Show PHP configuration info
show_info() {
    local php_confd=$(detect_php)

    echo ""
    info "PHP Configuration Info"
    echo ""
    echo "PHP Version: $(php -v | head -n 1)"
    echo "Configuration directory: $php_confd"
    echo ""
    echo "Custom configuration files in conf.d:"
    ls -lh "$php_confd"/99-custom* 2>/dev/null || echo "  (none found)"
    echo ""
    info "To view all PHP ini files: php --ini"
    info "To edit custom config: vim $PHP_CONF_DIR/custom.ini"
    info "After changes, restart PHP: brew services restart php"
}

# Main
main() {
    if $UNINSTALL; then
        uninstall
    else
        setup_custom_ini
        setup_local_ini

        if ! $DRY_RUN; then
            show_info
            echo ""
            warn "Remember to restart PHP to apply changes:"
            echo "  brew services restart php"
        fi
    fi
}

main
