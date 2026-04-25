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
args+=("--sandbox" "read-only")

# -c overrides switch provider routing in a way some corporate codex
# proxies / wrappers reject (e.g. "Error: Model provider 'responses' not
# found"). Set CODEX_NO_OVERRIDES=1 to skip the overrides and fall
# through to the proxy's defaults. Only the literal value `1` activates
# suppression -- any other value (including `0`, `false`, empty) keeps
# the overrides on, matching the documented "set to 1 to enable" semantic.
if [ "${CODEX_NO_OVERRIDES:-}" != 1 ]; then
    args+=(
        "-c" "model=${CODEX_MODEL:-gpt-5.4}"
        "-c" "model_reasoning_effort=high"
        "-c" "stream_idle_timeout_ms=3600000"
        "-c" "project_doc=$HOME/.claude/CLAUDE.md"
        "-c" "project_doc=./CLAUDE.md"
    )
fi

codex "${args[@]}" "$prompt"
