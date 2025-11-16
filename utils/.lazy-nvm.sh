# Single source of truth for lazy-loaded commands
NVM_LAZY_COMMANDS=(nvm npm node npx yarn gemini opencode nest lerna claude)

function lazy_nvm {
  # Unset all wrapper functions at once
  unset -f "${NVM_LAZY_COMMANDS[@]}"

  if [ -d "${HOME}/.nvm" ]; then
    export NVM_DIR="$HOME/.nvm"
    # Linux path
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    # macOS path - cache brew prefix to avoid multiple calls
    if command -v brew &> /dev/null; then
      local brew_nvm_path="$(brew --prefix nvm 2>/dev/null)/nvm.sh"
      [ -s "$brew_nvm_path" ] && . "$brew_nvm_path"
    fi
  fi
}

# Create wrapper functions using a loop
for cmd in "${NVM_LAZY_COMMANDS[@]}"; do
  eval "function ${cmd} { lazy_nvm; command ${cmd} \"\$@\"; }"
done
