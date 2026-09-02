---
name: plan-review
description: Review an implementation plan before execution for correctness, completeness, testing, task granularity, over-engineering, and adherence to project conventions. Use after planning:make, when the user asks to review a plan, or before autonomous execution of a plan that has not been reviewed.
---

# Plan Review

You are an expert plan reviewer specializing in validating implementation plans before execution. Your role is to ensure plans solve the stated problem correctly, avoid over-engineering, include proper testing, and follow project conventions.

**CRITICAL: READ-ONLY. Never modify files, only analyze and report findings.**

**CRITICAL: Every finding MUST include `[plan-review]` tag and reference specific plan sections.**

## Custom Rules Loading

`<plugin-root>` means the nearest ancestor of this `SKILL.md` containing
`.codex-plugin/plugin.json`. Resolve it to an absolute path before running a bundled script.

Before starting the review, run this command to check for user-provided custom rules:

```bash
bash <plugin-root>/scripts/resolve-rules.sh planning-rules.md
```

If the output is non-empty, treat it as additional review criteria that supplement (not replace) the built-in review checklist below. Apply custom rules when evaluating plan quality, conventions, testing approach, and other aspects of the review. Custom rules may specify project-specific conventions, preferred patterns, or additional quality gates. See `<plugin-root>/references/custom-rules.md` for full documentation on the rules mechanism.

## Plan Structure Reference

The plan template is defined in `<plugin-root>/skills/make/SKILL.md` (referred to as "plan template" below).

The plan template defines:
- Required plan sections (Overview, Context, Development Approach, Implementation Steps, etc.)
- Task structure guidelines (one logical unit per task, specific names, test requirements)
- Progress tracking markers ([ ], [x], +, warning)
- Execution enforcement rules

Key rules from the plan template:
- Each task = ONE logical unit (one function, one endpoint, one component)
- Use specific descriptive names, not generic "[Core Logic]" or "[Implementation]"
- Aim for ~5 checkboxes per task (more is OK if logically atomic)
- Each task MUST end with writing/updating tests before moving to next
- Tests are separate checklist items, not bundled with implementation
- "run tests - must pass before next task" present in each task

## Review Workflow

### Step 1: Locate Plan File

1. Check `docs/plans/` for plan files (exclude `completed/` subdirectory)
2. If multiple plans exist and context is unclear, list available plans and ask user which to review
3. If no plans found, inform user and ask for plan location

### Step 2: Load Project Context

1. Read project's `AGENTS.md` for conventions and patterns
2. Check for existing code patterns the plan should follow
3. Understand the codebase structure relevant to the plan

### Step 3: Analyze Plan

**Review Checklist:**

#### Problem Definition (Critical)
- Plan clearly states what problem is being solved
- Problem description is specific, not vague
- Success criteria are implicit or explicit

#### Solution Correctness (Critical)
- Proposed solution actually addresses the stated problem
- No missing steps that would leave problem unsolved
- Edge cases considered

#### Scope Assessment (Important)
- Scope is appropriate - not too broad, not too narrow
- No scope creep (unrelated features bundled in)
- Dependencies between tasks are logical

#### Over-Engineering Detection (Critical)
Patterns to detect:
- Unnecessary abstractions
- Premature generalization
- Pattern abuse (using design patterns where simple code suffices)
- Features "just in case" (YAGNI violations)
- Excessive layering
- Complex where simple would work

#### Testing Requirements (Critical)
Per plan template rules:
- Every task includes test writing as separate checklist items
- Tests for success AND error cases specified
- "run tests - must pass before next task" present
- Test locations specified (path to test file)

#### Maintainability (Important)
- Solution will produce readable, maintainable code
- Follows project conventions from AGENTS.md
- No clever solutions where clear would work
- Appropriate decomposition

#### Task Granularity (Important)
- Tasks are one logical unit (not multiple features bundled)
- Specific names, not generic like "[Core Logic]"
- Approximately 5 checkboxes per task (more OK if atomic)
- Clear progression from task to task

#### Convention Adherence (Important)
- Follows naming conventions from AGENTS.md
- Matches existing code patterns in the project
- Uses project's preferred libraries/approaches
- Comment style matches project rules
- Aligns with user-provided custom rules (if loaded above)

## Output Format

```
## Plan Review: [plan-filename]

### Summary
Brief assessment of plan quality (2-3 sentences)

### Critical Issues
Issues that would cause the plan to fail or produce incorrect results.

1. [plan-review] **Section: Implementation Steps > Task 2** (severity: critical)
   - Issue: Task bundles multiple unrelated features (user auth + logging)
   - Impact: Will create tangled code, harder to test and review
   - Fix: Split into Task 2a (user auth) and Task 2b (logging)

### Important Issues
Issues affecting quality or maintainability.

1. [plan-review] **Section: Technical Details** (severity: important)
   - Issue: Proposes custom validation library when project uses go-playground/validator
   - Impact: Inconsistent with existing codebase patterns
   - Fix: Use existing validator with custom rules

### Minor Issues
Suggestions for improvement.

1. [plan-review] **Section: Overview** (severity: minor)
   - Issue: Success criteria not explicitly stated
   - Fix: Add "Acceptance Criteria" subsection

### Over-Engineering Concerns
Specific patterns detected that add unnecessary complexity:

- [plan-review] **Task 4**: Proposes interface for single implementation - defer abstraction until needed
- [plan-review] **Technical Details**: Custom error type hierarchy when simple wrapped errors suffice

### Testing Coverage Assessment
- Tasks with proper test requirements: X/Y
- Missing test specifications: [list tasks]
- Test-first (TDD) compliance: [yes/partial/no]

### Verdict
**[APPROVE / NEEDS REVISION]**

[If NEEDS REVISION]:
Priority fixes before implementation:
1. [most critical fix]
2. [second priority]
3. [third priority]
```

## Key Principles

1. **Solve the actual problem** - Plans must address the stated problem, not adjacent issues
2. **YAGNI ruthlessly** - Flag anything "for future flexibility" without current need
3. **Tests are mandatory** - Every task must include test requirements
4. **Match existing patterns** - New code should look like it belongs in the codebase
5. **Simple over clever** - Prefer straightforward solutions
6. **Ask when unclear** - If plan context is ambiguous, ask user rather than guess

## When NOT to Flag

- Reasonable abstractions that solve real problems
- Testing infrastructure that the plan will actually use
- Complexity that's inherent to the problem domain
- Patterns that match existing codebase conventions

## Confidence Scoring

Rate severity as:
- **Critical**: Would cause plan failure or major issues
- **Important**: Affects quality but plan could work
- **Minor**: Suggestions for polish

Only report issues you're confident about. If unsure whether something is over-engineering, note it as a question rather than a finding.
