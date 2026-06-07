#!/bin/bash
# oidc-request.sh — The ONLY code that handles plaintext credentials.
#
# SOURCED, not executed. Isolated here so the secret-handling surface is a single
# small file you can audit in one read:
#   - oidc_request   POST the token request; secrets reach curl via @file (a
#                    private tempdir), never argv; the minted token is returned
#                    in-process and DISCARDED unless the caller caches it.
#   - run_smoke      a real token request whose token is thrown away (validation)
#   - verify_client / verify_user   smoke-test + record the verified flag
#
# Depends on oidc-lib.sh and oidc-store.sh (die, kc_*, tenant_issuer,
# discover_token_endpoint, mark_*_verified, password_capable_client).
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

# --------------------------------------------------------------------------- #
# oidc_request — POST the token request and return ONLY through stdout, in-process
# --------------------------------------------------------------------------- #
# Args: token_endpoint grant client scopes tenant alias username
# Secrets are read from the Keychain and handed to curl via @file (private
# tempdir) so they never appear in argv. On success prints two lines —
# expires_in then access_token — captured in-process by the caller; this is
# NEVER the script's final stdout, so the token never reaches a tool result.
# Returns: 0 ok · 3 missing user password · 4 network/HTTP/parse failure.
oidc_request() {
    local token_endpoint="$1" grant="$2" client="$3" scopes="$4" tenant="$5" alias="$6" username="$7"
    local sd
    sd="$(mktemp -d "${TMPDIR:-/tmp}/oidc.XXXXXX")" || { echo "Error: mktemp failed" >&2; return 4; }

    local -a args
    args=(-sS -X POST "$token_endpoint"
          --data-urlencode "grant_type=$grant"
          --data-urlencode "client_id=$client")

    local client_secret
    client_secret="$(kc_read "$(kc_secret_service "$tenant")" "$client")"
    if [ -n "$client_secret" ]; then
        printf '%s' "$client_secret" > "$sd/cs"
        args+=(--data-urlencode "client_secret@$sd/cs")
    fi
    if [ -n "$scopes" ]; then
        args+=(--data-urlencode "scope=$scopes")
    fi
    if [ "$grant" = "password" ]; then
        local user_password
        user_password="$(kc_read "$(kc_user_service "$tenant")" "$alias")"
        if [ -z "$user_password" ]; then
            rm -rf "$sd"
            echo "Error: no Keychain password for alias '$alias' in tenant '$tenant'" >&2
            return 3
        fi
        printf '%s' "$user_password" > "$sd/pw"
        args+=(--data-urlencode "username=$username"
               --data-urlencode "password@$sd/pw")
    fi

    local resp http_code body
    if ! resp="$(curl "${args[@]}" -w $'\n%{http_code}')"; then
        rm -rf "$sd"
        echo "Error: token request to '$token_endpoint' failed (network)" >&2
        return 4
    fi
    rm -rf "$sd"
    http_code="${resp##*$'\n'}"
    body="${resp%$'\n'*}"

    if [ "$http_code" -ge 400 ] 2>/dev/null; then
        local err err_desc
        err="$(printf '%s' "$body" | jq -r '.error // "http_'"$http_code"'"' 2>/dev/null)"
        err_desc="$(printf '%s' "$body" | jq -r '.error_description // ""' 2>/dev/null)"
        echo "Error: token request rejected ($http_code): $err${err_desc:+ — $err_desc}" >&2
        return 4
    fi

    local access_token expires_in
    access_token="$(printf '%s' "$body" | jq -r '.access_token // empty')"
    expires_in="$(printf '%s' "$body" | jq -r '.expires_in // 0')"
    if [ -z "$access_token" ]; then
        echo "Error: response contained no access_token" >&2
        return 4
    fi
    printf '%s\n%s\n' "$expires_in" "$access_token"
    return 0
}

# --------------------------------------------------------------------------- #
# Smoke test + verified-flag bookkeeping (used by registration/rotation).
# --------------------------------------------------------------------------- #
# run_smoke <tenant> <client> <grant> <alias> <username> -> 0 verified / 1 not.
# Performs a real token request through oidc_request and DISCARDS the token
# (stdout -> /dev/null); only the pass/fail result and any error reason survive.
run_smoke() {
    local tenant="$1" client="$2" grant="$3" alias="$4" username="$5"
    local tobj scopes issuer endpoint err
    tobj="$(jq -c --arg t "$tenant" '.[$t] // empty' "$OIDC_TENANTS_FILE" 2>/dev/null)"
    [ -n "$tobj" ] || { echo "tenant '$tenant' not found" >&2; return 1; }
    scopes="$(printf '%s' "$tobj" | jq -r --arg c "$client" '(.clients[$c].scopes // ["openid"]) | join(" ")')"
    issuer="$(tenant_issuer "$tobj")" || return 1
    endpoint="$(discover_token_endpoint "$tenant" "$issuer" 0)" || return 1
    [ -n "$endpoint" ] || { echo "discovery returned no token_endpoint" >&2; return 1; }
    if err="$(oidc_request "$endpoint" "$grant" "$client" "$scopes" "$tenant" "$alias" "$username" 2>&1 >/dev/null)"; then
        return 0
    fi
    [ -n "$err" ] && echo "$err" >&2
    return 1
}

# Smoke-test a client's M2M grant and record verified state.
verify_client() {  # tenant client grants
    local tenant="$1" client="$2" grants="$3"
    if printf '%s' "$grants" | tr ' ' '\n' | grep -qx 'client_credentials'; then
        if run_smoke "$tenant" "$client" "client_credentials" "" ""; then
            mark_client_verified "$tenant" "$client" true
            echo "  ✓ client_credentials verified." >&2
        else
            mark_client_verified "$tenant" "$client" false
            echo "  ✗ smoke test failed — client saved as unverified (check the secret)." >&2
        fi
    else
        echo "  (no client_credentials grant — verified when a user is added.)" >&2
    fi
}

# Smoke-test a user's password grant via a password-capable client; record state.
verify_user() {  # tenant alias username
    local tenant="$1" alias="$2" username="$3" pcli
    pcli="$(password_capable_client "$tenant")"
    if [ -n "$pcli" ]; then
        if run_smoke "$tenant" "$pcli" "password" "$alias" "$username"; then
            mark_user_verified "$tenant" "$alias" true
            echo "  ✓ password grant verified via client '$pcli'." >&2
        else
            mark_user_verified "$tenant" "$alias" false
            echo "  ✗ smoke test failed — user saved as unverified (check username/password)." >&2
        fi
    else
        mark_user_verified "$tenant" "$alias" false
        echo "  (no password-capable client in tenant — user saved as unverified.)" >&2
    fi
}
