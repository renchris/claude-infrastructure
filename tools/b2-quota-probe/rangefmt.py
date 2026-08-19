"""collapse integers into comma-separated ascending ranges.

[1, 2, 3, 5, 7, 8] -> "1-3,5,7,8"

runs of three or more render as "a-b"; runs of two stay "a,b" because the
hyphen form is no shorter and reads worse. duplicates collapse, input order
is irrelevant, negatives are fine.
"""

from __future__ import annotations

import sys


def format_ranges(nums: list[int]) -> str:
    """render nums as comma-separated ascending ranges."""
    ordered = sorted(set(nums))
    if not ordered:
        return ""

    parts: list[str] = []
    start = prev = ordered[0]

    def flush(lo: int, hi: int) -> None:
        span = hi - lo + 1
        if span == 1:
            parts.append(str(lo))
        elif span == 2:
            parts.append(f"{lo},{hi}")
        else:
            parts.append(f"{lo}-{hi}")

    for n in ordered[1:]:
        if n == prev + 1:
            prev = n
            continue
        flush(start, prev)
        start = prev = n
    flush(start, prev)

    return ",".join(parts)


def main(argv: list[str]) -> int:
    """CLI entry point: print the formatted string, or exit 2 on bad input."""
    try:
        nums = [int(arg) for arg in argv]
    except ValueError as exc:
        print(f"rangefmt: {exc}", file=sys.stderr)
        return 2
    print(format_ranges(nums))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
