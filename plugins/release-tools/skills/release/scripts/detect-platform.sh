#!/bin/bash
# detect GitHub vs GitLab vs Gitea from git remote
# outputs: github, gitlab, gitea, or error message

set -e

remote_url=$(git remote get-url origin 2>/dev/null)

if [ -z "$remote_url" ]; then
    echo "error: no origin remote configured"
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
    echo "error: unknown platform for $remote_url"
    exit 1
fi
