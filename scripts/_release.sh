#!/usr/bin/env bash
# Version selection for update.sh: where the checkout moves (the tip of its upstream branch, a release tag, or the version it was on
# before the last update) and how. Plain functions, no side effects until release_apply, so tests can drive them in a scratch repository.
#
#   release_describe                       the version of this checkout: a tag name, or tag-N-gHASH after it, or the short hash
#   release_target <upstream> <tag> <rollback> <previous-file> [allowed-signers]
#                                          prints the commit to move to; returns 1 with a reason on stderr
#   release_apply <commit>                 fast-forwards, or moves back to an older commit (refused if this checkout holds commits that
#                                          exist on no remote); returns 1 with a reason on stderr
#   release_remember <old-commit> <file>   records where we came from, for --rollback
#
# Tags are checked with `git verify-tag` when a signers file is given (SSH signatures: git config gpg.format ssh, allowed signers file);
# without one a tag is accepted as it is.

release_describe() {
    git describe --tags --always 2>/dev/null || git rev-parse --short HEAD
}

release_target() {
    local upstream="$1" tag="$2" rollback="$3" previous_file="$4" signers="${5:-}" commit
    if [ "$rollback" = 1 ]; then
        commit="$(cat "$previous_file" 2>/dev/null || true)"
        if [ -z "$commit" ] || ! git cat-file -e "${commit}^{commit}" 2>/dev/null; then
            echo "no earlier version is recorded (or it is no longer in this checkout)" >&2
            return 1
        fi
        printf '%s\n' "$commit"
    elif [ -n "$tag" ]; then
        commit="$(git rev-parse -q --verify "refs/tags/${tag}^{commit}")" || { echo "no tag '$tag' (git fetch --tags first)" >&2; return 1; }
        if [ -n "$signers" ]; then
            git -c "gpg.ssh.allowedSignersFile=$signers" verify-tag "$tag" >/dev/null 2>&1 \
                || { echo "tag '$tag' is not signed by an allowed signer ($signers)" >&2; return 1; }
        fi
        printf '%s\n' "$commit"
    else
        git rev-parse "$upstream^{commit}"
    fi
}

release_apply() {
    local target="$1"
    if git merge-base --is-ancestor HEAD "$target"; then
        git merge --ff-only "$target" >/dev/null
    elif git merge-base --is-ancestor "$target" HEAD; then
        if [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
            echo "this checkout has commits that exist on no remote; not moving back (they would be lost)" >&2
            return 1
        fi
        git reset --hard -q "$target"
    else
        echo "the target is not on the same line of history as this checkout" >&2
        return 1
    fi
}

release_remember() {
    printf '%s\n' "$1" >"$2"
}
