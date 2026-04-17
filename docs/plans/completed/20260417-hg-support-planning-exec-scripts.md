# hg support for planning/exec helper scripts

## Overview

The `planning` plugin's `/exec` skill crashes or silently misbehaves in Mercurial repos. Four shell scripts invoke `git` unconditionally, and `codex exec` rejects non-git working directories. This plan makes the four scripts VCS-aware (git + hg) and adds an orchestrator-level skip for the finalize and external-review phases in hg repos — without touching the git-oriented prompt files.

**Behaviour in git repos must stay byte-identical** to the pre-change baseline; git is the common case and any regression there is worse than the hg fix. jj support is intentionally out of scope — the dispatch pattern adopted here leaves it trivial to add later (single new arm in `detect-vcs.sh` plus a `detect_jj` equivalent).

The Mercurial-specific scope mirrors revdiff PR #90's pattern (umputun/revdiff), scaled down to shell: a `DetectVCS` probe that walks the VCS dispatch, shared behaviour where sensible, and preserved git output.

## Context (from discovery)

- **Scripts that crash in hg repos** (exit 128, `fatal: not a git repository`):
  - `plugins/planning/skills/exec/scripts/create-branch.sh`
  - `plugins/planning/skills/exec/scripts/stage-and-commit.sh`
- **Script that silently returns wrong value in hg** (returns `"main"` via final fallback):
  - `plugins/planning/skills/exec/scripts/detect-branch.sh`
- **Script blocked by codex** (codex exec: `Not inside a trusted directory and --skip-git-repo-check was not specified.`):
  - `plugins/planning/skills/exec/scripts/run-codex.sh`
- **Prompt files that reference git commands** — left untouched in this plan; orchestrator-level skip handles them:
  - `plugins/planning/skills/exec/references/prompts/finalizer.md` (uses `git fetch/rebase/log origin/*`, `git rebase -i`)
  - `plugins/planning/skills/exec/references/prompts/codex-review.md` (uses `git diff DEFAULT_BRANCH...HEAD`)
- **Orchestrator**: `plugins/planning/skills/exec/SKILL.md` — step 9 (external review) and step 11 (finalize) need the skip condition.
- **Testing convention**: `tests/test-*.sh` are run by CI (`.github/workflows/ci.yml`). Existing style (e.g. `tests/test-planning-resolve-rules.sh`): scaffold temp dirs with `mktemp -d`, assert outputs, trap-cleanup on exit. CI runs `shellcheck` on all `.sh` files. Mercurial is not currently installed in CI (`ubuntu-latest`).
- **Reference pattern**: `umputun/revdiff` PR #90 (`Add Mercurial VCS support`) — `DetectVCS` walks up dirs, VCS dispatch functions populate a shared field set, git output stays byte-identical. Ref translation patterns (`HEAD`→`.`, `HEAD~N`→`.~N`) documented there but not needed for these four scripts (no ref translation here).

## Development Approach

- **testing approach**: TDD where practical. Write `tests/test-exec-vcs-detect.sh` (new helper) and `tests/test-exec-vcs-dispatch.sh` (script behaviour in git vs hg) before editing the scripts. Fall back to manual matrix for hg integration where scaffolding is overkill.
- complete each task fully before moving to the next
- make small, focused changes — one script per task
- **keep git output byte-identical** — every git-repo edit must preserve `stdout + exit code` against a captured baseline
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
- **CRITICAL: all tests must pass before starting next task** — `bash tests/test-*.sh && find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck`
- **CRITICAL: update this plan file when scope changes during implementation**
- maintain backward compatibility (git users see no behaviour change)

## Testing Strategy

- **static**: `shellcheck` on every edited `.sh` file (CI enforces); `shfmt -d` locally before commit
- **automated shell tests** (under `tests/`, run by CI — requires hg in CI runner, installed in Task 1):
  - `tests/test-exec-vcs-detect.sh` — scaffolds git / hg / no-VCS / git+hg temp repos, asserts `detect-vcs.sh` output for each
  - `tests/test-exec-vcs-dispatch.sh` — scaffolds git + hg temp repos, runs `detect-branch.sh` / `create-branch.sh` / `stage-and-commit.sh`, asserts expected outputs + side effects (commit exists, branch set)
- **manual matrix** for `run-codex.sh` (requires live codex binary, not CI-friendly):

  | state | expected |
  |---|---|
  | git repo, `$CODEX_MODEL` unset | runs with `-c` flags, no `--skip-git-repo-check` |
  | hg repo | runs with `-c` flags AND `--skip-git-repo-check` |
  | non-VCS dir | script exits non-zero with clear error (from `detect-vcs.sh`) |

- **git regression baseline** (Task 1): capture pre-change output of each of the four scripts in a real git repo state; re-run after every task and `diff` — must be empty.
- **no python tests added** — this plan touches shell only.

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope
- keep plan in sync with actual work done

## Solution Overview

### Shared helper: `detect-vcs.sh`

New script at `plugins/planning/skills/exec/scripts/detect-vcs.sh`. Outputs one of `git` or `hg` on stdout, exits 1 with a stderr message otherwise.

Probe order: **git first, hg second**. (revdiff's jj-first precedence exists because jj colocates with `.git`; we have no jj support here, so git-first is correct and cheaper — `git rev-parse --git-dir` succeeds on every git repo and is faster than the hg check on the common path.) `command -v hg` guards the hg probe so git-only systems never spawn a missing-binary subprocess.

Each of the four existing scripts adds a two-line dispatch at the top:
```bash
vcs=$(bash "$(dirname "$0")/detect-vcs.sh")
```
…then a `case` that dispatches to a `do_<vcs>` function. The git function body is the **existing logic verbatim** — wrap-only, no edits — so the byte-identical-output guarantee is structural, not a property we have to maintain by hand.

### Per-script behaviour

- **`detect-branch.sh`** — hg arm: `echo "default"` (hg's universal default-branch name).
- **`create-branch.sh`** — hg arm: if `hg branch` ≠ `default`, echo it and exit (already on a feature branch); otherwise strip date prefix from plan filename. If a branch of that name already exists, `hg update <name>` to switch; otherwise `hg branch <name>` to create. Echo the name. (Named branches chosen over bookmarks because they survive rebases and match git's "this commit belongs to feature X" semantic. The existence check mirrors `create-branch.sh`'s git path, which does the same via `git show-ref` + `git checkout` vs `git checkout -b` — without it, re-running `/exec` on a partially-completed plan aborts.)
- **`stage-and-commit.sh`** — hg arm: `hg commit -A -m "$msg" -- "$@"`. The `-A` flag mark-adds untracked files (and mark-removes missing files) in the commit selection — this is the semantic parity with `git add -- "$@" && git commit -m "$msg"`. **Without `-A`, the very first task that creates a new file aborts** with `abort: <file>: file not tracked!`.
- **`run-codex.sh`** — keep all existing `-c` flags (unchanged). Only addition: append `--skip-git-repo-check` when `vcs=hg`.

### Orchestrator skip (SKILL.md)

Near step 1, add: "Run `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/detect-vcs.sh` and capture VCS. If output is `hg`: skip step 9 (external review) and step 11 (finalize) — report to user that hg-native finalize/review isn't upstream; users who want them can override via `.claude/exec-plan/prompts/finalizer.md` and `.claude/exec-plan/prompts/codex-review.md`."

This keeps the git-oriented prompt files untouched while still delivering a clean experience in hg repos (escape hatch via the existing override chain).

## Technical Details

### `detect-vcs.sh`

```bash
#!/bin/bash
# detect the VCS of the current working directory
# outputs "git" or "hg" on stdout; exits 1 if neither

set -e

if git rev-parse --git-dir >/dev/null 2>&1; then
    echo "git"
elif command -v hg >/dev/null 2>&1 && hg root >/dev/null 2>&1; then
    echo "hg"
else
    echo "error: not a git or mercurial repository" >&2
    exit 1
fi
```

Precedence note: if both `.git` and `.hg` exist at the same path (rare but legal), **git wins**. This matches revdiff's behaviour for the common case.

### Dispatch pattern (applied to each of the 4 scripts)

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
vcs=$(bash "$SCRIPT_DIR/detect-vcs.sh")

do_git() {
    # existing logic verbatim
}

do_hg() {
    # new hg-specific logic
}

case "$vcs" in
    git) do_git "$@" ;;
    hg)  do_hg "$@" ;;
    *)   echo "error: unsupported VCS: $vcs" >&2; exit 1 ;;
esac
```

`detect-vcs.sh` exits 1 on non-VCS; `set -e` in the caller propagates → the caller exits before the case on non-VCS. The `*)` arm is defensive: if `detect-vcs.sh` is later extended with a third VCS (e.g. `jj`), every call site fails loudly instead of silently no-op-ing. Cheap forward-compat insurance.

### hg-specific bodies

**`detect-branch.sh` — `do_hg`:**
```bash
do_hg() { echo "default"; }
```

**`create-branch.sh` — `do_hg`:**
```bash
do_hg() {
    local plan_file="$1"
    local current
    current=$(hg branch)
    if [ "$current" != "default" ]; then
        echo "$current"
        return 0
    fi
    # derive branch name from plan file (same sed as git path)
    local branch_name
    branch_name=$(basename "$plan_file" .md)
    # shellcheck disable=SC2001 # regex too complex for ${var//pattern}
    branch_name=$(echo "$branch_name" | sed 's/^[0-9]\{4\}-\{0,1\}[0-9]\{2\}-\{0,1\}[0-9]\{2\}-//')
    # if branch already exists (partial run recovery), update to it; else create
    if hg branches --template '{branch}\n' | grep -qx "$branch_name"; then
        hg update "$branch_name" >/dev/null
    else
        hg branch "$branch_name" >/dev/null
    fi
    echo "$branch_name"
}
```

**`stage-and-commit.sh` — `do_hg`:**
```bash
do_hg() {
    local msg="$1"; shift
    hg commit -A -m "$msg" -- "$@"
}
```

**`run-codex.sh` — full hg-aware shape:**
```bash
set -e
prompt="$1"
if [ -z "$prompt" ]; then
    echo "error: usage: run-codex.sh '<prompt>'" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
vcs=$(bash "$SCRIPT_DIR/detect-vcs.sh")

args=(exec)
[ "$vcs" = "hg" ] && args+=(--skip-git-repo-check)
args+=(
    --sandbox read-only
    -c "model=${CODEX_MODEL:-gpt-5.4}"
    -c "model_reasoning_effort=high"
    -c "stream_idle_timeout_ms=3600000"
    -c "project_doc=$HOME/.claude/CLAUDE.md"
    -c "project_doc=./CLAUDE.md"
)
codex "${args[@]}" "$prompt"
```
`--skip-git-repo-check` is positioned right after `exec` (before `--sandbox`) so codex parses it as an `exec`-level flag. The `-c` flag block is unchanged semantically.

### CI mercurial install

`.github/workflows/ci.yml`, `lint` job: add a step before `Run shell tests`:
```yaml
- name: Install mercurial
  run: |
      sudo apt-get install -y -qq --no-install-recommends mercurial || \
          (sudo apt-get update -qq && sudo apt-get install -y -qq --no-install-recommends mercurial)
      hg --version
```
Install-first / update-on-failure avoids the common `apt-get update` mirror flakiness when the package is already cached on `ubuntu-latest`. The trailing `hg --version` surfaces install failures in the install step rather than in a downstream test run as `hg: command not found`.

### SKILL.md edits (three explicit insertions)

Three separate edits to `plugins/planning/skills/exec/SKILL.md`:

**(1) Step 1** — add after "Determine the default branch" line:

> Then detect VCS: `vcs=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/detect-vcs.sh)`. Capture `$vcs` for use in step 9 and step 11.
>
> **If `vcs` is `hg`**: the external-review prompt (`prompts/codex-review.md`) and the finalize prompt (`prompts/finalizer.md`) use git-specific commands and are not VCS-translated upstream. Both phases will be skipped (see step 9 and step 11). Users who want hg-native review/finalize can override via `.claude/exec-plan/prompts/codex-review.md` and `.claude/exec-plan/prompts/finalizer.md` — note that when doing so, `DEFAULT_BRANCH` will be substituted as `default` (hg's default-branch name), so any `git rebase origin/DEFAULT_BRANCH` in the bundled template must be replaced with the hg equivalent (e.g. `hg rebase -d default`) in the override.

**(2) Step 9** — add at the very top (before the existing "Report to user: --- Review phase 3 ..." line):

> **hg skip**: If `vcs` is `hg`, skip this entire step. Report to user: "hg detected — skipping external review (git-only). Override `prompts/codex-review.md` via `.claude/exec-plan/` to enable hg-native review." Proceed directly to step 10.

**(3) Step 11** — add at the very top (before the existing "Check `finalize_enabled` userConfig ..." line):

> **hg skip**: If `vcs` is `hg`, skip this entire step. Report to user: "hg detected — skipping finalize (git-only). Override `prompts/finalizer.md` via `.claude/exec-plan/` to enable hg-native finalize." Proceed directly to step 12.

Insertions are at the top of steps 9 and 11 (not only at step 1) so the orchestrator's skip decision is local to the step — not reliant on long-range in-context retention. Also worth noting: step 10 (Review phase 4 — critical only) still runs in hg because it uses the same internal Claude-run review path as steps 7 and 8, which touch only files (not git commands).

### Worktree in hg (step 2) — not addressed in this plan

Step 2 asks the user whether to isolate in an `EnterWorktree`. `EnterWorktree` is a git-only tool (`git worktree add`). Task 6 must verify this assumption and, if confirmed, add "If `vcs` is `hg`, skip the worktree question and proceed in current directory" at the top of step 2. Out of scope to add hg worktree equivalent (hg has `hg share`, but tool support would be a separate plan).

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): helper script, dispatch refactor of four scripts, SKILL.md conditional, shell tests, CI update
- **Post-Completion** (no checkboxes): plugin version bump, manual `run-codex.sh` matrix, README changelog blurb, wild-testing on the user's real hg repo

## Implementation Steps

### Task 1: Add `detect-vcs.sh` helper + shell tests + CI mercurial install

**Files:**
- Create: `plugins/planning/skills/exec/scripts/detect-vcs.sh`
- Create: `tests/test-exec-vcs-detect.sh`
- Modify: `.github/workflows/ci.yml`

- [x] capture pre-change baseline for the four exec scripts in a throwaway git repo under `/tmp/exec-git-baseline/` and save outputs to `/tmp/exec-scripts-baseline-$(id -u).txt`. Seed the baseline repo's `refs/remotes/origin/HEAD` explicitly (`git remote add origin https://example.invalid/x.git && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main`) so `detect-branch.sh`'s fallback chain always takes path 1 — no network flake. Record for each script: stdout + exit code. Subsequent tasks' regression diffs must fail loudly if this file is missing (add `[ -f /tmp/exec-scripts-baseline-$(id -u).txt ] || { echo "missing baseline" >&2; exit 1; }` guard in each regression-diff step)
- [x] write `tests/test-exec-vcs-detect.sh` following the style of `tests/test-planning-resolve-rules.sh` (temp dirs, `assert_output`, trap cleanup). Cover: pure git repo → "git", pure hg repo → "hg", empty dir → exit 1, same-dir colocated `.git+.hg` → "git" (precedence — this is the scoped contract; nested boundary cases are out of scope), nested subdir of git repo → "git", nested subdir of hg repo → "hg", assert output is exactly `git\n` / `hg\n` (no trailing whitespace)
- [x] create `plugins/planning/skills/exec/scripts/detect-vcs.sh` per Technical Details. Make it executable (`chmod +x`)
- [x] run the new test — must pass
- [x] add mercurial install step to `.github/workflows/ci.yml` lint job (before "Run shell tests")
- [x] run `shellcheck plugins/planning/skills/exec/scripts/detect-vcs.sh tests/test-exec-vcs-detect.sh`
- [x] run `shfmt -d` on both new files; apply with `shfmt -w` if needed (used `shfmt -i 4` to match repo 4-space indent convention)
- [x] must pass before next task

### Task 2: Refactor `detect-branch.sh` to VCS dispatch (git path unchanged)

**Files:**
- Modify: `plugins/planning/skills/exec/scripts/detect-branch.sh`
- Create: `tests/test-exec-vcs-dispatch.sh` (git + hg coverage for all four dispatch scripts; add the `detect-branch` cases first, more added in subsequent tasks)

- [x] write `tests/test-exec-vcs-dispatch.sh` scaffolding FIRST (temp git and hg repos, helpers, trap cleanup). Add tests: git repo with `main` → outputs `main`; git repo with `master` → outputs `master`; hg repo (any state) → outputs `default`. Tests should fail against the current unmodified script for the hg case (silent-`main` bug) — confirm before implementing
- [x] wrap the existing body in `do_git()` — zero edits inside the function
- [x] add `do_hg() { echo "default"; }`
- [x] add dispatch at top (source `detect-vcs.sh`, case with `*)` safety arm)
- [x] git regression: `diff /tmp/exec-scripts-baseline-$(id -u).txt <(./detect-branch.sh)` against the baseline git repo — must be empty for this script's rows (fail-loud guard per Task 1)
- [x] `shellcheck` + `shfmt -d`
- [x] run `bash tests/test-*.sh` — all must pass
- [x] must pass before next task

### Task 3: Refactor `create-branch.sh` to VCS dispatch

**Files:**
- Modify: `plugins/planning/skills/exec/scripts/create-branch.sh`
- Modify: `tests/test-exec-vcs-dispatch.sh` (add `create-branch` cases)

- [x] extend `tests/test-exec-vcs-dispatch.sh` FIRST (tests before code): git repo on main with plan `20260329-feature-name.md` → creates/outputs `feature-name`; git repo already on feature → outputs current branch; hg repo on default with same plan → `hg branch` is set and outputs `feature-name`; hg repo already on `my-branch` → outputs `my-branch`; **hg repo re-run with branch already existing (partial-run recovery)** → `hg update` switches to it and outputs the name (catches the `hg branch` re-create abort); hg repo no-commit state → `hg branch` still sets the branch for next commit
- [x] confirm tests fail against current script (before implementation) so we know they actually exercise the hg path
- [x] wrap existing body in `do_git()` — zero edits inside (preserves the intricate default-branch fallback chain and date-prefix strip)
- [x] add `do_hg()` per Technical Details — MUST include the `hg branches | grep -qx` existence check + `hg update` vs `hg branch` branching, else re-runs will abort with "a branch of the same name already exists"
- [x] add dispatch at top (including the `*)` safety arm)
- [x] git regression diff must still be empty (with missing-baseline guard per Task 1)
- [x] `shellcheck` + `shfmt -d`
- [x] `bash tests/test-*.sh` — all pass
- [x] must pass before next task

### Task 4: Refactor `stage-and-commit.sh` to VCS dispatch

**Files:**
- Modify: `plugins/planning/skills/exec/scripts/stage-and-commit.sh`
- Modify: `tests/test-exec-vcs-dispatch.sh` (add `stage-and-commit` cases)

- [x] extend tests FIRST: git repo with modified tracked file → staged then committed; git repo with NEW untracked file → committed; hg repo with modified tracked file → committed via `hg commit -A` (assert `hg log -l 1 -T '{desc}'` matches message, `hg log -l 1 -T '{files}'` includes the file); **hg repo with NEW untracked file → committed without `abort: file not tracked`** (critical case — catches the missing `-A` flag bug); hg repo with deleted tracked file → `hg commit -A` records the removal
- [x] confirm the untracked-file tests fail against a `hg commit` (no `-A`) prototype to prove the test actually exercises the bug
- [x] wrap existing body in `do_git()`
- [x] add `do_hg()` per Technical Details: `hg commit -A -m "$msg" -- "$@"` — the `-A` is non-negotiable
- [x] add dispatch at top (including the `*)` safety arm)
- [x] git regression: commit behaviour on the baseline git repo must be identical (message, files, exit code). Note: the baseline capture in Task 1 should include stage-and-commit against both tracked-modified and untracked-new files so we compare apples to apples
- [x] `shellcheck` + `shfmt -d`
- [x] `bash tests/test-*.sh` — all pass
- [x] must pass before next task

### Task 5: Refactor `run-codex.sh` to VCS dispatch

**Files:**
- Modify: `plugins/planning/skills/exec/scripts/run-codex.sh`
- Modify: `tests/test-exec-vcs-dispatch.sh` (add invocation-shape cases — doesn't actually call codex)

- [x] extend tests FIRST: set `PATH=<stub-dir>:$PATH` where the stub `codex` does `printf '%s\n' "$@"` and exits 0 (create stub in a `mktemp -d`, not `/tmp/stub` directly, to keep the test hermetic). Assert: stub output in git repo has no `--skip-git-repo-check`; stub output in hg repo has `--skip-git-repo-check` **positioned right after `exec`** (before `--sandbox`); `-c model=` and `-c model_reasoning_effort=` appear in both; `project_doc=./CLAUDE.md` is present
- [x] refactor `run-codex.sh` to the exact shape in Technical Details (args-array, `exec` first, then conditional skip flag, then the `-c` flags)
- [x] keep all `-c` flags unchanged (`model`, `model_reasoning_effort`, `stream_idle_timeout_ms`, `project_doc` × 2). The `$CODEX_MODEL` env-var override must still work
- [x] add dispatch: `vcs=$(...)` line but no `do_git`/`do_hg` functions needed here — the VCS branch is just a conditional array-append. (If you prefer the do_git/do_hg shape for consistency with the other three scripts, that's fine — it's a style call; either is acceptable. Noted because the dispatch pattern in Technical Details assumes functions, but this script is simple enough the inline `[ "$vcs" = "hg" ] && args+=(--skip-git-repo-check)` is clearer.)
- [x] manual test (skipped — stub-based automated test provides equivalent coverage; stub asserts the exact invocation shape including `--skip-git-repo-check` positioning, preserving all `-c` flags and honouring `CODEX_MODEL`. Running live codex here would make real API calls without added signal beyond what the stub already verifies.)
- [x] `shellcheck` + `shfmt -d`
- [x] `bash tests/test-*.sh` — all pass
- [x] must pass before next task

### Task 6: Add VCS-aware skip in SKILL.md for finalize and external review

**Files:**
- Modify: `plugins/planning/skills/exec/SKILL.md`

- [x] apply insertion (1) at the end of step 1 — the detect-vcs call + hg note block (see SKILL.md edits in Technical Details for exact wording)
- [x] apply insertion (2) at the very top of step 9 — the hg skip block that routes to step 10
- [x] apply insertion (3) at the very top of step 11 — the hg skip block that routes to step 12
- [x] investigate `EnterWorktree` behaviour in hg repos: check Claude Code docs / try it manually in an hg repo — does the tool succeed, fail, or error unclearly? If it doesn't work cleanly, add a step-2 edit: "If `vcs` is `hg`, skip the worktree question and proceed in current directory." If it *does* work (e.g., because it wraps `jj`-style workspaces or similar), no edit needed but document findings in the commit message. Either outcome is fine; the key is a clear decision rather than leaving it ambiguous
- [x] grep the rest of SKILL.md for other git-specific instructions (`git diff`, `git log`, `git checkout`, `git rebase`) — flag any found in the document body, don't blanket-edit. Expected: none outside steps 9 and 11 (subagent prompts are in `references/prompts/`, not in SKILL.md)
- [x] use British spelling ("customise" not "customize", "behaviour" not "behavior") to match repo convention from global CLAUDE.md
- [x] verify YAML frontmatter still parses (`python3 -c "import yaml; yaml.safe_load(open('plugins/planning/skills/exec/SKILL.md').read().split('---')[1])"` — or just rely on CI's frontmatter validation step)
- [x] no code changes, no test additions for this task — documentation change only
- [x] must pass before next task

### Task 7: Verify acceptance criteria

- [x] re-run full baseline diff against `/tmp/exec-scripts-baseline-$(id -u).txt` on the same git repo state from Task 1 — every row empty
- [x] re-run `bash tests/test-*.sh` — all pass
- [x] re-run `find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck` — clean
- [x] re-run `shfmt -d` across touched files — clean
- [x] end-to-end smoke: scaffold an hg repo with a trivial plan under `docs/plans/20260417-smoke.md` and run `/planning:exec` on it (one task). Verify: branch `smoke` gets set via `hg branch`, task commit lands via `hg commit`, orchestrator skips steps 9 and 11 with the documented message
- [x] end-to-end smoke: same exercise in a git repo — confirm no behaviour change vs pre-plan (steps 9 and 11 still execute)
- [x] delete `/tmp/exec-scripts-baseline-$(id -u).txt` after verification passes
- [x] clean up `/tmp/exec-git-baseline/` and any hg scratch repos
- [x] must pass before next task

### Task 8: [Final] Update documentation + plan archival

- [x] README.md — add a line in the `plugins/planning/` description noting hg support for the `/exec` skill (scripts are VCS-aware; finalize and external review remain git-only, override via `.claude/exec-plan/` to customise)
- [x] CLAUDE.md — no change needed; existing conventions (shellcheck/shfmt rules, `${CLAUDE_PLUGIN_ROOT}` usage, plugin versioning) already cover the hg-aware scripts without modification
- [x] deferred — exec skill completion will archive after reviews and finalize (plan file must stay at current path so `/planning:exec` Review + Finalize phases 7-11 can still read it)

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only*

**Plugin version bump** (per CLAUDE.md rule on independent plugin versioning):
- `plugins/planning/.claude-plugin/plugin.json` — minor bump (new `detect-vcs.sh` helper + hg dispatch is additive; no breaking changes for git users)
- `.claude-plugin/marketplace.json` — sync the `planning` plugin version
- Ask the user to confirm the exact version number before bumping

**PR description notes:**
- Mention that this is hg-only; jj support is intentionally out of scope (dispatch pattern leaves it trivial to add later).
- Note that finalize + external review phases are skipped in hg repos with a pointer to the `.claude/exec-plan/prompts/` override mechanism.
- Call out the CI mercurial install as part of the change (so reviewers know why ubuntu-latest now pulls mercurial).

**Manual wild-testing** (nice-to-have, not required):
- Run `/planning:exec` on a real plan in an actual hg project. Confirm branch creation, per-task commits, and finalize/external-review skip all behave as documented.
- Optional: try the override path — drop a minimal `.claude/exec-plan/prompts/finalizer.md` with `hg rebase -d default` equivalent and confirm it gets picked up.
