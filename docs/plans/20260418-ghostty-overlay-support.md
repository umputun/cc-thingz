# Ghostty Terminal Overlay Support

## Overview
- Add Ghostty terminal overlay support to cc-thingz scripts that currently support only tmux/kitty/wezterm.
- Users on Ghostty cannot use `/planning:make` interactive review, `plan-annotate.py` fallback, or `/review:git-review` annotation flow — all three exit with "no overlay terminal available".
- The sibling `revdiff` repository already implements Ghostty overlay via AppleScript (`tell application "Ghostty" ... split ft direction down`) for Ghostty 1.3.0+ on macOS. This plan ports that mechanism into cc-thingz.

## Context (from discovery)
- Files with terminal overlay logic (all 3 currently lack Ghostty):
  - `plugins/planning/scripts/launch-plan-review.sh` — bash, launches revdiff TUI; supports tmux, kitty, wezterm.
  - `plugins/planning/scripts/plan-annotate.py` — Python, opens `$EDITOR`; supports tmux, kitty, wezterm.
  - `plugins/review/skills/git-review/scripts/git-review.py` — Python, opens `$EDITOR`; supports tmux, kitty, wezterm.
- Reference implementations in `../revdiff`:
  - `.claude-plugin/skills/revdiff/scripts/launch-revdiff.sh` — full overlay support (tmux/zellij/kitty/wezterm/cmux/ghostty/iterm2/vterm).
  - `plugins/revdiff-planning/scripts/launch-plan-review.sh` — planning-specific variant with Ghostty.
  - `docs/plans/completed/20260405-ghostty-support.md` — prior implementation plan.
- Ghostty detection: `TERM_PROGRAM == "ghostty"` plus `osascript` available **and** `CMUX_SURFACE_ID` unset. The cmux-guard is needed because cmux also sets `TERM_PROGRAM=ghostty`; without the guard, a cmux user would be routed to the AppleScript path and see an unexpected real-Ghostty split. Requires Ghostty 1.3.0+ (earlier versions lack `new surface configuration` AppleScript API).
- User scoped this plan to **Ghostty only** — not adding zellij/cmux/iterm2/vterm in this pass.
- Plugin versions to bump (minor, new terminal = new feature per CLAUDE.md's versioning guidance): `plugins/planning/.claude-plugin/plugin.json` (3.4.0 → 3.5.0), `plugins/review/.claude-plugin/plugin.json` (2.2.1 → 2.3.0).

## Development Approach
- **Testing approach**: manual verification only. Terminal overlays require a running Ghostty window — automated tests would either mock everything away (no real coverage) or need a desktop automation harness (out of scope).
- Small, focused changes: one script per task.
- Follow the existing block-order pattern: tmux → kitty → wezterm → **ghostty** (new) → error.
- Ghostty block uses `TERM_PROGRAM=ghostty` + `osascript` detection (matches revdiff pattern exactly).
- Preserve existing behavior: the error message at the bottom stays the source of truth for "what overlays are supported" — it gets updated too.
- Update docstrings, user-facing requirements comments, and docs to mention ghostty.
- **No new automated tests** per user decision. Each task ends with a manual verification step that the user performs.

## Testing Strategy
- **Unit tests**: none added (user chose manual-only).
- **Manual verification per script**:
  - Launch from a Ghostty terminal (1.3.0+, macOS). Confirm overlay opens as a split pane below with zoom enabled, blocks until closed, and returns annotations/diff correctly.
  - Negative: run outside Ghostty (e.g., plain Terminal.app with no `TMUX`/`KITTY_LISTEN_ON`/`WEZTERM_PANE`) and confirm the clean error message lists ghostty among supported terminals.
- **Shellcheck**: required for the modified bash script (per global `CLAUDE.md`).

## Progress Tracking
- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.
- Update plan if implementation deviates from original scope.

## Solution Overview
- For each of the three scripts, insert a **ghostty block** after the existing wezterm block and before the final "no overlay terminal available" error.
- The ghostty block:
  1. Detects `TERM_PROGRAM == "ghostty"` and presence of `osascript`.
  2. Creates a sentinel file path (shell) or tempfile (Python).
  3. Writes a launcher shell script that runs the real command and touches the sentinel on exit (same pattern as kitty/wezterm blocks).
  4. Invokes `osascript` with an AppleScript heredoc that calls `tell application "Ghostty"` to split the focused terminal downward, runs the launcher, zooms the new split, and returns the new terminal id.
  5. Polls for the sentinel, then calls another `osascript` to close the new terminal (dismisses Ghostty's default "press any key to close" prompt).
- All user-facing error messages updated: `"...requires tmux, kitty, wezterm, or ghostty"`.
- Docstring/comment updates to list ghostty as a supported terminal.

## Technical Details

### AppleScript for launching (bash variant)
```applescript
on run argv
    set launchScript to item 1 of argv
    tell application "Ghostty"
        set cfg to new surface configuration
        set command of cfg to launchScript
        set wait after command of cfg to false
        set ft to focused terminal of selected tab of front window
        set newTerm to split ft direction down with configuration cfg
        perform action "toggle_split_zoom" on newTerm
        return id of newTerm
    end tell
end run
```

### AppleScript for closing
```applescript
on run argv
    tell application "Ghostty" to close terminal id (item 1 of argv)
end run
```

### Python invocation pattern
For the two `.py` scripts, mirror the bash heredoc pattern `osascript - "$LAUNCH_SCRIPT" <<'APPLESCRIPT' ... APPLESCRIPT`. In Python: argv[1] is `-` (tells osascript to read the script from stdin), argv[2] onward become the AppleScript's `argv`. Pass the AppleScript body via `input=` (stdin).

Concrete snippet (launch):
```python
APPLESCRIPT = """on run argv
    set launchScript to item 1 of argv
    tell application "Ghostty"
        set cfg to new surface configuration
        set command of cfg to launchScript
        set wait after command of cfg to false
        set ft to focused terminal of selected tab of front window
        set newTerm to split ft direction down with configuration cfg
        perform action "toggle_split_zoom" on newTerm
        return id of newTerm
    end tell
end run
"""
result = subprocess.run(
    ["osascript", "-", str(launch_script_path)],
    input=APPLESCRIPT, text=True, capture_output=True,
)
if result.returncode != 0:
    # cleanup + return 1
    ...
ghostty_term_id = result.stdout.strip()
```

Close call (after sentinel):
```python
CLOSE_APPLESCRIPT = """on run argv
    tell application "Ghostty" to close terminal id (item 1 of argv)
end run
"""
subprocess.run(
    ["osascript", "-", ghostty_term_id],
    input=CLOSE_APPLESCRIPT, text=True, capture_output=True,
)
```

### Block position (bash script)
After the wezterm block (ends around line 79), before the final error (line 81). In Python scripts: after the wezterm branch, before `return 1`.

### Env propagation note (relevant only if editor env goes missing)
The revdiff reference prepends `/usr/bin/env EDITOR=... VISUAL=...` to the launcher command to survive Ghostty's `wait after command` re-exec shell. The current `plan-annotate.py` and `git-review.py` already resolve `$EDITOR` to an absolute path before passing it into the wrapper, so the env-prefix workaround is not needed here. Keep this in mind during manual verification — if `$EDITOR` fails to launch inside Ghostty, revisit.

## What Goes Where
- **Implementation Steps**: code edits to 3 scripts, docstring/comment updates, docs/README updates, plugin version bumps, shellcheck on bash.
- **Post-Completion**: manual verification in a real Ghostty window (macOS only).

## Implementation Steps

### Task 1: Add ghostty block to launch-plan-review.sh

**Files:**
- Modify: `plugins/planning/scripts/launch-plan-review.sh`

- [x] Insert ghostty block after the wezterm block (after line 79), before the final error message.
- [x] Gate on `[ "${TERM_PROGRAM:-}" = "ghostty" ] && [ -z "${CMUX_SURFACE_ID:-}" ] && command -v osascript >/dev/null 2>&1` — cmux-guard prevents misrouting when cmux sets `TERM_PROGRAM=ghostty`.
- [x] Create sentinel file via `mktemp /tmp/plan-review-done-XXXXXX` and immediately `rm -f` (matches existing pattern).
- [x] Create launcher script via `mktemp` containing `#!/bin/sh` + `$REVDIFF_CMD; touch '$SENTINEL'`, `chmod +x`.
- [x] Update trap to clean up launcher script (`trap 'rm -f "$OUTPUT_FILE" "$SENTINEL" "$LAUNCH_SCRIPT"' EXIT`).
- [x] Add `osascript` call with split-down + toggle_split_zoom AppleScript, capturing new terminal id.
- [x] Poll `while [ ! -f "$SENTINEL" ]; do sleep 0.3; done`.
- [x] Add close AppleScript to dismiss "press any key" prompt.
- [x] `cat "$OUTPUT_FILE"` then `exit 0`.
- [x] Update final error message to: `"error: no overlay terminal available (requires tmux, kitty, wezterm, or ghostty)"`.
- [x] Run `shellcheck plugins/planning/scripts/launch-plan-review.sh` and fix any warnings.
- [x] manual verify (skipped - not automatable): launch `bash plugins/planning/scripts/launch-plan-review.sh <some-plan.md>` inside a Ghostty window — split pane opens, revdiff loads, exits cleanly, annotations captured.

### Task 2: Add ghostty branch to plan-annotate.py open_editor

**Files:**
- Modify: `plugins/planning/scripts/plan-annotate.py`

- [x] Add ghostty branch inside `open_editor()` after the wezterm branch, before `return 1`.
- [x] Gate on `os.environ.get("TERM_PROGRAM") == "ghostty" and not os.environ.get("CMUX_SURFACE_ID") and shutil.which("osascript")` — cmux-guard prevents misrouting.
- [x] Create sentinel via `tempfile.mkstemp(prefix="plan-done-")` then unlink (existing pattern).
- [x] Build wrapper string: `f'{editor_cmd} {shlex.quote(str(filepath))}; touch {shlex.quote(str(sentinel))}'`.
- [x] Write wrapper to a temp launcher script via `tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False)` with `#!/bin/sh\n{wrapper}\n`, `chmod 0o755`.
- [x] Call `subprocess.run(["osascript", "-", launch_script_path], input=APPLESCRIPT, text=True, capture_output=True)` with the split+zoom AppleScript; read `result.stdout.strip()` as `ghostty_term_id`.
- [x] If osascript returns non-zero, unlink launcher + sentinel and `return 1`.
- [x] Poll sentinel with `time.sleep(0.3)` loop.
- [x] Call close AppleScript via `subprocess.run(["osascript", "-", ghostty_term_id], input=CLOSE_APPLESCRIPT, text=True, capture_output=True)`.
- [x] Unlink sentinel and launcher script, `return 0`.
- [x] Update top-of-file docstring: `requirements` list (line 29), `limitations` list (line 38), `terminal priority` line (line 35) to include ghostty.
- [x] Run `python3 plugins/planning/scripts/plan-annotate.py --test` to confirm embedded tests still pass (they do not exercise `open_editor`, so no changes expected).
- [x] manual verify (skipped - not automatable): invoke in file mode from Ghostty: `python3 plugins/planning/scripts/plan-annotate.py <some-plan.md>` — editor opens in split pane, edits produce diff on stdout.

### Task 3: Add ghostty branch to git-review.py open_editor

**Files:**
- Modify: `plugins/review/skills/git-review/scripts/git-review.py`

- [x] Add ghostty branch inside `open_editor()` after the wezterm branch, before `return 1` (around line 312).
- [x] Mirror the Task 2 implementation — same cmux-guarded gate, launcher file, osascript pattern.
- [x] Use prefix `"review-done-"` for sentinel to match existing git-review.py naming (NOT `plan-done-` from Task 2).
- [x] Set AppleScript title/context to match — no title is shown for Ghostty splits, so no title parameter needed.
- [x] Update the function docstring (line 258): `tries tmux first (if $TMUX is set), then kitty, then wezterm, then ghostty.`.
- [x] Update the error message in `run_review` (line 373): `"error: no overlay terminal available (requires tmux, kitty, wezterm, or ghostty)"`.
- [x] Run any existing tests: there are no `--test` flag tests in git-review.py beyond `run_tests()` — confirm by inspection.
- [x] manual verify (skipped - not automatable): inside a git repo with changes, launch `/review:git-review` from Ghostty; editor opens in split pane, annotations diff is printed on close.

### Task 4: Update user-facing documentation

**Files:**
- Modify: `README.md`
- Modify: `plugins/planning/references/usage.md`
- Modify: `plugins/planning/commands/make.md` (if it mentions terminal requirements)
- Modify: `plugins/planning/scripts/plan-review-hook.py` (docstring mentions terminals)
- Modify: `plugins/review/skills/git-review/SKILL.md` (if it mentions terminal requirements)

- [x] Run a broader grep to catch all phrasings (comma-separated, slash-separated, "or"): `grep -rEn "tmux[, /]|kitty[, /]|wezterm[, /]" plugins/ README.md` — update each hit to include ghostty.
- [x] Explicit docstring surfaces to update (line numbers may shift as Tasks 2/3 land; reference by section):
  - `plan-annotate.py` module docstring: the `(tmux or kitty)` parenthetical in the first paragraph, the `terminal priority:` arrow list (`tmux display-popup → kitty overlay → wezterm split-pane → ghostty split → error`), the `requirements` list, and the `limitations` list (`does not work in plain terminals`).
  - `git-review.py` module docstring: the `tmux/kitty/wezterm overlay` slash-separated form.
  - `plan-review-hook.py` docstring `requirements` line: `tmux, kitty, wezterm, or ghostty terminal`.
- [x] In `README.md`, find the planning and review plugin descriptions; update terminal requirement phrasing.
- [x] Ensure wording is consistent across all files (use the same canonical phrase: `tmux, kitty, wezterm, or ghostty`).
- [x] Add a brief one-line note in the appropriate reference/README that Ghostty requires 1.3.0+ on macOS. Place it where other terminal-specific caveats (e.g., kitty `allow_remote_control`) already live.
- [x] Final verification grep: `grep -rEn "tmux[, /]|kitty[, /]|wezterm[, /]" plugins/ README.md` should show ghostty included in every user-facing hit (vendored files, completed plans, and git history references are excluded).

### Task 5: Bump plugin versions

**Files:**
- Modify: `plugins/planning/.claude-plugin/plugin.json`
- Modify: `plugins/review/.claude-plugin/plugin.json`

- [x] Bump `plugins/planning/.claude-plugin/plugin.json` version `3.4.0` → `3.5.0` (minor: new terminal support = new feature per CLAUDE.md versioning guidance).
- [x] Bump `plugins/review/.claude-plugin/plugin.json` version `2.2.1` → `2.3.0` (same reasoning).
- [x] Do NOT change marketplace.json (no structural changes).

### Task 6: Verify acceptance criteria
- [ ] All three scripts now detect Ghostty and open a split pane instead of erroring out.
- [ ] Error message in all three scripts lists `ghostty` alongside tmux/kitty/wezterm.
- [ ] Docstrings, references, and README are consistent and mention ghostty.
- [ ] `shellcheck plugins/planning/scripts/launch-plan-review.sh` passes with no warnings.
- [ ] `python3 plugins/planning/scripts/plan-annotate.py --test` still passes.
- [ ] Grep-confirm there are no remaining "tmux, kitty, or wezterm" phrases that missed the update: `grep -rn "tmux, kitty" .` (excluding vendored files and completed plans).
- [ ] Plugin versions bumped.

### Task 7: [Final] Move plan to completed
- [ ] `mkdir -p docs/plans/completed`
- [ ] Move this plan file to `docs/plans/completed/`.

## Post-Completion
*Items requiring manual intervention outside this session.*

**Manual verification** (must be run from a Ghostty 1.3.0+ window on macOS):
- `/planning:make` → choose interactive review → confirm revdiff opens as a Ghostty split pane below, annotations loop works, split closes cleanly on quit.
- Trigger the `plan-annotate.py` fallback path (temporarily rename `revdiff` binary or unset from PATH) → confirm editor opens in Ghostty split pane, diff is returned on close.
- `/review:git-review` inside a repo with uncommitted changes → confirm `$EDITOR` opens in Ghostty split pane, diff annotations are captured.
- Negative: run each from plain Terminal.app (no TMUX, no Ghostty) → confirm the updated error message is shown with `ghostty` listed as a supported terminal.

**Release / marketplace**:
- Tag a release once changes land (user's standard release flow — out of scope for this plan).
- No `marketplace.json` update needed; plugin versions within their own `plugin.json` files handle discovery.
