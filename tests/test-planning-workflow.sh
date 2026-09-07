#!/bin/bash
# exercise the review and completion commands documented by the exec skill

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$REPO_ROOT" <<'PY'
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop())
EXEC = ROOT / "plugins/planning/skills/exec"
SKILL = (EXEC / "SKILL.md").read_text()


class ExecWorkflowTests(unittest.TestCase):
    def test_external_review_includes_committed_fixes(self):
        with tempfile.TemporaryDirectory() as work:
            env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")

            def git(*args):
                return subprocess.run(
                    ["git", *args], cwd=work, env=env, check=True,
                    capture_output=True, text=True,
                ).stdout

            git("init", "-q", "-b", "main")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            source = Path(work) / "code.txt"
            source.write_text("before\n")
            git("add", "code.txt")
            git("commit", "-qm", "Initial")
            git("switch", "-qc", "task")
            source.write_text("fixed\n")
            git("commit", "-qam", "Fix review finding")
            self.assertEqual(git("status", "--porcelain"), "")

            instruction = next(
                line for line in SKILL.splitlines()
                if line.startswith("1. **Resolve the review prompt**")
            )
            prompt = (EXEC / "references/prompts/codex-review.md").read_text()
            for name, text in (("exec skill", instruction), ("review prompt", prompt)):
                commands = re.findall(r"`(git diff[^`]*)`", text)
                self.assertTrue(commands, f"No review command found in {name}")
                for command in commands:
                    with self.subTest(source=name, command=command):
                        args = shlex.split(command.replace("DEFAULT_BRANCH", "main"))
                        self.assertIn("+fixed\n", git(*args[1:]))

    def test_completion_collects_timestamped_and_plain_decisions(self):
        with tempfile.TemporaryDirectory() as work:
            progress = Path(work) / "progress.txt"
            append = ["bash", str(EXEC / "scripts/append-progress.sh"), str(progress)]
            subprocess.run([*append, "task 1: completed"], check=True)
            for marker in ("decision", "deviation"):
                subprocess.run([*append, f"[{marker}] task 1: timestamped"], check=True)
            subprocess.run(
                append,
                input=(
                    "[decision] task 2: plain\n[deviation] task 2: plain\n"
                    "Review finding: quoted [decision] and [deviation] markers.\n"
                ),
                text=True, check=True,
            )
            expression = re.search(r"grep -E '([^']*decision[^']*)'", SKILL)
            self.assertIsNotNone(expression, "No completion collector found")
            result = subprocess.run(
                ["grep", "-E", expression.group(1), str(progress)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            entries = [
                re.sub(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ", "", line)
                for line in result.stdout.splitlines()
            ]
            self.assertEqual(entries, [
                "[decision] task 1: timestamped",
                "[deviation] task 1: timestamped",
                "[decision] task 2: plain",
                "[deviation] task 2: plain",
            ])


unittest.main(verbosity=2)
PY
