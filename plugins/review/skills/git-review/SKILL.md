---
name: git-review
description: Interactive git diff annotation review. Generates a cleaned-up diff, opens in editor for user annotations, and addresses feedback in a loop. Activates on "git review", "review changes", "review my changes", "annotate changes", "interactive review".
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Git Review

Interactive annotation-based code review using editor overlays.

## Activation Triggers

- "git review", "review changes", "review my changes"
- "annotate changes", "interactive review"
- "review diff", "annotate diff"

## How It Works

1. Script generates a cleaned-up diff file (friendly headers, no technical noise)
2. Opens in `$EDITOR` via tmux popup, kitty overlay, or wezterm split-pane
3. User adds annotations (comments, change requests) directly in the file
4. Script returns user's annotations as a git diff
5. Claude reads annotations, fixes code in the real repo
6. Script regenerates fresh diff (reflecting fixes), opens again
7. Loop until user closes editor without changes

## Workflow

### Step 1: Run the script

```bash
${CLAUDE_PLUGIN_ROOT}/skills/git-review/scripts/git-review.py [base_ref]
```

- No arguments: auto-detects uncommitted changes or branch vs default branch
- With argument: diffs against the specified ref (branch, tag, commit, `HEAD~3`)

### Step 2: Process annotations

If the script produces output (stdout), the user made annotations. The output is a
git diff showing what the user added/changed in the review file.

Read the diff carefully:
- **Added lines (+)**: user's annotations, comments, or change requests
- **Removed lines (-)**: user wants something removed or changed
- **Modified lines (- then +)**: user replaced text to show desired change

Each annotation is in context — the surrounding `===` file headers and diff content
show which file and code area the annotation refers to.

### Step 3: Plan changes

Enter plan mode (EnterPlanMode) to analyze annotations and design the fix approach:
- list each annotation and which file/code area it refers to
- describe the planned changes for each annotation
- get user approval before modifying any code

### Step 4: Address annotations

After plan approval, fix the actual source code in the real repository.
Each annotation is a directive — treat it as a code review comment that must be addressed.

### Step 5: Loop

After fixing code, run the script again. It regenerates a fresh diff reflecting
the fixes and opens the editor. The user can:
- Add more annotations → go back to step 2 (plan + fix again)
- Close without changes → review complete (no stdout output)

### Step 6: Done

When the script produces no output, the review is complete. Inform the user.

## Script Arguments

| Argument | Description |
|----------|-------------|
| (none) | auto-detect: uncommitted changes if present, otherwise branch vs default branch |
| `<ref>` | diff against specific ref: `master`, `main`, `HEAD~5`, `v1.2.0`, etc. |
| `--clean` | remove the review tracking repo from /tmp |
| `--test` | run embedded unit tests |

## Example Session

```
User: "review my changes"
→ run: git-review.py
→ editor opens with cleaned diff
→ user adds "this should validate input" next to a handler
→ user closes editor
→ stdout shows the annotation
→ enter plan mode: "annotation requests input validation in handler.go, plan: add validate() call"
→ user approves plan
→ Claude adds input validation to the handler
→ run: git-review.py (again)
→ editor opens with updated diff (validation now visible)
→ user closes without changes
→ no stdout → review complete
→ "review complete, all annotations addressed"
```

## Requirements

- tmux, kitty, or wezterm terminal (for editor overlay)
- `$EDITOR` set (defaults to micro)
- git
- kitty users: kitty.conf must have `allow_remote_control yes` and `listen_on unix:/tmp/kitty-$KITTY_PID`
