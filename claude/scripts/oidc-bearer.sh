#!/bin/bash
# oidc-bearer.sh — Print the cached OIDC access token for a tenant/client/user.
#
# INTENDED FOR INTERACTIVE TERMINAL USE ONLY — e.g.:
#   curl -H "Authorization: Bearer $(oidc-bearer <tenant> [client] [alias])" https://api...
#
# This is the ONE place a raw token is emitted, so it is deliberately split out
# from oidc-token.sh: the OIDC PreToolUse guard DENIES Claude from running it,
# keeping tokens out of model context. Fetch/refresh tokens via oidc-token.sh.
#
# Usage:  oidc-bearer.sh <tenant> [-c <client>] [-u <alias>]
#         oidc-bearer.sh --tenant <id> [--client <id>] [--user <alias>]
#         The tenant may be the first bare argument or given via --tenant.
#         --client/-c defaults to the tenant's defaultClient.
#         --user/-u selects an impersonation (password-grant) token; omit for M2M.
#
# Exit: 0 ok · 1 usage · 2 no cached token (run oidc-token.sh first)
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

set -euo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# shellcheck source=oidc-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/oidc-lib.sh"

usage() { echo "usage: oidc-bearer <tenant> [-c <client>] [-u <alias>]" >&2; }

# Named flags mirror oidc-token.sh (--tenant/--client/--user) so the same muscle
# memory works; tenant may also be the first bare positional. client/user are
# flags only — no optional-middle positionals to mis-slot.
tenant="" client="" alias=""
while [ $# -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
        --tenant)      tenant="${1:-}"; [ $# -gt 0 ] && shift || true ;;
        --tenant=*)    tenant="${arg#*=}" ;;
        --client|-c)   client="${1:-}"; [ $# -gt 0 ] && shift || true ;;
        --client=*)    client="${arg#*=}" ;;
        --user|-u)     alias="${1:-}";  [ $# -gt 0 ] && shift || true ;;
        --user=*)      alias="${arg#*=}" ;;
        -h|--help)     usage; exit 0 ;;
        -*)            usage; die "unknown flag '$arg'" 1 ;;
        *)             if [ -z "$tenant" ]; then tenant="$arg"
                       else die "unexpected argument '$arg' (client/user are flags: -c/-u)" 1; fi ;;
    esac
done
[ -n "$tenant" ] || { usage; exit 1; }

if [ -z "$client" ]; then
    client="$(oidc_default_client "$tenant")"
    [ -n "$client" ] || die "no client given (-c <client>) and tenant '$tenant' has no defaultClient" 1
fi

token_file="$(oidc_token_path "$tenant" "$client" "$alias")"
[ -s "$token_file" ] || die "no cached token for '$tenant/$client${alias:+/$alias}' — run: oidc-token.sh --tenant '$tenant'${alias:+ --user '$alias'}" 2

cat "$token_file"
