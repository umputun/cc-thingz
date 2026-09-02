#!/bin/bash
# append to the progress file with timestamp
# usage: append-progress.sh <progress-file> [message]
# if message is provided, appends single timestamped line
# if no message, reads stdin and appends all lines (for multi-line content)

set -e

if [ $# -lt 1 ]; then
    echo "error: usage: append-progress.sh <file> [message]" >&2
    exit 1
fi

file="$1"
shift

if [ $# -gt 0 ]; then
    # single line with timestamp
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$file"
else
    # multi-line from stdin
    cat >> "$file"
fi
