#!/usr/bin/env python3
"""Tests for the wordfreq CLI."""

import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import wordfreq  # noqa: E402

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wordfreq.py")


class TopWordsTest(unittest.TestCase):
    def test_orders_by_count_descending(self):
        text = "a a a b b c"
        self.assertEqual(wordfreq.top_words(text, 3), [(3, "a"), (2, "b"), (1, "c")])

    def test_ties_break_alphabetically(self):
        text = "pear apple mango apple pear mango"
        self.assertEqual(
            wordfreq.top_words(text, 3), [(2, "apple"), (2, "mango"), (2, "pear")]
        )

    def test_n_larger_than_vocabulary_returns_whole_vocabulary(self):
        text = "one two two"
        self.assertEqual(wordfreq.top_words(text, 99), [(2, "two"), (1, "one")])

    def test_punctuation_and_case_folding(self):
        text = "Hello, HELLO -- world's WORLD!  hello?"
        self.assertEqual(
            wordfreq.top_words(text, 4), [(3, "hello"), (2, "world"), (1, "s")]
        )

    def test_digits_are_tokens(self):
        text = "abc123 abc123 42"
        self.assertEqual(wordfreq.top_words(text, 2), [(2, "abc123"), (1, "42")])


class EmptyInputTest(unittest.TestCase):
    def test_empty_file_prints_nothing(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
            path = handle.name
        self.addCleanup(os.unlink, path)
        result = subprocess.run(
            [sys.executable, SCRIPT, path], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


class CliTest(unittest.TestCase):
    def _run(self, *args):
        return subprocess.run(
            [sys.executable, SCRIPT, *args], capture_output=True, text=True
        )

    def test_default_n_is_five(self):
        with tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8"
        ) as handle:
            handle.write("a b c d e f g")
            path = handle.name
        self.addCleanup(os.unlink, path)
        result = self._run(path)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(result.stdout.strip().splitlines()), 5)

    def test_missing_file_exits_2_with_one_stderr_line(self):
        result = self._run(os.path.join(tempfile.gettempdir(), "no-such-file-xyz.txt"))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(result.stderr.strip().splitlines()), 1)
        self.assertEqual(result.stdout, "")

    def test_non_positive_n_exits_2(self):
        with tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8"
        ) as handle:
            handle.write("a b")
            path = handle.name
        self.addCleanup(os.unlink, path)
        for bad in ("0", "-3", "two", "1.5"):
            with self.subTest(n=bad):
                result = self._run(path, "-n", bad)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(len(result.stderr.strip().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
