#!/bin/bash
# run external code review and return findings on stdout
# usage: run-external-review.sh "<external_review_cmd>" "<prompt>"
#
# with an empty <external_review_cmd>, delegates to run-codex.sh (codex-specific
# sandbox/model flags, hg handling). with a command set, that command is run
# instead, with the prompt appended as the final argv element. the "External
# review contract" section of README.md is authoritative for what the tool must
# be able to do, emit, and leave untouched -- do not restate it here
#
# exits 127 when the tool is not on PATH so the caller can skip the phase rather
# than treat it as a review failure. those two messages, and only those two, carry
# the marker "run-external-review:" on stderr, so a 127 raised by the reviewer
# itself (a wrapper script whose inner tool is missing) stays distinguishable from
# this one. nothing else written here may carry the marker -- an informational note
# that did would make a reviewer's own 127 read as "no tool installed" and silently
# skip the phase

set -e

cmd="$1"
prompt="$2"

if [ -z "$prompt" ]; then
    echo "error: usage: run-external-review.sh '<external_review_cmd>' '<prompt>'" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# a newline would be swallowed by the single `read` below, running a truncated
# command instead of the configured one -- report it rather than truncate silently
case "$cmd" in
    *$'\n'*)
        echo "error: external_review_cmd must be a single line" >&2
        exit 1
        ;;
esac

# split on whitespace so a command carrying flags works, e.g.
# "mytool review --strict". arguments containing spaces are not supported --
# wrap anything that needs quoting in a script and point the config at it.
# an unset or whitespace-only config yields a zero-length array, which must take
# the codex fallback rather than exit 127 and silently skip the whole phase
read -ra cmd_args <<< "$cmd"

if [ "${#cmd_args[@]}" -eq 0 ]; then
    if ! command -v codex > /dev/null 2>&1; then
        echo "error: run-external-review: codex not on PATH and external_review_cmd is not set" >&2
        exit 127
    fi
    exec bash "$SCRIPT_DIR/run-codex.sh" "$prompt"
fi

if ! command -v "${cmd_args[0]}" > /dev/null 2>&1; then
    echo "error: run-external-review: external_review_cmd not on PATH: ${cmd_args[0]}" >&2
    exit 127
fi

# exec so a kill on the ongoing task reaches the reviewer rather than a
# wrapper shell, matching the codex branch above.
# stdin from /dev/null: an inherited open pipe (background launch) would let a
# tool that reads stdin block forever, the same failure run-codex.sh guards against
exec "${cmd_args[@]}" "$prompt" < /dev/null
