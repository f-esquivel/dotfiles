#!/bin/bash
# oidc-store.sh — Config, Keychain, and discovery layer for oidc-token.sh.
#
# SOURCED, not executed. Owns everything that reads/writes persistent state:
#   - tenants.json (the config store)        load/validate/atomic-write
#   - the macOS Keychain (secrets/passwords) service names + read/write/delete
#   - OIDC discovery (.well-known)           cached token_endpoint lookup
#
# Plaintext secrets pass THROUGH kc_read into oidc-request.sh; nothing here
# prints them. Depends on oidc-lib.sh (OIDC_* paths, die) being sourced first.
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

# Ids that become part of a Keychain service / token-cache filename must stay in
# a safe charset and must not contain the "__" cache-key separator — otherwise
# two distinct (tenant,client,alias) triples could map to the same token file.
valid_id() {
    case "$1" in
        '')                return 1 ;;
        *__*)              return 1 ;;  # reserved cache-key separator
        *[!A-Za-z0-9._-]*) return 1 ;;  # only filesystem/keychain-safe chars
        *)                 return 0 ;;
    esac
}
require_id() {  # value kind
    valid_id "$1" || die "$2 '$1' is invalid — use only [A-Za-z0-9._-] and no '__'" 3
}

# --------------------------------------------------------------------------- #
# Keychain — one item per credential, never written to disk in plaintext.
# --------------------------------------------------------------------------- #
kc_secret_service() { printf 'oidc:%s:secret' "$1"; }  # tenant ; account = clientId
kc_user_service()   { printf 'oidc:%s:user'   "$1"; }  # tenant ; account = alias

# Read a Keychain password without echoing it. Empty (rc!=0) is a valid "absent".
kc_read()   { security find-generic-password -s "$1" -a "$2" -w 2>/dev/null || true; }
kc_write()  { security add-generic-password -U -s "$1" -a "$2" -w "$3" \
                  || die "failed to write Keychain item '$1' / '$2'" 3; }
kc_delete() { security delete-generic-password -s "$1" -a "$2" >/dev/null 2>&1 || true; }

# --------------------------------------------------------------------------- #
# tenants.json — the config store.
# --------------------------------------------------------------------------- #
ensure_store() {
    mkdir -p "$OIDC_CACHE_DIR" "$OIDC_RUN_DIR"
    [ -f "$OIDC_TENANTS_FILE" ] || ( umask 077; echo '{}' > "$OIDC_TENANTS_FILE" )
}

# Atomic write so an interrupted update can't corrupt tenants.json.
store_write() {
    local tmp="$OIDC_TENANTS_FILE.tmp"
    ( umask 077; printf '%s\n' "$1" > "$tmp" ) && mv "$tmp" "$OIDC_TENANTS_FILE"
}

# Read the whole tenant object; dies if absent / file invalid.
load_tenant() {  # tenant -> JSON object on stdout
    [ -f "$OIDC_TENANTS_FILE" ] || die "no tenants.json — run: oidc-token.sh tenant add" 3
    local obj
    obj="$(jq -c --arg t "$1" '.[$t] // empty' "$OIDC_TENANTS_FILE" 2>/dev/null)" \
        || die "invalid JSON in $OIDC_TENANTS_FILE" 3
    [ -n "$obj" ] || die "unknown tenant '$1' (see: oidc-token.sh list)" 3
    printf '%s' "$obj"
}

require_tenant() {  # tenant
    jq -e --arg t "$1" '.[$t]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1 \
        || die "unknown tenant '$1' (see: oidc-token.sh list)" 3
}

# Delete cached token files matching a glob under the run dir.
prune_tokens() { find "$OIDC_RUN_DIR" -maxdepth 1 -name "$1" -type f -delete 2>/dev/null || true; }

# Echo a client id that supports the password grant (defaultClient first), or empty.
password_capable_client() {
    jq -r --arg t "$1" '
        .[$t] as $T
        | ($T.defaultClient // "") as $dc
        | if (($T.clients // {})[$dc].grants // [] | index("password")) then $dc
          else (($T.clients // {}) | to_entries | map(select(.value.grants | index("password"))) | (.[0].key // ""))
          end' "$OIDC_TENANTS_FILE" 2>/dev/null
}

# --------------------------------------------------------------------------- #
# verified-flag bookkeeping (set by the smoke test in oidc-request.sh).
# --------------------------------------------------------------------------- #
oidc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

mark_client_verified() {  # tenant client bool
    local updated
    updated="$(jq --arg t "$1" --arg c "$2" --argjson v "$3" --arg ts "$(oidc_now)" \
        '.[$t].clients[$c].verified = $v | .[$t].clients[$c].lastChecked = $ts' \
        "$OIDC_TENANTS_FILE")" && store_write "$updated"
}
mark_user_verified() {  # tenant alias bool
    local updated
    updated="$(jq --arg t "$1" --arg a "$2" --argjson v "$3" --arg ts "$(oidc_now)" \
        '.[$t].users[$a].verified = $v | .[$t].users[$a].lastChecked = $ts' \
        "$OIDC_TENANTS_FILE")" && store_write "$updated"
}

# --------------------------------------------------------------------------- #
# Issuer + discovery.
# --------------------------------------------------------------------------- #
# Compose the issuer for a tenant object. Keycloak derives it from baseUrl+realm;
# other types may carry an explicit issuer (extension point).
tenant_issuer() {  # tenant-json -> issuer
    local obj="$1" type base realm issuer
    type="$(printf '%s' "$obj" | jq -r '.type // "keycloak"')"
    case "$type" in
        keycloak)
            base="$(printf '%s' "$obj" | jq -r '.baseUrl // empty')"
            realm="$(printf '%s' "$obj" | jq -r '.realm // empty')"
            [ -n "$base" ] && [ -n "$realm" ] || die "tenant missing baseUrl/realm" 3
            printf '%s/realms/%s' "${base%/}" "$realm"
            ;;
        *)
            issuer="$(printf '%s' "$obj" | jq -r '.issuer // empty')"
            [ -n "$issuer" ] || die "tenant type '$type' requires an explicit issuer" 3
            printf '%s' "$issuer"
            ;;
    esac
}

discover_token_endpoint() {  # tenant issuer refresh
    local tenant="$1" issuer="$2" refresh="$3"
    local cache="$OIDC_CACHE_DIR/$tenant.json"
    mkdir -p "$OIDC_CACHE_DIR"
    # Re-download when forced, missing, or the cached copy isn't valid JSON — a
    # poisoned cache (e.g. an HTML error page served with 200) must not stick.
    if [ "$refresh" = "1" ] || [ ! -s "$cache" ] || ! jq -e . "$cache" >/dev/null 2>&1; then
        curl -fsS "${issuer%/}/.well-known/openid-configuration" -o "$cache.tmp" \
            || die "OIDC discovery failed for issuer '$issuer'" 4
        # Validate BEFORE caching so we never persist garbage.
        if ! jq -e . "$cache.tmp" >/dev/null 2>&1; then
            rm -f "$cache.tmp"
            die "OIDC discovery for issuer '$issuer' returned invalid JSON" 4
        fi
        mv "$cache.tmp" "$cache"
    fi
    jq -r '.token_endpoint // empty' "$cache"
}
