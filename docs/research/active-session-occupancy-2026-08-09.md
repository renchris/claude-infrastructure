# Active-session occupancy — Phase B, measured

**Date:** 2026-08-09
**Wave:** S6.4 Phase B ("cut active-session occupancy"), `docs/plans/CONCURRENCY_PROGRAM.md`
**Instruments (this wave):** `scripts/hook-dispatch-bench.sh` (+ `tests/hook-dispatch-bench.bats`)
**Landed change:** the `--machine` memo in `scripts/wrap-ledger.sh` (+ `tests/wrap-ledger-cache.bats`)
**Inherits:** `docs/research/idle-session-occupancy-2026-08-09.md` (Wave A — residency is free)
**Closes as measured:** `docs/plans/HOOK_CHAIN_COST.md` §8's standing caveat, open since it was written

---

## 1. Verdict

Phase B named two levers. **Both premises turned out to be unmeasured, and they resolve in opposite
directions.**

| Lever | §S6.4's framing | What the measurement says |
|---|---|---|
| **Serialise the hooks** | "the count is not the variable" — implies a large win | **Premise confirmed, prize NOT first-order.** Hooks *are* dispatched concurrently (§2, newly measured). But the load integral is invariant under serialisation (§3): the entire win is a second-order queueing term that exists only in the contended regime. The lever is real and it is *conditional*, which is not how the plan reads. |
| **Shorten what holds a slot** | "cache branch/status per turn"; `git rev-parse` 17.95 ms vs 2.20 ms, an "8.2× saving" | **Right direction, wrong target and an unreproducible ratio.** The scattered `rev-parse` calls are the minority of the cost. One amplifier — `wrap-ledger.sh`, called by six Stop hooks — is ~80% of a Stop's git subprocesses (§4). Memoising it at the chokepoint: **60 → 27 git subprocesses per Stop, 2.22×, landed** (§5). The 17.95/2.20 pair does not reproduce (§6). |

**The single most useful sentence for the next wave:** the plan's own cost model pointed at the wrong
files, because nobody had counted the calls — and the count was reachable in an afternoon.

## 2. Claude Code dispatches a matcher group's hooks CONCURRENTLY

`HOOK_CHAIN_COST.md:396-399` states the gap plainly, and it had never been closed:

> **§2.3's chain measurement invoked each hook directly**, not through Claude Code. It therefore
> measures per-hook cost faithfully but says nothing about whether Claude Code runs a chain serially
> or in parallel […] **Unresolved, and named as unresolved.**

Every per-hook timing in this repo — the whole `HOOK_CHAIN_COST.md` table, `hook-chain.sh`'s header
block, the collapse A/B — was taken by invoking hooks *outside the harness*. None of them observes
the harness's own scheduling.

**Measured directly instead.** A passive sampler read `ps -axo pid=,ppid=,command=` at **21.9 Hz for
75 s**, bucketing rows by **command position** (never argv substring — this fleet's indexed
`pgrep-f-matches-agent-briefs` failure is what scoped Wave A's entire premise wrongly). 270 hook
processes were captured. Grouping by shared first-sighting, and attributing by parent pid:

```
dispatch t0=9.099   13 procs   8 DISTINCT hooks under ONE parent (pid 43530)
   anti-deference-nudge · boundary-handoff · completion-assert · dispatch-assert
   notify · operator-readout · session-beat · session-continue          ← a Stop event

dispatch t0=52.162  12 procs   9 DISTINCT hooks under ONE parent (pid 34838)   ← Stop
dispatch t0=64.099  14 procs   8 DISTINCT hooks under ONE parent (pid 34838)   ← Stop
dispatch t0=4.884   13 procs   9 DISTINCT hooks under ONE parent (pid 16897)   ← SessionStart
```

The Stop group registers **10 commands**; 8–9 of them are in flight *within a single 45 ms sample*,
under a single session's parent, three separate times. Serial dispatch would put every group at
size 1. **109 of 147 sightings were singletons and 38 were multi-member** — the singletons are the
short hooks the sampler caught alone, which is the expected shape and not evidence against.

This corroborates, from an independent direction, the static read already in the repo —
`docs/research/goal-in-handoff-2026-08-08.md:439`, the dispatcher `uL` @237793 mapping every
resolved hook to a concurrent async generator. **A code read and a live process sample now agree**,
which is worth more than either: the bundle read is version-specific and could rot silently, and the
process sample cannot see intent.

### 2.1 The asymmetry this method has, stated because it bounds the claim

Sampled intervals are **conservative**: `first_seen ≥ true start`, `last_seen ≤ true end`. So an
overlap the sampler finds is *real* — a lower bound on concurrency. An *absence* of overlap would be
weak evidence, because a hook shorter than the 46 ms sample period can be missed entirely. This
result is the strong direction; a null would not have been.

## 3. Why serialising is a second-order effect — and why the plan's framing oversells it

⚠ **The first-order term cancels.** `load` is the time-average of the runnable-thread count, so an
event's contribution is `∫(runnable) dt` = the **sum** over member processes of the time each spends
runnable. Ten members at once for `d` ms contributes `10d` thread-ms. Ten members in sequence for
`10d` ms contributes `10d` thread-ms. **Identical.** Serialisation cannot win here, and a bench that
reported a win on this term would be measuring its own error.

The whole prize is a **queueing** term: a process waiting in the run queue is in state **R**. It
accrues runnable-time while doing no work. Once the box is oversubscribed, every member's R-time
inflates by roughly the oversubscription factor, and the sum inflates with it. Serialising cuts the
instantaneous oversubscription, which deflates every member's R-time.

That is exactly what §S6.1's cross-over already implied, read carefully rather than quoted:

```
2,376 forks/s at concurrency 4   → +1.6  load
1,255 forks/s at concurrency 16  → +17.5 load
rate DOWN 1.9x, load UP 11x   ⇒  cost-per-fork rose ~21x between concurrency 4 and 16
```

**That 21× is the inflation term, and it is the entire lever.** It also says the lever is
*conditional*: it pays in proportion to how contended the box already is, and at the design point
(10 active sessions × ~10 concurrent hooks per Stop = ~100 simultaneous processes on 10 cores) the
contention is severe, which is precisely where it pays most.

`hooks/hook-chain.sh:41-46` reached this conclusion from the other side and stopped:

> the collapse's benefit is proportional to cost-per-fork, which is O(load), so it only pays in the
> high-load regime it exists to prevent — and therefore cannot be validated by measurement at normal
> load.

**It was right about wall-clock and wrong to stop there.** The error is treating "the box's load is
an uncontrolled nuisance" as fixed. Sweep the concurrency deliberately instead of accepting whatever
the box was doing, subtract a per-cycle ambient, and divide by completed work, and the term is
directly observable. `scripts/hook-dispatch-bench.sh` is that instrument.

**The consequence for `hook-chain.sh` is a re-opening, not a reversal.** Its shelving verdict
("REAL 6-guard chain, serial 174 ms · dispatcher exec ~180 ms") is a *wall-clock* result and remains
true. Wall-clock is the quantity that does *not* move under serialisation — the dispatcher trades
concurrency for duration at roughly constant product, which is what "no wall-clock change" means.
So that measurement is not evidence against the collapse on the occupancy axis; **it is silent on
it.** Re-adjudicating it needs the bench, not a re-run of the same A/B.

## 4. Where the git cost actually lives — one amplifier, not scattered calls

§S6.4 says "cache branch/status per turn instead of re-shelling per hook", which implies the cost is
spread across hooks. **It is not.** A census of every hook registered in `~/.claude/settings.json`,
by event, with file:line for each invocation:

| Event | git subprocesses on the hot path | Notes |
|---|---|---|
| PreToolUse/Bash (7 hooks) | **0** | every `git …` string in `validate-bash.sh` is inside a *deny message*, not an invocation; `git-worktree-guard.sh:49` is behind a `git worktree remove`/`git branch -d` matcher |
| PreToolUse/Write\|Edit (3) | **0** | — |
| PostToolUse/Bash (6) | **~0.2–1.8 amortised** | `teammate-checkpoint.sh:140` exits early on 4 of every 5 calls (`EVERY=5`); `waiting-recycle.sh`'s three calls need an armed sentinel and its own header records *1503 evaluations, 0 fires ever* |
| UserPromptSubmit (6) | **1** | `memory-nudge.sh:68` alone |
| SessionStart (14) | **~2** | `dod-persist.sh:37`, `activation-watch.sh:357` |
| **Stop (11 hooks)** | **~72–82 on a working close** | ← the entire problem |

**`scripts/wrap-ledger.sh` is the amplifier.** One `--machine` run is **10 git subprocesses** (17
when the live-layer arm runs), and **six Stop hooks each call it on the same event**:

```
session-continue.sh:529 · completion-assert.sh:189 and :191 · anti-deference-nudge.sh:249
boundary-handoff.sh:272 · operator-readout.sh:426 and :991
```

Repeated identical queries in ONE Stop, counted:

| query | repeats |
|---|---|
| `git status --porcelain` (cwd) | **6–9** |
| `git rev-parse HEAD` (cwd) | **6–8** |
| `git rev-parse --show-toplevel` | **8–9** |
| `git cherry "$TRUNK" HEAD` — a full patch-id walk | **6** |
| `git rev-list --count "$TRUNK"..HEAD` | **6** |
| the 7-call live-layer block against a *different* repo | **6** |

**Roughly six of every seven git subprocesses in a Stop event are literally the same query as
another one in the same event.**

One further asymmetry worth naming: `session-continue.sh:529` pays the full 10-call ledger *before*
the rung test at `:532` (`[ "$rung" = "🔧" ] || return 1`) — so the most expensive read on the event
is taken on every Stop including the ones where its answer cannot change the outcome.

## 5. The landed fix, and why it went at the chokepoint

Memoising at each call site would be **six edits to six safety-adjacent hooks**. The memo went into
`wrap-ledger.sh` itself — the one chokepoint all six already funnel through (MEMORY.md
`enforcement-must-live-at-the-chokepoint`).

**Measured on this repo, one Stop = 6 consumers, dispatched the way §2 says they actually are —
CONCURRENTLY:**

```
WRAP_CACHE=off (today)                     60 git subprocesses
memo, COLD  (all six arrive together)      27          ⇒ 2.22×
memo, WARM  (unchanged tree, within TTL)   18          ⇒ 3.33×
```

### 5.2 The sequential figure was real, and it measured the wrong arrival pattern

The first version of this memo had no single-flight, and it was measured by calling `--machine` six
times **in sequence**: 60 → 27, a clean 2.22×. That number was arithmetically correct and
operationally meaningless, because §2 of this very document had already established that the six
consumers do **not** arrive in sequence — they are dispatched inside one 45 ms window.

Re-measured in the shape production actually uses:

```
WRAP_CACHE=off                             60 git subprocesses
memo, six CONCURRENT, cold                 72          ⇒ 20% WORSE
```

All six miss together, all six compute, and the six fingerprints become pure added cost. **The memo
was a regression on its own hot path** — the first Stop after any tree change, which is the common
case — and the sequential bench could not see it.

Fixed with bounded **single-flight**: the first caller takes a `mkdir` lock and computes; the others
take one short sleep and re-read the atomically-`mv`'d result. Deliberately **one sleep, not a poll
loop** — `sleep` is a fork on this box, so a 40 ms poll over a 2 s bound would fork ~50 times per
loser and cost more than the git calls it saves. Fail-open at every step: cannot lock ⇒ compute;
waited and still nothing ⇒ compute; stale lock from a crashed winner ⇒ clear it and compute, never
wait behind a corpse. Pinned by `F1` (concurrent cold must be strictly cheaper than uncached), `F3`
(a backdated lock must not be waited behind) and the `F4` mutation (removing the lock must make the
concurrent path regress — if it did not, `F1` proves nothing).

**The generalisable lesson, and it is the sharper of this wave's two:** a cache benchmarked in an
arrival pattern its callers do not use will report the saving it was hoping for. The correction was
available in §2 of the same document — the concurrency finding and the cache were measured hours
apart and it took a deliberate re-check to connect them. *A cache may never make the uncached path
worse than uncached*, and that is a property of the **arrival pattern**, not of the hit rate.

**Keyed by content, not by time.** The key is HEAD + the full porcelain digest + the mtimes of the
non-git stores the rungs read (decisions ⇒ ⛔, backlog ⇒ 👤, failed migrations ⇒ 🚀). A pure TTL
would let a tree go dirty inside the window and still serve a ✅ — the false-done this ledger exists
to make impossible. `git status --porcelain` is therefore paid on every call and deliberately **not**
replaced by a stat-bit shortcut: `wrap-ledger.sh:157-169` already records that experiment and its
false-clean result.

**The residual staleness, stated rather than hidden:** a sibling's fetch can move the trunk ref
without moving any keyed input, so a hit inside the TTL can serve an `AHEAD` count up to TTL seconds
old. That errs toward **📦 still-parked** and never toward ✅ — the direction that matters, since the
hazard the ledger names is FM1 park-and-call-it-done, not its reverse.

`WRAP_CACHE=off` calls straight through. It is a *cache, not a guard*, so disabling it costs forks
and changes no verdict — the opposite of `hook-chain.sh`'s no-skip law, and the reason a kill switch
is safe here where it would be a defect there.

### 5.1 The TTL shipped INERT, and its own test is what caught it

The first draft bounded freshness with `find "$CACHE_FILE" -mmin +"$(TTL/60)"`. **BSD `find` takes
`-mmin` in whole minutes and truncates**, so every TTL under 60 s evaluated as `+0`, which matches
nothing for a file written this minute — and therefore reported **every** entry as fresh. The bound
did not exist. Nothing about the output looked wrong; the cache worked, the parity tests passed, and
the documented second bound was prose. `C3` (a 0 s TTL must never serve a hit) failed and is what
surfaced it. Replaced with an explicit `stat`/`date` age in seconds.

This is the repo's own indexed `spec-named-mechanism-may-be-prose-only` class, committed inside a
wave whose whole subject is that a plan's mechanisms had never been checked against the tree.

## 6. Correcting the plan's own cost figures

§S6.4 quotes "a hook's `git rev-parse` costs **17.95 ms** against **2.20 ms** for bare `bash -c :` —
an **8.2× occupancy saving**". **That pair does not reproduce, and the ratio mixes two different
measurement conventions** — the same wrapper-billing artifact `hook-chain.sh:12-16` and
`HOOK_CHAIN_COST.md:74-81` already flag against their own numbers.

Re-measured today, load ~8 on 10 cores, **marginal** cost (40 invocations inside one already-running
shell, so the wrapper's own fork is amortised rather than billed per call), median of 5 runs:

| probe | marginal | absolute (wrapper-billed) |
|---|---|---|
| `:` (shell builtin, no fork) | **0.28 ms** | 10.70 ms |
| `/bin/echo` (bare fork+exec) | **2.67 ms** | — |
| `git rev-parse --show-toplevel` | **7.08 ms** | 14.94 ms |
| `git rev-parse --abbrev-ref HEAD` | **7.03 ms** | 14.41 ms |
| `git status --porcelain` | **15.19 ms** | 21.10 ms |

So the honest statement of the lever is: **replacing a `git rev-parse` with a cached read saves
~6.8 ms marginal (7.08 → 0.28), and `git status --porcelain` saves ~14.9 ms.** The *direction* of
§S6.4's claim is right and the magnitude is defensible; the specific figures are not quotable and
should be re-derived, not repeated. Every figure here is load-conditional and carries its load.

## 7. Falsifiable predictions

Each is cheap and re-runnable with the landed instruments:

1. Sampling `ps` at ≥20 Hz during any Stop event shows ≥6 distinct hooks sharing one parent in one
   sample. A maximum group size of 1 would refute §2 and retire the serialisation lever entirely.
2. `scripts/hook-dispatch-bench.sh --control` on a box whose ambient is stable within 2× reports a
   median ratio in 0.80–1.25. A control that cannot hit its own null invalidates every live run
   taken under the same ambient — including any quoted here.
3. `hook-dispatch-bench.sh` at `--members 1` must report ~1.00 whatever the box is doing: with one
   member, parallel and serial dispatch are the same operation. A ratio materially off 1.00 there
   indicts the rig, not the subject.
4. A `git` counting shim on PATH during one real Stop reports **≤30** git subprocesses with the memo
   live and **≥60** with `WRAP_CACHE=off`. A figure near 60 in both refutes §5.
5. The bench's ratio should *rise* with `--sessions` and fall toward 1.00 as the box empties, because
   the effect is a queueing term. A ratio flat in concurrency would refute §3's mechanism while
   leaving its arithmetic intact — and would be the most interesting negative result available here.

## 8. Consequences for the rest of S6

- **The `hook-chain.sh` shelving is re-opened, not reversed** (§3). Its wall-clock verdict stands and
  is silent on occupancy. It is already written, heavily tested, and inert; re-adjudication needs the
  bench, and wiring it would be a `c10` migration (it edits `settings.json`), never a direct
  registration.
- **Phase D's gate terms inherit a second correction.** Wave A established the residency term is
  ~0.003. This wave adds that the *active* term is dominated by a small number of amplifying call
  sites, not by hook count — so a gate that admits on hook count or session count is measuring
  neither of the two things that matter.
- **The Stop event is the expensive one, by an order of magnitude** (§4). PreToolUse/Bash — the event
  every prior cost model in this repo optimised, and the one `hook-chain.sh` was built for — forks
  **zero** git subprocesses on its hot path. That is worth stating plainly: the collapse dispatcher
  was aimed at the cheap event.
- **`session-continue.sh:529` pays its ledger before the rung test that can discard it** (§4). A
  one-line reordering is worth one full `wrap-ledger` run per Stop on the non-🔧 path, and it is
  independent of the memo. Not taken here — it is a behaviour change inside the continuation
  actuator, and this wave's diff is already under the close protocol.

## 9. Method note

Four instrument defects were caught during this wave, each of which had already produced plausible
output — the same pattern Wave A §9 recorded, and the reason that section is now a standing habit:

- **The null control could not fail.** Its first version labelled both arms `serial`, so the verdict
  keyed both on the same name, awk overwrote one with the other, and it reported exactly `1.00x` by
  construction. A control that cannot report a difference is not a control; it is a decoration that
  certifies whatever it is pointed at.
- **The TTL bound was inert** (§5.1) — `find -mmin` truncation, caught only because a test asserted
  against it rather than reading the code.
- **A benchmark in the wrong arrival pattern** (§5.2) — six sequential calls reported a 2.22× saving
  for a change that was 20% *worse* in the concurrent shape its callers actually use. The refuting
  fact was already written down in §2 of this same document.
- **An apostrophe inside a single-quoted `awk` program** silently terminated the program mid-verdict.
  It failed loudly here, but the same class in a `sed` mutation expression made a mutation check
  *error out* rather than fail — and an erroring mutation check reads, at a glance, exactly like a
  failing subject.

Wave A's house rule holds without amendment: *an instrument that returns a clean figure is not
thereby a working instrument.* This wave adds a corollary aimed at the control itself — **a control
that agrees with you is the one most worth mutating**, because a control is the only thing in the
rig with nothing else checking it.
