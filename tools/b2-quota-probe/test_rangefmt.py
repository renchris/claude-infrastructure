"""tests for rangefmt: collapsing rules, ordering, and both CLI error paths."""

from __future__ import annotations

import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import rangefmt  # noqa: E402

SCRIPT = os.path.join(HERE, "rangefmt.py")


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, SCRIPT, *args],
        capture_output=True,
        text=True,
        check=False,
    )


class FormatRangesTest(unittest.TestCase):
    def test_empty_input(self) -> None:
        self.assertEqual(rangefmt.format_ranges([]), "")

    def test_single_value_stays_bare(self) -> None:
        self.assertEqual(rangefmt.format_ranges([4]), "4")
        self.assertEqual(rangefmt.format_ranges([1, 5, 9]), "1,5,9")

    def test_run_of_two_is_comma_not_hyphen(self) -> None:
        self.assertEqual(rangefmt.format_ranges([7, 8]), "7,8")
        self.assertEqual(rangefmt.format_ranges([1, 3, 4, 6]), "1,3,4,6")

    def test_run_of_three_or_more_is_hyphenated(self) -> None:
        self.assertEqual(rangefmt.format_ranges([1, 2, 3]), "1-3")
        self.assertEqual(rangefmt.format_ranges([1, 2, 3, 4, 5]), "1-5")

    def test_mixed_example(self) -> None:
        # the run 7,8 is length 2, so it stays comma-joined per the
        # "runs of 2 render a,b NOT a-b" rule.
        self.assertEqual(rangefmt.format_ranges([1, 2, 3, 5, 7, 8]), "1-3,5,7,8")

    def test_duplicates_collapse_and_order_is_irrelevant(self) -> None:
        self.assertEqual(rangefmt.format_ranges([3, 1, 2, 2, 3, 1]), "1-3")
        self.assertEqual(
            rangefmt.format_ranges([8, 5, 2, 1, 3, 7, 3]),
            rangefmt.format_ranges([1, 2, 3, 5, 7, 8]),
        )

    def test_negative_numbers(self) -> None:
        self.assertEqual(rangefmt.format_ranges([-3, -2, -1]), "-3--1")
        self.assertEqual(rangefmt.format_ranges([-2, -1, 0, 1, 4]), "-2-1,4")
        self.assertEqual(rangefmt.format_ranges([-5, -4]), "-5,-4")

    def test_boundary_between_two_and_three_run_lengths(self) -> None:
        self.assertEqual(rangefmt.format_ranges([10, 11, 13, 14, 15]), "10,11,13-15")

    def test_cli_prints_formatted_string(self) -> None:
        proc = run_cli("1", "2", "3", "5")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "1-3,5")

    def test_cli_accepts_negative_arguments(self) -> None:
        proc = run_cli("-3", "-2", "-1", "4")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "-3--1,4")

    def test_cli_no_arguments_prints_empty_and_exits_zero(self) -> None:
        proc = run_cli()
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout.strip(), "")
        self.assertEqual(proc.stderr, "")

    def test_cli_non_integer_argument_errors_to_stderr_with_exit_2(self) -> None:
        proc = run_cli("1", "banana", "3")
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(proc.stdout.strip(), "")
        self.assertIn("banana", proc.stderr)


if __name__ == "__main__":
    unittest.main()
