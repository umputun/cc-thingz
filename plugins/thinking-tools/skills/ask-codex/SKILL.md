---
name: ask-codex
description: Consult OpenAI Codex for investigation, debugging, or code review. Use when user explicitly asks to "ask codex", "check with codex", "codex review", or as a last resort when stuck after 4+ failed attempts at debugging, investigation, or bug fix and completely out of ideas. Codex is slow (2-5 min), so only escalate when truly stuck. Codex runs in read-only mode with full project access — it analyzes, we implement.
allowed-tools: Bash, Read, Grep, Glob
---

# Ask Codex

Consult OpenAI Codex (GPT-5.5) as a second opinion for investigation, debugging, or review tasks.

## Activation Triggers

**Explicit:**
- "ask codex", "check with codex", "codex review"
- "what does codex think", "get codex opinion"
- "consult codex", "run codex on this"

**Automatic (last resort — stuck detection):**
- 4+ failed attempts at the same bug fix or investigation
- completely out of ideas, all reasonable approaches exhausted
- going in circles with no progress despite multiple different strategies

## Workflow

### Step 1: Check Availability

Run `which codex` to verify the CLI is installed. If not found, inform the user and stop.

### Step 2: Build Context

Gather context from the current conversation:

1. **What's the problem/question** — summarize in 2-3 sentences
2. **What we know** — relevant files, error messages, behavior observed
3. **What we tried** — approaches attempted and why they failed (if applicable)
4. **Specific question** — what exactly codex should analyze or answer

Codex does NOT auto-load Claude Code's memory files — it only reads `AGENTS.md`. To give Codex the same project context Claude follows, prepend the memory-load preamble described in Step 3.

### Step 3: Construct Prompt

Build a focused prompt. Do NOT dump entire files — codex has full project access and can read them itself. Provide file paths and line references so codex knows where to look.

**Prepend a memory-load preamble.** Codex auto-loads only `AGENTS.md`; it does NOT read Claude Code's memory files (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`, `~/.claude/CLAUDE.md`), so the project conventions Claude follows are invisible to Codex unless you tell it to read them. Prepend this line to the prompt:

```
First read these project guidance files if present: <ABS_HOME>/.claude/CLAUDE.md, CLAUDE.md, CLAUDE.local.md, .claude/rules/
```

- Resolve `<ABS_HOME>` to the **absolute** home path (run `echo $HOME`, e.g. `/home/<user>`) and write the literal path — do NOT leave the string `$HOME` in the prompt. Whether `$HOME` expands depends on how the prompt is passed to Codex, and Codex may open the file with a non-shell tool that never expands it, so only a literal absolute path is reliable.
- No `@` prefix — `@file` is inert in `codex exec` (literal text, not an import).
- The project-relative paths resolve against Codex's working directory; Codex skips any that don't exist.

**Template for investigation/debug:**

```
# [Investigation/Debug] Request

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

**Template for code review (adversarial):**

When asked for a code review, use this adversarial prompt that requires structured JSON output:

```
<role>
You are performing an adversarial code review.
Your job is to break confidence in the change, not to validate it.
</role>

<task>
Review the provided changes as if you are trying to find the strongest reasons
this change should not ship yet.
Scope: [files and changes to review — paths, branch diff, or description]
Focus: [specific area if user specified one, otherwise "general"]
</task>

<operating_stance>
Default to skepticism.
Assume the change can fail in subtle, high-cost, or user-visible ways until
the evidence says otherwise. Do not give credit for good intent or partial fixes.
If something only works on the happy path, treat that as a real weakness.
</operating_stance>

<attack_surfaces>
Prioritize failures that are expensive, dangerous, or hard to detect:
- auth, permissions, tenant isolation, and trust boundaries
- data loss, corruption, duplication, and irreversible state changes
- rollback safety, retries, partial failure, and idempotency gaps
- race conditions, ordering assumptions, stale state, and re-entrancy
- empty-state, nil, timeout, and degraded dependency behavior
- version skew, schema drift, migration hazards, and compatibility regressions
- observability gaps that would hide failure or make recovery harder
</attack_surfaces>

<finding_bar>
Report only material findings. No style feedback, naming nitpicks, or speculative
concerns without evidence. Each finding must answer:
1. What can go wrong?
2. Why is this code path vulnerable?
3. What is the likely impact?
4. What concrete change would reduce the risk?
Prefer one strong finding over several weak ones.
</finding_bar>

<grounding_rules>
Every finding must be defensible from actual code you can see.
Do not invent files, lines, code paths, or runtime behavior you cannot support.
If a conclusion depends on an inference, state that explicitly and keep the
confidence score honest.
</grounding_rules>

<structured_output>
Return ONLY valid JSON. Example with concrete values:
{
  "verdict": "needs-attention",
  "summary": "auth middleware skips token validation on retry paths",
  "findings": [
    {
      "severity": "high",
      "title": "token validation bypassed on retry",
      "body": "retryHandler re-enters serveHTTP without revalidating the bearer token, allowing expired tokens through on transient failures",
      "file": "internal/auth/middleware.go",
      "line_start": 42,
      "line_end": 55,
      "confidence": 0.85,
      "recommendation": "move token validation before the retry loop entry point"
    }
  ],
  "next_steps": ["add test for expired-token retry scenario"]
}

Allowed values:
- verdict: "approve" or "needs-attention"
- severity: "critical", "high", "medium", or "low"
- confidence: 0.0 to 1.0

Use "needs-attention" if there is any material risk worth blocking on.
Use "approve" only if you cannot support any substantive finding.
</structured_output>
```

### Step 4: Execute Codex

Run codex in background (it takes 2-5 minutes for complex analysis):

```bash
codex exec -m gpt-5.5 \
  --sandbox read-only \
  -c model_reasoning_effort="xhigh" \
  -c stream_idle_timeout_ms=600000 \
  "prompt here" < /dev/null
```

**Execution rules:**
- Always end the invocation with `< /dev/null` (as shown). `codex exec` reads stdin to append a `<stdin>` block even when the prompt is a positional arg, so an inherited open pipe (common under a background launch) never closes and codex blocks forever on "Reading additional input from stdin…"; `/dev/null` gives immediate EOF.
- Always use `run_in_background: true` in Bash tool
- Monitor with BashOutput every 15-20 seconds
- Be patient during reasoning phase (1-3 minutes of silence is normal)
- Total timeout: 10 minutes for standard, 15 for complex

**Flags:**
- `--sandbox read-only` — codex can read all project files but cannot modify anything
- `-m gpt-5.5` — latest model (adjust as newer versions become available)
- `model_reasoning_effort="xhigh"` — deepest reasoning tier

### Step 5: Present Results

1. **Extract codex's analysis** — skip session info, token counts, prompt echo
2. **Parse structured output** — for reviews, codex returns JSON; parse and present as structured findings
3. **Add your assessment** — agree, disagree, or note caveats
4. **STOP and ask** — do NOT apply any fixes or changes without explicit user approval

**For investigation/debug responses** (unstructured):

```
**Codex Analysis:**

[Codex's response — cleaned up and formatted]

---

**Assessment:** [Your 2-3 sentence evaluation]

**Proposed action:** [What codex suggests — awaiting approval]
```

**For review responses** (structured JSON):

Parse the JSON output and present findings sorted by severity, filtered by confidence:

```
**Codex Review: [verdict]**
[summary]

**Findings** (N issues):

1. **[critical]** title (confidence: 0.9)
   file.go:42-55
   [body]
   → [recommendation]

2. **[high]** title (confidence: 0.8)
   ...

**Next steps:** [list]

---

**Assessment:** [Your evaluation — which findings are valid, which are false positives]
```

- skip findings with confidence < 0.3 (likely noise)
- group by severity: critical → high → medium → low
- if verdict is "approve" and no findings, just say "codex found no material issues"

**CRITICAL: After presenting findings, STOP. Do not apply fixes, do not touch files, do not start implementing suggestions. Explicitly ask the user what to do next. Codex findings are input for discussion, not automatic work orders.**

## Important Rules

- **Read-only always** — codex analyzes, we implement. Never let codex edit files.
- **Don't duplicate files** — codex has full project access. Provide paths, not content.
- **Focused prompts** — specific questions get better answers than broad "review everything".
- **Background execution** — always run in background to avoid timeout issues.
- **One question at a time** — if multiple concerns, run separate codex queries.
- **Critical thinking** — codex can be wrong. Evaluate its suggestions before implementing.

## When NOT to Use

- Simple questions you already know the answer to
- Tasks where the solution is clear and just needs implementation
- File searches or codebase navigation (use Grep/Glob instead)

## Troubleshooting

- **Codex not found**: `which codex` — install via `npm install -g @openai/codex`
- **Authentication**: `codex login` if getting auth errors
- **Timeout**: increase `stream_idle_timeout_ms` for complex analyses
- **Off-target response**: refine prompt with more specific file:line references
- **Hangs on "Reading additional input from stdin…"**: the invocation is missing the `< /dev/null` stdin redirect — add it (see Step 4).
