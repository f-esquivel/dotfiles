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
source "$_dir/oidc-lib.sh"   # OIDC_* paths + die + structured logging

LOG_SCRIPT="oidc-curl"       # identifies this writer in the centralized log
LOG_OP="curl"
# Mint a correlation id NOW and export it, so the delegated oidc-token.sh mint
# (a child process) shares this rid — the two-step run reads as one trace.
log_rid_init

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

# Canonical reason phrase for an HTTP status code (empty if unrecognized). Static
# map — carries no body content, so it is always safe to log.
http_reason() {  # <code>
    case "$1" in
        400) echo "Bad Request" ;;            401) echo "Unauthorized" ;;
        402) echo "Payment Required" ;;       403) echo "Forbidden" ;;
        404) echo "Not Found" ;;              405) echo "Method Not Allowed" ;;
        406) echo "Not Acceptable" ;;         408) echo "Request Timeout" ;;
        409) echo "Conflict" ;;               410) echo "Gone" ;;
        413) echo "Payload Too Large" ;;      415) echo "Unsupported Media Type" ;;
        422) echo "Unprocessable Entity" ;;   429) echo "Too Many Requests" ;;
        500) echo "Internal Server Error" ;;  501) echo "Not Implemented" ;;
        502) echo "Bad Gateway" ;;            503) echo "Service Unavailable" ;;
        504) echo "Gateway Timeout" ;;        3*)  echo "Redirect" ;;
        *)   echo "" ;;
    esac
}

# Pull a short, human-readable reason out of a response body: conventional error
# fields for JSON, the <title> for HTML. The body is already token-scrubbed by the
# caller; output is whitespace-flattened and capped at 200 chars. Empty when
# nothing usable is found. Best-effort — never fails the caller.
extract_detail() {  # <body> <content_type>
    local body="$1" ctype="$2" d="" head is_json=0
    head="$(printf '%s' "$body" | sed -E 's/^[[:space:]]+//' | cut -c1)"
    case "$ctype" in *json*) is_json=1 ;; esac
    [ "$is_json" = 0 ] && case "$head" in '{'|'[') is_json=1 ;; esac

    if [ "$is_json" = 1 ]; then
        d="$(printf '%s' "$body" | jq -r '
            # A string counts only if it has a non-whitespace char — jqs // skips
            # only null/false, so blank ("") fields must be filtered explicitly.
            def nonblank: select(type=="string" and test("\\S"));
            def firsterr:
                (.message? | nonblank)
                // (.error?  | if type=="object" then (.message? | nonblank)
                               else nonblank end)
                // (.detail? | nonblank)
                // (.title?  | nonblank)
                // (.errors? | if type=="array" then .[0]
                               elif type=="object" then (to_entries[0].value)
                               else . end)
                // (.exception? | nonblank)
                // empty;
            firsterr
            | if type=="string" then .
              elif (type=="number" or type=="boolean") then tostring
              else tojson end
        ' 2>/dev/null)" || d=""
    fi
    if [ -z "$d" ]; then
        case "$body" in
            *"<title>"*) d="${body#*<title>}"; d="${d%%</title>*}" ;;
        esac
    fi

    [ -n "$d" ] || return 0
    d="$(printf '%s' "$d" | tr '\n\r\t' '   ' | sed -E 's/  +/ /g; s/^ +//; s/ +$//')"
    printf '%s' "${d:0:200}"
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
# Context for any error logged from here on (no secrets).
LOG_TENANT="$tenant"; LOG_CLIENT="$client"; LOG_USER="$alias"

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
resp="$(curl "${c_args[@]}" "$url" -w $'\n%{http_code}\t%{content_type}' 2>"$sd/err")"
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

meta_line="${resp##*$'\n'}"
body="${resp%$'\n'*}"
http_code="${meta_line%%$'\t'*}"
ctype="${meta_line#*$'\t'}"   # used only to pick the detail extractor; not logged

# A non-2xx response is a likely execution issue — trace it with the canonical
# reason phrase and a short reason pulled from the body (JSON error field or HTML
# title). The raw body is still never logged; the request succeeded at the
# transport level, so the body is surfaced as usual and the exit stays 0.
case "$http_code" in
    2*) ;;
    *)  reason="$(http_reason "$http_code")"
        detail="$(extract_detail "$body" "$ctype")"
        log_event error curl "http=$http_code" ${reason:+"reason=$reason"} \
            "tenant=$tenant" ${client:+"client=$client"} ${alias:+"user=$alias"} \
            ${detail:+"detail=$detail"} \
            "msg=non-2xx response for $method $url" ;;
esac

printf '%s\n' "$body"
printf 'HTTP %s — %s %s\n' "$http_code" "$method" "$url" >&2
[ -n "$err" ] && printf '%s\n' "$err" >&2
exit 0
