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

🚨 **CORRECTION, 2026-09-02 — `cc-reaper` was *a* killer, not *the* killer, and it had already
stopped before it was fixed.** The 153 TERMs below are real and the whitelist gap was real, but
binned by day they run **2026-08-19 (29) · 08-20 (24) · 08-21 (22) · 08-22 (9) · 08-23 (14) ·
08-24 (17) · 08-25 (11) · 08-26 (1)** and then **zero**. The fix (`1ca324beb`) landed on 09-01,
five days after the reaper stopped selecting this subject. So it prevents recurrence of a genuine
defect and it did **not** unblock this week's lane; the active blocker from 08-26 onward is the
900 s bound (§3b A, and §3d for what is still true after W3). The headline this section originally
carried — "the garbage collector is eating the landing arm" — was true of 08-19..08-26 and was
asserted as though it were true of now. Recorded rather than silently rewritten: the reasoning
error is that a log's *existence* was read as a log's *currency*, which is the same shape as
`scan-revision-predates-the-fix` in this repo's own memory.

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
| **W8** | L | ✅ DONE — **§1.4's missing instrument**: the effort arm + its carrier record (§3i) | `scripts/backlog-telemetry.sh`, `scripts/rotate-autonomy-logs.sh` (drain_health_check only), their two suites |

**W8's locus is L, and it needs its one line of justification.** The wave's first act was a
*measurement* against two live stores whose result decided whether there was any implementation at
all — the fix was already landed, so a dispatched session briefed to "fix §1.4" would have built a
second one. Once the answer was "instrument, not fix", the deliverable was one arm in one file plus
its test, below the cost of briefing a session. Note that W3's row above claims this territory and
did not deliver it: W3 was re-tasked onto the four §3b kills, which is why §4 recorded (d) as having
no wave.

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

### W5 — the deadline is BUILT and LANDED; the acceptance number is blocked one layer down

`8da7f30b2` (`fix(cloud-return): the caller bounds this pass in TIME`) implements §3d, landed and
content-verified on trunk (4 paths, `land-verify` ✓, stranded-sweep clean).

**What it does.** `autonomy-sweep.sh` now holds the bound in ONE variable, `_cloudret_bound`, which
both arms `timeout -k 10` and is exported as `CC_RETURN_BOUND_S`; the child's single-flight lock TTL
derives from the same figure, deleting the hand-written `1200` that was "900 plus a third". In the
handle loop the child stops STARTING work when `elapsed + reserve` no longer fits 80% of that bound,
where **the reserve is measured, not assumed** — the pass times each `handle()` and carries the
worst forward, floored (first unit only) at the caller's own 120 s smoke budget. That is the part a
count cannot do: when land cost rises the reserve rises on the very pass that observed it. The stop
is journalled as its own `pass-deadline` ledger row, never folded into the cursor's `deferred`, and
the cursor is rewound to what the pass actually did so the unstarted tail returns next tick instead
of waiting a full rotation.

**One defect the tests surfaced, and it is the interesting one.** Newest-first governed ADMISSION
but not PROCESSING: the re-selection iterated the STATE rows and kept whichever ids matched,
discarding the sort it had just paid for. Invisible while every admitted row got handled — and
decisive the moment a budget can run out partway, because whoever starts first is who spends it. A
deadline over an unordered loop would have spent the budget on exactly the stale branches the sort
exists to deprioritise.

**Suites** cloud-return 44/44, autonomy-sweep 62/62, with **seven mutants RED-proved**, each on its
own assertion: the check deleted · the `pass-deadline` row deleted · the cursor rewind deleted · the
check firing unconditionally (caught by the FITS control, so the suite proves it fires for the right
*reason*, not merely that it can fire) · the handle order reverted · a literal `900` beside a correct
export · a correct `timeout` with no export. The deadline arms run on the REAL clock against a
genuinely slow fixture: every other arm in that suite freezes `CC_RETURN_NOW`, and a frozen clock
makes elapsed permanently 0 — a deadline that cannot fire, certified by a harness that collapsed the
two states it exists to tell apart.

🚨 **AND THE ACCEPTANCE NUMBER IS STILL NOT OBSERVED, FOR A REASON ONE LAYER BELOW THIS WAVE.**
`cloud_return_rc` is written by the DEPLOYED sweep, and the deployed sweep is a symlink into the
shared checkout's working tree — which `deploy-live.sh` refuses to advance:

```
deploy-live: waiting — no GREEN tree is a DESCENDANT of live HEAD 850d25a309f5 (the newest one,
             1eb128f88087, is BEHIND it); lag 9 commit(s) / 1h, inside the degrade budget (25 / 6h)
```

The converger is fail-closed on `postland-verify`'s stamp, and **that verifier is being CUT, not
going red**. Its newest stamp is for this wave's own commit and reads:

```
{"commit":"8da7f30b2…","verdict":"cut","failing":[],"run_s":2157,"suites":558,"env":{"load":"14.42"}}
```

`cut` is a machine event, not a verdict about the tree — `failing` is empty. A second run was in
flight at 2026-09-02T08:30Z under load 21.4/66.6/54.2. So the chain is: full-suite run cut by load →
`last-green` stays behind live HEAD → `deploy-live` correctly refuses → the live rail keeps executing
the PRE-deadline bytes → every tick is still 137. **Nothing about that indicts the deadline check**,
and nothing in this wave can drive it: it is the same class as §3c's smoke-budget finding — a bound
sized against a quiet machine, on a box whose load never gets quiet.

**What WAS measured about the fix on real data.** A bounded pass over a copy of the live declaration
store (613 declarations, 496 pending managed, 25 taken) under `CC_RETURN_BOUND_S=900`:

```
rc=0 elapsed=49s   cloud-return: 25 of 496 pending managed session(s) (cursor 275 → 300, 471 deferred)
```

Stated with its limit: that run is `--dry-run`, so it exercises the pass's FIXED cost (49 s, agreeing
with W3's 43 s) and not the lands, which are what the deadline exists to stop mid-slice. It proves
the overhead is not the binding constraint; the deadline's behaviour under real lands is proved by
the suite, and will be proved on the rail by the first `cloud_return_rc` of 0 after the live layer
converges.

**Also observed, live, while this wave ran**: pid 42611 — `cloud-return.sh --sweep --limit 25` out of
the live checkout — held the lock for 7m48s of its 900 s bound with no deadline check in it. That is
the defect still executing, on the old bytes, as designed until convergence.

### W5b — WHY the verifier keeps getting cut: `cc-reaper` was killing it, and the rule is a substring

Chasing "why is `deploy-live` waiting" produced a named culprit rather than a load excuse.
`bin/cc-reaper`'s `stuck-wrapper` arm read:

```awk
if (comm[p]=="bash" && args[p] ~ /cc-close-attrib/ && secs[p]>=1800) …
```

**That is a SUBSTRING test over a whole command line, and a command line is not a name.**
`postland-verify` runs its corpus as `bash …/bats tests/account-cliff-routing.bats …
tests/cc-close-attrib.bats …` over 558 files — **one of which is named after that tool** — so the
corpus matched at the 1800 s threshold every time it ran that long. Two independent logs, and then
a second reproduction 64 minutes later while this wave watched:

```
reaper  07:46:19Z  garbage: TERM stuck-wrapper pid=175 age=1810s argv=<bash …/bats …>
runner  07:48:24Z  corpus TRUNCATED — zero not-ok in a non-zero run — the run was KILLED by
                   signal 15 from OUTSIDE this runner
reaper  08:50:11Z  garbage: TERM stuck-wrapper pid=72748 age=3406s argv=<bash …/bats …>   (×3)
stamp   08:52:09Z  {"commit":"9b308d70a…","verdict":"cut"}
```

The age lands exactly on the corpus start (07:16:01 + 1810 s). Four of six reaper TERMs of a bats
corpus today are followed within ~2.5 min by a `cut` stamp; it is intermittent only because the
reaper's own classifier times out under load and yields no candidates at all.

**The blast radius is the whole deploy pipeline.** `postland-verify` is the ONLY writer of a GREEN
stamp and `deploy-live` is fail-closed on that stamp — so a garbage collector was holding the live
`~/.claude` layer shut. That is why W5's landed fix cannot reach the rail it fixes.

**Fixed in `9f9a64bb4`** by anchoring on argv POSITION, not by lengthening a name list — this repo's
own `pgrep-f-matches-agent-briefs` lesson, whose recorded remedy is exactly that. All three real
wrapper spellings still match; both corpus shapes stop matching. The control pair is one closed
world in both directions and **both halves are RED-proved**: the pre-fix unanchored regex fails the
*survives* half, and an over-wide anchor that collects nothing fails the *dies* half, so the fix
cannot widen into collect-nothing. `tests/cc-reaper.bats` 194/194.

**Deliberately NOT given the `wl` whitelist test its sibling arm has.** `wl` is matched against the
whole argv too, and this arm's subjects are `claude` sessions whose argv carries an operator-written
brief — briefs in this repo routinely say `ship-land`, `postland-verify`, `cc-dispatch`. A whitelist
there would make reapability depend on the PROSE of a prompt: the identical defect pointed the other
way, letting a genuinely stuck wrapper live. Position answers both directions; a name list neither.

🚨 **This is the FOURTH time this file has been found eating its own infrastructure** — `orphan-bash`
on `cloud-return.sh` (§1.1), `orphan-tool` on that call's own 900 s `timeout` (the comment at :655),
`stuck-wrapper` on `postland-verify` (here), against a file that already carries the header *"THE
LAND PATH IS NEVER GARBAGE"* above a list that missed the third spelling. The enumeration-vs-class
defect there is **recurrent, not incidental**, and the next fix to it should be a rule about
position/identity rather than another name.

⚠️ **AND THE FIX IS INERT UNTIL THE THING IT UNBLOCKS RUNS.** `~/.claude/bin/cc-reaper` is a symlink
into the live checkout, which only advances via `deploy-live`, which is fail-closed on the green
stamp the *old* reaper keeps killing. That is the repo's own `deployed-layer-bootstrap-circle`, and
it is filed as `5bc548efd14d` with a falsifier that retracts when `last-green` reaches live HEAD.
The circle is not deadlocked — 4 of 14 runs today reached green, because the kill is intermittent —
so it resolves on its own; it just cannot be *driven* from this side. `deploy-live` reported
`lag 20 commit(s) / 3h` against a degrade budget of `25 / 6h` at the time of writing.


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

- **2026-09-02 — W5 DONE as built-and-landed, NOT as accepted** (`8da7f30b2`, worktree
  `drain-deadline-w5`). §3d's deadline check is in the handle loop, the bound flows from the caller
  that owns the `timeout`, the deferral is its own ledger row and the cursor resumes at the row the
  pass did not start. cloud-return 44/44 · autonomy-sweep 62/62 · 7 mutants RED-proved. Landed and
  content-verified. **The acceptance number — a `cloud_return_rc` of 0 — is NOT observed, and the
  binding constraint is now one layer below this wave**: `deploy-live.sh` is fail-closed on
  `postland-verify`, whose newest stamp is for this wave's own commit and reads `verdict:"cut"` with
  `failing:[]` at load 14.42 (a machine event, not a verdict), so `last-green` stays BEHIND live HEAD
  and the deployed sweep goes on executing the pre-deadline bytes. Full detail, plus the 49 s / rc 0
  bounded dry-run over a copy of the real 613-declaration store and the limits of that measurement,
  in §3d's W5 subsection. This is the same class as §3c's smoke budget: a bound sized against a quiet
  machine, on a box that is never quiet.

- **2026-09-02 — W5b: the convergence blocker has a NAME** (`9f9a64bb4`). `cc-reaper`'s
  `stuck-wrapper` arm matched the SUBSTRING `cc-close-attrib` anywhere in a command line, and
  `postland-verify`'s 558-file corpus carries `tests/cc-close-attrib.bats` in its argv — so the
  reaper was TERMing the only party allowed to write a GREEN stamp, which `deploy-live` is
  fail-closed on. Two logs and two in-session reproductions (07:46/07:48 and 08:50/08:52). Fixed by
  anchoring on argv POSITION, with a both-directions control pair, both halves RED-proved;
  cc-reaper 194/194. It is the FOURTH kill by that file on its own infrastructure. The fix is inert
  until `deploy-live` converges (the reaper is itself a live symlink) — the bootstrap circle, filed
  `5bc548efd14d`, self-retracting. Detail in §3d W5b.

- **Still open after tonight**: the four §3b kills are FIXED (W3, above). What remains is
  (a) **the sweep's own runtime** — it needs a self-bound so it stops being garbage-collected at
  ~1400 s; whitelisting is refused for the reason in §3c; (b) **ship-land's smoke budget**, a
  false-refusal generator sitting directly on the drain path, in a file no wave owns;
  (c) the **dispatcher re-fire predicate** (`96e532227df8`), gated on the lane showing a non-zero
  drain rate; and (d) the local lane's self-reference (§1.4, recycle #277, no goal armed, zero
  backlog rows claimed), which still has NO wave assigned and is the remaining half of the
  operator's "deferring rather than completing" complaint.
  ↳ **(d) is TAKEN by W8 — see the 2026-09-03 entry below and §3i.** Its "no goal armed" clause was
  already false when written: `1eb128f88` landed the goal chokepoint on 09-01.
  ⚠️ **No cloud branch has LANDED yet.** The repaired path reaches the lander and the lander returns
  real verdicts; the two branches tried both refused on their OWN gates (one falsely at the 120 s
  budget, then genuinely 2-of-28 with a budget that fit). A successful land is a property of the
  stranded branches, not of the repair — adjudication is task #174's.

- **2026-09-03 — W4 DONE as built-and-landed, NOT as accepted** (worktree `drain-loop-w4`; full
  record §3g, which opens by reconciling itself with §3f — W7 measured that the observed 137s were
  dominated by `cc-cloud list`'s admission read, not by a land, so what W4 fixes is the NEXT binding
  term rather than the one that was firing). The deadline now survives the kill: the price of a land is persisted with the epoch it
  was observed at, written BEFORE the land so a cut records a lower bound, and read back to gate
  STARTING a land inside `handle()` rather than admitting a unit blind. The brief's (a)-or-(b) fork
  was refuted by measurement — `land.log` prices a land at p50 246 s / p90 680 s / max 14,783 s, both
  of the first two inside the existing 720 s budget — so neither raising the caller's bound (which
  `autonomy-sweep.sh:373-375` refuses in its own words, because §0a puts this block FIRST and the
  rest of the sweep waits behind it) nor admitting zero units (which starves the cheap 95% to guard
  against the expensive 5%) was taken. cloud-return 53/53, seven mutants RED-proved by anchored
  edits, two of which survived their first run because the ARM was wrong — see §3f, both are worth
  reading. ⚠️ **Still no daemon-produced `cloud_return_rc: 0`**, and this wave cannot produce one:
  that row comes from the deployed sweep, which advances only through `deploy-live`'s GREEN stamp
  (§W5, §W5b). The mechanism proof is the deliverable; the row is the later confirmation.

- **2026-09-03 — W8 DONE: §1.4 is measured, and its fix turned out to already be landed** (worktree
  `drain-loop-w4`; full record §3i). The wave opened by checking the brief's premise and found the
  closure-floor chokepoint (`1eb128f88`, 09-01) live and holding: the commits-per-closure ratio went
  **49.0x on 09-01 → 4.1x on 09-02 → 3.6x on 09-03**, with 16 of the 19 rows closed in that window
  carrying no `venue=cloud`. So the deliverable is not a second fix — it is the **instrument that
  was missing**, without which the working fix regresses as silently as the `--goal` did for 183
  fires. `backlog-telemetry.sh` gains an EFFORT arm (commits produced vs rows discharged,
  `scope=repo`, sharing the conversion arm's exact window and denominator, `--assert`-participating,
  abstaining on a numerator sample floor and on an unreadable repo). The live store reads **7.0x,
  green, ceiling 10** — so it cannot fire on the day it lands, and F2 proves it can fire at all.
  ⚠️ **The carrier had to change too, and that was this wave's own defect**: `rotate-autonomy-logs.sh`
  parsed only `scope=fleet` and debounced on rc + conversion verdict, so on a fleet ALREADY red with
  `drain-futile` an effort flip would have journalled `assert:"red"` beside `verdict:"drain-converting"`
  and then been debounced into invisibility. `effort`/`effort_ratio` are now in the record and in the
  key. No new launchd activation (§1.6 constraint holds). backlog-telemetry 23/23 ·
  drain-conversion-churn 19/19 · five mutants RED-proved — **one of which (F5) exposed a vacuous
  fixture of my own**, straddle-the-floor being the only shape that discriminates. Untouched and
  named: close attribution is at 7.7% coverage, which is why `lane=local-drain` still reads
  `lane-stalled` and why this arm is scoped fleet-wide rather than per-lane.

- **2026-09-04 — W9 DONE: §3e's flagged-not-fixed corollary, built** (cloud worker, full record §3j).
  §3e closed by naming a risk it declined to act on: `postland-verify.sh` defines CUT as a machine
  event and asserted, in shipped code, that an rc>128 came *"from OUTSIDE this runner"* — which W6's
  own intervention refutes, since this runner arms `timeout -k 10` with no `--foreground` and
  coreutils then SIGKILLs its own process group, surfacing as 137 for OUR OWN ceiling. §3e's stated
  remainder was that *"establishing an actual misfire needs the per-run rc"*, and the stamp carried
  none. Both halves are now closed: the message states the sender is **not established** and names
  the discriminator, and every stamp carries `rc`, `corpus_s` (the CORPUS's own clock, not `run_s`)
  and `bound_s` (the ceiling actually armed), each JSON `null` — never 0 — where the corpus did not
  run or no bound existed. This is the `elapsed_s`/`load1` fix on the `cloud-return` IDL row applied
  one layer down: the layer whose cut stamps are
  what hold `last-green` behind live HEAD, i.e. the reason every fix in this plan has been landed and
  inert. ⚠️ **It measures; it does not converge.** A stratified verdict needs cut stamps written by
  the DEPLOYED runner, so the first usable reading is one converge cycle away — and this wave cannot
  produce it, for the same reason §W5, §3f and §3g each recorded.

---

## 3e. THE SIGKILL IS ATTRIBUTED — `timeout` kills itself (W6, 2026-09-03)

**The sender is the `timeout` process.** GNU coreutils `timeout` 9.1 (`/opt/homebrew/bin/timeout`),
invoked without `--foreground`, puts ITSELF and its child in a new process group and delivers the
`-k` escalation to that whole group with `kill(0, SIGKILL)`. `SIGKILL` cannot be ignored, so
coreutils' own anti-self-signal guard is a no-op for signal 9 and `timeout` dies before it can reach
`status = EXIT_TIMEDOUT`. The shell therefore reports its direct child — the `timeout` pid — as
`Killed: 9` and yields 137. Nothing external is involved.

**The brief's premise was false, and it is the premise every wave since W3 inherited**: *"a `timeout`
killing its own child surfaces as 124, so this SIGKILL arrives from OUTSIDE."* True of the child's
death, false of `timeout`'s own. That is why three correct fixes changed nothing — the cause was
never in the code they changed, and `cc-reaper`, jetsam, `compressor-sentinel`, `capacity-alarm`,
`lead-supervisor` and `qos-census` are all uninvolved.

**Proved by intervention, not correlation.** A bystander (`/tmp/w6-pgid-victim.sh`, matching no
pattern on this box) placed in `timeout`'s process group DIES with it — a scope only a group-directed
signal has, and one no argv matcher can select. Flipping the single flag that governs group
signalling (`--foreground`) leaves that same bystander ALIVE and removes the job-control line, with
every daemon still running. Control: a child that dies on SIGTERM returns 124, so the harness can
produce the other verdict. Repeatability 5/5 within ~3 s each. Full arms, verbatim output and the
honest limit: `docs/research/sigkill-attribution-2026-09-03.md`.

**The precondition holds by construction**, which is why it is 137 on every row and not sometimes
124: `cloud-return.sh:776` is `trap 'lock_release' EXIT INT TERM`, and a bash trap runs only between
commands — when the bound fires the pass is inside `handle()` → `ship-land`, minutes long, so the
child cannot exit inside the `-k 10` grace. Same signature at a different bound on the sibling call
(`autonomy-sweep.sh:461`, `timeout -k 10 180 … cloud-refusal-route.sh`), killed in the same ticks.

**The honest limit.** `dtrace` and `ktrace` both refuse without root (SIP). What is proven is that
this mechanism reproduces the exact signature deterministically in isolation and is removed by the
one flag that governs it; no external sender is REQUIRED to explain any observation. The one method
that would close the residual "also" case is a root `dtrace proc:::signal-send` probe naming the
sender pid — filed as an operator step, not guessed at.

**Corollary, flagged not fixed.** `postland-verify.sh:34-35` defines CUT as a machine event and
`:2837` names its discriminator as *"a peer pkill shows rc>128 / a job-control line"* — exactly what
`timeout -k`'s own escalation produces, and the suite runs under `timeout -k 10 10800` (observed
live, pid 46358, 02:50 elapsed). So CUT cannot distinguish an external pkill from our own bound
firing. That matters because CUT is what holds `last-green` behind live HEAD and blocks
`deploy-live` per §W5. Stated as a RISK: the §W5 stamp's `run_s: 2157` is not a 10800 s bound, so
that particular cut was something else, and establishing an actual misfire needs the per-run rc.

**This licenses no bound change.** The bound is not the defect; the reading of 137 was. `--foreground`
is not a fix either — the child is still SIGKILLed and the pass still cut; it only stops the blast
reaching `timeout` and the group. W5's deadline remains the right owner of the real remaining
question (one `handle()` unit can exceed the whole remaining budget once started), now free of a
phantom killer.

---

## 3f. THE BUDGET WAS SPENT BEFORE THE WORK STARTED — and it was `cc-cloud list` (W7, 2026-09-03)

**The pass was never losing its budget inside `handle()`. It was losing it to the inventory read.**
W5's deadline gates STARTING a unit and deliberately never interrupts a land in flight, so the open
question after W6 was stated as *"a single `handle()` unit can exceed the entire remaining budget
once started"*. **The ledger refutes that**, and it is the only `pass-deadline` row that exists:

```json
{"ts":"2026-09-03T13:51:34Z","outcome":"pass-deadline","elapsed_s":907,"budget_s":720,
 "bound_s":900,"started":1,"unstarted":15,"worst_unit_s":4,"cursor_to":76}
```

`worst_unit_s: 4`. The one unit this pass started cost **four seconds**. The deadline check fired at
elapsed **907** — already past the 900 s bound — so `timeout` was in its `-k` grace when the row was
written, and the SIGKILL landed three seconds later. The budget was gone before the loop.

**Where it went, from the pass's own rows.** `START_S` = 13:51:34 − 907 = **13:36:27**. The
`pass-scope` row for the same pass (`cursor_from: 75`) is stamped **13:47:41** — and that row is
written BEFORE the first network call. So:

| phase | seconds | share | what it is |
|---|---|---|---|
| admission — `cc-cloud list --json`, filter, sort, cursor | **674** | 74% | disk only, no probe, no work |
| the two scoped probes over 25 ids (`poll --only`, `list --state --only`) | 229 | 25% | network, already bounded by `--only` |
| `handle()` × 1 | **4** | 0.4% | the actual work |

**The mechanism, measured first-hand.** `cmd_list --json` answered each of eighteen fields with its
own full-file scan through `dfield`, and escaped each through its own `$( )` subshell — **11,394
file scans and ~12,000 forks** to project a store of 633 thirteen-line files. A/B on this box, same
command, same store:

```
foreground        13 s      (which is why this survived: it is invisible where humans run it)
background band   still unfinished at 42 min, killed          ← the band launchd actually uses
```

`~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist` sets **`ProcessType Background`**. That is
the background QoS band, PRI 4, on a box whose load average sits above 20. This is the repo's own
`bound-must-fit-the-band-not-the-bench` lesson in its purest form: nothing in `cmd_list` is wrong in
the band it was written in, and it is catastrophic in the band it runs in.

**The fix is a constant factor, and touches no bound.** `dload` reads each declaration ONCE into
`D_<key>`/`S_<key>`; `jesc_v` escapes through `printf -v` instead of a subshell. No cap, timeout,
limit or retry moves — per §3e that would have been acting on a 137, which is forbidden and would
also have been aimed at the wrong phase.

```
foreground        13 s → 1 s      byte-identical over all 633 rows (age_s normalised: it is a clock)
background band   674 s → 4 s     ⚠️ SUPERSEDED — see "the honest speedup" below
```

### The honest speedup — and why the line above it was not one

🚨 **`674 s → 4 s` pairs two numbers taken at different LOADS, which makes it an artefact of the box
and not a measurement of the change.** The 674 s is a real production observation, reconstructed from
a pass's own ledger timestamps at load ~23. The 4 s was measured later at load ~14. Neither is wrong;
putting an arrow between them is. That is this repo's own `scalar-sample-of-a-varying-quantity`
lesson, committed here before anyone caught it — a quantity that varies across its subject was
sampled once per arm and then differenced.

**Paired, back-to-back, same box, alternating old/new so both arms see the same load:**

| band | old | new | ratio | load |
|---|---|---|---|---|
| background (the sweep's band) | 56 s · 59 s | 3 s · 4 s | **~16×** | 9.9 · 10.2 |
| foreground | 16 s · 15 s | 1 s · 1 s | **~15×** | same |

**The claim that survives is a RATIO, ~15×, stable across both bands** — which is what a constant
factor should look like, and unlike an absolute figure it does not rot with the box's load. Applied
to the production observation: 674 s of admission at load ~23 becomes ~45 s, which fits a 720 s
budget with room for real lands.

### The pass itself, end to end, in the production shape

Not the isolated call but `cloud-return.sh --sweep --limit 25` under `timeout -k 10 900`,
`taskpolicy -c background`, `CC_RETURN_BOUND_S=900` — against a COPY of the live declaration store
(642 declarations) and `--dry-run`, so a checkout copy can never land a branch or mark an item done:

```
NEW reader   rc=0  elapsed=94s    25 examined · pass-scope written · NO pass-deadline row
OLD reader   rc=0  elapsed=149s   25 examined · pass-scope written · NO pass-deadline row   (control)
```

🚨 **Read the control honestly: at load ~8 the OLD reader completes too.** This pair does NOT show
the fix rescuing a pass that would otherwise die — at that load nothing was dying. What it shows is
the pass's fixed cost falling from 149 s to 94 s of a 720 s budget on a quiet box, while the
production 137s were all recorded on a loaded one. **The fix's value is specifically at high load,
which is exactly when the lane was failing**, and the mechanism is the ~15× above rather than
anything visible in these two numbers.

**Its limit, stated rather than glossed:** `--dry-run` exercises the FIXED cost in full — which is
the 674 s this change removes — and does not exercise the lands. The deadline's behaviour once lands
are running is W5's suite's claim, not this one's.

**Verification.** `--json`, `--table` and `--json --only` all byte-identical against `origin/main`'s
reader over the live store. Suites green: cc-cloud 43/43 (4 new), cloud-return 45/45,
autonomy-sweep 62/62, cloud-reconcile 33/33, cloud-inbox 7/7 — **190/190**.

**Four mutants, each red on its own assertion** — the new failure modes are exactly the ones a
per-file reader has and a per-field reader cannot:

| mutant | red |
|---|---|
| the per-file reset hoisted out of the per-file path (initialises once, never clears) | bleed only |
| `jesc_v` does not escape | escaping only |
| `dload` resolves a duplicated key LAST-wins instead of first-wins | duplicate only |
| `eval` instead of `printf -v` | no-eval + escaping (both genuinely depend on verbatim storage) |

**One claim was wrong on the first pass and is corrected in the code.** The whitelist was documented
as the injection guard. It is not: the `${p}_` NAME PREFIX is what confines a `PATH=` line to
`D_PATH`, and `printf -v` refuses an invalid identifier rather than evaluating an array subscript
(probed on this box — it did not run). `DLOAD_KEYS` bounds the name set to exactly what the reset
clears, which is a *correctness* property and is what the bleed case pins. A mutant that disabled
the whitelist left the old test green, which is what exposed it.

**What this does NOT yet prove.** The acceptance number is still a live `cloud_return_rc` of 0, and
that needs a tick of the deployed sweep. The arithmetic now admits one: 4 + 229 = 233 s of a 720 s
budget, leaving ~487 s for units the deadline can spend and stop cleanly inside. The 229 s of scoped
probes is unchanged and is the next binding term if it ever grows.

🚨 **CORRECTION to the sentence immediately above — the next binding term is NOT the probes, it is a
LAND, and a sibling session measured it the same day.** `3457755d7` (`fix(cloud-return): the price of
a land outlives the pass that paid it`) found the complementary defect in W5's own deadline:
`WORST_UNIT_S=0` at the top of every pass, so the measured reserve is destroyed by exactly the event
it exists to predict, and the `N -gt 0` clause then admits unit #1 unconditionally. At their measured
**p90 land of 680 s**, one unit does not fit the ~487 s this change hands back — so the land, not the
229 s of probes, is what binds next. That commit reconciles with this one explicitly and declines to
claim the fifteen observed 137s, which `worst_unit_s: 4` already attributes to fixed cost. **Read the
two together: this one gives the pass a budget to spend, that one stops it spending the budget on a
unit it cannot finish.** Neither is sufficient alone.

### The two fixes RUN TOGETHER — nobody had done that, and they compose

Both landed the same day, in different files (`bin/cc-cloud` here, `scripts/cloud-return.sh` there),
so nothing forced them to meet. Run from the full trunk tree at `236c0c76c`, production shape —
`timeout -k 10 900` · `taskpolicy -c background` · `CC_RETURN_BOUND_S=900` · `--limit 25` — against a
COPY of the live declaration store under `--dry-run`:

```
rc=0   elapsed=145s of a 900s bound (budget 720)   25 examined
       1 pass-scope · 18 `waiting` verdicts (so the scoped probes DID run) · NO pass-deadline row
```

An earlier attempt at this scored 111 s and is NOT the number to quote: it ran from a partial tree
where `cloud-create-api.py` was absent, so 18 of 25 rows returned `abstain` — correct behaviour by
the subject, and a nearly-vacuous measurement, because a row that abstains never pays for the work
the timing is supposed to cover. The 145 s figure is from the full tree where those same rows reach a
real verdict.

### §3f status at hand-off — LANDED, content-verified, NOT YET LIVE

`7e0f6c9f1` is on `origin/main`; `land-verify` reported *3 path(s) present + content-identical*.
Suites on the landed tree: cc-cloud 43/43 · cloud-return 45/45 · autonomy-sweep 62/62 ·
cloud-reconcile 33/33 · cloud-inbox 7/7 = **190/190**. `shellcheck -S warning` 0 findings, matching
`origin/main`'s baseline of 0.

**The acceptance number is still unobserved, and the reason is one layer down — the same one §W5
hit.** `~/.claude/bin/cc-cloud` is a symlink into the SHARED CHECKOUT's working tree, and
`deploy-live` refuses to advance it:

```
deploy-live: already deployed — live layer is at the newest deployable commit 24c598bac1c7
             (6 un-stamped commit(s) above)
```

`~/.claude/autonomy/postland/last-green` reads `24c598bac1c7…` — the pre-land HEAD. The converger is
fail-closed on `postland-verify`'s stamp, that verifier was observed RUNNING on the new trunk
(`timeout -k 10 10800 … bats <the corpus>`), and until it stamps green the live rail keeps executing
the OLD reader. **So every `cloud_return_rc` written before that stamp is still evidence about the
pre-fix bytes and must not be read as evidence about this change.** Nothing here indicts the fix;
it is the §W5 convergence dependency, unchanged.

**Two land-gate facts worth keeping**, both about the gate rather than the tree: the first attempt
was refused `GATE RED` off a `GATE-KILLED` — `tests/cc-notify.bats` cut by the 120 s smoke budget
with ZERO `not ok`, which is backlog `b54edfb6da6e` (one budget across all suites) firing on an
unrelated suite. Re-run at `SHIP_LAND_SMOKE_BUDGET_S=900` the smoke went green in 285 s. The second
refusal WAS real and was mine: 36 fresh SC2154 from `printf -v`, which shellcheck cannot follow.

## 3g. W4 — THE PRICE OF A LAND NOW OUTLIVES THE PASS THAT PAID IT (2026-09-03)

**The defect W5's deadline still had, and it is one line.** `scripts/cloud-return.sh:907` set
`WORST_UNIT_S=0` at the top of every pass. The reserve therefore floored at `UNIT_RESERVE_S` (120 s)
on the first unit, the `N -gt 0` clause admitted unit #1 unconditionally — deliberately and
correctly, since a pass that admits itself and does nothing is a stall wearing a bound's clothes —
and if unit #1 fell through to a real land it outlived the caller's whole 900 s bound. The pass was
killed and **the observation died with it**. The next pass re-initialised to 0 and repeated
identically, forever: the estimate was learned per-pass and destroyed by the very event it exists to
prevent. Fifteen `cloud_return_rc` rows on 2026-09-03, every one 137 or 124, not one 0 — against a
cursor that was advancing and a lock that was never contended, so nothing else was wrong.

⚠️ **RECONCILED WITH §3f, WHICH LANDED THE SAME DAY AND FOUND A DIFFERENT CULPRIT FOR THE SAME
137s — read that section first.** This wave was briefed on the premise that unit #1 was a real land
outliving the bound. **§3f refutes that for the one `pass-deadline` row that exists**: `worst_unit_s:
4`, and 674 of 907 s went to `cc-cloud list`'s admission read *before the loop ever ran*. So the
observed kills were dominated by a fixed cost, not by a land, and W7's constant-factor fix is what
actually reclaims the budget. Two things survive that correction, and the honest framing is that
they are complementary rather than rival:

  * **The mechanism named below is real and unchanged** — `WORST_UNIT_S=0` per pass, an estimate
    destroyed by the event it exists to prevent — and no measurement in §3f touches it.
  * **It is now the NEXT binding term, and reachable rather than hypothetical.** With ~487 s of
    usable budget restored, one land priced at the measured p90 of 680 s still does not fit, and the
    pre-W4 loop starts it unconditionally and is killed exactly as before, destroying the
    observation again. §3f gives the pass a budget to spend; this stops it spending that budget on a
    unit it cannot finish.

The claim this section does NOT make, as a result: that the fifteen 137/124 rows were caused by
lands. They were not, on the only evidence there is.

### The measurement that decided the design, and it refutes both options as the brief posed them

The brief offered a fork: (a) raise `CC_SWEEP_RETURN_BOUND_S` so one land fits, or (b) admit zero
loudly. **Neither is right on its own, because the cost is BIMODAL and the brief's 1366 s figure is
the tail, not the body.** Measured over all 2,329 `total_s` rows of `~/.claude/land.log`:

```
n=2329   min 0   p50 246 s   p90 680 s   max 14,783 s
```

p50 and p90 both fit inside the 720 s budget the existing 900 s bound already yields. So (a) is
unnecessary — and it is also *contradicted in the tree*: `autonomy-sweep.sh:373-375` says in its own
words that the bound is "deliberately NOT raised to make lands fit — this pass shares a 300 s
launchd tick with the rest of the sweep, so a longer bound makes it a worse neighbour", and §0a
exists precisely because this block is FIRST and everything else waits behind it. And (b) alone
would have converted a SIGKILL loop into a no-op loop: `handle()` returns early and nearly free for
the overwhelming majority of rows (already returned · BOOTING · NOT-STARTED · worker running · not
quiet · refusal already earned on this head), so admitting zero UNITS starves the cheap 95% to
protect against the expensive 5%.

**The right cut is one level down: gate the LAND, not the unit.** Step 4 of `handle()` is the entire
cost; everything above it is disk and one bounded status probe. So the pass stops before STARTING a
land it cannot afford, and keeps doing all the cheap work it always could. That also fixes the span:
one scalar over all units is the wrong statistic for a bimodal population (memory:
`assertion-span-must-equal-its-subject`), and a global max would let one 14,783 s outlier price
every cheap unit out of the budget forever.

### What landed

Two estimates over two populations, each persisted with the epoch it was observed at:

| Sidecar | Population | Gates |
|---|---|---|
| `.return.unit_cost` | the worst NON-LANDING unit | seeds `WORST_UNIT_S`; admission to the loop |
| `.return.land_cost` + per-session `<id>.land-cost` | the price of a land | starting a land, inside `handle()` |

Three properties carry the fix:

1. **The floor is written BEFORE the land, not after.** A cut land is the observation the estimate
   most needs and the one no post-hoc measurement can ever take, because the process that would
   record it is the process that dies. The pre-land write is a lower bound and an honest one — the
   land ran at least until the bound fired, i.e. `BOUND_S - elapsed` — and the true figure supersedes
   it the moment the land completes, **including downward**, which is what stops one cut from pricing
   every later land at a whole bound forever.
2. **Nothing is a max forever.** Each record carries its epoch and expires (`CC_RETURN_COST_TTL_S`,
   6 h), so a pessimism earned by one pathological branch heals by itself instead of latching the
   lane shut. A stale or unparseable record reads as NO OBSERVATION, never as a cheap one.
3. **The per-session figure is what keeps one branch from speaking for all of them.** A deferral
   distinguishes the two cases in its own words and in its ledger row: "this tick is out of budget"
   resolves on the next tick and needs nobody; `fits_bound:false` — one land does not fit this bound
   at ANY elapsed — never resolves on its own and is the operator's to act on, with both remedies
   named.

A land deferred here has taken no lock, evaluated no gate and pushed nothing: it files no artifact,
sends no wake and latches nothing, which is the same standing a cut land already had.

### Proof

**DoD 1 — a pass given a bound it cannot fit exits 0 having stopped itself**, where the live rail was
SIGKILLed on this exact shape:

```
DoD-1 rc=0
DoD-1 | · session_test — NOT starting the land: a land is priced at 1400s and 0s of the 720s budget
DoD-1 | is spent — WHICH DOES NOT FIT THIS BOUND AT ALL: no tick can ever start it. Raise
DoD-1 | CC_SWEEP_RETURN_BOUND_S, or move the land off the sweep tick. Nothing filed, nothing latched.
```

**DoD 2 — the estimate survives the kill.** The pass is SIGKILLed mid-land (bats reports its own
`Killed: 9`), and the next pass reads the floor back and declines:

```
DoD-2 | session_test.land-cost = 1788458374 900
```

**DoD 3 — 53/53 with seven mutants RED-proved by ANCHORED edits**, each asserting its anchor matched
exactly once before writing, because a `sed` that matches nothing reads exactly like a surviving
mutant: the land gate deleted · the unit price not seeded from disk · the floor written after the
land instead of before · the completed measurement never superseding the floor · the non-landing
measurement never written · the expiry removed · a land folded into the non-landing price. The
control that can FAIL is the same fixture with **no price on disk**, which reproduces the pre-fix
behaviour and starts a land it cannot finish.

🚨 **Two of those seven survived the first run, and both were defects in this wave's own work, not
in the subject.** (i) The `SURVIVES THE KILL` arm ran the fixture under `timeout -k 2 6` — which
*looks* faithful and is not, because `timeout` signals the whole process GROUP (§3e): the lander
died, the pass observed rc 143, took its own land-cut path and ran to completion, after which the
POST-land write recorded the price and the arm passed with the floor deleted. It certified nothing.
The faithful shape is a SIGKILL to the pass while its lander still runs. (ii) The seed arm's
discriminator did not discriminate: unit #1's own in-pass measurement already produced the same stop,
so the persisted value changed no outcome. Both are the same lesson — an arm can be green for a
reason that has nothing to do with its subject.

**And the mutation run found a live defect nobody's assertion covered**: `cost_read` had
`2>/dev/null` AFTER its input redirection, and redirections apply left to right, so the shell's own
"No such file or directory" for a sidecar that does not exist yet went to an un-silenced stderr —
three of them in the middle of the pass's own output. Fixed.

**One landed arm was amended, and it is an amendment rather than a loosening.** `a LAND already in
flight is never abandoned to meet the deadline` (W5) asserts NON-INTERRUPTION, and to test that the
land must first BEGIN; its deliberately tiny 2 s bound cannot fit a land priced at the 120 s
cold-start floor. It now says `CC_RETURN_LAND_RESERVE_S=0` explicitly and runs at a 6 s bound — the
2 s budget was smaller than the pass's own fixed cost, which made admission a coin flip once the new
gate started reading the clock (observed failing 1 run in 2). Its subject is unchanged; whether the
new gate fires for the right reason is a different property with its own arms.

### What is NOT observed, and will not be from here

**No daemon-produced `cloud_return_rc: 0` row exists yet, and this wave cannot produce one.** The
row is written by the DEPLOYED sweep, which reaches this file through the live `~/.claude` layer,
which only advances via `deploy-live` — fail-closed on `postland-verify`'s GREEN stamp, which took
~1.5 days for W3's land and is the same converge lag §W5 and §W5b document. The mechanism proof
above is the deliverable; the daemon row is the later confirmation, and claiming it now would be
asserting a fact about a git ref while the machine ran older bytes — the `🚀` rung, whose whole
point is that landed is not live (`docs/research/inertness-generator-2026-08-07.md` §3).

---

## 3g. THE ACCEPTANCE NUMBER IS OBSERVED — and it is a WEAKER test than we believed (2026-09-03)

**`cloud_return_rc` of 0 is in the IDL.** Three of them, and the live layer does now run both fixes —
`~/.claude/bin/cc-cloud` is byte-identical to trunk's and contains `dload`/`jesc_v`;
`~/.claude/scripts/cloud-return.sh` carries `LAND_COST_F`. The shared checkout (which those symlinks
resolve into, i.e. the live layer's source) fast-forwarded `24c598bac → 236c0c76c` at **19:08:13Z**,
and `236c0c76c` contains both `7e0f6c9f1` and `3457755d7`.

```
17:58:32Z  rc=0    ← BEFORE convergence: the OLD reader
18:25:50Z  rc=137
19:07:35Z  rc=null
19:13:27Z  rc=137  ← AFTER convergence
19:47:09Z  rc=0    ← after: pass-deadline elapsed_s 791, started 4, unstarted 21
20:37:27Z  rc=0    ← after: pass-deadline elapsed_s 791, started 2, unstarted 23
```

The two post-convergence zeros are passes that did **real work** — `pass-scope` taken 25, four
`land-refused` verdicts and an `abstain` between them, then a clean stop at 791 s of a 900 s bound
via the deadline instead of a SIGKILL at 910. That is precisely the designed behaviour, and it is
what the lane was built to do.

🚨 **BUT THE 17:58 ROW REFUTES THE ACCEPTANCE CRITERION ITSELF, AND IT IS OURS TO OWN.** §3d chose
rc 0 as the acceptance number on the premise that it had *never occurred* and therefore could only
occur once the pass was repaired. The 17:58 pass was **not vacuous** — it wrote `pass-scope` taken
25, a `land-refused`, and a `pass-deadline` at `elapsed_s: 640, started: 1`. So a clean, working,
rc-0 pass happened **with the old reader, before either fix reached the live layer**. rc 0 was
already reachable; what it needed was for the pass to reach the deadline check before the bound
fired, which on a quiet box it could.

**The unexcluded confound is LOAD, and it is large.** Measured on this box across exactly the window
in which 137s turned into 0s: **~23.3 → ~14.6 → ~8.1–10.2**. The failing regime was a loaded box;
the passing regime was a quiet one. That is the same confound this wave's own A/B already surfaced —
at load ~8 the OLD reader completed a full pass in 149 s — and it means these three zeros **cannot
carry a causal claim** for either fix. `wrong-cause-corroborated-by-true-metric`, with the true
metric being our own acceptance number.

**What is honestly established, and what is not:**

| claim | status |
|---|---|
| both fixes are LIVE, content-verified in the enforcing store | **established** |
| the admission read is ~15× cheaper, paired, in both bands | **established** (§3f) |
| a pass now stops cleanly at its budget instead of being SIGKILLed | **established** — two `pass-deadline` rows, `elapsed_s: 791`, real work started |
| *these three zeros were caused by the fixes* | **NOT established** — one predates convergence; load fell ~23 → ~8 across the window |

**The acceptance test should have been load-controlled, and its replacement is a RATE, not an
event.** A single rc 0 is satisfiable by a quiet box. The discriminating measurement is the ratio of
0 to 137 over a window that *spans* loads — or, better, the rc paired with the pass's own
`elapsed_s` and the box's load average, neither of which the `cloud_return_rc` row currently carries.
**Filed rather than built here:** add `load` and `elapsed_s` to the `cloud-return` IDL row, so the
next person asking "did the fix work" can stratify instead of counting events. Until then the fixes
stand on §3f's paired ratio and the suites, not on these three rows.

---

## 3i. §1.4 HAD A FIX AND NO INSTRUMENT — the effort arm (W8, 2026-09-03)

§1.4 is the remaining half of the operator's "deferring rather than completing" complaint: the local
lane produced **304 trunk commits against 30 backlog closures** over seven days, its whole file
footprint being the drain's own machinery, each recycle auditing the recycle before it. The status
log recorded it as the item with **no wave assigned**.

### The fix already existed. Measured first, because the brief's premise deserved a check.

`scripts/drain-recycle-fire.sh` landed `1eb128f88` on 2026-09-01 and is the chokepoint that puts the
closure floor into the recycle GOAL — the one surface on this box that can refuse to let a session
stop. It is live (a per-file symlink, so it converged on the land rather than waiting on
`deploy-live`). Measured this session against the live stores:

| day | trunk commits | distinct ids closed | ratio |
|---|---|---|---|
| 08-29 | 49 | 1 | **49.0x** |
| 08-31 | 31 | 6 | 5.2x |
| 09-01 | 49 | 1 | **49.0x** |
| 09-02 | 41 | 10 | 4.1x |
| 09-03 | 32 | 9 | 3.6x |

The chokepoint landed at 09-01T21:51 local (09-02T04:51Z), and **16 of the 19 rows closed on 09-02
and 09-03 carry no `venue=cloud`** — they are the local lane's own. So the mechanism is holding, and
building a second fix for a defect whose fix is working would have been the wave's easiest mistake.

### What was actually missing: nothing could SEE it, and nothing would see it regress

Every arm of `backlog-telemetry.sh` read the backlog and only the backlog, so all of them were blind
to the same axis — **what the fleet spent its day on**. A lane closing one row a day, on cadence,
while landing forty-nine commits into its own machinery rendered `verdict=lane-ok`. That is §1.5 one
level up: the instrument that exists reads healthy over the defect, exactly as `cc-value` read
`value 87` through the zero-drain week.

A fix with no instrument regresses silently, and this one already has a precedent for doing so: the
chain dropped its `--goal` for **183 fires running** and no number on this box moved.

### What landed

An **EFFORT arm** in `scripts/backlog-telemetry.sh` — commits produced against rows discharged, over
the same seven days every other arm reports, with `verdict=effort-productive` /
`effort-self-referential` / `effort-unmeasured`, participating in `--assert`. Design points, each of
which is a refusal of a trap this repo has already paid for:

- **Scope is `repo`, labelled, and it is the same fact as `drain-futile`'s `scope=fleet` — not a
  shortcut.** A commit carries an author and a message, not the `lane` this file attributes closes
  by. Splitting the numerator per lane would mean inferring a lane from a commit, the identical
  guess the file refuses at the top for `venue`. It counts what §1.4 counted, the way §1.4 counted
  it, so the number is comparable to the one that named the bug.
- **One window, indexed twice.** The shell hands jq a commits-per-day map; jq sums it over the same
  `$w7dates` the conversion arm already scopes itself by, and the denominator is literally
  `$w7dids`. There is no second definition of "a close" and no second window.
- **The sample floor is on the NUMERATOR.** Below `CC_BLTM_EFFORT_MIN_COMMITS` (20) the arm
  abstains — a quiet week is not a self-referential one. It is deliberately NOT on the closes:
  `closes == 0` with real production is not too small a sample to judge, it is the **limit** of the
  defect, and a floor placed there would abstain exactly where the alarm has to fire.
- **A failed probe is UNKNOWN, never 0.** `COMMITS_BY_DAY` is the JSON literal `null` when git
  cannot be read, and an empty map when git answered with no commits. Rendered as a clean zero, a
  broken instrument would print the healthiest number this file can produce.
- **The polarity is checked in both directions before shipping.** The live store reads **7.0x** over
  7 days (green, ceiling 10) while the sick regime read 10.1x and 49x — so the arm neither fires on
  the day it lands nor is incapable of firing.

### The carrier could not have carried it, and that was this wave's own defect

`rotate-autonomy-logs.sh` (the hourly host W2 wired the assert onto — still no new activation, per
§1.6) parses the verdict from `grep 'scope=fleet'`, and its debounce key was `day + rc + conversion
verdict`. So the new arm would have ridden the rc while the journalled reason still read
`drain-converting` — a red with a green reason — and, because **the fleet is already red on
`drain-futile`**, an effort flip would have changed neither key term and been **debounced into
invisibility**. The record now carries `effort` and `effort_ratio`, parsed from its own `scope=repo`
line, and `effort` is part of the debounce key.

### Proof

`tests/backlog-telemetry.bats` 23/23 (F1-F7 new), `tests/drain-conversion-churn.bats` 19/19 (E6/E7
new). Six mutants RED-proved by anchored edits: the unresolved `$0` (F7), the `null` guard (F4), the floor's side (F5), the
zero-closes branch (F3), the ceiling's inclusivity (F2), and the `--assert` increment (F2's rc).

⚠️ **F5 initially survived its own mutant and the fixture was the reason.** It used 5 commits against
10 closes with a floor of 20 — *both* terms under the floor — so moving the floor from the numerator
to the denominator abstained either way and the case passed against the very defect its name claims
to pin. Only a fixture that STRADDLES the floor discriminates (now 5 commits / 25 closes: under the
denominator reading it renders 0.2x and `effort-productive`, and reds). A control whose two arms
agree asserts nothing, and a control named after the property is not a control that tests it.

🚨 **The land gate caught a live-layer blindness that every test I had written was structurally
unable to see, and it is the §1.6 generator wearing a new face.** The arm derived its repo with
`dirname "${BASH_SOURCE[0]}"/..`, and `scripts/self-path-lint.sh` refused the land (rc 6). It was
right: `~/.claude/scripts/` is a tree of PER-FILE symlinks into the checkout, and
`resolve_drain_telemetry` in `rotate-autonomy-logs.sh` **prefers that live path** — so the hourly
caller, the only invocation that actually runs, would have resolved its root to `~/.claude`, which
carries no `.git`, and rendered `effort-unmeasured` **forever**. Correct from every worktree, blind
in production, and invisible to a direct-path test: an instrument built to stop a silent regression
would itself have regressed silently on day one. `$0` is now resolved through its symlinks before
any `..` is taken (the canonical BSD-safe loop; no `readlink -f`), and **F7 pins the LAYOUT rather
than the call** — a fixture checkout that is a real repo plus a separate live tree holding only a
symlink, invoked with `CC_BLTM_REPO` unset. RED-proved by restoring the exact pre-fix line.

Also fixed: `tests/drain-conversion-churn.bats` now pins `CC_BLTM_REPO`. The arm's repo defaults to
the checkout the subject lives in — the operator's real git history — so an unpinned default would
have let that suite's verdicts, and the rotation host's journalling decisions, follow whatever
happened to be committed that day.

### Scope (grown): +unblock a pre-existing trunk red that was gating this land

The land's smoke phase went red on `tests/rotate-autonomy-logs.bats` case 12, and the gate named it
*"1 mapped to YOUR diff … a VERDICT about your diff"*. It was not. Verified by running that one case
in a **detached worktree at `origin/main` carrying none of this wave's changes** — it fails there
too. The land gate maps a suite to a diff by **file touch**, so a red that trunk already carried is
attributed to whoever edits `scripts/rotate-autonomy-logs.sh` next rather than to whoever caused it.

The cause is the recurrence that case's own comment already documents twice: `DEFAULT_TARGETS` ships
**22** paths and the test's independent `DEFAULT_RELPATHS` fixture pinned **19** — the three
`account-assignments.jsonl`, `account-utilization.jsonl` and `auth-timeseries.jsonl` landed without
it, so they counted as SKIPPED and broke both `"rotated":19` and `"skipped":0`. Resolved the way the
comment's own precedent says (the SHIPPING side wins), and the case now documents the third
occurrence. **The list is deliberately still hardcoded rather than derived from the script**, which
would end the recurrence permanently: it is the INDEPENDENT oracle, and deriving the expectation
from the subject would leave it unable to notice the subject DROPPING a target — a gate keyed on its
own signal, which cannot fail in the direction that matters. 14/14.

### What is NOT claimed

The ratio moved before this wave and not because of it; this arm measures, it does not drain. And
`lane=local-drain` still renders `lane-stalled` because close attribution sits at **7.7% coverage**
(2,355 of 2,553 closes carry no `lane`) — the effort arm is scoped fleet-wide precisely so it does
not inherit that gap, but the gap itself is untouched and is not this wave's.

---

## 3j. A CUT COULD NOT SAY WHAT CUT IT — and the one thing it did say was refuted (W9, 2026-09-04)

**§3e ended by flagging this and declining to act on it**, in its own words:

> **Corollary, flagged not fixed.** `postland-verify.sh:34-35` defines CUT as a machine event and
> `:2837` names its discriminator as *"a peer pkill shows rc>128 / a job-control line"* — exactly what
> `timeout -k`'s own escalation produces… So CUT cannot distinguish an external pkill from our own
> bound firing. That matters because CUT is what holds `last-green` behind live HEAD and blocks
> `deploy-live` per §W5. Stated as a RISK… establishing an actual misfire needs the per-run rc.

That is not a bookkeeping gap. **A cut stamp is the thing that keeps `last-green` behind live HEAD**,
and `deploy-live` is fail-closed on it — so it is the mechanism by which W3, W5, W5b, W7 and W4 each
landed a correct fix and then recorded, in five separate sections, that the fix was **not live**.
The one question an operator asks a cut — *is this our own ceiling, or is something killing us?* —
had no answer on disk at all.

### The refuted claim was in SHIPPED CODE, in three places, and it prescribed a remedy

`rc_why`'s rc>128 arm read:

```
the run was KILLED by signal N from OUTSIDE this runner (sender unidentified) - not the tree
```

and the block above it closed: *"What IS established: the signal came from outside this runner's
tree (both stall sites set `cutby` and force rc 124, and no `STALL:` line precedes any of the 14),
and the parent survived every one — which excludes anything signalling the process group."*
**Both legs are non-sequiturs**, and `docs/research/sigkill-attribution-2026-09-03.md` — W6's own
intervention, 5/5 on demand — settles each:

| the claim | why it does not hold |
|---|---|
| no `STALL:` line ⇒ not us | It excludes the **stall watcher**. It says nothing about the OTHER bound this runner arms, `timeout -k 10 "$SUITE_TO"`, which fires when the corpus **progresses** steadily past the wall. On that path `cutby` is never set and rc is never forced to 124. |
| the parent survived ⇒ not a group signal | That is what the mechanism **predicts**. Without `--foreground`, `timeout` puts *itself and its child* in a NEW process group and escalates with `kill(0, SIGKILL)` — a scope that by construction cannot reach this script. `SIGKILL` is uncatchable, so coreutils' anti-self-signal guard is a no-op, `timeout` dies before `status = EXIT_TIMEDOUT`, and the shell reports its direct child as `Killed: 9` ⇒ 137. |

The research doc names the inheritance outright — *"every downstream conclusion built on '137 + a
job-control line ⇒ an external sender' inherits that error"* — and these were three of them
(`rc_why`, the hung page's `NOT a cut:` line, the HUNG backlog title). A guessed sender is not a
harmless flourish: it prescribes *"go find the killer"*, which is a search for a process that need
not exist, on the one path everything else in this plan is waiting behind.

### What landed

**The message stops asserting a sender**, and names the discriminator instead:

```
the run was KILLED by signal 9 - sender NOT established: this runner arms `timeout -k` without
--foreground, whose own escalation signals its whole process group and surfaces identically to a
peer pkill or the OOM killer (compare the stamp corpus_s against bound_s) - not the tree
```

**And the stamp carries the axes rather than filing them.** `rc` · `corpus_s` · `bound_s`, on every
verdict:

* **`rc`** — WHICH non-verdict. Recorded as the code `classify_failures` was **handed**, after the
  `cutby` normalisation, so the stamp and the `CUT_WHY` beneath it are one fact stated twice. What
  the normalisation hides — that the watcher, not the ceiling, ended the run — is already in
  runner.log as its own `STALL:` line, which is the actuator's own record and outranks a
  re-derivation (memory: `make-the-actuator-the-arbiter`).
* **`corpus_s`** — WHOSE, the numerator. Deliberately **not `run_s`**, which also counts worktree
  prepare, syntax and the prelints: comparing that to a corpus bound compares two populations, which
  is this repo's own `bound-must-fit-the-band-not-the-bench` in the measurement rather than the bound.
* **`bound_s`** — WHOSE, the denominator, and only when one was actually **armed**. With no
  resolvable `timeout(1)`, `bounded` runs the corpus bare and nothing can cut it, so recording
  `SUITE_TO` there would describe a ceiling that cannot fire.

**All three render JSON `null`, never 0**, wherever the corpus did not run — the prelint-red path
skips it outright, and `0` would say *"it ran, instantly, well inside its ceiling"*, the single most
misleading value each field could take and precisely the reading they exist to end (memory:
`fail-safe-default-mimics-the-healthy-state`). That is the same call the sibling arm in
`autonomy-sweep.sh` makes for `elapsed_s`/`load1` on the `cloud-return` IDL row, one layer up — and,
per that arm's own record, the exact half `d1209750610a` reverted whole there before `6438e39c` (a
sibling cloud branch, unlanded as this is written) restored it. **Named by subject, not by section
number, deliberately:** this file's numbering is contested on trunk at the moment of writing — the
revert took a `3g → 3h` renumber with it, so two `## 3g` headings stand — and a cross-reference that
resolves only under one resolution of that is a pointer with a half-life.

Additive by construction: `scripts/offbox-green-pull.sh:23` records that **no consumer of `stamps/`
reads any field but `.verdict`**, so nothing that exists today can be broken by a new key.

### Proof

`tests/postland-verify.bats` gains contract clause **C4c** and five cases, and **every one has a
control that can fail in the opposite direction** — the property the C13h pair one screen up already
demands of this file:

| case | pins | the control that makes it mean something |
|---|---|---|
| C4c cut-axes | `rc` 137 · `corpus_s` a number · `bound_s` = the seam's own `4242` | pinning the SEAM's value, not "is a number", is what stops a hardcoded default passing |
| C4c never-ran | all three `null` on a prelint red | the arm that refutes a `0` default, which would satisfy every "is a number" assertion while lying |
| C4c no-bound | `bound_s` `null` under `CC_POSTLAND_TIMEOUT_BIN=`, **while `rc`/`corpus_s` stay numbers** | proves `bound_s` is read from what was armed, not printed from a constant — and that the null is scoped, not blanket |
| C33c sender | runner.log says `sender NOT established`, keeps `KILLED by signal 9`, and does **not** say `from OUTSIDE this runner` | asserted with `run` + an explicit status test, never a bare `!` — bash exempts a negated command from errexit, so `! grep -q` is a DEAD assertion |
| C33c rc 124 | `our own bound cut the run` is **unchanged**, and does not gain the hedge | the direction a blanket "we cannot know the sender" edit would break: 124 IS established, and trading a false certainty for a false doubt is not an improvement |

Five mutants, each RED on the assertion that owns it and on no other: the `null` default rendered as
`0` → never-ran · the armed-guard deleted → no-bound · the bound printed as a constant → cut-axes ·
the original `from OUTSIDE this runner` string restored → C33c sender · the 124 arm given the hedge →
C33c control.

⚠️ **TWO OF THOSE FIVE SURVIVED THEIR FIRST RUN, AND THE FIXTURE WAS NOT THE REASON — THE MUTANT WAS.**
The two bound mutants were applied with `perl -0pi -e 's/\Q…$SUITE_TO…\E/…/'`, and **`\Q` suppresses
metacharacters, not interpolation**: perl expanded `$SUITE_TO` and `$TIMEOUT_BIN` to empty, the
pattern matched nothing, and both "mutants" were the unmutated file passing its own tests. Re-run
with the sigils escaped, both redden on their own assertion. Recorded because it is the same shape as
§3i's F5 seen from the other side — there a control's two arms agreed, here a mutant never mutated —
and both produce the identical artefact: **a green that asserts nothing, indistinguishable from a
green that asserts everything.** The cheap guard is to make the mutation prove it landed (this run
prints the mutated line) rather than to trust that a substitution fired.

### Suite, stated with its host

`bash -n` clean; `shellcheck -S warning` 0 findings on `scripts/postland-verify.sh`, matching
`origin/main`'s baseline of 0. All five prelints this file gates itself on — walltime, hermeticity,
git-identity, subshell-cleanup, afunix-path — clean. `unattended-path-lint` output identical to
trunk's modulo line numbers, so this diff adds no finding.

`tests/postland-verify.bats` on the cloud worker's Linux VM: **130 ok · 2 skip · 7 not ok**, and
**all 7 reproduce byte-identically on `origin/main` with this diff stashed** — the `run.lock.d`
identity cluster (C6, C6b ×3, C33 ×2, and the plain live/dead-holder pair), which reads `ps -o
lstart` and is host-coupled; the 8th test in that same filter passes in both trees, so the
attribution is not "everything reds here". Not this diff's, and named rather than swallowed. It also
corroborates the entry this suite already carries in `scripts/offbox-excluded.manifest` — excluded
on COST, and this run says the exclusion is now load-bearing for CORRECTNESS on Linux too, which is a
finding that belongs to whoever owns that manifest and not to this wave.

One further environment fact worth recording, because it wasted a cycle: an eighth failure
(`C22b: the CUT says the LINT is broken`) was purely *"this VM has no git identity"* — `push_commit`
died 128 inside the fixture. It goes green with `GIT_AUTHOR_*`/`GIT_COMMITTER_*` exported, and it too
reproduces on stashed trunk. A suite whose fixtures commit needs an identity the off-box runner
supplies and a bare container does not.

### What is NOT claimed

**No stratified verdict about any real cut, and none is reachable from here.** These fields are
written by the DEPLOYED runner, which advances only through `deploy-live`'s GREEN stamp — the same
convergence dependency §W5, §W5b, §3f and §3g each recorded, and the very circle this instrument
exists to make legible. The first usable reading is one converge cycle away. Nor does this wave
claim the 14 kills §C33b measured were our own ceiling: it claims only that **nothing established
they were not**, and that the run after next will be able to say which on evidence rather than on a
sentence.

**And it does not touch the bound.** §3e's own closing line still governs — *"this licenses no bound
change; the bound is not the defect, the reading of 137 was."*
