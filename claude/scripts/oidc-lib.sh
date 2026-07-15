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

# --------------------------------------------------------------------------- #
# Host policy — where a minted token is allowed to go.
#
# Two audiences share these, so they live here rather than in oidc-store.sh:
# oidc-curl.sh (which sources only this lib) enforces them per request, and
# oidc-manage.sh enforces them when registering a host. One definition of "what
# is a host" / "is it loopback" / "is it allowed" keeps the check that guards a
# request identical to the check that guarded the registration.
#
# The rule enforced on top of these (in oidc-curl.sh):
#   loopback            always allowed — the token cannot leave the machine
#   registered + https  allowed only with --remote, and only for the tenant the
#                       host is registered under
#   anything else       refused
# --------------------------------------------------------------------------- #

# Bare, lowercased host of an http(s) URL (empty if there isn't one). Strips
# path/query/fragment before userinfo, so an '@' inside a query can't be mistaken
# for a userinfo delimiter and hide the real host.
oidc_url_host() {  # url -> host
    local host="${1#*://}"
    host="${host%%/*}"
    host="${host%%\?*}"
    host="${host%%#*}"
    host="${host##*@}"
    case "$host" in
        \[*\]*) host="${host#\[}"; host="${host%%\]*}" ;;  # [::1] / [::1]:port
        *:*)    host="${host%%:*}" ;;                      # host:port
    esac
    printf '%s' "$host" | tr 'A-Z' 'a-z'
}

# Is this host the local machine? (localhost, 127.0.0.0/8, ::1)
oidc_is_loopback_host() {  # host -> 0 loopback / 1 not
    case "$1" in
        localhost|::1|0:0:0:0:0:0:0:1) return 0 ;;
        127.*)
            # Only digits+dots after "127." — "127.evil.com" is a DNS name that
            # merely starts with 127, not a loopback address.
            case "${1#127.}" in
                *[!0-9.]*) return 1 ;;
                *)         return 0 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

# Is this a registrable remote host? A bare DNS hostname only: no scheme, port,
# path or userinfo, and no wildcards — allowedHosts matching is exact, so a '*'
# would silently never match rather than widen anything.
oidc_valid_host() {  # host -> 0 valid / 1 not
    case "$1" in
        '')                    return 1 ;;
        *[!A-Za-z0-9.-]*)      return 1 ;;
        .*|*.|*..*)            return 1 ;;  # no empty labels
        # No dash-edged label anywhere (RFC 1123): at the host edges, and — via
        # the ".-" / "-." pairs — at any interior label boundary too.
        -*|*-|*.-*|*-.*)       return 1 ;;
        *)                     return 0 ;;
    esac
}

# Is <host> registered on <tenant>'s allowedHosts? Exact match, and deliberately
# scoped to ONE tenant: a token minted for tenant A may never be sent to a host
# that only tenant B authorized.
oidc_tenant_allows_host() {  # tenant host -> 0 allowed / 1 not
    [ -f "$OIDC_TENANTS_FILE" ] || return 1
    jq -e --arg t "$1" --arg h "$2" \
        '((.[$t].allowedHosts // []) | index($h)) != null' \
        "$OIDC_TENANTS_FILE" >/dev/null 2>&1
}

# Host of the tenant's own issuer — the SSO provider that mints its tokens
# (Keycloak composes the issuer from baseUrl+realm, so the host is baseUrl's;
# other types carry an explicit issuer). Empty when the tenant is unknown or
# malformed. This host needs no allowedHosts entry: it is the party that ISSUED
# the token, so handing the token back to it reveals nothing it doesn't have.
oidc_tenant_issuer_host() {  # tenant -> host
    [ -f "$OIDC_TENANTS_FILE" ] || return 0
    local base
    base="$(jq -r --arg t "$1" '
        .[$t] // empty
        | if (.type // "keycloak") == "keycloak" then (.baseUrl // "") else (.issuer // "") end
    ' "$OIDC_TENANTS_FILE" 2>/dev/null)" || return 0
    [ -n "$base" ] || return 0
    oidc_url_host "$base"
}
