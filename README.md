# cc-thingz

Things to make [Claude Code](https://claude.ai/code) even better — hooks, skills, agents, and commands, packaged as a Claude Code plugin.

## Install

Add the marketplace and install:

    /plugin marketplace add umputun/cc-thingz
    /plugin install cc-thingz@umputun-cc-thingz

Test locally from the repo root:

    claude --plugin-dir .

<details>
<summary>Manual install (alternative)</summary>

If you prefer direct setup without the plugin system, copy the hook scripts and configure `settings.json` manually:

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

</details>

## Components

| Type | Name | Trigger | Description |
|------|------|---------|-------------|
| skill | [brainstorm](#skillsbrainstorm) | `/cc-thingz:brainstorm` | Collaborative design dialogue — idea → approaches → design → plan |
| command | [plan](#commandsplan) | `/cc-thingz:plan <desc>` | Structured implementation plan with interactive review loop |
| hook | [plan-annotate.py](#hooksplan-annotatepy) | `PreToolUse` / CLI | Plan annotation in `$EDITOR` with diff-based feedback loop |
| hook | [skill-forced-eval-hook.sh](#hooksskill-forced-eval-hooksh) | `UserPromptSubmit` | Forces skill evaluation before every response |

## skills/brainstorm

Collaborative design skill activated by `/cc-thingz:brainstorm` or trigger phrases like "brainstorm", "let's brainstorm", "help me design", "explore options for", etc.

Guides a 4-phase dialogue to turn ideas into designs:

1. **Understand** — gathers project context, asks questions one at a time (multiple choice preferred)
2. **Explore Approaches** — proposes 2-3 options with trade-offs, leads with recommendation
3. **Present Design** — breaks design into sections of 200-300 words, validates each incrementally
4. **Next Steps** — offers to write a plan (`/cc-thingz:plan`), enter plan mode, or start implementing

## commands/plan

Structured implementation plan creator activated by `/cc-thingz:plan <description>`. Creates a plan file in `docs/plans/yyyymmdd-<task-name>.md` through interactive context gathering.

Workflow:
- **Step 0** — parses intent and explores codebase for relevant context
- **Step 1** — asks focused questions one at a time (goal, scope, constraints, testing approach, title)
- **Step 1.5** — proposes 2-3 implementation approaches with trade-offs (skipped if obvious)
- **Step 2** — creates the plan file with tasks, file lists, test requirements, and progress tracking
- **Step 3** — offers interactive review (opens plan in `$EDITOR` via `plan-annotate.py`), auto review, start implementation, or done

The interactive review runs `plan-annotate.py` from the plugin root, creating an annotation feedback loop until the plan is finalized.

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
