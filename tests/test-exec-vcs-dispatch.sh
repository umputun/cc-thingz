#!/bin/bash
# automated tests for VCS dispatch in exec scripts
# covers detect-branch.sh (and additional scripts added in later tasks)
# scaffolds temp git and hg repos and asserts expected outputs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
EXEC_SCRIPTS_DIR="$REPO_ROOT/plugins/planning/skills/exec/scripts"
DETECT_BRANCH="$EXEC_SCRIPTS_DIR/detect-branch.sh"

passed=0
failed=0

# safety: verify dirs are under a recognised temp base before allowing any rm operations
assert_temp_dir() {
    local dir="$1"
    local tmpbase="${TMPDIR:-/tmp}"
    tmpbase="${tmpbase%/}"
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

# track all temp dirs created so cleanup hits every one
TMP_DIRS=()
mk_tmp() {
    local d
    d="$(mktemp -d)"
    assert_temp_dir "$d"
    TMP_DIRS+=("$d")
    echo "$d"
}

cleanup() {
    local d
    for d in "${TMP_DIRS[@]:-}"; do
        if [ -n "$d" ] && [ -d "$d" ]; then
            rm -rf "$d"
        fi
    done
    return 0
}
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

HG_AVAILABLE=1
if ! command -v hg >/dev/null 2>&1; then
    HG_AVAILABLE=0
    echo "note: hg not available, skipping hg-specific cases"
fi

# make git operations hermetic — no user hooks / signing / global config interference
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="Test"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test"
export GIT_COMMITTER_EMAIL="test@example.com"

# hg hermeticity — isolate from user config
export HGRCPATH=/dev/null
export HGUSER="Test <test@example.com>"

# helper: init a git repo on a given branch name, seed refs/remotes/origin/HEAD
# so detect-branch.sh always takes the cached-remote path
make_git_repo() {
    local dir="$1"
    local default_branch="$2"
    git -C "$dir" init -q -b "$default_branch"
    git -C "$dir" commit --allow-empty -q -m "initial"
    git -C "$dir" remote add origin "https://example.invalid/x.git"
    git -C "$dir" symbolic-ref "refs/remotes/origin/HEAD" "refs/remotes/origin/$default_branch"
}

make_hg_repo() {
    local dir="$1"
    hg init "$dir" >/dev/null
}

echo "testing VCS dispatch: detect-branch.sh"
echo "======================================"

# test 1: git repo on main -> outputs main
echo ""
echo "test 1: git repo with main as default"
GIT_MAIN="$(mk_tmp)"
make_git_repo "$GIT_MAIN" main
output="$(cd "$GIT_MAIN" && bash "$DETECT_BRANCH")"
assert_output "git repo on main outputs 'main'" "main" "$output"

# test 2: git repo on master -> outputs master
echo ""
echo "test 2: git repo with master as default"
GIT_MASTER="$(mk_tmp)"
make_git_repo "$GIT_MASTER" master
output="$(cd "$GIT_MASTER" && bash "$DETECT_BRANCH")"
assert_output "git repo on master outputs 'master'" "master" "$output"

# test 3: hg repo -> outputs default
if [ "$HG_AVAILABLE" -eq 1 ]; then
    echo ""
    echo "test 3: hg repo outputs 'default'"
    HG_REPO="$(mk_tmp)"
    make_hg_repo "$HG_REPO"
    output="$(cd "$HG_REPO" && bash "$DETECT_BRANCH")"
    assert_output "hg repo outputs 'default'" "default" "$output"

    # test 3b: hg repo with a named branch still outputs 'default' (detect-branch.sh reports
    # the repo's DEFAULT branch name, not the current one — mirrors git's semantic)
    echo ""
    echo "test 3b: hg repo on a named branch still outputs 'default'"
    HG_NAMED="$(mk_tmp)"
    make_hg_repo "$HG_NAMED"
    (cd "$HG_NAMED" && hg branch my-feature >/dev/null)
    output="$(cd "$HG_NAMED" && bash "$DETECT_BRANCH")"
    assert_output "hg repo on named branch outputs 'default'" "default" "$output"
fi

# summary
echo ""
echo "======================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
