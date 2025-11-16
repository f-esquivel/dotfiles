#!/usr/bin/env bash
# =============================================================================
# Update Script for Dotfiles
# =============================================================================
# Updates all components: dotfiles repo, Homebrew, Zim, and system packages

set -e

# Detect dotfiles directory dynamically
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
# Update Functions
# =============================================================================

update_dotfiles() {
    info "Updating dotfiles repository..."

    cd "$DOTFILES_DIR" || exit 1

    # Check if we have uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warn "You have uncommitted changes in your dotfiles"
        read -p "Stash changes and continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git stash
            info "Changes stashed"
        else
            info "Skipping dotfiles update"
            return 0
        fi
    fi

    # Pull latest changes
    if git pull --rebase; then
        success "Dotfiles updated"
    else
        error "Failed to update dotfiles"
        return 1
    fi
}

update_homebrew() {
    info "Updating Homebrew and packages..."

    if ! command -v brew &> /dev/null; then
        warn "Homebrew not installed, skipping"
        return 0
    fi

    # Update Homebrew itself
    brew update

    # Upgrade all packages
    info "Upgrading installed packages..."
    brew upgrade

    # Upgrade casks
    info "Upgrading casks..."
    brew upgrade --cask --greedy

    # Clean up old versions
    info "Cleaning up old versions..."
    brew cleanup

    # Run diagnostics
    info "Running diagnostics..."
    brew doctor || warn "Brew doctor found some issues (non-critical)"

    success "Homebrew updated"
}

update_brewfile() {
    info "Updating Brewfile..."

    if [ ! -f "$DOTFILES_DIR/brew/Brewfile" ]; then
        warn "Brewfile not found, skipping"
        return 0
    fi

    # Install any new packages from Brewfile
    brew bundle install --file="$DOTFILES_DIR/brew/Brewfile"

    # Install from local Brewfile if it exists
    if [ -f "$DOTFILES_DIR/brew/Brewfile.local" ]; then
        brew bundle install --file="$DOTFILES_DIR/brew/Brewfile.local"
    fi

    success "Brewfile packages installed"
}

update_zim() {
    info "Updating Zim and plugins..."

    if [ ! -d "${HOME}/.zim" ]; then
        warn "Zim not installed, skipping"
        return 0
    fi

    if command -v zsh &> /dev/null; then
        # Update Zim framework
        zsh -c "source ${HOME}/.zim/zimfw.zsh upgrade" || warn "Zim upgrade had issues"

        # Update Zim modules
        zsh -c "source ${HOME}/.zim/zimfw.zsh update" || warn "Zim module update had issues"

        success "Zim updated"
    else
        warn "Zsh not available, skipping Zim update"
    fi
}

update_npm_global() {
    info "Updating global NPM packages..."

    if ! command -v npm &> /dev/null; then
        warn "NPM not installed, skipping"
        return 0
    fi

    npm update -g
    success "Global NPM packages updated"
}

update_macos() {
    info "Checking for macOS updates..."

    if [[ "$OSTYPE" != "darwin"* ]]; then
        warn "Not on macOS, skipping"
        return 0
    fi

    # Check for updates
    softwareupdate --list

    read -p "Install macOS updates? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo softwareupdate --install --all
        success "macOS updated"
    else
        info "Skipping macOS updates"
    fi
}

# =============================================================================
# Main Update Flow
# =============================================================================

main() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║   Dotfiles Update Script              ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""

    # Parse command line arguments
    SKIP_DOTFILES=false
    SKIP_BREW=false
    SKIP_ZIM=false
    SKIP_NPM=false
    SKIP_MACOS=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-dotfiles)
                SKIP_DOTFILES=true
                shift
                ;;
            --skip-brew)
                SKIP_BREW=true
                shift
                ;;
            --skip-zim)
                SKIP_ZIM=true
                shift
                ;;
            --skip-npm)
                SKIP_NPM=true
                shift
                ;;
            --skip-macos)
                SKIP_MACOS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-dotfiles   Skip dotfiles git update"
                echo "  --skip-brew       Skip Homebrew updates"
                echo "  --skip-zim        Skip Zim updates"
                echo "  --skip-npm        Skip NPM global updates"
                echo "  --skip-macos      Skip macOS system updates"
                echo "  --help, -h        Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Run updates
    if [ "$SKIP_DOTFILES" = false ]; then
        update_dotfiles
        echo ""
    fi

    if [ "$SKIP_BREW" = false ]; then
        update_homebrew
        echo ""
        update_brewfile
        echo ""
    fi

    if [ "$SKIP_ZIM" = false ]; then
        update_zim
        echo ""
    fi

    if [ "$SKIP_NPM" = false ]; then
        update_npm_global
        echo ""
    fi

    if [ "$SKIP_MACOS" = false ]; then
        update_macos
        echo ""
    fi

    # Final message
    echo "╔═══════════════════════════════════════╗"
    echo "║   Update Complete! 🎉                 ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    success "All components updated successfully!"
    echo ""
    info "Tips:"
    echo "  - Restart your terminal to apply all changes"
    echo "  - Run 'brew doctor' if you encounter issues"
    echo "  - Check for breaking changes in updated packages"
    echo ""
}

# Run main function
main "$@"
