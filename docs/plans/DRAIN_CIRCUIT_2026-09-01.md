---
status: in-progress
---

# DRAIN CIRCUIT — the 24/7 pipeline is an open loop (2026-09-01)

**Scope (frozen):** audit both 24/7 drain lanes end-to-end, fix the measured defects that stop the
pipeline draining `cc-backlog` (telemetry + effective-work), and leave the loop self-sustaining.

**The answer to the operator's question, first.** No. Neither lane is self-sustaining. **The
garbage collector is eating the drain pipeline's landing arm**: `cc-reaper` has SIGTERMed
`cloud-return.sh --sweep` — the process that brings finished cloud work home — 153 times, because
the whitelist that was added on 2026-08-16 under the header *"THE LAND PATH IS NEVER GARBAGE"*
enumerated `ship-land` and `desk-land` and missed the outer driver of the cloud land path. So every
cloud session's output strands on a branch and its backlog item can never close. Separately, **the
local lane's subject has become its own output**, so it commits at ~10× the rate it closes backlog
items. The telemetry could not have told you either thing, because the one shipped surface built to
answer "is the fleet landing anything, or churning?" counts *commits*, not *backlog closure*, and
rendered a healthy number all week.

---

## 1. What was measured (all first-hand, this session)

### 1.1 The cloud lane's landing arm is wired, invoked, and killed on every run

⚠️ **This section was WRONG in the first draft of this document and the error is worth recording,
because it is the repo's own `caller-census-keyed-on-path-misses-the-name` lesson committed live.**
The first draft claimed "the landing arm is scheduled by nothing", on a `grep -rl cloud-reconcile`
over every plist that returned 0 against a control that returned 1–3 for known-scheduled jobs. The
control passed and the null was real — **for that name**. The scheduled arm does not call
`cloud-reconcile.sh`; it calls **`cloud-return.sh`**, and the one hit my grep did find in a
scheduled job (`autonomy-sweep.sh:1065`) really was a comment, which made the wrong conclusion look
confirmed. `scripts/cloud-reconcile.sh` is the *manual* `CONFIRM=1` path and is indeed unscheduled;
that is not the defect.

The real shape:

| Arm | Mechanism | State |
|---|---|---|
| **FIRE** | `com.claude.dispatcher` → `cc-dispatch --once`, `StartInterval` **300 s** | ✅ loaded + running (pid 74864) |
| **LAND** | `com.chrisren.autonomy-sweep` (300 s) → `autonomy-sweep.sh:1075` → `timeout -k 10 900 bash cloud-return.sh --sweep` | ✅ loaded + running (pid 94244) — and **killed mid-land every time** |

**`cc-reaper` is the killer, in its own log** (`~/.claude/logs/cc-reaper.log`, 153 `cloud-return`
rows):

```
[2026-08-25T17:29:06Z] garbage: TERM orphan-bash pid=12874 age=1505s argv=<bash …/scripts/cloud-return.sh --sweep>
[2026-08-25T19:58:06Z] garbage: TERM orphan-tool pid=11480 age=899s  argv=</opt/homebrew/bin/timeout -k 10 900 bash …/cloud-return.sh --swe>
[2026-08-25T20:15:41Z] garbage: TERM orphan-bash pid=11500 age=1955s argv=<bash …/scripts/cloud-return.sh --sweep>
```

and the receiving end, in the sweep's own stderr (`~/.claude/logs/autonomy-sweep.err.log`, mtime
2026-08-30, the same line recurring at :954, :1033, :1048 as the deployed copy moved):

```
/Users/chrisren/.claude/scripts/autonomy-sweep.sh: line 1048: 28017 Killed: 9  "$_tmo" -k 10 900 bash "$_cloudret" --sweep > /dev/null 2>&1
```

**The mechanism, end to end.** `autonomy-sweep` is launchd-parented, so both the `timeout` wrapper
and the `bash cloud-return.sh` beneath it run at `ppid 1`. `cc-reaper`'s garbage arm selects
`orphan-tool` on a `timeout` older than 120 s and `orphan-bash` on a bash older than 600 s, in each
case **only when the process's own argv misses the whitelist** (`bin/cc-reaper:627`). That whitelist
reads:

```
lead-supervisor|cc-dispatch|cc-discover|cc-reaper|qos-census|compressor-sentinel|postland-verify|
session-search|devserver-gc|deploy-live|cc-relogin|lr-reset-poller|teammate-reap|capacity-alarm|
power-policy|log-rotation|restic|worktree-gc|caffeinate|cc-await-ping|mailbox-wake-arm|
ship-land|desk-land|kitty|tmux|iTerm|launchd
```

`ship-land` and `desk-land` are there. **`cloud-return` and `cloud-reconcile` are not** — verified
by grepping the whitelist literal itself. A land needs far longer than 600 s (a single-branch
dry-run this session ran 452 s before being killed), so the sweep has never once been allowed to
finish. `cc-reaper:620-626` even carries the comment *"THE LAND PATH IS NEVER GARBAGE (2026-08-16)
… neither carried a whitelist token — so the arm classified an IN-PROGRESS LAND as the residue of a
dead session."* That fix named two spellings of the land path and missed the third — the repo's own
`denylist-enumerates-spellings-not-the-class` lesson, recurring in the file that records it.

**Corroborating null, with a passing control.** `log_idl cloud-return …` at `autonomy-sweep.sh:1079`
is unconditional — every path through that block logs, including `skipped-not-deployed`. The IDL
holds **0 `cloud-return` rows in 19,660 lines**, while the same instrument shows 1,079 `cc-dispatch`
rows in the last 2,000. So control never reaches :1079 at all. And the sweep's own ledger,
`~/.claude/autonomy/cloud/return.jsonl`, last wrote **2026-08-26T21:57:54Z** — five days ago — with
its final outcomes `land-refused` (`land_rc` 65) and `land-refused-cached` (`prior_rc` 70). **Two
stacked failures: the sweep is killed before it can land, and in the window when it did run, the
land was refusing.**

**A second, independent defect — the dispatcher's stated premise** (`bin/cc-dispatch:5-6`):

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

### 1.6 The generator: correct mechanisms that never get to finish

Every part is well built. `cloud-return.sh` is wired and invoked every 300 s — and killed.
`cloud-reconcile.sh` is careful, gate-delegating and fail-loud — and is the manual `CONFIRM=1`
path, unscheduled by design. `scripts/thrash-block-recover.sh` already exists and correctly handles
precisely the rule-B `cc-backlog-reap` oscillation in §1.3 — and is wired to nothing.

So the generator is **not** "nobody built it". It is that a correct mechanism reaches production
and is then defeated by a *sibling* mechanism that cannot see it: the reaper's whitelist is an
enumeration of spellings rather than a statement of the class, and the drain's own landing arm is
outside it. Where a mechanism instead needs an operator to switch it on, it rots in a queue that is
**11 deep with all 11 past 24 h**:

```
13-mailbox-gc · 18-fleet · 27-worktree-gc-infra · 30-teammate-reap-alarm · 33-escalation-watch
34-deploy-plist-fallback · 35-auth-timeseries · 36-start-latency-router · 37-postland-band
38-accounts-board · 41-browser-spin-guard
```

**Therefore any fix that ships as a new activation will rot exactly like these.** That is the
binding design constraint below, and it is measured, not assumed.

---

## 2. Phase 0 — orchestration

**Execution locus per wave.** W1 is **L** (lead-inline): the corrected fix is a whitelist token plus
its RED-proving fixture in one file, far below the cost of briefing a session, and it is the one
change that unblocks everything else. W2 and W3 are **S** (dispatched handoff sessions) — the
default; each is a self-contained implementation with its own gate run and neither needs the lead's
context. W0 was **L** and is done (its output is §1.1).

| Wave | Locus | Deliverable | Owns |
|---|---|---|---|
| **W0** | L | ✅ DONE — root-cause the land arm; result is §1.1 | lead |
| **W1** | L | **Stop the reaper eating the land** — whitelist `cloud-return`/`cloud-reconcile` + fixture pair | `bin/cc-reaper`, `tests/cc-reaper.bats` |
| **W2** | S | **Make the churn visible** — drain conversion + stranded in `cc-value` | `bin/cc-value`, tests |
| **W3** | S | **Re-aim the local lane at the backlog** — arm the §4.1 goal + closure floor | the drain-chain brief + `scripts/drain-chain-assert.sh` |

Single owner per file; no wave shares one. Lead context budget: hold ≥50 %, succeed after W1 lands.
Dependency: W1 blocks nothing formally, but until it lands the cloud lane cannot drain, so W2's
stranded metric will legitimately keep reading high — that is the metric working, not failing.

### The corrected fix for W1, and why it is one line plus a test

The first draft of this plan proposed adding a reconcile pass to `bin/cc-dispatch`, on the reasoning
that no land arm existed and a new launchd job would rot in the 11-deep activation queue. **That
premise is now known false** (§1.1): the arm exists, is scheduled, and runs. Building a second one
would have been a parallel rail beside a working one that is merely being killed — a strictly worse
outcome, and exactly the "mint a second renderer" defect in another costume.

The real fix is to add `cloud-return` (and `cloud-reconcile`, for the manual path) to the
`cc-reaper` whitelist at `bin/cc-reaper:627`, so the land path stops being classified as the residue
of a dead session. It must be proven with the fixture pair that file already uses: **the land shapes
survive while an unrelated orphan bash in the same closed world still dies**, so the exemption
cannot silently widen into "nothing is collected".

⚠️ **The whitelist is not the whole cure, and W1 must say so rather than declare victory.** Two
things stay open after it and are named here so they are not lost:
1. `timeout -k 10 900` at `autonomy-sweep.sh:1075` bounds the whole sweep at 900 s. A single-branch
   land ran 452 s this session. With 272 eligible branches a serial sweep cannot finish in one
   tick — so the bound must either rise, or the sweep must become explicitly incremental
   (land N per tick, journal what it deferred; a silent cap reads as "covered everything").
2. When the sweep *did* run, `return.jsonl` recorded `land-refused` with `land_rc` 65 and 70. Those
   refusal codes are unexplained and are a second, independent failure. W1 does not have to fix
   them, but it must not claim the lane is healthy while they stand.

### The constraint that still binds every wave (from §1.6)

**No fix may ship as a new operator activation.** The queue is 11 deep and all 11 are rotting past
24 h; a new activation is correct code that becomes the 12th. Prefer repairing an already-scheduled
mechanism — which, now that §1.1 is right, is exactly what W1 does.

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

## 3b. The full kill chain — measured by the 24-agent audit wave, and it is worse than §1.1

§1.1 established that `cc-reaper` collects the landing sweep, and W1 fixed that. A parallel
adversarial audit (24 agents, one verifier refused mid-run — see the caveat at the end) measured
the rest of the chain, and the reaper is only **one of four** reasons the lane cannot drain. The
landed whitelist fix is therefore **necessary and not sufficient**, and nothing below should be read
as cured by it.

**A. The 900 s bound is smaller than the pass's FIXED cost, before a single land is attempted.**
`autonomy-sweep.sh:1075` bounds the sweep at 900 s. Timed live against the real store:

| Step, before any land runs | Measured |
|---|---|
| `cc-cloud list --json --state` over 583 declarations (one bounded `ls-remote` each, 0.36 s/row) | **210 s** |
| `cc-cloud poll` — another `ls-remote` per 489 non-retired declarations | + |
| `handle()` — one `cloud-create-api.py --verify` control-plane call (0.409 s) per 304 returnable MANAGED sessions | + |
| Background QoS band tax (`ProcessType=Background`, `Nice=5`); A/B over 40 `ls-remote` calls: 12.0 s foreground vs 17.7 s | **×1.47** |
| **Fixed cost consumed with ZERO lands done** | **~675 s of 900 s** |

A land is then ship-land's full statics + ratchets + smoke gate — minutes each. The pass cannot
finish, so it is SIGKILLed. The IDL's `cloud_return_rc` timeline is the signature and contains no
success at all: `137, 4, 4, 4, 4, 4, 137, 137, 137`.

**B. Every SIGKILL strands the single-flight lock, costing up to twelve more ticks.**
`cloud-return.sh:140` traps `EXIT INT TERM` — none of which run on SIGKILL — and `lock_acquire`
(:131-146) only reaps a lock older than **3600 s**, against a **300 s** sweep cadence. So each kill
is followed by roughly an hour of `rc=4` lock-outs. That is what the run of `4`s above is.

**C. The land block is barely REACHED — about 1 pass in 48.** In the IDL archive spanning
2026-08-29T09:28 → 2026-09-01T01:09 (2.65 days, ~18 passes/day) there is exactly **one**
`cloud-return` row, while `join` (early in the sweep) fired 46 times and `config-parity`
(immediately above the land block) fired 4. Most passes die before line 1079 in the sweep's own
earlier, expensive stages.

**D. It is monotonically worsening and cannot self-recover.** `cloud-return.sh` has no `--limit`,
no shard and no cap, and `cc-cloud poll` has no scoping, so per-pass cost is **O(all declarations
ever created)** — 17 on 2026-08-08, **582 today**, growing 20-80/day (Aug 25: 81, Aug 26: 48,
Aug 27: 50, Aug 28: 57). Each new declaration adds ~0.8 s of `ls-remote` plus ~0.5 s of verify to a
budget fixed at 900 s. The `returned` event history matches exactly: 25/14/59/18 per day on
Aug 14-17, **0 for Aug 18-22**, 1 on Aug 23, 5 on Aug 25, and **0 ever since**.

**What is NOT the blocker, ruled out by measurement** — so nobody re-derives them: no caller was
ever removed (`git log --all -S'cloud-reconcile' -- '*.plist' 'hooks/*'` is empty; all six
`cc-offload land` commits are feature ADDs); the deployed layer is correctly symlinked; and the
eligibility gate is reachable — all 582 declarations carry a `branch=` field, so nothing falls into
the NO-DECL skip.

**The work is real.** 239 of the 273 eligible branches carry genuinely unlanded content (170 exactly
one commit ahead of trunk, 73 two or more, 30 nothing to land). But it is heavily redundant: the 313
branches are **72 distinct backlog items**, with 18 items accounting for 242 branches (77%) because
each was re-claimed and re-implemented 8-25 times. Only **95 distinct file paths** across all of them
are absent from `origin/main`, and a greedy set-cover says **52 branches capture every one**. Every
re-attempt produced its own blob for the same file, so the branches **cannot be merged, only chosen
between** — there is no 313-branch recovery, and 159 of 313 (51%) are already-landed duplicates or
superseded by a landed sibling.

**The consequent fix list, in dependency order** (none of these is W1, which is done):
1. `cloud-return.sh --limit N` + a persisted cursor, so a tick does bounded work instead of
   restarting an unbounded sweep. Newest-first (staleness compounds — §2).
2. Have `autonomy-sweep` clear `$CC_CLOUD_STATE/.return.lock` when *its own child* returns 137/143
   — it knows it did the killing — and/or size the reap window to the caller's bound plus slack
   rather than a hardcoded 3600 s.
3. Move the cloud-return call above the sweep's expensive premise/venue stages, or split it into its
   own job so it does not share a tick with work that consumes the whole tick.
4. GC dead declarations (94 of 582 are `.retired`) so the population is bounded by live work rather
   than by history.
5. Stop the dispatcher firing an item that already has an unlanded `claude/fire-*` branch declared
   against it — the decl store already records branch and item, and this is what produced 8-25
   attempts per item.

⚠️ **Audit caveat.** One verifier (`verify:reap-loop`) died on an API safeguard error and never
returned, so exactly one of the reap-oscillation findings in §1.3 carries no adversarial
verification. Everything in this section was independently re-measured against the live store.

---

## 3c. W3 — the three fixes shipped, and the two further kills the work uncovered

`686acbd70` implements §3b items 1-4. Item 5 is FILED, not built, for a reason given below.

### The numbers, measured against the live store on 2026-09-01

| | Before | After |
|---|---|---|
| `cc-cloud list --json --state`, unscoped, 583 declarations | **216.4 s** | scoped to the working set |
| a complete `cloud-return --sweep --limit 25` pass (poll + state + 25 control-plane verifies) | never finished | **43 s, rc 0** |
| `cloud_return_rc` | `137, 4, 4, 4, 4, 4, 137, 137, 137` — no success since 2026-08-24 | **0** |
| RETURN-READY sessions reached in one bounded pass | 0 | **19 of 25** |

The 216 s figure is the fixed cost §3b predicted at 210 s, re-measured independently. The pass now
journals a `pass-scope` ledger row every tick (`pending_total`, `taken`, `deferred`, `cursor_from`,
`cursor_to`) so the cap can never read as coverage.

### THE FIFTH KILL — the sweep itself is the reaper's single largest subject

§3b C observed that the land block is reached about 1 pass in 48 and attributed it to the sweep's
earlier expensive stages. The stages are not the mechanism. Two measurements:

**Over the live IDL, 2026-09-01T01:12→05:17Z (~48 ticks), filtering `tool=="autonomy-sweep"`:**

```
join            6 rows      ← §0, the first block
backlog-health  0 rows      ← §2b
config-parity   0 rows      ← §2c
cloud-return    0 rows      ← §2d, whose log_idl is UNCONDITIONAL
```

`log_idl cloud-return` journals on every path including `skipped-not-deployed`, so zero rows cannot
mean "it ran and had nothing to do". Control never arrived.

**In `~/.claude/logs/cc-reaper.log`, by subject, all time:**

```
719  autonomy-sweep.sh     ← the single largest subject in the file
676  account-fact-derive
374  mailbox-wake-arm.sh
153  cloud-return.sh       ← the W1 case, now fixed
```

with rows like `garbage: TERM orphan-bash pid=94244 age=1793s argv=</bin/bash …/autonomy-sweep.sh>`,
ages **1362-2063 s**. So the sweep is started every 300 s, runs for 25-35 minutes, and is collected
as garbage long before its lower half — and has been for weeks. This is the same defect W1 fixed,
in the same log, one level up: the fourth spelling of the land path.

**Why W3 did NOT simply whitelist it, which is the apparently-obvious fix.** `cc-reaper` is
currently this job's ONLY watchdog. launchd does not stack a second instance of a running job, so a
sweep that hangs stops the cadence entirely; today's TERM at ~1400 s is precisely what lets the next
tick start. Exempting it converts a periodic job into a permanently wedged one — strictly worse, and
unlike the reordering it is not order-only. The real repair is a self-bound on the sweep, which is a
different change with a different blast radius. **The reordering is what makes the lane drain
regardless**: at t≈0 s the cloud block completes inside its own 900 s bound with ~450 s of margin
against the earliest kill on record.

### THE SIXTH — ship-land's smoke budget convicted a green branch, and named it a verdict

The first real land attempt (`session_0112CMfyhNwqKdeLmiMDB6gT`, branch
`claude/fire-20260901T035401Z-22411-1`) was REFUSED, exit 70 → lander 6 → gate-red:

```
✗ gate: bats RED: tests/cc-relogin-poll.bats (failed twice)
⏱ gate: smoke budget 120s exhausted — remaining suite(s) not started, land PROCEEDS
✗ gate: smoke RED — 1 of 4 direct suite(s) named a failure (1 mapped to YOUR diff).
  This is a VERDICT about your diff (O(diff), reproducible): fix it, do not retry unchanged.
```

**It is not reproducible and it is not about the diff.** Checked out at that exact branch and run
standalone, `tests/cc-relogin-poll.bats` is **64/64, rc 0, in 58.35 s**. The bats process in the
gate log died `Terminated: 15`. The budget is **120 s for all four suites combined**, one of which
alone costs 58 s, and the box was at **load average 35.7** with a full postland-verify suite in
flight. A bound smaller than what it bounds can only convict — this repo's own
`exoneration-bound-must-fit-what-it-bounds` and `bound-must-fit-the-band-not-the-bench`, in the
gate that guards the lane this document is about.

The gate was NOT weakened to get past it. `SHIP_LAND_SMOKE_BUDGET_S` is the override ship-land
itself prints, and raising it lets every suite run to a real verdict instead of being cut into a
false one — the assertion set is unchanged and strictly more of it executes. **The standing risk
this leaves:** at the shipped 120 s, any branch whose smoke fan-out exceeds ~2 suites under load is
refused with a message that tells the reader not to retry it. That is a false-refusal generator
sitting directly on the drain path, and it is not W3's file to change.

### §3b item 5 is FILED, not built — `96e532227df8`

The redundancy is confirmed and worse than recorded: **47 distinct items carry 2 or more
declarations**, the worst carrying **30**. The fire predicate never reads the decl store's own
`item=` link, which it already has.

It is filed rather than shipped because its precondition is genuinely unmet. The guard is safe only
once the lane shows a non-zero drain rate; applied now, over 466 pending declarations with the drain
not yet observed in production, it does not de-duplicate cloud dispatch — it **halts** it for ~72
items, converting visible churn into a silent stall. The filed row carries that gate
(`backlog-telemetry lane=cloud closes>0`) and the shape it should take: a sibling of `cc-dispatch`'s
§1b DONE-GUARD, disk-only via `id_for_item` plus the absence of a `.returned` marker, never a
probing lookup — the same reason §1b refuses to content-verify at pull time.

---

## 3d. THE LIMIT AND THE BOUND ARE STILL NOT RECONCILED (measured 2026-09-02, post-W3)

W3's `--limit` is landed AND live AND wired — `~/.claude/scripts/autonomy-sweep.sh:395` passes
`--limit "${CC_SWEEP_RETURN_LIMIT:-25}"`, and the live `cloud-return.sh` parses it at :105-119.
**And the sweep is still SIGKILLed on every pass.** `cloud_return_rc` in the IDL, all recorded after
W3 landed (2026-09-01T12:55) and after its bytes reached the live layer:

```
2026-09-02T02:40:35Z rc=137   2026-09-02T04:12:48Z rc=137   2026-09-02T05:51:11Z rc=137
2026-09-02T03:17:03Z rc=137   2026-09-02T05:11:02Z rc=137
```

**Why, as the class rather than the instance.** `--limit` is a COUNT (25 pending managed sessions,
rotated by a persisted cursor at :774-788). The caller's bound is a DEADLINE. Nothing reconciles
them, and no better constant can: each taken session may trigger `handle()` →
`cloud-reconcile --land` → `desk-land` → `ship-land`, a full statics+ratchets+smoke gate measured in
minutes. 25 of those do not fit 900 s at any constant. This is the repo's own
`bound-must-fit-the-band-not-the-bench` lesson recurring — a bound sized against one population is a
permanent non-verdict against another.

**The fix is a deadline check, not a smaller number.** In the `while IFS= read -r ROW` loop at
`scripts/cloud-return.sh:838-844`, before calling `handle "$ROW"`, stop STARTING new work once
elapsed exceeds a safe fraction of the caller's bound, and journal that deferral SEPARATELY from the
cursor's own `deferred` count — a silent stop reads as "nothing pending". A count cannot adapt to
land duration; a deadline can, and it degrades gracefully as land cost changes. The caller should
tell the child its bound rather than the value living in two places that cannot check each other.

**Acceptance is one number never yet observed**: a `cloud_return_rc` of **0**. Every row in the
IDL's history is 137 or 4. Until one pass reports 0, the lane is not fixed — it has only been made
to close a single item during W3's own supervised run.


## 4. Status log

- **2026-09-01** — Audit complete across both lanes; 24-agent adversarial wave corroborated it and
  corrected §1.1 (see `3feac4443`). W0 done. **W1 done**: `1ca324beb` adds
  `cloud-return|cloud-reconcile` to the `cc-reaper` whitelist with a RED-proven fixture pair
  (mutant fails on its `got` assertion; full suite 193/193). Landed and content-verified on trunk;
  **not yet live** — the live layer is pinned at the `postland-verify` green stamp with un-stamped
  commits above it, which is normal converge lag and not this diff's to drive.

- **2026-09-01 — W2 DONE and verified BY EXECUTION, not by its report** (`ff901ddcb`, `406157795`).
  `scripts/backlog-telemetry.sh` is now `100755` on trunk and renders the conversion metric that
  existed nowhere in the repo. Running the trunk copy against the live store:

  ```
  CONVERSION 7D  claims=248 over 17 distinct id(s) → 1 converted to done (5.8%) · reclaim=14.5x per id
  verdict=drain-futile  scope=fleet  claims=248 ids=17 converted=1 (5.8%) floor=25% reclaim=14.5x
  --assert rc: 1
  ```

  and `bin/cc-value`, whose churn arm was structurally unreachable (it required fleet value to be
  exactly 0 while the local lane lands dozens of commits a day), now fires truthfully:

  ```
  FLEET  value 199 = 198 commits landed …  ⚠ FLEET CHURN — no-conversion, lane-silent:cloud
  DRAIN  23 claim(s) over 12 distinct id(s) → 0 reached done (0%, floor 25%) · reclaim 1.9x per id
  LANES  cloud 0 · local-drain 1
  ```

  Note the shape of the fix: `value` still reads 199 and its meaning is unchanged — the churn arm
  was ADDED beside it and names its reason, rather than redefining a number other consumers read.
  **The §1.6 constraint held**: no new launchd job. The assert rides `com.claude.log-rotation`
  (already hourly) via `scripts/rotate-autonomy-logs.sh`, debounced per UTC day or verdict change,
  with the disposition folded into that job's existing IDL record. 17-case bats suite green,
  including a healthy-window control that stays SILENT, a mutant proving it can fail, and
  UNKNOWN-vs-0 on an unreachable producer. W2 deliberately did NOT rate-floor `value/spend` — its
  numerator is the masked one (it read 21.2 during the zero-drain week); reasoning is in the commit
  body.

- **2026-09-01 — W3 DONE** (pane 197, worktree `drain-loop-w3`), all four §3b items shipped.
  `686acbd70` — bounded pass (`--limit`, default 25) + a persisted cursor + newest-first ordering,
  with `cc-cloud --only` scoping `poll` and `list --state` so the fixed cost stops being O(every
  declaration ever created); pid-liveness lock reap + a TTL sized to the caller's bound (1200 s, and
  NARROWER than the old 3600 s) + `autonomy-sweep` clearing the lock when its own child returns
  137/143; the cloud block hoisted from §2d to **§0a, the top of the pass**; and `cc-cloud gc`.
  `37727f17f` re-anchors the three live comments that pointed at the moved call.
  Suites: cloud-return 39/39, cc-cloud 39/39, autonomy-sweep 61/61, **six mutants RED-proved**
  (including the control that a reap must not steal from a live pass).
  **Measured:** a complete bounded pass is **43 s, rc 0** against **216.4 s** for the unscoped state
  read alone; **19 of 25** sessions reach RETURN-READY in one pass; the deferral is journalled every
  tick (`pass-scope`: `pending_total 468 · taken 25 · deferred 443`), never a silent cap.
  **§3c** records the two further kills this work uncovered: the sweep ITSELF is `cc-reaper`'s
  single largest subject (**719** TERM rows, ages 1362-2063 s), which is the real reason the land
  block was reached ~1 tick in 48 — and why whitelisting it is a TRAP, since the reaper is currently
  that job's only watchdog; and ship-land's **120 s smoke budget for four suites combined** refused
  a branch by naming a suite that is **64/64 in 58 s** standalone, under load 35.7, while telling
  the reader "reproducible: fix it, do not retry unchanged". §3b item 5 is FILED with its
  precondition (`96e532227df8`), not built — 47 items carry 2+ declarations (worst: 30), but the
  guard only de-duplicates once the lane drains; applied today it HALTS cloud dispatch for ~72 items.
  ⚠️ The goal-never-armed finding from the in-flight entry stands as history: `handoff-fire` abstained
  on a torn frame and two `cc-pane send` retries never reached this pane's transcript, so W3 ran the
  whole wave with no Stop-hook backstop (operator step `d7d5a8533f58`). It did not close early, but
  that was discipline rather than mechanism.

- **Still open after tonight**: the four §3b kills are FIXED (W3, above). What remains is
  (a) **the sweep's own runtime** — it needs a self-bound so it stops being garbage-collected at
  ~1400 s; whitelisting is refused for the reason in §3c; (b) **ship-land's smoke budget**, a
  false-refusal generator sitting directly on the drain path, in a file no wave owns;
  (c) the **dispatcher re-fire predicate** (`96e532227df8`), gated on the lane showing a non-zero
  drain rate; and (d) the local lane's self-reference (§1.4, recycle #277, no goal armed, zero
  backlog rows claimed), which still has NO wave assigned and is the remaining half of the
  operator's "deferring rather than completing" complaint.
  ⚠️ **No cloud branch has LANDED yet.** The repaired path reaches the lander and the lander returns
  real verdicts; the two branches tried both refused on their OWN gates (one falsely at the 120 s
  budget, then genuinely 2-of-28 with a budget that fit). A successful land is a property of the
  stranded branches, not of the repair — adjudication is task #174's.
