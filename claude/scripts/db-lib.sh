#!/bin/bash
# db-lib.sh — Shared helpers for the general-purpose DB agent scripts.
#
# SOURCED, not executed. Holds paths, the global target registry accessor,
# Keychain helpers, and the loopback / kind resolution shared by db-agent.sh
# (the resolver the agent drives) and db-guard.sh (the PreToolUse guard).
#
# Config model is a SINGLE GLOBAL REGISTRY — every alias is visible from every
# workspace; a project selects which DBs it touches by naming aliases at call
# time, not via a per-project config file.
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

# Root of all local, never-committed DB-agent state. Overridable via $DB_HOME.
: "${DB_HOME:=$HOME/.claude/db}"
DB_TARGETS_FILE="$DB_HOME/targets.json"

# Centralized structured logging — shared line shape with the oidc agent + guards.
# Audit lines carry alias + operation + verdict only, NEVER a resolved connection
# string / secret. See log-lib.sh for the schema.
# shellcheck source=log-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/log-lib.sh"
: "${LOG_AGENT:=db}"

# Keychain service for a target's password. account = the target's db user.
# Mirrors the oidc scripts' "service:scope" convention.
db_kc_service() { printf 'db:%s' "$1"; }            # arg = alias

db_kc_read()   { security find-generic-password -s "$1" -a "$2" -w 2>/dev/null || true; }
db_kc_write()  { security add-generic-password -U -s "$1" -a "$2" -w "$3" >/dev/null 2>&1; }
db_kc_delete() { security delete-generic-password -s "$1" -a "$2" >/dev/null 2>&1 || true; }

# Alias ids become a Keychain service component and a JSON key — keep them in a
# filesystem/Keychain-safe charset. Dots are allowed (e.g. billing.local).
db_valid_alias() {
    case "$1" in
        '')                return 1 ;;
        *[!A-Za-z0-9._-]*) return 1 ;;
        *)                 return 0 ;;
    esac
}

# A host is "local" only if it resolves to the loopback interface or a unix
# socket path. This is the hard local-only gate — a PROXY still listens on
# loopback (the user forwards test/prod through a localhost port), so a proxied
# target passes this check; what marks it prod-like is its `kind`, not its host.
db_is_loopback() {
    case "$1" in
        127.0.0.1|::1|localhost|localhost.localdomain) return 0 ;;
        /*)                                            return 0 ;;  # unix socket
        *)                                             return 1 ;;
    esac
}

# Echo a target object (compact JSON) for an alias, or empty if unknown.
db_target_obj() {
    [ -f "$DB_TARGETS_FILE" ] || return 0
    jq -c --arg a "$1" '.[$a] // empty' "$DB_TARGETS_FILE" 2>/dev/null
}

# Atomic, owner-only write of the registry so an interrupted update can't corrupt it.
db_write_targets() {
    local tmp="$DB_TARGETS_FILE.tmp"
    mkdir -p "$DB_HOME"
    ( umask 077; printf '%s\n' "$1" > "$tmp" ) && mv "$tmp" "$DB_TARGETS_FILE"
}

# Append an audit line as structured JSONL. Thin wrapper over log_event so the DB
# agent and the oidc agent share one writer/format.
#   db_audit <level> <op> [k=v ...]   (e.g. db_audit info read alias=foo commit=0)
db_audit() { log_event "$@"; }
