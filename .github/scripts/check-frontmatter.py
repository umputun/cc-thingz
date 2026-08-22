#!/usr/bin/env python3
"""check-frontmatter.py - validate YAML frontmatter in markdown files.

walks a directory tree and checks every .md file that opens with a '---' line:
the block must be terminated by a closing '---' and must parse as YAML. an
unterminated block fails - the loader never sees the metadata, so a truncated
skill or agent header would otherwise ship unnoticed.

files that do not open with '---' have no frontmatter and are skipped. a BOM, CRLF
line endings and trailing blanks on a delimiter line are normalised away first, so a
file saved by a Windows or whitespace-happy editor is checked rather than silently
skipped. files are decoded as UTF-8 regardless of the ambient locale.

usage:
    check-frontmatter.py [root]     validate tree (default: current directory)
    check-frontmatter.py --test     run unit tests
"""

import os
import re
import sys
from pathlib import Path

import yaml


def check_content(content: str) -> str | None:
    """validate frontmatter of a markdown document. returns error text or None when valid."""
    # normalise so a BOM or CRLF endings do not make a real '---' line unrecognisable,
    # which would skip the file as "no frontmatter" and hide broken metadata. the
    # trailing newline lets a closing '---' on the last line be found by the same
    # search as every other one, instead of needing its own offset arithmetic
    content = content.lstrip("\ufeff").replace("\r\n", "\n")
    if not content.endswith("\n"):
        content += "\n"

    # trailing blanks on a delimiter line are the same class of near-miss as a BOM or
    # CRLF: '--- \n' opens frontmatter for every YAML reader, so leaving it unmatched
    # would skip the file silently, and matching only the opener would then call a
    # valid block unterminated
    content = re.sub(r"^---[ \t]+$", "---", content, flags=re.MULTILINE)

    if not content.startswith("---\n"):
        return None

    # closing delimiter starts at index 3 so an empty block ('---\n---\n') is accepted
    end = content.find("\n---\n", 3)
    if end == -1:
        return (
            "unterminated frontmatter: no closing '---'. "
            "if the document deliberately opens with a horizontal rule, write it as '***'"
        )

    try:
        parsed = yaml.safe_load(content[4:end])
    except yaml.YAMLError as e:
        return str(e)

    # safe_load happily returns a scalar or a list for text that is valid YAML but not a
    # header: 'name thing' with the colon dropped parses as the string 'name thing' and
    # would pass, while the loader gets no name/description -- exactly the shipped-broken-
    # metadata case this gate exists to catch. None stays valid: that is an empty block
    if parsed is not None and not isinstance(parsed, dict):
        return f"frontmatter is not a YAML mapping (parsed as {type(parsed).__name__})"
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
            # a dangling symlink or a non-UTF-8 file must be reported as that file's
            # failure, not raise out of the walk and leave every later file unchecked
            try:
                # explicit utf-8: read_text() would otherwise decode with the ambient
                # locale, so on a non-UTF-8 host every file carrying an em-dash fails
                content = Path(path).read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as e:
                failures.append((path, f"unreadable: {e}"))
                continue
            error = check_content(content)
            if error:
                failures.append((path, error))
    return failures


def main(argv: list[str]) -> int:
    if argv and argv[0] == "--test":
        run_tests()
        return 0

    root = argv[0] if argv else "."
    # os.walk on a missing path yields nothing, so without this the check reports
    # success having validated zero files -- a typo would silently disable the gate
    if not os.path.isdir(root):
        print(f"error: not a directory: {root}", file=sys.stderr)
        return 1

    failures = check_tree(root)
    for path, error in failures:
        print(f"FAIL: {path}")
        print(f"  {error}")
    if failures:
        return 1
    print("all markdown frontmatter is valid YAML")
    return 0


def run_tests() -> None:
    """run embedded unit tests."""
    import contextlib
    import io
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

        def test_non_mapping_frontmatter_is_rejected(self) -> None:
            # a dropped colon still parses as valid YAML -- as a bare string, which leaves
            # the loader with no name/description
            error = check_content("---\nname thing\n---\n")
            self.assertIsNotNone(error)
            self.assertIn("not a YAML mapping", error)
            self.assertIsNotNone(check_content("---\n- a\n- b\n---\n"))
            self.assertIsNotNone(check_content("---\n42\n---\n"))

        def test_tab_indent_is_invalid_yaml(self) -> None:
            self.assertIsNotNone(check_content("---\nname: thing\n\tbad: indent\n---\n"))

        def test_crlf_frontmatter_is_checked(self) -> None:
            # a file saved with CRLF must not read as "no frontmatter" and slip through
            self.assertIsNone(check_content("---\r\nname: thing\r\n---\r\n\r\nbody\r\n"))
            error = check_content("---\r\nname: thing\r\n\r\nbody\r\n")
            self.assertIsNotNone(error)
            self.assertIn("unterminated", error)

        def test_bom_frontmatter_is_checked(self) -> None:
            self.assertIsNone(check_content("\ufeff---\nname: thing\n---\n"))
            error = check_content("\ufeff---\nname: thing\n\nbody\n")
            self.assertIsNotNone(error)
            self.assertIn("unterminated", error)

        def test_delimiter_with_trailing_blanks_is_checked(self) -> None:
            # a trailing space must not make the block invisible, nor make a
            # terminated block look unterminated
            self.assertIsNone(check_content("--- \nname: thing\n---\t\n\nbody\n"))
            error = check_content("--- \nname: thing\n\nbody\n")
            self.assertIsNotNone(error)
            self.assertIn("unterminated", error)
            self.assertIsNotNone(check_content("--- \nname: [unclosed\n--- \n"))

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

        def test_unreadable_file_does_not_stop_the_walk(self) -> None:
            # sorted before 'zbroken.md', so a raise here would hide the real failure
            with tempfile.TemporaryDirectory() as root:
                (Path(root) / "adangling.md").symlink_to(Path(root) / "gone")
                (Path(root) / "bbinary.md").write_bytes(b"\xff\xfe---\nname: x\n")
                self.write(root, "zbroken.md", "---\nname: broken\n\nbody\n")
                failures = dict(check_tree(root))
                names = sorted(Path(p).name for p in failures)
                self.assertEqual(names, ["adangling.md", "bbinary.md", "zbroken.md"])
                self.assertIn("unreadable", failures[str(Path(root) / "adangling.md")])

    class TestMain(unittest.TestCase):
        def run_main(self, argv: list[str]) -> int:
            # main() prints its report; swallow it so the test log stays readable
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return main(argv)

        def test_clean_tree_returns_zero(self) -> None:
            with tempfile.TemporaryDirectory() as root:
                (Path(root) / "good.md").write_text("---\nname: good\n---\n")
                self.assertEqual(self.run_main([root]), 0)

        def test_broken_tree_returns_one(self) -> None:
            with tempfile.TemporaryDirectory() as root:
                (Path(root) / "broken.md").write_text("---\nname: broken\n\nbody\n")
                self.assertEqual(self.run_main([root]), 1)

        def test_missing_root_returns_one(self) -> None:
            # a typo'd path must fail loudly rather than validate zero files and pass
            with tempfile.TemporaryDirectory() as root:
                self.assertEqual(self.run_main([str(Path(root) / "nope")]), 1)

    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for tc in [TestCheckContent, TestCheckTree, TestMain]:
        suite.addTests(loader.loadTestsFromTestCase(tc))
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
