#!/usr/bin/env python3
"""check-frontmatter.py - validate YAML frontmatter in markdown files.

walks a directory tree and checks every .md file that opens with a '---' line:
the block must be terminated by a closing '---' and must parse as YAML. an
unterminated block fails - the loader never sees the metadata, so a truncated
skill or agent header would otherwise ship unnoticed.

files that do not open with '---' have no frontmatter and are skipped.

usage:
    check-frontmatter.py [root]     validate tree (default: current directory)
    check-frontmatter.py --test     run unit tests
"""

import os
import sys
from pathlib import Path

import yaml


def check_content(content: str) -> str | None:
    """validate frontmatter of a markdown document. returns error text or None when valid."""
    if not content.startswith("---\n"):
        return None

    # closing delimiter starts at index 3 so an empty block ('---\n---\n') is accepted
    end = content.find("\n---\n", 3)
    if end == -1:
        if content.endswith("\n---"):
            # closing delimiter is the last line, with no trailing newline
            end = len(content) - 4
        else:
            return (
                "unterminated frontmatter: no closing '---'. "
                "if the document deliberately opens with a horizontal rule, write it as '***'"
            )

    try:
        yaml.safe_load(content[4:end])
    except yaml.YAMLError as e:
        return str(e)
    return None


def check_tree(root: str = ".") -> list[tuple[str, str]]:
    """walk root and validate every markdown file. returns (path, error) pairs."""
    failures = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d != ".git")
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            error = check_content(Path(path).read_text())
            if error:
                failures.append((path, error))
    return failures


def main(argv: list[str]) -> int:
    if argv and argv[0] == "--test":
        run_tests()
        return 0

    failures = check_tree(argv[0] if argv else ".")
    for path, error in failures:
        print(f"FAIL: {path}")
        print(f"  {error}")
    if failures:
        return 1
    print("all markdown frontmatter is valid YAML")
    return 0


def run_tests() -> None:
    """run embedded unit tests."""
    import tempfile
    import unittest

    class TestCheckContent(unittest.TestCase):
        def test_no_frontmatter(self) -> None:
            self.assertIsNone(check_content("# Title\n\nbody\n"))

        def test_valid_frontmatter(self) -> None:
            self.assertIsNone(check_content("---\nname: thing\ndescription: does it\n---\n\nbody\n"))

        def test_empty_frontmatter(self) -> None:
            self.assertIsNone(check_content("---\n---\n\nbody\n"))

        def test_closing_delimiter_at_eof(self) -> None:
            self.assertIsNone(check_content("---\nname: thing\n---"))

        def test_unterminated_frontmatter(self) -> None:
            error = check_content("---\nname: thing\ndescription: does it\n\n# Title\n")
            self.assertIsNotNone(error)
            self.assertIn("unterminated", error)

        def test_unterminated_when_body_has_hr(self) -> None:
            # a '---' that is not on its own line does not close the block
            error = check_content("---\nname: thing\n\ntext --- more text\n")
            self.assertIsNotNone(error)
            self.assertIn("unterminated", error)

        def test_invalid_yaml(self) -> None:
            error = check_content("---\nname: [unclosed\n---\n\nbody\n")
            self.assertIsNotNone(error)
            self.assertNotIn("unterminated", error)

        def test_tab_indent_is_invalid_yaml(self) -> None:
            self.assertIsNotNone(check_content("---\nname: thing\n\tbad: indent\n---\n"))

    class TestCheckTree(unittest.TestCase):
        def write(self, root: str, rel: str, content: str) -> None:
            path = Path(root) / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

        def test_reports_only_broken_files(self) -> None:
            with tempfile.TemporaryDirectory() as root:
                self.write(root, "good.md", "---\nname: good\n---\n\nbody\n")
                self.write(root, "plain.md", "# no frontmatter\n")
                self.write(root, "nested/broken.md", "---\nname: broken\n\nbody\n")
                failures = check_tree(root)
                self.assertEqual(len(failures), 1)
                self.assertTrue(failures[0][0].endswith("broken.md"))

        def test_skips_git_directory(self) -> None:
            with tempfile.TemporaryDirectory() as root:
                self.write(root, ".git/hooks/broken.md", "---\nname: broken\n\nbody\n")
                self.assertEqual(check_tree(root), [])

        def test_checks_dot_github_directory(self) -> None:
            # '.git' as a substring must not exclude '.github' from the walk
            with tempfile.TemporaryDirectory() as root:
                self.write(root, ".github/broken.md", "---\nname: broken\n\nbody\n")
                self.assertEqual(len(check_tree(root)), 1)

        def test_ignores_non_markdown(self) -> None:
            with tempfile.TemporaryDirectory() as root:
                self.write(root, "broken.txt", "---\nname: broken\n\nbody\n")
                self.assertEqual(check_tree(root), [])

    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for tc in [TestCheckContent, TestCheckTree]:
        suite.addTests(loader.loadTestsFromTestCase(tc))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
