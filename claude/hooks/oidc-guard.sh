#!/bin/bash
# oidc-guard.sh — PreToolUse guard that keeps OIDC secrets/tokens out of model context.
#
# Registered for the Bash and Read tools. It DENIES (exit 2) any tool call that
# would surface plaintext credential material to Claude:
#   - reading/printing a cached token file (~/.claude/oidc/run/*.token)
#   - running the raw-token printer (oidc-bearer)
#   - extracting a secret straight from the Keychain (security ... -w/-g)
#   - running curl verbosely (--trace / -v), which dumps Authorization headers
#   - registering a token destination (oidc-token tenant add-host/remove-host),
#     which would let an agent widen its own reach
# Everything else passes — including oidc-token.sh (emits metadata only) and
# oidc-curl.sh (mints + consumes the request itself, returning only the response
# body with the token scrubbed, so the token never enters context; where it may
# send that token is policed by oidc-curl's own modes, not here).
#
# Known gap: the verbose-curl rule matches -v/--verbose/--trace as whole words
# only, so bundled short forms (curl -sv / -fsSv) slip through — the tradeoff
# that keeps `grep -iv` and friends from false-tripping (see the rule below).
#
# The real guarantee is that oidc-token.sh never emits secrets; this guard just
# closes the side doors. Exit 0 = allow, Exit 2 = block with a message.

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Centralized structured logging (best-effort; a no-op if the lib is unavailable
# so the guard never fails to enforce just because logging broke).
if ! source "$(dirname "${BASH_SOURCE[0]}")/../scripts/log-lib.sh" 2>/dev/null; then
    log_event() { :; }
fi
LOG_AGENT="oidc"; LOG_SCRIPT="oidc-guard"

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT"  | jq -r '.tool_input.command   // empty' 2>/dev/null)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

deny() {
    echo "BLOCKED by oidc-guard: $1." >&2
    # Trace the block (reason only — never the command/file, which may name a token).
    log_event denied block "msg=$1"
    echo "OIDC tokens/secrets must never enter model context." >&2
    echo "To make an authenticated request from inside an agent, use the guarded" >&2
    echo "wrapper (the token never surfaces):" >&2
    echo '  oidc-curl --tenant <tenant> [--user <alias>] -- GET http://127.0.0.1:PORT/path' >&2
    echo '  oidc-curl --tenant <tenant> --inspect -- GET https://<issuer-host>/...   # the tenant SSO provider' >&2
    echo '  oidc-curl --tenant <tenant> --remote  -- GET https://<registered-host>/… # tenant add-host first' >&2
    echo "Otherwise have the user run it in their terminal, e.g.:" >&2
    echo '  curl -H "Authorization: Bearer $(oidc-bearer <tenant> [client] [alias])" https://api...' >&2
    exit 2
}

# Read/Edit/Write of a cached token file.
if printf '%s' "$FILE" | grep -qE '\.claude/oidc/run/'; then
    deny "reading a cached OIDC token file"
fi

[ -n "$CMD" ] || exit 0

# Any command that reads/prints a cached token file.
if printf '%s' "$CMD" | grep -qE '\.claude/oidc/run/[^[:space:]]*\.token'; then
    deny "referencing a cached OIDC token file"
fi

# The raw-token printer (script, full path, or shell alias). Match an EXECUTION,
# not a mere mention: the name must sit in command position — at the start, after
# a separator/operator (; & | && || newline), inside a `(`/`{` group or a `$(`/
# backtick substitution, optionally behind a path and/or an interpreter prefix
# (bash/sh/exec/…). This lets innocent text — a grep pattern, a heredoc, an
# `echo "see oidc-bearer"` — through, while still catching the ways it actually
# runs. (Agents that need an authenticated request should use oidc-curl instead.)
if printf '%s' "$CMD" | grep -qE '(^|[;&|`({]|&&|\|\||\$\()[[:space:]]*((bash|sh|zsh|ksh|dash|source|exec|command|eval|env|xargs)[[:space:]]+)?([[:alnum:]._/~+-]*/)?oidc-bearer(\.sh)?([[:space:]]|$|[;&|)`])'; then
    deny "running the raw-token printer (oidc-bearer)"
fi

# Self-authorizing a token destination. oidc-curl --remote will only reach hosts
# on a tenant's allowedHosts, which makes `tenant add-host` the trust anchor of
# that control: an agent that can register a host can send a live prod token
# anywhere it likes, and the allowlist becomes decoration. The subcommand also
# refuses to run without a TTY (which an agent shell lacks) — this rule is the
# second lock, and the one that explains itself.
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]/])oidc-token(\.sh)?[[:space:]]+tenant[[:space:]]+(add|remove)-host([[:space:]]|$)'; then
    deny "registering/revoking an OIDC token destination (tenant add-host is yours to run, in your own terminal)"
fi

# Pulling a secret directly out of the Keychain.
if printf '%s' "$CMD" | grep -qE 'security[[:space:]]+find-generic-password' \
   && printf '%s' "$CMD" | grep -qE '[[:space:]]-(w|g)([[:space:]]|$)'; then
    deny "extracting a Keychain secret"
fi
if printf '%s' "$CMD" | grep -qE 'security[[:space:]]+find-generic-password[^|]*oidc:'; then
    deny "reading an OIDC Keychain item"
fi

# Verbose/tracing curl leaks the Authorization header into output. Match the
# verbose flags as whole words (boundary on both sides) so unrelated tokens such
# as `grep -iv` or `sort -v` inside the same command line don't false-trigger.
# The `curl` token is anchored on its left (start / space / path-slash) so the
# safe wrapper `oidc-curl` is NOT mistaken for `curl` — otherwise `command -v
# oidc-curl` would trip on the `-v`. Note: bundled short forms like `curl -sv`/
# `-fsSv` are intentionally NOT caught — they're indistinguishable from `grep
# -iv` by token alone, and -v/--verbose/--trace cover what's worth guarding.
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]]|/)curl([[:space:]]|$)' \
   && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-vv?|--verbose|--trace(-ascii)?)([[:space:]]|=|$)'; then
    deny "verbose curl can leak Authorization headers"
fi

exit 0
