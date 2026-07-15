#!/bin/bash
# oidc-manage.sh — Interactive tenant/client/user administration for oidc-token.sh.
#
# SOURCED, not executed. Everything here is human-driven (read -p prompts) and
# config-mutating: register/extend tenants, rotate or remove credentials. It
# seeds the Keychain and tenants.json, then leans on oidc-request.sh to smoke
# test each new/rotated credential before trusting it.
#
# Depends on oidc-lib.sh, oidc-store.sh, oidc-request.sh.
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

confirm() {  # prompt -> 0 yes / 1 no
    local a; read -r -p "$1 [y/N]: " a
    case "$a" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# Refuse to run outside a real terminal. Most commands here are self-gating —
# they block on a `read` prompt for a secret, which an agent's non-interactive
# shell can't satisfy. add-host/remove-host are the exception: they take every
# argument on the command line, so without this they would run happily inside an
# agent. That matters more than the usual convenience check — allowedHosts is the
# one control standing between a live prod token and an arbitrary destination, so
# authorizing a host has to be an act by the human, at a keyboard. Belt and
# braces: oidc-guard blocks these from the Bash tool too.
require_interactive() {  # subcommand
    [ -t 0 ] || die "'$1' must be run by you, interactively, in your own terminal — it authorizes a real destination for live bearer tokens, so it is deliberately not something an agent can do on its own" 1
}

add_client_interactive() {  # tenant
    local tenant="$1" client grants scopes secret
    read -r -p "  Client ID: " client
    require_id "$client" "client id"
    if jq -e --arg t "$tenant" --arg c "$client" '.[$t].clients[$c]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1; then
        local ow; read -r -p "  Client '$client' already exists — overwrite? [y/N]: " ow
        case "$ow" in [yY]*) ;; *) die "aborted; client '$client' left unchanged" 3 ;; esac
    fi
    read -r -p "  Grants (space-separated: client_credentials password) [client_credentials]: " grants
    grants="${grants:-client_credentials}"
    read -r -p "  Scopes (space-separated) [openid]: " scopes
    scopes="${scopes:-openid}"
    read -r -s -p "  Client secret (blank for a public client): " secret; echo >&2
    if [ -n "$secret" ]; then
        kc_write "$(kc_secret_service "$tenant")" "$client" "$secret"
        echo "  Stored client secret in Keychain." >&2
    fi
    local gj sj updated
    gj="$(printf '%s' "$grants" | jq -R 'split(" ") | map(select(length>0))')"
    sj="$(printf '%s' "$scopes" | jq -R 'split(" ") | map(select(length>0))')"
    updated="$(jq --arg t "$tenant" --arg c "$client" --argjson g "$gj" --argjson s "$sj" \
        '.[$t].clients[$c] = {grants:$g, scopes:$s}
         | (if (.[$t].defaultClient // "") == "" then .[$t].defaultClient = $c else . end)' \
        "$OIDC_TENANTS_FILE")"
    store_write "$updated"
    echo "  Added client '$client' to tenant '$tenant'." >&2
    verify_client "$tenant" "$client" "$grants"
}

add_user_interactive() {  # tenant
    local tenant="$1" alias username label pw
    read -r -p "  User alias (what you'll pass to --user, e.g. dev): " alias
    require_id "$alias" "user alias"
    if jq -e --arg t "$tenant" --arg a "$alias" '.[$t].users[$a]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1; then
        local ow; read -r -p "  Alias '$alias' already exists — overwrite? [y/N]: " ow
        case "$ow" in [yY]*) ;; *) die "aborted; alias '$alias' left unchanged" 3 ;; esac
    fi
    read -r -p "  Real username (e.g. dev@example.com): " username
    [ -n "$username" ] || die "username is required" 3
    # A username may map to only one alias per tenant (keeps reverse lookup unambiguous).
    local dupu
    dupu="$(jq -r --arg t "$tenant" --arg a "$alias" --arg u "$username" \
        '(.[$t].users // {}) | to_entries[] | select(.value.username == $u and .key != $a) | .key' \
        "$OIDC_TENANTS_FILE" 2>/dev/null | head -n1)"
    [ -z "$dupu" ] || die "username '$username' is already mapped to alias '$dupu' in tenant '$tenant' — use that alias" 3
    read -r -p "  Label (optional, e.g. developer): " label
    read -r -s -p "  Password for '$alias': " pw; echo >&2
    [ -n "$pw" ] || die "password cannot be empty" 3
    kc_write "$(kc_user_service "$tenant")" "$alias" "$pw"
    local updated
    updated="$(jq --arg t "$tenant" --arg a "$alias" --arg u "$username" --arg l "$label" \
        '.[$t].users[$a] = ({username:$u} + (if $l=="" then {} else {label:$l} end))' \
        "$OIDC_TENANTS_FILE")"
    store_write "$updated"
    echo "  Added user alias '$alias' -> '$username' to tenant '$tenant'." >&2
    verify_user "$tenant" "$alias" "$username"
}

cmd_tenant() {
    ensure_store
    local sub="${1:-add}"; shift || true
    case "$sub" in
        add)
            local tenant type base realm
            read -r -p "Tenant id (e.g. acme-test): " tenant
            require_id "$tenant" "tenant id"
            jq -e --arg t "$tenant" '.[$t]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1 \
                && die "tenant '$tenant' already exists — extend it with 'tenant add-client $tenant' / 'tenant add-user $tenant', or pick a new id" 3
            read -r -p "Type [keycloak]: " type; type="${type:-keycloak}"
            read -r -p "Base URL (e.g. https://auth.example.com): " base
            [ -n "$base" ] || die "base URL is required" 3
            base="${base%/}"
            read -r -p "Realm / identifier (e.g. main): " realm
            [ -n "$realm" ] || die "realm is required" 3
            # Refuse a second tenant pointing at the same issuer (baseUrl+realm).
            local dupt
            dupt="$(jq -r --arg b "$base" --arg r "$realm" \
                'to_entries[] | select(((.value.baseUrl // "") | rtrimstr("/")) == $b and (.value.realm // "") == $r) | .key' \
                "$OIDC_TENANTS_FILE" 2>/dev/null | head -n1)"
            [ -z "$dupt" ] || die "issuer '$base/realms/$realm' is already configured as tenant '$dupt' — reuse it instead of adding a duplicate" 3
            local updated
            updated="$(jq --arg t "$tenant" --arg ty "$type" --arg b "$base" --arg r "$realm" \
                '.[$t] = {type:$ty, baseUrl:$b, realm:$r, clients:{}, users:{}}' \
                "$OIDC_TENANTS_FILE")"
            store_write "$updated"
            echo "Created tenant '$tenant'. Now add its first client:" >&2
            add_client_interactive "$tenant"
            local more
            while :; do
                read -r -p "Add a user alias for impersonation? [y/N]: " more
                case "$more" in [yY]*) add_user_interactive "$tenant" ;; *) break ;; esac
            done
            echo "Done. Fetch with: oidc-token.sh --tenant '$tenant'" >&2
            ;;
        add-client)
            local tenant="${1:-}"; [ -n "$tenant" ] || die "usage: oidc-token.sh tenant add-client <tenant>" 1
            jq -e --arg t "$tenant" '.[$t]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1 \
                || die "unknown tenant '$tenant'" 3
            add_client_interactive "$tenant"
            ;;
        add-user)
            local tenant="${1:-}"; [ -n "$tenant" ] || die "usage: oidc-token.sh tenant add-user <tenant>" 1
            require_tenant "$tenant"
            add_user_interactive "$tenant"
            ;;
        add-host)
            local tenant="${1:-}" host="${2:-}"
            [ -n "$tenant" ] && [ -n "$host" ] || die "usage: oidc-token.sh tenant add-host <tenant> <host>" 1
            require_tenant "$tenant"
            require_interactive "tenant add-host"
            host="$(printf '%s' "$host" | tr 'A-Z' 'a-z')"
            # Reject the near-misses explicitly — a silently-stored "https://api.x/v1"
            # would never match the bare host oidc-curl derives from a URL, and the
            # registration would look done while every call kept failing.
            case "$host" in
                *://*) die "pass a bare hostname, not a URL (e.g. api.example.com, not https://api.example.com/v1)" 1 ;;
                */*)   die "pass a bare hostname, without a path (e.g. api.example.com)" 1 ;;
                *:*)   die "pass a bare hostname, without a port — registering a host authorizes it on any port" 1 ;;
                \**)   die "wildcards are not supported — allowedHosts matching is exact; register each host you actually call" 1 ;;
            esac
            oidc_valid_host "$host" || die "'$host' is not a valid hostname — use only [A-Za-z0-9.-]" 1
            oidc_is_loopback_host "$host" \
                && die "'$host' is a loopback target — those are always allowed, so there is nothing to register" 1
            local issuer_host; issuer_host="$(oidc_tenant_issuer_host "$tenant")"
            [ "$host" = "$issuer_host" ] \
                && die "'$host' is tenant '$tenant''s own issuer — reach it with 'oidc-curl --tenant $tenant --inspect', no registration needed" 1
            if oidc_tenant_allows_host "$tenant" "$host"; then
                echo "Host '$host' is already registered for tenant '$tenant'." >&2
                return 0
            fi
            # Spell out what is being authorized before asking. The token this
            # unlocks is real, and the tenant's issuer says which realm it comes
            # from — that is the fact worth checking against prod-vs-testing.
            echo "About to authorize a live-token destination:" >&2
            echo "  tenant: $tenant" >&2
            echo "  issuer: $(jq -r --arg t "$tenant" '(.[$t].baseUrl // "?") + "/realms/" + (.[$t].realm // "?")' "$OIDC_TENANTS_FILE")" >&2
            echo "  host:   https://$host" >&2
            echo "Any token minted for '$tenant' (including user impersonation) may then be sent to this host by 'oidc-curl --remote'." >&2
            confirm "Authorize '$host' for tenant '$tenant'?" || die "aborted; '$host' NOT registered" 1
            local updated
            updated="$(jq --arg t "$tenant" --arg h "$host" \
                '.[$t].allowedHosts = (((.[$t].allowedHosts // []) + [$h]) | unique)' \
                "$OIDC_TENANTS_FILE")"
            store_write "$updated"
            echo "Registered '$host' for tenant '$tenant'. Call it with:" >&2
            echo "  oidc-curl --tenant $tenant --remote -- GET https://$host/path" >&2
            ;;
        remove-host)
            local tenant="${1:-}" host="${2:-}"
            [ -n "$tenant" ] && [ -n "$host" ] || die "usage: oidc-token.sh tenant remove-host <tenant> <host>" 1
            require_tenant "$tenant"
            require_interactive "tenant remove-host"
            host="$(printf '%s' "$host" | tr 'A-Z' 'a-z')"
            oidc_tenant_allows_host "$tenant" "$host" \
                || die "host '$host' is not registered for tenant '$tenant' (see: oidc-token.sh list)" 3
            confirm "Revoke '$host' as a token destination for tenant '$tenant'?" || die "aborted" 1
            local updated
            updated="$(jq --arg t "$tenant" --arg h "$host" \
                '.[$t].allowedHosts = ((.[$t].allowedHosts // []) | map(select(. != $h)))' \
                "$OIDC_TENANTS_FILE")"
            store_write "$updated"
            echo "Revoked '$host' for tenant '$tenant'." >&2
            ;;
        set-secret)
            local tenant="${1:-}" client="${2:-}"
            [ -n "$tenant" ] && [ -n "$client" ] || die "usage: oidc-token.sh tenant set-secret <tenant> <client>" 1
            require_tenant "$tenant"
            jq -e --arg t "$tenant" --arg c "$client" '.[$t].clients[$c]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1 \
                || die "tenant '$tenant' has no client '$client'" 3
            local secret
            read -r -s -p "New client secret for '$client': " secret; echo >&2
            [ -n "$secret" ] || die "secret cannot be empty" 3
            kc_write "$(kc_secret_service "$tenant")" "$client" "$secret"
            echo "Rotated secret for '$tenant/$client'." >&2
            local grants
            grants="$(jq -r --arg t "$tenant" --arg c "$client" '(.[$t].clients[$c].grants // []) | join(" ")' "$OIDC_TENANTS_FILE")"
            verify_client "$tenant" "$client" "$grants"
            ;;
        set-password)
            local tenant="${1:-}" alias="${2:-}"
            [ -n "$tenant" ] && [ -n "$alias" ] || die "usage: oidc-token.sh tenant set-password <tenant> <alias>" 1
            require_tenant "$tenant"
            jq -e --arg t "$tenant" --arg a "$alias" '.[$t].users[$a]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1 \
                || die "tenant '$tenant' has no user alias '$alias'" 3
            local pw
            read -r -s -p "New password for '$alias': " pw; echo >&2
            [ -n "$pw" ] || die "password cannot be empty" 3
            kc_write "$(kc_user_service "$tenant")" "$alias" "$pw"
            echo "Rotated password for '$tenant/$alias'." >&2
            local username
            username="$(jq -r --arg t "$tenant" --arg a "$alias" '.[$t].users[$a].username' "$OIDC_TENANTS_FILE")"
            verify_user "$tenant" "$alias" "$username"
            ;;
        remove-user)
            local tenant="${1:-}" alias="${2:-}"
            [ -n "$tenant" ] && [ -n "$alias" ] || die "usage: oidc-token.sh tenant remove-user <tenant> <alias>" 1
            require_tenant "$tenant"
            jq -e --arg t "$tenant" --arg a "$alias" '.[$t].users[$a]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1 \
                || die "tenant '$tenant' has no user alias '$alias'" 3
            confirm "Remove user '$alias' from tenant '$tenant' (deletes its Keychain password and cached tokens)?" \
                || die "aborted" 1
            kc_delete "$(kc_user_service "$tenant")" "$alias"
            local updated; updated="$(jq --arg t "$tenant" --arg a "$alias" 'del(.[$t].users[$a])' "$OIDC_TENANTS_FILE")"
            store_write "$updated"
            prune_tokens "${tenant}__*__${alias}.token"
            echo "Removed user '$alias' from tenant '$tenant'." >&2
            ;;
        remove-client)
            local tenant="${1:-}" client="${2:-}"
            [ -n "$tenant" ] && [ -n "$client" ] || die "usage: oidc-token.sh tenant remove-client <tenant> <client>" 1
            require_tenant "$tenant"
            jq -e --arg t "$tenant" --arg c "$client" '.[$t].clients[$c]' "$OIDC_TENANTS_FILE" >/dev/null 2>&1 \
                || die "tenant '$tenant' has no client '$client'" 3
            confirm "Remove client '$client' from tenant '$tenant' (deletes its Keychain secret and cached tokens)?" \
                || die "aborted" 1
            kc_delete "$(kc_secret_service "$tenant")" "$client"
            local updated; updated="$(jq --arg t "$tenant" --arg c "$client" \
                'del(.[$t].clients[$c])
                 | (if .[$t].defaultClient == $c
                    then .[$t].defaultClient = ((.[$t].clients // {} | keys | first) // null) else . end)' \
                "$OIDC_TENANTS_FILE")"
            store_write "$updated"
            prune_tokens "${tenant}__${client}.token"
            prune_tokens "${tenant}__${client}__*.token"
            echo "Removed client '$client' from tenant '$tenant'." >&2
            ;;
        remove)
            local tenant="${1:-}"
            [ -n "$tenant" ] || die "usage: oidc-token.sh tenant remove <tenant>" 1
            require_tenant "$tenant"
            confirm "Remove ENTIRE tenant '$tenant' — all clients, users, Keychain secrets/passwords, and cached tokens?" \
                || die "aborted" 1
            local c a
            for c in $(jq -r --arg t "$tenant" '(.[$t].clients // {}) | keys[]' "$OIDC_TENANTS_FILE" 2>/dev/null); do
                kc_delete "$(kc_secret_service "$tenant")" "$c"
            done
            for a in $(jq -r --arg t "$tenant" '(.[$t].users // {}) | keys[]' "$OIDC_TENANTS_FILE" 2>/dev/null); do
                kc_delete "$(kc_user_service "$tenant")" "$a"
            done
            local updated; updated="$(jq --arg t "$tenant" 'del(.[$t])' "$OIDC_TENANTS_FILE")"
            store_write "$updated"
            prune_tokens "${tenant}__*.token"
            rm -f "$OIDC_CACHE_DIR/$tenant.json"
            echo "Removed tenant '$tenant'." >&2
            ;;
        *) die "unknown 'tenant' subcommand '$sub' (add|add-client|add-user|add-host|set-secret|set-password|remove-user|remove-client|remove-host|remove)" 1 ;;
    esac
}
