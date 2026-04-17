#!/bin/bash
# create a feature branch from plan file name if on the default branch
# usage: create-branch.sh <plan-file-path>
# exits 0 if branch created or already on feature branch
# outputs branch name to stdout
#
# strips leading YYYYMMDD- date prefix from branch name since plan files
# use date prefixes (e.g., 20260329-feature-name.md) but branch names should not
# VCS-aware: dispatches to git or hg based on detect-vcs.sh

set -e

if [ -z "${1:-}" ]; then
    echo "error: plan file path required" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
vcs=$(bash "$SCRIPT_DIR/detect-vcs.sh")

# derive branch name from plan file path (shared by git and hg paths)
# e.g., docs/plans/20260329-feature-name.md -> feature-name
derive_branch_name() {
    local name
    name=$(basename "$1" .md)
    # strip leading date prefix if present (YYYYMMDD- or YYYY-MM-DD-)
    # shellcheck disable=SC2001 # regex too complex for ${var//pattern}
    name=$(echo "$name" | sed 's/^[0-9]\{4\}-\{0,1\}[0-9]\{2\}-\{0,1\}[0-9]\{2\}-//')
    echo "$name"
}

do_git() {
    local plan_file="$1"
    local current_branch
    current_branch=$(git branch --show-current)

    # detect the default branch using local-first fallback chain (avoids network calls that can hang)
    # 1. check cached remote HEAD (local, fast)
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [ -z "$default_branch" ]; then
        # 2. check for common default branch names locally
        for candidate in main master trunk develop; do
            if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
                default_branch="$candidate"
                break
            fi
        done
    fi
    if [ -z "$default_branch" ]; then
        # 3. last resort: ask remote (may block if network is unreachable)
        default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //')
    fi

    # if already on a feature branch (not the default and not detached), just report it
    if [ -n "$current_branch" ] && [ -n "$default_branch" ] && [ "$current_branch" != "$default_branch" ]; then
        echo "$current_branch"
        return 0
    elif [ -n "$current_branch" ] && [ -z "$default_branch" ] && [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
        # no default branch detected, fall back to main/master check
        echo "$current_branch"
        return 0
    fi

    local branch_name
    branch_name=$(derive_branch_name "$plan_file")

    # check if branch already exists
    if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
        git checkout "$branch_name"
    else
        git checkout -b "$branch_name"
    fi

    echo "$branch_name"
}

do_hg() {
    local plan_file="$1"
    local current
    current=$(hg branch)
    if [ "$current" != "default" ]; then
        echo "$current"
        return 0
    fi

    local branch_name
    branch_name=$(derive_branch_name "$plan_file")

    # partial-run recovery: if branch already committed, hg update; else hg branch.
    # fresh-branch (working-copy only) is not listed — 'hg branch' re-marks it safely.
    if hg branches -q | grep -qxF "$branch_name"; then
        hg update "$branch_name" >/dev/null
    else
        hg branch "$branch_name" >/dev/null
    fi

    echo "$branch_name"
}

case "$vcs" in
git) do_git "$@" ;;
hg) do_hg "$@" ;;
*)
    echo "error: unsupported VCS: $vcs" >&2
    exit 1
    ;;
esac
