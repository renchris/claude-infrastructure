# recon-consolidation — why the backlog is still 536 after a consolidation wave
Read-only recon, 2026-08-12. Store: `~/.claude/autonomy/backlog.jsonl` (8,634 records, 2.7 MB).
Live = open ∨ blocked ∨ claimed = **536** (open 321 · blocked 209 · claimed 6). `cc-backlog list --open`
projects **537** because that projection includes blocked rows (known, READINESS §3).

---

## THE ONE-LINE ANSWER

**The consolidation machinery cannot reduce the row count — by design — and the one component that
writes is wired in dry-run behind a flip criterion that is mechanically unreachable.** What actually
shrank the pile on 2026-08-10 was an untracked one-shot Python script (`prune.py`, 161 closes). The
pile refilled past its pre-wave peak in 48 hours.

---

## MECHANISM MAP — each component, wired-or-not, measured effect on the live store

| # | component | anchor | wired to | writes? | measured effect on the live store |
|---|---|---|---|---|---|
| 1 | `cc-backlog dups --mode dodref` | `bin/cc-backlog:45`, header `:308` | **nothing** | no (report) | 10 groups / 39 rows today. Blind to the 77% of rows carrying no `dodRef`. |
| 2 | `dups --mode title` | header `:326` | **nothing** | no | **0 groups** on today's store. Its population aged out (header `:341` admits this; control lives in `tests/cc-backlog-dups-family.bats`). |
| 3 | `dups --mode family` (IDF-weighted identifier containment) | header `:353` | **nothing** | no | 7 orphans with a candidate group today. Zero acted on. |
| 4 | `dups --mode mechanical` (KEY 4) | header `:389` | trigger `--fold` | no (report) | 18 groups / 46 rows. The only key a machine may act on. |
| 5 | `cc-backlog backfill [--apply]` | `bin/cc-backlog:55` | **NO CALLER** | only under `--apply` | Never run. Its absence is itself a filed open row — `073c620b571e`, condition `backfill-proposals-have-no-caller`, which states "grep over scripts/ hooks/ launchd/ finds zero invocations". |
| 6 | `cc-backlog link` | `bin/cc-backlog:33` | link.py (untracked), fold `--apply` | yes | 120 link records total: 6 hand-sweep 2026-08-08, **113 on 2026-08-11 all from `link.py`**, 1 on 08-12. |
| 7 | `backlog-consolidation-trigger.sh` (report/`--assert`) | `scripts/backlog-consolidation-trigger.sh` | — | no | Finds 2 clusters ≥5 today (14× `wt-7ff1b6f5ddbb`, 6× `mcp-w3-no-inherit`). |
| 8 | trigger `--file` (escalate residue) | `:280-305` | `autonomy-sweep.sh:507` | one condition row | `consolidation_trigger_rc:"0"` every sweep. Row exists (`5df742fb3894`) but **its title is frozen** — see finding 4. |
| 9 | **trigger `--fold`** (the only actuator) | `:113 do_fold()`, dry-run default `:65 APPLY=0` | `autonomy-sweep.sh:534` — **`--fold`, never `--fold --apply`** | **no, deliberately** | **10 of 10 recorded runs returned rc 124 (timeout).** See finding 1. |
| 10 | `needs` mint brake | `bin/cc-backlog:1834` | `cmd_needs` itself | re-files onto existing row | Live since 2026-08-12T00:34Z. 6 needs mints since, 1 absorption. |
| 11 | `backlog-ratchet.sh --assert` | `scripts/backlog-ratchet.sh` | `autonomy-sweep.sh:508` | no | RED right now (48.5% vs high-water 50.0%). `ratchet_rc` history: 56 of 154 sweeps = 1. |
| 12 | readiness gate at the dispatch seam | `bin/cc-dispatch:882` | cc-dispatch | no | `CC_DISPATCH_READY_GATE` default **`advisory`**; no override in any settings.json. 15 readiness records total; sampled verdicts all `ready:false` (`cites-nothing`, `no-prior-verdict`) — and admitted anyway. |
| 13 | `cc-premise` falsifier at claim | `bin/cc-premise:1028` | `cc-backlog claim` | **refuses the claim; never closes the row** | A row whose probe says GONE stays live-but-unfireable forever. 147 of 536 live rows carry a probe. |
| 14 | `cc-backlog compact` (drop aged `done`) | `bin/cc-backlog:2759` | **NO CALLER** (grep over `scripts/ hooks/ bin/ LaunchAgents/` finds none) | yes | Never run. 1,369 `done` rows still in every fold — this is the cost that breaks finding 1. |

**Nine of fourteen components have no caller or no write path. The single wired writer is `--fold`,
called in dry-run.**

---

## PRIOR WAVE LEDGER — decided vs landed

The 2026-08-09 wave (`docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md`) adjudicated **460 items** into
`verdicts.json`: KEEP 220 · PRUNE 117 · UPDATE 78 · MERGE 45.

**It landed. Fully.** Cross-checked all 460 ids against the live store:

| verdict | decided | current live status |
|---|---|---|
| PRUNE (117) | close | **117 done — 100%** |
| MERGE (45) | close | **44 done, 1 blocked — 98%** |
| KEEP (220) | keep open | 101 open · 58 blocked · 3 claimed · **58 already done** |
| UPDATE (78) | keep open, restate | 27 open · 32 blocked · **19 already done** |

Ids spot-checked by hand (verdict → live status → condition):
`d5a0cfc1686e` PRUNE→done · `2cb1a174c5bd` PRUNE→done · `e5bfe6d0af02` PRUNE→done ·
`149789b69fc4` PRUNE→done · `3c4083af1397` MERGE→done · `1572de03463c` MERGE→done ·
`986f6d8f9ce2` MERGE→done · `a31d1fe3de3d` MERGE→done · `b38279c10c55` KEEP→open/`master-fleet-footprint` ·
`7c05d45796d8` KEEP→open/`master-convergence-deadlock` · `8ad4b02602dc` KEEP→open/`master-stranded-work` ·
`73b8c28f6aae` UPDATE→open/`master-convergence-deadlock` · `1684440567db` KEEP→blocked · `4abcbbbbc997` UPDATE→open (no condition).

**But the two applying scripts are UNTRACKED** (`git status`: `??`):
`prune.py` (161 closes, `prune-log.txt`, 0 FAIL) and `link.py` (113 links, `link-log.txt`, 0 FAIL).
Both live only in `docs/plans/backlog-consolidation-2026-08-09/`. Neither is in the repo, neither has
a caller, both are one `git clean -f -d` from gone. **The only thing that has ever reduced this pile
is not part of the machine.**

**The 113 links wrote seven hand-authored `master-*` conditions**, not fold slugs — `link.py:26-35`
maps a triage *slice* to a master. Live group sizes today: `master-convergence-deadlock` 35 ·
`master-fire-gate` 22 · `master-fleet-footprint` 20 · `master-stranded-work` 10 · `master-account-facts` 5 ·
`master-enforcing-store` 4 · `memory-index-over-budget` 3. All 29 other live conditions are **n=1**.

**Verdict decay measured: 26% of KEEP and 24% of UPDATE closed within 3 days of being adjudicated
"still true today".** That is the READINESS section's own thesis (`:576`) confirmed by measurement —
a batch review over a growing stream is stale before it is applied.

---

## MEASURED — current consolidation state

**Condition coverage (live 536):** 129 rows carry a condition (24.1%), in **37 distinct groups**.
Of the 37, **29 are n=1** — a "group" of one governs nothing; the condition lease
(`bin/cc-backlog` claim guard 6) has an empty population on those.

**`cc-backlog dups --mode all --json` (10.2 s wall):**

| mode | groups | rows covered | sizes |
|---|---|---|---|
| dodref | 10 | 39 | 8, 7, 5, 4, 3, 3, 3, 2, 2, 2 |
| title | **0** | 0 | — |
| family | 7 orphans w/ candidates | 7 | (proposals, none applied) |
| mechanical | 18 | 46 | 6, 4, 3, 3, 3, 3, then 12× 2 |

**Trigger's own key at threshold 5:** 2 clusters — 14× `re-land wt-7ff1b6f5ddbb`, 6× `re-land mcp-w3-no-inherit`.
The 14× is the nine-different-worktrees false cluster the header (`:396`) documents; mechanical correctly refuses it.

**Independent near-duplicate estimate (two methods, computed here, not from `dups`):**

| method | groups | rows covered | **surplus rows** (rows − groups) |
|---|---|---|---|
| identical 12-word prose prefix + project | 20 | 58 | **38** |
| identical identifier-token set (digit-masked, ≥2 ids) | 19 | 50 | **31** |
| `dups --mode mechanical` (shipped key, both floors) | 18 | 46 | 28 |

**Estimated true-distinct-effort count: ~500 of 536 — roughly 93-95% are genuinely distinct.**
The three independent methods converge on a duplicate surplus of **28-38 rows, i.e. 5-7% of the pile.**

**Composition of the 536:** 460 claude-infrastructure · 76 belong to other repos (reso 54, doc_classifier 15,
work 2, misc 5) and cannot be closed from here. **179 rows are `source:"needs"`** (operator steps),
178 of them blocked — store size, not queue pressure (READINESS measurement #4, `:625`).

**Live-count trajectory, recomputed from the ledger fold:**

```
08-05 323 · 08-06 316 · 08-07 406 · 08-08 434 · 08-09 460  ← triage snapshot ("460 items")
08-10 387  ← prune.py closes 161 (231 done that day)
08-11 514  ← +127 in one day (242 adds)
08-12 537
```

**The wave's entire 161-row gain was erased in under 24 hours, and the pile is now 77 rows above its
pre-consolidation peak.** Adds/day: 156 · 242 · 28(partial). Done/day: 231 · 122 · 6.

---

## THE GAP — why consolidation does not converge

### G1. A fold cannot reduce the count. It is not designed to.
`scripts/backlog-consolidation-trigger.sh:202` asserts `conservation=ok — live 537→537 · open 322→322 ·
id set identical`. The docstring (`:46`) states it outright: *"Absorption is traceability, not closure."*
A `link` record has no status arm. **So even a perfect, fully-applied fold of all 18 mechanical groups
leaves the pile at 536.** The machinery answers *"how many workers may claim this?"* — it has never
answered *"how many rows are open?"*. The operator's question and the machine's question are different
questions, and nothing in the repo maps one to the other.

### G2. The one writing actuator has never completed a single run.
`scripts/autonomy-sweep.sh:534` calls `--fold` (dry-run) under `_bounded` = `timeout -k 5 60`
(`:505`). Every `backlog-health` record ever emitted — 3 in the archives + 7 live, **10 of 10** —
reads `fold_rc:"124"`, `fold_conservation:"no-verdict"`, `fold_verdict_lines:0`.

Measured cause: the fold costs **17.8 s wall in the foreground** (6 × `list --all --json` at 1.98 s +
`dups --mode mechanical` at 2.79 s), at load average 7.9. The sweep runs under
`~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist:14` **`ProcessType: Background`** + `Nice 5`
— the Darwin background QoS band (MEMORY: `darwin-qos-band-mechanics`, PRI 4). A 3.4× headroom does not
survive that band on a 15-session box. **This is MEMORY: `bound-must-fit-the-band-not-the-bench`,
shipped again.**

### G3. …so the flip criterion is mechanically unreachable.
`autonomy-sweep.sh:519-527` states the flip rule verbatim: *"when `fold_conservation` has read `ok`
across a run of sweeps and `fold_groups` is stable rather than drifting, change `--fold` to
`--fold --apply` here."* The series that would authorize the flip is **100% `no-verdict`**. Run in the
foreground today it reports `conservation=ok · 19 groups seen · 18 would fold · 0 ambiguous` — i.e.
**the criterion is already satisfied and no instrument on the box can see it.**
This is MEMORY: `cap-whose-population-is-empty` — the GREEN state does not exist — one layer below
where READINESS measurement #2 (`:610`) already found it in the ratchet.

### G4. The escalation row is frozen at its pre-R6 wording and can never update.
`cmd_add` returns early on a known id (`bin/cc-backlog:1096` — `if has_id "$id"; then … echo "$id"; return 0`),
so a condition-keyed `add` is a **no-op**, not an update. The trigger's `--file` docstring (`:21`)
claims *"repeated runs update rather than mint"*. They do not. Row `5df742fb3894`
(`backlog-duplicate-cluster-over-threshold`) still reads *"2 duplicate cluster(s) at/above 5 rows
(largest 6x)"* — the pre-R6 text, `lastTs 2026-08-11T08:36:59Z`. It contains no `REFUSED`, which the
current code emits (`:299`) and `tests/backlog-consolidation-trigger.bats:185` asserts. **The test
passes against a fixture; the live row has been stale for 26 hours and will stay stale forever.**

### G5. The mint brake covers a third of the store and none of the queue.
R7 (`:673`) calls the `needs` brake *"the only lever that changes the denominator's slope."* It landed
`8f1726cfb` (2026-08-11 17:34 PDT) and is live (`~/.claude/bin/cc-backlog` → the checkout; ancestor of
origin/main confirmed). Since then: **6 needs mints, 1 absorption.** Scope is `needs` only
(`bin/cc-backlog:1834`), which is 179/536 = 33% of the store and — because needs rows are born
blocked — **0% of dispatch pressure**. The 08-11 influx that erased the wave was 242 adds, of which
92 needs and 150 not-needs; the brake reaches none of the 150.

### G6. Nothing closes a row that is provably dead.
`cc-premise` returns `falsified` when a probe exits 0 (`bin/cc-premise:1028`) and that verdict
**refuses the claim** — it does not close the item. So a row whose own falsifier says the condition is
gone becomes permanently live and permanently unfireable. Combined with `cc-backlog compact` having
**no caller at all**, the store has no automatic exit path: 1,369 `done` rows still sit in every fold,
which is exactly the read cost that produces G2.

### G7. The other advisory-first gate never flipped either.
`bin/cc-dispatch:882` — `READY_GATE="${CC_DISPATCH_READY_GATE:-advisory}"`, no override anywhere in
the config dirs. Two flip-gated actuators (fold, readiness), both shipped advisory-first with an
explicit "measure then flip" contract, **neither flipped, and neither has an owner, a schedule, or a
consumer that reads the series.** The advisory-first discipline is correct; what is missing is that
nobody re-reads the measurement it produces.

---

## THE CONVERGENCE ARITHMETIC

- Duplicate surplus that any consolidation could ever remove: **28-38 rows (5-7%)**
- Rows a fold removes: **0** (G1)
- Rows the wired actuator has removed to date: **0** (G2)
- Rows the untracked one-shot script removed: **161** — refilled in 24 h
- Net store growth: **+150/day** on 08-11, **+23** on the partial 08-12

**Consolidation does not converge because it is aimed at the wrong quantity.** The pile is not a
duplicate pile — it is ~93-95% distinct efforts, minted faster than they close, with no automatic
closure path (G6) and no compaction (G14/G6). Deduplication at its theoretical maximum recovers 7%,
once. The wave's own READINESS section reached this conclusion (`:625`, "the consolidation lever is
therefore real but **second-order**") and then built three more deduplication mechanisms anyway.
