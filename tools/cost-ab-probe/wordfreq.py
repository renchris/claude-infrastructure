#!/usr/bin/env python3
"""Print the most frequent words in a text file.

usage: wordfreq.py <file> [-n N]

Words are runs of alphanumeric characters, case-folded. Output is one
`<count> <word>` line per word, ordered by count descending then word
ascending.
"""

import argparse
import re
import sys
from collections import Counter
from typing import List

TOKEN_SPLIT = re.compile(r"[\W_]+", re.UNICODE)


def tokenize(text: str) -> List[str]:
    """Lower-case `text` and split it into non-empty alphanumeric tokens."""
    return [token for token in TOKEN_SPLIT.split(text.lower()) if token]


def top_words(text: str, n: int) -> List[str]:
    """Return the top `n` `<count> <word>` lines for `text`."""
    counts = Counter(tokenize(text))
    ranked = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return [f"{count} {word}" for word, count in ranked[:n]]


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="wordfreq.py", description="print the most frequent words in a file"
    )
    parser.add_argument("file", help="path to a UTF-8 text file")
    parser.add_argument("-n", default="5", help="how many words to print (default: 5)")
    args = parser.parse_args(argv)

    try:
        n = int(args.n)
    except ValueError:
        n = 0
    if n < 1:
        print(
            f"wordfreq.py: -n must be a positive integer, got {args.n!r}",
            file=sys.stderr,
        )
        return 2

    try:
        with open(args.file, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        print(f"wordfreq.py: cannot read {args.file}: {exc.strerror}", file=sys.stderr)
        return 2

    for line in top_words(text, n):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
