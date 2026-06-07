#!/bin/bash
# oidc-lib.sh — Shared helpers for the OIDC tenant token scripts.
#
# This file is meant to be SOURCED, not executed. It holds the paths and the
# token-cache key logic shared by the three entry-point scripts:
#   oidc-token.sh    fetcher/manager    — mints a token, prints metadata only
#   oidc-bearer.sh   raw-token printer  — emits the cached token to stdout
#   oidc-curl.sh     loopback requester — mints + consumes, prints response body
#
# Who calls what, and why there are two ways to invoke these:
#   - Agents (Claude) call the scripts by ABSOLUTE PATH (~/.claude/scripts/*.sh).
#     A subagent shell is non-interactive and does NOT source ~/.zshrc, so the
#     oidc-* shell functions don't exist there — only the full path is reliable.
#     Agents may run oidc-token.sh and oidc-curl.sh; the guard BLOCKS them from
#     oidc-bearer.sh (a raw token would land in model context).
#   - Humans use the oidc-* shell functions (defined in zsh/.zshrc.user) at an
#     interactive prompt. oidc-bearer is human-only: it's how the handed-off
#     `curl -H "...$(oidc-bearer ...)"` consume string resolves a real token in
#     your own terminal, never in a tool result the model reads.
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

# Root of all local, never-committed OIDC state. Overridable via $OIDC_HOME.
: "${OIDC_HOME:=$HOME/.claude/oidc}"
OIDC_TENANTS_FILE="$OIDC_HOME/tenants.json"
OIDC_CACHE_DIR="$OIDC_HOME/.cache"
OIDC_RUN_DIR="$OIDC_HOME/run"

# Print an error to stderr and exit. Second arg overrides the exit code (default 1).
die() { echo "Error: $1" >&2; exit "${2:-1}"; }

# oidc_token_path <tenant> <client> [alias] -> cached token file path.
# Key = tenant__client[__alias], with path-unfriendly chars flattened.
oidc_token_path() {
    local tenant="$1" client="$2" alias="${3:-}"
    local key="${tenant}__${client}"
    [ -n "$alias" ] && key="${key}__${alias}"
    key="$(printf '%s' "$key" | tr '/ :@' '____')"
    printf '%s/%s.token' "$OIDC_RUN_DIR" "$key"
}

# oidc_default_client <tenant> -> the tenant's defaultClient (empty if unset).
# Reads tenants.json directly so oidc-bearer can resolve a bare `<tenant>`.
oidc_default_client() {
    [ -f "$OIDC_TENANTS_FILE" ] || return 0
    jq -r --arg t "$1" '.[$t].defaultClient // empty' "$OIDC_TENANTS_FILE" 2>/dev/null
}
