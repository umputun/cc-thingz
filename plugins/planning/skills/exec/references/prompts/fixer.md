# Fixer prompt

Use this for the fixer agent after collecting review findings (replace `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH` and `FINDINGS_LIST`):

```
Code review found the following issues. Verify and fix them.

Plan file: PLAN_FILE_PATH (read it to find validation commands in the "## Validation Commands" section)
Progress file: PROGRESS_FILE_PATH (read it for context on what previous iterations found and fixed)

FINDINGS:
FINDINGS_LIST

STEP 1 - VERIFY:
For each finding, read the actual code at the specified file:line. Check 20-30 lines of context. Classify as:
- CONFIRMED: real issue, fix it
- FALSE POSITIVE: doesn't exist or already mitigated, discard

STEP 2 - FIX:
- Fix all confirmed issues (including adding missing tests if flagged)

STEP 3 - VALIDATE (MANDATORY — code MUST compile and tests MUST pass before commit):
- Build, test, and run validation commands from PLAN_FILE_PATH
- If anything fails: fix it and re-run everything
- NEVER commit broken code

STEP 4 - COMMIT (only after STEP 3 passes with zero errors):
- Commit fixes: bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/stage-and-commit.sh "fix: address code review findings" <changed-files>

STEP 5 - LOG PROGRESS (after commit):
Log details: echo "- confirmed: <list>
- false positives: <list>
- fixes: <what changed>
- validation: <what passed>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH
IMPORTANT: Use ONLY the append-progress.sh script. Do NOT use cat >>, echo >>, or heredocs directly.

STEP 6 - REPORT (MANDATORY — this is your return value to the parent):
Your final response MUST include a structured summary starting with "FIXES:" on its own line, followed by one line per fix:
FIXES:
- fixed: <file>:<line> — <what was fixed>
- fixed: <file>:<line> — <what was fixed>
- false positive: <description> — <why discarded>

This report is shown to the user. Be specific about what changed.
```
