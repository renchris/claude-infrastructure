# q1a — recover pool and `--one` lane: what bounds how many recoveries run at once

Slot scope: `scripts/limit-recover/lr-fleet.sh` (`--recover` pool, `--one` lane) and the probe it calls.
Tags: MEASURED = I ran the command; READ = source or record; INFERRED = derived.
Live layer equals this checkout for `lr-fleet.sh`, `lr-lib.sh`, `capacity-admit.sh`, `spawn-presence.sh` (MEASURED, `diff -q` against `~/.claude/scripts/...`, all four IDENTICAL).

## 1. Verdict

- The count bound in both lanes is a **fixed constant of 2**, not a memory gate. `lf_pool_max` `lr-fleet.sh:1361-1365`, `lf_one_slot_max` `:1380-1384` (READ).
- Its recorded reasons are routing/admission races and account-side burst protection. No memory measurement appears in the commit, the plan draft, or ruling D8.1 (READ, section 3).
- The cap of 2 is the bound that bit in the records: 38 of 353 `--one` runs queued on it, observed peak overlap is exactly 2 (MEASURED, section 6).
- The memory terms of the capacity probe refused 0 of 55 `lr-fleet` probes in the ledger window; the last capacity PARK row in `fleet/*/results.tsv` is dated 2026-09-19 (MEASURED, section 6).
- Hypothesis "memory is the bottleneck" is **not supported for these two lanes**. Next bound after the cap: the box-wide serial admit lock (p50 13.2 s per admit, n=55).

## 2. Every bound, classified

| # | Mechanism | Site (`lr-fleet.sh` unless named) | Class | Default | Scope / what it holds |
|---|---|---|---|---|---|
| 1 | Pool width `LR_RECOVER_MAX_CONCURRENT` | `:1361-1365`, wait loop `:1435-1441`, use `:1490,1524` | fixed cap | 2 (junk/0 falls back to 2) | workers of ONE `--recover` process; poll `LR_POOL_POLL_S` 0.2 s; waits forever, never parks |
| 2 | `--one` slots `LR_ONE_MAX_CONCURRENT` | `:1379-1417`, take `:1680-1687` | fixed cap (mkdir slot dirs, pid+lstart holder) | 2 | box-wide across all `--one` processes; held from before `lf_one` through admit, actuator and proof wait; dry runs, nudge (`:1676`) and stranded (`:1678`) paths take none |
| 3 | Slot wait `LR_ONE_SLOT_WAIT_S` / `LR_ONE_SLOT_IVL_S` | `:1386,1408-1410` | wait on a clock | 900 s, 10 s poll | past 900 s the run PARKS (`:1682`) |
| 4 | Admit lock `$STATE/admit.lock` | take `:603-633`, hold `:971-975` | lock (mkdir mutex) | n/a | box-wide, ONE holder across pool workers and every `--one`; holds rank + `--assign` + probe + the whole capacity wait; actuator is outside |
| 5 | Admit-lock wait `LR_ADMIT_LOCK_WAIT_S` | `:605`, steal `:623-629` | wait on a clock | 600 s (was 300 until `7e16ce5f7`) | dead holder stolen at once; live holder stolen after 600 s, "a second recovery may be admitted" |
| 6 | Router rank bound | `lf_rank_timed` `:734-750` | wait on a clock (inside lock 4) | `--max-wait 3`, one retry at 15 s | measured wall p50 1.6 s, p90 15.7 s, max 91 s (n=232) |
| 7 | Capacity probe, headroom term | `lr-lib.sh:410-440` -> `capacity-admit.sh:1343-1354` | **memory gate** | reclaimable GB >= 4 | inside lock 4 |
| 8 | Capacity probe, segments term | `capacity-admit.sh:1374-1393`; ceiling raised call-scoped `lr-lib.sh:436` | **memory gate** (compressor) | 90% for this caller (50% elsewhere) | inside lock 4 |
| 9 | Capacity probe, active term | `capacity-admit.sh:1445-1472` | fixed cap (mid-turn sessions box-wide) | act + tokens in flight + 1 <= 8 | inside lock 4 |
| 10 | reserve-headroom | `capacity-admit.sh:1495-1500` | **memory gate** | floor 4 + reserve (rows show 6 GB operator present, 2 GB absent) | inside lock 4 |
| 11 | reserve-active | `capacity-admit.sh:1514-1523` | fixed cap | 8 - 1 when operator present | inside lock 4 |
| 12 | reserve-slots | `capacity-admit.sh:1529-1538` | fixed cap (resident trees) | trees + 1 <= 54 - reserve slots (3 or 6 in rows) | inside lock 4 |
| 13 | Capacity park `LR_FLEET_CAP_WAIT_S` / `LR_FLEET_CAP_IVL_S` | `:546-578` | wait on a clock | 120 s, 20 s step = 7 probes | inside lock 4, then PARK with the term named |
| 14 | Per-sid run claim `runs/by-sid/<sid>.active` | `:648-658`, `:1519` | lock (per sid) | n/a | pool only; `--one` relies on its caller's claim. Bounds duplicates, not width |
| 15 | `--max N` | `:1511` | fixed cap (count per run) | 0 = off | `--recover` only |
| 16 | Reconciler fence `lr_recon_may_act` | `:943-955` | lock (per sid, ownership) | inert | `recon.on` absent (MEASURED `ls ~/.reso/limit-recover/*.on` -> `autorecover.on` only) |
| 17 | Proof wait `LR_FLEET_PROOF_WAIT_S` | `:918-936`, `:1051-1053` | wait on a clock | 240 s, 5 s poll | detached `--one` only; inside slot 2 |
| 18 | Nudge engage wait `LF_NUDGE_ENGAGE_S` | `:1231-1239` | wait on a clock | 120 s | wake-in-place path; inside slot 2 when reached through `lf_one` |
| 19 | Router exclusion (no target) | `lf_pick_target` `:760-837` | account capacity, not box | soft reasons fall back (`:824-835`, list `:847`) | parks "no routable target"; 69 of 184 park rows |
| 20 | Upstream of `--one`: poller dispatch | `lr-reset-poller.sh:1113,1317-1322` | fixed cap + clock | 4 per account per tick; launchd `StartInterval` 600 s | neighbor slot; named because it gates arrivals into bound 2 |

Load term: OFF for this caller (`lr-lib.sh:435`), so loadavg bounds nothing here. Box read load1 115.44 on 10 CPUs at 06:36Z (MEASURED `uptime`).
Pool and `--one` caps are independent and additive (a pool worker never takes a slot, `:1376-1378`); both share lock 4.

## 3. KQ1 — where the 2 comes from

| Evidence | Says | Tag |
|---|---|---|
| `git blame -L 1340,1384`: `:1361-1366` from `c7ed6837e` (2026-09-21), `:1367-1384` from `7e16ce5f7` (2026-09-29) | two commits, one value | MEASURED |
| `git log -S LR_RECOVER_MAX_CONCURRENT`: `601807233` plan, `c7ed6837e` code, `87381352a`, `5b65782f9` | first code use is W6b | MEASURED |
| `c7ed6837e` message item 4: "`--recover` IS A POOL, NOT A QUEUE. LR_RECOVER_MAX_CONCURRENT (default 2)". No reason given for 2 | serial 115-658 s recoveries was the defect | READ |
| `docs/research/lr100p-2026-09-19/PLAN_DRAFT.md:749-751` (rejected alternatives): "`recover --all` at unbounded concurrency with N simultaneous probes — N probes mint N tokens and N ranks stack on rank[0] ... a pool of 2 with a serialized admit section" | reason = admission/routing race | READ |
| `7e16ce5f7` message: "(LR_ONE_MAX_CONCURRENT, default 2 as the pool's)"; comment `:1369-1372`: the unattended lane "had no cap at all ... four accounts is sixteen" | reason = bound an unbounded daemon lane | READ |
| D8.1 = `rulings.json` `/finals[5]/implementation_steps[1]`: "Keep burst protection as it is: 2 concurrent recoveries on the live legacy lane, then the 3-per-account first-turn pacer after the reconciler cutover"; `kind: none` | reason = account-side first-turn burst | READ; the D8.1 = index 1 mapping is INFERRED (index 2 is the evidence note the note itself calls D8.2; index 6 is the mover-weight item the plan calls D8.6) |
| `LIMIT_RECOVER_FLEET_V2.md:510,587`; `kmax-decision-8.md:42`: 0 of 40 first turns failed at N = 2..6 simultaneous cold starts; "the first-turn pacer of 3 is conservative rather than measured" | burst band never measured on this box above N=6 | READ |
| grep for memory, RAM, swap in `reports/W6B.md` and the pool hunks | no hit tying 2 to memory | MEASURED |

Stale text that says otherwise: `commands/limit-recover.md:597` "`fleet --recover` — sequenced, one session at a time, each behind the NON-charging capacity probe" and `lr-fleet.sh:22` "SEQUENCES (one at a time ...)". Both predate the pool (READ).

## 4. KQ2 — the admit section

- Holds `$STATE/admit.lock` (`:90`), a `mkdir` directory stamped pid+lstart (`:609-611`). One take, one release (`:971-975`).
- Inside: `lf_pick_target` (rank, optional retry, optional `claude-accounts --json` soft fallback, `--assign` write) then `lf_capacity_wait` (`:879`, `:905`).
- Serial across workers: yes, and across processes. The path is global to the state dir, so pool workers and every `--one` driver queue on it.
- Designed duration: "~1-2 s warm", cold `cc_sp_active` 7.2 s, up to 120 s when the probe refuses (`:587-592`, READ).
- Measured duration: rank wall plus rank-end to probe-verdict row, **p50 13.2 s, p90 61.2 s, max 138.8 s, n=55** (MEASURED; join of `fleet/one-*/rank.timing` with `idl.jsonl` rows `caller=lr-fleet`, nearest preceding rank within 130 s, 1 s clock resolution).
- Outside the lock: `lf_own_acct_live` wake check (`:961`), the actuator `lr-handoff.sh` (`:992`), the proof wait.
- Gap (INFERRED from READ): the header says the lock makes "worker 2's probe see the seat worker 1 just took" (`:584-585`), but `lf_admit_section` mints nothing; the admission token is minted later by `lr-handoff.sh:1463`, after the lock is released. Worker 2's probe sees worker 1 only through the `--assign` phantom on the rank side.

## 5. KQ3 — what the capacity park reads and refuses on

- Call chain: `lf_capacity_wait` `:546` -> `lr_capacity_probe_corrected` `lr-lib.sh:410` -> `cc_capacity_probe` `capacity-admit.sh:1135` (non-charging: `_cc_admit_spend` returns 9 without touching the budget, `:1603-1607`).
- Call-scoped settings: `CC_ADMIT_LOAD_TERM=off`, `CC_ADMIT_MAX_SEGMENT_PCT=90` (`lr-lib.sh:435-436`), `CC_SP_ACTIVE_OVERRIDE = raw - limit-corpse beats - self` (`lr-lib.sh:423-433`).
- Refusing terms in evaluation order: headroom (< 4 GB), segments (> 90%), active (act + tokens + 1 > 8), reserve-headroom (< 4 + reserve GB), reserve-active (operator present, > 7), reserve-slots (trees + 1 > 54 - reserve). Rows 7-12 above.
- Fail-open: probe library missing -> UNGATED (`:548`); unreadable headroom -> admit; blind segments/active -> noted and skipped. A missing `lr_capacity_probe_corrected` parks at once (`:558-560`).
- On refusal: re-probe every 20 s until 120 s waited, then PARK with `LF_PARK_REASON`; nothing moved (`:561-577`).

## 6. Measured from the records

Source: `~/.reso/limit-recover/fleet/` (490 run dirs: 480 `one-*`, 10 `--recover`, 703 result rows) and `~/.claude/autonomy/idl.jsonl` (109,079 rows, starts 2026-10-03T20:47Z).

| Measurement | Value | n |
|---|---|---|
| Park rows by reason (`results.tsv` col 6 = `parked`) | CWD-GONE 103, no routable target 69, capacity 7, target==source 3, DUPLICATE 2, `--one` cap 0, admit lock 0 | 184 |
| Dates of the 7 capacity parks | 2026-09-10 x2, 2026-09-19 x5; none since | 7 |
| `lr-fleet` probe verdicts in the ledger (2026-10-03T21:52Z to 2026-10-06T06:20Z) | 55 admit, 0 refuse | 55 |
| Reclaimable GB on those rows | min 11.75, p10 25.00, p50 30.34, p90 33.44, max 34.39 (floor 4, +6 operator present) | 55 |
| Segments % on those rows | p50 6.72, p90 10.60, max 50.63 (ceiling 90 on that row) | 55 |
| Closest call | 2026-10-04T21:37:24Z: 11.75 GB vs 10 GB effective floor, 50.63% segments | 1 of 55 |
| Mid-turn count on those rows | 0 on every row | 55 |
| `--one` runs since the first slot wait (2026-10-01T20:16Z) | 353; 38 waited on the slot cap (10.8%); 5 waited on capacity (1.4%) | 353 |
| Slot waits by day | 10-01: 19, 10-02: 3, 10-04: 15, 10-06: 1 | 38 |
| start -> rank, slot-waited | p50 102 s, p90 635 s, max 1343 s | 28 |
| start -> rank, not slot-waited | p50 3 s, p90 49 s, max 332 s | 188 |
| Peak overlap of [rank, result] intervals | 2 (5,858 s at 1; 2,680 s at 2) | 216 |
| rank -> result, `recycle-in-place/RECOVERED` | p50 193 s, p90 458 s, max 1053 s | 18 |
| start -> result, RECOVERED without a slot wait | p50 116.5 s, p90 468 s | 10 |
| Capacity wait lines in detached logs (all time) | 9 lines in 6 runs (2026-09-30 to 10-02): active 4, reserve-active 4, segments 1 (54.27% > 50%) ; 0 of the 6 parked | 6 |
| Admit-lock time steals in logs | 1 (">300s", old default) | 1 |
| `--recover` run dirs since the pool landed (2026-09-21T06:05Z) | 0; newest is `20260920T224224Z` | 10 |
| Live state now | `one-slots/` empty, `admit.lock` absent, no `lr-fleet.sh` process (`ls`, `ps`) | n/a |
| Env overrides of either cap | none in LaunchAgent plists or shell profiles (`grep -l`) | n/a |

Context outside this lane (READ from the same ledger): `lr-handoff` probes refused 17 times on 2026-10-04, 9 on segments (59.55-63.43% vs the 50% ceiling) and 8 on reserve-active. The one I traced (762a6daa, 15:53:18Z) was not started by `lr-fleet` (its fleet run had already ended as a nudge at 15:52:38Z). The segment ceiling for swaps was raised to 90% the same day (`85fb15804`).

## 7. KQ4 — theoretical throughput at N = 20

Inputs: S = 193 s (p50 rank -> result, RECOVERED, n=18); A = 13.2 s (p50 admit hold, n=55). All rows ESTIMATED from those measured inputs.

| Case | Formula | Wall for 20 |
|---|---|---|
| `--one` lane today, K=2 | ceil(N/K) x S | 10 x 193 s = 32 min (p50 S); 76 min at p90 S (458 s); 0.62 per min |
| `--recover` pool today, K=2, documented S 115-658 s (`:1341`) | 10 x S | 19 to 110 min |
| 20 detached `--one` launched together, 900 s slot clock | served = 2 x (floor(900/S) + 1) | S=193: 10 served, 10 PARK; S=116.5: 16 served, 4 PARK |
| Unattended, 20 on one account | 4 per tick, tick gap p50 11.3 min (`kmax-decision-8.md` item 8) | last dispatch about 45 min after the first, before any slot wait |
| K=6 | max(ceil(N/K) x S, N x A) | max(772, 264) s = 13 min |
| No cap | N x A + S | 457 s = 7.6 min at p50 A; 23.6 min at p90 A (61.2 s) |
| Active ceiling as the floor | at most 8 - other mid-turn sessions (7 with operator present), tokens in flight counted | not quantifiable without turn lengths; the term read 0 on 55 of 55 probes |

Order in which bounds bind as K rises: cap of 2 -> serial admit lock -> active ceiling 8 -> memory terms (11.75 to 34.39 GB reclaimable against a 4 to 10 GB floor).

## 8. Defects found on the way

1. **Phantom-active correction is inert on the first probe of every process.** `lr-lib.sh:423` tests `command -v cc_sp_active` before `cc_capacity_probe` runs, and `spawn-presence.sh` is only sourced lazily inside `cc_capacity_admit` (`capacity-admit.sh:510-532`, called at `:1238`). READ. Receipt (MEASURED): `fleet/one-20261001T202117Z-3a06361f/detached.log` line 3 refuses at "5 sessions mid-turn" with no correction line; line 4 "active census 5 includes 1 limit-corpse beat(s) — probing at 4" appears only before the second probe. All 5 logs that carry a correction line are logs with a capacity wait.
2. **From the second probe on, the correction scans every beat file with one `jq` each.** `lr-lib.sh:362-367`. `~/.claude/cc-beats` holds 6,914 files (4,737 stop, 2,177 prompt; 47 modified in 24 h; 6,409 older than 7 d) (MEASURED). A bash loop of the same `jq` took 16.6 s for 1,500 files at load1 115 (MEASURED) -> about 77 s for the full scan (ESTIMATED), paid inside the admit lock. `cc_sp_active` itself reads only beats inside `CC_SP_ACTIVE_WINDOW_S` (86,400 s, `spawn-presence.sh:334-357`), so older corpses are subtracted without ever having been counted.
3. **Stale prose** at `commands/limit-recover.md:597` and `lr-fleet.sh:22` (section 3).
4. **Lock header overstates** what the probe sees (section 4, last bullet).

## 9. Proposed changes

| # | Change | Files | Conviction | Risk |
|---|---|---|---|---|
| 1 | Raise both defaults 2 -> 6 (`LR_RECOVER_MAX_CONCURRENT`, `LR_ONE_MAX_CONCURRENT`); trial first by env, no code change | `lr-fleet.sh:1362-1363,1381-1382`, `tests/lr-fleet.bats` R12 cases | 60% | first-turn bursts above 6 per account unmeasured, and the 0/40 probe used one-word cold starts; box at load1 115; needs change 2 |
| 2 | Scale the admit-lock steal bound with the cap: default `max(600, (K-1) x (LR_FLEET_CAP_WAIT_S + 80))` | `lr-fleet.sh:605` | 70% | a wedged live holder stalls the lane longer before the loud steal |
| 3 | Bound `lr_phantom_actives` to beats inside `CC_SP_ACTIVE_WINDOW_S` in one `jq` pass, then load the presence library before the `command -v cc_sp_active` test | `lr-lib.sh:358-386,423` (shared with lr-handoff, lr-upgrade, move lane) | 72% | changes the first-probe verdict for every caller of the probe; under-refuse direction only |
| 4 | Correct "one session at a time" to the pool wording | `commands/limit-recover.md:597`, `lr-fleet.sh:22` | 90% | none beyond the skill text edit |
| 5 | Drive "rotate all" through one pool process (waits for a slot, single census, single report) rather than N detached `--one` drivers under the 900 s park clock | `bin/cc-lr` caller, `lr-fleet.sh --recover` | 55% | the pool has 0 runs on record since it landed; proven by bats stubs only |

## 10. Alternatives considered

- Remove both caps: rejected. Six or more waiters behind 120 s parks reach the 600 s steal (5 x 120 s), which the header calls a double admission (`:599-602`).
- Shrink the lock to the rank alone: rejected by the header (`:590-592`); the probe is the term that goes stale.
- Release the `--one` slot before the proof wait: rejected. The cap's stated purpose is first-turn burst protection and the first turn happens inside that wait.
- Per-account pacer (3 per account, `lr_recon/admit.py`) instead of a box-wide count: the designed successor, not live (`recon.on` absent).
- Loosen memory terms: no evidence for it in this lane (0 refusals in 55).

## 11. Uncertainties

- Mid-turn count read 0 on 55 of 55 `lr-fleet` probes while in-session `lr-handoff` probes read 3 to 7 in the same days; only one near pair exists (0 vs 3, 117 s apart). True zero or a context-dependent census: not determined.
- No post-pool `--recover` run exists, so pool-lane S is the comment's 115-658 s (2026-09-19), not a fresh measurement.
- Admit-hold figures rest on a timestamp join at 1 s resolution; a sid with several runs can mis-pair.
- The 77 s scan figure was taken at load1 115 and extrapolated from 1,500 files.
- First-turn behaviour above 6 simultaneous starts per account is unmeasured (decision 8 residual 1).
- `lr_recon/plan.py:437` takes `locks/admit.lock`; `lr-fleet.sh:90` takes `$STATE/admit.lock`. Whether these resolve to one path was not checked; the reconciler is off.
- Per-rotation memory cost was not measured here (neighbor slots).

## 12. What I ran

All read-only: `git log -S`, `git blame`, `git show --stat`, `grep`, `sed -n`, `diff -q`, `ls`, `ps`, `uptime`, `sysctl -n vm.swapusage` (2,173.75 M of 3,072 M used), `memory_pressure` (77% free), `python3 -c` aggregations over `fleet/*/results.tsv`, `detached.log`, `rank.timing` and `idl.jsonl`, and a `jq` read loop over beat files. No `cc-lr`, `cc-limited`, `lr-*.sh` or `claude-accounts` was executed. `--dry-run` was not used: it writes a run dir and `fleet/last` (`lr-fleet.sh:1595,1689`).
