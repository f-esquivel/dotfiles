#!/bin/bash
# oidc-curl.sh — Agent-safe authenticated request: mint a token AND consume it in
# one step, returning only the response body. The plaintext token never reaches
# stdout/stderr, so (unlike oidc-bearer.sh) the OIDC guard ALLOWS this script —
# an agent can hit a local API end-to-end without the token entering its context.
#
# How it stays leak-free:
#   - the token is read in-process and handed to curl via a private @file header
#     (never argv — mirrors oidc-request.sh's secret handling),
#   - curl is built here with a fixed safe flag set: never -v/--trace, and -w is
#     limited to %{http_code} (no header content),
#   - the response (body + curl stderr) is scrubbed of the exact token string,
#     and if the token still appears verbatim the request is refused outright —
#     this defeats endpoints that reflect the Authorization header back,
#   - targets are restricted to loopback (localhost / 127.0.0.0/8 / ::1), so a
#     misfired call cannot ship a live credential off the machine.
#
# Token selection mirrors oidc-token.sh / oidc-bearer.sh. Minting is delegated to
# oidc-token.sh (metadata only), so ALL secret-touching code stays in
# oidc-request.sh — this wrapper never reads the Keychain itself.
#
# Usage:
#   oidc-curl.sh [--tenant <id>] [--client <id>] [--user <alias>] [--refresh]
#                -- <METHOD> <URL> [--data <body>]... [--header 'K: V']...
#     The tenant may be the first bare argument or given via --tenant.
#     <METHOD>  one of GET HEAD POST PUT PATCH DELETE OPTIONS (case-insensitive)
#     <URL>     http(s) URL whose host is loopback only
#     --data    request body; repeatable parts are concatenated, sent raw
#     --header  extra request header; an Authorization header is rejected (this
#               script owns it). Repeatable.
#
# Exit: 0 ok · 1 usage · 2 missing dependency · 4 request/mint failed
#       · 5 policy violation (non-loopback target / forbidden header)
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

set -euo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

_dir="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=oidc-lib.sh
source "$_dir/oidc-lib.sh"   # OIDC_* paths + die

usage() {
    echo "usage: oidc-curl [--tenant <id>] [--client <id>] [--user <alias>] [--refresh]" >&2
    echo "                 -- <METHOD> <URL> [--data <body>]... [--header 'K: V']..." >&2
}

require_deps() {
    local cmd
    for cmd in jq curl; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not installed" 2
    done
}

# Accept only loopback hosts. Dies (exit 5) on anything that could leave the box.
require_loopback() {  # url
    local u="$1" host rest
    case "$u" in
        http://*|https://*) ;;
        *) die "URL must start with http:// or https://" 5 ;;
    esac
    host="${u#*://}"     # strip scheme
    host="${host%%/*}"   # strip path/query/fragment
    host="${host##*@}"   # strip userinfo
    case "$host" in
        \[*\]*) host="${host#\[}"; host="${host%%\]*}" ;;   # [::1] / [::1]:port
        *:*)    host="${host%%:*}" ;;                       # host:port
    esac
    host="$(printf '%s' "$host" | tr 'A-Z' 'a-z')"
    case "$host" in
        localhost|::1|0:0:0:0:0:0:0:1) return 0 ;;
        127.*)
            rest="${host#127.}"
            case "$rest" in
                *[!0-9.]*) die "refusing non-loopback target '$host'" 5 ;;
                *)         return 0 ;;
            esac
            ;;
        *) die "refusing non-loopback target '$host' (loopback only: localhost, 127.0.0.0/8, ::1)" 5 ;;
    esac
}

require_deps

# --- selection flags (consumed up to `--`) --------------------------------- #
tenant="" client="" alias="" refresh=""
while [ $# -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
        --)            break ;;
        --tenant)      tenant="${1:-}"; [ $# -gt 0 ] && shift || true ;;
        --tenant=*)    tenant="${arg#*=}" ;;
        --client|-c)   client="${1:-}"; [ $# -gt 0 ] && shift || true ;;
        --client=*)    client="${arg#*=}" ;;
        --user|-u)     alias="${1:-}";  [ $# -gt 0 ] && shift || true ;;
        --user=*)      alias="${arg#*=}" ;;
        --refresh)     refresh="--refresh" ;;
        -h|--help)     usage; exit 0 ;;
        -*)            usage; die "unknown selection flag '$arg' (request goes after --)" 1 ;;
        *)             if [ -z "$tenant" ]; then tenant="$arg"
                       else usage; die "unexpected argument '$arg' (request goes after --)" 1; fi ;;
    esac
done
[ -n "$tenant" ] || { usage; die "missing tenant (positional or --tenant <id>)" 1; }

# --- request: METHOD URL [--data ...] [--header ...] ----------------------- #
method="${1:-}"; [ $# -gt 0 ] && shift || true
url="${1:-}";    [ $# -gt 0 ] && shift || true
[ -n "$method" ] && [ -n "$url" ] || { usage; die "need <METHOD> <URL> after --" 1; }

method="$(printf '%s' "$method" | tr 'a-z' 'A-Z')"
case "$method" in
    GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS) ;;
    *) die "unsupported method '$method'" 1 ;;
esac
require_loopback "$url"

# Validate each header as it is parsed (fail fast, before any token is minted):
# reject newlines and any attempt to set Authorization — this script owns it.
add_header() {  # raw "K: V"
    case "$1" in *$'\n'*) die "a header may not contain newlines" 5 ;; esac
    local lname; lname="$(printf '%s' "${1%%:*}" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
    [ "$lname" = "authorization" ] && die "refusing to override the Authorization header" 5
    hdrs+=("$1")
}

data_parts=()
hdrs=()
while [ $# -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
        --data|-d)   data_parts+=("${1:-}"); [ $# -gt 0 ] && shift || true ;;
        --data=*)    data_parts+=("${arg#*=}") ;;
        --header|-H) add_header "${1:-}";    [ $# -gt 0 ] && shift || true ;;
        --header=*)  add_header "${arg#*=}" ;;
        *)           die "unknown request option '$arg'" 1 ;;
    esac
done

# --- mint via oidc-token.sh; reuse its resolved token_path (no duplication) - #
mint_args=(--tenant "$tenant")
[ -n "$client" ]  && mint_args+=(--client "$client")
[ -n "$alias" ]   && mint_args+=(--user "$alias")
[ -n "$refresh" ] && mint_args+=("$refresh")

meta="$("$_dir/oidc-token.sh" "${mint_args[@]}")" || die "token mint failed (see above)" 4
token_file="$(printf '%s' "$meta" | jq -r '.token_path // empty')"
[ -n "$token_file" ] && [ -s "$token_file" ] || die "mint produced no usable token cache file" 4

T="$(cat "$token_file")"
[ -n "$T" ] || die "cached token file is empty" 4

# --- assemble curl: token via @file header, fixed safe flag set ------------ #
sd="$(mktemp -d "${TMPDIR:-/tmp}/oidccurl.XXXXXX")" || die "mktemp failed" 4
trap 'rm -rf "$sd"' EXIT
( umask 077; printf 'Authorization: Bearer %s\n' "$T" > "$sd/h" )

c_args=(-sS -X "$method" -H @"$sd/h")

if [ "${#hdrs[@]}" -gt 0 ]; then
    for h in "${hdrs[@]}"; do c_args+=(-H "$h"); done
fi

if [ "${#data_parts[@]}" -gt 0 ]; then
    ( umask 077; : > "$sd/body" )
    for d in "${data_parts[@]}"; do printf '%s' "$d" >> "$sd/body"; done
    c_args+=(--data-binary @"$sd/body")
fi

# --- execute, scrub, guarantee no token surfaces --------------------------- #
set +e
resp="$(curl "${c_args[@]}" "$url" -w $'\n%{http_code}' 2>"$sd/err")"
rc=$?
set -e
err="$(cat "$sd/err" 2>/dev/null || true)"

# Best-effort redaction of the exact token (defeats header-reflecting endpoints).
resp="${resp//$T/[REDACTED-TOKEN]}"
err="${err//$T/[REDACTED-TOKEN]}"
# Hard guarantee: if the token still appears verbatim (e.g. the redaction glob
# was foiled by metacharacters), refuse to surface anything. The quoted case
# pattern is a literal substring test, not a glob.
case "$resp$err" in
    *"$T"*) die "response reflected the token verbatim — refusing to surface it" 4 ;;
esac

if [ "$rc" -ne 0 ]; then
    [ -n "$err" ] && printf '%s\n' "$err" >&2
    die "curl failed (exit $rc) for $method $url" 4
fi

http_code="${resp##*$'\n'}"
body="${resp%$'\n'*}"

printf '%s\n' "$body"
printf 'HTTP %s — %s %s\n' "$http_code" "$method" "$url" >&2
[ -n "$err" ] && printf '%s\n' "$err" >&2
exit 0
