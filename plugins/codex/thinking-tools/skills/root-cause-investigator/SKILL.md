---
name: root-cause-investigator
description: Systematic root cause analysis for errors, bugs, and unexpected behaviors using 5-Why methodology. Use when user reports errors, build failures, test failures, performance issues, integration problems, or any "it's not working" scenarios.
---

# Root Cause Investigator

Apply systematic 5-Why methodology to identify fundamental root causes of issues rather than treating symptoms. Guide thorough investigation through structured evidence gathering and analysis.

## Activation Triggers

- errors, bugs, or unexpected behavior
- build failures or test failures
- performance issues or degradation
- integration problems
- any "it's not working" scenarios

## The 5-Why Methodology

Systematically ask "why" five times to drill down to root cause:

1. **Why #1**: identify immediate cause (symptoms)
2. **Why #2**: uncover process/workflow issues
3. **Why #3**: find system-level problems
4. **Why #4**: discover design/architecture issues
5. **Why #5**: reveal fundamental root cause

## Investigation Workflow

### 1. Gather Initial Context

Collect information about the issue:

```
## Issue Summary
[brief description of reported problem]

## Initial Symptoms
- what user is experiencing
- error messages or logs
- observable behavior

## Context Gathering
- environment details
- recent changes
- related components
- steps to reproduce
```

### 2. Apply 5-Why Analysis

Structure the investigation with progressive depth:

```
## 5-Why Analysis

### Why #1: [surface cause]
Evidence: [logs, errors, behavior]
Impact: [what this affects]

### Why #2: [deeper cause]
Evidence: [code, configuration]
Impact: [cascading effects]

### Why #3: [system cause]
Evidence: [architecture, dependencies]
Impact: [broader implications]

### Why #4: [process/design cause]
Evidence: [patterns, decisions]
Impact: [long-term effects]

### Why #5: [root cause]
Evidence: [fundamental issue]
Impact: [core problem]
```

### 3. Identify Root Cause

Document the fundamental issue requiring attention:

```
## Root Cause Identified
[the fundamental issue that needs addressing]

## Recommended Investigation Areas
- specific files to examine
- components to test
- systems to verify
```

## Investigation Principles

1. **Avoid solution bias** - focus on understanding before fixing
2. **Gather evidence** - don't assume, verify with data
3. **Consider multiple causes** - issues often have multiple contributing factors
4. **Document findings** - clear documentation prevents repeat issues
5. **Think systemically** - consider broader implications
6. **Question assumptions** - challenge "it should work" thinking
7. **Use version control** - check when issue was introduced

## Using Reference Materials

Load reference files as needed during investigation:

- **references/patterns.md** - common root cause patterns by category (configuration, race conditions, resource exhaustion, integration failures, build/deployment issues)
- **references/techniques.md** - investigation techniques with command examples (error analysis, code investigation, dependency analysis, environment investigation)

## Best Practices

- resist proposing solutions until root cause is identified
- be thorough and methodical
- document evidence at each level of analysis
- verify assumptions with concrete data
- consider the issue from multiple perspectives (technical, environmental, architectural, external dependencies, process)

The goal is to find the fundamental cause, not just fix symptoms.
