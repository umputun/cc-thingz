#!/bin/bash
# resolve custom rules file through the two-layer override chain
# usage: resolve-rules.sh <filename>
#
# checks in order (first-found-wins, not merged):
#   1. .codex/<filename> (project override)
#   2. $CODEX_HOME/cc-thingz/planning/<filename> (user override)
#
# outputs file content to stdout if found, empty output if not
# exits 1 when a project override resolves outside the working directory

filename="$1"
if [ -z "$filename" ]; then
    exit 0
fi

codex_home="${CODEX_HOME:-$HOME/.codex}"
data_dir="$codex_home/cc-thingz/planning"

project_file=".codex/$filename"
if [ -f "$project_file" ] && [ -s "$project_file" ]; then
    project_root="$(pwd -P)"
    resolved_project_file="$(realpath "$project_file")"
    case "$resolved_project_file" in
        "$project_root"/*) cat "$resolved_project_file" ;;
        *)
            echo "error: refusing project rules outside working directory: $project_file" >&2
            exit 1
            ;;
    esac
elif [ -f "$data_dir/$filename" ] && [ -s "$data_dir/$filename" ]; then
    cat "$data_dir/$filename"
fi

exit 0
