---
status: in-progress
---

# Zero-human-in-the-loop account rotation — build plan

Scope (frozen, 2026-10-25): session moves and limit recovery run with no operator prompt and no auto-mode
denial, and can move a busy session mid-turn without disruption or a transcript fork — built as the waves
below, each landed inert behind its switch, with every operator-only step (migrations, activations, the
decisions in §3) filed rather than performed.

Sources: `docs/research/midturn-account-move-2026-10-25/REPORT.md` (mid-turn design, waves W0–W9, §12),
`docs/research/account-rotation-100p-2026-10-24/REPORT.md` (rebalancer, waves A–F, §6), and the
zero-HITL survey (permission surface, auto-mode, triggers, activations; each adversarially verified) at
`~/.reso/zero-hitl-2026-10-25/` — durable copy, `/tmp/zero-hitl/` is the original.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave.** S (a dispatched session in its own worktree, landing only through the
project-local `/ship` and converging with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`) for every
wave, except W9 and the 0079 run, which are O (the operator runs a numbered migration). No L or T waves.

**Lead.** Pane 314 (session lineage 30729231 → 58ec5fef). Budget: this plan, each wave's return ping and a
by-content land check, ≤80K tokens. Succession point: after the first batch lands, or at 50% context,
whichever is first — recycle with this file as the prompt.

**File ownership.** Exclusive per wave. Mid-turn waves follow REPORT §12 / SYNTHESIS §10. Additions here:
Z1 owns `migrations/0079-*`, `skills/limit-recover/SKILL.md` and `CLAUDE.rules.slim.10-session-close.md`;
A owns `bin/claude-accounts` until it lands (W5a takes it after); B owns the new
`scripts/limit-recover/lr_burn.py` (W8 extends it after). No wave touches `hooks/validate-bash.sh`
or `hooks/boundary-handoff.sh` (the `~` spelling fix landed in `cfba3c54a`).

| wave | goal | locus | deps | can start |
|---|---|---|---|---|
| **Z1** | permissions + guidance: migration 0079 (allow rules for `cc-lr`, `lr-handoff.sh`, absolute `handoff-fire.sh`; optional `autoMode.environment` line), "run `cc-lr` as the only command in the call" in the limit-recover skill, and the "moving sessions between accounts is routine: do it, never ask" paragraph in the slim close rules | S, then O for 0079 | — | now |
| **W0** | lane certification probes (P-P1 pointer lane decides decision `be5c5e83800f`) | S | — | now |
| **W1** | ps-free reconciler census, shadow | S | — | now |
| **W2** | three-key attribution API (home / billing / identity) | S | — | now |
| **A** | rebalancer landing band in `claude-accounts` (`--rebal-band --json`) | S | — | now |
| **B** | burn meter `lr_burn.py` | S | — | now |
| W3–W8 | lane broker → binding → readers → re-home → move front door → lane rebalance | S | W0 PASS + decisions `69c31338d082`, `be5c5e83800f` | after §3 |
| C–F | restart-actuator rebalance (turn-end catch, sink arm, controller job) | S | decision `69c31338d082`: if "Never", build C–F as designed; otherwise W7a/W8 subsume them | after §3 |
| W9 | lane activation migration 0080 + runbook | O | all | last |

First batch, fired 2026-10-25: Z1, W0, W1, W2 (A and B once the capacity gate admits; the box was at
12–13 sessions mid-turn against a ceiling of 8 at plan time).

## 1. Why this shape

- **Allow rules, not hooks, are the permission fix.** Verified in the 2.1.293 binary: a narrow
  `permissions.allow` match is settled before the auto-mode classifier and is never re-routed by the
  server-side hold; a chained or piped line can never match a rule, and three such lines were held and then
  denied during a "Classifier unavailable" outage while 22 of 22 single rule-matched commands ran
  (`verify-auto-mode.md`). A PreToolUse `allow` skips the classifier today only because server flag
  `tengu_virtual_knuth` is off — not something to build on.
- **Waiting for idle does not move anything.** Busy sessions are 66.8% of wall time and the restart mover
  moved 5 of 149 busy rows (mid-turn REPORT §1), so the restart-based rebalance (C–F) is worth building only
  if the zero-restart path is ruled out.

## 2. Known defects carried in

- `cc-lr move --status` reports a batch `done` while rows sit `pending / hold:in-flight` (batch
  `20261025T065251Z-next-next4-13375`: panes 217, 271, 301, 314). Owner: W7a (move front door verdicts).

## 3. Operator decisions gating W3+

`69c31338d082` (class C, 55%: switch a running session's paying account without restarting?),
`be5c5e83800f` (class C, 70%: pointer lane vs copied token), `c7156c87c1b6` and `3e362e7d3be1` (class B,
defaults stand unless overruled). Full options: mid-turn REPORT §13.
