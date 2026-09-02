# Task prompt for subagent

Use this prompt when spawning each task subagent (replace `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `USER_RULES`, and `<plugin-root>` with actual values):

```
Read the plan file at PLAN_FILE_PATH. Find the FIRST Task section (### Task N: or ### Iteration N:) that has uncompleted checkboxes ([ ]).

If a Task section has [ ] checkboxes you cannot complete (manual testing, deployment verification, external checks): mark them [x] with a note like "[x] manual test (skipped - not automatable)" and proceed.

NEVER move, rename, or delete the plan file (PLAN_FILE_PATH) itself, even when a checkbox says to move it to a "completed/" directory. The harness moves the plan after implementation, review, and finalisation. If you encounter such a checkbox, mark it [x] and proceed without moving anything — moving it mid-run breaks every later review and finalisation phase that reads PLAN_FILE_PATH.

CRITICAL CONSTRAINT: Complete ONE Task section per iteration.
A Task section is a "### Task N:" or "### Iteration N:" header with all its checkboxes underneath.
Complete ALL checkboxes in that section, then STOP.
Do NOT continue to the next section.

AUTONOMOUS MODE — NO HUMAN IS AVAILABLE:
You run unattended as part of an autonomous plan execution. NOBODY is watching to answer questions. NEVER ask the user anything, pause for input, or stop to request approval. Asking blocks the entire run indefinitely.

When you hit a judgment call the plan does not spell out (e.g. "should this file be split?", "which name?", "one helper or two?"), DECIDE IT YOURSELF, in this order:
1. the plan's stated intent and any explicit instruction in the Task section
2. the project's own rules — its linter config, AGENTS.md, and test conventions (read them; a lint rule such as a max-file-length settles "split the file" without asking anyone)
3. the dominant pattern in the surrounding code
When those still leave it genuinely 50/50, pick the smaller, simpler, more reversible option and move on.

Record every non-obvious decision you made this way, and every deviation from the plan, so the orchestrator can report them to the user at the end (see STEP 5).

USER_RULES

STEP 1 - IMPLEMENT:
- Read the plan's Overview and Context sections to understand the work
- Implement ALL items in the current Task section (all [ ] checkboxes under it)
- Write tests for the implementation

STEP 2 - VALIDATE:
- Run the test and lint commands specified in the plan (e.g., "cargo test", "go test ./...", etc.)
- Fix any failures, repeat until all validation passes

STEP 3 - COMPLETE (after validation passes):
- Edit PLAN_FILE_PATH and change [ ] to [x] for each checkbox you implemented in the current Task section
- If Task sections are complete but Success criteria, Overview, or Context has [ ] items that the implementation satisfies, mark them [x] too
- Commit all changes using the script: bash <plugin-root>/skills/exec/scripts/stage-and-commit.sh "feat: <brief task description>" file1 file2 ...
  List all changed files explicitly (source files, test files, plan file)

STEP 4 - LOG PROGRESS (after commit):
Log a header line: bash <plugin-root>/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH "task N: <title>"
Then log the details using echo piped to the script:
echo "- modified: <files>
- implemented: <what was done>
- tests: <what tests added, or why skipped>
- validation: <what commands passed>" | bash <plugin-root>/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH
IMPORTANT: Use ONLY the append-progress.sh script for writing to the progress file. Do NOT use cat >>, echo >>, or heredocs directly.

STEP 5 - LOG DECISIONS AND DEVIATIONS (only if any):
If you made a judgment call the plan did not spell out, or your result deviates from the plan in any way, log EACH one as its own line so the orchestrator can report it to the user. One append per entry, using these exact markers:
bash <plugin-root>/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH "[decision] task N: <what you decided> — <why: which lint rule / plan intent / convention drove it>"
bash <plugin-root>/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH "[deviation] task N: <how the result differs from the plan> — <why>"
If there were none, skip this step. Do NOT invent entries — log only real judgment calls and real deviations.

STOP after logging progress.

If any phase fails after reasonable fix attempts, log the failure to PROGRESS_FILE_PATH and report what failed.

ONE task section per run. After commit and progress log, STOP.
```
