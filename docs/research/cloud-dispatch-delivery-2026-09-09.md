# Cloud dispatch delivery — backlog 42ab9ce1a2e7 re-measured and CLOSED as already-cured

**Verdict: the cure is on trunk and live (`124c4da06`, 2026-09-04). The item's framing is REFUTED.
No code was written for this row.**

## What the item claimed (measured 2026-08-16, n=112)

40 LANDED (36%) · 32 STALLED (29%) · 32 NOT-STARTED (29%, "no ref after 1-4d") · 7 ABANDONED · 1
BOOTING. It named NOT-STARTED "the backlog's dominant inflow" and asked first: *does the VM boot at
all and die, or does the fire never reach it?*

## What is true 24 days later (n=688, re-measured 2026-09-09)

STALLED 372 (54%) · ABANDONED 214 (31%) · LANDED 93 (14%) · UNKNOWN 9.

**The FIRST QUESTION is answered, and it is neither branch of the fork it offered.** 465 of 688
declarations (STALLED + LANDED) carry a `last_sha` AND a `last_seen_at`: the VM booted, the fire
reached it, and it pushed. Only 207 left no trace at all (`base_probe=ok` on 204 of them). The VM
boots. The fire arrives. The loss is downstream of both.

**`NOT-STARTED` no longer exists as a verdict.** `7e3124e43` (2026-09-07) withdrew it past `life_s`
as overclaiming: a session that RAN, finished and never pushed leaves exactly what a session that
never booted leaves, and the claim was hardening with age in the wrong direction.

### The delivery rate was a denominator artifact

688 declarations are **157 unique items**. 51 items were dispatched more than once and account for
**565 of 688 declarations (82%)**; the worst single item was fired **38 times**. Per *declaration*
delivery is 14%; per *item* it is **52%** (81 of 157 landed at least once). Both "36%" and "14%" are
per-declaration rates over a population dominated by re-fires of the same work.

### The actual dominant inflow was re-dispatch of ALREADY-LANDED work

**211 of 688 declarations (31%) were fired after their own item had already landed** — 18 items, one
still being re-fired 11 days post-land (`01ab05685857`: landed 08-24, re-fired to 09-04, median gap
between re-fires 6.4 h). That waste is 39% of all STALLED and 25% of all ABANDONED: a large share of
both "failure" classes is the loop, not independent failures.

Mechanism: the DONE-GUARD is correct and fail-closed on the ledger's `wasDone` latch, but the latch
is set by the backlog `done`, which lags the cloud land. Measured over 77 items with both events:
median **2.33 d**, p90 **12.19 d**, max **20.33 d**. Every re-fire in that window reads a genuinely
open row.

## Why nothing needed building

`124c4da06` (2026-09-04) added two gates over one walk of the declaration store — ALREADY-DECLARED
per item, and a lane-wide pile cap — and its own commit message cites the same measurement this pass
re-derived independently (17 ids owning 379 of 665 declarations, worst 37 fires for one id; measured
here 5 days later as worst 38 of 688).

Effect discharged, not merely cured:

| | before cure | after cure |
|---|---|---|
| post-land re-dispatches | 210 | **1** |
| pending pile vs cap | 543, +23.5/day | **12 of 50** |
| fire rate | 29.9/day | ~2/day |

Since 2026-09-05 there are 6 declarations over 6 distinct items; the only two repeats
(`badb132df232`, `c18e7ea9e6b1`) each followed a `retired` verdict on the prior declaration, which
releases the item **by design** — both gates fall away as declarations become terminal. Zero gate
violations. The gate is demonstrably firing in production: 328 `already-declared` skip records in
`~/.claude/autonomy/idl.jsonl`, most recent reading `4 of 6 cloud item(s) already hold an unlanded
declaration and are NOT re-fired; pending_unlanded=12 of 50`.

**Landed AND live** — `~/.claude/bin/cc-dispatch` symlinks into the shared checkout and its blob is
`9109de61dc7a`, byte-identical to `origin/main:bin/cc-dispatch`, carrying both gate symbols.

## Dispatcher vintage

The brief that fired this session was composed by `bin/cc-dispatch` blob `b4e8edb92e17`; trunk and
live both read `9109de61dc7a`. The dispatcher that fired me was BEHIND — a convergence fact about
the deploy layer, not a defect in the cure. It is also why this row was still being dispatched with
a framing its own subsystem had already retired.

## The residual, named and not filed

Two facts survive this close and neither is this row's:

1. **STALLED is now the dominant class (54%)** and 226 of those are not post-land waste — a VM that
   pushes a ref and then freezes. That is a different question from the one this row asked, and it
   has no measurement here.
2. **Land→close latency is still 1.4-2.5 d** post-cure (n=3). The gates make it harmless for
   *dispatch*, because a pending declaration now holds the item. It is no longer an inflow source.

Neither is filed: (1) is not this row's scope and would be a fresh measurement, not a deferral, and
(2) is measured as harmless. Recording them here is the honest disposition — a row for either would
be an unanswerable placeholder a future session pays to re-derive.
