# Custom Rules for Brainstorm

Custom rules let you inject project-specific or personal conventions into the brainstorm workflow. Rules are free-form markdown loaded at skill invocation time and applied as additional instructions alongside the skill's built-in behavior.

## File Locations

Two levels, checked in order (first-found-wins, never merged):

1. **Project-level**: `.codex/brainstorm-rules.md` in the current working directory
2. **User-level**: `${CODEX_HOME:-$HOME/.codex}/cc-thingz/brainstorm/brainstorm-rules.md`

When both non-empty files exist, only the project-level file is used. Empty files are treated as absent and fall through to the next level.

## Resolution

The skill runs `resolve-rules.sh brainstorm-rules.md` via Bash at startup. The script uses `$CODEX_HOME` when set and otherwise defaults to `$HOME/.codex`. It outputs the first file found (project, then user) or empty output if neither exists.

## Managing Rules

Ask the brainstorm skill to manage rules:

- **show rules** — displays current rules and which level they came from
- **add/update project rules** — writes to `.codex/brainstorm-rules.md`
- **add/update user rules** — writes to `${CODEX_HOME:-$HOME/.codex}/cc-thingz/brainstorm/brainstorm-rules.md`
- **clear project rules** — deletes `.codex/brainstorm-rules.md`
- **clear user rules** — deletes `${CODEX_HOME:-$HOME/.codex}/cc-thingz/brainstorm/brainstorm-rules.md`

## Example Content

```markdown
## design preferences
- prefer simple solutions over clever abstractions
- always consider backward compatibility
- propose at most 3 approaches

## technology constraints
- backend must be Go with standard library where possible
- frontend uses HTMX, avoid JavaScript frameworks
- database is SQLite via sqlx

## naming conventions
- use camelCase for variables
- use PascalCase for exported types
```

## How Rules Apply

Rules influence design preferences, naming conventions, technology choices, and other aspects of the brainstorm dialogue. They supplement built-in instructions — they never replace them.
