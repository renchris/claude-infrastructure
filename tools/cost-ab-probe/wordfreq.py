#!/usr/bin/env python3
"""Print the most frequent words in a text file.

usage: wordfreq.py <file> [-n N]
"""

import re
import sys
from collections import Counter
from typing import List, Optional, Tuple

USAGE = "usage: wordfreq.py <file> [-n N]"
TOKEN_SPLIT = re.compile(r"[^a-z0-9]+")


def tokenize(text: str) -> List[str]:
    """Lowercase the text and split it on every run of non-alphanumeric characters."""
    return [token for token in TOKEN_SPLIT.split(text.lower()) if token]


def top_words(text: str, n: int) -> List[Tuple[str, int]]:
    """Return the n most frequent words, by count descending then word ascending."""
    counts = Counter(tokenize(text))
    return sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:n]


def parse_args(argv: List[str]) -> Tuple[Optional[str], Optional[int], Optional[str]]:
    """Return (path, n, error). Exactly one of path/error is non-None."""
    path: Optional[str] = None
    n = 5
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "-n":
            index += 1
            if index >= len(argv):
                return None, None, "-n requires a positive integer"
            raw = argv[index]
            if not raw.isdigit() or int(raw) < 1:
                return None, None, f"-n must be a positive integer, got: {raw}"
            n = int(raw)
        elif arg.startswith("-") and arg != "-":
            return None, None, f"unknown option: {arg}"
        elif path is None:
            path = arg
        else:
            return None, None, f"unexpected argument: {arg}"
        index += 1
    if path is None:
        return None, None, USAGE
    return path, n, None


def main(argv: List[str]) -> int:
    path, n, error = parse_args(argv)
    if error is not None or path is None or n is None:
        print(f"wordfreq.py: {error}", file=sys.stderr)
        return 2

    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        print(f"wordfreq.py: cannot read {path}: {exc.strerror}", file=sys.stderr)
        return 2

    for word, count in top_words(text, n):
        print(f"{count} {word}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
