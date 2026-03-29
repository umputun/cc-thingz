#!/bin/bash
# resolve a file through the three-layer override chain
# usage: resolve-file.sh <relative-path>
# e.g.: resolve-file.sh prompts/task.md
# e.g.: resolve-file.sh agents/quality.txt
#
# checks in order:
#   1. .claude/exec-plan/<path> (project override)
#   2. CLAUDE_PLUGIN_DATA/<path> (user override, if env var set)
#   3. bundled default (derived from script location)
#
# outputs the file content to stdout

set -e

path="$1"
if [ -z "$path" ]; then
    echo "error: usage: resolve-file.sh <relative-path>" >&2
    exit 1
fi

# derive skill root from script location
# script is at <skill-root>/scripts/resolve-file.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f ".claude/exec-plan/$path" ]; then
    cat ".claude/exec-plan/$path"
elif [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -f "$CLAUDE_PLUGIN_DATA/$path" ]; then
    cat "$CLAUDE_PLUGIN_DATA/$path"
elif [ -f "$SKILL_ROOT/references/$path" ]; then
    cat "$SKILL_ROOT/references/$path"
else
    echo "error: file not found in override chain: $path" >&2
    exit 1
fi
