# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A collection of utilities, configurations, and enhancements for Claude Code. This is not a Go project — it contains mixed content (scripts, configs, documentation, prompts, etc.) that improve the Claude Code workflow.

## Key Rules

- **README.md must be kept up to date** — whenever a new component, script, or configuration is added, update README.md with a description of what it does and how to use it.
- Content is MIT-licensed.
- This is a personal project by Umputun (GitHub).
- **No personal configuration** — scripts and configs must be generic and not contain hardcoded personal paths, editor preferences, or machine-specific settings. Use environment variables (e.g., `$EDITOR`) for user-specific values.
- **Self-contained documentation** — do not reference external custom skills, actions, or configurations that exist only in a user's personal Claude Code setup. All documentation must refer only to what exists in this repository.

## Conventions

- Scripts contain full install instructions in their docstrings. README install sections use a Claude Code prompt that fetches the raw file from GitHub and tells Claude to follow the embedded instructions — this avoids duplicating install steps between README and script.

## Structure

- `scripts/` — standalone scripts (Python, shell) for Claude Code hooks and utilities

## Testing

- Python scripts include embedded tests run via `--test` flag: `python3 scripts/<script>.py --test`
