# The denominator's 30× spread is four estimators, not four readings — and only one of them can identify a marginal

**Date:** 2026-08-25
**Item:** cc-backlog `193ae8ddce72` — *"Measure marginal load per ACTIVE session — the denominator of
every capacity claim, currently spanning 30× (0.172 / 0.566 / 1.89 / 2.5–5); sampler must pass a
correlation control."*
**DoD ref:** [`gc-cpu-vs-session-ceiling-2026-08-18.md`](gc-cpu-vs-session-ceiling-2026-08-18.md) §5
**Ships:** `scripts/session-load-marginal.sh` · `tests/session-load-marginal.bats` (22 cases)

---

## 1 · What this landed, and what it did not

**Landed:** the instrument, validated against planted ground truth, with the control the item names
as its acceptance criterion wired in as a fail-closed gate.

**NOT landed: a number.** Every figure in this document comes from a **simulation at the box's
measured parameters**, never from the box. Producing the real value needs the recorder running on the
10-core Darwin fleet — see §5. Saying otherwise would add a fifth unverified value to the four this
item exists to reconcile, which is the exact failure mode the DoD's own control was written against.

---

## 2 · The spread is not disagreement about a quantity — it is four different questions

The four incumbents are each arithmetically correct on their own terms. They differ because three of
them cannot identify a marginal *even in principle*:

| Value | Estimator | Why it cannot be the marginal |
|---|---|---|
| `0.172` | pooled OLS of load1 on session count, over **levels** | Unidentified — see §3. Its regressor explains ~0% of the outcome's variance on this box. |
| `0.566` | in-band bucket median | Same family, less power. That it differs from 0.172 by **3.3×** over the same machine is the tell. |
| `1.89` | `(44.4 − 27.4)/9`, nine sessions arriving together | Right *kind* — a difference — but n=1 pair, no drift arm, and nine-at-once is a different regime. The wave's own log records one instrumentation run moving load 19 → 36 with session count **unchanged**. |
| `2.5–5` | aggregate ÷ N (`spawn-presence.sh` header) | Not a marginal at all — the repo's own `[Ratio ≠ marginal]` defect. |

The load side of this box is dominated by terms the census cannot see. At a **constant N=15–16** it
read `11.21 / 19.06 / 27.26 / 29.67 / 32.14 / 36.07` — a ±8 swing, larger than the entire quantity
being estimated. Any estimator that does not condition on the moment the census *moves* is fitting
that swing.

---

## 3 · The diagnosis, made executable

`tests/session-load-marginal.bats` case 05 refits a series whose marginal is **planted at 1.00** the
way `0.172` and `0.566` were produced — OLS over levels — and reports its own interval:

```
level OLS      slope 0.9986   r² 0.00439   95% CI [-0.4791, 2.4763]
first-diff     beta  0.8915                95% CI [ 0.3608, 1.4221]
truth          1.00
```

**The level fit's interval contains every incumbent** — 0.172, 0.566, 1.89 and the bottom of 2.5–5.
It is not biased toward zero; the first run of that case measured a level slope of **0.666** on a
neighbouring fixture, which is not attenuation and is why the case is worded as it is. The level
slope is a near-zero covariance divided by a small census variance: a ratio of two quantities this
box does not hold still, so it can land anywhere. **That, and not a changing machine, is what
produced four numbers 30× apart** — they are draws from an estimator whose interval is ~3 load points
wide, and not one of them was quoted with an interval.

The first-difference fit on the *same series* excludes `0.172`, `1.89` and `2.5–5`, and retains
`0.566` alongside the truth. Differencing buys real discrimination; levels buy none.

---

## 4 · The estimator, and the two things that make it identify

    d_load = alpha + beta · d_census + e        over consecutive samples

- **`beta`** — marginal load per ACTIVE session.
- **`alpha`** — per-interval **drift**: everything that moves load without a session moving. This is
  the arm `1.89` had no way to subtract, and fitting it is what makes the design a
  difference-in-differences rather than a before/after.

**Why differencing.** Levels ask *"do busy moments have more sessions?"* — on this box, dominated by
confounders on their own clock. Differences ask *"when the census moved by one, did load move?"*, so
identification is local to the transition and any confounder slow relative to the sampling interval
differences out.

**Why natural arrivals, not a staged experiment.** The DoD sketched a babysat two-arm run: hold a
quiet window, fire one session, sample. That is one pair per sitting, needing N≥5 pairs at different
baselines — days of supervised work, which is why the measurement has never happened. A recorder at
fixed cadence harvests the same transitions for free, at every baseline the box naturally visits.

**Both censuses are recorded**, from `scripts/lib/spawn-presence.sh` rather than re-implemented:
`cc_sp_active` (mid-turn — the item's estimand) and `cc_sp_trees` (resident, matched at argv's
**command position**, which is how the DoD's "executable path, never argv" requirement is actually
satisfiable on Darwin). That library's header records three measured census defects a fresh
implementation re-commits by default.

⚠️ **`active` is a proven lower bound**, so a real transition recorded as no transition lands in the
drift arm and **biases `beta` upward**. A ceiling derived from this instrument is therefore
conservative — the safe direction for a gate, and stated out loud because an unstated bias direction
is how an estimate becomes a fact.

---

## 5 · The control that must be able to fail — and what it cost to state properly

The DoD's criterion, verbatim: *"the sampler has to reproduce the load average it apportions. If the
census stays flat while load moves, it is the instrument… No attribution figure should be quoted
again until a sampler clears that control."*

That is **two** checks, and conflating them makes the control unfalsifiable:

- **C1 — the census must MOVE (gated).** A census flat at 19–20 across a 2.3× load range cannot
  apportion anything. Failing C1 is **`BLIND`, and under BLIND no marginal is printed at all** — not
  wide, not hedged, not `null`-with-a-number-beside-it. A number on the page is quotable no matter
  what qualifies it. Armed only when load actually moved, so a quiet night is not "instrument
  failure". Suite cases 10–14; selftest case B replays the dead headline's own shape.
- **C2 — the census should EXPLAIN (reported, NOT gated).** `r(load1, census)` over levels. **On the
  fixture whose truth is 1.00, level-r is 0.066.** A correlation gate would have refused to emit a
  correct answer. Worse, gating on it would make the control unable to ever return *"sessions are
  cheap"* — it could only confirm the hypothesis. A census that moves while load does not follow is a
  **result**, not a blindness.

Four verdicts, never a boolean: `MEASURED` (0) · `INCONCLUSIVE` (1) · `BLIND` (2) · `NO-DATA` (3).

---

## 6 · What the measurement will cost — the number that reframes the item

From the validation run (400 rows at 60 s = 6.7 h of sampling, 114 transitions across 7 baselines):

| Question | Half-width needed | Intervals | Sampling at 60 s |
|---|---|---|---|
| Is it ~0.5 or ~2? (separate `0.566` from `1.89`) | < 0.66 | **~400** | **~7 hours** |
| Pin it to ±0.2 (separate `0.172` from `0.566`) | < 0.20 | ~2,809 | ~47 hours |

**The item is roughly one day of passive recording for the answer that matters**, and about two for a
tight one. The DoD's "sample 5 min → fire one session → sample 5 min" was never going to produce a
decisive number: at this box's noise, one pair has a half-width of several load points. An
`INCONCLUSIVE` run prints the `n` that would end it, so this is self-reporting rather than a
projection to be trusted.

---

## 7 · What remains — and it needs the box

Everything here is validated against planted truth on Linux. **The measurement itself needs the
10-core Darwin fleet**, because the quantity is a property of that machine and no other.

To take it:

```sh
# 1. record — one row per minute, alongside capacity-alarm
scripts/session-load-marginal.sh sample        # ~ms; from a 60 s timer

# 2. read it back, any time
scripts/session-load-marginal.sh analyze
```

Deliberately **not** landed as a launchd job: installing a recurring timer on the operator's box is
their call, not a maintenance edit, and the same restraint `capacity-alarm.sh` states about shedding
applies here. Until the recorder has run, **no attribution figure may be quoted** — that is the DoD's
rule, and it now has a mechanism behind it rather than a paragraph.

**Consumers waiting on the result:** `CC_ADMIT_ACTIVE_CEILING=8`, `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0`
(whose own code comment cites a "§9.5 measured ceiling" that
[contains no such derivation](gc-cpu-vs-session-ceiling-2026-08-18.md#3--the-actionable-finding-and-it-has-nothing-to-do-with-the-vendor)),
`MACHINE_CAPACITY_V2`'s model, and every "+N sessions" projection in the repo.

⚠️ **A caveat the instrument cannot remove.** The DoD's §5 also lists *"whether load average means
anything as a capacity signal at all"* as unmeasured, and `capacity-alarm.sh:139-147` records that
**the survived population contains the fatal value** (fatal at 2.53/core; 13 consecutive survivals at
2.92–5.98/core). This work makes the denominator *measurable*; it does not make load average a
capacity signal. A tight `beta` divided into a threshold that cannot separate fatal from survived
still yields a ceiling with no failure point behind it. That axis is a separate item.
