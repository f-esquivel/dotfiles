#!/bin/bash
# oidc-host-policy.test.sh — regression suite for "where may a live token go?"
#
# The host policy is a security boundary: it decides whether a real bearer token
# is allowed to leave this machine. It spans four files, so this suite covers all
# four rather than one script:
#   oidc-lib.sh     the host primitives (parse / classify / look up)
#   oidc-curl.sh    the per-request enforcement + the audit trail
#   oidc-manage.sh  `tenant add-host` — the human-only registration
#   oidc-guard.sh   the PreToolUse rule that keeps an agent out of add-host
#
# Hermetic and offline by construction:
#   - $OIDC_HOME + $CLAUDE_LOG_HOME are redirected to a temp dir, so the real
#     tenant store and the real logs are never touched,
#   - fixture issuers live under the RFC 2606 `.invalid` TLD, which cannot
#     resolve — a refusal never reaches the network, and a test that gets PAST
#     the policy fails its mint locally (~70ms) instead of calling a real host,
#   - the end-to-end section runs a throwaway issuer on loopback, so the paths
#     that only exist AFTER a successful mint (audit, scrubbing) are exercised
#     with a fake token and no credential,
#   - stdin is pinned per-case (</dev/null or a pty), so results don't depend on
#     whether a human or an agent invoked the suite.
#
# NOTE ON EXIT CODES — the policy check runs before any mint, so:
#   exit 5 = refused by policy (nothing was minted, nothing left the machine)
#   exit 4 = policy ALLOWED it and the mint then failed on the fixture
# That difference is what most cases below assert.
#
# By default it tests the DEPLOYED scripts (~/.claude/scripts, the symlinks the
# agent actually runs); override with SCRIPTS=/path ./oidc-host-policy.test.sh.
#
# Usage:  claude/scripts/oidc-host-policy.test.sh
# Exit:   0 = all green, 1 = at least one failure.

set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DEPLOYED="$HOME/.claude/scripts"
SCRIPTS="${SCRIPTS:-$([ -e "$SCRIPTS_DEPLOYED/oidc-curl.sh" ] && echo "$SCRIPTS_DEPLOYED" || echo "$DIR")}"
GUARD="${GUARD:-$HOME/.claude/hooks/oidc-guard.sh}"
[ -e "$GUARD" ] || GUARD="$DIR/../hooks/oidc-guard.sh"

CURL_SH="$SCRIPTS/oidc-curl.sh"
TOKEN_SH="$SCRIPTS/oidc-token.sh"

# --- hermetic sandbox ------------------------------------------------------ #
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/oidcpolicy.XXXXXX")" || exit 1
export OIDC_HOME="$SANDBOX/oidc"
export CLAUDE_LOG_HOME="$SANDBOX/logs"
mkdir -p "$OIDC_HOME/run" "$CLAUDE_LOG_HOME"
LOG="$CLAUDE_LOG_HOME/oidc.log"
FAKE_PID=""
cleanup() {
    if [ -n "$FAKE_PID" ]; then
        kill "$FAKE_PID" 2>/dev/null
        wait "$FAKE_PID" 2>/dev/null   # reap quietly: no "Terminated" on teardown
    fi
    rm -rf "$SANDBOX"
}
trap cleanup EXIT

pass=0; fail=0
FAILS=()
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); FAILS+=("$1"); }

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# --------------------------------------------------------------------------- #
# 1. Unit: the host primitives in oidc-lib.sh
# --------------------------------------------------------------------------- #
# Sourced directly so each branch is hit exactly, with no request in the way.
# shellcheck source=oidc-lib.sh
source "$SCRIPTS/oidc-lib.sh"

# eq <expected> <actual> <desc>
eq() {
    if [ "$1" = "$2" ]; then ok; else bad "$3 :: expected '$1', got '$2'"; fi
}
# rc_is <expected_rc> <actual_rc> <desc>
rc_is() {
    if [ "$1" = "$2" ]; then ok; else bad "$3 :: expected rc=$1, got rc=$2"; fi
}

section "1. oidc_url_host — parsing the host out of a URL"
eq "api.example.com" "$(oidc_url_host 'https://api.example.com/x')"        "plain host"
eq "api.example.com" "$(oidc_url_host 'https://api.example.com')"          "no path"
eq "api.example.com" "$(oidc_url_host 'https://api.example.com:8443/x')"   "port stripped"
eq "api.example.com" "$(oidc_url_host 'https://API.EXAMPLE.COM/x')"        "lowercased"
eq "api.example.com" "$(oidc_url_host 'https://api.example.com/x?a=1')"    "query after path"
eq "api.example.com" "$(oidc_url_host 'https://api.example.com?a=1')"      "query, no path"
eq "api.example.com" "$(oidc_url_host 'https://api.example.com#frag')"     "fragment"
eq "api.example.com" "$(oidc_url_host 'https://user@api.example.com/x')"   "userinfo stripped"
eq "api.example.com" "$(oidc_url_host 'https://u:p@api.example.com/x')"    "user:pass stripped"
eq "::1"             "$(oidc_url_host 'http://[::1]:8080/x')"              "IPv6 + port"
eq "::1"             "$(oidc_url_host 'http://[::1]/x')"                   "IPv6, no port"
eq ""                "$(oidc_url_host 'http:///path')"                     "empty host"
# The ordering that makes the parser safe: strip path/query BEFORE userinfo, so
# an '@' living in a query string cannot be mistaken for a userinfo delimiter
# and hand the caller the wrong host.
eq "api.example.com" "$(oidc_url_host 'https://api.example.com/p?q=a@evil.com')" "@ inside query is not userinfo"
eq "evil.com"        "$(oidc_url_host 'https://api.example.com@evil.com/x')"     "userinfo trick resolves to the REAL host"

section "2. oidc_is_loopback_host — is this the local machine?"
for h in localhost 127.0.0.1 127.1.2.3 127.0.0.53 ::1 0:0:0:0:0:0:0:1; do
    oidc_is_loopback_host "$h"; rc_is 0 "$?" "loopback: $h"
done
for h in api.example.com 127.evil.com 127.0.0.1.evil.com localhost.evil.com \
         notlocalhost 1270.0.0.1 "" 12.7.0.0.1; do
    oidc_is_loopback_host "$h"; rc_is 1 "$?" "NOT loopback: ${h:-<empty>}"
done

section "3. oidc_valid_host — what may be registered"
for h in api.example.com a a.b api-1.example.com x.y.z.example.com 1.2.3.4; do
    oidc_valid_host "$h"; rc_is 0 "$?" "valid: $h"
done
for h in "" "api example.com" "api_x.com" ".api.com" "api.com." "api..com" \
         "*.example.com" "api.example.com:443" "https://api.example.com" \
         "api.example.com/v1"; do
    oidc_valid_host "$h"; rc_is 1 "$?" "invalid: ${h:-<empty>}"
done
# Dash-edged labels (RFC 1123) — not just at the host edges, but at any interior
# label boundary. The interior cases used to be accepted.
for h in "-api.com" "api-.com" "api.-foo.com" "api.foo-.com" "a-.b-.com" "x.-y.z"; do
    oidc_valid_host "$h"; rc_is 1 "$?" "invalid (dash-edged label): $h"
done

# --- fixture store --------------------------------------------------------- #
# `.invalid` can never resolve (RFC 2606): a mint against these dies locally.
cat > "$OIDC_HOME/tenants.json" <<'JSON'
{
  "t1": { "type":"keycloak", "baseUrl":"https://auth.test.invalid", "realm":"main",
          "defaultClient":"c1",
          "clients":{"c1":{"grants":["client_credentials"],"scopes":["openid"]}},
          "users":{}, "allowedHosts":["api.test.invalid"] },
  "t2": { "type":"keycloak", "baseUrl":"https://auth2.test.invalid", "realm":"main",
          "defaultClient":"c1",
          "clients":{"c1":{"grants":["client_credentials"],"scopes":["openid"]}},
          "users":{}, "allowedHosts":[] },
  "tnohosts": { "type":"keycloak", "baseUrl":"https://auth3.test.invalid", "realm":"main",
          "defaultClient":"c1",
          "clients":{"c1":{"grants":["client_credentials"],"scopes":["openid"]}},
          "users":{} },
  "tlocal": { "type":"keycloak", "baseUrl":"http://localhost:1", "realm":"main",
          "defaultClient":"c1",
          "clients":{"c1":{"grants":["client_credentials"],"scopes":["openid"]}},
          "users":{} },
  "tgeneric": { "type":"oidc", "issuer":"https://issuer.test.invalid/x", "realm":"main",
          "defaultClient":"c1",
          "clients":{"c1":{"grants":["client_credentials"],"scopes":["openid"]}},
          "users":{} },
  "tempty": { "type":"keycloak", "realm":"main", "defaultClient":"c1",
          "clients":{"c1":{"grants":["client_credentials"],"scopes":["openid"]}},
          "users":{} }
}
JSON

section "4. oidc_tenant_allows_host / oidc_tenant_issuer_host"
oidc_tenant_allows_host t1 api.test.invalid;   rc_is 0 "$?" "t1 allows its registered host"
oidc_tenant_allows_host t1 evil.test.invalid;  rc_is 1 "$?" "t1 rejects an unregistered host"
oidc_tenant_allows_host t2 api.test.invalid;   rc_is 1 "$?" "t2 does NOT inherit t1's host (per-tenant scope)"
oidc_tenant_allows_host tnohosts api.test.invalid; rc_is 1 "$?" "absent allowedHosts = none (back-compat)"
oidc_tenant_allows_host nosuch api.test.invalid;   rc_is 1 "$?" "unknown tenant allows nothing"
eq "auth.test.invalid"   "$(oidc_tenant_issuer_host t1)"       "keycloak issuer host from baseUrl"
eq "issuer.test.invalid" "$(oidc_tenant_issuer_host tgeneric)" "non-keycloak issuer host from issuer"
eq ""                    "$(oidc_tenant_issuer_host tempty)"   "tenant with no baseUrl -> empty"
eq ""                    "$(oidc_tenant_issuer_host nosuch)"   "unknown tenant -> empty"
(
    OIDC_TENANTS_FILE="$SANDBOX/does-not-exist.json"
    eq "" "$(oidc_tenant_issuer_host t1)" "missing store -> empty issuer"
    oidc_tenant_allows_host t1 api.test.invalid; rc_is 1 "$?" "missing store allows nothing"
)

# --------------------------------------------------------------------------- #
# 2. oidc-curl: the per-request policy
# --------------------------------------------------------------------------- #
# curl_case <expected_rc> <desc> <stderr_substr|-> -- <oidc-curl args...>
#   5 = refused by policy · 4 = allowed, mint failed on the fixture · 1 = usage
curl_case() {
    local exp="$1" desc="$2" substr="$3"; shift 4
    local out rc okk=1
    out="$("$CURL_SH" "$@" 2>&1 </dev/null)"; rc=$?
    [ "$rc" = "$exp" ] || okk=0
    if [ "$substr" != "-" ]; then
        printf '%s' "$out" | grep -qiF -- "$substr" || okk=0
    fi
    if [ "$okk" = 1 ]; then ok; else
        bad "$desc :: exit=$rc (want $exp) :: $(printf '%s' "$out" | head -1)"
    fi
}
REFUSED=5; ALLOWED=4; USAGE=1

section "5. default mode — loopback only (unchanged behaviour)"
curl_case $ALLOWED "loopback 127.0.0.1 over http"  - -- --tenant t1 -- GET http://127.0.0.1:1/x
curl_case $ALLOWED "localhost over http"           - -- --tenant t1 -- GET http://localhost:1/x
curl_case $ALLOWED "127.x.y.z is loopback too"     - -- --tenant t1 -- GET http://127.9.9.9:1/x
curl_case $ALLOWED "IPv6 loopback"                 - -- --tenant t1 -- GET 'http://[::1]:1/x'
curl_case $REFUSED "external host, no flag"        "default mode is loopback only" -- --tenant t1 -- GET https://api.test.invalid/x
curl_case $REFUSED "the issuer itself, no flag"    "default mode is loopback only" -- --tenant t1 -- GET https://auth.test.invalid/x
curl_case $REFUSED "a registered host still needs --remote" "default mode is loopback only" -- --tenant t1 -- GET https://api.test.invalid/y

section "6. --remote — the tenant's registered allowedHosts"
curl_case $ALLOWED "registered host over https"       - -- --tenant t1 --remote -- GET https://api.test.invalid/x
curl_case $ALLOWED "registered host, uppercase URL"   - -- --tenant t1 --remote -- GET https://API.TEST.INVALID/x
curl_case $ALLOWED "registered host, port + query"    - -- --tenant t1 --remote -- GET 'https://api.test.invalid:8443/x?a=1'
curl_case $ALLOWED "loopback still works under --remote" - -- --tenant t1 --remote -- GET http://127.0.0.1:1/x
curl_case $REFUSED "unregistered host"                "is not registered for tenant" -- --tenant t1 --remote -- GET https://evil.test.invalid/x
curl_case $REFUSED "cross-tenant: t1's host from t2"  "is not registered for tenant 't2'" -- --tenant t2 --remote -- GET https://api.test.invalid/x
curl_case $REFUSED "tenant with no allowedHosts key"  "is not registered for tenant" -- --tenant tnohosts --remote -- GET https://api.test.invalid/x
curl_case $REFUSED "registered host over plaintext http" "must be https" -- --tenant t1 --remote -- GET http://api.test.invalid/x

section "7. --inspect — the tenant's own issuer host, and nothing else"
curl_case $ALLOWED "issuer host (userinfo)"        - -- --tenant t1 --inspect -- GET https://auth.test.invalid/realms/main/protocol/openid-connect/userinfo
curl_case $ALLOWED "issuer host (admin REST)"      - -- --tenant t1 --inspect -- GET https://auth.test.invalid/admin/realms/main/clients
curl_case $ALLOWED "issuer host, any method"       - -- --tenant t1 --inspect -- POST https://auth.test.invalid/admin/realms/main/clients --data '{}'
curl_case $ALLOWED "non-keycloak tenant issuer"    - -- --tenant tgeneric --inspect -- GET https://issuer.test.invalid/x
# REGRESSION: --inspect deliberately skips the loopback shortcut, so a tenant
# whose issuer IS a local Keycloak lands on the https check. Plaintext is keyed
# on the HOST, not the mode — http to this machine leaks nothing. This was a real
# bug: it used to refuse.
curl_case $ALLOWED "loopback issuer over plaintext http" - -- --tenant tlocal --inspect -- GET http://localhost:1/admin/realms/main/clients
curl_case $REFUSED "a registered host is NOT the issuer" "reaches only tenant" -- --tenant t1 --inspect -- GET https://api.test.invalid/x
curl_case $REFUSED "another tenant's issuer"       "reaches only tenant" -- --tenant t2 --inspect -- GET https://auth.test.invalid/x
curl_case $REFUSED "loopback is not t1's issuer"   "reaches only tenant" -- --tenant t1 --inspect -- GET http://127.0.0.1:1/x
curl_case $REFUSED "tenant with an unresolvable issuer" "cannot resolve the issuer host" -- --tenant tempty --inspect -- GET https://auth.test.invalid/x

section "8. host spoofing"
curl_case $REFUSED "userinfo trick (registered@evil)"  "is not registered" -- --tenant t1 --remote -- GET https://api.test.invalid@evil.test.invalid/x
curl_case $REFUSED "loopback-lookalike DNS name"       "is not registered" -- --tenant t1 --remote -- GET https://127.0.0.1.evil.test.invalid/x
curl_case $REFUSED "registered host only in the path"  "is not registered" -- --tenant t1 --remote -- GET https://evil.test.invalid/api.test.invalid
curl_case $REFUSED "registered host only in the query" "is not registered" -- --tenant t1 --remote -- GET 'https://evil.test.invalid/x?h=api.test.invalid'
curl_case $REFUSED "registered host as a subdomain"    "is not registered" -- --tenant t1 --remote -- GET https://api.test.invalid.evil.test.invalid/x
curl_case $REFUSED "subdomain of a registered host"    "is not registered" -- --tenant t1 --remote -- GET https://sub.api.test.invalid/x
curl_case $REFUSED "issuer as a subdomain, --inspect"  "reaches only tenant" -- --tenant t1 --inspect -- GET https://auth.test.invalid.evil.test.invalid/x
curl_case $REFUSED "non-http scheme"                   "must start with http" -- --tenant t1 --remote -- GET ftp://api.test.invalid/x
curl_case $REFUSED "file scheme"                       "must start with http" -- --tenant t1 -- GET file:///etc/hosts
curl_case $REFUSED "no host in the URL"                "could not parse a host" -- --tenant t1 -- GET http:///x

section "9. mode wiring & argument handling"
curl_case $USAGE   "--inspect and --remote together"  "mutually exclusive" -- --tenant t1 --inspect --remote -- GET https://auth.test.invalid/x
curl_case $USAGE   "--remote and --inspect together"  "mutually exclusive" -- --tenant t1 --remote --inspect -- GET https://auth.test.invalid/x
curl_case $ALLOWED "--inspect twice is fine"          - -- --tenant t1 --inspect --inspect -- GET https://auth.test.invalid/x
curl_case $ALLOWED "--remote twice is fine"           - -- --tenant t1 --remote --remote -- GET https://api.test.invalid/x
curl_case $ALLOWED "--tenant=<id> form"               - -- --tenant=t1 --remote -- GET https://api.test.invalid/x
curl_case $ALLOWED "positional tenant"                - -- t1 --remote -- GET https://api.test.invalid/x
curl_case $USAGE   "missing tenant"                   "missing tenant" -- -- GET http://127.0.0.1:1/x
curl_case $USAGE   "unknown selection flag"           "unknown selection flag" -- --tenant t1 --bogus -- GET http://127.0.0.1:1/x
curl_case $USAGE   "unexpected positional"            "unexpected argument" -- t1 extra -- GET http://127.0.0.1:1/x
curl_case $USAGE   "missing METHOD/URL after --"      "need <METHOD> <URL>" -- --tenant t1 --
curl_case $USAGE   "unsupported method"               "unsupported method" -- --tenant t1 -- BREW http://127.0.0.1:1/x
curl_case $ALLOWED "method is case-insensitive"       - -- --tenant t1 -- get http://127.0.0.1:1/x
curl_case $USAGE   "unknown request option"           "unknown request option" -- --tenant t1 -- GET http://127.0.0.1:1/x --bogus v
curl_case $USAGE   "--data and --form together"       "mutually exclusive" -- --tenant t1 -- POST http://127.0.0.1:1/x --data '{}' --form 'a=b'
# Both spellings of each selection flag reach the mint. An unknown client/user is
# rejected against tenants.json before anything touches the Keychain, so the flag
# plumbing is observable here with no credential — exit 4 (not 5) is itself the
# assertion that the target passed policy and the flag was carried to the mint.
curl_case $ALLOWED "--client <id>"      "no client 'nosuch'" -- --tenant t1 --client nosuch  -- GET http://127.0.0.1:1/x
curl_case $ALLOWED "--client=<id>"      "no client 'nosuch'" -- --tenant t1 --client=nosuch  -- GET http://127.0.0.1:1/x
curl_case $ALLOWED "-c <id>"            "no client 'nosuch'" -- --tenant t1 -c nosuch        -- GET http://127.0.0.1:1/x
curl_case $ALLOWED "--user <alias>"     "unknown user alias" -- --tenant t1 --user nosuch    -- GET http://127.0.0.1:1/x
curl_case $ALLOWED "--user=<alias>"     "unknown user alias" -- --tenant t1 --user=nosuch    -- GET http://127.0.0.1:1/x
curl_case $ALLOWED "-u <alias>"         "unknown user alias" -- --tenant t1 -u nosuch        -- GET http://127.0.0.1:1/x
# The inline `=` forms of the request options — a separate parse arm from the
# space-separated forms above, so a header smuggled in this way must hit the same
# Authorization refusal.
curl_case $USAGE   "--data= and --form= together"  "mutually exclusive"   -- --tenant t1 -- POST http://127.0.0.1:1/x --data=a --form=b
curl_case $REFUSED "--header= inline form"         "refusing to override" -- --tenant t1 -- GET http://127.0.0.1:1/x '--header=Authorization: Bearer x'
curl_case $REFUSED "overriding Authorization"         "refusing to override" -- --tenant t1 -- GET http://127.0.0.1:1/x --header 'Authorization: Bearer x'
curl_case $REFUSED "Authorization, odd casing/space"  "refusing to override" -- --tenant t1 -- GET http://127.0.0.1:1/x --header 'AUTHORIZATION : Bearer x'
curl_case $REFUSED "header with a newline"            "may not contain newlines" -- --tenant t1 -- GET http://127.0.0.1:1/x --header 'X-A: b
Set-Cookie: c'
curl_case 0        "--help"                           "loopback targets only" -- --help

# Policy is enforced BEFORE the mint — the whole point: a refusal must not have
# minted anything. Nothing may have been cached for a refused target.
section "10. a refusal never mints"
rm -f "$OIDC_HOME/run/"*.token 2>/dev/null
"$CURL_SH" --tenant t1 -- GET https://api.test.invalid/x >/dev/null 2>&1 </dev/null
n="$(find "$OIDC_HOME/run" -name '*.token' -type f 2>/dev/null | wc -l | tr -d ' ')"
eq "0" "$n" "refused request cached no token"

# --------------------------------------------------------------------------- #
# 3. End-to-end against a throwaway issuer on loopback
# --------------------------------------------------------------------------- #
# Everything above stops at the policy gate. This section mints a REAL (fake)
# token from a local stand-in and completes the request, so the paths that only
# exist after a mint — the audit line, the token scrubbing, the non-2xx trace —
# are exercised for real. No credential, no network.
section "11. end-to-end (local stand-in issuer)"

FAKE_PY="$SANDBOX/fake_issuer.py"
cat > "$FAKE_PY" <<'PY'
import json, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
PORT = int(sys.argv[1]); BASE = f"http://127.0.0.1:{PORT}"
# The 'glob' realm mints a token containing bracket metacharacters. A real JWT is
# base64url and can never look like this, but bash's ${var//$T/...} treats the
# needle as a GLOB, so such a token defeats the redaction — which is exactly the
# fallback the "refused to surface it" check exists for.
TOKENS = {"main": "FAKE-TOKEN-abc123", "glob": "FAKE[a]bc-TOKEN"}
def realm_of(path):
    m = re.search(r"/realms/([^/]+)/", path)
    return m.group(1) if m else "main"
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, obj, ctype="application/json", headers=None):
        body = obj.encode() if isinstance(obj, str) else json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", ctype)
        for k, v in (headers or {}).items(): self.send_header(k, v)
        self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)
    def _route(self):
        p = self.path.split("?")[0]; r = realm_of(p)
        if p.endswith("/.well-known/openid-configuration"):
            return self._send(200, {"issuer": f"{BASE}/realms/{r}",
                                    "token_endpoint": f"{BASE}/realms/{r}/token"})
        if p.endswith("/whoami"):  return self._send(200, {"sub": "service-account"})
        # Hands the caller's own Authorization header back — the hostile case the
        # scrubber exists for.
        if p.endswith("/reflect"): return self._send(200, {"you_sent": self.headers.get("Authorization","")})
        if p.endswith("/boom"):    return self._send(403, {"error":"forbidden","message":"nope, not allowed"})
        if p.endswith("/html"):    return self._send(500, "<html><title>Gateway exploded</title></html>", "text/html")
        # A 3xx pointing off-host: oidc-curl must NOT follow it (no -L), or an
        # authorized target could bounce the Authorization header anywhere.
        if p.endswith("/redirect"):
            return self._send(302, {"moved": True}, headers={"Location": "https://evil.test.invalid/stolen"})
        m = re.search(r"/status/(\d+)$", p)
        if m: return self._send(int(m.group(1)), {"message": "canned status"})
        if p.endswith("/echo"):
            n = int(self.headers.get("Content-Length", 0) or 0)
            return self._send(200, {"got": self.rfile.read(n).decode("utf8","replace")[:200],
                                    "ctype": self.headers.get("Content-Type","")})
        return self._send(404, {"error": "not_found"})
    do_GET = do_HEAD = do_DELETE = do_PUT = do_PATCH = do_OPTIONS = _route
    def do_POST(self):
        p = self.path.split("?")[0]
        if p.endswith("/token"):
            self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
            return self._send(200, {"access_token": TOKENS[realm_of(p)],
                                    "expires_in": 300, "token_type": "Bearer"})
        return self._route()
HTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY

# Grab a free port, then hand it to the stand-in.
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
python3 "$FAKE_PY" "$PORT" &
FAKE_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    curl -sS -o /dev/null "http://127.0.0.1:$PORT/realms/main/.well-known/openid-configuration" 2>/dev/null && break
    sleep 0.1
done

# An e2e tenant whose issuer IS the stand-in, plus a registered host that cannot
# resolve — that pairing is what lets the --remote audit path be observed (see
# "audit survives a failed request" below).
updated="$(jq --arg b "http://127.0.0.1:$PORT" '. + {
  "e2e": { "type":"keycloak", "baseUrl":$b, "realm":"main", "defaultClient":"c1",
           "clients":{"c1":{"grants":["client_credentials"],"scopes":["openid"]}},
           "users":{}, "allowedHosts":["api.test.invalid"] },
  "eglob": { "type":"keycloak", "baseUrl":$b, "realm":"glob", "defaultClient":"c1",
           "clients":{"c1":{"grants":["client_credentials"],"scopes":["openid"]}},
           "users":{}, "allowedHosts":[] } }' "$OIDC_HOME/tenants.json")"
printf '%s\n' "$updated" > "$OIDC_HOME/tenants.json"

FAKE_TOKEN="FAKE-TOKEN-abc123"
GLOB_TOKEN="FAKE[a]bc-TOKEN"
IS="http://127.0.0.1:$PORT/realms/main"
ISG="http://127.0.0.1:$PORT/realms/glob"

# Drop xtrace output when this suite is run under a coverage harness (which sets
# PS4 to a marker and exports SHELLOPTS=xtrace). xtrace echoes every command's
# arguments — including the Authorization header — so without this filter the
# INSTRUMENTATION would put the token on stderr and the scrub assertions below
# would blame the script for the harness's own leak.
#
# Only the FIRST line of a traced command carries the PS4 marker: an argument
# containing a newline (oidc-curl's `curl -w $'\n%{http_code}...'`) trails onto
# following lines that look like bare output. Dropping just the marked line would
# leave that tail — token and all — behind, so entries are consumed whole by
# tracking quote balance (xtrace single-quotes any argument it has to escape).
# \047 is the single quote, spelled in octal to stay readable inside this quoting.
#
# A normal run emits no marked lines at all, so this is a strict no-op there and
# the assertions below keep their teeth.
strip_trace() {
    awk '
    { if (inq) { if (gsub(/\047/, "&") % 2 == 1) inq = 0; next }
      if (index($0, "@COV|") > 0) { if (gsub(/\047/, "&") % 2 == 1) inq = 1; next }
      print }'
}

# e2e <desc> <expected_rc> -- <args...>  → sets $E_OUT / $E_ERR / $E_RC
e2e() {
    local desc="$1" exp="$2"; shift 3
    E_OUT="$("$CURL_SH" "$@" 2>"$SANDBOX/e.err" </dev/null)"; E_RC=$?
    E_ERR="$(strip_trace < "$SANDBOX/e.err")"
    if [ "$E_RC" = "$exp" ]; then ok; else bad "$desc :: exit=$E_RC (want $exp) :: $(printf '%s' "$E_ERR" | head -1)"; fi
}

: > "$LOG"
e2e "GET through --inspect succeeds" 0 -- --tenant e2e --inspect -- GET "$IS/whoami"
printf '%s' "$E_OUT" | grep -q 'service-account' && ok || bad "e2e --inspect: body not returned"
printf '%s' "$E_ERR" | grep -q 'HTTP 200' && ok || bad "e2e --inspect: status line missing on stderr"

# The reason --inspect needs no registration is that the issuer already HAS the
# token. It still gets audited: a call against an SSO provider is worth a trace
# wherever that provider lives.
jq -e 'select(.op=="curl-inspect" and .http=="200" and .tenant=="e2e" and .host=="127.0.0.1" and .method=="GET")' "$LOG" >/dev/null 2>&1 \
    && ok || bad "audit: no curl-inspect line for a successful --inspect call"

# The token must never reach the caller, even from an endpoint that deliberately
# echoes the Authorization header straight back.
: > "$LOG"
e2e "endpoint reflecting the token still returns 0" 0 -- --tenant e2e --inspect -- GET "$IS/reflect"
case "$E_OUT$E_ERR" in
    *"$FAKE_TOKEN"*) bad "SCRUB: the token leaked verbatim into the output" ;;
    *) ok ;;
esac
printf '%s' "$E_OUT" | grep -q 'REDACTED-TOKEN' && ok || bad "scrub: reflected token was not replaced with the redaction marker"

# A non-2xx is surfaced (exit stays 0) and traced with the canonical reason plus
# a short detail lifted from the body — never the body itself.
: > "$LOG"
e2e "403 is surfaced, not an error exit" 0 -- --tenant e2e --inspect -- GET "$IS/boom"
printf '%s' "$E_OUT" | grep -q 'not allowed' && ok || bad "non-2xx: body not surfaced"
jq -e 'select(.level=="error" and .http=="403" and .reason=="Forbidden" and (.detail|test("nope")))' "$LOG" >/dev/null 2>&1 \
    && ok || bad "non-2xx: no error line with reason+detail"
jq -e 'select(.op=="curl-inspect" and .http=="403")' "$LOG" >/dev/null 2>&1 \
    && ok || bad "non-2xx: --inspect call was not audited"

: > "$LOG"
e2e "HTML error yields a <title> detail" 0 -- --tenant e2e --inspect -- GET "$IS/html"
jq -e 'select(.level=="error" and .http=="500" and (.detail|test("Gateway exploded")))' "$LOG" >/dev/null 2>&1 \
    && ok || bad "non-2xx: <title> not extracted as the detail"

: > "$LOG"
e2e "POST --data reaches the server" 0 -- --tenant e2e --inspect -- POST "$IS/echo" --data '{"k":1}' --header 'Content-Type: application/json'
printf '%s' "$E_OUT" | grep -q '{\\"k\\":1}' && ok || bad "--data: body not delivered"
e2e "POST --form reaches the server" 0 -- --tenant e2e --inspect -- POST "$IS/echo" --form 'kind=avatar'
printf '%s' "$E_OUT" | grep -q 'multipart/form-data' && ok || bad "--form: multipart content-type not set by curl"

# The inline `=` forms carry a body just as the space-separated ones do.
e2e "POST --data=<body> inline form" 0 -- --tenant e2e --inspect -- POST "$IS/echo" '--data={"k":2}' '--header=Content-Type: application/json'
printf '%s' "$E_OUT" | grep -q '{\\"k\\":2}' && ok || bad "--data=: body not delivered"
e2e "POST --form=<part> inline form" 0 -- --tenant e2e --inspect -- POST "$IS/echo" '--form=kind=avatar'
printf '%s' "$E_OUT" | grep -q 'multipart/form-data' && ok || bad "--form=: multipart content-type not set by curl"

# --refresh is passed through to the mint (it re-mints rather than reusing cache).
e2e "--refresh forces a fresh mint" 0 -- --tenant e2e --refresh --inspect -- GET "$IS/whoami"
printf '%s' "$E_OUT" | grep -q 'service-account' && ok || bad "--refresh: body not returned"

# Plain loopback is NOT audited — existing log volume must be unchanged.
: > "$LOG"
"$CURL_SH" --tenant e2e -- GET "http://127.0.0.1:$PORT/realms/main/whoami" >/dev/null 2>&1 </dev/null
n="$(wc -l < "$LOG" | tr -d ' ')"
eq "0" "$n" "plain loopback writes no audit line (log volume unchanged)"

# The audit is written BEFORE the response is read, so a request that fails on
# the wire still leaves a trace of where the token went. This is the case that
# proves the ordering: the host cannot resolve, so curl fails — but the token was
# already handed over, and the line must exist anyway.
: > "$LOG"
e2e "--remote to an unresolvable registered host fails" 4 -- --tenant e2e --remote -- GET https://api.test.invalid/x
jq -e 'select(.op=="curl-remote" and .tenant=="e2e" and .host=="api.test.invalid" and .method=="GET" and (has("http")|not))' "$LOG" >/dev/null 2>&1 \
    && ok || bad "audit: --remote line missing (or has an http field) after a transport failure"

# --------------------------------------------------------------------------- #
section "12. http_reason — the canonical phrase behind every traced status"
# A non-2xx is traced with a phrase from a STATIC map, never from the response.
# That map is what lets the log say what went wrong without ever carrying body
# content, so each arm is worth pinning: a typo here would silently mislabel a
# real failure.
reason_is() {  # <code> <expected reason>
    : > "$LOG"
    "$CURL_SH" --tenant e2e --inspect -- GET "$IS/status/$1" >/dev/null 2>&1 </dev/null
    if jq -e --arg h "$1" --arg r "$2" \
        'select(.level=="error" and .http==$h and .reason==$r)' "$LOG" >/dev/null 2>&1
    then ok; else bad "http_reason: $1 not traced as '$2'"; fi
}
reason_is 400 "Bad Request";           reason_is 401 "Unauthorized"
reason_is 402 "Payment Required";      reason_is 403 "Forbidden"
reason_is 404 "Not Found";             reason_is 405 "Method Not Allowed"
reason_is 406 "Not Acceptable";        reason_is 408 "Request Timeout"
reason_is 409 "Conflict";              reason_is 410 "Gone"
reason_is 413 "Payload Too Large";     reason_is 415 "Unsupported Media Type"
reason_is 422 "Unprocessable Entity";  reason_is 429 "Too Many Requests"
reason_is 500 "Internal Server Error"; reason_is 501 "Not Implemented"
reason_is 502 "Bad Gateway";           reason_is 503 "Service Unavailable"
reason_is 504 "Gateway Timeout"
# An unmapped code still traces — just with no reason field rather than a guess.
: > "$LOG"
"$CURL_SH" --tenant e2e --inspect -- GET "$IS/status/418" >/dev/null 2>&1 </dev/null
jq -e 'select(.level=="error" and .http=="418" and (has("reason")|not))' "$LOG" >/dev/null 2>&1 \
    && ok || bad "http_reason: an unmapped status should trace with no reason field"

section "13. a 3xx is reported, never followed"
# No -L, deliberately: a target authorized by the mode could otherwise 3xx the
# Authorization header onward to a host that was never authorized. This redirect
# points at an unresolvable host, so had it been followed the request would have
# died (exit 4) instead of returning the 302 body.
: > "$LOG"
e2e "302 returns the redirect itself, exit 0" 0 -- --tenant e2e --inspect -- GET "$IS/redirect"
printf '%s' "$E_OUT" | grep -q 'moved' && ok || bad "3xx: the redirect's own body was not returned"
case "$E_OUT$E_ERR" in
    *stolen*) bad "REDIRECT: oidc-curl followed a 3xx to an unauthorized host" ;;
    *) ok ;;
esac
jq -e 'select(.level=="error" and .http=="302" and .reason=="Redirect")' "$LOG" >/dev/null 2>&1 \
    && ok || bad "3xx: not traced with the Redirect reason"

section "14. a token the redaction cannot match is refused, not surfaced"
# The scrubber's first pass is ${resp//$T/…}, where bash treats the needle as a
# GLOB — so a token containing brackets does not match its own literal, and the
# substitution silently does nothing. The hard guarantee behind it is a QUOTED
# case pattern (a literal substring test), which must catch what the glob missed
# and refuse to print anything at all.
#
# A real JWT is base64url and can never contain these characters; this tenant
# exists solely to make that last line of defence observable.
: > "$LOG"
e2e "unredactable reflected token fails closed" 4 -- --tenant eglob --inspect -- GET "$ISG/reflect"
printf '%s' "$E_ERR" | grep -q 'refusing to surface it' \
    && ok || bad "glob token: failed for the wrong reason (expected the reflect guard)"
case "$E_OUT$E_ERR" in
    *"$GLOB_TOKEN"*) bad "GLOB SCRUB: the unredactable token still reached the caller" ;;
    *) ok ;;
esac
# Failing closed still leaves the audit trail: the token was already on the wire.
jq -e 'select(.op=="curl-inspect" and .tenant=="eglob" and .http=="200")' "$LOG" >/dev/null 2>&1 \
    && ok || bad "glob token: refusing to surface the body must not skip the audit line"

# --------------------------------------------------------------------------- #
# 4. tenant add-host / remove-host — the human-only trust anchor
# --------------------------------------------------------------------------- #
section "15. tenant add-host — validation & the TTY gate"

# A pty driver: add-host is deliberately unusable without a real terminal, so the
# only way to test the happy path is to give it one. Answers the [y/N] prompt.
PTY_PY="$SANDBOX/pty_run.py"
cat > "$PTY_PY" <<'PY'
import os, pty, select, sys, time
answer, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
buf, sent, deadline = b"", False, time.time() + 15
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if not r:
        continue
    try:
        d = os.read(fd, 4096)
    except OSError:
        break
    if not d:
        break
    buf += d
    if not sent and b"[y/N]" in buf and answer:
        os.write(fd, (answer + "\n").encode()); sent = True
os.close(fd)
_, status = os.waitpid(pid, 0)
sys.stdout.buffer.write(buf)
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
PY

# host_case <expected_rc> <desc> <substr|-> -- <token args...>   (NO tty)
host_case() {
    local exp="$1" desc="$2" substr="$3"; shift 4
    local out rc okk=1
    out="$("$TOKEN_SH" "$@" 2>&1 </dev/null)"; rc=$?
    [ "$rc" = "$exp" ] || okk=0
    if [ "$substr" != "-" ]; then printf '%s' "$out" | grep -qiF -- "$substr" || okk=0; fi
    if [ "$okk" = 1 ]; then ok; else bad "$desc :: exit=$rc (want $exp) :: $(printf '%s' "$out" | head -1)"; fi
}
# pty_case <expected_rc> <desc> <answer> <substr|-> -- <token args...>  (real tty)
pty_case() {
    local exp="$1" desc="$2" ans="$3" substr="$4"; shift 5
    local out rc okk=1
    out="$(python3 "$PTY_PY" "$ans" "$TOKEN_SH" "$@" 2>&1)"; rc=$?
    [ "$rc" = "$exp" ] || okk=0
    if [ "$substr" != "-" ]; then printf '%s' "$out" | grep -qiF -- "$substr" || okk=0; fi
    if [ "$okk" = 1 ]; then ok; else bad "$desc :: exit=$rc (want $exp) :: $(printf '%s' "$out" | tr -d '\r' | head -1)"; fi
}

# THE security property: without a terminal, registration is impossible. An
# agent's shell has no tty, so this is what stops it authorizing its own target.
host_case 1 "add-host refuses without a tty"    "must be run by you, interactively" -- tenant add-host t1 new.test.invalid
host_case 1 "remove-host refuses without a tty" "must be run by you, interactively" -- tenant remove-host t1 api.test.invalid
# ...and it truly did not write.
oidc_tenant_allows_host t1 new.test.invalid; rc_is 1 "$?" "add-host without a tty stored nothing"
oidc_tenant_allows_host t1 api.test.invalid; rc_is 0 "$?" "remove-host without a tty removed nothing"

host_case 1 "add-host needs a host argument"   "usage:" -- tenant add-host t1
host_case 1 "add-host needs both arguments"    "usage:" -- tenant add-host
# Unknown tenant is rejected BEFORE the tty gate, so it is observable here.
host_case 3 "add-host rejects an unknown tenant" "unknown tenant" -- tenant add-host nosuch api.test.invalid

# Input shapes that would store an entry which could never match a parsed host.
pty_case 1 "add-host rejects a URL"        y "not a URL"        -- tenant add-host t1 https://new.test.invalid
pty_case 1 "add-host rejects a path"       y "without a path"   -- tenant add-host t1 new.test.invalid/v1
pty_case 1 "add-host rejects a port"       y "without a port"   -- tenant add-host t1 new.test.invalid:443
pty_case 1 "add-host rejects a wildcard"   y "wildcards are not supported" -- tenant add-host t1 '*.test.invalid'
pty_case 1 "add-host rejects bad chars"    y "not a valid hostname" -- tenant add-host t1 'new_host.test.invalid'
pty_case 1 "add-host rejects loopback"     y "nothing to register" -- tenant add-host t1 localhost
pty_case 1 "add-host rejects 127.0.0.1"    y "nothing to register" -- tenant add-host t1 127.0.0.1
pty_case 1 "add-host rejects the tenant's own issuer" y "--inspect" -- tenant add-host t1 auth.test.invalid

# The happy path, and the refusal path.
pty_case 1 "declining the prompt registers nothing" n "NOT registered" -- tenant add-host t1 new.test.invalid
oidc_tenant_allows_host t1 new.test.invalid; rc_is 1 "$?" "declined host was not stored"

pty_case 0 "add-host registers on confirmation" y "Registered" -- tenant add-host t1 new.test.invalid
oidc_tenant_allows_host t1 new.test.invalid; rc_is 0 "$?" "confirmed host IS stored"
# It must not have widened any OTHER tenant.
oidc_tenant_allows_host t2 new.test.invalid; rc_is 1 "$?" "registering for t1 did not widen t2"
# The confirmation prompt has to name what is being authorized.
out="$(python3 "$PTY_PY" n "$TOKEN_SH" tenant add-host t2 other.test.invalid 2>&1)"
printf '%s' "$out" | grep -q 'live-token destination' && ok || bad "add-host prompt does not say it authorizes a live-token destination"
printf '%s' "$out" | grep -q 'auth2.test.invalid' && ok || bad "add-host prompt does not show the tenant's issuer (prod-vs-testing check)"

# Idempotent: re-registering is a no-op that doesn't re-prompt.
pty_case 0 "re-adding an existing host is a no-op" "" "already registered" -- tenant add-host t1 new.test.invalid
n="$(jq -r '.t1.allowedHosts | length' "$OIDC_HOME/tenants.json")"
eq "2" "$n" "no duplicate entry after re-adding"

pty_case 0 "remove-host revokes" y "-" -- tenant remove-host t1 new.test.invalid
oidc_tenant_allows_host t1 new.test.invalid; rc_is 1 "$?" "removed host is gone"
oidc_tenant_allows_host t1 api.test.invalid; rc_is 0 "$?" "remove-host left the other host alone"

# `list` must surface allowedHosts — it's how the agent knows what --remote can reach.
section "16. list surfaces allowedHosts"
lst="$("$TOKEN_SH" list 2>/dev/null </dev/null)"
printf '%s' "$lst" | jq -e '.[] | select(.tenant=="t1") | .allowedHosts | index("api.test.invalid")' >/dev/null 2>&1 \
    && ok || bad "list: t1's allowedHosts not reported"
printf '%s' "$lst" | jq -e '.[] | select(.tenant=="tnohosts") | .allowedHosts == []' >/dev/null 2>&1 \
    && ok || bad "list: a tenant without allowedHosts should report [] (back-compat)"

# --------------------------------------------------------------------------- #
# 5. oidc-guard — the second lock
# --------------------------------------------------------------------------- #
section "17. oidc-guard blocks agent self-authorization"
# g <expected_exit> <desc> <command>   (2 = blocked, 0 = allowed)
g() {
    local exp="$1" desc="$2" cmd="$3" out rc
    out="$(jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}' | "$GUARD" 2>&1)"; rc=$?
    if [ "$rc" = "$exp" ]; then ok; else bad "$desc :: exit=$rc (want $exp) :: $(printf '%s' "$out" | head -1)"; fi
}
# The subcommand is assembled at runtime so this file can't trip the live guard
# on its own source when an agent greps or runs it.
AH="add-""host"; RH="remove-""host"
g 2 "blocks tenant add-host"              "oidc-token tenant $AH t1 api.example.com"
g 2 "blocks tenant remove-host"           "oidc-token tenant $RH t1 api.example.com"
g 2 "blocks the .sh form"                 "oidc-token.sh tenant $AH t1 api.example.com"
g 2 "blocks the full-path form"           "$HOME/.claude/scripts/oidc-token.sh tenant $AH t1 api.example.com"
g 2 "blocks it mid-pipeline"              "echo hi && oidc-token tenant $AH t1 api.example.com"
g 0 "allows tenant add (interactive reg)" "oidc-token tenant add"
g 0 "allows list"                         "oidc-token list"
g 0 "allows a mint"                       "oidc-token --tenant t1"
g 0 "allows oidc-curl --remote"           "oidc-curl --tenant t1 --remote -- GET https://api.example.com/x"
g 0 "allows oidc-curl --inspect"          "oidc-curl --tenant t1 --inspect -- GET https://auth.example.com/x"
# Documented gap, asserted so the doc stays honest: the rule is textual, so a
# dynamically-built subcommand slips past it. That is WHY require_interactive
# exists and is the real lock — this rule is the one that explains itself.
g 0 "known gap: dynamically-built subcommand evades the text rule" 'oidc-token tenant "add-""host" t1 api.example.com'

# The guard is registered for Read as well as Bash: a cached token is a file, and
# reading it directly would put the token in context just as surely as printing
# it. This arm keys on file_path, not command, so it needs its own payload shape.
# gf <expected_exit> <desc> <tool> <file_path>
gf() {
    local exp="$1" desc="$2" tool="$3" path="$4" out rc
    out="$(jq -nc --arg t "$tool" --arg p "$path" '{tool_name:$t, tool_input:{file_path:$p}}' | "$GUARD" 2>&1)"; rc=$?
    if [ "$rc" = "$exp" ]; then ok; else bad "$desc :: exit=$rc (want $exp) :: $(printf '%s' "$out" | head -1)"; fi
}
# The guard's other deny rules. They predate the host policy, but they share this
# hook — an edit to any rule can break its neighbours, and they had no coverage at
# all, so they are pinned here alongside the rule this feature added.
#
# Same runtime-assembly trick as AH/RH above, for the same reason: several of
# these rules match ANYWHERE in a command, so spelling the payloads literally
# would make an innocent `grep` of this very file trip the live guard.
BEARER="oidc-""bearer"; SEC="security find-generic-""password"; CURL_V="curl -""v"
g 2 "blocks the raw-token printer"           "$BEARER t1"
g 2 "blocks the printer's .sh form"          "$BEARER.sh t1"
g 2 "blocks the printer by full path"        "$HOME/.claude/scripts/$BEARER.sh t1"
g 2 "blocks the printer in a substitution"   "curl -H \"Authorization: Bearer \$($BEARER t1)\" http://x"
g 0 "allows the printer merely mentioned"    "echo \"see $BEARER for a raw token\""
g 2 "blocks referencing a cached token file" "cat \$HOME/.claude/oidc/run/t1__c1.token"
g 2 "blocks Keychain secret extraction"      "$SEC -s foo -w"
g 2 "blocks reading an OIDC Keychain item"   "$SEC -s 'oidc:t1:c1'"
g 2 "blocks verbose curl"                    "$CURL_V https://api.example.com/x"
g 2 "blocks curl --trace"                    "curl --trace out.txt https://api.example.com/x"
# Documented gaps/tradeoffs, asserted so the guard's header comment stays honest.
g 0 "known gap: bundled short verbose form (curl -sv) slips through" "curl -sv https://api.example.com/x"
g 0 "allows grep -iv — the false positive the whole-word rule buys" "grep -iv foo f | curl https://x"

# Enforcement must not depend on logging. The guard sources log-lib.sh
# best-effort and falls back to a no-op logger; a copy with no lib reachable
# proves a broken log can't silently disarm the guard.
mkdir -p "$SANDBOX/iso/hooks" "$SANDBOX/iso/scripts"
cp "$GUARD" "$SANDBOX/iso/hooks/oidc-guard.sh"
out="$(jq -nc --arg c "oidc-token tenant $AH t1 api.example.com" \
    '{tool_name:"Bash", tool_input:{command:$c}}' | "$SANDBOX/iso/hooks/oidc-guard.sh" 2>&1)"; rc=$?
[ "$rc" = 2 ] && ok || bad "guard: must still block when log-lib.sh is unavailable (exit=$rc)"

gf 2 "blocks Read of a cached token file"      Read "$HOME/.claude/oidc/run/t1__c1.token"
gf 2 "blocks Read of any path under the run dir" Read "$HOME/.claude/oidc/run/nested/x.token"
gf 0 "allows Read of the tenant registry"      Read "$HOME/.claude/oidc/tenants.json"
gf 0 "allows Read of an unrelated file"        Read "$HOME/.claude/settings.json"
# The rule itself keys only on file_path, so it fires for whatever tool is routed
# to it — but routing is settings.json's job, and only Read is wired (asserted
# below). Passing tool_name:"Edit" here would prove nothing about production; the
# honest coverage of Edit/Write is the wiring assertion in the static section.

# --------------------------------------------------------------------------- #
# 6. Static checks
# --------------------------------------------------------------------------- #
section "18. static"
for f in oidc-curl.sh oidc-lib.sh oidc-manage.sh oidc-token.sh; do
    bash -n "$SCRIPTS/$f" 2>/dev/null && ok || bad "syntax error in $f"
done
bash -n "$GUARD" 2>/dev/null && ok || bad "syntax error in oidc-guard.sh"
# The guard has to be registered, or none of section 17 protects anything in real life.
SETTINGS="$DIR/../settings.json"
jq -e '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[] | select(.command|test("oidc-guard"))' "$SETTINGS" >/dev/null 2>&1 \
    && ok || bad "wiring: oidc-guard is not registered for Bash in settings.json"
# Likewise for the file_path arm: without a Read matcher, the token-file rule is
# dead code no matter how well it tests in isolation.
jq -e '.hooks.PreToolUse[] | select(.matcher=="Read") | .hooks[] | select(.command|test("oidc-guard"))' "$SETTINGS" >/dev/null 2>&1 \
    && ok || bad "wiring: oidc-guard is not registered for Read in settings.json"
# KNOWN GAP, asserted so the guard's header comment stays honest: that comment
# says "Read/Edit/Write of a cached token file", but only Read is routed here.
# Read is the arm that matters (it's the one that would put a token in context);
# Edit is reachable only after a Read that this guard already blocks, and Write
# would overwrite a token rather than reveal one. This assertion fails the day
# Edit/Write get wired — at which point delete it and drop the comment's caveat.
for t in Edit Write; do
    if jq -e --arg t "$t" '.hooks.PreToolUse[] | select(.matcher==$t) | .hooks[] | select(.command|test("oidc-guard"))' "$SETTINGS" >/dev/null 2>&1
    then bad "wiring: oidc-guard IS now registered for $t — update the known-gap note"; else ok; fi
done

# --------------------------------------------------------------------------- #
printf '\n\033[1m=================== RESULTS ===================\033[0m\n'
printf 'passed: %s   failed: %s\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
    printf '\nFAILURES:\n'
    for f in "${FAILS[@]}"; do printf '  - %s\n' "$f"; done
fi
printf '\033[1m==============================================\033[0m\n'
[ "$fail" -eq 0 ]
