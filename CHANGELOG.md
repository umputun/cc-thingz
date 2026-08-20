# Changelog

This repo ships independent Claude Code plugins. Version headings use values from `plugins/<name>/.claude-plugin/plugin.json`; they are not git tags.

Entries are sorted by plugin version date, newest first.

## workflow v1.3.0 - 2026-08-23

### New Features

- `/workflow:backlog --all` walks every item in the backlog to a disposition, one at a time: brief the item, ask about it alone, carry out the answer, then move to the next. Blockers and relationships between items are worked out before the first question, so a prerequisite is asked about before whatever it unblocks
- Both argument forms now brief an item before asking about it — a summary in the agent's own words, then the effort, blast radius, and materiality, each one line carrying the fact behind it. The call is made against the repo as it stands rather than against the item's own account, which goes stale the same way its `where` does

### Bug Fixes

- `/workflow:backlog` no longer treats `where` as a dedupe key. The path and the slug find the candidates and the claimed defect settles it, so one file holding several unrelated defects no longer collapses them into one item, and a line that moved no longer hides an existing item from the next reviewer

## workflow v1.2.0 - 2026-08-22

### New Features

- `/workflow:backlog` reads, works, and maintains a repo's deferred-work items in `docs/backlog/` — one markdown file per item, `worth`/`where`/`added` frontmatter, and a create-then-delete lifecycle where the item is removed in the commit that lands its fix. Listing verifies each item's `where` against the current tree and reports a stale anchor as stale rather than as work; appending dedupes on `where` then slug, and refuses to write into a branch other than the repository default without asking

## release-tools v2.0.8 - 2026-08-21

### Other

- corrects two claims that `tea` cannot supply merged-PR metadata. Only `tea pr list` cannot: neither its seven default fields nor the full set of twenty-one values accepted by `--fields` includes a merged flag or a merge timestamp. `tea api` does return them, which the same comment in `get-notes.sh` already said five lines further down

## release-tools v2.0.7 - 2026-08-21

### Bug Fixes

- `get-notes.sh` no longer publishes a silently truncated PR list as complete release notes. GitHub starts with 50 merged PRs and doubles the requested limit until the response is shorter than the request; GitLab requests explicit 100-item pages until the final short page. Both paths keep the existing checked forge and `jq` failures
- the release workflow creates and pushes an annotated tag before the forge release call. Forge-created tags were lightweight, so their `creatordate` was the target commit's committer date rather than the release time. A PR merged after that commit but before the release was therefore listed again in the next release

### Other

- `tests/test-release-tools.sh` covers a 51-item GitHub result, a 101-item GitLab result, the exact page requests, and the annotated-tag ordering. Each assertion fails when its corresponding pagination or tag step is removed

## release-tools v2.0.6 - 2026-08-21

### Bug Fixes

- `get-notes.sh` no longer aborts every Gitea release. The v2.0.5 exit-status check made a pre-existing defect fatal: `tea pr list --state merged` is invalid, since `--state` accepts only `all`, `open` or `closed`, so the new guard fired on every Gitea run and no release could be produced at all. Before that check the failure was swallowed and the script fell through to commit-derived notes, which is degraded but usable. The Gitea arm now skips the forge call entirely, warns on stderr that PR metadata is unavailable, and returns those commit-derived notes. GitHub and GitLab keep the strict abort
- `tests/test-release-tools.sh` drops the Gitea fixture, which asserted a JSON shape `tea pr list` cannot produce. That output serializes the printable table, so every value is a flat string: there is no `merged` field and no `user.login`, and the test passed over an arm that had never worked. Gitea also leaves the failing-CLI matrix, since it no longer invokes a CLI, and gains a test asserting the warning, a zero exit, commit entries in the output, and that `tea` is never called

### Other

- `SKILL.md` documents the Gitea limitation so the agent treats the warning as expected rather than as a failure to abort on. Collecting real merged-PR metadata on Gitea needs `tea api /repos/{owner}/{repo}/pulls?state=closed`, whose raw REST payload does carry `merged`, `merged_at`, `number` and `user.login`; that needs a `tea` version floor, a pagination policy and verification against a live instance, so it is left for separate work
## planning v3.10.0 - 2026-08-20

### Bug Fixes

- exec: review phase 3 no longer dies on installs that never configured `external_review_cmd`. Claude Code substitutes `${user_config.KEY}` into skill content through a different path than hooks and MCP config: the skill path reads only values saved in `settings.json` and never merges in the schema `default`, and for an unset key it leaves the `${user_config....}` reference in the text verbatim. Double-quoted in the command line, that made bash abort the whole call with `bad substitution`, which step 9 reported as `External review: reviewer failed (exit 1)` — so the phase was dead for anyone who had not been through `/plugin configure`. The token is now single-quoted, and `run-external-review.sh` recognises a literal `${user_config.*}` value as unconfigured and takes the codex fallback with a note on stderr. Single-quoting also makes a configured value's own `$` and backticks inert, so the only character it cannot carry is `'`
- exec: the `external_review_cmd` setting now actually reaches the external review call. It was declared in `plugin.json` and documented in the README, but step 9 of the exec skill routed unconditionally to `run-codex.sh`, which hardcodes `codex` and accepts only a prompt argument, so a configured command was never used. Review phase 3 now goes through a new `run-external-review.sh` that takes the setting as its first argument and falls back to codex when it is empty, and the exec skill passes the value through Claude Code's `${user_config.external_review_cmd}` substitution rather than a placeholder token the orchestrator had no way to resolve. Fixes #42
- exec: user-level prompt and agent overrides no longer pin themselves at the version installed. A `SessionStart` hook eagerly copied all seven prompts and six agent files into `$CLAUDE_PLUGIN_DATA` on first run, and only when absent, so every install became a full-shadow install whose copies silently outranked bundled defaults forever. Twelve later fixes to those files never reached anyone seeded before them. The hook has been removed; `resolve-file.sh` already falls through to bundled defaults. Fixes #42

### New Features

- exec: `run-external-review.sh` defines a contract for third-party review tools — the prompt arrives as the final argument, findings go to stdout tagged `CRITICAL`/`MAJOR`/`MINOR`, the tool sandboxes itself, and exit code `127` means "not installed", which makes the run skip the phase rather than report a review failure. An unset or whitespace-only setting takes the codex fallback, so a stray space in the config cannot silently skip the review phase
- exec: `customize-file.sh` refuses to write through a symlinked directory component. The existing check covered the destination file, but any ancestor directory could be a symlink too — `mkdir -p` accepts it and `cp` follows it, so a repository shipping a `.claude/exec-plan/prompts` symlink got the bundled content written wherever it pointed. Components at or below the override root are checked; the data dir itself is not, since a symlinked `$HOME` or `~/.claude` is a legitimate setup. The data-dir argument is normalized first — every trailing slash is stripped, not just one, because a leftover slash kept the walk from ever matching the override root: it ran past it and rejected the legitimate symlink above, or, for a relative data dir, spun on `.` forever. `/` normalizes to empty and is rejected rather than silently downgraded to a project-level copy
- exec: `customize-file.sh` copies a bundled prompt or agent file into a project-level or user-level override path on demand, so only files someone intends to edit become overrides. It refuses to overwrite an existing override, including a dangling symlink that would otherwise be followed outside the override directory, and rejects absolute or traversing paths. A passed-but-empty data directory is reported rather than silently downgraded to a project-level copy

### Improvements

- exec: review phase 3 wording is no longer codex-specific, since the phase can now run a different tool. Progress messages say "external review" instead of "codex review", and the stats report follows: its severity-exit and fixer-iteration lines no longer say "Codex", and its phase-grouping table recognises the `Fixer - external review` description that step 9 now prescribes — previously a phase-3 fixer matched no group and its tokens and duration dropped out of the report entirely
- exec: the review prompt is written to a file and passed as `"$(cat …)"` rather than pasted inline into the command line. The bundled prompt asks for findings formatted as `` `SEVERITY: file:line - description` ``, and those backticks were command substitutions in the double-quoted argument — the reviewer received the format instruction blanked out. Step 9 now also names the write mechanism: the file goes out through the Write tool, because `echo "…" >` or a heredoc with an unquoted delimiter expands the same backticks at write time and puts the damage in the file instead of the command line
- exec: the `NO ISSUES FOUND` marker no longer short-circuits the severity scan. Step 9 checked for the marker first and ended the phase on a hit, so a reviewer that echoed the phrase while also reporting a `CRITICAL` — the phrase is part of the instruction its own prompt gives it, which is exactly the text an LLM tends to repeat back — made the phase report clean, skipped the fixer, and dropped the finding. The scan now runs first and the marker counts as clean only when it finds no `CRITICAL` or `MAJOR`
- exec: `run-external-review.sh` rejects a multi-line `external_review_cmd` instead of running its first line, which is all the single `read` ever saw
- exec: a reviewer that runs and fails is no longer reported as a clean review. Only exit `127` means "tool not available"; any other non-zero exit is reported as a reviewer failure instead of falling through the severity scan with empty output and reporting "only minor findings". An exit `0` with nothing on stdout is a reviewer failure too — a reviewer that produced no output has failed regardless of its exit code — and a clean result now requires the explicit `NO ISSUES FOUND` marker the contract makes mandatory, rather than that marker "or equivalent". Together those close the hole where a tool that exited successfully without reviewing anything was reported as a clean review
- exec: `codex-review.md` no longer carries its own weaker copy of the exit-code rule. Its header still said "if the script exits 127, no external review tool is available — skip this phase", which is exactly the silent skip the marker check was added to prevent, and the orchestrator resolves and reads that file on every iteration. It now defers to step 9 of the exec skill, the same single-sourcing already applied to the contract in the script header
- exec: `run-codex.sh` execs codex instead of leaving a wrapper shell in between, so a kill on the background task reaches the reviewer on the codex path too — which is what `run-external-review.sh`'s own exec chain already assumed
- exec: step 9's "no output" rule matches what the orchestrator can actually see. It asked for a check on empty *stdout*, but the script inherits both streams and the tool result merges them, so a reviewer whose only output was progress chatter on stderr passed the check and its chatter went to the fixer as findings. The rule now covers the combined text
- exec: the skip and failure messages quote the reason the script printed to stderr, so a missing configured command and a missing codex are distinguishable. Both of those messages now carry a `run-external-review:` marker, and review phase 3 treats a `127` as "skip the phase" only when that marker is present — a `127` raised by the reviewer itself, such as a wrapper script whose own inner tool is missing, is reported as a reviewer failure instead of silently skipping the review
- added `tests/test-planning-external-review.sh` covering command routing, flag handling, stdin isolation, the codex fallback, exit codes, and override copying
- the bundled-fallback test compares resolved content instead of checking non-emptiness, which the error-capture fallback value satisfied unconditionally
- exec: the external review contract now has exactly one authoritative description. It was stated twice — in `README.md` and in the `run-external-review.sh` header — and the two copies had already drifted apart. The script header now names the README as authoritative and keeps only what a reader of the script needs on the spot: the argument order and the `127` convention. The README gained the two requirements neither copy carried — the tool must be able to run shell commands and read files in the working tree (the prompt tells it to run a diff and read the plan, the progress file, and sources, so a plain text-in/text-out LLM CLI satisfies every other bullet and reviews nothing), and it must read nothing from stdin, which the script redirects from `/dev/null`
- `references/usage.md` no longer carries its own copy of the customization commands. Nothing loads that file as skill content, so `${CLAUDE_PLUGIN_ROOT}` never expanded there and the block told the reader to run `bash /skills/exec/scripts/customize-file.sh`. It now points at the README section that carries the runnable, spelled-out form
- the README documents that `external_review_cmd` is shell-parsed before `run-external-review.sh` sees it, since Claude Code substitutes the value into the command line that launches the script — it lands inside single quotes, so `"`, `$`, backtick and `\` are inert, spaces and `;` are safe, and the only character it cannot carry is a literal `'`. Not exploitable by a checked-out repository: plugin config comes from user, flag, and policy settings only, never from project settings
- the prompt-quoting assertions can now fail. They passed the single token `THE-PROMPT`, for which the quoted and unquoted `exec` forms are byte-identical; with a multi-word prompt they discriminate, and both the direct and the codex-fallback paths were mutation-tested to confirm they go red when the quoting is removed
- test helpers no longer collide across suites. `report` is renamed `assert_output`, matching the sibling suites, and the command-running `assert_rc` is renamed `assert_exit_rc` so it cannot be mistaken for `test-planning-disable-review.sh`'s `assert_rc <name> <expected> <actual>`, which compares two values instead of running a command

### Other

- Upgrading from an earlier version: files already seeded into `$CLAUDE_PLUGIN_DATA/prompts/` and `$CLAUDE_PLUGIN_DATA/agents/` still take precedence and will not be refreshed automatically. Delete the ones you never edited to pick up current bundled defaults; the directory path is under `~/.claude/plugins/data/`

## planning v3.9.1 - 2026-08-20

### Bug Fixes

- exec: `stage-and-commit.sh` no longer commits files outside the list it was given. The git arm ran `git add -- <files>` and then a bare `git commit`, which commits the whole index, so anything staged before the call was swept in — per-task commits stopped being a record of what the task changed, and a rejected commit left its own files staged for the next call to carry into an unrelated commit under the wrong message. The commit is now scoped to the listed paths, matching what the hg arm already did. A path-scoped commit runs hooks against a temporary index, so nothing a `pre-commit` hook stages reaches the real index — neither a reformatted copy of a listed file nor an unlisted one the hook adds itself, such as a regenerated lockfile. Every path the commit actually recorded is reconciled once it succeeds, so the index agrees with HEAD either way; reconciling only the listed paths would leave an unlisted one sitting in the index as a staged deletion of a file present in both HEAD and the working tree. Work that is staged but not committed is left staged rather than committed or discarded. File names are passed as `:(literal)` pathspecs so a name holding `*`, `?` or `[...]` matches itself instead of some other file, and the reconciliation anchors its paths with `:(top)` so a call made from a subdirectory still lands. An empty file argument is refused up front, since as a pathspec it would match everything under the current directory. Related to #46, reported by @paskal

## planning v3.9.0 - 2026-08-20

### New Features

- plan-review overlay: add an `orca` terminal backend to `launch-plan-review.sh`. Inside the Orca app (`TERM_PROGRAM=Orca`) the launcher had no matching branch, so the `ExitPlanMode` hook and `/planning:make` interactive review fell through to "no overlay terminal available" even with revdiff installed. The new branch opens revdiff in a new terminal tab via the orca CLI (`terminal create --command --focus`, pinned to the caller's worktree card through `ORCA_WORKTREE_ID`), blocks on a sentinel file until revdiff exits, then closes the tab with `terminal close --tab`. A sentinel is needed because `terminal create --command` runs inside an interactive shell that stays open after the command, so `terminal wait --for exit` never fires

## release-tools v2.0.5 - 2026-08-20

### Bug Fixes

- `get-notes.sh` aborts when the forge CLI fails instead of shipping release notes with every PR entry missing. The CLI sat at the head of a `cli | jq | while` pipeline, so the script's exit status was the loop's — always 0 — and the CLI's own diagnostics went to `/dev/null`. `gh` missing, unauthenticated, rate-limited or pointed at the wrong repository all read as "this release has no PRs", and the workflow wrote those notes to the changelog and published the release with nothing indicating a failure. The Gitea branch was worse: a missing `tea` was wrapped in `command -v` with no `else`, a completely silent no-op. This is the same exit-0 hole the v2.0.4 unknown-platform guard closed, reached by the far more common route
- `get-notes.sh` reports a `jq` failure too. `jq` is not installed by default on macOS, and an absent one drained the pipeline and left notes that listed no PRs. A forge renaming a field is not this case: jq reads a missing key as null and still exits 0, so only a type change trips the check
- `get-notes.sh` initialises `tag_date` unconditionally. It was only ever assigned inside `if [ -n "$last_tag" ]`, so in an untagged repository it kept whatever an inherited environment variable of that name held and filtered PRs against it. The tag-date fallback also gained a `|| true`, since under `set -e` a git failure there killed the run with a bare exit code and no message
- `SKILL.md` tells the agent that the helpers exit non-zero with the reason on stderr, and to abort rather than continue with an empty value. The Scripts block documented only what each helper prints on stdout, so the failures above had no documented consequence even once they were loud. Partly addresses `docs/backlog/release-skill-never-tells-agent-to-abort.md`

### Other

- `tests/test-release-tools.sh` covers a failing forge CLI on all three platforms and a failing `jq`, asserting a non-zero exit, empty stdout, and a diagnostic naming the tool — the previous commit-grouping tests stubbed `gh` as always-failing and asserted success, which locked the old behaviour in

## release-tools v2.0.4 - 2026-08-20

### Bug Fixes

- `get-notes.sh` no longer drops PRs merged just after the last tag. The cutoff came from `git log --format=%aI`, which keeps the tag author's local UTC offset, while the forge APIs report merge times in UTC — and `jq` compares the two as plain strings. For a tagger at `+02:00` every PR merged within two hours after the tag compared as older than it and vanished from the release notes. The tag date is now rendered in UTC with the same `Z` suffix the APIs use
- `get-notes.sh` takes the cutoff from the tag's own date rather than the tagged commit's author date. An author date survives rebases and cherry-picks, so it can sit days before the tag that points at it — and every PR merged in that window got re-listed in the next release's notes, having already shipped in the previous one. The date now comes from `git for-each-ref --format=%(creatordate:…)`, which is the tagger time for an annotated tag and the committer time for a lightweight one
- `get-notes.sh` rejects an unknown platform. Anything other than `github`, `gitlab` or `gitea` fell through all three collection branches and returned commit-only notes with exit 0, which reads as a successful run that simply found no PRs

### Other

- extended `tests/test-release-tools.sh` to cover the paths these fixes touch: the `glab repo view` fallback for self-hosted GitLab, GitLab and Gitea PR collection (whose `jq` field names had never been exercised, so a typo in either produced empty notes silently), an unknown platform, the tag-date cutoff against merge times half an hour either side of the tag, and a tag created hours after its commit was authored. The forge CLIs are stubbed so results depend on neither the network nor what is installed

## release-tools v2.0.3 - 2026-08-19

### Bug Fixes

- the new-release skill now points at the real helper scripts. `ebd1cfb` renamed `skills/release` to `skills/new` but left the workflow steps calling `${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/*.sh`, a path that does not exist in the plugin, so every step failed at runtime. The same rename left a stale `chmod` path in the manual install instructions
- helper scripts are invoked with `bash` instead of `sh`, matching every other plugin. They carry a `#!/bin/bash` shebang and use bash-only syntax (`[[ ]]`, here-strings), which fails under a POSIX `sh` such as dash
- `detect-platform.sh` now reports why it failed. `set -e` aborted on the failing `git remote get-url` before the check that prints `error: no origin remote configured` could run, so the caller got git's exit code and no explanation. Running outside a repository is reported separately
- all three helpers write their errors to stderr. The skill captures stdout as the value (`platform=$(...)`), so an error message on stdout was swallowed into the variable and never shown

## planning v3.8.5 - 2026-08-17

### Bug Fixes

- plan-review and plan-annotate overlays now scope to the agent's own pane in an agterm split, so the sibling pane stays live and usable instead of being covered. `--pane "$AGTERM_PANE"` is passed to `session overlay open` for `left`/`right` and to `session status blocked` for all pane values, including `scratch`, which `overlay open` does not accept. Related to #40, implemented by @vladislav-yevtushenko

## review v2.2.4 - 2026-08-17

### Bug Fixes

- git-review editor overlays now scope to the agent's own pane in an agterm split, matching the plan-review change above. Related to #40, implemented by @vladislav-yevtushenko

## planning v3.8.4 - 2026-07-12

### Bug Fixes

- exec: autonomous execution no longer stops to ask the user questions mid-run. Task and fixer subagents are told no human is available, so they decide judgment calls themselves (from the plan's intent, the project's lint rules and CLAUDE.md, and the surrounding code) instead of pausing. Each non-obvious decision and plan deviation is logged, and the orchestrator reports them all at completion under "Decisions made autonomously / Deviations from the plan"
- exec: worktree isolation no longer touches the main working directory. In worktree mode the feature branch is created only inside the `EnterWorktree` worktree (renamed to drop the `worktree-` prefix), and Step 4's create-branch.sh is skipped, so the main tree is never checked out to the feature branch. Added an isolation guard that verifies the main tree's branch is unchanged, plus a `--print-name` mode to create-branch.sh that derives the branch name with no git side effects

## planning v3.8.3 - 2026-07-12

### Bug Fixes

- plan-annotate `$EDITOR`: a malformed `$EDITOR` with an unbalanced quote (e.g. `EDITOR='emacs "'`) made `shlex.split` raise `ValueError` and abort `open_editor()` with an unhandled traceback, and a set-but-empty `$EDITOR` raised `IndexError`. Both now fall back to the default editor

### Improvements

- plan-annotate: use `vi` as the default editor (POSIX-standard, always present) instead of `micro` when `$EDITOR` is unset, empty, or malformed
- plan-annotate: extract the `$EDITOR`-to-argv construction into a `build_editor_cmd()` helper and cover it with tests (single-word resolution, multi-word args, empty/malformed fallback, not-on-PATH)

## review v2.2.3 - 2026-07-12

### Bug Fixes

- git-review `$EDITOR`: a malformed `$EDITOR` with an unbalanced quote (e.g. `EDITOR='emacs "'`) made `shlex.split` raise `ValueError` and abort `open_editor()` with an unhandled traceback. It now falls back to the default editor on a malformed or empty `$EDITOR`

### Improvements

- git-review: use `vi` as the default editor (POSIX-standard, always present) instead of `micro` when `$EDITOR` is unset, empty, or malformed
- git-review: extract the `$EDITOR`-to-argv construction into a `build_editor_cmd()` helper and cover it with tests (single-word resolution, multi-word args, empty/malformed fallback, not-on-PATH)

## review v2.2.2 - 2026-07-09

### Bug Fixes

- git-review `$EDITOR` overlay: add an `agterm` terminal backend to `git-review.py`. In an agterm session `open_editor()` only knew tmux/kitty/wezterm, so it fell through to a stray `KITTY_LISTEN_ON` (opening the editor in an invisible background kitty) or errored out. It now opens `$EDITOR` in a full-pane overlay via `agtermctl session overlay open --block` (checked before tmux/kitty/wezterm, mirroring `planning`'s `plan-annotate.py`), toggling the session status indicator to blocked while up and restoring active on exit
- git-review multi-word `$EDITOR`: fix `open_editor()` quoting the entire `$EDITOR` string as a single shell token, which made every overlay backend try to exec a binary literally named e.g. `emacsclient -c -a ''` and fail silently. `$EDITOR` is now `shlex.split` into argv with its first token resolved to an absolute path and each part re-quoted, so multi-word editors work across the agterm/tmux/kitty/wezterm paths

## planning v3.8.2 - 2026-07-04

### Bug Fixes

- plan review `$EDITOR` fallback: add an `agterm` terminal backend to `plan-annotate.py`. In an agterm session with no `revdiff` installed, `open_editor()` only knew tmux/kitty/wezterm, so it fell through to a stray `KITTY_LISTEN_ON` and opened the editor in an invisible background kitty (or hung on the sentinel) instead of agterm. It now opens `$EDITOR` in a full-pane overlay via `agtermctl session overlay open --block` (checked before tmux/kitty, mirroring `launch-plan-review.sh`), toggling the session status indicator to blocked while up and restoring active on exit

## planning v3.8.1 - 2026-06-29

### Bug Fixes

- plan review: add `PLANNING_DISABLE_REVDIFF=1` to skip interactive plan review entirely on both routes (the `ExitPlanMode` hook and `/planning:make`). Under `claude /remote-control` the overlay opened on the host terminal the remote client cannot see, blocking the session indefinitely; the flag bypasses both revdiff and the `$EDITOR` fallback and falls through to the normal `ExitPlanMode` confirmation #32

## planning v3.8.0 - 2026-06-28

### New Features

- plan-review overlay: add a `herdr` terminal backend to `launch-plan-review.sh`. Opens revdiff in a new fullscreen tab via the herdr CLI (`tab create` / `pane run` / `tab close`), blocking on a sentinel file until the overlay closes, so `/planning:make` interactive review and the `ExitPlanMode` hook work inside herdr sessions. #31
- plan-review overlay: add an `agterm` terminal backend to `launch-plan-review.sh`. Opens revdiff in a full-pane overlay via `agtermctl session overlay open --block` and toggles the session status indicator to blocked while the overlay is up, restoring active on exit.

## planning v3.7.8 - 2026-06-23

### Bug Fixes

- make: instruct the plan template to renumber the two trailing tasks (verify acceptance criteria, update documentation) with concrete sequential integers. They were shown as literal "Task N-1" and "Task N" placeholders with no substitution rule, so generated plans transcribed the letter `N` verbatim instead of continuing the task numbering

## thinking-tools v1.2.2 - 2026-06-22

### Improvements

- ask-codex: add a memory-load preamble so Codex reads Claude's memory files (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`, `~/.claude/CLAUDE.md`); Codex only auto-loads `AGENTS.md` #30 @alexkart
- ask-codex: raise default `model_reasoning_effort` to `xhigh` and align the intro wording with `gpt-5.5` #30 @alexkart

### Bug Fixes

- ask-codex: drop the dead `-c project_doc=...` overrides. `project_doc` is not a valid Codex config key, so they loaded nothing #30 @alexkart
- ask-codex: redirect stdin from `/dev/null` so `codex exec` no longer hangs on "Reading additional input from stdin…" on fresh installs (#26) #30 @alexkart

## planning v3.7.7 - 2026-06-22

### Bug Fixes

- exec: drop the dead `-c project_doc=...` overrides from `run-codex.sh`. `project_doc` is not a valid Codex config key, so the codex review pass loaded nothing #30 @alexkart

## planning v3.7.6 - 2026-06-09

### Bug Fixes

- exec: report the plan move honestly. Step 13 hardcoded "plan moved to completed/" in the final line even though the move is best-effort, so a no-op (plan already under `completed/` or missing) or a failed move would print a false claim. The suffix is now appended only when `move-plan.sh` actually moved the file.
- exec: `move-plan.sh` refuses to overwrite an existing destination instead of clobbering it. A same-named plan already under `completed/` now causes a non-zero exit (reported, non-blocking) rather than a silent `mv` over the existing file.

## planning v3.7.5 - 2026-06-09

### Bug Fixes

- exec: move the finished plan into `docs/plans/completed/` at completion. The plan's final "move to completed/" checkbox was marked `[x]` by a task subagent but the file never moved (the orchestrator explicitly refused, and a mid-run move would break every later phase's `PLAN_FILE_PATH`). Step 13 now performs the move via a VCS-aware `move-plan.sh` (git/hg), committing without pushing, so finished plans leave `docs/plans/` and stop re-appearing as `/planning:exec` candidates.
- exec: forbid task subagents from moving/renaming the plan file. A subagent could interpret the "move to completed/" checkbox as an automatable `git mv` and abort the run when the orchestrator's `PLAN_FILE_PATH` re-read failed; the task prompt now marks such a checkbox `[x]` and leaves the move to the harness.

## planning v3.7.4 - 2026-06-02

### Improvements

- make the plan-review overlay popup size configurable via `REVDIFF_POPUP_WIDTH` / `REVDIFF_POPUP_HEIGHT` env vars, defaulting to 90% #27 @aldobrynin

### Bug Fixes

- pass `90%` (not 90 cells) to zellij for the plan-review overlay #27 @aldobrynin

## planning v3.7.3 - 2026-06-01

### Bug Fixes

- exec: enforce one-task-at-a-time in the task loop. Step 6 described a sequential loop but never forbade batch-spawning, so an autonomous run could fan out all remaining tasks in parallel — corrupting the shared plan file and working tree. Added an explicit guard that the parallel-fanout instruction applies only to the review phases.

## planning v3.7.2 - 2026-05-30

### Bug Fixes

- redirect codex stdin from `/dev/null` in `run-codex.sh` so the external review step does not hang when launched with an inherited open stdin (e.g. background tasks); `codex exec` reads stdin to append a `<stdin>` block even when a prompt arg is given

## thinking-tools v1.2.1 - 2026-05-18

### Improvements

- bump `ask-codex` default Codex model to `gpt-5.5` #22 @fitz123

## release-tools v2.0.2 - 2026-05-18

### Improvements

- replace Git-specific wording with generic repository wording #11 @paskal

## workflow v1.1.0 - 2026-05-16

### New Features

- route learn discoveries to `CLAUDE.local.md` when they are per-developer or per-checkout and the file exists #25 @alexkart
- defer to project memory placement rules before using workflow defaults #25 @alexkart

### Improvements

- show inferred memory destinations in the selection prompt #25 @alexkart
- clarify that `Other` selects discoveries only, not arbitrary output paths #25 @alexkart

### Bug Fixes

- read user memory while checking for duplicate discoveries #25 @alexkart

## workflow v1.0.1 - 2026-05-14

### Bug Fixes

- align learn skill wording with Claude Code memory docs #24 @alexkart

## planning v3.7.1 - 2026-05-13

### Bug Fixes

- keep the worktree choice mandatory and reframe the prompt by current branch state 74789cc

## planning v3.7.0 - 2026-05-13

### New Features

- add stats summary phase to `/planning:exec` with wall-clock time, tokens, tool use, agent count, diff stats, commits, and final state 72faf91

## planning v3.6.8 - 2026-05-13

### Improvements

- change default Codex model to `gpt-5.5` and reasoning effort to `xhigh` 0d6ad06

## planning v3.6.7 - 2026-05-13

### Bug Fixes

- make the worktree question mandatory in exec step 2 bcc9a22

## planning v3.6.6 - 2026-05-13

### Bug Fixes

- require structured review findings grouped by severity and preserve agent attribution 0b4e71f

## planning v3.6.5 - 2026-05-13

### Bug Fixes

- trigger review agents in one parallel batch and require severity tags 7db9756

## planning v3.6.4 - 2026-05-13

### Improvements

- document prompt customization patterns and the subagent fanout constraint d665eab

## planning v3.6.3 - 2026-05-13

### Bug Fixes

- run review fanout from the main orchestrator because subagents cannot spawn agents 957b0ad

## planning v3.6.2 - 2026-05-13

### New Features

- pass the plan file to Codex so review has intent context 1379f32

## planning v3.6.1 - 2026-05-13

### New Features

- stop the Codex review loop after an iteration has no critical or major findings 0917ff4

## brainstorm v2.2.2 - 2026-05-04

### Bug Fixes

- align brainstorm-generated plan filenames with `/planning:make` 5f947a7

## planning v3.6.0 - 2026-04-25

### New Features

- add `CODEX_NO_OVERRIDES=1` for Codex wrappers that reject `-c` overrides #20 @paskal

## planning v3.5.1 - 2026-04-25

### Improvements

- modernize Mercurial dispatch for newer `hg` behavior #19 @paskal

## planning v3.5.0 - 2026-04-23

### Bug Fixes

- add zellij, kaku, cmux, ghostty, iTerm2, and emacs vterm backends to the plan review launcher #18 @umputun
- list kaku in the no-overlay error message #18 @umputun

## planning v3.4.0 - 2026-04-17

### New Features

- add Mercurial support to `/planning:exec` helper scripts #15 @paskal
- add VCS dispatch for branch detection, branch creation, commit staging, and Codex review #15 @paskal

### Improvements

- skip git-only finalize and external review phases in Mercurial repositories #15 @paskal

## planning v3.3.0 - 2026-04-16

### New Features

- narrow phase 1 re-check loop to critical review agents d7a1f65

## thinking-tools v1.2.0 - 2026-04-13

### New Features

- add stuck-detection triggers to `ask-codex` c5091a7
- add adversarial code review template with structured JSON output c5091a7

### Improvements

- split `ask-codex` presentation formats for investigation and review c5091a7
- update default Codex model to `gpt-5.4` c5091a7

## planning v3.2.1 - 2026-04-13

### Bug Fixes

- pass plugin data directory as an argument to custom-rule resolve scripts 8aaa38b

## brainstorm v2.2.1 - 2026-04-13

### Bug Fixes

- pass plugin data directory as an argument to custom-rule resolve scripts 8aaa38b

## planning v3.2.0 - 2026-04-12

### New Features

- add custom rules injection to `/planning:make`, `/planning:exec`, and plan-review #13 @umputun
- add `custom-rules.md` and `usage.md` references for planning #13 @umputun
- add tests for custom-rule resolution #13 @umputun

### Bug Fixes

- fix README manual install copy paths for planning references #13 @umputun
- add `$CLAUDE_PLUGIN_DATA` guard to rules management instructions #13 @umputun

## brainstorm v2.2.0 - 2026-04-12

### New Features

- add custom rules injection to the brainstorm skill #13 @umputun
- add `custom-rules.md` and `usage.md` references for brainstorm #13 @umputun
- add tests for custom-rule resolution #13 @umputun

## planning v3.1.2 - 2026-04-04

### Bug Fixes

- use `window_id` instead of `id` for kitty overlay targeting 33a6b57

## review v2.2.1 - 2026-04-04

### Bug Fixes

- use `window_id` instead of `id` for kitty overlay targeting 33a6b57

## planning v3.1.1 - 2026-04-04

### Bug Fixes

- fix `AskUserQuestion` option limit and script path resolution 3635dc5

## planning v3.1.0 - 2026-04-04

### New Features

- add revdiff support for plan review with editor fallback 1fcf4d4

### Improvements

- replace unnecessary Git-specific prose with generic repository wording #11 @paskal
- add Solution Overview and TodoWrite guidance to `/planning:make` 1fcf4d4

## brainstorm v2.1.0 - 2026-04-04

### Improvements

- rename direct skill invocation from `/brainstorm:do` to `/brainstorm:brainstorm` 1ee00db

## planning v3.0.3 - 2026-03-31

### Bug Fixes

- fix YAML frontmatter parsing and shellcheck warnings #10 @paskal

### Other

- add CI checks for YAML frontmatter and shell scripts #10 @paskal

## release-tools v2.0.1 - 2026-03-31

### Bug Fixes

- fix shellcheck warnings in release note generation #10 @paskal

## planning v3.0.2 - 2026-03-31

### New Features

- add `Execute autonomously` option to `/planning:make` 76132b3

### Bug Fixes

- stop the exec orchestrator from doing subagent work directly 44bf46d
- move `plan-annotate.py` to plugin-level `scripts/` for reliable cross-plugin path resolution f7b3a6b

## planning v3.0.1 - 2026-03-31

### Bug Fixes

- make `create-branch.sh` usage mandatory in `/planning:exec` f7fc577

## planning v3.0.0 - 2026-03-30

### New Features

- add `/planning:exec` for autonomous plan execution #8 @umputun
- add task loop, multi-phase review, fixer agent, optional finalize, and override chain #8 @umputun
- add bundled exec prompts, agents, and helper scripts #8 @umputun

## review v2.2.0 - 2026-03-30

### Improvements

- remove personal preferences from the writing-style skill #9 @umputun

## planning v2.1.2 - 2026-03-27

### Bug Fixes

- correct plan-review references to `/planning:make` #6 @bronislav
- resolve `$EDITOR` to an absolute path in overlay shells #7 @bronislav
- replace stale `/action:plan` reference with `/planning:make` 2dfcf67

## planning v2.1.1 - 2026-03-16

### Bug Fixes

- use the focused window for file-mode kitty overlay c9078b7

## review v2.1.1 - 2026-03-13

### New Features

- add `--branch` flag to git-review for remote branch review f9403c8

## thinking-tools v1.1.0 - 2026-03-06

### New Features

- add `ask-codex` skill for OpenAI Codex consultation c0715a3

## planning v2.1.0 - 2026-03-01

### New Features

- add plan-review agent for automated plan quality review 8bf680a

## review v2.1.0 - 2026-02-28

### New Features

- add git-review skill for interactive diff annotation #2 @umputun

### Bug Fixes

- handle copied files like renamed files in git-review #2 @umputun
- remove dead diff argument assignment in uncommitted mode #2 @umputun
- add early git repository guard in git-review #2 @umputun

## planning v2.0.1 - 2026-02-26

### New Features

- add wezterm support to the plan annotation hook #1 @tdragon

### Bug Fixes

- target kitty overlay to the originating window ee53808
- use explicit kitty socket for the plan annotation hook 82bc6a4

## brainstorm v2.0.0 - 2026-02-17

### Improvements

- rename skill invocations to remove repeated plugin names ebd1cfb

## planning v2.0.0 - 2026-02-17

### Improvements

- rename skill invocations to remove repeated plugin names ebd1cfb

## release-tools v2.0.0 - 2026-02-17

### Improvements

- rename skill invocations to remove repeated plugin names ebd1cfb

## review v2.0.0 - 2026-02-17

### Improvements

- rename skill invocations to remove repeated plugin names ebd1cfb

## brainstorm v1.0.0 - 2026-02-17

Initial marketplace release.

### New Features

- add brainstorm skill for collaborative design dialogue 70b947f

## planning v1.0.0 - 2026-02-17

Initial marketplace release.

### New Features

- add planning plugin with `/planning:make` and plan annotation support 70b947f

## release-tools v1.0.0 - 2026-02-17

Initial release.

### New Features

- add release workflow skill and last-tag helper a59bb1f

## review v1.0.0 - 2026-02-17

Initial marketplace release.

### New Features

- add PR review and writing-style skills 70b947f

## skill-eval v1.0.0 - 2026-02-17

Initial marketplace release.

### New Features

- add skill evaluation hook 70b947f

## thinking-tools v1.0.0 - 2026-02-17

Initial release.

### New Features

- add dialectic and root-cause-investigator skills d627b3f

## workflow v1.0.0 - 2026-02-17

Initial release.

### New Features

- add learn, clarify, wrong, md-copy, and txt-copy skills 782e0e3
