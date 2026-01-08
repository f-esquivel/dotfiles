# ~/.config/husky/init.sh
# Husky v9+ init script. Loads NVM for git hooks in non-interactive shells.

# Add Homebrew to PATH (Apple Silicon and Intel)
[ -d "/opt/homebrew/bin" ] && export PATH="/opt/homebrew/bin:$PATH"
[ -d "/usr/local/bin" ] && export PATH="/usr/local/bin:$PATH"

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
