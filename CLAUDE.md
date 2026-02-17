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
- **Cross-references** — when skills reference other skills within the same plugin, use the plugin name prefix (e.g., `/review:writing-style`). When referencing skills in other plugins, use that plugin's name (e.g., `/planning:plan`).

## Structure

- `.claude-plugin/marketplace.json` — marketplace catalog listing all plugins
- `plugins/` — each subdirectory is an independent plugin:
  - `plugins/brainstorm/` — collaborative design skill
  - `plugins/review/` — PR review skill + writing style skill
  - `plugins/planning/` — plan command + plan-annotate hook
  - `plugins/skill-eval/` — skill evaluation hook
- Each plugin has its own `.claude-plugin/plugin.json`, and standard subdirectories (`skills/`, `commands/`, `hooks/`) as needed.

## Testing

- Python scripts include embedded tests run via `--test` flag: `python3 plugins/planning/hooks/plan-annotate.py --test`
