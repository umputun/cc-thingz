# cc-thingz

A collection of utilities, configurations, and enhancements for [Claude Code](https://claude.ai/code).

## Contents

### scripts/plan-annotate.py

Interactive plan annotation tool for Claude Code. Opens plans in your `$EDITOR` via a terminal overlay (tmux popup or kitty overlay), lets you annotate directly, and feeds a unified diff back to Claude so it revises the plan. This creates a feedback loop: annotate → Claude revises → annotate again → until you close the editor without changes.

**Annotation style** — edit the plan text directly:
- Add lines to request additions
- Delete lines to request removal
- Modify lines to request changes
- Add inline comments (e.g., `- [ ] create handler — use JWT not sessions`)

**Two modes:**

*Hook mode* (default, no arguments) — acts as a `PreToolUse` hook for `ExitPlanMode`. When Claude finishes planning and calls `ExitPlanMode`, the hook automatically intercepts, opens the plan content in your editor, and waits. If you make changes, it denies the tool call with the diff as the reason, forcing Claude to revise and try again. If you close without changes, it proceeds to the normal approval dialog. This is the "set and forget" mode — once installed, every plan gets an annotation pass before approval.

*File mode* (`plan-annotate.py <plan-file>`) — opens a copy of the given file in your editor and outputs the unified diff to stdout (no JSON wrapping). Designed for integration with custom plan-making skills or actions. A workflow that generates plan files can call `plan-annotate.py docs/plans/foo.md` via Bash, read the diff output, revise the file, and loop until no diff is returned.

**Requirements:** tmux or kitty terminal, `$EDITOR` (defaults to `micro`)

**Install:**

Ask Claude Code:

> Fetch https://raw.githubusercontent.com/umputun/cc-thingz/master/scripts/plan-annotate.py, read the install instructions in its docstring, and follow them.

**Run tests:** `python3 scripts/plan-annotate.py --test`

## License

MIT
