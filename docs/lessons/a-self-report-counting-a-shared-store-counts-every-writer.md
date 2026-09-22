# A self-report that counts a SHARED store counts every writer, not just itself

**Measured 2026-09-22**, `docs/research/backlog-drain-audit-2026-09-22/a5-supply-side.md`.

## The defect

`cc-discover` reports how much work it added by bracketing its own pass:

```
n0=$(backlog_count)      # wc -l on ~/.claude/autonomy/backlog.jsonl
  ... run the critics ...
n1=$(backlog_count)
echo "added $((n1-n0))"
```

Over 39 runs it self-reported **275 adds**. The store gained **4** rows it actually authored.
A **~69× inflation**, reported confidently, in the one number the supply side publishes about itself.

## Why the bracket is not a measurement

`backlog_count()` is `wc -l` on a store that **other processes write concurrently**. Worse, the
subject *causes* those writes: `cc-backlog` fires `dispatch_kick` on rc 0 — **including a deduped,
no-op add** (`bin/cc-backlog:7000`) — and the woken dispatcher's 1,674 claim/reopen records land
inside the n0..n1 bracket.

So the delta is not "what I added". It is "everything anyone appended while I ran", and the largest
contributor is **the consumer this pass just woke up**. The supply side's only self-report was
measuring the drain.

Note the two failures compose, and each alone is survivable:
1. **Shared denominator** — the store has other writers, so the bracket over-counts.
2. **Self-induced traffic** — the subject triggers the biggest other writer, so the over-count is
   *correlated with the subject's own activity*. A busier pass reports a bigger number. The metric
   therefore moves in the right direction for the wrong reason, which is what makes it survive
   review: it never looks broken.

## The rule

**A before/after delta on a mutable shared store measures the STORE's traffic, never your own
contribution.** Count what you appended, at the point you append it — not by differencing a
global.

Concretely, in order of preference:
- Have the write path return an id and count the ids you got back (`add` already echoes one).
- Stamp provenance on the row and count rows carrying your stamp.
- If you must bracket, bracket a resource **nothing else writes** — a private temp file, your own
  journal — never the shared ledger.

## The generalisation, and where else to look for it

This is not about backlogs. It is about any self-report of the form `after − before` where `before`
and `after` are reads of something outside the subject's exclusive control:

- rows in a shared table · files in a shared directory · lines in a shared log
- entries in a work queue · refs in a shared repo · keys in a shared cache
- **any counter the subject's own side effects can advance**

The tell is that the metric has **no way to be wrong in the safe direction**. It cannot
under-report. Every concurrent writer inflates it, and a subject that wakes its consumers inflates
it most exactly when it is working hardest.

## Companion lessons

- `process-count-is-not-a-count-of-the-work.md` — same family: a cheap global proxy standing in for
  an attributed count.
- `a-test-double-s-output-is-indistinguishable-in-a-shared-store.md` — the *provenance* half of the
  same problem; stamping the row is the fix both lessons point at.
- `positive-control-the-denominator.md` — when a ratio looks wrong, suspect the denominator's
  population before the numerator.
- `damping-store-understates-emission-volume.md` — the mirror case: a shared store that
  *under*-reports because it is overwritten in place.

## How to falsify a suspected instance

Run the producer against a **private copy** of the store with every other writer stopped, and
compare its self-report to the row count it actually authored. If the two disagree, the bracket is
counting someone else. Do not skip the "other writers stopped" half — a quiet box reproduces the
healthy reading and proves nothing (`a-cure-is-verified-only-under-the-load-that-caused-it.md`).
