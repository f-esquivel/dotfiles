#!/bin/bash
# gl-validate-positions.sh — Validate review-comment positions against an MR diff
#
# Reads the same review JSON consumed by gl-post-review.sh and verifies that
# every comment's (new_path, new_line) — or (old_path, old_line) for deletion
# comments — maps to a line that actually exists in the MR diff
# `base_sha..head_sha`. GitLab rejects DiffNotes whose position falls outside
# this range with `400: line_code can't be blank`, so catching it pre-flight
# turns a noisy post-hoc failure into a clean abort.
#
# Usage: gl-validate-positions.sh <review-data.json>
# Exit:  0 = all positions valid
#        1 = one or more positions out of scope (manifest printed to stderr)
#        2 = bad usage / missing dependency / git failure
#
# Compat: targets bash 3.2 (macOS system /bin/bash). Avoid bash 4+ features
# (mapfile, `declare -A`, `${var,,}`, etc.) when editing this file.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <review-data.json>" >&2
    exit 2
fi

REVIEW_JSON="$1"
if [ ! -f "$REVIEW_JSON" ]; then
    echo "Error: file not found: $REVIEW_JSON" >&2
    exit 2
fi

for cmd in jq git awk; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed" >&2
        exit 2
    fi
done

BASE_SHA=$(jq -er '.diff_refs.base_sha' "$REVIEW_JSON")
HEAD_SHA=$(jq -er '.diff_refs.head_sha' "$REVIEW_JSON")

# Ensure both SHAs resolve locally — the diff is computed from the working repo.
for sha in "$BASE_SHA" "$HEAD_SHA"; do
    if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
        echo "Error: commit $sha not found locally — fetch the MR refs first" >&2
        exit 2
    fi
done

# ---------------------------------------------------------------------------
# Build per-file line sets in a tmp dir.
# new-side lines:  added (+) and context lines inside any hunk
# old-side lines:  deleted (-) and context lines inside any hunk
# ---------------------------------------------------------------------------

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Collect unique paths referenced by comments (new_path or old_path). Use a
# read-loop (not `mapfile`) for bash 3.2 compatibility (macOS default).
PATHS=()
while IFS= read -r p; do
    [ -n "$p" ] && PATHS+=("$p")
done < <(jq -r '
    [.comments[]? | (.new_path, .old_path)] | map(select(. != null)) | unique | .[]
' "$REVIEW_JSON")

for path in "${PATHS[@]+"${PATHS[@]}"}"; do
    safe=$(printf '%s' "$path" | tr '/' '_')
    # `git diff base..head -- <path>` is the authoritative MR-side diff.
    # Empty output (path unchanged in range) yields empty line sets, which
    # correctly causes any comment on that path to be flagged.
    git diff "$BASE_SHA..$HEAD_SHA" -- "$path" 2>/dev/null \
        | awk -v new_out="$TMP/new_${safe}" -v old_out="$TMP/old_${safe}" '
            /^@@/ {
                # @@ -a,b +c,d @@  — capture old start (a) and new start (c)
                match($0, /-[0-9]+/);  old_n = substr($0, RSTART+1, RLENGTH-1) + 0
                match($0, /\+[0-9]+/); new_n = substr($0, RSTART+1, RLENGTH-1) + 0
                in_hunk = 1
                next
            }
            !in_hunk { next }
            /^\+\+\+/ || /^---/ { next }
            /^\\/ { next }                                  # "\ No newline at EOF"
            /^\+/ { print new_n >> new_out; new_n++; next }
            /^-/  { print old_n >> old_out; old_n++; next }
            /^ /  {
                print new_n >> new_out; new_n++
                print old_n >> old_out; old_n++
                next
            }
        '
done

# ---------------------------------------------------------------------------
# Validate each comment.
# ---------------------------------------------------------------------------

REJECTIONS=0
TOTAL=$(jq '.comments | length' "$REVIEW_JSON")

# `seq 0 -1` on macOS BSD seq produces "0\n-1" (not empty as on GNU seq);
# guard against the zero-comment case explicitly.
if [ "$TOTAL" -eq 0 ]; then
    echo "Validation: 0 comments, nothing to validate"
    exit 0
fi

for i in $(seq 0 $((TOTAL - 1))); do
    comment=$(jq -c ".comments[$i]" "$REVIEW_JSON")
    new_path=$(echo "$comment" | jq -r '.new_path // empty')
    new_line=$(echo "$comment" | jq -r '.new_line // empty')
    old_path=$(echo "$comment" | jq -r '.old_path // empty')
    old_line=$(echo "$comment" | jq -r '.old_line // empty')

    # GitLab requires at least one of (new_line, old_line). new_line wins for
    # added/context lines; old_line wins for deletions.
    if [ -n "$new_line" ] && [ -n "$new_path" ]; then
        safe=$(printf '%s' "$new_path" | tr '/' '_')
        set_file="$TMP/new_${safe}"
        target="$new_line"
        side="new"
        path="$new_path"
    elif [ -n "$old_line" ] && [ -n "$old_path" ]; then
        safe=$(printf '%s' "$old_path" | tr '/' '_')
        set_file="$TMP/old_${safe}"
        target="$old_line"
        side="old"
        path="$old_path"
    else
        echo "Reject [#$((i+1))]: comment has no usable (path, line) pair" >&2
        REJECTIONS=$((REJECTIONS + 1))
        continue
    fi

    if [ ! -f "$set_file" ] || ! grep -qx "$target" "$set_file"; then
        echo "Reject [#$((i+1))]: $path:$target ($side-side) is not in base_sha..head_sha" >&2
        REJECTIONS=$((REJECTIONS + 1))
    fi
done

if [ "$REJECTIONS" -gt 0 ]; then
    echo "Error: $REJECTIONS of $TOTAL comment position(s) are out of MR scope" >&2
    exit 1
fi

echo "Validation: all $TOTAL comment positions are within base_sha..head_sha"
exit 0
