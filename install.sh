#!/usr/bin/env bash
# =============================================================================
# Dotfiles Installation Script
# =============================================================================
# Bootstraps a new machine with dotfiles and all necessary tools

set -e

# Detect dotfiles directory dynamically (where this script is located)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"

# Flags
DRY_RUN=false
INTERACTIVE=false
SKIP_BACKUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --interactive|-i)
            INTERACTIVE=true
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
            echo "  --dry-run         Show what would be done without making changes"
            echo "  --interactive, -i Ask before overwriting existing files"
            echo "  --skip-backup     Don't create backups of existing files"
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
# Backup and Symlink Helper Functions
# =============================================================================

# Check if a path is already a symlink to our dotfiles
is_our_symlink() {
    local path="$1"
    local target="$2"

    if [ -L "$path" ]; then
        local current_target="$(readlink "$path")"
        if [ "$current_target" = "$target" ]; then
            return 0  # Already linked correctly
        fi
    fi
    return 1
}

# Backup a file or directory
backup_file() {
    local file="$1"

    if [ ! -e "$file" ] && [ ! -L "$file" ]; then
        return 0  # Nothing to backup
    fi

    if [ "$SKIP_BACKUP" = true ]; then
        warn "Skipping backup of $file (--skip-backup flag set)"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would backup: $file -> $BACKUP_DIR/$(basename "$file")"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    local backup_path="$BACKUP_DIR/$(basename "$file")"

    # Handle case where backup already exists
    if [ -e "$backup_path" ]; then
        backup_path="${backup_path}.$(date +%s)"
    fi

    cp -r "$file" "$backup_path"
    info "Backed up: $file -> $backup_path"
}

# Safely create a symlink with backup
safe_symlink() {
    local source="$1"
    local target="$2"
    local description="${3:-file}"

    # Check if already linked correctly
    if is_our_symlink "$target" "$source"; then
        success "$description is already linked correctly"
        return 0
    fi

    # Check if target exists
    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ "$INTERACTIVE" = true ]; then
            warn "$description already exists at: $target"
            read -p "Overwrite? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Skipping $description"
                return 0
            fi
        fi

        backup_file "$target"

        if [ "$DRY_RUN" = false ]; then
            rm -rf "$target"
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would link: $source -> $target"
    else
        ln -sf "$source" "$target"
        success "Linked $description"
    fi
}

# =============================================================================
# 1. Install Homebrew
# =============================================================================

install_homebrew() {
    info "Checking for Homebrew..."
    if command -v brew &> /dev/null; then
        success "Homebrew is already installed"
    else
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would install Homebrew"
        else
            info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

            # Set up Homebrew in PATH for Apple Silicon
            if [[ $(uname -m) == 'arm64' ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
            success "Homebrew installed"
        fi
    fi
}

# =============================================================================
# 2. Install Homebrew Packages
# =============================================================================

install_brew_packages() {
    info "Installing Homebrew packages..."

    if [ "$DRY_RUN" = true ]; then
        if [ -f "$DOTFILES_DIR/brew/Brewfile" ]; then
            info "[DRY RUN] Would install packages from Brewfile"
        fi
        if [ -f "$DOTFILES_DIR/brew/Brewfile.local" ]; then
            info "[DRY RUN] Would install packages from Brewfile.local"
        fi
        return 0
    fi

    if [ -f "$DOTFILES_DIR/brew/Brewfile" ]; then
        brew bundle install --file="$DOTFILES_DIR/brew/Brewfile"
        success "Main packages installed from Brewfile"
    else
        error "Brewfile not found at $DOTFILES_DIR/brew/Brewfile"
        return 1
    fi

    if [ -f "$DOTFILES_DIR/brew/Brewfile.local" ]; then
        brew bundle install --file="$DOTFILES_DIR/brew/Brewfile.local"
        success "Machine-specific packages installed from Brewfile.local"
    else
        warn "No Brewfile.local found. Skipping machine-specific packages."
    fi
}

# =============================================================================
# 3. Setup NVM Directory
# =============================================================================

setup_nvm() {
    info "Setting up NVM directory..."

    # Create NVM directory if it doesn't exist
    # This is required by NVM to store Node versions
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$HOME/.nvm"
        success "NVM directory created at ~/.nvm"
    else
        info "[DRY RUN] Would create ~/.nvm directory"
    fi
}

# =============================================================================
# 4. Setup Zsh Configuration
# =============================================================================

setup_zsh() {
    info "Setting up Zsh configuration..."

    # Symlink zsh configs
    safe_symlink "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc" ".zshrc"
    safe_symlink "$DOTFILES_DIR/zsh/.zprofile" "$HOME/.zprofile" ".zprofile"
    safe_symlink "$DOTFILES_DIR/zsh/.zimrc" "$HOME/.zimrc" ".zimrc"

    # Create .zshrc.secrets if it doesn't exist
    if [ ! -f "$DOTFILES_DIR/zsh/.zshrc.secrets" ]; then
        if [ "$DRY_RUN" = false ]; then
            cp "$DOTFILES_DIR/zsh/.zshrc.secrets.template" "$DOTFILES_DIR/zsh/.zshrc.secrets"
            warn "Created .zshrc.secrets from template. Please edit it with your API keys."
        else
            info "[DRY RUN] Would create .zshrc.secrets from template"
        fi
    fi

    if [ "$DRY_RUN" = false ]; then
        success "Zsh configuration linked"
    fi
}

# =============================================================================
# 5. Setup SSH Configuration
# =============================================================================

setup_ssh() {
    info "Setting up SSH configuration..."

    # Create .ssh directory if it doesn't exist
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    else
        info "[DRY RUN] Would create ~/.ssh directory"
    fi

    # Symlink SSH config
    safe_symlink "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config" "SSH config"

    # Create config.local if it doesn't exist
    if [ ! -f "$DOTFILES_DIR/ssh/config.local" ]; then
        if [ "$DRY_RUN" = false ]; then
            cp "$DOTFILES_DIR/ssh/config.local.template" "$DOTFILES_DIR/ssh/config.local"
            warn "Created ssh/config.local from template. Please edit it with your SSH key paths."
        else
            info "[DRY RUN] Would create ssh/config.local from template"
        fi
    fi

    if [ "$DRY_RUN" = false ]; then
        success "SSH configuration linked"
    fi
}

# =============================================================================
# 6. Setup Git Configuration
# =============================================================================

setup_git() {
    info "Setting up Git configuration..."

    # Symlink gitconfig
    safe_symlink "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig" ".gitconfig"

    if [ "$DRY_RUN" = false ]; then
        success "Git configuration linked"
    fi
}

# =============================================================================
# 7. Setup PHP Configuration
# =============================================================================

setup_php() {
    info "Setting up PHP configuration..."

    # Check if PHP is installed
    if ! command -v php &> /dev/null; then
        warn "PHP not installed. Skipping PHP configuration."
        warn "Install with: brew install php (or brew install php@X.Y for specific version)"
        return 0
    fi

    # Run the PHP setup script
    if [ -f "$DOTFILES_DIR/scripts/php-setup.sh" ]; then
        if [ "$DRY_RUN" = true ]; then
            "$DOTFILES_DIR/scripts/php-setup.sh" --dry-run
        else
            "$DOTFILES_DIR/scripts/php-setup.sh"
            success "PHP configuration linked"
        fi
    else
        warn "PHP setup script not found, skipping"
    fi
}

# =============================================================================
# 8. Setup Utility Files
# =============================================================================

setup_utils() {
    info "Setting up utility files..."

    # Symlink .hushlogin to suppress login messages
    if [ -f "$DOTFILES_DIR/utils/.hushlogin" ]; then
        safe_symlink "$DOTFILES_DIR/utils/.hushlogin" "$HOME/.hushlogin" ".hushlogin"
    fi

    # Symlink .npmrc for NPM configuration
    if [ -f "$DOTFILES_DIR/utils/.npmrc" ]; then
        safe_symlink "$DOTFILES_DIR/utils/.npmrc" "$HOME/.npmrc" ".npmrc"
    fi

    if [ "$DRY_RUN" = false ]; then
        success "Utility files configured"
    fi
}

# =============================================================================
# 9. Setup Husky (Git Hooks)
# =============================================================================

setup_husky() {
    info "Setting up Husky configuration..."

    # Create ~/.config/husky directory if it doesn't exist
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$HOME/.config/husky"
    else
        echo "[DRY RUN] Would create: $HOME/.config/husky"
    fi

    # Symlink init.sh for NVM loading in git hooks
    if [ -f "$DOTFILES_DIR/husky/init.sh" ]; then
        safe_symlink "$DOTFILES_DIR/husky/init.sh" "$HOME/.config/husky/init.sh" "husky/init.sh"
    fi

    if [ "$DRY_RUN" = false ]; then
        success "Husky configured"
    fi
}

# =============================================================================
# 10. Setup Ghostty Terminal
# =============================================================================

setup_ghostty() {
    info "Setting up Ghostty configuration..."

    # Create .config/ghostty directory if it doesn't exist
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$HOME/.config/ghostty"
    else
        info "[DRY RUN] Would create ~/.config/ghostty directory"
    fi

    # Symlink Ghostty config
    if [ -f "$DOTFILES_DIR/ghostty/config" ]; then
        safe_symlink "$DOTFILES_DIR/ghostty/config" "$HOME/.config/ghostty/config" "Ghostty config"
        if [ "$DRY_RUN" = false ]; then
            success "Ghostty configuration linked"
        fi
    else
        warn "Ghostty config not found, skipping"
    fi
}

# =============================================================================
# 11. Setup Claude Code
# =============================================================================

setup_claude_code() {
    info "Setting up Claude Code configuration..."

    # Create ~/.claude directory if it doesn't exist
    # Note: Don't symlink the entire directory - it contains runtime data
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$HOME/.claude"
    else
        info "[DRY RUN] Would create ~/.claude directory"
    fi

    # Symlink global settings.json
    if [ -f "$DOTFILES_DIR/claude/settings.json" ]; then
        safe_symlink "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json" "Claude Code settings"
    else
        warn "Claude Code settings.json not found, skipping"
    fi

    # Symlink global CLAUDE.md
    if [ -f "$DOTFILES_DIR/claude/CLAUDE.md" ]; then
        safe_symlink "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "Claude Code global instructions"
    fi

    # Symlink global commands directory
    if [ -d "$DOTFILES_DIR/claude/commands" ]; then
        safe_symlink "$DOTFILES_DIR/claude/commands" "$HOME/.claude/commands" "Claude Code global commands"
    fi

    if [ "$DRY_RUN" = false ]; then
        success "Claude Code configuration linked"
    fi
}

# =============================================================================
# 12. Setup JetBrains Toolbox
# =============================================================================

setup_jetbrains() {
    info "Setting up JetBrains Toolbox configuration..."

    # Create JetBrains Toolbox config directory if it doesn't exist
    local toolbox_config_dir="$HOME/Library/Application Support/JetBrains/Toolbox"

    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$toolbox_config_dir"
        # Create ~/.local/bin for shell scripts (user-owned, no sudo needed)
        mkdir -p "$HOME/.local/bin"
    else
        info "[DRY RUN] Would create $toolbox_config_dir directory"
        info "[DRY RUN] Would create ~/.local/bin directory"
    fi

    # Create .settings.json from template if it doesn't exist
    if [ ! -f "$DOTFILES_DIR/jetbrains/.settings.json" ]; then
        if [ "$DRY_RUN" = false ]; then
            if [ -f "$DOTFILES_DIR/jetbrains/.settings.json.template" ]; then
                cp "$DOTFILES_DIR/jetbrains/.settings.json.template" "$DOTFILES_DIR/jetbrains/.settings.json"
                info "Created .settings.json from template"
                warn "JetBrains Toolbox will add your account info when you sign in"
            else
                warn "JetBrains Toolbox template not found, skipping"
                return 0
            fi
        else
            info "[DRY RUN] Would create .settings.json from template"
        fi
    fi

    # Symlink JetBrains Toolbox settings
    if [ -f "$DOTFILES_DIR/jetbrains/.settings.json" ]; then
        safe_symlink "$DOTFILES_DIR/jetbrains/.settings.json" "$toolbox_config_dir/.settings.json" "JetBrains Toolbox settings"

        if [ "$DRY_RUN" = false ]; then
            success "JetBrains Toolbox configuration linked"
            info "Shell scripts will be created in: ~/.local/bin"
            warn "Restart JetBrains Toolbox for changes to take effect"
        fi
    else
        warn "JetBrains Toolbox config not found, skipping"
    fi
}

# =============================================================================
# 12. Install Zim (Zsh Plugin Manager)
# =============================================================================

install_zim() {
    info "Installing Zim (Zsh plugin manager)..."

    export ZIM_HOME="${HOME}/.zim"

    if [[ ! -e ${ZIM_HOME}/zimfw.zsh ]]; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would install Zim to $ZIM_HOME"
        else
            curl -fsSL --create-dirs -o ${ZIM_HOME}/zimfw.zsh \
                https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
            success "Zim installed"
        fi
    else
        success "Zim is already installed"
    fi

    # Install Zim modules
    if command -v zsh &> /dev/null; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would install Zim modules"
        else
            ZIM_HOME="${HOME}/.zim" zsh -c "source \${ZIM_HOME}/zimfw.zsh install"
            success "Zim modules installed"
        fi
    fi
}

# =============================================================================
# 13. Install Node.js LTS via NVM
# =============================================================================

install_node_lts() {
    info "Installing Node.js LTS version..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would install Node.js LTS via NVM"
        return 0
    fi

    # Load NVM in a subshell to install Node
    export NVM_DIR="$HOME/.nvm"

    # Source NVM
    local nvm_sh=""
    if command -v brew &> /dev/null && [ -s "$(brew --prefix nvm)/nvm.sh" ]; then
        nvm_sh="$(brew --prefix nvm)/nvm.sh"
    elif [ -s "$NVM_DIR/nvm.sh" ]; then
        nvm_sh="$NVM_DIR/nvm.sh"
    else
        warn "NVM not found, skipping Node.js installation"
        warn "You can install Node.js later with: nvm install --lts"
        return 0
    fi

    # Load NVM and install LTS in current shell
    source "$nvm_sh"

    # Check if any Node version is already installed
    if nvm ls | grep -q "N/A"; then
        info "Installing Node.js LTS..."
        nvm install --lts
        nvm use --lts
        success "Node.js LTS installed"
        info "Node version: $(node --version)"
        info "NPM version: $(npm --version)"
    else
        success "Node.js is already installed"
        info "Current version: $(nvm current 2>/dev/null || echo 'N/A')"
        info "To install LTS: nvm install --lts"
    fi
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    echo ""
    if [ "$DRY_RUN" = true ]; then
        echo "╔═══════════════════════════════════════╗"
        echo "║   Dotfiles Installation (DRY RUN)     ║"
        echo "╚═══════════════════════════════════════╝"
    else
        echo "╔═══════════════════════════════════════╗"
        echo "║   Dotfiles Installation Script        ║"
        echo "╚═══════════════════════════════════════╝"
    fi
    echo ""
    info "Dotfiles directory: $DOTFILES_DIR"
    if [ "$SKIP_BACKUP" = false ]; then
        info "Backup directory: $BACKUP_DIR"
    fi
    echo ""

    # Change to dotfiles directory
    cd "$DOTFILES_DIR" || exit 1

    # Run installation steps
    install_homebrew
    echo ""

    #install_brew_packages
    #echo ""

    setup_nvm
    echo ""

    setup_zsh
    echo ""

    setup_ssh
    echo ""

    setup_git
    echo ""

    #setup_php
    #echo ""

    setup_utils
    echo ""

    setup_husky
    echo ""

    setup_ghostty
    echo ""

    setup_claude_code
    echo ""

    setup_jetbrains
    echo ""

    install_zim
    echo ""

    install_node_lts
    echo ""

    # Optional: Import game configs
    if [ -d "$DOTFILES_DIR/games/lol" ] && [ -n "$(ls -A "$DOTFILES_DIR/games/lol" 2>/dev/null | grep -v README)" ]; then
        read -p "Import League of Legends configs? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            "$DOTFILES_DIR/scripts/lol-import.sh" || warn "LoL import failed (non-critical)"
            echo ""
        fi
    fi

    # Final message
    if [ "$DRY_RUN" = true ]; then
        echo "╔═══════════════════════════════════════╗"
        echo "║   Dry Run Complete!                   ║"
        echo "╚═══════════════════════════════════════╝"
        echo ""
        info "This was a dry run. No changes were made."
        info "Run without --dry-run to perform the actual installation."
    else
        echo "╔═══════════════════════════════════════╗"
        echo "║   Installation Complete! 🎉           ║"
        echo "╚═══════════════════════════════════════╝"
        echo ""
        success "Dotfiles have been installed successfully!"

        if [ "$SKIP_BACKUP" = false ] && [ -d "$BACKUP_DIR" ]; then
            echo ""
            info "Backups saved to: $BACKUP_DIR"
        fi
    fi

    echo ""
    info "Next steps:"
    echo "  1. Edit \$DOTFILES_DIR/zsh/.zshrc.secrets with your API keys"
    echo "  2. Edit \$DOTFILES_DIR/ssh/config.local with your SSH key paths"
    echo "  3. Restart your terminal or run: exec zsh"
    echo ""
    info "Optional:"
    echo "  - Set Zsh as default shell: chsh -s \$(which zsh)"
    echo "  - Review installed packages: brew list"
    echo "  - Check Node version: node --version"
    echo "  - Install other Node versions: nvm install <version>"
    echo ""
}

# Run main function
main
