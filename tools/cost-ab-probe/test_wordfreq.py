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
    def test_orders_by_count_descending(self) -> None:
        text = "a b b c c c"
        self.assertEqual(wordfreq.top_words(text, 3), [("c", 3), ("b", 2), ("a", 1)])

    def test_ties_break_alphabetically(self) -> None:
        text = "pear apple mango apple pear mango zebra"
        self.assertEqual(
            wordfreq.top_words(text, 4),
            [("apple", 2), ("mango", 2), ("pear", 2), ("zebra", 1)],
        )

    def test_n_larger_than_vocabulary(self) -> None:
        self.assertEqual(wordfreq.top_words("one two two", 99), [("two", 2), ("one", 1)])

    def test_punctuation_and_case_folding(self) -> None:
        text = "Hello, HELLO -- world's world; hello!!"
        self.assertEqual(
            wordfreq.top_words(text, 3), [("hello", 3), ("world", 2), ("s", 1)]
        )

    def test_digits_are_tokens(self) -> None:
        self.assertEqual(wordfreq.top_words("v2 v2 x1", 2), [("v2", 2), ("x1", 1)])


class CliTest(unittest.TestCase):
    def run_cli(self, *args: str) -> "subprocess.CompletedProcess[str]":
        return subprocess.run(
            [sys.executable, SCRIPT, *args], capture_output=True, text=True
        )

    def test_empty_file_produces_no_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "empty.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("")
            result = self.run_cli(path)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_default_n_is_five(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "words.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("a b c d e f g")
            result = self.run_cli(path)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines(), ["1 a", "1 b", "1 c", "1 d", "1 e"])

    def test_missing_file_exits_two(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "nope.txt")
            result = self.run_cli(path)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(result.stderr.strip().splitlines()), 1)
        self.assertEqual(result.stdout, "")

    def test_invalid_n_exits_two(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "words.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("a b c")
            for bad in ("0", "-3", "two", "1.5"):
                with self.subTest(n=bad):
                    result = self.run_cli(path, "-n", bad)
                    self.assertEqual(result.returncode, 2)
                    self.assertEqual(len(result.stderr.strip().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
