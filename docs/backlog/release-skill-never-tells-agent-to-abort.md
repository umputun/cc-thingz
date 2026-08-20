---
worth: yes
where: plugins/release-tools/skills/new/SKILL.md:17
added: 2026-08-19
---
# the release skill documents only stdout values and never tells the agent to stop on a helper failure

The Scripts block at `SKILL.md:17-22` lists what each helper prints on stdout and nothing else — not that
they exit non-zero, not that the reason goes to stderr. `grep -n 'abort'` over the file returns exactly one
hit, the Edge Cases row at `:225`, and no step checks an exit status or says to stop. Step 3's own
prerequisite check has the same shape (`echo "error: uncommitted changes"` at `:55-57`, no abort), so there
is no stop instruction elsewhere in the file to pattern-match against.

The reachable case is our own Gitea. `detect-platform.sh:20-25` greps for `github\.com`, `gitlab\.` and
`gitea\.`; `git.umputun.com` matches none of them, and `glab repo view` on a Gitea remote fails, so line 29
fires with `error: unknown platform`. `$platform` is then empty, Step 6 calls `get-notes.sh ""` and gets
`error: platform required`, and the documented workflow still walks the agent to Step 8's preview with no
notes to improvise from.

Fix: one line in the Scripts block — the helpers exit non-zero and print the reason on stderr; if any of
Steps 2, 5 or 6 fails, report that text to the user and abort the workflow. It has to stop the run, not
just echo, since `:55-57` already shows the echo-without-abort shape.

Partly mitigated by PR #44: `var=$(cmd)` propagates the substitution's exit status, so the Bash tool now
surfaces both a non-zero code and the stderr text to the agent. Before that PR the error text was captured
*into* `$platform`, which was strictly worse.

Partly landed: the Scripts block now carries the exit-non-zero/abort line, added
alongside the `get-notes.sh` forge-CLI failure fix (the failure it describes became
reachable and loud there). Steps 2, 5 and the `:55-57` echo-without-abort shape are
untouched.

Open and unresolved: `plugins/release-tools/skills/last-tag/SKILL.md:20` says "**Important**: Avoid `$()`
command substitution in Bash tool - use sequential steps", while this skill's entire workflow is built on
`$()` captures. One plugin ships two contradictory conventions. If that note reflects a real limitation the
fix here is structural rather than a documentation line — the values may not reach the agent as `$platform`
/ `$new_version` / `$notes` at all. The exit-status propagation above argues the note is stale, but that was
not confirmed against the Bash tool's actual behavior.

Surfaced reviewing PR #44. `git blame` puts the Scripts block and `:55-57` at `a59bb1f5`; the PR touches
only lines 48, 72 and 85.
