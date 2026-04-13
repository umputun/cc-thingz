# Planning Plugin Usage

The planning plugin has three components: make (plan creation), exec (autonomous execution), and plan-review (quality review agent).

## Make — `/planning:make`

### Triggers
- `/planning:make <description>` — create an implementation plan
- invoked automatically by brainstorm when user picks "Write plan"

### Workflow
1. **Step 0** — parses intent (feature, bug fix, refactor, migration) and explores codebase for context
2. **Step 1** — asks focused questions one at a time: goal, scope, constraints, testing approach, title
3. **Step 1.5** — proposes 2-3 implementation approaches with trade-offs (skipped if obvious)
4. **Step 2** — creates plan file at `docs/plans/yyyymmdd-<task-name>.md`
5. **Step 3** — offers next steps: interactive review, auto review, implement, or done

### Examples
```
/planning:make add user authentication
/planning:make fix the race condition in the connection pool
/planning:make refactor the middleware stack
/planning:make add my Go testing rules to user-level planning rules
```

### Plan File Structure
- Overview, Context, Development Approach, Testing Strategy
- Implementation Steps with `### Task N:` sections
- Each task has `**Files:**` block and `[ ]` checkboxes
- Progress tracking with `[x]`, `➕`, `⚠️` markers

## Exec — `/planning:exec`

### Triggers
- `/planning:exec [plan-file]` — execute a plan autonomously
- "exec", "execute plan", "run plan"

### Workflow
1. Resolves plan file (from argument or picks from `docs/plans/`)
2. Asks about worktree isolation (worktree vs current directory)
3. Creates a feature branch
4. Executes tasks sequentially — one subagent per task, commits after each
5. Runs multi-phase review: comprehensive → code smells → external (codex) → critical-only
6. Optional finalize: rebase and squash commits

### Configuration
Set via `userConfig` in plugin.json (prompted at install):

| Key | Default | Description |
|-----|---------|-------------|
| `external_review_cmd` | *(auto-detect codex)* | external review tool command |
| `task_retries` | `1` | retries for failed tasks |
| `review_iterations` | `5` | max fix-and-recheck cycles |
| `external_review_iterations` | `10` | max external review iterations |
| `finalize_enabled` | `true` | run rebase + squash phase |
| `plans_dir` | `docs/plans` | directory for plan files |

### Customization
Prompts and agent definitions use a three-layer override chain:
1. Project: `.claude/exec-plan/prompts/` and `.claude/exec-plan/agents/`
2. User: `$CLAUDE_PLUGIN_DATA/prompts/` and `$CLAUDE_PLUGIN_DATA/agents/`
3. Bundled defaults

A `SessionStart` hook copies bundled defaults to `$CLAUDE_PLUGIN_DATA` on first run — edit the copies to customize.

## Plan-Review — agent

### Triggers
- launched by make's "Auto review" option
- usable as `subagent_type: "plan-review"` in Agent tool calls

### What It Checks
- problem definition and solution correctness
- scope creep and over-engineering
- testing requirements and coverage
- task granularity and ordering
- convention adherence (via CLAUDE.md and custom rules)

### Output
Structured report with severity-rated findings:
- Critical Issues, Important Issues, Minor Issues
- Over-Engineering Concerns
- Testing Coverage Assessment
- Verdict: APPROVE or NEEDS REVISION

## Interactive Review

After creating a plan, make offers interactive review via:
- **revdiff** (if installed) — TUI with syntax highlighting and line-level annotations
- **plan-annotate.py** (fallback) — opens plan in `$EDITOR` via terminal overlay

Both loop until the user quits without annotations.
