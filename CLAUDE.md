# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

Things to make Claude Code even better — hooks, skills, and commands, organized as a marketplace of independent plugins.

## Key Rules

- **README.md must be kept up to date** — whenever a new component, script, or configuration is added, update README.md with a description of what it does and how to use it.
- Content is MIT-licensed.
- This is a personal project by Umputun (GitHub).
- **No personal configuration** — scripts and configs must be generic and not contain hardcoded personal paths, editor preferences, or machine-specific settings. Use environment variables (e.g., `$EDITOR`) for user-specific values.
- **Self-contained documentation** — do not reference external custom skills, actions, or configurations that exist only in a user's personal Claude Code setup. All documentation must refer only to what exists in this repository.

## Conventions

- Hook scripts use `${CLAUDE_PLUGIN_ROOT}` for path resolution when running as a plugin. The plugin system copies files to a cache location during install, so absolute/relative paths won't work.
- Manual install instructions are kept in README.md as a fallback for users who prefer direct setup.
- **Versioning** — each plugin has its own `version` in `plugins/<name>/.claude-plugin/plugin.json`. Bump independently per plugin. Use semver: patch for bug fixes, minor for new components, major for breaking changes.
- **Cross-references** — when skills reference other skills within the same plugin, use the plugin name prefix (e.g., `/review:writing-style`). When referencing skills in other plugins, use that plugin's name (e.g., `/planning:make`).

## Structure

- `.claude-plugin/marketplace.json` — marketplace catalog listing all plugins
- `plugins/` — each subdirectory is an independent plugin:
  - `plugins/brainstorm/` — collaborative design skill
  - `plugins/review/` — PR review skill + writing style skill
  - `plugins/planning/` — plan command, exec skill, plan-annotate hook, and bundled reference files
  - `plugins/release-tools/` — release workflow + last-tag skills
  - `plugins/thinking-tools/` — dialectic analysis + root-cause-investigator skills
  - `plugins/skill-eval/` — skill evaluation hook
  - `plugins/workflow/` — session workflow helpers (learn, clarify, wrong, md-copy, txt-copy)
- Each plugin has its own `.claude-plugin/plugin.json`, and standard subdirectories (`skills/`, `commands/`, `hooks/`) as needed.

## Local Plugin Development

- **Testing locally** — use `claude --plugin-dir plugins/<name>` to load a local plugin without publishing. Use `/reload-plugins` inside a session to pick up file changes without restarting.
- **Updating marketplace cache** — plugin hooks and skills are read from `~/.claude/plugins/marketplaces/`, not `cache/`. When manually testing changes, copy files to the marketplace path.

## Known Claude Code Limitations

- **Plugin skill autocomplete** — skills defined in `skills/*/SKILL.md` don't appear in the `/` autocomplete dropdown, only commands in `commands/*.md` do. Skills are still invocable by typing the full name (e.g., `/planning:exec`) or via natural language intent matching.
- **Plugin hook deny rendering** — PreToolUse hooks that return `permissionDecision: "deny"` display as "blocking error" with an ugly error prefix in the TUI. The same deny from a settings.json hook renders cleanly as a permission prompt. This is a Claude Code rendering issue, not fixable from the plugin side.

## Testing

- Python scripts include embedded tests run via `--test` flag: `python3 plugins/planning/scripts/plan-annotate.py --test`
- Shell scripts have standalone test scripts: `bash plugins/planning/scripts/test-resolve-rules.sh`

## Custom Rules Injection

- Plugins can support user-provided custom rules via `resolve-rules.sh` scripts in `plugins/<name>/scripts/`
- Resolution chain: `.claude/<rules-file>` (project) → `$CLAUDE_PLUGIN_DATA/<rules-file>` (user), first-found-wins, never merged
- Skills/commands load rules via LLM-invoked bash (`bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh <filename>`) and apply as additional instructions
- Reference docs for each plugin's rules mechanism live in `plugins/<name>/references/custom-rules.md`
