---
name: ask-codex
description: Consult OpenAI Codex (GPT-5) for investigation, debugging, or code review. This skill should be used when user explicitly asks to "ask codex", "check with codex", "codex review", "get codex opinion", or "consult codex".
allowed-tools: Bash, Read, Grep, Glob
---

# Ask Codex

Consult OpenAI Codex (GPT-5) as a second opinion for investigation, debugging, or review tasks. Codex runs in read-only mode with full project access — it analyzes, Claude implements.

## Activation Triggers

- "ask codex", "check with codex", "codex review"
- "what does codex think", "get codex opinion"
- "consult codex", "run codex on this"

## Workflow

### Step 1: Check Availability

Run `which codex` to verify the CLI is installed. If not found, inform the user and stop.

### Step 2: Build Context

Gather context from the current conversation:

1. **What's the problem/question** — summarize in 2-3 sentences
2. **What we know** — relevant files, error messages, behavior observed
3. **What we tried** — approaches attempted and why they failed (if applicable)
4. **Specific question** — what exactly codex should analyze or answer

### Step 3: Construct Prompt

Build a focused prompt. Do NOT dump entire files — codex has full project access and can read them itself. Provide file paths and line references so codex knows where to look.

**Template:**

```
# [Investigation/Debug/Review] Request

## Problem
[2-3 sentence description]

## Context
- Files: [path/to/file.go:lineNumber, ...]
- Observed: [what's happening]
- Expected: [what should happen]

## What We Tried
[List approaches and outcomes, or "First consultation" if fresh question]

## Question
[Specific, focused question for codex to answer]

Provide:
1. Root cause analysis (if debugging)
2. Concrete recommendation with file:line references
3. Why previous approaches failed (if applicable)

Keep response focused and actionable.
```

### Step 4: Execute Codex

Run codex in background (it takes 2-5 minutes for complex analysis):

```bash
codex exec -m gpt-5 \
  --sandbox read-only \
  -c model_reasoning_effort="high" \
  -c stream_idle_timeout_ms=600000 \
  -c project_doc="./CLAUDE.md" \
  "prompt here"
```

**Execution rules:**
- Always use `run_in_background: true` in Bash tool
- Monitor with BashOutput every 15-20 seconds
- Be patient during reasoning phase (1-3 minutes of silence is normal)
- Total timeout: 10 minutes for standard, 15 for complex

**Flags:**
- `--sandbox read-only` — codex can read all project files but cannot modify anything
- `-m gpt-5` — codex model (adjust to latest available)
- `model_reasoning_effort="high"` — maximum reasoning depth
- `project_doc` — passes CLAUDE.md as project context

### Step 5: Present Results

1. **Extract codex's analysis** — skip session info, token counts, prompt echo
2. **Present findings** clearly formatted
3. **Add assessment** — agree, disagree, or note caveats
4. **Propose next steps** — ask if user wants to implement the suggestion

**Output format:**

```
**Codex Analysis:**

[Codex's response — cleaned up and formatted]

---

**Assessment:** [2-3 sentence evaluation of codex's findings]

**Next steps:** [What to do with this information]
```

## Important Rules

- **Read-only always** — codex analyzes, Claude implements. Never let codex edit files.
- **Don't duplicate files** — codex has full project access. Provide paths, not content.
- **Focused prompts** — specific questions get better answers than broad "review everything".
- **Background execution** — always run in background to avoid timeout issues.
- **One question at a time** — if multiple concerns, run separate codex queries.
- **Critical thinking** — codex can be wrong. Evaluate its suggestions before implementing.
