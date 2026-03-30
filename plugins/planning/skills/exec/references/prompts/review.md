# Review orchestration prompt

Use this prompt when spawning the review agent (replace `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, `REVIEW_PHASE`, and `RESOLVE_SCRIPT`).

The review agent launches individual review agents, collects findings, and reports back. It does NOT fix anything — the orchestrator passes findings to the fixer.

## Phase 1 — comprehensive (5 agents)

Used when `REVIEW_PHASE` is `comprehensive`.

For each agent, resolve its prompt file using the resolve script:
```
bash RESOLVE_SCRIPT agents/quality.txt
bash RESOLVE_SCRIPT agents/implementation.txt
bash RESOLVE_SCRIPT agents/testing.txt
bash RESOLVE_SCRIPT agents/simplification.txt
bash RESOLVE_SCRIPT agents/documentation.txt
```

Read the resolved content for each agent. Replace `DEFAULT_BRANCH` with the actual value in each prompt. Prepend each agent prompt with:

"CRITICAL: You are a READ-ONLY reviewer. Do NOT run git stash, git checkout, git reset, or any command that modifies the working tree. Other agents run in parallel. Only use git diff, git log, git show, and read files.

Run `git diff DEFAULT_BRANCH...HEAD` to see all changes. Read the actual source files for full context — do not review from diff alone.

The plan file at PLAN_FILE_PATH describes the goal and requirements — use it to understand what the code is supposed to do.

Read the progress file at PROGRESS_FILE_PATH for context on previous review iterations and fixes. Re-evaluate all findings independently — previous fixes may be incomplete or wrong, and previously dismissed issues may be real."

Launch all 5 in parallel — send ALL 5 Agent tool calls in a SINGLE message. Use `mode: "bypassPermissions"`, `subagent_type: "general-purpose"` for each.

After ALL 5 agents return:
- Collect and deduplicate findings from all agents
- Same file:line + same issue — merge
- Report ALL findings — do NOT verify, fix, or dismiss any
- ONLY include agents that reported actual issues — omit agents that found nothing
- List each finding as: agent-name: file:line — description

## Phase 2 — critical only (2 agents)

Used when `REVIEW_PHASE` is `critical`.

Resolve only `quality.txt` and `implementation.txt` using the resolve script. Prepend each agent prompt with: "Report ONLY critical and major issues — bugs, security vulnerabilities, data loss risks, broken functionality, incorrect logic, missing critical error handling. Ignore style, minor improvements, suggestions."

Launch both in parallel. Same format as Phase 1.

After BOTH agents return:
- Same collection/deduplication as Phase 1
- Only keep critical/major severity findings
