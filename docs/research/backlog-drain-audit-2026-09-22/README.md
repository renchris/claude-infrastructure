# cc-backlog drain pipelines — productivity audit, 2026-09-22

Eight parallel read-only measurement agents against three subjects the operator named: the 24/7
LOCAL drain pipeline, the 24/7 CLOUD drain pipeline, and the cc-backlog store itself. Per-axis
reports are the files beside this one; every number below is re-derivable from the commands they
record. Nothing was mutated: no store write, no fire, no land.

---

## Headline

**All three subjects are productive. None is failing the way the phrase "drain to zero" implies —
and "drain to zero" is unreachable by construction rather than by underperformance.**

`cc-dispatch` selects `status=="open"` only (`bin/cc-dispatch:1921`). The live pile is **350 rows:
340 blocked, 10 open, 0 claimed.** The lanes' addressable queue is therefore **2.9%**, and only
**2 of those 10** sit in a project listed in `scripts/dispatch-projects.conf`. The pile did not
drain — it **sorted**: against the 2026-09-04 baseline in `BACKLOG_ZERO_2026-09-04.md` §1, open went
371 → 10 (−97%) while blocked went 243 → 340 (+40%). Blocked is now 97.1% of live.

The single best positive number, which no routine instrument reports: **1,576 landed commits on
`origin/main` cite a backlog id — 29.0% of the repo's 5,433-commit history, 651 in the last 30
days.** All 1,165 distinct cited tokens fail `git cat-file`, so these are ids, not short shas
misread. Median lag from row-filed to citing-commit is **101 h**, 40.1% over seven days: the rows
**drove** the commits rather than recording them. The ledger is load-bearing. The autonomous lanes
are a **32.6% consumer** of it; the rest is sessions working rows by hand.

---

## The three subjects

### 1. There are THREE lanes, not two — and the most productive local one has no clock

| lane | clock | state | measured yield |
|---|---|---|---|
| **dispatcher** (local) | `com.claude.dispatcher`, 300 s, loaded | alive | **259 closes / 30 d** — all 259 in the 15.2 d after the 09-07 un-park, exactly **0** in the 15 d before |
| **drain-chain** (local) | **none — in no launchd plist** | **dead 12.3 d** (since 2026-09-09) | 397 closes before death; landed trunk content for **124 of 397 (31.2%)** |
| **cloud** | `com.chrisren.autonomy-sweep` (300 s) + dispatcher | alive; landed work 4 h before the probe | **116 distinct rows → landed on `origin/main` over 45 d** |

`launchctl list | grep claude` misses the cloud return half because it is `com.chrisren.*`, not
`com.claude.*`. Both halves logged within 15 minutes of the audit.

The cloud lane is the **most productive of the three**. Its leak is waste, not loss: 545 of 727
declarations (74.9%) re-fire an item already out there; one item was fired 38 times.

### 2. The dominant defect is upstream of every lane: the worker is never born

**805 of 972 claims in 7 days (82.8%) ended `reopen / releaseReason:"spawn-fail"`** — `cc-dispatch`
claims the row, `handoff-fire.sh` refuses, the claim rolls back seconds later. **Pick-to-landed is
5.9%** (57 of 972). 62 distinct rows are in that loop on a ~15-minute cycle.

Two causes, from `cc-dispatch`'s own `action:"failed"` rows: **rc=3** the pane-id-lint payload gate
(196 aborts / 69 h) and **rc=1** no pane anchor / iTerm2 congested (314). Separately, handoff-fire's
load gate rejected **470** spawns at box load 23–26 against a 2.0/core ceiling.

The ceiling was never what bound it: `free_slots == 0` in **0 of 5,766** passes, `live_workers`
peaked at 8 against `CEILING=12`. The lane idled with capacity in hand because the box was too
loaded to fire — not because the queue was empty.

**The emblematic bug is self-referential.** Row `d6d7edef60a3`'s title is *about* handoff-fire's
pane-id gates; the dispatcher embeds the title in the generated brief; the pane-id lint convicts the
brief for containing it. **382 claim→refuse→reopen cycles over 11 days**, 774 records, still cycling
during the audit. **78.4% of all local dispatcher claims end in `reopen`.**

The brake that would catch this was disarmed deliberately and correctly: `bin/cc-backlog:6449`
— *"A SELF-RELEASE IS NOT A THRASH CYCLE"* — added because reap rule B was blocking 228 rows on
dispatcher rollbacks. Side effect: a row that cannot spawn is never blocked and never reaped.
`drain-pick.sh` does hold it (`thrash_held`, claims ≥ 5); `cc-dispatch` does not. **Two arbiters,
one store, opposite answers.**

**Nothing closes a row on a land.** `grep -c 'cc-backlog done' scripts/ship-land.sh` → **0**. On the
local lane the only closer is a worker obeying a sentence in a generated markdown brief
(`drain-brief.template.md:64`). The automatic closers are `cc-premise:2914` (falsifier passed —
*moot*, not work) and `cloud-return.sh` step 8 (cloud only).

### 3. The store is healthy; the FILING door is where the pile comes from

3,740 distinct items over 23,348 records, **0 malformed lines**, two independent folds agreeing
exactly. Duplicates are effectively solved — 94% of live rows are condition-keyed, near-duplicate
clustering is 2.9%.

**Closure quality: 38.4% of terminal closures carry a trunk-verified artifact; 47.3% are no-ops.**
Restricted to the population the git oracle can judge (`project=claude-infrastructure`, n=2,408):
**50.4% delivered, 39.2% no-op.** This re-derives the recorded lesson (*"40-55% of closures were
no-ops"*) exactly. **Zero fabricated closures in 30 verified rows** — 15/15 cited shas are live
ancestors of `origin/main`, 21/21 cited paths present. *The defect is not lying; it is closing rows
that never needed work.* 35.4% of all `done` events are falsifier/premise retractions, not delivery.

**The four-class impossibility gate binds one verb.** `add --why-not-now` validates the class
(rc 2 otherwise), but **65.3% of the pile enters via `needs`/`block`, which validate non-emptiness
only**. Result: **305 of 340 blocked rows (89.7%) carry no impossibility class**, 183 of 340 were
last re-checked >14 d ago, and only **9.1% carry a falsifier** against a p50 age of 26 d. Honest
counterfactual queue had the rule been enforced at filing: **~250–270, not ~20** — so this is a
real filing defect of ~24–31%, not the 90% a first look suggests.

---

## The through-line: five instruments are dead, and each died silently

This is the finding that generalises past the backlog. Every one of these is a detector that ran,
exited 0 or near-0, and reported nothing while the thing it watched was broken.

| instrument | state | mechanism |
|---|---|---|
| `drain-chain-assert.sh` | ~1,700 runs since the chain died, **filed nothing** | files via `cc-backlog add --condition local-drain-chain-dead` with both streams to `/dev/null` and `exit 0` regardless (`:326-339`); an `add` on a **done-latched** condition warns to stderr and appends nothing (`cc-backlog:2155`). The only such row ever was closed 2026-09-04 — **five days before the chain died**. |
| `cloud-lane-liveness.sh` | permanently **VOID** (exit 3), 6 days | baseline pinned to a floor of 426 refs; its own sibling `branch-prune-landed.sh` deleted 76 between 09-05 and 09-15. Observed 334. Cannot recover. Journals `fire_read_rc:"3"` every ~10 min into a log nobody reads. |
| `cc-quota-price` | abstains on **every** window | `weekly_reset_at` carries per-sample microseconds (186 distinct strings per account-day for a reset identical to the second); `buckets()` string-compares it → **625 of 690 buckets dropped** as "reset-changed". Cost-per-closed-item is therefore not computable today. |
| `cc-discover`'s self-report | inflated **~69×** (275 claimed vs 4 real adds) | `backlog_count()` is `wc -l` on the shared store; `cc-backlog` fires `dispatch_kick` on rc 0 *including a deduped add*, and that dispatcher's 1,674 writes land inside the n0..n1 bracket. **The supply side's only self-report measures the drain it just woke.** |
| `backlog-ratchet` | rc 1 for 41 days, now **unreachably green** | the drain's own success drove its denominator (9) below its own floor (20). |

Beside them, one critic is structurally dead: **C1 `frontier-hole` has minted 0 in 67 days** — its
regex `^### H-[0-9].*OPEN` cannot match the live ledger's `H-INERT-1` / `H-CAP-1` headings.

And the operator-facing chokepoint is a *sixth* blind spot of the same family: the two rows
`operator-readout.sh` names as where "work keeps stopping" are both condition-keyed cloud-session
rows that took **65 block events in September alone**, naming 8 distinct cloud sessions — each one a
cloud session stalled on a permission grant or a question answerable only in the cloud web UI. A
human-in-the-loop requirement sitting inside an unattended 24/7 lane.

---

## Convergence, stated honestly

Two windows, both correct, and they disagree about direction:

- **30 days:** add 1,141 / done 1,345 = **net −204**. Dominated by one 5-day wave, 2026-09-05→09-09,
  which took live 589 → 344.
- **Last 14 days:** **+20.45 / week**, and the blocked stratum alone is **+45.75 / week** in every
  window.

The 28-day −80.74/wk slope that projects zero on 2026-10-22 is a **dead regime**. No zero-crossing
exists in the current one. Two shipped instruments disagree on the sign at this moment — telemetry
says `net −1`, `backlog-flow-assert` says `+3`, same store, same hour — because the window
definition, not the pipeline, decides a criterion whose margin is |net| ≤ 3 on ~220.

## Quota

The **"unused weekly quota is decaying inventory, so the pipelines' opportunity cost is ~zero"**
defence **fails on current data**: the last **7 consecutive resets all finished 100% used / 0 pp
stranded** (09-12 → 09-20). Opportunity cost is 1:1. Box contention nevertheless **acquits** the
pipelines: `r(spawns/day, non-OK%) = −0.276`, negative. Note the live `/accounts` strand nowcast
forecasts ~181 pp dying in 4–5 days; the replay says the last seven resets did not strand. The
nowcast is a forecast, the replay is an outcome — trust the replay.

## Design record

**26 of 47 named mechanisms are in force (55%). Only 2 are prose-only.** The dominant failure mode
is **BUILT-AND-INERT**, not unbuilt. Specifically:

- The **READINESS gate**: all three waves CLOSED, the gate BUILT — and `gate:"advisory"` in
  **6,296 of 6,296** dispatcher passes, reading `would_block: 100%` in 2,007 of them. It has blocked
  nothing, ever. The dispatcher plist still describes it as *"filed, not built."*
- `CC_DISPATCH_VENUE_ONLY=cloud` is **not** on the live daemon, refuting two load-bearing safety
  comments in `cc-dispatch` (`:1043`, `:3269`) and `CLOUD_BACKLOG_PIPELINE.md`'s fact table.
- The **"332 unlanded cloud declarations against a cap of 50"** refusal is **not in force**:
  re-running the predicate by hand gives **0 pending against a cap of 50**. It held 58.8 h
  (09-04T19:38Z → 09-07T06:23Z) and `cloud-retire-terminal.sh` drained it. The plist comment still
  presents it as current.
- `cc-cloud`'s `landed()` returns "not landed" on empty `paths=`, and 598 of 727 declarations have
  empty paths — so its own STALLED count is largely decay, not unlanded work.

## What could not be measured

- **Cost per closed item** — blocked on the `cc-quota-price` bucket defect above. The missing unit
  is pp/Mtok. The existing `$3.35/closure` figure is off-currency
  (`usage_credits_authorized=false`).
- **Per-agent closure quality** — the join key is extinct: 0 of 150 commits carry a session trailer.
- **IDL retention is 11.36 days**, not 30, so every per-pass figure is bounded by that; all 30-day
  figures come from `backlog.jsonl`.
- **Premise liveness on 90% of the pile** — only 34 of 350 live rows carry a falsifier, so the rest
  is asserted live and never measured.
- **981 closures (29%)** whose work lives in repos this oracle cannot see.
