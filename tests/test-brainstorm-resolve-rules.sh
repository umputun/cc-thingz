#!/bin/bash
# automated tests for resolve-rules.sh
# exercises the two-layer resolution chain with various scenarios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RESOLVE_SCRIPT="$REPO_ROOT/plugins/brainstorm/scripts/resolve-rules.sh"
TEST_FILENAME="test-rules.md"

passed=0
failed=0

# setup temp working directory to avoid polluting the real working directory
WORK_DIR="$(mktemp -d)"
USER_DIR="$(mktemp -d)"

# safety: verify dirs are under /tmp or $TMPDIR before allowing any rm operations
assert_temp_dir() {
    local dir="$1"
    local tmpbase="${TMPDIR:-/tmp}"
    tmpbase="${tmpbase%/}"
    case "$dir" in "$tmpbase"/*) ;; *) echo "FATAL: $dir is not under $tmpbase, refusing to proceed" >&2; exit 1;; esac
}
assert_temp_dir "$WORK_DIR"
assert_temp_dir "$USER_DIR"

cleanup() { rm -rf "$WORK_DIR" "$USER_DIR"; }
trap cleanup EXIT

run_resolve() {
    # run from the temp work directory with CLAUDE_PLUGIN_DATA set to temp user dir
    (cd "$WORK_DIR" && CLAUDE_PLUGIN_DATA="$USER_DIR" bash "$RESOLVE_SCRIPT" "$TEST_FILENAME")
}

assert_output() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected: $(printf '%q' "$expected")"
        echo "    actual:   $(printf '%q' "$actual")"
        failed=$((failed + 1))
    fi
}

assert_empty() {
    local test_name="$1"
    local actual="$2"
    if [ -z "$actual" ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected empty output"
        echo "    actual: $(printf '%q' "$actual")"
        failed=$((failed + 1))
    fi
}

echo "testing resolve-rules.sh (brainstorm)"
echo "======================================"

# test 1: no files present - empty output
echo ""
echo "test 1: no files present"
rm -rf "$WORK_DIR/.claude"
rm -f "${USER_DIR:?}/$TEST_FILENAME"
output="$(run_resolve)"
assert_empty "no files produces empty output" "$output"

# test 2: only project file - outputs project content
echo ""
echo "test 2: only project file"
mkdir -p "$WORK_DIR/.claude"
echo "project rules content" > "$WORK_DIR/.claude/$TEST_FILENAME"
rm -f "$USER_DIR/$TEST_FILENAME"
output="$(run_resolve)"
assert_output "project file content returned" "project rules content" "$output"

# cleanup for next test
rm -rf "$WORK_DIR/.claude"

# test 3: only user file - outputs user content
echo ""
echo "test 3: only user file"
rm -rf "$WORK_DIR/.claude"
echo "user rules content" > "$USER_DIR/$TEST_FILENAME"
output="$(run_resolve)"
assert_output "user file content returned" "user rules content" "$output"

# cleanup for next test
rm -f "$USER_DIR/$TEST_FILENAME"

# test 4: both files - project wins (first-found-wins)
echo ""
echo "test 4: both files present (project wins)"
mkdir -p "$WORK_DIR/.claude"
echo "project rules content" > "$WORK_DIR/.claude/$TEST_FILENAME"
echo "user rules content" > "$USER_DIR/$TEST_FILENAME"
output="$(run_resolve)"
assert_output "project file takes precedence" "project rules content" "$output"

# cleanup for next test
rm -rf "$WORK_DIR/.claude"
rm -f "$USER_DIR/$TEST_FILENAME"

# test 5: empty file - empty output
echo ""
echo "test 5: empty project file"
mkdir -p "$WORK_DIR/.claude"
touch "$WORK_DIR/.claude/$TEST_FILENAME"
rm -f "$USER_DIR/$TEST_FILENAME"
output="$(run_resolve)"
assert_empty "empty file produces empty output" "$output"

# test 5b: empty project file, non-empty user file - user wins
echo ""
echo "test 5b: empty project file with user file present"
echo "user rules content" > "$USER_DIR/$TEST_FILENAME"
output="$(run_resolve)"
assert_output "user file returned when project file is empty" "user rules content" "$output"

# cleanup
rm -rf "$WORK_DIR/.claude"
rm -f "$USER_DIR/$TEST_FILENAME"

# test 6: no filename argument - empty output
echo ""
echo "test 6: no filename argument"
output="$( (cd "$WORK_DIR" && CLAUDE_PLUGIN_DATA="$USER_DIR" bash "$RESOLVE_SCRIPT") )"
assert_empty "no argument produces empty output" "$output"

# test 7: CLAUDE_PLUGIN_DATA unset - only project path checked
echo ""
echo "test 7: CLAUDE_PLUGIN_DATA unset"
mkdir -p "$WORK_DIR/.claude"
echo "project only" > "$WORK_DIR/.claude/$TEST_FILENAME"
output="$( (cd "$WORK_DIR" && unset CLAUDE_PLUGIN_DATA && bash "$RESOLVE_SCRIPT" "$TEST_FILENAME") )"
assert_output "works without CLAUDE_PLUGIN_DATA" "project only" "$output"

rm -rf "$WORK_DIR/.claude"

# summary
echo ""
echo "======================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
