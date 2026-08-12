---
status: open
---

# MASTER: verification integrity — the instruments that decide red and green are wrong

**Condition key:** `master-verification-integrity` · **Live members 2026-08-12:** 34 (28 open · 6 blocked)
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
