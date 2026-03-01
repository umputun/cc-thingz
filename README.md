# cc-thingz

Things to make [Claude Code](https://claude.ai/code) even better — hooks, skills, and commands, organized as a marketplace of independent plugins.

This is an unapologetically opinionated set. Every skill here is something I actually use — some multiple times a day (brainstorm, plan, review), others less often but worth having in the toolbox. There are plenty of plugin collections out there, from random grab-bags to well-organized catalogs. This one is mine, and it reflects how I work. Even if you don't need my particular toolbox, it might give you ideas for building your own and making Claude Code do what you want it to do.

## Install

Add the marketplace, then install the plugins you want:

    /plugin marketplace add umputun/cc-thingz

    /plugin install brainstorm@umputun-cc-thingz
    /plugin install review@umputun-cc-thingz
    /plugin install planning@umputun-cc-thingz
    /plugin install release-tools@umputun-cc-thingz
    /plugin install thinking-tools@umputun-cc-thingz
    /plugin install skill-eval@umputun-cc-thingz
    /plugin install workflow@umputun-cc-thingz

Test a plugin locally:

    claude --plugin-dir plugins/brainstorm

<details>
<summary>Manual install (alternative)</summary>

Copy the files you want to your Claude Code config directory manually.

**brainstorm** — skill:
```bash
cp -r plugins/brainstorm/skills/do ~/.claude/skills/
```

**review** — skills (review-pr + git-review + writing-style):
```bash
cp -r plugins/review/skills/pr ~/.claude/skills/
cp -r plugins/review/skills/git-review ~/.claude/skills/
cp -r plugins/review/skills/writing-style ~/.claude/skills/
chmod +x ~/.claude/skills/git-review/scripts/git-review.py
```

Note: update the `/review:writing-style` reference inside `pr/SKILL.md` to `/writing-style` when installed manually.

**planning** — command + hook:
```bash
cp plugins/planning/commands/make.md ~/.claude/commands/
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
cp -r plugins/release-tools/skills/new ~/.claude/skills/
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

**workflow** — skills:
```bash
cp -r plugins/workflow/skills/learn ~/.claude/skills/
cp -r plugins/workflow/skills/clarify ~/.claude/skills/
cp -r plugins/workflow/skills/wrong ~/.claude/skills/
cp -r plugins/workflow/skills/md-copy ~/.claude/skills/
cp -r plugins/workflow/skills/txt-copy ~/.claude/skills/
```

Restart Claude Code for changes to take effect.

</details>

## Plugins

| Plugin | Description |
|--------|-------------|
| [brainstorm](#brainstorm) | Collaborative design dialogue — idea to approaches to design to plan |
| [review](#review) | PR review + interactive git diff annotation review + writing style guide |
| [planning](#planning) | Structured implementation planning with interactive annotation review |
| [release-tools](#release-tools) | Release workflow — auto-versioning, release notes, changelog |
| [thinking-tools](#thinking-tools) | Analytical thinking — dialectic analysis, root cause investigation |
| [skill-eval](#skill-eval) | Forces skill evaluation before every response |
| [workflow](#workflow) | Session helpers — knowledge capture, confusion handling, clipboard copy |

### brainstorm

Collaborative design skill. Invoke with `/brainstorm:do` or trigger phrases like "brainstorm", "let's brainstorm", "help me design", "explore options for", etc.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/brainstorm:do` | Collaborative design dialogue — idea → approaches → design → plan |

Guides a 4-phase dialogue to turn ideas into designs:

1. **Understand** — gathers project context, asks questions one at a time (multiple choice preferred)
2. **Explore Approaches** — proposes 2-3 options with trade-offs, leads with recommendation
3. **Present Design** — breaks design into sections of 200-300 words, validates each incrementally
4. **Next Steps** — offers to write a plan (`/planning:make`), enter plan mode, or start implementing

### review

PR review, interactive git diff annotation review, and writing style tools. Install together — review-pr uses writing-style for drafting comments.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/review:pr <number>` | PR review with architecture analysis, scope creep detection, and merge workflow |
| skill | `/review:git-review [ref]` | Interactive git diff annotation review — editor overlay with feedback loop |
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

**git-review** — interactive annotation-based code review. Generates a cleaned-up diff, opens it in `$EDITOR` via tmux popup, kitty overlay, or wezterm split-pane. You annotate directly in the diff, and the script returns your changes as a git diff. Claude reads annotations, fixes code, regenerates the diff, and loops until you close the editor without changes. Supports auto-detection of uncommitted changes or branch diffs.

Run tests: `python3 plugins/review/skills/git-review/scripts/git-review.py --test`

**writing-style** — enforces direct, brief writing for tickets, PRs, code reviews, and commit messages. Core principles: brevity, honest feedback, problem-solution structure, technical precision, anti-AI-speak. Does NOT apply to README.md, public docs, or blog posts.

### planning

Structured implementation planning with interactive annotation review.

| Component | Trigger | Description |
|-----------|---------|-------------|
| command | `/planning:make <desc>` | Structured implementation plan with interactive review loop |
| hook | `PreToolUse` / CLI | Plan annotation in `$EDITOR` with diff-based feedback loop |

**plan command** — creates a plan file in `docs/plans/yyyymmdd-<task-name>.md` through interactive context gathering:
- **Step 0** — parses intent and explores codebase for relevant context
- **Step 1** — asks focused questions one at a time (goal, scope, constraints, testing approach, title)
- **Step 1.5** — proposes 2-3 implementation approaches with trade-offs (skipped if obvious)
- **Step 2** — creates the plan file with tasks, file lists, test requirements, and progress tracking
- **Step 3** — offers interactive review (opens plan in `$EDITOR` via plan-annotate), auto review, start implementation, or done

**plan-annotate.py** — interactive plan annotation tool. Opens plans in your `$EDITOR` via a terminal overlay (tmux popup, kitty overlay, or wezterm split-pane), lets you annotate directly, and feeds a unified diff back to Claude so it revises the plan. Two modes:

- *Hook mode* (default) — intercepts `ExitPlanMode`, opens plan in editor, denies tool call with diff if changes made, forcing revision loop
- *File mode* (`plan-annotate.py <plan-file>`) — outputs unified diff to stdout for integration with custom workflows

Requirements: tmux, kitty, or wezterm terminal, `$EDITOR` (defaults to `micro`). **Kitty users** must enable remote control in `kitty.conf`:

```
allow_remote_control yes
listen_on unix:/tmp/kitty-$KITTY_PID
```

Run tests: `python3 plugins/planning/hooks/plan-annotate.py --test`

### release-tools

Release workflow tools for creating versioned releases with auto-generated notes.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/release-tools:new` | Create GitHub/GitLab/Gitea release with auto-versioning and release notes |
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

### workflow

Session workflow helpers for knowledge capture, confusion handling, course correction, and clipboard operations.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/workflow:learn` | Capture strategic project knowledge to local CLAUDE.md |
| skill | `/workflow:clarify` | Investigate and explain user confusion, determine if real issue exists |
| skill | `/workflow:wrong` | Reset and re-evaluate when current approach isn't working |
| skill | `/workflow:md-copy` | Format final answer as markdown and copy to clipboard |
| skill | `/workflow:txt-copy` | Copy generated text content to clipboard |

**learn** — reviews conversation history, extracts strategic project knowledge (architecture patterns, conventions, operational insights), and saves selected items to local CLAUDE.md. Uses granular selection via AskUserQuestion so the user picks exactly what to keep.

**clarify** — activates on confusion signals ("I don't understand", "why is this happening", etc.). Investigates the actual codebase to determine whether the confusion stems from a misunderstanding or a real issue. If real, proceeds to plan mode for a fix.

**wrong** — resets the current approach when it's not working. Re-analyzes the core problem, proposes 2-3 fresh alternatives with trade-offs, and recommends the best path forward.

**md-copy** — formats the session's final answer as clean markdown (bold titles instead of headings, proper tables, code blocks) and copies to clipboard. Cross-platform clipboard detection (macOS pbcopy, Linux xclip/xsel).

**txt-copy** — copies generated text (emails, messages, letters) to clipboard via a timestamped temp file. Cross-platform clipboard detection (macOS pbcopy, Linux xclip/xsel).

## Credits

Some skills and scripts were influenced by or adapted from community ideas, blog posts, and open-source examples. Sources were not tracked accurately from the start. If you recognize your work and want proper attribution, please [open an issue](https://github.com/umputun/cc-thingz/issues) — I'll fix it.

## License

MIT
