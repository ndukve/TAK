#!/usr/bin/env bash
# `git merge --ff-only` (update.sh) removes tracked files a commit deleted,
# but it can't touch Python's own __pycache__/*.pyc — those were never
# tracked by git, so a .py file deleted upstream (admin/api, scripts/) leaves
# its compiled bytecode sitting on disk indefinitely.

# Remove __pycache__ entries for every .py file a commit range deleted.
cleanup_stale_pycache() {
    local old_ref="$1" new_ref="$2"
    local deleted removed=0
    deleted="$(git diff --no-renames --name-only --diff-filter=D "$old_ref" "$new_ref" -- '*.py' 2>/dev/null || true)"
    [ -z "$deleted" ] && return 0

    while IFS= read -r rel_path; do
        [ -z "$rel_path" ] && continue
        local dir base stem cache_dir
        dir="$(dirname "$rel_path")"
        base="$(basename "$rel_path")"
        stem="${base%.py}"
        cache_dir="$SCRIPT_DIR/$dir/__pycache__"
        [ -d "$cache_dir" ] || continue
        while IFS= read -r -d '' stale; do
            rm -f -- "$stale"
            removed=$((removed + 1))
        done < <(find "$cache_dir" -maxdepth 1 -name "${stem}.cpython-*.pyc" -print0 2>/dev/null)
    done <<< "$deleted"

    [ "$removed" -gt 0 ] && info "Removed $removed stale __pycache__ file(s) for modules deleted upstream"
    return 0
}
