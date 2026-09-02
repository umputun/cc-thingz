---
name: brainstorm
description: Use before any creative work or significant changes. Activates on "brainstorm", "let's brainstorm", "deep analysis", "analyze this feature", "think through", "help me design", "explore options for", or when user asks for thorough analysis of changes, features, or architectural decisions. Guides collaborative dialogue to turn ideas into designs through one-at-a-time questions, approach exploration, and incremental validation.
---

# Brainstorm

Turn ideas into designs through collaborative dialogue before implementation.

## path resolution

`<plugin-root>` means the nearest ancestor of this `SKILL.md` containing
`.codex-plugin/plugin.json`. Resolve it to an absolute path before running a bundled script.

## custom rules loading

before starting, run this command to check for user-provided custom rules:

```bash
bash <plugin-root>/scripts/resolve-rules.sh brainstorm-rules.md
```

if the output is non-empty, treat it as additional instructions that supplement (not replace) the built-in rules below. apply custom rules alongside the skill's own instructions throughout the brainstorm process — they may influence design preferences, naming conventions, technology choices, or other aspects of the brainstorm session. custom rules content is guidance for the brainstorm dialogue, not content to embed verbatim in the output.

### rules management

when the user asks to add, show, or clear custom brainstorm rules, handle these operations:

- **show rules**: run `bash <plugin-root>/scripts/resolve-rules.sh brainstorm-rules.md` and display the output. if the output is empty, tell the user no custom rules are configured at either level. otherwise, to determine the source, check if `.codex/brainstorm-rules.md` exists and is non-empty (project-level) — if not, the output came from user-level. tell the user which level it came from.
- **add/update project rules**: write content to `.codex/brainstorm-rules.md` in the current working directory.
- **add/update user rules**: write content to `${CODEX_HOME:-$HOME/.codex}/cc-thingz/brainstorm/brainstorm-rules.md`, creating its parent directory first.
- **clear project rules**: delete `.codex/brainstorm-rules.md`.
- **clear user rules**: delete `${CODEX_HOME:-$HOME/.codex}/cc-thingz/brainstorm/brainstorm-rules.md` if it exists.

project-level rules (`.codex/brainstorm-rules.md`) take precedence over user-level rules (`${CODEX_HOME:-$HOME/.codex}/cc-thingz/brainstorm/brainstorm-rules.md`). when both non-empty files exist, only project-level rules are loaded. empty files are treated as absent and fall through to the next level. see `<plugin-root>/references/custom-rules.md` for full documentation on the rules mechanism.

**CRITICAL: this skill must NEVER modify its own files (skills, scripts, references, hooks, plugin.json). the ONLY files it may create or modify for rules management are `.codex/brainstorm-rules.md` and `${CODEX_HOME:-$HOME/.codex}/cc-thingz/brainstorm/brainstorm-rules.md`. if the user asks to change the skill's behavior, suggest creating a plan — do not edit skill files directly.**

## Process

### Phase 1: Understand the Idea

Check project context first, then ask questions one at a time:

1. **Gather context** - check files, docs, recent commits relevant to the idea
2. **Ask questions one at a time** - prefer multiple choice when possible
3. **Focus on**: purpose, constraints, success criteria, integration points

Do not overwhelm with multiple questions. One question per message. If a topic needs more exploration, break it into multiple questions.

### Phase 2: Explore Approaches

Once the problem is understood:

1. **Propose 2-3 different approaches** with trade-offs
2. **Lead with recommended option** and explain reasoning
3. **Present conversationally** - not a formal document yet

Example format:
```
I see three approaches:

**Option A: [name]** (recommended)
- how it works: ...
- pros: ...
- cons: ...

**Option B: [name]**
- how it works: ...
- pros: ...
- cons: ...

Which direction appeals to you?
```

### Phase 3: Present Design

After approach is selected:

1. **Break design into sections** of 200-300 words each
2. **Ask after each section** whether it looks right
3. **Cover**: architecture, components, data flow, error handling, testing
4. **Be ready to backtrack** if something doesn't make sense

Do not present entire design at once. Incremental validation catches misunderstandings early.

### Phase 4: Next Steps

After design is validated, ask the user to choose one option:

Offer these choices in one multiple-choice question:

- **Write plan**: create `docs/plans/yyyymmdd-<task-name>.md` with the `planning:make` skill
- **Inline plan**: prepare a structured implementation plan for approval
- **Start now**: begin implementing directly

- **Write plan**: invoke the `planning:make` skill to create the plan file. Pass brainstorm context (discovered files, selected approach, design decisions) so it has full context without re-asking questions
- **Inline plan**: prepare a detailed plan in the conversation and obtain approval
- **Start now**: proceeds directly if design is simple enough

## Key Principles

- **One question at a time** - do not overwhelm with multiple questions
- **Multiple choice preferred** - easier to answer than open-ended when possible
- **YAGNI ruthlessly** - remove unnecessary features from all designs, keep scope minimal
- **Explore alternatives** - always propose 2-3 approaches before settling
- **Incremental validation** - present design in sections, validate each
- **Be flexible** - go back and clarify when something doesn't make sense
- **Lead with recommendation** - have an opinion, explain why, but let user decide
- **Duplication vs abstraction** - when code repeats, ask user: prefer duplication (simpler, no coupling) or abstraction (DRY but adds complexity)? explain trade-offs before deciding

## Task Tracking

When implementing after brainstorm:
- Track implementation tasks using available task management tools (task lists, plan file checkboxes, or similar)
- Mark each task as completed immediately when done (do not batch)
- Keep user informed of progress through status updates
