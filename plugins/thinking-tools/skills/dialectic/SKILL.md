---
name: dialectic
description: Prove and counter-prove a statement using parallel agents to eliminate confirmation bias. Use when someone says "dialectic", "prove/disprove", "stress test this claim", "is this really true", "argue both sides", or when a statement needs objective analysis from opposing viewpoints.
argument-hint: '<statement to analyze>'
allowed-tools: Bash, Read, Grep, Glob, Task, AskUserQuestion
---

# Dialectic Analysis

Objective analysis of a statement by running two agents with opposing goals in parallel, then synthesizing findings.

## Process

### Step 1: Launch Parallel Agents

**CRITICAL: Both Task tool calls MUST be in a single message for true parallel execution.** Do NOT use run_in_background. Do NOT launch sequentially. Foreground agents in the same message run in parallel and block until both complete.

**Agent 1 (Thesis)** — find all POSITIVE evidence:
- what works well, improvements, correct patterns
- supporting facts, proof the statement is TRUE
- benefits, strengths, successful outcomes

**Agent 2 (Antithesis)** — find all NEGATIVE evidence:
- what's problematic, issues, risks, anti-patterns
- edge cases, proof the statement is FALSE
- weaknesses, failure modes, hidden costs

Both agents must provide specific file paths and line numbers when analyzing code.

### Step 2: Synthesize

After both agents complete, synthesize findings into an objective conclusion:
- weigh evidence from both sides
- identify where thesis and antithesis agree (strongest signal)
- note unresolved tensions

### Step 3: Verify

**CRITICAL** — after presenting the synthesis, verify it against actual implementation:
- read the specific files and line numbers referenced by both agents
- confirm the evidence cited actually exists in the codebase
- check the implementation flow matches the claims made
- verify the synthesis accurately reflects the actual code context
- identify any misinterpretations or missing context from agent reports
- revise synthesis if verification reveals inaccuracies

## Use Cases

**Architecture decisions:**
```
/thinking-tools:dialectic this microservice split improves maintainability
```

**Bug analysis:**
```
/thinking-tools:dialectic the connection pool fixes the timeout issue
```

**Performance claims:**
```
/thinking-tools:dialectic caching reduced database load by 80%
```

**Refactoring safety:**
```
/thinking-tools:dialectic extracting this interface simplifies testing
```

**Code review:**
```
/thinking-tools:dialectic this implementation is thread-safe
```

**Review changes:**
```
/thinking-tools:dialectic review the changes in server.go
```

## Key Principles

- **Eliminate confirmation bias** — examining both sides simultaneously prevents anchoring on the first conclusion
- **Evidence-based** — agents must cite specific files, lines, and facts, not general claims
- **Verification required** — synthesis must be checked against actual code before presenting
- **Objective conclusion** — the goal is truth, not winning either side
