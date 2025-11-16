#!/usr/bin/env bash
# =============================================================================
# League of Legends Config Export Script
# =============================================================================
# Exports keybindings and game settings from LoL installation to dotfiles

set -e

# Detect dotfiles directory dynamically
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOL_DOTFILES_DIR="$DOTFILES_DIR/games/lol"

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
# Export Configuration Files
# =============================================================================

export_configs() {
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

    # Create backup directory with timestamp
    local backup_dir="$LOL_DOTFILES_DIR/backup-$(date +%Y%m%d_%H%M%S)"

    # Important config files to export
    local config_files=(
        "PersistedSettings.json"      # Keybindings, game settings, interface
        "game.cfg"                    # Game configuration
        "input.ini"                   # Input settings
        "LCUAccountPreferences.yaml"  # Account preferences (HUD, etc.)
        "PerksPreferences.yaml"       # Runes/perks preferences
        "ItemSets.json"               # Custom item sets
    )

    info "Exporting configuration files..."
    echo ""

    local exported=0
    local skipped=0

    for config_file in "${config_files[@]}"; do
        local source_file="$lol_config_dir/$config_file"
        local dest_file="$LOL_DOTFILES_DIR/$config_file"

        if [ -f "$source_file" ]; then
            # Backup existing file if it exists
            if [ -f "$dest_file" ]; then
                mkdir -p "$backup_dir"
                cp "$dest_file" "$backup_dir/"
                info "Backed up existing: $config_file"
            fi

            # Copy the config file
            cp "$source_file" "$dest_file"
            success "Exported: $config_file"
            ((exported++))
        else
            warn "Not found: $config_file (skipping)"
            ((skipped++))
        fi
    done

    echo ""
    info "Export Summary:"
    echo "  ✓ Exported: $exported files"
    if [ $skipped -gt 0 ]; then
        echo "  ⊘ Skipped: $skipped files (not found)"
    fi
    if [ -d "$backup_dir" ]; then
        echo "  💾 Backup: $backup_dir"
    fi
    echo ""

    # Create metadata file
    cat > "$LOL_DOTFILES_DIR/export-info.txt" <<EOF
Export Date: $(date)
Source: $lol_config_dir

Files exported:
EOF

    for config_file in "${config_files[@]}"; do
        if [ -f "$LOL_DOTFILES_DIR/$config_file" ]; then
            echo "  - $config_file" >> "$LOL_DOTFILES_DIR/export-info.txt"
        fi
    done

    success "Configuration exported to: $LOL_DOTFILES_DIR"
    echo ""
    info "Next steps:"
    echo "  1. Review the exported configs: ls -la $LOL_DOTFILES_DIR"
    echo "  2. Commit to git: cd $DOTFILES_DIR && git add games/ && git commit -m 'Update LoL configs'"
    echo "  3. Restore on another machine: $DOTFILES_DIR/scripts/lol-import.sh"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║   League of Legends Config Export     ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""

    # Create destination directory if it doesn't exist
    mkdir -p "$LOL_DOTFILES_DIR"

    # Export configs
    export_configs

    echo "╔═══════════════════════════════════════╗"
    echo "║   Export Complete! 🎮                 ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
}

main "$@"
