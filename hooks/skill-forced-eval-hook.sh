#!/bin/sh
# skill-forced-eval-hook.sh - UserPromptSubmit hook for Claude Code.
#
# forces Claude to evaluate and activate relevant skills before implementation.

cat <<'EOF'
INSTRUCTION: MANDATORY SKILL ACTIVATION

Check available skills for relevance before proceeding.

IF any skills are relevant:
  1. State which skills and why (can be multiple)
  2. Immediately activate ALL relevant skills with Skill(skill-name) tool calls
  3. Then proceed with task

IF no skills are relevant:
  - Proceed directly

Example of multiple skills:
  User asks "check mongo on server 192.168.1.111 for yesterday's data and report any issues"
  → Activate: datetime (for "yesterday"), mongo (for query), ssh (for server access)

CRITICAL: Activate ALL relevant skills via Skill() tool before implementation.
Multiple skills can and should be activated when applicable.
Mentioning a skill without activating it is worthless.
EOF
