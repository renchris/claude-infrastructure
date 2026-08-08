#!/usr/bin/env python3
"""bats-assert-liveness.py — block-position analyzer for DEAD bats assertions.

An assertion in a bats test body is DEAD when its failure cannot reach the test's
exit status. bats runs each body under `set -eET`, so *most* failing commands abort
the test — but bash exempts three construct families from `errexit`, and for those
the only thing that still fails the test is being the body's FINAL command:

  1. `[[ ... ]]`   bash conditional keyword   (POSIX `test`/`[ ]` is NOT exempt)
  2. `(( ... ))`   arithmetic evaluation
  3. `! cmd`       any command whose status is inverted with `!`

Non-final occurrences of these are silently no-ops: the assertion is evaluated, its
false result is discarded, and the test passes. shellcheck does NOT flag classes 1
and 2 at all (SC2251 covers only some `!` uses), which is why this analyzer exists:
deadness is a function of BLOCK POSITION, not of the line in isolation.

Why `[ ]` survives where `[[ ]]` dies: `[` is a builtin — an ordinary simple command,
fully subject to errexit. `[[` and `((` are shell keywords/compound commands, which
bash 3.2 (the macOS system bash this suite runs under) exempts. See the empirical
grid in docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md.

Finality is judged CONSERVATIVELY, in the safe direction: an occurrence is treated as
live only when it is provably the last meaningful statement at the top level of its
`@test` body. Anything nested inside `if`/`while`/`for`/`case`/`{ }` is reported, since
whether it is reached — and whether its status survives — is data-dependent. A false
report costs one mechanical edit; a false all-clear is absorbed forever.

Occurrences in *condition* position (`if [[ ... ]]`, `while ! cmd`, and non-final
elements of `&&`/`||` lists) are NOT assertions and are never reported.

Usage:
  bats-assert-liveness.py [--format text|tsv|count] [--summary] [PATH ...]

PATH defaults to tests/*.bats. Exit status: 0 = no dead assertions, 1 = findings,
2 = usage/IO error. Intended to run in the commit gate, so 1 is a hard failure.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

# ---------------------------------------------------------------- construct classes

CLASS_COND = "cond-keyword"  # [[ ... ]]
CLASS_ARITH = "arith"  # (( ... ))
CLASS_NEG = "negation"  # ! cmd
CLASS_AND_ABSORBED = (
    "and-absorbed"  # assertion && ...  (non-last element of AND-OR list)
)

# Commands whose failure in an `A && B` left position reads as an intended assertion, as
# opposed to setup like `mkdir -p x && cd x` whose absorption is not a test defect.
RE_ASSERTIONISH = re.compile(r"^(\[\[?|test|grep|diff|cmp|!)(\s|$)")

# A leading `!` as a whole-command negation: `! foo`, `!  [ x ]`, `! [[ x ]]`.
# Requires whitespace after `!` so `!=` and history-ish `!$` never match.
RE_NEG = re.compile(r"^!\s+\S")
RE_COND_OPEN = re.compile(r"(?<![\[\w$])\[\[(?=\s|$)")
RE_ARITH_OPEN = re.compile(r"(?<![\w$])\(\((?=[\s\w$!+-])")

# Statement keywords that open a nesting level.
RE_OPENER = re.compile(r"^(if|while|until|for|case)\b")
# Words that close / continue a nesting level; never assertions themselves.
RE_CLOSER = re.compile(r"^(fi|done|esac|else|elif\b|;;|\}|\))\s*$")
# Condition-position prefixes: the construct's status is consumed by the keyword.
RE_COND_CTX = re.compile(r"^(if|elif|while|until)\s+")
# A `for` header is never an assertion — notably `for ((i=0; i<n; i++)); do`, whose `((`
# must not be read as an arithmetic assertion.
RE_FOR_HDR = re.compile(r"^for\b")

RE_TEST_OPEN = re.compile(r"^@test\b")


def strip_comment(line: str) -> str:
    """Remove a trailing `#` comment, respecting quotes. Cheap but adequate here."""
    out = []
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\" and quote == '"':
                out.append(c)
                i += 1
                if i < len(line):
                    out.append(line[i])
                    i += 1
                continue
            if c == quote:
                quote = None
            out.append(c)
        else:
            if c in "'\"":
                quote = c
                out.append(c)
            elif c == "#":
                # `#` starts a comment only at a word boundary.
                if not out or out[-1].isspace():
                    break
                out.append(c)
            else:
                out.append(c)
        i += 1
    return "".join(out)


def strip_quoted(s: str) -> str:
    """Blank out the CONTENTS of quoted spans, preserving length and structure.

    Construct detection must see shell structure, not string data: a test that builds a
    fixture by passing bats source as arguments — `mkblock "$D/t.bats" '[[ 1 -eq 2 ]]'` —
    contains `[[` only inside quotes and asserts nothing. Blanking contents (rather than
    deleting spans) keeps every offset usable for reporting.
    """
    out = list(s)
    quote = None
    i = 0
    while i < len(s):
        c = s[i]
        if quote:
            if c == "\\" and quote == '"':
                out[i] = " "
                if i + 1 < len(s):
                    out[i + 1] = " "
                i += 2
                continue
            if c == quote:
                quote = None
            else:
                out[i] = " "
        elif c == "\\":
            # OUTSIDE quotes a backslash escapes the next character, so `\"` is a LITERAL quote and
            # must not open a span. Without this the scanner opened a phantom quote at the `\"` in
            # `[[ "$o" =~ foo\":\? ]] || false`, blanked everything after it — including the
            # `|| false` that revives the assertion — and then reported the line as a dead negation.
            # A false RED, and an expensive one: it is what held the postland verifier at red, which
            # is what froze the live layer, because deploy-live is fail-closed on a green stamp.
            out[i] = " "
            if i + 1 < len(s):
                out[i + 1] = " "
            i += 2
            continue
        elif c in "'\"":
            quote = c
        i += 1
    return "".join(out)


def heredoc_open(raw: str) -> tuple[str, bool] | None:
    """Delimiter + tab-strip flag for a heredoc OPENED on this line, else None.

    Two requirements pull in opposite directions, and satisfying only one of them is a
    measured defect in each direction:

      (a) The `<<` must be shell SYNTAX, not string data. A fixture that writes shell
          source — `printf 'cat <<EOF\\n…'` — contains `<<EOF` only inside quotes and opens
          nothing; treating it as an opener starts a skip that never terminates and
          silently swallows the rest of the block (the original §4 defect 3).
      (b) The delimiter's OWN quotes are syntax, not data. `<<'EOS'` is this repo's
          dominant form (60 of 189 suites).

    The earlier fix for (a) applied `strip_quoted` to the whole line and then looked for
    `<<\\s*([A-Za-z_]\\w*)`. That blanks the contents of `'EOS'`, so the delimiter vanished
    and NO heredoc was ever recognised in form (b) — every such fixture body was analyzed
    as if it were this file's own assertions. That is a FALSE-POSITIVE generator whose
    `|| false` remedy edits the FIXTURE, changing the subject a lint-under-test is asked
    about (4 live findings in tests/alarm-polarity-lint.bats, all inside `<<'EOS'` bodies).

    Both hold at once by splitting the two questions: POSITION is validated against the
    masked line — `strip_quoted` blanks quoted contents, so a `<<` still visible there is
    provably outside quotes — while the DELIMITER is parsed from `raw`, where its quoting
    survives. `<<<` (herestring) is checked per-occurrence, not per-line, so a real
    heredoc on a line that also carries a herestring is still seen.
    """
    masked = strip_quoted(raw)
    for m in re.finditer(r"<<", masked):
        i = m.start()
        if masked[i : i + 3] == "<<<" or masked[i - 1 : i + 1] == "<<":
            continue  # herestring, or the tail of one already considered
        d = re.match(
            r"""<<(-?)\s*(?:'([^']+)'|"([^"]+)"|\\?([A-Za-z_][A-Za-z0-9_]*))""", raw[i:]
        )
        if d:
            return (d.group(2) or d.group(3) or d.group(4)), d.group(1) == "-"
    return None


# ---------------------------------------------------------------- logical statements

# `&&`, `||` and `|` continue onto the next line all by themselves.
RE_CONT_OP = re.compile(r"(&&|\|\||\|)$")


def trailing_backslashes(s: str) -> int:
    """How many `\\` the string ENDS with. Parity is what decides a continuation."""
    n = 0
    while n < len(s) and s[len(s) - 1 - n] == "\\":
        n += 1
    return n


def line_continues(raw: str, code: str) -> bool:
    """True when the NEXT source line belongs to this same LOGICAL statement.

    Two bash rules that read different text, and conflating them is a defect in each
    direction:

      * A backslash continuation must be the RAW line's last character — `foo \\  # c`
        does not continue — and an EVEN run of trailing backslashes is a literal `\\`,
        not a continuation.
      * `&&` / `||` / `|` continue across the newline whether or not a comment follows,
        so that half is judged on the COMMENT-STRIPPED code.

    This is the single definition of "one statement" for the analyzer AND the fixer
    (which imports it). A private copy in either would be free to drift, and a drift
    here is precisely how the fixer came to append ` || false` to a line whose statement
    ran on — see bats-assert-liveness-fix.py's module docstring.
    """
    if trailing_backslashes(raw.rstrip("\n")) % 2 == 1:
        return True
    return bool(RE_CONT_OP.search(code))


def join_continued(fragments: list[str]) -> str:
    """Splice the comment-stripped fragments of one logical statement onto one line.

    A continuation backslash is dropped from EVERY fragment, the last included: bash removes
    `\\<newline>` unconditionally, so a statement left dangling by a blank line — `foo \\`
    with nothing after it — is simply `foo`. Keeping that trailing `\\` on the joined text is
    what let it survive into an emitted repair and escape the appended space.
    """
    parts: list[str] = []
    for frag in fragments:
        f = frag.rstrip()
        if trailing_backslashes(f) % 2 == 1:
            f = f[:-1].rstrip()
        if f:
            parts.append(f)
    return " ".join(parts)


class Stmt:
    """One LOGICAL statement inside a @test body — possibly spanning several lines."""

    __slots__ = ("lineno", "depth", "text")

    def __init__(self, lineno: int, depth: int, text: str):
        self.lineno = lineno
        self.depth = depth
        self.text = text


def parse_block(lines: list[str], start: int, end: int) -> list[Stmt]:
    """Collect meaningful statements between body lines (start, end) exclusive.

    Continuation lines are JOINED into the statement they belong to, so `classify` is
    handed the whole AND-OR list rather than its first physical line. Judging a fragment
    is not a conservative approximation, it is a wrong answer in both directions:
    `! grep -q X "$F" \\` alone reads as a bare dead negation, while the statement it
    heads — `… || { echo diag; false; }` — is LIVE (verified under bats both ways).

    Skips heredoc bodies entirely — a fixture that *writes* bats source must never be
    analyzed as if it were this file's own assertions.
    """
    stmts: list[Stmt] = []
    depth = 0
    heredoc: str | None = None
    heredoc_tabs = False
    pending: list[str] = []  # fragments of a statement still being continued
    pending_lineno = 0

    def flush() -> None:
        nonlocal depth, pending
        text = join_continued(pending)
        pending = []
        if not text:
            return
        if RE_CLOSER.match(text):
            depth = max(0, depth - 1)
            return
        stmts.append(Stmt(pending_lineno, depth, text))
        if RE_OPENER.match(text):
            depth += 1
        # A trailing `{` (function/group) also opens a level.
        elif text.endswith("{") and not RE_TEST_OPEN.match(text):
            depth += 1

    for ln in range(start, end):
        raw = lines[ln]

        if heredoc is not None:
            probe = raw.lstrip("\t") if heredoc_tabs else raw
            if probe.strip() == heredoc:
                heredoc = None
            continue

        code = strip_comment(raw).strip()

        # Opening a heredoc: remember the delimiter, skip its body.
        opened = heredoc_open(raw)
        if opened is not None:
            heredoc, heredoc_tabs = opened

        if not code:
            # A blank or comment-only line ends a continuation, as it does in bash for
            # the backslash form. Anything already buffered is flushed as it stands.
            if pending:
                flush()
            continue

        if not pending:
            pending_lineno = ln + 1
        pending.append(code)
        if not line_continues(raw, code):
            flush()

    if pending:
        flush()
    return stmts


def split_and_or(code: str) -> list[tuple[str, str]]:
    """Split an AND-OR list into (element, following-operator) pairs, quote-aware.

    The trailing element's operator is "". `&&`/`||` inside quotes or `$(...)` are not
    separators. Returns a single pair for a plain command.
    """
    elems: list[tuple[str, str]] = []
    buf: list[str] = []
    quote: str | None = None
    par = 0
    brack = 0  # `[[ ... ]]` depth — `[[ A && B ]]` is ONE element, not a list
    i = 0
    while i < len(code):
        c = code[i]
        if quote:
            # ...and INSIDE a double-quoted span too. `"\"sid\":\"$sid\""` closed its quote at the
            # first `\"` without this, so the rest of the line scanned as unquoted and the element
            # boundaries were wrong. Single quotes take no escapes in shell, so this is `"` only.
            if c == "\\" and quote == '"':
                buf.append(c)
                if i + 1 < len(code):
                    buf.append(code[i + 1])
                i += 2
                continue
            buf.append(c)
            if c == quote:
                quote = None
            i += 1
            continue
        if c == "\\":
            # A backslash OUTSIDE quotes escapes the next character, so `\"` is a LITERAL quote and
            # must not open a span. Without this, `! [[ "$o" =~ foo\":\? ]] || false` scanned as one
            # unterminated quoted element: the `||` was swallowed, the list came back as a SINGLE
            # element, and the `false` that revives the negation was invisible. The line was then
            # reported as a dead assertion — a false RED on an assertion that does fire, verified
            # under bats both ways.
            buf.append(c)
            if i + 1 < len(code):
                buf.append(code[i + 1])
            i += 2
            continue
        if c in "'\"":
            quote = c
            buf.append(c)
            i += 1
            continue
        if code.startswith("[[", i):
            brack += 1
            buf.append("[[")
            i += 2
            continue
        if code.startswith("]]", i):
            brack = max(0, brack - 1)
            buf.append("]]")
            i += 2
            continue
        if c == "(":
            par += 1
        elif c == ")":
            par = max(0, par - 1)
        if par == 0 and brack == 0 and code.startswith(("&&", "||"), i):
            elems.append(("".join(buf).strip(), code[i : i + 2]))
            buf = []
            i += 2
            continue
        buf.append(c)
        i += 1
    elems.append(("".join(buf).strip(), ""))
    return elems


def is_assertionish(elem: str) -> bool:
    """True when `elem`'s failure reads as an intended assertion.

    Checks the element itself AND its final pipeline stage, so the common bats idiom
    `echo "$output" | grep -q X && ...` is recognised (a pipeline's status is its last
    stage's). Narrowing to assertion-shaped commands keeps genuine setup chains such as
    `mkdir -p "$D" && cd "$D"` out of the report — their absorption is not a test defect.
    """
    elem = strip_quoted(elem).strip()
    if RE_ASSERTIONISH.match(elem):
        return True
    last_stage = elem.rsplit("|", 1)[-1].strip() if "|" in elem else ""
    return bool(last_stage and RE_ASSERTIONISH.match(last_stage))


def is_hard_fail(elem: str) -> bool:
    """True when `elem` reliably fails the test — a usable `||` failure handler.

    Covers `false`, `exit N`/`return N` for non-zero N, and a `{ ...; return 1; }` group.
    A benign handler (`|| echo missing`) is deliberately NOT one: it swallows the failure,
    which leaves the assertion just as unenforced.
    """
    e = strip_quoted(elem).strip()
    if re.match(r"^false(\s|$)", e):
        return True
    return bool(re.search(r"\b(exit|return)\s+[1-9]", e))


def is_always_true(elem: str) -> bool:
    """True when `elem` cannot fail — `true` or `:`.

    As the right-hand side of the chain's final `||`, such a handler pins the whole
    list's status to 0. See `chain_cannot_fail`.
    """
    return bool(re.match(r"^(true|:)(\s|$)", strip_quoted(elem).strip()))


def is_conditional_action(elem: str) -> bool:
    """True when `elem` is an ACTION taken when a guard holds, not an assertion.

    `[ -z "$line" ] && continue` and `[ "$x" = DENY ] && bad="$bad$line"` are
    if-statements written as AND-OR lists: the left side is a predicate whose FALSE
    branch is the normal path, not a defect. Reporting them is not merely noise —
    the fixer's ` || false` would invert the guard and fail the test on the ordinary
    path, so this exemption is load-bearing rather than cosmetic.

    Deliberately narrow: loop control and assignment only. `exit`/`return` are left
    reportable, since over-reporting there is harmless while a missed assertion is not.
    """
    e = strip_quoted(elem).strip()
    return bool(re.match(r"^(continue|break)(\s|$)", e) or re.match(r"^\w+\+?=", e))


def chain_cannot_fail(code: str) -> bool:
    """True when `code`'s status is 0 on every path, so POSITION cannot revive it.

    `A && false || true` is the shape that motivated this: it reads as "A must not
    match", but the trailing `|| true` swallows the `false` the author put there to
    signal the failure. Its status is 0 whether A matches or not, so it is dead even
    as a test body's LAST statement — the one place finality normally rescues.
    """
    elems = split_and_or(code)
    return len(elems) > 1 and elems[-2][1] == "||" and is_always_true(elems[-1][0])


def elem_dead_class(elem: str) -> str | None:
    """Dead-class of an element in STATUS-DETERMINING position, else None."""
    elem = strip_quoted(elem).strip()
    if RE_NEG.match(elem):
        return CLASS_NEG
    if RE_COND_OPEN.search(elem):
        return CLASS_COND
    if RE_ARITH_OPEN.search(elem):
        return CLASS_ARITH
    return None


def classify(code: str) -> str | None:
    """Return the dead-class of `code` as a non-final assertion, or None.

    Two independent ways a non-final statement's failure is discarded:

    1. The list's LAST element — the status-determining one — is an errexit-exempt
       construct (`[[ ]]`, `(( ))`, `! cmd`).
    2. An element joined by `&&` FAILS: POSIX exempts every non-last element of an
       AND-OR list from errexit, so the list yields that element's non-zero status and
       the test sails on. This holds for ANY command, `[ ]` and `false` included —
       verified empirically. `||` is NOT this case: a failing left side routes into the
       right side, which is a handled branch rather than a discarded assertion.
    """
    elems = split_and_or(code)

    # (1) status-determining tail
    tail_cls = elem_dead_class(elems[-1][0])
    if tail_cls is not None:
        return tail_cls

    # (2) assertion absorbed by a following `&&`.
    #
    # A trailing `|| <handler>` rescues the whole chain: in `A && B || exit 1` every
    # failure path — A's and B's alike — routes into the handler, so when the handler
    # itself reliably fails the list is LIVE and nothing is absorbed.
    has_handler = len(elems) > 1 and elems[-2][1] == "||"
    if has_handler and is_hard_fail(elems[-1][0]):
        return None

    # A conditional ACTION (`&& continue`, `&& x=y`) is an if-statement, not an
    # absorbed assertion — the guard's false branch is the normal path.
    if is_conditional_action(elems[-1][0]):
        return None

    for elem, op in elems[:-1]:
        if op == "&&" and is_assertionish(elem):
            return CLASS_AND_ABSORBED

    return None


def analyze_file(path: str) -> list[dict]:
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:  # pragma: no cover - surfaced to caller
        print(f"{path}: cannot read: {exc}", file=sys.stderr)
        return []

    lines = text.split("\n")
    findings: list[dict] = []
    i = 0
    while i < len(lines):
        if not RE_TEST_OPEN.match(lines[i]):
            i += 1
            continue
        # Body runs from the line after `@test ... {` to the closing `}` at column 0.
        j = i + 1
        while j < len(lines) and lines[j] != "}":
            j += 1
        name = lines[i].strip()
        stmts = parse_block(lines, i + 1, j)

        # The body's exit status is the status of the last TOP-LEVEL statement.
        final_lineno = None
        for s in reversed(stmts):
            if s.depth == 0:
                final_lineno = s.lineno
                break

        for s in stmts:
            if RE_COND_CTX.match(s.text) or RE_FOR_HDR.match(s.text):
                continue  # condition / loop-header position — not an assertion
            cls = classify(s.text)
            if cls is None:
                continue
            if (
                s.depth == 0
                and s.lineno == final_lineno
                and not chain_cannot_fail(s.text)
            ):
                # Provably final ⇒ its status IS the test's status — UNLESS the chain
                # cannot produce a non-zero status at all, in which case being last
                # rescues nothing.
                continue
            findings.append(
                {
                    "path": path,
                    "line": s.lineno,
                    "cls": cls,
                    "test": name,
                    "code": s.text,
                    "nested": s.depth > 0,
                }
            )
        i = j + 1
    return findings


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="*", help="bats files (default: tests/*.bats)")
    ap.add_argument("--format", choices=("text", "tsv", "count"), default="text")
    ap.add_argument(
        "--summary", action="store_true", help="append per-file/per-class totals"
    )
    args = ap.parse_args(argv)

    paths = args.paths or sorted(glob.glob("tests/*.bats"))
    if not paths:
        print("bats-assert-liveness: no bats files found", file=sys.stderr)
        return 2

    findings: list[dict] = []
    for p in paths:
        findings.extend(analyze_file(p))

    if args.format == "count":
        print(len(findings))
        return 1 if findings else 0

    for f in findings:
        if args.format == "tsv":
            print(f"{f['path']}\t{f['line']}\t{f['cls']}\t{f['code']}")
        else:
            print(f"{f['path']}:{f['line']}: DEAD [{f['cls']}] {f['code']}")

    if args.summary:
        by_file: dict[str, int] = {}
        by_cls: dict[str, int] = {}
        for f in findings:
            by_file[f["path"]] = by_file.get(f["path"], 0) + 1
            by_cls[f["cls"]] = by_cls.get(f["cls"], 0) + 1
        print("", file=sys.stderr)
        print(
            f"── {len(findings)} dead assertion(s) in {len(by_file)} of {len(paths)} file(s)",
            file=sys.stderr,
        )
        for cls in sorted(by_cls):
            print(f"   {cls:<14} {by_cls[cls]}", file=sys.stderr)
        for p in sorted(by_file, key=lambda k: (-by_file[k], k)):
            print(f"   {by_file[p]:>4}  {os.path.basename(p)}", file=sys.stderr)

    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
