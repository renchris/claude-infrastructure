# Is the backlog net-positive, and can it drain to zero? — 2026-08-25

**Scope (frozen):** settle (a) whether filing→completion delay makes cc-backlog completions
non-net-positive against a moved-on HEAD, (b) whether the 24/7 local and cloud drains make real
progress to zero or are a treadmill, and (c) whether a days/weeks/one-month timeline to zero is
reachable.

---

## THE ANSWER

**The pool is 6–8 days of work, and it has not shrunk in 18 days.** Drain *capacity* was never the
constraint — at the measured completion rate the entire 494-item pool clears in 6.3 days (14-day
rate) or 8.4 days (7-day rate), and the agent-actionable part in 3.8–5.0 days. It does not clear
because the machine files new work at almost exactly the rate it completes work, and **80% of what
it files is about its own machinery**.

So: the operator's worry (b) is **confirmed, and it is structural, not a matter of effort**. Worry
(a) — staleness — is **real as exposure but is not the binding constraint**; the binding constraint
is the arrival rate. A days-to-weeks timeline is reachable, but only by changing what gets filed,
not by draining harder.

---

## The measurements

All from `~/.claude/autonomy/backlog.jsonl` (14,173 records, 0 malformed, 2,781 distinct ids,
2026-07-18 → 2026-08-25) and `git` on this checkout. Scripts:
`scratchpad/{fold,trend,drift}.py` (this session).

### Fold — the current state

State is the fold of the `event` field, last transition wins:

| state | count |
|---|---|
| done | 2,288 |
| open | 291 |
| blocked | 197 |
| claimed | 6 |
| **NOT-DONE** | **494** |

Event totals: `add` 2,781 · `claim` 2,779 · `done` 2,441 · `block` 1,784 · `reopen` 1,764 ·
`venue` 934 · `link` 837 · `falsify` 403 · `unblock` 395 · `update` 55.

⚠️ **`reopen` is lease churn, not rework.** 1,764 reopen events looks like massive re-do, but only
**17 ids** were ever `done` and later reopened. `reopen` is what a lease release emits when a claim
expires without completion. Anyone reading 1,764/2,441 as a rework rate has mis-folded the ledger.

### Worry (b), THE TREADMILL — confirmed by an experiment the system already ran on itself

The pool has been flat since Aug 7:

| date | NOT-DONE | done (cum) |
|---|---|---|
| Aug 7 | 405 | 857 |
| Aug 9 | **460** | 1,020 |
| Aug 11 | 515 | 1,363 |
| Aug 12 | 541 | 1,430 |
| Aug 16 | 445 | 1,767 |
| Aug 18 | 403 | 1,965 |
| Aug 23 | 508 | 2,206 |
| **Aug 25** | **494** | **2,288** |

**The experiment.** On 2026-08-09 the pool stood at exactly **460**. A full-corpus triage ran against
precisely that population — `docs/plans/backlog-consolidation-2026-08-09/verdicts.json` holds exactly
**460** verdicts (task #152 names "all 460 open items"). Its dispositions:

| verdict | n | share |
|---|---|---|
| KEEP | 220 | 47.8% |
| PRUNE | 117 | 25.4% |
| UPDATE | 78 | 17.0% |
| MERGE | 45 | 9.8% |

**It was applied** — all 117 PRUNE and all 45 MERGE ids fold to `done` in the ledger today (verified;
0 of the 460 ids are missing from the ledger). So 162 items (35.2% of the entire pool) were disposed
of as work that should never have been done.

**Sixteen days and 1,268 completions later the pool is 494 — larger than the 460 it started from.**

That is the answer to worry (b), and it is not a projection: the single most aggressive intervention
available (triage the whole corpus, prune a third of it) was executed in full and bought nothing.
A pool that returns to its starting size after being cut by 35% is not draining.

**Rates.** The two windows disagree in *sign*, which is itself the finding:

| window | adds/day | dones/day | net |
|---|---|---|---|
| last 14 days | 74.1 | 78.5 | −62 |
| last 7 days | 62.9 | 59.0 | **+27** |

No convergence is measurable. Any time-to-zero quoted from the 14-day window is noise at the 7-day
window, where the pool *grows*.

### Why the rates match: filing is coupled to draining by construction

`bin/cc-backlog:5821` — **"S5 KICK-ON-WRITE"**:

> `add` is the ONLY moment new work enters the ledger, so the writer kicking one decision pass is
> what removes the average wait from the 5-minute decision bound.

**Filing an item fires a dispatch pass that starts a session to work it.** The loop closes: a drain
session works an item → discovers defects in the machinery while working → files them → each filing
kicks the dispatcher → more sessions → more discoveries. Arrival rate and completion rate are not
independent quantities that happen to be equal; they are mechanically coupled. Kill switch exists:
`CC_BACKLOG_KICK=off`.

### What is being filed: the machine maintaining the machine

| measure | share of adds |
|---|---|
| `project == claude-infrastructure` (filer's own label — the honest floor) | 1,782 / 2,782 = **64.1%** |
| title matches agent-machinery vocabulary, last 7 days | 355 / 441 = **80.5%** |
| title matches agent-machinery vocabulary, last 14 days | 885 / 1,038 = **85.3%** |

The keyword regex is broad and over-matches; the project label is the conservative instrument. Both
agree in direction: **the large majority of filed work is the agent infrastructure repairing itself**,
not work with a consumer outside this machine.

The `add` sources make the generator structure visible:

| source | n | what it is |
|---|---|---|
| `needs` | 711 | operator-owned steps filed at session close |
| `plan-open` | 458 | harvested from open plan-doc sections |
| *(blank)* | 338 | **the drain sessions' own discoveries** |
| `postland-verify` | 129 | daemon |
| `desk-observed` | 43 | daemon |
| everything else | ~1,100 | one-off session ids |

The blank-source bucket is the self-feeding one, and it is **accelerating**: 0–1 filings/day around
Aug 14–16, rising to 34 on Aug 23 and 16 on Aug 24. Sampled titles from the Aug 24–25 overnight run
are all about the drain apparatus itself — *"THE DRAIN CHAIN'S SUCCESSION ARTIFACT LIVES IN /tmp,
WHICH A REBOOT WIPES"*, *"THE SUCCESSION BRIEF HAS OUTGROWN THE ARGV PATH THAT handoff-fire ITSELF
COMPOSES"*, *"unattended-path-lint's launchd half SILENTLY EXEMPTS 2 of 26 shipped plists"*.

### Worry (a), STALENESS — real exposure, not the binding constraint

**Latency, add → first done** (n = 2,296):

| p50 | p75 | p90 | p95 | p99 | max |
|---|---|---|---|---|---|
| 13.5 h | 108 h | 223 h (9.3 d) | 313 h | 464 h | 758 h (31.6 d) |

45.1% of completions took >24 h; 31.1% >72 h; 15.9% >1 week.

**Tree movement during that window.** `origin/main` took 3,439 commits in the 40-day period (~86/day),
so the drift per item is large:

| commits landing between filing and completion | |
|---|---|
| p25 | 2 |
| p50 | **61** |
| p75 | 450 |
| p90 | 885 |
| p99 | 1,822 |
| max | 2,912 |

Only **5.8%** of completed items completed against an unchanged tree. 45.4% completed after >100
commits had landed; 39.1% after >200.

This confirms the operator's *exposure* claim exactly. It does **not** by itself establish harm — an
item survives 885 commits if none of them touched its subject, and the ledger has a `falsify` verb
(403 events) that attaches a re-run probe and refuses to store a probe that already exits 0. Whether
that mechanism actually covers the open pool is the one thing the fan-out is still measuring; it is
recorded as an open question below rather than asserted.

**The reason staleness is not the binding constraint:** even if every stale item were free to
complete, the pool would still not shrink, because the arrival rate would be unchanged. Staleness
raises the *cost per item*; the arrival rate sets the *destination*.

### The floor: 197 blocked rows, 184 with no recorded reason

| | |
|---|---|
| blocked | 197 |
| age since block: p50 / p90 / max | 7 d / 17 d / 36 d |
| blocked >7 d | 52 |
| blocked >14 d | 31 |
| **blocker reason unrecorded** | **184 of 197 (93.4%)** |
| blocked by `cc-backlog-reap` (machine, not a human gate) | 13 |

Open-item ages, for comparison: p50 4 d, p90 15 d, max 34 d; 99 open >7 d, 41 open >14 d.

93.4% of blocked rows record no blocker. A premise that was never written down cannot be
re-validated, so these rows can only ever be re-read by a human — this is the repo's own
*"stale ask outlives premise"* lesson realised at scale.

### Cloud lane yield: 79 commits stranded off trunk

Task #174 currently reads *"Recover the 153 stranded cloud commits across 113 claude/fire-* branches"*
— that is the **commit-count** oracle, and it overstates, because a rebasing land rewrites objects so
`rev-list origin/main..<branch>` counts content that did land.

Re-measured by **content** (patch-id against the last 6,000 trunk commits, 3,615 distinct patch-ids):

| | branches | commits |
|---|---|---|
| scanned (`origin/claude/*`, `origin/fire-*`) | 114 | — |
| fully landed by content | 8 | — |
| unlanded by content — **Aug 24–25, still in flight** | 38 | 55 |
| unlanded by content — **older, genuinely stranded** | **68** | **79** |

So the real stranded figure is **79 commits across 68 branches**, not 153/113. It is still a direct
net-positivity loss: cloud sessions that ran, produced commits, and whose value never reached trunk.

### Time to zero if filing stopped

| completion rate | agent-actionable (297) | full pool (494) |
|---|---|---|
| 78.5/day (14-day) | **3.8 days** | **6.3 days** |
| 59.0/day (7-day) | **5.0 days** | **8.4 days** |

This is the number that reframes the whole question. **The backlog is not large.** It is a bit over a
week of work at the throughput the machine already demonstrates. It only looks like a forever-thing
because roughly 70 items/day are added while roughly 70 items/day are completed.

---

## Open questions the fan-out is still measuring

These are recorded as unknown rather than guessed:

- **Falsifier coverage.** 403 `falsify` events exist; how many *currently open* rows carry a probe is
  not yet measured. This decides whether staleness is mitigated or merely nameable.
- **Boundedness of `needs` and `plan-open`** (1,169 adds between them). If the plan corpus keeps
  growing, `plan-open` never exhausts.
- **How much of the 494 is duplicate or already-fixed-but-still-open.** The Aug 9 triage found 35.2%
  PRUNE/MERGE; if that rate still holds, ~174 of today's pool is not real work.
- **Whether cloud runs bill the same weekly meter** (task #175, open).

---

## What follows

The intervention that matches the diagnosis is **admission control, not more throughput**. Ranked by
effect per unit of effort, with the arithmetic each rests on:

1. **Stop the drain from filing into its own queue.** The blank-source bucket (338 adds, accelerating
   to ~16–34/day) is the self-feeding loop. Machinery defects discovered *while draining* should land
   in a separate register that is not dispatch-kicked. Effect: removes the coupling that makes
   arrival ≈ completion.
2. **Set the target to a bounded WIP, not zero.** "Zero" is unreachable by construction while
   generators are unbounded, and a target that cannot be hit reads as "forever". A reachable
   restatement: *zero agent-actionable items older than 14 days*, which today means clearing 41 rows.
3. **Re-run the Aug 9 triage rate against today's pool.** If 35.2% still prunes, that is ~174 items
   off 494 for one pass — but note the Aug 9 experiment proves this alone does not hold.
4. **Record a blocker reason on every `block`.** 184 unrecoverable rows is the permanent floor;
   without a reason field there is no path to ever re-validating them.
5. **Land or delete the 79 stranded cloud commits.** Work already paid for that currently yields zero.

Items 1 and 2 are the only ones that change the *destination*; 3–5 change the *level*.
