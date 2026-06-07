#!/bin/bash
# db-guard.sh — PreToolUse guard enforcing the DB agent's hard local-only rule
# below the agent's reach.
#
# Registered for the Bash tool. It is deliberately LOW-COLLATERAL: it does NOT
# block local DB work in the main session. It DENIES (exit 2) only:
#   - a raw DB client (psql/mysql/pg_dump/…) aimed at a NON-loopback host
#     (via -h/--host, a connection URI, or PGHOST/MYSQL_HOST) — the local-only
#     rule, enforced everywhere, so nothing can sidestep db-agent.sh to reach a
#     remote DB directly. Proxies listen on loopback, so they still pass.
#   - extracting a DB password straight from the Keychain (security … db:… -w/-g)
#
# The agent's transactional rollback-by-default + nuclear deny-list live inside
# db-agent.sh (the agent's only DB tool); this guard just shuts the remote door.
# Exit 0 = allow, Exit 2 = block with a message.

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

deny() {
    echo "BLOCKED by db-guard: $1." >&2
    echo "Databases are local-only. Use db-agent.sh against a loopback/proxy alias," >&2
    echo "or run the direct command yourself in your terminal." >&2
    exit 2
}

# A host string that is loopback / socket / empty is fine; anything else is remote.
host_is_remote() {
    case "$1" in
        ''|127.0.0.1|::1|localhost|localhost.localdomain) return 1 ;;
        /*)                                               return 1 ;;  # unix socket
        *)                                                return 0 ;;
    esac
}

# Pulling a DB secret out of the Keychain.
if printf '%s' "$CMD" | grep -qE 'security[[:space:]]+find-generic-password[^|]*(-s[[:space:]]+|-s)?db:' \
   && printf '%s' "$CMD" | grep -qE '[[:space:]]-(w|g)([[:space:]]|$)'; then
    deny "extracting a DB Keychain secret"
fi

# Only scrutinize commands that actually invoke a raw DB client. (db-agent.sh
# itself contains none of these tokens at the Bash-call layer — its inner psql/
# mysql runs inside the script, invisible here — so it is never matched.)
printf '%s' "$CMD" | grep -qE '(^|[^[:alnum:]_])(psql|mysql|mysqladmin|pg_dump|pg_dumpall|pg_restore|mysqldump)([^[:alnum:]_]|$)' || exit 0

# Collect every host the command names, then deny if any is remote.
hosts=$(
    {
        # -h <host>  /  --host <host>  /  --host=<host>
        printf '%s' "$CMD" | grep -oE '(-h|--host)([[:space:]]+|=)[^[:space:]]+' \
            | sed -E 's/^(-h|--host)([[:space:]]+|=)//'
        # connection URIs: postgres(ql)://[user[:pw]@]host[:port]/…  and mysql://…
        printf '%s' "$CMD" | grep -oE '(postgres(ql)?|mysql)://[^[:space:]"'"'"']+' \
            | sed -E 's#^[a-z]+://##; s/^[^@/]*@//; s#[:/?].*$##'
        # PGHOST= / MYSQL_HOST= env assignments
        printf '%s' "$CMD" | grep -oE '(PGHOST|MYSQL_HOST)=[^[:space:]]+' \
            | sed -E 's/^[A-Z_]+=//'
    } 2>/dev/null
)

IFS='
'
for h in $hosts; do
    # Strip surrounding quotes that may have been captured.
    h="${h%\"}"; h="${h#\"}"; h="${h%\'}"; h="${h#\'}"
    if host_is_remote "$h"; then
        deny "raw DB client aimed at non-loopback host '$h'"
    fi
done

exit 0
