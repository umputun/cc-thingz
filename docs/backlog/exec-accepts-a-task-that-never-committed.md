---
worth: later
where: plugins/planning/skills/exec/SKILL.md
added: 2026-08-20
---
# exec accepts a task as complete without checking that its commit succeeded

A task subagent edits files, ticks its checkboxes in the plan, and calls `stage-and-commit.sh`. If that
commit fails, the task's work stays in the working tree and its ticked checkboxes stay in the plan file.
The orchestrator reads the checkboxes as the success signal and starts the next task, which edits the same
plan file, lists it among its own changed files, and commits both tasks' checkbox changes under its own
message.

Scoping the commit to its file list (#46, PR #48) does not fix this. That fix stops a *disjoint* file being
swept in, and it works: after a rejected commit the failed task's files stay staged and the next call
commits only its own. But both tasks genuinely change the same plan file, so the second task's commit
legitimately includes it, carrying the first task's ticks along. The overlap is in the working tree, not in
the index, and nothing inside the commit helper can see it.

The same applies to any source file two tasks both touch, which is why per-task commits cannot be trusted
as a record of what one task changed whenever a commit has failed earlier in the run.

The fix belongs in the orchestrator: either fail-stop the run when `stage-and-commit.sh` exits non-zero, or
verify HEAD advanced before accepting a task as complete and moving on. Deferred because it changes the
autonomous run's failure behaviour, which wants deciding on its own rather than inside a commit-helper fix.

Surfaced by codex while vetting the #46 fix.
