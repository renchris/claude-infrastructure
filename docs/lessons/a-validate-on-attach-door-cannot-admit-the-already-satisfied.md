# A validate-on-attach door cannot admit the already-satisfied, so that population needs its own lane

**Measured 2026-09-22**, `docs/research/drain-100p-q5-pilot-2026-09-22.md`.

## The shape

`cc-backlog falsify <id> --probe "<cmd>"` runs the probe **before storing it** and **refuses one
that exits 0 against a live row (rc 5)**. The intent is sound and it is the safety property the
whole premise-first design leans on: a probe that is already true would retire the row the instant
it is attached, so refusing it blocks a lying probe.

But "the probe passes right now" is the *only* thing the door measures, and two different
populations produce that reading:

| | probe passes now because… | truth | door |
|---|---|---|---|
| **lying probe** | it keys on the wrong thing | row is LIVE | refuses — correct |
| **already-moot row** | the row's premise genuinely died | row is MOOT | refuses — also |

Measured instance: `4f31ab82428c` (a launchd job still not loaded — live) and `0618ec5090a4`
(*"Press Ctrl-U in kitty pane 341"*, pane gone — moot) were refused identically.

## Why that is structural, not a bug

The consequence is not "the door is too strict". It is that **the attach-then-sweep pipeline can
only ever reach rows whose premise is TRUE TODAY and decays LATER.** A row whose premise died before
anyone wrote its probe is permanently invisible to the mechanism built to retire it — and those are
exactly the rows with immediate yield. In the measured run the pipeline's honest output was **ten
closes and zero falsifiers.**

So a design of the form *"attach a checkable condition, let a sweep retire what decays"* is
incomplete by construction unless it has a second arm. The unit of work is **adjudicate**, with
three outcomes — close it, falsify it, or leave it — not one.

## The rule

**Whenever a gate admits an artifact by evaluating it once at attach time, ask what its verdict
means for an artifact that is ALREADY satisfied.** If "already satisfied" and "wrong" produce the
same verdict, the gate has collapsed two populations, and the already-satisfied one has no path in.
Give it an explicit separate lane rather than discovering later that a whole stratum was unreachable.

The tell is a predicate of the form *"refuse if it passes now"*. It is a statement about the
PROBE, and it is being read as a statement about the ROW.

## Where else this shape lives

- A validation that rejects a migration which is already applied — the idempotent case and the
  broken case look alike.
- A health check that refuses to register a service already reporting healthy.
- A `--falsifier` / `--precondition` / `--guard` field on any work item.
- An alarm that refuses to arm on a condition currently firing.

## Companions

- `discharge-predicate-must-measure-its-own-subject.md` — the paired defect on the other side: the
  probe keying on a correlated object rather than the row's subject. In the same run, 3 of 13 rows
  would have been retired on an identifier their text merely MENTIONED, one of them a date-gated
  row reading *"On or after 2026-09-26"*.
- `arming-and-mootness-cannot-share-one-falsifier.md` — the same field asked to carry two meanings.
- `empty-vs-no-surface.md` — one reading, two states, opposite actions.
