# Wave B — implementation-ready target list: active-session occupancy by event class

**Date:** 2026-08-09 · **Scope:** S6.4 Phase B, the only remaining load lever (S6-UPDATE §3)
**Inherits:** `docs/research/active-session-occupancy-2026-08-09.md` (Wave B measured, nothing landed),
`docs/research/idle-session-occupancy-2026-08-09.md` (Wave A — residency is free)
**Method:** every hook in the LIVE `~/.claude/settings.json` replayed against a fixture payload in a
scratch `$HOME`, timed by subtree rusage, fork-counted by a control-validated `PATH` shim; live-box
occupancy read with an R-state sampler. Nothing was registered, no store was written by intent
(one leak, §9.3). Every number below is either **MEASURED** with its command, or **MODELLED** from
measured parts and labelled.

---

## 1. Verdict

**The plan's Wave B target list is aimed one event too late.** Three findings reorder it:

1. **The largest single hook cost on this box is not on Stop. It is `setup-task-symlinks.sh` on
   SessionStart — ~4 s of CPU and ~800 forks per session start, all of it discarded**, because the
   hook needs ~43 s of CPU to finish and `settings.json` gives it `timeout: 5`. It is killed every
   time, its `additionalContext` never reaches the model, and the next SessionStart redoes the same
   truncated prefix. Cost grows linearly in a global store that only grows (2,155 task-list
   directories, **97% of them empty**, each still costing ~20 ms of CPU and 4 forks). This is
   free to cut: the work is already thrown away.
2. **The Stop lever is real and bigger than the doc's census said** — `wrap-ledger.sh --machine`
   measures **19 git subprocesses / 36 execs / 180 ms CPU per call** in this repo (the doc's figure
   was 10, or 17 with the live-layer arm), and there are **7 call sites**, not 6. A working close is
   therefore ~133 git subprocesses and ~1.26 s of CPU *in wrap-ledger alone*.
3. **The withdrawn memo is recoverable, and the fix is to change what the key is SCOPED to, not to
   make the fingerprint smarter.** The withdrawn design keyed on *content* and so had to *detect
   change* across an unbounded window — which is what a directory mtime cannot do and what a content
   digest cannot do cheaply. Scope the key to the **event** instead (§6) and there is nothing to
   detect: within one Stop the ledger *should* be one snapshot, and across turns the key always
   differs. Cost 2.25 ms, no TTL, no store fingerprint, and the consumer suite passes by
   construction rather than by tuning.

Two answers that **remove** work from Wave B's list:

- **XProtect assessment is NOT re-paid per exec of the same script (§7).** 50 re-execs of an
  already-assessed file cost **+0.00 s** of `XprotectService` CPU. Hooks execute stable files, so
  the hook path pays zero Gatekeeper tax. The 31% figure belongs to Wave C: a **first** exec of a
  newly-created file costs **138.5 ms wall and ~134 ms of XprotectService CPU, synchronously**, and
  `bash <file>` avoids it entirely.
- **`grep` in a hook is `/usr/bin/grep` (BSD, 2.67 ms), not ugrep.** The `ugrep 1.206` runnable
  threads the probe sees are the Bash *tool's* grep — agent payload, not hooks.

---

## 2. Per-event table (MEASURED)

Replay rig: `HOME` = scratch tree, cwd = a scratch git repo, fixture stdin per event.
`CPU` = subtree `user+sys` from `/usr/bin/time -p` over N iterations (captures every fork, unlike
ΔCPU sampling — Wave A's named blind spot). `execs` = `PATH`-shim count, **positive control: a
script doing exactly 5 `git` calls counted exactly 5, and a builtin-only `$( )` subshell counted 0**
(so these are EXEC counts; a fork without an exec is invisible and the true fork count is higher).

| Event | hooks | Σ CPU ms | Σ execs | git | wall if serial | wall if concurrent (max member) | dominant member |
|---|---|---|---|---|---|---|---|
| PreToolUse/`Bash` | 7 | **145** | 38 | **0** | 208 | 74 | `validate-bash.sh` 65 ms / 23 execs (**14 `grep`**) |
| PostToolUse/`Bash` | 6 | **143** | 27 | 1 | 184 | 67 | `waiting-recycle.sh` 58 ms / 11 |
| PreToolUse/`Write\|Edit` | 3 | **74** | 17 | 0 | 189 | 93 | `backup-before-write.sh` 34 ms / 9 |
| PostToolUse/`Write\|Edit` | 7 | **110** | 18 | 1 | 309 | 60 | `teammate-checkpoint.sh` 28 ms / 4 |
| UserPromptSubmit | 6 | **315** | 57 | 1 | 407 | 146 | `handoff-intent-nudge.sh` 130 ms (1 `ps`); `session-beat.sh` 105 ms / 32 (**12 `ps`**) |
| Stop — *abstaining*, trivial repo (rig floor) | 11 | **953** | 181 | 22 | 1,183 | 320 | `operator-readout.sh` 287 ms / 53 |
| Stop — *working close*, this repo (MODELLED, §4) | 11 | **~2,060** | ~370 | **~133** | — | ~500 | 7× `wrap-ledger` = 1,260 ms |
| SessionStart | 14 | **≥4,340** (timeout-capped; ~43,000 uncapped) | **≥900** (~8,600 uncapped) | ~2 | — | ≥5,000 (killed) | `setup-task-symlinks.sh` ≥3,900 ms / ~800 execs |

SessionStart **excluding** `setup-task-symlinks.sh`: 434 ms CPU / 103 execs across 13 hooks.

Per-member detail for the two events that matter (CPU ms / execs):

```
Stop (rig floor):  operator-readout 287/53(11 git) · dispatch-assert 158/21 · session-continue 150/31(9 git)
                   boundary-handoff 120/10 · session-beat 105/30(12 ps) · anti-deference 42/12
                   completion-assert 42/12 · teammate-checkpoint 32/8(2 git) · beacon 12/3
                   cache-expiry-tracker 5/1 · notify 2/0
PreToolUse/Bash:   validate-bash 65/23 · qos-rewrite 24/6 · git-worktree-guard 15/3 · ship-rail 12/2
                   rm-safe-allowlist 11/2 · keychain-guard 11/1 · curl-gate-scope 7/1
```

### Primitive cost table (MEASURED, marginal, live box at load ≈ 4.5/core)

| primitive | wall ms | CPU ms |
|---|---|---|
| `/bin/echo` (bare fork+exec floor) | 2.83 | **2.00** |
| `/usr/bin/grep -q` | 3.50 | 2.67 |
| `bash -c :` | 3.50 | 2.67 |
| `dirname` | 4.50 | 2.17 |
| `stat -f '%m %z'` | 5.50 | 2.25 |
| **`jq` (tiny payload)** | 5.17 | **4.17** |
| `git rev-parse HEAD` | 9.25 | 6.50 |
| `git cherry origin/main HEAD` | 13.33 | 10.67 |
| `shasum -a 1` | 15.00 | 13.50 |
| `git status --porcelain` | 18.00 | 17.50 |
| **`ps -axo pid=,stat=`** | 26.00 | 23.00 |
| `python3 -c pass` | 29.50 | 27.00 |
| **`ps -axo pid=,ppid=,command=`** | 55.50 | **49.50** |
| `cc-decide list --open --class C --json` | 4.00 | 1.00 |
| `cc-backlog list --blocked --json` | 2.00 | 0.00 |

Two consequences. **`ps` with an argv column is the most expensive thing a hook does per call** —
20× a bare fork — and `session-beat.sh` does it 12 times on *both* UserPromptSubmit and Stop.
And **§5.4's "always run the two bounded store forks" costs 1.0 ms, i.e. nothing** — so the
split-cache design's correctness argument buys no measurable saving over caching them (§6).

---

## 3. Event rates and the occupancy decomposition

**Rates, MEASURED from the live fleet** (`~/.claude/autonomy/idl.jsonl` bucketed by `sid`;
`~/.claude/logs/bash-commands.log` for the Bash rate):

| event | fleet rate | per-session band | representative ACTIVE |
|---|---|---|---|
| Bash tool call | 22.2/min over 18 sessions | 0.9 – 11.5/min | **4/min** |
| Stop | 1.37/min over 21 sessions | 0.05 – 0.80/min | **0.5/min** |
| UserPromptSubmit | ≈ Stop | — | 0.5/min |
| Write/Edit | not logged — **MODELLED** at 0.4× Bash | — | 1.5/min |

**Per-active-session hook CPU** (rate × measured per-event CPU):

| event class | s CPU/min | share |
|---|---|---|
| **Stop** | 1.030 | **39.4%** |
| PreToolUse/Bash | 0.580 | 22.2% |
| PostToolUse/Bash | 0.572 | 21.9% |
| Write/Edit pair | 0.276 | 10.6% |
| UserPromptSubmit | 0.158 | 6.0% |
| SessionStart | ~0 amortised — **dominates a ramp** | — |
| **total** | **2.616 s/min = 0.0436 cores** | 100% |

### 3.1 The inflation term is the whole gap, and two independent routes size it at ~35×

0.0436 cores of *work* cannot be 1.6 runnable threads. The difference is the queueing term §3 of the
prior findings doc derived and §S6.1's cross-over measured (cost-per-fork rose ~21× between
concurrency 4 and 16). Sized two ways, today, on a box measured at **MEAN RUNNABLE 45.04 on 10 cores**:

- **Top-down.** If hooks were the whole of the 1.6, inflation = 1.6 / 0.0436 = **37×**.
- **Bottom-up, via `jq`.** Hooks emit a modelled 117.5 `jq`/min per active session (7 on
  PreToolUse/Bash, 11 on PostToolUse/Bash, 14 on the Edit pair, 10 on UserPromptSubmit, 39 on Stop)
  = 1.96/s × 4.17 ms = **0.0082 threads uninflated**. Measured `jq` occupancy box-wide is **2.803
  runnable threads** — the single largest short-lived component, 6.2% of the box — which over ~10
  active sessions is ≤0.28/session. Inflation = **34×** if every `jq` on the box is hook-driven.

The two agree, and the second carries the honest caveat: "every `jq` is hook-driven" is an upper
bound, so **35× is an upper reading and ~20× (§S6.1's own measured cross-over) is the conservative
one**. Every lever below is priced in the same ΔCPU currency, so the *ranking* is invariant to which
figure is right; only the absolute Δ-threads scale. **All Δ-occupancy figures below use ×20.**

### 3.2 What actually holds the runnable slots right now (MEASURED)

`scripts/occupancy-probe.sh` at 1 Hz / 60 s, and a 5.9 Hz / 40 s spawn-rate sampler:

```
MEAN RUNNABLE 45.04 (10 cores)        R_mean    spawn/s
  jq                                   2.803       4.7      ← largest short-lived component
  cc-dispatch (daemon)                 2.744       1.5
  claude (inference, ~15-20 sessions)  2.332       0.25
  ps                                   1.567       6.0
  cc-backlog (daemon)                  1.487       2.2
  find                                 1.466       0.07
  ugrep  (Bash TOOL's grep, not hooks) 1.206       0.15
  git                                  1.643       5.9
  mds + mds_stores (Spotlight)         1.833       —
  bash (all forms)                     ~0.9       ~18
  XprotectService                      0.597       —
```

Two components nobody in S6 owns, both larger than most Wave B levers:

- **Box-wide daemons: 6.25 runnable threads = 13.9%** (`cc-dispatch` 2.744, `cc-backlog` 1.487,
  `autonomy-sweep.sh` 0.718, `assignee-pane-residency.sh` 0.714, `deploy-parity-assert.sh` 0.584).
  These do **not** scale with sessions, so they do not move the per-active-session slope — but they
  eat the same ceiling, and they are bigger than every per-session hook lever combined.
- **Spotlight: 1.833 threads = 4.1%**, indexing the worktree tree.

⚠️ **The per-process figure my sampler prints is biased and must not be quoted.** `R_mean` is an
unbiased estimator of mean runnable count, but the spawn rate under-counts processes shorter than the
~170 ms sample period, so `R_seconds_per_process` is inflated by exactly that factor. Use `R_mean`.

---

## 4. The Stop event, corrected

**`wrap-ledger.sh --machine`, MEASURED in this worktree** (`/usr/bin/time -p`, 5 iterations;
argv captured with a `git`-only shim):

```
196 ms wall · 180 ms CPU · 36 execs · 19 git subprocesses
```

The 19, in order, one call:

```
 1 rev-parse --is-inside-work-tree        11 config --get remote.origin.url
 2 symbolic-ref --short -q refs/remotes/origin/HEAD
 3 rev-parse --verify -q origin/main      12 -C <live-repo> rev-parse --is-inside-work-tree
 4 rev-parse HEAD                         13 -C <live-repo> config --get remote.origin.url
 5 status --porcelain                     14 -C <live-repo> rev-parse HEAD
 6 rev-list --count origin/main..HEAD     15 -C <live-repo> rev-list --count HEAD..origin/main
 7 cherry origin/main HEAD                16 -C <live-repo> merge-base --is-ancestor <a> <b>
 8 rev-list --abbrev-commit origin/main..HEAD  17 cat-file -e <sha>^{commit}
 9 rev-parse --git-common-dir             18 diff --diff-filter=A --name-only <a> <b>   (LIVE_ADDS)
10 rev-parse --show-toplevel              19 log -1 --format=%ct HEAD
```

Calls 12–19 are the live-layer arm (`LIVE`/`LIVE_LAG`/`LIVE_ADDS`), which runs **only in a repo whose
`origin` matches the live layer's** — i.e. exactly in claude-infrastructure, where every close
happens. Against a trivial repo with a different origin the same call is **94 ms / 12 execs / 9 git**.
So the doc's "10, or 17 with the live-layer arm" is a **floor**; the live-layer arm plus this repo's
history walk brings it to 19.

**Seven call sites, not six** (`operator-readout.sh` has two):

```
session-continue.sh:524 · completion-assert.sh:174 · anti-deference-nudge.sh:244
boundary-handoff.sh:268 · operator-readout.sh:422 · operator-readout.sh:1003
```
(the seventh is `completion-assert.sh:178`'s guard resolving the same path; the doc counted
`:189`/`:191`, line numbers have since drifted.)

⇒ **a working close is ~133 git subprocesses and ~1.26 s of CPU in `wrap-ledger` alone**, on top of
~800 ms of everything else — MODELLED as `953 ms (measured abstaining floor) − 2×94 ms (the two
trivial-repo ledgers the rig actually reached) + 7×180 ms` = **~2.06 s CPU / ~370 execs**.

The rig's Stop floor is the **abstaining** Stop: `dispatch-assert` (`no-assistant-text`),
`boundary-handoff` (`no-telemetry`), `operator-readout` (`nothing-to-surface`) and
`completion-assert` all abstained on the fixture, yet **`session-continue.sh` and
`operator-readout.sh` still each paid a full ledger** — so even the cheapest Stop pays two.
`session-continue.sh:524` pays its ledger **before** the rung test at `:527` that can discard it,
the asymmetry the prior doc named and did not take.

---

## 5. `setup-task-symlinks.sh` — the largest hook on the box, and it is thrown away

**MEASURED, isolated fixture** (`CC_TASKS_DIR` pointed at a scratch tree, `HOME` scratch):

| fixture | wall | CPU | per dir |
|---|---|---|---|
| 60 task lists, all non-empty, **all summaries deleted** (1st run) | 2,360 ms | 1,480 ms | 24.7 ms |
| same 60, **all summaries fresh** (2nd run) | 1,987 ms | 1,523 ms | 25.4 ms |
| same 60, summaries deleted again (control) | 1,890 ms | 1,500 ms | 25.0 ms |
| **300 EMPTY task-list dirs** | 7,550 ms | 5,940 ms | **19.8 ms** |
| same 300 empty, 2nd run | 8,080 ms | 5,950 ms | 19.8 ms |

Three facts, each measured:

1. **There is no freshness guard.** Fresh and stale cost the same to within 3%.
   `hooks/lib/task-helpers.sh` → `regenerate_summary()` runs `basename` + `cat .highwatermark` +
   `find` + `jq` + a write for **every** directory, every time, and its only early return is
   `[ ! -d "$dir" ]`.
2. **An EMPTY directory costs 80% of a full one** (19.8 vs 25.0 ms) — it still pays `find` and a
   `jq -n` that writes a zeroed summary.
3. **The loop is unbounded in the global store**: `setup-task-symlinks.sh:94` is
   `for dir in "$TASKS_DIR"/*/`. Live store, measured: **2,155 task-list directories, 66 non-empty,
   993 task JSON files** — i.e. **97% of the loop's iterations are over empty directories.**

Projected full cost: `2,089 × 19.8 ms + 66 × 25.0 ms` = **~43 s CPU, ~55 s wall, ~8,600 execs**
per SessionStart.

🚨 **It never gets there. `settings.json` gives this hook `timeout: 5`.** So on every session start
it burns ~5 s wall / ~4 s CPU / ~800 forks over the first ~200 directories, is killed, its
`additionalContext` (`"Tasks: N active…"`) never reaches the model, and the *next* SessionStart
starts from the same deterministic glob prefix and regenerates the same first ~200 summaries again.
**Nothing downstream currently works, so nothing downstream can regress.** (The rig's first
SessionStart run reported exactly 8,008 ms under an 8 s harness bound — the wall clamped to the
bound, which is how the truncation was found.)

---

## 6. The withdrawn memo: the fingerprint that IS sound

**Why the withdrawn design could not be fixed in place.** It keyed on *content* and therefore had to
**detect change** over an unbounded window (a TTL). Two properties killed it, and neither is tunable:
a directory's mtime does not move when a file's contents change (5da21949's tests 37/38/40 — a
class-C packet flipped open→vetoed *inside* an existing file, and the memo served the pre-veto ⛔ on
the highest-priority rung); and the digest that *would* see it costs 16.46 ms and grows without bound
with the store.

**The reframe: scope the key to the EVENT, not to the content.** The 6–7 consumers are not
independent queries at arbitrary times — they are one event, dispatched inside a single ~45 ms
window (measured, prior doc §2). Within one Stop they *should* observe one snapshot; today they each
take their own and can already disagree. So the cache never needs to detect a change. It needs only
to (a) serve one snapshot per event and (b) never serve across events.

```
key = session_id  ⊕  stat -f '%m %z' "$transcript_path"        # 1 exec, 2.25 ms CPU
```

| property | why it holds | which prior failure it retires |
|---|---|---|
| **No TTL at all** | the key is not time-derived | the `find -mmin` inert-bound class (b4ebdc06) |
| **No store fingerprint** | an operator resolving a decision happens BETWEEN turns, and a new turn always appends to the transcript ⇒ new key | the directory-mtime blindness that reverted it (5da21949) |
| **Absent key ⇒ no cache** | CLI / `/wrap` / /Users/chrisren/.claude/bin/cc-bats callers pass no `transcript_path` and always compute | makes `tests/wrap-ledger.bats` pass **by construction**, not by tuning |
| **Race degrades, never lies** | if the harness appends mid-event, consumers compute different keys ⇒ 2 computes instead of 1 | never a wrong rung |
| **Single-flight retained** | six cold misses inside 45 ms measured **20% WORSE** than uncached without it (9adc5120); keep the `mkdir` lock + ONE sleep, never a poll loop (a 40 ms poll forks ~50 sleeps per loser) | the wrong-arrival-pattern benchmark |
| **Store forks stay inside the snapshot** | measured at **1.0 ms and 0.0 ms CPU** — §5.4's "always re-run them" split buys nothing and costs a correctness argument | — |

**Measured cost per Stop:** `7 × 180 ms = 1,260 ms` → `180 + 6 × ~6 ms = 216 ms`, i.e. **5.8×**, and
**133 git subprocesses → 19**.

**Falsifiable predictions** (each cheap, each capable of refuting the design):

1. A `git`-counting shim across one real working Stop reports **≥114** git subprocesses today and
   **≤25** with the memo. Materially under 114 would mean §4's call-site census is wrong.
2. `tests/wrap-ledger.bats` stays **0 red** with the memo ON. If any of tests 37/38/40 *does* pass a
   `transcript_path`, this design is refuted and the fallback is §5.4's split-cache.
3. Two Stop events in one session must yield two distinct keys: `stat -f '%m %z'` on the transcript
   must differ across any turn. A transcript that does not grow within a turn refutes the key.
4. Logging the key from each of the 7 consumers over 20 real Stops must show **one distinct key per
   event**. More than one means the harness writes during dispatch — the memo then degrades to
   today's cost, which is the designed failure direction.

### 6.1 BUILT AND MEASURED (2026-08-11, backlog `9414dfb87233`)

Shipped in `scripts/wrap-ledger.sh` § THE MEMO, with the seven call sites passing `$WRAP_TRANSCRIPT`.
Harness: `scripts/wrap-ledger-memo-bench.sh` — N concurrent callers, git subprocesses counted by a
PATH shim, throwaway fixture repos, a live layer sharing the work tree's origin so the live-layer arm
(calls 12–19) actually runs. **No sequential arm exists in it**, deliberately.

| arm (N=7 concurrent, the real call-site count) | git subprocesses |
|---|---|
| `WRAP_CACHE=off` (control — today's close) | **133** |
| memo, COLD (a new event: nothing is cached) | **19** |
| memo, WARM (the same event again) | **0** |
| MUTANT — the single-flight lock neutered, nothing else changed | **133** |

Prediction 1 **holds exactly**: 133 today (§4's census predicted the number to the unit), 19 with the
memo against a ≤25 bound. Prediction 2 **holds**: `tests/wrap-ledger.bats` is 66/66 with the memo on,
by construction rather than by tuning — no test in it passes a transcript. Prediction 3 is what the
key rests on and is now pinned by a test that replays 5da21949's exact grave (a class-C packet
flipped open→vetoed between events, through the REAL `bin/cc-decide`), plus a mutation control that
neuters the transcript term and reproduces the staleness on demand. Prediction 4 is unmeasurable from
this VM — it needs 20 real Stops on the operator's box — and is the one open falsifier.

Two design points the measurement forced, neither of them in the plan above:

- **The lock's parent directory must exist before the lock.** With the memo dir absent, `mkdir
  "$lock"` fails for EVERY caller, so all six become waiters, all six time out, and all six compute:
  114 git and **2.8 s** of wall where uncached is 114 git and 0.48 s. That is FAILURE 1 rebuilt with
  sleeps on top, from one missing `[ -d ]`.
- **A flat wait cannot serve both ends.** 3 × 100 ms woke every loser before the winner finished
  (114 git again). The sleeps now double — 50/100/200/400 ms, ≤4 forks, ≤750 ms — which is roughly
  the uncached cost of the whole script under six-way contention, so the worst case degrades to
  "uncached plus the wait" instead of an unbounded hold. `WRAP_CACHE_WAIT_TRIES` / `_WAIT_MS` tune it.

Also corrected in passing: `stat -f '%m %z'` is **BSD-only**. GNU `stat -f` is `--file-system`, and it
prints a multi-line filesystem block on stdout while returning non-zero — so trusting its rc or its
non-emptiness would key every session on one constant string, i.e. a memo that never invalidates.
The implementation tries BSD, then GNU, and **validates that it got two integers** either way.

---

## 7. XProtect: assessment is per FILE, not per exec (MEASURED)

Arms run back to back, `XprotectService` (pid 913) and `syspolicyd` (498) cumulative CPU read
before/after with `ps -o time=` (hundredths resolution — not sampling):

| arm | wall / exec | XprotectService ΔCPU | reading |
|---|---|---|---|
| B — same script × 50 (shebang) | 8.6 ms | +0.27 s (≈ ambient) | cached |
| D — same script × 50, again | 7.2 ms | **+0.00 s** | cached |
| E — 50 already-assessed copies, 2nd run | 6.6 ms | **+0.01 s** | cached |
| **G — 50 FRESH files, shebang exec** | **138.5 ms** | **+6.71 s (0.97 cores)** | **assessed** |
| **F — 50 FRESH files, `bash <file>`** | **6.4 ms** | **+0.00 s** | **not assessed at all** |
| H — those same files, 2nd run via `bash` | 8.3 ms | +0.00 s | control |
| tail control — 8 s quiescent immediately after a 60-file burst | — | +0.28 s (0.03 cores) | **no async tail — it is synchronous** |

- **Answer to the brief's question (d): NO.** Re-exec of the same script is free. Hooks execute
  stable, long-lived files, so **the hook path pays zero Gatekeeper tax** and XProtect is not a
  Wave B lever.
- The cost is **first exec of a newly-created file**: ~138 ms wall, ~134 ms of XprotectService CPU,
  **synchronous** (the tail control rules out deferred work). Keyed on file identity, not content —
  50 byte-identical copies each paid in full.
- **`bash <file>` bypasses it entirely** (the file is read, not `execve`'d). That is a one-token
  remedy for any tool that writes a script and runs it.
- Baseline when quiescent: `XprotectService` **0.01 cores**, lifetime average **0.069 cores**;
  `syspolicyd` 0.07 / 0.023. The 31% figure is **not reproducible at rest** — it is a burst signature
  of new-file creation (worktree provisioning, installs, compiles, agent-written temp scripts) and
  belongs to Wave C, not Wave B.

---

## 8. Ranked lever list

Δ-occupancy at **10 active sessions**, inflation **×20** (§3.1's conservative reading; ×35 is the
upper one — multiply through if you take it).

| # | Lever | Δ execs | Δ CPU (s/min @10 active) | **Δ runnable threads** | Risk / precondition |
|---|---|---|---|---|---|
| **L1** | `regenerate_summary()` gets a freshness guard (`_summary.json` newer than every `*.json` in the dir ⇒ skip) **and** an empty-dir short-circuit; bound the loop to lists mapped to a project | **−800 / SessionStart** (−8,600 if it ever completed) | ramp-dominant: at 10 starts/min, **−39** | **−13 during a ramp**; ~0 steady-state | **LOW.** The work is already discarded at `timeout:5`, so nothing downstream can regress. Precondition: a test that the guard still regenerates when a task JSON is newer. Keep `timeout:5` as a tripwire. |
| **L2** | Stop: event-scoped memo, 7 `wrap-ledger --machine` → 1 (§6) | −216 / Stop (**−114 git**) | −5.4 | **−1.8** | **MEDIUM** — close-protocol core. Preconditions: `tests/wrap-ledger.bats` 0 red with the memo ON; single-flight retained; prediction 2 checked first. |
| **L3** | `validate-bash.sh`: 14 `grep` execs → bash `[[ =~ ]]` (a builtin, zero forks) | −13 / Bash call | −2.2 | **−0.73** | **MED-HIGH — it is a SAFETY gate.** Two indexed failures live in this exact file (`denylist-enumerates-spellings-not-the-class`, `guard-proxy-fails-in-both-directions`). Precondition: one mutation control **per pattern**, each red-on-neuter. |
| **L4** | `jq` collapse: one `jq … \| @tsv` + `read` per hook instead of 3–7 re-parses of the same stdin (`session-beat` 6, `dispatch-assert` 7, `session-continue` 6, `anti-deference` 6, `completion-assert` 6, `waiting-recycle` 4, `log-bash` 3, `backup-before-write` 3, `check-edit-boundary` 3) | −10 / Bash call, −28 / Stop | −2.3 | **−0.77** | **LOW** but 9+ files. `jq` is the box's largest short-lived component (2.803 threads, 6.2%). |
| **L5** | `session-beat.sh`: 12 `ps` → 1 snapshot reused (fires on **both** UserPromptSubmit and Stop) | −11 / event × 2 events / turn | −0.9 | **−0.30** | **LOW.** `ps -axo …command=` is 49.5 ms CPU — 20× a bare fork. |
| **L6** | `handoff-intent-nudge.sh`: drop or share the full-argv `ps` (130 ms CPU for one hook, on every prompt) | −1 exec, −120 ms | −0.65 | **−0.22** | **LOW.** Can consume L5's shared snapshot. |
| **L7** | `session-continue.sh:524`: move the ledger call **after** the `:527` rung test | −36 execs on every non-🔧 Stop | −1.4 | **−0.47** | **LOW-MED** — behaviour change inside the continuation actuator; independent of L2 and *subsumed* by it. Take L2 **or** L7, not both. |

**Take L1 + L2 + L4 and the per-active-session hook CPU falls 2.616 → 1.85 s/min (−29%)**, with the
ramp cost cut by an order of magnitude. L1 is first not because it is largest in steady state (it is
not) but because it is the only one whose downside is provably zero.

**Named and NOT in Wave B's scope, both larger than any single lever above:**

- **Box-wide daemons — 6.25 runnable threads (13.9%).** `cc-dispatch` 2.744, `cc-backlog` 1.487,
  `autonomy-sweep.sh` 0.718, `assignee-pane-residency.sh` 0.714, `deploy-parity-assert.sh` 0.584.
  Session-independent, so they do not change the 1.6 slope — but they consume the same ceiling and
  no wave owns them.
- **Spotlight — 1.833 threads (4.1%).** `mds` + `mds_stores` indexing the worktree tree.
- **XProtect first-exec — Wave C.** ~138 ms per newly-created file exec'd via shebang; `bash <file>`
  is free.

---

## 9. Method notes, limits, and one leak

### 9.1 What the instruments can and cannot see
- **Exec count, not fork count.** The `PATH` shim counts `execve` of a shimmed name. A `$( )`
  subshell that runs only builtins forks without exec'ing and is **invisible** — the control proved
  this deliberately (5 `git` counted 5; a builtin-only subshell counted 0). Every exec figure here is
  a **floor** on forks.
- **Absolute-path invocations bypass the shim.** Only `notify.sh` uses them
  (`/opt/homebrew/bin/timeout`, `gtimeout`), and it measured 0 execs / 1.7 ms — immaterial.
- **Side-effecting binaries were counted but not executed** (`osascript`, `it2`, `tmux`, `afplay`,
  `open`, `curl`, `kill`, `pkill`, `launchctl`, `cc-notify`, `cc-mail`, `cc-await-ping`, `claude*`).
  This **under-states** any hook whose real cost is in those calls — chiefly `notify.sh`, which
  therefore reads as ~free and is not ranked.
- **Serial invocation.** Each hook was timed alone. Under the harness's concurrent dispatch, wall
  collapses toward the max member while **CPU is unchanged** and R-time inflates (§3.1). The CPU
  column is the load-bearing one; the "wall if concurrent" column is indicative only.
- **The Stop rig floor is the ABSTAINING Stop** on a trivial repo. The working-close row is
  MODELLED from measured parts and labelled as such.
- **Write/Edit event rate is MODELLED** at 0.4× the Bash rate — it is the only rate not measured, and
  it drives 10.6% of the total. Measuring it would need a PostToolUse counter that does not exist.

### 9.2 The per-process occupancy figure is biased — do not quote it
`R_mean` from the sampler is unbiased. The spawn-rate denominator under-counts processes shorter than
the sample period, so `R_seconds_per_process` is inflated by the same factor. Reported for shape only.

### 9.3 🚨 A rig leak, recorded because it is the generalisable lesson
`HOME` was overridden to a scratch tree, which is **not sufficient isolation**:
`hooks/lib/task-helpers.sh:13` resolves `CC_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"`, and
**`CLAUDE_CONFIG_DIR` is exported into every agent's environment** (here `~/.claude-tertiary`). So the
first `setup-task-symlinks.sh` replay read — and could write `_summary.json` into — the **live**
task store. Checked afterwards: 0 files under that store carry mtimes inside the rig's execution
window (495 carry mtimes from the last 5 minutes, i.e. a concurrent live writer), and the write is
idempotent by construction (a summary re-derived from the same task JSONs), so no state was lost.
The subsequent scaling runs pinned `CLAUDE_CONFIG_DIR`, `CC_TASKS_DIR` and `CC_TASKS_INDEX` to the
scratch tree. **Lesson: `$HOME` is not the config root on this box; a replay rig must pin every
`CLAUDE_*` root, not just `HOME`.** One upside — it means §5's 2,155-directory figure is live truth,
not a fixture.

### 9.4 Adversarial pass — what a hostile reviewer would check, and what it found
- *"Is the hook set the same for every session?"* — Checked. Neither
  `~/.claude/settings.local.json` (absent) nor this worktree's `.claude/settings.json` /
  `.claude/settings.local.json` register any hook. The 79-entry global set is the whole population.
- *"Is `wrap-ledger` really called 7×, or are the call sites guarded?"* — Read every site. Only
  `completion-assert.sh:178` guards (`abstain "no-wrap-ledger"` when the script is missing, not when
  the ledger is unneeded). None is conditional on the close being a working one, which is why even
  the abstaining rig Stop paid two full ledgers.
- *"Does caching the store half race a Stop hook that WRITES those stores?"* — Checked. Five Stop
  hooks mention `cc-backlog`/`cc-decide`, but every occurrence is inside **advisory prose emitted to
  the model** (`completion-assert.sh:624`, `dispatch-assert.sh:191`/`:225`, `operator-readout.sh:35`),
  never an invocation. No Stop hook mutates a store its siblings read, so the event-scoped snapshot
  is sound.
- *"Was the 8,008 ms SessionStart figure a rig artifact?"* — Yes, partly, and the artifact was the
  finding: the wall clamped to the harness bound. Re-measured in isolation with a scaling law
  (§5), which is what turned "expensive" into "killed at `timeout:5`, every time".
- *"Is `grep` in hooks ugrep?"* — No. `bash -lc 'command -v grep'` → `/usr/bin/grep`, BSD 2.6.0,
  2.67 ms. The prior suspicion is wrong; ugrep is *faster* (0.67 ms) and the probe's `ugrep` rows
  are the Bash tool's own grep.
- *"Is the 31% XProtect figure being explained away?"* — It is being **relocated**, with a control:
  re-exec of the same file is +0.00 s, first exec of a new file is +134 ms, and the post-burst
  quiescent arm rules out an async tail.

### 9.5 What this wave did NOT establish
- The **inflation factor** is the largest uncertainty (×20 vs ×35) and is the one number that scales
  every Δ in §8. `scripts/hook-dispatch-bench.sh --control` on a box with ambient stable within 2×
  is the certifying run, and the box has not been quiet enough for it (prior doc §7 prediction 2).
- The **working-close Stop total** is modelled, not measured end to end. Measuring it needs a clone
  of this repo with a matching `origin` URL so the live-layer arm engages, plus a transcript fixture
  that makes all seven consumers proceed rather than abstain.
- The **Write/Edit event rate** is unmeasured (§9.1).
- Whether the harness appends to the transcript **during** hook dispatch — §6 prediction 4. The memo
  is safe either way; only its hit rate is at stake.
