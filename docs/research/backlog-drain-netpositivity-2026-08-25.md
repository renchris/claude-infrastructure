# Is the backlog net-positive, and can it drain to zero? — 2026-08-25

**Scope (frozen):** settle (a) whether filing→completion delay makes cc-backlog completions
non-net-positive against a moved-on HEAD, (b) whether the 24/7 local and cloud drains make real
progress to zero or are a treadmill, and (c) whether a days/weeks/one-month timeline to zero is
reachable.

**Method.** Direct folds of `~/.claude/autonomy/backlog.jsonl` (14,249 records, 0 malformed) plus a
23-agent fan-out (12 recon axes → 10 adversarial verifiers → synthesis; 4.07 M tokens). Every
verified claim was attacked by a fresh-context verifier whose default was REFUTED. **Ten of ten
survived-into-verification claims were refuted or re-scoped** — §7 records them, because those
failures are the most useful part of this document.

---

## 1. THE ANSWER

**Roughly half the drain's output is not net-positive: 40–55% of the 2,294 closures match a verbatim
no-op disposition (already-landed, auto-retracted, duplicate, refuted, superseded).** And the
operator's staleness intuition is confirmed as a **dose-response** — a row closed after a week is
closed as premise-dead 23.4% of the time versus 4.2% under a day.

**It is not converging, and the honest word is *unmeasurable*, not *slow*:** the pool's trend slope
flips sign with the fitting window (+12.95/day over 30 d, −4.68/day over 14 d, +14.21/day over 7 d).
The agent-facing board specifically sat at **287 ± 38 for 19 days while 1,635 items were closed
inside it** — sixteen hundred closures moved the actionable board **+40, in the wrong direction**.

**Days/weeks/a-month is NOT reachable for "the backlog" as one number, and no intervention makes it
so.** It becomes reachable only by splitting the board: the **303 agent-reachable rows can plausibly
hit zero by mid-to-late September**; the **198 blocked rows have no agent path at all** and will sit
until the operator spends 3–7 sittings on them.

---

## 2. Worry (a) — STALENESS

**VERDICT: REAL and dose-responsive. It degrades the value of a completion; it usually does not
destroy the target.**

### The number that settles it

Refutation rate at close by residence time, over all 2,294 completed rows (strict regex, uppercase
verdict tokens only):

| residence time | n | closed as premise-dead | rate |
|---|---:|---:|---:|
| < 24 h | 1,261 | 53 | **4.2%** |
| 24–72 h | 321 | 30 | **9.3%** |
| 72–168 h | 348 | 42 | **12.1%** |
| > 168 h (1 week) | 364 | 85 | **23.4%** |

Monotone, **5.6× across the range**. A wider regex gives 19.3% → 38.5%, still monotone. Only 68 of
2,294 closures are unclassifiable, so the instrument is not blind.

**Staleness = (tree velocity) × (queue residence). Tree velocity is exogenous; residence is ours.**
`cc-backlog freshness` reports p50 **415 commits** of trunk movement since filing across the 501 live
rows (max 3,253). Independent check on completed rows: commits landing between filing and completion
run p50 61 / p90 885 / max 2,912, with only **5.8% completing against an unchanged tree**.

### The live pool is already in the expensive band

Age of the 501 live rows: p50 5.8 d, p90 17.9 d, max 36.3 d. **230 rows (45.9%) are already older
than 7 days**; 119 (23.8%) older than 14. Applying the measured >168 h rate projects **~54 (strict)
to ~89 (wide) rows that will close as premise-dead rather than fixed** — a projection from closed
rows, not a measurement of live ones (§7).

### The mitigation is built and 91% unapplied

`cc-backlog freshness` reads **`never validated: 457 of 501 live rows`**. Only 47 live rows carry a
falsifier probe at all. When the sweep does run it works: the 2026-08-24T07:59Z pass marked 4 rows
falsified and all 4 closed within 3 minutes. **This is a scheduling problem, not a design problem.**

#### 🚨 CORRECTION 2026-08-25 (item `37b112d8950d`, the L1 dispatch) — THE SENTENCE ABOVE IS WRONG IN BOTH HALVES

It is **not a scheduling problem**, and the number **is not a backlog of unrun probes**. Read off
trunk code, not the store:

1. **The sweep is already scheduled and already whole-store.** `scripts/autonomy-sweep.sh:732-820`
   (§2b-iii, "THE CURRENCY PASS") runs `cc-premise sweep --json --record --limit 150
   --close-falsified 5` on a 6 h gate (`CC_PREMISE_PASS_EVERY_S`, default 21600) inside a job that
   fires every 300 s (`launchd/com.chrisren.autonomy-sweep.plist:12`). The 2026-08-24T07:59Z pass
   cited above **is that job** — it is the mitigation running, not an existence proof of a
   mitigation nobody runs. There is no additional pass to fire.
2. **The 457 are the rows the sweep CANNOT ask, and refusing to stamp them is deliberate.**
   `bin/cc-premise:2991-3000`: *"ONLY PROBED ROWS ARE STAMPED, and this is the line the whole wave
   turns on… stamping [an unprobed row] as validated would drive the never-validated headline to
   ZERO while ~400 of 564 rows had had nothing run against them. That is not a weaker metric than
   none, it is a WORSE one."* `never_validated` is computed as live rows absent from the validated
   snapshot (`bin/cc-backlog:4601,4606`), and only probed rows enter it. So **457 is a CAPABILITY
   deficit, not an EXECUTION one** — precisely the distinction `cmd_validated`'s own header draws
   (`bin/cc-backlog:4307`: *"Coverage is a claim about capability; this is the record of an ACT"*).
   This document made exactly the conflation that header exists to prevent.
3. **Therefore both of the item's projected effects are unreachable by running the sweep.**
   "Converts ~400 rows from unknown to known freshness" is a no-op by construction — the pass
   already visits every non-done row every time (`bin/cc-premise:3008-3010`: only the *probe* is
   sharded, never the report) and stamps none of them, because nothing was measured. And the closer
   takes only the `falsified` bucket (`bin/cc-premise:3087`), which only a stored or derived **probe**
   can produce; a probe-less row can never enter it, so "retire 54–89 rows" cannot come from this
   lever at any cadence.
4. **`cc-backlog falsify` is one row, one hand-written probe.** `bin/cc-backlog:3349-3360` — it
   exists precisely because `add --falsifier` cannot reach an existing row, and it attaches a single
   `--probe "<sh one-liner>"` per invocation, running it first and refusing an exit-0 store. There is
   no bulk generator. "Run `cc-backlog falsify` over every live row lacking a probe" is therefore
   **457 authored shell predicates**, not a sweep.

**Corrected L1 — see §6.** The 54–89 estimate itself is untouched by this correction; it was always a
projection from closed-row rates (§7 "Still blind" item 1 says so), and it stays **UNMEASURED**,
because the instrument that would measure it does not reach the population it was pointed at.

### What refutes the strong form

The ticket usually still points at a real artifact. All 20 sampled files from the >72 h population
still exist at HEAD (20/20). Of 291 file:line anchors, only **6.1% had vanished** at claim time;
58.8% had merely **moved within the same file**. **The line number and the premise rot; the file does
not** — so a stale row is usually cheap to revalidate, which is exactly why L1 below is the top
intervention.

The sharpest instance is recorded in the repo's own code, `scripts/ship-land.sh:1020-1024`: *"censused
2026-08-12, 24 of the 25 `re-land …` rows … were false — the work had landed under a different sha —
and actioning four of them would have REVERTED trunk."*

---

## 3. Worry (b) — TREADMILL and NET-POSITIVITY

**VERDICT: CONFIRMED at the ledger and commit level. PARTIALLY REFUTED at the work level — the drain
is *not* primarily eating its own tail; it is absorbing a large exogenous inflow it cannot outrun.**

### The number that settles it

Over the last 19 days the **agent-facing board (open + claimed) went 263 → 303, OLS +0.29/day**,
mean 287, min 261, max 337 — while **1,635 items were closed and 1,679 filed inside that window.**

### Net-positivity: 40–55% of closures changed nothing

Unambiguous machine-generated no-op dispositions cover **858 of 2,294 closures = 37.4%**
(C2-flood retraction 387 · consolidation prune/merge 159 · auto-retracted 99 · landed-by-content 86 ·
cc-premise auto-close 46 · drain-recycle close 41 · "no longer holds" 40). Widening to include
duplicate/REFUTED/SUPERSEDED gives **1,171 = 51.0%**. An independent hand-count (n=45) gave 55.6%,
95% CI [41.0, 70.1] — overlapping. **Honest band: 40–55%.**

### The experiment the system already ran on itself

On 2026-08-09 the pool stood at exactly **460**. A full-corpus triage ran against precisely that
population — `docs/plans/backlog-consolidation-2026-08-09/verdicts.json` holds exactly **460**
verdicts — and disposed of **162 (35.2%) as PRUNE or MERGE**. It was applied: all 117 PRUNE and all
45 MERGE ids fold to `done` today, 0 of the 460 missing from the ledger. **Sixteen days and 1,268
completions later the pool was larger than the 460 it started from.** The most aggressive intervention
available was executed in full and bought nothing.

### What the machine commits

Last 14 days on `origin/main`: **1,130 commits; 460 (40.7%) touch ONLY `docs/`; 1,044 (92.4%) touch
only `bin|hooks|scripts|docs|tests|commands|skills`.** The drain lane's own artifact
`docs/plans/BACKLOG_DRAIN_24_7.md` is **1,756,936 bytes / 20,469 lines**, grew **+19,234 / −68 lines
in 7 days** (99.6% pure append), and has minted **187 numbered "methods" with no retirement
mechanism**.

### Cost

252 drain sessions over 12 days billed **4.07 billion tokens** — ~18.8 M tokens per row closed,
~$243/day inferred at Opus list prices (a token measurement; the Max plan is a quota meter, not a
dollar meter). The lane runs **25.5 recycles/day at a median of 1 row closed per recycle**.

### 🚨 Where the treadmill hypothesis is NOT supported — and this corrects my own first read

The adversarial pass refuted the strongest self-feeding claims, and I believe it:

- **`source=needs`, the largest generator, is 78.2% drained** — 560 done / 151 blocked / **5 open**.
  A generator with five open items is not a treadmill.
- **The `re-land` family** — 327 rows, my flagship treadmill evidence — is **92.7% done, 0 open,
  self-retracting at filing (median true life 34 seconds)**, and contributes 24 of 501 live rows
  (4.8%). Deleting every re-land row moves the pool 501 → 477. It changes nothing.
- **The drain self-feeds only ~7 of the ~64 adds/day.** ~89% of inflow is **exogenous**, filed by
  ~15 concurrent producers, not by the drain.

**So the correct diagnosis is not "the machine invents work for itself." It is: the machine files
faster than it can honestly finish, and 40–55% of what it finishes was already finished or was never
real.**

---

## 4. The generator structure

| generator | live rows (of 501) | rate | bounded? | note |
|---|---:|---:|---|---|
| **`cc-backlog needs`** | **157** (152 blocked) | ~25/day | **UNBOUNDED** | Rows are born `blocked` (`bin/cc-backlog:2802`) and `cc-dispatch` selects `status=="open"` only (`bin/cc-dispatch:1512,1522`) — **this generator writes straight into the operator's inbox and no agent is ever dispatched onto one.** Coerced by Stop-hook blocks naming the verb verbatim (`hooks/completion-assert.sh:946/947/948`, `hooks/session-continue.sh:938`). Agent-authored slice +3.1/day. |
| ↳ `ship-land.sh:1000` re-land trap | 24 | ~4/day | in principle | 330 ids for 134 branches (max 41 for one). Already throttled **8.6×** (37.0→4.3/day) by `aa1886a5e` + `017650872`. **A largely fixed defect.** |
| **agent free-text, `--source` omitted** | **102** | ~35/day | **unreachable by policy** | `--source` defaults to `""` (`bin/cc-backlog:1365`). Second-largest live slice; no per-source rule can touch it. |
| **`plan-open`** | 17 | **0 adds in ~86 hourly runs** | **BOUNDED, SATURATED** | Ceiling = 46 live plan docs, all already carry a row, headroom 0. But it rides an unbounded input: 83 plan docs added in 30 days, retirement manual-only. ⚠️ Its telemetry **lies upward**. |
| **`postland-verify`** | ~4 | ~4/week | **CURED** | Condition-keying landed. Now the *stalest* class: p50 57.5 h. |
| deploy-live · autonomy-sweep · desk-observed | ~5 | 5 of 480 adds in 7 d (1.0%) | negligible | `desk-observed`/`close-integrity` have **no code that files them** — agent-typed labels. |

### The structural fact underneath all of it

**Only 148 of 2,782 adds (5.3%) carry a `--condition` key. Where used, deduplication is perfect —
148 condition groups → 148 ids, max 1 distinct id per group.** The other 94.7% are title-hashed, so a
recurring problem mints a fresh row every recurrence. Consequence: **466 of 2,782 adds (16.8%) are
surplus rows sharing a near-identical normalized title, 67.2% machine-authored. The mechanism that
fixes this is built, correct, and unused.**

### The second structural fact — the split is ~2:1 against the operator

Last 7 days: 493 adds → **315 born `open` (45.0/day, agent-facing)** and **178 born `blocked`
(25.4/day, operator-facing)**. The operator stream has no agent exit by design and grows ~+3/day net.

### Filing is coupled to draining by construction

`bin/cc-backlog:5821` — **"S5 KICK-ON-WRITE"**: every `add` fires a dispatch pass that starts a
session to work it. Kill switch: `CC_BACKLOG_KICK=off`. This is why arrival and completion track each
other at ~70/day; they are not independent quantities that happen to match.

---

## 5. THE TIMELINE

### There is no measurable convergence — the slope flips sign by window

| window | pool OLS slope | net flow | implied date to zero |
|---|---:|---:|---|
| 30 days | **+12.95/day** | +9.8/day | never — passes 1,000 ≈ 2026-11-16 |
| 18 days | −0.30/day | — | ~4.6 years |
| 14 days | **−4.68/day** | −1.4/day | 107 d (slope) / 358 d (flow) |
| 7 days | **+14.21/day** | −3.4/day | never (slope) / 147 d (flow) |

The 7-day slope and 7-day flow **disagree in sign with each other**. Level series: Jul 28 = 125 →
Aug 8 = 405 → Aug 16 = 578 → Aug 19 = 403 → Aug 25 = 501.

> **Any "days to zero" figure quoted so far — including the drain lane's own 25 days — is
> window-shopping.** That figure was fitted over 23 board readings inside roughly one day.

### Scenarios

| # | scenario | effect on the 501 | date pool = 0 | confidence |
|---|---|---|---|---|
| **A** | **do nothing** | slope indeterminate | **UNKNOWN — sign flips by window** | none |
| **B** | bulk-falsify the 457 unvalidated rows | **−54 to −89, one-time** | still none — a level shift, not a slope change | projection |
| **C** | B + generator cuts (inflow 64→57/day) | net ≈ −10/day | ≈ 43 days → **2026-10-07** | **low** — outflow is itself 40–55% no-ops |
| **D** | **C scored on the AGENT BOARD only (303 rows)** | agent inflow 45/day vs agent closure | **≈ 3–5 weeks → mid-to-late September** | **the only defensible date** |
| **E** | D + operator clears the floor | blocked 198 → ~60 | agent board mid-Sept; floor in 1–2 weeks of *operator* time, in parallel | medium |
| F | add drain capacity (2× recycles) | — | **no effect on the date; ~$243 → ~$486/day** | measured |

> ⚠️ **Scenario B is not executable as written** (correction, §2 and §6): "bulk-falsify the 457" has
> no bulk form — the sweep cannot ask a probe-less row, and probes are attached one authored
> predicate at a time. Its **−54 to −89** was a projection from closed-row rates, not a measurement,
> and it does not survive as a costed intervention. Rows **C** and **E**, which take B as an input,
> inherit that: their level-shift term is unfunded until L1′ is done. **D is unaffected** — it is
> scored on the agent board's own flows and never depended on B.

**The only row yielding a defensible date is D, and it gets there by changing the *target*, not the
throughput.** "Drain the backlog to zero" has no date because it conflates two populations with
different owners.

---

## 6. WHAT TO ACTUALLY DO — ranked by effect per effort

**L1 · Run the falsifier sweep across all 457 unvalidated live rows — AGENT, ~1 day.**
`cc-premise sweep --record` / `cc-backlog falsify` over every live row lacking a probe, then
`--close-falsified`. Retires an estimated **54–89 rows with no work done**, and converts ~400 more
from *unknown freshness* to *known*. Existence proof: the 2026-08-24 pass falsified 4 rows, all
closed within 3 minutes. **#1 because it attacks residence-time decay directly and makes every later
decision cheaper.**

> 🚨 **RETRACTED 2026-08-25 as written — see the CORRECTION in §2.** The sweep half is already
> running unattended every 6 h and is already whole-store; the 457 rows are the ones it *cannot*
> ask, because they carry no probe and `cc-premise` refuses to stamp a row it did not measure. No
> re-run of any cadence moves that number, and the closer can only retire rows a probe falsified.
>
> **L1′ · Give the standing rows probes — AGENT, and it is per-row authoring, not a sweep.** The
> lever that actually moves `never_validated` is `cc-backlog falsify <id> --probe "<sh one-liner>"`,
> one authored predicate at a time (`bin/cc-backlog:3349`), against the ~457 probe-less live rows.
> Sizing is therefore **hours per batch of rows, not ~1 day for the population** — and it should be
> ordered by residence time, since §2's dose-response is what makes an old row worth a probe.
> The prospective half is already solved and is L2: generators that emit `--falsifier` at filing
> time cover new rows for free, which is why `add --falsifier` exists and why only rows minted
> before those generators landed are in this pile.
>
> **L1″ · Give the prose verdicts an exit — AGENT, small, and it is the closest thing to the
> "retire rows with no work done" this item promised.** Every pass already computes `superseded`
> and `self-duplicate` over **every** non-done row, probe or not (`bin/cc-premise:3008-3010,
> 3144-3145`), and reports them. Nothing closes them: `_close_falsified` is handed the `falsified`
> bucket alone (`bin/cc-premise:3087`). Those two buckets are a retirement queue that is measured
> four times a day and consumed never. ⚠️ Not a free change — `cc-premise`'s docstring argues at
> length that refusal is reserved for the narrow whole-claim case, so an auto-closer over
> `superseded` needs the same cap-and-re-ask discipline `_close_falsified` already carries, and
> `corrected`/`suspect` must stay out of it.

**L2 · Adopt `--condition` at the four uncured mint sites — AGENT, ~half a day.**
`scripts/ship-land.sh:1000`, `scripts/postland-verify.sh:793-797`, `scripts/deploy-live.sh:725,870`,
`scripts/autonomy-sweep.sh:381`. Prospectively removes ~**5–8 adds/day**. The pattern is proven twice
in this repo (postland ~10×, re-land 8.6×).

**L3 · Decide the operator-gated blocked rows — OPERATOR ONLY, 3–7 sittings.**
Run L1 against the blocked pool *first*: a hand-check of 16 mechanically-verifiable blocked rows found
**8 dead outright, 1 partly dead (56%)** — including three separate filings of "plug the MacBook into
AC power" against a machine `pmset -g ps` reports is on AC and charged. Honest sizing: **45–135 rows**
are genuinely un-performable by any agent. **This is the only lever that touches the floor.**

**L4 · Stop the Stop-hook coercion filing into the operator inbox — AGENT + one config decision.**
Either raise the filing bar (require a falsifier) or route agent-capable steps to `cc-backlog add`
(open) rather than `needs` (blocked). −3.1/day permanent inflow into the floor. The store carries its
own proof the misfiling is real: id `3f174ae7f254`, closed *"Refiled as AGENT work — this was
mislabeled operator-owned."*

**L5 · Split the board and stop reporting one number — OPERATOR DECISION, 5 minutes.**
Define zero as **two** targets: agent board (303) and operator floor (198). Converts an unmeasurable
date into a measurable one at zero engineering cost, and removes the ledger's biggest distortion —
**the whole-pool series is flat only because a falling agent board and a rising operator floor
cancel.**

**L6 · Cap the drain lane's own document generator — AGENT, ~2 h.** Rotate
`docs/plans/BACKLOG_DRAIN_24_7.md` (1.76 MB) and retire the 187 methods. **Effect on the date: ZERO.**
Listed last deliberately — do not let it displace L1–L3.

**Explicitly NOT recommended: adding drain capacity.** The lane already closes ~42% of everything
closed fleet-wide, runs 25.5 recycles/day, and the agent board did not move in 19 days.

---

## 6a. The cloud lane, separately: it cannot be the answer

Reported by the cloud axis and **independently re-checked by me** on the return ledger:

- **Only 5.7% of the pool is cloud-eligible** — `cc-eligible sweep` refuses 466 of 494, with 191
  refused as `ineligible-box` (local-only state a VM cannot see). **3 items are actually claimable.**
  This ceiling is a property of the work, not a tuning parameter.
- **The land arm is dead.** Verified-returned lands by day: Aug 11=3, 12=4, 14=25, 15=13, 16=59,
  17=18, **then zero through Aug 22, one on Aug 23, zero since** (51 distinct ids ever). Corroborated
  in-tree at `scripts/cloud-reconcile.sh:281`.
- **Refused items retry forever**: 2,189 return events over 107 ids (mean 20.5, max 124 on one id);
  last-wins terminal state shows **59 of 107 (55%) never reach success**. Dominant cause is the land
  pipeline's own crash debris (rc 70 = 738 events) which the repo documents as recurring *"once per
  pass, forever, because nothing reaps the debris."*
- **Stranded content**: 246 commits across 106 branches not on trunk by patch-id, 88 minted on
  Aug 25 alone. (My own first pass said 79/68 — it scanned only remote refs, missing 105 local
  `refs/heads/claude/*`, and wrongly excluded Aug 24–25 as "in flight" when the land arm was dead.)
- **Cloud is not free capacity** — the A/B (`docs/research/cloud-local-cost-ab-2026-08-11.md`) shows
  it bills the same Max-quota meter at 0.81× local, inside the noise. **This answers task #175.**

---

## 7. WHAT WE GOT WRONG — and where measurement is still blind

**All ten claims that reached adversarial verification were refuted or re-scoped.** The pattern is
worth naming: **every one failed the same way — a real number attached to the wrong denominator, the
wrong population, or the wrong conclusion. The counts were fine; the *folds* were not.**

1. **"6 automated `needs` mint sites ⇒ treadmill."** Site census correct. **Bearing wrong** —
   `needs` is 78.2% drained with 5 open. The launchd evidence leg was a **blind instrument**:
   `grep -l <script> ~/Library/LaunchAgents/*.plist` returns nothing for four of five scripts;
   reachability is real but only transitive.
2. **"326 re-land rows = 45.9% of `needs`."** Arithmetic reproduces; **denominator wrong** —
   `land_failure_inbox` was born 2026-08-10, so 178 of 713 `needs` adds predate the generator.
   Corrected: 61.1% within its lifetime, **4.8% of the live pool**.
3. **"153 auto-retracted rows, median life 36 minutes."** Actually **98 rows / 163 events, median
   true life 34 SECONDS**. The 36-minute figure measured the gap between separate land failures on a
   re-filed id. **Bearing inverted** — zero `claim` events across all 98 ids, so no drain capacity was
   ever consumed. This is a containment test firing correctly.
4. **"144 not-done `needs` rows have no agent-reachable exit."** Count right, inference refuted:
   **530 of 563 completed `needs` rows (94.1%) closed straight out of `blocked`**.
5. **"80 of 117 blocked rows are physical/decision gates."** Population is **152, not 117**; physical
   is **11 rows / 9 distinct acts**, not 28 (three are the same AC-power step filed thrice).
6. **"Agent-authored `needs` +6/day."** Corrected to **+3.1/day** — +6.1 is the *maximum* slope
   obtainable across all 24 candidate start dates.
7. **"1,104 blocks over 711 ids proves a recurrence brake."** `cmd_needs` writes a `block`
   unconditionally on first filing, so baseline is 1 block/mint.

**My own corrections, made during this session:**

- **`reopen` is lease churn, not rework.** 1,764 reopen events, but only **17 ids** were ever
  done-then-reopened. Reading 1,764/2,441 as a rework rate mis-folds the ledger.
- **"54 of 91 open rows point at a vanished path"** was a wrong-population artifact — dodRefs from
  *other* repos resolved against this checkout. Corrected via `git ls-tree origin/main`: **7 of 44
  (15.9%)** for claude-infrastructure, and ≥3 of those 7 are not file paths at all. True target-drift
  is under ~10%.
- **The stranded-cloud count** (79/68 → 246/106), see §6a.
- **"The pool is flat"** is true over 18 days and false over 30 (125 → 501). The load-bearing flat
  series is the **agent board** (+0.29/day over 19 d), not the whole pool.

**Correction made by the L1 dispatch itself (item `37b112d8950d`, 2026-08-25), and it is the
eleventh instance of §7's own pattern — a right number folded onto the wrong population:**

- **"The mitigation is built and 91% unapplied … a scheduling problem, not a design problem"
  (§2) is REFUTED, and with it L1's two projected effects.** `never validated: 457` counts rows
  **no probe can speak for**, not probes waiting to be run: the currency pass already runs every 6 h
  unattended (`scripts/autonomy-sweep.sh:732`), already visits every non-done row, and
  `bin/cc-premise:2991` refuses to stamp a row it did not measure *on purpose*, because stamping
  unprobed rows would drive this very headline to zero while nothing had been checked. I read a
  **capability** metric as an **execution** deficit — the exact conflation `bin/cc-backlog:4307`
  warns about in the writer's own header. Full derivation and the corrected levers (L1′, L1″) are in
  §2 and §6.

### Still blind — say "unknown", not a number

1. **Live staleness is projected, not measured.** The 54–89 figure applies *closed-row* rates to
   *live* rows. **The true live rate is UNKNOWN until L1 runs** — and per the correction above, L1
   as specified could never have measured it. It stays unknown until the ~457 probe-less rows are
   given probes one at a time (L1′), which is a different and larger piece of work.
2. **The `project` field records the worktree directory basename, not the repo.** ~100 rows are filed
   under slugs like `.desk-land-claude-fire-…`. **Every per-project census here undercounts
   claude-infrastructure by an unknown margin** — including my own 64.1% machinery figure.
3. **Value classification is keyword-based, hand-checked error rate 16.7%** (n=30). My 80.5% /
   85.3% machinery figures carry roughly ±3pp and over-count in the product direction.
4. **No shipped command reads a session's narrative back** — a fleet-wide transcript grep timed out
   at 120 s across 2,846 transcripts, so "how much re-work does a stale row cause" rests on
   completing sessions' own written verdicts.
5. **Cost is inferred, not billed.** The 4.07 B token count is measured; the dollar figure is list
   pricing applied to it.
6. **`~/.claude-next` holds 0 transcripts** while four other account roots hold 713/831/729/573.
   Unexplained; any fleet-wide transcript census may be missing a stratum.

---

## 8. Reproduction

```
wc -l ~/.claude/autonomy/backlog.jsonl                 → 14,249
jq -c . ~/.claude/autonomy/backlog.jsonl >/dev/null    → rc 0 (0 malformed)
bin/cc-backlog list --blocked | grep -c '^blocked'     → 198
bin/cc-backlog freshness                               → never validated 457 of 501; commits since filing p50 415, max 3253
bin/cc-eligible sweep                                  → 494 non-done; eligible 28; ineligible-box 191
```

Folds are state-set by `add|reopen|unblock|claim|done|block` **only** — `falsify|link|venue|update`
are **not** states, and folding on the raw last event is the documented trap
(`bin/cc-backlog:5347`). Scripts: `scratchpad/{fold,trend,drift}.py` (this session).

Workflow run `wf_63410424-45d` — 12 recon axes, 10 adversarial verifiers, 1 synthesis; 23 agents,
4,133,060 subagent tokens, 817 tool uses. Journal: `subagents/workflows/wf_63410424-45d/journal.jsonl`.
