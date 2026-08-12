# recon-staleness — how a cc-backlog item goes stale, and what (fails to) re-validate it
Read-only recon, 2026-08-12T08:4x UTC. Repo `~/Development/claude-infrastructure` @ `0ffe96995`.
Store: `~/.claude/autonomy/backlog.jsonl` — 8,634 records, 1,905 folded ids, 327 live (open∨claimed),
210 blocked. Every number below re-derived this session; none quoted from a plan.

---

## 0. THE ONE-LINE ANSWER

A falsifier is executed at **exactly one place in the codebase** — `assess()`
(`bin/cc-premise:1819`, the sole call site of `run_falsifier`) — and `assess()` is reached only from
`cc-backlog claim` (guard 5, `bin/cc-backlog:1488`), `cc-backlog unblock` (advisory,
`bin/cc-backlog:1721`), `cc-dispatch`'s brief injection, and `cc-premise sweep`/`check` (no
scheduler calls those). **Re-validation is therefore a side effect of somebody trying to WORK the
item.** An item nobody works is never re-asked, at any age, and nothing on the box counts that.
205 of 327 live rows (63%) have never been claimed once.

---

## 1. MECHANISM MAP

| # | component | what it does | wired to run automatically? | measured coverage / state |
|---|---|---|---|---|
| M1 | `run_falsifier` (`bin/cc-premise:1020`) | re-runs the item's stored probe against today's tree; exit 0 ⇒ `falsified` (BLOCKS the claim), non-zero ⇒ advisory "still live"; fail-OPEN on timeout/exception | **NO scheduler.** One call site: `assess()` `:1819`. Bound `CC_PREMISE_FALSIFIER_TIMEOUT=20s` | 159/327 live rows carry a probe = **48.6%** |
| M2 | `assess()` (`:1805`) | the whole predicate: falsifier → filing-day screen → plan-open derived → postland derived → plan-title snapshot → supersession → self-dup → corrector → sha/path/evidence-churn arms | **NO scheduler.** Consumers: `check`, `contract`, `sweep` | — |
| M3 | `cc-backlog claim` guard 5 (`bin/cc-backlog:1488-1540`) | runs `cc-premise check`; rc 3 REFUSES the claim (`verdict=premise-refuted`); non-3 output rides the claim contract | **YES — but only when a human/dispatcher claims.** `CC_BACKLOG_PREMISE_GATE` (unset ⇒ on; verified not set in any settings.json/plist/zshrc) | the only *blocking* re-validation in the system |
| M4 | `cc-backlog unblock` re-read (`:1719-1738`) | same predicate, **advisory only** — prints the contract to stderr, blocks nothing. Explicitly **scoped to `unblock` and NOT `reopen`** (`:1713-1716`: reopen is "machine traffic … no deciding reader") | on the unblock path only | 44 of 327 live rows have ever been unblocked; **276 reopens** on live rows re-admitted with zero re-read |
| M5 | `evidence_churn_lines` (`bin/cc-premise:936`) | the real age arm: *has trunk moved under the files this item cites since `first_ts`?* `git rev-list --count --since=<first_ts> origin/main -- <cited paths>`. Floor `STALE_AFTER_S=24h`, `CHURN_COMMITS_MAX=6` | rides M2 — same claim/unblock/dispatch path only | reaches only rows with a **resolvable cited path**; 202/328 cite ≥1 path, **111 (33.8%) cite nothing at all** ⇒ structurally invisible to it |
| M6 | `filing_day_screen` / `cc-premise screen [--all]` (`:1381`, `:2224`) | THE SECOND SCREEN — would this probe have FAILED on filing day? Reconstructs the filing-day trunk and re-asks the probe's clauses. 3 verdicts incl. first-class UNDECIDABLE. Wired ONE-WAY into `assess` (can only downgrade a refusal) | `screen <id>` inline: yes, via `assess`. **`screen --all`: ZERO callers** — grepped by NAME across `~/.claude/{hooks,scripts,bin}`, settings*.json, LaunchAgents | ran it live: **86 DISCRIMINATING · 0 ANTI-COVERAGE · 81 UNDECIDABLE** over 167 stored probes — i.e. **48.5% of stored probes cannot even be screened** |
| M7 | `cc-premise sweep` (`:2094`) | whole-store triage: superseded / self-duplicate / falsified / corrected / suspect + re-key clusters + dupes-of-done | **ZERO callers.** Not in any hook, script, launchd job, `commands/` or `skills/` (grepped by name) | inert |
| M8 | `scripts/backlog-ratchet.sh` | census of 2 numbers: falsifier coverage %, days-to-close median/p75. `--assert` exits 1 iff coverage fell below a high-water mark. **Reports only — gates nothing.** Explicitly "a CENSUS until coverage becomes non-trivial" (header) | **YES** — `scripts/autonomy-sweep.sh:508`, launchd `com.chrisren.autonomy-sweep` @ 300 s, PID 69074 live | live now: **48.6% (159/327)**; high-water file says **50.0%** ⇒ `--assert` is RED |
| M9 | `scripts/backlog-consolidation-trigger.sh --file` / `--fold` | cluster detector; `--file` files ONE condition-keyed row when a cluster crosses threshold; `--fold` joins mechanically-identical rows (DRY-RUN by design) | **YES** — `autonomy-sweep.sh:507` and `:534`, same 300 s tick, 60 s bound | `--file` rc 0 (7/7). **`--fold` rc 124 — TIMES OUT on every single sweep** (7/7), yielding `fold_conservation=no-verdict` |
| M10 | `cc-dispatch` READINESS (W1, `bin/cc-dispatch:882`) | `ready = premise-standing ∧ probe-trustworthy ∧ venue-current ∧ cluster-resolved`, keyed on trunk sha, voided by a path-intersecting diff | **YES** — computed per admission | `CC_DISPATCH_READY_GATE` defaults **`advisory`** (`:882`) and the plist does not set it ⇒ verdict computed, journalled to the IDL, **admitted anyway**. Plan measured would-block at 60%, 6/10 of which are *cites-nothing* |
| M11 | `cc-dispatch` plan-open premise gate (`:1465-1526`) | retracts items whose entire claim was "this plan is open" once the plan closed | YES, on the dispatch path | narrow class only; fails OPEN |
| M12 | `cc-backlog reap` / `cc-reaper` (`bin/cc-backlog:642-660`) | **stale CLAIMS, not stale content** — reopens a claim past `STALE_CLAIM_S` whose claimer is provably dead | YES (`com.chrisren.cc-reaper`) | orthogonal: it re-admits without re-reading, and reopen is M4-exempt |
| M13 | `cc-backlog falsify` (`:2006`) | attaches a probe to an EXISTING row and **runs it before storing** (rc 5 refusal on exit-0; `--force`/`--no-run`/`--clear`) | manual verb, no scheduler | 181 `falsify` records total; last one **2026-08-11T19:41Z** |
| M14 | `cc-backlog add --falsifier` (`:1124-1131`) | attaches a probe at creation — **and does NOT run it**. `cmd_add` writes the JSON straight through with no exit-0 screen | on every generator add | asymmetry with M13: a generator-emitted probe is stored **unscreened** and may not execute until first claim, possibly never |

---

## 2. MEASURED NUMBERS

**Store shape (live = open ∨ claimed, folded from raw records):**
- live **327** · blocked **210** · done-or-other to 1,905 total ids
- falsifier coverage **48.6%** (159/327) — matches `backlog-ratchet.sh` run with an isolated state file
- **168 live rows carry no probe at all**
- **205 live rows (62.7%) have never been claimed** ⇒ their stored probe (if any) may never have executed
- **122 live rows have zero claim AND zero falsify event** ⇒ no re-validation opportunity has ever occurred, by any path

**Age (from `first_ts`, live rows):** p50 **2.0 d** · p75 **3.5 d** · p90 **9.0 d** · max **21.7 d**.
38 live rows >7 d, 4 >14 d, 0 >30 d.

**The number that matters — commits HEAD has advanced since filing.** This repo lands ~150 commits/day
(151 in the last 24 h; 884 in 7 d; 2,190 in 21 d). For the 292 live rows belonging to
`claude-infrastructure`, `git rev-list --count --since=<first_ts> origin/main`:

| | commits landed since the row was written |
|---|---|
| min | 1 |
| p25 | **184** |
| **p50** | **361** |
| p75 | **558** |
| p90 | **737** |
| max | **2,066** |
| rows >100 commits stale | **249 / 292 (85%)** |
| rows >500 | 93 |
| rows >1,000 | 21 |

So "hundreds of commits old" is not the tail — **it is the median**. A 2-day-old row is already 361
commits behind, and the age distribution looks healthy (p50 = 2 d) precisely because the store's
clock is days while the tree's clock is commits.

**Citation blindness (the reach limit on every git-based arm):** of 328 live rows —
cite ≥1 path **202 (61.6%)** · cite ≥1 sha **85 (25.9%)** · **cite NOTHING: 111 (33.8%)**.

**Never re-validated, and unmeasurable:** the store schema has 23 keys —
`by condition dodRef event evidence falsifier force id needs project reclaim releaseReason role run
selfRelease session source title ts venue venuePlan venueWhy`. There is **no `lastValidated` /
`validatedAt` / `checkedAt` field**, and `grep -n "lastValidated\|validatedAt\|revalidat\|last_checked"`
across `cc-backlog`, `cc-premise`, `cc-dispatch` returns **zero hits**. A falsifier run leaves no
trace anywhere — not in the ledger, not in the IDL. "How many items have ever been re-validated" is
therefore **not answerable from the store**; the best available proxy is claim/falsify events, and by
that proxy 122/327 have had none.

**Live IDL evidence (7 `backlog-health` rows, 06:39Z → 08:38Z today):**
`ratchet_rc = "1"` on **7/7** · `fold_rc = "124"` on **7/7** · `fold_conservation = "no-verdict"` on
**7/7** · `consolidation_trigger_rc = "0"`.

**Venue interlock (the currently-binding shutoff):** the dispatcher plist runs with
`CC_DISPATCH_VENUE_ONLY=cloud`. `bin/cc-dispatch:1402` filters on `.venuePlan == "cloud"`. Live rows
by `venuePlan`: **local 241 · cloud 47 · none 40**. So **281 of 328 live rows (86%) are PARKED and
cannot be claimed at all** — and the claim path is the only blocking re-validation in the system.
The `com.claude.dispatcher` job is loaded (LastExitStatus 0) but the last claim event in the store is
**07:15Z** and `dispatch-fires.log` last moved **00:15Z**.

---

## 3. THE GAP — the specific missing links

**G1 · Re-validation is demand-driven; nothing supplies demand.** `run_falsifier` has one call site
(`bin/cc-premise:1819`) inside `assess()`, and `assess()` is only reached by someone trying to consume
the item. `cc-premise`'s own header defends this ("the durable form has to run at CONSUMPTION, every
time … a one-time review goes stale the moment it finishes") — and that reasoning is sound *for an
item that gets consumed*. It has no answer for the 205 live rows nobody has ever claimed. There is no
"stale item" concept anywhere: `STALE_*` in `bin/cc-backlog` refers **only** to dead claims
(`STALE_CLAIM_S`, `CC_BACKLOG_LOCK_STALE_S`) and to dropping terminal rows in `compact`.

**G2 · Nothing records that a probe ran, so decay is unmeasurable.** No `lastValidated` field exists
(§2). `backlog-ratchet.sh` measures *coverage* — how many rows CAN re-check themselves — and calls it
"the leading indicator". It cannot measure how many rows *have been* re-checked, because that datum is
never written. A store could be 100% covered and 0% ever-executed and the ratchet would read GREEN.

**G3 · Age is measured in days; decay happens in commits.** Every age reader in the system uses wall
time: `_age_seconds` (`cc-premise:919`), `STALE_AFTER_S = 24*3600` (`:270`), the ratchet's
days-to-close. The one commit-aware arm — `evidence_churn_lines` (`:936`) — is (a) advisory by
construction (its own docstring: "ADVISORY, AND NEVER A VERDICT"), (b) gated on `present_paths` from
the caller, so blind to the 33.8% of rows citing nothing, and (c) reached only via M2, i.e. only when
someone claims. Nothing anywhere computes "N commits have landed since this row was written" as a
standing number.

**G4 · `reopen` is the amnesia hole, and it is the high-volume path.** `bin/cc-backlog:1713-1716`
deliberately scopes the re-admission re-read to `unblock` only, reasoning that reopen is machine
traffic with "no deciding reader". Measured: **276 reopens across 118 live rows vs 44 unblocks**. The
defect `evidence_churn_lines`' own docstring documents (`149789b69fc4` → re-dispatched 7 days on with
a file list discharged 39 minutes after filing) travels this exact path, and the arm built to catch it
is not on it.

**G5 · The exit-0 screen is asymmetric between the two writers.** `cmd_falsify` (`:2006`) runs the
probe before storing and refuses rc 5 on exit-0. `cmd_add --falsifier` (`:1124`) writes it straight
through with no screen. The four generators emit probes via `add`, so the write path that produces
most coverage is the one with no admission check on the probe.

**G6 · The one always-on instrument is red and unwired to any actuator.** `autonomy-sweep.sh:508`
captures `_rat_rc` and — per `:544` — passes it into `log_idl backlog-health` and **nothing else**.
There is no branch on it: no `cc-notify`, no banner, no `cc-backlog add`. Compare the trigger at
`:507`, which *files* a row. The ratchet has read RED on 7/7 recorded runs today (48.6% vs a 50.0%
high-water) and the only consequence is a JSON field. This is the *same* failure the ratchet's own
header says W0 fixed — it was 100.0% vs 51.5% then, it is 50.0% vs 48.6% now.

---

## 4. LOOKS LIKE THE CURE, IS INERT

| thing | why it looks like the cure | why it isn't |
|---|---|---|
| `cc-premise sweep` (`:2094`) | it IS the whole-store re-validation pass — buckets every non-done item by verdict, runs `assess` on each | **zero callers.** Not in `hooks/`, `scripts/`, `bin/`, `commands/`, `skills/`, any settings.json, any LaunchAgent. Built, documented, never invoked |
| `cc-premise screen --all` (`:2224`) | catches the *anti-coverage* class the CURRENCY pass measured as dominant (8 of 16 refuted probes) | **zero callers.** Runs clean by hand (86/0/81) and nothing schedules it. Also deliberately exits 0 always, so it cannot be wired as a gate without changing it |
| `scripts/backlog-ratchet.sh --assert` | the standing rot alarm, and it *is* on the 300 s tick | reports coverage, never currency; and its rc is journalled, never acted on (G6). It also cannot distinguish "probe exists" from "probe ever ran" (G2) |
| `--fold` caller (`autonomy-sweep.sh:534`) | W3's actuator for the duplicate pile, wired in deliberately | **rc 124 on 7/7 sweeps** — it exceeds the 60 s `_bounded` timeout every time and returns `no-verdict`. Built, called, and producing nothing. The header's "flip to `--apply` when `fold_conservation` has read `ok` across a run of sweeps" can never be satisfied, because it has never once read `ok` |
| `CC_DISPATCH_READY_GATE` (`cc-dispatch:882`) | the R1 conjunction at the admission chokepoint — exactly the right place | defaults `advisory`; the plist does not override it. The verdict is computed and the item admitted anyway. Deliberate (W1 measured a 60% would-block), but it means the readiness verdict currently changes nothing |
| `CC_DISPATCH_VENUE_ONLY=cloud` (plist) | a migration lever, working as designed | it **parks 281 of 328 live rows** from the only blocking re-validation path. An interlock intended to steer venue also silently switched off currency-checking for 86% of the store |
| `docs/plans/readiness-2026-08-11/` W1-W3 | the design that names all four readiness properties | W1/W2/W3 landed; the plan's own table still marks **cluster identity as "detector, not actuator"** and the actuator that was built is the one timing out above |

---

## 5. TOP-10 FINDINGS (file:line anchors)

1. `bin/cc-premise:1819` — `run_falsifier`'s **only** call site. Re-validation is demand-driven; 205/327 live rows have never generated demand.
2. Store schema has **no `lastValidated`** (23 keys, verified). Grep for `lastValidated|validatedAt|revalidat|last_checked` in `cc-backlog`/`cc-premise`/`cc-dispatch` = 0 hits. Decay is unmeasurable by construction.
3. **Median live row = 361 commits behind trunk**; 249/292 (85%) are >100 commits behind; max 2,066. Age in days (p50 = 2.0 d) reads healthy over the same population.
4. `scripts/autonomy-sweep.sh:508` + `:544` — `_rat_rc` is journalled and never branched on. **7/7 `ratchet_rc="1"` today** (48.6% vs 50.0% high-water) with zero consequence.
5. `scripts/autonomy-sweep.sh:534` — the `--fold` actuator returns **rc 124 on 7/7 sweeps**; `fold_conservation` has never once read `ok`, so the documented `--apply` flip is unreachable.
6. `bin/cc-backlog:1713-1716` — the unblock re-read is deliberately **not** on `reopen`. 276 reopens vs 44 unblocks across live rows: the amnesia path is 6× the guarded one.
7. `bin/cc-dispatch:1402` + the dispatcher plist's `CC_DISPATCH_VENUE_ONLY=cloud` — **281/328 live rows parked** out of the only blocking re-validation path (venuePlan: local 241 · cloud 47 · none 40).
8. `bin/cc-premise:2094` (`sweep`) and `:2224` (`screen --all`) — **both have zero callers** anywhere on the box. Live `screen --all`: 86 DISCRIMINATING / 0 ANTI-COVERAGE / **81 UNDECIDABLE** (48.5% of probes unscreenable).
9. `bin/cc-backlog:1124-1131` (`cmd_add`) stores `--falsifier` **without running it**, while `cmd_falsify` (`:2006`) refuses rc 5 on an exit-0 probe. The generator write path has no probe-admission screen.
10. `bin/cc-premise:936` (`evidence_churn_lines`) is the only commit-aware staleness arm — advisory by design, floor 24 h, and blind to the **111/328 (33.8%) live rows that cite no path or sha at all**.

---

## 6. ADVERSARIAL PASS — what I checked because it would have refuted the above

- **"The premise gate is just turned off."** `CC_BACKLOG_PREMISE_GATE`, `CC_PREMISE_FALSIFIER`, `CC_DISPATCH_READY_GATE` are set in **no** `~/.claude/settings*.json`, no LaunchAgent plist, no `~/.zshrc`. Defaults hold: gate on, falsifier on, ready-gate advisory.
- **"Something else re-runs probes."** `grep -n "run_falsifier("` → 2 hits, one def one call. No bulk re-runner exists.
- **"A hook surfaces staleness at read time."** `hooks/operator-readout.sh` and `scripts/wrap-ledger.sh` read `cc-backlog list --blocked/--open` for the `👤` rung and the OPERATOR block — **status-filtered, never age- or currency-filtered**.
- **"The ratchet's `--assert` red is meaningful noise, not a real fall."** Ran it with `CC_RATCHET_STATE=/tmp/...` (isolated, live store untouched): 48.6% live vs a 50.0% recorded high-water dated 2026-08-12T00:37Z. It is a genuine ~1.4 pt fall over ~8 h — and it is reaching nobody.
- **"`cc-eligible` / `cc-venue` cover this."** They answer *venue* (can a VM run it) and re-run cc-premise as ONE derived read (`bin/cc-venue:219`). Neither re-asks currency on an unclaimed item.
- **"The plan already names the gap."** `docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md:593` marks premise currency ✅ "re-run at claim". That row is the finding: ✅ is conditional on a claim happening, and today 86% of rows cannot be claimed at all.

## 7. BLOCKERS / UNCERTAINTIES

- I did **not** run `cc-premise sweep` (it executes 159 stored probes as a side effect and the brief is read-only). Its verdict-bucket counts over the live store are therefore unmeasured.
- Commit-since figures are computed against `origin/main` for the 292 `claude-infrastructure`-scoped live rows; cross-project rows (reso-management-app etc.) are correctly excluded — their staleness would have to be measured in their own repos, and `assess`'s git arms deliberately stay silent on them (`cc-premise:1888`).
- The IDL holds only 7 `backlog-health` rows (log rotation), so "7/7" is today's window, not all history. The plan records the same shape at 3/3 on 2026-08-11.
