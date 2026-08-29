# The 2× p99 CPU win is not our concurrency lever — and the constant that actually stops us was never measured

**Date:** 2026-08-18
**Question (operator):** does the Claude Code CLI now using 2× less CPU at p99 drastically affect our
~15 concurrent-session limitation, and are there actionable outcomes?
**Method:** 6-axis wave (version path · gate constants · load mechanism · live 2.1.228-vs-2.1.234 A/B ·
memory adversary · ceiling model), each independently re-run by an adversarial verifier. 4 of 6
verifiers returned; the load-mechanism verifier was aborted at 00:59 and the memory-adversary
verifier never returned. **Every claim below is labelled by whether it survived verification.**
Raw A/B measurements: [`data/gc-cpu-ab-2026-08-18.md`](data/gc-cpu-ab-2026-08-18.md).

**The vendor claim under test** ([@ClaudeDevs](https://x.com/ClaudeDevs), 2026-08-17): "Claude Code CLI
now uses 2× less CPU at p99. Bun's garbage collector was running on a fixed timer, so it would kick in
mid-turn and steal CPU right when Claude Code was busiest. Now it waits until the process is idle."
Chart: CPU **share** p99 24% → 10%, p50 5.8% → 2.5%, across releases v2.1.228 → v2.1.232, step at
**v2.1.229** (Aug 12).

---

## 1 · The verdict

**No — and it fails on two independent legs, either of which alone is sufficient.**

**Leg 1 — claude.exe is ~4.7% of the quantity our gate measures.** The gate that refuses new sessions
(`CC_FIRE_MAX_LOAD_PER_CORE`) keys on **load average**, and Darwin's load average counts *runnable
threads*, never CPU time. A per-thread census attributing the load numerator by process found all live
claude.exe processes together contribute **1.075 of 22.95 runnable threads (4.7%)**. This is the single
most important number in the wave, and it is the one that **replicated under an independently written
parser** (finder measured 0.950/19.27 = 4.9%; verifier measured 1.075/22.95 = 4.7%). Deleting *100% of
Claude's runnable threads* removes ~5% of the load average. The vendor's win is a fraction of that
fraction.

**Put in the gate's own units, this is the number to remember:** the GC-attributable change is
**0.019 runnable threads across the entire 14-session fleet** — measured by summing the
`BUN_JSC_logGC` stop-the-world pause fields (105.1 → 65.0 ms per 30 s = 0.134% of one core per
session). Against a load of 19 and a ceiling of 20, that is **~0.1% of the gap**.

**Leg 2 — the measured CPU win is real but is NOT the GC fix.** An interleaved n=32/cell A/B of
2.1.228 vs 2.1.234 measured **−8.9% CPU (t≈10)** — reproducible, and not the advertised 2× (the
vendor's 24%→10% is a p99 across *their whole fleet*, a different statistic from our workload). But the
finder attributed the whole delta to one named change across a **six-release span**. The verifier ran
the GC-isolating arm the finder never ran, on the post-fix binary where the knob is provably live
(`BUN_GC_TIMER_INTERVAL=1` → **+13.5%** CPU, t≈5):

> `BUN_GC_TIMER_DISABLE=1` on 2.1.234 changes CPU by **+0.6%** — a null (0.5300 → 0.5334 s, sems
> 0.0027 / 0.0029).

**Turning garbage collection off entirely, on the fixed binary, buys nothing.** So the −8.9% belongs to
the other 33 releases' worth of changes in the band, not to the GC scheduler. The one claim that would
have made this a capacity story does not survive its own control.

---

## 2 · The numbers that survived adversarial verification

| Finding | Number | Status |
|---|---|---|
| claude.exe share of the load-average numerator | **4.7%** (verifier) / 4.9% (finder) | ✅ replicated, independent parser |
| Measured CPU delta 2.1.228 → 2.1.234 | **−8.9%**, t≈10, n=32/cell interleaved | ✅ reproduced |
| CPU delta attributable to the **GC fix** | **+0.6% — a null** | ✅ GC-isolating arm, knob proven live |
| Whole claude fleet's CPU demand | **0.36–0.68 cores** across loads of 25 / 33 / 55; no single proc >21.4% of a core | ✅ reproduced over a 2× wider load range |
| Bun-GC fix in the public CHANGELOG | **absent** — 5588 lines, 3 "garbage" hits, all unrelated; attribution is tweet-only | ✅ independent fetch |
| `cc-upgrade-gate` coverage of this question | **zero** — all 14 checks, none measures CPU, threads or load | ✅ |
| Sessions running the MANIFEST-gated launcher | **0 of 13** (argv[0] census; all on `.claude-220`) | ✅ |
| `gate-off` share of gated fires | **242 gate-off vs 271 measured (~47%)** | ✅ reproduced exactly |
| Hard 15-session wall | **does not exist** — 52 resident in 24 h, headroom p10 22 GB, swap 0.00 | ✅ |
| Peak physical footprint, 228 vs 234 | 1370 vs 1374 MB, t=0.11 | ❌ **the "no memory harm" reading is refuted** — see below |
| Heap at collection, 220 → 234 | **+5.8 MB mean / +9.7 MB peak** | ✅ small harm *measured*, not absent |
| Idle stop-the-world eden collections | 2.1.220 **69/62/62** per 30 s → 2.1.234 **30/30/30** | ✅ |
| 2.1.220 is pre-fix | **by DATE**: 220 published 2026-07-24T23:11Z; the Bun fix commit `68ec9e5d0800` is authored 2026-07-30 | ✅ (the strings evidence was refuted; the date is not) |
| Historic refusals below 3.0/core | **25 of 49 (51%)**, p50 exactly 3.00 | ✅ re-derived |
| Load at CONSTANT session count (N=15–16) | **11.21 / 19.06 / 27.26 / 29.67 / 32.14 / 36.07** | ✅ — a ±8 swing exceeding the entire session-attributable term |

### What the verification killed

Recording these explicitly, because a refuted claim that quietly vanishes is how a wave launders its
own errors:

- **"claude.exe lacks the GC-timer env knobs, proving we lack the fix."** REFUTED — an anchored-grep
  artifact. `grep -c '^BUN_GC_TIMER_DISABLE$'` only matches a NUL-delimited string; in 2.1.220 and
  2.1.228 the name sits inside a run-together blob. A raw `LC_ALL=C grep -a` byte search finds it in
  **all three** binaries. *(This is the repo's own indexed `C locale` / greedy-anchor lesson, live again.)*
- **"64% of the runnable population is our own launchd automation."** REFUTED as a number — the census
  failed a correlation control it never ran: `corr(load, R-procs) = −0.05`, flat at 19–20 R procs across
  a 2.3× load range. The *direction* (the fork storm, not Claude, owns the load) survives on the
  thread-level census; the 64% figure does not.
- **"The gate is a hard cliff at 2.0/core."** REFUTED at the mechanism — `handoff-fire.sh:4300`
  defaults `CC_FIRE_ADMIT_BUDGET` to **1**, so after *one* consecutive refusal the next fire is
  ADMITTED into the saturated box (`basis: budget-expired`). It is a one-refusal speed bump.
- **"The gate is refusing right now."** REFUTED — simulated from a `sysctl` read, never observed. The
  last real refusal was 2026-08-17T07:19Z, and 36 of 47 refusals fall on just two days. Refusals are a
  burst, not a standing condition.
- **"2.5–5 runnable threads per active session."** PARTIALLY REFUTED — an aggregate÷N, not a marginal.
  The cited measurement is load1 27.4 → 44.4 across nine all-active sessions; the true marginal is
  **(44.4−27.4)/9 = 1.89**, not 2.5–5. *(The repo's own `[Ratio ≠ marginal]` defect.)*
- **"The fix buys +0.2 sessions" / "collapsing cc-dispatch frees 4.0 load points."** Both REFUTED as
  arithmetic on a `0.434 load/session` coefficient that is an unidentifiable one-point fit — its
  "fixed load" of 12.33 was chosen as the residual at N=16, so matching the observation is guaranteed
  by construction rather than predicted.
- **"The theory of memory harm is refuted."** ITSELF REFUTED — the adversary axis's own retained logs
  show heap-at-collection **+5.8 MB mean / +9.7 MB peak** on 234. Small harm *measured*, not absent.
  The peak-footprint null (t=0.11) was a startup benchmark and does not carry the claim.
- **"Set `CLAUDE_CODE_FORK_SUBAGENT=0` before the first fan-out."** REFUTED and inverted — see §4.
- **"The gate is a wall you hit at 15."** REFUTED at the mechanism a second way: `CC_FIRE_ADMIT_BUDGET`
  defaults to 1, so a refusal costs a *retrying* caller one round-trip and then admits. Whether our
  automated fires retry is unverified — and that, not the ceiling, decides what raising it buys.
- **"The A/B ingested 8.8 MB and peaked at 1.37 GB in one turn."** REFUTED — the harness output file is
  35 bytes: `Not logged in · Please run /login`. Both cells are ~0.5–1.0 s **startup** benchmarks. No
  mid-turn measurement exists on either binary, which is exactly the phase the vendor's claim is about.

---

## 3 · The actionable finding, and it has nothing to do with the vendor

**The constant that stops us was never derived from anything.**

`CC_HW_DEFAULT_MAX_LOAD_PER_CORE = 2.0` (`scripts/lib/capacity-admit.sh`, the `CC_HW_DEFAULT_*` literal
block — cite it by symbol, not by line: it was `:134` when this was written and is `:161` today) is the
number that becomes the load-20 ceiling on this 10-core box, and both gates expand it. Its own code
comment cited "§9.5's measured ceiling" — and **§9.5 contains no such derivation**; it shows only that
the gate admits at 1.55 and refuses at 2.92, which is a demonstration that a threshold thresholds. The
origin commit `0fc3a3d33` measured the motivating incident at **2.72/core** and picked 2.0 with no
stated rule. The verifier read the full commit body and **confirmed this verbatim** — it called it the
strongest finding in the wave.

✅ **The falsified citation is DISCHARGED on trunk** (2026-08-25, `docs(capacity-admit): the ceiling
cites a section that has no derivation, and the term it parameterises already defaults off` — cite by
subject, a land rebases). That header now states the falsification itself rather than the citation:
it records that 2.0/core was never derived, that the origin incident sat at 2.72/core *above* the
shipped ceiling, and that no derivation is reachable on this axis. Nothing in this paragraph is
outstanding work; it is kept as the diagnosis the fix discharged.

Worse, the repo's own instrument already documents that this axis cannot do the job
(`scripts/capacity-alarm.sh:139-147`, verbatim):

> **THE SURVIVED POPULATION CONTAINS THE FATAL VALUE.** Fatal 2026-08-05: 25.3 on 10 cores = 2.53/core.
> Survived: 13 consecutive samples at a CONSTANT 31–32 sessions spanning 29.15–59.80, i.e.
> **2.92–5.98/core — every one of them ABOVE the fatal reading, all 13 on a box that lived.**

So the threshold sits *below* every load this machine has demonstrably survived, and above the one
that killed it — an axis that provably cannot separate fatal from survived. And the fleet already
behaves accordingly: **47% of gated fires run with the gate switched off.**

**This does not license raising it.** The verifier refuted the projection that 3.0/core buys 20–22
sessions — it rests on a load ∝ sessions proportionality the data contradicts (at load 23.49 the top
consumers were `bun` 65%, `mediaanalysisd` 33%, `kernel_task` 25%, with the highest claude.exe at
**5.5%** and 52% idle). Corroborated live while writing this: **load 10.66 at 13 sessions**, against
19.06 at 14 sessions twelve hours earlier — the same session count spanning a 1.8× load range.

### 🚨 …and it does not license DERIVING it either — this paragraph refuted itself, and 19 attempts to say so never landed (2026-08-29)

This section used to close: *"The honest actionable is therefore **to derive the number, not to move
it**: re-run the axis-09-style measurement (load1 delta across N all-active sessions) and **set the
ceiling from a measured failure point**."*

**That prescription is disproved by the evidence quoted ten lines above it, in this same section.**
The block quote establishes that the survived population CONTAINS the fatal value — fatal at
2.53/core against 13 consecutive survived samples spanning 2.92–5.98/core — and the very next
sentence draws the correct conclusion: *"an axis that provably cannot separate fatal from survived."*
A quantity that cannot separate fatal from survived **has no measured failure point to set a ceiling
from**. The instrument says so in its own words (`scripts/capacity-alarm.sh`, rung-7 header):
*"load-per-core does not separate fatal from survived, and **no setting of these two numbers can make
it**"* — and that population is *executable*, pinned in the selftest with 5.98/core as a known false
ALARM, so this is a control a re-derivation has to argue with rather than a paragraph.

A second, independent refutation landed after this doc was written. `fix(fire-gate): load1 does not
move with the spawn it was gating` (2026-08-20) established that an additional **resident** session
moves the 1-minute runnable count by ~0. So the defect is not the *value* of the literal — **the
INPUT is wrong**, and no value of it can make the term correct. Both legs point the same way: there
is nothing to derive on this axis, and a two-arm experiment would return a number that means nothing.

**What the repo did instead, and it is already on trunk.** The load term is a **switch, never a
ceiling** (C18): it `DEFAULT`s OFF in `capacity_gate()` (`CC_FIRE_LOAD_TERM`) and has been off on the
Agent-tool path since Wave D. `segments` and `active` carry its intent, because they *do* move with
the spawn. The literal stays at 2.0 deliberately — raising it is the lazy design
`docs/plans/LOAD_INSENSITIVE_VERIFY_V2.md:156` exists to reject — and it now binds only where
`cc_capacity_admit` leaves the term on: the two unattended recovery callers
(`scripts/boot-resume-launch.sh`, `scripts/limit-recover/lr-fire-resume.sh`), which price that
imprecision at a delayed resume and are budget-released after `CC_ADMIT_BUDGET` consecutive refusals.

**Why this paragraph was expensive.** It is the DoD ref for backlog `e981656df348`
(*"…was never derived from a measured failure — derive it, do NOT blind-raise; blocked on the
marginal-load measurement"*), so every dispatch of that item read a prescription this section had
already disproved and dutifully went looking for the unreachable derivation. **The stated blocker is
also a misattribution:** the marginal-load measurement (backlog `193ae8ddce72`,
`marginal-load-per-active-session-2026-08-19.md` §6) denominates `CC_ADMIT_ACTIVE_CEILING` — a
per-**ACTIVE-session** coefficient — not this per-**core** load literal; and that doc's §6a says even
the active ceiling is *"not blocked on §6"*, since it stands on the 127/127 refusal band. So this
item was never gated on that measurement, and running it would not have discharged this item.

**And the recurrence was not one defect but two, multiplying.** Measured here across every ref:
**41 commits touch this file, and exactly 19 of them are prior attempts to strike this very
prescription** — `8f4469c3` (08-19) *"the constant is underivable on this axis, not merely
underived"*, `a2959d56` (08-24), `64a308c7`/`695bef1e` (08-25, a duplicate pair), `74448046`,
`b4927874`, `90b004d1`, `10e3ab7d`, `b92eb06b`, `e66dd4f0` (08-26, whose own subject reads *"that
unsatisfiable row is why it cycled five times"*), `60aa4a2b`, `ec5d8504`, `994437db` (08-27),
`a8af4f34`, `02f5ecc9`, `655f23e1`, `38d559a7` (08-28), `1eac82dd`, `d2336b0c` (08-29). **Zero of
the 19 reached trunk** — the prescription was still live in `origin/main` when this session read it,
which is the content proof. Ten days, nineteen correct diagnoses, no cure, because *diagnosis was
never the bottleneck.* Landing was.

**The landing half has a named cause, and it is provisionable.** A cloud VM cannot run `/ship` until
`shellcheck` and `bats` are installed: `scripts/bats-shellcheck-lint.sh` exits 2 (non-verdict) ⇒
`GATE_KILLED` ⇒ `ship-land.sh` exit 9, on a *docs-only* land, because its entry condition is a
property of the repo rather than the diff (`cloud-land-arm-step-2026-08-25.md` §8.1). This session
hit both locks, ran `apt-get install -y shellcheck bats`, and both selftests went green (19/19 and
44/44). Every dispatch of this item before it was a cloud dispatch of a doc fix into a venue that
could not land a doc fix.

**The rule this leaves behind:** a section that quotes a disproof and then prescribes the disproved
remedy will regenerate work forever, because each dispatch re-reads the prescription and not the
quote. When evidence kills a remedy, **strike the remedy in the same edit** — a doc is a store, and a
stale prescription in a store is an instruction. And the corollary this file paid nineteen times for:
**a fix that does not land does not exist.** Re-deriving a diagnosis that is already correct on
nineteen branches is not diligence; check whether the cure is stranded before writing a twentieth.

## 4 · If 2.1.234 is adopted, adopt it on other grounds — and set one env var first

The upgrade is defensible for 33 releases of unrelated fixes, never for capacity. Two items gate it:

1. **`2.1.232` turns subagent forking ON BY DEFAULT** — a fork subagent "inherits the full conversation
   and prompt cache", so it starts at parent-sized heap instead of climbing the log curve. Against this
   repo's own census (`SUBAGENT foot ≈ −206 + 65.4·ln(age_s)`, r²=0.967, ~212 MB at 600 s; MAIN
   plateaus ~450 MB) that would be ~+240 MB per concurrent subagent, ~2.9 GB at our default N=12
   fan-out, on a box whose established failure mode is compressor-page exhaustion.
   ❌ **But the +240 MB was never measured, and the proposed mitigation is worse than the risk.**
   🚨 **Do NOT set `CLAUDE_CODE_FORK_SUBAGENT=0`.** The real 2.1.234 binary tests it with *strict*
   boolean comparison against a parsed env object — `if(V.CLAUDE_CODE_FORK_SUBAGENT===!0) return
   "env"` / `===!1 return "disabled"`. Whether the string `"0"` coerces to `false` there is
   unverified; if it does not, the setting **enables fork-by-default across every launcher** — the
   exact inverse of the intent. This was a top-ranked recommendation from one axis and it did not
   survive verification. The correct action is *no action* until the coercion is read out of the
   binary.
2. **The version pin is 7–8 sites, not one.** SSOT is `~/.zshrc:496`; copies at `accounts.json:14`,
   `hooks/model-permission-decider.py:93`, `scripts/lib/cloud-create.sh:116`,
   `scripts/capacity-ramp.sh:51`, `scripts/mcp-modal-probe.py:28`, `scripts/mcp-modal-e2e-probe.py:12`,
   `bin/cc-offload:87`. A flip that edits only `~/.zshrc` leaves the rest pointing at a directory that
   still exists and still works — silent drift. Also: `docs/activation/pending-activation/28-cc-220-advance-activate.sh`
   is hardcoded `FROM_DIR="claude-219"` / `TO_DIR="claude-220"` with no env override, and its backup
   namespace `zshrc.cc220-*` would collide with a copied 234 script's `--undo`.

The soak rule is satisfiable without a waiver: every version ≥ 2.1.229 carries the fix, and **2.1.234
qualifies on ~2026-08-24** under this repo's own 2.1.220 precedent if no successor ships.

## 5 · Still unmeasured

- **The mid-turn regime.** Every A/B cell auth-failed in <1 s, so no measurement of an *active,
  model-driven turn* exists on either binary — precisely the phase the vendor's claim is about. The
  GC-isolating null (+0.6%) is measured at startup/idle, so it bounds the idle regime, not the busy one.
- **Whether the daemon population scales with session count** — decides whether the gate is merely
  mis-keyed or actively self-defeating. One `cc-dispatch`-instance-count vs session-count regression away.
- **`kernel_task`'s runnable contribution** — absent from `ps -axM` entirely (~720 kernel threads
  invisible against `top`'s 5593).

- **Marginal load per ACTIVE session — the denominator of every capacity claim in this repo.** This
  wave produced **four values spanning 30×**: `0.172` (pooled OLS), `0.566` (in-band bucket median),
  `1.89` (delta-marginal from the cited axis-09 pair), `2.5–5` (published, an aggregate÷N).
  `CC_ADMIT_ACTIVE_CEILING=8`, the felt ~15 wall, `MACHINE_CAPACITY_V2`'s whole model and every
  "+N sessions" figure above all divide by it.
  **Adjudicated 2026-08-19** (`marginal-load-per-active-session-2026-08-19.md`, backlog
  `193ae8ddce72`): none of the four is repairable — three are arithmetically disqualified and
  `0.172`/`0.566` have **no committed derivation anywhere on trunk** — and the instrument behind all
  four (`load1` regressed on session count) is *unidentified* on this box, because B3 measured 87.3%
  of the load numerator as not-Claude across an 8.35→46.39 daily range and A8's direct probe watched
  load FALL while a unit was added. The sampler this bullet asks for is landed
  (`scripts/capacity-marginal.sh`, controls proven able to fail in `tests/capacity-marginal.bats`);
  the coefficient itself still wants one ~1 h on-box window (§6 of that doc) — now driven end to end
  by `scripts/capacity-marginal-run.sh`, one resumable command that also makes §6's stop rule
  mechanical, since only an *instrument* term (`C1:swing` / `C2:corr` / `C2:constant`) is that
  paragraph's finding and a quiet box (`C2:neff` / `C3:flat`) is not (§6b). **Until it exists, none
  of the four may be quoted.** ✅ **The ban is now enforced in code (2026-08-26, §6a of that doc):**
  the citation sites were struck and labelled REFUTED, with **no value substituted**. There were
  **three**, not the two named here — `scripts/lib/capacity-admit.sh`,
  `hooks/agent-teams-enforce.sh` (a runtime deny message, not a comment) and
  `scripts/lib/spawn-presence.sh`, the library that *defines* the ACTIVE population the coefficient
  is denominated in. `CC_ADMIT_ACTIVE_CEILING=8` is **not** blocked on the measurement: it now
  stands on the 127/127 refusal band, a count over refusals that needs no per-session divisor.
  Re-grep at the PASS rather than working from any list of paths.
- **Whether load average means anything as a capacity signal at all.** At constant N=15–16 the box
  read **11.21 → 36.07**; one instrumentation run alone moved it 19 → 36 with session count unchanged.
- **Whether automated fires retry after a capacity refusal** — decides whether raising the ceiling
  buys throughput or only latency.
- **Turn latency.** The reframing that "~15 is a felt *latency* ceiling, not an admission wall" was
  refuted as *unsupported*: there is no turn-latency instrument, no queue depth, no wait-time
  distribution anywhere in the fleet. The box demonstrably admits 52 resident sessions; what degrades
  at ~15 has never been measured, only felt.

**The one next measurement:** marginal Δload from adding exactly **one** active session at a
held-constant baseline, N≥5 at different baselines, counting sessions by **executable path, never
argv** (argv reads 30–33 against a true 15–16, because briefs mention the path):

```sh
# quiet window: sysctl -n vm.loadavg stable ±1 over 5 min
ps -axo comm= | grep -c 'claude-220/node_modules'      # the honest session count
# sample load1 5 min -> fire ONE --goal-armed session doing real work -> sample 5 min
```

**The control that must be able to fail:** the sampler has to reproduce the load average it
apportions. If the census stays flat while load moves, it is the instrument — which is exactly how
this wave's "64% is our own automation" headline died. No attribution figure should be quoted again
until a sampler clears that control.

**That sampler is now `scripts/capacity-marginal.sh`** (2026-08-19). It implements this paragraph as
three required controls — LEVEL (does the census reproduce the load, at more than one load) ·
DYNAMICS (does it move when load moves, over `n_eff` independent observations, not `n`) · IDENTIFY
(did the ACTIVE count vary at all) — and emits `NO-ATTRIBUTION` with the failing term rather than a
number when any of them fails. The first row of `tests/capacity-marginal.bats` replays the exact
census shape that killed the 64% headline and asserts the refusal, so the control is known to be able
to fail rather than assumed to be. Design, the adjudication of the four values, and the run protocol:
`marginal-load-per-active-session-2026-08-19.md`.

---

## 6 · Provenance

13 agents, 12 completed, **1 died on a genuine session limit** (`verify:load-mechanism`, aborted
00:59 — "You've hit your session limit · resets 3:30am"); its axis therefore carries a finder with no
adversarial check, and is flagged as such above. 2.05 M subagent tokens, 412 tool calls, 12.4 h wall
clock. Workflow run `wf_96a89c2d-c5b`.
