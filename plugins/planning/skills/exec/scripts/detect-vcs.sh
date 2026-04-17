#!/bin/bash
# detect the VCS of the current working directory
# outputs "git" or "hg" on stdout; exits 1 if neither
# precedence: git first, hg second; if both colocated, git wins

set -e

if git rev-parse --git-dir >/dev/null 2>&1; then
    echo "git"
elif command -v hg >/dev/null 2>&1 && hg root >/dev/null 2>&1; then
    echo "hg"
else
    echo "error: not a git or mercurial repository" >&2
    exit 1
fi
