#!/bin/bash
# automated tests for VCS dispatch in all four exec scripts
# covers detect-branch.sh, create-branch.sh, stage-and-commit.sh, run-codex.sh
# (git + hg paths) plus non-VCS exit-code propagation via set -e
# scaffolds temp git and hg repos and asserts expected outputs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
EXEC_SCRIPTS_DIR="$REPO_ROOT/plugins/planning/skills/exec/scripts"
DETECT_BRANCH="$EXEC_SCRIPTS_DIR/detect-branch.sh"
CREATE_BRANCH="$EXEC_SCRIPTS_DIR/create-branch.sh"
STAGE_AND_COMMIT="$EXEC_SCRIPTS_DIR/stage-and-commit.sh"
RUN_CODEX="$EXEC_SCRIPTS_DIR/run-codex.sh"

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

# assertion helper: checks a string contains a substring
assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    case "$haystack" in
    *"$needle"*)
        echo "  PASS: $test_name"
        passed=$((passed + 1))
        ;;
    *)
        echo "  FAIL: $test_name"
        echo "    expected substring: $(printf '%q' "$needle")"
        echo "    in:                 $(printf '%q' "$haystack")"
        failed=$((failed + 1))
        ;;
    esac
}

# assertion helper: checks a string does NOT contain a substring
assert_not_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    case "$haystack" in
    *"$needle"*)
        echo "  FAIL: $test_name"
        echo "    unexpected substring: $(printf '%q' "$needle")"
        echo "    in:                   $(printf '%q' "$haystack")"
        failed=$((failed + 1))
        ;;
    *)
        echo "  PASS: $test_name"
        passed=$((passed + 1))
        ;;
    esac
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

# test 3: vanilla hg repo with no remote refs -> outputs 'default' fallback
if [ "$HG_AVAILABLE" -eq 1 ]; then
    echo ""
    echo "test 3: hg repo with no remote/<name> refs falls back to 'default'"
    HG_REPO="$(mk_tmp)"
    make_hg_repo "$HG_REPO"
    output="$(cd "$HG_REPO" && bash "$DETECT_BRANCH")"
    assert_output "hg repo without remote refs outputs 'default'" "default" "$output"

    # test 3b: hg repo that exposes remote/master as a revset -> outputs 'remote/master'.
    # vanilla hg does not ship a remote-tracking-ref layout out of the box, so we
    # simulate one via a [revsetalias] entry that resolves remote/master to an
    # existing bookmark. the patched do_hg probes `present(remote/<name>)`, which
    # accepts any revset that resolves, so the alias is a faithful stand-in for
    # modern-Mercurial environments that expose remote-tracking refs natively.
    echo ""
    echo "test 3b: hg repo with remote/master as a revset outputs 'remote/master'"
    HG_REMOTE_MASTER="$(mk_tmp)"
    make_hg_repo "$HG_REMOTE_MASTER"
    (
        cd "$HG_REMOTE_MASTER"
        cat >>.hg/hgrc <<'HGRC'
[revsetalias]
remote/master = bookmark("master")
HGRC
        echo seed >seed.txt
        hg add seed.txt >/dev/null
        hg commit -m seed >/dev/null
        hg book master >/dev/null
    )
    output="$(cd "$HG_REMOTE_MASTER" && bash "$DETECT_BRANCH")"
    assert_output "hg repo with remote/master outputs 'remote/master'" "remote/master" "$output"

    # test 3c: hg repo with remote/main but not remote/master -> outputs 'remote/main'
    # exercises the candidate-order fallthrough when the first candidate is absent.
    echo ""
    echo "test 3c: hg repo with only remote/main outputs 'remote/main'"
    HG_REMOTE_MAIN="$(mk_tmp)"
    make_hg_repo "$HG_REMOTE_MAIN"
    (
        cd "$HG_REMOTE_MAIN"
        cat >>.hg/hgrc <<'HGRC'
[revsetalias]
remote/main = bookmark("main")
HGRC
        echo seed >seed.txt
        hg add seed.txt >/dev/null
        hg commit -m seed >/dev/null
        hg book main >/dev/null
    )
    output="$(cd "$HG_REMOTE_MAIN" && bash "$DETECT_BRANCH")"
    assert_output "hg repo with only remote/main outputs 'remote/main'" "remote/main" "$output"
fi

echo ""
echo "testing VCS dispatch: create-branch.sh"
echo "======================================"

PLAN_FILE_DATED="docs/plans/20260329-feature-name.md"
EXPECTED_DERIVED_BRANCH="feature-name"

# test 4: git repo on main with dated plan -> creates and outputs derived branch name
echo ""
echo "test 4: git repo on main, plan with date prefix -> creates feature branch"
GIT_CB_MAIN="$(mk_tmp)"
make_git_repo "$GIT_CB_MAIN" main
output="$(cd "$GIT_CB_MAIN" && bash "$CREATE_BRANCH" "$PLAN_FILE_DATED" 2>/dev/null | tail -n 1)"
assert_output "git/main: outputs derived branch name" "$EXPECTED_DERIVED_BRANCH" "$output"
current="$(git -C "$GIT_CB_MAIN" branch --show-current)"
assert_output "git/main: actually switched to new branch" "$EXPECTED_DERIVED_BRANCH" "$current"

# test 5: git repo already on feature branch -> outputs current branch, no switch
echo ""
echo "test 5: git repo already on feature branch -> outputs current, no switch"
GIT_CB_FEAT="$(mk_tmp)"
make_git_repo "$GIT_CB_FEAT" main
git -C "$GIT_CB_FEAT" checkout -q -b existing-feature
output="$(cd "$GIT_CB_FEAT" && bash "$CREATE_BRANCH" "$PLAN_FILE_DATED" 2>/dev/null | tail -n 1)"
assert_output "git/existing-feature: outputs current branch" "existing-feature" "$output"
current="$(git -C "$GIT_CB_FEAT" branch --show-current)"
assert_output "git/existing-feature: still on existing-feature" "existing-feature" "$current"

if [ "$HG_AVAILABLE" -eq 1 ]; then
    # test 6: hg repo with no active bookmark -> creates bookmark, outputs derived name
    echo ""
    echo "test 6: hg repo no active bookmark -> creates bookmark, outputs derived name"
    HG_CB_DEFAULT="$(mk_tmp)"
    make_hg_repo "$HG_CB_DEFAULT"
    # seed one commit so there's a parent to attach the bookmark to
    (
        cd "$HG_CB_DEFAULT"
        echo "seed" >seed.txt
        hg add seed.txt >/dev/null
        hg commit -m "seed" >/dev/null
    )
    output="$(cd "$HG_CB_DEFAULT" && bash "$CREATE_BRANCH" "$PLAN_FILE_DATED" 2>/dev/null | tail -n 1)"
    assert_output "hg/no-active: outputs derived branch name" "$EXPECTED_DERIVED_BRANCH" "$output"
    # verify the bookmark was created and is now active
    book_list="$(cd "$HG_CB_DEFAULT" && hg book --template '{bookmark}\n')"
    assert_contains "hg/no-active: bookmark created with derived name" "$book_list" "$EXPECTED_DERIVED_BRANCH"
    active="$(cd "$HG_CB_DEFAULT" && hg log -r . --template '{activebookmark}\n')"
    assert_output "hg/no-active: new bookmark is active" "$EXPECTED_DERIVED_BRANCH" "$active"

    # test 7: hg repo already on a non-default bookmark -> outputs current, does NOT create derived bookmark
    echo ""
    echo "test 7: hg repo already on my-branch -> outputs current, does not create derived"
    HG_CB_ON_BRANCH="$(mk_tmp)"
    make_hg_repo "$HG_CB_ON_BRANCH"
    (
        cd "$HG_CB_ON_BRANCH"
        echo "seed" >seed.txt
        hg add seed.txt >/dev/null
        hg commit -m "seed" >/dev/null
        hg book my-branch >/dev/null
    )
    output="$(cd "$HG_CB_ON_BRANCH" && bash "$CREATE_BRANCH" "$PLAN_FILE_DATED" 2>/dev/null | tail -n 1)"
    assert_output "hg/my-branch: outputs current bookmark" "my-branch" "$output"
    active="$(cd "$HG_CB_ON_BRANCH" && hg log -r . --template '{activebookmark}\n')"
    assert_output "hg/my-branch: still on my-branch" "my-branch" "$active"
    # derived bookmark must NOT have been created
    book_list="$(cd "$HG_CB_ON_BRANCH" && hg book --template '{bookmark}\n')"
    assert_not_contains "hg/my-branch: derived bookmark not created" "$book_list" "$EXPECTED_DERIVED_BRANCH"

    # test 8: hg repo with existing inactive bookmark (partial-run recovery)
    # -- must 'hg update' it, not 'hg book' again (bookmark already exists)
    echo ""
    echo "test 8: hg repo with inactive derived bookmark -> hg update activates it"
    HG_CB_REENTER="$(mk_tmp)"
    make_hg_repo "$HG_CB_REENTER"
    (
        cd "$HG_CB_REENTER"
        echo "seed" >seed.txt
        hg add seed.txt >/dev/null
        hg commit -m "seed" >/dev/null
        # create the derived-name bookmark, then deactivate it to simulate
        # a prior partial run leaving the bookmark but no active selection
        hg book "$EXPECTED_DERIVED_BRANCH" >/dev/null
        hg book -i >/dev/null
    )
    # record whereami before re-run so we can assert the working copy did not move
    before_rev="$(cd "$HG_CB_REENTER" && hg log -r . --template '{node}\n')"
    output="$(cd "$HG_CB_REENTER" && bash "$CREATE_BRANCH" "$PLAN_FILE_DATED" 2>&1 | tail -n 1)"
    assert_output "hg/reenter: outputs derived branch name" "$EXPECTED_DERIVED_BRANCH" "$output"
    active="$(cd "$HG_CB_REENTER" && hg log -r . --template '{activebookmark}\n')"
    assert_output "hg/reenter: derived bookmark is now active (via hg update)" "$EXPECTED_DERIVED_BRANCH" "$active"
    after_rev="$(cd "$HG_CB_REENTER" && hg log -r . --template '{node}\n')"
    assert_output "hg/reenter: working copy did not move" "$before_rev" "$after_rev"

    # test 9: hg repo with no commits yet -> hg book attaches to null parent, works fine
    echo ""
    echo "test 9: hg repo no-commit state -> bookmark created on null parent"
    HG_CB_FRESH="$(mk_tmp)"
    make_hg_repo "$HG_CB_FRESH"
    output="$(cd "$HG_CB_FRESH" && bash "$CREATE_BRANCH" "$PLAN_FILE_DATED" 2>/dev/null | tail -n 1)"
    assert_output "hg/fresh: outputs derived branch name" "$EXPECTED_DERIVED_BRANCH" "$output"
    active="$(cd "$HG_CB_FRESH" && hg log -r . --template '{activebookmark}\n')"
    assert_output "hg/fresh: derived bookmark is active" "$EXPECTED_DERIVED_BRANCH" "$active"

    # test 9b: active bookmark IS the default (e.g. master/main) -> must NOT early-return;
    # still create the derived bookmark. regression for the "any active bookmark counts as
    # feature branch" bug that would otherwise skip bookmark creation in bookmark-based
    # repos where the default line itself is held by an active bookmark.
    echo ""
    echo "test 9b: active default bookmark -> still creates derived bookmark"
    HG_CB_ACTIVE_DEFAULT="$(mk_tmp)"
    make_hg_repo "$HG_CB_ACTIVE_DEFAULT"
    (
        cd "$HG_CB_ACTIVE_DEFAULT"
        # set up a remote/master revset alias so detect-branch.sh returns remote/master;
        # create-branch.sh will strip the `remote/` prefix and compare against the
        # active bookmark `master`, treating it as the default rather than a feature
        cat >>.hg/hgrc <<'HGRC'
[revsetalias]
remote/master = bookmark("master")
HGRC
        echo "seed" >seed.txt
        hg add seed.txt >/dev/null
        hg commit -m "seed" >/dev/null
        # create master as an active bookmark -- the default line is itself bookmarked
        hg book master >/dev/null
    )
    # confirm active bookmark is master before we run create-branch
    active_before="$(cd "$HG_CB_ACTIVE_DEFAULT" && hg log -r . --template '{activebookmark}\n')"
    assert_output "hg/active-default: precondition -- master bookmark is active" "master" "$active_before"
    output="$(cd "$HG_CB_ACTIVE_DEFAULT" && bash "$CREATE_BRANCH" "$PLAN_FILE_DATED" 2>/dev/null | tail -n 1)"
    assert_output "hg/active-default: outputs derived bookmark, not master" "$EXPECTED_DERIVED_BRANCH" "$output"
    book_list="$(cd "$HG_CB_ACTIVE_DEFAULT" && hg book --template '{bookmark}\n')"
    assert_contains "hg/active-default: derived bookmark was created" "$book_list" "$EXPECTED_DERIVED_BRANCH"
    active_after="$(cd "$HG_CB_ACTIVE_DEFAULT" && hg log -r . --template '{activebookmark}\n')"
    assert_output "hg/active-default: derived bookmark is now active" "$EXPECTED_DERIVED_BRANCH" "$active_after"
fi

echo ""
echo "testing VCS dispatch: stage-and-commit.sh"
echo "========================================="

# test 10: git repo, modified tracked file -> staged and committed
echo ""
echo "test 10: git repo, modified tracked file -> staged + committed"
GIT_SC_MODIFIED="$(mk_tmp)"
make_git_repo "$GIT_SC_MODIFIED" main
(
    cd "$GIT_SC_MODIFIED"
    echo "initial" >README.md
    git add README.md
    git commit -q -m "seed readme"
    echo "updated" >README.md
)
rc=0
(cd "$GIT_SC_MODIFIED" && bash "$STAGE_AND_COMMIT" "update readme" README.md >/dev/null 2>&1) || rc=$?
assert_output "git/modified: exit code 0" "0" "$rc"
subject="$(git -C "$GIT_SC_MODIFIED" log -1 --pretty=%s)"
assert_output "git/modified: commit subject matches" "update readme" "$subject"
files="$(git -C "$GIT_SC_MODIFIED" show --name-only --pretty=format: HEAD | sed '/^$/d')"
assert_output "git/modified: commit contains README.md" "README.md" "$files"

# test 11: git repo, new untracked file -> added and committed
echo ""
echo "test 11: git repo, new untracked file -> added + committed"
GIT_SC_NEW="$(mk_tmp)"
make_git_repo "$GIT_SC_NEW" main
(
    cd "$GIT_SC_NEW"
    echo "content" >newfile.txt
)
rc=0
(cd "$GIT_SC_NEW" && bash "$STAGE_AND_COMMIT" "add newfile" newfile.txt >/dev/null 2>&1) || rc=$?
assert_output "git/new: exit code 0" "0" "$rc"
subject="$(git -C "$GIT_SC_NEW" log -1 --pretty=%s)"
assert_output "git/new: commit subject matches" "add newfile" "$subject"
files="$(git -C "$GIT_SC_NEW" show --name-only --pretty=format: HEAD | sed '/^$/d')"
assert_output "git/new: commit contains newfile.txt" "newfile.txt" "$files"

if [ "$HG_AVAILABLE" -eq 1 ]; then
    # test 12: hg repo, modified tracked file -> committed via hg commit -A
    echo ""
    echo "test 12: hg repo, modified tracked file -> committed"
    HG_SC_MODIFIED="$(mk_tmp)"
    make_hg_repo "$HG_SC_MODIFIED"
    (
        cd "$HG_SC_MODIFIED"
        echo "initial" >README.md
        hg add README.md >/dev/null
        hg commit -m "seed readme" >/dev/null
        echo "updated" >README.md
    )
    rc=0
    (cd "$HG_SC_MODIFIED" && bash "$STAGE_AND_COMMIT" "update readme" README.md >/dev/null 2>&1) || rc=$?
    assert_output "hg/modified: exit code 0" "0" "$rc"
    subject="$(cd "$HG_SC_MODIFIED" && hg log -l 1 -T '{desc}')"
    assert_output "hg/modified: commit subject matches" "update readme" "$subject"
    files="$(cd "$HG_SC_MODIFIED" && hg log -l 1 -T '{files}')"
    assert_output "hg/modified: commit contains README.md" "README.md" "$files"

    # test 13: hg repo, new untracked file -> committed WITHOUT 'abort: file not tracked'
    # this is the critical case that catches the missing -A flag bug
    echo ""
    echo "test 13: hg repo, new untracked file -> committed via -A"
    HG_SC_NEW="$(mk_tmp)"
    make_hg_repo "$HG_SC_NEW"
    (
        cd "$HG_SC_NEW"
        echo "seed" >seed.txt
        hg add seed.txt >/dev/null
        hg commit -m "seed" >/dev/null
        echo "content" >newfile.txt
    )
    rc=0
    (cd "$HG_SC_NEW" && bash "$STAGE_AND_COMMIT" "add newfile" newfile.txt >/dev/null 2>&1) || rc=$?
    assert_output "hg/new: exit code 0 (no 'file not tracked' abort)" "0" "$rc"
    subject="$(cd "$HG_SC_NEW" && hg log -l 1 -T '{desc}')"
    assert_output "hg/new: commit subject matches" "add newfile" "$subject"
    files="$(cd "$HG_SC_NEW" && hg log -l 1 -T '{files}')"
    assert_output "hg/new: commit contains newfile.txt" "newfile.txt" "$files"

    # test 14: hg repo with deleted tracked file -> hg commit -A records the removal
    echo ""
    echo "test 14: hg repo, deleted tracked file -> removal recorded"
    HG_SC_DELETED="$(mk_tmp)"
    make_hg_repo "$HG_SC_DELETED"
    (
        cd "$HG_SC_DELETED"
        echo "seed" >seed.txt
        echo "gone" >gone.txt
        hg add seed.txt gone.txt >/dev/null
        hg commit -m "seed" >/dev/null
        rm -f gone.txt
    )
    rc=0
    (cd "$HG_SC_DELETED" && bash "$STAGE_AND_COMMIT" "remove gone" gone.txt >/dev/null 2>&1) || rc=$?
    assert_output "hg/deleted: exit code 0" "0" "$rc"
    subject="$(cd "$HG_SC_DELETED" && hg log -l 1 -T '{desc}')"
    assert_output "hg/deleted: commit subject matches" "remove gone" "$subject"
    files="$(cd "$HG_SC_DELETED" && hg log -l 1 -T '{files}')"
    assert_output "hg/deleted: commit contains gone.txt" "gone.txt" "$files"
    # confirm gone.txt is not in the working copy manifest
    manifest="$(cd "$HG_SC_DELETED" && hg manifest)"
    case "$manifest" in
    *gone.txt*)
        echo "  FAIL: hg/deleted: gone.txt still in manifest"
        failed=$((failed + 1))
        ;;
    *)
        echo "  PASS: hg/deleted: gone.txt removed from manifest"
        passed=$((passed + 1))
        ;;
    esac
fi

echo ""
echo "testing VCS dispatch: run-codex.sh"
echo "=================================="

# create a codex stub that prints each argument on its own line and exits 0.
# using a unique dir per run keeps the test hermetic against any real codex install.
STUB_DIR="$(mk_tmp)"
cat >"$STUB_DIR/codex" <<'STUB'
#!/bin/bash
for arg in "$@"; do
    printf '%s\n' "$arg"
done
STUB
chmod +x "$STUB_DIR/codex"

# test 15: git repo -> codex called WITHOUT --skip-git-repo-check
echo ""
echo "test 15: git repo -> codex invocation has no --skip-git-repo-check"
GIT_RC="$(mk_tmp)"
make_git_repo "$GIT_RC" main
stub_out="$(cd "$GIT_RC" && PATH="$STUB_DIR:$PATH" bash "$RUN_CODEX" "hello prompt")"
assert_not_contains "git: no --skip-git-repo-check" "$stub_out" "--skip-git-repo-check"
assert_contains "git: exec is present" "$stub_out" "exec"
assert_contains "git: --sandbox is present" "$stub_out" "--sandbox"
assert_contains "git: -c model= flag present" "$stub_out" "model=gpt-5.4"
assert_contains "git: -c model_reasoning_effort= flag present" "$stub_out" "model_reasoning_effort=high"
assert_contains "git: -c stream_idle_timeout_ms= flag present" "$stub_out" "stream_idle_timeout_ms=3600000"
assert_contains "git: project_doc=./CLAUDE.md flag present" "$stub_out" "project_doc=./CLAUDE.md"
assert_contains "git: prompt is passed through" "$stub_out" "hello prompt"

# test 15b: git repo with CODEX_MODEL override -> model is overridden
echo ""
echo "test 15b: git repo with CODEX_MODEL override"
stub_out="$(cd "$GIT_RC" && CODEX_MODEL=gpt-5.5 PATH="$STUB_DIR:$PATH" bash "$RUN_CODEX" "hello prompt")"
assert_contains "git: CODEX_MODEL env var overrides model" "$stub_out" "model=gpt-5.5"
assert_not_contains "git: default model not used when override set" "$stub_out" "model=gpt-5.4"

# test 15c: CODEX_NO_OVERRIDES=1 suppresses all -c flags -- for proxies that reject them
echo ""
echo "test 15c: CODEX_NO_OVERRIDES=1 suppresses -c overrides"
stub_out="$(cd "$GIT_RC" && CODEX_NO_OVERRIDES=1 PATH="$STUB_DIR:$PATH" bash "$RUN_CODEX" "hello prompt")"
assert_not_contains "git: no -c model= when CODEX_NO_OVERRIDES=1" "$stub_out" "model=gpt-5.4"
assert_not_contains "git: no -c model_reasoning_effort= when CODEX_NO_OVERRIDES=1" "$stub_out" "model_reasoning_effort"
assert_not_contains "git: no -c stream_idle_timeout_ms= when CODEX_NO_OVERRIDES=1" "$stub_out" "stream_idle_timeout_ms"
assert_not_contains "git: no project_doc when CODEX_NO_OVERRIDES=1" "$stub_out" "project_doc"
# non -c args (exec / --sandbox / prompt) must still be there
assert_contains "git: exec still present with CODEX_NO_OVERRIDES=1" "$stub_out" "exec"
assert_contains "git: --sandbox still present with CODEX_NO_OVERRIDES=1" "$stub_out" "--sandbox"
assert_contains "git: prompt still passed with CODEX_NO_OVERRIDES=1" "$stub_out" "hello prompt"

# test 15d: only the literal "1" activates suppression -- other values must NOT silently turn it on.
# guards against the "set to 1 to enable" semantic surprise where someone tries =0 to disable
# and accidentally enables it.
echo ""
echo "test 15d: CODEX_NO_OVERRIDES=0 does NOT activate suppression"
stub_out="$(cd "$GIT_RC" && CODEX_NO_OVERRIDES=0 PATH="$STUB_DIR:$PATH" bash "$RUN_CODEX" "hello prompt")"
assert_contains "git: -c model= present when CODEX_NO_OVERRIDES=0" "$stub_out" "model=gpt-5.4"

echo ""
echo "test 15e: CODEX_NO_OVERRIDES=false does NOT activate suppression"
stub_out="$(cd "$GIT_RC" && CODEX_NO_OVERRIDES=false PATH="$STUB_DIR:$PATH" bash "$RUN_CODEX" "hello prompt")"
assert_contains "git: -c model= present when CODEX_NO_OVERRIDES=false" "$stub_out" "model=gpt-5.4"

echo ""
echo "test 15f: CODEX_NO_OVERRIDES=no does NOT activate suppression"
stub_out="$(cd "$GIT_RC" && CODEX_NO_OVERRIDES=no PATH="$STUB_DIR:$PATH" bash "$RUN_CODEX" "hello prompt")"
assert_contains "git: -c model= present when CODEX_NO_OVERRIDES=no" "$stub_out" "model=gpt-5.4"

if [ "$HG_AVAILABLE" -eq 1 ]; then
    # test 16: hg repo -> codex called WITH --skip-git-repo-check positioned
    # right after 'exec' (before --sandbox)
    echo ""
    echo "test 16: hg repo -> codex has --skip-git-repo-check immediately after exec"
    HG_RC="$(mk_tmp)"
    make_hg_repo "$HG_RC"
    stub_out="$(cd "$HG_RC" && PATH="$STUB_DIR:$PATH" bash "$RUN_CODEX" "hello prompt")"
    assert_contains "hg: --skip-git-repo-check flag is present" "$stub_out" "--skip-git-repo-check"
    assert_contains "hg: exec is present" "$stub_out" "exec"
    assert_contains "hg: --sandbox is present" "$stub_out" "--sandbox"
    assert_contains "hg: -c model= flag present" "$stub_out" "model=gpt-5.4"
    assert_contains "hg: -c model_reasoning_effort= flag present" "$stub_out" "model_reasoning_effort=high"
    assert_contains "hg: project_doc=./CLAUDE.md flag present" "$stub_out" "project_doc=./CLAUDE.md"
    assert_contains "hg: prompt is passed through" "$stub_out" "hello prompt"

    # verify ordering: exec, then --skip-git-repo-check, then --sandbox
    # the stub outputs one arg per line, so we can directly index by line
    line1="$(printf '%s\n' "$stub_out" | sed -n '1p')"
    line2="$(printf '%s\n' "$stub_out" | sed -n '2p')"
    line3="$(printf '%s\n' "$stub_out" | sed -n '3p')"
    line4="$(printf '%s\n' "$stub_out" | sed -n '4p')"
    assert_output "hg: arg 1 is 'exec'" "exec" "$line1"
    assert_output "hg: arg 2 is '--skip-git-repo-check'" "--skip-git-repo-check" "$line2"
    assert_output "hg: arg 3 is '--sandbox'" "--sandbox" "$line3"
    assert_output "hg: arg 4 is 'read-only'" "read-only" "$line4"
fi

echo ""
echo "testing VCS dispatch: non-VCS dir propagation (set -e)"
echo "======================================================"

# test 17-20: each of the four exec scripts must exit non-zero in a non-VCS dir
# (detect-vcs.sh exits 1; set -e in the caller must propagate without falling through
# to the git/hg code paths)
EMPTY_DIR="$(mk_tmp)"

echo ""
echo "test 17: detect-branch.sh exits non-zero in empty dir"
rc=0
(cd "$EMPTY_DIR" && bash "$DETECT_BRANCH" >/dev/null 2>&1) || rc=$?
assert_exit_nonzero "detect-branch.sh: empty dir exits non-zero" "$rc"

echo ""
echo "test 18: create-branch.sh exits non-zero in empty dir"
rc=0
(cd "$EMPTY_DIR" && bash "$CREATE_BRANCH" "docs/plans/20260329-feature-name.md" >/dev/null 2>&1) || rc=$?
assert_exit_nonzero "create-branch.sh: empty dir exits non-zero" "$rc"

echo ""
echo "test 19: stage-and-commit.sh exits non-zero in empty dir"
rc=0
(cd "$EMPTY_DIR" && bash "$STAGE_AND_COMMIT" "msg" file.txt >/dev/null 2>&1) || rc=$?
assert_exit_nonzero "stage-and-commit.sh: empty dir exits non-zero" "$rc"

echo ""
echo "test 20: run-codex.sh exits non-zero in empty dir"
rc=0
(cd "$EMPTY_DIR" && PATH="$STUB_DIR:$PATH" bash "$RUN_CODEX" "prompt" >/dev/null 2>&1) || rc=$?
assert_exit_nonzero "run-codex.sh: empty dir exits non-zero" "$rc"

# summary
echo ""
echo "======================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
