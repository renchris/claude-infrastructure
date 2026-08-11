#!/usr/bin/env python3
"""Print the most frequent words in a UTF-8 text file.

usage: wordfreq.py <file> [-n N]

Tokens are runs of alphanumeric characters, lowercased. Output is
`<count> <word>`, ordered by count descending then word ascending.
"""

import argparse
import re
import sys
from collections import Counter

TOKEN_SPLIT = re.compile(r"[^0-9a-z]+")


def tokenize(text: str) -> list[str]:
    """Lowercase, split on every run of non-alphanumeric chars, drop empties."""
    return [tok for tok in TOKEN_SPLIT.split(text.lower()) if tok]


def top_words(text: str, n: int) -> list[tuple[int, str]]:
    """Return the top n (count, word) pairs, count DESC then word ASC."""
    counts = Counter(tokenize(text))
    ranked = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return [(count, word) for word, count in ranked[:n]]


def positive_int(value: str) -> int:
    number = int(value)
    if number < 1:
        raise ValueError(value)
    return number


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(add_help=True, description=__doc__)
    parser.add_argument("file")
    parser.add_argument("-n", default="5")
    args = parser.parse_args(argv)

    try:
        n = positive_int(args.n)
    except ValueError:
        print(
            f"wordfreq: -n must be a positive integer, got {args.n!r}", file=sys.stderr
        )
        return 2

    try:
        with open(args.file, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        print(f"wordfreq: cannot read {args.file}: {exc.strerror}", file=sys.stderr)
        return 2

    for count, word in top_words(text, n):
        print(f"{count} {word}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
