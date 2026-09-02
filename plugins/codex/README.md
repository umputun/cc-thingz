# Codex plugins

This directory packages every cc-thingz plugin for OpenAI Codex. Each child directory is an
independent plugin with a `.codex-plugin/plugin.json` manifest and one or more skills. The root
marketplace is [`.agents/plugins/marketplace.json`](../../.agents/plugins/marketplace.json).

## Install

From GitHub:

```bash
codex plugin marketplace add umputun/cc-thingz
codex plugin add planning@umputun-cc-thingz
```

From a local checkout:

```bash
codex plugin marketplace add /absolute/path/to/cc-thingz
codex plugin add planning@umputun-cc-thingz
```

Repeat `codex plugin add` for any of these plugins:

| Plugin | Codex skills |
|---|---|
| `brainstorm` | `brainstorm` |
| `planning` | `make`, `plan-review`, `exec` |
| `release-tools` | `last-tag`, `new` |
| `review` | `git-review`, `pr`, `writing-style` |
| `skill-eval` | `skill-eval` |
| `thinking-tools` | `ask-codex`, `dialectic`, `root-cause-investigator` |
| `workflow` | `backlog`, `clarify`, `learn`, `md-copy`, `txt-copy`, `wrong` |

Start a new session after installation so Codex discovers the skills.

## Host-specific behaviour

The Codex packages preserve the Claude workflows while using Codex-native discovery and project
paths:

- Claude commands and reusable agents are skills in Codex.
- `AGENTS.md` is the default project-guidance destination for the workflow plugin.
- Project rules live in `.codex/brainstorm-rules.md` and `.codex/planning-rules.md`.
- User rules and planning configuration live under
  `${CODEX_HOME:-$HOME/.codex}/cc-thingz/`.
- The executable `external_review_cmd` setting is user-only; project configuration may override
  safe workflow settings but cannot select a command.
- Planning prompt overrides live in `.codex/exec-plan/` at project level or
  `${CODEX_HOME:-$HOME/.codex}/cc-thingz/planning/exec-plan/` at user level.

To start an override from a bundled planning prompt, resolve the planning plugin root from the
`planning:exec` skill's absolute catalogue path, then run:

```bash
bash "<planning-plugin-root>/skills/exec/scripts/customize-file.sh" prompts/review.md
bash "<planning-plugin-root>/skills/exec/scripts/customize-file.sh" prompts/review.md --user
```

The first command writes a project override; the second writes a user override. See the
[planning usage reference](planning/references/usage.md#customization) for the precedence rules.

Codex skips `prompt` and `agent` hook handlers. The planning plugin therefore exposes plan creation
and review as explicit skills. Codex does run trusted command hooks, so skill-eval preserves its
`UserPromptSubmit` behaviour through `hooks/hooks.json`; review and trust that hook through `/hooks`
before use. Interactive plan annotation remains available from `planning:make` through
`launch-plan-review.sh` or the bundled editor fallback.

## Validation

Validate manifests and skills with the Codex plugin and skill validators, then run the repository's
existing script tests. A local installation from the repository root is the final packaging check.
