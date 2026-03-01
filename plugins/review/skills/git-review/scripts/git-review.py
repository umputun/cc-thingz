#!/usr/bin/env python3
"""git-review.py - interactive git diff annotation tool.

generates a cleaned-up diff file, opens it in $EDITOR via tmux/kitty/wezterm overlay,
and tracks user annotations via a git repo in /tmp. returns the user's
annotations (additions/edits) as a git diff on stdout.

usage:
    git-review.py              # auto-detect: uncommitted or branch vs default
    git-review.py <base>       # diff against specific ref (branch, tag, HEAD~3)
    git-review.py --test       # run embedded tests

auto-detect logic:
    1. if uncommitted changes exist (staged + unstaged) → use those
    2. otherwise → diff current branch vs auto-detected default branch

the script manages a git repo in /tmp/<project>-<branch>/ to track annotations.
each invocation regenerates the cleaned diff, commits it, opens the editor,
and returns `git diff` output showing what the user changed.

requirements:
    - tmux, kitty, or wezterm terminal (tmux tried first, then kitty, then wezterm)
    - $EDITOR set (defaults to micro)
    - git
    - kitty users: kitty.conf must have allow_remote_control and listen_on configured
"""

import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def git(*args: str, cwd: str | None = None) -> str:
    """run a git command and return stdout."""
    result = subprocess.run(
        ["git"] + list(args),
        capture_output=True, text=True, cwd=cwd,
    )
    return result.stdout.strip()


def git_ok(*args: str, cwd: str | None = None) -> bool:
    """run a git command and return True if it succeeded."""
    result = subprocess.run(
        ["git"] + list(args),
        capture_output=True, text=True, cwd=cwd,
    )
    return result.returncode == 0


def detect_default_branch() -> str:
    """detect the default branch (master, main, trunk)."""
    # try origin/HEAD first
    ref = git("symbolic-ref", "refs/remotes/origin/HEAD")
    if ref:
        return ref.replace("refs/remotes/origin/", "")

    # probe common branch names
    for branch in ("master", "main", "trunk"):
        if git_ok("rev-parse", "--verify", f"origin/{branch}"):
            return branch

    # last resort: try local branches
    for branch in ("master", "main", "trunk"):
        if git_ok("rev-parse", "--verify", branch):
            return branch

    return "master"


def has_uncommitted_changes() -> bool:
    """check if there are uncommitted changes (staged, unstaged, or untracked)."""
    return bool(git("diff", "--name-only") or git("diff", "--cached", "--name-only")
                or git("ls-files", "--others", "--exclude-standard"))


def get_project_name() -> str:
    """get project name from git remote or directory name."""
    remote = git("remote", "get-url", "origin")
    if remote:
        # extract repo name from URL
        name = remote.rstrip("/").rsplit("/", 1)[-1]
        name = name.removesuffix(".git")
        return name
    # fall back to directory name
    return Path.cwd().name


def get_current_branch() -> str:
    """get current branch name."""
    return git("rev-parse", "--abbrev-ref", "HEAD")


def get_file_status(diff_args: list[str]) -> dict[str, str]:
    """get file statuses from git diff --name-status."""
    output = git("diff", "--name-status", *diff_args)
    statuses = {}
    for line in output.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t", 1)
        if len(parts) == 2:
            code, name = parts
            if code.startswith(("R", "C")):
                # rename/copy: status is like R100\told\tnew or C100\told\tnew
                multi_parts = line.split("\t")
                if len(multi_parts) >= 3:
                    name = multi_parts[2]
                    statuses[name] = "renamed" if code.startswith("R") else "copied"
                    continue
            status_map = {"A": "new", "M": "modified", "D": "deleted"}
            statuses[name] = status_map.get(code[0], "changed")
    return statuses


def get_untracked_files() -> list[str]:
    """get list of untracked files (not ignored)."""
    output = git("ls-files", "--others", "--exclude-standard")
    if not output:
        return []
    return output.splitlines()


def generate_untracked_diff(files: list[str]) -> str:
    """generate synthetic diff sections for untracked files."""
    sections = []
    for fpath in files:
        try:
            content = Path(fpath).read_text()
        except (OSError, UnicodeDecodeError):
            continue
        lines = content.splitlines()
        prefixed = "\n".join(f"+{line}" for line in lines)
        sections.append(f"=== {fpath} (untracked) ===\n\n{prefixed}")
    return "\n\n".join(sections) + "\n" if sections else ""


def generate_clean_diff(diff_args: list[str]) -> str:
    """generate cleaned-up diff with friendly headers."""
    raw_diff = git("diff", *diff_args)
    if not raw_diff:
        return ""

    statuses = get_file_status(diff_args)

    # parse and reformat
    lines = raw_diff.splitlines()
    output = []
    current_file = None
    skip_header = True

    for line in lines:
        # detect file header
        if line.startswith("diff --git "):
            match = re.search(r" b/(.+)$", line)
            if match:
                current_file = match.group(1)
                status = statuses.get(current_file, "changed")
                if output:
                    output.append("")
                output.append(f"=== {current_file} ({status}) ===")
                output.append("")
            skip_header = True
            continue

        # skip technical headers
        if skip_header:
            if line.startswith(("index ", "--- ", "+++ ", "old mode", "new mode",
                                "new file mode", "deleted file mode",
                                "similarity index", "rename from", "rename to",
                                "copy from", "copy to")):
                continue

        # replace @@ hunk headers with separator
        if line.startswith("@@"):
            skip_header = False
            # extract function context if present (after the second @@)
            context_match = re.search(r"@@ .+? @@\s*(.+)", line)
            if context_match:
                output.append(f"··· {context_match.group(1)}")
            else:
                output.append("···")
            continue

        skip_header = False
        output.append(line)

    return "\n".join(output) + "\n"


def make_header(diff_args: list[str], mode: str) -> str:
    """generate a header line for the review file."""
    branch = get_current_branch()
    parts = [f"Branch: {branch}"]

    if mode == "uncommitted":
        staged = len(git("diff", "--cached", "--name-only").splitlines()) if git("diff", "--cached", "--name-only") else 0
        unstaged = len(git("diff", "--name-only").splitlines()) if git("diff", "--name-only") else 0
        untracked = len(get_untracked_files())
        parts.append(f"Staged: {staged}")
        parts.append(f"Unstaged: {unstaged}")
        if untracked:
            parts.append(f"Untracked: {untracked}")
    else:
        base = diff_args[0].split("...")[0] if diff_args else "?"
        commit_count = git("rev-list", "--count", f"{base}..HEAD") if "..." in diff_args[0] else "?"
        file_count = len(git("diff", "--name-only", *diff_args).splitlines())
        parts.append(f"Base: {base}")
        parts.append(f"Commits: {commit_count}")
        parts.append(f"Files: {file_count}")

    return " | ".join(parts)


def get_review_dir() -> Path:
    """get the review directory path in /tmp."""
    project = get_project_name()
    branch = get_current_branch()
    # sanitize for filesystem
    safe_name = re.sub(r"[^a-zA-Z0-9_.-]", "-", f"{project}-{branch}")
    return Path(tempfile.gettempdir()) / f"git-review-{safe_name}"


def setup_review_repo(review_dir: Path, content: str) -> None:
    """set up or update the git repo in the review directory."""
    review_file = review_dir / "review.diff"

    if not (review_dir / ".git").exists():
        review_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", "-q"], cwd=review_dir, capture_output=True)
        # configure git user for commits in the review repo
        subprocess.run(["git", "config", "user.email", "review@local"], cwd=review_dir, capture_output=True)
        subprocess.run(["git", "config", "user.name", "review"], cwd=review_dir, capture_output=True)

    review_file.write_text(content)
    subprocess.run(["git", "add", "review.diff"], cwd=review_dir, capture_output=True)
    subprocess.run(
        ["git", "commit", "-q", "-m", "update review", "--allow-empty"],
        cwd=review_dir, capture_output=True,
    )


def open_editor(filepath: Path) -> int:
    """open file in $EDITOR via tmux popup, kitty overlay, or wezterm split-pane, blocking until editor closes.
    tries tmux first (if $TMUX is set), then kitty, then wezterm. returns non-zero if none is available."""
    editor = os.environ.get("EDITOR", "micro")

    # tmux: display-popup -E blocks until the command exits, no sentinel needed
    if os.environ.get("TMUX") and shutil.which("tmux"):
        result = subprocess.run(
            ["tmux", "display-popup", "-E", "-w", "90%", "-h", "90%",
             "-T", " Git Review ", "--", editor, str(filepath)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return result.returncode

    # kitty: use sentinel file to detect when editor closes.
    # requires KITTY_LISTEN_ON for socket communication — Claude Code runs
    # without a TTY, so kitty @ can't auto-detect via /dev/tty.
    # kitty.conf needs: allow_remote_control yes + listen_on unix:/tmp/kitty-$KITTY_PID
    kitty_sock = os.environ.get("KITTY_LISTEN_ON")
    if kitty_sock and shutil.which("kitty"):
        fd, sentinel_path = tempfile.mkstemp(prefix="review-done-")
        os.close(fd)
        os.unlink(sentinel_path)
        sentinel = Path(sentinel_path)
        wrapper = f'{shlex.quote(editor)} {shlex.quote(str(filepath))}; touch {shlex.quote(str(sentinel))}'
        cmd = ["kitty", "@", "--to", kitty_sock, "launch", "--type=overlay",
               f"--title=Git Review: {filepath.name}"]
        # target the kitty window where claude is running, not the active one
        kitty_wid = os.environ.get("KITTY_WINDOW_ID")
        if kitty_wid:
            cmd.extend(["--match", f"id:{kitty_wid}"])
        cmd.extend(["sh", "-c", wrapper])
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        while not sentinel.exists():
            time.sleep(0.3)
        sentinel.unlink(missing_ok=True)
        return 0

    # wezterm: split-pane with sentinel file (same pattern as kitty)
    wezterm_pane = os.environ.get("WEZTERM_PANE")
    if wezterm_pane and shutil.which("wezterm"):
        fd, sentinel_path = tempfile.mkstemp(prefix="review-done-")
        os.close(fd)
        os.unlink(sentinel_path)
        sentinel = Path(sentinel_path)
        wrapper = f'{shlex.quote(editor)} {shlex.quote(str(filepath))}; touch {shlex.quote(str(sentinel))}'
        subprocess.run(
            ["wezterm", "cli", "split-pane", "--bottom", "--percent", "80",
             "--pane-id", wezterm_pane, "--", "sh", "-c", wrapper],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        while not sentinel.exists():
            time.sleep(0.3)
        sentinel.unlink(missing_ok=True)
        return 0

    return 1


def get_annotations(review_dir: Path) -> str:
    """get the user's annotations as a git diff."""
    return git("diff", cwd=str(review_dir))


def run_review(base_ref: str | None = None) -> None:
    """main review flow: generate diff, open editor, return annotations."""
    if not git_ok("rev-parse", "--is-inside-work-tree"):
        print("error: not inside a git repository", file=sys.stderr)
        sys.exit(1)

    # determine diff mode and args
    if base_ref:
        # explicit base provided
        if "..." in base_ref or ".." in base_ref:
            diff_args = [base_ref]
        else:
            diff_args = [f"{base_ref}...HEAD"]
        mode = "branch"
    elif has_uncommitted_changes():
        diff_args = ["HEAD"]  # diff vs HEAD to include both staged and unstaged
        mode = "uncommitted"
    else:
        default_branch = detect_default_branch()
        diff_args = [f"{default_branch}...HEAD"]
        mode = "branch"

    # generate cleaned diff
    clean_diff = generate_clean_diff(diff_args)

    # append untracked files for uncommitted mode
    untracked_diff = ""
    if mode == "uncommitted":
        untracked = get_untracked_files()
        if untracked:
            untracked_diff = generate_untracked_diff(untracked)

    if not clean_diff and not untracked_diff:
        print("no changes to review", file=sys.stderr)
        sys.exit(0)

    # add header
    header = make_header(diff_args, mode)
    parts = [f"# {header}"]
    if clean_diff:
        parts.append(clean_diff)
    if untracked_diff:
        parts.append(untracked_diff)
    content = "\n\n".join(parts) + "\n"

    # set up review repo and open editor
    review_dir = get_review_dir()
    setup_review_repo(review_dir, content)

    review_file = review_dir / "review.diff"
    if open_editor(review_file) != 0:
        print("error: no overlay terminal available (requires tmux, kitty, or wezterm)", file=sys.stderr)
        sys.exit(1)

    # get annotations
    annotations = get_annotations(review_dir)
    if annotations:
        print(annotations)


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="interactive git diff annotation tool")
    parser.add_argument("--test", action="store_true", help="run embedded tests")
    parser.add_argument("--clean", action="store_true", help="remove review repo from /tmp")
    parser.add_argument("base_ref", nargs="?", help="base ref to diff against (branch, tag, commit)")
    args = parser.parse_args()

    if args.test:
        run_tests()
        return

    if args.clean:
        review_dir = get_review_dir()
        if review_dir.exists():
            shutil.rmtree(review_dir)
            print(f"removed {review_dir}", file=sys.stderr)
        else:
            print("no review repo to clean", file=sys.stderr)
        return

    run_review(args.base_ref)


def run_tests() -> None:
    """run embedded unit tests."""
    import unittest

    class TestDetectDefaultBranch(unittest.TestCase):
        def test_returns_string(self) -> None:
            result = detect_default_branch()
            self.assertIsInstance(result, str)
            self.assertTrue(len(result) > 0)

    class TestGetProjectName(unittest.TestCase):
        def test_returns_string(self) -> None:
            result = get_project_name()
            self.assertIsInstance(result, str)
            self.assertTrue(len(result) > 0)

    class TestGetCurrentBranch(unittest.TestCase):
        def test_returns_string(self) -> None:
            result = get_current_branch()
            self.assertIsInstance(result, str)

    class TestGetReviewDir(unittest.TestCase):
        def test_returns_path_in_tmp(self) -> None:
            result = get_review_dir()
            self.assertTrue(str(result).startswith(tempfile.gettempdir()))
            self.assertIn("git-review-", str(result))

    class TestGenerateCleanDiff(unittest.TestCase):
        def test_empty_diff(self) -> None:
            # diff against HEAD with no changes should be empty
            result = generate_clean_diff(["HEAD", "--", "/dev/null"])
            self.assertEqual(result, "")

    class TestHasUncommittedChanges(unittest.TestCase):
        def test_returns_bool(self) -> None:
            result = has_uncommitted_changes()
            self.assertIsInstance(result, bool)

    class TestGetFileStatus(unittest.TestCase):
        def test_empty_diff(self) -> None:
            result = get_file_status(["HEAD", "--", "/dev/null"])
            self.assertEqual(result, {})

    class TestMakeHeader(unittest.TestCase):
        def test_uncommitted_header(self) -> None:
            result = make_header(["HEAD"], "uncommitted")
            self.assertIn("Branch:", result)
            self.assertIn("Staged:", result)

    class TestSetupReviewRepo(unittest.TestCase):
        def test_creates_repo(self) -> None:
            test_dir = Path(tempfile.mkdtemp(prefix="git-review-test-"))
            try:
                setup_review_repo(test_dir, "test content\n")
                self.assertTrue((test_dir / ".git").exists())
                self.assertTrue((test_dir / "review.diff").exists())
                self.assertEqual((test_dir / "review.diff").read_text(), "test content\n")
            finally:
                shutil.rmtree(test_dir, ignore_errors=True)

        def test_updates_existing_repo(self) -> None:
            test_dir = Path(tempfile.mkdtemp(prefix="git-review-test-"))
            try:
                setup_review_repo(test_dir, "first\n")
                setup_review_repo(test_dir, "second\n")
                self.assertEqual((test_dir / "review.diff").read_text(), "second\n")
            finally:
                shutil.rmtree(test_dir, ignore_errors=True)

    class TestGetUntrackedFiles(unittest.TestCase):
        def test_returns_list(self) -> None:
            result = get_untracked_files()
            self.assertIsInstance(result, list)

    class TestGenerateUntrackedDiff(unittest.TestCase):
        def test_empty_list(self) -> None:
            result = generate_untracked_diff([])
            self.assertEqual(result, "")

        def test_with_file(self) -> None:
            test_dir = Path(tempfile.mkdtemp(prefix="git-review-test-"))
            try:
                test_file = test_dir / "hello.txt"
                test_file.write_text("line one\nline two\n")
                result = generate_untracked_diff([str(test_file)])
                self.assertIn("(untracked)", result)
                self.assertIn("+line one", result)
                self.assertIn("+line two", result)
            finally:
                shutil.rmtree(test_dir, ignore_errors=True)

        def test_binary_file_skipped(self) -> None:
            test_dir = Path(tempfile.mkdtemp(prefix="git-review-test-"))
            try:
                test_file = test_dir / "binary.bin"
                test_file.write_bytes(b"\x00\x01\x02\xff")
                result = generate_untracked_diff([str(test_file)])
                self.assertEqual(result, "")
            finally:
                shutil.rmtree(test_dir, ignore_errors=True)

    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for tc in [TestDetectDefaultBranch, TestGetProjectName, TestGetCurrentBranch,
               TestGetReviewDir, TestGenerateCleanDiff, TestHasUncommittedChanges,
               TestGetFileStatus, TestMakeHeader, TestSetupReviewRepo,
               TestGetUntrackedFiles, TestGenerateUntrackedDiff]:
        suite.addTests(loader.loadTestsFromTestCase(tc))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\r\033[K", end="")
        sys.exit(130)
