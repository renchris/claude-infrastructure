# A6 — Design record of the cc-backlog drain pipelines, audited against live state

**Audited 2026-09-22T06:00–06:30Z · read-only · trunk `e3f7a2e7c` · live layer `LIVE_LAG=1`, no breach
(so every script read below IS the one that runs — all per-file symlinks into this checkout).**

---

## 1 · Headline

**The machinery is ~90% built and ~55% in force. Nothing named in these eight plans is missing from
the tree; what is missing is ENFORCEMENT and a LIVING LANE.**

| | count |
|---|---|
| concrete mechanisms named across the 8 plans and resolved against the tree | **47** |
| BUILT and demonstrably in force today | **26 (55%)** |
| BUILT but INERT — present, wired, and structurally unable to act | **13 (28%)** |
| PARTIALLY BUILT — the mechanism exists, its stated property does not | **6 (13%)** |
| PROSE-ONLY — named, never built | **2 (4%)** |

Only **2 of 47** identifiers are prose-only (`bin/foo.sh`, an illustrative placeholder; and
`CC_DISPATCH_READY_GATE=enforce` as an operating state). The dominant failure is not vapour — it is
**built-and-inert**: a detector that computes the right verdict and files nothing, a gate that
computes the right refusal and admits anyway, a lane whose four scripts all pass their suites and
which has been DEAD for 12.3 days.

**The three facts that decide the program:**

1. **Lane B (the local drain, BACKLOG_ZERO's whole deliverable) is DEAD and has been since
   2026-09-09.** `drain-chain-assert.sh --json` → `{"verdict":"dead","why":"no-brief-no-lease",
   "live_rows":350,"brief_age_s":1063311}`. Newest brief is `fire-drain-infra-recycle333.txt`,
   2026-09-09 17:41. Telemetry agrees independently: `lane-stalled lane=local-drain age=296h`.
2. **The detector for exactly that state has run every ~10 min throughout and filed NOTHING**
   (mechanism in §3, claim R1).
3. **The "open" queue really did drain — to 10 rows, of which only 2 are in the dispatch set.** The
   pile did not go away; it moved. `open=10 · blocked=340 · LIVE=350` against a peak of 617 on
   2026-09-04. **The residue is 340 operator-owned blocked rows and 49 open decision packets.**

---

## 2 · Claims ledger

Legend: **BUILT** = present and acting · **INERT** = present, wired, cannot act in the current state ·
**PARTIAL** = exists but its stated property does not hold · **PROSE** = never built.

### 2.1 BACKLOG_DRAIN_24_7.md (`status: open`, the self-declared SSOT)

| Mechanism | Doc ref | Verdict | Evidence |
|---|---|---|---|
| Lane A: `cc-venue → cc-dispatch(300s) → cc-offload up --via api → cloud-return.sh → cloud-refusal-route.sh` | §4 Lane A | **BUILT** | all five exist; `launchctl list` shows `com.claude.dispatcher` pid 17380 and `com.chrisren.autonomy-sweep` pid 50030 loaded. Lane `cloud` has **41 closes**, first 2026-09-02, last **2026-09-22T02:43:35Z** |
| A2 "prove ONE dispatcher-driven cloud land end-to-end… until this probe passes, cloud is a paper lane" | §4 A2 | **BUILT — claim now satisfied** | 41 cloud-lane `done` records with `lane:"cloud"`. Supersedes §NEXT-PHASE's *"No dispatcher-driven cloud session has EVER been created"* (2026-08-11) |
| A4 "Keep `CC_DISPATCH_VENUE_ONLY=cloud` on the DAEMON" | §4 A4 | **NOT IN FORCE** | live argv is `export PATH=… ; export CC_DISPATCH_PROJECT="claude-infrastructure"; export CC_FIRE_CLOUD=on; exec …/cc-dispatch --once` — **no `VENUE_ONLY`**. Live plist byte-identical to `launchd/com.claude.dispatcher.plist`. Routing last 2 d: **45 local / 9 cloud** |
| Lane B: chained self-recycling goal-armed local session (B1) | §4 Lane B | **INERT** | `drain-recycle-fire.sh` (377 ln) + suite (35 tests) exist and are live-symlinked; the chain stopped at recycle #333 on 2026-09-09. 34 briefs on disk, none since |
| B2 freshness-at-claim (run the falsifier against pristine trunk before working a row) | §4 B2 | **PARTIAL** | `cc-premise` runs at claim (937 `premise` records, all 2026-09-11→now). But `cc-backlog freshness`: **317 of 350 live rows NEVER validated (90.6%)**; commits-since-filing p50 **1,667** |
| B4 blocked-row platter via `cc-do`/`operator-readout` | §4 B4 | **BUILT** | `bin/cc-do` (549 ln), `hooks/operator-readout.sh` (1664 ln) both present and wired |
| B5 conservation: each recycle closes ≥ it files | §4 B5 | **INERT** | enforced only inside the recycle brief + goal; no recycle since 09-09, so unenforced for 12 d |
| `scripts/drain-chain-assert.sh` — the liveness detector | §6, "IMPLEMENTED 2026-08-16" | **INERT** (see §3 R1) | exists (545 ln), called from `autonomy-sweep.sh:544` as `--file`, computes `dead` correctly — and files nothing |
| `scripts/backlog-flow-assert.sh` — the weekly flow report | §6, "IMPLEMENTED 2026-09-08" | **BUILT** | `--json` → `{"verdict":"net-positive","added":224,"closed":221,"net":3}`; journalled into the sweep's `backlog-health` IDL row every tick |
| §5 exit gate, probe 2: "one recycle boundary crossed unattended" | §5 | **REFUTED as a standing property** | the chain crossed ~333 of them and then stopped; nothing restarted it |

### 2.2 BACKLOG_ZERO_2026-09-04.md (`status: complete`, `closed: 2026-09-07`)

| Mechanism | Doc ref | Verdict | Evidence |
|---|---|---|---|
| `scripts/drain-brief.template.md` (≤150 ln, anti-accretion ratchet) | §3 | **BUILT** | 96 lines, under the 200-line refusal bound |
| `scripts/drain-brief.sh` | §3 | **BUILT** | 176 ln; `tests/drain-brief.bats` **14 tests** |
| `scripts/drain-pick.sh` | §3 | **BUILT** | 113 ln; `tests/drain-pick.bats` **7 tests** |
| `scripts/drain-recycle-fire.sh` + `closed_pre >= min` goal floor | §3 | **BUILT, UNUSED** | 377 ln; `tests/drain-recycle-fire.bats` **35 tests**. 14+7+35 = **56**, doc claims "46 tests" — under-claimed, not over |
| W1 landing sha `89a020f08` | Phase 0 | **VERIFIED** | `git merge-base --is-ancestor 89a020f08 origin/main` → YES; `89a020f08 2026-09-04 feat(drain): the local lane's brief is generated from a template…` |
| W2a: DROP as a discharging remedy in `hooks/dispatch-assert.sh` | Phase 0 W2a | **BUILT** | file present (259 ln) |
| W3-F: `thrash-block-recover.sh` "wired" (was built with zero callers) | Phase 0 W3, §1.1a | **BUILT — the 2026-09-04 "zero callers" claim is now false** | callers: `scripts/autonomy-sweep.sh`. Same for `branch-prune-landed.sh` (callers: `autonomy-sweep.sh`, `cloud-retire-terminal.sh`) |
| Frozen scope: "closes ≥ files over `backlog-telemetry.sh`'s rolling window" | Scope (frozen) | **NOT MET TODAY** | see §3 R2 |

### 2.3 BACKLOG_CONSOLIDATION_2026-08-09.md (`status: superseded`, closed 2026-08-14) — the READINESS gate

| Mechanism | Doc ref | Verdict | Evidence |
|---|---|---|---|
| R1 · readiness conjunction at the `cc-dispatch` admission seam | §READINESS R1, W1 | **BUILT** | `bin/cc-dispatch:1354` `READY_GATE="${CC_DISPATCH_READY_GATE:-advisory}"`; `:2449` computes, `:2469` enforces, `:1592` journals |
| R2 · `readyAt` keyed on trunk sha, voided by a path-intersecting diff | §READINESS R2 | **BUILT** | `:1386-1401` (`readyAt` scan), `:1597-1600` (`idl_readiness`) |
| R3 · advisory-first, then flip to enforcing | §READINESS R3 | **PARTIAL — the flip never happened** | 226 readiness verdicts journalled today, **`gate:"advisory"` on 226 of 226** |
| R4 · the second screen (filing-day discrimination) | §READINESS R4, W2 | **BUILT** | `bin/cc-premise` carries `filing_day_screen` / `ANTI-COVERAGE` (17 hits); `tests/cc-premise-filing-day.bats` present |
| R5 · fix the ratchet instrument (dispatchable denominator, floor guard, re-baseline) | §READINESS R5, W0 | **BUILT, PERMANENTLY RED** | `scripts/backlog-ratchet.sh --assert` → **rc 1**, `coverage 22.2% (2 of 9 probeable; 10 live) · high-water 69.0% (NOT raised — denominator 9 < floor 20)` |
| R6 · consolidation actuator `--fold [--apply]` | W3 | **BUILT** | `scripts/backlog-consolidation-trigger.sh` (400 ln), called from `autonomy-sweep.sh` |
| R7 · `needs` condition-keyed so recurrence UPDATES not MINTS | W3 | **BUILT** | `cc-backlog needs` re-files onto the live row; the `add` arm's done-latch path is at `bin/cc-backlog:2155` |
| `CC_DISPATCH_READY_GATE=enforce` as an operating state | closing section | **PROSE-ONLY** | never set in any plist, any settings file, or any live process |

### 2.4 CLOUD_BACKLOG_PIPELINE.md (`status: complete`)

| Mechanism | Doc ref | Verdict | Evidence |
|---|---|---|---|
| `cc-offload up --via api` + `cloud-create-api.py` | §1 | **BUILT** | `bin/cc-offload` 999 ln, `scripts/cloud-create-api.py` 674 ln |
| `cloud-return.sh` auto-land | §1 | **BUILT** | 1288 ln; called by `autonomy-sweep.sh` and `com.chrisren.autonomy-sweep.plist` |
| `cloud-refusal-route.sh` (W3 refusal loop) | §6/W3 | **BUILT** | 631 ln; caller `autonomy-sweep.sh` |
| `cloud-reconcile.sh` | §13 | **BUILT, MANUAL ONLY** | 984 ln; `CONFIRM=1` path, unscheduled — as DRAIN_CIRCUIT §1.1 already corrected |
| Wave table W2 (management rails) / W4 (cost A/B) unticked in Phase 0 | Phase 0 | **PARTIAL bookkeeping** | both are marked DONE in the body (`§6 · W2 … built (2026-08-11)`, `2026-08-11 — W4 DONE`) but never ticked in the wave table. Table and body disagree |
| whole document `status: complete` | frontmatter | **REFUTED by an open operator decision** | `cc-decide` packet **`663522aa67b1`** is OPEN: *"Retire, repair, or redesign the 24/7 cloud backlog lane"* |

### 2.5 AUTONOMY_DISPATCH_V2.md (`status: in-progress`)

| Mechanism | Doc ref | Verdict | Evidence |
|---|---|---|---|
| S5 · kick-on-write, `CC_BACKLOG_KICK` default on | §3 S5 | **BUILT** | `~/.claude/autonomy/.dispatch-kick` touched 2026-09-22 00:59 |
| A2 · decision within 300 s of add | §7 A2 | **UNMEASURABLE as specified** | of 110 adds since 09-19, only **2** ever entered the decision population (the rest born `blocked` or in a non-dispatched project). n=2: 16 s and 34,343 s. The criterion's denominator no longer exists |
| A11 · activation is real | §7 A11 | **VERIFIED** | label loaded (pid 17380), `/tmp/claude-dispatcher.stderr.log` non-empty and current |
| F15 · "discovery refills a queue nothing drains" | §5 F15 | **STILL LIVE, now self-referential** | `cc-discover` C2 `plan-open` has minted **475** `advance <plan>` rows all-time, **30** of them naming these very pipeline docs (e.g. `70f0001c657b` ← BACKLOG_DRAIN_24_7, `c18e7ea9e6b1` ← DRAIN_CIRCUIT, `64c150ba2a8e` ← BACKLOG_ZERO). Five of the eight pipeline plans are `open`/`in-progress`, so **the drain pipeline's own plan docs are inflow generators into the drain pipeline** |

### 2.6 MACHINE_CAPACITY_V2.md §12.1 · DRAIN_CIRCUIT · BACKLOG_SELF_DRAINING

| Mechanism | Doc ref | Verdict | Evidence |
|---|---|---|---|
| `capacity_gate()` covers every spawn path | MACHINE_CAPACITY_V2 §12.1 | **PARTIAL→CLOSED-BY-ASSERTION** | §12.1's bypass table is superseded by `tests/capacity-admit-coverage.bats`; `scripts/lib/capacity-admit.sh` 1528 ln present. The doc says *"read that suite, not this table"* — correct discipline, and the table is still printed above it |
| `cc-reaper` whitelist gap eating `cloud-return.sh` | DRAIN_CIRCUIT §1.1 | **BUILT + self-corrected** | the doc's own 2026-09-02 correction records the killer stopped 08-26, five days before the fix landed — kept rather than rewritten |
| `cloud-lane-liveness.sh`, `drain-chain-assert.sh`, `rotate-autonomy-logs.sh`, `self-path-lint.sh`, `branch-prune-landed.sh` | DRAIN_CIRCUIT §3 | **ALL BUILT + called** | caller census run; none has zero callers |
| W1 · "every open row carries a currency verdict … with a `lastValidated` fact" | SELF_DRAINING §3 W1 ✅DONE | **PARTIAL** | the field is a DERIVED projection (`bin/cc-backlog:5435`, `.v.ts`), never a stored event — correct by design (`:915`). But `cc-backlog freshness` reads **317 of 350 never validated** |
| W4 · drain (the only unticked wave) | SELF_DRAINING §3 W4 | **INERT** | W4 IS Lane B, and Lane B is dead |
| `bin/foo.sh` | CLOUD_BACKLOG_PIPELINE | **PROSE** | illustrative placeholder, no file — noted for completeness, not a defect |

---

## 3 · Refuted completion claims

### R1 · "IMPLEMENTED 2026-08-16 → `drain-chain-assert.sh` … the row it files carries `--assert` as its falsifier and retires itself when the chain restarts" (BACKLOG_DRAIN_24_7 §6)

**REFUTED for the current state — this is the detector's FOURTH blindness, and it is new.**

The chain died 2026-09-09. `--file` has run every autonomy-sweep tick since (≈1,700 runs). It has
filed **nothing**. Mechanism, read out of the two scripts:

- `drain-chain-assert.sh:326-339` — on `dead`, calls
  `cc-backlog add --condition local-drain-chain-dead …`, redirects **both streams to `/dev/null`**,
  and `exit 0` on failure *and* on success.
- `bin/cc-backlog:2155` — an `add` whose condition key is **done-latched** prints
  `WARNING — this event-key is already DONE; NOT re-opened` to **stderr** and appends no record.
- The only `local-drain-chain-dead` row ever created is `02d53c4b4078`, filed 2026-09-01 and
  **closed 2026-09-04** (`done`, evidence: *"falsifier passed rc=0 (silent) … I am recycle #301"*).
  `grep -o '"condition":"[^"]*drain[^"]*"' backlog.jsonl | sort | uniq -c` → `1 local-drain-chain-dead`.

So the condition key was latched DONE five days before the chain actually died, and every later
conviction has been swallowed. Corroborating: none of the 10 open rows names the dead chain, and the
sweep journals `drain_chain_rc: "0"` on every tick — which is **`--file`'s only possible exit code**
(fail-open by construction), so that IDL field can never convict. `fail-safe-default-mimics-the-
healthy-state`, in the field.

Prior three blindnesses, all recorded in §6 and all cured: wrong invariant (2026-08-18), brief-glob +
constant cloud-lease disjunct (2026-08-31), downstream-of-the-900 s-bound (2026-09-16, "the death was
found by a human"). The cure for #4 is not in the tree.

### R2 · BACKLOG_ZERO `status: complete / closed: 2026-09-07`, frozen scope "closes ≥ files over the rolling window"

**REFUTED on both halves, by the instruments the plan itself nominated.**

- `backlog-flow-assert.sh --json` → `verdict: net-positive`, `added 224 · closed 221 · net +3`.
  `--assert` exits **1** on that verdict. The acceptance criterion fails.
- The lane the plan rebuilt (W1 scripts, W5 go-live at recycle #300) ran to #333 and stopped two days
  after the plan closed.

⚠️ **The two shipped instruments disagree today and the criterion sits at the noise floor.**
`backlog-telemetry.sh` prints `ROLLING 7-DAY filed=220 closed=221 net=-1` (reads *"draining"*) while
`backlog-flow-assert.sh` prints `net +3` (reads *"net-positive"*) — same store, same hour. The
difference is the window definition (telemetry: last 7 days *with events*; flow: last 604,800 s), and
|net| ≤ 3 against ~220 means **the window choice, not the pipeline, decides the verdict.** Do not
quote either as settling the goal.

### R3 · "the live dispatcher runs `CC_DISPATCH_VENUE_ONLY=cloud` (read from launchd argv)" — `bin/cc-dispatch:1043` and `:3269`, and CLOUD_BACKLOG_PIPELINE's "do not re-derive" fact table

**REFUTED.** Live argv (`plutil -extract ProgramArguments.2 raw`) carries only `PATH`,
`CC_DISPATCH_PROJECT`, `CC_FIRE_CLOUD=on`. This is not cosmetic: both call sites use that premise as
a **load-bearing safety argument** — `:1043` argues the two `git fetch` calls "never run on the box
that actually fires", and `:3269` argues the worktree-freshness gate "is irrelevant to the only lane
it admits". Both arguments are now void. Venue routing over the last 2 days is **45 local / 9 cloud**.

Knock-on: open decision packet **`ff24ce1f7808`** (*"The standing backlog dispatcher only fires work
into Claude Cloud… the cloud-only filter parks 96% of the queue every pass"*) **has a false premise
today** — the filter is off. It should be re-derived before it is answered.

### R4 · READINESS W1 "advisory-first … then flip to enforcing"; "the cure is item CITATIONS"

**The flip never happened and the gating metric moved the wrong way.**
Folded from `~/.claude/autonomy/idl.jsonl` over today's 3.4 h window (the IDL rotates daily):

| | 2026-08-11 (W1's measurement) | **2026-09-22 (this audit)** |
|---|---|---|
| would-block rate | 60% (pass 2) | **73.5%** — 166 void / 60 ready of 226 |
| dominant void reason | `cites-nothing`, 6 of 10 | **`cites-nothing`, 164 of 166 (98.8%)** |
| gate mode | advisory | **advisory on 226 of 226** |

The dispatcher plist's hazard block (line 75-85, live file byte-identical to the repo SSOT, last
edited 2026-09-07) still reads *"The readiness conjunction that closes this is **filed, not built**:
… waves d73a772a8468 / 0e8a10c501af / df003b95630b."* **All three waves are CLOSED in
`backlog.jsonl`:**

| wave | last event | evidence |
|---|---|---|
| `d73a772a8468` (W1 conjunction) | **done 2026-09-05T06:04:26Z** | *"W1 landed by CONTENT: `git show origin/main:bin/cc-dispatch \| grep -c CC_DISPATCH_READY_GATE` = 3, readyAt = 10"* |
| `0e8a10c501af` (W2 second screen) | **done 2026-08-16T23:18:47Z** | `cloud-worker-work-upstream:6c9745b61` |
| `df003b95630b` (W3 fold + brake) | **done 2026-08-17T09:12:05Z** | cloud `session_01HPjoZESE7rpqvWFETibh1V` |

So the plist's stated reason is stale by 5–36 days. The accurate statement is **"built, advisory-only,
never flipped"** — and the plist's own revert condition (*"Do that only once the readiness gate is
enforcing, or the two reasons above are both still true"*) therefore reads on a fact nobody re-checked.

### R5 · READINESS W0 "the instrument" (`backlog-ratchet.sh`: dispatchable denominator + floor guard + re-baseline)

**All three delivered — and the alarm has been RED continuously for 41 days, now for a NEW reason
that the drain's own success created.**

`bash scripts/backlog-ratchet.sh --assert` → **rc 1**:
`coverage 22.2% (2 of 9 probeable; 10 live) · high-water 69.0% (NOT raised — denominator 9 < floor 20)`.

The floor guard (R5's own deliverable, built to stop a degenerate read latching an unreachable target)
now **prevents the high-water from ever being re-baselined downward**, because the open queue drained
to 10 rows and the probeable denominator is 9 — below the floor of 20. The ratchet is therefore
mechanically incapable of going green at any level of effort. This is READINESS measurement #2's
*"a ratchet whose healthy state the population cannot attain"* re-manifesting through its own cure.

It is not a runaway generator: it folds onto one condition-keyed row (`e08ad9ab1ff6`, filed
2026-08-12) — which was **closed 2026-08-16** and has therefore been swallowed by the same
done-latch as R1 ever since. `autonomy-sweep` journals `ratchet_rc:"1" ratchet_filed:"filed"` on
every tick; the second field is aspirational.

### R6 · BACKLOG_SELF_DRAINING W1 ✅DONE — "every open row carries a currency verdict … never-validated 536→387"

**PARTIAL.** The pass runs (937 `premise` records, all since 2026-09-11). But by the shipped
instrument, `bin/cc-backlog freshness`:

```
never validated    : 317 of 350 live rows   ← the number that must fall
validated          : 33   (clear=32 · suspect=1)
commits since filing: p50 1667 · p75 2517 · p90 3479 · max 5056   (over 350 rows vs e3f7a2e7c)
```

The **absolute** count improved (387 → 317) and the **rate got worse**: 68% → **90.6%** never
validated, because the denominator collapsed faster than the numerator. A median live row was filed
**1,667 commits** ago against a readiness gate that is advisory. That pairing — p50 1,667 commits of
drift and a 73.5% would-block rate that blocks nothing — is the STALENESS hazard, unmitigated, in
numbers.

---

## 4 · Published numbers — every one has a date, several have already decayed

🚨 **Re-derive, never re-quote.** The command in the last column is the one that re-derives it.

| Figure | Value as published | As of | Status today | Re-derive with |
|---|---|---|---|---|
| live rows | 568 (269 open · 298 blocked) | 2026-08-16 | **350 (10 open · 340 blocked)** | `scripts/backlog-telemetry.sh` |
| live rows | 612 (371 open · 241 blocked); peak 617 | 2026-09-04 | superseded | same |
| peak LIVE | — | — | **617 on 2026-09-04** (still the all-time peak) | same |
| rolling 7 d flow | filed 105 · closed 51 · **net +54** | 2026-09-04 | **filed 220 · closed 221 · net −1** (telemetry) / **+3** (flow-assert) — see R2 | `scripts/backlog-telemetry.sh` · `scripts/backlog-flow-assert.sh --json` |
| conversion 7 d | 173 claims / 23 ids → **8.6% done**, `verdict=drain-futile` | 2026-09-04 | **958 claims / 113 ids → 93.8%, `verdict=drain-converting`**, reclaim 8.4× | `scripts/backlog-telemetry.sh` |
| effort ratio | 264 commits vs 46 closes = **5.7×** (ceiling 10×) | 2026-09-04 | **602 commits vs 210 closes = 2.8×**, `effort-productive` | same |
| close attribution | cloud **3** · local-drain 65 · session 81 · land 57 · sweep 13 | 2026-09-04 | **cloud 41 · local-drain 397 · session 547 · land 85 · sweep 74**; coverage 31.4% | same |
| cloud lane throughput | 29.9 fires/d → 1.3 returns/d → **0.7 closes/d**; pending 543 (+23.5/d, ~400-day horizon) | 2026-09-04 | not re-derived here — `cc-cloud` census needed | `bin/cc-cloud` declarations fold |
| cloud land success | **0 in ~1,000 attempts** (rc 758×70 · 239×65) | 2026-09-04 | **refuted** — 41 cloud closes, last 2026-09-22T02:43Z | `lane:"cloud"` fold over `backlog.jsonl` |
| cloud dispatch delivery | 40 LANDED (36%) · 32 STALLED · 32 NOT-STARTED · 7 ABANDONED · 1 BOOTING, n=112 | ~2026-08-2x | **half-life short** — the landing arm changed twice since | `bin/cc-cloud` declaration census |
| dispatcher argv | `CC_FIRE_CLOUD=on CC_DISPATCH_VENUE_ONLY=cloud`, marked *"do not re-derive"* | 2026-08-11 | **REFUTED** (R3) | `plutil -extract ProgramArguments.2 raw ~/Library/LaunchAgents/com.claude.dispatcher.plist` |
| local pane spawns | "frozen at 191" | 2026-08-11 | stale — the filter is off | `grep -c '→ fired: claude' ~/.claude/logs/dispatch-fires.log` |
| venue split of the live queue | 45 cloud · 236 local · 31 unlabelled | 2026-08-11 | **routing events last 2 d: 45 local · 9 cloud** | fold `event=="venue"` on `venuePlan` |
| readiness would-block | **60%** (pass 2), 6 of 10 `cites-nothing` | 2026-08-11 | **73.5%**, 164 of 166 `cites-nothing` | fold `action=="readiness"` over `~/.claude/autonomy/idl.jsonl` |
| open rows without a venue label | 219 → retired → 312 open+claimed, 281 with `venuePlan`, 31 without | 2026-08-11 | **third decay already recorded in-doc** | `cc-backlog list --open --json` |
| falsifier coverage | 51.5% (157 of 305), high-water latched 100.0% | 2026-08-11 | **22.2% (2 of 9 probeable), high-water 69.0%, denominator below floor** (R5) | `scripts/backlog-ratchet.sh --assert` |
| never-validated rows | 536 → **387** | 2026-08-12 | **317 of 350 (90.6%)** | `bin/cc-backlog freshness` |
| `needs` inflow | 132 of the last 225 adds are `needs`, born blocked | 2026-08-11 | **still the dominant generator**: adds since 09-21 = needs 13 · blank 4 · postland-verify 5 | fold `event=="add"` on `source` |
| `cc-reaper` TERMs on `cloud-return.sh` | 153 | 2026-09-01 | **already self-corrected in-doc**: binned by day it ran 08-19→08-26 then zero | `~/.claude/logs/cc-reaper.log` |
| `local-drain-chain-dead` detections | "filed ZERO rows at any status across its entire deployed life" | 2026-08-18 | **still 1 row ever, and it is closed** (R1) | `grep -o '"condition":"[^"]*drain[^"]*"' backlog.jsonl \| sort \| uniq -c` |
| §2b-v detector run rate | "has run 0 times/day since 2026-09-08" | 2026-09-17 | **fixed** — hoisted; `drain_chain_rc`/`backlog_flow_*` present in every recent `backlog-health` row | `grep '"backlog-health"' ~/.claude/autonomy/idl.jsonl \| tail` |

---

## 5 · "Drain to zero" — the goal, its criterion, and its instrument

**Defined by:** `docs/plans/BACKLOG_DRAIN_24_7.md`, title line and frozen scope —
*"drain cc-backlog to zero, and keep it there… such that the backlog trends DOWN (closes ≥ files,
week over week) instead of net-filing."* Restated verbatim in BACKLOG_ZERO's frozen scope.

**The acceptance criterion is NOT a literal zero.** It is a *slope*: closes ≥ files over a rolling
week. `BACKLOG_DRAIN_24_7 §1.1` explicitly rejects the literal reading — *"No whole-backlog zero was
ever claimed on disk. Every zero was per-EFFORT and counted only `open`, silently excluding
`blocked`"* — and §6 fixes the reporting format as `<effort>: N open / M blocked (K operator-gated)`.

**The instrument EXISTS and is shipped, twice over:**
- `scripts/backlog-telemetry.sh` (647 ln, read-only, nominated by BACKLOG_ZERO's frozen scope)
- `scripts/backlog-flow-assert.sh` (BACKLOG_DRAIN §6's fourth invariant, landed 2026-09-08 `5000db42`,
  wired into `autonomy-sweep.sh` and journalled to the `backlog-health` IDL row every tick)

So this is **not** a phrase without an instrument. It is the opposite failure: **two instruments, one
question, disagreeing verdicts on the same day** (R2), because the criterion's margin (|net| ≤ 3) is
smaller than the difference between their window definitions. Neither is wrong; the criterion is
under-specified.

**Progress against it, honestly:** the OPEN queue is drained — 10 rows, and only 2 of them
(`d6d7edef60a3`, `52e837e8f22d`) are in the dispatcher's set; the other 8 are `sevenrooms-bridge`(6),
`personal`(1), `voiceink`(1), which the dispatcher logs as `project-not-dispatched` every pass. The
BLOCKED tail grew 267 → 340 over the same 13 days. **The pipeline did not drain the backlog; it sorted
it** — into a near-empty agent-workable queue and a 340-row operator-owned pile the machine has no
verb for.

---

## 6 · The operator-owned residue that gates these pipelines

**49 open decision packets** (`bin/cc-decide list --open`). Directly gating the drain pipelines:

| id | class | the question |
|---|---|---|
| **`663522aa67b1`** | C | **Retire, repair, or redesign the 24/7 cloud backlog lane.** Cites the 2026-09-10 frontier campaign: cloud draws the same Max quota (p=6.5e-06); 12.8% yield is a fixable landing arm; repaired it lands 4–10 rows/day at $5–6 vs local's 18 on the same meter; retiring must be SEQUENCED (settle 14 unretired declarations + stop `cc-venue` relabelling before removing `CC_FIRE_CLOUD`, or 6 rows strand in both lanes). **This is why `CLOUD_BACKLOG_PIPELINE.md status: complete` cannot be taken at face value.** |
| **`ff24ce1f7808`** | C | Should the dispatcher fire local worker sessions again instead of cloud-only? **Premise is stale (R3)** — the cloud-only filter is already off. Needs re-derivation before it is answered. |
| `0f354fc4d693` | C | Who owns an orphaned class-C packet? 28–29 open, median 13 d, p90 50 d; only 1–3 authoring sessions alive; `wrap-ledger.sh:900` joins ⛔ on `session_sid`, so **96% can never render ⛔ again** — i.e. the decision queue itself has no live surfacing path |
| `4194644aea26` | C | May the unattended deploy job restart an out-of-date daemon by itself? |
| `f7f296389c6e` | C | Ratify the C10 rescope split (env-var + hook-registration migrations land autonomously). Migration 0014 has waited 22 days; this gates staged migration 0022 |
| `a3b5aadfb217` | C | GO LIVE — two commands, both landed and gate-green, waiting on the operator |
| `b6b6879b8650` | C | Should our own PreToolUse `ask` verdicts (11 sites) return `deny` in a FIRED session? The dialog is what wedged Lane B panes |
| `ba1a148a0e2f` / `bed4ce4ec791` / `f6e4c09d07e3` | C | Scratch-write permissions and who may answer a worker's permission prompt — five panes frozen 16–32 min on this class |
| `560878f571fa` | B | Shared-checkout commit-gate escape hatch — **due 2026-09-24T12:00Z** |
| `b008ba266e4c` | B | Memory-pressure handler killing wake-path watchers — **due 2026-09-22T12:00Z (today)** |
| 5 × `shipland-esc-*` | B | ship-land refused 5 branches on escalation-surface patterns; each is stranded work |

**340 blocked backlog rows** (`bin/cc-backlog list --blocked | wc -l` → 340). Composition (by my own
fold over the record trail — the shipped fold reports 340 and mine reports 108 terminal-`block` rows,
so **treat the composition as indicative and the 340 as authoritative**): the dominant source is
`needs` (operator-only steps), 48 carry an executable `run` field (one-command operator actions
routable through `cc-do`), and only 14 carry a falsifier — so most of the pile cannot self-retract.

**Named example, still open and still blocking:** `02e67ee88123` — 14 guardrails wired in some config
dirs and missing in others; fix requires the staged C10 migration 0021.

---

## 7 · Method notes and residual uncertainty

- **Every script read is the one that runs.** `wrap-ledger.sh --machine` → `LIVE=1 LIVE_SRC=ok
  LIVE_LAG=1 LIVE_ADDS=0`, and all 10 drain-critical files under `~/.claude/` are per-file symlinks
  into this checkout. No landed-≠-live gap contaminates any verdict above.
- **I did not re-implement the fold.** Where my own Python fold disagreed with a shipped tool
  (blocked: 108 vs 340; `lastValidated`: absent vs the `freshness` report's 33 validated), I report
  the shipped tool's number and flag mine as indicative. Two of my early measurements were wrong for
  exactly this reason and are corrected above.
- **Unmeasured, named rather than guessed:** (a) the cloud lane's current fires/returns/closes per
  day — I confirmed 41 lifetime closes but did not census `cc-cloud` declarations, so
  CLOUD_BACKLOG_PIPELINE's `36% LANDED / 29% NOT-STARTED` stands un-refreshed; (b) whether Lane B's
  death has a cause in the pane (wedged modal vs quota vs clean exit) — `drain-chain-assert` reports
  `pane:null sid:null`, and resolving it needs the handoffs/registry join I did not run; (c) the
  `local-drain` lane's 397 lifetime closes vs BACKLOG_ZERO's 2026-09-04 figure of 65 — the jump is
  real but I did not attribute it to links #300-#333.
- **The adversarial pass changed three conclusions.** (1) I nearly reported `thrash-block-recover.sh`
  and `branch-prune-landed.sh` as zero-caller on the plan's word — a caller census refuted it.
  (2) I nearly reported acceptance criterion A2 as failed on a 2-of-110 join before checking that 108
  of those adds never enter the decision population at all. (3) I nearly reported `lastValidated` as a
  missing field on a store grep, before finding `bin/cc-backlog:915` explaining why it is derived and
  running the shipped `freshness` report instead.

---

## 8 · Every command run

```bash
# inventory
ls docs/plans/ | grep -iE 'backlog|autonomy|dispatch|cloud|zero'
grep -ril "drain to zero\|drain-to-zero\|BACKLOG_ZERO" docs/
ls docs/plans/backlog-consolidation-2026-08-09/ docs/plans/readiness-2026-08-11/
ls docs/research/ | grep -iE 'backlog|drain|autonomy|dispatch|zero|cloud'
ls docs/activation/
git log -1 --format=%ad --date=short -- <each plan>
wc -l <each plan>

# claims ledger — identifier extraction and existence
grep -oE '(scripts|hooks|bin|tests)/[A-Za-z0-9_./-]+\.(sh|py|md|bats|jsonl|json)|\bcc-[a-z-]+\b' <each plan> | sort -u
for p in <39 script paths>; do [ -e "$p" ] && wc -l "$p"; done
for b in <27 cc-* tools>; do [ -e "bin/$b" ] && wc -l "bin/$b"; done

# caller census (the "built with zero callers" check)
grep -rl "<script>" --include='*.sh' --include='*.py' --include='*.plist' --include='cc-*' scripts bin hooks launchd

# plan reading
sed -n '583,972p' docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md
sed -n '1,140p'  docs/plans/BACKLOG_ZERO_2026-09-04.md
sed -n '7,88p;32396,32601p;32940,33079p' docs/plans/BACKLOG_DRAIN_24_7.md
sed -n '1,60p;530,560p;1195,1215p' docs/plans/CLOUD_BACKLOG_PIPELINE.md
sed -n '1,70p'   docs/plans/DRAIN_CIRCUIT_2026-09-01.md
sed -n '328,356p' docs/plans/AUTONOMY_DISPATCH_V2.md
sed -n '1,40p;179,200p' docs/plans/BACKLOG_SELF_DRAINING_2026-08-12.md
grep -n '## .*12\.1' -A30 docs/plans/MACHINE_CAPACITY_V2.md
head -80 docs/activation/dispatcher-activate-snippet.md
head -30 docs/activation/discovery-activate-snippet.md
bash scripts/find-plan.sh --status <each plan>

# live wiring
launchctl list | grep -iE 'dispatch|discovery|autonomy|reaper|deploy-live|postland'
ls -la ~/Library/LaunchAgents/
plutil -p        ~/Library/LaunchAgents/com.claude.dispatcher.plist
plutil -extract ProgramArguments.2 raw ~/Library/LaunchAgents/com.claude.dispatcher.plist
plutil -extract ProgramArguments raw   ~/Library/LaunchAgents/com.claude.discovery.plist
diff ~/Library/LaunchAgents/com.claude.dispatcher.plist launchd/com.claude.dispatcher.plist
sed -n '55,110p' launchd/com.claude.dispatcher.plist
tail -25 /tmp/claude-dispatcher.stderr.log
git log --oneline -S'CC_DISPATCH_VENUE_ONLY' -- launchd/com.claude.dispatcher.plist

# code reads
grep -n "CC_DISPATCH_READY_GATE\|READY_SCAN\|readyAt" bin/cc-dispatch
sed -n '244,262p;1038,1048p;3264,3274p' bin/cc-dispatch
sed -n '326,345p' scripts/drain-chain-assert.sh
grep -n '\-\-file\|--assert\|MODE=\|exit ' scripts/drain-chain-assert.sh
sed -n '525,560p;1734,1770p' scripts/autonomy-sweep.sh
sed -n '2140,2165p;5420,5440p' bin/cc-backlog
grep -n "lastValidated" bin/cc-backlog

# LIVE MEASUREMENTS (all read-only)
bash scripts/backlog-telemetry.sh
bash scripts/drain-chain-assert.sh --json
bash scripts/backlog-flow-assert.sh --json
bash scripts/backlog-ratchet.sh --assert            # TRUE rc captured without a pipe
bash scripts/wrap-ledger.sh --machine
bin/cc-backlog list --open
bin/cc-backlog list --blocked | wc -l
bin/cc-backlog list --open --json
bin/cc-backlog freshness
bin/cc-decide list --open
git merge-base --is-ancestor 89a020f08 origin/main
ls ~/.claude/autonomy/fire-drain-infra-recycle*.txt | wc -l
grep -o '"condition":"[^"]*drain[^"]*"' ~/.claude/autonomy/backlog.jsonl | sort | uniq -c
grep -h '"backlog-health"' ~/.claude/autonomy/idl.jsonl | tail -3
for f in <10 drain scripts>; do readlink ~/.claude/$f; done     # live-layer parity

# python folds over ~/.claude/autonomy/{backlog,idl}.jsonl (read-only, no writes)
#  - event census, distinct-id census, field-name census
#  - the three READINESS wave ids d73a772a8468 / 0e8a10c501af / df003b95630b
#  - readiness verdict fold (state / reason / gate)
#  - cc-dispatch IDL action census + decision-record shape
#  - add-to-decision latency join (A2)
#  - venue routing fold, plan-open generator fold, blocked-pile composition
#  - lane:"cloud" done-record fold, premise-record date range
```

**Nothing was written to any store. No session was fired. No mutating verb was run.**
The only files created are this report and `/tmp/backlog-probe/ratchet.out`.
