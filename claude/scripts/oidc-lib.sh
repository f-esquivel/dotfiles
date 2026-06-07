#!/bin/bash
# oidc-lib.sh — Shared helpers for the OIDC tenant token scripts.
#
# This file is meant to be SOURCED, not executed. It holds the paths and the
# token-cache key logic shared by oidc-token.sh (fetcher/manager) and
# oidc-bearer.sh (raw-token printer).
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
