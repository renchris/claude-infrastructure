# bash 3.2 counts parentheses inside a heredoc body it will never execute

**2026-09-20.** `scripts/limit-recover/lr-fire-resume.sh` — the script that EXECs the unattended
resume — did not **parse** under `/bin/bash`:

```
lr-fire-resume.sh: line 965: unexpected EOF while looking for matching `"'
```

Line 965 is fine. So is every line near it. The cause was a single unbalanced `(` in a **comment**,
hundreds of lines earlier, inside a `python3` heredoc that bash never executes. Under bash 5.3 the
file parses cleanly, so `bash -n` said OK and the defect was invisible until launchd ran it.

## The mechanism

To find the `)` that closes `"$( … )"`, bash must scan forward. bash 3.2 does that scan over the
**raw text of the substitution, heredoc bodies included** — it does not first carve out the heredoc
as an opaque blob. An unbalanced `(` inside that text makes 3.2 mis-locate the end of the
substitution, and it then reports the failure wherever its confusion finally surfaces: a line that is
frequently hundreds of lines away and entirely innocent.

It is not a blind character count — 3.2 does honour shell quoting during the scan. Measured, all
four bodies inside `x="$(python3 - <<'PY' … PY)"`:

| heredoc body | `/bin/bash 3.2 -n` | `bash 5.3 -n` |
|---|---|---|
| `print("ok")  # bare comment paren: (` | **FAIL** | PASS |
| `print("a (b")`  — paren inside a double-quoted string | PASS | PASS |
| `print('a (b')`  — paren inside a single-quoted string | PASS | PASS |
| `pass  # ("`     — unbalanced paren *and* quote | **FAIL** | PASS |

So the rule is: **inside a command substitution, an unbalanced `(` that is not itself inside shell
quotes breaks bash 3.2 — even in a comment, even in a language bash is not parsing.** A quoted paren
is safe, which is why this survives casual review: most parens in Python are inside string literals
and cause nothing. The one in a comment is the one that bites.

An unbalanced quote does the same thing by the same route (row 4), which is why the reported error
names a quote (`` matching `"' ``) when the actual culprit is a paren — the paren desynchronised the
scan, and the quote is merely where it noticed.

## Why it is expensive

The interpreter split is the same one as
[the deployment interpreter is not the one on your PATH](the-deployment-interpreter-is-not-the-one-on-your-path.md),
but the failure mode is worse in two ways. The error **points at the wrong line**, so the search
starts in the wrong place; and the surfaces that run `/bin/bash` — launchd, cron, an off-box runner —
are exactly the ones nobody watches. Here the unattended recovery chain was **dead on every one of
them while looking green on the desk**. The suites that caught it reported only
`` `[ "$status" -eq 0 ]' failed `` across 31 cases in two files, with no syntax error anywhere in the
output, because the script died before producing any.

That repo's `tests/bash32-parse-lint.bats` already covers this CLASS, and its existing rows name a
`case`+`continue` arm and an apostrophe. **Parens are a third trigger of one mechanism**, and the
first two do not suggest looking for it.

## The rule

For any file whose shebang is `#!/bin/bash`, or that any launchd/cron/CI job invokes through
`/bin/bash`, run **`/bin/bash -n`** as well as `bash -n`. They are different programs eighteen years
apart, and only the first one is the deployment interpreter.

When `/bin/bash -n` reports an `unexpected EOF` at a line that is obviously fine, **do not read that
line**. Find the nearest enclosing `"$( … )"` above it and balance the parens and quotes in its raw
body, comments and heredocs included.

```bash
# Reproduce in four lines — 3.2 fails, 5.x passes:
printf '#!/bin/bash\nx="$(python3 - <<'"'"'PY'"'"'\n# (\nprint(1)\nPY\n)"\n' > /tmp/r.sh
/bin/bash -n /tmp/r.sh          # syntax error, on a line that is fine
/opt/homebrew/bin/bash -n /tmp/r.sh   # silent
```
