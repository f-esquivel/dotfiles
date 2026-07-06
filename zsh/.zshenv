# Sourced first for every zsh invocation (before the global /etc/zsh/zshrc).
#
# On Debian/Ubuntu (incl. WSL) the global /etc/zsh/zshrc runs `compinit` unless
# `skip_global_compinit` is set. That early compinit fires before Zim loads, so
# Zim's `completion` module warns "completion was already initialized before
# completion module." Skipping it here lets Zim own compinit exactly once.
# Harmless on macOS, where no global rc runs compinit.
skip_global_compinit=1
