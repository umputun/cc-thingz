#!/usr/bin/env python3
"""plan-review-hook.py - PreToolUse hook for ExitPlanMode.

intercepts ExitPlanMode and opens plan for user review. uses revdiff if
installed (syntax-highlighted TUI with line annotations), falls back to
plan-annotate.py ($EDITOR with unified diff) if not.

hook receives JSON on stdin with the plan content in tool_input.plan field.
returns PreToolUse hook JSON response with permissionDecision:
  - "ask"  → no changes/annotations, proceed to normal confirmation
  - "deny" → feedback found, sent as denial reason

requirements:
  - revdiff (preferred) or $EDITOR (fallback)
  - tmux, kitty, wezterm, or ghostty terminal
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
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


def make_response(decision: str, reason: str = "") -> None:
    """output PreToolUse hook response and exit with appropriate code.
    deny: plain text to stderr + exit 2 (Claude Code blocks the tool and shows the text).
    ask/allow: JSON to stdout + exit 0."""
    if decision == "deny":
        print(reason, file=sys.stderr)
        sys.exit(2)
    resp: dict = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        }
    }
    if reason:
        resp["hookSpecificOutput"]["permissionDecisionReason"] = reason
    print(json.dumps(resp, indent=2))


def try_revdiff(plan_content: str, plugin_root: str) -> str | None:
    """try reviewing plan with revdiff.

    returns:
        None: revdiff unavailable, launcher missing, or no overlay terminal
              (exit 127) → caller should fall back to plan-annotate.py
        "":   plan reviewed with no annotations → caller should respond "ask"
        str:  user annotations → caller should respond "deny" with this text

    on launcher/runtime failure (non-zero, non-127 exit) this function emits
    an "ask" response via make_response() and exits the process directly —
    a tool failure should NOT block ExitPlanMode as if the plan were wrong.
    """
    if not shutil.which("revdiff"):
        return None

    launcher = Path(plugin_root) / "scripts" / "launch-plan-review.sh"
    if not launcher.exists():
        return None

    # write plan to temp file
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".md", prefix="plan-review-", delete=False
    ) as tmp:
        tmp.write(plan_content)
        tmp_path = Path(tmp.name)

    try:
        result = subprocess.run(
            [str(launcher), str(tmp_path)],
            capture_output=True, text=True, timeout=345600,
            env={**os.environ},
        )
        # distinguish launcher outcomes:
        #   exit 127     → no overlay terminal available; fall back to plan-annotate.py
        #   other non-0 → overlay attempted but launcher/revdiff failed; surface
        #                 as "ask" so the user sees the tool error without the plan
        #                 being wrongly rejected as needing revision
        #   exit 0, ""   → user reviewed the plan and added no annotations (approve)
        #   exit 0, text → user added annotations (deny with feedback)
        if result.returncode == 127:
            return None
        if result.returncode != 0:
            stderr_text = (result.stderr or "").strip()[:500] or "no stderr output"
            make_response(
                "ask",
                f"revdiff review failed (exit {result.returncode}): {stderr_text}",
            )
            # make_response only sys.exits on "deny"; exit explicitly so main()
            # doesn't continue and misinterpret this as user feedback.
            sys.exit(0)
        annotations = result.stdout.strip()
        if not annotations:
            return ""
        return (
            "user reviewed the plan in revdiff and added annotations. "
            "each annotation references a specific line and contains the user's feedback.\n\n"
            f"{annotations}\n\n"
            "adjust the plan to address each annotation, then call ExitPlanMode again."
        )
    finally:
        tmp_path.unlink(missing_ok=True)


def main() -> None:
    plan_content = read_plan_from_stdin()
    if not plan_content:
        make_response("ask", "no plan content in hook event")
        return

    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if not plugin_root:
        make_response("ask", "CLAUDE_PLUGIN_ROOT not set")
        return

    # try revdiff first
    result = try_revdiff(plan_content, plugin_root)
    if result is not None:
        if not result:
            make_response("ask", "plan reviewed, no annotations")
        else:
            make_response("deny", result)
        return

    # fall back to plan-annotate.py — it handles its own editor overlay and diffing.
    # since we already consumed stdin, we need to re-feed the JSON to it.
    annotate_script = Path(plugin_root) / "scripts" / "plan-annotate.py"
    if not annotate_script.exists():
        make_response("ask", "no review tool available (revdiff not installed, plan-annotate.py not found)")
        return

    stdin_data = json.dumps({"tool_input": {"plan": plan_content}})
    fallback = subprocess.run(
        [sys.executable, str(annotate_script)],
        input=stdin_data, capture_output=True, text=True, timeout=345600,
        env={**os.environ},
    )

    # plan-annotate.py outputs the hook JSON response directly
    output = fallback.stdout.strip()
    if output:
        print(output)
        return
    # empty stdout + non-zero exit means plan-annotate.py crashed — surface the
    # error instead of silently approving the unreviewed plan.
    if fallback.returncode != 0:
        stderr_text = (fallback.stderr or "").strip()[:500] or "no stderr output"
        make_response(
            "ask",
            f"plan-annotate.py failed (exit {fallback.returncode}): {stderr_text}",
        )
        return
    make_response("ask", "plan reviewed, no changes")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\r\033[K", end="")
        sys.exit(130)
