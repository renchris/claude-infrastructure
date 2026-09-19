# A keep-both resolution of two appended blocks can leave the first one unterminated

2026-09-19, landing Round A of the limit-recover rebuild (`docs/plans/LIMIT_RECOVER_100P.md` § 9).

## What happened

Two waves, W1 and W4, each appended new `@test` cases to the end of `tests/lr-fleet.bats`. Rebasing
W4 over W1 conflicted on that file. The hunk read like a textbook append-append: HEAD held W1's two
cases, theirs held W4's four, no helper or `setup()` inside the region. I resolved it the obvious way
— delete the three marker lines, keep both blocks — and moved on. `bash -n` on a bats file is not a
valid check (bats syntax is not bash), and the `bats --count` I ran was shadowed by a
`grep -c '^@test'` fallback that printed a number whether or not the file loaded.

The suite then failed at the land gate with `bats-gather-tests … unexpected end of file from '{' on
line 482`. W1's last case had no closing brace.

## Why

git's diff had aligned the two waves' **identical closing lines** — the `}` and the blank line that
end every `@test` — as a *common suffix* and placed them BELOW the `>>>>>>>` marker as shared context.
So HEAD's block inside the markers ended mid-statement, theirs ended with a complete case, and the
one shared closing served W4's last case only. A keep-both resolution that preserves the markers'
interior verbatim reproduces exactly that: the first block runs straight into the second.

The two blocks were pure appends over one base (proved with `cmp` on the base-length prefix of each
side), so the correct file was `base + W1's tail + W4's tail` — not the conflict hunk's interior.

## The rule

When two sides both APPEND to the same file, do not resolve from the conflict hunk's interior: rebuild
the file as `base + side-A tail + side-B tail` after proving each side is a pure append over the base.
Then verify the merged file with the loader that will actually consume it — for a bats suite that is
`bats --count` (which gathers every `@test`), never `bash -n` and never a `grep -c '^@test'` fallback,
both of which print a number for a file that cannot load.

## Companions

- `docs/lessons/a-gate-refusal-is-not-a-gate-result.md` — assert the plan line before believing a
  filtered result; the gather failure here surfaced as ONE `not ok` over a `1..1` plan.
- `docs/lessons/fixture-stub-cannot-carry-an-apostrophe.md` — run the artifact through its real
  consumer before trusting a proxy check.
