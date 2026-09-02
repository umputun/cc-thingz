# Planning Plugin Usage

The planning plugin has three components: make (plan creation), exec (autonomous execution), and plan-review (quality review agent).

## Make: `planning:make`

### Triggers
- `planning:make <description>` — create an implementation plan
- invoked automatically by brainstorm when user picks "Write plan"

### Workflow
1. **Step 0** — parses intent (feature, bug fix, refactor, migration) and explores codebase for context
2. **Step 1** — asks focused questions one at a time: goal, scope, constraints, testing approach, title
3. **Step 1.5** — proposes 2-3 implementation approaches with trade-offs (skipped if obvious)
4. **Step 2** — creates plan file at `docs/plans/yyyymmdd-<task-name>.md`
5. **Step 3** — offers next steps: interactive review, auto review, implement, or done

### Examples
```
planning:make add user authentication
planning:make fix the race condition in the connection pool
planning:make refactor the middleware stack
planning:make add my Go testing rules to user-level planning rules
```

### Plan File Structure
- Overview, Context, Development Approach, Testing Strategy
- Implementation Steps with `### Task N:` sections
- Each task has `**Files:**` block and `[ ]` checkboxes
- Progress tracking with `[x]`, `➕`, `⚠️` markers

## Exec: `planning:exec`

### Triggers
- `planning:exec [plan-file]` — execute a plan autonomously
- "exec", "execute plan", "run plan"

### Workflow
1. Resolves plan file (from argument or picks from `docs/plans/`)
2. Asks about worktree isolation (worktree vs current directory)
3. Creates a feature branch
4. Executes tasks sequentially — one subagent per task, commits after each
5. Runs multi-phase review: comprehensive (iteration 1) then critical re-check loop → code smells → external review → critical-only
6. Optional finalize: rebase and squash commits
7. Completes terminal actions: moves the plan, commits that move, and records the outcome
8. Produces a run summary from the completed progress and VCS state

### Configuration
Set user configuration in
`${CODEX_HOME:-$HOME/.codex}/cc-thingz/planning/config.json`. A project may override the safe
workflow settings in `.codex/planning.json`, but project configuration must not contain
`external_review_cmd` or `plans_dir` because those keys select an executable or files outside the
checked-out configuration.

| Key | Default | Description |
|-----|---------|-------------|
| `external_review_cmd` | *(empty — falls back to codex)* | user-only external review tool command; prompt appended as final argv, findings on stdout |
| `task_retries` | `1` | retries for failed tasks; integer from 0 through 3 |
| `review_iterations` | `5` | max fix-and-recheck cycles; integer from 0 through 10 |
| `external_review_iterations` | `10` | max external review iterations; integer from 0 through 10 |
| `finalize_enabled` | `true` | run rebase + squash phase |
| `plans_dir` | `docs/plans` | user-only directory for plan files |

### Customization
Prompts and agent definitions use a three-layer override chain:
1. Project: `.codex/exec-plan/prompts/` and `.codex/exec-plan/agents/`
2. User: `${CODEX_HOME:-$HOME/.codex}/cc-thingz/planning/exec-plan/prompts/` and `agents/`
3. Bundled defaults

Nothing is copied anywhere automatically. Existing Claude installations may have seeded their plugin data with
copies of every bundled prompt and agent — those copies still shadow the bundled defaults and no longer track
upgrades, so check that directory and delete anything you did not deliberately edit.

To customize a file, resolve the planning plugin root from this skill's absolute catalogue path, then run the
bundled helper. Omit `--user` for a project override under `.codex/exec-plan/`; include it for a user override:

```bash
bash "<planning-plugin-root>/skills/exec/scripts/customize-file.sh" prompts/review.md
bash "<planning-plugin-root>/skills/exec/scripts/customize-file.sh" prompts/review.md --user
```

An override shadows the bundled default until the override is deleted.

### Customization patterns

- *Route review fanout to named specialists.* Override `prompts/review.md` to launch named subagents (`qa-expert`, `code-quality`, `go-test-expert`, `implementation-reviewer`, `documentation`) instead of `general-purpose`.
- *Delegate to an existing skill.* Override a prompt or agent file to read another skill's `SKILL.md` and follow it inline. Examples: `agents/smells.txt` → `/smells` skill; `prompts/finalizer.md` → `/rebase-commits` skill.

### Subagent constraint

`prompts/review.md` is read by the main session as an orchestration playbook. Leaf prompts (`task.md`, `fixer.md`, `finalizer.md`, `codex-review.md`, and `agents/smells.txt`) can be passed to subagents because they do not launch further workers.

## Plan-Review — agent

### Triggers
- launched by make's "Auto review" option
- usable directly as the `planning:plan-review` skill

### What It Checks
- problem definition and solution correctness
- scope creep and over-engineering
- testing requirements and coverage
- task granularity and ordering
- convention adherence (via AGENTS.md and custom rules)

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
