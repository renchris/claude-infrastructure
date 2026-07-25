---
status: open
found-by: relogin-build session, 2026-07-25 (surfaced by tm/relogin-sched, verified by lead)
scope: FINDING + REPRODUCTION ONLY — 22 sites deliberately NOT swept here (see "Why not fixed here")
severity: silent misparse — wrong data, green tests, no error
---

# `IFS=$'\t' read` silently shifts fields left when any field is empty

## The defect

Tab is an **IFS-whitespace** character, so `read` collapses a *run* of delimiters into
one. Any empty field therefore does not produce an empty variable — it **shifts every
later field one position left**, silently, with no error and no non-zero status.

## Reproduction (verified this machine, 2026-07-25)

```bash
printf 'acct\tREQUIRED\t\t2026-08-01\t12\tclaude-next\n' \
  | { IFS=$'\t' read -r a b c d e f; echo "c=[$c] d=[$d] e=[$e] f=[$f]"; }
```

```
c=[2026-08-01] d=[12] e=[claude-next] f=[]
```

Expected `c=[]` (the empty field) and `f=[claude-next]`. Instead everything after the
empty field moved left by one.

## Why it is severe, not cosmetic

This is not a display bug — it silently rewrites *meaning*:

- **It bit this build for real.** In the relogin poller, a `launcher` string landed in the
  numeric `k` (live-session count) field. A non-empty `k` reads as "account busy", so the
  poller would have **skipped that account forever, silently**, while its test suite stayed
  green. An account that is never attempted looks identical to an account that needs
  nothing — until the login deadline passes.
- **`bin/cc-blockers` renders the operator's recovery command** from
  `while IFS=$'\t' read -r slug acct model refusal cmd`. Any row with an empty middle
  field (missing `refusal`, absent `account`, no `blocked_model`) shifts `recover_cmd` out
  of its variable — so the operator's one-glance blocker view shows a truncated or wrong
  command. That is a direct defeat of the Silver-Platter rule.

The general shape: **the more nullable the schema, the more often the parse is wrong** —
and it is wrong in a direction that produces plausible-looking values rather than obvious
garbage.

## The fix — sentinel padding, NOT a non-whitespace IFS

The tempting fix is a non-whitespace delimiter. **It does not work on macOS.** Verified on
`/bin/bash` 3.2.57(1)-release (arm64-apple-darwin24):

```bash
printf 'x\001\001y\n' | /bin/bash -c 'IFS=$"\001" read -r p q; echo "p=[$p] q=[$q]"'
# p=[xy] q=[]      <-- did not split at all
```

The working fix is to **guarantee no field is ever empty at the producer**, then strip the
sentinel after the read:

```bash
# producer: give every nullable field a placeholder
jq -r '.[] | [ (.a // "—"), (.b // "—"), (.c // "—") ] | @tsv'

# consumer: read, then un-sentinel
while IFS=$'\t' read -r a b c; do
  [ "$a" = "—" ] && a=""
  ...
done
```

`tm/relogin-sched` applied exactly this (`norm`/`dash` sentinel padding on all four
field-reads) in `bin/cc-relogin-poll`, with a regression test.

## Exposure

**22 other `IFS=$'\t' read` sites across `bin/` and `hooks/`.** Any whose fields can be
empty carry the same latent silent-misparse. Enumerate them with:

```bash
grep -rn "IFS=\$'\\\\t' read" bin/ hooks/
```

For each, the question is only: *can any field ever be empty or null?* If yes, it is
already wrong on those rows.

`bin/cc-blockers` was **fixed in this build** (it is in the relogin team's scope). The
other 21 are untouched.

## Why not fixed here

The Follow-On Gate fails on **boundedness**: 22 sites spread across files that other live
sessions currently hold in their own worktrees. A sweep from this session would collide
with in-flight work and drag unrelated files into a landing whose scope is the relogin
build. Measuring and documenting is cheap and collision-free; the sweep is neither.

## Suggested sequencing

1. Enumerate with the grep above and triage by *nullability of the schema*, not by call
   count — a site with three always-present fields is safe; one reading an optional
   `refusal`/`reason`/`detail` is not.
2. Fix at the **producer** (add `// "—"` in the `jq @tsv`) wherever the producer is in the
   same repo — one change protects every consumer of that stream.
3. Add a test per site with a deliberately empty middle field. That test fails today.
4. Consider a shared `tsv_read` helper in `lib/` so the sentinel convention is declared
   once rather than re-derived 22 times.
