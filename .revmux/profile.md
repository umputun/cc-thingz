# Project profile: cc-thingz

## What it is

A published marketplace of Claude Code plugins: hooks, skills and commands. There is no compiled code and
no service. What ships is bash helper scripts, a few python scripts, and markdown prompt files that agents
read and act on. Consumers install plugins by name from the marketplace, so anything under `plugins/` is a
release artifact the moment it is tagged.

## What a real failure looks like here

The scripts run unattended, inside autonomous loops nobody is watching. The failures that matter are the
ones that are silent:

- a helper that corrupts a user's git state, commits the wrong files, or loses work
- a prompt file that instructs an agent to do the wrong thing, or contradicts itself so the agent picks
  either reading
- a script that fails without saying why, or reports success after doing nothing
- a path or name that does not resolve once the plugin is copied to its install cache

A crash is not the worst case. A helper that exits 0 having done something wrong is, because the loop keeps
going and the damage compounds across a run.

## Blast radius

Every user who installed the plugin, in their own repositories, on their own working trees. That is wider
than a personal tool: the code runs on other people's git state. It is not production infrastructure and no
customer data is at risk, but "the author can just fix it" does not apply.

## Who runs and maintains it

Solo maintainer (umputun), with a handful of repeat outside contributors. No on-call. CI runs shellcheck
over every `.sh` in the repo, every `tests/test-*.sh` suite, and the python test flags.

## Reporting bar

Report anything that would make an unattended run do the wrong thing quietly, however narrow the trigger.
Report a prompt or document that would mislead an agent executing it, at the severity the wrong action
deserves, not as a documentation nit.

Do not report: prose style in markdown, wording preferences, missing sections nobody asked for, or shell
constructs that shellcheck already passes and that work on bash 3.2 and later.

## Deliberate conventions, not defects

- helper scripts use `${CLAUDE_PLUGIN_ROOT}` for path resolution; the plugin system copies files to a cache
  location, so relative and absolute paths are wrong by design
- each plugin carries its own `version` in `plugins/<name>/.claude-plugin/plugin.json` and is bumped
  independently, with a matching `CHANGELOG.md` entry
- scripts are `#!/bin/bash` and invoked with `bash`, never `sh`
- markdown under `plugins/` is instructions for an agent, not documentation for a person. Judge it on
  whether an agent following it literally does the right thing
- subagents cannot spawn subagents, so any prompt needing parallel fan-out is executed by the main session
  rather than handed to a spawned agent
