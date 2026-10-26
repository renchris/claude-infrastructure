# Self-recycle latency and the "Background work is running" dialog — 2026-10-26

Trigger: pane 7 (Otto 4413, `/tmp/fire-otto4413.txt`) self-recycled at 06:40Z. The operator watched
the "Background work is running" dialog for about a minute; the watcher then chose "Move to
background and exit", stopped the background copy it had just created, and the successor ran.
Watcher log: `$TMPDIR/handoff-recycle-7-1792996800-PXc2sT.log`. Ledger: `~/.claude/logs/handoffs.jsonl`
rows 1182-1191.

## Answer

The plain self-recycle loses ~15 s to a polling cadence and to a dialog it raises on itself. The
cron/background-work self-recycle loses another ~40-60 s to a slow classification and a background
copy it then kills. The fastest path that stays fault tolerant is to keep the existing watcher and
change three things: (1) for a self-recycle, the WATCHER types the first `/exit`, after the
recycle's own tool call has returned (no dialog); (2) a dialog, when one still appears, is detected
within ~1 s rather than at 15 s; (3) a dialog whose only background work is session scheduled tasks
or the inbox watcher is answered "Exit and stop tasks", with the session crons carried into the
successor's prompt. Failures keep today's retry ticket and recovery packet and gain one dedupe'd
research-session fire per failure class.

## Measurements (ledger, watcher's first row → `recycle-successor-claimed`)

| path | n | latency | what happens |
|---|---|---|---|
| SIGNAL (remote move, at rest, SIGTERM) | 15 | 10-24 s, median ~14 s | no dialog, no keystroke |
| SELFCALL (dialog raised by the recycle's own call) | 30 | 24-52 s, median ~37 s | dialog sits until the 15 s check, then Esc + `/exit` |
| SELFCALL + KEEPWORK (also a cron or bg job) | 5 | 76-110 s | as above, then classification, keep-work, bgcopy fork + stop |

34 of the 47 engaged self-recycles in the ledger took the SELFCALL path. In all 34
`recycle-bgwork-selfcall` rows the caller had already returned when the watcher looked
(`returned:0s`); the dialog was first seen at 15-21 s only because that is the poll cadence
(`rcy_bgwork_every`, default 15, `scripts/handoff-fire.sh` ~line 12628). Esc + `/exit` after the call
returned then exited cleanly 34 of 34 times.

## Root causes

- **R1 — cadence.** The dialog check runs at 15 s after `exit-committed`, every 15 s. The dialog is up
  within ~1 s of the `/exit`.
- **R2 — the foreground types `/exit` inside its own tool call.** On kitty the composer is readable
  mid-turn, so the self-recycle does not defer (`hf_recycle_defer` runs only on an unreadable
  composer, `recycle_composer_block`), and the foreground's `/exit` (typed path after
  `hf_exit_signal` declines, ~line 20593) lands while the Bash call that runs `handoff-fire.sh` is
  still alive. Claude Code counts that call as background work and raises the dialog. The selfcall
  arm (`rcy_bgwork_selfcall_retry`) then repairs it. The dialog exists only because of the order.
- **R3 — session scheduled tasks read as "none".** `hf_bg_work_kind` classifies child processes. A
  `CronCreate` task is in-process, so the Otto pane read `none shipland=no pids=-`; stop-if-watcher held,
  the self-recycle default fell back to keep-work, and "Move to background and exit" forked a second
  live copy (with a live cron that could fire a poll turn) that `rcy_bgcopy_stop` stopped 2 s later.
  The cron dies either way; keep-work bought nothing and opened a race. 2 of the 4 keep-work logs in
  `$TMPDIR` are this case (pane 7 twice); the other 2 were real work (`work pids=…`).
- **R4 — ~38 s between deciding and answering.** The watcher printed `bgwork@21s` (computed at
  06:40:48) and the answer row is stamped 06:41:26. Between them: `hf_team_live`, registry `jq`,
  `hf_bg_work_kind`, a 500-line `session read`, `goal_live_for_sid` (a `find` over every projects
  dir), `transcript_for_sid`. Load was ~70-100. Not profiled yet.
- **R5 — the existing deferred path is not the answer as built.** `hf_recycle_defer` → turn-end wait
  → at-rest proof → SIGTERM exists end to end, but production ran it twice (pane 316, 2026-10-25) and
  both held: the turn "ended", a Stop-hook continuation started a new turn, and the post-wait composer
  gate read a running turn for 180 s (`recycle-held-unreachable`, snapshot
  `~/.claude/logs/composer-snapshots/20261025T042044Z-win316--held-unreachable-gate.ansi`). Waiting for
  end-of-turn couples the recycle to every Stop hook in the fleet.

## Design

**D1 — delegated first `/exit` (self form only).** When `RCY_CALLER_PID` names the recycle's own tool
call, the foreground runs every gate it runs today (composer gate, last read, load gate, resume debt),
writes `exit-committed` plus a new `exit-delegated` marker, and returns without typing. The watcher,
seeing `exit-delegated`, polls `kill -0 $RCY_CALLER_PID` at 0.2-0.5 s (bound
`CC_RECYCLE_SELFCALL_WAIT_S`, default 60), then types `/exit` through `hf_exit_readback` (read back,
CR only on an exact `/exit`, receipt otherwise). This is the selfcall retry's own mechanism (34/34
clean) without the first `/exit`, the dialog and the Esc. A call that does not return inside the
bound holds with the existing retry ticket, nothing typed. Kill switch `CC_RECYCLE_DELEGATE_EXIT=off`
restores today's order. Not for remote, resume or transplant recycles (no caller pid).
Open measurement for the implementer: whether a `/exit` typed while the model is still streaming its
closing text interrupts that text or waits for it. Either is acceptable; record which.

**D2 — fast dialog detection.** After `exit-committed`, check the dialog every 1 s for the first 30 s,
then every 15 s as today (`rcy_bgwork_next` / `rcy_bgwork_every`). Keep the `CC_RECYCLE_BGWORK_MAX`
keystroke bound. Each check is one `session read`; 30 reads is cheap next to a minute of an
operator-visible dialog.

**D3 — scheduled tasks are not work the recycle preserves.** Read the predecessor transcript for
`CronCreate` tool uses not followed by a matching `CronDelete` and not `durable:true` (durable tasks
survive the exit on their own). If the dialog's listed items are only scheduled tasks and/or the inbox
watcher, and `hf_bg_work_kind` reads `none` or `watcher`, answer "Exit and stop tasks" (the existing
stop-if-watcher arm, widened) and append the live session crons to the successor prompt file as a
"re-create these with CronCreate" block before the key is sent (the staged command reads the prompt
file with `$(cat …)` at launch, so the append is seen). Real work (`work pids=…`, ship-land) keeps
today's keep-work answer. Kill switch `CC_RECYCLE_CRON_CARRY=off`.

**D4 — bound the classification.** Profile the R4 gap with timestamped `PS4` under load, then cache
or drop what the self-recycle answer does not need (e.g. `goal_live_for_sid` resolves the transcript
once per watcher, not per call). Target: answer within 3 s of detection.

**D5 — failure escalation.** Every terminal failure arm of the watcher and foreground (`recycle-held-*`,
`recycle-dead`, `recycle-unverified`, `recycle-watcher-orphaned`, `exit-signal-ignored`) already
writes a ledger row, and the self form writes a retry ticket that `hooks/boundary-handoff.sh` turns
into a re-run. Add `hf_recycle_escalate <class>`: write
`~/.claude/autonomy/recycle-incidents/<class>.json` (count, last ts, evidence paths: watcher log,
ledger rows, screen snapshot), and on the first occurrence of a class in 24 h fire one research
session (`handoff-fire.sh`, headless anchor, `--goal` = a root-cause doc with a proposed fix at
`docs/research/recycle-incident-<class>-<date>.md`). Bounds: one fire per class per 24 h, three per
day overall, `CC_RECYCLE_ESCALATE=off`. The retry still runs first; the research session is for the
cause, not for this pane.

## Rejected

- **SIGTERM at end of turn (the existing deferral, made unconditional).** 0 of 2 in production (R5);
  depends on Stop hooks letting the session go idle; adds the turn's closing time plus a 10 s settle.
- **SIGTERM as soon as the call returns.** No dialog and ~1.4 s, but it destroys the model's closing
  turn mid-stream and skips its Stop hooks; the at-rest gate exists precisely to forbid that
  (`docs/research/recycle-sigterm-proof-2026-10-11/REPORT.md`, mid-turn run m2).
- **Answering keep-work for crons (today).** Forks a live copy whose cron can fire a turn, then kills
  it; the cron is lost either way.

## Expected result

Plain self-recycle: watcher start → claimed ≈ commit time + ~2 s, i.e. the SIGNAL path's 10-24 s, with
no dialog drawn. Cron/watcher self-recycle: the same plus one dialog answered within ~2 s, no
background copy, crons re-created by the successor.

## Verification the implementation owes

1. Suites: the watcher's bats coverage for the selfcall arm, stop-if-watcher and the precommit/K1
   markers, plus new cases for `exit-delegated`, the 1 s cadence, cron carry and escalation dedupe.
2. Live: ≥5 plain self-recycles and ≥2 with a session `CronCreate` task on kitty, reporting per run
   watcher-start → claimed from the ledger and whether any dialog was drawn (screen reads in the
   watcher log). Pass: zero dialogs on the plain runs, median ≤ 20 s, cron runs with no
   `recycle-bgcopy-stop` row and the cron present in the successor.
