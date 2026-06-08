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

# Centralized structured logging (shared with db-agent + guards). The entry
# script sets LOG_SCRIPT (oidc-token / oidc-curl) and LOG_OP, and populates the
# LOG_TENANT/CLIENT/GRANT/USER context vars as it resolves them — die() and
# oidc_log_error attach whichever are set. Tokens/secrets are NEVER passed.
# shellcheck source=log-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/log-lib.sh"
: "${LOG_AGENT:=oidc}"

# Emit a structured error line with whatever OIDC context vars are currently set.
# Shared by die() and the direct-exit failure paths (e.g. a delegated request
# that exits without going through die). Best-effort; never breaks the caller.
#   oidc_log_error <op> <exit-code> <msg>
oidc_log_error() {
    local extra=()
    [ -n "${LOG_TENANT:-}" ] && extra+=("tenant=$LOG_TENANT")
    [ -n "${LOG_CLIENT:-}" ] && extra+=("client=$LOG_CLIENT")
    [ -n "${LOG_GRANT:-}" ]  && extra+=("grant=$LOG_GRANT")
    [ -n "${LOG_USER:-}" ]   && extra+=("user=$LOG_USER")
    log_event error "$1" "exit=$2" "msg=$3" ${extra[@]+"${extra[@]}"} 2>/dev/null || true
}

# Print an error to stderr and exit. Second arg overrides the exit code (default
# 1). Every error path in the oidc scripts funnels through here, so wrapping it
# captures all failures (with context) at one choke point — the msg is the same
# operator-facing text already shown on stderr, so it is safe to log.
die() {
    local msg="$1" code="${2:-1}"
    echo "Error: $msg" >&2
    oidc_log_error "${LOG_OP:-unknown}" "$code" "$msg"
    exit "$code"
}

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
