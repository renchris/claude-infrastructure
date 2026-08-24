# MEMORY.md "over the loader cap" — the premise is refuted, and the item is a re-mint

**Date:** 2026-08-24
**Backlog item:** `c7bef93baca6` — *"MEMORY.md index back over the loader cap (23.4KB vs 24.4KB read
limit) — needs the human-gated /compact-memory pass, not an ad-hoc trim"*
**Verdict:** REFUTED on four independent grounds. No compaction pass was run, and none was owed.

This file exists because the condition re-mints. `bin/cc-premise:2521-2524` already records that "the
memory-index condition re-mints an item citing `MEMORY.md` every few days"; the next worker dispatched
on the next mint should read this instead of re-deriving it.

---

## 1. The item's own numbers contradict its own claim

> "back over the loader cap (**23.4KB vs 24.4KB** read limit)"

23.4 < 24.4. Under the figures the title itself carries, the index is **1KB under** the cap it is
alleged to be over. Nothing needed to be cut even on the item's own (dead) premise.

## 2. The unit is dead — superseded 2026-08-15

`24.4 KiB = 24985 B` is the pre-2026-08-15 byte premise. It is explicitly marked **superseded** in the
tree, at `hooks/memory-nudge.sh:22-23`, and the correction is the SSOT
`hooks/lib/memory-index-measure.sh`. Read out of the shipped bundle (Claude Code 2.1.233; stripping
landed in 2.1.211, cc-backlog `7a56de4c54ab`), the loader:

1. **strips the YAML frontmatter** — `/^---\s*\n([\s\S]*?)---\s*\n?/`, so a `--- … ---` header is free;
2. **strips block HTML comments** — including the `<!-- cold tier: … -->` pointer the rotor itself writes;
3. **trims**, then compares **`String.length` — UTF-16 code units — against 25,000**, plus a **200-line** cap.

A KB figure from `wc -c` therefore **over**-measures in three independent directions at once. The
em-dashes and middots this index is dense with (`—`, `⇒`, `·`, `≠`) cost 3 bytes on disk and **one**
unit against the cap. There is no reading of "23.4KB" that is a measurement of the thing the loader
checks.

## 3. The prescribed cure is the thing that already failed twelve times

> "needs the human-gated /compact-memory pass, not an ad-hoc trim"

An advisory-plus-manual-pass is precisely the shape that did not hold. `hooks/backup-before-write.sh:33-38`:
the index was **compacted twelve times between 2026-07-25 and 2026-08-06 and went back over every
time**, because `hooks/memory-nudge.sh` measures correctly but only *advises*. "A rule enforced
anywhere but where the act happens is detection, not a gate."

What actually landed, and is live on trunk:

| Mechanism | File | Role |
|---|---|---|
| Append-time chokepoint | `hooks/lib/memory-index-budget.sh` | **Refuses** the Write/Edit that would breach either cap |
| Automatic rotor | `bin/cc-memory-rotate` | Moves closed-out entries to the cold tier, verbatim and reversibly |
| Single measurer | `hooks/lib/memory-index-measure.sh` | Gate, advisory and rotor can never disagree |

The rotor's self-heal is measured, not hoped: 2026-08-21, on a `cp -Rp` copy of the live
claude-infrastructure index pushed past the cap — `rotated moved=29 stage2=29`, **25873 → 20949
units**, back under 25,000 with 4,051 units of headroom (`bin/cc-memory-rotate:71-80`). A human-gated
compaction pass is what those two mechanisms were built to replace.

## 4. The item is item N of a condition that was explicitly de-duplicated

`bin/cc-backlog:280-295` records the defect and its fix. The ledger's event key is
`project + title + source`, so **a title carrying a live measurement re-keys itself every time it is
measured**. One standing condition — "this project's memory index is over its loader budget" —
therefore minted **21 separate items** between 2026-07-25 and 2026-08-06 (15 claude-infrastructure,
6 reso-management-app): `…21.2KB…`, `…22.1KB…`, `…23.3KB…`, `…24.1KB…`, `…20.5KB…`, `…20.6KB…` — each a
different hash of the same fact. The done-guard could not fire either: `004502cf59ab` closed at
21:28:01Z, `0fc2ae0d0140` was claimed at 21:34:01Z, six minutes later, same condition, no code change
between.

The fix was `--condition <slug>`, which keys on `project+condition` and **drops the measurement from
the hash**. The slug may not contain a digit, deliberately.

**This item's title carries `23.4KB`.** It is the exact shape the condition key exists to collapse.
`hooks/memory-nudge.sh:250-254` even hands the correct filing form to any session that reads the
advisory, and notes that the prior false mints "happened at **20.5 KB and 22.5 KB — under this
limit**" — the same under-the-cap shape as this one.

The correct filing form, for whoever sees this condition next:

```
cc-backlog add --condition memory-index-over-budget --project <project> --title "<the live size>"
```

---

## Where MEMORY.md actually lives — the location the premise check asked to resolve

`MEMORY.md` has **zero carriers on `origin/main`** and does not exist anywhere on a fresh clone. It is
**not a repo file at all**: it is the user auto-memory index at
`~/.claude*/projects/<encoded-cwd>/memory/MEMORY.md`, on the operator's machine. This is documented at
`bin/cc-premise:2519-2524`, which notes that collapsing "zero carriers" into "missing path" made that
arm "a FALSE POSITIVE BY CONSTRUCTION for a whole live population" (backlog `a431c71076e6`, measured on
`cf6eb3e47b12`).

Consequence for dispatch: **this item is unactionable from any remote/ephemeral session by
construction** — the file it names is not in the repo, and `~/.claude/autonomy/` (the backlog store) is
not present either. It can only be measured on the operator's machine, and there the append-time gate
and the rotor already hold it without a human pass.

## Residual defect found and fixed

`bin/cc-memory-rotate:348` still stamped `${LIMIT} B read limit` into the `<!-- cold tier: … -->`
pointer — a **byte** label on a value that is loader **chars**. That line is written *into the index*,
i.e. into the one file the next observer measures, so it re-seeded the dead byte premise at exactly the
point where someone sizes the next cut. Corrected in this change to `${LIMIT}-char read limit`. No test
asserted the old substring (`tests/cc-memory-rotate.bats:106` matches only `cold tier`).

**The first attempt at that one-word fix was RED, and the failure is worth keeping.** Spelling the unit
out in the stamp — `(loader chars, NOT bytes — see hooks/lib/memory-index-measure.sh)` — failed
`tests/cc-memory-rotate.bats` **17** and **20**, both raw-size assertions. The pointer is free against
the 25,000-char cap because the loader strips block comments (test 9 pins exactly that), and it is
easy to read "free" as free *everywhere*. It is not: it still costs a **line** against the 200-line cap
and real bytes on disk. This is the rotor's own recorded mistake — `hooks/lib/memory-index-measure.sh:21`
notes "the rotor was budgeting for its own bookkeeping" — arriving from the opposite direction. The
explanation belongs in the source comment; the stamp gets the one corrected word.
