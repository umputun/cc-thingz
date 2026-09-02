#!/bin/bash
# detect the default branch name of the current repository
# outputs the branch name to stdout
# avoids network calls when possible
# VCS-aware: dispatches to git or hg based on detect-vcs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
vcs=$(bash "$SCRIPT_DIR/detect-vcs.sh")

do_git() {
    local branch
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
    # probe common default-branch remote-tracking refs first — modern Mercurial
    # workflows expose the upstream default as `remote/<name>` and jj uses the
    # same convention. present(remote/<name>) returns empty instead of aborting
    # when the revset is absent, so the loop is safe on repos that do not
    # expose remote-tracking refs this way
    local candidate
    for candidate in master main trunk; do
        if hg log -r "present(remote/$candidate)" --template '{node}\n' 2>/dev/null | grep -q .; then
            echo "remote/$candidate"
            return 0
        fi
    done

    # vanilla-hg fallback: the traditional named branch
    echo "default"
}

case "$vcs" in
git) do_git ;;
hg) do_hg ;;
*)
    echo "error: unsupported VCS: $vcs" >&2
    exit 1
    ;;
esac
