#!/usr/bin/env python3
"""sba-mutate.py — produce a named MUTANT of hooks/lib/smart-bash-allowlist.py.

Used by tests/smart-bash-allowlist-inert.bats to give its green-in-both-arms SAFETY cases
power. Each mutant REMOVES THE CURE rather than disabling one arm of it: a mutant written as
`if False:` around one branch leaves the safe fallback in place and survives, which makes the
case look guarded when it is not.

Every mutation asserts its anchor matched EXACTLY ONCE and exits non-zero otherwise, so a
refactor that moves the code makes the suite fail loudly instead of silently applying nothing
(memory: a mutant anchored on a non-unique string applies to nothing and the green proves
nothing).

Usage: sba-mutate.py <name> <source.py> <dest.py>
"""

import sys


def sub(text, old, new, what):
    n = text.count(old)
    if n != 1:
        sys.stderr.write(
            "sba-mutate: anchor for %r matched %d times, expected 1 — "
            "the subject moved and this mutant would apply to nothing\n" % (what, n)
        )
        raise SystemExit(2)
    return text.replace(old, new)


MUTANTS = {}


def mutant(fn):
    MUTANTS[fn.__name__] = fn
    return fn


@mutant
def arith_never(s):
    """Delete the screen that keeps a COMMAND from hiding inside an arithmetic body."""
    return sub(
        s,
        "                if any(t in body for t in _ARITH_NEVER) or not _ARITH_CHARS.match(body):\n"
        '                    return [], "", False  # something could execute in there\n',
        "",
        "arithmetic body screen",
    )


@mutant
def arith_pair(s):
    """Drop the `))`-pair requirement, so `$( (subshell) )` is read as arithmetic."""
    return sub(
        s,
        'return j if j > 0 and cmd[j - 1] == ")" else None',
        "return j",
        "arith_end `))` pair requirement",
    )


@mutant
def noop_above_redirect(s):
    """Hoist the `[` / `:` branches ABOVE the redirect scanner, so `: > file` is allowed."""
    branches = (
        '    if v == "[":\n'
        '        if parts[-1] != "]":\n'
        "            return None\n"
        '        return "[: test builtin, read-only, no redirect"\n'
        '    if v == ":":\n'
        '        return ": no-op builtin, read-only, no redirect"\n'
    )
    s = sub(s, branches, "", "the [ / : branches (removal)")
    return sub(
        s,
        "    parts = seg.split()\n",
        "    parts = seg.split()\n" + branches,
        "the [ / : branches (hoist above redirects_to_file)",
    )


@mutant
def comment_as_verb(s):
    """Admit a comment as an allowed VERB instead of reducing it away, so a comment-only
    command satisfies decide()'s `judged > 0` and is allowed outright."""
    s = sub(
        s,
        '    if s.startswith("#"):\n        return ""\n',
        "",
        "comment reduction in normalize()",
    )
    # The injection has to sit ABOVE allowed_segment's `v is None` return: `verb()` cannot match
    # `#`, so a branch placed lower (beside READ_ONLY) is unreachable and the mutant SURVIVES —
    # which reads as a guarded case and guards nothing. Measured: the first draft did exactly that.
    return sub(
        s,
        "    v = verb(seg)\n    if v is None:\n        return None\n",
        '    if seg.startswith("#"):\n'
        '        return "comment"\n'
        "    v = verb(seg)\n    if v is None:\n        return None\n",
        "comment admitted as a verb, above the v-is-None return",
    )


def main(argv):
    if len(argv) != 4:
        sys.stderr.write(__doc__)
        return 2
    name, src, dest = argv[1], argv[2], argv[3]
    if name not in MUTANTS:
        sys.stderr.write(
            "sba-mutate: unknown mutant %r (have: %s)\n"
            % (name, ", ".join(sorted(MUTANTS)))
        )
        return 2
    with open(src, encoding="utf-8") as fh:
        text = fh.read()
    out = MUTANTS[name](text)
    if out == text:
        sys.stderr.write("sba-mutate: %s changed nothing\n" % name)
        return 2
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
