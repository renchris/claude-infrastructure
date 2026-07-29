# Landing-pipeline failure — root-cause reconciliation, keystone, architecture

**Date:** 2026-07-26 · **Method:** 6-lens Dynamic Workflow (4 filed-cause lenses + a
baseline-blind Fable-5 derivation panelist + telemetry forensics) over frozen evidence, with
adversarial default-to-refute verification. Every number below was measured this session from
disk truth or a live probe. Claims inherited from earlier sessions are marked and several are
**corrected**.

---

## 0. Corrections to the frozen evidence pack (do not inherit the originals)

| Frozen claim | Verdict | Measured truth |
|---|---|---|
| "Nothing has landed since 04:37:47Z" | **FALSE** | `exit:0` lands at 06:01:59Z, 06:08:08Z, 06:17:46Z. `origin/main` advanced 55c8afa → 1f19ac0 → 12b9405 → 4c737ce → 8edac69 → 5a80a64. The pipeline is **intermittently succeeding**. |
| "164 stranded + 45 orphaned = 209 patches" | **Over-count** | 481 branches carry unlanded commits, but **208 are ship-land's own `ship/backup-*` / `preland-backup-*` safety refs**. Real: 273 branches, 396 commits, **197 distinct patch-ids, 190 truly stranded** (7 already on trunk by content; dupe check sampled 400 trunk commits, so 7 is a floor). |
| `exit` histogram over `land.log` | **Double-counted** | `land.log` has **two writers**: ship-land appends `"tool":"ship-land"` lines (174), `land-lock.sh` appends its own lock lines with **no `tool` field** (256); only 121 pair. Every failure rate computed over the raw file is wrong. **Attested (ship-land) totals: `exit:0` 126, `exit:6` 39, `exit:3` 9.** |
| "the iTerm2 API is wedged machine-wide" (`3c6bf04ba842`) | **ARTIFACT** | Re-probed: rc=0 in 1.2–3.6 s, wrapper and real binary, repeatedly. Already fixed by `8edac69` + `5a80a64`, both **on trunk**. |
| "gate-policy.sh is not executable — worth resolving" | **Non-issue** | It is `SOURCED`, never executed (`ship-land.sh:104`, `[[ -r ]]`). Mode 644 is correct and deliberate; `SHIP_LAND_GATE_SCOPE_DEFAULT=scoped` takes effect. |
| "swap 2.5 G of 4 G used, 546,696 pageouts ⇒ memory exhaustion" | **FALSE — the premise is a misreading** | The machine has **64 GB RAM**. The "4096 M" is the *dynamically-grown swapfile*, not a cap; its volume has **5.0 TiB free**. `vm.page_free_wanted: 0`, `kern.memorystatus_level: 47–59` — not a pressure regime. Live footprint: **63 bats processes = 2.7 GB total**, versus 27 `claude` processes = 9.6 GB. bats is not the memory consumer and there is no exhaustion. |
| "`exit:143` occurred only twice, so peer-killing is marginal" (**my own earlier claim — retracted**) | **FALSE — measurement artifact** | `ship-land.sh` installs **no signal trap** and passes only hardcoded literals to `attest_land`, so **it can never record its own signal death**. Both `143` lines come from `land-lock.sh`'s EXIT trap, which only fires if the kill lands during the short *locked* child. The 20–50 min **unlocked** gate — where the suite actually runs — is entirely unobserved. "2" is a **capture floor (~18 %)**, not a rate. The true driver-kill rate is *unmeasurable from `land.log` by construction*. |

---

## 1. Root-cause reconciliation

### The single statistic that organises everything

Attested scoped-era outcomes, split by which gate tier actually ran
(`selected_n == -1` ⇒ the run took `run_bats_all` — the full 124-suite / 1,749-test gate;
`SELECTED_N` is only assigned inside the scoped branch, `ship-land.sh:297,367`):

| Gate tier | Landed | Failed | Failure rate |
|---|---|---|---|
| **FULL** (`selected_n = -1`) | 1 | **33** | **97 %** |
| **narrow** (`selected_n` 0,1,14,15,16,19,26,53,59,63,74) | 7 | 6 | 46 % |

**The FULL tier is a death sentence; the narrow tier is a coin flip.** Everything below is
either *what pushes lands into the FULL tier* or *what kills them once they are there*.

> **Scope this headline honestly (adversarial-verify correction, applied).** These figures are
> for the **instrumented scoped era only** — `gate_scope`/`selected_n` did not exist before
> `d1c5219` landed the selector at 2026-07-25 16:40, and the field first appears in `land.log`
> at 00:09:49Z on 07-26. Verifiers that computed the share **all-time** got ~26–35 %; within the
> mechanism's own era they got 76–85 %, consistent with the 33/39 above. Quote the era, never
> the lifetime number. Two further cautions from the same pass: `land.log` is **live** (it grew
> 430 → 437 rows mid-session), so any exact count is a snapshot; and one verifier argues the
> `added ⇒ FULL` rule is better called the **router** than the root cause — the root being that
> the FULL tier is fatal at all. That is a fair refinement and it is why this document frames a
> **loop with three moving parts**, not a single root cause.

### The four filed causes, adjudicated

| # | Filed cause | Verdict | Share | Basis |
|---|---|---|---|---|
| 3 | `f8e40b4c577d` — fail-closed degradation **amplifies** load | **REAL — DOMINANT** | ~62 % | Confirmed, but **not** via the path it was filed under. See below. |
| 2 | `a0718a5d78b3` — peers kill each other's gates | **REAL — DOMINANT among killers** | ≥54 % of REDs are externally cut; true rate unmeasurable (no signal trap) | Live killer captured (PID 26727, argv below). Documented sweeps killed ≥11 drivers; 2 were logged. |
| 1 | `77738605376f` — concurrent suites **OOM**-kill each other | **REFUTED — 0 %** | 0 % | **`memorystatus: killing` events in the last 4 h: ZERO**, with a passing positive control (the same predicate returns 2,568 `memorystatus` lines, so the query works and the zero is real). 64 GB RAM, 5 TiB swap headroom, `page_free_wanted: 0`, `memorystatus_level` 47–59. Live footprint: 62 bats processes = **3.2 GB**, versus 27 `claude` processes = **11.1 GB** — bats is not even the major consumer. The observed `Killed: 9` is therefore **not jetsam**; see *The killer, sharpened* below — the leading suspect is `cc-teardown`'s TERM→KILL ladder driven by a timer, not a peer and not memory. |
| 4 | `3c6bf04ba842` — it2 API wedged machine-wide | **ARTIFACT — already fixed** | 0 % | Refuted by 8 direct probes; fixed by `8edac69`+`5a80a64`. |
| — | `9c5d0ba74e79` — a signal-killed gate is misreported RED | **SAME CAUSE, DIFFERENT MASK** | — | Not independent: it is the *reporting organ* of #1, #2 and #3. Two lenses converged on this independently. |

### #3 is real but was filed under the wrong mechanism

The filed path — `postland_net_live()` degrading scoped→FULL when stamps go stale — **is not
firing**, and cannot: the guard counts only `"verdict":"green"` stamps, and
`[[ "$newest" -gt 0 ]] || return 0` (`ship-land.sh:238`) treats *zero green stamps* as "net not
adopted yet ⇒ trust". All 5 postland stamps are `"verdict":"red"`, so the guard is permanently
inert. **A net that runs and is always red is indistinguishable, to its own guard, from a net
that was never adopted.**

The mechanism that *is* firing is a different fail-closed rule, in the selector:

```python
# scripts/gate-select.sh:308-310 (pre-fix)
else:
    if code == "A":
        emit_full("added-unmapped:%s" % path)     # ← fires BEFORE clauses (a),(b),(d),(e)
```

The label is a lie. The rule never checks whether the added file is mapped — it emits FULL for
**every added non-test, non-prose file**, before any mapping clause runs. This fleet's dominant
change shape is `bin/cc-foo` + `tests/cc-foo.bats` **added together**, so the very suite that
maps the new file was never consulted.

Replaying four real failing ranges through the selector: **three said
`FULL <- added-unmapped:<new bin/ or scripts/ file>`**; the fourth said `FULL <- shared-lib:`.

### Why the FULL tier kills lands — three compounding mechanisms

1. **Long exposure.** A full gate runs 1,186–3,217 s (20–53 min, from `postland/runner.log`).
   Median interval between successful trunk lands is **1,101 s (~18 min)**. So
   **T_gate > T_trunk-move**: a full-gate lander is more likely than not to be lapped, hit the
   CAS check (`ship-land.sh:441`), and re-gate the whole tree from scratch. λ·T ≥ 1 — a livelock.
2. **The in-lock fallback serialises the machine.** After `SHIP_LAND_GATE_ROUNDS` (default 3)
   optimistic rounds are invalidated, ship-land re-execs with empty `GATE_BASE`/`GATE_HEAD` and
   gates **inside the machine-wide land mutex** (`ship-land.sh:666-670`, `main_locked`
   `:424-428` — "a held mutex stops further pipeline movement"). **Observed live during this
   session:** PID 97389 (`wt-ed222b4a2ea9`) held the lock **35+ minutes** running `bats tests/`,
   with this session's *already-green* land queued behind it. The design invariant "the mutex is
   held for seconds" is false in practice: `hold_s` median **228 s**, p90 **682 s**, max
   **6,771 s (1.9 h)**; only **29 %** of holds are under 30 s.

   **Crucially, this is not an independent defect.** That fallback calls `run_gate`, which still
   honours `SCOPE=scoped` — so it is a *whole-suite* stall **only because the selector said
   FULL**. Fix the selector and the same fallback holds the mutex for one narrow gate (~4 suites)
   instead of 1,749 tests. The keystone therefore dissolves the lock-hold pathology **without
   touching the lock design at all** — which is exactly what a change that must not revert the
   2026-07-25 unlocked-parallel design needs to do.
3. **Cuts are laundered as RED at every layer.**
   - `run_bats_all` (`ship-land.sh:246-249`) branches on the **exit code only** —
     `bats tests/ >&2 || return 1`. A SIGTERM/SIGKILL of any one of 124 suites, with zero
     `not ok` lines, becomes `✗ gate: bats RED` ⇒ `exit 6`. It has **no** flake-exoneration,
     unlike `run_scoped_suite` (`:252-283`) which absorbs exactly this.
   - The post-land verifier does the same: `postland-verify.sh:150` —
     `if [ -z "$pairs" ]; then FAILING=("tests/")` — fabricates the sentinel `failing=tests/`
     when the TAP contains **no parseable `not ok` at all**. **4 of the last 5 postland "RED"
     verdicts carry `failing=tests/` with `retries=0` — they were CUTS, not reds.** This is
     also why no green stamp has ever been written, which is why the guard in #3 is inert.

**Empirical proof that CUT ≠ RED at scale:** of the 39 attested gate-REDs, **21 (54 %) fall in
7 same-second clusters spanning 2–4 *different* worktrees, and all 21 ran the FULL tier.**
Synchronized failure across independent repos in the same second is statistically impossible
for genuine test failures — those are machine-wide cut events. Independently: multiple
full-suite runs on disk reached **1,460 / 1,588 / 1,608 / 1,643 `ok` with ZERO `not ok`**, and
`fullbats.out` completed **1,643/1,643 at EXIT=0**. **The suite is green when it is allowed to
finish.**

### The killer, sharpened — it is probably neither peers nor jetsam (STRONG LEAD, 2026-07-26)

The 30-agent wave's OOM lens refuted jetsam **and** named a better suspect. Three measurements,
each independently checked by the lead:

1. **Every SIGKILL on this machine targets ONE file: `tests/cc-reaper.bats`.** `flakes.jsonl`
   now holds 3 × `exit 137` entries, all that suite; plus the `Killed: 9` at
   `ship-land.sh:252`. **Jetsam cannot be suite-specific** — it selects by priority band and
   footprint, and would take the 26 `claude` processes holding 14 GB long before a 2.8 MB
   `bash bats` script. It took neither.
2. **The load correlation is INVERTED.** The three `exit 137` rows sit at loadavg
   **15.10 / 15.32 / 15.32** — the *lowest* in the file — while the SIGTERM and genuine
   `not ok` rows sit at **19.23 / 19.36 / 20.92 / 21.10**. `77738605376f` predicts SIGKILL at
   load 17-20; the measurement says the opposite.
3. **A TERM→KILL ladder is live on this machine, on a timer.** `cc-teardown:345-353` is exactly
   `kill -TERM` → grace poll → `kill -KILL`, and `cc-reaper sweep --reap` runs continuously
   (2 live sweeps observed; the wave additionally caught worktree-local copies sweeping
   machine-wide). A timer-driven killer explains the low-load correlation that neither jetsam
   nor a human-typed peer command does.

**The most parsimonious reading: `tests/cc-reaper.bats` builds fixture sessions that a
concurrently-sweeping live `cc-reaper --reap` classifies as reapable and tears down through
cc-teardown's ladder — the reaper reaping its own test suite.** This is the exact failure the
`109-of-124 non-hermetic suites` fact predicts: the suite mutates and is mutated by the
operator's live `~/.claude` state.

Note `cc-reaper` *does* carry the right guards in principle — `cc-reaper:44,138`: "active /
owned-wait / coordination-hang / rate-limited / crashed are NEVER reaped". So the defect is not
a missing rule; it is that a **test fixture is indistinguishable from a real reapable session**.

**Status: STRONG LEAD, not proven** — the correlation is tight and the mechanism is present,
but nobody has caught the ladder in the act against a bats PID. The OOM *refutation* is proven;
this replacement is not. **Do not file it as fact.** The cheap decisive probe: have
`cc-teardown` log every PID it TERMs with that PID's argv, run the fleet an hour, and grep for
`bats`. If it appears, the remedy is a hermeticity fix (fixture PIDs outside the reaper's
candidate set), not scheduling and not a standing instruction — which would make it a **fourth**
independent path to the same "gate dies → cut → laundered as RED" outcome.

*(Ownership note: `bin/cc-reaper` / `bin/cc-teardown` have an active owner who landed
`ce17de1`+`b494439` in this area today. Hand off, do not edit.)*

### Reconciliation verdict

Four filed causes collapse to **one loop with three moving parts**:

> **#3 opens the exposure window** (`added ⇒ FULL` routes 85 % of failing lands into a 20–53 min
> FULL gate) → **#2 does the killing** (peers SIGTERM/SIGKILL whatever is in flight; #1 is the
> same event with jetsam wrongly blamed) → **`9c5d0ba74e79` launders the cut as RED**
> (`run_bats_all` reads the exit code, never the `not ok` count) → the land fails → the session
> is told to "clear the sibling gates and land now" → **back to #2**. #4 was a real total block
> on full-scope landing until `8edac69`, and is now closed.

The choice between #1 and #2 is *second-order*: both are "an external signal cut a long-running
gate", and #1's mechanism is refuted outright. The productive question is not **"who is killing
gates"** but **"why is a 20–53 minute FULL gate running at all, and why does its death read as a
test failure?"** — which is what the keystone and K2 answer.

> **Blind-panel corroboration.** A Fable-5 panelist given only the system model and raw
> telemetry — never the four filed causes, never this session's conclusions — independently
> derived the `added ⇒ FULL` rule as its **FM1, "dominant strand-producer"**, and nominated the
> exact same smallest change. It also independently surfaced the two-writer `land.log`
> double-count and the `failing=tests/` sentinel. Convergence from an unanchored derivation is
> the strongest evidence in this document.

---

## Status at end of session (2026-07-26)

| | state |
|---|---|
| **Keystone** — `added ⇒ FULL` deleted | ✅ **LANDED `19a2cfe`**, content-verified on `origin/main` |
| **K2** — a CUT is not a RED (both layers) | ✅ **LANDED `c605a2e`**, content-verified; 390 ok / 0 not-ok |
| This findings doc | ✅ on trunk (`095665f`, updated here) |
| K3 closure bound · K4 union cap · K5 in-lock bound | specified with measured numbers, **not built** |

Both landed changes went through the **normal scoped gate** — no full gate, no kill switch, no
operator command. The bootstrap deadlock is broken: the pipeline that could not repair itself
has now repaired itself twice.

---

## 2. THE KEYSTONE — landed

**Change:** delete the two lines at `scripts/gate-select.sh:309-310`. An added file then runs
the *same* mapping clauses as a modified one, and the pre-existing `unmapped` rung
(`:325-326`) still fails it closed if nothing maps it — exactly what the label promised.

**Fail-closed is preserved.** An added file that nothing maps still yields FULL, via
`unmapped:`. The widening removed was also **pure cost**: no pre-existing test can cover a path
that did not exist, so FULL bought no coverage the clauses do not already buy.

**Measured effect** — same 40 trunk commits, baseline selector vs patched:

| | FULL | narrow |
|---|---|---|
| baseline (trunk) | 8 / 40 (20 %) — **7 of them `added-unmapped`** | 32 |
| **patched** | **3 / 40 (7.5 %)** — 2 genuine `unmapped`, 1 `full-trigger` (`install.sh`) | **37** |

> Note on survivorship: measuring over *trunk* commits **under-states** the problem, because the
> added-file lands are precisely the ones that failed and therefore never reached trunk. The
> unbiased population is *attempted* lands, where 33 of 39 failures ran the FULL tier.

**Landability — the binding constraint, discharged.** The patch touches `scripts/gate-select.sh`
(status **M**, not A) and `tests/gate-select.bats`. Run through the selector, its own landing
range selects **4 suites, 1 direct**:

```
tests/gate-select.bats  <- literal|naming|closure|stem|suite   (DIRECT)
tests/land-gate-cas.bats <- stem
tests/ship-land.bats     <- stem
tests/install-wire-hooks.bats <- install-glob
```

It lands through the **normal scoped path** — no healthy full gate, no operator command, no kill
switch, no bypass. This is the property that makes it not-patch-#165.

**Verification actually run this session:** all four selected suites green —
`gate-select 23/23`, `install-wire-hooks 7/7`, `land-gate-cas 9/9`, `ship-land 32/32`
= **71/71, `not ok` = 0**. The three new tests are **sabotage-proven**: restoring the deleted
rung turns exactly those three RED (5, 6, 7) and nothing else — they are load-bearing, not
decorative.

**Rollback:** revert the commit; the rung is two lines. Kill switch unchanged
(`SHIP_LAND_GATE_SCOPE=full`).

---

## 3. Durable architecture

The keystone is **necessary but not sufficient** — the narrow tier still fails 46 % of the time.
Ordered by dependency; each step is independently landable through a scoped gate.

**K2 — a CUT is not a RED. ✅ LANDED `c605a2e` (2026-07-26), content-verified.**
Both layers now take the verdict from the **TAP body**, never the exit code.

**Why the obvious patch would have failed silently.** The natural implementation — treat
`rc == 137 || rc == 143` as a cut — **cannot work**, and would have looked correct while doing
nothing. bats runs `exec bats-exec-suite | bats_test_count_validator | formatter` under
`set -o pipefail` (`bats:501,517-524`), and `bats_test_count_validator` returns **1** on a
truncated TAP stream; under `pipefail` the rightmost non-zero status wins, so a **SIGKILLed
suite surfaces as plain `1`** — never 137 or 143. Exit-code cut-detection is impossible here.
The `not ok` count is the only honest discriminator. *(This was surfaced by a keystone panelist
and corrected the lead's own drafted patch, which had used the signal test.)*

- `ship-land.sh` `run_bats_all`: `rc != 0 && notok == 0` ⇒ one exoneration re-run in a fresh
  TMPDIR — the appeal `run_scoped_suite:252` always had and the FULL tier lacked, which is why
  the FULL tier failed 33 of its 34 runs. The cut is recorded to `flakes.jsonl` as
  `cut-not-red` so it stays legible rather than vanishing. A real `not ok` is still RED with no
  free retry.
- `postland-verify.sh:150`: the same TAP stamped `verdict:"red"` via the fabricated
  `failing=tests/` sentinel. A cut now stamps `cut` — unearned-green avoided,
  deploy-blocking-red avoided, and the tree stays unstamped-green so the **next sweep retries
  it**. No bisect, no page: you cannot bisect a machine event, and paging on one trains the
  operator to ignore pages.

> **THE THIRD SYMPTOM — this defect also froze DEPLOYMENT, which nobody had connected.**
> The red stamp is what `deploy-live.sh` reads. With every post-land run cut and stamped red,
> **no green stamp could ever exist**, so the sanctioned deploy path refused permanently.
> Measured verbatim before the fix:
> ```
> deploy-live: REFUSED — no GREEN stamp among the newest 200 commits of origin/main
>              — nothing is safe to deploy
> ```
> `~/.claude` symlinks the shared checkout, so the **live hooks and scripts of the whole fleet
> could not advance** — landing and deploying were both blocked by one misread exit code.
> (The keystone itself did not need this: `GATE_SELECT` resolves to `${SCRIPT_DIR}/gate-select.sh`
> — the landing worktree's own copy — so it takes effect for every session on its next rebase.)

Tests are **sabotage-proven** on both layers: reverting either detection reddens exactly the
CUT test and leaves the real-red control green (`ship-land.bats` 34/34,
`postland-verify.bats` 16/16).

**K3 — bound or split the `closure` clause (the second widening path — M-shaped changes).**
The keystone fixes **A**-shaped changes (added files). It does nothing for **M**-shaped ones,
and there the breadth comes from clause (c), `closure` (`gate-select.sh:316`). Surfaced by the
originating session and **independently re-measured here** on the now-landed range
`origin/main~2..origin/main` — a *pure-M, two-file* change (`M bin/cc-backlog`,
`M tests/cc-backlog.bats`):

| metric | value |
|---|---|
| suites selected | **55 of 124** |
| tests selected | **989 of 1,749 (57 %)** |
| suites carrying the `closure` clause | **55 of 55** |
| **suites reachable ONLY via `closure`** | **39 of 55 (71 %)** |

Other clauses contribute 15 `stem`, 7 `literal`, 1 each `suite`/`naming`/`install-glob`.
`bin/cc-backlog` is a leaf CLI invoked by `cc-reaper`, `cc-dispatch`, `cc-blockers`,
`cc-digest`, `autonomy-sweep`, `boot-resume`, `operator-readout` and the desk scripts, so its
transitive closure reaches most of the desk corpus. The relation is unbounded-depth: **a suite
that merely *reaches* the changed path is weighted the same as one that *tests* it.**

**Calibration — this is an optimisation, not a blocker.** That 55-suite gate **landed
successfully at 07:28:02Z** (`exit:0`, `hold_s=161`). So closure breadth is *wasteful, not
fatal*, and K3 ranks **below** K2. The right lever is a **depth bound** (direct callers, not
transitive) or a **direct/indirect split** where indirect suites are sampled or deferred — and
the primitive already exists: `gate-select.sh --direct` encodes exactly that distinction and is
already consumed by `run_scoped_suite` for flake-exoneration.

*(Method note, worth keeping: `--explain` writes to **stderr**, so attribution needs
`2>&1 >/dev/null`. And attributing a suite to "closure-only" requires filtering to lines
containing ` <- ` first — the selector also emits 55 non-attribution lines that otherwise
pollute every suite's clause set and silently produce "0 closure-only".)*

**K4 — cap UNION-SCOPE re-gate amplification (newly surfaced this session, measured live).**
On a stale-gate re-round (`exit 42`), `run_gate` unions your range with `FIRST_BASE..<new base>`
— the trunk delta siblings landed while you gated (`ship-land.sh:322-325`). So **your gate cost
compounds with whatever landed during your gate.** Measured on this session's own land, at the
moment it happened:

| | suites selected |
|---|---|
| my own range (`merge-base..HEAD`) | **4** |
| after one sibling landed mid-gate — the union actually re-gated | **57** |

**A 14× cost increase caused entirely by someone else's land.** This is a positive-feedback
term and a livelock mechanism in its own right, distinct from the others: the longer your gate
runs, the more siblings land, the more expensive your *re*-gate, the longer it runs. It is the
mechanical bridge from `exit 42` (23 occurrences) to `exit 6`.

The union's safety rationale is **real and must be respected** — the *composed* tree can break
where neither change alone does, which is exactly what a CAS re-round exists to catch. But the
cost is currently unbounded. Defensible narrowings, in order of conservatism: (a) union only the
**interaction set** — suites selected by *both* ranges, plus my own — since the sibling's own
suites were just proven green on trunk by its own gate; (b) cap the union's contribution and
defer the remainder to the post-land net (once K2 makes that net actually work); (c) leave as-is
but make it *visible* — today a 4-suite land silently becomes a 57-suite land with no log line
saying why.

**K5 — bound the in-lock gate.** The FULL-mode fallback holding the machine-wide mutex is the
worst amplifier once contention starts. Lowest priority: it is a *consequence* of expensive
gates, and the keystone plus K3/K4 remove most of the expense.

**On the five options.** The 2026-07-25 unlocked-parallel design is **correct and must not be
reverted** — it removed an N × suite-time queue. Its flaw was never parallelism; it was that
*the thing being run in parallel was 1,749 tests*. Therefore:

- **Honest scoping (option 4) — ADOPT.** This is the keystone plus K2. It attacks the cost, not
  the schedule, and it is the only option that is landable without first being landed.
- **Serialize (1) — REJECT.** Re-creates the 40-min queue the current design was built to kill;
  and the in-lock fallback already demonstrates, live, how badly a serialized full gate behaves.
- **Cap concurrency (2) — SECOND-ORDER.** Worth doing only after K2; with narrow gates the
  contention it manages largely disappears.
- **CI offload (3) — WRONG SHAPE HERE.** 109 of 124 suites are non-hermetic and read/mutate the
  operator's live `~/.claude`; they do not have a CI-portable environment to run in. Hermeticity
  is a prerequisite, not a consequence.
- **Resumable gate (5) — HIGH VALUE, LATER.** A 26-minute green run being discarded with no
  record is a real defect, but it is a mitigation for long gates; the keystone removes most long
  gates outright.

**Non-code remedy (zero gate, operator-owned).** No committed script kills gates broadly —
verified by grep over `bin/ scripts/ hooks/`; every hit is targeted-by-pid teardown or a test
fixture. The kill loops are **ad-hoc commands typed by agent sessions** (one captured live:
PID 26727, `/tmp/wt-close-harden`, `kill -TERM` over every `ship-land.sh` and every
`bats-core/(bats|bats-exec)` on the machine, then its own land). The remedy is a standing
prohibition plus, if wanted, a PreToolUse guard that refuses an unscoped kill of another
session's gate. **Wiring a hook is C10 operator-owned — propose, never self-edit.**

**Items dissolved** (≥3 target met): `3c6bf04ba842` (close as fixed — zero code),
`9c5d0ba74e79` (merge into K2), `f8e40b4c577d` (keystone + K2), the false-RED half of
`a0718a5d78b3` and `77738605376f`, and the strand-generator behind `35de32d78364` /
`85de64e3ce08`.

---

## 4. Landing sequence for the stranded patches

**Ground truth first — the filed counts were wrong.** 190 truly-stranded distinct patches
across 273 branches (not 209 across "164 + 45"); 208 of the 481 unlanded-commit branches are
ship-land's own backup refs and must be excluded, not landed.

1. **Do not land backup refs.** `ship/backup-*` and `preland-backup-*` are safety artefacts.
   Filter them out before any sequencing.
2. **Drop content-duplicates.** Compare `git patch-id --stable` against trunk; 7 are already
   landed by content on a 400-commit sample alone. Re-landing them creates conflicts for no gain.
3. **Order smallest-diff first, and by selector cost** — sort candidates by what
   `gate-select.sh` picks for their range. Post-keystone, ~92 % select narrow; land those first,
   in parallel, since the unlocked design already supports it.
4. **Batch the FULL-tier remainder.** The arithmetic forbids one-at-a-time: 190 lands × a 20–53
   min full gate is 60–160 hours of serialized gate time. The residual FULL set (files under
   `lib/`, deletions, renames, `install.sh`) should be **composed into a few octopus batches**
   that pay the full-gate cost *once per batch*, not once per patch.
5. **Orphans** (branch with no worktree) need no recovery ceremony — the commits are in the
   shared object store; land the branch ref directly. The worktree was never the artefact.
6. **Land the keystone and K2 before touching the backlog.** Draining 190 patches through the
   pre-keystone selector would put nearly all of them into the 97 %-failure FULL tier.

---

## 5. THE 0-GREEN-STAMP DEADLOCK — closed 2026-07-29 (backlog `10941179f8ec`)

Three hypotheses were filed and retracted before this one. Recording the chain, because each was
refuted by measurement rather than by argument:

| # | Hypothesis | Verdict |
|---|---|---|
| 1 | **Load** starves the corpus | **REFUTED** (RESTART-BRIEF §6) — reds at load 9.34 in the same window a sibling landed 2307/0 |
| 2 | **PATH**-dependence in the daemon env | **REFUTED** — a verifier carrying the fix (`873e646b`) still stamped red |
| 3 | postland's **reused worktree / custom TMPDIR** | **OBSOLETE** — land-pipeline-v2 (`8d50f953`) mints a fresh cell per run; still 0 green in the 7 post-v2 stamps |

### The actual cause: the retry ladder counted OUR OWN bound as a failure

`scripts/postland-verify.sh` bounds each ladder re-run at `FILE_TO=300s` and scored it
`[ "$rc" -eq 0 ] || fails=$((fails+1))` — **any** non-zero, including rc 124, which the script's own
`bounded()` helper documents as *"rc 124 = OUR bound fired"*. Consequence: **a suite whose solo
runtime exceeds the bound can only ever be convicted, never exonerated.** Both retries return 124,
`fails` reaches 3/3, and the tree is stamped a *reproducible RED* that no re-run can clear. A red
stamp is exactly what `deploy-live.sh --auto` and ship-land's `postland_net_live` read — hence
**33 stamps, 0 green, ever**, and a live layer 32 commits behind trunk.

Every *other* rc-124 site in the same file already refuses to read its own bound as evidence — C22
prelint ⇒ cut, `confirm_hang` ⇒ the HUNG discriminator, `classify_hang` case 1, the stall unify.
The ladder was the sole exception, and it was the one on the deploy-blocking path.

**Evidence (all disk truth, 2026-07-29):**

1. `flakes.jsonl` 2026-07-28T19:39:38Z — `tests/postland-verify.bats`, `"signal":"exit 124 /
   notok=0"`, `"loadavg":"6.61"`, `"outcome":"cut-not-red"`. The suite blows the 300 s bound at
   **load 6.6**, and the *land* gate filed that identical signal correctly as a cut.
2. The last 5 post-v2 REDs all name **one** suite — `tests/postland-verify.bats` — at loads
   4.01 / 6.05 / 9.38 / 9.40 / 11.76. Load-independent by inspection.
3. Measured solo: 51 tests, ~60 s/test ⇒ **~50 min, 10× the bound** — and that is at *normal*
   priority, while the ladder runs at `nice -19` + `taskpolicy -c background`, so it is a lower bound.
   Confirmed live, in production, mid-investigation: the running corpus's own
   `bats-exec-file …/tests/postland-verify.bats` (pid 24914) was **1 h 17 min into that one file and
   still going**, against a ladder bound of 300 s. Not a projection — a `ps` reading.
4. The convicted suites are exactly the heaviest ones — `waiting-recycle` 98 tests, `cc-reaper` 80,
   `ship-land` 74, `cc-backlog` 61, `postland-verify` 51. The bound, not the tree, was deciding.
5. Onset correlates with size, not with any tree change: the suite went 40 → 61 `@test` on
   2026-07-28 (`d84ae514`, v2 semantics); the first conviction is 2026-07-28T20:53.

### The fix (C23)

1. **rc 124 in the ladder is an abstention, not a fail** — following the script's own
   `PRELINT_UNPROVEN` idiom: neither convicted nor cleared ⇒ the run downgrades to a **CUT** and is
   retried next sweep (`LADDER_UNPROVEN`). Attempt 2 is skipped on abstention — under an identical
   bound it would abstain identically, so it buys no information and costs another bound.
2. **The re-run is the failing TEST, not its whole file** (`bats -f`, anchored + metachar-escaped),
   so the bound can fit what it bounds: seconds instead of ~50 min. A filter matching nothing exits
   `1..0` — a non-verdict that would exonerate for free — so a `tap_plan > 0` guard falls back to the
   whole file under a separate, larger `RETRY_TO` (5400 s). Seam:
   `POSTLAND_RETRY_GRANULARITY=file`.

Granularity measured on an instrumented fixture (one file, a failing test beside a witness test that
records every execution of itself): **test-granular = 2 witness runs** (the corpus + C20's bisect,
which legitimately re-runs the whole file to locate a culprit — the retries contribute zero) versus
**file-granular = 4** (corpus + two whole-file retries + bisect). The delta of exactly 2 is the two
retries, so the seam is doing precisely what it claims and nothing else.

Stated trade-off: an *intra*-file ordering dependence now reads as a flake rather than a red. The
ladder already discarded *cross*-file ordering by re-running the file alone; this widens the same
assumption one level, and a permanently un-exonerable suite is the worse failure.

## Reading rules this investigation had to obey (and one it nearly broke)

- **CUT ≠ RED** — read the `not ok` count, never the exit code.
- **A bound you imposed is never evidence about the subject** (§5). Ask *whose* bound fired before
  scoring an rc. And a bound the re-run cannot fit inside is not a bound — it is a verdict.
- **143 = SIGTERM, 137 = SIGKILL** — different causes; never conflate.
- Verify landings by **content**, never `rev-list --count`.
- A `pgrep -f` negative is not death — positive-control the detector.
- **Near-miss, recorded honestly:** `Terminated: 15` lines inside full-suite logs looked like
  external kills of the gate. They are mostly **tests killing their own `sleep 30` / `sleep 60`
  helpers** — benign, in-test behaviour. The genuine external-cut evidence is the per-suite
  `Killed: 9` at `ship-land.sh:252` and the 7 same-second cross-repo clusters, not those lines.
