# Brainstorm Usage

## Triggers

The brainstorm skill activates on:
- "brainstorm", "let's brainstorm"
- "deep analysis", "analyze this feature"
- "think through", "help me design"
- "explore options for"
- any request for thorough analysis of changes, features, or architectural decisions

Invoke the `brainstorm:brainstorm` skill directly or let it activate via intent matching.

## Workflow Phases

### Phase 1: Understand
- gathers project context (files, docs, recent commits)
- asks questions one at a time, preferring multiple choice
- focuses on purpose, constraints, success criteria, integration points

### Phase 2: Explore Approaches
- proposes 2-3 different approaches with trade-offs
- leads with recommended option and reasoning
- user picks an approach before proceeding

### Phase 3: Present Design
- breaks design into 200-300 word sections
- validates each section incrementally with the user
- covers architecture, components, data flow, error handling, testing

### Phase 4: Next Steps
- **Write plan** — invokes the `planning:make` skill with the brainstorm context
- **Inline plan** — prepares a structured plan for approval
- **Start now** — begins implementing directly

## Examples

```
User: "let's brainstorm how to add caching to the API"
→ Phase 1: asks about cache scope, invalidation needs, performance goals
→ Phase 2: proposes in-memory LRU, Redis, HTTP cache headers
→ Phase 3: details selected approach section by section
→ Phase 4: user picks "Write plan" → the `planning:make` skill runs with full context

User: "brainstorm a better error handling strategy"
→ Phase 1: examines current error patterns, asks about requirements
→ Phase 2: proposes error wrapping, custom types, sentinel errors
→ Phase 3: designs the selected approach incrementally
→ Phase 4: user picks "Start now" → implementation begins

User: "add my Go rules to user-level brainstorm rules"
→ asks what rules to add, writes to the Codex user-level rules file
```

## Key Principles

- one question at a time — never overwhelm with multiple questions
- multiple choice preferred over open-ended when possible
- YAGNI ruthlessly — remove unnecessary features from designs
- always explore 2-3 alternatives before settling
- lead with recommendation, explain why, let user decide
- incremental validation catches misunderstandings early
