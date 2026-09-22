# A1 — Productivity of the LOCAL cc-backlog drain lane
Measured 2026-09-22 (box clock CDT / all timestamps below are UTC unless stated). READ-ONLY probe.
Subject: `com.claude.dispatcher` launchd job → `~/.claude/bin/cc-dispatch --once` → local `handoff-fire.sh` spawn.

---

## 1. Headline verdict

**The local lane is productive but runs at ~3% of its own configured ceiling, and 87% of its
passes are structurally incapable of spawning anything.**

The three numbers that answer the question:

| | Number |
|---|---|
| Items the LOCAL lane drove to closure, **30 days** (2026-08-23 → 09-22) | **259 distinct ids** attributed (199 closed by the item's own worker worktree) — **all 259 fall in the 15.2 days after the 09-07 un-park**; the lane produced **exactly 0** in the 15 days before it |
| Items the LOCAL lane drove to closure, **IDL-instrumented window** (11.36 d, 09-10T21:21 → 09-22T06:02) | **55** ids with BOTH a `cc-dispatch fired` record AND a close by their own `<host>-wt-<id>` worker = **4.84/day** |
| Fraction of dispatcher passes that produced any work | **0.98%** of ALL passes (67 of 6,817) · **6.11%** of the spawn-capable `--once` passes (67 of 1,097) |

Three findings carry the verdict:

1. **87.4% of dispatcher passes cannot spawn by construction.** `cc-backlog add` kicks
   `cc-dispatch --decide` (`bin/cc-backlog:6994`), and `--decide` returns at step 3a with *zero
   wave-plan calls, zero claims, zero spawns* (`bin/cc-dispatch:2529`). Measured: 5,199 of 6,296
   summarised passes were `--decide`. Only the launchd `--once` job can fire.
2. **The launchd backstop delivers 96.6 passes/day, not the 288/day its `StartInterval 300` promises**
   — because the median `--once` pass takes **356 s** and the mean **560 s**, so **59% overrun the
   interval** and launchd will not overlap an instance. `launchctl print … runs = 517` over the
   5.35 d since boot = 96.6/day, matching the IDL's 1,097 `--once` passes / 11.36 d = 96.6/day exactly.
3. **The ceiling was never the binding constraint.** `free_slots` was **0 in zero of 5,766 passes**;
   `live_workers` peaked at 8 against `CEILING=12` and was **0 in 62.8% of passes**. The lane sat
   idle with capacity in hand.

The lane is *not* dead and it is *not* mis-parked: it last fired a worker **2026-09-22T04:48:02Z**
(item `1117e6f228cf` → next2, pane 496), 74 minutes before this probe.

---

## 2. Measurement tables

### 2.1 Store coverage — and the hard limit on "30 days"

| Store | Path | Coverage | 30-day question answerable? |
|---|---|---|---|
| IDL journal | `~/.claude/autonomy/idl.jsonl` + 8 `.gz` archives | **2026-09-10T21:21:06Z → 2026-09-22T06:01:33Z = 11.36 d**, contiguous, no gaps | **NO** — 18.6 of the 30 days are not retained |
| Backlog ledger | `~/.claude/autonomy/backlog.jsonl` (23,348 records) | 2026-07-18T23:23:56Z → 2026-09-22T05:56:45Z | **YES** |
| Dispatcher stderr | `/tmp/claude-dispatcher.stderr.log` | born at boot **2026-09-16 16:34 CDT** → now = 5.35 d | NO |
| Dispatcher stdout | `/tmp/claude-dispatcher.stdout.log` | **0 bytes** — the launchd path prints nothing on stdout; verdicts go to stderr + IDL. Not a death signal | n/a |

Chain integrity control: `cc-idl verify` → `OK: 8770 sealed line(s) intact · 2479 unsealed tail`, rc 0.
(Archives were **not** individually verified.)

### 2.2 Dispatcher passes per day, by disposition (IDL window)

`passes_tot` = summaries + backlog-empty early exits + pass-lock skips. `admitted` = sum of
per-pass admit verdicts. `fired_LOCAL` / `fired_cloud` are the venue split of `action:"fired"`.

| day | passes_tot | summaries | backlog-empty | lock-skip | admitted | fired_LOCAL | fired_cloud | passes that fired | spawn failures | unplaced | abstain |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-10 (partial) | 12 | 12 | 0 | 0 | 70 | 1 | 1 | 1 | 0 | 3 | 0 |
| 2026-09-11 | 506 | 447 | 56 | 3 | 3564 | 9 | 13 | 13 | 18 | 418 | 0 |
| 2026-09-12 | 446 | 430 | 14 | 2 | 4913 | 0 | 1 | 1 | 8 | 822 | 2 |
| 2026-09-13 | 470 | 437 | 32 | 1 | 4780 | 1 | 1 | 2 | 9 | 926 | 0 |
| 2026-09-14 | 454 | 427 | 25 | 2 | 4780 | 3 | 0 | 2 | 14 | 466 | 0 |
| 2026-09-15 | 448 | 423 | 25 | 0 | 4769 | 0 | 0 | 0 | 15 | 506 | 0 |
| 2026-09-16 | 534 | 490 | 40 | 4 | 5292 | 2 | 2 | 3 | 50 | 363 | 0 |
| 2026-09-17 | 783 | 740 | 43 | 0 | 7716 | 16 | 4 | 12 | 282 | 295 | 0 |
| 2026-09-18 | 916 | 831 | 85 | 0 | 1728 | 10 | 1 | 6 | 136 | 45 | 0 |
| 2026-09-19 | 772 | 707 | 64 | 1 | 1444 | 5 | 2 | 6 | 89 | 98 | 0 |
| 2026-09-20 | 545 | 496 | 48 | 1 | 1632 | 16 | 5 | 14 | 56 | 98 | 0 |
| 2026-09-21 | 748 | 665 | 82 | 1 | 1703 | 5 | 3 | 5 | 159 | 6 | 0 |
| 2026-09-22 (to 06:02) | 198 | 191 | 7 | 0 | 371 | 1 | 1 | 2 | 41 | 2 | 0 |
| **TOTAL** | **6832** | **6296** | **521** | **15** | **42762** | **69** | **34** | **67** | **877** | **4048** | **2** |

Rate: **600 passes/day**, of which **96.6/day** are spawn-capable `--once`.

### 2.3 Pass mode split — the 87% that cannot spawn

| mode | n | median duration | mean | p90 | max | > 300 s |
|---|---|---|---|---|---|---|
| `--once` (launchd; can claim + spawn) | 1,097 (17.4%) | **356 s** | **560 s** | 1,079 s | 13,077 s | **59.0%** |
| `--decide` (kick from `cc-backlog add`; zero claims, zero spawns) | 5,199 (82.6%) | 113 s | 166 s | 360 s | 13,371 s | 14.6% |

Control that `--once` ≡ launchd: since-boot summaries with `admitted_terminal != null` = **510**;
`launchctl … runs` = **517**. (Difference = early-return passes + the odd manual run.)

### 2.4 Venue classification of fires — two independent signals, perfect agreement

`cc-dispatch` writes `idl claimed … venue=cloud` **only** on the cloud path (`bin/cc-dispatch:2999`,
guarded by `if [ "$venue" = cloud ]`), and `idl fired` on **both** paths without a venue field.
Classifying by "is there a `claimed venue=cloud` for this id within 1 h before the fire" against the
independent "does the fire line carry `anchored to live pane N`" (a local-only handoff-fire artefact):

| | anchored to a pane | no anchor |
|---|---|---|
| preceded by a cloud claim | 0 | **34** |
| no cloud claim | **69** | 0 |

Zero off-diagonal ⇒ **69 LOCAL fires, 34 CLOUD fires**, no ambiguous cases.

### 2.5 What happened to each of the 69 local fires

| disposition | n | % |
|---|---|---|
| **CLOSED by its own fired worker** (`closedBy` = `<host>-wt-<id>`) | **53** | 76.8% |
| closed later by someone else | 8 | 11.6% |
| ended **BLOCKED** (needs-human row filed — a legitimate non-close) | 5 | 7.2% |
| **WASTED — the row was already `done` BEFORE the fire landed** | **2** | 2.9% |
| closed later by the cc-premise sweep, not the worker | 1 | 1.4% |

Fire → own-worker close latency (n = 54): median **0.46 h**, p25 0.24 h, p75 1.19 h, p90 6.05 h, max 11.77 h.
Bucketed: `<3 min` 7 · `3-15 min` 10 · `15-60 min` 20 · `1-4 h` 11 · `>4 h` 6.
(The 7 sub-3-minute closes are worth a separate look — they are more consistent with "the row was
already satisfied" than with work performed.)

### 2.6 Claims → closes, from the backlog ledger (30 days, the only 30-day-capable store)

Dispatcher LOCAL claims = `event:"claim"`, `role:"dispatcher"`, **no** `venue` field
(cc-dispatch deliberately omits `--venue local`; `bin/cc-dispatch:2770-2772`).

| | 30 d (08-23 → 09-22) |
|---|---|
| dispatcher LOCAL claims | **1,110** over **275 distinct ids** |
| next terminal transition = **reopen** (spawn refused, self-release) | **870 (78.4%)** |
| next terminal transition = **done** | 204 (18.4%) |
| next terminal transition = **block** | 36 (3.2%) |
| claim → done latency | median **0.78 h**, p25 0.30, p75 1.57, max 7.87 |

**Distinct items closed, attributed to a local dispatcher claim within 24 h:**

| window | days | attributed closes | of which closed by the item's own worktree | rate |
|---|---|---|---|---|
| 30-day 08-23 → 09-22 | 30.0 | **259** | 199 | 8.63 /d |
| parked sub-window 08-23 → 09-06 | 15.0 | **0** | 0 | **0 /d** |
| un-parked 09-07 → 09-22 | 15.2 | 259 | 199 | 16.98 /d |
| — of that, pre-IDL 09-07 → 09-10T21:21 (post-un-park burst) | 3.89 | 148 | 124 | **31.88 /d** |
| — of that, IDL window 09-10T21:21 → 09-22 | 11.36 | 111 | 75 | 6.60 /d |

**Attribution ceiling (adversarial check).** Of the 75 own-worktree closes the ledger attributes to
the local lane inside the IDL window, only **55 have a matching `cc-dispatch fired` record**. The
other **20** were claimed by the dispatcher, never fired by it, and later closed by something else
working in an identically-named worktree. `55` is therefore the defensible local-lane number for
that window and `75` is the upper bound.

### 2.7 Per-item claim→close latency, IDL-fired subset

n = 53 attributed: median **0.46 h**, p25 0.24, p75 1.19, p90 6.05, max 11.77.
Never-closed after a fire: **7** of 69 — 5 became `block` rows (legitimate), and **2 had literally
zero ledger records after the fire** because the row had been closed *seconds before*:
`81909b601916` (done 04:01:20Z, fired 04:04:01Z — closed by a *sibling* item's worker) and
`d03e77679af8` (done 14:14:40Z, fired **14:14:43Z** — a 3-second race).

### 2.8 Dispatcher stderr — error classes (5.35 d since boot, 2,854 lines, rc-checked)

| n | class |
|---|---|
| 517×4 | `cc-dispatch: 8 open item(s) in project(s) OUTSIDE the dispatch set …` + 3 detail lines (one per launchd run; this is how `runs=517` was corroborated) |
| 312 | `cc-dispatch: skipped <id> — its premise no longer holds (claim refused at the actuator)` |
| 306 | `cc-dispatch: /Users/chrisren/Development/.worktrees/wt-<id> was behind origin/main with nothing of its own — fast-forwarded, firing` |
| 91 | `cc-dispatch: wave-plan WALL[capacity] — re-planning N → N item(s) at the capacity it reported; N deferred.` |
| 56 | `cc-dispatch: ⚠️  wave-plan gave NO verdict (the account oracle did not answer) — N item(s) deferred` |
| 11 | `cc-dispatch: skipped <id> — landed during this pass's admission tail (claim refused)` |
| 3 | `cc-dispatch: an admission is already in flight — DECIDING ONLY (zero claims, zero spawns).` |
| 1 | `cc-dispatch: fetch failed — basing off last-fetched origin/main` |

### 2.9 Spawn failures (IDL `action:"failed"`, n = 877 over 76 distinct ids)

| rc | n | verbatim excerpt (as journalled) |
|---|---|---|
| 1 | **470** | `spawn rc=1 (reopened, self-release) — y be busy or congested.    REFUSING to mint a fresh window on an unknown, since that is indistinguishable from    a real anchor being available. Nothing was launched; retry once iTerm2 is responsive.` |
| 3 | **385** | `spawn rc=3 (reopened, self-release) —  an operational address !!   (resolved at send time) and the FULL uuid for a historical fact. !!   Intentional counter-example? add  pane-id-lint:allow  to that line. !!   Override: CC_PANE_ID_GATE=0` |
| 4 | 11 | `spawn rc=4 (reopened, self-release) — or the desk ROLE (cc-notify "$(cat ~/.claude/cc-roles/desk)" / --role desk)  and NEVER prescribe SendMessage for a desk/terminal announce. For a deliberate one-way fire, drop the cc-notify reference.` |
| 11 | 1 | (fire-cleanup / ring pane not found) |

**Concentration.** The top id alone owns **382 of 877 (43.6%)**:

| id | failures | first | last |
|---|---|---|---|
| **d6d7edef60a3** | **382** | 2026-09-11T04:52:28Z | **2026-09-22T05:50:53Z** (10 min before this probe) |
| 1117e6f228cf | 52 | 2026-09-21T17:18:44Z | 2026-09-22T04:30:06Z |
| 8e67a1fa2d40 | 22 | 2026-09-11T01:52:24Z | 2026-09-17T18:24:48Z |
| 9f8a985115a9 | 20 | 2026-09-11T07:46:34Z | 2026-09-17T18:51:45Z |

`d6d7edef60a3` has been claim→refuse→reopen→re-claim for **11 days straight** on a deterministic
`pane-id-lint` refusal of its own brief. It can never succeed and nothing stops it retrying.

The rc=1 congestion class is bursty and tracks box load: 267 of 452 on 2026-09-17, 67 on 09-21.
(Box load average at probe time: **23.12 / 26.69 / 26.06** against handoff-fire's
`CC_FIRE_MAX_LOAD_PER_CORE` default of **2.00/core**.)

### 2.10 Where the admission slots go — 90.6% of skips are the CLOUD pile

| n | % of 16,773 skips | class |
|---|---|---|
| 13,211 | 78.8% | CLOUD: already-declared (an unlanded cloud session already holds the row) |
| 1,976 | 11.8% | CLOUD: ineligible off-box |
| 1,516 | 9.0% | premise refuted at the claim actuator (either venue) |
| 55 | 0.3% | already done |
| 15 | 0.1% | pass-in-flight (singleton lock) |

Per-item decision verdicts (n = 147,416): `skip/project-not-dispatched` 56,652 · `admit` 42,789 ·
`defer/capacity` 29,807 · `defer/cluster-sibling` 17,817 · `defer/pass-in-flight` 304 ·
`skip/already-done` 44 · `skip/plan-premise-stale` 3.

Unplaced causes (n = 4,048): `capacity-surplus` 2,788 · **`wall-unknown` 1,065** · `spawn-cap` 66 ·
null 63 · `wall-capacity` 42 · `wall-capped` 24.

### 2.11 Ceilings actually in force, and theoretical vs measured drain

Launchd `ProgramArguments` exports exactly three things and **no ceiling overrides**:
`PATH`, `CC_DISPATCH_PROJECT=claude-infrastructure`, `CC_FIRE_CLOUD=on`. So every ceiling is the
binary's default:

| knob | value in force | source | binding? |
|---|---|---|---|
| `CC_DISPATCH_MAX_SPAWN` | **2** per pass | `bin/cc-dispatch:279` (default) | yes — but only 66 `spawn-cap` unplaced records in 11 d |
| `CC_DISPATCH_CEILING` | **12** on-box concurrency | `bin/cc-dispatch:440` | **never** — `free_slots == 0` in **0 of 5,766** passes |
| `CC_DISPATCH_CLOUD_CEILING` | 6 | `bin/cc-dispatch:446` | n/a to local |
| `CC_DISPATCH_CLOUD_PENDING_MAX` | 50 | `bin/cc-dispatch` header | cloud only |
| cc-wave-plan total concurrency | 8 (`\|accounts\| × CC_WAVE_MAX_PER_ACCT`) | `bin/cc-dispatch:173` | `live_workers` max observed = 8, hit 9 times of 5,766 |
| handoff-fire capacity gate | `CC_FIRE_MAX_LOAD_PER_CORE` = **2.00/core**, active-session ceiling 8 mid-turn | `scripts/handoff-fire.sh:5923, 6543` | **yes** — 470 rc=1 refusals |
| `StartInterval` | 300 s | plist | superseded in practice by pass duration |

`live_workers` distribution over 5,766 passes: **0 → 3,620 (62.8%)** · 1 → 1,217 · 2 → 515 ·
3 → 238 · 4 → 52 · 5 → 78 · 6 → 32 · 7 → 5 · 8 → 9.

**Theoretical vs measured:**

| bound | arithmetic | spawns/day | measured 6.07/day is… |
|---|---|---|---|
| configured cadence | 288 passes/d (300 s) × MAX_SPAWN 2 | **576** | **1.05%** |
| *measured* launchd cadence | 96.6 `--once`/d × MAX_SPAWN 2 | **193** | **3.14%** |
| concurrency × work duration (wave-plan cap 8, median 0.46 h) | 8 / 0.46 h × 24 | **417** | 1.46% |
| on-box ceiling × work duration (CEILING 12, 0.46 h) | 12 / 0.46 h × 24 | 626 | 0.97% |

Measured attributed closes: **4.84/day** (IDL window, both-signals) / **8.63/day** (30-day ledger
attribution) / **16.98/day** across the un-parked 15.2 days.

### 2.12 Venue parking — verified from the STORE, not the plist comment

`event:"claim"` + `role:"dispatcher"`, grouped by day and by the presence of a `venue` field:

| day | LOCAL (no venue) | cloud |
|---|---|---|
| 2026-08-10 | 54 | 0 |
| 2026-08-11 | 63 | 1 |
| **2026-08-12** | **3** | 28 |
| 2026-08-13 … 2026-09-04 | **0** (23 consecutive days) | 20–114/day |
| **2026-09-05, 09-06** | **0** | **0** ← the dispatcher fired in NEITHER venue |
| **2026-09-07** | **17** | 5 |
| 2026-09-08 | 57 | 0 |
| … 2026-09-22 | 7–298/day | 0–13/day |

This independently confirms both plist claims: cloud-only from **2026-08-12** (one day after the
09-08-11 directive), un-parked **2026-09-07**, and the two-day total outage 09-05/09-06 the plist
comment describes.

**Current backlog fold** (last-transition-wins over all 3,740 ids): **done 3,390 · blocked 340 ·
open 10**. All 10 open rows carry `venuePlan: local`. The queue the lane is draining is now nearly
empty — which is itself part of why the measured rate is low in the last few days.

---

## 3. Silent-failure modes found

| # | mode | evidence |
|---|---|---|
| **S1** | **A pass that reports success while spawning nothing — by construction.** `cc-backlog add` kicks `cc-dispatch --decide`, which journals a full `summary` (with `admitted: N`) and returns at step 3a with zero claims/spawns. 5,199 of 6,296 summaries (82.6%) are this. A reader counting "dispatcher passes" over-counts the spawn-capable ones **5.7×**. | `bin/cc-backlog:6994` (`"$bin" --decide`), `bin/cc-dispatch:2529` |
| **S2** | **A claim that leases a row effectively forever.** `d6d7edef60a3`: **382** claim→spawn-rc=3→reopen cycles over 11 days on a *deterministic* `pane-id-lint` refusal, still cycling at 05:50Z today. The thrash counter re-ranks it but never retires it. 78.4% of all local dispatcher claims end in `reopen`. | `jq 'select(.action=="failed")'` on the IDL |
| **S3** | **The launchd timer silently delivers 1/3 its configured rate.** `StartInterval 300` vs a 560 s mean `--once` pass ⇒ 96.6 runs/day, not 288. Nothing measures or alarms on this; `launchctl print … runs` is the only witness. | `runs = 517` / 5.35 d vs plist `StartInterval 300` |
| **S4** | **Fires onto already-closed rows.** 2 of 69 local fires (2.9%) spawned a pane for a row closed **3 seconds** and **3 minutes** earlier. The `already-done` guard exists (`skip/already-done` fired 44 times) but loses the race between admission and spawn. | `81909b601916`, `d03e77679af8` |
| **S5** | **The readiness gate computes a verdict it never enforces.** `ready_gate` = `advisory` in **6,296 / 6,296** passes; `ready_would_block_pct` = **100** in 2,007 of them. A gate that would have blocked every admitted item, 2,007 times, and blocked none. | `jq '.ready_gate,.ready_would_block_pct'` on summaries |
| **S6** | **`wall-unknown` never pages.** 1,065 unplaced records where cc-route exceeded its 20 s bound and the oracle gave no answer — "Retry next pass", forever, with no escalation. Only the `quota-cliff` arm calls `write_page` (`bin/cc-dispatch:2684`); the `venue-only` abstain arm (`:2026`) pages nothing (it never fired). Total abstains in 11.36 d: **2**. | unplaced cause histogram |
| **S7** | **Attribution leak: 20 closes look like the local lane and are not.** 20 ids inside the IDL window were closed by a `<host>-wt-<id>` worker after a dispatcher claim but with **no `cc-dispatch fired` record**. Either the fire went unjournalled (the `idl` writer is `>> "$IDL" 2>/dev/null \|\| true`, so an I/O error is silent) or another actuator picked the row up. Both readings inflate any naive ledger-only productivity count by ~36%. | §2.6 |
| **S8** | **A sibling lane died silently.** `lane:"local-drain"` (the `drain-recycle-fire.sh` recycle loop) produced **397 closes in 30 days** and has emitted **nothing since 2026-09-09T22:00Z**. It is in no launchd plist, so nothing restarts or alarms on it. | `jq 'select(.lane=="local-drain")'` by day |
| **S9** | **Decide-pass volume is unexplained by its only producer.** The kick fires **only** from `cc-backlog add` (`bin/cc-backlog:7000`), the live store records ~20–57 adds/day, yet **458 `--decide` passes/day** run, spread evenly across all 24 hours (144–307/hr, no burstiness). ~93% of kicks are backed by no add in this store — most plausibly test suites reaching the deployed `cc-dispatch` through the un-pinned kick seam (the very class `scripts/test-hermeticity-lint.sh` rule 8 exists to catch). **Not proven here.** | §4 |

---

## 4. What I could NOT measure, and why

1. **The 30-day window from the IDL.** The IDL retains **11.36 days** (2026-09-10T21:21 →
   2026-09-22T06:01). Passes, dispositions, fires, spawn failures and the stderr log therefore
   cover 11.36 d / 5.35 d respectively, **not 30**. Every 30-day figure in this report comes from
   `backlog.jsonl` (which does reach back to 07-18) and is a *claim/close* measurement, not a
   *pass/fire* one. There is no store on this box that can give 30 days of dispatcher passes.
2. **Which producer drives the ~458 `--decide` passes/day** (S9). The kick leaves no provenance — it
   spawns detached with stdout/stderr to `/dev/null` and the IDL record carries only `<ts>-<pid>`.
   Distinguishing "an `add` against a fixtured store" from "an agent invoking cc-dispatch" would
   need live process capture, which is out of scope for a read-only probe.
3. **Whether any `fired` record is missing.** `idl()` appends with `2>/dev/null || true`, so a fire
   whose journal write failed is indistinguishable from a fire that never happened. The 20 ids in S7
   are the size of the residual; I cannot split them.
4. **IDL archive integrity.** `cc-idl verify` checks the live epoch only (`OK: 8770 sealed intact`).
   The eight `.gz` archives supplying 10 of the 11.36 days were read but **not** hash-verified
   against their `.chain` sidecars.
5. **Whether the 7 sub-3-minute closes represent real work.** They are consistent with a worker
   finding the row already satisfied, but the ledger's `evidence` field is free text and I did not
   adjudicate each one.
6. **The `quota-cliff` page.** Both abstains (2026-09-12T03:45:50Z and 03:54:50Z) reach a
   `write_page` call in source; I found no page file dated to them in `~/.claude/autonomy/pages/`,
   but that directory holds 577 entries under several naming schemes and I could not establish the
   dispatcher's own page filename, so this is **unresolved, not negative**.

---

## 5. Every command that produced a number

```bash
# --- store discovery + coverage ---
ls -la ~/.claude/autonomy/idl*; wc -l ~/.claude/autonomy/idl.jsonl
for f in ~/.claude/autonomy/idl.jsonl.*.gz; do case "$f" in *chain*) continue;; esac; \
  gzcat "$f" | head -1 | jq -r .ts; gzcat "$f" | tail -1 | jq -r .ts; done
stat -f '%Sm %SB' -t '%F %T' /tmp/claude-dispatcher.stderr.log
sysctl -n kern.boottime

# --- build the working corpus (rc checked, not 2>/dev/null) ---
mkdir -p /tmp/backlog-probe/work && cd /Users/chrisren/.claude/autonomy
( for f in $(ls idl.jsonl.*.gz | grep -v chain | sort); do gzcat "$f"; done; cat idl.jsonl ) \
  > /tmp/backlog-probe/work/idl-all.jsonl ; echo "rc=$?"      # 924,016 lines
cd /tmp/backlog-probe/work
jq -rc 'select(.actor=="cc-dispatch")' idl-all.jsonl > dispatch.jsonl   # 219,047
jq -c  'select(.action=="summary")'    dispatch.jsonl > summ.jsonl      # 6,296
jq -c  'select(.id!=null)' ~/.claude/autonomy/backlog.jsonl > bl.jsonl  # 23,348

# --- 2.2 action histogram / per-day table ---
jq -r '.action' dispatch.jsonl | sort | uniq -c | sort -rn
jq -s '{passes:length,fired:(map(.fired)|add),abstained:(map(.abstained)|add),
        failed:(map(.failed)|add),skipped:(map(.skipped)|add),admitted:(map(.admitted)|add),
        deferred:(map(.deferred)|add),unplaced:(map(.unplaced)|add)}' summ.jsonl
jq -r 'select(.action=="summary") | select(.fired>0) | .ts' dispatch.jsonl | wc -l      # 67
jq -r 'select(.action=="passed")|.ts' dispatch.jsonl | wc -l                            # 521
jq -r 'select(.action=="skipped" and (.detail|test("singleton lock")))|.ts' dispatch.jsonl | wc -l  # 15

# --- 2.3 pass mode split + durations (python: parse pass id "<YYYYmmddTHHMMSSZ>-<pid>") ---
#   duration = summary.ts - strptime(pass.split('-')[0], "%Y%m%dT%H%M%SZ")
#   mode: admitted_terminal != null  <=>  --once (reached step 3); null <=> --decide (step 3a return)
launchctl print gui/$UID/com.claude.dispatcher | grep -E 'runs|last exit|run interval'   # runs = 517

# --- 2.4 venue classification of fires (the 2x2) ---
jq -r 'select(.action=="fired") | [.ts,(.detail|split(" ")[0]),.detail] | @tsv' dispatch.jsonl > fired.tsv
jq -r 'select(.action=="claimed") | [.ts,(.detail|split(":")[0])] | @tsv' dispatch.jsonl > cloudclaim.tsv
#   python: cloud <=> a claimed record for the same id within 3600 s before the fire
#           cross-tab against ('anchored' in detail)  ->  34/0 , 0/69

# --- 2.5 / 2.7 fire -> close, from bl.jsonl folded per id, sorted by ts ---
#   python: first done with ts >= fire_ts ; attribution = closedBy.endswith('-wt-'+id)
#   "wasted" = a done BEFORE the fire with no reopen/add between it and the fire

# --- 2.6 ledger claims (LOCAL = role dispatcher AND no venue field) ---
jq -r 'select(.event=="claim" and .ts>="2026-08-23")|[(.role//"norole"),(.venue//"novenue")]|@tsv' \
  bl.jsonl | sort | uniq -c | sort -rn
#   -> 1110 dispatcher/novenue, 480 dispatcher/cloud, 478 norole/local, 242 norole/novenue

# --- 2.8 stderr classes (no 2>/dev/null anywhere) ---
wc -l /tmp/claude-dispatcher.stderr.log /tmp/claude-dispatcher.stdout.log     # 2854 / 0
sed -E 's/[0-9a-f]{12}/<ID>/g; s/[0-9]+/N/g' /tmp/claude-dispatcher.stderr.log \
  | cut -c1-100 | sort | uniq -c | sort -rn | head -20

# --- 2.9 spawn failures ---
jq -r 'select(.action=="failed")|.detail' dispatch.jsonl | grep -o 'spawn rc=[0-9]*' | sort | uniq -c | sort -rn
jq -r 'select(.action=="failed")|(.detail|split(":")[0])' dispatch.jsonl | sort | uniq -c | sort -rn | head
jq -r 'select(.action=="failed" and (.detail|startswith("d6d7edef60a3")))|.ts' dispatch.jsonl > d6.ts
echo "n=$(wc -l < d6.ts) first=$(head -1 d6.ts) last=$(tail -1 d6.ts)"

# --- 2.10 skip classes / decisions / unplaced ---
jq -r 'select(.action=="decision")|[(.verdict//"-"),(.reason//"-")]|@tsv' dispatch.jsonl | sort | uniq -c | sort -rn
jq -r 'select(.action=="unplaced")|.cause' dispatch.jsonl | sort | uniq -c | sort -rn

# --- 2.11 ceilings ---
cat ~/Library/LaunchAgents/com.claude.dispatcher.plist         # exports: PATH, PROJECT, CC_FIRE_CLOUD only
grep -n 'MAX_SPAWN=\|CEILING="' bin/cc-dispatch                # :279 MAX_SPAWN 2 · :440 CEILING 12 · :446 CLOUD 6
jq -r 'select(.action=="decision" and .live_workers!=null)|[.pass,(.live_workers|tostring),(.free_slots|tostring)]|@tsv' \
  dispatch.jsonl | sort -u -k1,1 > lw.tsv
awk -F'\t' '{print $2}' lw.tsv | sort -n | uniq -c            # live_workers histogram, max 8
awk -F'\t' '$3==0' lw.tsv | wc -l                             # 0 passes at free_slots==0
grep -n 'CC_FIRE_MAX_LOAD_PER_CORE' scripts/handoff-fire.sh   # :5923 default 2.0/core
uptime                                                        # load 23.12 26.69 26.06

# --- 2.12 park verification from the store ---
#   python over bl.jsonl: event==claim and role==dispatcher, grouped by ts[:10] and (venue or 'LOCAL')

# --- controls ---
cd ~/Development/claude-infrastructure
md5 -q bin/cc-dispatch ~/.claude/bin/cc-dispatch     # identical (the deployed path IS a symlink here)
git rev-list --count HEAD..origin/main               # 1 — and `git diff --name-only HEAD origin/main`
                                                     #     is docs-only, so the running binary is current
timeout 180 ~/.claude/bin/cc-idl verify              # OK: 8770 sealed intact, rc 0
timeout 120 ~/.claude/bin/cc-backlog list | tail -20 # control fold vs my own fold: 10 open, 340 blocked
```
