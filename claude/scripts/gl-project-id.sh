#!/bin/bash
# gl-project-id.sh — Resolve the URL-encoded GitLab project identifier.
#
# Resolves the project from the local git remote (via `glab repo view`) and
# emits a form that is safe to interpolate into a `/api/v4/projects/...` URL —
# i.e. either a numeric ID or a path with `/` encoded as `%2F`.
#
# Without this, hand-crafted JSON often carries a raw namespaced path
# (e.g. "group/subgroup/project") whose slashes are interpreted as path
# separators by the GitLab API and cause every request to return 404.
#
# Usage:   gl-project-id.sh [--format=path|id]
# Default: --format=path  (URL-encoded namespaced path, e.g. group%2Fproject)
#
# Exit:    0 = success
#          1 = bad usage
#          2 = glab call failed (network, auth, not in a glab-aware repo)
#          3 = response missing required fields
#
# Examples:
#   PROJECT_ID="$(~/.claude/scripts/gl-project-id.sh)"
#   ~/.claude/scripts/gl-project-id.sh --format=id
#
# Compat: targets bash 3.2 (macOS system /bin/bash).

set -euo pipefail

FORMAT="path"

if [ $# -gt 1 ]; then
    echo "Usage: $0 [--format=path|id]" >&2
    exit 1
fi

if [ $# -eq 1 ]; then
    case "$1" in
        --format=path) FORMAT="path" ;;
        --format=id)   FORMAT="id"   ;;
        *) echo "Error: unknown format '$1' (expected --format=path|id)" >&2; exit 1 ;;
    esac
fi

for cmd in glab jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' is required but not installed" >&2
        exit 2
    fi
done

if ! REPO_JSON="$(glab repo view --output json 2>/dev/null)"; then
    echo "Error: glab repo view failed (not in a GitLab repo, or auth/network failure)" >&2
    exit 2
fi

case "$FORMAT" in
    path)
        # path_with_namespace is the canonical "group/subgroup/project" form.
        FULL_PATH="$(printf '%s' "$REPO_JSON" | jq -r '.path_with_namespace // empty')"
        if [ -z "$FULL_PATH" ]; then
            echo "Error: response missing 'path_with_namespace'" >&2
            exit 3
        fi
        # URL-encode every slash. No other path component characters require
        # encoding for GitLab namespaces (alnum, dash, underscore, dot).
        printf '%s\n' "$FULL_PATH" | sed 's|/|%2F|g'
        ;;
    id)
        ID="$(printf '%s' "$REPO_JSON" | jq -r '.id // empty')"
        if [ -z "$ID" ]; then
            echo "Error: response missing numeric 'id'" >&2
            exit 3
        fi
        printf '%s\n' "$ID"
        ;;
esac
