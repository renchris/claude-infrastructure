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

  Rows closed so far this effort: **0**. Filed: **0**. Store: **470 → (re-derive at effort close)**.
