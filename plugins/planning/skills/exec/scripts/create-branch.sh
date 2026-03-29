#!/bin/bash
# create a feature branch from plan file name if on the default branch
# usage: create-branch.sh <plan-file-path>
# exits 0 if branch created or already on feature branch
# outputs branch name to stdout
#
# strips leading YYYYMMDD- date prefix from branch name since plan files
# use date prefixes (e.g., 20260329-feature-name.md) but branch names should not

set -e

plan_file="$1"
if [ -z "$plan_file" ]; then
    echo "error: plan file path required" >&2
    exit 1
fi

current_branch=$(git branch --show-current)

# handle detached HEAD — treat as being on default branch
if [ -z "$current_branch" ]; then
    current_branch=""
fi

# detect the default branch using local-first fallback chain (avoids network calls that can hang)
# 1. check cached remote HEAD (local, fast)
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
    exit 0
elif [ -n "$current_branch" ] && [ -z "$default_branch" ] && [ "$current_branch" != "main" ] && [ "$current_branch" != "master" ]; then
    # no default branch detected, fall back to main/master check
    echo "$current_branch"
    exit 0
fi

# derive branch name from plan file name
# e.g., docs/plans/20260329-feature-name.md -> feature-name
branch_name=$(basename "$plan_file" .md)

# strip leading date prefix if present (YYYYMMDD- or YYYY-MM-DD-)
branch_name=$(echo "$branch_name" | sed 's/^[0-9]\{4\}-\{0,1\}[0-9]\{2\}-\{0,1\}[0-9]\{2\}-//')

# check if branch already exists
if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    git checkout "$branch_name"
else
    git checkout -b "$branch_name"
fi

echo "$branch_name"
