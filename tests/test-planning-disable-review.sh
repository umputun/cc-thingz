#!/bin/bash
# tests for PLANNING_DISABLE_REVDIFF — skips interactive plan review on the
# ExitPlanMode hook route and the launch-plan-review.sh launcher route, so a
# remote client (claude /remote-control) is not blocked by a host-only overlay.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
HOOK="$REPO_ROOT/plugins/planning/scripts/plan-review-hook.py"
LAUNCHER="$REPO_ROOT/plugins/planning/scripts/launch-plan-review.sh"

passed=0
failed=0

assert_contains() {
    local test_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) echo "  PASS: $test_name"; passed=$((passed + 1)) ;;
        *) echo "  FAIL: $test_name"; echo "    expected to contain: $needle"; echo "    actual: $(printf '%q' "$haystack")"; failed=$((failed + 1)) ;;
    esac
}

assert_empty() {
    local test_name="$1" actual="$2"
    if [ -z "$actual" ]; then
        echo "  PASS: $test_name"; passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"; echo "    expected empty output"; echo "    actual: $(printf '%q' "$actual")"; failed=$((failed + 1))
    fi
}

assert_rc() {
    local test_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $test_name"; passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"; echo "    expected rc: $expected, actual: $actual"; failed=$((failed + 1))
    fi
}

echo "testing PLANNING_DISABLE_REVDIFF"
echo "================================"

# test 1: hook route returns an "ask" response with the disabled reason, without
# needing CLAUDE_PLUGIN_ROOT or any overlay terminal (guard fires before both)
echo ""
echo "test 1: hook route skips review when disabled"
event='{"tool_input":{"plan":"# Plan\n- task 1\n"}}'
out="$(printf '%s' "$event" | PLANNING_DISABLE_REVDIFF=1 python3 "$HOOK" 2>/dev/null)"
assert_contains "hook returns ask decision" '"permissionDecision": "ask"' "$out"
assert_contains "hook reports disabled reason" "PLANNING_DISABLE_REVDIFF" "$out"

# test 2: launcher route exits 0 with empty output (no overlay opened) when disabled
echo ""
echo "test 2: launcher skips overlay when disabled"
PLAN_FILE="$(mktemp "${TMPDIR:-/tmp}/plan-review-test-XXXXXX")"
printf '# Plan\n- task 1\n' > "$PLAN_FILE"
lout="$(PLANNING_DISABLE_REVDIFF=1 bash "$LAUNCHER" "$PLAN_FILE" 2>/dev/null)"
lrc=$?
rm -f "$PLAN_FILE"
assert_rc "launcher exits 0" 0 "$lrc"
assert_empty "launcher produces no annotations" "$lout"

# summary
echo ""
echo "================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
