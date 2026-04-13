# Task prompt for subagent

Use this prompt when spawning each task subagent (replace `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `USER_RULES`, and `${CLAUDE_PLUGIN_ROOT}` with actual values):

```
Read the plan file at PLAN_FILE_PATH. Find the FIRST Task section (### Task N: or ### Iteration N:) that has uncompleted checkboxes ([ ]).

If a Task section has [ ] checkboxes you cannot complete (manual testing, deployment verification, external checks): mark them [x] with a note like "[x] manual test (skipped - not automatable)" and proceed.

CRITICAL CONSTRAINT: Complete ONE Task section per iteration.
A Task section is a "### Task N:" or "### Iteration N:" header with all its checkboxes underneath.
Complete ALL checkboxes in that section, then STOP.
Do NOT continue to the next section.

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
- Commit all changes using the script: bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/stage-and-commit.sh "feat: <brief task description>" file1 file2 ...
  List all changed files explicitly (source files, test files, plan file)

STEP 4 - LOG PROGRESS (after commit):
Log a header line: bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH "task N: <title>"
Then log the details using echo piped to the script:
echo "- modified: <files>
- implemented: <what was done>
- tests: <what tests added, or why skipped>
- validation: <what commands passed>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH
IMPORTANT: Use ONLY the append-progress.sh script for writing to the progress file. Do NOT use cat >>, echo >>, or heredocs directly.

STOP after logging progress.

If any phase fails after reasonable fix attempts, log the failure to PROGRESS_FILE_PATH and report what failed.

ONE task section per run. After commit and progress log, STOP.
```
