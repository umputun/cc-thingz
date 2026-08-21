#!/bin/bash
# automated tests for run-external-review.sh and customize-file.sh
# covers external_review_cmd routing, the codex fallback, and opt-in override copying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
EXEC_SCRIPTS="$REPO_ROOT/plugins/planning/skills/exec/scripts"
REVIEW_SCRIPT="$EXEC_SCRIPTS/run-external-review.sh"
CUSTOMIZE_SCRIPT="$EXEC_SCRIPTS/customize-file.sh"

passed=0
failed=0

WORK_DIR="$(mktemp -d)"
BIN_DIR="$(mktemp -d)"
# PATH holding only the externals run-external-review.sh needs, so codex is
# guaranteed absent no matter what the host has installed in /usr/bin
NO_CODEX_DIR="$(mktemp -d)"

# safety: verify dirs live under the directory mktemp actually uses before any rm.
# the base comes from mktemp itself, not $TMPDIR -- BSD mktemp on macOS ignores
# TMPDIR for the default template and always uses _CS_DARWIN_USER_TEMP_DIR
# (/var/folders/.../T), so comparing against $TMPDIR aborts the suite on every
# macOS host. all dirs below come from a bare `mktemp -d`, so they share this base
TMP_BASE="$(dirname "$(mktemp -u)")"
assert_temp_dir() {
    local dir="$1"
    case "$dir" in "$TMP_BASE"/?*) ;; *) echo "FATAL: $dir is not under $TMP_BASE, refusing to proceed" >&2; exit 1;; esac
}
assert_temp_dir "$WORK_DIR"
assert_temp_dir "$BIN_DIR"
assert_temp_dir "$NO_CODEX_DIR"

cleanup() { rm -rf "$WORK_DIR" "$BIN_DIR" "$NO_CODEX_DIR"; }
trap cleanup EXIT

ln -s "$(command -v dirname)" "$NO_CODEX_DIR/dirname"

# run the interpreter running this suite, by absolute path. "env PATH=... bash"
# would resolve bash from the stripped PATH, so on a host without /bin/bash env
# itself exits 127 and an exit-code assertion passes for the wrong reason
SHELL_BIN="${BASH:-/bin/bash}"

# fake reviewer: reports how many bytes it read from stdin and what its last argv was
cat > "$BIN_DIR/fake-reviewer" <<'EOF'
#!/bin/bash
n=$(cat | wc -c | tr -d ' ')
echo "stdin=$n flags=${*:1:$#-1} prompt=${!#}"
EOF
chmod +x "$BIN_DIR/fake-reviewer"

# fake reviewer that runs and fails: a non-127 exit must reach the caller unchanged,
# so the orchestrator reports a reviewer failure instead of scanning empty output
# and concluding "no findings"
cat > "$BIN_DIR/fake-failing-reviewer" <<'EOF'
#!/bin/bash
echo "reviewer blew up" >&2
exit 3
EOF
chmod +x "$BIN_DIR/fake-failing-reviewer"

# fake codex: proves the empty-cmd path delegates to run-codex.sh
cat > "$BIN_DIR/codex" <<'EOF'
#!/bin/bash
echo "codex-called-with-last-arg=${!#}"
EOF
chmod +x "$BIN_DIR/codex"

assert_output() {
    local test_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        failed=$((failed + 1))
    fi
}

assert_exit_rc() {
    local test_name="$1" expected_rc="$2"
    shift 2
    local rc=0 out
    # keep the output so a failing exit-code assertion is actionable in CI
    out=$("$@" 2>&1) || rc=$?
    assert_output "$test_name" "$expected_rc" "$rc"
    [ "$rc" = "$expected_rc" ] || echo "    output:   $out"
}

# an exit code alone is often reachable by more than one branch (a bad path and an
# unknown bundled file both exit 1; `exec` of a missing binary yields 127 with no
# guard at all), so pin the message too or the assertion cannot tell them apart
assert_exit_stderr() {
    local test_name="$1" expected_rc="$2" expected_err="$3"
    shift 3
    local rc=0 err
    err=$("$@" 2>&1 >/dev/null) || rc=$?
    assert_output "$test_name (rc)" "$expected_rc" "$rc"
    case "$err" in
        *"$expected_err"*) assert_output "$test_name (stderr)" "matches" "matches" ;;
        *) assert_output "$test_name (stderr)" "*$expected_err*" "$err" ;;
    esac
}

echo "== run-external-review.sh =="

# configured command receives the prompt as its final argument
out=$(PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "fake-reviewer" "review the whole diff") || out="<rc=$?>"
assert_output "prompt passed as final argv" "stdin=0 flags= prompt=review the whole diff" "$out"

# a command string carrying flags is word-split, prompt still lands last
out=$(PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "fake-reviewer review --strict" "review the whole diff") || out="<rc=$?>"
assert_output "flags preserved before prompt" "stdin=0 flags=review --strict prompt=review the whole diff" "$out"

# an inherited pipe must not reach the tool, otherwise a background launch hangs
out=$(echo piped-data | PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "fake-reviewer" "P") || out="<rc=$?>"
assert_output "stdin isolated from inherited pipe" "stdin=0 flags= prompt=P" "$out"

# empty config falls back to codex rather than failing. runs in a throw-away repo
# because the delegated run-codex.sh calls detect-vcs.sh, which needs a VCS dir --
# never against the live working tree, which would break in a .git-less checkout
git init -q "$WORK_DIR/repo"
out=$(cd "$WORK_DIR/repo" && PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "" "review the whole diff") || out="<rc=$?>"
assert_output "empty cmd falls back to codex" "codex-called-with-last-arg=review the whole diff" "$out"

# a whitespace-only config must take the codex fallback too. it is non-empty, so a
# bare -z test would let it through to `command -v ""` and exit 127, which the
# caller reads as "no tool available" and silently skips the whole review phase
out=$(cd "$WORK_DIR/repo" && PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "   " "review the whole diff") || out="<rc=$?>"
assert_output "whitespace-only cmd falls back to codex" "codex-called-with-last-arg=review the whole diff" "$out"

# Claude Code's skill-content substitution leaves a ${user_config.KEY} reference in
# place when the option has no saved value, so the literal token is what an install
# that never went through /plugin configure actually passes. it must take the codex
# fallback: without this it reaches `command -v` and exits 127, which the orchestrator
# reads as "no review tool installed" and skips review phase 3 for most users
out=$(cd "$WORK_DIR/repo" && PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" '${user_config.external_review_cmd}' "review the whole diff") || out="<rc=$?>"
assert_output "unconfigured token falls back to codex" "codex-called-with-last-arg=review the whole diff" "$out"
# and it says why, so the run is not silent about having ignored the setting
err=$(cd "$WORK_DIR/repo" && PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" '${user_config.external_review_cmd}' "P" 2>&1 >/dev/null) || true
case "$err" in
    *"external_review_cmd is not configured"*) assert_output "unconfigured token noted on stderr" "noted" "noted" ;;
    *) assert_output "unconfigured token noted on stderr" "noted" "silent: $err" ;;
esac
# ...and that note must not carry the run-external-review marker. step 9 of SKILL.md
# treats a 127 as "skip the phase" only when stderr carries the marker, so a marker on
# this note would make a codex that ran and exited 127 (a wrapper whose inner binary is
# missing) look like "no review tool installed" on the default, never-configured install
cp "$BIN_DIR/codex" "$BIN_DIR/codex.ok"
cat > "$BIN_DIR/codex" <<'EOF'
#!/bin/bash
echo "inner tool not found" >&2
exit 127
EOF
chmod +x "$BIN_DIR/codex"
err=$(cd "$WORK_DIR/repo" && PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" '${user_config.external_review_cmd}' "P" 2>&1 >/dev/null) || true
case "$err" in
    *run-external-review:*) assert_output "unconfigured note carries no marker" "no marker" "marker present: $err" ;;
    *) assert_output "unconfigured note carries no marker" "no marker" "no marker" ;;
esac
# restore the succeeding fake: later assertions in this suite rely on it
mv "$BIN_DIR/codex.ok" "$BIN_DIR/codex"

# a real command that merely looks token-ish must not be swallowed by that guard
assert_exit_stderr "non-token cmd still resolved normally" 127 \
    "run-external-review: external_review_cmd not on PATH: user_config.external_review_cmd" \
    env PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "user_config.external_review_cmd" "P"

# 127 lets the caller skip the phase instead of reporting a review failure. the
# message matters as much as the code: step 9 of SKILL.md treats 127 as "skip" only
# when stderr carries the run-external-review marker, so a 127 from inside the
# reviewer itself stays a reviewer failure. asserting only rc would also pass with
# the `command -v` guard deleted, since `exec` of a missing binary exits 127 by itself
assert_exit_stderr "missing tool exits 127 with marker" 127 \
    "run-external-review: external_review_cmd not on PATH: definitely-not-a-tool-xyz" \
    env PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "definitely-not-a-tool-xyz --flag" "P"
assert_exit_stderr "missing codex exits 127 with marker" 127 \
    "run-external-review: codex not on PATH and external_review_cmd is not set" \
    env PATH="$NO_CODEX_DIR" "$SHELL_BIN" "$REVIEW_SCRIPT" "" "P"
# a reviewer that exits 127 on its own must not carry the marker, or the orchestrator
# would report the phase as skipped and never notice the review did not happen
cat > "$BIN_DIR/fake-127-reviewer" <<'EOF'
#!/bin/bash
echo "wrapped tool not found" >&2
exit 127
EOF
chmod +x "$BIN_DIR/fake-127-reviewer"
out=$(PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "fake-127-reviewer" "P" 2>&1 >/dev/null) || true
case "$out" in
    *run-external-review:*) assert_output "reviewer 127 carries no marker" "no marker" "marker present" ;;
    *) assert_output "reviewer 127 carries no marker" "no marker" "no marker" ;;
esac
# a multi-line value would be truncated to its first line by `read`, running a
# different command than configured -- report it instead
assert_exit_stderr "multi-line cmd rejected" 1 "must be a single line" \
    env PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "fake-reviewer
rm -rf /" "P"
assert_exit_rc "missing prompt exits 1" 1 \
    bash "$REVIEW_SCRIPT" "fake-reviewer"
# a reviewer that ran and failed must not be mistaken for 127 ("tool absent") or 0
assert_exit_rc "reviewer failure exit code propagates" 3 \
    env PATH="$BIN_DIR:$PATH" bash "$REVIEW_SCRIPT" "fake-failing-reviewer" "P"

echo "== customize-file.sh =="

# copying is opt-in: the bundled file is reachable without any override present.
# runs in the still-clean temp dir, since resolve-file.sh checks .claude/exec-plan
# relative to cwd and a developer's own override would otherwise satisfy this
# keep the `||`: dropping it aborts the suite under `set -e` and loses the summary.
# compare content rather than non-emptiness, since the fallback value is itself non-empty
bundled=$(cd "$WORK_DIR" && env -u CLAUDE_PLUGIN_DATA bash "$EXEC_SCRIPTS/resolve-file.sh" prompts/review.md) || bundled="<rc=$?>"
expected_bundled=$(cat "$REPO_ROOT/plugins/planning/skills/exec/references/prompts/review.md") || expected_bundled="<missing bundled file>"
if [ "$bundled" = "$expected_bundled" ]; then
    assert_output "bundled default resolves with no override" "bundled content" "bundled content"
else
    assert_output "bundled default resolves with no override" "bundled content" "${bundled%%$'\n'*}"
fi

mkdir -p "$WORK_DIR/fresh"

dest=$(cd "$WORK_DIR" && bash "$CUSTOMIZE_SCRIPT" prompts/review.md) || dest="<rc=$?>"
assert_output "project copy destination" ".claude/exec-plan/prompts/review.md" "$dest"

if diff -q "$WORK_DIR/.claude/exec-plan/prompts/review.md" \
    "$REPO_ROOT/plugins/planning/skills/exec/references/prompts/review.md" > /dev/null; then
    assert_output "copy matches bundled content" "same" "same"
else
    assert_output "copy matches bundled content" "same" "differs"
fi

# the copy now shadows the bundled default, which is why copying must be opt-in
echo "MY OVERRIDE" > "$WORK_DIR/.claude/exec-plan/prompts/review.md"
out=$(cd "$WORK_DIR" && bash "$EXEC_SCRIPTS/resolve-file.sh" prompts/review.md) || out="<rc=$?>"
assert_output "override shadows bundled default" "MY OVERRIDE" "$out"

dest=$(cd "$WORK_DIR" && bash "$CUSTOMIZE_SCRIPT" agents/quality.txt "$WORK_DIR/data") || dest="<rc=$?>"
assert_output "user-level copy destination" "$WORK_DIR/data/agents/quality.txt" "$dest"

if diff -q "$WORK_DIR/data/agents/quality.txt" \
    "$REPO_ROOT/plugins/planning/skills/exec/references/agents/quality.txt" > /dev/null 2>&1; then
    assert_output "user-level copy actually written" "same" "same"
else
    assert_output "user-level copy actually written" "same" "missing-or-differs"
fi

# the copy above is only useful if resolve-file.sh reads that layer back, and the
# project layer must win over it -- nothing seeds the user layer anymore, so this
# opt-in copy is the only route into it
echo "USER LEVEL" > "$WORK_DIR/data/agents/quality.txt"
out=$(cd "$WORK_DIR/fresh" && bash "$EXEC_SCRIPTS/resolve-file.sh" agents/quality.txt "$WORK_DIR/data") || out="<rc=$?>"
assert_output "user-level override is read back" "USER LEVEL" "$out"

mkdir -p "$WORK_DIR/fresh/.claude/exec-plan/agents"
echo "PROJECT LEVEL" > "$WORK_DIR/fresh/.claude/exec-plan/agents/quality.txt"
out=$(cd "$WORK_DIR/fresh" && bash "$EXEC_SCRIPTS/resolve-file.sh" agents/quality.txt "$WORK_DIR/data") || out="<rc=$?>"
assert_output "project override beats user override" "PROJECT LEVEL" "$out"

assert_exit_rc "refuses to clobber existing override" 1 \
    bash -c "cd '$WORK_DIR' && bash '$CUSTOMIZE_SCRIPT' prompts/review.md"

# a dangling symlink is invisible to -e, and cp would follow it and write the
# bundled content wherever it points, escaping the override dir entirely
mkdir -p "$WORK_DIR/link/.claude/exec-plan/prompts" "$WORK_DIR/outside"
ln -s "$WORK_DIR/outside/HIJACKED" "$WORK_DIR/link/.claude/exec-plan/prompts/review.md"
assert_exit_rc "refuses to follow a dangling symlink" 1 \
    bash -c "cd '$WORK_DIR/link' && bash '$CUSTOMIZE_SCRIPT' prompts/review.md"
if [ -e "$WORK_DIR/outside/HIJACKED" ]; then
    assert_output "symlink target left untouched" "absent" "written"
else
    assert_output "symlink target left untouched" "absent" "absent"
fi

# a symlinked ancestor is the same escape as a symlinked leaf: -e/-L do not see it,
# mkdir -p accepts it and cp follows it, so the copy lands outside the override dir
mkdir -p "$WORK_DIR/parentlink/.claude/exec-plan" "$WORK_DIR/parent-outside"
ln -s "$WORK_DIR/parent-outside" "$WORK_DIR/parentlink/.claude/exec-plan/prompts"
assert_exit_stderr "refuses a symlinked parent directory" 1 "symlinked directory component" \
    bash -c "cd '$WORK_DIR/parentlink' && bash '$CUSTOMIZE_SCRIPT' prompts/review.md"
if [ -e "$WORK_DIR/parent-outside/review.md" ]; then
    assert_output "symlinked parent target left untouched" "absent" "written"
else
    assert_output "symlinked parent target left untouched" "absent" "absent"
fi

# same check for a user-level copy, where the root comes from the data-dir argument
mkdir -p "$WORK_DIR/data2" "$WORK_DIR/data-outside"
ln -s "$WORK_DIR/data-outside" "$WORK_DIR/data2/agents"
assert_exit_stderr "refuses a symlinked parent under the data dir" 1 "symlinked directory component" \
    bash -c "cd '$WORK_DIR' && bash '$CUSTOMIZE_SCRIPT' agents/quality.txt '$WORK_DIR/data2'"
if [ -e "$WORK_DIR/data-outside/quality.txt" ]; then
    assert_output "symlinked data-dir target left untouched" "absent" "written"
else
    assert_output "symlinked data-dir target left untouched" "absent" "absent"
fi

# a data dir with a redundant trailing slash is normalized before use. stripping only
# one slash leaves it in the destination path and, worse, in the $stop the symlink walk
# compares against -- the walk then never matches the override root
mkdir -p "$WORK_DIR/slash/data"
dest=$(cd "$WORK_DIR/slash" && bash "$CUSTOMIZE_SCRIPT" agents/quality.txt "$WORK_DIR/slash/data//") || dest="<rc=$?>"
assert_output "trailing slashes stripped from data dir" "$WORK_DIR/slash/data/agents/quality.txt" "$dest"

# and the walk must still stop at the override root: a symlinked component *above* the
# data dir is a legitimate setup (a symlinked $HOME or ~/.claude), so it must not be
# rejected -- which is what an unnormalized $stop caused
mkdir -p "$WORK_DIR/slashreal/data"
ln -s "$WORK_DIR/slashreal" "$WORK_DIR/slashlink"
dest=$(cd "$WORK_DIR" && bash "$CUSTOMIZE_SCRIPT" agents/quality.txt "$WORK_DIR/slashlink/data//") || dest="<rc=$?>"
assert_output "symlink above the override root still allowed" "$WORK_DIR/slashlink/data/agents/quality.txt" "$dest"

# "/" strips to empty, so it must be rejected rather than falling through to the
# project-level branch -- the same silent downgrade the empty-argument guard prevents
assert_exit_stderr "filesystem-root data-dir rejected" 1 "empty or the filesystem root" \
    bash -c "cd '$WORK_DIR' && bash '$CUSTOMIZE_SCRIPT' prompts/task.md '/'"
if [ -e "$WORK_DIR/.claude/exec-plan/prompts/task.md" ]; then
    assert_output "root data-dir wrote nothing" "absent" "written"
else
    assert_output "root data-dir wrote nothing" "absent" "absent"
fi

# an empty data-dir means ${CLAUDE_PLUGIN_DATA} substituted to nothing; silently
# writing a project-level copy would not be what the caller asked for
assert_exit_rc "empty data-dir argument rejected" 1 \
    bash -c "cd '$WORK_DIR' && bash '$CUSTOMIZE_SCRIPT' prompts/finalizer.md ''"
if [ -e "$WORK_DIR/.claude/exec-plan/prompts/finalizer.md" ]; then
    assert_output "empty data-dir wrote nothing" "absent" "written"
else
    assert_output "empty data-dir wrote nothing" "absent" "absent"
fi
assert_exit_stderr "unknown bundled file exits 1" 1 "no bundled file at" \
    bash -c "cd '$WORK_DIR' && bash '$CUSTOMIZE_SCRIPT' prompts/does-not-exist.md"
# assert the guard's own message: '../../../etc/x' names nothing bundled, so rc=1
# alone still passes with the traversal guard deleted
assert_exit_stderr "path traversal rejected" 1 "path must be relative and stay inside" \
    bash -c "cd '$WORK_DIR' && bash '$CUSTOMIZE_SCRIPT' ../../../etc/x"
# and a traversal that does resolve to a real bundled file: without the guard this
# copies successfully, one level above the override dir
assert_exit_stderr "traversal to a real bundled file rejected" 1 "path must be relative and stay inside" \
    bash -c "cd '$WORK_DIR/fresh' && bash '$CUSTOMIZE_SCRIPT' ../references/prompts/review.md"
if [ -e "$WORK_DIR/fresh/.claude/references/prompts/review.md" ] || [ -e "$WORK_DIR/fresh/.claude/exec-plan/../references/prompts/review.md" ]; then
    assert_output "traversal wrote nothing" "absent" "written"
else
    assert_output "traversal wrote nothing" "absent" "absent"
fi
assert_exit_stderr "absolute path rejected" 1 "path must be relative and stay inside" \
    bash -c "cd '$WORK_DIR' && bash '$CUSTOMIZE_SCRIPT' /etc/passwd"
assert_exit_rc "no arguments exits 1" 1 \
    bash "$CUSTOMIZE_SCRIPT"

echo "== SKILL.md invocation =="

# the token must be single-quoted in the command SKILL.md tells the orchestrator to
# run. double-quoted, an unconfigured option (which substitutes to the reference
# verbatim, not to the schema default) makes bash abort the call with "bad
# substitution" -- so review phase 3 dies before the script's fallback can help
skill_md="$(dirname "$(dirname "$REVIEW_SCRIPT")")/SKILL.md"
invocation=$(grep -c "run-external-review.sh '\${user_config.external_review_cmd}'" "$skill_md" || true)
assert_output "SKILL.md single-quotes the config token" "1" "$invocation"
bad_quote=$(grep -c "run-external-review.sh \"\${user_config" "$skill_md" || true)
assert_output "SKILL.md does not double-quote the config token" "0" "$bad_quote"

echo
echo "======================================"
echo "results: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
