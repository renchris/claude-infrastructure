#!/usr/bin/env python3
"""Print the most frequent words in a text file.

usage: wordfreq.py <file> [-n N]
"""

import re
import sys
from collections import Counter

USAGE = "usage: wordfreq.py <file> [-n N]"
TOKEN_SPLIT = re.compile(r"[^0-9a-z]+")


def tokenize(text):
    """Lowercase the text and split it on runs of non-alphanumeric characters."""
    return [tok for tok in TOKEN_SPLIT.split(text.lower()) if tok]


def top_words(text, n):
    """Return the n most common tokens, by count descending then word ascending."""
    counts = Counter(tokenize(text))
    return sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:n]


def parse_args(argv):
    """Return (path, n). Raises ValueError with a one-line message on bad input."""
    path = None
    n = 5
    rest = list(argv)
    while rest:
        arg = rest.pop(0)
        if arg == "-n":
            if not rest:
                raise ValueError("-n requires a positive integer")
            n = to_positive_int(rest.pop(0))
        elif arg.startswith("-n"):
            n = to_positive_int(arg[2:])
        elif path is None:
            path = arg
        else:
            raise ValueError(f"unexpected argument: {arg}")
    if path is None:
        raise ValueError(USAGE)
    return path, n


def to_positive_int(value):
    try:
        parsed = int(value)
    except ValueError:
        raise ValueError(f"not a positive integer: {value}")
    if parsed < 1:
        raise ValueError(f"not a positive integer: {value}")
    return parsed


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    try:
        path, n = parse_args(argv)
    except ValueError as exc:
        print(f"wordfreq.py: {exc}", file=sys.stderr)
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
    sys.exit(main())
