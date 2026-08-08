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

That derivation has ONE precondition — S must be ABLE to succeed — and the negative-assertion
family violates it. See revive() for the family, the rewrite it gets instead, and why a shape
this cannot prove is DECLINED rather than repaired on a guess.

A finding names a LINE; the thing to repair is a STATEMENT, and in this corpus those differ
often (201 of the suites use `\` continuations). Every repair below is therefore derived from
the whole logical statement — the finding's line joined with its continuations — and only the
emission is per-line. Judging the head line alone is not a conservative approximation, it is a
corruption: ` || false` appended after a trailing `\` escapes the SPACE instead of continuing
the line, which strands the next line's `|| { …; false; }` as a statement beginning with `||`
— a bash syntax error. Measured 2026-08-03 on tests/teammate-auto-shutdown.bats: 30 ok → 0 ok,
and this script exited 0 announcing "0 dead assertions" over the file it had just broken.

Usage:
  bats-assert-liveness-fix.py [--dry-run] [PATH ...]

Idempotent: an already-revived statement is recognised STRUCTURALLY, not by spelling, and is
never touched. Exit 0 on success, 2 if any line was DECLINED or the analyzer still reports
findings afterwards.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

HERE = Path(__file__).resolve().parent
ANALYZER = HERE / "bats-assert-liveness.py"

# What counts as ONE statement is imported, never re-implemented: this script consumes the
# analyzer's line numbers, so a private copy of that rule would be free to drift — and a drift
# is exactly how an append landed on the head of a statement that ran on.
_spec = importlib.util.spec_from_file_location("bats_assert_liveness", ANALYZER)
if _spec is None or _spec.loader is None:  # pragma: no cover - packaging accident
    sys.exit(f"bats-assert-liveness-fix: cannot load analyzer at {ANALYZER}")
_an = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_an)
line_continues = _an.line_continues
join_continued = _an.join_continued
strip_comment = _an.strip_comment
trailing_backslashes = _an.trailing_backslashes

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


# ── shell structure: what is TOP LEVEL and what is merely nested ────────────────────────────────

RE_NEG = re.compile(r"^!\s")
RE_ALWAYS_FAILS = re.compile(r"^(?:false|return\s+[1-9][0-9]*|exit\s+[1-9][0-9]*)$")
RE_ALWAYS_TRUE = re.compile(r"^(?:true|:)$")
# A failure token in COMMAND position, matched on a quote-blanked copy so that `grep -q "false"`
# — string data, not structure — can never trip it.
RE_FAIL_WORD = re.compile(
    r"(?:^|[;&|(){}])\s*(?:false|return\s+[1-9][0-9]*|exit\s+[1-9][0-9]*)\s*(?=$|[;&|)}])"
)

NEVER = "never"  # provably cannot exit 0
CAN_SUCCEED = "can-succeed"  # not structurally always-failing
UNKNOWN = "unknown"  # neither proven — a DECLINE, never a default


def blank_quoted(s: str) -> str:
    """Blank the CONTENTS of quoted spans, preserving length. Structure, not string data."""
    out = list(s)
    quote = None
    i = 0
    while i < len(s):
        c = s[i]
        if quote:
            if c == "\\" and quote == '"':
                out[i] = out[i + 1] = " " if i + 1 < len(s) else " "
                i += 2
                continue
            if c == quote:
                quote = None
            else:
                out[i] = " "
        elif c in "'\"":
            quote = c
        i += 1
    return "".join(out)


def top_level_seps(code: str) -> list[tuple[int, str]] | None:
    """Offsets of TOP-LEVEL list separators (`&&`, `||`, `;`, `&`), or None if it does not scan.

    Nesting inside quotes, `[[ ]]`, `(( ))`, `( )`, `${ }` and `{ ; }` is NOT top level:
    `[[ 1 -eq 1 && 1 -eq 2 ]]` is ONE operand, and reading its inner `&&` as a list separator
    would let a rewrite silently change what the test asserts. A plain `|` is inside a single
    pipeline, not a separator. None — unbalanced, a line continuation, a heredoc — is a DECLINE.
    """
    seps: list[tuple[int, str]] = []
    quote: str | None = None
    paren = brace = brack = 0
    i, n = 0, len(code)
    while i < n:
        c = code[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c == "\\":
            if i + 1 >= n:
                # The escaped character is the NEWLINE: this is a line continuation, so the
                # statement is not all here. Refusing at the scanner is what makes the
                # corruption structurally impossible rather than merely avoided by callers.
                return None
            i += 2
            continue
        if c in "'\"":
            quote = c
            i += 1
            continue
        if code.startswith("[[", i):
            brack += 1
            i += 2
            continue
        if code.startswith("]]", i) and brack:
            brack -= 1
            i += 2
            continue
        if c == "(":
            paren += 1
        elif c == ")":
            paren -= 1
        elif c == "{":
            brace += 1
        elif c == "}":
            brace -= 1
        elif paren == brace == brack == 0:
            if code.startswith("&&", i) or code.startswith("||", i):
                seps.append((i, code[i : i + 2]))
                i += 2
                continue
            if c in ";&":
                seps.append((i, c))
        i += 1
    if quote or paren or brace or brack:
        return None
    return seps


def split_and_or(code: str) -> list[tuple[str, str]] | None:
    """`[(operator, operand), …]` for the top-level AND-OR list; the first operator is "".

    None when the line does not scan, or when a top-level `;`/`&` makes it more than one list —
    the negation rewrite below is only valid across a SINGLE AND-OR list.
    """
    seps = top_level_seps(code)
    if seps is None or any(t in (";", "&") for _, t in seps):
        return None
    parts: list[tuple[str, str]] = []
    prev_op, prev_end = "", 0
    for pos, tok in seps:
        parts.append((prev_op, code[prev_end:pos].strip()))
        prev_op, prev_end = tok, pos + len(tok)
    parts.append((prev_op, code[prev_end:].strip()))
    return parts


def can_succeed(code: str, depth: int = 0) -> str:
    """Can `code` ever exit 0? Three-valued — and UNKNOWN is a decline, not a lenient default.

    Only NEVER earns the negation rewrite and only CAN_SUCCEED earns the ` || false` append.
    Anything unproven is reported to a human instead of guessed at: a fixer that emits a wrong
    repair is worse than one that admits it does not know (the prescription this file IS was
    itself the counter-example — see revive()).
    """
    s = code.strip().rstrip(";").strip()
    if depth > 3 or not s:
        return UNKNOWN
    if RE_ALWAYS_FAILS.match(s):
        return NEVER
    if RE_ALWAYS_TRUE.match(s):
        return CAN_SUCCEED
    if (s.startswith("{") and s.endswith("}")) or (
        s.startswith("(") and s.endswith(")")
    ):
        # A group's status is its LAST statement's. Split on `;`/`&` only — `&&`/`||` bind
        # tighter and belong to that last statement, not to the group. The `;` before `}` is
        # MANDATORY in bash, so the final segment is routinely empty: that is a terminator, not
        # a statement, and reading it as one made every `{ …; false; }` unclassifiable.
        body = s[1:-1].strip()
        seps = top_level_seps(body)
        if seps is None:
            return UNKNOWN
        segs: list[tuple[str, str]] = []
        prev = 0
        for pos, tok in seps:
            if tok in (";", "&"):
                segs.append((body[prev:pos].strip(), tok))
                prev = pos + 1
        segs.append((body[prev:].strip(), ""))
        while len(segs) > 1 and not segs[-1][0]:
            segs.pop()
        text, term = segs[-1]
        if term == "&":
            return CAN_SUCCEED  # a backgrounded last command leaves the group at the shell's 0
        return can_succeed(text, depth + 1)
    parts = split_and_or(s)
    if parts is None:
        return UNKNOWN
    if len(parts) > 1:
        acc = can_succeed(parts[0][1], depth + 1)
        for op, operand in parts[1:]:
            nxt = can_succeed(operand, depth + 1)
            if op == "&&":  # exits 0 only if BOTH do
                acc = NEVER if NEVER in (acc, nxt) else (acc if acc == nxt else UNKNOWN)
            else:  # `||` exits 0 if EITHER does
                acc = (
                    CAN_SUCCEED
                    if CAN_SUCCEED in (acc, nxt)
                    else (acc if acc == nxt else UNKNOWN)
                )
        return acc
    # A single pipeline. A failure token we did not structurally place is unproven, not benign.
    if RE_FAIL_WORD.search(blank_quoted(s)):
        return UNKNOWN
    return CAN_SUCCEED


class Undecidable(Exception):
    """This line's correct repair is not derivable here — report it, never guess at it."""


class Repair(NamedTuple):
    """A derived repair, tagged with HOW it changes the statement.

    `append` only ever adds a trailing element, so it can be emitted onto the last physical
    line of a multi-line statement with the rest untouched. `rewrite` re-forms the statement
    around a new `!`/`||`, which has no faithful re-flow across a split the author chose — so
    across lines it is reported for a hand-edit instead of guessed at.
    """

    kind: str  # "append" | "rewrite"
    text: str  # the whole statement, repaired, on one line


def revive(code: str) -> Repair | None:
    """Rewrite `code` so its failure reaches the test's exit status, or None if already live.

    The default transform APPENDS ` || false`: the statement's failure then lands in the list's
    last, un-negated element, where errexit applies. That is sound for exactly one reason — the
    statement can still succeed — and the NEGATIVE-ASSERTION FAMILY breaks it:

        A && <something that can never exit 0>          "fail the test if A matches"

    Appending there is not a weaker repair, it is a destructive one. A-matches (the intended
    FAILURE path) and A-does-not-match (the intended PASS path) BOTH land on the appended
    `false`, so a passing test becomes permanently red. Measured, non-final position:

        bash -ec 'echo clean | grep -q NOPE && { echo m; false; }          ; echo TAIL'  → 0
        bash -ec 'echo clean | grep -q NOPE && { echo m; false; } || false ; echo TAIL'  → 1
        bash -ec '! echo clean | grep -q NOPE || { echo m; false; }        ; echo TAIL'  → 0

    The family is therefore REWRITTEN as the negation the author meant — `! A || <same RHS>` —
    which fails exactly when A matches, keeps the author's diagnostic body, preserves `$output`,
    and is correct in FINAL position too, where the original returns A's status instead.

    The RHS is classified STRUCTURALLY (can_succeed), not by spelling, because a spelling list is
    a list of the shapes you already got wrong. The first version recognised only bare `false`,
    so the far more common `A && { echo "diag"; false; }` fell through to the append and cost a
    real land: P2 of tests/handoff-fire-capacity-gate.bats went red against a WORKING fix
    (752024be), while this script printed "analyzer now reports 0 dead assertions" — a false
    all-clear over a file it had just corrupted.

    A trailing `|| true` / `|| :` is dropped rather than appended to: it pins the status to 0,
    so `A && false || true || false` is still 0 on every path and the assertion stays dead.

    Raises Undecidable for a shape whose repair is not derivable — a compound left side (`! X`
    binds to one pipeline, so `! (X || Y)` is not `! X || Y`), an already-negated left side
    (`! ! cmd` is a bash syntax error), or an RHS that cannot be classified either way.
    """
    parts = split_and_or(code)
    if parts is None:
        raise Undecidable("not a single scannable AND-OR list")

    # Drop trailing always-true handlers before judging the real last element.
    while (
        len(parts) > 1 and parts[-1][0] == "||" and RE_ALWAYS_TRUE.match(parts[-1][1])
    ):
        parts = parts[:-1]

    op, last = parts[-1]
    verdict = can_succeed(last)

    if verdict == NEVER:
        if op == "||":
            return None  # `A || false`, `A || { …; false; }` — already the live form
        head = parts[:-1]
        if len(head) != 1 or head[0][0] != "":
            raise Undecidable(
                "`A && <never-succeeds>` with a compound left side: `!` negates one pipeline, "
                "so the negation rewrite would change what is asserted"
            )
        a = head[0][1]
        if RE_NEG.match(a):
            raise Undecidable(
                "left side is already negated — `! ! cmd` is a bash syntax error"
            )
        # Indentation is re-applied explicitly: the block's shape is how these
        # assertion runs are read, and a de-indented line reviews as unrelated.
        indent = code[: len(code) - len(code.lstrip())]
        return Repair("rewrite", f"{indent}! {a} || {last}")

    if verdict == CAN_SUCCEED:
        return Repair("append", code.rstrip() + SUFFIX)

    raise Undecidable(
        f"cannot prove the last element ({last!r}) can succeed; appending ` || false` to a "
        "statement that never succeeds fails on BOTH branches"
    )


def statement_span(lines: list[str], idx: int) -> list[int]:
    """Indices of every physical line of the logical statement starting at `idx`.

    Mirrors the analyzer's own block parser — same continuation predicate, the same stop at
    a blank/comment-only line, and the same `}`-at-column-0 body boundary — so the two can
    never disagree about where the statement the finding names actually ends.
    """
    span = [idx]
    while True:
        i = span[-1]
        if i + 1 >= len(lines):
            break
        if not line_continues(lines[i], strip_comment(lines[i]).strip()):
            break
        if lines[i + 1] == "}" or not strip_comment(lines[i + 1]).strip():
            break
        span.append(i + 1)
    return span


def multiline_rewrite_advice(stmt: str, repair: Repair, nlines: int) -> str:
    """Why a `rewrite` split across lines is declined, and the two forms that resolve it."""
    parts = split_and_or(stmt)
    cond = parts[0][1] if parts else stmt
    return (
        "the repair re-forms the statement around a new `!`/`||`, and this one is split "
        f"across {nlines} lines — there is no faithful re-flow of that across a split the "
        "author chose. Replace those lines with either\n"
        f"       {repair.text.strip()}\n"
        "     or the explicit block form, whichever reads better here:\n"
        f"       if {cond}; then …; false; fi"
    )


def splice_comment(original: str, new_code: str, comment: str) -> str:
    """Re-attach `original`'s trailing comment after `new_code`, holding its column."""
    if not comment:
        return new_code
    # Keep a trailing comment at its original column when the longer code still leaves
    # room, so annotated assertion blocks hold their shape; otherwise fall back to a
    # single space.
    body = comment.strip()
    gap = max(1, original.index(body) - len(new_code))
    return new_code + " " * gap + body


def fix_file(
    path: str, lines_to_fix: list[int], dry_run: bool
) -> tuple[int, list[tuple[int, str, str]]]:
    """Rewrite the named statements in place. Returns (count, declined) — see revive().

    A DECLINED statement is left byte-identical. That is the whole point: the alternative
    to a repair this script cannot derive is a hand-edit, not a plausible-looking guess.
    """
    src = Path(path).read_text(encoding="utf-8")
    lines = src.split("\n")
    changed = 0
    declined: list[tuple[int, str, str]] = []
    for ln in sorted(lines_to_fix):
        idx = ln - 1
        span = statement_span(lines, idx)
        stmt = join_continued([strip_comment(lines[i]).strip() for i in span])
        try:
            repair = revive(stmt)
        except Undecidable as exc:
            declined.append((ln, stmt, str(exc)))
            continue
        if repair is None:
            continue  # already revived
        if repair.kind == "append":
            # An append only ever adds a trailing element, so it lands on the statement's
            # LAST physical line and every line before it is untouched.
            target = span[-1]
            code, comment = split_trailing_comment(lines[target])
            code = code.rstrip()
            if trailing_backslashes(code) % 2 == 1:
                # A continuation left dangling by a blank line or EOF. bash drops it, and
                # so must we — appending AFTER it escapes the space instead of continuing.
                code = code[:-1].rstrip()
            lines[target] = splice_comment(lines[target], code + SUFFIX, comment)
        elif len(span) == 1:
            code, comment = split_trailing_comment(lines[idx])
            lines[idx] = splice_comment(lines[idx], repair.text, comment)
        else:
            declined.append(
                (ln, stmt, multiline_rewrite_advice(stmt, repair, len(span)))
            )
            continue
        changed += 1
    if changed and not dry_run:
        Path(path).write_text("\n".join(lines), encoding="utf-8")
    return changed, declined


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
    declines: list[tuple[str, int, str, str]] = []
    for p in sorted(by_file):
        n, declined = fix_file(p, by_file[p], args.dry_run)
        total += n
        declines += [(p, ln, src, why) for ln, src, why in declined]
        print(f"{'would fix' if args.dry_run else 'fixed'} {n:>3}  {p}")

    verb = "would revive" if args.dry_run else "revived"
    print(f"── {verb} {total} assertion(s) across {len(by_file)} file(s)")

    if declines:
        # Loud and non-zero. A decline is the one outcome that still needs a human, so it must
        # never read like the quiet "already revived" skip it would otherwise be mistaken for.
        print(
            f"\n!! DECLINED {len(declines)} line(s) — no repair emitted, files left untouched.",
            file=sys.stderr,
        )
        for p, ln, src, why in declines:
            print(f"   {p}:{ln}\n     {src}\n     ↳ {why}", file=sys.stderr)
        print(
            "   Hand-edit these, and verify BOTH directions with a mutant: a negative assertion\n"
            "   whose condition is already false cannot distinguish 'revived' from 'always fails'.",
            file=sys.stderr,
        )
        return 2

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
