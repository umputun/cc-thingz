# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

Things to make Claude Code even better — hooks, skills, agents, and commands, packaged as a Claude Code plugin.

## Key Rules

- **README.md must be kept up to date** — whenever a new component, script, or configuration is added, update README.md with a description of what it does and how to use it.
- Content is MIT-licensed.
- This is a personal project by Umputun (GitHub).
- **No personal configuration** — scripts and configs must be generic and not contain hardcoded personal paths, editor preferences, or machine-specific settings. Use environment variables (e.g., `$EDITOR`) for user-specific values.
- **Self-contained documentation** — do not reference external custom skills, actions, or configurations that exist only in a user's personal Claude Code setup. All documentation must refer only to what exists in this repository.

## Conventions

- Hook scripts use `${CLAUDE_PLUGIN_ROOT}` for path resolution when running as a plugin. The plugin system copies files to a cache location during install, so absolute/relative paths won't work.
- Manual install instructions are kept in README.md as a fallback for users who prefer direct setup.
- **Versioning** — bump `version` in `.claude-plugin/plugin.json` when adding or changing plugin components. Use semver: patch for bug fixes, minor for new hooks/skills/agents, major for breaking changes.

## Structure

- `.claude-plugin/` — plugin manifest (`plugin.json`) and marketplace catalog (`marketplace.json`)
- `hooks/` — hook scripts and hook definitions (`hooks.json`) for Claude Code
- `skills/` — skill definitions (SKILL.md files) for Claude Code
- `commands/` — slash command definitions for Claude Code

## Testing

- Python scripts include embedded tests run via `--test` flag: `python3 hooks/<script>.py --test`
