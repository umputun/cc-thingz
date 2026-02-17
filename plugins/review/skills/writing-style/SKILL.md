---
name: writing-style
description: Use for technical communication - GitHub/GitLab tickets, PR/MR descriptions, issue comments, code review comments, commit messages. Direct, brief style with no AI-speak. NOT for README.md, public docs, or blog posts.
---

# Technical Communication Style Guide

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
- No pleasantries or filler
- One-word responses when appropriate: "done.", "fixed", "added"
- Skip "I hope this helps" or "let me know if you have questions"
- Examples:
  - "done. published to registry"
  - "fixed in latest commit"
  - "LGTM"

## Honest and Direct Feedback

- Say "I don't think so" directly
- Express uncertainty openly: "I'm not sure", "I can't see how"
- Don't soften criticism artificially
- Be blunt when warranted

Examples:
- "I don't like else construct, and this part will be simpler without"
- "this is odd"
- "I don't think this is enough because the images only support x86"

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

Example:
```
couple of issues here:

1. size calculated after processing, UI side had no way to match it. changed to raw size in the request body
2. unicode string length was incorrect - calculated size in bytes. fixed.
```

## Technical Precision

- Include exact references: file paths, line numbers, commit hashes
- Link to specific commits/issues
- Use inline code with backticks
- Code blocks with triple backticks

Examples:
- "see commit abc1234 for details"
- "check `pkg/handler/auth.go:42`"

## Minimal Punctuation

- Often omit periods at end of brief statements
- Comma splices common and acceptable
- Almost never use exclamation marks
- **Never use em-dashes** (--- or --) - use plain hyphens (-) or commas instead

## Context Assumptions

- Assume reader has technical context
- Don't over-explain basics
- Link to code/commits instead of lengthy explanations
- Use domain-specific terminology freely

## Code Review Comments

- Point out issues directly
- Suggest alternatives with code
- Question design decisions: "is it a good idea?", "why do we need this?"
- Reference specific lines

Examples:
- "is it a good idea? does it mean we expect docker to be in default build?"
- "I think this can be done directly on reader, without ReadAll putting potentially large []byte in memory"

## Questions and Answers

- Direct yes/no when possible
- Brief explanations after
- Don't restate the question

Examples:
- "yes, this is the correct one. are you sure this one is sending the cookie?"
- "no, unrelated. this issue is about caching of static assets on the browser side"

# AI-Typical Language to Avoid

AI-generated text has recognizable patterns. Avoid these to sound human:

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
- "comprehensive" - use "full", "complete"
- "robust" - use "solid", "reliable"
- "leverage" - use "use"
- "utilize" - use "use"
- "facilitate" - use "help", "enable"
- "ensure" - use "make sure"
- "enhance" - use "improve"
- "optimal" - use "best"
- "seamless" - just skip it
- "streamline" - use "simplify"

**Abstract nouns (convert to verbs):**
- "the implementation of" - "we implemented"
- "make a decision" - "decide"
- "provide assistance" - "help"
- "perform an analysis" - "analyze"

**Hedging phrases (be direct instead):**
- "I think maybe we could consider..." - state opinion directly
- "It would seem that..." - state the fact
- "Perhaps it might be worth..." - suggest directly

**Transition padding:**
- "Furthermore..." - "also" or just continue
- "Additionally..." - "also" or skip
- "Moreover..." - skip
- "In conclusion..." - skip (just conclude)

**Meta-commentary (delete):**
- "This approach works by..." - just describe what it does
- "The benefit of this is..." - state the benefit directly
- "What this means is..." - just say it

# What NOT to Do

Don't use:
- Em-dashes (--- or --) - use plain hyphens (-) or commas instead
- Exclamation marks (except very rarely)
- "Thanks in advance"
- "Hope this helps"
- "Let me know if you have any questions"
- Overly polite hedging
- Corporate speak
- Marketing language

Don't write:
- "I appreciate your patience"
- "Looking forward to hearing from you"
- "Best regards" (in issue comments)
- "I hope you're doing well"

# Markdown Formatting

- Inline code: `like this`
- Code blocks: ```language
- Links: [text](url)
- Bold: **text** (rare, only for emphasis)
- Italic: _text_ (for side notes, clarifications)
- Lists with `-` or `1.`

# Examples by Context

## Issue Comment

```
this is odd. the image is built the same way and I see all 3 supported archs

tried on arm64 - worked fine
```

## PR Review

```
I don't like else construct, and this part will be simpler without. the unnecessary calculation is justified by better readability.

newW, newH := w*limit/h, limit
if w > h {
    newW, newH = limit, h*limit/w
}
```

## Quick Response

```
done.
```

```
makes sense. changed.
```

## Problem Description

```
couple of issues here:

1. size calculated after processing, UI side had no way to match it. changed to raw size in request body
2. unicode string length was incorrect - calculated size in bytes. fixed.

still open - in safari UI doesn't allow entering full size due to EOL treatment.
```

## Technical Explanation

```
this was a tricky one. the "session" query param conflicted with the auth middleware and was treated as a token. had to rename the middleware param to avoid the collision. no changes needed on your side, should be back compatible.
```

# Application Summary

1. **Be concise** - fewer words is better
2. **Be direct** - no hedging unless genuinely uncertain
3. **Skip pleasantries** - get to the point
4. **Be honest** - say when you don't know or disagree
5. **Link, don't explain** - reference commits/code
6. **Question directly** - "is it a good idea?", "why?"
7. **Avoid AI-speak** - no "comprehensive", "leverage", "facilitate", "in order to"

**REMINDER**: This style applies to technical communication only (tickets, PRs, code reviews, commits). Use proper English for README.md, public docs, and blog posts.
