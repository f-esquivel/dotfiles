#!/bin/bash
# gl-mr-diff-refs.sh — Fetch GitLab MR diff_refs (base_sha, head_sha, start_sha)
#
# Resolves the project from the local git remote (via `glab`), so no
# URL-encoded project path is required. Validates the response and ensures
# all three SHAs are present and well-formed before printing.
#
# Usage:   gl-mr-diff-refs.sh <iid> [--format=env|json]
# Default: --format=env  (shell-eval-safe KEY=VALUE lines)
#
# Exit:    0 = success
#          1 = bad usage
#          2 = glab call failed (network, auth, missing MR)
#          3 = response missing diff_refs or contains invalid SHAs
#
# Examples:
#   eval "$(gl-mr-diff-refs.sh 42)"
#   gl-mr-diff-refs.sh 42 --format=json | jq .

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <iid> [--format=env|json]" >&2
    exit 1
fi

IID="$1"
FORMAT="env"

if [ $# -eq 2 ]; then
    case "$2" in
        --format=env)  FORMAT="env"  ;;
        --format=json) FORMAT="json" ;;
        *) echo "Error: unknown format '$2' (expected --format=env|json)" >&2; exit 1 ;;
    esac
fi

if ! [[ "$IID" =~ ^[0-9]+$ ]]; then
    echo "Error: iid must be a positive integer, got '$IID'" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

for cmd in glab jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' is required but not installed" >&2
        exit 2
    fi
done

# ---------------------------------------------------------------------------
# Fetch + validate
# ---------------------------------------------------------------------------

# `glab mr view` resolves project from the local git remote — no URL encoding.
if ! MR_JSON="$(glab mr view "$IID" --output json 2>/dev/null)"; then
    echo "Error: glab mr view failed for iid=$IID (auth, network, or MR not found)" >&2
    exit 2
fi

# Verify body is valid JSON containing diff_refs
if ! printf '%s' "$MR_JSON" | jq -e 'has("diff_refs") and (.diff_refs != null)' >/dev/null; then
    echo "Error: response missing 'diff_refs' for iid=$IID" >&2
    exit 3
fi

# Extract the three SHAs (well-formed git hashes contain no whitespace).
read -r BASE_SHA HEAD_SHA START_SHA < <(
    printf '%s' "$MR_JSON" \
      | jq -r '.diff_refs | "\(.base_sha // "") \(.head_sha // "") \(.start_sha // "")"'
) || true

SHA_RE='^[0-9a-f]{40}$'
for pair in "base_sha=$BASE_SHA" "head_sha=$HEAD_SHA" "start_sha=$START_SHA"; do
    name="${pair%%=*}"
    val="${pair#*=}"
    if ! [[ "$val" =~ $SHA_RE ]]; then
        echo "Error: invalid or empty $name for iid=$IID: '$val'" >&2
        exit 3
    fi
done

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

case "$FORMAT" in
    env)
        printf 'BASE_SHA=%s\n'  "$BASE_SHA"
        printf 'HEAD_SHA=%s\n'  "$HEAD_SHA"
        printf 'START_SHA=%s\n' "$START_SHA"
        ;;
    json)
        jq -n \
            --arg base  "$BASE_SHA" \
            --arg head  "$HEAD_SHA" \
            --arg start "$START_SHA" \
            '{base_sha: $base, head_sha: $head, start_sha: $start}'
        ;;
esac
