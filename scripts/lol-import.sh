#!/usr/bin/env bash
# =============================================================================
# League of Legends Config Import Script
# =============================================================================
# Imports keybindings and game settings from dotfiles to LoL installation

set -e

# Detect dotfiles directory dynamically
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOL_DOTFILES_DIR="$DOTFILES_DIR/games/lol"

# Flags
DRY_RUN=false
SKIP_BACKUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run      Show what would be done without making changes"
            echo "  --skip-backup  Don't backup existing config files"
            echo "  --help, -h     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# =============================================================================
# Find League of Legends Installation
# =============================================================================

find_lol_config() {
    # Common LoL config locations on macOS
    # The actual game config is in the .app bundle
    local config_paths=(
        "/Applications/League of Legends.app/Contents/LoL/Config"
        "$HOME/Library/Application Support/Riot Games/League of Legends/Config"
        "$HOME/Library/Preferences/Riot Games/League of Legends/Config"
    )

    for path in "${config_paths[@]}"; do
        if [ -d "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

# =============================================================================
# Import Configuration Files
# =============================================================================

import_configs() {
    info "Searching for League of Legends installation..."

    local lol_config_dir
    if ! lol_config_dir=$(find_lol_config); then
        error "League of Legends config directory not found!"
        echo ""
        info "Expected locations:"
        echo "  - /Applications/League of Legends.app/Contents/LoL/Config"
        echo "  - ~/Library/Application Support/Riot Games/League of Legends/Config"
        echo ""
        error "Make sure League of Legends is installed and you've launched it at least once."
        exit 1
    fi

    success "Found LoL config at: $lol_config_dir"
    echo ""

    # Check if we have exported configs
    if [ ! -d "$LOL_DOTFILES_DIR" ] || [ -z "$(ls -A "$LOL_DOTFILES_DIR" 2>/dev/null)" ]; then
        error "No exported LoL configs found in: $LOL_DOTFILES_DIR"
        echo ""
        info "Run the export script first:"
        echo "  $DOTFILES_DIR/scripts/lol-export.sh"
        exit 1
    fi

    # Create backup directory with timestamp
    local backup_dir="$HOME/.lol-config-backup-$(date +%Y%m%d_%H%M%S)"

    info "Importing configuration files..."
    echo ""

    local imported=0
    local skipped=0

    # Find all config files in dotfiles
    while IFS= read -r -d '' source_file; do
        local filename=$(basename "$source_file")

        # Skip metadata and backup files
        if [[ "$filename" == "export-info.txt" ]] || [[ "$filename" == backup-* ]]; then
            continue
        fi

        local dest_file="$lol_config_dir/$filename"

        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would import: $filename"
            ((imported++))
            continue
        fi

        # Backup existing file
        if [ -f "$dest_file" ] && [ "$SKIP_BACKUP" = false ]; then
            mkdir -p "$backup_dir"
            cp "$dest_file" "$backup_dir/"
            info "Backed up: $filename"
        fi

        # Copy config file
        cp "$source_file" "$dest_file"
        success "Imported: $filename"
        ((imported++))

    done < <(find "$LOL_DOTFILES_DIR" -maxdepth 1 -type f -print0)

    echo ""

    if [ "$DRY_RUN" = true ]; then
        info "Dry Run Summary:"
        echo "  ⊙ Would import: $imported files"
        echo ""
        info "Run without --dry-run to perform the import"
    else
        info "Import Summary:"
        echo "  ✓ Imported: $imported files"
        if [ -d "$backup_dir" ]; then
            echo "  💾 Backup: $backup_dir"
        fi
        echo ""
        success "Configuration imported to: $lol_config_dir"
        echo ""
        info "Next steps:"
        echo "  1. Launch League of Legends"
        echo "  2. Verify your keybindings and settings"
        echo "  3. If something went wrong, restore from: $backup_dir"
    fi
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    if [ "$DRY_RUN" = true ]; then
        echo "╔═══════════════════════════════════════╗"
        echo "║   LoL Config Import (DRY RUN)         ║"
        echo "╚═══════════════════════════════════════╝"
    else
        echo "╔═══════════════════════════════════════╗"
        echo "║   League of Legends Config Import     ║"
        echo "╚═══════════════════════════════════════╝"
    fi
    echo ""

    # Import configs
    import_configs

    if [ "$DRY_RUN" = false ]; then
        echo "╔═══════════════════════════════════════╗"
        echo "║   Import Complete! 🎮                 ║"
        echo "╚═══════════════════════════════════════╝"
    fi
    echo ""
}

main
