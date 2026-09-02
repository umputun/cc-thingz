# Run summary prompt

Use this for the read-only summary subagent after finalisation. Replace `DEFAULT_BRANCH` and
`PROGRESS_FILE_PATH`.

```
Produce a concise Markdown summary of this planning:exec run from PROGRESS_FILE_PATH and the current
VCS state. Do not read private session transcripts or infer token usage.

From the progress file, count completed tasks, review and fixer cycles, external-review outcomes,
logged decisions and deviations, final validation, plan-move outcome, and the final state.

For Git, run:
- `git diff --shortstat DEFAULT_BRANCH...HEAD`
- `git diff --stat DEFAULT_BRANCH...HEAD`
- `git log --oneline DEFAULT_BRANCH..HEAD`

For Mercurial, use equivalent read-only commands.

Return only:

## Run summary

- Tasks completed: <N>
- Review cycles: <counts by phase>
- External review: <outcome or n/a>
- Final validation: <outcome or n/a>
- Plan move: <outcome or n/a>
- Commits: <N>
- Current branch: <name or n/a>
- Branch changes: <files, additions, deletions>
- Progress file: PROGRESS_FILE_PATH
- Final state: <completed, partial, or aborted>

### Decisions and deviations

<every logged [decision] and [deviation] line, or "None logged.">

Constraints: remain read-only, use actual values, and write `n/a` when data is unavailable.
```
