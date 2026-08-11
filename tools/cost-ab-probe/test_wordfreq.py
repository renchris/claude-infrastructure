#!/usr/bin/env python3
"""Tests for the wordfreq CLI."""

import io
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import wordfreq  # noqa: E402

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wordfreq.py")


def run_cli(text, extra_args=()):
    """Run main() over a temp file holding text; return (exit_code, stdout lines)."""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as fh:
        fh.write(text)
        path = fh.name
    try:
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = wordfreq.main([path, *extra_args])
        return code, buf.getvalue().splitlines()
    finally:
        os.unlink(path)


class TestTopWords(unittest.TestCase):
    def test_orders_by_count_descending(self):
        code, lines = run_cli("a a a b b c")
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["3 a", "2 b", "1 c"])

    def test_ties_break_alphabetically(self):
        code, lines = run_cli("delta bravo alpha charlie")
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["1 alpha", "1 bravo", "1 charlie", "1 delta"])

    def test_n_larger_than_vocabulary(self):
        code, lines = run_cli("one two two", ["-n", "50"])
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["2 two", "1 one"])

    def test_punctuation_and_case_folding(self):
        code, lines = run_cli("Hello, HELLO -- world!!! world's world")
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["3 world", "2 hello", "1 s"])

    def test_empty_file_prints_nothing(self):
        code, lines = run_cli("")
        self.assertEqual(code, 0)
        self.assertEqual(lines, [])

    def test_default_n_is_five(self):
        code, lines = run_cli("a b c d e f g")
        self.assertEqual(code, 0)
        self.assertEqual(len(lines), 5)

    def test_digits_are_tokens(self):
        code, lines = run_cli("abc123 abc123 42", ["-n", "2"])
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["2 abc123", "1 42"])


class TestErrors(unittest.TestCase):
    def test_missing_file_exits_2(self):
        proc = subprocess.run(
            [sys.executable, SCRIPT, "/nonexistent/definitely/not/here.txt"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(proc.stdout, "")
        self.assertEqual(len(proc.stderr.strip().splitlines()), 1)

    def test_non_positive_n_exits_2(self):
        proc = subprocess.run(
            [sys.executable, SCRIPT, SCRIPT, "-n", "0"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(len(proc.stderr.strip().splitlines()), 1)

    def test_non_integer_n_exits_2(self):
        proc = subprocess.run(
            [sys.executable, SCRIPT, SCRIPT, "-n", "three"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(len(proc.stderr.strip().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
