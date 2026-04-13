# Custom Rules Injection for Planning and Brainstorm Plugins

## Overview
- Add user-provided custom rules injection to planning (make, plan-review, exec) and brainstorm skills
- Users can provide language-specific or project-specific rules (e.g., Go testing conventions, Python linting) that get loaded into skill prompts at invocation time
- Rules are free-form markdown, loaded at runtime and appended to the skill/command prompt as additional instructions — no schema or structured format required
- Two levels: project-scoped (`.claude/`) and user-scoped (`$CLAUDE_PLUGIN_DATA/`)

**Acceptance criteria**:
- Users can manually create `.claude/planning-rules.md` (project) or `$CLAUDE_PLUGIN_DATA/planning-rules.md` (user-level) and see their content applied as additional prompt instructions when invoking make, exec, plan-review, or brainstorm
- Same for brainstorm with `.claude/brainstorm-rules.md` and `$CLAUDE_PLUGIN_DATA/brainstorm-rules.md`
- Users can ask any skill to create/update rules interactively (e.g., "add my Go rules to user-level planning rules", "set up brainstorm rules from my-conventions.md")
- Users can ask any skill to show or clear existing rules at either level
- Project-level rules take precedence over user-level rules (first-found-wins)

## Context (from discovery)
- `plugins/planning/` — version 3.1.2, has make command, exec skill, plan-review agent, hooks, scripts
- `plugins/brainstorm/` — version 2.1.0, minimal structure: just `skills/brainstorm/SKILL.md` and `plugin.json`
- `resolve-file.sh` already exists in exec for 3-layer override chain (project → user → bundled)
- `$CLAUDE_PLUGIN_DATA` is per-plugin persistent storage managed by Claude Code
- No cross-plugin dependency — each plugin is fully self-contained

### Injection mechanism
- All file types (commands, skills, agents) use the same approach: LLM-invoked bash
- Each skill/command/agent includes instructions telling Claude to run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh <filename>` at the start and apply the output as custom rules
- This is consistent, works everywhere, and allows interactive rules management (user can ask to add/show/clear rules mid-session)

## Development Approach
- **testing approach**: automated shell tests for resolve-rules.sh + manual verification for skill integration
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: verify each skill loads rules correctly after modification**
- run existing tests (plan-annotate.py --test) to ensure no regressions

## Testing Strategy
- **automated tests**: `test-resolve-rules.sh` script exercising resolution chain: (1) no files present, (2) only project file, (3) only user file, (4) both files — project wins (first-found-wins, NOT merged), (5) empty file
- **regression**: `plan-annotate.py --test` for existing functionality
- **manual verification**: create sample rules files, invoke each skill, verify rules appear in context
- **"both levels" semantics**: first-found-wins — when both project and user files exist, only project-level content is output. Files are never merged or concatenated.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

## Solution Overview
- Each plugin gets a `resolve-rules.sh` script that checks project path then user path, outputs content or nothing
- All skills/commands/agents use LLM-invoked bash to call `resolve-rules.sh` — consistent mechanism everywhere
- Skills include instructions for rules management (add, show, clear) at both levels
- Reference docs for the mechanism are placed at the plugin level (`plugins/<name>/references/custom-rules.md`)

### Resolution Chain

**Planning plugin** (make, plan-review, exec):
1. `.claude/planning-rules.md` (project override)
2. `$CLAUDE_PLUGIN_DATA/planning-rules.md` (user override)
3. Nothing (no bundled default)

**Brainstorm plugin**:
1. `.claude/brainstorm-rules.md` (project override)
2. `$CLAUDE_PLUGIN_DATA/brainstorm-rules.md` (user override)
3. Nothing (no bundled default)

**Semantics**: first-found-wins. When both levels exist, only the project-level file content is output. Files are never merged.

## Technical Details
- `resolve-rules.sh` takes a filename argument (e.g., `planning-rules.md` or `brainstorm-rules.md`)
- Project path: `.claude/<filename>` (relative to working directory)
- User path: `$CLAUDE_PLUGIN_DATA/<filename>` (per-plugin persistent storage)
- Output: file content to stdout if found, empty output (exit 0) if no file found — never errors
- First file found wins (project over user), raw content without wrapping (wrapping is done in the skill/command markdown)
- All file types use LLM-invoked bash: instruct Claude to run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh planning-rules.md` and apply the output as additional rules alongside the skill's built-in instructions
- Planning's existing `resolve-file.sh` is NOT modified — `resolve-rules.sh` is a separate, simpler script
- Rules content is wrapped in a labeled section in each skill/command so the LLM knows what it is

### Exec subagent propagation
- The exec SKILL.md loads rules via LLM-invoked bash at orchestrator level
- Rules content is included in the orchestrator's context and passed to task subagents via the task prompt
- Add a `USER_RULES` placeholder to `references/prompts/task.md` that the orchestrator substitutes with resolved rules content (or empty string if no rules)
- This follows the existing placeholder pattern (PLAN_FILE_PATH, PROGRESS_FILE_PATH, etc.)

## What Goes Where
- **Implementation Steps** — all changes within this repository
- **Post-Completion** — manual verification with installed plugins

## Implementation Steps

### Task 1: Create resolve-rules.sh for planning plugin

**Files:**
- Create: `plugins/planning/scripts/resolve-rules.sh`

- [x] create `plugins/planning/scripts/resolve-rules.sh` with behavior: takes filename arg, checks `.claude/<filename>` first, then `$CLAUDE_PLUGIN_DATA/<filename>`, outputs first found file content to stdout, exit 0 always (empty output if no file found), first-found-wins (not merged), raw content without wrapping
- [x] make script executable (`chmod +x`)
- [x] verify script works: create temp `.claude/planning-rules.md`, run script, confirm output; remove file, confirm empty output

### Task 2: Create resolve-rules.sh for brainstorm plugin

**Files:**
- Create: `plugins/brainstorm/scripts/resolve-rules.sh`

- [x] create `plugins/brainstorm/scripts/` directory
- [x] create `plugins/brainstorm/scripts/resolve-rules.sh` — same logic as planning's copy, standalone
- [x] make script executable
- [x] verify script works same as task 1

### Task 3: Add automated tests for resolve-rules.sh

**Files:**
- Create: `plugins/planning/scripts/test-resolve-rules.sh`

- [x] create test script that exercises: (1) no files present → empty output, (2) only project file → outputs project content, (3) only user file → outputs user content, (4) both files → outputs project content only, (5) empty file → empty output
- [x] use temp directories and cleanup to avoid polluting working directory
- [x] make script executable
- [x] run tests, verify all pass

### Task 4: Add rules injection to planning:make command

**Files:**
- Modify: `plugins/planning/commands/make.md`

- [x] add LLM-invoked bash instructions after frontmatter, before step 0 — tell Claude to run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh planning-rules.md` and apply non-empty output as additional rules (appended to, not replacing, the command's built-in instructions)
- [x] add rules management instructions — when user asks to add/show/clear rules, handle at both project (`.claude/planning-rules.md`) and user (`$CLAUDE_PLUGIN_DATA/planning-rules.md`) levels. Rules guide plan-creation behavior, not embedded in output plan file.
- [x] verify: create sample rules file, invoke `/planning:make`, confirm rules appear in context

### Task 5: Add rules injection to plan-review agent

**Files:**
- Modify: `plugins/planning/agents/plan-review.md`

- [ ] add `Bash` to the agent's `tools` list in frontmatter (currently only has `Read, Glob, Grep`)
- [ ] add LLM-invoked bash instructions telling Claude to run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh planning-rules.md` and apply non-empty output as additional rules context
- [ ] add instruction to apply user rules when reviewing plan quality, conventions, and testing approach
- [ ] verify: create sample rules file, confirm plan-review agent sees and applies rules

### Task 6: Add rules injection to planning:exec skill

**Files:**
- Modify: `plugins/planning/skills/exec/SKILL.md`
- Modify: `plugins/planning/skills/exec/references/prompts/task.md`

- [ ] add LLM-invoked bash instructions in exec SKILL.md to run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh planning-rules.md` and apply non-empty output as additional rules
- [ ] add `USER_RULES` placeholder to `references/prompts/task.md` so rules propagate to task subagents
- [ ] add `USER_RULES` to the placeholder substitution list in SKILL.md (alongside PLAN_FILE_PATH, etc.)
- [ ] verify: create sample rules file, confirm exec skill loads rules and task prompt includes them

### Task 7: Add rules injection to brainstorm skill

**Files:**
- Modify: `plugins/brainstorm/skills/brainstorm/SKILL.md`

- [ ] add LLM-invoked bash instructions to run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh brainstorm-rules.md` and apply non-empty output as additional rules
- [ ] add rules management instructions — when user asks to add/show/clear rules, handle at both project (`.claude/brainstorm-rules.md`) and user (`$CLAUDE_PLUGIN_DATA/brainstorm-rules.md`) levels
- [ ] verify: create sample rules file, invoke brainstorm, confirm rules appear

### Task 8: Add custom-rules.md reference docs

**Files:**
- Create: `plugins/planning/references/custom-rules.md`
- Create: `plugins/brainstorm/references/custom-rules.md`

- [ ] create `plugins/planning/references/custom-rules.md` — documents the rules mechanism, file locations (project + user), resolution order, example content, how to add/show/clear rules
- [ ] create `plugins/brainstorm/references/custom-rules.md` — same structure, brainstorm-specific file names
- [ ] reference these docs from each skill's rules management instructions

### Task 9: Run regression tests and verify no breakage

- [ ] run `python3 plugins/planning/scripts/plan-annotate.py --test`
- [ ] run `bash plugins/planning/scripts/test-resolve-rules.sh`
- [ ] verify all existing hook scripts still reference correct paths
- [ ] spot-check that exec's existing `resolve-file.sh` is unchanged and still works

### Task 10: Update README and bump plugin versions

**Files:**
- Modify: `README.md`
- Modify: `plugins/planning/.claude-plugin/plugin.json`
- Modify: `plugins/brainstorm/.claude-plugin/plugin.json`

- [ ] add "Custom Rules" section to README explaining the mechanism, file locations, resolution order, and example usage for both plugins
- [ ] bump planning plugin version (minor: new feature)
- [ ] bump brainstorm plugin version (minor: new feature)

### Task 11: [Final] Update documentation
- [ ] update CLAUDE.md if new patterns discovered
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion

**Manual verification:**
- install plugins locally (`claude --plugin-dir plugins/planning` and `claude --plugin-dir plugins/brainstorm`)
- create sample `.claude/planning-rules.md` with Go-specific rules in a test project
- invoke `/planning:make`, verify rules are loaded and influence plan output
- invoke brainstorm, verify rules management works
- test user-level rules via `$CLAUDE_PLUGIN_DATA`
