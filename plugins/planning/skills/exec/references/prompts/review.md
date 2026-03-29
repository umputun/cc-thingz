# Review orchestration prompt

Use this prompt when spawning the review agent (replace `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH`, and `REVIEW_PHASE`).

The review agent launches individual review agents, collects findings, and reports back. It does NOT fix anything — the orchestrator passes findings to the fixer.

## Phase 1 — comprehensive (5 agents)

Used when `REVIEW_PHASE` is `comprehensive`.

Launch all 5 in parallel — send ALL 5 Agent tool calls in a SINGLE message. Use `mode: "bypassPermissions"`, `subagent_type: "general-purpose"` for each.

For each agent, resolve the prompt file through the override chain:
1. Check project `.claude/exec-plan/agents/<name>.txt` — use if it exists
2. Else check `${CLAUDE_PLUGIN_DATA}/agents/<name>.txt` — use if it exists
3. Else use `${CLAUDE_PLUGIN_ROOT}/skills/exec/references/agents/<name>.txt`

Read the resolved file and use its content as the agent prompt. Replace `DEFAULT_BRANCH` with the actual value in each prompt.

**Agent 1** — resolve `quality.txt`
**Agent 2** — resolve `implementation.txt`
**Agent 3** — resolve `testing.txt`
**Agent 4** — resolve `simplification.txt`
**Agent 5** — resolve `documentation.txt`

After ALL 5 agents return:
- Collect and deduplicate findings from all agents
- Same file:line + same issue — merge
- Report ALL findings — do NOT verify, fix, or dismiss any
- ONLY include agents that reported actual issues — omit agents that found nothing
- List each finding as: agent-name: file:line — description

## Phase 2 — critical only (2 agents)

Used when `REVIEW_PHASE` is `critical`.

Launch both in parallel. Same override chain resolution as Phase 1.

Prepend each agent prompt with: "Report ONLY critical and major issues — bugs, security vulnerabilities, data loss risks, broken functionality, incorrect logic, missing critical error handling. Ignore style, minor improvements, suggestions."

**Agent 1** — resolve `quality.txt`
**Agent 2** — resolve `implementation.txt`

After BOTH agents return:
- Same collection/deduplication as Phase 1
- Only keep critical/major severity findings
