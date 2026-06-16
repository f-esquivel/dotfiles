#!/bin/bash
# secret-guard.sh — PreToolUse guard that keeps secret material out of context.
#
# Registered for the Bash and Grep tools. Hard-denies (exit 2) attempts to:
#   - read a known secret FILE through any content reader / input redirection /
#     source in Bash  (.env[.*], *.secrets, *.local, ssh keys, *.pem/*.key,
#     .netrc, .pgpass, .aws/credentials) — closes the gap left by the native
#     `permissions.deny` Read rules, which Bash bypasses.
#   - search for secret KEY NAMES (anything matching SECRET / CREDENTIAL /
#     PASSWORD / TOKEN / API_KEY / ACCESS_KEY / PRIVATE_KEY / BEARER) via a
#     grep-family command in Bash OR via the native Grep tool's pattern — this
#     blocks value disclosure regardless of which file holds the value.
#   - dump the environment (bare printenv/env, export -p, declare -x), read a
#     secret-named env var, or echo a secret-named variable to stdout.
#
# This is a LOW-COLLATERAL DETERRENT, not a sandbox — same philosophy as
# db-guard. It stops the direct and accidental reads (cat .env, grep -r SECRET,
# echo $TOKEN), NOT a determined interpreter path (python -c "open('.env')",
# base64 round-trips, copying a file then reading the copy). Widening the net to
# every interpreter would block legitimate python/node use, so we accept the
# residual and cover the obvious 90%.
#
# The matching native layer lives in settings.json `permissions.deny` (Read
# rules for the same secret files) which covers the Read/Grep/Glob file tools.
#
# Exit 0 = allow, Exit 2 = block with a message. Compat: bash 3.2 (macOS).

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Centralized structured logging (best-effort; a no-op if the lib is unavailable
# so the guard never fails to enforce just because logging broke).
if ! source "$(dirname "${BASH_SOURCE[0]}")/../scripts/log-lib.sh" 2>/dev/null; then
    log_event() { :; }
fi
LOG_AGENT="secret"; LOG_SCRIPT="secret-guard"

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

deny() {
    echo "BLOCKED by secret-guard: $1." >&2
    echo "Pulling secret material into context is disabled. If you genuinely need" >&2
    echo "this value, inspect it yourself in your own terminal." >&2
    # Trace the block (reason only — the command may itself carry a secret).
    log_event denied block "tool=${TOOL:-?}" "msg=$1"
    exit 2
}

# Case-insensitive ERE presence test.
has() { printf '%s' "$1" | grep -qiE "$2"; }

# Secret key NAMES (value-bearing). Leading boundary + plural-aware trailing
# boundary keeps identifiers like getSecretManager / "secretsauce" from matching.
SECRET_KEYS='([^A-Za-z]|^)(SECRETS?|CREDENTIALS?|PASSWORDS?|PASSWD|TOKENS?|API[_-]?KEYS?|ACCESS[_-]?KEYS?|SECRET[_-]?ACCESS[_-]?KEYS?|PRIVATE[_-]?KEYS?|BEARER)([^A-Za-z]|$)'

# ---- Grep tool: block searching for secret key names --------------------
if [ "$TOOL" = "Grep" ]; then
    PATTERN=$(printf '%s' "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null)
    [ -n "$PATTERN" ] || exit 0
    has "$PATTERN" "$SECRET_KEYS" && deny "Grep pattern targets secret key names"
    exit 0
fi

# ---- everything else we guard runs through Bash -------------------------
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Quote-stripped view for the file / search / dump checks below: blank out single-
# and double-quoted spans so a command that merely MENTIONS a secret token inside
# an argument string — a commit message, `echo` prose, a here-doc — is not misread
# as reading one. The var-expansion check (#4) deliberately uses the RAW command,
# since a genuine `echo "$SECRET"` keeps the variable inside double quotes.
# (newlines folded to \001 first so a multi-line quoted span — e.g. a commit
#  body — is matched as one; sed is otherwise line-oriented.)
CMD_NQ=$(printf '%s' "$CMD" | tr '\n' '\001' \
    | sed "s/'[^']*'/''/g; s/\"[^\"]*\"/\"\"/g" | tr '\001' '\n')

# 1) Reading a secret FILE via a content reader / input redirection / source.
READER='(^|[^[:alnum:]_/-])(cat|bat|less|more|head|tail|nl|tac|grep|egrep|fgrep|rg|ag|ack|sed|gawk|awk|cut|xxd|od|hexdump|strings|base64|dd|tee|paste|fold|column)([^[:alnum:]_]|$)'
# `source`/`.` only as a command (start, or after ; & |) — not a prose period.
SOURCE='(^|[;&|][[:space:]]*)(source|\.)[[:space:]]+[^[:space:];&|]'
REDIR_IN='<[[:space:]]*[^[:space:]<]'

# Files that are always secret stores ( .env handled separately below so its
# scaffolds can be excluded ). Allows a path separator before the filename.
# `credentials`/`secrets` are only treated as files when path-qualified (…/cred…)
# or carrying a config extension (secrets.yml) — never as a bare word, so
# `grep CREDENTIALS` falls through to the key-name check instead.
SECRET_FILE='((^|[^[:alnum:]_.-])([^[:space:]/]*\.(secrets|local|pem|key)|(secrets?|credentials?)\.(ya?ml|json|toml|ini|conf|cfg|env)|id_(rsa|dsa|ecdsa|ed25519)|\.netrc|\.pgpass)([^[:alnum:]]|$))|(/(secrets?|credentials?)($|[/.[:space:]"]))'

secret_file_present=0
has "$CMD_NQ" "$SECRET_FILE" && secret_file_present=1

# .env references, minus the well-known non-secret scaffolds.
env_refs=$(printf '%s' "$CMD_NQ" | grep -oE '\.env(\.[A-Za-z0-9_-]+)?' 2>/dev/null)
if [ -n "$env_refs" ]; then
    while IFS= read -r ref; do
        case "$ref" in
            .env.example|.env.template|.env.sample|.env.dist|.env.tmpl) : ;;
            *) secret_file_present=1 ;;
        esac
    done <<EOF
$env_refs
EOF
fi

if [ "$secret_file_present" = "1" ]; then
    if has "$CMD_NQ" "$READER" || has "$CMD_NQ" "$SOURCE" \
       || printf '%s' "$CMD_NQ" | grep -qE "$REDIR_IN"; then
        deny "reading a secret file's contents"
    fi
fi

# 2) Searching for secret KEY NAMES via a grep-family command (value disclosure).
#    The `-` in the boundary class excludes `--grep` (git log --grep=…), which
#    searches commit messages, not file contents.
GREP_FAMILY='(^|[^[:alnum:]_/-])(grep|egrep|fgrep|rg|ag|ack)([^[:alnum:]_]|$)'
if has "$CMD_NQ" "$GREP_FAMILY" && has "$CMD_NQ" "$SECRET_KEYS"; then
    deny "searching for secret key names"
fi

# 3) Dumping the environment.
#    bare printenv / env (no command after) → whole-env dump.
printf '%s' "$CMD_NQ" | grep -qE '(^|[;&|][[:space:]]*)printenv([[:space:]]*$|[[:space:]]*[|;&>])' \
    && deny "dumping the environment (printenv)"
printf '%s' "$CMD_NQ" | grep -qE '(^|[;&|][[:space:]]*)env([[:space:]]*$|[[:space:]]*[|;&>])' \
    && deny "dumping the environment (env)"
has "$CMD_NQ" '(^|[^[:alnum:]_-])(export[[:space:]]+-p|declare[[:space:]]+-x)([^[:alnum:]]|$)' \
    && deny "dumping exported variables"
#    printenv/env naming a specifically secret var.
if has "$CMD_NQ" '(^|[^[:alnum:]_/-])(printenv|env)[[:space:]]+[A-Za-z0-9_]' && has "$CMD_NQ" "$SECRET_KEYS"; then
    deny "reading a secret environment variable"
fi

# 4) echo/printf expanding a secret-named variable into stdout.
if has "$CMD" '(^|[^[:alnum:]_/-])(echo|printf|print)([^[:alnum:]]|$)' \
   && has "$CMD" '\$\{?[A-Za-z0-9_]*(SECRET|CREDENTIAL|PASSWORD|PASSWD|TOKEN|API[_-]?KEY|ACCESS[_-]?KEY|PRIVATE[_-]?KEY|BEARER)'; then
    deny "echoing a secret-named variable"
fi

exit 0
