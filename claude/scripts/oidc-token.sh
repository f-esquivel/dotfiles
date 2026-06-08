#!/bin/bash
# oidc-token.sh — Fetch an OIDC access token for a configured tenant/client and
# cache it locally, WITHOUT ever printing the token itself.
#
# The token is written to a per-(tenant,client,user) file (chmod 600) under
# ~/.claude/oidc/run/; only non-sensitive metadata (tenant, client, grant, user,
# expiry, the file path) is printed to stdout. Consume the token in your
# terminal with:
#
#     curl -H "Authorization: Bearer $(oidc-bearer <tenant> [-c <client>] [-u <alias>])" https://api...
#
# This separation is deliberate: Claude/agents can invoke this script to mint a
# token, but the plaintext token never enters a tool result the model reads.
#
# To CALL a loopback API rather than just mint, use the sibling oidc-curl.sh: it
# mints (delegating here) and makes the request in one step, returning only the
# response body — prefer it over minting here and consuming the token separately.
#
# HANDLE WITH CARE — this is an impersonation device. It mints real bearer
# tokens (incl. user-password grants) against whatever issuer a tenant points
# at. It is environment-agnostic: it does not know or care whether an issuer is
# "testing" or "prod" — that responsibility is entirely on the tenants you
# configure. Only ever point tenants at issuers you are authorized to use.
#
# Configuration (all local, never committed) lives under ~/.claude/oidc/:
#   tenants.json   tenant -> { type, baseUrl, realm, defaultClient,
#                              clients:{ <id>:{grants:[…],scopes:[…],verified,lastChecked} },
#                              users:{ <alias>:{username,label,verified,lastChecked} } }
#   .cache/<tenant>.json   cached OIDC discovery (indefinite; --refresh rebuilds)
#   run/<tenant>__<client>[__<alias>].token   cached token (chmod 600, pruned)
# Secrets live in the macOS Keychain (per tenant), never on disk:
#   client secret -> service "oidc:<tenant>:secret", account <clientId>
#   user password -> service "oidc:<tenant>:user",   account <alias>
#
# Registration is validated and de-duplicated:
#   - adding a client/user runs a smoke token request and records verified:true|
#     false (a failure still saves the entry, just flagged unverified)
#   - a duplicate tenant id OR a duplicate issuer (same baseUrl+realm) is refused
#   - re-adding a client/alias asks for confirmation; a username may map to only
#     one alias per tenant
#   - tenant/client/alias ids are restricted to [A-Za-z0-9._-] (no "__") so the
#     per-(tenant,client,alias) token cache key can never collide
#
# Usage:
#   oidc-token.sh --tenant <id> [--client <id>] [--user <alias>] [--refresh]
#   oidc-token.sh list
#   oidc-token.sh tenant add
#   oidc-token.sh tenant add-client    <tenant>
#   oidc-token.sh tenant add-user      <tenant>
#   oidc-token.sh tenant set-secret    <tenant> <client>   # rotate client secret
#   oidc-token.sh tenant set-password  <tenant> <alias>    # rotate user password
#   oidc-token.sh tenant remove-client <tenant> <client>
#   oidc-token.sh tenant remove-user   <tenant> <alias>
#   oidc-token.sh tenant remove        <tenant>            # wipe tenant + secrets
#
#   --client  defaults to the tenant's defaultClient.
#   --user    selects a password-grant by user ALIAS (resolved to the real
#             username); pass the raw username and it is matched too.
#   list      prints tenants/clients/users (aliases) as JSON — no secrets.
#
# Exit: 0 ok · 1 usage · 2 missing dependency · 3 config error · 4 token request failed
#
# Implementation is split across sibling modules (all sourced below):
#   oidc-lib.sh      shared paths + token-cache key (also used by oidc-bearer/curl.sh)
#   oidc-store.sh    tenants.json I/O, Keychain, OIDC discovery
#   oidc-request.sh  the token request + smoke verify (the only secret-touching code)
#   oidc-manage.sh   interactive tenant/client/user administration
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

set -euo pipefail

# Prefer trusted binary locations first (this script reads Keychain secrets, so
# resolving the wrong `security`/`curl` matters).
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# shellcheck source=oidc-lib.sh
_oidc_dir="$(dirname "${BASH_SOURCE[0]}")"
source "$_oidc_dir/oidc-lib.sh"      # OIDC_* paths, die, token-cache key
source "$_oidc_dir/oidc-store.sh"    # config store, Keychain, discovery
source "$_oidc_dir/oidc-request.sh"  # token request + smoke verify
source "$_oidc_dir/oidc-manage.sh"   # interactive administration

LOG_SCRIPT="oidc-token"              # identifies this writer in the centralized log

require_deps() {
    local cmd
    for cmd in jq curl security; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not installed" 2
    done
}

# --------------------------------------------------------------------------- #
# list — tenants/clients/users as JSON (no secrets)
# --------------------------------------------------------------------------- #
cmd_list() {
    [ -f "$OIDC_TENANTS_FILE" ] || { echo '[]'; return; }
    jq -e . "$OIDC_TENANTS_FILE" >/dev/null 2>&1 || die "invalid JSON in $OIDC_TENANTS_FILE" 3
    jq '
      to_entries | map({
        tenant: .key,
        type: (.value.type // "keycloak"),
        issuer: ((.value.baseUrl // "") + (if .value.realm then "/realms/" + .value.realm else "" end)),
        defaultClient: (.value.defaultClient // null),
        clients: ((.value.clients // {}) | to_entries
                  | map({id: .key, grants: (.value.grants // []),
                         verified: .value.verified,
                         lastChecked: .value.lastChecked})),
        users: ((.value.users // {}) | to_entries
                | map({alias: .key, username: .value.username, label: (.value.label // null),
                       verified: .value.verified,
                       lastChecked: .value.lastChecked}))
      })' "$OIDC_TENANTS_FILE"
}

# --------------------------------------------------------------------------- #
# fetch — mint and cache a token, print metadata only
# --------------------------------------------------------------------------- #
cmd_fetch() {
    local tenant="" client="" user_arg="" refresh="0"
    while [ $# -gt 0 ]; do
        case "$1" in
            --tenant)   tenant="${2:-}";  shift 2 ;;
            --client)   client="${2:-}";  shift 2 ;;
            --user)     user_arg="${2:-}";shift 2 ;;
            --refresh)  refresh="1";      shift ;;
            --tenant=*) tenant="${1#*=}"; shift ;;
            --client=*) client="${1#*=}"; shift ;;
            --user=*)   user_arg="${1#*=}";shift ;;
            *)          die "unknown argument '$1' (need --tenant <id>)" 1 ;;
        esac
    done
    [ -n "$tenant" ] || die "missing --tenant <id> (see: oidc-token.sh list)" 1
    LOG_TENANT="$tenant"   # context for any error logged from here on

    local tobj; tobj="$(load_tenant "$tenant")"

    [ -n "$client" ] || client="$(printf '%s' "$tobj" | jq -r '.defaultClient // empty')"
    if [ -z "$client" ]; then
        if [ -n "$user_arg" ]; then
            die "impersonating '$user_arg' needs a client with the 'password' grant, but tenant '$tenant' has no client configured — add one with: oidc-token.sh tenant add-client $tenant" 3
        fi
        die "no --client given and tenant '$tenant' has no defaultClient — add a client with: oidc-token.sh tenant add-client $tenant" 1
    fi
    local cobj
    cobj="$(printf '%s' "$tobj" | jq -c --arg c "$client" '.clients[$c] // empty')"
    [ -n "$cobj" ] || die "tenant '$tenant' has no client '$client'" 3
    LOG_CLIENT="$client"
    local scopes
    scopes="$(printf '%s' "$cobj" | jq -r '(.scopes // ["openid"]) | join(" ")')"

    # Grant is implied: password when a user is requested, else client_credentials.
    local grant alias="" username=""
    if [ -n "$user_arg" ]; then
        grant="password"
        # Resolve by alias; fall back to matching a configured username.
        local uobj
        uobj="$(printf '%s' "$tobj" | jq -c --arg a "$user_arg" '.users[$a] // empty')"
        if [ -n "$uobj" ]; then
            alias="$user_arg"
        else
            alias="$(printf '%s' "$tobj" | jq -r --arg u "$user_arg" \
                '((.users // {}) | to_entries[] | select(.value.username==$u) | .key)' | head -n1)"
            [ -n "$alias" ] || die "unknown user alias '$user_arg' for tenant '$tenant' (see: oidc-token.sh list)" 3
            uobj="$(printf '%s' "$tobj" | jq -c --arg a "$alias" '.users[$a]')"
        fi
        username="$(printf '%s' "$uobj" | jq -r '.username')"
    else
        grant="client_credentials"
    fi
    LOG_GRANT="$grant"; LOG_USER="$alias"

    # Validate the client supports the implied grant.
    local supported
    supported="$(printf '%s' "$cobj" | jq -r '(.grants // []) | join(" ")')"
    case " $supported " in
        *" $grant "*) ;;
        *) die "client '$client' does not support '$grant' (supports: ${supported:-none}) — add or pick a client with the '$grant' grant: oidc-token.sh tenant add-client $tenant" 3 ;;
    esac

    local issuer token_endpoint
    issuer="$(tenant_issuer "$tobj")"
    token_endpoint="$(discover_token_endpoint "$tenant" "$issuer" "$refresh")"
    [ -n "$token_endpoint" ] || die "discovery for tenant '$tenant' has no token_endpoint" 4

    # Mint the token via the shared requester. The plaintext token is captured
    # in-process (line 2) and never reaches this script's final stdout.
    local fetched access_token expires_in rc=0
    fetched="$(oidc_request "$token_endpoint" "$grant" "$client" "$scopes" "$tenant" "$alias" "$username")" \
        || { rc=$?; oidc_log_error mint "$rc" "token request to issuer failed"; exit "$rc"; }
    expires_in="$(printf '%s\n' "$fetched" | sed -n '1p')"
    access_token="$(printf '%s\n' "$fetched" | sed -n '2p')"
    [ -n "$access_token" ] || die "response contained no access_token" 4
    # Coerce to a plain integer so the metadata jq below (--argjson) can't choke
    # on an oddly-shaped expires_in after the token is already in hand.
    case "$expires_in" in ''|*[!0-9]*) expires_in=0 ;; esac

    mkdir -p "$OIDC_RUN_DIR"
    local token_file; token_file="$(oidc_token_path "$tenant" "$client" "$alias")"
    ( umask 077; printf '%s' "$access_token" > "$token_file" ) \
        || die "minted a token but failed to write the cache file '$token_file'" 4
    chmod 600 "$token_file"

    # Keep the run dir bounded: drop cached tokens older than 12h.
    find "$OIDC_RUN_DIR" -name '*.token' -type f -mmin +720 -delete 2>/dev/null || true

    # Metadata only — deliberately NO token in this output.
    local consume="curl -H \"Authorization: Bearer \$(oidc-bearer $tenant -c $client${alias:+ -u $alias})\" ..."
    jq -n \
        --arg tenant "$tenant" --arg client "$client" --arg grant "$grant" \
        --arg user "$alias" --arg username "$username" \
        --argjson expires_in "${expires_in:-0}" \
        --arg token_path "$token_file" --arg consume "$consume" \
        '{status:"ready", tenant:$tenant, client:$client, grant:$grant,
          user:(if $user=="" then null else $user end),
          username:(if $username=="" then null else $username end),
          expires_in:$expires_in, token_path:$token_path, consume:$consume}'
}

# --------------------------------------------------------------------------- #
main() {
    log_rid_init   # correlation id; shared with a parent oidc-curl if it set one
    require_deps
    case "${1:-}" in
        list)           LOG_OP="list";   cmd_list ;;
        tenant)         LOG_OP="tenant"; shift; cmd_tenant "$@" ;;
        -h|--help)      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
        *)              LOG_OP="mint";   cmd_fetch "$@" ;;
    esac
}

main "$@"
