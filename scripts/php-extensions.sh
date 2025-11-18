#!/usr/bin/env bash
# =============================================================================
# PHP PECL Extensions Manager
# =============================================================================
# Manages PECL extensions based on extensions.list file
# Helps restore extensions after PHP upgrades
#
# Usage:
#   ./php-extensions.sh install          # Install all listed extensions
#   ./php-extensions.sh list             # List currently installed extensions
#   ./php-extensions.sh backup           # Backup current extensions to list
#   ./php-extensions.sh reinstall        # Reinstall all listed extensions
#   ./php-extensions.sh --help           # Show help
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

# Determine dotfiles directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
EXTENSIONS_FILE="$DOTFILES_DIR/php/extensions.list"

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

show_help() {
    cat << EOF
PHP PECL Extensions Manager

Usage:
    $(basename "$0") <command>

Commands:
    install          Install all extensions listed in extensions.list
    list             List currently installed PECL extensions
    backup           Backup currently installed extensions to extensions.list
    reinstall        Reinstall all extensions (useful after PHP upgrade)
    --help, -h       Show this help message

Examples:
    # List current extensions
    $(basename "$0") list

    # Backup current extensions to track them
    $(basename "$0") backup

    # After PHP upgrade, reinstall all extensions
    $(basename "$0") reinstall

    # Install new extensions from list
    $(basename "$0") install

Files:
    Extensions list: $EXTENSIONS_FILE
    Custom PHP ini:  $DOTFILES_DIR/php/conf.d/custom.ini

Notes:
    - Edit extensions.list to add/remove extensions
    - Lines starting with # are ignored (comments)
    - Inline comments are supported (e.g., "redis  # Redis client")
    - Format: extension_name or extension_name@version
    - After installing extensions, restart PHP:
      brew services restart php

EOF
}

# Read extensions from file (skip comments and empty lines, strip inline comments)
read_extensions() {
    if [[ ! -f "$EXTENSIONS_FILE" ]]; then
        error "Extensions file not found: $EXTENSIONS_FILE"
        exit 1
    fi

    # Skip lines starting with #, remove inline comments, trim whitespace, skip empty lines
    grep -v '^[[:space:]]*#' "$EXTENSIONS_FILE" | \
        sed 's/#.*//' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        grep -v '^[[:space:]]*$' || true
}

# List currently installed PECL extensions
list_extensions() {
    info "Currently installed PECL extensions:"
    echo ""

    if command -v pecl &> /dev/null; then
        pecl list
    else
        error "PECL not found. Is PHP installed?"
        exit 1
    fi
}

# Backup current extensions to list file
backup_extensions() {
    info "Backing up current PECL extensions to $EXTENSIONS_FILE"

    if ! command -v pecl &> /dev/null; then
        error "PECL not found. Is PHP installed?"
        exit 1
    fi

    # Create backup
    local backup_file="${EXTENSIONS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    if [[ -f "$EXTENSIONS_FILE" ]]; then
        cp "$EXTENSIONS_FILE" "$backup_file"
        info "Created backup: $backup_file"
    fi

    # Get current extensions (skip header lines)
    local extensions=$(pecl list | tail -n +4 | awk '{print $1}' | grep -v '^$' || true)

    if [[ -z "$extensions" ]]; then
        warn "No PECL extensions currently installed"
        return
    fi

    # Preserve file header
    local temp_file=$(mktemp)
    head -n 15 "$EXTENSIONS_FILE" > "$temp_file"

    echo "" >> "$temp_file"
    echo "# Backed up on $(date '+%Y-%m-%d %H:%M:%S')" >> "$temp_file"
    echo "$extensions" >> "$temp_file"

    mv "$temp_file" "$EXTENSIONS_FILE"

    success "Backed up extensions to $EXTENSIONS_FILE"
    echo ""
    echo "Extensions backed up:"
    echo "$extensions" | sed 's/^/  - /'
}

# Install extensions from list
install_extensions() {
    local extensions=$(read_extensions)

    if [[ -z "$extensions" ]]; then
        warn "No extensions listed in $EXTENSIONS_FILE"
        echo ""
        echo "Add extensions to the file (one per line), for example:"
        echo "  redis"
        echo "  imagick"
        echo "  xdebug"
        return
    fi

    info "Installing PECL extensions from $EXTENSIONS_FILE"
    echo ""

    while IFS= read -r extension; do
        if [[ -n "$extension" ]]; then
            info "Installing: $extension"

            # Check if already installed
            if pecl list | grep -q "^${extension%%@*}"; then
                warn "Already installed: ${extension%%@*}"
            else
                # Redirect stdin from /dev/null to prevent PECL from reading our extension list
                # This avoids PECL using next extensions as answers to interactive prompts
                if pecl install "$extension" </dev/null; then
                    success "Installed: $extension"
                else
                    error "Failed to install: $extension"
                fi
            fi
            echo ""
        fi
    done <<< "$extensions"

    success "Extension installation complete"
    echo ""
    warn "Remember to restart PHP: brew services restart php"
}

# Reinstall extensions (useful after PHP upgrade)
reinstall_extensions() {
    local extensions=$(read_extensions)

    if [[ -z "$extensions" ]]; then
        warn "No extensions listed in $EXTENSIONS_FILE"
        return
    fi

    info "Reinstalling PECL extensions from $EXTENSIONS_FILE"
    echo ""
    warn "This will reinstall all extensions (useful after PHP upgrade)"
    echo ""

    while IFS= read -r extension; do
        if [[ -n "$extension" ]]; then
            info "Reinstalling: $extension"

            # Uninstall if exists (ignore errors)
            pecl uninstall "${extension%%@*}" 2>/dev/null || true

            # Install - redirect stdin from /dev/null to prevent interactive prompts
            if pecl install "$extension" </dev/null; then
                success "Reinstalled: $extension"
            else
                error "Failed to reinstall: $extension"
            fi
            echo ""
        fi
    done <<< "$extensions"

    success "Extension reinstallation complete"
    echo ""
    warn "Remember to restart PHP: brew services restart php"
}

# Main command handler
main() {
    case "${1:-}" in
        install)
            install_extensions
            ;;
        list)
            list_extensions
            ;;
        backup)
            backup_extensions
            ;;
        reinstall)
            reinstall_extensions
            ;;
        --help|-h|help)
            show_help
            ;;
        *)
            error "Unknown command: ${1:-}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
