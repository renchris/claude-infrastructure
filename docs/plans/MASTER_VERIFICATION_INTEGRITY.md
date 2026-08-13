---
status: open
---

# MASTER: verification integrity — the instruments that decide red and green are wrong

**Condition key:** `master-verification-integrity` · **Live members 2026-08-12 (measured after the apply):** 31 (30 open · 1 blocked)
**Inventory:**
`cc-backlog list --all --json | jq -r '.[]|select(.condition=="master-verification-integrity" and .status!="done")|"\(.id) \(.status) \(.title[0:90])"'`

**Why this is ONE effort, and why it should be worked EARLY.** Every other wave's claim of done rides
on these instruments, and they are measurably unreliable in both directions: **9 of 15 land-gate
ratchet arms collapse a lint's exit 2 (could-not-run) into `gate_red` (tree-is-bad)**; a SIGKILLed bats
run is misreported as GATE RED although signal-kill is a third state; the `bats-assert-liveness` arm
fails OPEN on every non-verdict because `ship-land` reads stdout instead of the exit code; **89
non-final bare-`!` assertions are structurally dead across 28 test files.** A wave that lands a fix and
reads a false verdict has not landed a fix.

## Phase 0 · Agent Team Orchestration

**EXECUTION LOCUS PER WAVE.** S = dispatched handoff session (the default) · T = in-session teammates · L = lead-inline.

🚨 **SUPERSEDED FOR THE LOCAL DRAIN (2026-08-13): read every `S` below as `T`.** This table was
authored under the one-session-per-wave model. The non-cloud backlog is now worked by THE LOCAL DRAIN —
a single standing session whose entire purpose is that it occupies **one** of the ~15 concurrent slots
for its whole life (`BACKLOG_SELF_DRAINING_2026-08-12.md:392`: *"One slot, indefinite duration — because
the bottleneck is concurrent sessions (~15), not session length"*). Firing a dispatched session per wave
spends a second slot and defeats the mission. Work every wave with **teammates INSIDE the drain session**
(`Agent({name})`, worktree-isolated, ≤150-line briefs, each torn down with a structured
`shutdown_request` — a plain-text broadcast leaves an orphaned pane and worktree), and recycle at the
EFFORT boundary via `handoff-fire.sh --recycle` — same pane, fresh context, no new slot. The `S` markers
below are left in place as the historical record of how these waves were originally scoped.

| Wave | Execution locus | Deliverable | Depends on |
|---|---|---|---|
| **V1 · three states, not two** | **S** | could-not-run, signal-killed and failed are distinct everywhere | — |
| **V2 · de-vacuum the corpus** | **S** | no assertion passes because it cannot fail | — |
| **V3 · blind instruments** | **S** | each lint's judged population equals its stated scope | — |
| **V4 · chokepoints** | **S** | a class fixed once cannot re-enter unnoticed | V2 |

**Lead context budget:** ≥50%. **Succession point:** after V2 — de-vacuuming is mechanical and bulky;
the blindness work is judgment.

## Sub-waves

### V1 · A non-verdict is not a failure (and not a pass)
The recurring shape: an exit code that means *"I could not ask"* lands in a `*)` arm beside *"the
answer was no"*, and both read as red — or worse, as green. Members: the 9 ratchet arms collapsing
exit 2; SIGKILL reported as GATE RED; `pipefail-sigpipe-lint`'s exit 2 unreachable on `--scan` because
`hits=$(scan) || true` swallows it; `utc-stamp-lint:238`'s `|| rc=1` collapsing `lint_dir`'s return 2
into a tree-red. **"I could not ask" must never read as "the answer was no"** (memory:
`enum-new-member-falls-into-fail-closed-default`, `threshold-must-separate-fatal-from-survived`).

### V2 · De-vacuum — an assertion that cannot fail is not an assertion
89 dead bare-`!` assertions across 28 test files (31 in `cc-reaper.bats` alone): in bash, `! cmd` is
exempt from errexit, so a negative written that way only fails as the LAST line of a body. Also here:
`scripts/banner-gate-redproof.py` is an UNWIRED red-proof; a committed positive control that replays a
MOVING ref proves nothing about the past.

🚨 **Every fix in this sub-wave must be RED-PROVED against pristine trunk.** The predecessor session
lost time to a harness that extracted one shell function without the helper it calls, making every case
return UNKNOWN and pass vacuously — **against the broken binary too**. One mutant per SITE, and a
control that can genuinely fail (memory: `verification-harness-vacuous-pass-traps`,
`per-site-mutation-attributes-coverage`).

### V3 · Blind instruments — the judged population is not the stated scope
`own-set basename collapse` in test-hermeticity / git-identity / utc-stamp / tsv-pad: the own-set is
keyed on basenames, so a file's namesake exempts it. The hermeticity lint is blind to
`boot-resume-launch`'s capacity gate. `unattended-path-lint.sh` reads only the SECOND arm of an
alternation case label (`githooks|launchd)`), so the first arm is unchecked. `gate-select`'s D/R/C rung
still keys on `is_prose`, so DELETING prose outside `docs/` answers the wrong question.
`CC_PERMGATE_SET` / `CC_TSVPAD_DIRS` move a lint's judged population without moving its stated scope.
A lint's blindness composes — one blind spot hides the next defect (memory:
`lint-blindness-composes-and-hides-the-next-defect`).

### V4 · Chokepoints — a class fixed once must not re-enter
There is NO CHOKEPOINT for the unescaped-backtick `@test` name class that was fixed across `tests/` on
2026-08-10. Detection in its own suite is not enforcement: **gate the event that IS the act**, and let
the gate allow its own cure (memory: `enforcement-must-live-at-the-chokepoint`).

## Definition of done
A land verdict is trustworthy: no arm collapses could-not-run into red, no assertion in the corpus can
pass vacuously (proved per site by a mutant), every lint's judged population equals its documented
scope, and each class fixed in this wave has a chokepoint that would refuse its return.

## Status log
- **2026-08-12 — created by W2 of `BACKLOG_SELF_DRAINING_2026-08-12.md`.** 34 rows joined by
  `group.py`. Recommended FIRST of the ten: every other wave's DoD is measured by these instruments.

- **2026-08-13 — THE LOCAL DRAIN, effort 2 opened.** Store baseline at start: **470** non-cloud rows
  (`master-verification-integrity` holds 29, of which **20 are non-cloud and mine**; the other 9 are
  `venuePlan=cloud`). Condition claimed as one lease on `f295605eec01` (`verdict=clear`). Twenty rows
  fanned out to five read-only triage agents for a currency verdict each, before any code was written.

  **V0 · THE MASTER INSTANCE OF THIS CONDITION, found while landing an unrelated docs commit.** This
  effort exists because "the instruments that decide red and green are wrong in both directions". The
  largest live instance is not in any of the 20 rows — it is the verifier that owns the full-suite
  claim for this repo, and it is **stuck in a state its own source predicted**:

  - `postland-verify`'s last six stamps are **5 × `cut` + 1 × `hung`, zero green**, each after
    42 min–2.5 h of work (`run_s` 2533–8970). Every recent stamp records `corpus=null` — a verdict
    with no denominator, which `postland-verify.sh:2485` itself calls "THE STAMP'S DENOMINATOR".
  - Cause, from `~/.claude/autonomy/postland/runner.log`, **11 times in 14 h**: `corpus TRUNCATED —
    zero not-ok in a non-zero run — the run was KILLED by signal 15 [since 22:23Z: signal 9] from
    OUTSIDE this runner (sender unidentified) - not the tree`.
  - **`cut` is the CORRECT verdict**, not a bug: the code deliberately refuses to convict a tree on a
    truncated run (`classify_hang`/`classify_failures`, case (a)). The defect is downstream, and
    `postland-verify.sh:1533` states it verbatim: *"With every run cut, NO GREEN STAMP CAN EVER EXIST,
    so deploy-live refuses forever."*
  - **Measured live, exactly as predicted:** `deploy-live: waiting — no GREEN tree is a DESCENDANT of
    live HEAD a54569dbf020 (the newest one, 8f1726cfbe8e, is BEHIND it); lag 10 commit(s) / 2h, inside
    the degrade budget (25 / 6h)`. It reads *inside budget*, which is why nothing has alarmed — but it
    cannot leave that state, because the only thing that would clear it is a new green stamp and every
    run is cut. The budget will breach with nothing to advance to. **This blocks the live layer for the
    whole machine, not just this session.**

  **Ruled out, so the next session does not re-derive them:** not the OS (59% memory free, zero swap,
  no jetsam kills in 12 h); `scripts/gate-cleanup.sh` **is** worktree-scoped (`:23` — "scope REAL
  rather than textual: the worktree is a filesystem fact"); and `hooks/validate-bash.sh:558` already
  DENIES a worktree-unscoped `pkill -9 -f bats-core/bats` at the tool call, citing the 2026-07-26
  false-RED epidemic (`a0718a5d78b3`) as its measured cause. So the known agent-side vector is CLOSED —
  the sender executes outside that guard, which is precisely why it is unidentified. Remaining suspects
  are the launchd jobs that can signal without passing validate-bash: `cc-gc`, `worktree-gc-infra`,
  `team-orphan-reaper`, `teammate-reap-alarm`, `devserver-gc`, `lead-supervisor`, `dispatcher`,
  `capacity-alarm`. **NOT YET A MEASUREMENT — do not act on that list.** The kill intervals
  (~61 min, several times) most likely reflect postland's OWN relaunch cadence, not the killer's.

  **The instrument cannot close its own loop**, and that is the V1/V3-shaped fix: a runner that reports
  *"killed by someone, I don't know who"* can never name a culprit, so this recurs indefinitely. Sender
  attribution is the prerequisite for any cure, not an optional diagnostic.

  **Same shape as row `8efd655b0fe1`** (hermetic CI: a matrix shard CANCELLED mid-run by a runner
  shutdown signal, ~41 suites of evidence lost, measured 4-for-4). One cause may generate both.

  **Two instrument traps hit this session, both of which produced a false reading before being caught:**
  1. `grep -r` over `~/.claude/bin|scripts|hooks` returns **EMPTY** — those are per-file symlinks into
     the checkout and `grep -r` does not follow symlinks found during a walk. A "no sites found" there
     is a blind instrument, not an absence. Grep the checkout's real files.
  2. Fanning out 5 triage agents took load to **2.03/core — exactly `cc-bats`'s refusal threshold**
     (rc 75, empty stdout, a DEFERRAL not a pass). On this box **fan-out and bats verification cannot
     overlap**; they must be sequenced.

  **`🚀` attribution (not this effort's loose end).** The ledger's `LIVE_ADDS=1` is
  `tests/lr-reset-poller-engagement.bats`, added by the PREDECESSOR's effort-1 commit `4ba91ad95`.
  Open row `4e6a51df2a84` already covers the class: `tests/` is not in `~/.claude`, so **no converger
  can ever carry it**. Attributed, not driven, and never laundered into a `✅`.

  Landed this session so far: **`bf3db4326`** — 26 of 39 waves across the ten `MASTER_*.md` plans
  carried `S = dispatched handoff session` as their execution locus, authored before the mission
  pivoted to one standing session. A successor following any of those tables would spend a second
  concurrent slot and defeat the drain's single invariant. Purely additive (110 lines, 0 deleted); the
  historical `S` markers are preserved as the record of original scoping.

  **CLOSED THIS EFFORT (2), both on content, neither by running its row's remedy:**
  - `918e9bac60b6` — ALREADY-DONE. A DISPROOF row whose disproof is CONFIRMED: `scripts/unattended-path-lint.sh`
    exists (blob `808a895d82d16f77ec398852daf1089247acd3b3` on origin/main), its header cites its own
    generator `cb6701bf2217` at `:26`, it IS wired into ship-land (`SHIP_LAND_UNATTENDED_LINT`,
    `ship-land.sh:2558`, selftest guard `:2576`), and `--selftest` discriminates in both directions
    (`:259`). **One correction that does not change the verdict:** the row cites the wiring at `:1757`
    and smoke at `:1976`; live lines are `:2551-2576`. The row's line numbers were stale, the wiring is real.
  - `3309486727cf` — DUPLICATE of `f295605eec01`, closed as store hygiene and explicitly NOT as fixed.
    Both name one defect: `assert_twinkle_tables_paired` (`gen.py:2319`) compares only lengths
    (`:2329`), blind to VALUE. `f295605eec01` survives because it is strictly richer — it carries the
    assertion band (max floor ≤ .60, `STAR_TWINKLE_MAX` ≥ eligible low-field count,
    `len(STAR_PERIODS)` ≥ 6) and the red-proof (restore .70/18/4).

  **VERIFIED REAL, with its premise re-measured (do not re-triage):** `5d6dcbe8d462`. All three claims
  hold — nightly's globs are `scripts/*gate*.sh` / `*lint*.sh` (`nightly-regression.sh:65-66`) and a
  `.py` matches neither; `--check-anchors` does not exist (0 hits); `tests/anti-vacuity-contract.bats`
  census is scoped to `tests/` (`:62`). ⚠️ **A naive grep says the harness IS referenced from that
  suite — the reference is a COMMENT** (`:25`, *"OUT OF SCOPE, deliberately … Filed rather than
  smuggled in here"*). Mention ≠ invocation; this is the same trap as row `5456e4cba2b5`, and it nearly
  produced a false ALREADY-DONE here.

  **THE DENOMINATOR IS SOUND — audited, because it looked vacuous.** `cc-backlog list --open --json`
  returns **539** open rows with HETEROGENEOUS keys: `venuePlan` is present on only **340** (absent on
  199, 37%), while `venue` is present on all 539. So the mission filter
  `select((.venuePlan // "unlabelled") != "cloud")` defaults 199 rows to non-cloud, which reads like a
  vacuous filter. **It is not.** Cross-tab: 271 `venue=local/plan=local` · 199 `venue=local/plan=absent`
  · 45 `venue=local/plan=cloud` · 24 `venue=cloud/plan=cloud`. **Zero** rows are plan-absent AND
  `venue=cloud`, so the default is safe. **Keep `venuePlan` (470). Do NOT switch to `venue` (515)** —
  that wrongly adopts the 45 rows planned for the cloud venue.

  **THE INTAKE LEAK HAS A MECHANISM, not just a rate.** Closed 2 + filed 1 should read 469; the store
  read **470**. Measured cause: in 90 minutes siblings minted four rows, two of them AUTOMATICALLY by
  the re-land generator on a FAILED sibling land — `cdeb77e34952` (ship-land exit 143/SIGTERM) and
  `cfa642b48fc7` (exit 5). Lands fail because the box is saturated, so **load manufactures backlog
  faster than a drain closes it**. This is the same cancellation the predecessor measured, now with the
  generator visible. The predecessor's remedy row `b15a2984d134` (ship-land's falsifier attach is
  swallowed) is still open.

  **A SELF-FALSIFICATION worth keeping.** The box went to battery at 21:16 PDT (98%; now 38%), and an
  already-`blocked` row `8177e9ba98e6` asks the operator to plug in, citing postland being unable to
  stamp green. Tempting single cause — and **false**: postland's SIGKILLs began 2026-08-12T22:23:58Z =
  **15:23 PDT, six hours BEFORE** the battery switch, with SIGTERM cuts back to 15:02 PDT, and `pmset`
  records no thermal and no performance warning. Power will not clear the kill-loop. Filed
  `782607797fc5` (privileged signal trace — genuinely operator-gated: macOS exposes no unprivileged way
  to learn a signal's SENDER) stands as a SEPARATE cause from `8177e9ba98e6`. **Do not merge them.**

  🚨 **TRIAGE FAN-OUT FAILED — 5 agents, 0 deliveries, BOTH channels.** Five named `Agent({name})`
  triage agents were spawned over the 20 rows. They emitted `idle_notification` repeatedly and
  delivered **nothing** by message, then nothing by file after being re-briefed with an explicit
  Delivery path. `TaskStop` de-registered all five (`in_process_teammate`). **Both closes above came
  from the lead verifying rows directly, in a fraction of the elapsed time.** Memory
  `shutdown-request-is-not-an-actuator` already prescribes the Delivery-path field and records the file
  channel at 4/4 vs SendMessage 0/4 — here even the file channel returned 0/5. **NEXT EFFORT: triage
  the cheap rows inline first (a content read is minutes), and treat fan-out as optional
  breadth, never as the critical path.** A named agent is a persistent teammate whose findings must be
  REQUESTED, not awaited — and requesting them may still return nothing.

  **CURRENCY VERDICTS — verified inline against source, implementable without re-triage.** All four
  are **REAL** (premise holds today); each fix below is fully specified, so the next session writes
  code rather than re-deriving.

  | Row | Verified defect (file:line) | Fix, already proven elsewhere |
  |---|---|---|
  | `4239f02465cb` | `scripts/utc-stamp-lint.sh` — `lint_dir … \|\| rc=1` on **both** branches of the `CC_UTC_OWN` conditional collapses `lint_dir`'s return **2** (could-not-run) into `rc=1` (tree-red). | Discriminate 2. The same file already gets this right for the empty-target case (`scanned -eq 0` → "NOT a clean verdict"), so the concept is present and this site was missed. Port the 3-state shape from `scripts/test-hermeticity-lint.sh` (:92, :180). |
  | `6557a992d498` | `scripts/test-walltime-lint.sh:92` `in_allowlist() { printf '%s\n' "$2" \| grep -qxF "$1"; }` — a bare grep, so a lost fork (rc≥2) reads as **"not in allowlist"** and FABRICATES a TIMEBOMB. `future_dates()` :99-102 is an unchecked 4-stage pipeline (`grep -vE \| grep -oE \| sort -u \| awk`). | Port **both** cited commits, and both are real: `afaf40deb` *"a check that could not RUN is a non-verdict, not a leak"* + `ed4e6c6a5` *"retry the pure predicates before condemning the run"*. **Consequence confirmed:** `tests/test-walltime-lint.bats` IS in `scripts/host-suites.manifest:172`, so `deploy-live` runs it and a false RED gets filed automatically. |
  | `09f087a7f3d8` | `scripts/terminal-bench.sh:167` — `ps -eo pid=,comm= \| awk '{n=split($2,a,"/"); …}'`. `comm=` is **last**, so its value is complete and its **spaces split**; `$2` is only the first token. An fnm/Application-Support-installed binary is never found, and the bench **silently measures nothing**. | The `$2..NF` rebuild proven in `273df7cd6` *"the actuator's cohort test could not name a single real node process"*. ⚠️ Note the irony to avoid repeating: `:163-164` carries a careful comment citing `pgrep-f-matches-agent-briefs` — the author guarded one argv trap and fell into a neighbouring one. |
  | `86488ad1c966` | **NOT YET LOCATED — partial.** The alternation-arm gap in `scripts/unattended-path-lint.sh` was not pinned by static grep; `:570` documents that a case label is noise-not-dependency, `:743` holds a `case`-based membership helper. | Needs a constructed fixture in a `mktemp -d` run through the lint to pin the arm that escapes. **Do not close on the greps above** — absence of a grep hit is not absence of the defect. |

  Rows closed this effort: **2**. Filed: **1** (`782607797fc5`, operator-gated). Condition non-cloud:
  **20 → 19**. Store non-cloud: **470 → 470 (FLAT — sibling intake cancelled the net, as above).**

  **`0f74f41042c5` — REPRODUCED LIVE, accidentally, while landing an unrelated docs commit.** The row
  says unattended-path-lint's finding set is a function of the caller's live `$PATH`
  (`installed_somewhere`), so *"author's worktree green, landing box red"* is reachable from a
  binary-inventory difference alone. **Observed, on a commit touching exactly ONE markdown file:**
  `ship-land` refused with `✗ gate: unattended-path RED — a file THIS LAND CHANGES invokes a binary by
  bare name that is unreachable on the PATH it will actually run with` → `✗ ship-land: GATE RED — not
  pushing`. The same lint run standalone in the same worktree, same second, exited **rc=0 with empty
  output**; an immediate `ship-land` retry with a **byte-identical tree** then landed cleanly
  (`387bb02c1`). So the gate is **nondeterministic across invocations with no tree change** — a land
  verdict that flips on ambient state is exactly this effort's condition, and it blocked a real land.
  **Upgrade the row from "reachable in principle" to "observed 2026-08-13"; it is no longer only a
  divergence risk, it is an intermittent false RED on the landing path.** Note the diagnosis trap: the
  RED names *"a file THIS LAND CHANGES"* while the only changed file was `.md`, so the message's own
  scope claim is untrue in the failing case — check whether the judged population is the diff at all.

  **STATE AT THIS ENTRY (box on battery, 33% / ~52 min — everything below is landed, so power loss
  costs context only).** Landed + content-verified this session: `bf3db4326`, `7ac98a6c1`, `9625360f4`.
  Next actions in priority order for whoever resumes: (1) implement the three fully-specified fixes
  above, each with a per-SITE mutant — `4239f02465cb` and `09f087a7f3d8` are near one-liners with the
  rebuild already proven in a named commit; (2) pin `86488ad1c966` with a real fixture; (3) the two
  RED-on-trunk rows `c6c5ef54881e` / `0711d9e18934` still need an actual `cc-bats` run — they were
  never verified, and `ok=0 notok=0` from a refused run is a NON-VERDICT, never a pass.

- **2026-08-13 — first CODE fix of this effort landed: `4239f02465cb` CLOSED (`3aecd1472`).**
  `scripts/utc-stamp-lint.sh` collapsed `lint_dir`'s three-code contract (0 clean / 1 findings /
  2 could-not-run) into two, via `lint_dir … || rc=1` on **both** branches of the `CC_UTC_OWN`
  conditional. Now cased: 0 passes, 1 sets `rc=1`, anything else sets a non-verdict that exits **2**.
  The fix extends this file's OWN contract rather than inventing one — the branch immediately below
  already exits 2 for `scanned==0` and calls it *"NOT a clean verdict"*.

  **Fail-closed direction, chosen deliberately:** a non-verdict dominates BOTH a clean result and a
  finding. A run that could not judge every target has not earned the right to characterise the tree.
  Findings still print; only the exit code is withheld.

  🚨 **THE LESSON THAT GENERALISES TO EVERY REMAINING ROW IN THIS EFFORT.** All **17** pre-existing
  selftest cases called `lint_dir` **directly**, so every one of them was GREEN for the entire life of
  this bug — because the collapse lived in the **caller**. A suite that exercises the function can
  never see a defect in the code that calls it. The three added cases drive the **script** (17/17 →
  20/20) and are mutant-proved: restoring `|| rc=1` fires exactly the two new cases by name. When
  fixing the rest of this effort, **ask which layer the defect is in and put the guard THERE** — most
  of these rows are caller-side collapses, and their existing suites will look reassuringly green.

  Also worth knowing: `tests/utc-stamp-lint.bats:37` pins the selftest count by literal grep and
  fails with *"update this assertion deliberately"*. That is the `exact-count-assertion-tripwires-its-own-subject`
  shape — it reds on the suite's own GROWTH, never on a regression — but it is self-documenting and
  was ratified as designed (now `20/20`), not redesigned. 12/12 green.

  **NO LAND REGRESSION:** `ship-land.sh:2322` treats any non-zero as `gate_red`, so a could-not-run
  was red before (1) and is red now (2). What changed is that the lint is now HONEST, which is the
  prerequisite for `446fe07464e0` (9 of 15 ratchet arms still collapse exit 2 into `gate_red`).

- **2026-08-13 — the live layer CONVERGED, and it is important not to misread why.** After
  `b7f771848` the ledger reads `✅ Complete & live on trunk`, the shared checkout is at that sha, and
  all four of this session's fixes are verified LIVE **by content** (`arm_nonverdict` ×9 in
  `~/.claude/scripts/ship-land.sh`; the `$N..NF` rebuild in `~/.claude/hooks/lib/context-econ.sh`;
  `CHECK_FAILED` ×9 in the live `test-walltime-lint.sh`; `nonverdict` ×3 in the live
  `utc-stamp-lint.sh`). `deploy-live` also ran its three host-suite checks against the LIVE layer and
  all passed — including `tests/test-walltime-lint.bats`, i.e. this session's own fix re-proved where
  it actually executes.

  🚨 **But the postland deadlock is NOT resolved, and a later reader must not conclude it was.** Every
  postland stamp is still `cut` — **zero green in the preceding 6 hours, 68 cumulative kill events in
  `runner.log`**, with a run in flight. The live layer advanced through the **DEGRADED-ADVANCE** path:
  the converge budget expired, and `deploy-live` is built (dcf2f11a) to convert that standing refusal
  into *advance + page* rather than an indefinite freeze — the exact design
  `permission-gate-lint`'s header cites as the cure for the 545-refusal scar. **So trunk is live
  WITHOUT a full-suite green proof behind it.** That is the system working as designed, not the
  problem going away. Filed row `782607797fc5` (privileged signal trace to name the killer) remains
  live and operator-gated; do not close it on the strength of a converged live layer.

  The distinction generalises: **`✅ live` answers "are the bytes deployed", never "was the tree
  proved"**. Those are different questions with different instruments, and this session had them
  briefly conflated.

## RESUME HERE — effort 2 state at the 2026-08-13 pause-point (15 non-cloud rows open)

**Landed this session (all content-verified, and all four verified LIVE by content):** `3aecd1472`
utc-stamp-lint non-verdict · `3bb7935b7` comm-split ×3 sites · `c78666902` test-walltime-lint
non-verdict ×2 predicates · `b7f771848` ship-land 8 gate arms + permission-gate ratchet 15→9.
Plus the docs/adjudication commits. **Closed from this condition: `918e9bac60b6`, `3309486727cf`,
`4239f02465cb`, `09f087a7f3d8`, `6557a992d498`, `446fe07464e0`, `9183cbf21772`.**

**THE METHOD THAT WORKED, use it:** triage each row INLINE with a content read (minutes), then fix.
The 5-agent fan-out at the start of this effort delivered **0 findings through either channel** and
had to be `TaskStop`ed; every close this session came from the lead reading the row's cited files.

**THE RECURRING SHAPE, true of all four fixes:** the defect was in the CALLER, and the existing suite
exercised the CALLEE — so the suite was green for the bug's entire life. Ask which layer the defect is
in and put the guard THERE. Every fix here was mutant-proved (revert it, the new case fails BY NAME
while the pre-existing cases still pass).

**Per-row currency verdicts for what remains:**

| Row | Verdict | Note for whoever takes it |
|---|---|---|
| `5456e4cba2b5` | **REAL, and subtler than the row states — read this before starting** | `references_fire()` (`test-hermeticity-lint.sh:944`) ALREADY strips comments; that was a prior fix for this same class (header `:936-943`: 71 suites matched the raw grep, 15 prose-only, 9 latent blockers). The residual gap is **string literals in code** — `tests/cc-eligible-history.bats:224` holds `handoff-fire` inside a fixture STRING, not an invocation. ✅ The correct shape already exists in the same file: **Rule 3 is scoped by the LEG the lever gates, "never by whether the suite happens to mention the lever"** (`:52-54`). ⚠️ **HAZARD:** narrowing mention→invocation risks a FALSE NEGATIVE (a suite that really does read ambient load going undetected), which is strictly worse than today's harmless pin. Demand a two-sided proof: a string-literal-only suite must go OUT of scope AND a real invocation must stay IN. |
| `5ef0dcb22aec` | REAL | The AMBIENT check knows `handoff-fire`'s `CC_FIRE_CAPACITY_GATE` but not `scripts/lib/capacity-admit.sh`'s `CC_ADMIT_GATE`. Same rule-1 machinery; adding a second seam is mechanical once `5456e4cba2b5`'s scoping question is settled — **do that one first**, they touch the same predicate. |
| `86488ad1c966` | REAL, NOT YET PINNED | The alternation-arm gap (`githooks\|launchd)`) was not located by static grep. Needs a constructed fixture in a `mktemp -d` run through the lint. **Absence of a grep hit is not absence of the defect** — this session proved that four separate ways. |
| `0f74f41042c5` | REAL — **upgraded to OBSERVED** | Reproduced live this session: `ship-land` refused with `unattended-path RED` on a commit touching ONE markdown file, while the same lint standalone exited 0, and an immediate retry on a byte-identical tree landed. Intermittent false RED on the landing path, not merely a divergence risk. |
| `f295605eec01` | REAL | Starfield twinkle has no VALUE gate (`assert_twinkle_tables_paired`, `gen.py:2319/:2329`, compares lengths only). Assertion band + red-proof are in this file's earlier entry. Note `5d6dcbe8d462` first — the harness it would extend is itself unwired. |
| `5d6dcbe8d462` | REAL, premise re-verified | `banner-gate-redproof.py` is unwired: nightly globs `scripts/*gate*.sh` / `*lint*.sh` (`nightly-regression.sh:65-66`), a `.py` matches neither; `--check-anchors` does not exist (0 hits); `anti-vacuity-contract.bats`'s census is `tests/`-only and its mention of the harness is a COMMENT (`:25`), not a wiring. |
| `79811022b6a4` · `b449e49f1438` · `cf440684e0e1` · `f8f1b2c16fa8` · `8efd655b0fe1` · `c6c5ef54881e` · `0711d9e18934` | NOT YET TRIAGED this session | `c6c5ef54881e` / `0711d9e18934` claim suites are RED on trunk and were **never actually run** — a refused `cc-bats` returns `ok=0 notok=0`, which is a NON-VERDICT, never a pass. Run them before believing either. |
| `782607797fc5` · `05ff1e5fabc0` | FILED BY THIS SESSION | operator-gated signal trace; and the 3 CI-only reds from run 31586181611 (locale and OS platform already REFUTED — do not re-run those two hypotheses). |

- **2026-08-13 — `5d6dcbe8d462`: the row's premise is RIGHT, its prescribed remedy is WRONG for this
  harness. Corrected spec below; do not start from the row.**

  **Premise confirmed (all three claims):** `scripts/banner-gate-redproof.py` is unwired — nightly's
  step-4 globs are `scripts/*gate*.sh` and `scripts/*lint*.sh` (`nightly-regression.sh:65-66`) and a
  `.py` matches neither; `--check-anchors` does not exist (0 hits); and
  `tests/anti-vacuity-contract.bats`'s CENSUS globs **`tests/*redproof*`**, so a harness living in
  `scripts/` is structurally out of its scope. Its only mention there is a COMMENT (`:25-27`) that
  says so outright: *"OUT OF SCOPE, deliberately … has no --check-anchors mode. Filed rather than
  smuggled in here."*

  **COUNT SETTLED:** `grep -c '^@case('` = **37**. Row `5d6dcbe8d462` says 37 (correct);
  `f295605eec01` says 30 (wrong) — use 37.

  🚨 **WHY THE PRESCRIBED PORT DOES NOT APPLY.** The row calls this "the same class as the two fixed
  in 9ea31151dd94" and says the fix shape is "settled and already proven twice". The CLASS is the same
  (an unwired red-proof); the SHAPE is not. The two precedent harnesses are **declarative**: their
  `CASES` are `(name, anchor, replacement, must_break)` tuples over the subject's SOURCE TEXT, so
  `--check-anchors` is just `src.count(anchor) != 1` (`tests/cc-queue-redproof.py:177`). This harness
  is **procedural**: `CASES` is `(name, want, fn)` and each `fn` mutates LIVE MODULE STATE —
  `g.WORLD_MOD["rAsk"] = ((0,12,0),(12,6,2.5)); g.build(v())` — with only **3 of 37** cases doing any
  text substitution at all. **There are no anchors to count.** Porting the precedent verbatim would
  produce a flag that checks nothing, which is the exact vacuity the suite exists to prevent.

  **THE CORRECTED REMEDY** — same goal (catch ROT cheaply, no render/build), different mechanism:
  1. **AST-derive each case's dependencies.** Walk each `@case`-decorated function with `ast` and
     collect every `g.<NAME>` attribute access. Assert each `<NAME>` still exists on the imported
     module. A case poking `g.STAR_TWINKLE` after that table is renamed is silently inert today, and
     that is this harness's equivalent of a dead anchor.
  2. **Assert each case's `want` string is still reachable** — i.e. still appears in the gate
     vocabulary the assertions raise. A `want` no longer emitted by any assertion can never match, so
     the case can never fail: dead by a second route.
  3. **Wiring needs a decision the row does not make:** the census glob is `tests/*redproof*` and this
     file is `scripts/`. Either widen the glob to cover both directories (and say so in the census
     comment, which currently *justifies* the narrow scope), or add an explicit case invoking it.
     **Do not silently widen** — the comment at `:25` is a deliberate scoping decision with a stated
     reason, and overriding it without addressing that reason is how a guard loses its meaning.

  Not implemented this session: it is a per-case AST pass plus a census-scope decision in a subsystem
  (banner/SVG build) this session had no other reason to touch, and half-building it would leave a
  flag that returns 0 unconditionally — worse than the current honest gap.
