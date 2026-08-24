# Deriving `CC_HW_DEFAULT_MAX_LOAD_PER_CORE` — the axis admits no capacity constant, and the blocking measurement is discharged

**Date:** 2026-08-24 · **Box under study:** MacBookPro18,2 (M1 Max), `hw.ncpu`=10, 64 GiB, macOS 15.6
**Item:** backlog `e981656df348` — *"`CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0` was never derived from a
measured failure (`capacity-admit.sh:134` cites a section that falsifies itself) — derive it, do NOT
blind-raise; blocked on the marginal-load measurement."*
**DoD ref:** [`gc-cpu-vs-session-ceiling-2026-08-18.md`](gc-cpu-vs-session-ceiling-2026-08-18.md) §3, §5
**Method:** derivation from measurements already landed on trunk. **No new measurement was taken** —
the derivation's first result is that the measurement the item was blocked on *has already been made
in substance*, and that the specific two-arm experiment §5 asked for cannot be run at all. Labels:
**[M]** measured (by the cited landed instrument) · **[I]** inferred/arithmetic · **[Q]** quoted.

---

## 1 · Verdict

1. **The blocking measurement is DISCHARGED.** Marginal load from one additional session is
   **≈1.2% of the box's runnable population when that session is working (≈0.2 load units at the
   20.0 ceiling), ≈0.2% when it is resident at a prompt (≈0.04)** — from A8's per-root census, which
   cleared both a positive and a negative control, cross-checked against B3's independent
   thread-level attribution. §3.
2. **The two-arm experiment §5 prescribed CANNOT be run**, and that is a result, not a scheduling
   problem: the effect is **0.6% of the noise** in the quantity it would be read from, needing
   **~10³–10⁴ paired fires** to resolve. §3.3. A8 hit this live — its probe ran while the box's load
   *fell* 28.96 → 26.75 [M].
3. **No value of the constant is derivable as a capacity threshold — two independent proofs.**
   Rule R1 (set it at the measured failure) requires `T ≤ 2.53` and `T > 5.98` simultaneously: the
   survived population *contains and exceeds* the only fatal reading. §4.1. Rule R2 (set it from a
   capacity model) requires a stable ambient term; ambient moved **8.35 → 46.39 in one day** [M] and
   is **87.3%** of the numerator. §4.2. Both yield the empty set. These are proofs about the axis,
   not shortages of data — more sampling cannot change either.
4. **The only admissible rule is R3 — a runaway circuit-breaker set above the whole survived
   population — and its derived value is `8.0`/core**, which is not a new number: it is the value
   this repo already derived from *this same population* for its sibling gate on 2026-08-08
   (`CC_GATE_MAX_LOAD_PER_CORE`, `.claude/commands/ship.md:118`). §4.3.
5. **`2.0` is no longer "the constant that stops us" — that ended on 2026-08-21.** Task #170 switched
   the fire path's load **term** off by default, and the Agent-tool path has been off since Wave D.
   The constant now binds on exactly **two unattended recovery callers**, which is the one place the
   file's own header says a refusal is most expensive. §5.
6. **Nothing here licenses moving the number, and this commit does not.** The delivered change is
   the derivation plus the correction of a code comment that cites a section which refutes it. The
   term/ceiling decision §6 sequences is a live-box behaviour change on the universal spawn
   chokepoint and is filed, not fired.

---

## 2 · What the constant's own citation claims, and what that section says

`scripts/lib/capacity-admit.sh:132-134`, verbatim as it stood before this commit:

> ```
> # (tests/capacity-admit-coverage.bats case 26 is the ratchet). 2.0/core is §9.5's measured ceiling;
> # 4 GB is M10's reclaimable floor.
> CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0
> ```

`MACHINE_CAPACITY_V2.md` §9.5 (`:741-762`) is titled **"SELF-CORRECTION — my 'permanent dispatch
outage' projection is FALSIFIED"**. It contains no derivation of any ceiling. What it contains is a
retraction whose evidence is *two observations of the gate thresholding*: it refuses over a window at
2.92–5.98/core and admits at 1.55/core, and the section concludes only *"a ceiling that refuses at
4.0/core and admits at 1.55/core is behaving as a ceiling, not as an outage."* That is a demonstration
that a threshold thresholds. **The cited section is also the source of the survived population that
§4.1 uses to prove no threshold on this axis can work** — so the citation does not merely fail to
support the constant, it points at the evidence against it.

The actual origin is commit `0fc3a3d33` (2026-07-29, *"feat(handoff-fire): machine-capacity admission
gate at the spawn chokepoint"*). Its body measures the motivating lag incident — *"1-min load 27
(2.72/core), 8% idle"* — and then states the constant with **no rule connecting the two**:

> - refuses a NET-NEW fire above CC_FIRE_MAX_LOAD_PER_CORE (default 2.0) with a distinct exit 9

`2.0` sits **below** the incident it was chosen from (2.72) and below every reading in §4.1's survived
column. No failure was ever observed at it.

---

## 3 · The blocked measurement — marginal load per session

### 3.1 What §5 asked for, and why the instrument it named cannot answer

> **[Q]** *"The one next measurement: marginal Δload from adding exactly one active session at a
> held-constant baseline, N≥5 at different baselines"* — `gc-cpu-vs-session-ceiling-2026-08-18.md` §5.

That is a **whole-box Δload** design. It was attempted on 2026-08-19 and failed in the direction that
matters: **A8 §1.5 [M]** — *"Whole-box Δload CANNOT resolve one unit — during my probe the box load
**fell** (28.96 → 26.75)."* The DoD's own §2 table records the reason: load at a **constant** N=15–16
read **11.21 / 19.06 / 27.26 / 29.67 / 32.14 / 36.07** — a ±8 swing that already exceeds the entire
session-attributable term. B3's four censuses widen it: **8.35 → 46.39 on one day** [M].

### 3.2 The instrument that does resolve it, and its controls

Per-root attribution, not whole-box differencing: sample `ps` state at 2 Hz, walk each process to its
owning session root, count runnable. A8 §3b, 51 samples over 30 s.

**Positive control:** the busy probe reads **1.30** — it can read >1.
**Negative control:** the blocked launcher wrapper reads **0.000 over 608 samples** — it can read 0.
**Level control (B3 §2b, the independent re-run):** load ÷ census across three windows spanning a 2.7×
load range = **1.235 / 1.077 / 0.913**, best agreement at the high load that matters. **PASSES.**
*(B3's dynamics control FAILS/UNDECIDED — each window is ~2.5 independent observations against a 60 s
time constant. Read everything below as a LEVEL attribution and never as a predictor of load's motion.)*

### 3.3 The number, stated so it does not depend on a disputed conversion

A8 published its per-unit figures in load units via a **×1.553** R-procs→load factor. B3 called that
factor unreproduced (it measured 0.913–1.235). **Both can be right and the dispute is a denominator
mismatch, not an error:** A8 counted runnable *processes* (`ps -axo stat=`), B3 counted runnable
*threads* (`ps -axM`), and threads ≥ procs, so load÷threads < load÷procs by construction. Rather than
pick a side, take the **share**, which is conversion-free — a proportion of whatever load the box is
carrying at the moment of the decision:

| unit | R-procs/sample | **share of the 18.654 box-wide runnable procs** | **load units at the 20.0 ceiling** |
|---|---:|---:|---:|
| interactive session, working | 0.216 | **1.16%** | **0.23** |
| interactive session, fleet-average (idle at prompt) | 0.041 | **0.22%** | **0.044** |
| in-process subagent, actively tool-calling | 0.315 | 1.69% | 0.34 |
| pane team agent, API-blocked | 0.020 | 0.11% | 0.021 |
| headless `-p`, 100% mid-turn | 0.974–1.300 | 5.2–7.0% | 1.04–1.39 |

*(A8 §3b, mean load 28.96 over the run. **[M]** for the shares; **[I]** for the load-unit column,
which is the share applied to the ceiling.)*

**Independent corroboration, different instrument, different denominator:** B3's thread-level census
attributes **12.7%** of the numerator to class C (all Claude sessions + agents + the tools they spawn)
across ~14 units ⇒ **~0.9% per unit** [M]. Same order as the 1.16%/0.22% pair. Two instruments that
disagree about the conversion factor agree about the share.

**This is the number that was blocked**, and it also adjudicates the DoD's own spread of four
candidates spanning 30× (`0.172` pooled OLS · `0.566` bucket median · `1.89` delta-marginal ·
`2.5–5` published): **0.2 corroborates the pooled OLS and refutes the last two.** The `1.89` was a
whole-box delta of exactly the kind §3.1 shows cannot resolve one unit; the `2.5–5` is the aggregate÷N
the DoD had already flagged as `[Ratio ≠ marginal]`.

**Why the prescribed two-arm design is not merely hard but infeasible [I].** Effect 0.23; per-arm SD
of the baseline is at best the ±8 the DoD measured at constant N, and 15 across B3's day. Paired arms
at SD=8 need `n ≈ 2·(1.96·8/0.23)² ≈ 9,300`; even at a charitable SD=3, `n ≈ 1,300`. **The decision
variable is ~0.6% of the noise in the quantity being thresholded.** No feasible number of fires
recovers it, which is the same fact §4.2 states from the other side.

---

## 4 · The derivation: three candidate rules, and what each yields

### 4.1 R1 — "set the threshold at the measured failure point" ⇒ **empty set**

| outcome | load1/core | n | source |
|---|---:|---:|---|
| **FATAL** — kernel panic, watchdogd starvation, 2026-08-05 | **2.53** | 1 | `capacity-alarm.sh:141` (25.3 on 10 cores) |
| survived — healthy box, 13 sessions, 24 GB free, 0 B compressor | 2.16 | 1 | `MACHINE_CAPACITY_V2.md:1488` (§12.2, load 21.55) |
| survived — reso, **42 h sustained**, no panic | 2.50 | 1 | `capacity-alarm.sh:144` |
| survived — A8 probe window | 2.68–2.90 | — | A8 §1.5 |
| survived — fire REFUSE while the Agent gate ADMITted | 3.14 | 1 | A5 `:17` |
| survived — refusing real fires, other three terms nowhere near limits | 3.37 | 1 | `handoff-fire.sh:4849-4855` |
| survived — B3 run4 census mean, box working | 3.46 | 1 | B3 §2a |
| survived — active term read 4 of 8 at this load | 3.72 | 1 | B3 §1.4 |
| survived — **13 consecutive samples at a CONSTANT 31–32 sessions** | **2.92–5.98** | 13 | `MACHINE_CAPACITY_V2.md:486` |

Individual values of that 13: `29.15 37.66 44.35 45.96 47.01 49.94 50.43 55.56 56.96 56.04 54.74
56.24 59.80` (÷10 cores) — *"a 2.05× swing while session count changed by at most 1"* [M].

**The separation test.** Catching the fatal requires `T ≤ 2.53`. Not firing on the survived population
requires `T > 5.98`. **The two intervals are disjoint.** No threshold on this axis separates fatal from
survived, and no amount of further sampling can create a separation the population forbids — this is
the repo's own [[threshold-must-separate-fatal-from-survived]] rule, already written down for
`capacity-alarm.sh`'s rung 7 (`MACHINE_CAPACITY_V2.md:1609`, *"explicitly UNCALIBRATED"*) and never
applied to the admission constant that shares the axis.

**Scored at the shipped value, `T = 2.0`:** it fires on 1 of 1 fatal and on **20 of 20** survived
readings ⇒ sensitivity 1.00, **specificity 0.00**, precision **1/21 = 4.8%** [I]. *(Limitation, stated:
these readings are not independent draws from one process — they are the box's recorded history at
differing session counts and differing ambient. That weakens any rate computed from them; it does not
weaken the interval argument, which needs only that the values were observed at all.)*

### 4.2 R2 — "set it from a capacity model, `ceiling = ambient + N × marginal`" ⇒ **no constant exists**

The model needs a stable ambient. **[M]** B3's four censuses, same box, same day: load1 **8.35 →
46.39**. Composition at the definitive census (240 samples, level control passing):

| class | % of numerator |
|---|---:|
| macOS / third-party | 33.6% |
| **our own automation** (hooks · pollers · CLI; `cc-backlog` alone is 17.5% of the box) | **25.9%** |
| **Claude sessions/agents + their tools** | **12.7%** |
| unattributable short-lived forks | 10.9% |
| devserver · terminal · browser · editor | 15.2% |

Solve the model for the shipped ceiling of 20.0 using §3.3's marginal of 0.23:
at the day's low ambient (8.35) it admits **N ≈ 50** working sessions; at the day's high ambient
(46.39) it admits **N = 0**, no matter how idle the fleet is. **One constant expressing both "50" and
"0" on the same box on the same day is not a capacity model** — it is a reading of the 87.3% of the
numerator that is not the subject of the decision. This is exactly §12.2's live proof
(`MACHINE_CAPACITY_V2.md:1488`): 2.16/core with 24 GB free and 0 B compressor, a healthy box, refused.

R2 does not yield *no answer* — it yields an answer of the wrong **type**: headroom relative to a
measured ambient, which a single scalar literal cannot express.

### 4.3 R3 — "a runaway circuit-breaker, set above the whole survived population" ⇒ **8.0/core**

The one role the axis can still play is the one it plays for the sibling gate. On 2026-08-08 the land
gate's ceiling was re-derived from **this same population** (`.claude/commands/ship.md:118`, verbatim):

> **The default ceiling is DERIVED from the box** — `hw.ncpu × CC_GATE_MAX_LOAD_PER_CORE` (factor 8,
> so 80 on a 10-core Mac) … a box whose own capacity work (`MACHINE_CAPACITY_V2` §8.5.7) measured it
> *surviving* 2.92–5.98/core in ordinary operation. Measured effect: **352 of 405 lands that reached
> the check were shed (87%)** … what remains is a **runaway circuit-breaker, not a capacity model**.

**Rule:** the breaker fires only where the box has never been observed to work. Max survived = 5.98;
the shipped sibling value is **8.0**, a 34% margin. **So the derived value for
`CC_HW_DEFAULT_MAX_LOAD_PER_CORE` under the only admissible rule is `8.0`/core — the repo's own
already-landed breaker constant, four times the current literal.** Two gates on one box currently
differ by 4× on the same axis for no derived reason.

🚨 **This is not the forbidden move.** `LOAD_INSENSITIVE_VERIFY_V2.md:156` kills *"raise
`CC_FIRE_MAX_LOAD_PER_CORE` until tests pass"* — a fix that keeps a term whose input is wrong and
moves the number it is compared against, buying a window that re-breaks at the next occupancy. The
distinction is the **role**: R3 does not retain the capacity function at a looser setting, it
*surrenders* the capacity function (to the terms in §6) and keeps only the breaker. A breaker whose
value is derived from the survived population re-breaks at nothing, because there is nothing above it
the box has been seen to survive.

**And the capacity function has somewhere derived to go.** The `active` term separates where load does
not: **[M]** B3 §1.4 — at load **37.17** (186% of ceiling ⇒ REFUSE) the live `cc_sp_active` read
**4 of a ceiling of 8** ⇒ ADMIT. So did `segments`: **[M]** on the quiet box the headroom term read
40.55 GB (ADMIT) against segments 0.00%; **at the panic** headroom read 29.79 GB — still ADMIT —
against segments at **100%** (`capacity-admit.sh` header). The compressor term is the only rung in the
tree that has been observed to take different values on a survived box and a dying one.

---

## 5 · Where `2.0` still binds — the live-state audit

The item was filed against a state that has since changed, and the change is most of the harm.

| path | load term | ceiling in force |
|---|---|---|
| `handoff-fire.sh` `capacity_gate()` — every fire | **off** since 2026-08-21 (`:4879`, task #170) | not evaluated |
| Agent tool — `hooks/agent-teams-enforce.sh:229` | **off** since Wave D (`CC_ADMIT_LOAD_TERM=off`) | not evaluated |
| **`scripts/boot-resume-launch.sh:266`** | **ON** — no override, library default `:-on` | **2.0/core** |
| **`scripts/limit-recover/lr-fire-resume.sh:318`** | **ON** — no override, library default `:-on` | **2.0/core** |

Task #170's own reasoning, at `handoff-fire.sh:4849-4859` [M], is the mechanism-side counterpart of
§3.3: *"Measured while it was refusing real fires at 3.37/core against the 2.00 ceiling: the other
three terms were nowhere near their limits — reclaimable headroom 21.64 GB against a 4 GB floor,
compressor segments 6.99% against a 50% ceiling, 5 sessions mid-turn against a ceiling of 8 … Every
live `claude` process sat in S/Ss; load1 counts only runnable and uninterruptible, so a RESIDENT
session contributes ~0 to the number this term reads."* It also states the claim precisely, and this
doc keeps that precision: **our tooling is ~2/3 of the numerator; what is ~0 is one ADDITIONAL
resident session** — the only question a spawn gate asks.

**The residual has a specific cost and a specific irony.** The two callers still evaluating the
underived constant are the *unattended recovery* paths — the boot storm (**[M]** loadavg 346 at
boot+2 min) and limit-recovery — which are precisely the callers `capacity-admit.sh`'s own header says
must never stand on a refusal. They are budget-bounded (`CC_ADMIT_BUDGET=3`), so the outcome is 3
refusals and a page per boot rather than an outage: **delay plus a page, from a term measured to be
100% false-positive against the survived population.** They also now disagree by construction with the
other two paths — the exact defect #170's comment claims to have closed (*"After this they agree by
construction rather than by coincidence"*), which is true of the pair it aligned and not of these two.

---

## 6 · What follows, sequenced — and what this commit does and does not do

**Done here (no behaviour change, no number moved):** this derivation, and the correction of
`capacity-admit.sh:132`'s citation so the constant no longer claims a provenance the cited section
refutes.

**Filed, not fired — one decision, two admissible answers, and they are mutually exclusive:**

- **(a) Finish #170's demotion.** Pass `CC_ADMIT_LOAD_TERM=off` at `boot-resume-launch.sh:266` and
  `lr-fire-resume.sh:318`, aligning all four spawn paths. The constant then reaches nothing by
  default and its value stops mattering. *Cheapest, and consistent with §4.1's proof that the term
  cannot inform an admission decision.*
- **(b) Keep the term on those two paths as a breaker and set the shared default to the derived
  `8.0`.** Uses §4.3's rule; makes the two gates agree with the land gate instead of differing 4×.
  *Costs: one literal change that `tests/capacity-admit-coverage.bats` case 26 ratchets, and it is a
  default on the universal spawn chokepoint.*

**Do not do both** — (b) after (a) sets a breaker on a term nothing evaluates, which is the
`spec-named-mechanism-may-be-prose-only` shape. Either way the **capacity** function belongs to
`active` + `segments` (§4.3), which are built and shipped but not wired on the fire path — B3 §1.4's
recommendation, still open.

**Why this commit stops here rather than firing (a) or (b).** Both are gate-default changes on the
spawn chokepoint whose failure mode is box-wide, and the deriving session ran in a Linux container
with no `vm_stat`, no `hw.ncpu`, no `bats` — it could not execute one case of
`tests/capacity-admit.bats`, `capacity-admit-active.bats`, `capacity-admit-coverage.bats` or
`handoff-fire-capacity-gate.bats`, all of which stub Darwin probes. A derived number is not a licence
to land an unrunnable change; C18 (`memory-econ-rearchitecture-2026-08-10/prior-art.md:245`) binds
even when the default move is the deliberate subject rather than a side effect.

---

## 7 · What this derivation does NOT establish

- **Nothing about the 4 GB headroom floor.** `CC_HW_DEFAULT_MIN_HEADROOM_GB` shares the line and the
  ratchet but not this analysis. Its own status is already recorded next door: **0 firings in 127
  refusals**, and it read ADMIT at 29.79 GB *at the panic*. It needs the same treatment.
- **Nothing about the fatal population's size.** Four panics are on record (07-30, 07-31 ×2, 08-05);
  only 08-05 carries a load reading, because the sampler emitted no CPU term until later. R1's fatal
  column is `n=1` and cannot be widened retroactively. This weakens R1's *sensitivity* estimate — it
  does not weaken §4.1, whose argument runs entirely through the survived column.
- **Nothing about `capacity-alarm.sh`'s 1.5/2.5 rungs.** They are an ALARM, never a gate; a false
  alarm costs one page on a transition. They already carry this doc's §4.1 argument in their own
  header and their false-positive population is executable in the selftest. Unchanged, deliberately.
- **No new live measurement of any kind.** Every number above is quoted from a landed instrument with
  its controls named. The one thing §5 asked for that is still genuinely open is B3's, not this
  item's: whether wiring `active` + `segments` onto the fire path changes the admit/refuse ratio.
