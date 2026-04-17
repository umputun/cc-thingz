#!/bin/bash
# run codex review and return output
# usage: run-codex.sh "<prompt>"
# outputs codex response to stdout
# VCS-aware: in hg repos, adds --skip-git-repo-check so codex doesn't refuse

set -e

prompt="$1"
if [ -z "$prompt" ]; then
    echo "error: usage: run-codex.sh '<prompt>'" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# detect-vcs.sh exits non-zero on non-VCS dirs; set -e propagates so the
# script aborts before reaching codex with an unknown VCS value
vcs=$(bash "$SCRIPT_DIR/detect-vcs.sh")

# build args as an array so the hg-specific flag can be positioned right after
# 'exec' (before --sandbox) as an exec-level option
args=("exec")
[ "$vcs" = "hg" ] && args+=("--skip-git-repo-check")
args+=(
    "--sandbox" "read-only"
    "-c" "model=${CODEX_MODEL:-gpt-5.4}"
    "-c" "model_reasoning_effort=high"
    "-c" "stream_idle_timeout_ms=3600000"
    "-c" "project_doc=$HOME/.claude/CLAUDE.md"
    "-c" "project_doc=./CLAUDE.md"
)

codex "${args[@]}" "$prompt"
