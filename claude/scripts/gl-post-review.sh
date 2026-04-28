#!/bin/bash
# gl-post-review.sh — Post GitLab MR review comments via 2-channel API strategy
#
# Reads a JSON file with review data and posts comments to GitLab:
#   Channel A (direct): praise, question, thought → Discussions API (immediate)
#   Channel B (draft):  issue, suggestion, nitpick, chore → Draft Notes API (batched)
#
# Usage: gl-post-review.sh <review-data.json>
# Exit:  0 = success, 1 = partial failure, 2 = total failure

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

if [ $# -ne 1 ]; then
    echo "Usage: $0 <review-data.json>" >&2
    exit 2
fi

REVIEW_JSON="$1"
if [ ! -f "$REVIEW_JSON" ]; then
    echo "Error: file not found: $REVIEW_JSON" >&2
    exit 2
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

TOKEN=$(glab auth status -t 2>&1 | awk '/Token/{print $NF}')
if [ -z "$TOKEN" ]; then
    echo "Error: failed to extract GitLab token from 'glab auth status -t'" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Parse input
# ---------------------------------------------------------------------------

GITLAB_URL=$(jq -r '.gitlab_url' "$REVIEW_JSON")
PROJECT_ID=$(jq -r '.project_id' "$REVIEW_JSON")
MR_IID=$(jq -r '.mr_iid' "$REVIEW_JSON")
VERDICT=$(jq -r '.verdict // "comment"' "$REVIEW_JSON")
ISSUE_ID=$(jq -r '.issue_id // empty' "$REVIEW_JSON")

BASE_SHA=$(jq -r '.diff_refs.base_sha' "$REVIEW_JSON")
HEAD_SHA=$(jq -r '.diff_refs.head_sha' "$REVIEW_JSON")
START_SHA=$(jq -r '.diff_refs.start_sha' "$REVIEW_JSON")

BASE_URL="$GITLAB_URL/api/v4/projects/$PROJECT_ID/merge_requests/$MR_IID"

DIRECT_COUNT=$(jq '[.comments[] | select(.channel == "direct")] | length' "$REVIEW_JSON")
DRAFT_COUNT=$(jq '[.comments[] | select(.channel == "draft")] | length' "$REVIEW_JSON")

HAD_FAILURE=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build position JSON for a comment, omitting null line fields
build_position() {
    local comment="$1"
    echo "$comment" | jq -c '{
        position_type: "text",
        base_sha: "'"$BASE_SHA"'",
        head_sha: "'"$HEAD_SHA"'",
        start_sha: "'"$START_SHA"'",
        old_path: .old_path,
        new_path: .new_path
    } + (if .old_line != null then {old_line: .old_line} else {} end)
      + (if .new_line != null then {new_line: .new_line} else {} end)'
}

# POST JSON to a GitLab API endpoint, return HTTP status code
post_json() {
    local url="$1"
    local payload="$2"
    curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "PRIVATE-TOKEN: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url"
}

# ---------------------------------------------------------------------------
# Channel A: Direct comments (Discussions API)
# ---------------------------------------------------------------------------

if [ "$DIRECT_COUNT" -gt 0 ]; then
    direct_ok=0
    direct_fail=0

    for i in $(seq 0 $((DIRECT_COUNT - 1))); do
        comment=$(jq -c "[.comments[] | select(.channel == \"direct\")][$i]" "$REVIEW_JSON")
        position=$(build_position "$comment")
        body=$(echo "$comment" | jq -r '.body')

        payload=$(jq -n --arg body "$body" --argjson position "$position" \
            '{body: $body, position: $position}')

        http_code=$(post_json "$BASE_URL/discussions" "$payload")

        if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
            ((direct_ok++))
        else
            ((direct_fail++))
            echo "Warning: direct comment $((i + 1)) failed (HTTP $http_code)" >&2
        fi
    done

    if [ "$direct_fail" -eq 0 ]; then
        echo "Channel A (direct): $direct_ok/$DIRECT_COUNT OK"
    else
        echo "Channel A (direct): $direct_ok/$DIRECT_COUNT OK, $direct_fail failed"
        HAD_FAILURE=true
    fi
fi

# ---------------------------------------------------------------------------
# Channel B: Draft notes (Draft Notes API)
# ---------------------------------------------------------------------------

if [ "$DRAFT_COUNT" -gt 0 ]; then
    draft_ok=0
    draft_fail=0

    for i in $(seq 0 $((DRAFT_COUNT - 1))); do
        comment=$(jq -c "[.comments[] | select(.channel == \"draft\")][$i]" "$REVIEW_JSON")
        position=$(build_position "$comment")
        note=$(echo "$comment" | jq -r '.note')

        payload=$(jq -n --arg note "$note" --argjson position "$position" \
            '{note: $note, position: $position}')

        http_code=$(post_json "$BASE_URL/draft_notes" "$payload")

        if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
            ((draft_ok++))
        else
            ((draft_fail++))
            echo "Warning: draft note $((i + 1)) failed (HTTP $http_code)" >&2
        fi
    done

    if [ "$draft_fail" -eq 0 ]; then
        echo "Channel B (draft): $draft_ok/$DRAFT_COUNT OK"
    else
        echo "Channel B (draft): $draft_ok/$DRAFT_COUNT OK, $draft_fail failed"
        HAD_FAILURE=true
    fi

    # -- Bulk publish ----------------------------------------------------------

    bulk_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "PRIVATE-TOKEN: $TOKEN" \
        "$BASE_URL/draft_notes/bulk_publish")

    if [[ "$bulk_code" =~ ^2[0-9]{2}$ ]]; then
        echo "Bulk publish: OK"
    else
        echo "Warning: bulk_publish returned HTTP $bulk_code, verifying..." >&2

        # Bulk publish may succeed server-side despite returning 500.
        # Poll multiple times before falling back to individual publish
        # to avoid duplicates from re-publishing already-published drafts.
        remaining="$DRAFT_COUNT"
        for attempt in 1 2 3 4 5; do
            sleep 3
            remaining=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$BASE_URL/draft_notes" | jq 'length')
            if [ "$remaining" -eq 0 ]; then
                echo "Bulk publish: OK (succeeded despite HTTP $bulk_code, confirmed on attempt $attempt)"
                break
            fi
            echo "  Attempt $attempt: $remaining drafts still remain, waiting..." >&2
        done

        if [ "$remaining" -gt 0 ]; then
            # Before individual publish, check whether bulk_publish actually
            # created published notes (GitLab can return 500 yet succeed).
            # Count notes authored by us on this MR to detect ghost-publish.
            author_username=$(glab auth status 2>&1 | awk '/Logged in.*as/{print $NF}' | tr -d ',')
            published_count=0
            if [ -n "$author_username" ]; then
                published_count=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$BASE_URL/discussions" \
                    | jq --arg user "$author_username" \
                        '[.[] | .notes[] | select(.author.username == $user and .type == "DiffNote")] | length')
            fi

            if [ "$published_count" -ge "$DRAFT_COUNT" ]; then
                echo "Bulk publish: OK (notes already published despite stale draft listing, $published_count found)" >&2
                # Drafts are ghost entries — delete them to clean up.
                draft_ids=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$BASE_URL/draft_notes" | jq -r '.[].id')
                for draft_id in $draft_ids; do
                    curl -s -o /dev/null \
                        -X DELETE \
                        -H "PRIVATE-TOKEN: $TOKEN" \
                        "$BASE_URL/draft_notes/$draft_id"
                done
            else
                echo "Bulk publish: $remaining drafts remain, publishing individually..." >&2

                draft_ids=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$BASE_URL/draft_notes" | jq -r '.[].id')
                for draft_id in $draft_ids; do
                    curl -s -o /dev/null \
                        -X PUT \
                        -H "PRIVATE-TOKEN: $TOKEN" \
                        "$BASE_URL/draft_notes/$draft_id/publish"
                done

                sleep 2
                remaining=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" "$BASE_URL/draft_notes" | jq 'length')
                if [ "$remaining" -eq 0 ]; then
                    echo "Bulk publish: OK (individual publish succeeded)"
                else
                    echo "Error: $remaining drafts still remain after individual publish" >&2
                    HAD_FAILURE=true
                fi
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

case "$VERDICT" in
    approve)
        if glab mr approve "$MR_IID" >/dev/null 2>&1; then
            echo "Verdict (approve): OK"
        else
            echo "Warning: approval failed" >&2
            HAD_FAILURE=true
        fi
        glab mr update "$MR_IID" --label "development::done" >/dev/null 2>&1
        if [ -n "$ISSUE_ID" ]; then
            glab issue update "$ISSUE_ID" --label "development::done" >/dev/null 2>&1
        fi
        echo "Labels: development::done"
        ;;
    request_changes)
        glab mr update "$MR_IID" --label "development::rejected" >/dev/null 2>&1
        if [ -n "$ISSUE_ID" ]; then
            glab issue update "$ISSUE_ID" --label "development::rejected" >/dev/null 2>&1
        fi
        echo "Verdict (request_changes): labels applied (manual UI action required)"
        ;;
    comment | needs_discussion)
        echo "Verdict ($VERDICT): no additional action"
        ;;
    *)
        echo "Warning: unknown verdict '$VERDICT'" >&2
        ;;
esac

# ---------------------------------------------------------------------------
# Exit
# ---------------------------------------------------------------------------

if [ "$HAD_FAILURE" = true ]; then
    exit 1
fi
exit 0
