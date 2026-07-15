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
#   - redirects are never followed, so an authorized target cannot bounce the
#     Authorization header to a host that was never authorized,
#   - where the token may go is decided by MODE, not by the caller's URL alone
#     (see below) — the default stays loopback, so a misfired call cannot ship a
#     live credential off the machine.
#
# Modes — each widens the target set by exactly one well-understood step:
#   (default)   loopback only (localhost / 127.0.0.0/8 / ::1). The token cannot
#               leave the machine.
#   --inspect   the tenant's OWN issuer host (from its baseUrl), plus nothing
#               else. Needs no registration: the issuer is the party that MINTED
#               the token, so handing it back reveals nothing it doesn't have.
#               This is how you explore an SSO provider (userinfo, admin REST…).
#   --remote    loopback, plus the hosts registered on THIS tenant's allowedHosts
#               (exact match). Registration is human-only and interactive
#               (oidc-token tenant add-host) — an agent cannot authorize a
#               destination for itself, so a hallucinated or injected hostname
#               never receives a live token. Scoped per tenant: a prod token can
#               only reach hosts registered under the prod tenant.
# --inspect and --remote are mutually exclusive. Off-box targets (both modes)
# must be https — a bearer token never travels a real network in plaintext — and
# every off-box request is audited to ~/.claude/logs/oidc.log (host/method/status,
# never the body).
#
# Token selection mirrors oidc-token.sh / oidc-bearer.sh. Minting is delegated to
# oidc-token.sh (metadata only), so ALL secret-touching code stays in
# oidc-request.sh — this wrapper never reads the Keychain itself.
#
# Usage:
#   oidc-curl.sh [--tenant <id>] [--client <id>] [--user <alias>] [--refresh]
#                [--inspect | --remote]
#                -- <METHOD> <URL> [--data <body>]... [--form <part>]... [--header 'K: V']...
#     The tenant may be the first bare argument or given via --tenant.
#     <METHOD>  one of GET HEAD POST PUT PATCH DELETE OPTIONS (case-insensitive)
#     <URL>     http(s) URL whose host the selected mode authorizes
#     --data    raw request body; repeatable parts are concatenated, sent raw.
#               Mutually exclusive with --form.
#     --form    multipart/form-data part, passed verbatim to curl -F. Repeatable.
#               Supports field=value and curl's file refs (field=@/path to upload
#               a file, field=</path to read a field value from a file). curl sets
#               the multipart Content-Type + boundary itself, so don't also set a
#               Content-Type header. Mutually exclusive with --data.
#     --header  extra request header; an Authorization header is rejected (this
#               script owns it). Repeatable.
#
# Exit: 0 ok · 1 usage · 2 missing dependency · 4 request/mint failed
#       · 5 policy violation (target not authorized by the mode / plaintext
#         off-box target / forbidden header)
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
    echo "                 [--inspect | --remote]" >&2
    echo "                 -- <METHOD> <URL> [--data <body>]... [--form <part>]... [--header 'K: V']..." >&2
    echo "  (default)  loopback targets only" >&2
    echo "  --inspect  the tenant's own issuer host (SSO provider) — no registration needed" >&2
    echo "  --remote   loopback + the tenant's registered allowedHosts (https only)" >&2
}

require_deps() {
    local cmd
    for cmd in jq curl; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not installed" 2
    done
}

# Decide whether $url may receive a live bearer token, per the selected mode.
# Sets target_kind (loopback|inspect|remote) and target_host for the audit trail.
# Dies (exit 5) on anything the mode does not authorize.
require_allowed_target() {  # url
    local u="$1" host issuer_host
    case "$u" in
        http://*|https://*) ;;
        *) die "URL must start with http:// or https://" 5 ;;
    esac
    host="$(oidc_url_host "$u")"
    [ -n "$host" ] || die "could not parse a host out of the URL" 5
    target_host="$host"

    # Loopback is allowed in every mode except --inspect, which is deliberately
    # narrow: it authorizes the issuer host and nothing else (if that issuer IS
    # loopback, the check below matches it anyway).
    if [ "$mode" != "inspect" ] && oidc_is_loopback_host "$host"; then
        target_kind="loopback"
        return 0
    fi

    case "$mode" in
        inspect)
            issuer_host="$(oidc_tenant_issuer_host "$tenant")"
            [ -n "$issuer_host" ] \
                || die "cannot resolve the issuer host for tenant '$tenant' — is it configured? (see: oidc-token.sh list)" 5
            [ "$host" = "$issuer_host" ] \
                || die "--inspect reaches only tenant '$tenant''s own issuer host ('$issuer_host'), not '$host' — to call another host, register it and use --remote" 5
            target_kind="inspect"
            ;;
        remote)
            oidc_tenant_allows_host "$tenant" "$host" \
                || die "host '$host' is not registered for tenant '$tenant' — a token for a tenant may only reach that tenant's own allowedHosts (see: oidc-token.sh list). Registering is yours to do, in your own terminal: oidc-token tenant add-host $tenant $host" 5
            target_kind="remote"
            ;;
        *)
            die "refusing non-loopback target '$host' — the default mode is loopback only (localhost, 127.0.0.0/8, ::1). Use --inspect to reach tenant '$tenant''s own issuer, or register the host and use --remote" 5
            ;;
    esac

    # A token on a real network must not travel in plaintext. Keyed on the host
    # rather than the mode: --inspect skips the loopback shortcut above, so a
    # tenant whose issuer IS a local Keycloak (http://localhost:8080) arrives
    # here — and http to the local machine leaks nothing.
    if ! oidc_is_loopback_host "$host"; then
        case "$u" in
            https://*) ;;
            *) die "refusing to send a bearer token to '$host' over plaintext http — targets off this machine must be https" 5 ;;
        esac
    fi
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
tenant="" client="" alias="" refresh="" mode="loopback"
target_kind="" target_host=""
set_mode() {  # requested mode — the three are mutually exclusive
    [ "$mode" = "loopback" ] || [ "$mode" = "$1" ] \
        || die "--inspect and --remote are mutually exclusive (--inspect reaches the tenant's issuer; --remote reaches its registered hosts)" 1
    mode="$1"
}
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
        --inspect)     set_mode inspect ;;
        --remote)      set_mode remote ;;
        -h|--help)     usage; exit 0 ;;
        -*)            usage; die "unknown selection flag '$arg' (request goes after --)" 1 ;;
        *)             if [ -z "$tenant" ]; then tenant="$arg"
                       else usage; die "unexpected argument '$arg' (request goes after --)" 1; fi ;;
    esac
done
[ -n "$tenant" ] || { usage; die "missing tenant (positional or --tenant <id>)" 1; }
# Context for any error logged from here on (no secrets).
LOG_TENANT="$tenant"; LOG_CLIENT="$client"; LOG_USER="$alias"

# Audit every request that needed a mode to authorize it (--inspect / --remote),
# recording only where the token went — never the body. Called for each such
# attempt, success or not: by then the token has already been sent, so the line
# must exist even when the response turns out to be unusable.
#
# Plain loopback (the default mode) is not audited, so existing log volume is
# unchanged. --inspect IS audited even when the tenant's issuer happens to be
# loopback itself: a call against an SSO provider is worth a trace wherever that
# provider lives.
log_target_audit() {  # http_code (may be empty on a transport failure)
    case "$target_kind" in
        inspect|remote) ;;
        *) return 0 ;;
    esac
    log_event info "curl-$target_kind" "tenant=$tenant" ${client:+"client=$client"} \
        ${alias:+"user=$alias"} "host=$target_host" "method=$method" \
        ${1:+"http=$1"} "msg=$method $url"
}

# --- request: METHOD URL [--data ...] [--header ...] ----------------------- #
method="${1:-}"; [ $# -gt 0 ] && shift || true
url="${1:-}";    [ $# -gt 0 ] && shift || true
[ -n "$method" ] && [ -n "$url" ] || { usage; die "need <METHOD> <URL> after --" 1; }

method="$(printf '%s' "$method" | tr 'a-z' 'A-Z')"
case "$method" in
    GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS) ;;
    *) die "unsupported method '$method'" 1 ;;
esac
require_allowed_target "$url"

# Validate each header as it is parsed (fail fast, before any token is minted):
# reject newlines and any attempt to set Authorization — this script owns it.
add_header() {  # raw "K: V"
    case "$1" in *$'\n'*) die "a header may not contain newlines" 5 ;; esac
    local lname; lname="$(printf '%s' "${1%%:*}" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
    [ "$lname" = "authorization" ] && die "refusing to override the Authorization header" 5
    hdrs+=("$1")
}

data_parts=()
form_parts=()
hdrs=()
while [ $# -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
        --data|-d)   data_parts+=("${1:-}"); [ $# -gt 0 ] && shift || true ;;
        --data=*)    data_parts+=("${arg#*=}") ;;
        --form|-F)   form_parts+=("${1:-}"); [ $# -gt 0 ] && shift || true ;;
        --form=*)    form_parts+=("${arg#*=}") ;;
        --header|-H) add_header "${1:-}";    [ $# -gt 0 ] && shift || true ;;
        --header=*)  add_header "${arg#*=}" ;;
        *)           die "unknown request option '$arg'" 1 ;;
    esac
done

# --data and --form both set the request body; curl accepts only one kind.
if [ "${#data_parts[@]}" -gt 0 ] && [ "${#form_parts[@]}" -gt 0 ]; then
    die "--data and --form are mutually exclusive (pick raw body OR multipart)" 1
fi

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
elif [ "${#form_parts[@]}" -gt 0 ]; then
    # Multipart: hand each part to curl -F verbatim. curl reads any field=@/path
    # file uploads (and field=</path field-from-file) itself and sets the
    # multipart/form-data Content-Type + boundary. The Authorization header still
    # rides the private @file above; no -F part can reference it (the temp dir is
    # an unguessable mktemp path), and the response is token-scrubbed as usual.
    for f in "${form_parts[@]}"; do c_args+=(-F "$f"); done
fi

# --- execute, scrub, guarantee no token surfaces --------------------------- #
# No -L: redirects are never followed, so a target that 3xx's elsewhere cannot
# bounce the Authorization header to a host the mode never authorized.
set +e
resp="$(curl "${c_args[@]}" "$url" -w $'\n%{http_code}\t%{content_type}' 2>"$sd/err")"
rc=$?
set -e
err="$(cat "$sd/err" 2>/dev/null || true)"

# curl writes the -w trailer itself (status + content type), so it carries no
# response content and is safe to read before the body is scrubbed. It's absent
# when the transport failed and curl produced nothing.
http_code="" ctype=""
if [ "$rc" -eq 0 ]; then
    meta_line="${resp##*$'\n'}"
    http_code="${meta_line%%$'\t'*}"
    ctype="${meta_line#*$'\t'}"   # only picks the detail extractor; not logged
fi

# Audit before any failure path can exit: the token is already on the wire.
log_target_audit "$http_code"

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

body="${resp%$'\n'*}"

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
