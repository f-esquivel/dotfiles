#!/bin/bash
# log-lib.sh — Shared structured (JSONL) event logger for the Claude agents.
#
# SOURCED, not executed. Both db-lib.sh and oidc-lib.sh source this, and the two
# PreToolUse guards (db-guard.sh / oidc-guard.sh) source it directly, so every
# agent surface writes the SAME line shape into one centralized log dir. One JSON
# object per line — query with jq, e.g.:
#
#   jq -c 'select(.level=="error")'        ~/.claude/logs/oidc.log
#   jq -c 'select(.rid=="a1b2c3d4")'       ~/.claude/logs/*.log    # one invocation
#
# Lines NEVER carry secrets. Callers pass only non-sensitive fields (alias /
# tenant / client / grant / user alias / host / exit code / a sanitized message).
# Tokens, passwords, connection strings and response bodies must never be passed.
#
# Schema (core keys always present):
#   ts      ISO-8601 with timezone
#   agent   db | oidc
#   script  db-agent | db-guard | oidc-token | oidc-curl | oidc-guard
#   level   error | denied | info
#   op      the operation (read | write | mint | curl | block | list | tenant | …)
#   rid     correlation id — ties multi-step / multi-process runs together
#   …       any extra k=v pairs the caller supplies (exit, alias, tenant, http, …)
#
# Env contract (set by the sourcing script before calling log_event):
#   LOG_AGENT, LOG_SCRIPT  — identify the writer (default to empty if unset)
#   LOG_RID                — correlation id; auto-generated on first use and
#                            exported so child processes share it
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

# Root of all local, never-committed agent logs. Overridable via $CLAUDE_LOG_HOME.
: "${CLAUDE_LOG_HOME:=$HOME/.claude/logs}"

# Generate a short correlation id ONCE per invocation, unless one was inherited
# from the environment (so a parent — e.g. oidc-curl spawning oidc-token — shares
# its rid with the child). Exported so child processes inherit it.
log_rid_init() {
    if [ -z "${LOG_RID:-}" ]; then
        if command -v uuidgen >/dev/null 2>&1; then
            LOG_RID="$(uuidgen | tr 'A-Z' 'a-z' | cut -c1-8)"
        else
            LOG_RID="$$-$(date '+%s')"
        fi
    fi
    export LOG_RID
}

# log_event <level> <op> [k=v ...] — append one JSONL line. Best-effort: a logging
# problem must NEVER break the agent's real work, so every failure path returns 0.
log_event() {
    command -v jq >/dev/null 2>&1 || return 0
    [ $# -ge 2 ] || return 0
    local level="$1" op="$2"; shift 2
    log_rid_init

    local dir="$CLAUDE_LOG_HOME"
    local file="$dir/${LOG_AGENT:-agent}.log"
    mkdir -p "$dir" 2>/dev/null || return 0

    local args filter
    args=(--arg ts "$(date '+%Y-%m-%dT%H:%M:%S%z')"
          --arg agent  "${LOG_AGENT:-}"
          --arg script "${LOG_SCRIPT:-}"
          --arg level  "$level"
          --arg op     "$op"
          --arg rid    "${LOG_RID:-}")
    filter='{ts:$ts, agent:$agent, script:$script, level:$level, op:$op, rid:$rid}'

    local kv k v
    for kv in "$@"; do
        case "$kv" in
            *=*) k="${kv%%=*}"; v="${kv#*=}" ;;
            *)   continue ;;
        esac
        # Keys become jq identifiers — skip anything unsafe rather than break.
        case "$k" in
            ''|*[!A-Za-z0-9_]*) continue ;;
        esac
        args+=(--arg "$k" "$v")
        filter="$filter + {$k:\$$k}"
    done

    ( umask 077; jq -nc "${args[@]}" "$filter" >> "$file" ) 2>/dev/null || return 0
}
