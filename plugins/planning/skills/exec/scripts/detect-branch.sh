#!/bin/bash
# detect the default branch name of the current repository
# outputs the branch name to stdout
# avoids network calls when possible
# VCS-aware: dispatches to git or hg based on detect-vcs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
vcs=$(bash "$SCRIPT_DIR/detect-vcs.sh")

do_git() {
    # 1. check cached remote HEAD (local, fast)
    branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

    # 2. check for common default branch names locally
    if [ -z "$branch" ]; then
        for candidate in main master trunk develop; do
            if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
                branch="$candidate"
                break
            fi
        done
    fi

    # 3. last resort: ask remote (may block if network is unreachable)
    if [ -z "$branch" ]; then
        branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //')
    fi

    # 4. fallback
    if [ -z "$branch" ]; then
        branch="main"
    fi

    echo "$branch"
}

do_hg() {
    echo "default"
}

case "$vcs" in
git) do_git "$@" ;;
hg) do_hg "$@" ;;
*)
    echo "error: unsupported VCS: $vcs" >&2
    exit 1
    ;;
esac
