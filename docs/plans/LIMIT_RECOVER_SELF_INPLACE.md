---
status: done
---

# LIMIT_RECOVER_SELF_INPLACE — a session moves itself, in place, with no external help

Scope (frozen): a live session can move ITSELF to another account in place (same pane, same session uuid, full transcript) with no operator step and no external terminal, both (a) when it invokes the move from its own turn and (b) when an originating peer session requests it; root causes found by a research Dynamic Workflow; a plan written at docs/plans/LIMIT_RECOVER_SELF_INPLACE.md (Phase 0 per plan-conventions); implemented with tests; landed and LIVE in the enforcing store per this repo's ship policy; proven by a real in-place self-move of a live session.

Goal (operator, 2026-10-17): proven by printing, after the move, the same session id running under the new config dir, plus the landed sha on origin/main; do not weaken any safety gate.

Hard constraints: no safety gate weakened (at-rest checks, single-copy fences, claim locks — fix the self path, never delete a guard); reso-management-app touched only by the one proof move of session 43e6eb4b; quota-heavy actions bounded, throwaway sessions first; operator panes moved only when idle with nothing in flight.

## Phase 0 — Agent Team Orchestration

- **Execution locus per wave**
  | wave | what | locus | why |
  |---|---|---|---|
  | W0 research | reproduce + trace each failure to file:line | Dynamic Workflow (workflow-lean, read-only, adversarial verify) | read-only fan-out of ~6 same-shaped units |
  | W1 implement | self-path fixes across handoff-fire.sh / cc-lr / lr-handoff | T (named teammates, one per disjoint file) or L | decided after W0; the files are disjoint per root cause, combined output small |
  | W2 land + converge | /ship, deploy-live degraded tier | L | lead-only by policy (standing-land) |
  | W3 proof | throwaway self-move, peer-requested move, then 43e6eb4b | L | needs live panes the lead watches |
- **Task size per unit:** 40–150K output tokens, 3–6 files per teammate.
- **Lead context budget:** hold ≥50% for deciding; **succession point:** after W2 lands (recycle before W3 if over ~60%).
- Worktree: lead on `lr-self-inplace`; teammates in their own worktrees, merged by rebase + ff.

## Evidence (session 43e6eb4b, pane 8, next4 → next, 2026-10-17/18)

1. Peer-sent `handoff-fire.sh --recycle --transplanted-source --source-pane 8 --source-session 43e6eb4b …` run from the session's OWN Bash tool: transplant copied + confirmed, then `recycle ABORTED before /exit (held: busy): transcript not at rest (rc 1 …)`, unconfirm rc 0. A background cc-await-ping watcher was also running.
2. Retry: `--recycle REFUSED: --transplanted-source, but session 43e6eb4b has NO transplant tombstone` — the abort's unconfirm removed it; the peer's retry line was not re-runnable.
3. `cc-lr switch --target next --dry-run` → "a real run would QUEUE"; real run → "REFUSED — the reconciler is live and it has no switch lane … Use: cc-lr move". Dry and real disagree.
4. `cc-lr move --sid <self> --to next` (own Bash AND operator `!`) → `hold:self`.
5. Separate terminal, `cc-lr move --pane 8 --to next --until-idle 900` → `hold:in-flight — another actuator holds its claim (pid 51575)`; 51575 was the worker of the settled batch 20261018T000816Z-next4-next-49288 (result NOTMOVED: HELD:unreachable, lr-handoff rc 6). Leftovers: locks/43e6eb4b….aborted-20261018T004143Z, ….unconfirmed-20261018T004117Z.
6. `cc-lr move` holds a session with a background job, while the WAKE FLOOR stop hook demands every idle session run a background cc-await-ping watcher ⇒ an idle healthy session is unmovable by construction.

## Lead's first trace (pre-W0, to be verified by W0)

- E1: `scripts/handoff-fire.sh:15344` — any `--source-pane/--source-session` selects the REMOTE form (`RCY_REMOTE=1`) even when the named pane IS the caller's own; the remote form's last read (`hf_recycle_last_read`, ~:3489) then re-proves at-rest on the caller's own transcript, which is mid-turn by construction. The self form deliberately reads the composer only (comment at :3486-3488).
- E3: `bin/cc-lr` cmd_switch (~:1873) returns the dry run BEFORE `cl_recon_queue` applies its switch-lane refusal (:253-258).
- E1 origin: the ORIGINAL external move (batch 20261018T000816Z) reached `handoff-fire --recycle` remote form, which held because kitty's control socket `/tmp/kitty-44163` refused the connection (transient: it answers in 0.05–0.10 s at 2026-10-17 22:0x local); lr-handoff aborted the admit (rc 6, HELD:unreachable). The held recycle's pane-close row was then retried by `scripts/pane-close-retry.sh:260`, which `cc-notify`s **the pane's occupant — the subject session itself —** with "RECYCLE RETRY … re-run: handoff-fire.sh <argv>". The subject ran a REMOTE-form command about itself from inside its own turn ⇒ E1. A remote recycle's retry must be re-run by an external actuator (the move lane), never handed to its subject.
- Self-turn deferral already exists for the plain self form (`hf_recycle_defer`, handoff-fire.sh ~:5095-5175: fork, wait for the caller's tool call to return and the transcript to settle, then run every gate) but `hf_recycle_defer_eligible` excludes `RCY_REMOTE=1` and any `RESUME_LAUNCHER` (~:5087) — i.e. exactly the transplant self-move.
- E6 nuance: the move census already treats a cc-await-ping-only Bash shell as `watcher`, not `work` (`lr-upgrade.sh:540-556`), unless the watcher shell has a child other than cc-await-ping/tail; W0 to establish which classifier held.
- E3/E4 loop: `cc-lr move` holds self (`bin/cc-lr:1229`) and points at `cc-lr switch` (:1629), which refuses while the reconciler is live and points at `cc-lr move`.

## W0 — Research (Dynamic Workflow) — DONE (run wf_118bf2fb-7c0, 7 tracers + 2 skeptics per finding)

Verified root causes (skeptic verdicts in the run journal; file:line at b3ec7e5e8):

| # | root cause | evidence | verdict |
|---|---|---|---|
| R1 | `--source-pane/--source-session` always selects the REMOTE recycle form, even for the caller's own pane; its post-confirm last read (`hf_recycle_last_read` :3489-3580) re-proves at-rest on the caller's mid-turn transcript ⇒ always `held: busy` from self | 1 | 2/2 upheld |
| R2 | A remote recycle held on a deaf kitty files an owed `recycle` row with the WORKER's argv (`hf_recycle_owed_record` :2080), and `pane-close-retry.sh drain_recycle` :249-264 mails it to the pane's occupant, which is the SUBJECT ⇒ the subject ran a remote argv about itself, while worker 51575 still held the claim, lock and record id (two actuators; handoff-fire / lr-handoff / lr-transplant never read `runs/by-sid/<sid>.active`) | 1, 2, 5 | 2/2 upheld |
| R3 | The hold's unconfirm correctly withdraws tombstone + lock + target copy (single-copy guard, KEEP), but the stand-down prints `Re-run: $CMD` = the resume LAUNCHER line, never a re-admit; the replayed argv can never pass again | 2 | 2/2 upheld; the `recycle ABORTED … (held: X) … unconfirm rc 0.` sentence is regex-parsed by lr-handoff.sh:1975 and lr_recon test_settle.py — append, never reword |
| R4 | `cc-lr move` maps the caller to terminal `hold:self` (bin/cc-lr:1229) and `rotate` points it at `switch` (:1629); `switch` refuses while the reconciler is live (:253-258) and points at `move` ⇒ no self lane. The working lane (a detached poller worker that waits for idle, then acts as an outsider through every gate) exists but self rows are never routed to it | 3, 4 | 2/2 upheld |
| R5 | `switch --dry-run` returns "would QUEUE" (:1877) before `cl_recon_queue`'s refusal ⇒ dry and real disagree | 3 | 2/2 upheld |
| R6 | The first domino: the worker's remote recycle held at the kitty precheck ("did not accept a connection") on a box at load ~290; the probe's own bound timing out reads the same as a refusal (`kitty_socket_accepting` :1435), and the worker never retries a clean, fully-aborted `HELD:unreachable` (lr-move-worker.sh W5/W6) ⇒ the only retry left was the mail to the subject | 5 | upheld (65-80%) |
| R7 | The load hold (:3763-3800, :18375; incident F1 2026-10-09, KEEP) fires AFTER the confirm for every resume recycle (they never stage), so on a loaded box every move pays admit + confirm + unconfirm and leaves a `locks/<sid>.unconfirmed-*` dir | 1, lock leftovers | forensic tracer, 85% |
| R8 | The poller is the only move-request consumer; a 45+ min tick strands requests, and `cc-lr move` happily queues duplicate requests for one sid | 5 | forensic tracer, 65% |

Refuted / not causes:
- E6 (wake-floor watcher blocks a move): REFUTED 2/2. Both job classifiers already count a cc-await-ping-only shell as `watcher` (lr-upgrade.sh:540-556, handoff-fire.sh ~:2868); the move lane answers the /exit dialog with stop-if-watcher and the successor re-arms. Observed background-job holds were model-written poll loops (real work). No classifier change.
- E5 "stale claim after a settled batch": REFUTED 2/2 as stated. Worker 51575 was genuinely live for ~36 min (lr-handoff 24.6 min to hold on the deaf socket, then ~11 min in one verdict read at load ~290); the hold was the guard working. The 33 s result-to-release gap in `finish()` is real but latent (fix anyway, cheap).
- Live state 2026-10-18 03:24Z: load 316 on 10 cores (31/core vs the 8/core bound) — no in-place resume recycle can pass R7's gate on this box until load falls. Not a defect; the proof waits for it.

## W1 — Implement (locus T: four teammates, disjoint files)

Why T, not S: four small units (each tens of lines + tests) whose outputs must be merged and exercised together in this session's proof; combined output small; the lead's window is at ~10%.

| teammate | files (sole owner) | changes |
|---|---|---|
| `sip-cclr` | bin/cc-lr, scripts/limit-recover/lr-move-batch.sh, tests/cc-lr*.bats, tests/lr-move-plan.bats | R4: self row ⇒ `wait:self` (act=wait, budget max(--until-idle, CC_LR_MOVE_SELF_WAIT_S=900)); cmd_move never blocks on a self row ("end your turn now"); `switch` self with the reconciler live ⇒ delegate to the move lane; R5: dry run shares the decision; rotate hint ⇒ `cc-lr move --sid`; R8: refuse a duplicate unclaimed request for the same sid; batch census pinned `LRU_SELF_SID=` |
| `sip-hfire` | scripts/handoff-fire.sh, tests/handoff-recycle-*.bats, tests/handoff-fire-kitty.bats | R1: remote form naming the caller's own session/pane ⇒ REFUSED rc 2 before any transplant phase, naming the move-lane command; R2: `--transplanted-source` remote pre-pass refuses when a live foreign holder owns `runs/by-sid/<sid>.active`; owed row records `form=remote` + record id; R3: after an unconfirm on a transplanted source, an extra line names the re-drive (`cc-lr move --sid S --to A`), existing sentence bytes unchanged; R6: probe timeout = `unprovable`, re-probed with backoff (≤180 s) when the caller is detached |
| `sip-pcq` | scripts/pane-close-retry.sh, scripts/limit-recover/lr-handoff.sh, tests/pane-close-queue.bats, tests/lr-handoff-*.bats | R2: drain_recycle never mails a remote row (argv has `--source-pane` or `form=remote`) to the pane; drops it; lr-handoff clears the pane's owed row after a clean abort |
| `sip-worker` | scripts/limit-recover/lr-move-worker.sh, tests/lr-move-worker.bats | R6: bounded retry (2×, 45 s backoff) of a clean `HELD:unreachable` with abort rc 0, claim kept, guards re-checked; R7: before actuate, wait while load/core is over `hf_recycle_load_bound`, NOTMOVED `HELD:load` with nothing touched at the deadline; claim released right after the result write |

**Ownership correction (2026-10-17 22:3x local).** A parallel session, `lr-inplace-immediacy` (pane 362, plan docs/plans/LR_INPLACE_IMMEDIACY.md, started 21:07), already has teammates on lr-move-worker.sh (load pre-gate), lr-move-batch.sh, bin/cc-lr's cmd_move arg loop + lr-upgrade census, and handoff-fire's kitty precheck (:1420-1500). One owner per file wins, so: `sip-worker` stopped and its three items (unreachable retry, load wait, early claim release) were routed to that session by cc-notify; `sip-hfire` dropped R6's probe change; `sip-cclr` dropped the lr-move-batch.sh pin (routed) and the R8 dedup, keeps only the self/switch hunks in bin/cc-lr with tests in a new tests/cc-lr-move-self.bats. Whoever lands second rebases.

**W1 status (2026-10-18 00:50 local).** Merged on `lr-self-inplace`: `0f964b7ce` (cc-lr self lane, sip-cclr), `933839de3` + `e198fb14c` (pane-close-retry drop + lr-handoff owed-row spend, sip-pcq), `36ec2f1b3` (handoff-fire R1/R2/R3, committed by the lead from sip-hfire's worktree), plus a shellcheck-header fix. `sip-worker`'s finished `69ed4dae1` stays on `lr-sip-worker`, offered to the immediacy session (not landed here). Behavioural suites NOT yet run: the box sat at load 400-670 (40-67/core) from ~22:00, and `cc-bats` refuses admission while live bats roots ≥ its ceiling and load/core ≥ its bound (bin/cc-bats ~:701); shellcheck itself ran at 0.1% CPU. Teammates looped on the refusal (one loop is unbounded-ish: 150×20 s per suite); a lead `kill` of that loop was denied by auto mode and not re-attempted.

**W1 — DONE (2026-10-18 ~05:40 local).** Suites run by hand, green: cc-lr-move-self 5/5, handoff-recycle-self-source 13/13, lr-handoff-owed-row 4/4, cc-lr-request 21/21, handoff-recycle-remote-resume 48/48, cc-lr-rotate-queued 3/3. Pre-existing reds proved on base, not ours: pane-close-queue teammate-auto-shutdown; handoff-recycle-turn-wait #4/#6 (event-then-ticket race under load). Learning: compound `[[ a ]] && [[ b ]]` assertions in a bats control hide the first leg from errexit; split them (51e3374e2).

## W2 — Land + converge — DONE

Landed via `scripts/ship-land.sh` in the range ending `51e3374e2` (land-verify: 10 paths content-identical; the smoke leg was shed for load, so the land itself is behaviourally ungated — the suites above are the behavioural evidence). Converged live on the degraded tier (`CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, 2196228fc → 51e3374e2); live `~/.claude/bin/cc-lr` carries `wait:self`. Blocker met: a stale 0-byte shared-checkout `.git/index.lock` (04:41, no holder) failed the land's kicked converge; removed after confirming no holder.

## W3 — Proof — DONE (2026-10-18)

| proof | session · pane | result |
|---|---|---|
| (a) self-move from its own turn | `6f8d7bd2-90dc-4f9f-8b56-cf420ce86525` · 445, next3 → next2 | batch `20261018T184542Z-next3-next2-72712` MOVED in 266 s (conjuncts 1111111); pid 62874 `CLAUDE_CONFIG_DIR=~/.claude-secondary --resume <same sid>`; registry row 445 `account=claude-secondary`; next3 copy tombstoned `.jsonl.handed-off` |
| (b) peer-requested (`cc-lr move --sid … --to next2 --until-idle 900` from the lead) | `be57feef-f8a3-43dc-a1fa-d429b68292b3` · 458, next3 → next2 | batch `20261018T185310Z-next3-next2-90217` MOVED; pid 11844 on `~/.claude-secondary`, same sid; one copy |
| (c) 43e6eb4b → next | `43e6eb4b-…` · 8 | SUPERSEDED, not run: already moved in place next4 → next2 at 07:15Z by pane 344's batch `20261018T064955Z-next4-next2-7738` (MOVED, one copy), before this wave's recycle; its goal (off next4) is met and a second move of a live operator pane buys nothing (accounts differ only in quota). It can move itself now with `cc-lr move --sid "$CLAUDE_CODE_SESSION_ID" --to next`. |

Defects the first run of (a) found, fixed, landed in the range ending `dc74a6c22`:
- `11b063908` — the self-wait budget scales with load. Batch `20261018T131324Z-next3-next2-94791` went NOTMOVED `still-busy:move after 900s` with nothing touched: a self row needs two consecutive batch censuses calling it at rest, and one census took ~11 min at 13/core, so a flat 900 s could never hold two. Now 900 × min(4, 1 + load/core ÷ 5); `CC_LR_MOVE_SELF_WAIT_S` stays exact. Residual (theirs, lr-move-batch.sh): census time itself grows with load.
- `dc74a6c22` — lr-handoff read the recycle's stderr before its asynchronous tee had drained (reported by lr-inplace-immediacy; lr-handoff-flags 28-30 intermittent). /bin/bash 3.2 builds a process substitution on an external command's redirect in the forked child, so neither `wait` nor `$!` reaches it, and `${!:-}` is indirect expansion that dies under `set -u`; the substitution drops a `.drained` marker the parent polls for, bounded 15 s.

Learning: the 8/core recycle load hold was right to hold, and the proof only had to wait for a window (load fell from ~300 to ~40 by 13:50 local).

Not doing (with reason): self-transplant deferral inside handoff-fire (a second self path; the move lane already defers honestly); live-holder check inside lr-transplant confirm/unconfirm (risks refusing every legitimate in-place move through the lr-handoff → handoff-fire ancestry; R2's handoff-fire pre-pass check closes the same entry); changing the load bound.
