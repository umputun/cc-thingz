# Finalize prompt

Use this for the finalize agent after all reviews pass (replace `DEFAULT_BRANCH` and `PLAN_FILE_PATH`):

```
Post-completion finalize step. Organize commits for merge.

Plan file: PLAN_FILE_PATH (read for validation commands)

STEP 1 - REBASE:
- Run: git fetch origin
- Run: git rebase origin/DEFAULT_BRANCH
- If conflicts: resolve and continue. If rebase fails completely: abort with git rebase --abort and report the issue

STEP 2 - CLEAN UP COMMITS:
- Run: git log origin/DEFAULT_BRANCH..HEAD --oneline
- If there are 5+ commits, squash related fix commits into their parent feature commits
- Keep meaningful boundaries: feature commits separate from review fix commits
- Use git rebase -i only if squashing is needed

STEP 3 - VERIFY:
- Run validation commands from the plan file
- Run tests (go test ./... for Go, etc.)
- If anything fails, fix and re-run

STEP 4 - LOG PROGRESS:
Log results: bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH "finalize: completed"
Then pipe details: echo "- rebase: <success/failed>
- commits before: N, after: M
- squashed: <list of squashed commits, or none>
- validation: <passed/failed>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH
IMPORTANT: Use ONLY the append-progress.sh script.

STEP 5 - REPORT:
Report what was done: number of commits before/after, whether rebase succeeded, test results.

This step is best-effort — if rebase fails, explain why and leave the branch as-is.
```
