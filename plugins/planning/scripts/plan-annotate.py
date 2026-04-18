#!/usr/bin/env python3
"""plan-annotate.py - PreToolUse hook for ExitPlanMode.

interactive plan review hook that lets you annotate Claude's plans directly
in your editor before approving them. when Claude calls ExitPlanMode, this
hook intercepts the call, opens the plan in $EDITOR via a terminal overlay
(tmux, kitty, wezterm, or ghostty), and waits for you to review/edit. if you make changes,
the hook computes a unified diff and sends it back to Claude as a denial
reason, forcing Claude to revise the plan based on your annotations. if
you make no changes, the normal approval dialog appears.

this creates a feedback loop: annotate → Claude revises → annotate again →
until you're satisfied and close the editor without changes.

annotation style - edit the plan text directly in your editor:
  - add new lines to request additions (e.g., "add error handling here")
  - delete lines to request removal
  - modify lines to request changes (e.g., change "use polling" to "use websockets")
  - add inline comments after existing text (e.g., "- [ ] create handler - use JWT not sessions")
any text change works - the hook diffs original vs edited and Claude sees
exactly what you added, removed, or modified.

hook receives JSON on stdin with the plan content in tool_input.plan field.
returns PreToolUse hook JSON response with permissionDecision:
  - "ask"  → no changes made, proceed to normal confirmation
  - "deny" → changes detected, unified diff sent as denial reason

requirements:
  - tmux, kitty, wezterm, or ghostty terminal (tmux tried first, then kitty, then wezterm, then ghostty)
  - $EDITOR set (defaults to micro)
  - kitty users: kitty.conf must have allow_remote_control and listen_on configured:
      allow_remote_control yes
      listen_on unix:/tmp/kitty-$KITTY_PID
  - ghostty users: requires Ghostty 1.3.0+ on macOS (uses AppleScript)

terminal priority: tmux display-popup → kitty overlay → wezterm split-pane → ghostty split → error

limitations:
  - requires tmux, kitty, wezterm, or ghostty - without any, returns error (no annotation)
  - does not work in plain terminals (iTerm2, Terminal.app, etc.)
  - kitty requires KITTY_LISTEN_ON env var (set by kitty when listen_on is configured)
  - the hook blocks until the editor closes; timeout should be set high
  - plan content comes from Claude's ExitPlanMode call, not from the plan
    file on disk - if you edit the file on disk separately, those changes
    won't be seen by this hook

file mode (for /planning:make integration):

    plan-annotate.py docs/plans/foo.md

opens a copy of the plan file in $EDITOR. if user makes changes, outputs
the unified diff to stdout (no JSON wrapping). Claude reads the diff,
revises the plan file, and calls again - looping until no changes.

usage:
    plan-annotate.py [--test]           # hook mode (stdin JSON)
    plan-annotate.py <plan-file>        # file mode (opens file copy in editor)
"""

import difflib
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def read_plan_from_stdin() -> str:
    """read plan content from hook event JSON on stdin."""
    raw = sys.stdin.read()
    if not raw.strip():
        return ""
    try:
        event = json.loads(raw)
        return event.get("tool_input", {}).get("plan", "")
    except json.JSONDecodeError:
        return ""


def make_response(decision: str, reason: str = "") -> str:
    """build PreToolUse hook JSON response."""
    resp: dict = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        }
    }
    if reason:
        resp["hookSpecificOutput"]["permissionDecisionReason"] = reason
    return json.dumps(resp, indent=2)


def get_diff(original: str, edited: str) -> str:
    """get unified diff between original and edited content."""
    orig_lines = original.splitlines(keepends=True)
    edit_lines = edited.splitlines(keepends=True)
    diff = difflib.unified_diff(orig_lines, edit_lines, fromfile="original", tofile="annotated", n=2)
    return "".join(diff)


def open_editor(filepath: Path, target_window: bool = True) -> int:
    """open file in $EDITOR via tmux popup, kitty overlay, wezterm split-pane, or ghostty split, blocking until editor closes.
    tries tmux first (if $TMUX is set), then kitty, then wezterm, then ghostty. returns non-zero if none is available.
    when target_window is True (hook mode), targets the kitty window from KITTY_WINDOW_ID.
    when False (file mode), opens in the currently focused window."""
    editor = os.environ.get("EDITOR", "micro")
    # resolve the first token of $EDITOR to an absolute path so that
    # sh -c (used by kitty/wezterm overlays) can find the binary even
    # when /opt/homebrew/bin or similar dirs are not in sh's default PATH.
    editor_parts = shlex.split(editor)
    resolved = shutil.which(editor_parts[0])
    if resolved:
        editor_parts[0] = resolved
    editor_cmd = " ".join(shlex.quote(p) for p in editor_parts)

    # tmux: display-popup -E blocks until the command exits, no sentinel needed
    if os.environ.get("TMUX") and shutil.which("tmux"):
        result = subprocess.run(
            ["tmux", "display-popup", "-E", "-w", "90%", "-h", "90%",
             "-T", "Plan Review", "--", "sh", "-c",
             f'{editor_cmd} {shlex.quote(str(filepath))}'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return result.returncode

    # kitty: use sentinel file to detect when editor closes.
    # requires KITTY_LISTEN_ON for socket communication — Claude Code runs
    # without a TTY, so kitty @ can't auto-detect via /dev/tty.
    # kitty.conf needs: allow_remote_control yes + listen_on unix:/tmp/kitty-$KITTY_PID
    kitty_sock = os.environ.get("KITTY_LISTEN_ON")
    if kitty_sock and shutil.which("kitty"):
        fd, sentinel_path = tempfile.mkstemp(prefix="plan-done-")
        os.close(fd)
        os.unlink(sentinel_path)
        sentinel = Path(sentinel_path)
        wrapper = f'{editor_cmd} {shlex.quote(str(filepath))}; touch {shlex.quote(str(sentinel))}'
        cmd = ["kitty", "@", "--to", kitty_sock, "launch", "--type=overlay",
               f"--title=Plan Review: {filepath.name}"]
        # in hook mode, target claude's window; in file mode, use focused window
        if target_window:
            kitty_wid = os.environ.get("KITTY_WINDOW_ID")
            if kitty_wid:
                cmd.extend(["--match", f"window_id:{kitty_wid}"])
        cmd.extend(["sh", "-c", wrapper])
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        while not sentinel.exists():
            time.sleep(0.3)
        sentinel.unlink(missing_ok=True)
        return 0

    # wezterm: split-pane with sentinel file (same pattern as kitty)
    wezterm_pane = os.environ.get("WEZTERM_PANE")
    if wezterm_pane and shutil.which("wezterm"):
        fd, sentinel_path = tempfile.mkstemp(prefix="plan-done-")
        os.close(fd)
        os.unlink(sentinel_path)
        sentinel = Path(sentinel_path)
        wrapper = f'{editor_cmd} {shlex.quote(str(filepath))}; touch {shlex.quote(str(sentinel))}'
        subprocess.run(
            ["wezterm", "cli", "split-pane", "--bottom", "--percent", "80",
             "--pane-id", wezterm_pane, "--", "sh", "-c", wrapper],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        while not sentinel.exists():
            time.sleep(0.3)
        sentinel.unlink(missing_ok=True)
        return 0

    # ghostty: split pane via AppleScript (macOS only, requires Ghostty 1.3.0+).
    # cmux sets TERM_PROGRAM=ghostty too; guard on CMUX_SURFACE_ID to avoid
    # misrouting a cmux session into a real-Ghostty AppleScript split.
    if (
        os.environ.get("TERM_PROGRAM") == "ghostty"
        and not os.environ.get("CMUX_SURFACE_ID")
        and shutil.which("osascript")
    ):
        fd, sentinel_path = tempfile.mkstemp(prefix="plan-done-")
        os.close(fd)
        os.unlink(sentinel_path)
        sentinel = Path(sentinel_path)
        wrapper = f'{editor_cmd} {shlex.quote(str(filepath))}; touch {shlex.quote(str(sentinel))}'

        launcher = tempfile.NamedTemporaryFile(
            mode="w", suffix=".sh", prefix="plan-launch-", delete=False
        )
        launcher.write(f"#!/bin/sh\n{wrapper}\n")
        launcher.close()
        launch_script_path = Path(launcher.name)
        os.chmod(launch_script_path, 0o755)

        applescript = """on run argv
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
            input=applescript, text=True, capture_output=True,
        )
        if result.returncode != 0:
            launch_script_path.unlink(missing_ok=True)
            sentinel.unlink(missing_ok=True)
            return 1
        ghostty_term_id = result.stdout.strip()

        while not sentinel.exists():
            time.sleep(0.3)

        # dismiss Ghostty's default "press any key to close" prompt
        close_applescript = """on run argv
    tell application "Ghostty" to close terminal id (item 1 of argv)
end run
"""
        subprocess.run(
            ["osascript", "-", ghostty_term_id],
            input=close_applescript, text=True, capture_output=True,
        )
        sentinel.unlink(missing_ok=True)
        launch_script_path.unlink(missing_ok=True)
        return 0

    return 1


def run_file_mode(plan_file: Path) -> None:
    """file mode: open plan copy in editor, output diff to stdout."""
    if not plan_file.exists():
        print(f"error: file not found: {plan_file}", file=sys.stderr)
        sys.exit(1)

    plan_content = plan_file.read_text()

    # copy to temp file for annotation
    with tempfile.NamedTemporaryFile(mode="w", suffix=".md", prefix="plan-review-", delete=False) as tmp:
        tmp.write(plan_content)
        tmp_path = Path(tmp.name)

    try:
        if open_editor(tmp_path, target_window=False) != 0:
            print("error: no overlay terminal available (requires tmux, kitty, wezterm, or ghostty)", file=sys.stderr)
            sys.exit(1)

        edited_content = tmp_path.read_text()
        diff = get_diff(plan_content, edited_content)

        if diff:
            print(diff)
    finally:
        tmp_path.unlink(missing_ok=True)


def run_hook_mode() -> None:
    """hook mode: read plan from stdin JSON, output hook response."""
    plan_content = read_plan_from_stdin()
    if not plan_content:
        print(make_response("ask", "no plan content in hook event"))
        return

    # write plan to temp file for editing
    with tempfile.NamedTemporaryFile(mode="w", suffix=".md", prefix="plan-review-", delete=False) as tmp:
        tmp.write(plan_content)
        tmp_path = Path(tmp.name)

    try:
        if open_editor(tmp_path) != 0:
            print(make_response("ask", "no overlay terminal available (requires tmux, kitty, wezterm, or ghostty), skipping plan annotation"))
            return

        edited_content = tmp_path.read_text()
        diff = get_diff(plan_content, edited_content)

        if not diff:
            print(make_response("ask", "plan reviewed, no changes"))
        else:
            feedback = (
                "user reviewed the plan in an editor and made changes. "
                "the diff below shows what the user modified (lines starting with - are original, + are user's version).\n"
                "examine each diff hunk to understand the user's feedback:\n"
                "- added lines (+) are user's annotations, comments, or requested additions\n"
                "- removed lines (-) with replacement (+) show what the user wants changed\n"
                "- removed lines (-) without replacement mean the user wants that removed\n"
                "- context lines (no prefix) show surrounding plan content for reference\n\n"
                f"{diff}\n"
                "adjust the plan to address each annotation, then call ExitPlanMode again."
            )
            print(make_response("deny", feedback))
    finally:
        tmp_path.unlink(missing_ok=True)


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="plan annotation hook for ExitPlanMode")
    parser.add_argument("--test", action="store_true", help="run unit tests")
    parser.add_argument("plan_file", nargs="?", help="plan file path (file mode)")
    args = parser.parse_args()

    if args.test:
        run_tests()
        return

    if args.plan_file:
        run_file_mode(Path(args.plan_file))
    else:
        run_hook_mode()


def run_tests() -> None:
    """run embedded unit tests."""
    import unittest

    class TestGetDiff(unittest.TestCase):
        def test_no_changes(self) -> None:
            text = "# Plan\n- task 1\n- task 2\n"
            self.assertEqual(get_diff(text, text), "")

        def test_added_line(self) -> None:
            original = "# Plan\n- task 1\n- task 2\n"
            edited = "# Plan\n- task 1\nadd timestamps\n- task 2\n"
            diff = get_diff(original, edited)
            self.assertIn("+add timestamps", diff)
            self.assertIn("task 1", diff)

        def test_removed_line(self) -> None:
            original = "# Plan\n- task 1\n- task 2\n"
            edited = "# Plan\n- task 2\n"
            diff = get_diff(original, edited)
            self.assertIn("-- task 1", diff)

        def test_modified_line(self) -> None:
            original = "# Plan\n- task 1\n"
            edited = "# Plan\n- task 1 (use JWT)\n"
            diff = get_diff(original, edited)
            self.assertIn("-- task 1", diff)
            self.assertIn("+- task 1 (use JWT)", diff)

        def test_multiple_changes(self) -> None:
            original = "# Plan\n\n## A\n- item\n\n## B\n- item\n"
            edited = "# Plan\n\n## A\n- item\nnote about A\n\n## B\n- item\nnote about B\n"
            diff = get_diff(original, edited)
            self.assertIn("+note about A", diff)
            self.assertIn("+note about B", diff)

    class TestReadPlanFromStdin(unittest.TestCase):
        def test_valid_event(self) -> None:
            import io
            event = json.dumps({"tool_input": {"plan": "# My Plan\n- task 1"}})
            old_stdin = sys.stdin
            sys.stdin = io.StringIO(event)
            try:
                self.assertEqual(read_plan_from_stdin(), "# My Plan\n- task 1")
            finally:
                sys.stdin = old_stdin

        def test_empty_stdin(self) -> None:
            import io
            old_stdin = sys.stdin
            sys.stdin = io.StringIO("")
            try:
                self.assertEqual(read_plan_from_stdin(), "")
            finally:
                sys.stdin = old_stdin

        def test_no_plan_field(self) -> None:
            import io
            old_stdin = sys.stdin
            sys.stdin = io.StringIO(json.dumps({"tool_input": {}}))
            try:
                self.assertEqual(read_plan_from_stdin(), "")
            finally:
                sys.stdin = old_stdin

        def test_invalid_json(self) -> None:
            import io
            old_stdin = sys.stdin
            sys.stdin = io.StringIO("not json")
            try:
                self.assertEqual(read_plan_from_stdin(), "")
            finally:
                sys.stdin = old_stdin

    class TestResponses(unittest.TestCase):
        def test_ask_response(self) -> None:
            result = json.loads(make_response("ask", "reviewed"))
            out = result["hookSpecificOutput"]
            self.assertEqual(out["hookEventName"], "PreToolUse")
            self.assertEqual(out["permissionDecision"], "ask")

        def test_deny_response(self) -> None:
            result = json.loads(make_response("deny", "fix this"))
            out = result["hookSpecificOutput"]
            self.assertEqual(out["permissionDecision"], "deny")
            self.assertIn("fix this", out["permissionDecisionReason"])

        def test_special_chars_in_json(self) -> None:
            result = make_response("deny", 'has "quotes" and\nnewlines')
            parsed = json.loads(result)
            self.assertIn("quotes", parsed["hookSpecificOutput"]["permissionDecisionReason"])

    class TestFileMode(unittest.TestCase):
        def test_file_not_found(self) -> None:
            path = Path("/tmp/nonexistent-plan-test-12345.md")
            with self.assertRaises(SystemExit) as ctx:
                run_file_mode(path)
            self.assertEqual(ctx.exception.code, 1)

        def test_file_read(self) -> None:
            # verify file mode reads content correctly
            tmp = Path(tempfile.mktemp(suffix=".md"))
            tmp.write_text("# Plan\n- task 1\n")
            try:
                content = tmp.read_text()
                self.assertEqual(content, "# Plan\n- task 1\n")
            finally:
                tmp.unlink(missing_ok=True)

    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for tc in [TestGetDiff, TestReadPlanFromStdin, TestResponses, TestFileMode]:
        suite.addTests(loader.loadTestsFromTestCase(tc))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\r\033[K", end="")
        sys.exit(130)
