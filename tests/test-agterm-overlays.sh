#!/usr/bin/env bash
# Focused stub-only regressions for planning/review agterm paths.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 - "$ROOT" <<'PY'
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
root = Path(sys.argv[1])
modules = []
for name, relative in (
    ("plan", "plugins/planning/scripts/plan-annotate.py"),
    ("git", "plugins/review/skills/git-review/scripts/git-review.py"),
):
    spec = importlib.util.spec_from_file_location(name, root / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    modules.append(module)
launcher = root / "plugins/planning/scripts/launch-plan-review.sh"

class TestAgterm(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="overlay-stubs-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / "bin"
        self.app = self.base / "app"
        self.bin.mkdir()
        self.app.mkdir()
        self.file = self.base / "plan 'quoted'; $(touch nope).md"
        self.file.write_text("plan\n")
        self.log = self.base / "log"
        self.state = self.base / "state"
        self.args = self.base / "args"
        self.surfaces = [dict(kind="left", paneID="sibling", visible=True),
                         dict(kind="right", paneID="mine", visible=True)]
        self.env = dict(HOME=str(self.base), PATH=f"{self.bin}:/usr/bin:/bin", TMPDIR=str(self.base),
                        AGTERM_ENABLED="1", AGTERM_SESSION_ID="owner", AGTERM_PANE_ID="mine",
                        AGTERM_PANE="left", AGTERM_SOCKET="/tmp/owner socket", AGTERM_WINDOW_ID="window",
                        KITTY_LISTEN_ON="inherited", TMUX="inherited", EDITOR=f"{self.bin / 'editor'} '' 'a b'",
                        TEST_LOG=str(self.log), TEST_STATE=str(self.state), TEST_ARGS=str(self.args))
        self.stub("agtermctl", '''
a = sys.argv[1:]
with open(os.environ["TEST_LOG"], "a") as f:
    f.write(json.dumps([sys.argv[0], a]) + "\\n")
if a[:1] == ["tree"]:
    print(os.environ["TEST_TREE"])
elif a == ["session", "status", "--help"]:
    print("--pane-id")
elif a[:2] == ["session", "status"]:
    if os.environ.get("TEST_STATUS_FAIL"):
        sys.exit(6)
    Path(os.environ["TEST_STATE"]).write_text(a[2] + " mine")
elif a[:3] == ["session", "overlay", "open"]:
    mode = os.environ.get("TEST_MODE", "run")
    if mode == "refused":
        sys.exit(7)
    if mode == "replaced":
        sys.exit(int(os.environ.get("TEST_CTL_RC", "0")))
    r = subprocess.run(["/bin/bash", "-c", a[3]])
    sys.exit(int(os.environ.get("TEST_CTL_RC", str(r.returncode))))
else:
    sys.exit(9)
''')
        editor = '''
Path(os.environ["TEST_ARGS"]).write_text(json.dumps(sys.argv[1:]))
for arg in sys.argv[1:]:
    if arg.startswith("--output="):
        Path(arg.split("=", 1)[1]).write_text(os.environ.get("TEST_OUTPUT", ""))
if os.environ.get("TEST_SIGNAL"):
    os.kill(os.getppid(), getattr(signal, "SIG" + os.environ["TEST_SIGNAL"]))
    sys.exit(0)
sys.exit(int(os.environ.get("TEST_REVIEW_RC", "0")))
'''
        self.stub("editor", editor)
        self.stub("revdiff", editor)
        for name in ("kitty", "tmux"):
            self.stub(name, 'raise AssertionError("inherited backend must not run")')
        (self.app / "agtermctl").write_bytes((self.bin / "agtermctl").read_bytes())
        (self.app / "agtermctl").chmod(0o755)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\nimport json, os, signal, subprocess, sys\nfrom pathlib import Path\n" + body)
        path.chmod(0o755)

    def run_backend(self, backend, **overrides):
        self.log.write_text("")
        self.state.write_text("blocked sibling")
        env = dict(self.env, TEST_TREE=json.dumps({"result": {"tree": {"workspaces": [
            {"sessions": [{"id": "owner", "surfaces": self.surfaces}]}]}}}), **overrides)
        if backend == "shell":
            result = subprocess.run(["/bin/bash", str(launcher), str(self.file)], env=env,
                                    capture_output=True, text=True, cwd=self.base)
            rc, output = result.returncode, result.stdout
        else:
            with patch.dict(os.environ, env, clear=True), contextlib.redirect_stderr(io.StringIO()):
                rc = modules[backend].open_editor(self.file)
            output = ""
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return rc, output, calls

    def test_routing_quoting_owner_and_exit(self):
        for backend in (0, 1, "shell"):
            with self.subTest(backend=backend):
                rc, output, calls = self.run_backend(backend, TEST_OUTPUT="annotations")
                self.assertEqual(rc, 0)
                overlay = next(a for _, a in calls if a[:3] == ["session", "overlay", "open"])
                for flag, value in (("--target", "owner"), ("--socket", "/tmp/owner socket"),
                                    ("--window", "window"), ("--pane", "right")):
                    self.assertEqual(overlay[overlay.index(flag) + 1], value)
                self.assertNotIn("--size-percent", overlay)
                self.assertEqual(self.state.read_text(), "active mine")
                status = [a for _, a in calls if a[:2] == ["session", "status"] and a[2] != "--help"]
                self.assertEqual([a[2] for a in status], ["blocked", "active"])
                for call in status:
                    for flag, value in (("--target", "owner"), ("--socket", "/tmp/owner socket"),
                                        ("--window", "window"), ("--pane-id", "mine")):
                        self.assertEqual(call[call.index(flag) + 1], value)
                args = json.loads(self.args.read_text())
                if backend == "shell":
                    self.assertEqual(output, "annotations")
                    self.assertIn("--only=" + str(self.file), args)
                else:
                    self.assertEqual(args, ["", "a b", str(self.file)])
                self.assertFalse((self.base / "nope").exists())
                rc, _, _ = self.run_backend(backend, TEST_REVIEW_RC="4")
                self.assertEqual(rc, 4)
        self.assertEqual(self.run_backend("shell", TEST_REVIEW_RC="10")[0], 0)
        self.assertEqual(self.run_backend(0, TEST_REVIEW_RC="10")[0], 10)

    def test_refusal_replacement_and_status_failure(self):
        for backend in (0, 1, "shell"):
            for mode, ctl, expected in (("refused", "0", 7), ("replaced", "0", 1), ("replaced", "23", 23)):
                with self.subTest(backend=backend, mode=mode, ctl=ctl):
                    rc, _, calls = self.run_backend(backend, TEST_MODE=mode, TEST_CTL_RC=ctl)
                    self.assertEqual(rc, expected)
                    self.assertEqual(self.state.read_text(), "blocked sibling")
                    self.assertEqual(sum(a[:3] == ["session", "overlay", "open"] for _, a in calls), 1)
                    self.assertFalse(any(a[:3] == ["session", "status", "blocked"] for _, a in calls))
            self.assertEqual(self.run_backend(backend, TEST_CTL_RC="23")[0], 0)
            self.assertEqual(self.run_backend(backend, TEST_STATUS_FAIL="1")[0], 0)
            self.assertEqual(self.state.read_text(), "blocked sibling")

    def test_pane_errors_and_explicit_geometry(self):
        for backend in (0, 1, "shell"):
            for token in ("unknown", ""):
                rc, _, calls = self.run_backend(backend, AGTERM_PANE_ID=token)
                self.assertEqual(rc, 1)
                self.assertFalse(any(a[:3] == ["session", "overlay", "open"] for _, a in calls))
                self.assertEqual(self.state.read_text(), "blocked sibling")
            self.surfaces[1]["visible"] = False
            self.assertEqual(self.run_backend(backend, REVDIFF_OVERLAY_SIZE="75")[0], 1)
            self.surfaces[1]["visible"] = True
            self.surfaces[1]["kind"] = "scratch"
            self.assertEqual(self.run_backend(backend)[0], 1)
            rc, _, calls = self.run_backend(backend, REVDIFF_OVERLAY_SIZE="75")
            self.assertEqual(rc, 0)
            overlay = next(a for _, a in calls if a[:3] == ["session", "overlay", "open"])
            self.assertNotIn("--pane", overlay)
            self.assertEqual(overlay[overlay.index("--size-percent") + 1], "75")
            self.surfaces[1]["kind"] = "right"
            self.assertEqual(self.run_backend(backend, AGTERM_SESSION_ID="")[0], 1)

    def test_legacy_visibility_and_cli_preference(self):
        self.surfaces = [dict(kind="left", visible=True)]
        for backend in (0, 1, "shell"):
            for overrides, selected in (({}, self.bin), ({"GHOSTTY_BIN_DIR": str(self.app)}, self.app),
                                        ({"GHOSTTY_BIN_DIR": str(self.app), "AGTERMCTL": str(self.bin / "agtermctl")}, self.bin)):
                rc, _, calls = self.run_backend(backend, **overrides)
                self.assertEqual(rc, 0)
                self.assertEqual({cli for cli, _ in calls}, {str(selected / "agtermctl")})
                status = [a for _, a in calls if a[:3] == ["session", "status", "active"]][0]
                self.assertEqual(status[status.index("--pane") + 1], "left")
            self.surfaces[0]["visible"] = False
            self.assertEqual(self.run_backend(backend, REVDIFF_OVERLAY_SIZE="75")[0], 1)
            self.surfaces[0]["visible"] = True
            self.assertEqual(self.run_backend(backend, AGTERM_PANE="right", REVDIFF_OVERLAY_SIZE="75")[0], 1)

    def test_signal_cleanup_without_completion(self):
        for backend in (0, 1, "shell"):
            for signal_name in ("HUP", "INT", "TERM"):
                with self.subTest(backend=backend, signal=signal_name):
                    self.assertEqual(self.run_backend(backend, TEST_SIGNAL=signal_name, TEST_CTL_RC="0")[0], 1)
                    self.assertEqual(self.state.read_text(), "active mine")

unittest.main(argv=[sys.argv[0]], verbosity=2)
PY
