# cc-thingz

Things to make [Claude Code](https://claude.ai/code) even better — hooks, skills, agents, and commands, packaged as a Claude Code plugin.

## Install

Add the marketplace and install:

    /plugin marketplace add umputun/cc-thingz
    /plugin install cc-thingz@umputun-cc-thingz

Test locally from the repo root:

    claude --plugin-dir .

**Manual install (alternative)** — if you prefer direct setup without the plugin system, copy the hook scripts and configure `settings.json` manually:

1. Copy `hooks/plan-annotate.py` and `hooks/skill-forced-eval-hook.sh` to `~/.claude/scripts/`
2. Make them executable: `chmod +x ~/.claude/scripts/plan-annotate.py ~/.claude/scripts/skill-forced-eval-hook.sh`
3. Add hook entries to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "ExitPlanMode",
      "hooks": [{
        "type": "command",
        "command": "~/.claude/scripts/plan-annotate.py",
        "timeout": 345600
      }]
    }],
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "~/.claude/scripts/skill-forced-eval-hook.sh"
      }]
    }]
  }
}
```

4. Restart Claude Code for hooks to take effect.

## hooks/plan-annotate.py

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

**Run tests:** `python3 hooks/plan-annotate.py --test`

## hooks/skill-forced-eval-hook.sh

`UserPromptSubmit` hook that forces Claude to evaluate and activate relevant skills before proceeding with implementation. By default, Claude Code often ignores available skills and jumps straight to generic responses. This hook injects a system reminder on every prompt that enforces an evaluate → activate → implement sequence.

When installed, Claude will either list relevant skills and call `Skill()` for each before implementing, or proceed directly when no skills are relevant.

## License

MIT
