#!/bin/sh
# UserPromptSubmit hook for Codex.

cat <<'EOF'
INSTRUCTION: MANDATORY SKILL EVALUATION

Before acting:
1. Check the complete available skills catalogue for relevant skills.
2. If any are relevant, state which skills apply and why.
3. Read each selected SKILL.md completely before acting.
4. Follow every selected workflow, using the smallest set that covers the request.

If no skill applies, proceed directly.
EOF
