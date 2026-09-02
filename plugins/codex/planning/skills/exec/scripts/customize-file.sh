#!/bin/bash
# copy a bundled prompt or agent file to an override location for editing
# usage: customize-file.sh <relative-path> [--user]
# e.g.: customize-file.sh prompts/review.md
# e.g.: customize-file.sh agents/quality.txt --user
#
# with --user, copies to the Codex user override directory for all projects.
# without it, copies to .codex/exec-plan/<path> at project level.
#
# an override shadows the bundled default permanently -- see the "Customization"
# paragraph of README.md, which is authoritative for the consequences
#
# refuses to overwrite an existing override; prints the destination path

set -e

path="$1"
if [ -z "$path" ]; then
    echo "error: usage: customize-file.sh <relative-path> [--user]" >&2
    exit 1
fi

case "$path" in
    /*|../*|*/../*|*/..)
        echo "error: path must be relative and stay inside the override dir: $path" >&2
        exit 1
        ;;
esac

scope="${2:-}"
if [ -n "$scope" ] && [ "$scope" != "--user" ]; then
    echo "error: second argument must be --user" >&2
    exit 1
fi

codex_home="${CODEX_HOME:-$HOME/.codex}"
data_dir=""
if [ "$scope" = "--user" ]; then
    data_dir="$codex_home/cc-thingz/planning/exec-plan"
fi

# derive skill root from script location: <skill-root>/scripts/customize-file.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"

src="$SKILL_ROOT/references/$path"
if [ ! -f "$src" ]; then
    echo "error: no bundled file at $path" >&2
    exit 1
fi

if [ -n "$data_dir" ]; then
    dest="$data_dir/$path"
else
    dest=".codex/exec-plan/$path"
fi

# -L as well as -e: a dangling symlink is invisible to -e, and cp would follow it
# and write outside the override directory, defeating the path guard above
if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "error: override already exists, edit it in place: $dest" >&2
    exit 1
fi

# the -e/-L check above only covers the destination file. any ancestor directory can
# be a symlink too: mkdir -p accepts it and cp follows it, so the copy lands outside
# the override dir. walk the components at or below the override root and refuse any
# symlink among them. components above the root are not checked -- the data dir comes
# from the caller, and a symlinked $HOME or ~/.codex is a legitimate setup.
#
# the two branches are deliberately asymmetric: at project level the walk stops at the
# working directory, so `.codex` itself is checked too. that is stricter than the
# user-level exemption on purpose -- `.codex` comes out of the checked-out repository,
# not the caller, so a repo shipping `.codex` as a symlink could otherwise redirect the
# copy anywhere. someone whose `.codex` is symlinked into a dotfiles repo gets a clear
# error and can use the user-level data dir instead
if [ -n "$data_dir" ]; then
    stop="$data_dir"
else
    stop="."
fi
# "." terminates the walk as well as "/": dirname "." is ".", so a $stop that is somehow
# absent from the chain would otherwise spin here forever rather than fail
dir="$(dirname "$dest")"
while [ "$dir" != "$stop" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    if [ -L "$dir" ]; then
        echo "error: refusing to write through a symlinked directory component: $dir" >&2
        exit 1
    fi
    dir="$(dirname "$dir")"
done

mkdir -p "$(dirname "$dest")"
cp "$src" "$dest"
echo "$dest"
