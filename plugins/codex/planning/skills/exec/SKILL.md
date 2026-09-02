---
name: exec
description: Execute a structured implementation plan autonomously, one task at a time, with fresh implementation agents, staged reviews, an independent external review, progress logging, and final branch cleanup. Use when the user asks to execute or implement an approved plan autonomously.
---

# Autonomous Plan Execution

Execute a plan sequentially with isolated task contexts and review gates.

## Invocation

The optional argument is a plan file path. If omitted, select a current plan from the configured plans directory.

## Path resolution

`<plugin-root>` means the nearest ancestor of this `SKILL.md` containing
`.codex-plugin/plugin.json`. Resolve it to an absolute path before running any bundled script or
substituting it into a prompt.

## Configuration

Start with these defaults:

```json
{
  "external_review_cmd": "",
  "task_retries": 1,
  "review_iterations": 5,
  "external_review_iterations": 10,
  "finalize_enabled": true,
  "plans_dir": "docs/plans"
}
```

Load `${CODEX_HOME:-$HOME/.codex}/cc-thingz/planning/config.json` when it exists and merge its
recognised keys over the defaults. Then load `.codex/planning.json` from the project root when it
exists, but allow it to override only `task_retries`, `review_iterations`,
`external_review_iterations`, and `finalize_enabled`.

`external_review_cmd` selects an executable and `plans_dir` selects files to edit and move. Both
may come only from the user-level file. Reject a project configuration containing either key with
an actionable error. Never execute a command or select a plan path from checked-out configuration.

Require integer iteration counts in these ranges: `task_retries` from 0 through 3, and
`review_iterations` and `external_review_iterations` from 0 through 10. Reject invalid types,
out-of-range counts, and an empty or non-string `plans_dir` with an actionable error. Do not
require a configuration file for the core workflow.

## Prompt overrides

Bundled prompts and agent instructions live under `skills/exec/references/`. Resolve every file
through this command before reading it:

```bash
bash <plugin-root>/skills/exec/scripts/resolve-file.sh prompts/task.md
bash <plugin-root>/skills/exec/scripts/resolve-file.sh agents/quality.txt
```

The script checks project overrides in `.codex/exec-plan/`, user overrides in
`${CODEX_HOME:-$HOME/.codex}/cc-thingz/planning/exec-plan/`, then the bundled copy.

Substitute every placeholder before passing a resolved prompt to a subagent. Common placeholders
are `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `DEFAULT_BRANCH`, `<plugin-root>`, `RESOLVE_SCRIPT`,
`PLUGIN_DATA_DIR`, and `USER_RULES`; phase prompts add `FINDINGS_LIST`, `REVIEW_PHASE`, or
`DIFF_COMMAND`. Set `PLUGIN_DATA_DIR` to
`${CODEX_HOME:-$HOME/.codex}/cc-thingz/planning/exec-plan`.

## Custom rules

Load planning rules at startup:

```bash
bash <plugin-root>/scripts/resolve-rules.sh planning-rules.md
```

When non-empty, substitute them as `ADDITIONAL CUSTOM RULES:\n<content>` for `USER_RULES`.
Otherwise substitute an empty string. Project rules at `.codex/planning-rules.md` take precedence
over `${CODEX_HOME:-$HOME/.codex}/cc-thingz/planning/planning-rules.md`.

## Step 1: Select and validate the plan

1. Use the argument path when supplied.
2. Otherwise list Markdown files under `plans_dir`, excluding `completed/`. Use the sole match
   automatically or ask the user to choose when several exist.
3. Read the plan in full. Reject missing files, malformed plans, and plans with no task checkboxes.
4. Verify that the plan's acceptance criteria and test commands are concrete enough to execute.

## Step 2: Detect repository state

Run:

```bash
bash <plugin-root>/skills/exec/scripts/detect-vcs.sh
bash <plugin-root>/skills/exec/scripts/detect-branch.sh
```

Record the VCS, default branch, current branch, and dirty working-tree state. Preserve unrelated
changes. Stop if the plan overlaps existing uncommitted changes that cannot be isolated safely.

## Step 3: Choose the workspace

For Git, ask once whether to use an isolated worktree or the current checkout. Recommend an
isolated worktree when starting from the default branch and the current checkout when already on a
feature branch. This question is mandatory because it changes where the user's work lives.

For an isolated worktree:

1. Derive the branch name without side effects:
   `bash <plugin-root>/skills/exec/scripts/create-branch.sh --print-name <plan-file-path>`.
2. Create a task-specific path outside the repository, under `/tmp`, with `git worktree add` and a
   new branch from the current HEAD. Validate the exact path before creation.
3. Continue all later commands in that worktree and record its absolute path.

For the current checkout, continue there. Mercurial has no bundled isolation workflow, so continue
in the current checkout and explain that limitation.

## Step 4: Create or retain the feature branch

In the current checkout, create a feature branch only when currently on the default branch:

```bash
bash <plugin-root>/skills/exec/scripts/create-branch.sh <plan-file-path>
```

Keep an existing feature branch unchanged. Never push during this skill.

## Step 5: Initialise progress

Derive `<plan-name>` from the plan filename and initialise:

```bash
bash <plugin-root>/skills/exec/scripts/init-progress.sh /tmp/progress-<plan-name>.txt <plan-file-path> <branch-name>
```

Use `append-progress.sh` for every later write. Report the progress path to the user.

## Step 6: Execute tasks sequentially

Repeat until no unchecked box remains in a `### Task N:` or `### Iteration N:` section:

1. Re-read the plan and select the first incomplete task.
2. Show the task title and its unchecked items.
3. Resolve `prompts/task.md`, substitute all placeholders, and launch exactly one implementation
   subagent with the available collaboration mechanism.
4. Wait for that subagent to finish, then re-read the plan and run the task's stated verification.
5. The task succeeds only when its checkboxes are marked and its discriminating tests pass.
6. If it fails, launch a fresh implementation subagent with the failure evidence. Retry up to
   `task_retries`; then stop and report the exact blocker.

Do not implement, debug, or edit code in the orchestrator during this loop. Later tasks may depend
on earlier ones, so never execute plan tasks in parallel. Maximum: 50 task iterations.

## Step 7: Review phase 1

Run a comprehensive review on iteration 1, then critical-only re-checks:

1. Resolve `prompts/review.md` as an orchestrator playbook.
2. For iteration 1, set `REVIEW_PHASE=comprehensive` and launch the quality, implementation,
   testing, simplification, and documentation reviewers. Start them concurrently up to the
   runtime's concurrency limit, filling free slots until all five finish.
3. On later iterations set `REVIEW_PHASE=critical` and launch only quality and implementation.
4. Preserve every reviewer's complete output. Log it and pass it unedited to a fixer subagent using
   `prompts/fixer.md`.
5. Re-run the relevant review after fixes. Stop early when all reviewers report no issues, or after
   `review_iterations` cycles.

## Step 8: Review phase 2

Resolve `agents/smells.txt` and run one code-smell reviewer. If it reports findings, pass its full
output to a fresh fixer subagent and verify the resulting changes. Log findings and fixes.

## Step 9: Review phase 3

Skip external review for Mercurial.

For Git, loop up to `external_review_iterations`:

1. Resolve `prompts/codex-review.md`; substitute `DIFF_COMMAND` as
   `git diff DEFAULT_BRANCH...HEAD` on every iteration so committed fixer changes remain visible.
2. Write the resolved prompt to `/tmp/external-review-<plan-name>.txt` using a safe file-writing
   tool so backticks and dollar signs remain literal.
3. Run `run-external-review.sh`, passing `external_review_cmd` as the first argument and the prompt
   contents as the second. An empty command uses Codex. Close stdin for a Codex subprocess.
4. If it exits 127 and stderr contains the script-owned `run-external-review:` marker, report the
   tool as unavailable and skip this phase. Treat any other non-zero exit as reviewer failure.
5. Treat empty output, or output with neither a `NO ISSUES FOUND` marker nor a `CRITICAL`, `MAJOR`,
   or `MINOR` tag, as reviewer failure.
6. Pass all valid findings to a fresh fixer subagent. Re-run when a whole-word `CRITICAL` or
   `MAJOR` finding was present; otherwise stop after applying and verifying minor fixes.

Never interpret an empty reviewer result as a clean review.

## Step 10: Review phase 4

Resolve `prompts/review.md` with `REVIEW_PHASE=critical`. Launch quality and implementation
reviewers concurrently, pass all findings to a fixer, and verify any fixes once.

## Step 11: Finalise

Skip for Mercurial or when `finalize_enabled` is false. Otherwise resolve `prompts/finalizer.md` and
launch one finaliser subagent to fetch, rebase on the current upstream default branch, clean up
commits, and run final validation. A conflict must be resolved safely or aborted cleanly. Never
push.

## Step 12: Complete terminal actions

1. Collect every progress line matching `grep -E '\[(decision|deviation)\]'` for the completion
   fallback. Timestamped lines place these markers after the timestamp. Say explicitly when none
   were logged.
2. Run `move-plan.sh` to move the plan into its sibling `completed/` directory and commit that move.
   Capture its output and exit status without hiding a failure.
3. Append `[completion] validation: <outcome>`, `[completion] branch: <name>`, and
   `[completion] plan move: <outcome>` to the progress file, then append `completed`.

## Step 13: Produce run summary

Resolve `prompts/stats.md` and launch one summary subagent after the terminal actions. It reads the
updated progress file and VCS state, not private session transcripts, and reports task counts,
review cycles, autonomous decisions, validation, plan-move outcome, and final branch statistics.
Show its complete output. This phase is best effort; if it fails, report the completion record and
the decisions or deviations collected in Step 12 instead.

## Invariants

- The plan file is the source of truth and is re-read after every subagent.
- One implementation task runs at a time; review work alone may run concurrently.
- Every subagent receives a self-contained prompt and must not ask the user questions.
- The orchestrator never filters findings before the fixer sees them.
- A check proves the change only when its failure condition is distinguishable.
- Preserve unrelated work, never push, and clean up only worktrees created by this run.
