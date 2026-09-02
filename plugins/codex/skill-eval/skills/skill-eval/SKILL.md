---
name: skill-eval
description: ALWAYS ACTIVATE before every response. Evaluate all available skills for relevance, announce the relevant skills and why, read their complete SKILL.md files, and follow every applicable workflow before proceeding. If no skill applies, proceed directly.
---

# Mandatory Skill Evaluation

The bundled `UserPromptSubmit` command hook injects these instructions for every prompt after the
user trusts the hook. This skill provides the same workflow when activated explicitly.

Before acting on the user's request:

1. Check the complete available-skills catalogue for semantic matches, including implicit matches.
2. If one or more skills apply, state which skills will be used and why.
3. Read every selected `SKILL.md` completely and follow its instructions.
4. When several skills apply, use the smallest set that covers the request and state the order.
5. If no skill applies, continue without announcing an empty selection.

Mentioning a skill is not activation. Its complete instructions must be read before task actions begin.
