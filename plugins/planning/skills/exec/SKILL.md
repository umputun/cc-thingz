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

Always substitute: `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `DEFAULT_BRANCH`, `${CLAUDE_PLUGIN_ROOT}` (resolve to actual absolute path), `RESOLVE_SCRIPT` (absolute path to `${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/resolve-file.sh`), `PLUGIN_DATA_DIR` (resolved `${CLAUDE_PLUGIN_DATA}` path — passed as second argument to resolve-file.sh so it can find user overrides), `USER_RULES` (resolved custom rules content from the rules loading step, or empty string if no rules found), and phase-specific values (`FINDINGS_LIST`, `REVIEW_PHASE`, `DIFF_COMMAND`).

## Custom Rules Loading

Before starting execution, run this command via Bash tool to check for user-provided custom rules:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh planning-rules.md ${CLAUDE_PLUGIN_DATA}
```

If the output is non-empty, store it as the resolved custom rules content. When substituting `USER_RULES` in task prompts, wrap the content with a label so the subagent understands it: use "ADDITIONAL CUSTOM RULES:\n<content>" as the substitution. If the output is empty, substitute an empty string for `USER_RULES`. See `${CLAUDE_PLUGIN_ROOT}/references/custom-rules.md` for full documentation on the rules mechanism.

## Process

### Step 1. Resolve plan file

If `$ARGUMENTS` contains a file path, use it. Otherwise, list `.md` files in the `plans_dir` userConfig directory (default: `docs/plans/`), excluding `completed/`. If exactly one plan found, use it automatically. If multiple found, ask the user to pick one using AskUserQuestion.

Read the plan file. Count total Task sections (`### Task N:` or `### Iteration N:`) to know the scope.

Determine the default branch: `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/detect-branch.sh`

### Step 2. Ask about worktree isolation

Ask the user whether to run in an isolated git worktree or in the current working directory using AskUserQuestion:

- **Worktree** — creates an isolated copy of the repo, all work happens there. Clean separation from the main working directory. Best for long-running plans where you want to keep working in the main repo.
- **Current directory** — works directly in the current repo. Simpler, but blocks the working directory during execution.

If user chooses "Worktree", use `EnterWorktree` tool to create an isolated worktree before proceeding. All subsequent steps (branch creation, task execution, reviews, finalize) happen inside the worktree. At completion, report the worktree path and branch so the user can review and merge.

If user chooses "Current directory", proceed normally without worktree.

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

Update tasks as you go: `TaskUpdate(taskId, status="in_progress")` when starting, `TaskUpdate(taskId, status="completed")` when done.

### Step 4. Create branch

**MANDATORY**: Run the script below. Do NOT create the branch manually — the script strips the date prefix from the plan filename (e.g., `20260329-feature-name.md` → branch `feature-name`).

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
   - The task prompt from `prompts/task.md`, with all placeholders substituted as described in the Placeholder Substitution section above (including `USER_RULES`)
6. **After subagent returns**, re-read the plan file and check if that task's checkboxes are now `[x]`
   - If yes — task succeeded, continue loop
   - If no — **retry** with a fresh subagent for the same task up to `task_retries` times (userConfig, default: 1). If all retries fail, stop and report failure to user
7. **Report to user**: "Task N completed" (one line). The task subagent logs details to the progress file.

CRITICAL: Do NOT stop the loop based on subagent return text. The ONLY condition to stop is: no `[ ]` checkboxes remain in any Task section (`### Task N:` or `### Iteration N:`). Always re-read the plan file to check.

CRITICAL: You are the ORCHESTRATOR. Never read code, debug errors, investigate diagnostics, or fix issues yourself. If a subagent leaves problems (compiler errors, test failures, lint issues), retry with a fresh subagent — pass the error details in the prompt so it can fix them. All code work happens inside subagents, not in the orchestrator.

Maximum iterations safety limit: 50. If reached, stop and report to user.

### Step 7. Review phase 1 — comprehensive then critical re-check

After all tasks complete, run a comprehensive code review on iteration 1, then narrow to critical-only re-checks on subsequent iterations to verify the fixer's work without re-running the full heavy sweep.

Report to user: "--- Review phase 1: comprehensive ---"

Loop up to `review_iterations` times (userConfig, default: 5). Track the current iteration number:

1. **Spawn a review agent** — resolve `prompts/review.md` through the override chain. Launch one Agent tool call with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`, and the resolved prompt. Replace `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, and `${CLAUDE_PLUGIN_ROOT}`.
   - **Iteration 1**: set `REVIEW_PHASE` to `comprehensive`. The review agent launches 5 agents in parallel (quality, implementation, testing, simplification, documentation).
   - **Iteration 2 and later**: set `REVIEW_PHASE` to `critical`. The review agent launches 2 agents (quality, implementation) focused on critical/major issues only. Before this iteration, report to user: "--- Review phase 1: critical re-check (iteration N) ---"

2. **Collect findings** — pass the review agent's COMPLETE output (not a summary) to the fixer. Do NOT summarize, filter, or dismiss any findings. ALL findings are actionable. Report to user with a short list of findings. Log to progress file:
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file> "review phase 1: findings"`
   Then pipe: `echo "<findings>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file>`

3. **If ALL agents reported zero issues** → report "Review phase 1: clean" and proceed to the next phase.

4. **Spawn a fixer agent** — resolve `prompts/fixer.md` through the override chain. Launch with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`. Pass the FULL unedited review output as FINDINGS_LIST — the fixer decides what's real, not you.

5. **After fixer returns** → show the "FIXES:" section to the user. Report "Review phase 1: iteration N fixes applied". Loop back to step 1.

If `review_iterations` reached with issues still found, report "Review phase 1: max iterations reached, moving on" and continue.

### Step 8. Review phase 2 — code smells

Report to user: "--- Review phase 2: code smells analysis ---"

Run once (no loop):

1. **Spawn a smells agent** — resolve `agents/smells.txt` through the override chain. Launch one Agent tool call with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`, and the resolved agent prompt.

2. **Collect findings** — after the agent returns, report to user with a compact list of findings (one line per finding). Log findings to progress file:
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file> "review phase 2 smells: findings"`
   Then pipe the findings: `echo "<findings>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file>`

3. **If no issues found** → report "Smells analysis: clean" and proceed to the next phase.

4. **Spawn a fixer agent** — resolve `prompts/fixer.md` through the override chain. Launch with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`. Pass the FULL smells output as FINDINGS_LIST.

5. **After fixer returns** → report fixes to user. Proceed to the next phase.

### Step 9. Review phase 3 — codex external review

Report to user: "--- Review phase 3: codex external review ---"

Adversarial loop: codex reviews the code, fixer evaluates and fixes, codex re-reviews. Same fixer pattern as Claude reviews.

Determine the external review command:
- If `external_review_cmd` userConfig is set, use that command
- Else check if codex is available: `which codex`
- If neither is available, report "External review: skipped (no external tool available)" and proceed to step 10

Loop up to `external_review_iterations` times (userConfig, default: 10):

1. **Resolve the codex prompt** — read `prompts/codex-review.md` through the override chain. Replace `DIFF_COMMAND` (iteration 1: `git diff DEFAULT_BRANCH...HEAD`, subsequent: `git diff`) and `PROGRESS_FILE_PATH`. The progress file contains all previous review findings and fixer responses — codex reads it to avoid re-reporting fixed issues.

2. **Run codex** — `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/run-codex.sh "<resolved prompt>"` with `run_in_background: true`. You will be notified when done — do NOT poll or sleep.

3. **Check codex output** — if codex reports "NO ISSUES FOUND" or equivalent, phase is done. Proceed to step 10.

4. **Report codex findings to user** — show a compact list (one line per finding).

5. **Spawn a fixer agent** — same as other review phases. Resolve `prompts/fixer.md`, pass codex output as FINDINGS_LIST. Fixer verifies, fixes, commits, reports FIXES.

6. **Report fixer results to user** — show FIXES section. Log to progress file. Loop back to step 1.

If `external_review_iterations` reached, report "Codex review: max iterations reached, moving on" and continue.

### Step 10. Review phase 4 — critical only

Report to user: "--- Review phase 4: critical/major only (single pass) ---"

Same structure as step 7 but with `REVIEW_PHASE` set to `critical`. Resolve `prompts/review.md` through the override chain, spawn one review agent. The review agent launches 2 agents (quality, implementation) focusing on critical/major issues only. Same fixer flow — pass findings to fixer, show FIXES to user.

### Step 11. Finalize

Check `finalize_enabled` userConfig (default: true). If false, skip this step.

After all reviews pass, rebase and clean up commits.

Report to user: "--- Finalize: rebase and clean up commits ---"

Spawn one Agent tool call with `mode: "bypassPermissions"`, `subagent_type: "general-purpose"`, and the prompt from `prompts/finalizer.md`. Replace `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, and `PROGRESS_FILE_PATH`.

This is best-effort — if rebase fails, report the issue but don't block completion.

### Step 12. Completion

When finalize is done (or skipped on failure):
- Log completion to progress file: `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh <progress-file> "completed"`
- Report summary: "All N tasks completed, reviews passed, branch finalized"
- Do NOT move the plan file or push — just report completion

## Key rules

- Each subagent gets a fresh context — no accumulated state from previous tasks
- Parent session only tracks: task number, success/failure, retry count
- Plan file is the single source of truth for progress — always re-read it
- No signals — just checkboxes in the plan for task progress
- Maintain progress file (`/tmp/progress-<plan-name>.txt`) — see `prompts/progress-file.md` for format and when to write
- Do not modify the plan file yourself — only subagents modify it
- Do not implement or fix code yourself — only subagents implement and fix
- If a subagent fails or leaves broken code, re-run the loop — do NOT investigate or fix it yourself
- NEVER dismiss findings as "pre-existing", "not from changes", or "architectural" — ALL findings are actionable
- NEVER summarize or filter agent findings — pass the full output to the fixer agent verbatim
- All prompt and agent files MUST be resolved through the three-layer override chain before use
- All `subagent_type` values must be `general-purpose` — agent files provide the specialized prompt
- After reading a prompt file, substitute all placeholders before passing to subagent (see Placeholder Substitution)
