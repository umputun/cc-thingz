---
name: learn
description: Update local CLAUDE.md with strategic knowledge discovered during this session. Use when user says "learn", "save knowledge", "update claude.md", "capture learnings", or at end of significant work sessions. Also used by commit skill for pre-commit knowledge capture.
allowed-tools: Read, Edit, AskUserQuestion
---

# Learn

Review the current conversation history and identify strategic, reusable project knowledge that should be captured in the local CLAUDE.md file.

## Analysis Process

1. **Review Session History**
   - Examine all files read and modified during this session
   - Identify patterns discovered while working on tasks
   - Note architectural insights gained from exploring the codebase

2. **Extract Strategic Knowledge**
   - Filter out tactical details (bug fixes, specific implementations)
   - Focus on reusable patterns and project structure
   - Identify conventions and architectural decisions

3. **Categorize Findings**
   - Project architecture and structure
   - Data flow patterns
   - External service integrations
   - Project-specific conventions
   - Key dependencies and their purposes
   - Configuration patterns
   - Testing strategies
   - Build and deployment processes
   - Operational knowledge (debugging, DevOps)

## What Qualifies for Local CLAUDE.md

**INCLUDE** - Strategic discoveries from this session:
- Architectural patterns uncovered while working
- Project structure insights gained from navigation
- Conventions noticed across multiple files
- Integration patterns discovered
- Configuration approaches identified
- Testing strategies observed
- Build/deployment processes encountered
- Performance optimizations found
- Security implementations discovered
- Operational knowledge:
  - Database locations and connection details per environment
  - Useful queries discovered during debugging
  - Testing procedures and verification steps
  - Deployment workflows and commands
  - Log locations and monitoring endpoints
  - Environment-specific quirks and gotchas

**EXCLUDE** - Session-specific tactical work:
- The specific bug we fixed
- The particular feature we implemented
- Temporary workarounds we used
- One-off code changes
- TODO items we encountered
- Historical context about changes

## Decision Criteria

Ask yourself for each discovery:
- "Will this help understand the project in 6 months?"
- "Is this a pattern that appears multiple times?"
- "Does this represent a project-wide convention?"
- "Would knowing this speed up future development?"
- "Would this save debugging time in the future?" (for operational knowledge)

## Workflow

### 1. Check Existing Local CLAUDE.md
First, check if local CLAUDE.md exists and read its current content to avoid duplication.

### 2. Early Exit if Nothing Found
If no new strategic knowledge was discovered during this session:
- Report "no new strategic knowledge to capture"
- Do NOT use AskUserQuestion tool
- End the skill execution

### 3. New Knowledge to Add
Present discovered knowledge formatted for local CLAUDE.md:
```markdown
## [Section Name]
- Discovery 1
- Discovery 2
```

### 4. User Confirmation with AskUserQuestion Tool

**CRITICAL**: Use AskUserQuestion tool for granular selection of what to save.

Build options dynamically based on discoveries:
- First option: "All knowledge" - save everything discovered
- Last option before custom: "None" - skip saving entirely
- Middle options: Individual knowledge items (up to 2-3 most significant)
- User can always type custom selection via "Other"

Example with 3 discoveries:
```
question: "Which knowledge should I save to local CLAUDE.md?"
options:
  - label: "All (3 items)"
    description: "Save all discovered patterns"
  - label: "Testing pattern"
    description: "Table-driven tests with shared fixtures"
  - label: "Config approach"
    description: "Environment-based configuration loading"
  - label: "None"
    description: "Skip saving, nothing worth keeping"
```

Example with 1 discovery:
```
question: "Save this knowledge to local CLAUDE.md?"
options:
  - label: "Yes"
    description: "Save: [brief description of the discovery]"
  - label: "No"
    description: "Skip saving"
```

After user selection:
- "All" -> save everything
- "None" -> end without saving
- Specific item -> save only that item
- "Other" -> user types custom selection (comma-separated items or partial list)

## Important Guidelines
- Only capture genuinely new discoveries from this session
- Don't duplicate existing local or global CLAUDE.md content
- Focus on patterns observed, not specific code written
- Keep descriptions concise and actionable
- MUST use AskUserQuestion tool for confirmation (not plain text questions)
- If no knowledge found, exit early without asking
