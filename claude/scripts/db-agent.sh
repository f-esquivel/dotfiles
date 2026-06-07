#!/bin/bash
# db-agent.sh — The single tool the general-purpose DB agent drives.
#
# Connects to databases declared in a GLOBAL registry (~/.claude/db/targets.json),
# resolves the password from the macOS Keychain into the environment ONLY for the
# duration of one client invocation, and runs the requested operation through one
# of two channels:
#
#   read  (`sql`)   SELECT / EXPLAIN / catalog introspection. Any mutating verb is
#                   rejected. This is the default, free-flowing channel.
#   write (`write`) DML/DDL wrapped in a transaction that ROLLS BACK by default —
#                   you see the effect (rows touched), then it is discarded. It
#                   PERSISTS only with --commit. A nuclear deny-list blocks the
#                   catastrophic ops (DROP DATABASE, unguarded DELETE/UPDATE,
#                   role/grant/admin ops, TRUNCATE) even with --commit.
#
# Hard local-only: every target's host must be loopback / a unix socket. A target
# may declare kind="proxy" (a localhost port forwarding to a remote test/prod DB);
# it still passes the loopback gate but is announced as PROXY and treated prod-like.
#
# Config (all local, never committed) lives under ~/.claude/db/:
#   targets.json   alias -> { engine, kind, host, port, database, user, proxyTarget? }
#                  engine ∈ {postgres, mysql} ; kind ∈ {local, proxy}
# Secrets live in the macOS Keychain, never on disk:
#   db password -> service "db:<alias>", account <user>
#
# Usage:
#   db-agent.sh list                                  # targets as JSON, no secrets
#   db-agent.sh sql   <alias> [--csv] -- <SQL...>     # read channel
#   db-agent.sh write <alias> [--commit] [--csv] -- <SQL...>
#   db-agent.sh target add                            # interactive (user runs)
#   db-agent.sh target set-password <alias>           # interactive (user runs)
#   db-agent.sh target remove <alias>
#
#   SQL after `--` is joined with spaces; pass `-` to read SQL from stdin.
#
# Exit: 0 ok · 1 usage · 2 missing dependency · 3 config error · 4 denied by policy
#       · 5 db command failed
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

set -euo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# shellcheck source=db-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/db-lib.sh"

die()   { echo "Error: $1" >&2; exit "${2:-1}"; }
note()  { echo "$1" >&2; }   # diagnostics to stderr — keeps query stdout clean

require_deps() {
    command -v jq >/dev/null 2>&1 || die "'jq' is required but not installed" 2
}

# ---- target resolution ------------------------------------------------------

# Populates ENGINE KIND HOST PORT DATABASE USER PROXYTARGET for an alias.
ENGINE="" KIND="" HOST="" PORT="" DATABASE="" USER_="" PROXYTARGET=""
resolve_target() {
    local alias="$1" obj
    db_valid_alias "$alias" || die "invalid alias '$alias'" 1
    obj="$(db_target_obj "$alias")"
    [ -n "$obj" ] || die "unknown alias '$alias' — run: db-agent.sh list" 3
    ENGINE="$(printf '%s' "$obj"   | jq -r '.engine      // empty')"
    KIND="$(printf '%s' "$obj"     | jq -r '.kind        // "local"')"
    HOST="$(printf '%s' "$obj"     | jq -r '.host        // empty')"
    PORT="$(printf '%s' "$obj"     | jq -r '.port        // empty')"
    DATABASE="$(printf '%s' "$obj" | jq -r '.database    // empty')"
    USER_="$(printf '%s' "$obj"    | jq -r '.user        // empty')"
    PROXYTARGET="$(printf '%s' "$obj" | jq -r '.proxyTarget // empty')"
    case "$ENGINE" in postgres|mysql) ;; *) die "alias '$alias' has unsupported engine '$ENGINE'" 3 ;; esac
    [ -n "$HOST" ] || die "alias '$alias' has no host" 3
    db_is_loopback "$HOST" || die "alias '$alias' host '$HOST' is not loopback — local-only is a hard rule" 4
}

banner() {
    local k="$KIND"
    if [ "$KIND" = "proxy" ]; then
        k="PROXY${PROXYTARGET:+ → $PROXYTARGET}"
    fi
    note "[$1 | $ENGINE | $k | db=$DATABASE]"
}

# ---- statement policy -------------------------------------------------------

# Normalize SQL to one lowercased, single-spaced line for keyword scanning.
norm_sql() { printf '%s' "$1" | tr '\n\r\t' '   ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }

# Nuclear ops — denied in EVERY mode, even with --commit. Echoes the matched
# reason and returns 0 when something is denied, 1 when clean.
scan_nuclear() {
    local n; n="$(norm_sql "$1")"
    local pat reason
    # pattern:::human-reason pairs (`:::` delimiter — patterns contain `|`).
    for pair in \
        'drop +(database|schema):::DROP DATABASE/SCHEMA' \
        '(create|drop|alter|rename) +(role|user):::role/user management' \
        'drop +owned:::DROP OWNED' \
        'grant +:::GRANT' \
        'revoke +:::REVOKE' \
        'truncate +:::TRUNCATE (not rollback-safe on MySQL)' \
        'alter +system:::ALTER SYSTEM' \
        'set +(global|persist):::SET GLOBAL/PERSIST' \
        'flush +(privileges|hosts|logs|tables):::FLUSH' \
        'reset +(master|slave|replica):::RESET replication' \
        'change +(master|replication):::CHANGE replication source' \
        '(start|stop) +(slave|replica):::START/STOP replica' \
        'shutdown( |;|$):::SHUTDOWN' \
        '(install|uninstall) +(plugin|component):::plugin/component management' \
    ; do
        pat="${pair%%:::*}"; reason="${pair##*:::}"
        if printf '%s' "$n" | grep -qE "(^| )$pat"; then echo "$reason"; return 0; fi
    done
    # Unguarded DELETE / UPDATE (no WHERE) — catastrophic on commit.
    if printf '%s' "$n" | grep -qE '(^| )delete +from ' && ! printf '%s' "$n" | grep -qE ' where '; then
        echo "DELETE without WHERE"; return 0
    fi
    if printf '%s' "$n" | grep -qE '(^| )update +' && printf '%s' "$n" | grep -qE ' set ' && ! printf '%s' "$n" | grep -qE ' where '; then
        echo "UPDATE without WHERE"; return 0
    fi
    return 1
}

# Read channel: reject anything that could mutate. Echoes reason / returns 0 on deny.
scan_mutates() {
    local n; n="$(norm_sql "$1")"
    if printf '%s' "$n" | grep -qE '(^| )(insert|update|delete|truncate|drop|create|alter|replace|merge|grant|revoke|comment +on|rename|lock +tables|call |do +|load +data|copy +[^;]* from)'; then
        echo "mutating statement in the read channel — use: db-agent.sh write"
        return 0
    fi
    return 1
}

# ---- execution --------------------------------------------------------------

read_sql_arg() {  # joins remaining args, or reads stdin when arg is "-"
    if [ "$#" -eq 0 ]; then die "no SQL given (after --)" 1; fi
    if [ "$#" -eq 1 ] && [ "$1" = "-" ]; then cat; else printf '%s' "$*"; fi
}

run_pg() {  # run_pg <body-sql> <csv:0|1> <readonly:0|1>   (body already wrapped if needed)
    local body="$1" csv="$2" ro="${3:-0}" pw fmt=() pgopts=""
    pw="$(db_kc_read "$(db_kc_service "$ALIAS")" "$USER_")"
    [ "$csv" = "1" ] && fmt=(--csv)
    # Server-side read-only at connection startup — no output, unlike an inline SET.
    [ "$ro" = "1" ] && pgopts="-c default_transaction_read_only=on"
    PGPASSWORD="$pw" PGOPTIONS="$pgopts" PGCONNECT_TIMEOUT=8 \
        psql -h "$HOST" -p "${PORT:-5432}" -U "$USER_" -d "$DATABASE" \
             -v ON_ERROR_STOP=1 -P pager=off ${fmt[@]+"${fmt[@]}"} <<<"$body"
}

run_mysql() {  # run_mysql <body-sql> <csv:0|1>
    local body="$1" csv="$2" pw cfg rc=0 flags=()
    pw="$(db_kc_read "$(db_kc_service "$ALIAS")" "$USER_")"
    cfg="$(mktemp "${TMPDIR:-/tmp}/db.XXXXXX")" || die "mktemp failed" 5
    trap 'rm -f "$cfg"' RETURN
    {
        printf '[client]\nhost=%s\nport=%s\nuser=%s\ndatabase=%s\n' \
            "$HOST" "${PORT:-3306}" "$USER_" "$DATABASE"
        [ -n "$pw" ] && printf 'password=%s\n' "$pw"
    } >"$cfg"
    chmod 600 "$cfg"
    [ "$csv" = "1" ] && flags=(--batch)   # TSV when machine-readable output wanted
    mysql --defaults-extra-file="$cfg" ${flags[@]+"${flags[@]}"} <<<"$body" || rc=$?
    return $rc
}

dispatch_sql() {  # dispatch_sql <mode:read|write> <commit:0|1> <csv> <sql>
    local mode="$1" commit="$2" csv="$3" sql="$4" reason body verb ro=0

    # Nuclear floor applies to both channels.
    if reason="$(scan_nuclear "$sql")"; then
        db_audit "$ALIAS	$mode	DENIED:nuclear($reason)"
        die "DENIED — $reason. Blocked below the agent's reach; not overridable." 4
    fi

    if [ "$mode" = "read" ]; then
        if reason="$(scan_mutates "$sql")"; then
            db_audit "$ALIAS	read	DENIED:mutation"
            die "DENIED — $reason" 4
        fi
        body="$sql"
        [ "$ENGINE" = "postgres" ] && ro=1
    else
        # Lone `;` terminates the user statement even when they omit one; a
        # trailing empty statement is a harmless no-op if they included it.
        verb=$([ "$commit" = "1" ] && echo COMMIT || echo ROLLBACK)
        if [ "$ENGINE" = "postgres" ]; then
            body="BEGIN;
$sql
;
$verb;"
        else
            body="SET autocommit=0;
START TRANSACTION;
$sql
;
$verb;"
        fi
    fi

    db_audit "$ALIAS	$mode	commit=$commit	ok"
    if [ "$ENGINE" = "postgres" ]; then run_pg   "$body" "$csv" "$ro"
    else                                run_mysql "$body" "$csv"; fi

    if [ "$mode" = "write" ] && [ "$commit" = "0" ]; then
        note "— rolled back (dry-run). Re-run with --commit to persist."
    elif [ "$mode" = "write" ] && [ "$commit" = "1" ]; then
        note "— COMMITTED${KIND:+ to $KIND}${PROXYTARGET:+ ($PROXYTARGET)}."
    fi
}

# ---- subcommands ------------------------------------------------------------

cmd_list() {
    [ -f "$DB_TARGETS_FILE" ] || { echo '{}'; return 0; }
    # Strip nothing sensitive — passwords are never in this file.
    jq 'to_entries | map({alias: .key} + .value) | sort_by(.alias)' "$DB_TARGETS_FILE"
}

# Parse `<alias> [flags] -- <sql>` shared by sql/write.
ALIAS=""
parse_run() {  # sets ALIAS, echoes "<commit> <csv>\n<sql>" via globals
    RUN_COMMIT=0 RUN_CSV=0 RUN_SQL=""
    ALIAS="${1:-}"; shift || true
    [ -n "$ALIAS" ] || die "missing <alias>" 1
    while [ $# -gt 0 ]; do
        case "$1" in
            --commit) RUN_COMMIT=1; shift ;;
            --csv)    RUN_CSV=1; shift ;;
            --)       shift; RUN_SQL="$(read_sql_arg "$@")"; break ;;
            -*)       die "unknown flag '$1'" 1 ;;
            *)        die "unexpected arg '$1' (SQL must follow --)" 1 ;;
        esac
    done
    [ -n "$RUN_SQL" ] || die "no SQL given (after --)" 1
    resolve_target "$ALIAS"
}

cmd_sql() {   parse_run "$@"; banner "$ALIAS"; dispatch_sql read  0            "$RUN_CSV" "$RUN_SQL"; }
cmd_write() { parse_run "$@"; banner "$ALIAS"; dispatch_sql write "$RUN_COMMIT" "$RUN_CSV" "$RUN_SQL"; }

cmd_target() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        add)          target_add ;;
        set-password) target_set_password "${1:-}" ;;
        remove)       target_remove "${1:-}" ;;
        *)            die "usage: db-agent.sh target {add|set-password <alias>|remove <alias>}" 1 ;;
    esac
}

prompt() { local v; printf '%s' "$1" >&2; read -r v; printf '%s' "$v"; }

target_add() {
    local alias engine kind host port database user proxytarget pw current
    alias="$(prompt 'alias (e.g. billing.local): ')"
    db_valid_alias "$alias" || die "invalid alias" 1
    [ -n "$(db_target_obj "$alias")" ] && die "alias '$alias' already exists (remove it first)" 3
    engine="$(prompt 'engine [postgres|mysql]: ')"
    case "$engine" in postgres|mysql) ;; *) die "engine must be postgres or mysql" 1 ;; esac
    kind="$(prompt 'kind [local|proxy] (proxy = localhost port forwarding to a remote DB): ')"
    case "$kind" in local|proxy) ;; *) die "kind must be local or proxy" 1 ;; esac
    host="$(prompt 'host [127.0.0.1]: ')"; host="${host:-127.0.0.1}"
    db_is_loopback "$host" || die "host '$host' is not loopback — local-only is a hard rule" 4
    port="$(prompt "port [$([ "$engine" = postgres ] && echo 5432 || echo 3306)]: ")"
    port="${port:-$([ "$engine" = postgres ] && echo 5432 || echo 3306)}"
    database="$(prompt 'database: ')"
    user="$(prompt 'user: ')"
    proxytarget=""
    [ "$kind" = "proxy" ] && proxytarget="$(prompt 'proxyTarget label (e.g. gcp:staging:orders): ')"
    printf 'password (leave empty for socket/trust/.pgpass auth): ' >&2; read -rs pw; echo >&2

    current="$( [ -f "$DB_TARGETS_FILE" ] && cat "$DB_TARGETS_FILE" || echo '{}' )"
    local updated
    updated="$(printf '%s' "$current" | jq \
        --arg a "$alias" --arg e "$engine" --arg k "$kind" --arg h "$host" \
        --argjson p "$port" --arg d "$database" --arg u "$user" --arg pt "$proxytarget" \
        '.[$a] = ({engine:$e, kind:$k, host:$h, port:$p, database:$d, user:$u}
                  + (if $pt == "" then {} else {proxyTarget:$pt} end))')"
    db_write_targets "$updated"
    [ -n "$pw" ] && db_kc_write "$(db_kc_service "$alias")" "$user" "$pw"
    note "Added '$alias'. Password ${pw:+stored in Keychain}${pw:+.}${pw:-not set (relying on socket/trust auth).}"
}

target_set_password() {
    local alias="$1" user pw
    [ -n "$alias" ] || die "usage: db-agent.sh target set-password <alias>" 1
    [ -n "$(db_target_obj "$alias")" ] || die "unknown alias '$alias'" 3
    user="$(db_target_obj "$alias" | jq -r '.user')"
    printf 'new password for %s (%s): ' "$alias" "$user" >&2; read -rs pw; echo >&2
    [ -n "$pw" ] || die "empty password" 1
    db_kc_write "$(db_kc_service "$alias")" "$user" "$pw"
    note "Updated Keychain password for '$alias'."
}

target_remove() {
    local alias="$1" user
    [ -n "$alias" ] || die "usage: db-agent.sh target remove <alias>" 1
    [ -n "$(db_target_obj "$alias")" ] || die "unknown alias '$alias'" 3
    user="$(db_target_obj "$alias" | jq -r '.user')"
    db_kc_delete "$(db_kc_service "$alias")" "$user"
    db_write_targets "$(jq --arg a "$alias" 'del(.[$a])' "$DB_TARGETS_FILE")"
    note "Removed '$alias' (config + Keychain)."
}

# ---- main -------------------------------------------------------------------

require_deps
cmd="${1:-}"; shift || true
case "$cmd" in
    list)         cmd_list ;;
    sql)          cmd_sql "$@" ;;
    write)        cmd_write "$@" ;;
    target)       cmd_target "$@" ;;
    -h|--help|'') sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)            die "unknown command '$cmd' (list|sql|write|target)" 1 ;;
esac
