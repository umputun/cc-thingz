#!/bin/bash
# automated tests for detect-vcs.sh
# covers git, hg, colocated git+hg (git wins), nested subdir resolution, and non-VCS failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DETECT_SCRIPT="$REPO_ROOT/plugins/planning/skills/exec/scripts/detect-vcs.sh"

passed=0
failed=0

# safety: verify dirs are under /tmp or $TMPDIR before allowing any rm operations
assert_temp_dir() {
    local dir="$1"
    local tmpbase="${TMPDIR:-/tmp}"
    tmpbase="${tmpbase%/}"
    # also allow macOS-style /private/var/... that $TMPDIR may resolve to
    case "$dir" in
    "$tmpbase"/*) ;;
    /tmp/*) ;;
    /private/tmp/*) ;;
    /private/var/*) ;;
    /var/folders/*) ;;
    *)
        echo "FATAL: $dir is not under a recognised temp base, refusing to proceed" >&2
        exit 1
        ;;
    esac
}

GIT_DIR="$(mktemp -d)"
HG_DIR="$(mktemp -d)"
COLOCATED_DIR="$(mktemp -d)"
EMPTY_DIR="$(mktemp -d)"
assert_temp_dir "$GIT_DIR"
assert_temp_dir "$HG_DIR"
assert_temp_dir "$COLOCATED_DIR"
assert_temp_dir "$EMPTY_DIR"

cleanup() { rm -rf "$GIT_DIR" "$HG_DIR" "$COLOCATED_DIR" "$EMPTY_DIR"; }
trap cleanup EXIT

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

assert_exit_nonzero() {
    local test_name="$1"
    local actual_rc="$2"
    if [ "$actual_rc" -ne 0 ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name (expected non-zero exit, got 0)"
        failed=$((failed + 1))
    fi
}

echo "testing detect-vcs.sh"
echo "========================"

# skip hg tests if hg is not installed
HG_AVAILABLE=1
if ! command -v hg >/dev/null 2>&1; then
    HG_AVAILABLE=0
    echo "note: hg not available, skipping hg-specific cases"
fi

# scaffold git repo
git -C "$GIT_DIR" init -q
mkdir -p "$GIT_DIR/sub/deep"

# scaffold hg repo (if available)
if [ "$HG_AVAILABLE" -eq 1 ]; then
    hg init "$HG_DIR" >/dev/null
    mkdir -p "$HG_DIR/sub/deep"
fi

# scaffold colocated git+hg repo (if hg available)
if [ "$HG_AVAILABLE" -eq 1 ]; then
    git -C "$COLOCATED_DIR" init -q
    hg init "$COLOCATED_DIR" >/dev/null
fi

# test 1: pure git repo -> "git"
echo ""
echo "test 1: pure git repo"
output="$(cd "$GIT_DIR" && bash "$DETECT_SCRIPT")"
assert_output "pure git root outputs 'git'" "git" "$output"

# test 1b: ensure exact 'git\n' output (4 bytes: g, i, t, newline)
echo ""
echo "test 1b: exact 'git' newline-terminated output (no trailing whitespace)"
raw_bytes="$(cd "$GIT_DIR" && bash "$DETECT_SCRIPT" | wc -c | tr -d ' ')"
raw_content="$(cd "$GIT_DIR" && bash "$DETECT_SCRIPT")"
if [ "$raw_bytes" = "4" ] && [ "$raw_content" = "git" ]; then
    echo "  PASS: git output is exactly 'git' plus newline (4 bytes)"
    passed=$((passed + 1))
else
    echo "  FAIL: git output bytes=$raw_bytes content=$(printf '%q' "$raw_content")"
    failed=$((failed + 1))
fi

# test 2: nested subdir of git repo -> "git"
echo ""
echo "test 2: nested subdir of git repo"
output="$(cd "$GIT_DIR/sub/deep" && bash "$DETECT_SCRIPT")"
assert_output "nested subdir resolves to 'git'" "git" "$output"

# test 3: pure hg repo -> "hg" (skipped if hg not available)
if [ "$HG_AVAILABLE" -eq 1 ]; then
    echo ""
    echo "test 3: pure hg repo"
    output="$(cd "$HG_DIR" && bash "$DETECT_SCRIPT")"
    assert_output "pure hg root outputs 'hg'" "hg" "$output"

    echo ""
    echo "test 3b: exact 'hg' newline-terminated output (no trailing whitespace)"
    raw_bytes="$(cd "$HG_DIR" && bash "$DETECT_SCRIPT" | wc -c | tr -d ' ')"
    raw_content="$(cd "$HG_DIR" && bash "$DETECT_SCRIPT")"
    if [ "$raw_bytes" = "3" ] && [ "$raw_content" = "hg" ]; then
        echo "  PASS: hg output is exactly 'hg' plus newline (3 bytes)"
        passed=$((passed + 1))
    else
        echo "  FAIL: hg output bytes=$raw_bytes content=$(printf '%q' "$raw_content")"
        failed=$((failed + 1))
    fi

    # test 4: nested subdir of hg repo -> "hg"
    echo ""
    echo "test 4: nested subdir of hg repo"
    output="$(cd "$HG_DIR/sub/deep" && bash "$DETECT_SCRIPT")"
    assert_output "nested hg subdir resolves to 'hg'" "hg" "$output"

    # test 5: colocated .git + .hg -> "git" (precedence)
    echo ""
    echo "test 5: colocated git+hg root (git wins)"
    output="$(cd "$COLOCATED_DIR" && bash "$DETECT_SCRIPT")"
    assert_output "colocated repo resolves to 'git'" "git" "$output"
fi

# test 6: empty dir -> exit 1
echo ""
echo "test 6: empty non-VCS dir exits non-zero"
set +e
(cd "$EMPTY_DIR" && bash "$DETECT_SCRIPT" >/dev/null 2>&1)
rc=$?
set -e
assert_exit_nonzero "non-VCS dir exits non-zero" "$rc"

# summary
echo ""
echo "========================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
