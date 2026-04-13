# Brainstorm Usage

## Triggers

The brainstorm skill activates on:
- "brainstorm", "let's brainstorm"
- "deep analysis", "analyze this feature"
- "think through", "help me design"
- "explore options for"
- any request for thorough analysis of changes, features, or architectural decisions

Invoke directly with `/brainstorm:brainstorm` or let it activate via intent matching.

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
- **Write plan** — invokes `/planning:make` passing brainstorm context
- **Plan mode** — enters structured plan mode for detailed planning
- **Start now** — begins implementing directly

## Examples

```
User: "let's brainstorm how to add caching to the API"
→ Phase 1: asks about cache scope, invalidation needs, performance goals
→ Phase 2: proposes in-memory LRU, Redis, HTTP cache headers
→ Phase 3: details selected approach section by section
→ Phase 4: user picks "Write plan" → /planning:make runs with full context

User: "brainstorm a better error handling strategy"
→ Phase 1: examines current error patterns, asks about requirements
→ Phase 2: proposes error wrapping, custom types, sentinel errors
→ Phase 3: designs the selected approach incrementally
→ Phase 4: user picks "Start now" → implementation begins

User: "/brainstorm:brainstorm add my Go rules to user-level brainstorm rules"
→ asks what rules to add, writes to $CLAUDE_PLUGIN_DATA/brainstorm-rules.md
```

## Key Principles

- one question at a time — never overwhelm with multiple questions
- multiple choice preferred over open-ended when possible
- YAGNI ruthlessly — remove unnecessary features from designs
- always explore 2-3 alternatives before settling
- lead with recommendation, explain why, let user decide
- incremental validation catches misunderstandings early
