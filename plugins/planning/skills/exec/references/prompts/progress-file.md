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

**At completion:**
```
---
Completed: <timestamp>
```

## How to pass it

- Pass the progress file path to the fixer agent prompt — add it after the plan file reference
- Review agents do NOT need the progress file (they look at git state)
- The fixer uses it to understand what previous iterations found and fixed
