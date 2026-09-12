# DRAIN CIRCUIT — the fire arm gets an instrument, and the statistic is the GAP (2026-09-12)

**Subject:** the closing finding of W10
(`docs/research/drain-circuit-w9-prediction-readjudication-2026-09-11.md` §5), which this session
was dispatched to advance:

> **The gap this re-adjudication exposes: the prediction had three arms and only one of them was
> made falsifiable.** The fire arm — the one that turned out to be wrong, by 10x — had no stated
> falsifier, no threshold and no instrument. It was refuted here only because ref names happen to
> carry timestamps.

W10 could not do more than that from its venue: it wrote the re-measurement command into a fenced
block and moved on. **Nothing executes a fenced block.** This session turns it into an instrument
with a declared criterion, a suite, and a carrier that runs it between dispatches — and in the
course of doing so found that W10's own headline number had already rotted by 84 % in one day,
which is the strongest available argument that the number was never the right deliverable.

**Venue:** cloud VM, off-box. Every figure is first-hand from `origin`'s refs and `origin/main`'s
log — the only source this box can read. §6 states what that still costs.

---

## 1. The controls, re-run before anything was believed

Both of W10's controls reproduce exactly. They are re-run rather than inherited because the whole
method rests on them, and this repo's own rule is that a pre-existing state is a claim until it is
measured.

| control | W9 (09-07) | W10 (09-11) | **W11 (09-12)** |
|---|---|---|---|
| fire refs dated ≤ 2026-09-07 | 425 | 426 | **426** |
| `claude/*` heads that are not well-formed fire refs | — | 0 | **0** |
| non-`claude/` heads on the remote | — | 4 | **4** (`main`, `ab-local-1`, `ab-local-2`, `cc-bootping-probe-tmp`) |

The population is **monotone**, which is what a never-deleting store must be
(`cloud-return.sh:529`, `cloud-retire-terminal.sh:55`). So an absent date is still a real absence
and not a collection artifact, and the lane has still not been renamed — this plan's §1.1 scar,
where a `grep -rl` null was real *for a name* and wrong about the world.

Total fire refs now: **445** (444 excluding this session's own boot ping; see §3.3).

---

## 2. W10's number rotted in one day, and that is the finding

W10 measured the fire arm at **2.50 fires/day** over the four complete days 09-07…09-10. Re-running
the identical expression one day later:

| UTC day | cloud fires | trunk commits (UTC) |
|---|---|---|
| 2026-09-05 | 0 | 42 |
| 2026-09-06 | 0 | 37 |
| 2026-09-07 | 5 | 72 |
| 2026-09-08 | 0 | 130 |
| 2026-09-09 | 1 | 152 |
| 2026-09-10 | 4 | 133 |
| **2026-09-11** | **13** | 61 |
| 2026-09-12 *(partial)* | 1 *(this session)* | — |

| window | fires | per day |
|---|---|---|
| 09-07…09-10 (W10's, 4 complete days) | 10 | **2.50** ← reproduces W10 exactly |
| 09-07…09-11 (5 complete days) | 23 | **4.60** |
| rolling 7 d to 09-12T01:14Z | 23 | **3.29** |

**09-11 alone delivered 13 fires — more than W10's entire four-day window.** The same statistic over
the same lane, computed the same way, moved **+84 %** in twenty-four hours.

This is not a criticism of W10, which said so itself (*"The fire figure in §2 is a reading taken on
2026-09-11 and will rot exactly like the ~25/day it refutes"*). It is the third instance in this
plan of the same error class and the first one caught in advance: W9 read ~25/day off the
09-03/09-04 burst and carried it forward as a property of the pipeline; 2.50/day is a four-day lull
carried forward the same way. **Any ceiling derived from an observed rate inherits the rot of the
rate it was derived from.**

### 2.1 A hygiene trap in the cross-lane comparison, found while reproducing it

W10's trunk column (09-08 **130**, 09-09 **152**, 09-10 **133**) reproduces only on the **UTC** day
boundary. Counted on the committer's own `−05:00` offset the same commits give 09-08 **152**,
09-09 **140**, 09-10 **105** — up to 28 commits moved, and the peak moves from 09-09 to 09-08.

Both tables are true; they are different questions. The point is that the fire census is *forced* to
UTC (fire ref names carry a `Z` stamp) while a `git log` date is whatever basis you ask for, and
nothing made that explicit. **A cross-lane comparison is only sound if both lanes are counted on the
same day boundary.** W10 happened to use UTC for both and is correct; a reader re-deriving the table
with a default `git log --date=short` would silently get the other one and conclude the two sessions
disagree about trunk.

---

## 3. What was built, and why the gap rather than the rate

`scripts/cloud-lane-liveness.sh` — ref-derived, store-free, venue-independent; it needs no backlog
store, no IDL, and no `~/.claude` layer, so it answers identically on the desk and on a cloud VM.

### 3.1 The rate cannot express the fault, and the gap can

The fault this plan has always been about is a **stall** — W9's 58 h 45 m deadlock, W10's 31.1 h and
35.8 h gaps, the 09-08 zero day. A mean over a window cannot say "the lane went quiet":

- **It averages the stall away.** W10's window reads 2.50 fires/day and *contains* a 35.78 h silence
  and a zero day. Both facts come from the same seven numbers; only one survives the mean.
- **It rots** (§2).

So the rate is **reported** — it is real context and suppressing it would be its own dishonesty —
and the **verdict is the gap**. They are kept apart deliberately, W2's add-don't-redefine. Reading
the rate as liveness would be §1.5's defect in its fourth costume: §1.5 counted commits where the
question was closure, §W9(3) counted pile size where the question was disposition, W10 §4 found
trunk volume reading as pipeline health where the question was per-lane liveness — and
rate-for-liveness is the same mistake one step further in.

### 3.2 The OPEN gap is the verdict; closed gaps are history, never a charge

A stall **in progress has no closing endpoint**, so a max-gap-between-fires is structurally blind to
the live failure — it can only ever describe stalls that already ended. `now − last_fire` is
therefore the verdict arm.

Closed gaps in the window are reported beside it (`stalls_in_window`, `max_closed_gap_h`) and never
charged, or the 58.76 h silence that ended five days ago would hold the gate red forever — a gate
with no path to green, the shape this repo's corpus says to audit rather than build around.

This is also why the instrument has to **ride something**. The lane's history is legible whenever
you look, because ref names are timestamped; but a stall is only *actionable while it is happening*,
and between dispatches nothing sampled the lane at all. On 09-08 it fired zero times while trunk
took 130 commits, and no surface said so for three days.

### 3.3 🚨 The reader can be its own subject

Run from a cloud VM, this script's own boot-ping branch **is** the newest fire ref, so `now − last`
is seconds by construction and the live arm **can never trip**. That is worse than useless: it means
firing a session *to diagnose a stalled lane* is the act that makes the lane read healthy — a census
matching itself, the repo's `argv-census-must-not-carry-its-pattern-in-argv` shape in a different
medium.

The ref naming the current branch is excluded and the exclusion is **named in the output**. It is
self-limiting: on the desk `HEAD` is never a fire ref, so nothing is dropped. Measured here — the
run below drops exactly one ref, 445 → 444, and the gap it reports is to the *previous* session's
fire rather than to my own push four minutes earlier.

### 3.4 Every UNKNOWN arm ranks ABOVE the compare, and the asymmetry is the reason

A census that cannot be trusted reports a **quiet** lane, never a busy one. So each of these
outranks the gap compare, and letting any fall through would mint `STALLED` out of an instrument
failure:

| arm | why it voids the census |
|---|---|
| the `ls-remote` failed | "cannot look" is not "nothing found" — non-zero rc with zero rows is byte-identical to a remote holding no fires (`cloud-reconcile.sh:51` states the same law) |
| a malformed `claude/*` ref | the lane may have been renamed; §1.1's scar |
| the ref population **shrank** below its pinned floor | a branch was deleted, so an absent date stops being evidence |
| no fire ref survives the self-exclusion | there is nothing to measure a gap from |

`UNKNOWN` nulls **every** numeric field. A reading taken through a sensor that could not run is not
a smaller reading, it is no reading, and a consumer summing these rows must not be handed a zero.

### 3.5 The ceiling comes from the plan's name, not from a burst

**24 h**, because the plan is *"the 24/7 pipeline is an open loop"* and a lane that is 24/7 and has
not fired in a day has stalled by its own definition. Deriving it from an observed rate is exactly
the error W9 made, so it is not derived from one.

Its polarity is **measured against the real series**, not hoped for:

| interval | length | verdict at a 24 h ceiling |
|---|---|---|
| 09-04T19:37:54Z → 09-07T06:23:32Z | 58.76 h | **STALLED** ← W9's deadlock, reproduced to the minute |
| 09-07T17:36:18Z → 09-09T00:44:25Z | 31.14 h | **STALLED** ← W10's |
| 09-09T00:44:25Z → 09-10T12:31:01Z | 35.78 h | **STALLED** ← W10's |
| every interval since 09-10T12:31Z | ≤ 6.33 h | LIVE |

It fires on exactly the events this plan calls stalls and is silent on everything since the lane
reopened. Seam: `CC_LANE_FIRE_CEILING_H`.

### 3.6 The live reading

```
cloud-lane-liveness — the cloud FIRE lane, read from origin
  last fire     2026-09-11T22:15:04Z  (3.04 h ago)
  ceiling       24 h  — from the plan name (24/7), not from an observed rate
  window        7 d  · 23 fire(s) · 3.29/day  ← CONTEXT, never the verdict
  history       3 stall(s) over the ceiling in-window · widest closed gap 58.76 h
  population    444 fire refs · 426 dated <=20260907 against a pinned floor of 426
  self-excluded claude/fire-20260912T010855Z-86683-1
  VERDICT       LIVE — last fire 3.04 h ago, inside the 24.00 h ceiling
```

The widest closed gap being **58.76 h** — W9's own 58 h 45 m deadlock, independently recomputed
from ref names by a tool that was told nothing about it — is the positive control for the entire
census.

---

## 4. The carrier

`scripts/cloud-return-lane.sh` gains a §0 that journals a `cloud-fire-gap` IDL row each tick.

**Why this observer.** It must not share a failure mode with its subject, and this one cannot: the
fire lane is reached by the **dispatcher**, this lane is spawned by the **sweep**. The observer
stays up exactly when the subject goes down. §1.6's constraint holds — no new launchd job, and the
tick already pays for network.

**Why first.** One `ls-remote`, read-only, no lock, and — the property that decides the position —
no dependency on anything the passes below produce: it observes the *fire* lane, not this lane's own
output. Everything sequenced under the 5,400 s return bound is reachable only because *"a killed
child ends the command, not the script"*; a read that needs no such argument belongs where the
argument is not needed at all. The inner-bound-starves-the-tail shape this lane's own header records
is avoided by construction rather than by measurement.

**Absent is `null`, never a zeroed reading** — the same law as the retire census below it. A cut or
crashed read is validated with `jq -e .` before journalling, because one malformed value would abort
every `jq -rs` slurp of the whole journal.

---

## 5. Proof

`tests/cloud-lane-liveness.bats` **17/17**; `tests/cloud-return-lane.bats` 14 → **19/19**. The green
is worth nothing on its own, so twelve mutants were run, each required to redden a **predicted** case
set, with the subject restored byte-identical afterwards (`cmp`: IDENTICAL) and a comment-only
control killing nothing in both files:

| mutant | kills | property credited |
|---|---|---|
| M1 no self-exclusion | 3, 4 | the reader's own boot ping closes the gap it was fired to measure |
| M2 cannot-look falls through | 5, 6, 15 | a dead sensor reads as a quiet lane |
| M3 verdict charges history | 8, 12 | a stall that *ended* holds the gate red |
| M4 verdict = rate | 10 | the statistic W9/W10 argued over |
| M5 no population control | 7, 15 | a deleted branch voids the census |
| M6 no rename control | 9, 15 | §1.1's scar |
| M7 no clock-skew clamp | 14 | a future stamp yields a negative gap |
| M8 CONTROL comment-only | *none* | the suite is behaviour-keyed, not prose-keyed |
| MC1 drop the `jq` validation | 19 | a half-written line reaches the journal |
| MC2 move §0 below RETURN | 15 | the read becomes starvable |
| MC3 absent journals `{}` | 18 | a non-reading reads as a reading |
| MC4 CONTROL comment-only | *none* | — |

**Three of the first eight predictions were wrong, and each wrong one was a finding:**

- **M2 killed 5 and 15 but case 6 SURVIVED.** Case 6 claimed to test that an `UNKNOWN` reading nulls
  every number — and it does — but it passed equally on the *no-fire-refs* arm, so it credited a
  cure it never ran. It now asserts the **reason**, and the mutant kills it. A green case that
  survives the mutant aimed at it is testing something other than what its name says.
- **M3 as first written** (verdict = widest *closed* gap) killed six cases, which attributes nothing.
  Refined to `verdict = max(open, closed)` it kills exactly the two that encode "history is reported,
  never charged".
- **M5/M6 additionally kill 15** (`--selftest`), correctly and unpredicted: the selftest is an
  independent second guard on the same verdict arms.

A vacuous assertion of my own was caught in the same pass: in `jq`,
`A and .elapsed_s | type != "string"` pipes the **whole conjunction** into `type` and is
unconditionally true. Parenthesised.

**Not mine, attributed by A/B against a detached worktree at `origin/main` carrying none of this
diff** — a pre-existing red is a claim until it is measured:

- `bats-assert-liveness` reds on exactly `{3, 4, 5, 14, 21, 36}` in **both** arms; its own case 3 is
  the CONTROL naming the bash 3.2 grid this Linux VM does not have.
- `unattended-path-lint` output is byte-identical in both arms but for the checkout path inside one
  message.
- `bats-kill-guard-lint` 35/35, `bats-shim-parity-lint` 28/28, `bats-shortfall-nonverdict`,
  `bats-testname-eval-lint` (666 suites) — all clean.

⚠️ **NOT shellcheck-verified** — shellcheck is absent on this VM. The desk's land gate owns that arm.

---

## 6. What is NOT claimed, and what is still open

**The instrument does not explain the rate, and must not be read as claiming to.** W10 left the
cause of the fire rate explicitly open between (a) a genuinely drained backlog — a *good* outcome —
and (b) a dispatcher only reached when an operator is present. Nothing here separates them; that
still needs a store read only the desk can do. 09-11's burst structure (13 fires, clustered at
04:39–04:40, 07:49–08:42 and 16:31–16:35) leans toward (b) exactly as W10's did, and is still
evidence rather than proof.

**W9's stated falsifier remains UNRUN.** `sum(census.landed) / sum(census.retired) > 25 %` over a
7-day window needs the `cloud-retire` IDL rows on the operator box. The typed `census` that makes it
runnable is on trunk and content-verified (`scripts/cloud-return-lane.sh`); only the store is out of
reach. This session did not touch that arm.

**The LAND arm was not instrumented, deliberately.** It is the arm W10 *confirmed*, its instrument is
described in W10 §3.1 (subject-on-trunk, because the desk lander replays and ancestry/`git cherry`
therefore lie), and it costs a fetch per branch rather than one `ls-remote`. Building it here would
be scope this item did not ask for.

**The `cloud-fire-gap` rows have no reader yet.** They are journalled beside the lane's existing
rows in the shape every existing consumer already parses, but nothing asserts on them. Whether a
`STALLED` reading should page, and through which existing surface, is an operator-box question
(C10 forbids editing live hooks or launchd from here) and is left to the desk. The instrument's
`--assert` exit code (1 = STALLED, 3 = UNKNOWN) is the seam for it.

---

## 7. Dispatcher vintage

The brief that fired this session was composed by `bin/cc-dispatch` blob
`9109de61dc7add48cd94809d54e591af0bfe9021`, against `origin/main`'s
`27c461a5f1a4de551fdfbe2a619e28e696c13aaa` — **DIFFERENT**, so the dispatcher that fired this
session is behind trunk.

Sharper than W9's and W10's identical observations, and worth stating because it is now a series:
`9109de61…` is the **same blob that fired W10 a day earlier**, while trunk's copy has changed twice
in between (`5a983031` 09-11T02:11−05:00, `59270aae` 09-11T10:14−05:00) and stood at `e61bcbfc…`
when W10 read it. So the live dispatcher has been behind through at least two waves while trunk
moved under it. A convergence fact about the deploy layer, not a defect in anything read here —
*landed is not live* — and consistent with W10 §3.3's measured 17–96 h return latency.

**Cure sha asserted:** W9 landed as `140c2889b5ff09597b8b151b0d5f0f1dc908f109`
(`git merge-base --is-ancestor 140c2889b5ff09597b8b151b0d5f0f1dc908f109 origin/main` → exit 0), and
W10 landed as `44a18513` — this session's checkout is trunk exactly
(`git rev-list --count HEAD..origin/main` = 0 after `--unshallow`), so every file read here is
trunk's own copy and not a stale horizon.
