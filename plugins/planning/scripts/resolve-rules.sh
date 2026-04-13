#!/bin/bash
# resolve custom rules file through the two-layer override chain
# usage: resolve-rules.sh <filename>
# e.g.: resolve-rules.sh planning-rules.md
#
# checks in order (first-found-wins, not merged):
#   1. .claude/<filename> (project override)
#   2. $CLAUDE_PLUGIN_DATA/<filename> (user override)
#
# outputs file content to stdout if found, empty output if not
# always exits 0

filename="$1"
if [ -z "$filename" ]; then
    exit 0
fi

if [ -f ".claude/$filename" ] && [ -s ".claude/$filename" ]; then
    cat ".claude/$filename"
elif [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -f "$CLAUDE_PLUGIN_DATA/$filename" ] && [ -s "$CLAUDE_PLUGIN_DATA/$filename" ]; then
    cat "$CLAUDE_PLUGIN_DATA/$filename"
fi

exit 0
