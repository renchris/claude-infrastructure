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

**First-batch status (2026-10-25 08:45 CDT): not launched, blocked on the terminal.** Every fire of Z1, W0,
W1, W2 failed to open a pane: kitty pid 1881's remote-control socket `/tmp/kitty-1881` answers every
connection with EOF or `write: broken pipe`. This is not load: it persisted as load fell from 487 to 164, and
kitty held exactly 258 unix sockets across an hour. Already filed for the operator by another session as
backlog `8aaba6defbc5` (relaunch kitty if its UI is frozen). Two fire-path hangs found on the way are fixed
and live: unbounded multi-pid `ps -o pid=,lstart= -p` in `scripts/lib/spawn-presence.sh` (`57730d18c`) and
`bin/cc-sessions` (`19c297766`). Re-fire: `bash /tmp/zh-fire/fire-when-kitty.sh` (waits for kitty, fires the
four briefs `/tmp/fire-zh-{Z1,W1,W2,W0}.txt` one at a time; if /tmp is gone, rebuild the briefs from this
plan's wave rows and the mid-turn REPORT §12). Branches `feat/zh-*` and their worktrees exist, kept by the
UNKNOWN-outcome cleanup; no session ever ran in them.

**First batch DONE (2026-10-26 07:35 CDT), all landed off, content-verified and live.** The kitty relaunch
cleared the terminal blocker; briefs now live in `~/.reso/zero-hitl-2026-10-25/briefs/` (a reboot wiped /tmp).
- Z1 (pane 129): `6fdd12b32` migration **0084** (0079-0083 were taken) + test, `5c80ad5ad` run-cc-lr-alone rule
  in `commands/limit-recover.md` (the skill file the brief named does not exist) and the never-ask sentence.
  Operator step `86df376a8d6e`: run 0084 `--confirm settings.json` (7 rules).
- W1 (pane 130): `45de9dd6d` + `cfaed9d73` ps-free census, shadow behind `recon/ps-free.mode`; 1,942-row parity
  vs ps, 0 mismatches. Operator step `e6c53dd64680` (reconciler reload). Left for W7b: `act.py:809` still uses ps.
- W2 (pane 131): `bf61ef0f6` (+ fixups `d4f0ced10`, `61662b193`) three-key attribution API, `CC_BILLING` off.
  Ledger contract for W3 is in the `scripts/lib/billing.py` docstring.
- W0 (pane 132): `407da1095` + `9597ea91c`; 2.1.293 CERTIFIED (`~/.reso/lanes/cert/2.1.293.json`). P-P1 pointer lane
  PASS (next2 to next mid-turn, adopted 22.7 s after the flip, 0 x 401, no token file), P-S1, P-R1, P-L4 PASS;
  P-L2 has not yet spanned a real refresh (`LANE_PL2_MAX_WAIT_S`). W9 must set `GATE_LANES_GATING=1`.
- Lead fixes: `b02a03703` settles the agents of an ended workflow run in `live_subagents_of` (the root cause
  of pane 314's own move never firing, found by W1) and repairs trunk's red census case 25.
- Learned: a dispatched wave stalled 4 h on a PreToolUse `rm -r` confirmation no one could answer; the shared
  brief now bans prompting commands by name.
- Next: W3-W8 wait on `69c31338d082` (recommend build-with-switches-off, 65%) and `be5c5e83800f` (pointer
  lanes, 88% after P-P1). A and B (rebalancer landing band, burn meter) are ungated and fire next.
- **A and B DONE (2026-10-26 09:45 CDT), inert and live.** A (pane 153): `5b6a8e202` `claude-accounts --rebal-band
  --json` (fixture sinks next4, next3; live today none, next3 already at 81%), plus trunk-red test fixes `f66b205aa`
  and `4340ca5f2`; `bin/claude-accounts` is free for W5a. B (pane 154): `9c535609b` `lr_burn.py`, replayed hours
  0.0% off the independent census; priced pp/h vs measured pace ranges 0.20-1.46 by account-hour, so W8 must
  apportion with prices but meter with the account's own pace. Nothing ungated remains: W3-W8 and C-F wait on §3.

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
