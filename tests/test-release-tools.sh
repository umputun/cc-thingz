#!/bin/bash
# automated tests for the release-tools helper scripts
# covers calc-version.sh (version bump from the last tag), detect-platform.sh
# (platform from the origin remote) and get-notes.sh (notes built from commits)
# scaffolds temp git repos and stubs the forge CLIs so the results depend on
# neither the network nor what is installed on the machine

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_SCRIPTS_DIR="$REPO_ROOT/plugins/release-tools/skills/new/scripts"
CALC_VERSION="$RELEASE_SCRIPTS_DIR/calc-version.sh"
DETECT_PLATFORM="$RELEASE_SCRIPTS_DIR/detect-platform.sh"
GET_NOTES="$RELEASE_SCRIPTS_DIR/get-notes.sh"

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

# every scratch dir lives under one root: mk_tmp runs inside command
# substitutions, so a dir recorded in an array there would not survive the
# subshell and cleanup would miss it
TMP_ROOT="$(mktemp -d)"
assert_temp_dir "$TMP_ROOT"

mk_tmp() {
    mktemp -d "$TMP_ROOT/scratch-XXXXXX"
}

cleanup() {
    rm -rf "$TMP_ROOT"
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

assert_exit_nonzero() {
    local test_name="$1"
    local actual_rc="$2"
    if [ "$actual_rc" -ne 0 ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected non-zero exit, got 0"
        failed=$((failed + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected to contain: $(printf '%q' "$needle")"
        echo "    actual:              $(printf '%q' "$haystack")"
        failed=$((failed + 1))
    fi
}

assert_not_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected NOT to contain: $(printf '%q' "$needle")"
        echo "    actual:                  $(printf '%q' "$haystack")"
        failed=$((failed + 1))
    fi
}

# run a command inside a directory, capturing stdout and stderr separately.
# sets cap_out, cap_err and cap_rc. the scripts print values on stdout and
# diagnostics on stderr, so the two streams have to be asserted apart.
run_capture() {
    local dir="$1"
    shift
    local err_file
    err_file="$(mktemp "$TMP_ROOT/stderr-XXXXXX")"
    cap_rc=0
    cap_out="$(cd "$dir" && "$@" 2>"$err_file")" || cap_rc=$?
    cap_err="$(cat "$err_file")"
    rm -f "$err_file"
}

# repo-local identity and signing settings keep commits and tags independent of
# the machine's global git config
make_git_repo() {
    local dir="$1"
    git -C "$dir" init -q -b master
    git -C "$dir" config user.email "test@example.invalid"
    git -C "$dir" config user.name "test"
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" config tag.gpgSign false
    git -C "$dir" commit --allow-empty -q -m "initial"
}

# commit with the given subject, in the current directory
commit_msg() {
    local msg="$1"
    echo "$msg" >>log.txt
    git add log.txt
    git commit -q -m "$msg"
}

# stub the forge CLIs: get-notes.sh reads merged PRs/MRs through them and
# detect-platform.sh falls back to `glab repo view` for unrecognised remotes.
# stubs that always fail keep both deterministic on any machine.
STUB_DIR="$(mk_tmp)"
for tool in gh glab tea; do
    printf '#!/bin/sh\nexit 1\n' >"$STUB_DIR/$tool"
    chmod +x "$STUB_DIR/$tool"
done
STUB_PATH="$STUB_DIR:$PATH"

echo "testing calc-version.sh"
echo "======================="

# test 1: repo without tags -> first-release defaults
echo ""
echo "test 1: no tags -> first-release defaults"
CV_NO_TAG="$(mk_tmp)"
make_git_repo "$CV_NO_TAG"
output="$(cd "$CV_NO_TAG" && bash "$CALC_VERSION" major)"
assert_output "calc-version/no-tag: major -> v1.0.0" "v1.0.0" "$output"
output="$(cd "$CV_NO_TAG" && bash "$CALC_VERSION" minor)"
assert_output "calc-version/no-tag: minor -> v0.1.0" "v0.1.0" "$output"
output="$(cd "$CV_NO_TAG" && bash "$CALC_VERSION" hotfix)"
assert_output "calc-version/no-tag: hotfix -> v0.0.1" "v0.0.1" "$output"

# test 2: repo with v1.2.3 -> bumps the right component
echo ""
echo "test 2: existing tag -> component bump"
CV_TAGGED="$(mk_tmp)"
make_git_repo "$CV_TAGGED"
git -C "$CV_TAGGED" tag v1.2.3
output="$(cd "$CV_TAGGED" && bash "$CALC_VERSION" major)"
assert_output "calc-version/tagged: major -> v2.0.0" "v2.0.0" "$output"
output="$(cd "$CV_TAGGED" && bash "$CALC_VERSION" minor)"
assert_output "calc-version/tagged: minor -> v1.3.0" "v1.3.0" "$output"
output="$(cd "$CV_TAGGED" && bash "$CALC_VERSION" hotfix)"
assert_output "calc-version/tagged: hotfix -> v1.2.4" "v1.2.4" "$output"

# test 3: pre-release suffix is stripped before the bump
echo ""
echo "test 3: pre-release tag -> suffix stripped"
CV_PRERELEASE="$(mk_tmp)"
make_git_repo "$CV_PRERELEASE"
git -C "$CV_PRERELEASE" tag v2.5.9-rc1
output="$(cd "$CV_PRERELEASE" && bash "$CALC_VERSION" hotfix)"
assert_output "calc-version/pre-release: hotfix -> v2.5.10" "v2.5.10" "$output"
output="$(cd "$CV_PRERELEASE" && bash "$CALC_VERSION" minor)"
assert_output "calc-version/pre-release: minor -> v2.6.0" "v2.6.0" "$output"

# test 4: unparsable tag -> error, no version printed
echo ""
echo "test 4: unparsable tag -> error"
CV_BAD_TAG="$(mk_tmp)"
make_git_repo "$CV_BAD_TAG"
git -C "$CV_BAD_TAG" tag vfoo.bar.baz
run_capture "$CV_BAD_TAG" bash "$CALC_VERSION" minor
assert_exit_nonzero "calc-version/bad-tag: exits non-zero" "$cap_rc"
assert_output "calc-version/bad-tag: no version on stdout" "" "$cap_out"
assert_contains "calc-version/bad-tag: names the tag on stderr" "$cap_err" "cannot parse version from vfoo.bar.baz"

# test 5: bad arguments -> error
echo ""
echo "test 5: bad arguments -> error"
run_capture "$CV_TAGGED" bash "$CALC_VERSION"
assert_exit_nonzero "calc-version/no-arg: exits non-zero" "$cap_rc"
assert_output "calc-version/no-arg: no version on stdout" "" "$cap_out"
assert_contains "calc-version/no-arg: explains the usage on stderr" "$cap_err" "release type required"
run_capture "$CV_TAGGED" bash "$CALC_VERSION" patch
assert_exit_nonzero "calc-version/invalid-type: exits non-zero with a tag present" "$cap_rc"
assert_output "calc-version/invalid-type: no version on stdout" "" "$cap_out"
assert_contains "calc-version/invalid-type: names the type on stderr" "$cap_err" "invalid type: patch"
run_capture "$CV_NO_TAG" bash "$CALC_VERSION" patch
assert_exit_nonzero "calc-version/invalid-type: exits non-zero without tags" "$cap_rc"
assert_contains "calc-version/invalid-type: names the type on stderr without tags" "$cap_err" "invalid type: patch"

echo ""
echo "testing detect-platform.sh"
echo "=========================="

# creates a fresh repo whose origin is the given URL and echoes its path
make_repo_with_origin() {
    local url="$1"
    local dir
    dir="$(mk_tmp)"
    make_git_repo "$dir"
    git -C "$dir" remote add origin "$url"
    echo "$dir"
}

# runs detect-platform.sh in such a repo and echoes what it puts on stdout
run_detect_platform() {
    local dir
    dir="$(make_repo_with_origin "$1")"
    (cd "$dir" && PATH="$STUB_PATH" bash "$DETECT_PLATFORM")
}

# test 6: remote URL -> platform
echo ""
echo "test 6: remote URL -> platform"
output="$(run_detect_platform "git@github.com:umputun/cc-thingz.git")"
assert_output "detect-platform: github ssh remote" "github" "$output"
output="$(run_detect_platform "https://github.com/umputun/cc-thingz.git")"
assert_output "detect-platform: github https remote" "github" "$output"
output="$(run_detect_platform "git@gitlab.com:group/project.git")"
assert_output "detect-platform: gitlab remote" "gitlab" "$output"
output="$(run_detect_platform "https://gitea.example.invalid/group/project.git")"
assert_output "detect-platform: gitea remote" "gitea" "$output"

# test 7: unrecognised remote -> error (glab stub fails the fallback probe)
echo ""
echo "test 7: unrecognised remote -> error"
DP_UNKNOWN="$(make_repo_with_origin "https://git.example.invalid/group/project.git")"
run_capture "$DP_UNKNOWN" env PATH="$STUB_PATH" bash "$DETECT_PLATFORM"
assert_exit_nonzero "detect-platform/unknown: exits non-zero" "$cap_rc"
assert_output "detect-platform/unknown: no platform on stdout" "" "$cap_out"
assert_contains "detect-platform/unknown: names the remote on stderr" "$cap_err" "unknown platform for https://git.example.invalid/group/project.git"

# test 8: no origin remote -> diagnostic on stderr, nothing on stdout
echo ""
echo "test 8: no origin remote -> error"
DP_NO_REMOTE="$(mk_tmp)"
make_git_repo "$DP_NO_REMOTE"
run_capture "$DP_NO_REMOTE" env PATH="$STUB_PATH" bash "$DETECT_PLATFORM"
assert_exit_nonzero "detect-platform/no-remote: exits non-zero" "$cap_rc"
assert_output "detect-platform/no-remote: no platform on stdout" "" "$cap_out"
assert_contains "detect-platform/no-remote: reports the missing origin on stderr" "$cap_err" "error: no origin remote configured"

# test 8b: outside a repository -> reported separately from a missing origin.
# GIT_CEILING_DIRECTORIES stops git's upward search at the scratch root, so the
# result does not depend on where $TMPDIR happens to live
echo ""
echo "test 8b: outside a git repository -> error"
DP_NO_REPO="$(mk_tmp)"
run_capture "$DP_NO_REPO" env PATH="$STUB_PATH" GIT_CEILING_DIRECTORIES="$TMP_ROOT" bash "$DETECT_PLATFORM"
assert_exit_nonzero "detect-platform/no-repo: exits non-zero" "$cap_rc"
assert_output "detect-platform/no-repo: no platform on stdout" "" "$cap_out"
assert_contains "detect-platform/no-repo: says it is not a repository" "$cap_err" "error: not a git repository"

echo ""
echo "testing get-notes.sh"
echo "===================="

# test 9: untagged repo -> commits grouped by conventional prefix
echo ""
echo "test 9: untagged repo -> commits grouped by prefix"
GN_NO_TAG="$(mk_tmp)"
make_git_repo "$GN_NO_TAG"
(
    cd "$GN_NO_TAG"
    commit_msg "feat: add plan annotations"
    commit_msg "fix(exec): stop dropping the exit code"
    commit_msg "chore: tidy up scripts"
    commit_msg "unprefixed subject line"
)
output="$(cd "$GN_NO_TAG" && PATH="$STUB_PATH" bash "$GET_NOTES" github)"
assert_contains "get-notes/no-tag: features section" "$output" "**New Features**"
assert_contains "get-notes/no-tag: feat entry loses its prefix" "$output" "- add plan annotations"
assert_contains "get-notes/no-tag: fixes section" "$output" "**Bug Fixes**"
assert_contains "get-notes/no-tag: fix entry loses prefix and scope" "$output" "- stop dropping the exit code"
assert_contains "get-notes/no-tag: improvements section" "$output" "**Improvements**"
assert_contains "get-notes/no-tag: chore entry loses its prefix" "$output" "- tidy up scripts"
assert_contains "get-notes/no-tag: other section" "$output" "**Other**"
assert_contains "get-notes/no-tag: unprefixed entry kept verbatim" "$output" "- unprefixed subject line"

# test 10: tagged repo -> only commits after the last tag
echo ""
echo "test 10: tagged repo -> only commits after the last tag"
GN_TAGGED="$(mk_tmp)"
make_git_repo "$GN_TAGGED"
(
    cd "$GN_TAGGED"
    commit_msg "feat: shipped in the last release"
    git tag v1.0.0
    commit_msg "fix: landed after the tag"
)
output="$(cd "$GN_TAGGED" && PATH="$STUB_PATH" bash "$GET_NOTES" github)"
assert_contains "get-notes/tagged: post-tag commit included" "$output" "- landed after the tag"
assert_not_contains "get-notes/tagged: pre-tag commit excluded" "$output" "shipped in the last release"

# tests 11 and 12 need a real jq: get-notes.sh shapes the forge JSON with it,
# and stubbing jq as well would leave nothing under test
JQ_AVAILABLE=0
if command -v jq >/dev/null 2>&1; then
    JQ_AVAILABLE=1
else
    echo ""
    echo "SKIP: jq not installed, skipping PR collection tests"
fi

if [ "$JQ_AVAILABLE" -eq 1 ]; then
    # gh stub returning two merged PRs: one merged far in the future (after any
    # tag this suite creates) and one merged in 1970 (before it)
    STUB_PR_DIR="$(mk_tmp)"
    cat >"$STUB_PR_DIR/gh" <<'STUB'
#!/bin/sh
cat <<'JSON'
[
  {"number":45,"title":"feat: add user authentication","mergedAt":"2999-01-01T00:00:00Z","author":{"login":"someone"}},
  {"number":12,"title":"fix: correct the login timeout","mergedAt":"1970-01-01T00:00:00Z","author":{"login":"other"}}
]
JSON
STUB
    chmod +x "$STUB_PR_DIR/gh"
    STUB_PR_PATH="$STUB_PR_DIR:$PATH"

    # test 11: untagged repo -> every merged PR is listed with number and author
    echo ""
    echo "test 11: untagged repo -> merged PRs listed with number and author"
    output="$(cd "$GN_NO_TAG" && PATH="$STUB_PR_PATH" bash "$GET_NOTES" github)"
    assert_contains "get-notes/prs: feat PR entry" "$output" "- add user authentication #45 @someone"
    assert_contains "get-notes/prs: fix PR entry" "$output" "- correct the login timeout #12 @other"

    # test 12: tagged repo -> PRs merged before the tag are dropped
    echo ""
    echo "test 12: tagged repo -> PRs merged before the tag are dropped"
    output="$(cd "$GN_TAGGED" && PATH="$STUB_PR_PATH" bash "$GET_NOTES" github)"
    assert_contains "get-notes/prs-tagged: post-tag PR included" "$output" "- add user authentication #45 @someone"
    assert_not_contains "get-notes/prs-tagged: pre-tag PR excluded" "$output" "#12 @other"
fi

# test 13: missing platform argument -> error
echo ""
echo "test 13: missing platform argument -> error"
run_capture "$GN_NO_TAG" env PATH="$STUB_PATH" bash "$GET_NOTES"
assert_exit_nonzero "get-notes/no-arg: exits non-zero" "$cap_rc"
assert_output "get-notes/no-arg: no notes on stdout" "" "$cap_out"
assert_contains "get-notes/no-arg: explains the usage on stderr" "$cap_err" "platform required"

# summary
echo ""
echo "======================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
