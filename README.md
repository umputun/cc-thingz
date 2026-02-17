# cc-thingz

Things to make [Claude Code](https://claude.ai/code) even better — hooks, skills, and commands, organized as a marketplace of independent plugins.

## Install

Add the marketplace, then install the plugins you want:

    /plugin marketplace add umputun/cc-thingz

    /plugin install brainstorm@umputun-cc-thingz
    /plugin install review@umputun-cc-thingz
    /plugin install planning@umputun-cc-thingz
    /plugin install release-tools@umputun-cc-thingz
    /plugin install thinking-tools@umputun-cc-thingz
    /plugin install skill-eval@umputun-cc-thingz

Test a plugin locally:

    claude --plugin-dir plugins/brainstorm

<details>
<summary>Manual install (alternative)</summary>

Copy the files you want to your Claude Code config directory manually.

**brainstorm** — skill:
```bash
cp -r plugins/brainstorm/skills/brainstorm ~/.claude/skills/
```

**review** — skills (review-pr + writing-style):
```bash
cp -r plugins/review/skills/review-pr ~/.claude/skills/
cp -r plugins/review/skills/writing-style ~/.claude/skills/
```

Note: update the `/review:writing-style` reference inside `review-pr/SKILL.md` to `/writing-style` when installed manually.

**planning** — command + hook:
```bash
cp plugins/planning/commands/plan.md ~/.claude/commands/
cp plugins/planning/hooks/plan-annotate.py ~/.claude/scripts/
chmod +x ~/.claude/scripts/plan-annotate.py
```

Add the plan-annotate hook to `~/.claude/settings.json`:
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
    }]
  }
}
```

**release-tools** — skills + scripts:
```bash
cp -r plugins/release-tools/skills/release ~/.claude/skills/
cp -r plugins/release-tools/skills/last-tag ~/.claude/skills/
chmod +x ~/.claude/skills/release/scripts/*.sh
```

**thinking-tools** — skills:
```bash
cp -r plugins/thinking-tools/skills/dialectic ~/.claude/skills/
cp -r plugins/thinking-tools/skills/root-cause-investigator ~/.claude/skills/
```

**skill-eval** — hook:
```bash
cp plugins/skill-eval/hooks/skill-forced-eval-hook.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/skill-forced-eval-hook.sh
```

Add the skill-eval hook to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "~/.claude/scripts/skill-forced-eval-hook.sh"
      }]
    }]
  }
}
```

Restart Claude Code for changes to take effect.

</details>

## Plugins

### brainstorm

Collaborative design skill. Invoke with `/brainstorm:brainstorm` or trigger phrases like "brainstorm", "let's brainstorm", "help me design", "explore options for", etc.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/brainstorm:brainstorm` | Collaborative design dialogue — idea → approaches → design → plan |

Guides a 4-phase dialogue to turn ideas into designs:

1. **Understand** — gathers project context, asks questions one at a time (multiple choice preferred)
2. **Explore Approaches** — proposes 2-3 options with trade-offs, leads with recommendation
3. **Present Design** — breaks design into sections of 200-300 words, validates each incrementally
4. **Next Steps** — offers to write a plan (`/planning:plan`), enter plan mode, or start implementing

### review

PR review and writing style tools. Install together — review-pr uses writing-style for drafting comments.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/review:review-pr <number>` | PR review with architecture analysis, scope creep detection, and merge workflow |
| skill | `/review:writing-style` | Direct technical communication — anti-AI-speak, brevity, no filler |

**review-pr** — analyzes code quality, architecture, test coverage, and identifies scope creep:
- **Phase 0** — detects PR vs issue (issues get a simpler comment-only flow)
- **Phase 1** — fetches PR metadata, discussion history, merge status, and inline suggestions
- **Phase 1.5** — asks review mode: Full (worktree + tests + linter + architecture) or Quick (diff-only)
- **Phase 2** — sets up worktree and launches a subagent for deep analysis
- **Phase 3-4** — presents findings, resolves open design questions
- **Phase 5** — drafts review comment using `/review:writing-style`, posts as formal review
- **Post-approve** — recommends merge strategy (rebase vs squash vs merge)

Uses `gh` CLI for all GitHub operations and git worktrees to avoid disrupting the current checkout.

**writing-style** — enforces direct, brief writing for tickets, PRs, code reviews, and commit messages. Core principles: brevity, honest feedback, problem-solution structure, technical precision, anti-AI-speak. Does NOT apply to README.md, public docs, or blog posts.

### planning

Structured implementation planning with interactive annotation review.

| Component | Trigger | Description |
|-----------|---------|-------------|
| command | `/planning:plan <desc>` | Structured implementation plan with interactive review loop |
| hook | `PreToolUse` / CLI | Plan annotation in `$EDITOR` with diff-based feedback loop |

**plan command** — creates a plan file in `docs/plans/yyyymmdd-<task-name>.md` through interactive context gathering:
- **Step 0** — parses intent and explores codebase for relevant context
- **Step 1** — asks focused questions one at a time (goal, scope, constraints, testing approach, title)
- **Step 1.5** — proposes 2-3 implementation approaches with trade-offs (skipped if obvious)
- **Step 2** — creates the plan file with tasks, file lists, test requirements, and progress tracking
- **Step 3** — offers interactive review (opens plan in `$EDITOR` via plan-annotate), auto review, start implementation, or done

**plan-annotate.py** — interactive plan annotation tool. Opens plans in your `$EDITOR` via a terminal overlay (tmux popup or kitty overlay), lets you annotate directly, and feeds a unified diff back to Claude so it revises the plan. Two modes:

- *Hook mode* (default) — intercepts `ExitPlanMode`, opens plan in editor, denies tool call with diff if changes made, forcing revision loop
- *File mode* (`plan-annotate.py <plan-file>`) — outputs unified diff to stdout for integration with custom workflows

Requirements: tmux or kitty terminal, `$EDITOR` (defaults to `micro`). Run tests: `python3 plugins/planning/hooks/plan-annotate.py --test`

### release-tools

Release workflow tools for creating versioned releases with auto-generated notes.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/release-tools:release` | Create GitHub/GitLab/Gitea release with auto-versioning and release notes |
| skill | `/release-tools:last-tag` | Show commits since the last git tag in a formatted table |

**release** — full release workflow: asks release type (hotfix/minor/major), auto-detects platform (GitHub/GitLab/Gitea), calculates semantic version, generates release notes grouped by type (features/improvements/fixes) from merged PRs and commits, updates CHANGELOG if present, shows preview for confirmation, then publishes. Includes helper scripts for platform detection, version calculation, and notes generation.

**last-tag** — shows commits since the last git tag in a formatted table with date, author, hash, and description. Detects single vs multiple authors and adjusts table layout. Offers interactive drill-down into individual commit details.

### thinking-tools

Analytical thinking tools for objective analysis.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/thinking-tools:dialectic <statement>` | Prove and counter-prove a statement using parallel agents |
| skill | `/thinking-tools:root-cause-investigator` | Systematic 5-Why root cause analysis for errors and bugs |

**dialectic** — runs two agents in parallel with opposing goals (thesis vs antithesis) to eliminate confirmation bias. One agent finds all positive evidence, the other finds all negative evidence. After both complete, synthesizes findings into an objective conclusion and verifies cited evidence against actual code.

Use cases: architecture decisions, bug analysis, performance claims, refactoring safety, code review.

**root-cause-investigator** — applies 5-Why methodology to drill from symptoms to fundamental root causes. Structures investigation through progressive depth: surface cause → process issues → system problems → design issues → root cause. Includes reference materials for common patterns (race conditions, resource exhaustion, integration failures) and investigation techniques.

### skill-eval

Forces skill evaluation before every response.

| Component | Trigger | Description |
|-----------|---------|-------------|
| hook | `UserPromptSubmit` | Forces skill evaluation before every response |

By default, Claude Code often ignores available skills and jumps straight to generic responses. This hook injects a system reminder on every prompt that enforces an evaluate → activate → implement sequence. When installed, Claude will either list relevant skills and call `Skill()` for each before implementing, or proceed directly when no skills are relevant.

## Credits

Some skills and scripts were influenced by or adapted from community ideas, blog posts, and open-source examples. Sources were not tracked accurately from the start. If you recognize your work and want proper attribution, please [open an issue](https://github.com/umputun/cc-thingz/issues) — I'll fix it.

## License

MIT
