#!/bin/bash
# detect the default branch name using local-first fallback chain
# outputs the branch name to stdout
# avoids network calls when possible

set -e

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
