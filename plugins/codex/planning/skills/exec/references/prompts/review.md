# Review fanout playbook

This file is a playbook for the main orchestrator, not a leaf subagent prompt. Resolve
`DEFAULT_BRANCH`, `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `REVIEW_PHASE`, and `RESOLVE_SCRIPT`
before following it.

Each reviewer is read-only. Include this preamble in every reviewer prompt:

```
CRITICAL: You are a READ-ONLY reviewer. Do not run git stash, git checkout, git reset, or any
command that modifies the working tree. Other reviewers may run concurrently. Use git diff, git
log, git show, and read-only file inspection.

Run `git diff DEFAULT_BRANCH...HEAD` to inspect the complete change. Read the source files for full
context and use PLAN_FILE_PATH for intended behaviour. Read PROGRESS_FILE_PATH for previous review
cycles, but re-evaluate the implementation independently.

Tag every finding with CRITICAL, MAJOR, or MINOR and format it as:
`SEVERITY: file:line - description`.
```

Severity meanings:

- `CRITICAL`: crashes, data loss, security vulnerabilities, or race conditions
- `MAJOR`: incorrect behaviour, missing error handling, or broken contracts
- `MINOR`: documentation drift, style, nits, and optional improvements

## Comprehensive mode

When `REVIEW_PHASE` is `comprehensive`, resolve these files before launching reviewers:

```bash
bash RESOLVE_SCRIPT agents/quality.txt
bash RESOLVE_SCRIPT agents/implementation.txt
bash RESOLVE_SCRIPT agents/testing.txt
bash RESOLVE_SCRIPT agents/simplification.txt
bash RESOLVE_SCRIPT agents/documentation.txt
```

Launch all five independent reviewers concurrently up to the runtime's concurrency limit. Fill
free slots until every reviewer has finished. Do not embed the diff in their prompts.

## Critical mode

When `REVIEW_PHASE` is `critical`, resolve only `agents/quality.txt` and
`agents/implementation.txt`. Add this instruction to their preamble:

```
Report only CRITICAL and MAJOR issues. Ignore style, optional improvements, and minor findings.
```

Launch both reviewers before waiting for either result.

## Collection

After all requested reviewers finish, produce a strict findings list:

- Group by `CRITICAL`, `MAJOR`, then `MINOR`; omit empty groups.
- Use `- <reviewer>: <file:line> - <description>` for each finding.
- Merge duplicate file, line, and issue findings while preserving both reviewer names.
- Do not verify, dismiss, or fix findings in this playbook. Pass the complete list to the fixer.
- End with `Total: <N> findings (<C> critical, <M> major, <m> minor)`.

For critical mode, drop minor findings. If neither reviewer reports a blocking issue, emit exactly:
`Critical re-check: clean - no critical/major findings.`
