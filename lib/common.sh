#!/usr/bin/env bash
# =============================================================================
# Shared helpers for dotfiles scripts
# =============================================================================
# Source from any script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"          # for scripts at repo root
#   source "$SCRIPT_DIR/../lib/common.sh"       # for scripts in scripts/
#
# After sourcing:
#   - $DOTFILES_DIR is exported (resolved from this file's location)
#   - info/success/warn/error log helpers are available
#   - require_command <name> aborts if a command is missing
#   - RED/GREEN/YELLOW/BLUE/NC color vars are set (back-compat)

# Resolve dotfiles root from this file's location: lib/common.sh -> repo root.
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    export DOTFILES_DIR
fi

# Color codes — disabled when stdout is not a TTY or NO_COLOR is set.
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    NC=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

info()    { printf '%b\n' "${BLUE}ℹ️  $1${NC}"; }
success() { printf '%b\n' "${GREEN}✅ $1${NC}"; }
warn()    { printf '%b\n' "${YELLOW}⚠️  $1${NC}"; }
error()   { printf '%b\n' "${RED}❌ $1${NC}" >&2; }

# Abort if a required command isn't on PATH.
require_command() {
    command -v "$1" &>/dev/null || {
        error "$1 is required but not installed"
        exit 1
    }
}
