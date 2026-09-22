# A5 — SUPPLY SIDE of cc-backlog: producers, rates, and whether drain-to-zero is reachable

Read-only probe, 2026-09-22. Store: `~/.claude/autonomy/backlog.jsonl`, 23,348 records,
2026-07-18T23:23:56Z → 2026-09-22T05:56:45Z = **67 days** (the store is younger than the
requested 12-week window; 67 days IS the whole history).

---

## 1. HEADLINE — supply:drain and the convergence verdict

| window | new distinct items/day | first-`done`/day | supply:drain | net |
|---|---|---|---|---|
| full 67 d | **55.82** | **50.66** | **1.102 : 1** | +5.16/d (+346) |
| last 28 d | 31.21 | 37.79 | **0.826 : 1** | −6.57/d |
| last 14 d | 36.71 | 36.43 | **1.008 : 1** | +0.29/d |
| 5.23 d discovery-log window | 36.10 | 32.86 | 1.099 : 1 | +3.24/d |

**VERDICT: drain-to-zero is NOT arithmetically impossible, and on the queue the dispatcher
actually drains it has essentially already happened.** The live fold is
`open=10 · blocked=340 · done=3390` (3,740 total; my event replay reproduces it exactly).

Two separate arithmetics, and conflating them is what makes the system look divergent:

- **OPEN** (what `cc-dispatch` pulls): slope **−7.52 items/day** since 2026-08-08.
  350 on 2026-09-01 → **10 today**. Of those 10, **8 sit in projects absent from
  `scripts/dispatch-projects.conf`** (sevenrooms-bridge 6, personal 1, voiceink 1) and are
  therefore structurally unreachable by the dispatcher — it prints the refusal 517 times in
  the current log. **Only 2 open items are genuinely dispatchable.** Converged.
- **BLOCKED** (operator-owned, no lane drains it): slope **+3.57 items/day** since
  2026-08-08. 169 → **340**. Median age 27 d, p90 46 d, max 64 d (= store age).
  Entry 20.64/d vs unblock 3.93/d over the last 28 d = **5.3:1**.
- **LIVE (open+blocked)** slope **−3.95 items/day** — falling, but only because OPEN is
  falling faster than BLOCKED is rising. LIVE has sat in a 330–580 band since 2026-08-08.

So the honest statement is: **supply does not exceed drain; supply RE-ROUTES.** Work leaves
the drainable queue and accumulates in the operator-owned one at +3.6/day. The pump that
would make convergence impossible does not exist — **97% of the standing 340 blocked rows
are one-off agent/operator judgment filings, not a generator** (see §2.4).

**And 47.9% of the drain is not work.** Classifying all 3,394 first-`done` records by their
`evidence` string: substantive 1,767 (52.1%) · retracted/flood 646 (19.0%) · stale/obsolete
368 (10.8%) · consolidated/pruned 305 (9.0%) · falsifier-passed 119 (3.5%) · no evidence 95
(2.8%) · already-landed-litter 94 (2.8%). This matches the resident lesson
`closure-count-is-not-value-delivered` ("40–55% of closures were no-ops") to the point.
Roughly half of both sides of the ratio is one machine retracting another machine's output.

---

## 2. The critic roster and the per-producer tables

### 2.1 Standing critics inside `bin/cc-discover` (529 lines, 4 critics, no more)

| # | critic | fn @ line | source it reads | event/state it keys on | idempotent? | adds ever |
|---|---|---|---|---|---|---|
| C1 | `frontier-hole` | `critic_frontier_hole` **:175–193** | `CC_DISCOVER_FRONTIER_LEDGER` (`docs/research/FRONTIER_HOLES.md`) | `grep -E '^###[[:space:]]+H-[0-9].*OPEN'` | yes (hash on title) | **0** |
| C2 | `plan-open` | `critic_plan_open` **:195–299** | `find-plan.sh --list-open`, screened by `plan-phase-scan.sh --falsify` (:290) | a plan row whose YAML frontmatter says open AND whose phase-scan does not print `FALSIFIED` | yes, **but see §6** | **471** |
| C3 | `wiring-inert` | `critic_wiring_inert` **:301–335** | `~/.claude/autonomy/idl.jsonl` snapshot | a hook with ≥`INERT_MIN`(10) in-horizon (`168 h`) evals, ALL abstentions, ALL BLIND-reason | yes | **4** (last 2026-07-19) |
| C4 | `gate-red` | `critic_gate_red` **:337–353** | `$CC_DISCOVER_GATES` = `never-stuck-gate.sh premortem-gate.sh` | a gate script exiting non-zero | yes | **2** (last 2026-07-19) |

Shared machinery: `add_candidate` **:137–155** (one `cc-backlog add` per candidate),
`emit_critic_result` **:157–170**, `run_once` **:355–378** (runs C1→C2→C3→C4 in order),
`abstain` **:118–121** (a missing source ABSTAINS, never fabricates).

**Two of the four critics are structurally dead, and one cannot ever fire.**

- **C1 has minted 0 rows in 67 days and CANNOT match.** The live ledger's headings are
  `### H-INERT-1 · …`, `### H-CAP-1 · …`, `### H-DSH-1 — …`, `### C-CAP-1 …`. The critic's
  regex requires a **digit** immediately after `H-`. `grep -cE '^###[[:space:]]+H-[0-9].*OPEN'`
  on the live file returns **0**; the file contains the word `OPEN` exactly once and was last
  written **2026-08-09** (44 days stale). C1 is a critic whose premise decayed twice over —
  a stale ledger AND a naming convention its pattern no longer describes — and it reports
  `[frontier-hole] passed: 0 candidate(s)`, which is indistinguishable from health.
- **C3 and C4 last fired 2026-07-19** (6 rows total, all in the first 24 h). Both gates
  resolve and both are green; C3's reason-aware exoneration correctly clears every hook.
  They are quiet-because-healthy, not broken — but they carry **0.16% of supply**.
- **C3's horizon rests on a premise that is now false.** `INERT_HORIZON_H=168` (7 days),
  but `idl.jsonl` currently spans **2026-09-22T02:43 → 06:05 = 3.4 hours** (10,888 lines).
  The store is 49× narrower than the window the critic thinks it is asking over. It still
  fires-safe (everything in the file passes a 168 h cutoff), but the designed recency
  semantics are not what is running.

So **cc-discover is effectively a ONE-critic feed**: `plan-open` is 471/477 = **98.7%** of
its output.

### 2.2 cc-discover's own "added N" self-report is inflated ~69×

Measured over `/tmp/claude-discovery.stdout.log` (39 runs, 2026-09-16T22:29:01Z →
2026-09-22T04:07:10Z = 125.64 h; 35 carry a summary line):

- **self-reported**: `sum(added) = 275`, mean **7.86 new items per run**, median 6, max 18.
- **actually in the store** over the identical window, from all four critics: **4 items**
  (`plan-open` on 09-16, 09-17, 09-19, 09-20; one each).
- **inflation factor ≈ 69×.**

Mechanism, read out of the code rather than inferred:

1. `backlog_count()` (**cc-discover:101–104**) is `wc -l` over the SHARED store. Its comment
   says "a NEW add appends exactly one line" — true of an add, false of the file, which
   receives every verb from every producer.
2. `add_candidate` (**:144, :152**) brackets each `cc-backlog add` with `n0`/`n1` and counts
   any growth as its own new item.
3. `cc-backlog`'s `add` arm fires `dispatch_kick` on **rc 0 — including a DEDUPED add**
   (`bin/cc-backlog:7000`, `[ "$_add_rc" -eq 0 ] && … && dispatch_kick`). The kick spawns a
   full `cc-dispatch --decide` pass, debounced at 30 s (`:6957`).
4. That dispatcher pass writes `claim` / `reopen` rows into the same file, *inside* the
   n0..n1 bracket. Measured in the window: **912 `claim` + 762 `reopen` = 1,674 records**,
   against 189 `add`. Total store append rate **20.68 records/hour**.

So a 47-candidate `plan-open` pass wakes the dispatcher roughly every 30 s of its own
runtime and then counts the dispatcher's lease churn as its own discoveries. **The supply
side's only self-report is a measurement of the drain side it just woke up.** Do not quote
`cc-discover: N added` for anything.

### 2.3 Per-producer supply, by ISO week (`event=="add"`, 3,740 records)

Producer classes: cc-discover critic = source ∈ {plan-open, frontier-hole, wiring-inert,
gate-red}. Automated script = source ∈ the script-name set in §3, or `source=="needs"` with
a machine title signature (`^re-land `, `^post-deploy `, …) — that is `scripts/ship-land.sh:1315`,
which files `add --source needs`. Everything else is agent/session judgment.

```
PRODUCER                                      07-13  07-20  07-27  08-03  08-10  08-17  08-24  08-31  09-07  09-14  09-21   TOTAL
agent/session: ad-hoc source                     55    137    202    252    253    187     63     51     43     23      1    1267
automated script: ship-land/deploy (needs)         -      -      -      2    218    112     47     63    149     82      7     680
agent-judgment: needs (operator step)              -      -     19    121    117     97     43     35    106     80      6     624
cc-discover critic: plan-open                   394      2     23      9     24      6      -      4      5      4      -     471
agent/session: (no source)                         -      4     17    119     85     93     34     25     40     34      4     455
automated script: postland-verify                  -     17     40     44     19      6      5     22     22     15      5     195
automated script: deploy-live                      -      -      2      5      3      1      -      1      1      4      -      17
automated script: autonomy-sweep                   2      2      5      1      -      -      -      -      -      -      -      10
automated script: close-integrity                  -      -      -      -      9      -      -      -      -      -      -       9
cc-discover critic: wiring-inert                   4      -      -      -      -      -      -      -      -      -      -       4
cc-discover critic: gate-red                       2      -      -      -      -      -      -      -      -      -      -       2
automated: backlog-consolidation-trigger           -      -      -      -      1      -      -      -      -      -      -       1
automated: settings-drift-assert                   -      -      -      -      1      -      -      -      -      -      -       1
automated: backlog-grouping-sweep                  -      -      -      -      1      -      -      -      -      -      -       1
automated: backlog-ratchet                         -      -      -      -      1      -      -      -      -      -      -       1
automated: drain-chain-assert                      -      -      -      -      -      -      -      1      -      -      -       1
automated: backlog-flow-assert                     -      -      -      -      -      -      -      -      -      1      -       1
-------------------------------------------------------------------------------------------------------------------------------
ALL                                             457    162    308    553    732    502    192    202    366    243     23    3740
```

**AUTOMATED (fires with no human in the loop): 1,394 = 37.3%.
AGENT/SESSION judgment: 2,346 = 62.7%. OPERATOR: 0 measured.**

(The operator has no `cc-backlog add` path — his interface is `cc-do`, which only closes
`needs` rows. 778 distinct `source` values exist and none is operator-shaped. Caveat: a
`source` field cannot distinguish "agent filed this because the operator asked" from
"agent filed this on its own", so 0 is a floor on operator origination, not a proof.)

### 2.4 Who dominates

1. **The session/agent close, by a factor of ~5 over every machine.** 2,346 of 3,740.
   The single largest sub-class is `source=="needs"` filed by an agent (624) plus ad-hoc
   session sources (1,267) plus empty-source (455). `hooks/completion-assert.sh:1278`
   states the same finding from the other side: *"432 of 526 live backlog rows (82.1%)
   exist because a session wrote something down instead of finishing or dropping it."*
2. **`scripts/ship-land.sh`'s re-land filer, 680 rows (18.2%)** — the largest single
   machine producer, and it is a *pump with a matching drain*: 264 of its rows close with
   `auto-retracted at filing: land-content-verify…` in the same breath.
3. **cc-discover, 477 rows (12.8%) — and 394 of those (82.6%) were minted in week 1**,
   the 2026-07-19 unscoped-flood the code itself documents at `cc-discover:225-228`
   ("one --once added 261 foreign 'advance' items"). 387 of them were mass-closed with
   evidence `C2-unscoped flood retracted; scoped default la…`. **Since 2026-07-26,
   cc-discover has supplied 83 items over 59 days = 1.41/day = 2.5% of total supply.**
4. `postland-verify` 195 (5.2%), `deploy-live` 17, everything else ≤ 10.

### 2.5 Two named scope items are NOT part of this system

- **`bin/cc-suggest-filter` (523 lines) has nothing to do with the backlog.** It is a local
  port of Claude Code's `TM_` prompt-suggestion rejection ladder (see its header). Repo-wide
  grep for callers outside its own file: **zero**. It neither files nor suppresses backlog rows.
- **`bin/cc-eligible` (1,631 lines) is a DRAIN-side gate, not a supply filter.** It answers
  "may this item run off-box in a cloud VM", consumed at `cc-backlog claim --venue cloud`.
  It can refuse a claim; it cannot refuse a filing.

---

## 3. Every filing site found

Grep basis: `hooks/ scripts/ bin/` for `cc-backlog add`, `cc-backlog needs`, `cc-backlog block`,
then filtered to *executable* invocations (prose inside hook `reason=` strings excluded).

### 3.1 AUTOMATED filers — fire with no human, 17 sites in 12 files

| file:line | verb | `--source` | trigger | scheduled by | matching drainer? |
|---|---|---|---|---|---|
| `bin/cc-discover:191` (C1) | add | `frontier-hole` | OPEN hole in ledger | `com.claude.discovery` 3600 s | yes (`cc-dispatch`) — **but 0 output ever** |
| `bin/cc-discover:288` (C2) | add | `plan-open` | open plan row | same | yes |
| `bin/cc-discover:331` (C3) | add | `wiring-inert` | all-blind hook | same | yes |
| `bin/cc-discover:347` (C4) | add | `gate-red` | gate exits ≠ 0 | same | yes |
| `scripts/ship-land.sh:1315` | add | `needs` (born blocked) | every FAILED land | `/ship` (agent-fired) | **yes — its own `--falsifier` retracts it** |
| `scripts/ship-land.sh:1344` | needs | `needs` | fallback when `add --run` unsupported | same | yes |
| `scripts/postland-verify.sh:962` | add | `postland-verify` | post-land RED/HUNG | `com.claude.postland-verify`, `com.claude.deploy-live`, autonomy-sweep | partial (§6) |
| `scripts/postland-verify.sh:3638` | add (`--condition`) | `postland-verify` | failing entry, condition-keyed | same | yes — condition key dedupes |
| `scripts/deploy-live.sh:1044` | add | `deploy-live` | post-deploy HOST CUT | `com.claude.deploy-live` 600 s | yes |
| `scripts/deploy-live.sh:1259` | add | `deploy-live` | post-deploy HOST RED | same | yes |
| `scripts/deploy-live.sh:812,813` | needs | `needs` | converge refused | same | operator (`cc-do`) |
| `scripts/deploy-migrations.sh:297,299` | needs | `needs` | un-run migration | via deploy-live | operator |
| `scripts/autonomy-sweep.sh:1081` | add | `autonomy-sweep` | class-B decision default fired | `com.chrisren.autonomy-sweep` **300 s** | yes |
| `scripts/autonomy-sweep.sh:1694` | add | `backlog-ratchet` | falsifier coverage below high-water | same | yes |
| `scripts/backlog-grouping-sweep.sh:111,195` | add | `backlog-grouping-sweep` | sweep cannot run / ungrouped rows above floor | autonomy-sweep:1197 | yes |
| `scripts/backlog-consolidation-trigger.sh:121,391` | add | `backlog-consolidation-trigger` | clusters ≥ threshold | autonomy-sweep:1195 | yes |
| `scripts/settings-drift-assert.sh:267` | add | `settings-drift-assert` | guardrail missing in a config dir | autonomy-sweep:488/510 | yes |
| `scripts/drain-chain-assert.sh:332` | add | `drain-chain-assert` | drain chain broken | autonomy-sweep:543 | yes |
| `scripts/backlog-flow-assert.sh:239` | add | `backlog-flow-assert` | flow invariant broken | autonomy-sweep:547 | yes |
| `scripts/custody-deathwatch.sh:389` | needs | `needs` | undischarged custody debt | autonomy-sweep:1914 | operator |
| `scripts/boot-resume.sh:412` | needs | `needs` | sessions open at boot, no desk | `com.claude.boot-resume` | operator |
| `scripts/cloud-return.sh:952` | **block** | — | a cloud worker parked a row | autonomy-sweep:669/687 | operator |
| `scripts/drain-peer-findings.py` | add (via `bin/cc-backlog`) | varies | peer findings drain | agent-run | yes |
| `scripts/cloud-answer.py:206` | needs | `needs` | cloud answer path | agent-run | operator |

**The finding that matters here: every one of the eight `*-assert` / `*-sweep` /
`*-trigger` filers rides `scripts/autonomy-sweep.sh`, which is a launchd job at
`StartInterval 300` — the SAME 5-minute clock as the dispatcher, not the hourly one.**
The plist's "deliberate asymmetry" therefore governs only `cc-discover`, which is the
least productive automated producer in the system (2.5% of supply since week 1).

**An automated filer with no matching drainer — the "pump into a bucket" test:** the only
class that qualifies is the `needs` verb. Every `needs` row is **born blocked** and
deliberately skips `dispatch_kick` (`bin/cc-backlog:799, :2295, :3643, :7027`), so no lane
drains it — only `cc-do` run by the operator. **Automated `needs` filers: 7 sites**
(ship-land ×2, deploy-live ×2, deploy-migrations ×2, custody-deathwatch, boot-resume,
cloud-answer). Their measured contribution to the STANDING blocked pile, however, is
**10 of 340 = 3%** (§2.4), because ship-land's rows self-retract via their stored falsifier
and deploy-live's are condition-keyed. The pump exists; the bucket it fills is nearly empty.

### 3.2 HOOKS — zero direct filers, two compulsion pumps

No hook in `hooks/` invokes `cc-backlog` at all. Every grep hit is **prose inside a
`reason=` string** that a Stop hook feeds back to the model. Two of them are pumps in the
causal sense — they BLOCK the close until a durable record exists:

| hook:line | mechanism |
|---|---|
| `hooks/dispatch-assert.sh:224, :256` | Stop hook. Fire predicate = `naming-tell ∧ no-queue-write ∧ ¬kill-switch`. Blocks the close and hands over the literal `cc-backlog add …` / `cc-backlog block … --needs` / `cc-decide open` commands. Registered at `~/.claude/settings.json:1009`. Measured in the (3.4 h) IDL: **114 abstained, 1 fired**. |
| `hooks/completion-assert.sh:1277–1279` | Stop hook, D1/D4/D5 arms. Same shape; D4's text is the "432 of 526 live rows (82.1%)" citation. |
| `hooks/memory-nudge.sh:341`, `hooks/lib/memory-index-budget.sh:380` | advisory only — prescribe `add --condition memory-index-over-budget` so the condition key collapses 21 measurements into 1 row. A SUPPRESSOR, not a filer. |

This is why the producer table reads 62.7% agent-judgment: the hooks generate the
*obligation*, the agent's close generates the *row*. Neither is visible as a machine
`source` value.

---

## 4. Measured cadence — testing the plist's "deliberate asymmetry"

The plist comment: *"StartInterval STAYS 3600 while the dispatcher's drops 900 → 300 …
discovering faster refills a queue nothing drains (F15)."*

**A cadence in a config file is a REQUEST. Counted events, not the config:**

| job | requested | **measured** | delivery | window |
|---|---|---|---|---|
| `com.claude.discovery` | 1.000 runs/h | **0.310 runs/h** (39 runs / 125.64 h) | **31%** | 2026-09-16T22:29 → 2026-09-22T04:07 (run headers in `/tmp/claude-discovery.stdout.log`) |
| `com.claude.dispatcher` | 12.00 passes/h | **4.02 passes/h** (517 passes / 128.45 h) | **34%** | log birth 2026-09-16T16:34 → mtime 2026-09-22T01:01 (`/tmp/claude-dispatcher.stderr.log`) |

Both jobs are throttled by roughly the same factor (machine sleep; both are
`ProcessType Background`), so **the RATIO survives: measured asymmetry = 13.0× against a
designed 12×.** The reasoning is intact on its own terms.

**But it does not produce the drain-favouring ratio by the route the comment claims,
and the comment's premise is now false:**

| quantity | value |
|---|---|
| items **minted per discovery pass**, all four critics | **0.103** |
| items **closed per dispatcher pass** | **0.333** |
| per-pass drain/supply headroom | **3.2×** |
| …multiplied by the 13.0× cadence asymmetry | **42×** |

So one hourly discovery pass mints 0.103 items and the ~13 dispatcher passes that follow it
close ~4.3. **Each discovery pass is out-drained ~42:1 by the dispatcher passes between
them.** The asymmetry is not merely adequate, it is over-provisioned by 1.5 orders of
magnitude — because C1/C3/C4 are dead (§2.1) and C2 now mints ~1/day.

The comment's stated premise — *"the backlog is already 121 deep … a queue nothing drains"* —
is refuted by the live fold: the **open** queue is **10**, of which **2** are dispatchable.
Holding discovery at 3600 s is currently costing supply, not protecting the queue. (This is
a finding about the reasoning, not a recommendation: C10 says the operator owns this plist,
and the correct move is to fix C1's regex and C2's flood-scoping before touching the clock.)

**Honest gap:** 4 of 39 discovery runs produced no summary line (killed mid-run or the log's
first run was truncated at head). The 275/35 mean uses the 35 that did.

---

## 5. Duplicate suppression — how often a critic defeats its own hash

IDs are `hash(project + title + source)` (`bin/cc-backlog:12, :1084, :2049`), so an identical
re-add is a no-op. The defeat is a **varying title for one logical finding**. Method:
normalise every add title (collapse `\d{8}T\d{6}Z`, ISO dates, 12-hex ids, 7–40-hex shas,
and bare integers to tokens), group by `(project, normalised-title)`, and count surplus
distinct ids per group.

```
total add records                                      3740
distinct ids among adds                                3740   (no id ever re-added — dedupe works at the hash)
normalised-title groups                                3347
groups holding >1 DISTINCT id                            51
SURPLUS ids attributable to title variance              393
HASH-DEFEAT RATE                                       10.5%  of all supply
```

| source | distinct ids | surplus from title variance | rate |
|---|---|---|---|
| `needs` (ship-land re-land) | 1,304 | **320** | **25%** |
| `postland-verify` | 195 | **63** | **32%** |
| `deploy-live` | 17 | 4 | 24% |
| `(empty)` | 451 | 1 | 0% |
| **cc-discover critics** | **477** | **0** | **0%** |

**The critics named in the brief are clean; the automated filers next to them are not.**
Worst three groups:

| distinct ids | source | normalised title |
|---|---|---|
| **112** | needs | `re-land claude/fire-<TS>-<N>-<N>: ship-land could not complete and its author's pane may be gone` |
| **103** | needs | `re-land wt-<ID>: ship-land could not complete and its author's pane may be gone` |
| **68** | needs | `re-land claude/fire-<TS>-<N>-<N> (/private/tmp/.desk-land-…-<N>): ship-land exited <N>` |
| 18 | postland-verify | `post-land RED: tests/deploy-parity.bats @ <ID>` |
| 12 | postland-verify | `post-land RED: tests/capacity-alarm-segments.bats::… column <N>` |

Sampled raw titles for the first group show the exact re-keying tokens:

```
b2335ec192a8  2026-08-12T20:34:09Z  re-land claude/fire-20260812T172113Z-3600-1 (/private/tmp/.desk-land-…-7180):  ship-land exited 143 (SIGTERM) … refs/land/failed/20260812T203351Z-nosid-…
5c9d1ad56b7a  2026-08-12T20:55:51Z  re-land claude/fire-20260812T172113Z-3600-1 (/private/tmp/.desk-land-…-44893): ship-land exited 6   (exit)    … refs/land/failed/20260812T205538Z-nosid-…
d726830de892  2026-08-13T01:23:54Z  re-land claude/fire-20260812T172113Z-3600-1 (/private/tmp/.desk-land-…-69066): ship-land exited 143 (SIGTERM) … refs/land/failed/20260813T012314Z-nosid-…
```

Three re-keying tokens per title: the **per-attempt PID** in the scratch dir, the **exit
code**, and the **timestamped `refs/land/failed/<stamp>` ref**. One logical finding —
*"branch X failed to land"* — minted **41 distinct ids for that single branch**. `cc-backlog`
ships the remedy (`--condition <slug>`, which re-keys the hash to `project+condition` and
drops title+source, `:359, :1090`), and `postland-verify.sh:3638` already uses it via
`cond_slug`; `ship-land.sh:1315` does not.

**Churn is NOT a confound on this.** Only 22 of 3,394 ever-done items (0.6%) were reopened
after `done`; 171 have >1 `done` event. The 2,915 `reopen` records are overwhelmingly
lease releases (314 by `cc-backlog-reap`, the rest by hostname-pid claimers), not re-mints.
First-`done` is therefore a sound drain measure.

---

## 6. Adversarial pass — what I went looking for after the first answer

1. **"Is `blocked` a pump-fed bucket?"** Hypothesis from §5: ship-land's 680 re-land rows
   are born blocked and would pile up. **Refuted by measurement.** Of the standing 340,
   only 10 (3%) are machine-filed; 330 are one-off agent/operator judgment. ship-land's
   rows carry a stored `--falsifier` (`ship-land.sh:1381`) and 264 of them closed with
   `auto-retracted at filing: land-content-verify…`. The pump has its drain.
2. **"Is `done` actually terminal?"** 2,915 `reopen` events looked like re-mint churn.
   Measured: 0.6% reopen-after-done. Not a confound.
3. **"Does the open queue being at 10 mean it drained?"** Only partly — **8 of 10 are in
   projects outside `scripts/dispatch-projects.conf`** (personal, sevenrooms-bridge,
   voiceink), which the dispatcher names in every pass and cannot touch. That is an
   operator-owned config gate masquerading as an `open` row.
4. **"Are the two brief-named tools really supply-side?"** No — `cc-suggest-filter` has
   zero callers and is about Claude Code's prompt-suggestion ladder; `cc-eligible` is a
   claim-time venue gate. Neither files or suppresses a backlog row (§2.5).
5. **"Does any hook file?"** No. The hooks compel; they never write (§3.2).
6. **"Is the discovery job's own count trustworthy?"** No — 69× inflated, mechanism traced
   to `backlog_count()` × `dispatch_kick` (§2.2). This is the single most load-bearing
   correction in this report: taking `cc-discover: N added` at face value would have put
   supply at 52.5 items/day from one producer, and the true figure is 0.76/day.

---

## 7. Every command that produced a number

All scratch scripts persist at `/tmp/backlog-probe/`. Nothing here mutates; `cc-backlog list`
is the only binary invoked and it is a pure read (`bin/cc-backlog:7031`, "Pure read, no
dispatch_kick"), run with `CC_BACKLOG_KICK=off` belt-and-braces. `cc-discover` was **never
executed** — its `--dry-run` exists but even that writes `idl.jsonl`, so the code and the
store were read instead.

```bash
# --- store shape -------------------------------------------------------------
jq -rs 'group_by(.event)|map({event:.[0].event,n:length})|sort_by(-.n)[]|"\(.n)\t\(.event)"' \
   ~/.claude/autonomy/backlog.jsonl
jq -rs '[.[].ts]|[min,max]|@tsv' ~/.claude/autonomy/backlog.jsonl
jq -rs '[.[]|select(.event=="add")]|group_by(.source)|map({s:(.[0].source//"(null)"),n:length})|sort_by(-.n)[]|"\(.n)\t\(.s)"' \
   ~/.claude/autonomy/backlog.jsonl

# --- live fold (open / blocked / done) ---------------------------------------
CC_BACKLOG_KICK=off cc-backlog list --all --json \
  | jq -rs 'if (.[0]|type)=="array" then .[0] else . end|group_by(.status)|map({s:.[0].status,n:length})[]|"\(.n)\t\(.s)"'
#   → 3390 done / 340 blocked / 10 open

# --- supply vs drain, weekly + windowed (§1) ---------------------------------
python3 /tmp/backlog-probe/rate.py
python3 /tmp/backlog-probe/window.py     # window-matched to the discovery log

# --- per-producer weekly table (§2.3) ----------------------------------------
python3 /tmp/backlog-probe/prod.py

# --- queue-depth replay + slopes (§1) ----------------------------------------
#   (state machine add→open, block→blocked, unblock→open, done→done, reopen-after-done→open;
#    reproduces the live fold exactly, which is the control on the replay)
python3 /tmp/backlog-probe/blocked.py

# --- done/reopen churn control (§6.2) ----------------------------------------
python3 /tmp/backlog-probe/churn.py
#   → 22/3394 reopened after done (0.6%)

# --- hash defeat by title variance (§5) --------------------------------------
python3 /tmp/backlog-probe/norm.py
#   → 393 surplus ids, 10.5%

# --- closure-kind classification (§1) ----------------------------------------
jq -rs '[.[]|select(.event=="done")|(.evidence//"(none)")|.[0:46]]|group_by(.)|map({t:.[0],n:length})|sort_by(-.n)[]|"\(.n)\t\(.t)"' \
   ~/.claude/autonomy/backlog.jsonl | head -20
#   + the regex classifier inline in §1 (retract/prune/stale/no-ev vs substantive)

# --- MEASURED cadence, not requested (§4) ------------------------------------
grep -c '^# cc-discover' /tmp/claude-discovery.stdout.log                       # 39 runs
grep '^# cc-discover' /tmp/claude-discovery.stdout.log | head -1; \
grep '^# cc-discover' /tmp/claude-discovery.stdout.log | tail -1                # 125.64 h span
grep '^cc-discover: ' /tmp/claude-discovery.stdout.log | awk '{print $2}' \
  | sort -n | awk '{a[NR]=$1;s+=$1} END{print NR,s,s/NR,a[int((NR+1)/2)],a[1],a[NR]}'
#   → n=35 sum=275 mean=7.857 median=6 min=0 max=18
grep -c 'open item(s) in project(s) OUTSIDE' /tmp/claude-dispatcher.stderr.log  # 517 passes
stat -f '%SB birth %Sm mtime' -t '%Y-%m-%dT%H:%M:%S' /tmp/claude-dispatcher.stderr.log
launchctl print gui/$(id -u)/com.claude.discovery | head -30                    # state = running
plutil -extract StartInterval raw ~/Library/LaunchAgents/com.claude.dispatcher.plist   # 300
plutil -extract StartInterval raw ~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist  # 300

# --- C1 is structurally dead (§2.1) ------------------------------------------
grep -cE '^###[[:space:]]+H-[0-9].*OPEN' \
   ~/Development/claude-infrastructure/docs/research/FRONTIER_HOLES.md     # → 0
grep -nE '^###.*H-' ~/Development/claude-infrastructure/docs/research/FRONTIER_HOLES.md | head
ls -la ~/Development/claude-infrastructure/docs/research/FRONTIER_HOLES.md # mtime Aug  9
jq -rs '[.[]|select(.event=="add" and (.source|IN("gate-red","wiring-inert","frontier-hole")))][]|"\(.ts) \(.source)"' \
   ~/.claude/autonomy/backlog.jsonl                                        # last 2026-07-19

# --- C3's store is 49x narrower than its horizon (§2.1) ----------------------
jq -rs '[.[].ts]|[min,max]|@tsv' ~/.claude/autonomy/idl.jsonl              # 3.4 h span, 10888 lines

# --- filing-site enumeration (§3) --------------------------------------------
grep -rn 'cc-backlog add\|cc-backlog needs\|cc-backlog block' hooks/ scripts/ bin/ commands/
grep -rnE '"\$BACKLOG_BIN" (add|needs|block)|\$BACKLOG" (add|needs)' hooks/ scripts/ bin/
grep -n 'dispatch_kick' bin/cc-backlog                                     # :7000 fires on rc 0
sed -n '99,104p' bin/cc-discover                                           # backlog_count = wc -l
grep -onE '(backlog-grouping-sweep|backlog-consolidation-trigger|settings-drift-assert|drain-chain-assert|backlog-flow-assert|custody-deathwatch|postland-verify|cloud-return)\.sh' \
   scripts/autonomy-sweep.sh                                               # all ride the 300 s sweep

# --- store append rate inside the discovery window (§2.2) --------------------
jq -rs --arg lo 2026-09-16T22:29:01Z --arg hi 2026-09-22T04:07:10Z \
   '[.[]|select(.ts>=$lo and .ts<=$hi)]|group_by(.event)|map({e:.[0].event,n:length})|sort_by(-.n)[]|"\(.n)\t\(.e)"' \
   ~/.claude/autonomy/backlog.jsonl
#   → 2598 records / 125.64 h = 20.68 records/hour; claim 912 + reopen 762 vs add 189
```

---

## 8. What I could not measure

| # | gap | why | direction of the error |
|---|---|---|---|
| 1 | **12 weeks was asked for; the store is 67 days old.** | `backlog.jsonl` begins 2026-07-18T23:23:56Z. No archive found. | The 67-day figures ARE the full history. Week-1 (2026-07-13) is an outlier that pulls the full-window supply:drain up to 1.102; excluding it the ratio is drain-favouring. |
| 2 | **Delivered cadence for `com.chrisren.autonomy-sweep`** (the 300 s clock carrying 8 filers). | Its `.out.log` is 0 bytes; the `.err.log` is silent-when-healthy with no timestamps and no per-pass marker. | Unknown. I assumed it is throttled like its two siblings (~33% delivery) but did NOT measure it. Its 239 recorded `FATAL — cannot source cc-common.sh (resolve_bin unavailable)` lines are undated and could represent a long blind period. |
| 3 | **Operator-originated supply.** | No `source` value is operator-shaped, and the field cannot distinguish "agent filed at the operator's request" from "agent filed unprompted". | "0 operator adds" is a FLOOR, not a proof. Some fraction of the 2,346 agent rows are operator-dictated. |
| 4 | **`dispatch-assert` / `completion-assert` pump volume over the real window.** | `idl.jsonl` retains only 3.4 h (10,888 lines). Measured 114 abstains / 1 fire there; extrapolating to a rate assumes a stationarity I did not test. | Under-measured; the compulsion pump is probably larger than 1 fire. |
| 5 | **Whether `cc-discover` would mint more if C1's regex were fixed.** | Would require running the critic. I refused to run `cc-discover` at all (even `--dry-run` writes `idl.jsonl` via `idl_log`, and `--dry-run` suppresses that only at `:113` — the risk is asymmetric and the brief said read-only). | Unknown. The ledger has 0 items matching `OPEN` under ANY heading spelling today, so a fixed regex would likely still mint 0 until a panel writes a new hole. |
| 6 | **Whether the 8 out-of-dispatch-set OPEN rows are genuinely undrainable or merely unconfigured.** | `dispatch-projects.conf` lists `personal`, `sevenrooms-bridge`, `voiceink` in neither the dispatch set nor the `skip=` set. Deciding is an operator config call. | They will sit at `open` forever with the current conf, which makes the "open queue" number 10 when the drainable number is 2. |
| 7 | **The 4 discovery runs with no summary line.** | Log head truncation vs mid-run kill is indistinguishable from the file. | The 7.86/run mean is over 35 of 39; the inflation finding is unaffected (it rests on 4 real store adds against any denominator). |
| 8 | **Retention/rotation of `/tmp/claude-*.log`.** | Both were born 2026-09-16 (one day after `com.claude.log-rotation` presumably ran). Cadence before that date is unmeasurable. | The 31%/34% delivery figures describe one 5-day window on a laptop, not a standing rate. Re-derive, never re-quote. |
