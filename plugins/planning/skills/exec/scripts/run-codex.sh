#!/bin/bash
# run codex review and return output
# usage: run-codex.sh "<prompt>"
# outputs codex response to stdout

set -e

prompt="$1"
if [ -z "$prompt" ]; then
    echo "error: usage: run-codex.sh '<prompt>'" >&2
    exit 1
fi

codex exec \
  --sandbox read-only \
  -c model="gpt-5.4" \
  -c model_reasoning_effort="high" \
  -c stream_idle_timeout_ms=3600000 \
  -c project_doc="$HOME/.claude/CLAUDE.md" \
  -c project_doc="./CLAUDE.md" \
  "$prompt"
