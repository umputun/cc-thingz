# External review prompt

This is the prompt sent to the external review tool. Replace `DIFF_COMMAND`, `PLAN_FILE_PATH`, and `PROGRESS_FILE_PATH` before passing.

- Iteration 1: `DIFF_COMMAND` = `git diff DEFAULT_BRANCH...HEAD`
- Subsequent: `DIFF_COMMAND` = `git diff`

Step 9 of the exec skill is authoritative for how the script's exit codes are handled — do not restate the rules here. In particular a `127` is a skip only when the script's own stderr marker is present.

## Prompt

Review code changes. Run DIFF_COMMAND to see changes. Read source files for context. Read the plan at PLAN_FILE_PATH to understand the intent before evaluating findings — this lets you distinguish intentional design decisions from real defects. Read the progress file at PROGRESS_FILE_PATH for context on previous review iterations and fixes — re-evaluate all findings independently, previous fixes may be incomplete or wrong. Check for: bugs, security issues, race conditions, error handling, code quality.

Tag each finding with severity:
- CRITICAL: bugs causing crashes, data loss, security holes, race conditions
- MAJOR: real correctness issues — incorrect behavior, missing error handling, broken contracts
- MINOR: style, documentation drift, doc/code inconsistencies, nits, optional improvements

Format each finding on its own line as: `SEVERITY: file:line - description`.

If nothing found: NO ISSUES FOUND.
