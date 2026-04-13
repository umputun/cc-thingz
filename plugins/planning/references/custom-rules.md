# Custom Rules for Planning

Custom rules let you inject project-specific or personal conventions into the planning workflow (make, exec, plan-review). Rules are free-form markdown loaded at skill invocation time and applied as additional instructions alongside the skill's built-in behavior.

## File Locations

Two levels, checked in order (first-found-wins, never merged):

1. **Project-level**: `.claude/planning-rules.md` in the current working directory
2. **User-level**: `$CLAUDE_PLUGIN_DATA/planning-rules.md` (per-plugin persistent storage)

When both files exist, only the project-level file is used.

## Resolution

Each skill runs `resolve-rules.sh planning-rules.md` via Bash at startup. The script outputs the first file found (project, then user) or produces empty output if neither exists.

## Managing Rules

Ask any planning skill (make, exec, brainstorm) to manage rules:

- **show rules** — displays current rules and which level they came from
- **add/update project rules** — writes to `.claude/planning-rules.md`
- **add/update user rules** — writes to `$CLAUDE_PLUGIN_DATA/planning-rules.md`
- **clear project rules** — deletes `.claude/planning-rules.md`
- **clear user rules** — deletes `$CLAUDE_PLUGIN_DATA/planning-rules.md`

## Example Content

```markdown
## testing conventions
- use table-driven tests with testify
- mock external dependencies with moq
- aim for 80% coverage minimum

## naming
- use camelCase for local variables
- keep function names under 30 characters

## plan structure preferences
- max 5 checkboxes per task
- always include rollback steps for migrations
```

## How Rules Apply

- **make**: rules influence plan structure, testing approach, naming conventions, task granularity
- **plan-review**: rules become additional review criteria for convention adherence
- **exec**: rules propagate to task subagents via the `USER_RULES` placeholder in task prompts

Rules supplement built-in instructions — they never replace them.
