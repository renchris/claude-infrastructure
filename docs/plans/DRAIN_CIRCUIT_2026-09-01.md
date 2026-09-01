---
status: in-progress
---

# DRAIN CIRCUIT — the 24/7 pipeline is an open loop (2026-09-01)

**Scope (frozen):** audit both 24/7 drain lanes end-to-end, fix the measured defects that stop the
pipeline draining `cc-backlog` (telemetry + effective-work), and leave the loop self-sustaining.

**The answer to the operator's question, first.** No. Neither lane is self-sustaining, and the
reason is structural rather than a tuning problem: **the cloud lane's landing arm is scheduled by
nothing**, so every cloud session's output strands on a branch and its backlog item can never
close; and **the local lane's subject has become its own output**, so it commits at ~10× the rate
it closes backlog items. The telemetry could not have told you this, because the one shipped
surface built to answer "is the fleet landing anything, or churning?" counts *commits*, not
*backlog closure*, and rendered a healthy number all week.

---

## 1. What was measured (all first-hand, this session)

### 1.1 The cloud lane is a half-circuit

| Arm | Mechanism | Scheduled? |
|---|---|---|
| **FIRE** | `com.claude.dispatcher` → `cc-dispatch --once`, `StartInterval` **300 s** | ✅ loaded + running (pid 74864) |
| **LAND** | `scripts/cloud-reconcile.sh` (gate G6, "THE CLOUD LANDING PATH") | ❌ **nothing invokes it, ever** |

Verified with a **positive control**, because a null from a blind grep is not absence:

```
CONTROL (known-scheduled)        SUBJECT (the land arm)
  cc-dispatch      → 1 plist      cloud-reconcile      → 0 plists
  cc-reaper        → 2 plists     cc-offload           → 0 plists
  deploy-live      → 3 plists     cloud-return         → 0 plists
  postland-verify  → 2 plists     thrash-block-recover → 0 plists
                                  branch-prune-landed  → 0 plists
```

Both namespaces (`com.claude.*` and `com.chrisren.*`) were in the grep's population; `crontab -l`
is empty; and the single in-tree reference from a scheduled job — `scripts/autonomy-sweep.sh:1065`
— is a **comment**, not a call.

**The false premise, in the dispatcher's own header** (`bin/cc-dispatch:5-6`):

> It does NOT land work itself — the spawned session's lead lands via the existing ship-land rails.

True for a **local** worker. Structurally impossible for a **cloud** worker, and
`scripts/cloud-reconcile.sh`'s own header says why: a cloud VM has no `~/.claude`, no `gh`, cannot
run the project-local `/ship`, and its commits are authored `noreply@anthropic.com`, which
`githooks/pre-push` refuses by design. The dispatcher was migrated to **cloud-only on 2026-08-11**
(plist header: `CC_DISPATCH_VENUE_ONLY=cloud`) and this landing premise was never revisited. That
single un-revisited sentence is the root cause.

### 1.2 What the open loop produces

`scripts/cloud-reconcile.sh --list` (read-only), 345 rows:

| State | Count |
|---|---|
| **ELIGIBLE** — declared, ready, waiting for a lander that never runs | **272** |
| RETIRED | 40 |
| LANDED | 32 |

Age histogram of the 272 — **210 of them are 2026-08-24 → 08-29**, exactly the window in which
drain collapsed:

```
08-18  2   08-22  2   08-26 44   08-30  4
08-19  3   08-23  2   08-27 46   08-31 17
08-20  5   08-24 17   08-28 49   09-01  6
08-21  4   08-25 30   08-29 41
```

### 1.3 The churn this creates in the ledger

Last 7 days over `~/.claude/autonomy/backlog.jsonl`:

```
claim 244   block 219   unblock 183   add 45   done 30
```

The 244 claims are over **17 distinct item ids**, all `venue=cloud`, each re-claimed **8–23 times**,
and **1 of the 17** ever reached `done`. Read from the record trails, the cycle is:

1. dispatcher claims the item, fires a cloud VM on `claude/fire-<ts>`, custody OPEN;
2. the VM works and pushes; **nothing lands it**;
3. `cc-backlog-reap` finds the claim past its ceiling but the worker still ALIVE, so it writes
   `event:"block"` with a `needs:` string addressed to the **operator**;
4. `cc-backlog-reap` later writes `event:"unblock"`;
5. the item returns to open, the dispatcher re-claims it — 5 minutes later, forever.

Throughput across the same transition: **~80–240 done/day in mid-August → 0–6/day since Aug 26.**

### 1.4 The local lane is alive, productive, and self-referential

It is **not** dead — it is the `docs(drain): recycle #N — method M` chain, currently at **recycle
#277 / method #249**. Over 7 days it produced **304 trunk commits** against **30 backlog closures**
— roughly **10 commits per closure** — and its file footprint is entirely the pipeline's own
machinery: `tests/` 143, `docs/research/` 132, `scripts/` 112, `docs/plans/` 110, `bin/` 58.

Its subject is its own previous output. From `BACKLOG_DRAIN_24_7.md:953`:

> **HOW I GOT THERE — #267's method 239 pointed at the destinations it named and did not measure.**

Each recycle audits the recycle before it. The work is careful and the findings are real, but the
loop is closed: it improves the drain machinery and never touches the backlog the machinery exists
to drain. This is precisely the operator's "deferring rather than completing".

### 1.5 The telemetry could not have caught it

`bin/cc-value` exists for exactly this question — its own header: *"is the fleet LANDING anything,
or churning?"* Run this session, over the week in which drain was zero:

```
value ledger — 24h window · churn-floor 8%   (6 repos scanned)
  FLEET   value 87  = 86 commits landed (86 unattributed) · 1 tasks closed   |  spend ~29% · v/spend 3
```

`value 87` reads as health. The defect is the **unit**: it counts *commits*, and has no term for
work that was produced and then stranded. No shipped surface computes either metric that would
have made this visible on day one:

- **conversion** — claims → dones over the window (this week: 244 → 1, **0.4 %**);
- **stranded** — count and age of ELIGIBLE-but-unlanded cloud branches (**272, oldest 14 d**).

### 1.6 The generator: correct mechanisms, unwired

Every part is well built. `cloud-reconcile.sh` is careful, gate-delegating, fail-loud.
`scripts/thrash-block-recover.sh` already exists and correctly handles precisely the rule-B
`cc-backlog-reap` block oscillation in §1.3. **Neither is wired to anything.** The reason is the
same for both: wiring is a C10 **operator-gated activation**, and the activation queue is
**11 deep and all 11 are rotting >24 h**:

```
13-mailbox-gc · 18-fleet · 27-worktree-gc-infra · 30-teammate-reap-alarm · 33-escalation-watch
34-deploy-plist-fallback · 35-auth-timeseries · 36-start-latency-router · 37-postland-band
38-accounts-board · 41-browser-spin-guard
```

**Therefore any fix that ships as a new activation will rot exactly like these.** That is the
binding design constraint below, and it is measured, not assumed.

---

## 2. Phase 0 — orchestration

**Execution locus per wave.** W1 and W2 are **S** (dispatched handoff sessions) — the default; each
is a self-contained implementation with its own gate run, and neither needs the lead's context.
W0 is **L** (lead-inline): it is one bounded read-only measurement whose output shapes both briefs.

| Wave | Locus | Deliverable | Owns |
|---|---|---|---|
| **W0** | L | Land-path viability: does a *recent* branch rebase + gate clean? | lead |
| **W1** | S | **Close the circuit** — reconcile inside an already-running job | `bin/cc-dispatch`, `scripts/cloud-reconcile.sh`, tests |
| **W2** | S | **Make the churn visible** — drain conversion + stranded in `cc-value` | `bin/cc-value`, tests |

Single owner per file; W1 and W2 share none. Lead context budget: hold ≥50 %, succeed at W2 fire.

### The binding constraint on W1 (from §1.6)

**The fix must not require a new operator activation.** `com.claude.dispatcher` is already loaded
and already runs every 300 s; a reconcile pass added *inside* it inherits that schedule and cannot
rot in the pending queue. A new `com.claude.cloud-reconcile.plist` would be correct code that
becomes the 12th rotting activation — the defect this document exists to end.

### The second constraint on W1: it must survive `cc-reaper`

Measured this session: a `cloud-reconcile → desk-land → ship-land` run was **SIGTERM'd at 452 s**
by `cc-reaper` for being `ppid 1`:

```
✗ ship-land: verdict=killed signal=SIGTERM role=outer elapsed=452s ppid=1 ancestry=[]
  — we are ORPHANED (ppid 1) — the shape every cc-reaper orphan class selects on.
```

plus, from the same run, the process the signal actually reached:

```
desk-land.sh: line 89: 55520 Terminated: 15   ( cd "$TARGET_TOP" && "$@" )
```

A launchd-spawned reconcile is *also* `ppid 1`. The exemption `cc-reaper` ships is an **argv
whitelist** (`bin/cc-reaper:627`, `wl=`), matched per-process against that process's own `args[]` —
*not* a `LAND_T0` env var, which is only ship-land's elapsed-time accumulator
(`scripts/ship-land.sh:344`). That whitelist already carries `ship-land`, `desk-land` and
`cc-dispatch`; it does **not** carry `cloud-reconcile`. And note what the kill reached: an inner
subshell whose own argv is `( cd "$TARGET_TOP" && "$@" )` and therefore carries none of those
tokens, while `above[]` protects only the ancestors of a live `claude` binary.

W1 must therefore determine **empirically** which links in the
dispatcher → reconcile → desk-land → ship-land chain present `ppid 1` with a non-whitelisted argv,
fix exactly those, and prove it with the fixture pair `tests/cc-reaper.bats` already uses: the land
shapes survive while an unrelated orphan bash in the same closed world still dies, so the exemption
cannot silently widen into "nothing is collected".

⚠️ **Provenance caveat.** The kill above was *this session's* invocation being backgrounded into an
orphan, not a production observation. It is the exact shape a scheduled land presents, but until W1
measures it under the dispatcher, the production claim is a prediction, not a finding.

### Known-clean vs known-conflicting

The **oldest** ELIGIBLE branch (08-18, 14 d stale) hit a rebase conflict in `scripts/handoff-fire.sh`
on the dry-run. Staleness compounds: the missing scheduler does not merely strand work, it **rots**
it. W1 should land newest-first and treat a conflict as a per-branch PARK, never a lane stall.

---

## 3. What is NOT proposed, and why

- **Bulk-landing all 272 branches now.** Blast radius: 272 rebases onto a moving trunk, each with a
  full gate. It is an operator value call, not an agent one, and it is also the *wrong shape* — once
  W1 lands, the loop drains them on its own schedule. The bulk land is a consequence of the fix, not
  the fix.
- **A new launchd job for the lander.** See §1.6 — it would rot.
- **Deleting the stranded branches.** Their content has not been adjudicated here; task #174
  ("Recover the 246 stranded cloud commits… patch-id verified") owns that question and its count is
  now 313, so its conclusion needs re-checking before anything is discarded.

---

## 4. Status log

- **2026-09-01** — audit complete, all §1 findings first-hand and control-verified. Plan written.
  W0/W1/W2 not yet started.
