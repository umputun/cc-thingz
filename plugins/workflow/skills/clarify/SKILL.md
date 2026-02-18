---
name: clarify
description: This skill should be used when user appears confused, frustrated, or shows misalignment between expectations and reality. Triggers on phrases like "I don't understand", "this doesn't make sense", "confused", "wait, shouldn't it...", "why is this happening", "I thought X did Y", contradictory statements, or frustration signals. Analyzes the confusion, explains the actual behavior, and determines if there's a real issue to address.
allowed-tools: EnterPlanMode, AskUserQuestion
---

# Clarify

Handle user confusion by verifying intent, explaining actual behavior, and determining if there's a real issue.

**Primary goal**: Clarify and explain, not fix. Most confusion stems from misunderstanding or forgetting, not from bugs.

## Activation Triggers

- "confused", "I'm confused", "this is confusing"
- "I don't understand", "doesn't make sense", "makes no sense"
- "wait, shouldn't it...", "but I thought..."
- "why is this happening", "why does this..."
- "I expected X but got Y"
- "this is wrong", "something's off"
- frustration signals, contradictory statements
- questions that reveal misconceptions about system behavior

## Important Context

Users often:
- **Work on multiple projects in parallel** and may confuse behaviors between them
- **Forget how things were implemented** especially after time away
- **Have outdated mental models** based on old versions or different projects
- **Mix up similar concepts** from different codebases or frameworks

But also:
- **Users are experienced developers** - their instincts are often correct
- **Real bugs exist** - about half of confusion cases point to actual issues
- **User expectations are reasonable** - if something feels wrong, investigate thoroughly

**Do not assume either way.** Investigate before concluding. Both outcomes are equally valid:
- User misremembered/mixed things up -> clarify with evidence
- System has a genuine issue -> proceed to plan mode for fix

## Workflow

### Phase 1: Identify the Confusion

1. **Extract the core question** - What specifically is the user asking about?
2. **Identify the expectation** - What did the user expect to happen?
3. **Identify the reality** - What is actually happening?
4. **Locate the gap** - Where is the misalignment?
5. **Consider context mixing** - Could user be thinking of a different project/feature?

Categories of confusion:
- **Memory gap** - user forgot how it works, needs a reminder
- **Project mixing** - user confused this with another project they're working on
- **Outdated mental model** - user's understanding is based on old behavior
- **Architectural** - misunderstanding system design, component relationships, data flow
- **Behavioral** - expecting different runtime behavior than what occurs
- **Configuration** - settings not producing expected results
- **Documentation** - docs don't match implementation or are unclear
- **Conceptual** - misunderstanding underlying concepts or patterns
- **Implementation** - code doesn't work as assumed

### Phase 2: Investigate

Before explaining, gather evidence:

1. **Read relevant code** - Understand actual implementation
2. **Check configuration** - Verify settings and their effects
3. **Review documentation** - See what's documented vs actual behavior
4. **Trace the flow** - Follow execution path if behavioral confusion

Do not guess or assume. Investigate the actual system state.

### Phase 3: Explain (Gently)

Structure the explanation with patience and care:

1. **Acknowledge the confusion** - Validate that it's understandable, confusion is normal
2. **State the expectation** - "You expected X to do Y"
3. **State the reality** - "Actually, X does Z because..."
4. **Explain why** - Provide the reasoning/design decision behind the behavior
5. **Show evidence** - Point to specific code, config, or docs

Tone guidelines:
- Be gentle, not condescending - user may have simply forgotten
- Avoid "you're wrong" framing - use "here's how it actually works"
- If user mixed up projects, clarify without judgment
- Remind that it's easy to forget details when working on multiple things

Keep explanations:
- Concrete, not abstract
- Backed by evidence from the codebase
- Focused on the specific case, not general theory

### Phase 4: Assess

**Start with the most common cases first:**

**A) Memory gap - user simply forgot**
- User implemented this but forgot how it works
- System is working exactly as designed
- Resolution: gentle reminder with code references

**B) Project mixing - wrong mental context**
- User is thinking of a different project or codebase
- This project works differently than user's current mental model
- Resolution: clarify which project this is and how it differs

**C) Outdated understanding**
- System changed since user last worked on it
- Or user's mental model never matched reality
- Resolution: explain current behavior with evidence

**D) Documentation issue**
- System works correctly but docs are misleading/missing
- Resolution: suggest updating docs, may use EnterPlanMode

**E) Configuration issue**
- System can do what user expects but isn't configured for it
- Resolution: suggest configuration changes

**F) Real issue - design or implementation problem**
- User's expectation is reasonable AND system genuinely doesn't meet it
- This indicates a bug, design flaw, or missing feature
- Resolution: **MUST proceed to Phase 5**

### Phase 5: Plan the Fix (for real issues)

If Phase 4 identified a real issue (category F):

#### Step 1: Summarize and Assess Scope

Explain to user what fixing this involves:

**Scope categories:**
- **Trivial** - Simple fix, single file, no side effects
- **Localized** - Few files, contained to one component
- **Moderate** - Multiple components affected, requires testing
- **Significant** - Cross-cutting concern, affects multiple subsystems
- **Architectural** - Fundamental design change, may require rethinking approach

Be explicit: "This is a [scope] change because [reason]."

User must understand the magnitude before deciding to proceed.

#### Step 2: Present Options (if multiple approaches exist)

When there are multiple valid solutions, use **AskUserQuestion** tool to present choices:

- List 2-4 options with clear trade-off descriptions
- Put recommended option first with "(Recommended)" suffix
- Include "Do nothing" as an option when relevant:
  - Issue is cosmetic or low-impact
  - Workaround exists
  - Fix is risky relative to benefit
  - Issue is edge case that rarely occurs
- Let user choose the approach

#### Step 3: Proceed to Plan Mode

After user confirms or selects an approach:

1. **Use EnterPlanMode** - Create implementation plan for the chosen approach
2. Plan should reflect the scope assessment from Step 1

**CRITICAL**: Do not attempt to fix issues without planning. Always use EnterPlanMode for:
- Bug fixes
- Design changes
- Missing features
- Documentation updates that require code understanding

## Response Format

```
## Understanding Your Confusion

**What you expected**: [user's expectation]
**What actually happens**: [actual behavior]

## Why This Happens

[Explanation with evidence - code references, config, docs]

## Assessment

[One of: Not an issue / Documentation issue / Real issue / Configuration issue]

[If real issue]:
This is a real issue that should be addressed. I recommend switching to plan mode to design a proper fix.

Should I enter plan mode to plan the solution?
```

## Guidelines

**Mindset:**
- Users are experienced developers - trust their instincts
- About half of confusion cases are real issues, half are misunderstandings
- Users work on many projects - confusion between them is normal
- Memory is fallible - be patient when reminding how things work

**Approach:**
- Never dismiss confusion as "user error" - investigate first
- Never assume something is broken without evidence either
- Always back explanations with evidence from the actual codebase
- If unsure, ask clarifying questions before investigating
- Keep the tone helpful, not condescending
- If the confusion reveals a real problem, treat it as valuable feedback
- Don't over-explain - focus on the specific confusion, not general tutorials

**Fixing:**
- **Investigate first, then determine outcome**
- If it's a misunderstanding -> explain clearly with evidence
- If it's a real issue -> proceed to plan mode for fix
- **Use EnterPlanMode when investigation confirms a genuine bug/flaw**
