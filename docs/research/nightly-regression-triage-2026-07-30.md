# nightly-regression RED @ 2026-07-25T20:33:06Z — triage

**Item:** cc-backlog `5fb957ffb085` · **Triaged:** 2026-07-30 · **Branch:** `wt-5fb957ffb085`

## Verdict

The page was not reporting a regression. **Five of the seven checks in the 2026-07-25 set were
false**, and the RED set could never have gone green, because the runner scored three classes of
non-regression as regressions. That is why eight consecutive nights (07-19..26, escalating
7→8→9→12) were all RED and all unactioned.

The item's stated hypothesis — peer-pkill signal-death (`a0718a5d78b3`) and the unattributed-RED
rule (`d1ba434f6239`) — was **right about `bats:tests`** (13 of its 15 named failures were
load-induced cuts) but is **not** what produced the majority of the RED *set*. No amount of
quiet-box re-running would have cleared that majority: it was classification error in the harness.

## Per-check classification (the 07-25 set of 7)

| # | Check | Verdict | Evidence |
|---|---|---|---|
| 1 | `bats:tests` | **13/15 FALSE**, 2 load-dependent | Re-ran the 2 owning suites: 21/23 passed. The 2 survivors assert exit 0 on a `--dry-run` that `capacity_gate` correctly refuses (exit 9) above 2.0 load/core |
| 2 | `never-stuck-gate(live)` | **REAL, chronic, declared** | 19 met · 2 failed — the *same* 19·2 this job's own header cites as the signal it was built for. Pre-existing, not a 07-25 event |
| 3 | `cc-upgrade-gate.sh` | **FALSE — harness** | Bare-run; requires `<bin> <model> <account>` → usage, exit 2 |
| 4 | `gate-manifest.sh --selftest` | **FALSE — stale** | Bare-verb `selftest`; now exits 0 (fixed since the page) |
| 5 | `premortem-gate.sh --selftest` | **FALSE as regression** | Deliberate `exit 1` at `:97`. Its own output: *"Red here is not a bug — it is the bar"* |
| 6 | `wait-safety-gate.sh --selftest` | **FALSE as regression** | Same by-design bar, `:129` |
| 7 | `claude-lint-models.sh` | **FALSE — fixed by a sibling** | Bare-run needed `--all`. Fixed by `86556233` *"accept the --selftest flag form the nightly runner passes"* |

## Root causes (four distinct, all now fixed except as noted)

**1. Two tests depended on ambient box load.** `handoff-fire-account-sweep.bats:226,234` assert on a
`--dry-run` *readout's content* but also asserted `[ "$status" -eq 0 ]`. The P0-17 capacity gate
refuses a net-new fire above 2.0 load/core with exit 9, so on a busy box both failed. Measured: exit
9 at 2.05/core. → **`b161389d`** (per-test `CC_FIRE_CAPACITY_GATE=off`, the gate's own documented
kill switch at `handoff-fire.sh:1286`). Same class as memory `metric-zero-by-refusing-gate`
(capacity_gate made 16 postland tests fail by load).

> **I first fixed this in the wrong place, and the correction is the more useful finding.** My first
> attempt exempted `--dry-run` from the gate (`handoff-fire.sh:2273`), reasoning that a dry-run
> spawns nothing so it costs no capacity. The gate's own dedicated suite refuted it: **`--dry-run` is
> the deliberate harness for observing the gate** — `handoff-fire-capacity-gate.bats`' `fire()` helper
> puts `--dry-run` on all 13 cases and its header says so outright. Exempting it made the gate
> unobservable and broke 6 of the 13, including the ADMIT positive control and all three fail-open
> cases. Reverted in **`734e88e3`**.
>
> The suite is right on the merits too, which is why the revert is correct rather than a compromise:
> a dry-run answers *"what WOULD happen if I fired?"*, and on a saturated box that answer is
> **refused**. Exiting 0 with a full readout would assert a fire that would not occur. Exit 9 was
> correct behaviour meeting a test that assumed an idle box.
>
> The transferable part: **when a shared flag has two callers with incompatible expectations, the one
> with a dedicated suite and a written rationale is stating a contract; the one asserting a bare exit
> code is usually just assuming an environment.** Weakening the mechanism to satisfy the assumption
> would have silently deleted a gate that 13 tests exist to prove. Verified after the revert: both
> suites together 26/26, 0 failed.

**2. `telemetry-e2e` read a directory the writes had moved out of.** `statusline.sh:87` gained
`TDIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"` (`df6b328f`, 07-25). The suite has exported
`CC_TELEMETRY_DIR="$SB"` since `671c211b`, so the writes moved into the sandbox while T1/T2/T3 kept
asserting against the hardcoded live path — a 100%-deterministic miss, verified 3/3. **The stale
comment is what hid it**: it stated the seam's *absence* as a fact long after it existed.

Two different failures, not one:
- **T1/T3** — the file they read is never written. T3 reported *"150 torn reads"* — 150 of 150, the
  signature of an **absent** file, not a torn one; a real atomicity bug yields a handful.
- **T2** — a *negative* assertion ("no unknown.json"), so the stale path made it pass **vacuously**:
  it could not fail whatever the guard did. It had been asserting nothing since the seam landed.

This cascaded far past the suite: `premortem-gate.sh:72` gates its S-2 criterion on this suite
exiting 0, so the miss flipped S-2 ⛔ and took premortem-gate from **7·1 to 6·2** — which the
nightly counts as a regression. → **`dfe13d03`**. Suite 19/2 → 21/0 and premortem 6·2 → 7·1, both
at load 53, higher than the load under which they failed.

**3. The runner scored three classes of non-regression as regressions.** → **`3822b6a1`**

- **LIBRARY** — `gate-policy.sh` documents itself *"SOURCED, never executed (no shebang, not +x, on
  purpose)"*. Executing it yields `Permission denied`, scored as a regression.
- **UNSAFE** — for these the naive fix is *worse than the false RED*: giving `cc-upgrade-gate.sh`
  its required argv would make this 04:00 job **spawn live sessions nightly** (`GATE_SPAWN` defaults
  to 1), violating the job's own side-effect-free contract. The usage-exit was accidentally
  protective. `gate-cleanup.sh` is declared for the same reason — it sends SIGTERM/SIGKILL to gate
  processes (latent only: scoped to the shared checkout, where policy forbids working, so it
  currently reports "nothing to clean").
- **READINESS BAR** — **8 of the 14** `*gate*.sh` scripts are bars that say so in their own output
  (*"Red here is not a bug — it is the bar"*). Chronic by design ⇒ never a regression alone. Not
  silenced: each bar's failed-**count** is compared to a declared baseline, so a bar that gets
  *worse* still pages. This is not hypothetical — premortem had already slipped 7·1 → 6·2 inside a
  RED nobody could read.

**4. Non-verdicts were convicted as failures.** `rc 124/137/143` now classify as NON-VERDICT.
137/143 is the peer-pkill class from the item's own hypothesis. Convicting on a *missing* verdict is
what made these pages unreadable. A per-check bound was added too
(`CC_NIGHTLY_CHECK_TIMEOUT_S`, default 300s): four readiness gates **re-run `bats` internally** (5,
3, 3, 7 invocations), so this job ran the suite five times over and its log stamps landed *hours*
after its 04:00 trigger.

## Result

Validated against the real corpus (bats + live checks stubbed, page/log to temp): **RED 12 → 3**, and
then **3 → 2** once the generator fix below landed. Both survivors are genuine, named, reproducible
lint violations — not regressions of this item, and filed separately:

- `growth-coverage-lint.sh` — 5 unclassified growth surfaces (`security`, `vendor`,
  `autonomy/postland`, `autonomy/recycle-events.jsonl`)
- `pane-id-lint.sh` — 26 truncated pane ids (all in `docs/research/**` prose; scope question, see below)

### The generator fix: one declaration set, four failures — landed by a SIBLING, not by me

`reaper-horizon-lint`'s remaining violations turned out to be the shared root of most of the RED set.
`premortem-gate`'s S-1 (`premortem-gate.sh:63`) and `wait-safety-gate`'s L0 (`wait-safety-gate.sh:57`)
both shell out to that lint, and those two gates were in turn **`never-stuck-gate`'s two failing
legs**. So three `$DECLARED` entries cleared four named failures — and cleared them *properly*, to
green, not merely reclassified:

> **Attribution + a convergence I lost, correctly.** I implemented these three declarations
> independently and my commit was **dropped at rebase**: `3f8972ce` (*"fix(reaper-lint): score -mtime
> and marker-seconds horizons, then declare 3 reapers"*) had already landed the same three
> declarations **and fixed the `-mtime`/epoch-delta blind spot that I only NAMED**. Their work is
> strictly superior, so I stood down and skipped my commit rather than merge a comment block that
> would have contradicted their `§1b`/`§1c` scorers. Adjudicated the way the convergence protocol
> requires — by running *my* verifications against *their* code: `reaper-horizon-lint` clean,
> `premortem-gate` 8·0, `wait-safety-gate` 13·0, identical outcomes. My filed blind-spot item was
> closed as already-fixed by `3f8972ce`, not re-opened.
>
> Worth noting for anyone reading the numbers below: the table's *before* column is what **this
> session measured**, and the *after* is trunk's — the improvement is real but the fix is theirs.

| | before | after |
|---|---|---|
| `reaper-horizon-lint` | ⛔ 3 violations | **clean** |
| `premortem-gate` | 7·1 (6·2 at worst) | **8 met · 0 failed** — *"un-hold is defensible"* |
| `wait-safety-gate` | 12·1 | **13 met · 0 failed** — *"un-hold is defensible"* |

Two process notes worth carrying:

- **The page's violation list was 5 days stale.** It named 4 files; a live run named 3, and only 2
  overlapped (`cc-recover-safeguard` and `lead-crash-watchdog` had since been declared;
  `bin/cc-await-ping` had newly appeared). Re-derive from a run, never act on a page's list.
- **Two of the three horizons had to be verified by hand, because the lint cannot see them.** §1 greps
  `-mmin \+[0-9]+` and §2 greps `RETAIN_H`/`CC_SUP_GC_S`, so a horizon written as `-mtime +N`
  (`dispatch-assert.sh:117`, 7d) or as an epoch subtraction against a constant
  (`desk-invariant.sh:332-343`, 7d) is bounded by **nothing**. Both sit 100× above the 6000s floor
  today, but a future edit lowering either passes the gate silently — and §3's own header names this
  exact failure: *"a detector with a blind spot is the bug it exists to prevent."* Filed, not fixed here.

Selftest 21 → 37 assertions, 0 failed, on `/bin/bash` 3.2 (what the plist runs). Every new branch is
RED-proven, including the two that must stay RED (a regressed bar, an undeclared bar) and a real
`exit 1` as the control.

## Open / not in this item

- **`never-stuck-gate` 19·2** — real and chronic, the invariant this job exists to watch. A separate
  subsystem item, not a 07-25 regression.
- **The nightly has not run since 2026-07-26.** `regression.log` has one entry per night for
  07-19..26 and nothing for 07-27..29; `launchctl list` shows no `com.claude.nightly-regression`
  even though `~/Library/LaunchAgents/com.claude.nightly-regression.plist` exists. Reloading a
  launchd job is a **C10 operator-only** action.
- **`pane-id-lint` scope** — its 26 findings are historical pane ids quoted in research prose. A
  whole-tree lint makes every author answerable for every other's docs (memory
  `whole-tree-lint-is-a-fleet-wide-hard-stop`). Worth scoping to the diff; not done here.
- **4 readiness bars still undeclared** (`limit-reset`, `respawn`, `route`,
  `session-lifecycle-safety-gate`) — they re-run `bats` internally and could not be measured under
  load. Fail-closed by design: they read RED as "undeclared bar" until a measured baseline is added.

## The transferable rule

**An alarm whose set can never be empty carries the same information as one that cannot fire** —
and it is worse than silence, because it *hides* real movement inside itself. premortem-gate slipped
7·1 → 6·2 in plain view of a nightly page and nobody could see it. Before treating a chronic RED as
a regression, separate the verdicts the exit code cannot express: **by-design red** (a readiness
bar), **could-not-run** (cut, killed, or externally signalled), and **not-a-check** (a library, a
script needing argv, a mutation). Only what remains is a regression. Count NOT-success, not
non-zero.

Corollary from #2: **a comment asserting a seam's absence is a claim with an expiry date.** The
comment *"no CC_TELEMETRY_DIR seam yet"* outlived the seam by days and was the single thing that
made a deterministic, 3/3-reproducible miss look like a flake.
