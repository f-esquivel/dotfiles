#!/bin/bash
# gl-post-review.sh — Post GitLab MR review comments via 2-channel API strategy
#
# Reads a JSON file with review data and posts comments to GitLab:
#   Channel A (direct): praise, question, thought → Discussions API (immediate)
#   Channel B (draft):  issue, suggestion, nitpick, chore → Draft Notes API (batched)
#
# Pre-flight: every comment position is validated against the MR's
# base_sha..head_sha diff via gl-validate-positions.sh. If any position is
# out of scope, nothing is posted (atomic abort).
#
# Bulk-publish recovery is driven by the IDs of the drafts WE created in this
# run, not by DiffNote counts — so other reviewers' activity, pagination, and
# username parsing all become irrelevant. Drafts that we cannot confirm as
# published are LEFT in place so a subsequent run can retry without losing data.
#
# Usage: gl-post-review.sh [--dry-run] <review-data.json>
#   --dry-run  Run pre-flight validation and print the planned HTTP calls
#              (method, URL, payload) without executing any of them.
# Exit:  0 = success, 1 = partial failure, 2 = total failure
#
# Compat: targets bash 3.2 (macOS system /bin/bash). Avoid bash 4+ features
# (mapfile, `declare -A`, `${var,,}`, etc.) when editing this file.

set -euo pipefail

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

DRY_RUN=false
if [ $# -ge 1 ] && [ "$1" = "--dry-run" ]; then
    DRY_RUN=true
    shift
fi

if [ $# -ne 1 ]; then
    echo "Usage: $0 [--dry-run] <review-data.json>" >&2
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Auth — prefer $GITLAB_TOKEN, fall back to parsing `glab auth status -t`.
# (glab has no dedicated get-token subcommand as of v1.x.)
# ---------------------------------------------------------------------------

TOKEN="${GITLAB_TOKEN:-}"
if [ -z "$TOKEN" ] && [ "$DRY_RUN" = false ]; then
    TOKEN=$(glab auth status -t 2>&1 | awk '/Token/{print $NF}' || true)
fi
if [ -z "$TOKEN" ] && [ "$DRY_RUN" = false ]; then
    echo "Error: no GitLab token available (set \$GITLAB_TOKEN or run 'glab auth login')" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Parse input
# ---------------------------------------------------------------------------

GITLAB_URL=$(jq -er '.gitlab_url' "$REVIEW_JSON")
PROJECT_ID=$(jq -er '.project_id' "$REVIEW_JSON")
MR_IID=$(jq -er '.mr_iid' "$REVIEW_JSON")
VERDICT=$(jq -r '.verdict // "comment"' "$REVIEW_JSON")
ISSUE_ID=$(jq -r '.issue_id // empty' "$REVIEW_JSON")

BASE_SHA=$(jq -er '.diff_refs.base_sha' "$REVIEW_JSON")
HEAD_SHA=$(jq -er '.diff_refs.head_sha' "$REVIEW_JSON")
START_SHA=$(jq -er '.diff_refs.start_sha' "$REVIEW_JSON")

# Normalize project_id: GitLab's `/api/v4/projects/:id` accepts either a numeric
# ID or a URL-encoded namespaced path. A raw namespaced path with literal `/`
# is interpreted as additional path segments and yields 404. If the JSON
# carries a raw path (contains `/` and no `%`), encode the slashes here so the
# rest of the script can interpolate $PROJECT_ID safely. Already-encoded paths
# and numeric IDs pass through unchanged.
if [[ "$PROJECT_ID" == */* ]] && [[ "$PROJECT_ID" != *%* ]]; then
    PROJECT_ID=$(printf '%s' "$PROJECT_ID" | sed 's|/|%2F|g')
fi

PROJECT_URL="$GITLAB_URL/api/v4/projects/$PROJECT_ID"
BASE_URL="$PROJECT_URL/merge_requests/$MR_IID"

DIRECT_COUNT=$(jq '[.comments[] | select(.channel == "direct")] | length' "$REVIEW_JSON")
DRAFT_COUNT=$(jq '[.comments[] | select(.channel == "draft")] | length' "$REVIEW_JSON")

HAD_FAILURE=false

# ---------------------------------------------------------------------------
# Pre-flight: project must exist & be reachable.
#
# Cheap GET /projects/:id catches the original 404-per-draft failure mode
# (raw-slash project path, typo, missing access) up front instead of after
# the validation pass and channel-A posts. In dry-run we only check if a
# token happens to be available — we don't require auth there.
# ---------------------------------------------------------------------------

if [ -n "$TOKEN" ]; then
    project_check_body=$(mktemp)
    project_check_code=$(curl -s -o "$project_check_body" -w "%{http_code}" \
        -H "PRIVATE-TOKEN: $TOKEN" \
        "$PROJECT_URL")
    if [[ ! "$project_check_code" =~ ^2[0-9]{2}$ ]]; then
        echo "Error: project pre-flight failed: GET $PROJECT_URL → HTTP $project_check_code" >&2
        echo "  project_id from JSON: $(jq -r '.project_id' "$REVIEW_JSON")" >&2
        echo "  resolved (encoded):   $PROJECT_ID" >&2
        if [ "$project_check_code" = "404" ]; then
            echo "  Hint: ensure project_id is a numeric ID or a URL-encoded namespaced path" >&2
            echo "        (use ~/.claude/scripts/gl-project-id.sh to emit the correct form)." >&2
        fi
        rm -f "$project_check_body"
        exit 2
    fi
    rm -f "$project_check_body"
fi

# ---------------------------------------------------------------------------
# Pre-flight: validate positions are within base_sha..head_sha.
# ---------------------------------------------------------------------------

if [ -x "$SCRIPT_DIR/gl-validate-positions.sh" ]; then
    if ! "$SCRIPT_DIR/gl-validate-positions.sh" "$REVIEW_JSON"; then
        echo "Aborting: position validation failed — no comments posted." >&2
        exit 2
    fi
else
    echo "Warning: gl-validate-positions.sh not found — skipping pre-flight validation" >&2
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Print a single planned API call in dry-run mode.
dry_print() {
    local method="$1" url="$2" payload="${3:-}"
    echo "[DRY] $method $url"
    if [ -n "$payload" ]; then
        echo "$payload" | jq . 2>/dev/null | sed 's/^/      /' || echo "      $payload"
    fi
}

# Build position JSON for a comment, omitting null line fields. Uses --arg so
# SHAs and paths are properly quoted regardless of content.
build_position() {
    local comment="$1"
    echo "$comment" | jq -c \
        --arg base "$BASE_SHA" \
        --arg head "$HEAD_SHA" \
        --arg start "$START_SHA" \
        '{
            position_type: "text",
            base_sha: $base,
            head_sha: $head,
            start_sha: $start,
            old_path: .old_path,
            new_path: .new_path
        } + (if .old_line != null then {old_line: .old_line} else {} end)
          + (if .new_line != null then {new_line: .new_line} else {} end)'
}

# POST JSON; print HTTP status to stdout, response body to a caller-provided file.
post_json_capture() {
    local url="$1" payload="$2" body_out="$3"
    curl -s -o "$body_out" -w "%{http_code}" \
        -X POST \
        -H "PRIVATE-TOKEN: $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url"
}

# ---------------------------------------------------------------------------
# Dry-run: emit the planned plan and exit before any HTTP call.
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" = true ]; then
    echo "=== DRY RUN: $((DIRECT_COUNT + DRAFT_COUNT)) comment(s) on MR !$MR_IID ==="

    if [ "$DIRECT_COUNT" -gt 0 ]; then
        echo "--- Channel A (direct, $DIRECT_COUNT) ---"
        for i in $(seq 0 $((DIRECT_COUNT - 1))); do
            comment=$(jq -c "[.comments[] | select(.channel == \"direct\")][$i]" "$REVIEW_JSON")
            position=$(build_position "$comment")
            body=$(echo "$comment" | jq -r '.body')
            payload=$(jq -n --arg body "$body" --argjson position "$position" \
                '{body: $body, position: $position}')
            dry_print "POST" "$BASE_URL/discussions" "$payload"
        done
    fi

    if [ "$DRAFT_COUNT" -gt 0 ]; then
        echo "--- Channel B (draft, $DRAFT_COUNT) ---"
        for i in $(seq 0 $((DRAFT_COUNT - 1))); do
            comment=$(jq -c "[.comments[] | select(.channel == \"draft\")][$i]" "$REVIEW_JSON")
            position=$(build_position "$comment")
            note=$(echo "$comment" | jq -r '.note')
            payload=$(jq -n --arg note "$note" --argjson position "$position" \
                '{note: $note, position: $position}')
            dry_print "POST" "$BASE_URL/draft_notes" "$payload"
        done
        dry_print "POST" "$BASE_URL/draft_notes/bulk_publish"
    fi

    echo "--- Verdict ---"
    case "$VERDICT" in
        approve)         echo "[DRY] glab mr approve $MR_IID + label development::done" ;;
        request_changes) echo "[DRY] label development::rejected (manual UI for actual reject)" ;;
        *)               echo "[DRY] verdict=$VERDICT (no label change)" ;;
    esac
    echo "=== DRY RUN: end (no HTTP calls executed) ==="
    exit 0
fi

# ---------------------------------------------------------------------------
# Channel A: Direct comments (Discussions API)
# ---------------------------------------------------------------------------

if [ "$DIRECT_COUNT" -gt 0 ]; then
    direct_ok=0
    direct_fail=0
    body_tmp=$(mktemp)
    trap 'rm -f "$body_tmp"' EXIT

    for i in $(seq 0 $((DIRECT_COUNT - 1))); do
        comment=$(jq -c "[.comments[] | select(.channel == \"direct\")][$i]" "$REVIEW_JSON")
        position=$(build_position "$comment")
        body=$(echo "$comment" | jq -r '.body')

        payload=$(jq -n --arg body "$body" --argjson position "$position" \
            '{body: $body, position: $position}')

        http_code=$(post_json_capture "$BASE_URL/discussions" "$payload" "$body_tmp")

        if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
            direct_ok=$((direct_ok + 1))
        else
            direct_fail=$((direct_fail + 1))
            file=$(echo "$comment" | jq -r '.new_path // .old_path // "?"')
            line=$(echo "$comment" | jq -r '.new_line // .old_line // "?"')
            echo "Warning: direct comment $((i + 1)) at $file:$line failed (HTTP $http_code)" >&2
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
# Channel B: Draft notes (Draft Notes API) + bulk publish with ID tracking
# ---------------------------------------------------------------------------

if [ "$DRAFT_COUNT" -gt 0 ]; then
    # Parallel arrays — bash 3.2 has no associative arrays. Lookup by index.
    OUR_DRAFT_IDS=()           # IDs created in this run
    OUR_DRAFT_LABELS=()        # parallel "file:line" labels for reports
    draft_ok=0
    draft_fail=0
    body_tmp=$(mktemp)
    trap 'rm -f "$body_tmp"' EXIT

    for i in $(seq 0 $((DRAFT_COUNT - 1))); do
        comment=$(jq -c "[.comments[] | select(.channel == \"draft\")][$i]" "$REVIEW_JSON")
        position=$(build_position "$comment")
        note=$(echo "$comment" | jq -r '.note')
        file=$(echo "$comment" | jq -r '.new_path // .old_path // "?"')
        line=$(echo "$comment" | jq -r '.new_line // .old_line // "?"')

        payload=$(jq -n --arg note "$note" --argjson position "$position" \
            '{note: $note, position: $position}')

        http_code=$(post_json_capture "$BASE_URL/draft_notes" "$payload" "$body_tmp")

        if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
            draft_id=$(jq -r '.id // empty' "$body_tmp")
            if [ -n "$draft_id" ]; then
                OUR_DRAFT_IDS+=("$draft_id")
                OUR_DRAFT_LABELS+=("$file:$line")
                draft_ok=$((draft_ok + 1))
            else
                draft_fail=$((draft_fail + 1))
                echo "Warning: draft note $((i + 1)) at $file:$line returned 2xx but no id field" >&2
            fi
        else
            draft_fail=$((draft_fail + 1))
            echo "Warning: draft note $((i + 1)) at $file:$line failed (HTTP $http_code)" >&2
        fi
    done

    if [ "$draft_fail" -eq 0 ]; then
        echo "Channel B (draft): $draft_ok/$DRAFT_COUNT created"
    else
        echo "Channel B (draft): $draft_ok/$DRAFT_COUNT created, $draft_fail failed"
        HAD_FAILURE=true
    fi

    # -- Bulk publish ----------------------------------------------------------

    if [ "${#OUR_DRAFT_IDS[@]}" -eq 0 ]; then
        echo "Bulk publish: skipped (no drafts created)"
    else
        bulk_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST \
            -H "PRIVATE-TOKEN: $TOKEN" \
            "$BASE_URL/draft_notes/bulk_publish")

        # Whether bulk_publish returns 2xx or not, the truth is in the draft
        # listing: which of OUR specific IDs survived?
        if [[ ! "$bulk_code" =~ ^2[0-9]{2}$ ]]; then
            echo "Warning: bulk_publish returned HTTP $bulk_code, verifying against our draft IDs..." >&2
            sleep 2
        fi

        remaining_drafts=$(curl -sf -H "PRIVATE-TOKEN: $TOKEN" "$BASE_URL/draft_notes" \
            | jq -r '.[].id' || echo "")

        unpublished=()           # IDs that still need publishing
        unpublished_labels=()    # parallel "file:line" labels
        for idx in "${!OUR_DRAFT_IDS[@]}"; do
            id="${OUR_DRAFT_IDS[$idx]}"
            if echo "$remaining_drafts" | grep -qx "$id"; then
                unpublished+=("$id")
                unpublished_labels+=("${OUR_DRAFT_LABELS[$idx]}")
            fi
        done

        if [ "${#unpublished[@]}" -eq 0 ]; then
            if [[ "$bulk_code" =~ ^2[0-9]{2}$ ]]; then
                echo "Bulk publish: OK (${#OUR_DRAFT_IDS[@]} drafts published)"
            else
                echo "Bulk publish: OK (HTTP $bulk_code but all ${#OUR_DRAFT_IDS[@]} drafts confirmed published)"
            fi
        else
            # Try to publish each survivor individually. 404 means the draft
            # was published in a race between list and PUT — count as success.
            echo "Bulk publish: ${#unpublished[@]}/${#OUR_DRAFT_IDS[@]} drafts unpublished, retrying individually..." >&2
            individual_ok=0
            individual_fail=0
            still_pending=()

            for idx in "${!unpublished[@]}"; do
                id="${unpublished[$idx]}"
                label="${unpublished_labels[$idx]}"
                pub_code=$(curl -s -o /dev/null -w "%{http_code}" \
                    -X PUT \
                    -H "PRIVATE-TOKEN: $TOKEN" \
                    "$BASE_URL/draft_notes/$id/publish")
                if [[ "$pub_code" =~ ^2[0-9]{2}$ ]] || [ "$pub_code" = "404" ]; then
                    individual_ok=$((individual_ok + 1))
                else
                    individual_fail=$((individual_fail + 1))
                    still_pending+=("$id ($label) HTTP $pub_code")
                fi
            done

            if [ "$individual_fail" -eq 0 ]; then
                echo "Bulk publish: OK (individual retry: $individual_ok/${#unpublished[@]})"
            else
                echo "Error: $individual_fail draft(s) could not be published; left in place for retry:" >&2
                for entry in "${still_pending[@]}"; do
                    echo "  - draft $entry" >&2
                done
                HAD_FAILURE=true
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Verdict — only apply labels if we did not have a posting failure.
# ---------------------------------------------------------------------------

if [ "$HAD_FAILURE" = true ]; then
    echo "Skipping verdict labels: posting had failures" >&2
else
    case "$VERDICT" in
        approve)
            if glab mr approve "$MR_IID" >/dev/null 2>&1; then
                echo "Verdict (approve): OK"
            else
                echo "Warning: approval failed" >&2
                HAD_FAILURE=true
            fi
            glab mr update "$MR_IID" --label "development::done" >/dev/null 2>&1 || true
            if [ -n "$ISSUE_ID" ]; then
                glab issue update "$ISSUE_ID" --label "development::done" >/dev/null 2>&1 || true
            fi
            echo "Labels: development::done"
            ;;
        request_changes)
            glab mr update "$MR_IID" --label "development::rejected" >/dev/null 2>&1 || true
            if [ -n "$ISSUE_ID" ]; then
                glab issue update "$ISSUE_ID" --label "development::rejected" >/dev/null 2>&1 || true
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
fi

# ---------------------------------------------------------------------------
# Exit
# ---------------------------------------------------------------------------

if [ "$HAD_FAILURE" = true ]; then
    exit 1
fi
exit 0
