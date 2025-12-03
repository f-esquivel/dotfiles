# Single source of truth for lazy-loaded commands
NVM_LAZY_COMMANDS=(nvm npm node npx nest lerna yarn)

function lazy_nvm {
  # Unset all wrapper functions (only if they exist)
  # NOTE: We hardcode the list here instead of using NVM_LAZY_COMMANDS because
  # shell environment snapshots (like Claude Code uses) may not capture the array,
  # which would cause the unset loop to do nothing and result in infinite recursion.
  local cmd
  for cmd in nvm npm node npx nest lerna yarn; do
    if typeset -f "$cmd" > /dev/null; then
      unset -f "$cmd"
    fi
  done

  # Set NVM_DIR (defaults to ~/.nvm)
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

  # Try to load NVM from multiple sources
  local nvm_loaded=false

  # Try Homebrew installation first (common on macOS)
  if command -v brew &> /dev/null; then
    local brew_nvm_path="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
    if [ -s "$brew_nvm_path" ]; then
      . "$brew_nvm_path"
      nvm_loaded=true
    fi
  fi

  # Try standard installation path (git clone method)
  if [ "$nvm_loaded" = false ] && [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm_loaded=true
  fi

  # If NVM couldn't be loaded, show a helpful message
  if [ "$nvm_loaded" = false ]; then
    echo "NVM is not installed. Install it from https://github.com/nvm-sh/nvm"
    return 1
  fi
}

# Create wrapper functions using a loop
for cmd in "${NVM_LAZY_COMMANDS[@]}"; do
  eval "function ${cmd} { lazy_nvm; ${cmd} \"\$@\"; }"
done
