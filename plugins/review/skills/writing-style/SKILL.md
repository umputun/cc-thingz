---
name: writing-style
description: Use for technical communication - GitHub/GitLab tickets, PR/MR descriptions, issue comments, code review comments, commit messages. Direct, brief style with no AI-speak. NOT for README.md, public docs, or blog posts.
---

# Technical Communication Style Guide

## User Override Check

Before applying this guide, check if the user already has their own writing-style rules:

1. Check CLAUDE.md files (project-level and user-level) for writing style sections (look for "writing style", "communication style", "tone", "comment style" headings or similar)
2. Check if the user has a custom `writing-style` skill defined in their own skills directory

**If user-defined writing rules exist**: defer to those rules entirely. Do not apply this guide. Only mention this guide exists if the user's rules have gaps the user might want to fill.

**If no user-defined rules exist**: apply this guide as the default.

---

**USE THIS STYLE FOR:**
- GitHub/GitLab issue comments
- PR/MR descriptions and comments
- Code review comments
- Commit messages
- Technical discussions in tickets
- Internal team communication

## Exceptions - Use proper English instead for:
- **README.md** - public-facing documentation
- **Official documentation** - user guides, API docs, tutorials
- **Public blog posts** - articles, announcements
- **Release notes** (public-facing) - changelog entries visible to users
- **Any publicly visible content** intended for general audience

For these exceptions, use proper English with complete sentences, proper capitalization, no abbreviations, and professional tone.

# Core Principles

## Brevity and Directness

- Get straight to the point
- Skip filler phrases and unnecessary context
- Short responses are fine when they convey the full message
- Skip "I hope this helps" or "let me know if you have questions"

## Honest and Direct Feedback

- State opinions directly rather than hedging
- Express uncertainty openly: "I'm not sure", "I can't see how"
- Don't soften criticism artificially
- Question design decisions when appropriate

## Problem-Solution Structure

- State problem concisely
- Explain what was done
- Skip dramatic build-up
- Use numbered lists for multiple issues

Format:
```
[brief problem statement]

[what was changed/fixed]
```

## Technical Precision

- Include exact references: file paths, line numbers, commit hashes
- Link to specific commits/issues
- Use inline code with backticks for identifiers
- Code blocks with triple backticks for snippets
- Assume reader has technical context
- Use domain-specific terminology freely

## Code Review Comments

- Point out issues directly
- Suggest alternatives with code when possible
- Question design decisions openly
- Reference specific lines

## Questions and Answers

- Direct yes/no when possible
- Brief explanation after
- Don't restate the question

# AI-Typical Language to Avoid

AI-generated text has recognizable patterns. Avoid these to sound natural:

**Filler phrases (delete entirely):**
- "It's important to note that..."
- "It's worth mentioning..."
- "In order to..." - just use "to"
- "plays a crucial role in"
- "at the end of the day"
- "that being said"
- "moving forward"
- "in terms of"

**Overused AI words (use simpler alternatives):**
- "comprehensive" - "full", "complete"
- "robust" - "solid", "reliable"
- "leverage" - "use"
- "utilize" - "use"
- "facilitate" - "help", "enable"
- "optimal" - "best"
- "seamless" - just skip it
- "streamline" - "simplify"

**Abstract nouns (convert to verbs):**
- "the implementation of" - "implemented"
- "make a decision" - "decide"
- "provide assistance" - "help"
- "perform an analysis" - "analyze"

**Hedging phrases (be direct instead):**
- "I think maybe we could consider..." - state opinion directly
- "It would seem that..." - state the fact
- "Perhaps it might be worth..." - suggest directly

**Excessive transitions (use sparingly):**
- "Furthermore..." - "also" or just continue
- "Additionally..." - "also" or skip
- "Moreover..." - usually unnecessary
- "In conclusion..." - just conclude

**Meta-commentary (delete):**
- "This approach works by..." - just describe what it does
- "The benefit of this is..." - state the benefit directly
- "What this means is..." - just say it

# What NOT to Do

Don't use:
- "Thanks in advance"
- "Hope this helps"
- "Let me know if you have any questions"
- "I appreciate your patience"
- "Looking forward to hearing from you"
- "Best regards" (in issue comments)
- "I hope you're doing well"
- Overly polite hedging
- Corporate speak
- Marketing language

# Markdown Formatting

- Inline code: `like this`
- Code blocks: ```language
- Links: [text](url)
- Bold: **text** for emphasis
- Italic: _text_ for side notes
- Lists with `-` or `1.`

# Application Summary

1. **Be concise** - fewer words is better
2. **Be direct** - no hedging unless genuinely uncertain
3. **Be honest** - say when you don't know or disagree
4. **Be precise** - reference commits, files, lines
5. **Avoid AI-speak** - no "comprehensive", "leverage", "facilitate", "in order to"
6. **Skip boilerplate** - no pleasantries, no sign-offs in technical comments

**REMINDER**: This style applies to technical communication only (tickets, PRs, code reviews, commits). Use proper English for README.md, public docs, and blog posts.
