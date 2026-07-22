---
name: exec
description: "Execute plan tasks sequentially using subagents. Use when user says 'exec', 'execute plan', 'run plan', or wants to implement a plan file task by task with isolated subagents."
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash:*), Agent, AskUserQuestion, TaskCreate, TaskUpdate, EnterWorktree
---

# exec

Execute plan file tasks sequentially, each in an isolated subagent.

## Arguments

- `$ARGUMENTS` — path to plan file (optional; if omitted, ask user to pick from `plans_dir` userConfig directory, default: `docs/plans/`)

## File Resolution

ALWAYS use the resolve script to read prompt and agent files. NEVER construct the override chain manually:
```
bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/resolve-file.sh prompts/task.md ${CLAUDE_PLUGIN_DATA}
bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/resolve-file.sh agents/quality.txt ${CLAUDE_PLUGIN_DATA}
```
The script checks project overrides, user overrides, and bundled defaults automatically.

### Placeholder Substitution

After reading a prompt file, replace ALL placeholders with actual values before passing to a subagent. Subagents run in fresh contexts without plugin env vars.

Always substitute: `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `DEFAULT_BRANCH`, `${CLAUDE_PLUGIN_ROOT}` (resolve to actual absolute path), `RESOLVE_SCRIPT` (absolute path to `${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/resolve-file.sh`), `PLUGIN_DATA_DIR` (resolved `${CLAUDE_PLUGIN_DATA}` path — passed as second argument to resolve-file.sh so it can find user overrides), `USER_RULES` (resolved custom rules content from the rules loading step, or empty string if no rules found), `SUBAGENT_MODEL` (in `prompts/review.md`: the resolved `REVIEW_MODEL`, or empty string), and phase-specific values (`FINDINGS_LIST`, `REVIEW_PHASE`, `DIFF_COMMAND`).

## Custom Rules Loading

Before starting execution, run this command via Bash tool to check for user-provided custom rules:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh planning-rules.md ${CLAUDE_PLUGIN_DATA}
```

If the output is non-empty, store it as the resolved custom rules content. When substituting `USER_RULES` in task prompts, wrap the content with a label so the subagent understands it: use "ADDITIONAL CUSTOM RULES:\n<content>" as the substitution. If the output is empty, substitute an empty string for `USER_RULES`. See `${CLAUDE_PLUGIN_ROOT}/references/custom-rules.md` for full documentation on the rules mechanism.

## Subagent Model

Subagents split into two tiers, each with its own userConfig, both falling back to `subagent_model`:

- **work tier** — `work_model`, falling back to `subagent_model`. Applies to the task subagents (step 6), every fixer (steps 7-10), the finalizer (step 11), and the stats agent (step 12).
- **review tier** — `review_model`, falling back to `subagent_model`. Applies to the read-only review agents launched from `prompts/review.md` (steps 7 and 10) and the smells agent (step 8).

Resolve both once at the start: `WORK_MODEL` = `work_model` if non-empty else `subagent_model`; `REVIEW_MODEL` = `review_model` if non-empty else `subagent_model`. On each Agent tool call, pass `model: <resolved value for that tier>` when it is non-empty; omit `model` entirely when it is empty so the subagent inherits the orchestrator's model.

This lets the orchestrator run on a cheap/limited model while well-defined subagent work runs on a stronger one (e.g. orchestrator on Fable, subagents on Opus). It applies to Agent tool calls only — the external review in step 9 runs through `run-codex.sh` and is unaffected.

## Process

### Step 1. Resolve plan file

If `$ARGUMENTS` contains a file path, use it. Otherwise, list `.md` files in the `plans_dir` userConfig directory (default: `docs/plans/`), excluding `completed/`. If exactly one plan found, use it automatically. If multiple found, ask the user to pick one using AskUserQuestion.

Read the plan file. Count total Task sections (`### Task N:` or `### Iteration N:`) to know the scope.

Determine the default branch: `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/detect-branch.sh`

Note: in `hg` repos, detect-branch.sh returns `remote/<name>` (checking `master`, `main`, `trunk` in that order) in modern-Mercurial repos that expose upstream default via `remote/<name>` refs, and falls back to `default` in repos that use the traditional named-branch convention instead. The external-review prompt (`prompts/codex-review.md`) and the finalize prompt (`prompts/finalizer.md`) use git-specific commands and are not VCS-translated upstream. Both phases will be skipped (see step 9 and step 11, which re-detect VCS locally). Users who want hg-native review/finalize can override via `.claude/exec-plan/prompts/codex-review.md` and `.claude/exec-plan/prompts/finalizer.md` — any `git rebase origin/DEFAULT_BRANCH` in the bundled template must be replaced with the hg equivalent in the override, e.g. `hg rebase -d remote/master` when the repo exposes remote-tracking refs, or `hg rebase -d default` when it uses the traditional named-branch convention.

### Step 2. Ask about worktree isolation

**hg skip**: Detect VCS with `vcs=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/detect-vcs.sh)`. If `vcs` is `hg`, skip the worktree question and proceed in current directory. The `EnterWorktree` tool is git-only (wraps `git worktree add`) and has no hg equivalent upstream; users who want isolation in hg repos can use `hg share` manually before invoking `/exec`.

First detect current branch state — run `git branch --show-current` and compare with the default branch detected earlier (from `detect-branch.sh`). Two cases:

**Case A — currently on the default branch (master/main/trunk).** Step 4 will create a new feature branch. Ask the user where it should live. Invoke the **AskUserQuestion** tool with this payload:

```json
{
  "questions": [{
    "question": "Where should the feature branch be created?",
    "header": "Branch location",
    "options": [
      {"label": "Worktree (isolated)", "description": "Create the feature branch in a new isolated git worktree (under .claude/worktrees/). Main working directory stays on the default branch."},
      {"label": "In-place", "description": "Create the feature branch in this working directory. Main directory switches to the feature branch for the duration of the run."}
    ],
    "multiSelect": false
  }]
}
```

**Case B — currently on a feature branch.** Step 4 will keep using this branch. Ask whether to move it to an isolated worktree or stay here. Invoke the **AskUserQuestion** tool with this payload:

```json
{
  "questions": [{
    "question": "You're already on a feature branch. Run the plan here, or in an isolated worktree?",
    "header": "Isolation",
    "options": [
      {"label": "Stay here", "description": "Run the plan in this working directory, on the existing feature branch."},
      {"label": "Move to worktree", "description": "Copy this branch into a new isolated git worktree (under .claude/worktrees/). Main directory stays untouched."}
    ],
    "multiSelect": false
  }]
}
```

In BOTH cases: invoke the AskUserQuestion tool **now**, do not generate text first, do not skip, do not assume. Auto mode does NOT exempt this question — the choice affects the user's working directory and the orchestrator cannot decide on their behalf.

**If the user picks "Worktree (isolated)" or "Move to worktree"** — the main working directory MUST NOT be touched at all: no branch is created or checked out there, and no file changes land there. That isolation is the entire point of this mode. Set `worktree_mode = true` and do this:

1. Record the main tree's path and current branch so you can verify it stayed untouched: `main_tree=$(git rev-parse --show-toplevel)` and `main_branch=$(git branch --show-current)`.
2. Derive the feature branch name with NO git side effects: `name=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/create-branch.sh --print-name <plan-file-path>)`.
3. Create the isolated worktree with the `EnterWorktree` tool, passing `<name>` as the worktree name. It creates `.claude/worktrees/<name>/` on a new branch `worktree-<name>` forked from the current HEAD and switches the session into it. Capture the worktree's absolute path as `worktree_path`.
4. Drop the `worktree-` prefix so the branch is just `<name>`, operating on the worktree only: `git -C <worktree_path> branch -m <name>`.
5. **This means Step 4 (create-branch.sh) is SKIPPED** — the branch already exists inside the worktree. Running create-branch.sh here would `git checkout -b` in the main tree and break isolation.
6. **Isolation guard**: verify the main tree is untouched — `git -C "$main_tree" branch --show-current` MUST still equal `main_branch`. If it changed, STOP and report the isolation breach instead of continuing.
7. Every later step (task execution, reviews, finalize, stats, the plan move) runs inside the worktree; use `<name>` wherever a branch name is needed. At completion, report `worktree_path` and `<name>` so the user can review and merge.

**If the user picks "In-place" or "Stay here"** — set `worktree_mode = false` and proceed normally; Step 4 creates the branch in this working directory.

### Step 3. Create task list

ALWAYS create tasks using TaskCreate before starting any work. Create one task per plan Task section plus review phases:

For each `### Task N:` section in the plan:
- `TaskCreate(subject="Task N: <title>", description="<checkbox items>", activeForm="Executing task N...")`

Then add review tasks:
- `TaskCreate(subject="Review phase 1: comprehensive", description="5 parallel review agents + fixer", activeForm="Running review phase 1...")`
- `TaskCreate(subject="Review phase 2: code smells", description="smells agent + fixer", activeForm="Running smells review...")`
- `TaskCreate(subject="Review phase 3: codex external", description="adversarial codex/claude review loop", activeForm="Running codex review...")`
- `TaskCreate(subject="Review phase 4: critical only", description="2 review agents + fixer", activeForm="Running review phase 4...")`
- `TaskCreate(subject="Finalize", description="rebase, clean up commits, verify", activeForm="Finalizing...")`
- `TaskCreate(subject="Stats summary", description="aggregate token/duration/git stats from session log", activeForm="Summarizing stats...")`

Update tasks as you go: `TaskUpdate(taskId, status="in_progress")` when starting, `TaskUpdate(taskId, status="completed")` when done.

### Step 4. Create branch

**Skip this step entirely when `worktree_mode` is true** — Step 2 already created the branch (`<name>`) inside the isolated worktree, and running this here would `git checkout -b` in the main working tree and break isolation. Carry `<name>` forward as the branch name and go to Step 5.

Otherwise (in-place mode), **MANDATORY**: run the script below. Do NOT create the branch manually — the script strips the date prefix from the plan filename (e.g., `20260329-feature-name.md` → branch `feature-name`).

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/create-branch.sh <plan-file-path>
```

The script creates a feature branch if currently on main/master, or stays on the current branch if already on a feature branch. Capture and use the branch name it outputs.

### Step 5. Initialize progress file

Initialize the progress file: `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/init-progress.sh /tmp/progress-<plan-name>.txt <plan-file-path> <branch-name>` (derive `<plan-name>` from the plan file stem, e.g., `fix-issues.md` → `progress-fix-issues`). The script creates the file with a header. Report the full progress file path to the user.

IMPORTANT: Always use `${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh` to write to the progress file after initialization. Never write directly.

### Step 6. Task loop

Repeat until no `[ ]` checkboxes remain in any Task section:

1. **Re-read the plan file** (subagent modifies it each iteration)
2. **Find the first Task section** (`### Task N:` or `### Iteration N:`) that still has `[ ]` checkboxes
3. **If none found** — all tasks complete, go to step 7
4. **Announce the task to the user** — before spawning the subagent, output a visible summary:
   - Task number and title (from the `### Task N:` header)
   - List all `[ ]` checkbox items in that task section
   - Example output:
     ```
     --- Task 1: Fix error handling ---
     - [ ] Handle the error from os.ReadFile
     - [ ] Either log and exit or handle gracefully
     ```
5. **Spawn a subagent** using Agent tool with:
   - `mode: "bypassPermissions"`
   - `subagent_type: "general-purpose"`
   - `model: <WORK_MODEL>` when resolved non-empty (see Subagent Model)
   - The task prompt from `prompts/task.md`, with all placeholders substituted as described in the Placeholder Substitution section above (including `USER_RULES`)
6. **After subagent returns**, re-read the plan file and check if that task's checkboxes are now `[x]`
   - If yes — task succeeded, continue loop
   - If no — **retry** with a fresh subagent for the same task up to `task_retries` times (userConfig, default: 1). If all retries fail, stop and report failure to user
7. **Report to user**: "Task N completed" (one line). The task subagent logs details to the progress file.

CRITICAL: Spawn exactly ONE task subagent per iteration and WAIT for it to return before starting the next. NEVER batch-spawn multiple task subagents in a single message. Plan tasks are ordered and interdependent — later tasks build on the files earlier tasks create, and every task subagent edits the same plan-file checkboxes and overlapping source files, so running them in parallel corrupts the plan and the working tree. The "launch in a single message for parallel execution" instruction applies ONLY to the review phases (steps 7 and 10), never to this task loop.

CRITICAL: Do NOT stop the loop based on subagent return text. The ONLY condition to stop is: no `[ ]` checkboxes remain in any Task section (`### Task N:` or `### Iteration N:`). Always re-read the plan file to check.

CRITICAL: You are the ORCHESTRATOR. Never read code, debug errors, investigate diagnostics, or fix issues yourself. If a subagent leaves problems (compiler errors, test failures, lint issues), retry with a fresh subagent — pass the error details in the prompt so it can fix them. All code work happens inside subagents, not in the orchestrator.

Maximum iterations safety limit: 50. If reached, stop and report to user.

### Step 7. Review phase 1 — comprehensive then critical re-check

After all tasks complete, run a comprehensive code review on iteration 1, then narrow to critical-only re-checks on subsequent iterations to verify the fixer's work without re-running the full heavy sweep.

Report to user: "--- Review phase 1: comprehensive ---"

Loop up to `review_iterations` times (userConfig, default: 5). Track the current iteration number:

1. **Read review.md as a playbook (NOT as a subagent prompt)** — resolve `prompts/review.md` through the override chain and read it from this main session. It tells YOU (the orchestrator) which specialist agents to fan out for the current `REVIEW_PHASE`. Substitute `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `${CLAUDE_PLUGIN_ROOT}`, `REVIEW_PHASE`, and `SUBAGENT_MODEL` in the resolved content. Then follow the playbook FROM THIS SESSION: launch the specified Agent tool calls in a single message for parallel execution. Subagents do not have Agent tool access, so the fanout MUST be initiated from the main orchestrator.
   - **Iteration 1**: set `REVIEW_PHASE` to `comprehensive`. Per the playbook, launch 5 parallel review agents (quality, implementation, testing, simplification, documentation).
   - **Iteration 2 and later**: set `REVIEW_PHASE` to `critical`. Per the playbook, launch 2 parallel review agents (quality, implementation) focused on critical/major issues only. Before this iteration, report to user: "--- Review phase 1: critical re-check (iteration N) ---"

2. **Collect findings** — collect findings from ALL launched review agents. Pass the COMPLETE output (not a summary) to the fixer. Do NOT summarize, filter, or dismiss any findings. ALL findings are actionable. Report to user with a short list of findings. Log to progress file:
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file> "review phase 1: findings"`
   Then pipe: `echo "<findings>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file>`

3. **If ALL agents reported zero issues** → report "Review phase 1: clean" and proceed to the next phase.

4. **Spawn a fixer agent** — resolve `prompts/fixer.md` through the override chain. Launch with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`. Pass the FULL unedited review output as FINDINGS_LIST — the fixer decides what's real, not you.

5. **After fixer returns** → show the "FIXES:" section to the user. Report "Review phase 1: iteration N fixes applied". Loop back to step 1.

If `review_iterations` reached with issues still found, report "Review phase 1: max iterations reached, moving on" and continue.

### Step 8. Review phase 2 — code smells

Report to user: "--- Review phase 2: code smells analysis ---"

Run once (no loop):

1. **Spawn a smells agent** — resolve `agents/smells.txt` through the override chain. Launch one Agent tool call with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`, `model: <REVIEW_MODEL>` when non-empty, and the resolved agent prompt.

2. **Collect findings** — after the agent returns, report to user with a compact list of findings (one line per finding). Log findings to progress file:
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file> "review phase 2: findings"`
   Then pipe the findings: `echo "<findings>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file>`

3. **If no issues found** → report "Smells analysis: clean" and proceed to the next phase.

4. **Spawn a fixer agent** — resolve `prompts/fixer.md` through the override chain. Launch with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`. Pass the FULL smells output as FINDINGS_LIST.

5. **After fixer returns** → report fixes to user. Proceed to the next phase.

### Step 9. Review phase 3 — codex external review

**hg skip**: Detect VCS with `vcs=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/detect-vcs.sh)`. If `vcs` is `hg`, skip this entire step. Report to user: "hg detected — skipping external review (git-only). Override `prompts/codex-review.md` via `.claude/exec-plan/` to enable hg-native review." Proceed directly to step 10.

Report to user: "--- Review phase 3: codex external review ---"

Adversarial loop: codex reviews the code, fixer evaluates and fixes, codex re-reviews. The loop exits early once an iteration produces no `CRITICAL` or `MAJOR` findings — minor-only iterations still get fixed by the fixer, but no further codex round-trip happens. Subsequent phases (smells, critical-only) act as the final safety net.

Determine the external review command:
- If `external_review_cmd` userConfig is set, use that command
- Else check if codex is available: `which codex`
- If neither is available, report "External review: skipped (no external tool available)" and proceed to step 10

Loop up to `external_review_iterations` times (userConfig, default: 10):

1. **Resolve the codex prompt** — read `prompts/codex-review.md` through the override chain. Replace `DIFF_COMMAND` using `vcs=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/detect-vcs.sh)`: for `git`, iteration 1 is `git diff DEFAULT_BRANCH...HEAD` and subsequent iterations are `git diff`; for `hg`, iteration 1 is `hg diff -r 'ancestor(., DEFAULT_BRANCH)'` and subsequent iterations are `hg diff`. Also replace `PLAN_FILE_PATH` (so codex can read the plan for intent) and `PROGRESS_FILE_PATH` (so codex can read prior review iterations and fixer responses and avoid re-reporting fixed issues).

2. **Run codex** — `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/run-codex.sh "<resolved prompt>"` with `run_in_background: true`. You will be notified when done — do NOT poll or sleep.

3. **Check codex output** — if codex reports "NO ISSUES FOUND" or equivalent, phase is done. Proceed to step 10.

4. **Classify severity** — scan the codex output for `CRITICAL` or `MAJOR` markers (case-insensitive whole-word match). Set `has_blocking = true` if either is present, otherwise `has_blocking = false`. Findings without an explicit severity tag are treated as MINOR — `has_blocking` stays false in that case.

5. **Report codex findings to user** — show a compact list (one line per finding).

6. **Spawn a fixer agent** — same as other review phases. Resolve `prompts/fixer.md`, pass codex output as FINDINGS_LIST. Fixer verifies, fixes, commits, reports FIXES.

7. **Report fixer results to user** — show FIXES section. Log to progress file.

8. **Decide whether to loop**:
   - If `has_blocking` is false → report "Codex review: only minor findings — fixes applied, stopping loop" and proceed to step 10.
   - Otherwise → loop back to step 1.

If `external_review_iterations` reached with critical/major issues still found, report "Codex review: max iterations reached, moving on" and continue.

### Step 10. Review phase 4 — critical only

Report to user: "--- Review phase 4: critical/major only (single pass) ---"

Same structure as step 7 but with `REVIEW_PHASE` set to `critical`. Resolve `prompts/review.md` and follow its playbook FROM THIS MAIN SESSION — launch 2 parallel review agents (quality, implementation) focusing on critical/major issues only. Subagents do not have Agent tool access, so the fanout MUST be initiated from the main orchestrator. Same fixer flow — pass findings to fixer, show FIXES to user.

### Step 11. Finalize

**hg skip**: Detect VCS with `vcs=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/detect-vcs.sh)`. If `vcs` is `hg`, skip this entire step. Report to user: "hg detected — skipping finalize (git-only). Override `prompts/finalizer.md` via `.claude/exec-plan/` to enable hg-native finalize." Note that `DEFAULT_BRANCH` substitutes as whatever detect-branch.sh returned — `remote/master` (or `remote/main`/`remote/trunk`) in modern-Mercurial repos that expose remote-tracking refs, `default` in repos that use the traditional named-branch convention — so any `git rebase origin/DEFAULT_BRANCH` in the bundled template must be replaced with the hg equivalent (e.g. `hg rebase -d remote/master`, or `hg rebase -d default` in the named-branch case) in the override. Proceed directly to step 12.

Check `finalize_enabled` userConfig (default: true). If false, skip this step.

After all reviews pass, rebase and clean up commits.

Report to user: "--- Finalize: rebase and clean up commits ---"

Spawn one Agent tool call with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`, and the prompt from `prompts/finalizer.md`. Replace `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, and `PROGRESS_FILE_PATH`.

This is best-effort — if rebase fails, report the issue but don't block completion.

### Step 12. Stats summary

After finalize (or after step 11 was skipped on hg/disabled), spawn one Agent tool call with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`, and the prompt from `prompts/stats.md`. Replace `DEFAULT_BRANCH` and `PROGRESS_FILE_PATH` in the resolved content.

The stats agent reads this session's main log + subagent logs from `~/.claude/projects/<cwd-encoded>/`, aggregates per-phase token/duration/tool-use counts, runs `git diff --shortstat DEFAULT_BRANCH...HEAD` for branch churn, and returns a compact markdown report.

Show the stats agent's full markdown output to the user verbatim. Do NOT summarize it further — the agent already produces a tight summary.

This step is best-effort — if the stats agent fails or the session log path can't be resolved, report the failure but do not block completion.

### Step 13. Completion

When stats summary is done (or skipped on failure):
- **Report autonomous decisions and deviations to the user.** The run had no human to answer questions, so subagents decided judgment calls themselves and logged them. Collect every such entry from the progress file — `grep -E '^\[(decision|deviation)\]' <progress-file>` — and present them in a dedicated section titled **"Decisions made autonomously / Deviations from the plan"**, one bullet per entry with its stated reason, so the user learns every question the run answered on its own and why. If there are none, state "no autonomous decisions or deviations were logged." Do this regardless of whether finalize ran — finalize is skipped on hg or when disabled, so this is the guaranteed place the user always gets the report.
- Log completion to progress file: `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file> "completed"`
- Move the finished plan into its `completed/` subdirectory and commit it (best-effort): `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/move-plan.sh <plan-file-path>`. The script is a no-op when the plan is already under `completed/` or missing, derives the target as a `completed/` sibling of the plan's directory (so it respects a custom `plans_dir` and worktrees), and commits the move VCS-aware (git/hg). Do NOT push. If the script exits non-zero, report the failure but do not block completion.
- Report the final line "All N tasks completed, reviews passed, branch finalized". Append ", plan moved to completed/" ONLY when move-plan.sh actually moved the file (it printed `moved plan to ...`); omit the suffix when the move was a no-op (already under `completed/` or missing) or exited non-zero

## Key rules

- Each subagent gets a fresh context — no accumulated state from previous tasks
- Parent session only tracks: task number, success/failure, retry count
- Plan file is the single source of truth for progress — always re-read it
- No signals — just checkboxes in the plan for task progress
- Maintain progress file (`/tmp/progress-<plan-name>.txt`) — see `prompts/progress-file.md` for format and when to write
- Do not modify the plan file yourself during the task, review, and finalize phases — only subagents modify it. The sole exception is the terminal move in step 13 (after all phases finish), which the orchestrator performs via `move-plan.sh`
- Do not implement or fix code yourself — only subagents implement and fix
- If a subagent fails or leaves broken code, re-run the loop — do NOT investigate or fix it yourself
- NEVER dismiss findings as "pre-existing", "not from changes", or "architectural" — ALL findings are actionable
- NEVER summarize or filter agent findings — pass the full output to the fixer agent verbatim
- All prompt and agent files MUST be resolved through the three-layer override chain before use
- All `subagent_type` values must be `general-purpose` — agent files provide the specialized prompt
- Every Agent tool call passes `model` from its tier — `WORK_MODEL` for task/fixer/finalizer/stats, `REVIEW_MODEL` for review and smells agents — and omits `model` when the resolved value is empty (see Subagent Model)
- After reading a prompt file, substitute all placeholders before passing to subagent (see Placeholder Substitution)
- Subagents run with NO human available — they must NEVER ask the user a question (no AskUserQuestion, no pausing for input). They decide judgment calls the plan does not settle from the project's lint rules, CLAUDE.md, and code conventions, and log each as a `[decision]`/`[deviation]` line for the completion report
- In worktree mode (`worktree_mode = true`) the main working directory is never touched — no branch is created or checked out there and no changes land there; all git operations run inside the worktree, and Step 4's create-branch.sh is skipped
