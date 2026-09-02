#!/bin/bash
# detect GitHub vs GitLab vs Gitea from git remote
# outputs: github, gitlab or gitea on stdout, errors on stderr

set -e

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: not a git repository" >&2
    exit 1
fi

# || true keeps set -e from aborting when origin is missing, so the check below reports it
remote_url=$(git remote get-url origin 2>/dev/null || true)

if [ -z "$remote_url" ]; then
    echo "error: no origin remote configured" >&2
    exit 1
fi

if echo "$remote_url" | grep -qiE "github\.com"; then
    echo "github"
elif echo "$remote_url" | grep -qiE "gitlab\."; then
    echo "gitlab"
elif echo "$remote_url" | grep -qiE "gitea\."; then
    echo "gitea"
elif command -v glab &>/dev/null && glab repo view &>/dev/null; then
    echo "gitlab"
else
    echo "error: unknown platform for $remote_url" >&2
    exit 1
fi
