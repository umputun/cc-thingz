# Codex external review

## Codex command

Write the review prompt to a temp file, then run codex via the script:

1. Write this prompt to a temp file (replace `DIFF_COMMAND` and `PREVIOUS_CONTEXT`):
   ```
   Review code changes. Run DIFF_COMMAND to see changes. Read source files for context. Check for: bugs, security issues, race conditions, error handling, code quality. Report as: file:line - description. If nothing found: NO ISSUES FOUND. PREVIOUS_CONTEXT
   ```

2. Run: `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/run-codex.sh <prompt-file>`
   The script runs codex synchronously with a 10-minute timeout and outputs the response.

- Iteration 1: `DIFF_COMMAND` = `git diff DEFAULT_BRANCH...HEAD` (full branch diff)
- Subsequent iterations: `DIFF_COMMAND` = `git diff` (working tree only)
- `PREVIOUS_CONTEXT` is empty on iteration 1; on subsequent iterations it becomes: "Claude responded to your previous findings: <evaluator response> — re-evaluate considering Claude's counter-arguments."

If `codex` is not installed (command not found), skip this phase entirely and report "codex not available, skipping external review".

## Evaluator prompt

Use this for the Claude evaluator agent after codex returns (replace `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, and `CODEX_OUTPUT`):

```
Codex (GPT-5) reviewed the code and reported these findings. Evaluate each one critically.

Plan file: PLAN_FILE_PATH (read for validation commands)
Progress file: PROGRESS_FILE_PATH (read for context)

CODEX FINDINGS:
CODEX_OUTPUT

For EACH finding:
1. Read the actual code at the specified file:line
2. Check 20-30 lines of context, trace callers if needed
3. Classify as:
   - CONFIRMED: real issue, fix it
   - FALSE POSITIVE: explain why (intentional design, already mitigated, etc.)

After evaluation:
- Fix all confirmed issues
- Run validation commands from the plan file — ALL must pass
- If fixes made: commit with bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/stage-and-commit.sh "fix: address codex review findings" <changed-files>
- Log to progress file:
  bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH "codex evaluator: iteration N"
  then pipe details: echo "- confirmed: <list>
  - false positives: <list>
  - fixes: <what changed>" | bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/append-progress.sh PROGRESS_FILE_PATH
  IMPORTANT: Use ONLY the append-progress.sh script.

Your response MUST include:
FIXES:
- fixed: <file>:<line> — <what was fixed>
- false positive: <description> — <why rejected>

Your explanations for false positives will be passed back to codex as context for the next review iteration.
IMPORTANT: Do NOT run codex yourself. The parent orchestrates codex execution.
```
