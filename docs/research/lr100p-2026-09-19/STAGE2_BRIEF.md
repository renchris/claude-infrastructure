# STAGE 2 (Opus 5, high) — implement `docs/plans/LIMIT_RECOVER_100P.md` § 10 with Agent Teams, in THIS pane

You are stage 2 of a two-stage ladder (CLAUDE.md § Frontier Tier Routing). Stage 1 (Fable 5.1) wrote the plan and
its receipts; it edited no code. You implement. Same pane, same session uuid, fresh context.

## Read first, in this order (nothing else is needed to start)

1. `docs/plans/LIMIT_RECOVER_100P.md` § 10 — the measured root cause (§10.1), the decision (§10.2), Phase 0, the
   W8–W12 wave table with file:line anchors, **§10.3 the critic pass (binding amendments — read it WITH the table)**, the DoD, kill switches, open decisions, dropped items.
2. `docs/research/lr100p-2026-09-19/inplace-default-2026-09-20.md` — the receipts (R1–R10) behind every §10 claim.
3. `docs/plans/LIMIT_RECOVER_100P.md` § 9 Phase 0 + Waves — the rules block Round A and W2 ran under (brief ≤ 150
   lines, pre-grepped anchors, "Stop on issue, message lead", one writer per file, smallest-diff-first merges).
4. `.claude/CLAUDE.md` — never commit in the shared checkout; land via the project `/ship`; converge on the degraded
   tier, never `--force`.

## Scope (frozen)

`/limit-recover` recovers a limit-blocked session IN ITS OWN PANE BY DEFAULT — same kitty window id, same session
uuid, new account — from every driver (attached session, detached fleet run, launchd poller); a pane whose session
has moved is a named, retirable state (`HUSK`); the bare spawn survives only where there is no pane. Waves W8–W12 as
written in § 10. Iron rule 7: nothing here lands a recovered session's work.

## The one fact that decides the order

The in-place recycle has NEVER succeeded from a detached or daemon driver (0 of 9 on record) because
`handoff-fire.sh:9247` pins the terminal verdict from the DRIVER's ancestry (`bin/cc-in-kitty` rc 1 for any
orphan ⇒ `CC_TERM=iterm2` ⇒ the kitty pane "resolves to no tty"). **W8 fixes that and is the precondition of W11
and of W12's arm (f).** Do not start W11 before W8's suite is green. `cc-in-kitty` itself is NOT to be changed
(§10 Dropped, first row).

## Step 0 — land the plan commits (docs-only; trunk was RED on two W2 suites and the sibling is fixing them)

Branch `lr-inplace` (this worktree) carries two docs-only commits ahead of trunk: the § 10 plan commit and the
lesson `docs/lessons/remote-pane-identity-is-the-targets-not-the-drivers.md`. Their land was refused at
2026-09-20 02:2xZ by the smoke gate on two suites that map to W2's landed diff, not to these commits
(`ship.log`: "NONE of them map to your diff … the trunk delta e4a4fcc49..bdb1a4553"). The sibling that landed W2
(`a4241557`, pane 127) replied at 02:05 local: **"I AM ON BOTH … landing within the next gate round; I will ping
you when it is on trunk."** So: `git fetch origin && git rebase origin/main`, confirm both are green on trunk, and
`bash scripts/ship-land.sh` from this worktree. Only if the sibling's land has NOT arrived and the gate refuses
again on the same two suites, the fixes are exact and ≤ 5 lines — do them here, first:

1. `tests/handoff-alarm-records.bats:323` — the DELIBERATE pin `[ "$(grep -c '^    hf_alarm ' "$FIRE")" -eq 6 ]`
   is 7 on trunk: W2 (`eaf7c82da`) added the SEVENTH site, class `recycle-boot-indeterminate`, at
   `handoff-fire.sh:6923`. Per the test's own comment: add that sha + class to the comment, raise the count to 7.
2. `tests/handoff-fire-capacity-gate.bats:513` pin-guard — `tests/handoff-probe-preconditions.bats` setup() has
   `export CC_FIRE_CAPACITY_GATE=off` but not `export CC_FIRE_HEADROOM_GATE=off` (`_setup_gate_off:376-377` needs
   both). Add the one export beside `:42`.

Never both of you on the same two lines: check trunk before touching either.

## Execution (Phase 0 of § 10, restated)

- Round B — spawn in ONE message: **W8** (handoff-fire remote-pane terminal identity + lr-handoff socket block
  move + `tests/handoff-remote-pane-term.bats`), **W9a** (lr-fleet `--mark` refusal + `--duplicates` dedupe),
  **W10-census** (lf_locate pane-first pass + `HUSK` disposition + lr-lib predicates + the LIMIT_DETECT amendment
  text). Each teammate: `Agent({ name, model: "opus" })`, own worktree off trunk, brief ≤ 150 lines with the
  anchors from § 10 re-grepped at its HEAD.
- Round C — after W8 lands: **W9b** (`pin_still_live` ancestry), then **W10-actuator** (`--retire-husks`, poller
  HUSK arm) ∥ **W11** (default flip, `--spawn`, idempotent transplant, rc-4 text, command doc).
- Round D — **W12** (drill arms f + g; live acceptance: retire panes 110 / 126 / 150 through the new actuator and
  prove it with a fresh `kitty @ ls`).
- Capacity: `cc_capacity_probe` refused at plan time (load ~4/core against 2.0). Re-measure before every spawn; a
  refused spawn is a PARK (fall back to workflow agents in pre-created worktrees, as Round A did) — never a retry loop.
- Lead: merge smallest-diff first; each wave's bats suite + `shellcheck -S warning` on every touched `.sh` green in
  YOUR worktree before its land; `bash scripts/ship-land.sh` from your worktree; converge with
  `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` and confirm `LIVE_SHA` via `wrap-ledger.sh --machine`.
  Hold ≥ 50 % context for merge judgment; recycle (same pane) after Round B lands.

## Gates every wave must keep green (named in § 10 DoD)

`tests/handoff-selfclose-kitty-identity.bats` · `tests/handoff-selfclose-terminal-pin-order.bats` ·
`tests/handoff-fire-kitty-daemon.bats` · `tests/cc-in-kitty.bats` · `tests/handoff-recycle-remote-resume.bats` ·
`tests/handoff-selfclose-transplanted-source.bats` · `tests/lr-fleet.bats` · `tests/lr-lib.bats` ·
`tests/lr-handoff-launcher-quoting.bats` · `tests/capacity-admit.bats`. Never the full suite in a teammate; the land
gate is admission-exempt and runs it.

## Definition of done for stage 2

All § 10 DoD bullets measured true; W8–W12 landed on `origin/main` by content (`git ls-tree origin/main -- <paths>`
present, `git diff` empty on your paths); live layer converged; `lr-fleet.sh --locate` shows `0 HUSK` and
`--duplicates` prints nothing after the live acceptance; § 10's status log carries the landed shas. Open decision 1
(`--spawn` reachability) is the operator's — ship option (a) and name it in the close.

## Do not

- commit in `~/Development/claude-infrastructure`; run the launcher from a Bash tool call; hand-spawn a
  `recover-<sid8>` window; `--force` the converge; write a kill phrase into any brief.
