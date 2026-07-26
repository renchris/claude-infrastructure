#!/usr/bin/env python3
"""bats-assert-liveness-fix.py — revive the DEAD assertions bats-assert-liveness.py finds.

The fix is a uniform ` || false` suffix on the offending statement. That single form
revives all four dead classes, and it is the idiom this repo already established in
tests/cc-notify.bats (see its header comment).

Why NOT the two fixes that look obvious:

  * `[[ ... ]]` → `[ ... ]` BREAKS 98% of the call sites. 129 of the 131 `[[ ]]` findings
    use glob (`== *"txt"*`) or regex (`=~`) matching, which POSIX `[ ]` cannot express —
    `[ "$out" == *"txt"* ]` is a literal comparison against the pattern text itself, so it
    silently asserts something else entirely (and exposes an unquoted `*` to globbing).
  * `! cmd` → `run cmd; [ "$status" -ne 0 ]` CLOBBERS `$output`/`$status`. These negations
    routinely sit between a `run` and a later `echo "$output" | grep -q ...`, so the
    rewrite breaks the *following* assertion (verified: tests/cc-reaper.bats:167-169 shape).

` || false` keeps the original operator's exact semantics, preserves `$output`, and is a
one-token diff. Correctness of the revival, for a non-final statement S:

  S succeeds        → `||` short-circuits            → status 0, test continues (unchanged)
  S fails           → `false` runs as the list's LAST element, un-negated, so errexit
                      applies                        → the test now fails, as intended

Usage:
  bats-assert-liveness-fix.py [--dry-run] [PATH ...]

Idempotent: a statement already ending in `|| false` is never reported by the analyzer and
so is never touched. Exit 0 on success, 2 if the analyzer still reports findings afterwards.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ANALYZER = HERE / "bats-assert-liveness.py"

SUFFIX = " || false"


def findings(paths: list[str]) -> list[tuple[str, int, str, str]]:
    """Ask the analyzer for (path, line, class, code) tuples."""
    cmd = [sys.executable, str(ANALYZER), "--format", "tsv", *paths]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 2:
        sys.stderr.write(res.stderr)
        raise SystemExit(2)
    out = []
    for row in res.stdout.strip().split("\n"):
        if not row:
            continue
        p, ln, cls, code = row.split("\t", 3)
        out.append((p, int(ln), cls, code))
    return out


def split_trailing_comment(line: str) -> tuple[str, str]:
    """Split a source line into (code, comment-with-leading-space) respecting quotes."""
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "#" and i > 0 and line[i - 1].isspace():
            return line[:i].rstrip(), " " + line[i:]
        i += 1
    return line.rstrip(), ""

    # `A && false || true`


RE_SWALLOWED = re.compile(
    r"^(?P<indent>\s*)(?P<a>.+?)\s*&&\s*false\s*\|\|\s*(?:true|:)\s*$"
)


def revive(code: str) -> str | None:
    """Rewrite `code` so its failure reaches the test's exit status, or None if unfixable.

    The default transform APPENDS ` || false`: the statement's failure then lands in the
    list's last, un-negated element, where errexit applies.

    That append is a NO-OP for one shape. `A && false || true` reads as "A must not
    match", but the trailing always-true handler already pins the status to 0 — appending
    yields `A && false || true || false`, which is still 0 on every path. Verified:

        bash -ec 'echo hit | grep -q hit && false || true || false'   → status 0

    So that shape is REWRITTEN rather than appended to, into the negation the author
    meant: `! A || false`. Same intent, and its failure is now reachable.
    """
    if re.search(r"\|\|\s*false$", code):
        return None  # already revived
    m = RE_SWALLOWED.match(code)
    if m:
        # Indentation is re-applied explicitly: the block's shape is how these
        # assertion runs are read, and a de-indented line reviews as unrelated.
        return f"{m.group('indent')}! {m.group('a').strip()}{SUFFIX}"
    return code + SUFFIX


def fix_file(path: str, lines_to_fix: list[int], dry_run: bool) -> int:
    src = Path(path).read_text(encoding="utf-8")
    lines = src.split("\n")
    changed = 0
    for ln in sorted(lines_to_fix):
        idx = ln - 1
        original = lines[idx]
        code, comment = split_trailing_comment(original)
        new_code = revive(code)
        if new_code is None:
            continue  # already revived
        if comment:
            # Keep a trailing comment at its original column when the longer code still
            # leaves room, so annotated assertion blocks hold their shape; otherwise fall
            # back to a single space.
            body = comment.strip()
            gap = max(1, original.index(body) - len(new_code))
            new_line = new_code + " " * gap + body
        else:
            new_line = new_code
        lines[idx] = new_line
        changed += 1
    if changed and not dry_run:
        Path(path).write_text("\n".join(lines), encoding="utf-8")
    return changed


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="*", help="bats files (default: tests/*.bats)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    found = findings(args.paths)
    if not found:
        print("bats-assert-liveness-fix: nothing to do — no dead assertions")
        return 0

    by_file: dict[str, list[int]] = {}
    for p, ln, _cls, _code in found:
        by_file.setdefault(p, []).append(ln)

    total = 0
    for p in sorted(by_file):
        n = fix_file(p, by_file[p], args.dry_run)
        total += n
        print(f"{'would fix' if args.dry_run else 'fixed'} {n:>3}  {p}")

    verb = "would revive" if args.dry_run else "revived"
    print(f"── {verb} {total} assertion(s) across {len(by_file)} file(s)")

    if args.dry_run:
        return 0

    left = findings(args.paths)
    if left:
        print(
            f"!! analyzer STILL reports {len(left)} finding(s) after the fix",
            file=sys.stderr,
        )
        for p, ln, cls, code in left[:10]:
            print(f"   {p}:{ln} [{cls}] {code}", file=sys.stderr)
        return 2
    print("── analyzer now reports 0 dead assertions")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
