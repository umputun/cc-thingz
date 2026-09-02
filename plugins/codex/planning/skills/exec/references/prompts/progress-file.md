# Progress file

The parent maintains a progress file at `/tmp/progress-<plan-name>.txt` (derived from plan file stem, e.g., `fix-issues.md` → `/tmp/progress-fix-issues.txt`). This file accumulates context across all phases so review agents and the fixer can see what happened before them.

## When to write

The parent appends to the progress file at these points using `append-progress.sh` (do not use `cat >>` or direct writes; always append via the script):

**At start:**
```
# progress
Plan: <plan-file-path>
Branch: <branch-name>
Started: <timestamp>
---
```

**After each task completes:**
```
[task] Task N: <title> — completed
```

**After each task fails:**
```
[task] Task N: <title> — FAILED (retry N)
```

**Before review phase:**
```
--- review phase N: <type> ---
```

**After review agents return (before fixer):**
```
[review] iteration N findings:
<full agent output pasted here>
```

**After fixer completes:**
```
[fixer] iteration N: <fixer's report of what was fixed/discarded>
```

**Whenever a subagent makes an autonomous judgment call or deviates from the plan** (the task and fixer subagents write these directly, one line per entry, since no human is available to ask):
```
[decision] task N: <what was decided> — <why: lint rule / plan intent / convention>
[deviation] task N: <how the result differs from the plan> — <why>
```
The orchestrator greps these markers at completion and reports them to the user (see the exec SKILL completion step), so the user learns every question the run answered on its own and why.
`append-progress.sh` prefixes these entries with a timestamp, so the completion collector matches the
markers anywhere on the line.

**After terminal completion actions:**
```
[completion] validation: <outcome>
[completion] branch: <name>
[completion] plan move: <outcome>
completed
```

## How to pass it

- Pass the progress file path to the fixer agent prompt — add it after the plan file reference
- Review agents do NOT need the progress file (they look at repository state)
- The fixer uses it to understand what previous iterations found and fixed
