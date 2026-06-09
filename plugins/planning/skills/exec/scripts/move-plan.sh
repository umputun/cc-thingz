#!/bin/bash
# move a completed plan file into its sibling completed/ directory and commit it
# usage: move-plan.sh <plan-file-path>
# no-op if the plan is already under completed/ or the file is missing
# VCS-aware commit via stage-and-commit.sh; does NOT push

set -e

if [ $# -lt 1 ]; then
    echo "error: usage: move-plan.sh <plan-file-path>" >&2
    exit 1
fi

plan="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# already under completed/ — nothing to do
case "$plan" in
*/completed/*)
    echo "plan already under completed/: $plan"
    exit 0
    ;;
esac

# file missing (already moved, or never existed) — nothing to do
if [ ! -f "$plan" ]; then
    echo "plan file not found, skipping move: $plan" >&2
    exit 0
fi

base="$(basename "$plan")"
dest_dir="$(dirname "$plan")/completed"
dest="$dest_dir/$base"

# refuse to clobber an existing completed plan with the same name
if [ -e "$dest" ]; then
    echo "error: destination already exists, refusing to overwrite: $dest" >&2
    exit 1
fi

mkdir -p "$dest_dir"
mv "$plan" "$dest"

# stage-and-commit.sh stages both the (now-removed) old path and the new path;
# git and hg each record this as the rename plus commit
bash "$SCRIPT_DIR/stage-and-commit.sh" "docs: move completed plan $base to completed/" "$plan" "$dest"

echo "moved plan to $dest"
