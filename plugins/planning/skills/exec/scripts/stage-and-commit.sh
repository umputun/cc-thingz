#!/bin/bash
# stage files and commit with a message
# usage: stage-and-commit.sh <message> <file1> [file2 ...]
# VCS-aware: dispatches to git or hg based on detect-vcs.sh

set -e

if [ $# -lt 2 ]; then
    echo "error: usage: stage-and-commit.sh <message> <file1> [file2 ...]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
vcs=$(bash "$SCRIPT_DIR/detect-vcs.sh")

do_git() {
    local msg="$1"
    shift
    git add -- "$@"
    git commit -m "$msg"
}

do_hg() {
    # -A marks untracked files as added and missing files as removed within the
    # commit selection — parity with 'git add -- <files> && git commit'. Without
    # -A, committing a new untracked file aborts with 'file not tracked'.
    local msg="$1"
    shift
    hg commit -A -m "$msg" -- "$@"
}

case "$vcs" in
git) do_git "$@" ;;
hg) do_hg "$@" ;;
*)
    echo "error: unsupported VCS: $vcs" >&2
    exit 1
    ;;
esac
