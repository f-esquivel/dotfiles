#!/bin/bash
# oidc-guard.sh — PreToolUse guard that keeps OIDC secrets/tokens out of model context.
#
# Registered for the Bash and Read tools. It DENIES (exit 2) any tool call that
# would surface plaintext credential material to Claude:
#   - reading/printing a cached token file (~/.claude/oidc/run/*.token)
#   - running the raw-token printer (oidc-bearer)
#   - extracting a secret straight from the Keychain (security ... -w/-g)
#   - running curl verbosely (--trace / -v), which dumps Authorization headers
# Everything else (including oidc-token.sh, which only emits metadata) passes.
#
# Known gap: the verbose-curl rule matches -v/--verbose/--trace as whole words
# only, so bundled short forms (curl -sv / -fsSv) slip through — the tradeoff
# that keeps `grep -iv` and friends from false-tripping (see the rule below).
#
# The real guarantee is that oidc-token.sh never emits secrets; this guard just
# closes the side doors. Exit 0 = allow, Exit 2 = block with a message.

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT"  | jq -r '.tool_input.command   // empty' 2>/dev/null)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

deny() {
    echo "BLOCKED by oidc-guard: $1." >&2
    echo "OIDC tokens/secrets must never enter model context." >&2
    echo "Have the user run it in their terminal instead, e.g.:" >&2
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

# The raw-token printer (script, full path, or shell alias). Substring match:
# "oidc-bearer" is specific enough that any occurrence is a deliberate attempt.
if printf '%s' "$CMD" | grep -qF 'oidc-bearer'; then
    deny "running the raw-token printer (oidc-bearer)"
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
# Note: bundled short forms like `curl -sv`/`-fsSv` are intentionally NOT caught
# — they're indistinguishable from `grep -iv` by token alone, and -v/--verbose/
# --trace cover the verbose invocations worth guarding against.
if printf '%s' "$CMD" | grep -qE 'curl([[:space:]]|$)' \
   && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-vv?|--verbose|--trace(-ascii)?)([[:space:]]|=|$)'; then
    deny "verbose curl can leak Authorization headers"
fi

exit 0
