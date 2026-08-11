#!/usr/bin/env python3
"""Tests for the wordfreq CLI."""

import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CLI = os.path.join(HERE, "wordfreq.py")
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import wordfreq  # noqa: E402  (path setup must precede the import)


def run_cli(*args):
    """Run the CLI with `args` and return the CompletedProcess."""
    return subprocess.run(
        [sys.executable, CLI, *args], capture_output=True, text=True, check=False
    )


class TopWordsTest(unittest.TestCase):
    def test_orders_by_count_descending(self):
        text = "a b b c c c"
        self.assertEqual(wordfreq.top_words(text, 3), ["3 c", "2 b", "1 a"])

    def test_ties_break_alphabetically(self):
        text = "delta alpha charlie bravo"
        self.assertEqual(
            wordfreq.top_words(text, 4), ["1 alpha", "1 bravo", "1 charlie", "1 delta"]
        )

    def test_n_larger_than_vocabulary_returns_whole_vocabulary(self):
        text = "one two two"
        self.assertEqual(wordfreq.top_words(text, 50), ["2 two", "1 one"])

    def test_punctuation_and_case_are_folded(self):
        text = "The cat -- THE CAT's hat, the_cat!"
        self.assertEqual(
            wordfreq.tokenize(text),
            ["the", "cat", "the", "cat", "s", "hat", "the", "cat"],
        )
        self.assertEqual(wordfreq.top_words(text, 2), ["3 cat", "3 the"])

    def test_empty_input_produces_no_lines(self):
        self.assertEqual(wordfreq.tokenize(""), [])
        self.assertEqual(wordfreq.top_words("", 5), [])


class CliTest(unittest.TestCase):
    def test_empty_file_prints_nothing_and_exits_zero(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
            path = handle.name
        self.addCleanup(os.unlink, path)
        result = run_cli(path)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_default_n_is_five(self):
        with tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8"
        ) as handle:
            handle.write("a b c d e f g")
            path = handle.name
        self.addCleanup(os.unlink, path)
        result = run_cli(path)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            result.stdout.splitlines(), ["1 a", "1 b", "1 c", "1 d", "1 e"]
        )

    def test_missing_file_exits_two_with_one_stderr_line(self):
        result = run_cli(os.path.join(HERE, "no-such-file.txt"))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertEqual(len(result.stderr.strip().splitlines()), 1)

    def test_non_positive_n_exits_two_with_one_stderr_line(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
            path = handle.name
        self.addCleanup(os.unlink, path)
        for bad in ("0", "-3", "two"):
            with self.subTest(n=bad):
                result = run_cli(path, "-n", bad)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(len(result.stderr.strip().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
