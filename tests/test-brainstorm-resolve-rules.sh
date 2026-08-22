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

# safety: verify dirs live under the directory mktemp actually uses before any rm.
# the base comes from mktemp itself, not $TMPDIR -- BSD mktemp on macOS ignores
# TMPDIR for the default template and always uses _CS_DARWIN_USER_TEMP_DIR
# (/var/folders/.../T), so comparing against $TMPDIR aborts the suite on every
# macOS host. both dirs below come from a bare `mktemp -d`, so they share this base
TMP_BASE="$(dirname "$(mktemp -u)")"
assert_temp_dir() {
    local dir="$1"
    case "$dir" in "$TMP_BASE"/?*) ;; *) echo "FATAL: $dir is not under $TMP_BASE, refusing to proceed" >&2; exit 1;; esac
}
assert_temp_dir "$WORK_DIR"
assert_temp_dir "$USER_DIR"

cleanup() { rm -rf "$WORK_DIR" "$USER_DIR"; }
trap cleanup EXIT

run_resolve() {
    # run from the temp work directory with data dir passed as argument (primary mechanism)
    (cd "$WORK_DIR" && bash "$RESOLVE_SCRIPT" "$TEST_FILENAME" "$USER_DIR")
}

run_resolve_env() {
    # run from the temp work directory with CLAUDE_PLUGIN_DATA as env var (fallback)
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
output="$( (cd "$WORK_DIR" && bash "$RESOLVE_SCRIPT") )"
assert_empty "no argument produces empty output" "$output"

# test 7: no data dir and no env var - only project path checked
echo ""
echo "test 7: no data dir argument and no env var"
mkdir -p "$WORK_DIR/.claude"
echo "project only" > "$WORK_DIR/.claude/$TEST_FILENAME"
output="$( (cd "$WORK_DIR" && unset CLAUDE_PLUGIN_DATA && bash "$RESOLVE_SCRIPT" "$TEST_FILENAME") )"
assert_output "works without data dir or env var" "project only" "$output"

rm -rf "$WORK_DIR/.claude"

# test 8: env var fallback when no argument provided
echo ""
echo "test 8: env var fallback (no data-dir argument)"
rm -rf "$WORK_DIR/.claude"
echo "user via env" > "$USER_DIR/$TEST_FILENAME"
output="$(run_resolve_env)"
assert_output "env var fallback works" "user via env" "$output"

rm -f "$USER_DIR/$TEST_FILENAME"

# test 9: argument takes precedence over env var
echo ""
echo "test 9: argument overrides env var"
ALT_DIR="$(mktemp -d)"
assert_temp_dir "$ALT_DIR"
echo "from argument" > "$ALT_DIR/$TEST_FILENAME"
echo "from env var" > "$USER_DIR/$TEST_FILENAME"
rm -rf "$WORK_DIR/.claude"
output="$( (cd "$WORK_DIR" && CLAUDE_PLUGIN_DATA="$USER_DIR" bash "$RESOLVE_SCRIPT" "$TEST_FILENAME" "$ALT_DIR") )"
assert_output "argument overrides env var" "from argument" "$output"

rm -rf "$ALT_DIR" "${USER_DIR:?}/$TEST_FILENAME"

# summary
echo ""
echo "======================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
