# Re-adjudicating the hook-chain collapse on the occupancy axis

**Date:** 2026-09-08 · **Item:** backlog `05c79abca813` (filed 2026-08-09T23:44:17Z)
**Subjects:** `hooks/hook-chain.sh` · `scripts/hook-dispatch-bench.sh` · `config/hook-chains.d/`
**Inherits:** `docs/research/active-session-occupancy-2026-08-09.md` §3.1 · `docs/plans/HOOK_CHAIN_COST.md` §3

---

## 1. Verdict

The item's premise is **correct and still live**: `hook-chain.sh`'s shelving verdict (`a5cab5617` —
"REAL 6-guard chain, serial 174 ms · dispatcher ~180 ms") is a wall-clock result, wall-clock is the
quantity that does *not* move under serialisation, and nothing on trunk has re-adjudicated it since.
The only commit touching either cited file in the 30 days since filing is `8bbf1d9f0`, a pipefail-lint
repair that happens to drain a line in `hook-chain.sh` and says nothing about the collapse.

**The collapse must not be wired today, and the reason is not the occupancy number.** It is a
readiness fact that holds whatever that number turns out to be:

> `config/hook-chains.d/pretooluse-bash` had drifted **four members behind** the settings.json set it
> replaces (six named, ten registered), plus one more on `posttooluse-bash` (two named, three
> registered), and the file also still named `curl-gate.py` after activation 26 repointed
> settings.json at `curl-gate-scope.sh`. Wiring the dispatcher in that state would have run
> **`smart-bash-allowlist.sh`, `qos-rewrite.sh`, `coldcompile-admit.sh`, `pr-gate.sh` and
> `relay-verbatim.sh` zero times — silently.**

Both instruments this adjudication depends on were broken in the same way — each derived its own
acceptance criterion from something that could not see the subject — and both are repaired here.

**And repairing the first one recovers a result from data that has been on disk since 2026-08-09.**
Re-read under the sign-test interval, that run's five per-cycle ratios give a **94% CI of 2.10..6.43,
which excludes 1.00**, against a null control whose 94% CI is 0.29..1.51 and contains it. The two do
not overlap. So **the SIGN of the effect is established** — parallel dispatch really does cost
strictly more occupancy per unit of work than serial — and only its **magnitude** is still unmeasured
(§4.2). The old gate could not say this, because it never asked whether the interval excluded the
null; it only asked whether the range was wide, and answered "wide" to both arms alike.

**The magnitude run has since been made** (§5.1, 2026-09-09): parallel dispatch costs a median
**5.98×** the occupancy per dispatch, 96% CI **3.45..8.35**, against a null control that certified
under the same ambient at 0.96× (94% CI 0.74..1.20). Sign *and* size are now on the record. This
paragraph read *"the magnitude run remains unrun, for a reason recorded in §5 rather than waved
at"* until that run; §5 is kept intact and the reason it gave was sound for exactly one day.

## 2. Defect 1 — the bench's acceptance gate was anti-monotone in evidence

`scripts/hook-dispatch-bench.sh` is the instrument the item names, and it has produced exactly one
live result: a median parallel/serial ratio of **3.46×** whose null control failed on spread
(0.29..1.51 over 5 cycles). `active-session-occupancy-2026-08-09.md` §3.1 states the remedy — *"re-run
both arms on a box whose ambient is stable within 2×"* — and the bench itself printed a second one:
*"Re-run quieter, or with more cycles, before quoting it."*

**The second remedy could not work, and it is the only one the operator of the bench controls.** The
gate was `max/min > 2.5` over the per-cycle ratios. The range of a sample is non-decreasing in the
sample size, so every added cycle could only widen it — while the median it guards converges.

Measured, 2,000 replicates per point, ratios drawn from one *unbiased* distribution at the noise that
live control actually showed:

| cycles | 3 | 5 | 10 | 20 | 40 | 80 |
|---|---|---|---|---|---|---|
| P(control certifies), old gate | 51.7% | 42.1% | 19.2% | 2.1% | **0.0%** | **0.0%** |
| median error, `\|log2\|` of the median ratio | 0.244 | 0.200 | 0.138 | 0.103 | 0.071 | 0.051 |

The estimator was converging and the gate was diverging. Certification was unreachable *by collecting
data*.

**Repair:** the dispersion statistic is now the two-sided distribution-free **sign-test interval** on
the median — with the `m` per-cycle ratios sorted, `[R[k], R[m+1-k]]` covers the population median
with probability `1 - 2·P(Bin(m,½) ≤ k-1)`, and `k` is the tightest index reaching 90%. It assumes no
distribution, it is exact at every `m`, and its width **shrinks** as cycles are added.

Positive control on the statistic itself, 4,000 replicates per point — an interval with the wrong
coverage would be a worse rig, not a better one:

| m | k | nominal | empirical coverage | P(certify) new | P(certify) old |
|---|---|---|---|---|---|
| 3 | 1 | 75.0% | 74.4% | 54.7% | 50.7% |
| 5 | 1 | 93.8% | 93.6% | 49.7% | 42.1% |
| 10 | 2 | 97.9% | 97.5% | 73.5% | 18.2% |
| 20 | 6 | 95.9% | 95.8% | 95.7% | 2.3% |
| 40 | 15 | 91.9% | 91.7% | 91.7% | 0.0% |
| 80 | 33 | 90.7% | 90.3% | 90.3% | 0.0% |

Coverage tracks nominal within 0.5pp at every `m`, and certification now *rises* with evidence toward
the nominal confidence level, which is the correct asymptote.

**Below m=5 no `k` reaches 90%, so the interval degenerates to the full range and the gate is
byte-identical to the one it replaces at the 3-cycle default.** That is why `C1`, `C2` and `C2b` keep
their verdicts unchanged; it is the honest reading of three points, and it is labelled as such
(`— below the 90% target`) rather than dressed up as a 90% result. Tests: `E1` (must-change — the
interval narrows 1.00..5.00 → 2.00..4.00 across 5 → 21 cycles while the sample range widens
5× → 100×), `E2` (exact order statistics: m=20 ⇒ k=6 ⇒ 6.00..15.00 at 96%), `E3` (must-not-change),
`D4` (mutation — restoring the sample extremes as the endpoints makes `E1` unpassable again).

## 3. Defect 2 — the drift guard's expectation lived inside the checker

`tests/hook-chain-live-parity.bats` carries a test named *"registry membership matches the
settings.json set it replaces (drift guard)"*. It compared the registry to `$MEMBERS` — **a literal
array in its own `setup()`**. So it could only ever detect a change to the registry, never a change to
the thing the registry exists to mirror. Both were frozen at the six guards of 2026-07-31; settings.json
grew to ten; the guard stayed green across the entire drift and has never once gone red.

This is `MEMORY.md` `checker-population-rests-on-an-untested-belief` exactly: when a checker enumerates
*where* to look, falsify the sentence that justifies the enumeration.

**Why it is a safety matter on a component that is deliberately inert.** `hook-chain.sh`'s stated
safety laws include LOUD INERTNESS — *"absent/empty registry or missing member refuses, never admits"*.
That law fires on a member missing from **disk**. A member missing from the **registry** is a different
failure with no symptom at all: the dispatcher runs the list it was given, and the list is the
authority. The law that reads as covering this case does not cover it.

**Repair:** the drift guard now derives its expectation from the live `settings.json` (seam
`CC_LIVE_SETTINGS`; a missing file `skip`s with a reason rather than passing), checks **both**
registries, and treats an empty read as an instrument failure rather than a clean bill. A mutation
control appends one Bash hook to a copy of settings.json and requires the guard to fire and name it —
a fixture that changes nothing at all under the old expectation. `$MEMBERS` stays as the parity
*fixture* corpus, which is a legitimate and separate job, and now says so where it is defined.

The registries are reconciled to settings.json in the same commit, so the guard is green on truth
rather than on a stale constant.

## 4. What this settles about the collapse

| Question | Answer |
|---|---|
| Is the shelving verdict silent on occupancy? | **Yes** — the item's premise holds; `a5cab5617` measured wall-clock, and wall-clock is invariant under serialisation by construction. |
| Is the occupancy prize plausible? | **Yes, and the base is larger than §8 implied.** PreToolUse/matcher:Bash registers **ten** hooks today, dispatched concurrently, on the most frequent event there is. §8's "the collapse dispatcher was aimed at the cheap event" is true of *git subprocesses* and does not transfer to the fork-burst axis. |
| Is it measured? | **Sign yes, magnitude no.** The 94% CI is 2.10..6.43 (§4.2); pinning the number needs the deferred run (§5). |
| Should it be wired? | **No, today** — on §3's readiness grounds, which are independent of the measurement. A wiring migration must run the repaired drift guard first. |

### 4.1 A correction the adjudication turns on: the collapse removes CONCURRENCY, not forks

`HOOK_CHAIN_COST.md` §3 frames both structural answers as removing work — *"a broker or a collapse
removes registered-hook `fork`+`exec`s"*. Read against `hook-chain.sh`'s own two modes, that is not
what the collapse does:

| | harness forks | dispatcher forks | execs | peak concurrent |
|---|---|---|---|---|
| today, 10 registered entries | 10 | — | 10 | **10** |
| collapse, `exec` mode (the DEFAULT) | 1 | 10 | 10 | **2** |
| collapse, `source` mode (opt-in) | 1 | 10 (subshells) | 1 | **2** |

In the default mode the process count goes **up by one** and not a single `fork`+`exec` is removed.
Only `source` mode removes execs, and that is the mode whose largest member measured 48 ms *worse*
(`validate-bash.sh`, 94 → 142 ms).

This is not a quibble — it is why the wall-clock A/B was always going to read flat, and it is why the
occupancy axis is the *only* one on which this design can win. The dispatcher trades duration for
concurrency at roughly constant product, which is precisely the trade `session-capacity-ceiling`
§12 says is worth making (fork **rate** is not a capacity variable; fork **concurrency** is). A
reader who takes §3 at its word will look for a saving in the fork count, find none, and conclude the
collapse is worthless — when the thing it actually does is the thing the capacity model asks for.

### 4.2 The sign was already established — the old gate simply could not report it

`active-session-occupancy-2026-08-09.md` §3.1 publishes every number needed to re-adjudicate its own
run, and both arms are exactly reconstructible from them: the live arm's five per-cycle ratios are
printed in full (`2.10 2.66 3.46 3.70 6.43`), and at m=5 the sign-test interval is `[min, max]`, so
the control's interval depends only on its published `0.29..1.51` and its published median of exactly
`1.00` — the interior values are unobservable to the statistic and nothing here rests on them.

```
LIVE     median 3.46x   94% CI 2.10..6.43   ⚠ sign established, magnitude not (span 3.06x)
CONTROL  median 1.00x   94% CI 0.29..1.51   ⛔ unbiased, UNDERPOWERED
```

**The live interval excludes 1.00 and lies entirely above the control's.** §3.1 reached for that
comparison in prose — *"the live effect's floor (2.10) sits above the control's ceiling (1.51)"* — and
then withdrew it as *"directional, not certified"*, because the gate it had to answer to could only
speak about the range. It is now the instrument's own output at a stated confidence, which is a
different epistemic object from an eyeballed comparison in a footnote.

What this does **not** license is quoting `3.46×`. A 2.10..6.43 interval is a factor-of-three span:
the collapse's occupancy prize is somewhere between "doubles" and "sextuples", and every downstream
capacity sum needs the magnitude, not the sign. That is the run §5 defers.

## 5. What is NOT measured here, and why that is a refusal rather than an omission

> **Superseded 2026-09-09 by §5.1** — the run happened; the ceiling this section measures moved
> from a median load1 of 32.0 to 19.90 and the sweep caught a window. This section is kept intact as
> the record of why it was a refusal rather than an omission, and its reasoning is unchanged.

What §4.2 cannot supply is the magnitude, and that needs a quieter box. The certified run needs
`load1 < 14` (the bench's own start floor: *"a second-order effect is not
resolvable above it"*). Sampled every 10 s for the whole session — **139 readings, load1 24.4 to 48.5,
median 32.0** — on 10 cores, with **65-67 live `claude` processes** throughout. It never came within
10 of the floor, in either direction. The machine's own admission gate agrees and is stricter:
`cc-bats` refused to run any suite at `CC_BATS_MAX_LOAD_PER_CORE=2.0` against a load/core of ~3.2.

The bench's parallel arm holds `sessions × members` processes by construction — that is the quantity
under test and it cannot be throttled, only refused. Firing a deliberate fork-burst into a box the
capacity gate is already turning work away from is precisely what a capacity gate exists to prevent.
So the run is deferred on a **measured** ceiling, not a felt one.

It is filed with a falsifier, and the command is one line — the rig is landed, repaired and
self-certifying now, which is the whole of what this session could add to it:

```
scripts/hook-dispatch-bench.sh --control --cycles 20 --sessions 3 --members 8 --out /tmp/hdb-control.tsv
scripts/hook-dispatch-bench.sh           --cycles 20 --sessions 3 --members 8 --out /tmp/hdb-live.tsv
```

Twenty cycles rather than the default three: §2's table is the reason the number is 20 and not 5, and
under the old gate that choice would have made certification *less* likely.

Filed as backlog `2c563601bdd4` (*"run the certified occupancy sweep"*), class `not-yet-true`, with a
falsifier that retracts it if the collapse is abandoned or the verdict is recorded. **Whoever runs it:
write the result into this file under the literal heading `CERTIFIED OCCUPANCY VERDICT`** — that string
is what the falsifier greps for on trunk, and a verdict recorded under any other wording leaves the row
open forever.

## 5.1 CERTIFIED OCCUPANCY VERDICT — run 2026-09-09, box quiet enough at last

> ⚠ **Read §5.2 before quoting `5.98×`.** An independent run of the same commands, on the same box at
> strictly lower ambient, reads 2.90× (90% CI 2.45..5.32). The two agree where their ambient overlaps;
> the ratio this rig reports rises monotonically with ambient, and the cause is measured there. The
> **sign** below is unaffected and is now replicated three times.

**Parallel dispatch costs a median 5.98× the attributable occupancy per dispatch that serial dispatch
does, 96% CI 3.45..8.35 — and the null control certified under the same ambient, at median 0.96×
(truth is 1.00), 94% CI 0.74..1.20.** The live interval's lower bound, 3.45, clears the control band's
upper bound, 1.20, by a factor of ~2.9. The collapse's benefit on the occupancy axis is real and its
magnitude is now an interval rather than a direction.

**It replicates the 2026-08-09 run, which is the one thing neither run could supply alone.** §1's
re-read of that five-cycle data gives a 94% CI of **2.10..6.43**; this twenty-cycle run gives 96% **3.45..8.35**. The intervals overlap over 3.45..6.43 and both exclude 1.00, a month apart, on
different ambient, through a gate that was rewritten in between. A single run of a rig whose own
acceptance criterion had just been replaced is exactly the result one should not quote bare.

Backlog `2c563601bdd4` is discharged by this section. §5's refusal stood for exactly one day: the
premise it was filed under (`not-yet-true` — *"the box has never been quiet enough"*) was still true
when this run began, and the item was driven by **waiting for the box**, not by relaxing the floor.
150 ambient samples at 10 s over the wait window: min 13.39, p25 17.19, **median 19.90**, p75 28.48,
max 43.12 — only **2 of 150** readings at or under the bench's 14 start floor. Both arms were fired
into those windows by a poller that re-tries on the bench's own `exit 4`; the floor was never
overridden and `CC_HDB_MAX_START_LOAD` was never set. Contrast §5's filing-day sample: 139 readings,
median 32.0, never within 10 of the floor. The ceiling moved; it was not lowered.

| | control (null: serial vs serial) | live (parallel vs serial) |
|---|---|---|
| cycles requested / yielding a ratio | 20 / 19 | 20 / 15 |
| load1 at start → end | 13.93 → 20.91 | 14.00 → 33.90 |
| peak parallel processes | 24 | 24 |
| mean attributable occupancy, serial | 0.06914 | 0.02886 |
| mean attributable occupancy, arm B | 0.05869 (serial-b) | 0.26559 (parallel) |
| **median per-cycle ratio** | **0.96×** | **5.98×** |
| sign-test CI on the median | 0.74..1.20 (94%, k=6 of 19) | 3.45..8.35 (96%, k=4 of 15) |
| sample range of the per-cycle ratios | −1.19..162.28 | 0.32..16.15 |

**The bottom row is the whole of §2's argument, arriving as data rather than as simulation.** The
control's per-cycle ratios span −1.19..162.28 — a `max/min` of about −136, and 65× on the positive
part alone. Under the gate this rig carried until 2026-09-08 that control fails, catastrophically and
at any threshold, so the live 5.98× beside it would have been unquotable. Under the sign-test interval
the same 19 draws certify at 0.74..1.20, because 17 of the 19 sit inside 0.37..1.86 and the median
moves by at most one rank for each contaminated cycle. §2 predicted P(certify) ≈ 95.7% at m=20 for an
unbiased control and 2.1% under the old gate; this control certified. The estimator was always able to
see the effect — only the gate could not report it.

### Three caveats, none of which withdraw the verdict

1. **Both runs carry the bench's own `⚠ AMBIENT MOVED >2x BETWEEN CYCLES`.** Ambient ran 9.875..30.625
   (control) and 8.500..23.708 (live) runnable threads. The bench prints this to mean *treat the ratio
   as indicative*. What licenses quoting it anyway is not that the warning is minor but that **the
   control was run under that same ambient and passed**: the null arm is the empirical answer to *"can
   this rig resolve a ratio here?"*, and it answered — outside 0.74..1.20 — before the live arm was
   fired. That is the ordering the two-arm design exists to produce, and it is why a proxy warning does
   not overrule a measured one.
2. **The ratio filter is one-sided, and it drops more cycles when the box is noisier.** `verdict()`
   keeps a cycle only when serial's attributable occupancy is `> 1e-7`, so cycles where a burst pushed
   ambient above the serial arm are discarded — 1 of 20 in control, **5 of 20** in live. Retained
   near-zero denominators inflate their ratio, so the surviving set is biased *upward* at the tail.
   The median is the defence (one contaminated cycle moves it one rank), and the CI is computed on the
   retained m, so both are honest about the smaller sample; the 5-cycle loss is why live's k=4 of 15
   buys a *wider* 96% band than control's k=6 of 19 buys at 94%.
3. **Per-dispatch is the axis; throughput moves the other way.** Over the live run the parallel arm
   completed 77,238 dispatches against serial's 5,036 — 15.3×. §4.1's correction is what reconciles
   these: the collapse removes *concurrency*, not forks, so serial is not doing the same work more
   cheaply, it is doing less work at a lower cost each. Nothing here says the collapse is free; it says
   its occupancy benefit per dispatch is ~6×, which is the number §4.2 could establish the sign of and
   not the size.

Raw results, re-readable with `scripts/hook-dispatch-bench.sh --analyse <tsv>`: `/tmp/hdb-control.tsv`
and `/tmp/hdb-live.tsv` (session copies under the running session's scratchpad). Commands were §5's
verbatim, at `--cycles 20 --sessions 3 --members 8`.

## 5.2 The certified ratio is a FUNCTION of ambient, and §5.1's 5.98× is its noisy-box end

**An independent run of §5's verbatim commands — taken on the same box two hours EARLIER, at strictly
lower ambient — reads a median 2.90×, 90% CI 2.45..5.32. It does not contradict §5.1.** Over the
ambient band the two runs share, they agree to within noise: **3.41× against 3.53×**. What differs is
which stretch of the ambient axis each run sampled, and the ratio this rig reports is a **monotone
increasing function of that axis**. So `5.98×` is not *the* occupancy cost of parallel dispatch; it is
the reading at the ambient that run's box happened to hold, and it is the highest of the three
readings taken to date.

This run is also the only one of the three whose **both** arms clear the bench's own
`⚠ AMBIENT MOVED >2x BETWEEN CYCLES` — control span 1.92×, live span 1.82×. §5.1's caveat 1 argues
correctly that a passing control licenses quoting a ratio despite that warning; what it could not know
is that the warning's *subject* moves the estimate, so clearing it is not a formality.

| | §5.1 control | §5.1 live | **this control** | **this live** |
|---|---|---|---|---|
| load1 start → end | 13.93 → 20.91 | 14.00 → 33.90 | 13.27 → 15.94 | 12.64 → 30.24 |
| ambient (idle arm), runnable | 9.875..30.625 | 8.500..23.708 | **8.125..15.625** | **7.125..13.000** |
| ambient span | 3.10× | 2.79× | **1.92×** | **1.82×** |
| `⚠ AMBIENT MOVED >2x` | fired | fired | **silent** | **silent** |
| cycles yielding a ratio | 19 / 20 | 15 / 20 | 19 / 20 | **18 / 20** |
| median per-cycle ratio | 0.96× | 5.98× | 0.92× | **2.90×** |
| sign-test CI | 0.74..1.20 (94%) | 3.45..8.35 (96%) | 0.73..1.42 (94%) | **2.45..5.32 (90%)** |

**The two nulls replicate; only the live magnitude moves.** 0.92× against 0.96×, CIs 0.73..1.42
against 0.74..1.20, on ambient differing by 1.6×. The rig's null is reproducible, so the live gap is
not the rig being unrepeatable — it is the live estimate tracking something the null cannot see,
because a null's two arms share a denominator scale and the live comparison does not.

### Why it moves — the denominator, not the physics

Both explanations predict the same positive ambient→ratio correlation, so it needs a discriminating
arm rather than a plausible story. §3's thesis says cost-per-fork is `O(load)`, so the *real*
queueing penalty should grow with ambient. The competing account is §5.1's own caveat 2, extended:
the estimator divides by **serial's** attributable occupancy, which is the small quantity, so ambient
noise is a large *relative* error on the denominator and a small one on the numerator.

They differ in where the movement shows up. Pooled over both live runs, 33 retained cycles:

```
Spearman(ambient, SERIAL attributable/dispatch)   = -0.566     ← denominator collapses
Spearman(ambient, PARALLEL attributable/dispatch) = +0.273     ← numerator barely moves
Spearman(ambient, ratio)                          = +0.553

tercile          ambient        serialAttrib   parallelAttrib   ratio    serial disp   parallel disp
low           7.12..10.12          0.09529          0.25000     2.67×          243            735
mid          10.33..12.42          0.03098          0.17770     5.32×          243            745
high         12.46..19.29          0.04166          0.29418     6.38×          249            724
```

**The last two columns are the control that settles it: throughput is FLAT across terciles.** Both
arms complete the same work at every ambient level — serial 243/243/249 dispatches, parallel
735/745/724 — so serial's attributable occupancy falling by two thirds is not serial doing less. It is
the per-cycle idle subtraction eating a signal that was only ~0.8–3 runnable threads wide to begin
with. Under the O(load) account the numerator had to carry the rise; it does not.

The same relationship holds *within* each run separately, which removes any cross-run confound:
Spearman(ambient, ratio) = **+0.478** over this run's 18 cycles and **+0.518** over §5.1's 15. Split
each run at its own median ambient: 2.45× / 4.52× here, 3.97× / 6.38× there.

### What this changes, and what it does not

**The sign is untouched and now replicated three times** — 2026-08-09 (2.10..6.43), §5.1
(3.45..8.35) and this run (2.45..5.32) all exclude 1.00, against nulls at 0.92–0.96×. Parallel
dispatch costs strictly more occupancy per dispatch. That was §4.2's claim and it stands.

**The magnitude does change.** The best estimate for a box that is actually quiet is **2.90×
(2.45..5.32)**, and the lowest-ambient tercile across both runs reads **2.67×**. Because the residual
bias runs *upward* with ambient, these remain upper-ish readings rather than a floor. `5.98×` should
not be carried downstream as the occupancy cost; quote the interval and say which ambient it was
taken at.

**And the bench's remaining acceptance statistic is a range.** §2 removed `max/min` from the gate
because the range of a sample is non-decreasing in `n`; the `⚠ AMBIENT MOVED >2x` check is `max/min`
over the idle arm, the same shape, and it is the one an operator must now reason past to quote a
number. The correlation above is the property-of-the-estimate replacement: it asks whether the ratio
is *moving with* ambient, which is the thing that biases it, and it does not inflate merely by
collecting more cycles. **It is now in the bench** (`ambient-sensitivity: Spearman(ambient, ratio)`,
warning at one-sided p < 0.05, with the quiet-half/noisy-half medians so the actionable figure is
printed rather than merely demanded). Both runs above fire it; a fixture whose ambient swings 2.1×
with a flat ratio trips the old range check and leaves the new one silent, which is the whole of the
difference between the two statistics.

### Method notes

1. **Two workers on one box silently overwrite each other's raw results.** §5's commands hardcode
   `/tmp/hdb-control.tsv` and `/tmp/hdb-live.tsv`, and §5.1's run re-wrote both two hours after this
   one, so `--analyse` on those paths returned §5.1's numbers under this run's filename with no
   error and no tell — a plausible, different, wrong verdict for the earlier run. This run's live TSV
   was reconstructed from its own stdout table and re-analysed to byte-identical figures before use;
   it is committed at `docs/research/data/hdb-live-quiet-2026-09-09.tsv` rather than left in `/tmp`.
   This run's control survives only as its printed verdict and its 19 ratios: `-0.75 0.34 0.39 0.51
   0.55 0.73 0.75 0.83 0.88 0.92 1.24 1.28 1.34 1.42 1.52 1.58 1.71 2.29 2.55`.
2. **§6 prediction 2 is confirmed, within a single run.** Re-analysing this run's control over its own
   first 5 cycles gives 88% CI 0.39..2.29 against 94% CI 0.73..1.42 at 20 — narrower at *higher*
   coverage, same box, same ambient, nested subsample. The per-cycle ratios do behave as independent
   draws and the sign-test interval is the right instrument.
3. The floor was never overridden here either: `CC_HDB_MAX_START_LOAD` was never set, and both arms
   were fired by a poller that waited for `load1 < 13.5` against the bench's own 14.

## 6. Falsifiable predictions

1. Run at `--members 1`, the bench must report a CI containing 1.00 whatever the box is doing: with
   one member, parallel and serial dispatch are the same operation. Anything else indicts the rig.
   (Inherited from `active-session-occupancy-2026-08-09.md` §7.3, still unrun.)
2. ~~The control's 90% CI at 20 cycles must be **narrower** than at 5 on the same box.~~ **CONFIRMED
   2026-09-09, and on the strongest available design — the same box, the same run, nested
   prefixes of one control TSV rather than two runs on different days.** Re-analysing the first
   5, 10 and 20 cycles of §5.1's control gives CI widths **2.39 → 1.14 → 0.46**, monotone
   decreasing, while the statistic the old gate used moved the other way over the identical
   draws: the sample range went **−1.19..1.20 → −1.19..162.28**, a 135× widening. One dataset,
   two dispersion statistics, opposite signs of the derivative in evidence. The per-cycle ratios
   behave as independent draws and the sign-test interval is the right instrument.
   Reproduce: `awk -F'\t' '$1<=5' hdb-control.tsv > c5.tsv && scripts/hook-dispatch-bench.sh --control --analyse c5.tsv`
3. The repaired drift guard must go **red** the next time a Bash hook is added to settings.json
   without a registry edit. A guard that stays green through such a change has regressed to §3.

## 7. Method note

Both defects here are the same shape, and it is worth naming once: **an acceptance criterion that
cannot see its own subject.** The bench's gate was computed from a statistic that moved the wrong way
with evidence; the drift guard's expectation was computed from a constant inside the checker. Each
produced clean, plausible output for weeks. Wave A's house rule holds again without amendment — *an
instrument that returns a clean figure is not thereby a working instrument* — and the corollary this
adds is that the criterion deserves the same suspicion as the measurement: **check that more evidence
makes your gate easier to pass, not harder.**
