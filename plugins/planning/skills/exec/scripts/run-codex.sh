#!/bin/bash
# run codex review and return output
# usage: run-codex.sh <prompt-file>
# the prompt file contains the review prompt text
# passes prompt via stdin to avoid command-line length limits
# outputs codex response to stdout

set -e

prompt_file="$1"
if [ -z "$prompt_file" ] || [ ! -f "$prompt_file" ]; then
    echo "error: usage: run-codex.sh <prompt-file>" >&2
    exit 1
fi

codex exec \
  --sandbox read-only \
  -c model="gpt-5.4" \
  -c model_reasoning_effort="high" \
  -c stream_idle_timeout_ms=3600000 \
  -c project_doc="$HOME/.claude/CLAUDE.md" \
  -c project_doc="./CLAUDE.md" \
  < "$prompt_file"
