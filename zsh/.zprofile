# Initialize Homebrew from whichever prefix exists on this machine.
# macOS Apple Silicon: /opt/homebrew · macOS Intel: /usr/local
# Linux/WSL (Linuxbrew): /home/linuxbrew/.linuxbrew or ~/.linuxbrew
# Stays silent when Homebrew isn't installed (e.g. a fresh WSL box).
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew \
             /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
  if [[ -x "$_brew" ]]; then
    eval "$("$_brew" shellenv)"
    break
  fi
done
unset _brew

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init.zsh 2>/dev/null || :
