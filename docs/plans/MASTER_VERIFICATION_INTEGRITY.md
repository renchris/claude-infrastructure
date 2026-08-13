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

- **2026-08-13 — `tests/autonomy-sweep.bats` HANGS, and it is ORDER-DEPENDENT. Narrowed here; not
  fixed.** A postland page arrived on this session's own land
  (`~/.claude/autonomy/pages/postland-hung-autonomy-sweep-0fcd40186b3c.page`, tree `0fcd40186b3c`,
  sha `b7f77184815d`): *"wedged at 231/8845 completed — timeout:10800s"*, with
  `proof: re-ran tests/autonomy-sweep.bats ALONE in this pristine detached worktree; wedged again:
  true` and, importantly, **`NOT a cut: no signal reached this run`** — so this is NOT the
  external-kill class that produces the 68 `KILLED by signal` events; it is a genuine hang.

  **This is the SAME suite that is red in CI run 31586181611** (case 25, `D2 CONTROL`), filed as
  `05ff1e5fabc0`. Two independent instruments now agree the suite is broken, by two different
  symptoms.

  **REPRODUCED and NARROWED this session:**
  - A full-suite run wedges immediately **after test 34**, i.e. inside test 35
    (`POSITIVE CONTROL: rung 1 REACHED short-circuits — no banner, records seen`, `:719`).
  - 🚨 **But test 35 run ALONE passes, and so does test 34.** `bats -f` on each returns `ok 1`
    immediately. **So the hang is ORDER- or STATE-dependent — it is not a property of test 35's
    body**, and anyone who opens `:719` looking for a blocking call will find nothing and conclude
    the page was wrong.

  **RULED OUT — do not re-derive these:**
  - **`osascript`** — the obvious suspect, because test 35 is the first to set
    `CC_SWEEP_OS_CHANNEL=auto`. It is stubbed in `setup()` (`:79-85`, and `PATH` is exported there so
    every test inherits it) **and** the subject invokes it as
    `sweep_bounded 10 osascript - … <<'OSA'` (`autonomy-sweep.sh:941`) — bounded at 10s AND fed a
    heredoc, so the stub's `cat >/dev/null` cannot block on an open stdin either. Both halves checked.
  - **`it2`** — stubbed via `CC_IT2_BIN` + `CC_STUB_IT2_OUT` (`:93-99`), and the D4 cases set the
    listing explicitly.
  - **an external kill** — the page's own `NOT a cut` line, derived from the absence of a signal.

  **WHERE TO LOOK NEXT:** accumulated state or a leaked background child from an EARLIER test that
  only bites once test 35's `auto` channel opens. The suite writes into several exported dirs
  (`CC_PAGES_DIR`, `CC_ANNOUNCE_ALARM_DIR`, `CC_SWEEP_SEEN_DIR`, `CC_IDL`, …) that persist across
  tests within a `BATS_TEST_TMPDIR`, and `sweep_bounded` bounds the CHILD it forks but not a
  grandchild it leaves behind. Bisect by running tests 1..35 and then 30..35 — the pair that
  reproduces names the interaction, and neither member will reproduce alone.

## RESUME-HERE, REFRESHED — 2026-08-13, effort 2 at **10** non-cloud rows (was 20)

**Supersedes the earlier RESUME-HERE table above on the row LIST only** (that table's per-row analysis
and hazards remain valid and are not repeated). Store this session: **470 → 442**.

**Closed from this condition (10):** `918e9bac60b6` `3309486727cf` `4239f02465cb` `09f087a7f3d8`
`6557a992d498` `446fe07464e0` `9183cbf21772` `c6c5ef54881e` `0711d9e18934` `f8f1b2c16fa8`
`79811022b6a4` `f295605eec01` — several on MEASUREMENT rather than repair, which is a legitimate
close when the row asserted a red that is no longer there (both RED-on-trunk rows had never actually
been run; a refused `cc-bats` returns `ok=0 notok=0`, a NON-VERDICT that looks identical to unresolved
forever).

**Code landed this session (8), all content-verified and all verified LIVE by content:**
`3aecd1472` utc-stamp-lint non-verdict · `3bb7935b7` comm-split ×3 sites · `c78666902`
test-walltime-lint non-verdict ×2 predicates · `b7f771848` ship-land 8 gate arms + permission-gate
ratchet 15→9 · `ec3202ec3` + `e779d6335` the @test-name eval chokepoint (new lint, wired at BOTH
chokepoints) · `38ce5099d` offbox per-suite START marker · `e2d03d069` the banner twinkle value gate.

**THE 10 THAT REMAIN, and what each actually needs:**

| Row | State | Next action |
|---|---|---|
| `5456e4cba2b5` | REAL, hazard documented above | **Do this one FIRST** — `5ef0dcb22aec` touches the same predicate and should follow it. |
| `5ef0dcb22aec` | REAL (blocked) | Add `CC_ADMIT_GATE` as a second seam to rule 1; mechanical once the scoping question above is settled. |
| `86488ad1c966` | REAL, NOT PINNED | Needs a constructed fixture in `mktemp -d`; static grep did not locate the alternation arm. |
| `0f74f41042c5` | REAL, **OBSERVED** | Reproduced live: an intermittent false RED on the landing path, not merely a divergence risk. |
| `5d6dcbe8d462` | REAL, **remedy CORRECTED above** | Do NOT start from the row — its `--check-anchors` port does not apply (procedural vs declarative cases). Corrected spec is in this file. |
| `b449e49f1438` | NOT TRIAGED | The row asks for its own serialized land; it would red 3 currently-green suites. |
| `cf440684e0e1` | NOT TRIAGED, large | Perf; the row's own analysis says arm-level keying is NOT the answer. |
| `8efd655b0fe1` | INSTRUMENTED, not solved | The START marker is landed (`38ce5099d`), so the NEXT cancellation names its culprit. Nothing more to do until one happens. Do not exclude the reaper suites on inference — the row forbids it and the streak is now broken (run 31586181611: `unreported 0`, 10/10 shards). |
| `05ff1e5fabc0` | FILED (mine) | 3 CI-only reds. Locale and OS-platform hypotheses already REFUTED — do not re-run them. `autonomy-sweep` is additionally narrowed above (order-dependent hang). |
| `782607797fc5` | **BLOCKED — operator** | Privileged signal trace. macOS exposes no unprivileged way to learn a signal's sender. Still live: the live layer converged by DEGRADED ADVANCE, not because postland recovered. |

**Two of the ten are mine-and-filed and two are genuinely blocked, so the workable remainder is six.**

## RESUME-HERE, RECYCLE #2 — 2026-08-13, effort 2 at **8** non-cloud rows (was 10)

**Supersedes the list above on the row COUNT only.** Store this session: **442 → 445** — I closed 2
and filed 0, so the **+3 is entirely sibling intake**. Report both ends; a close count alone reads as
progress the store does not show.

**Closed (2), both LANDED and content-verified:** `5456e4cba2b5` (`c787a099a`) · `86488ad1c966`
(`3a30a7d6d`).

### 🚨 THE LESSON OF THIS RECYCLE: a row's claim about what is ALREADY HANDLED is its least-tested sentence

Both rows carried a reassurance, and **both reassurances were false in the direction that makes the
fix look smaller than it is.** A filer measures the case that FAILED; the clause describing what is
safe is written from impression, never from a probe. Test it first — it is where the scope hides.

| Row | What it said was already handled | What was measured |
|---|---|---|
| `86488ad1c966` | *"the lint already suppresses a plain single-word case label; the ALTERNATION form is the gap"* — repeated verbatim in `tests/deploy-parity.bats:1049` | **No label suppression existed at all.** `launchd)` alone emitted identically. Single-word labels only LOOK handled because the usual ones (`githooks`, `start`, `*`) name no installed binary, so `installed_somewhere` discards them downstream. Any label naming a real binary — `install)`, `test)`, `find)`, `time)` — leaked the same. |
| `86488ad1c966` | (implied) the defect is a false POSITIVE | The same missing state made the scanner wrong **both ways**: it reported LABELS and was **blind to every case BODY**. A bare binary invoked inside any `case` body was unreadable to this lint for its whole life. The silent half was the larger one. |
| `5456e4cba2b5` | *"the detector should key on an INVOCATION position"* | Built and measured FIRST, then **rejected**. It drops 21 suites, one being `tests/spawn-presence.bats`, which EXTRACTS `capacity_gate` from the real script and runs it under `bash -c`. It is load-sensitive, pins with form 2, and cites the rule by name — an execution predicate leaves that pin unenforced by this lint *and* by the sibling `_fires` ratchet, which cannot see the indirection either. |

**The asymmetry that decided `5456e4cba2b5`, and it generalises:** a false negative is a suite
silently reading the live box; a false positive is one harmless `export`. So the fix stayed BROAD and
subtracted only what is provably a SENTENCE (a name followed by two bare lowercase words). Exactly 4
suites left scope, all prose-only, none executing anything. **When a narrowing and a subtraction both
close a false positive, prefer the subtraction — it cannot manufacture a false negative.**

**A vacuous fixture, caught by mutation and worth repeating.** `19a` was first spelled with the filed
symptom's own words (`githooks|launchd)`). The hooks half is judged against `STOCK_PATH`, where
`/usr/sbin/launchd` and `/usr/bin/osascript` both resolve — so that fixture is GREEN with or without
the fix. Neutering the label state left it PASSING; only the real-tree case moved. Re-spelled with
`shellcheck` (not on the stock floor) it discriminates. **A fixture built from the symptom's own
vocabulary is the most likely one to be vacuous**, because the symptom's words were chosen by where
it happened to fire, not by what the predicate keys on.

**Two allowlist entries were bug residue.** `hooks/live-session-registry.sh:claude` and
`hooks/session-start.sh:claude` — both `claude|claude-*)` case labels — existed ONLY because the
scanner mis-read them. The stuck-entry alarm surfaced them the moment it stopped lying. **When a
detector is fixed, read its ratchet immediately: entries minted by the defect are now stale, and the
ratchet-only-shrinks rule makes deleting them part of landing the fix.**

**THE 8 THAT REMAIN — 5 workable.** `5ef0dcb22aec` (NEXT: add `CC_ADMIT_GATE` as a second seam;
scoping question now settled — reuse `strip_prose`, and note the naive "names a caller" scope puts
**22 suites** in scope of which 17 are unpinned, so it ships RED on arrival unless it follows rule 5's
idiom and grandfathers today's measured set) · `0f74f41042c5` (OBSERVED intermittent false RED on the
landing path; `installed_somewhere` reads the caller's live `$PATH`) · `5d6dcbe8d462` (remedy
CORRECTED earlier in this file — do NOT start from the row) · `b449e49f1438` · `cf440684e0e1` (perf,
large). Not workable: `05ff1e5fabc0` + `782607797fc5` (mine/operator-blocked), `8efd655b0fe1`
(instrumented; nothing to do until a cancellation happens).

**Mechanics worth inheriting.** `ship-land.sh` takes **~15-20 min**; the `Bash` tool caps at 600 s and
auto-backgrounds it — read the task output file, do not re-fire. Its smoke stage **gate-killed a suite
on both lands** (`exit 124`, ZERO `not ok`): that is a NON-VERDICT by the gate's own words, not a red —
run the suite yourself and carry your own verdict.

---

## RECYCLE #3 — `5ef0dcb22aec` closed: the hermeticity lint's RULE 7 (the capacity-ADMIT gate)

**What landed.** `scripts/test-hermeticity-lint.sh` gained a seventh rule — rule 2's twin at
`scripts/lib/capacity-admit.sh` — with its own ratchet (`EMBEDDED_ADMIT_ALLOWLIST`), its own two env
seams (`CC_HERM_ADMIT_ALLOWLIST`, `CC_HERM_ADMIT_RULE=off`), 15 new `--selftest` assertions (97 →
112) and 13 new cases in `tests/test-hermeticity-lint.bats` (54 → 67). The shared `strip_prose` was
generalised from a hardcoded `handoff-fire` to a parameter so the twins cannot drift.

### The row's remedy was TRUE WHEN FILED and FALSE when worked — by two days

The item (filed 2026-08-10) described the fix as porting rule 2's two sufficient forms with the
names swapped: form 1 `CC_ADMIT_GATE=off`, form 2 `CC_ADMIT_LOADAVG_OVERRIDE` +
`CC_ADMIT_HEADROOM_OVERRIDE`. `450a47c50` (2026-08-12) added a **third term** — the operator RESERVE
— which runs over an otherwise-ADMITTING box and refuses on inputs neither override touches:
`cc_sp_operator_state` (live presence) and `cc_sp_trees` (a live `ps -eo` census of session trees).
A fixtured `$HOME` does not absent either: `_cc_admit_load_presence` resolves `spawn-presence.sh`
**relative to `capacity-admit.sh`'s own directory FIRST**, so a suite pointing `$HOME` at a tmpdir
still loads the real library.

**Proven two-sided on the gate's own suite, which was in exactly the shape the row prescribed:**
`bats tests/capacity-admit.bats` is **20/20** ambient and **17/20** under `CC_SP_TREES_OVERRIDE=999`
(cases 13, 14 and P3 flip on the census alone). Porting form 2 verbatim would have certified the one
suite whose subject IS this gate as PINNED while it read the live box — **a false negative minted by
the rule that exists to prevent it.** Form 2 therefore has THREE clauses; the third is
`CC_ADMIT_RESERVE_TERM=off` **or** `CC_SP_TREES_OVERRIDE` (the presence read behind it resolves from
`CC_BEAT_DIR`, whose default is `$HOME`-rooted and therefore rule 1's business — rule 5's split).

🚨 **This is the recycle-#2 lesson arriving through a new door, and the door is what generalises.**
Recycle #2 found reassurance clauses that were false *as written*. This one was **true as written
and expired**: nothing about the sentence was wrong, a sibling commit two days later made it
incomplete, and the row has no mechanism to learn that. So the probe is not only *"is the clause
true?"* but ***"what has the row's cited mechanism done SINCE the row was filed?"*** — one
`git log -S <the term> --since <firstTs>` on the cited file. Same shape as
`resident-policy-must-not-restate-perishable-facts`, one level down: a **backlog row** is also a
resident restatement of a perishable fact.

### Two corrections to this handover's own numbers, both from measuring rather than accepting

| Handover said | Measured |
|---|---|
| 6 callers: `boot-resume-launch.sh`, `capacity-alarm.sh`, `lib/spawn-presence.sh`, `lib/worker-claim-gate.sh`, `lr-fire-resume.sh`, `hooks/agent-teams-enforce.sh` | **3 + 1.** `capacity-alarm.sh` and `lib/spawn-presence.sh` only SOURCE the library; `lib/worker-claim-gate.sh` names `CC_ADMIT_BUDGET` in a comment. None calls `cc_capacity_admit`. `handoff-fire.sh` also only sources it (for the shared `cc_hw_*` terms under `CC_FIRE_*`), so rule 2's and rule 7's populations are **disjoint by construction** — asserted in `tests/test-hermeticity-lint.bats`. |
| "22 suites in scope, 17 unpinned — ships RED on arrival" | **20 in scope, 4 pinned, 16 violating.** The 22/17 came from the looser "names a caller" scope over the wrong caller set; a ratchet built from it would have shipped four lines no predicate could ever retire. |

### The ratchet shipped at 15, not 16 — one was fixed instead

`tests/capacity-admit.bats` is the one whose ambience was **measured** rather than inferred, and its
own header already claimed the property it had lost (*"otherwise every assertion here would flip
with the mood of the machine running the suite"* — written before the reserve term existed). One
line (`export CC_ADMIT_RESERVE_TERM=off`) closes it: now **20/20 both ambient and under a saturated
census**. Per the ratchet-only-shrinks rule, deleting its allowlist line was part of landing the fix.
The other 15 are grandfathered — several are static text-analysis suites that `grep` a caller's
SOURCE and execute nothing, a position neither `strip_comments` nor `strip_prose` can distinguish,
and rule 2's settled asymmetry (a false negative is a suite silently reading the live box; a false
positive is one harmless export) says keep them in and retire them one at a time.

### Mutation-proved, one mutation per site

| Mutant | Killed, by name |
|---|---|
| `references_admit` → always out of scope | 7 rule-7 assertions, zero rules-1-6 collateral |
| rule 7 unwired from `lint_dir` | the same 7 |
| **form 2 loses its reserve clause** (the row's remedy verbatim) | *"the two-variable form 2 counted as PINNED — the reserve term (450a47c50) is unguarded"* — **and the real-tree case independently**, which is corroborating evidence that `capacity-admit.bats` was genuinely in that state |
| `strip_prose` → `cat` | *"a caller named only in PROSE pulled a suite INTO rule 7"* + the real-tree case |

**The lint fires on its own /Users/chrisren/.claude/bin/cc-bats file** once that file names a caller — caught by the suite's own
real-tree case, fixed the way this file fixes every such case: dogfood the pin in `setup()`, never
grandfather the lint's own suite under its own rule.

---

## RESUME-HERE, RECYCLE #4 — 2026-08-13, effort 2 at **16** rows (NOT 8 — see the roster below)

**Closed this recycle (1), LANDED and content-verified:** `5ef0dcb22aec` (`88bf5cf1f`, 4 paths
present + `git diff` empty on origin/main). **Store: 445 → 446** — I closed 1 and filed 0, so the +2
is entirely sibling intake. Report BOTH ends; a close count alone reads as progress the store does
not show.

### 🚨 THE ROSTER WAS WRONG BY 8, AND THE HANDOVER IS NOT THE STORE

Recycle #3's brief (and recycle #2's RESUME-HERE) said *"THE 8 THAT REMAIN — 5 workable."* Measured
at this boundary, `condition=master-verification-integrity` holds **16 open rows**, of which 15
remain after this close. The 8 the brief never named are all vintage 2026-08-11/12 — the same dates
as the rows it did name — so they were either linked into the condition by a sibling after it was
written, or simply missed. **Do not carry a row count across a recycle: re-derive it, from the
store, at every boundary.** Same class as the reassurance lesson below, applied to the handover
itself.

```
cc-backlog list --open --json | jq -r '.[] | select(.condition=="master-verification-integrity")
  | "\(.id)  \(.status)  \(.firstTs[0:10])  \(.title[0:80])"'
```

**Not workable (3):** `05ff1e5fabc0` (mine/filed) · `782607797fc5` (operator-blocked) ·
`8efd655b0fe1` (instrumented; nothing to do until a cancellation happens).

**Workable (12), and only the first two have been triaged — the other ten are UNREAD by any
recycle so far, so give each one question 2 below before starting:** `0f74f41042c5` (triaged in
full, see below) · `5d6dcbe8d462` (spec corrected earlier in this file — do NOT start from the row)
· `b449e49f1438` · `cf440684e0e1` · `3ec6c070f52f` · `73583e2519d6` · `67a7d78c1134` ·
`0be0bd2c0b65` · `c1a29f8ee045` · `57ff249657e0` · `2c5ab136d63f` · `b02e87582e96` · `e191b6801be5`.

**THE LESSON OF THIS RECYCLE — the reassurance clause has a SECOND failure mode, and it is invisible
to the recycle-#2 probe.** Recycle #2 found clauses false *as written*. `5ef0dcb22aec`'s was **true
as written and EXPIRED**: nothing in the sentence was wrong, a sibling commit two days later
(`450a47c50`) added a third term, and the row has no mechanism to learn that. So the probe is now two
questions, and the second is new:

1. *Is the clause true?* (recycle #2)
2. ***What has the row's cited mechanism done SINCE `firstTs`?*** — one
   `git log --since <firstTs> -- <the cited file>`, or `-S <the cited term>`. Cheap, and it is what
   caught this one.

A backlog row is a **resident restatement of a perishable fact** — the same class as
`resident-policy-must-not-restate-perishable-facts`, one level down. The older the row, the more the
reassurance is a claim about a tree that no longer exists. **Both rows still open from before
2026-08-12 should get question 2 before any work starts.**

### NEXT ROW — `0f74f41042c5`, already triaged INLINE this recycle; do not re-derive

**The row's own reassurance** (in its title: *"blocking channel now closed by own-scoping the stuck
ratchet, the divergence is not"*) was probed and is **TRUE** — `scripts/unattended-path-lint.sh:822`
own-scopes the NEW-finding arm and `:970` the stuck-ratchet arm, and case 17b already pins the
lean-caller direction (`/usr/sbin:/sbin` joined the static suffix). Question 2 also answered:
`3a30a7d6d` (recycle #2's own fix) is the only change to that file since the row was filed, and it
does not touch this.

**THE RESIDUAL, stated precisely.** `installed_somewhere` (`:644`) searches `${PATH}` — the caller's
LIVE inherited PATH — plus a static suffix, and a **NO DROPS the finding**. Both arms being
own-scoped closes the *sibling-file* blocking channel but NOT this one: a file **in the author's own
diff** whose finding exists only because the LANDING box has a binary the author's box lacks blocks
that author on a red they cannot reproduce. This is verbatim the defect the SIBLING lint already
names and solved — `test-hermeticity-lint.sh` RULE 5's header: *"A lint that resolved the operator's
PATH to reach a verdict would be committing the defect it exists to catch — and it would also be
wrong, since `timeout` is /usr/bin on one box and Homebrew coreutils on the next."*

🚨 **MEASURED, and it kills the obvious fix.** Mutating `installed_somewhere` over the real tree
(copies in scratch, tree untouched):

| `installed_somewhere` | findings |
|---|---|
| real | **35** |
| always-YES | **975** |
| always-NO | **0** |

It drops **940 of 975 (96.4%)** — it is the load-bearing noise filter, not a nicety. So *"skip the
filter for files in the own-set"* — the tempting narrowing — floods the author with ~96% noise on
their own files. **Rejected by measurement, not by argument.**

**The design that survives, and it is a SUBTRACTION-shaped union rather than a narrowing** (the
standing preference: a narrowing can manufacture a false negative, this cannot):

```
installed_somewhere(W)  ==  W ∈ CHECKED_IN_INVENTORY  ||  reachable_on(<today's union>)
```

A committed, tree-derived inventory of names known to be real binaries, unioned with today's live
probe. It can only ever **ADD** a finding relative to today, never drop one, so it cannot manufacture
a false negative in the direction that matters (a suite silently reading the live box). A box missing
`gtimeout` now reports it anyway, so the author sees locally what the landing box will see. Same
idiom as this repo's `EMBEDDED_*_ALLOWLIST` ratchets and RULE 5's tree-derived seam table.
**Not yet built.** Open questions for whoever takes it: how the inventory is generated and
re-generated (a `--emit-inventory` verb?), and whether it ratchets (only-grows, since a name that was
ever a binary stays one).

**Then:** `5d6dcbe8d462` (do NOT start from the row — the corrected AST spec is earlier in this
file) · `b449e49f1438` · `cf440684e0e1` (perf, large; the row's own analysis says arm-level keying is
NOT the answer). Not workable: `05ff1e5fabc0` + `782607797fc5` (mine/operator-blocked), `8efd655b0fe1`.

**Live layer, unchanged and NOT yours.** `deploy-live.sh` still declines — *"no GREEN tree is a
DESCENDANT of live HEAD"* — because the postland verifier is cut-loop-stuck (already filed,
operator-gated, `782607797fc5`; do NOT re-file). Lag was 14 commits / 3h, inside the degrade budget
(25 / 6h), but **2 NEW files from SIBLING commits are absent**, and an ADD gets no budget, so the
ledger reads 🚀 for the whole box. Your own landed change is a MODIFY riding an existing per-file
symlink and goes live on the next fast-forward. Never `deploy-live --force`.

**Mechanics confirmed again.** `ship-land.sh` took ~13 min and auto-backgrounded; **do not pipe it
through `tail`** — the pipe buffers, so the task output file stays 0 bytes and you cannot watch
progress. Its smoke stage gate-killed `tests/ship-land.bats` for the THIRD consecutive land
(`exit 124`, ZERO `not ok`) — a NON-VERDICT by the gate's own words, on a suite that was not in the
diff. Run your own suites and carry your own verdict.

---

## RESUME-HERE, RECYCLE #5 — 2026-08-13, effort 2

**Closed this recycle (1):** `0f74f41042c5` (`fb7d0591c`). Filed 0.

### 🚨 THE ROSTER, AND WHY IT KEEPS READING DIFFERENTLY

Recycle #4's brief said *"15 rows — 3 not-workable, 12 workable."* That count is right about the
CONDITION and wrong about THIS SESSION's population, and the difference is not drift — it is a
filter nobody had applied:

```
condition=master-verification-integrity, open : 15
  of which venuePlan=cloud                    :  8   ← out of scope for the local drain
  of which non-cloud                          :  7
    blocked (782607797fc5, operator-gated)    :  1
    not workable (05ff1e5fabc0 mine/filed,
                  8efd655b0fe1 instrumented)  :  2
    WORKABLE                                  :  4   ← 0f74f41042c5 (now closed), 5d6dcbe8d462,
                                                       b449e49f1438, cf440684e0e1
```

So the "wrong by 8" of recycle #4 and the 8 cloud rows are the SAME EIGHT. Recycle #3 counted the
non-cloud rows, recycle #4 counted every row in the condition, and each read the other's number as
an error. **Both counts were correct; neither stated its denominator.** Re-derive with the venue
filter, and say which population you counted — a bare row count is not a fact about anything.
(memory: `positive-control-the-denominator`, one level down: police the denominator by NAMING it.)

**Remaining workable (3):** `5d6dcbe8d462` (do NOT start from the row — corrected AST spec earlier in
this file) · `b449e49f1438` · `cf440684e0e1` (perf, large; the row's own analysis says arm-level
keying is NOT the answer). Give each the two-question reassurance probe first.

### `0f74f41042c5` — CLOSED, and what the triage actually found

The RESUME-HERE's triage was correct and its design survived contact. Two corrections worth carrying:

1. **The residual was NARROWER than stated, and the narrowing is the good news.** The row's residual
   reads as if `installed_somewhere` poisons the whole lint. It does not: the **ordering rule** at
   all three call sites (`allowlist BEFORE installability`, `:852`) had already immunised the
   STUCK-ratchet arm, with a comment naming this exact failure class and a suite case (14) pinning
   it. Only the **new-finding** arm was left environment-sensitive. Read the call sites before
   sizing a fix from the row's prose — the prose understated how much was already handled.
2. **The defect reproduces in one command**, and this is the measurement to lead with next time:
   ```
   diff <(CC_UNATTENDED_ALLOWLIST="" lint tree) <(PATH=/usr/bin:/bin CC_UNATTENDED_ALLOWLIST="" lint tree)
   ```
   Before: 35 vs 31 findings, the 4 being `bun`/`cargo`/`ruff`/`agent-browser`, and `ONLY-IN-LEAN`
   **empty** — the drop is strictly one-way, which is what makes a UNION the right shape. After:
   byte-identical.

**Built:** `EMBEDDED_BINARY_INVENTORY` (102 names) + `in_inventory()` + `--emit-inventory` +
`CC_UNATTENDED_INVENTORY` seam. Both open questions from recycle #4 are answered: the verb unions
and never subtracts, and it ratchets **UPWARD** — the opposite direction from `EMBEDDED_ALLOWLIST`,
which is why it deliberately has NO stuck-entry check (retiring a name because today's box lacks it
would restore the very environment-sensitivity the list removes).

### 🚨 THE LESSON OF THIS RECYCLE — TWO vacuous fixtures, and the SECOND was a bad MUTANT, not a bad test

The brief warns that a fixture spelled in the symptom's own vocabulary is the likeliest to be
vacuous. It happened twice here, and the two have **opposite** remedies:

1. **A genuinely vacuous test.** My first suite case asserted "under a stripped PATH the corpus still
   reports binaries that PATH cannot reach". It passed under the reverted-arm mutant. Cause: the
   control counted names unreachable on `$STOCK`, but `installed_somewhere` probes
   STOCK ∪ Homebrew ∪ /usr/local ∪ …, so Homebrew binaries kept it green with the arm gone. **A
   control must be keyed on the predicate's ACTUAL domain, not on the one the prose names.**
2. **A MIS-TARGETED mutant that reads identically.** Its replacement seemed to fail the same way —
   deleting `shellcheck` from the inventory left the suite green. But `shellcheck` is **not in the
   corpus's finding set at all** (every site resolves it absolutely or hardens PATH), so the
   mutation was invisible by construction. Re-targeted at `lsof` — measured to be in the finding set
   — the case fails by name with its remedy printed. **A green suite under a mutant has two causes,
   and they look the same: the test cannot see the defect, or the MUTANT never introduced one.
   Derive the mutation target from the subject's measured output, never from its vocabulary.**
   (memory: `control-must-replay-the-real-artifact`.)

**And the durable structural finding:** the union arm's value is CROSS-BOX, so it is *provably
untestable* against the real corpus on the box that generated the inventory — there, every name the
inventory vouches for is also live, so no real-tree run can distinguish the arm from its absence.
That is why the division of labour is: **`--selftest` owns the MECHANISM** (20a red via inventory
only, 20b control, 20c whole-line matching — synthetic trees can fake a box that lacks a binary),
and **the suite owns COVERAGE** (case 18: every name the real corpus reports must be in the
inventory, else its finding is box-dependent). Asking either to do the other's job yields a vacuous
pass. When a fix's value is only visible across environments, do not look for one test — split it.

**Also fixed in passing:** the suite header restated "--selftest with 18 cases". It read 27 before
this land. The number is now DELETED rather than updated — a resident restatement of a perishable
fact has no path to learn it changed (memory: `resident-policy-must-not-restate-perishable-facts`).

### `5d6dcbe8d462` — CLOSED (`da4054e3d`). What the corrected spec got right, and what it still got wrong

The plan's AST spec was right to reject the `--check-anchors` port and right about both rot routes.
**Both of its literal spellings were still wrong, and one command each disproved them:**

| spec as written | measured | corrected |
|---|---|---|
| walk `g.<NAME>` attribute accesses | 1 of 66 is a **Store** — case 1 installs `g.assert_nothing_calls_me` on purpose | `ast.Load` context only ⇒ 65 reads, 0 stale |
| `want` still appears in gen.py | **5 of 37** wants span an f-string interpolation (`found {n} of {m} vertices`) | match against literals **and f-string constant fragments**, in word order within one literal ⇒ 0 unreachable |

Both would have shipped a check that convicts true cases on day one. **Measure a predicate against the
real corpus before wiring it, even when the design is already agreed** — the spec is a hypothesis
about the tree, and this tree falsified two of them.

🚨 **THE FIND WORTH MORE THAN THE ROW — the census could not catch what it was built to catch, and
DOCUMENTING the fix disarmed it.** `tests/anti-vacuity-contract.bats`'s CENSUS prints *"Each must be
invoked by a case … not merely mentioned in a comment"* and then ran
`grep -q -- "$b" "$BATS_TEST_FILENAME"` **over the whole file**. Measured: delete the new
banner-gate-redproof case and the census stays **GREEN**, satisfied by the four comment mentions in
the paragraph explaining the harness. The gradient is perverse and worth stating as a rule:

> **The more carefully a harness is documented inside its own census file, the more thoroughly its
> census entry is disarmed.** Prose about a subject is indistinguishable from wiring to any check
> that greps the file rather than its executable lines.

Cure: strip comment lines before the grep — which is only what the failure message already claimed.
(memory: `contract-prose-can-understate-the-mechanism`, inverted — here the prose OVERSTATED it.)

**And the hardening itself shipped as a silent NO-OP first.** The literal shell-escaping sequence
`'"'"'` was written into the .bats file rather than used to build a command line, so grep's pattern
became garbage, `grep -v` stripped nothing, and the census behaved exactly as before. It read as a
fix, the suite stayed green, and only the mutant caught it. **A guard whose repair you cannot see
fail has not been repaired.**

**Mutation caught THREE distinct things this recycle** — a vacuous suite case, a mis-targeted mutant,
and a no-op fix. None was visible from a green suite.

### NEXT ROW — `b449e49f1438`, TRIAGED IN FULL, not started

**Q2 answered, and it moved the work: the row's own list is STALE BY ONE.** Of the three "guarded,
silently vacuous" siblings, `tests/session-start-mcp-probe.bats` **has already been fixed** (2 commits
since `firstTs` 2026-08-11T19:20:09Z; its control now opens *"PINNED SHA, NOT `origin/main`. This
control replayed origin/main, which MOVES…"*). Two remain:

```
tests/compressor-sentinel.bats:50    git -C "$REPO" show origin/main:scripts/compressor-sentinel.sh … || true
tests/ignition-gate-census.bats:55   git -C "$REPO" show origin/main:bin/cc-ignition-gate > "$PRE" … || true
```

**The deferral reason has EXPIRED, and own-scoping is why.** The row parked itself because *"the lint
would red 3 currently-green suites and block every concurrent lander in the live dispatch wave."*
Every comparable lint in this repo is already own-scoped — `→ gate: X own-scope — blocking on N
file(s) in this land's diff; others advisory` — so a lint built to that established pattern blocks
nobody who does not touch these files, and the stated F1 downside simply does not arise. There are
other live sessions (measured: `wt-pool-2`, `wave-w4-stranded`, `wt-pool-5`), so the concern was not
imaginary; own-scope dissolves it rather than out-waiting it.

**PRE-MEASURED FOR THE DETECTOR — the comment/code split the row names is NOT sufficient.** The
census over `tests/*.bats` returns three hits, and the third is innocent for a reason the row does
not anticipate:

```
tests/cc-dispatch-projects.bats:359   grep -q "git show origin/main:<path>" "$C/brief-proj-b-1.txt"
```

That is the moving-ref phrase **inside a string being asserted about**, on a fully executed line. So
the discriminator is not comment-vs-code but **invocation vs mention**: the defect is `git … show
<moving-ref>:<path>` in COMMAND position, not the characters appearing on an executed line. Build the
detector against all three and require it to flag exactly two — a lint that flags 3 is as wrong as
one that flags 0, and this file is the positive control for the too-wide direction.

**Each of the two also needs the second half:** an immutable pin AND a **pre-fix MARKER assertion**.
The pin alone still goes vacuous if the sha is ever re-pointed; the marker grep is precisely what made
`capacity-alarm-permb` fail LOUDLY rather than silently.

---

## RESUME-HERE, RECYCLE #6 — 2026-08-13, effort 2

**Closed this recycle: `b449e49f1438` (`85fd75bc8`). Filed 0.** Store, non-cloud open: **445 → 444**
(re-derive; state the population — `condition=master-verification-integrity` still holds 8 `cloud`
rows that are outside this drain by construction, which is the denominator bug recycle #5 settled).

**Remaining workable in this condition: ONE — `cf440684e0e1`** (perf, large; the row's own analysis
says arm-level keying is NOT the answer). Untriaged. Give it the two-question reassurance probe
first, and probe its own deferral reason the same way — that is what dissolved this row.

### `b449e49f1438` — CLOSED. The triage was right about the work and WRONG about the diagnosis

The RESUME-HERE handed over a complete triage and it held on every point that shaped the *work*: the
list was stale by one, the deferral had expired, own-scoping dissolves it, the discriminator is
invocation-vs-mention, and the detector must flag exactly 2 of 3. All confirmed, unchanged.

🚨 **But the row's central claim — "they are GREEN NOW and that is why they are worse" — was true of
only ONE of the two, and the other was the opposite failure.** Measured by replaying the pre-edit
files:

| site | row predicted | MEASURED |
|---|---|---|
| `tests/ignition-gate-census.bats` | silently vacuous | **9/9 GREEN** replaying the FIXED gate — vacuous, as claimed |
| `tests/compressor-sentinel.bats` | silently vacuous | **cases 72/75/76 RED ON TRUNK**, and had been since `6dd3ea468` |

So one of the two sites was a **standing trunk red** that every full run had been carrying, and the
row filed it as a silent-green. The lesson is not that the row was careless — it is that **the two
poles of this defect are produced by the SAME cause and are indistinguishable without running it**.
Whether a moved ref reddens or goes vacuous depends entirely on what the control happens to assert:

- compressor-sentinel asserts a pre-fix **VALUE** (`precensus` must read `1 1 878`), and the post-fix
  artifact returns a different one ⇒ LOUD.
- ignition-gate-census asserts the pre-fix gate reads **node_n=0**, and the post-fix gate ALSO reads
  0 through `pregate` — which sets no `CC_IGNITION_EXE_FILE`, so the new name table names none of the
  fixture's synthetic pids ⇒ 0 for an unrelated reason ⇒ SILENT.

**Generalisable:** a control that asserts an ABSENCE (`-z`, `= 0`, "does not appear") can be
satisfied by a second, unrelated cause; one that asserts a pre-fix VALUE cannot. When you cannot
afford to find out which pole you are on, assert the value.

### What shipped

`scripts/moving-ref-control-lint.sh` (22-case `--selftest`) + `tests/moving-ref-control-lint.bats`
(7 cases) + the `run_gate` arm in `scripts/ship-land.sh`, own-scoped with the three-state contract
its siblings use. Both sites pin **`808c09609`** (=`6dd3ea468^`) and assert a marker.

- **The MARKER had to be derived from the measured diff, and the obvious one was WRONG.** The
  natural marker for the ignition gate is its pre-fix `ps` spelling `pid=,etime=,comm=,args=` —
  which greps **1 on BOTH sides**, because the post-fix file names it in the comment explaining the
  fix. `exe_rows` / `exe_table` (the identifiers the fix INTRODUCED) discriminate 0-vs-3. This is
  the third consecutive recycle in which a marker/mutant spelled from the subject's VOCABULARY
  rather than its MEASURED output was the defect.
- **Quote-stripping is the discriminator**, not comment-vs-code. `cc-dispatch-projects.bats:359` is
  a fully executed line whose phrase is a string being asserted about. Strip balanced quoted spans;
  a **dangling** quote keeps the remainder RAW (fail-closed).
- **The rule is a SUBTRACTION**: pinned ⇔ 7+ hex characters, everything else moves. No enumeration
  of `origin/main | HEAD | main | …` to go stale. A ref that strips to an unreadable expansion is
  flagged too — a pin that cannot be read from the file cannot be audited from the file.

### 🚨 THE LESSON OF THIS RECYCLE — a mutant that never applied reads exactly like a blind test, and it happened TWICE IN ONE SESSION

Recycle #5 already recorded this class ("a green suite under a mutant has two causes"). It recurred
here in its most embarrassing form: **the mutation command itself failed and the run was green
because nothing had changed.**

- `sed -i '' 's|  \[ "${3:-0}" = "1" \] || return 0|…'` — the `||` inside the pattern is a **bad sed
  delimiter**, so sed errored and the file was untouched. Verdict read `22/22`.
- The perl retry with `\Q…\E` silently matched nothing for the same family of reasons. Verdict read
  `22/22` again.

Both would have been recorded as "the suite cannot see this mutation" — a fabricated coverage gap
that costs real work to chase. **The cure is one line: make the mutator ASSERT its own precondition.**

```python
assert s.count(old) == 1, f"MUTANT NOT APPLICABLE: {s.count(old)} occurrences"
```

Every mutant after that printed `applied` before its verdict was read. Ten mutants ran under that
discipline and **one found a real gap**: the fail-open variant of the dangling-quote branch left
*every other case green*, so the documented fail-closed behaviour was unpinned. It is now case
`dangling`. **A mutation harness needs a positive control exactly as much as a matcher does** — and
the control is not "did the suite go red", it is "did the mutation happen at all".

### Carry-forward for `cf440684e0e1` and beyond

- Triage INLINE with a content read; the 5-agent fan-out that returned 0 findings has not been
  re-tried and should not be.
- The two-question reassurance probe keeps paying — question 2 (`git log --since <firstTs> -- <cited
  file>`) removed a third of this row's work, and probing the row's own DEFERRAL reason removed the
  rest of the reason it had been parked.
- `ship-land.sh` now has one more gate arm. It is own-scoped and sub-second; a land that touches no
  `tests/*.bats` never sees it.

### `cf440684e0e1` — TRIAGED IN FULL, not started. Its blocker does not exist

**Do NOT start from the row, and do not start from `docs/research/land-architecture-100p-2026-08-10
.md` §5.P3 either — start from the CORRECTION appended to §5.P3 on 2026-08-13 (`4fa8d34a5`).** The
row is a faithful restatement of that section's three findings, and **three of the four do not
survive a read of the code they cite.** All three refutations came from one question asked of the
citation rather than the conclusion, and neither needed a measurement rig:

| §5.P3 finding | verdict |
|---|---|
| **1** — `test-hermeticity` rule 4 is cross-file (a property of a PAIR of files), so no per-file verdict exists | **FALSE.** The scan is `for f in …` and both predicates take ONE file. No pairing anywhere. The header states the rule was written this way on purpose: *"the compliant position is not 'fixture $HOME' but 'make the path PER-RUN UNIQUE'"*. The misreading comes from the arm's VOCABULARY — it prints `COLLIDES … two concurrent runs share it` and `0 collisions`, but the collision is between two runs of the SAME tool. |
| **3a** — `unattended-path-lint` also judges `settings.json`, outside its pathspec | **FALSE, and stale before it was written.** `hook_population()` stopped intersecting the live settings.json at **`da81f555b` (2026-08-06)** — four days before the note, five before the row — deliberately, because directory scanning is *"deterministic, hermetic, and strictly WIDER"*. Strictly wider IS the superset direction, so it now argues the opposite of its citation. |
| **3b** — pipefail's pathspec lists `docs/*`, so it is not a superset | **TRUE but POLARITY-INVERTED.** Listing `docs/*` makes the spec WIDER than the judged population, which is what a superset is. Too wide costs extra invalidations; only too NARROW is the stale-verdict generator. |
| **2** — arm-level keying skips only 27-46% of re-rounds over the last 200 lands | **STANDS, unprobed.** This is the real objection and it is sufficient: do NOT build arm-level keying. |

**What that changes.** §5.P3's own recommended path — per-file memoization *inside* each lint's scan
loop, "what would actually reach ≤10s" — was blocked by exactly one thing, finding 1's file-locality
failure. **Every arm named is file-local, so the blocker is gone.** The remaining work is the
mechanical read-set declaration itself (~15 lints) plus a per-lint locality proof; the three
declarations derived by hand above are the first three and none needed an exception.

**Two cautions for whoever builds it.** (a) The row's timing (re-round 127-137s, arms ~112s) is from
2026-08-10 and the arm set has GROWN since — `bats-testname-eval-lint`, `offbox-admission`,
`test-hermeticity` rule 7, and `moving-ref-control` all landed after it. **Re-measure before
optimising**; a published figure decays with its source. (b) Half a declaration standard is worse
than none — a partial read-set invites keying on a non-superset, which the row correctly calls a
stale-verdict generator. Land all of them or none.

### The generator this whole recycle kept hitting, stated once

Four independent defects this session reduce to one move: **a claim taken from a subject's
VOCABULARY instead of its MEASURED behaviour.**

1. A marker chosen from the pre-fix `ps` spelling — greps 1 on BOTH sides, because the post-fix file
   names it in the comment explaining the fix.
2. §5.P3's finding 1 — "cross-file" read off the word `COLLIDES` in a message, over a loop that
   compares nothing.
3. Recycle #5's mis-targeted mutant — `shellcheck` deleted from an inventory it was never in.
4. Recycle #5's vacuous control — keyed on `$STOCK` while the predicate probed a wider domain.

**The cure is always the same and it is cheap: read what the code DOES to the thing you are naming,
before you name it.** One `sed` over a scan loop. One `grep -c` on both artifacts. One `git log -S`
on the citation. Each of these cost under a minute and each removed real work or prevented a
fabricated finding.

## RESUME-HERE, RECYCLE #7 — 2026-08-13, effort 2

**Store, non-cloud open at entry: 444.** Custody clean, tree clean. Taking `cf440684e0e1`, the last
workable row in `master-verification-integrity`.

### The re-measurement the row demanded, and it moved the target

Caution (a) of recycle #6 said the row's 2026-08-10 timings had decayed and the arm set had grown.
Both true, but the correction that matters is one **I introduced and then caught**, and it is the
same generator this plan has been tracking for three recycles.

🚨 **I timed every arm by running it bare — and the gate does not invoke them that way.** ship-land
runs each arm through `own_run`, which EXPORTS the arm's own-set variable. For most arms that only
decides blocking-vs-advisory and the scan is unchanged. For `bats-shellcheck-lint` it decides **what
gets scanned at all**: with an own-set the lint scans only the suites that own-set names
(`scripts/bats-shellcheck-lint.sh`, the `scoped=()` loop at the entrypoint), and a land touching no
`.bats` file exits before shellcheck runs.

| | bare run (what I first measured) | as the gate invokes it |
|---|---|---|
| `bats-shellcheck-lint` | **50.50s** — census over all 467 suites | **0.07s** |

Had I not read the entrypoint I would have spent this recycle memoizing the single most expensive
arm in my table, which is **0.07s in production**. The row's own 2026-08-10 figures never listed
bats-shellcheck among the heavy arms — the row was right and my measurement was wrong, because it
measured a mode the gate never executes. *Same generator, new face: I named the arm's cost from the
invocation I typed rather than the invocation that runs.*

### The corrected arm table (this worktree, 2026-08-13, own-sets exported as `own_run` does)

    test-hermeticity   45.96      git-identity     13.27      unattended-path  11.44 (+13.41 selftest)
    pane-spawn          7.71      test-walltime     6.77      pipefail          6.04 (+0.96)
    bats-kill-guard     5.47      moving-ref        5.22      utc-stamp         5.21 (+4.91)
    test-afunix         4.88      self-path         1.68 (+1.82)                bats-shellcheck   0.07
    permission-gate / chromium-bundle / tsv-pad / offbox-admission   ~0.8 combined

**~114s main + ~21s selftest ≈ 135s** (row measured ~112s). The arms grew; so did the total.
**`test-hermeticity` alone is 46s — 34% of the arms.** It is the whole target; nothing else is close.

Its internal shape, measured by scaling the corpus (ENV_ROOT is `$ROOT` regardless of the dir
argument, so the table build is a constant and the two costs separate cleanly):

    n=0  10.38s   n=60  14.60s   n=120  18.64s   n=240  26.87s   n=467  42.37s

**10.4s fixed** (the SEAM/ENV table build over 331 `bin` + `scripts/*.sh` + `hooks/*.sh` files)
**+ 0.069s per .bats suite** — linear, 32s of the 46s is the per-suite loop.

### The scope reduction: the read-set declaration is the REFUTED path's prerequisite

The row says *"PREREQUISITE, and probably the whole item: a mechanical read-set declaration per gate
lint"*, and recycle #6's caution (b) says land all ~15 declarations or none. **Neither binds the work
that is actually left**, and the source that settles it is the row's own citation.

`scripts/lib/gate-memo.sh`'s closing section lists four reasons the arms are not memoized. Reason
**4** — the population declaration is not a superset — is a prerequisite of the **arm-level key**,
which is reason **3**, which is finding 2, which recycle #6 confirmed **STANDS: do not build
arm-level keying**. The per-file path is named separately in that same footer:

> *"What WOULD reach the target is per-file memoization INSIDE each lint's scan loop … That needs a
> **file-locality proof per lint**"*

A locality proof, not a declaration. And because each lint's memo is keyed on its own inputs, an
unmemoized lint runs exactly as it does today — so a partial rollout is **incomplete, never
unsound**. Caution (b)'s "all or none" governs the declaration standard, which is not being built.
**One lint, done completely, is a whole unit.**

### Locality, MEASURED not read

For `bats-shellcheck-lint` (before its cost was corrected away) the proof was worth keeping as the
pattern: shellcheck is invoked without `-x`, so a file's findings should not depend on its
batch-mates. Confirmed by running the corpus batched and then one file per invocation — **147
findings both ways, byte-identical**. That is the shape every per-lint locality proof should take:
run the real corpus both ways and diff, never quote the flag.

### Next: per-suite memo inside `test-hermeticity-lint.sh`

Read set per suite, from the scan loop at `scripts/test-hermeticity-lint.sh:1552`: the suite's own
bytes, the lint's own blob (all seven embedded allowlists and every predicate), and the **SEAM_TABLE
+ ENV_TABLE** built from `bin`/`scripts`/`hooks` (rules 5 and 6 consult them per suite). Rules 1, 2,
3, 4 and 7 are file-local — rule 4's per-file-ness is recycle #6's refutation of §5.P3 finding 1.

The memoizable value is **"this suite emitted nothing"**, and that is own-set-independent by
construction: every `printf` in the loop sits inside a finding branch, and `in_own` only selects
which *wording* a finding gets. So a clean suite is clean for every land, and the memo keeps
gate-memo's "only ever cache a green" invariant unwidened.

**Two hazards to build against.** (1) Every emitting branch also increments exactly one counter, so
a counter-sum snapshot around each suite detects "emitted nothing" in two lines — but that is only
true while it stays true, so the selftest must pin a violating suite as NEVER memoized, per rule.
(2) `CHECK_FAILED` must veto recording: a suite whose predicate could not RUN has no verdict to
cache, and caching its fail-SAFE 'hermetic' would convert a non-verdict into a permanent green.

### BUILT: the per-suite memo in `test-hermeticity-lint.sh` (`c62c4a9cd`)

`herm_memo_arm` declares the read set (`HERM_READSET`) and folds it into a checker-id, so
gate-memo's audited `memo_file_hit` / `memo_file_record` are reused unchanged. The cached fact is
**"this suite emitted nothing"**; the record site has two vetoes; `--selftest` grew from 112 to 120
cases and `tests/herm-suite-memo.bats` (7 cases) covers the real corpus.

**Four defects, and every one was found by a control rather than by review.**

1. **`SELF` is relative** (`./scripts/…`) and the symlink loop preserves it, so `git hash-object
   -- "$SELF"` returns nothing the moment anything resolves it from another directory — the memo
   silently never armed. Caught by the positive control (a1).
2. **`SELF_ABS` then assumed `$ROOT/scripts/`**, which is true of the checkout and false of every
   copy — same silent-off failure. Caught by the /Users/chrisren/.claude/bin/cc-bats case that revises the lint by copying it.
3. 🚨 **The `CHECK_FAILED` veto was a per-suite DELTA, and that is a real unsoundness I shipped for
   one iteration.** A delta vetoes only the FIRST suite whose predicate dies; every suite after it
   compares 1-to-1, comes out equal, and gets **recorded as green — out of a run that exits 2
   precisely because it produced no verdict**. `is_hermetic`'s third state returns fail-SAFE
   'hermetic' so a dead grep cannot fabricate a leak, which means a non-verdict is byte-identical
   to a clean suite at the record site. It is now absolute (`CHECK_FAILED -eq 0`).
4. **A test that passed for the wrong reason.** The read-set case for the rule-6 table used two
   different ENV_ROOT *directories* — but `env_root` is in the read set in its own right, so the
   keys differed by path and the table was never tested. It passed while its mutant stayed green.
   Fixed by holding the root path constant and letting a third file appear inside it.

**The mutants, all with the applied-assertion the last recycle mandated** (`assert s.count(old)==1`;
every one printed `applied` before its verdict was read):

| mutant | verdict |
|---|---|
| readset drops the allowlist | RED, 3 cases |
| readset drops the env table | RED, 1 case — **green until defect 4 was fixed** |
| record drops the emit veto | RED, 3 cases |
| record drops the CHECK_FAILED veto | RED, 1 case — **green until defect 3 was fixed** |
| hit ignores `HERM_MEMO_OK` | GREEN — **equivalent mutant, verified not assumed**: `memo_file_key` returns 1 on `MEMO_OK != 1` (gate-memo.sh:144), so the guard is redundant defence-in-depth |

Two of the five mutants were green against a suite that already looked complete, and each pointed at
a real bug rather than a missing case. **The pattern worth carrying: a mutant that stays green is
either a coverage gap or an equivalent mutant, and the two are told apart by reading the code, never
by adding a case until it goes red.**

**For the next lint.** The shape is now proven and portable: (i) time the arm *through `own_run`*;
(ii) split the cost into fixed vs per-item by scaling the corpus; (iii) write the read set down as
an executable declaration — everything the verdict depends on that is not the item's own bytes;
(iv) cache only "emitted nothing", never a finding; (v) veto on any could-not-run, absolutely;
(vi) mutate each read-set element and each veto separately. Remaining heavy arms, gate-faithful:
`git-identity` 13.3s, `unattended-path` 11.4s (+13.4s selftest), `pane-spawn` 7.7s.
