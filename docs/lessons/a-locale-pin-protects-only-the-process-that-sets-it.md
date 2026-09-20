# A locale pin protects only the process that sets it

**Incident:** cc-backlog `137f29a38c10` — post-land RED,
`tests/lr-resume-answer-width.bats` @ `cde5cbfa0a08`, 8 of 11.
**Full write-up:** `docs/research/lr-resume-expect-encoding-2026-09-20.md`.

## The rule

When you build a pattern, an escape, or a quoted string for **another program** to parse, its
validity is decided by **that program's** decoding, not by yours. Pinning your own locale fixes
your own string ops and reaches no further. Audit the consumer's decoding under the consumer's own
spellings, and validate the artifact there.

## What happened

`scripts/limit-recover/lr-fire-resume.sh` builds a Tcl regex in `lr_wrap_re` and hands it to
`expect`. A 2026-08-12 cure (`4ed74ee9c`) had already pinned `LC_CTYPE` inside that function so
bash would split `❯` as one character rather than three bytes. That cure was correct and was still
working — measured, its output is byte-identical under `LC_ALL=C` and under UTF-8.

But Tcl reads `LC_ALL` for **itself** to choose `encoding system`, and the builder emitted a
backslash before every non-alphanumeric character:

| `encoding system` | first token | Tcl ARE verdict |
|---|---|---|
| `utf-8` | `\❯` — ❯ is not alphanumeric | literal-escape ⇒ compiles |
| `iso8859-1` | `\â` — â **is** alphanumeric in Latin-1 | unknown escape ⇒ **REFUSED** |

The refusal killed the expect program outright: the arm never ran, the keylog stayed empty, and the
script still exited **0**. Fail-open and silent, presenting as "the selector never moved".

## Three things that made it hard to see

1. **It counted as a relapse.** Same suite, same `❯`, same 8-of-11. The previous cure's own comment
   records that count, so the second defect read as the first one returning. A cure still doing its
   job does not stop the next hop from being broken — verify the cure before re-deriving it.

2. **The green path and the red path differ only by ambient locale.** `/ship`'s gate and any desk
   `bats` run inherit UTF-8 and pass. `postland-verify` runs the corpus from launchd, whose plist
   exports PATH and nothing else — no `LANG`, no `LC_ALL`, so libc falls back to C. That is the
   same LANG-less launchd corpus run behind post-land RED `d6a4896406aa`
   (`hooks/anti-deference-nudge.sh:214`), where a POSIX bracket expression degraded to a byte set.
   **Ask what env the failing runner actually supplies before theorising about the code.**

3. **The suite could not catch it on a desk.** A mutant reverting the cure left all 11 original
   tests green under a UTF-8 runner. The suite only redded off-box because `offbox-run.sh` pins
   `LC_ALL=C` — which is precisely the trap that file's own § COROLLARY names: *an axis supplied by
   the harness is an axis the suite is not testing.* A suite testing an env-coupled invariant must
   set the hostile value **itself**.

## The cure shape

Escape **ASCII punctuation only**. Every Tcl ARE metacharacter is ASCII, so nothing is lost, and a
non-ASCII character is a literal under either encoding — pattern and input then decode the same way
and match. Generalised: *do not emit an escape whose legality depends on a classification the
consumer makes.*

Test membership against a literal set rather than `[[:ascii:]]` or a glob range — a range is
collation-dependent, a class table is interpreter-dependent, and this file runs under macOS
`/bin/bash` 3.2.57. `${set#*"$ch"}` is plain POSIX expansion needing neither, already proven in
desk-executed code (`hooks/validate-bash.sh:476`, `hooks/lib/dod-path.sh:127`,
`hooks/lib/placeholder.sh:108`).

## Method note — prove the blast radius, don't argue it

The diff could reach siblings only through `lr_wrap_re`'s output, so that output was diffed
directly, trunk vs branch, for all 14 phrases the repo calls it with: 7 ASCII-only phrases
byte-identical, 7 `❯` phrases differing by exactly one byte. Then compile-and-match verdicts against
the real captures showed that byte is **inert under UTF-8** (identical MATCH/NOMATCH at every
width) and decisive under C. That is a stronger and far cheaper control than a whole-suite A/B —
and the suite A/B attempted first was confounded twice over: a `git clone --local` resolved
`origin/main` to the *clone source's* stale local branch rather than to trunk, and running both
arms concurrently let them contend. **Check what `origin/main` resolves to inside a clone, and run
A/B arms sequentially.**

## Companions

- `docs/lessons/a-fixture-s-hermeticity-ends-where-its-subject-spawns-a-third-tool.md` — the same
  boundary for PATHS; this is the encoding/escaping face of it.
- `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/c-locale-turns-character-ops-into-byte-ops.md`
  — green on the desk, red in CI ⇒ try `LC_ALL=C` first.
- `docs/lessons/the-deployment-interpreter-is-not-the-one-on-your-path.md` — the scheduler's env is
  not your shell's, which is why the launchd plist was the decisive read here.
