# Active-session occupancy — Phase B, measured

**Date:** 2026-08-09
**Wave:** S6.4 Phase B ("cut active-session occupancy"), `docs/plans/CONCURRENCY_PROGRAM.md`
**Instruments (this wave):** `scripts/hook-dispatch-bench.sh` (+ `tests/hook-dispatch-bench.bats`)
**Landed change:** none to the runtime — the one attempted (a `wrap-ledger --machine` memo) was
measured, found to break the ledger, and **withdrawn** (§5)
**Inherits:** `docs/research/idle-session-occupancy-2026-08-09.md` (Wave A — residency is free)
**Closes as measured:** `docs/plans/HOOK_CHAIN_COST.md` §8's standing caveat, open since it was written

---

## 1. Verdict

Phase B named two levers. **Both premises turned out to be unmeasured, and they resolve in opposite
directions.**

| Lever | §S6.4's framing | What the measurement says |
|---|---|---|
| **Serialise the hooks** | "the count is not the variable" — implies a large win | **Premise confirmed, prize NOT first-order.** Hooks *are* dispatched concurrently (§2, newly measured). But the load integral is invariant under serialisation (§3): the entire win is a second-order queueing term that exists only in the contended regime. The lever is real and it is *conditional*, which is not how the plan reads. |
| **Shorten what holds a slot** | "cache branch/status per turn"; `git rev-parse` 17.95 ms vs 2.20 ms, an "8.2× saving" | **Right direction, wrong target and an unreproducible ratio.** The scattered `rev-parse` calls are the minority of the cost. One amplifier — `wrap-ledger.sh`, called by six Stop hooks — is ~80% of a Stop's git subprocesses (§4). Memoising it at the chokepoint measured **60 → 27 git subprocesses per Stop** and was then **WITHDRAWN**: it makes the ⛔ rung go stale, because no cheap fingerprint covers the ledger's non-git inputs (§5). The 17.95/2.20 pair does not reproduce (§6). |

**The single most useful sentence for the next wave:** the plan's own cost model pointed at the wrong
files, because nobody had counted the calls — and the count was reachable in an afternoon.

**What is landed is the evidence and the instruments, not a speedup.** That is the honest summary of
this wave: the serialisation lever is now measured rather than assumed, the git cost is now located
rather than guessed, and the obvious fix for the latter was built, measured, and rejected on its own
evidence.

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

### 3.1 Measured: parallel dispatch costs ~3.5× the occupancy of serial, for identical work

`scripts/hook-dispatch-bench.sh`, 3 simulated sessions × 8 members, 4 s windows, 5 interleaved
cycles, ambient subtracted per cycle, divided by completed dispatches:

```
                     R-seconds per dispatch     per-cycle ratios
serial                       0.09689
parallel                     0.31308            2.10  2.66  3.46  3.70  6.43
                                                MEDIAN 3.46x   (spread 2.10..6.43)
```

Identical work per dispatch in both arms — 8 members, same bodies. The serial arm completed ~132
dispatches per window against the parallel arm's ~430, and dividing by that is what makes the
comparison legitimate.

⚠️ **This number is DIRECTIONAL, not certified, and the rig says so itself.** The null control run
immediately before it, under the same ambient, reported a **median of exactly 1.00× — correct — with
a spread of 0.29..1.51**. So the rig is *unbiased and underpowered*: its noise floor is ±50%, which
is wider than most effects worth finding. By the acceptance rule written into the bench, that is a
FAILED control and the live median is not quotable bare.

What can be said honestly is the comparison of the two ranges: **the live effect's floor (2.10)
sits above the control's ceiling (1.51)**, and all five live cycles exceeded every control cycle but
one. That is real evidence for the *direction and rough scale* of §3's queueing term, and it is not
a measurement of its magnitude. The box was never quiet during this wave — a sibling worktree held a
94%-CPU python job throughout, and the bench refused outright (exit 4, load floor) on three earlier
attempts.

**To certify it:** re-run both arms on a box whose ambient is stable within 2×, per §7's prediction 2.
The instrument is landed and the run is a single command.

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

## 5. The obvious fix, built and then WITHDRAWN on its own evidence

The memo was written, tested (18 tests, 4 mutation controls), measured, committed — and then removed
before landing, because the consumer suite refuted it. The sequence is recorded in full because each
step produced a plausible number that the next step destroyed, and the next reader deserves the
reasons rather than the conclusion.

### 5.1 What was built

`wrap-ledger.sh --machine` memoised at the chokepoint all six consumers already funnel through
(MEMORY.md `enforcement-must-live-at-the-chokepoint`), keyed by content — HEAD + the full porcelain
digest + the mtimes of the non-git stores the rungs read — with a TTL as a second bound, atomic
`mktemp`+`mv` writes, and `WRAP_CACHE=off` degrading to today.

### 5.2 It shipped INERT, then it shipped a REGRESSION — two measurements, two corrections

**The TTL did not exist.** The first draft bounded freshness with `find -mmin +"$(TTL/60)"`. BSD
`find` takes `-mmin` in whole minutes and truncates, so every TTL under 60 s evaluated as `+0`, which
matches nothing for a file written this minute, and therefore reported **every** entry as fresh.
Nothing about the output looked wrong. Its own test (`a 0 s TTL must never serve a hit`) is what
surfaced it — the repo's indexed `spec-named-mechanism-may-be-prose-only` class.

**Then it was benchmarked in the wrong arrival pattern.** Six sequential `--machine` calls read
60 → 27 git subprocesses, a clean 2.22×. But §2 of this same document had already established that
the six consumers do **not** arrive in sequence — they land inside one 45 ms window. Re-measured in
production shape:

```
WRAP_CACHE=off                             60 git subprocesses
memo, six CONCURRENT, cold                 72          ⇒ 20% WORSE
memo, six CONCURRENT, cold + single-flight 27          ⇒ 2.22×
memo, six CONCURRENT, warm                 18          ⇒ 3.33×
```

Cold, all six miss together, all six compute, and the six fingerprints are pure added cost. **The
memo was a regression on its own hot path** — the first Stop after any tree change — and the
sequential bench was structurally unable to see it. Fixed with bounded single-flight (a `mkdir` lock
plus **one** sleep for the losers; a 40 ms poll loop would fork ~50 sleeps per loser and cost more
than the git calls it saves).

### 5.3 And then the consumer suite refuted the whole approach

`tests/wrap-ledger.bats` went **3 red** with the memo on and **0 red** with `WRAP_CACHE=off` — the
same 0 as `origin/main`, so the attribution is unambiguous. The three:

```
37  open class-B from THIS session ⇒ NOT ⛔
38  a vetoed/actioned class-C     ⇒ NOT ⛔
40  dirty tree + a blocking decision ⇒ RUNG=⛔
```

All three are **⛔ rung** cases, and the cause is not tunable:

- **A directory's mtime does not move when a file's CONTENT changes.** Test 38 flips a class-C packet
  from open to vetoed *inside an existing file*. The store directory is untouched, so a fingerprint
  built from directory mtimes cannot see it — the memo serves the pre-veto ⛔ over a decision the
  operator has already resolved.
- **`stat` mtime is second-granular**, so even content-addressed changes that *do* touch a directory
  are invisible to a second call in the same second.

The fix that would work is a **content digest of the stores**, and it was priced rather than assumed:
`find + stat + cksum` over the live stores costs **16.46 ms** against 115 decision files today. That
is more than two git calls, paid by every one of the six consumers, and it **grows without bound with
the decision store** — a new unbounded per-Stop cost introduced by a change whose entire purpose is
removing unbounded per-Stop cost.

**So the memo is withdrawn, and the reason is the shape of the problem, not the quality of the
attempt.** The ⛔ rung outranks everything and is derived from an unbounded content-addressed store
that no cheap fingerprint covers. `wrap-ledger.sh` is byte-identical to trunk.

### 5.4 The design that would work, recorded so it is not rebuilt from scratch

**Split the computation, not the cache.** The ledger's fields divide cleanly:

| fields | source | cacheable? |
|---|---|---|
| `DIRTY · AHEAD · CHERRY · UNLANDED · SHAS · TRUNK · LIVE_*` | git | **yes** — HEAD + porcelain is a complete and cheap key |
| `BLOCKED · BLOCKED_SRC` | `cc-decide list --open --class C --json` | no — one bounded fork, always fresh |
| `YOURS · YOURS_SRC` | `cc-backlog list --blocked --json` | no — one bounded fork, always fresh |

Cache the git half; always run the two bounded store forks; re-derive `RUNG` from the union. That
keeps every rung exact while still collapsing ~7 of the 10 git subprocesses, and the two store forks
were already being paid on every call. It was **not** attempted here because re-deriving `RUNG`
outside its existing code path is a change to the close protocol's core, and this wave had already
spent its risk budget on the two corrections above.

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
4. A `git` counting shim on PATH during one real Stop reports **≥60** git subprocesses today. That is
   the standing cost §5.4's split-cache design would cut to ~20; a figure well under 60 would mean
   the census in §4 is wrong about the consumer count.
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
- **A fix that passed its own suite and failed its consumer's** (§5.3). 18 tests and 4 mutation
  controls, all green, over a fingerprint that could not see a file's contents change. The suite
  tested what the cache *does*; only the consumer tested what the ledger must *mean*.
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
