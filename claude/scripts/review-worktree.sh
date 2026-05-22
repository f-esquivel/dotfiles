#!/usr/bin/env bash
# review-worktree.sh — manage review worktrees under ~/.claude/worktrees/reviews/
#
# Subcommands:
#   init <gl|gh> <id>                          Emit eval-able exports:
#                                                REPO_SLUG, MAIN_REPO, WORKTREE, META_FILE
#   write-meta <gl|gh> <id> [key=value ...]   Create/update sidecar meta.json
#   list [--json]                              List all review worktrees with status
#   remove <gl|gh> <id>                        Remove worktree + meta (uses meta's main_repo)
#   remove-path <worktree_path>                Remove a specific worktree by path
#
# Layout:
#   ~/.claude/worktrees/reviews/
#     <repo-slug>/
#       gl-676/              ← the worktree (git checkout)
#       gl-676.meta.json     ← sidecar metadata

set -euo pipefail

ROOT="${HOME}/.claude/worktrees/reviews"

usage() {
    sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
}

# Resolve the main repo (works from inside a worktree too).
main_repo_from_cwd() {
    local common_dir
    common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        echo "error: not in a git repo" >&2
        return 2
    }
    if [[ "$common_dir" != /* ]]; then
        common_dir="$(pwd)/$common_dir"
    fi
    # Strip trailing /.git (or /name.git for bare); for normal repos this is /.git
    dirname "$common_dir"
}

repo_slug_from_cwd() {
    basename "$(main_repo_from_cwd)"
}

cmd_init() {
    [[ $# -eq 2 ]] || usage
    local prefix="$1" id="$2"
    local slug main
    slug="$(repo_slug_from_cwd)"
    main="$(main_repo_from_cwd)"
    mkdir -p "${ROOT}/${slug}"
    cat <<EOF
REPO_SLUG=${slug}
MAIN_REPO=${main}
WORKTREE=${ROOT}/${slug}/${prefix}-${id}
META_FILE=${ROOT}/${slug}/${prefix}-${id}.meta.json
EOF
}

cmd_write_meta() {
    [[ $# -ge 2 ]] || usage
    local prefix="$1" id="$2"; shift 2
    local slug main meta
    slug="$(repo_slug_from_cwd)"
    main="$(main_repo_from_cwd)"
    meta="${ROOT}/${slug}/${prefix}-${id}.meta.json"
    mkdir -p "$(dirname "$meta")"
    python3 - "$meta" "$prefix" "$id" "$slug" "$main" "$@" <<'PY'
import json, sys, os, datetime, pathlib
meta_path, prefix, mr_id, slug, main_repo, *kvs = sys.argv[1:]
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
data = {}
if os.path.exists(meta_path):
    with open(meta_path) as f:
        data = json.load(f)
data.setdefault("platform_prefix", prefix)
data.setdefault("mr_id", int(mr_id))
data.setdefault("repo_slug", slug)
data.setdefault("main_repo", main_repo)
data.setdefault("created_at", now)
data["updated_at"] = now
for kv in kvs:
    k, _, v = kv.partition("=")
    if not k:
        continue
    # coerce int / bool when obvious
    if v.isdigit() or (v.startswith("-") and v[1:].isdigit()):
        v = int(v)
    elif v.lower() in ("true", "false"):
        v = v.lower() == "true"
    data[k] = v
pathlib.Path(meta_path).write_text(json.dumps(data, indent=2) + "\n")
print(meta_path)
PY
}

cmd_list() {
    local fmt="text"
    [[ ${1:-} == "--json" ]] && fmt="json"
    python3 - "$ROOT" "$fmt" <<'PY'
import json, os, sys, datetime
root, fmt = sys.argv[1], sys.argv[2]
entries = []
if os.path.isdir(root):
    for slug in sorted(os.listdir(root)):
        slug_dir = os.path.join(root, slug)
        if not os.path.isdir(slug_dir):
            continue
        for name in sorted(os.listdir(slug_dir)):
            if not name.endswith(".meta.json"):
                continue
            with open(os.path.join(slug_dir, name)) as f:
                d = json.load(f)
            d["worktree_path"] = os.path.join(slug_dir, name[: -len(".meta.json")])
            d["worktree_exists"] = os.path.isdir(d["worktree_path"])
            try:
                created = datetime.datetime.fromisoformat(d["created_at"].replace("Z", "+00:00"))
                d["age_days"] = (datetime.datetime.now(datetime.timezone.utc) - created).days
            except Exception:
                d["age_days"] = None
            entries.append(d)
if fmt == "json":
    print(json.dumps(entries, indent=2))
else:
    if not entries:
        print("(no review worktrees found)")
        sys.exit(0)
    for e in entries:
        age = f'{e["age_days"]}d' if e["age_days"] is not None else "?"
        status = "exists" if e["worktree_exists"] else "MISSING"
        print(
            f'{e["repo_slug"]}/{e["platform_prefix"]}-{e["mr_id"]}  '
            f'age={age}  [{status}]  '
            f'verdict={e.get("last_verdict","-")}  rounds={e.get("rounds","-")}'
        )
        print(f'  branch: {e.get("branch","-")}')
        print(f'  path:   {e["worktree_path"]}')
        print(f'  main:   {e["main_repo"]}')
PY
}

_remove_one() {
    local meta="$1" wt main
    [[ -f "$meta" ]] || { echo "no meta at $meta" >&2; return 1; }
    main="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("main_repo",""))' "$meta")"
    wt="${meta%.meta.json}"
    if [[ -n "$main" && -d "$main" && -d "$wt" ]]; then
        git -C "$main" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    elif [[ -d "$wt" ]]; then
        rm -rf "$wt"
    fi
    [[ -n "$main" && -d "$main" ]] && git -C "$main" worktree prune 2>/dev/null || true
    rm -f "$meta"
    # Remove the per-repo slug dir if empty
    rmdir "$(dirname "$meta")" 2>/dev/null || true
    echo "removed $(basename "$(dirname "$meta")")/$(basename "$wt")"
}

cmd_remove() {
    [[ $# -eq 2 ]] || usage
    local prefix="$1" id="$2"
    local found=0
    shopt -s dotglob nullglob
    if [[ -d "$ROOT" ]]; then
        for slug_dir in "$ROOT"/*/; do
            [[ -d "$slug_dir" ]] || continue
            local meta="${slug_dir}${prefix}-${id}.meta.json"
            if [[ -f "$meta" ]]; then
                _remove_one "$meta"
                found=1
            fi
        done
    fi
    shopt -u dotglob nullglob
    if [[ $found -eq 0 ]]; then
        echo "no meta found for ${prefix}-${id}" >&2
        return 1
    fi
}

cmd_remove_path() {
    [[ $# -eq 1 ]] || usage
    local wt="$1"
    local meta="${wt}.meta.json"
    if [[ -f "$meta" ]]; then
        _remove_one "$meta"
    else
        echo "no meta sidecar at $meta — refusing to remove" >&2
        return 1
    fi
}

[[ $# -ge 1 ]] || usage
cmd="$1"; shift || true
case "$cmd" in
    init)        cmd_init "$@" ;;
    write-meta)  cmd_write_meta "$@" ;;
    list)        cmd_list "$@" ;;
    remove)      cmd_remove "$@" ;;
    remove-path) cmd_remove_path "$@" ;;
    *)           usage ;;
esac
