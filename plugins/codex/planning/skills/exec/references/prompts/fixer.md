# Fixer prompt

Use this for the fixer agent after collecting review findings (replace `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH` and `FINDINGS_LIST`):

```
Code review found the following issues. Verify and fix them.

Plan file: PLAN_FILE_PATH (read it to find validation commands in the "## Validation Commands" section)
Progress file: PROGRESS_FILE_PATH (read it for context on what previous iterations found and fixed)

FINDINGS:
FINDINGS_LIST

AUTONOMOUS MODE — NO HUMAN IS AVAILABLE:
You run unattended. NOBODY is watching to answer questions. NEVER ask the user anything or pause for input or approval. Asking blocks the entire run. When a fix involves a judgment call the finding does not settle, decide it yourself from the project's lint rules, AGENTS.md, and the surrounding code's dominant pattern; when genuinely 50/50, take the smaller, more reversible option. Record any non-obvious decision or plan deviation in STEP 5.

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
- Commit fixes: bash <plugin-root>/skills/exec/scripts/stage-and-commit.sh "fix: address code review findings" <changed-files>

STEP 5 - LOG PROGRESS (after commit):
Log details: echo "- confirmed: <list>
- false positives: <list>
- fixes: <what changed>
- validation: <what passed>" | bash <plugin-root>/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH
IMPORTANT: Use ONLY the append-progress.sh script. Do NOT use cat >>, echo >>, or heredocs directly.
If you made any judgment call the finding did not settle, or deviated from the plan, log each as its own line so the orchestrator can report it to the user (one append per entry):
bash <plugin-root>/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH "[decision] fixer: <what you decided> — <why>"
bash <plugin-root>/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH "[deviation] fixer: <how it differs from the plan> — <why>"

STEP 6 - REPORT (MANDATORY — this is your return value to the parent):
Your final response MUST include a structured summary starting with "FIXES:" on its own line, followed by one line per fix:
FIXES:
- fixed: <file>:<line> — <what was fixed>
- fixed: <file>:<line> — <what was fixed>
- false positive: <description> — <why discarded>

This report is shown to the user. Be specific about what changed.
```
