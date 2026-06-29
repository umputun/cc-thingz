# Changelog

This repo ships independent Claude Code plugins. Version headings use values from `plugins/<name>/.claude-plugin/plugin.json`; they are not git tags.

Entries are sorted by plugin version date, newest first.

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
