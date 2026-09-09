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

The magnitude run remains **unrun**, for a reason recorded in §5 rather than waved at.

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

## 6. Falsifiable predictions

1. Run at `--members 1`, the bench must report a CI containing 1.00 whatever the box is doing: with
   one member, parallel and serial dispatch are the same operation. Anything else indicts the rig.
   (Inherited from `active-session-occupancy-2026-08-09.md` §7.3, still unrun.)
2. The control's 90% CI at 20 cycles must be **narrower** than at 5 on the same box. If it is not, the
   per-cycle ratios are not independent draws and the sign-test interval is the wrong instrument —
   which would be a finding about the bench's cycling, not about the subject.
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
