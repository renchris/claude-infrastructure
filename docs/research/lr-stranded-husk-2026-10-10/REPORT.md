# Stranded husk + held draft — research report (2026-10-10)

Round 1: Dynamic Workflow wf_84de517e-2e0 (6 research slots, 6 skeptics, 1 synthesis; workflow-lean @ xhigh). The synthesis slot could not write files (subagent write refused), so the lead rendered its per-cause output below verbatim. Line numbers are at a2f020096 (pre-fix); re-anchor on function names after edits.

Round-1 convictions (research → skeptic → reconciled): C1 65→35→50 · C2 68→42→50 · C3 68→45→50 · C4 62→45→45 · C5 72→35→55 · C6 78→40→50. All at or below 90%, so round 2 (targeted measurement + design closure) runs before any implementation, per Follow-On Gate F2.

Coordination received during round 1:
- FLEET_V2 lead (pane 16): HOLD any change under scripts/limit-recover/lr_recon/** until the next2-7d-1791630000 shadow cohort settles (at/after 2026-10-10T11:00Z); legacy scripts are free to land.
- Lead (pane 180): root cause 3 recurred on panes 2 (7f5deb68), 3 (1c0f7f90), 14 (4d059264) — copied to next, recycle HELD:unreachable, only holder is each pane's own next2 process. Include them in the field proof.
- Step 0 done 2026-10-10T06:28Z: images 1-5.png copied to ~/.reso/limit-recover/drafts/186452ed-02e5-4749-a4aa-8ece6f9ba1bf/20261010-preserve/ (sizes match the /private/tmp originals).

---

## conv=35 :: X0 ANSWER, CROSS-CUTTING FINDINGS, OWNERSHIP.

ANSWER: Five independent defects strand pane 168, and

X0 ANSWER, CROSS-CUTTING FINDINGS, OWNERSHIP.

ANSWER: Five independent defects strand pane 168, and an image-chip gap decides what can be kept. None of the six proposals is ready to implement as written. All six skeptics returned 'sound-with-changes' and cut conviction to 35-45%. After merging their required changes, my reconciled conviction is 45-55% per cause. That is at or below 90%, so the lead must do more research first.

Most of what is owed is measurement:
1. On 2.1.293, under a PTY or on a scratch pane: where a dialog digit lands when the dialog has just been dismissed, and what a bracketed paste does when the clipboard holds an image.
2. The red-before runs that every slot deferred because cc-bats refused under load.

Three facts no slot owned:
- The one working actuator would still refuse this husk. The '--husk' recycle would hold pane 168 as busy even after the draft is carried: its last read sees the /exit local-command echoes as a turn in flight.
- C2 and C3 are one design. They must share one successor predicate and one driver.
- The images are perishable. 4.png (the operator's image, swallowed by the guard at 04:20:05) and 5.png (the chip) exist only under /private/tmp, which tmp_cleaner purges after about 3 days. Earliest purge, estimated from the daily 00:00 CDT run and the +3-day rule: 2026-10-13T05:00Z. Copy them now.

State at 06:14:29Z (measured): pid 28699 alive on next2; nothing runs the session on next4; no request queued; recon off.

SYNTHESIS MEASUREMENTS (all read-only):
- 'date -u' => 2026-10-10T06:14:29Z.
- 'ps -o pid=,etime=,command= -p 28699' => alive, etime 05:14:30, claude-293.
- 'pgrep -P 28699 -l' => '32928 node' (the ms-365 MCP server; watcher pid 75441 is gone).
- jq on ~/.claude/cc-registry/168.json => pid 28699, sid 186452ed, account claude-secondary, pane 168.
- ~/.claude-secondary/sessions/28699.json exists; no quaternary session row names the sid.
- ls on the images dir => 1-5.png present; 4.png 196643 B, 5.png 318668 B.
- recon.on absent; autorecover.on present; no requests/186452ed file.
- 'cat <SRC>.jsonl.handed-off <SRC>.jsonl | tail -n 400 | jq <hf_transcript_at_rest select>' => after 'assistant api-error 04:05:55.562Z', three 'user -' records at 04:19:57.638-.639 (local-command-caveat, command-name /exit, local-command-stdout). So hf_transcript_at_rest returns 1 and hf_recycle_last_read holds busy (handoff-fire.sh:3216-3256).
- 'grep -n recycle_composer_block / recycle_fire_commit' => the composer gate runs at :17146, before the commit at :17533, which runs the last read at :16951-16953. The lead's 04:53 '--husk' run stopped at the composer, so it never reached that hold.
- sed handoff-fire.sh:13002-13004 => HF_ORIG_ARGV, HF_ORIG_SELF and HF_ORIG_PWD exist. handoff-fire already captures its own argv, which corrects the C5 skeptic.
- sed :3086-3096 => $CMD is the relaunch line. So today's refusal at :17231 already names the wrong re-run command.
- sed :572 and :9651 => RCY_TRANSPLANT_CAUSE is reset at :572, before the watcher block, so the watcher cannot inherit that name from env.
- grep CLAUDE.global.slim.md:188 => lists 'a GUI-only step' as a user step. slim is the installed default, and no slot named it.
- Spot sed reads of the cited lines in C1-C5 matched.

### Fix
CROSS-CUTTING:
(1) The at-rest companion (C3 item 8) blocks the field proof. It is measured, it is on no slot's critical path, and it is assigned to L3.
(2) The C2 and C3 fixes share one predicate, lr_successor_state, owned by L2, and one driver, lf_husk_recycle, owned by L3.
(3) C4, C5 and C6 all meet in recycle_composer_block. L4 owns that code and applies C5's wording.
(4) Copy 4.png and 5.png out of /tmp now (X1 step 0).
(5) The 'Engaged is not running' lesson applies: the field proof needs a process census, not just a transcript.
(6) The 'launcher runs the live layer' lesson applies: land and converge before the field proof.

LAND ORDER:
1. L2's lr-lib.sh predicate.
2. L1.
3. L3, including the at-rest companion.
4. L4.
5. L5, atomically with L4 or after it.
Each lane rebases onto the previous land and re-anchors on strings.

SHARED FILES:
- scripts/handoff-fire.sh, three lanes in disjoint regions.
  - L1: the watcher bgwork block and the 60/150/300 nudge, plus one export beside detach.
  - L3: hf_transcript_at_rest(), and the probe limit arm before 'echo "limit: NO'.
  - L4: recycle_composer_block(), the EXIT trap line, the hf_carry loader, the probe composer arm, the watcher put-back, hf_alarm, and one export beside detach.
- scripts/limit-recover/lr-upgrade.sh, split by region.
  - L3: lru_retired_source and the :994 disposition, lru_at_rest, the lru_mint_launcher hoist, and the :2769 text.
  - L4: lru_draft_restore and the composer-occupied save.

### Files
- L1 bgwork (C1): /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/handoff-fire.sh [watcher bgwork block from 'rcy_siw_why="" rcy_siw_kind="" rcy_self_siw=0' through the recycle-dead text; nudge 'case "$rcy_nudge_at" in 60|150|300)'; one export HF_RCY_TRANSPLANT_CAUSE beside HF_RCY_ORIG_ARGV_FILE]; tests/handoff-recycle-bgwork-dialog.bats; tests/handoff-recycle-bgcopy-stop.bats; docs/research/exit-bgwork-dialog-2026-09-10/exit-dialog-probe.py
- L2 successor owner (C2 + C5 text in its files): /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-lib.sh; scripts/limit-recover/lr-move-lib.sh; scripts/limit-recover/lr-reset-poller.sh (whole file, including the :870 text); scripts/limit-recover/lr_recon/{census.py,__main__.py,classify.py,report.py} (including C3's HOLD-HUSK mapping and C5's report text); bin/cc-resume-debt; tests/lr-poller-stranded-husk.bats (new); tests/fixtures/lr-stale-parity/cases.json (new); tests/lr-lib.bats; tests/cc-resume-debt.bats; lr_recon/tests/{test_census.py,test_report.py}
- L3 husk driver (C3 + C5 text in its files): /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-fleet.sh (whole file, including C2 part D and the :1264 text); bin/cc-lr; scripts/limit-recover/lr-upgrade.sh [lru_retired_source/:994, lru_at_rest, lru_mint_launcher hoist, :2769]; scripts/limit-recover/lr-handoff.sh [:686-694]; scripts/handoff-fire.sh [hf_transcript_at_rest(); probe limit arm]; tests/lr-fleet.bats; tests/handoff-fire-recycle-custody.bats (husk and at-rest cases); tests/lr-upgrade.bats
- L4 draft and image carry (C4 + C6 + C5 refusal text): /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/lib/composer-carry.sh (new); scripts/lib/lr-composer-snapshot.sh; scripts/lib/cc-tui.sh; scripts/handoff-fire.sh [recycle_composer_block() including :17219-17232, EXIT trap line + hf_rcy_draft_exit_restore, hf_carry loader, probe composer arm, watcher put-back, hf_alarm, HF_RCY_DRAFT_FILE export]; scripts/limit-recover/lr-upgrade.sh [lru_draft_restore and the save]; tests/lr-drill.sh; docs/plans/LIMIT_RECOVER_FLEET_V2.md; docs/research/lr-fleet-v2-decisions-2026-09-30/rulings.json; tests/handoff-recycle-draft-carry.bats (new); tests/lr-switch-driver.bats; tests/cc-tui.bats; tests/handoff-recycle-messages.bats; custody F5b/F5c
- L5 doctrine and hook (C5): /Users/chrisren/Development/.worktrees/lr-stranded-husk/commands/limit-recover.md; hooks/anti-deference-nudge.sh; tests/anti-deference-nudge.bats plus its handback fixture; CLAUDE.global.md; CLAUDE.global.slim.md; CLAUDE.rules.slim.10-session-close.md; hooks/completion-assert.sh; docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md; docs/plans/LIMIT_RECOVER_ZERO_MEMORY.md; tests/lr-doc-banned-transport.bats (or a sibling)

### Test
Each lane's own entry below gives its tests. Every suite runs serially and asserts its '1..N' plan line against the ok count; a cc-bats deferral is not a result.

## conv=50 :: C1: background-work answer on a transplant recycle.

POLICY (the wrong default):
- Every in-place lr

C1: background-work answer on a transplant recycle.

POLICY (the wrong default):
- Every in-place lr-handoff recycle passes --transplanted-source (lr-handoff.sh:1822). Only placed lanes force cancel (:1852-1854). So the fleet/poller lane keeps the default 'on', which means keep-work.
- The self default to stop-if-watcher (handoff-fire.sh:10144-10147) needs -z $bgk and RCY_CALLER_PID. A remote recycle has neither, so it sends $bgk at :10262.
- Keep-work on a retired, limited source starts a second live copy. The precheck measured 'bg_work: watcher' only, so stop-if-watcher (:10159-10202) would have pressed 'Exit and stop tasks', losing nothing.

MECHANISM (why the TUI did not exit): the '2' at 04:20:34 never chose keep-work. Evidence:
- no continued-in record;
- no new jobs dir;
- task bfccuz2ni delivered into pid 28699's own queue at 04:36:58;
- the composer read 'hold' at 60, 150 and 300 s (recycle_nudge_decision :4347-4359).
Best fit: the 30 s match was live, since the 500-line scrollback read matched nothing from 45 s on, so it was not a persisting stale render. The dialog was dismissed in the same window: an operator prompt was blocked at 04:20:05.824Z, 8 s after /exit. The operator attribution is hooks/validate-bash.sh:211, not bin/cc-suggest-filter:267. So the '2' landed in the composer. After the send there is no landing check (:10258-10277 continues).

PRECEDENT: watcher 17321 (pane 7, 2026-10-09T03:18:28Z) had the same non-landing. The existing nudge (:10282-10309) recovered it because its composer was clean. This class is 2 of 25.

MEASURED (by the slots):
- handoffs.jsonl: 6 rows from watcher 77720 (answered '2', bgcopy=unknown, three nudge-held, recycle-dead 04:36:45).
- group_by(watcher_pid): 25 keep-work watchers, 23 continued-in.
- Skeptic baselines: bgcopy-stop.bats '1..11', 11 ok; bgwork-dialog.bats '1..47', 47 ok.

### Fix
PART A: transplanted limit source defaults to stop-if-watcher (handoff-fire.sh).
1. Export HF_RCY_TRANSPLANT_CAUSE beside the HF_RCY_ORIG_* exports before detach (:17398-17407). It needs a new name because :572 resets RCY_TRANSPLANT_CAUSE (measured). lr-handoff already threads --transplant-cause.
2. Beside :10018, set rcy_tp_siw=0 and rcy_bg_answer0=${CC_RECYCLE_BGWORK_ANSWER:-on}.
3. After :10147, switch to stop-if-watcher (and set rcy_tp_siw=1) when ALL hold:
   - answer0 is 'on';
   - RCY_RESUME_SID and RCY_SRC_TX are both non-empty;
   - HF_RCY_TRANSPLANT_CAUSE is 'limit';
   - CC_RECYCLE_TRANSPLANT_STOP_WATCHER is not 'off'.
4. In the stop-if-watcher hold fallback (:10200-10201): when transplanted, a keep-work row exists and team_rc=1, answer 'on' (keep-work plus bgcopy_stop); otherwise cancel.
5. Add lane=transplant at :10197. The :10355 text names the stop-tasks row and asks nothing.
6. Stated scope change: a transplanted source on a menu with no keep-work row now answers '1' instead of Esc.

PART B: prove the answer landed, rebuilt on the existing nudge.
1. Record the last digit and its time at :10194 and :10262.
2. 'Did not land' needs positive evidence, ALL of:
   - not at_shell;
   - bgcopy returned 'unknown';
   - pane_bgwork_seen false;
   - composer readable on two reads at least 2 s apart.
   Ambiguous means keep waiting.
3. If the composer reads exactly our digit, or /exit plus our digit:
   - run composer_scrub_verified, then it2_paste_submit_verified '/exit' once per watcher;
   - set rcy_bgwork_next=waited+3;
   - allow one answer beyond CC_RECYCLE_BGWORK_MAX;
   - same shape as :9962-9978 and :10001-10017.
   Check this after bgcopy_stop returns 'unknown' and in the 60/150/300 nudge. Add no new poll before bgcopy_stop (:6208-6220).
4. If operator text is followed by our digit:
   - send one read-back-verified backspace;
   - emit recycle-held-draft (settle.py:65-73 consumes it);
   - leave the session to the C2 owner and the C4 carry;
   - never exit 1 with an unconsumed unconfirm=needed (settle.py:390-405).
5. Kill switch: CC_RECYCLE_BGWORK_LAND_CHECK=off.
6. Drop the original Part B.3.

OWED BEFORE PART B LANDS: a PTY run on 2.1.293 using exit-dialog-probe.py, measuring:
- where a digit lands as the dialog is dismissed;
- the composer after Esc;
- the composer_content verdict during 'Moving to background' and during stop-tasks shutdown, with a ─ table row above the dialog.

### Files
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/handoff-fire.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/handoff-recycle-bgwork-dialog.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/handoff-recycle-bgcopy-stop.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/docs/research/exit-bgwork-dialog-2026-09-10/exit-dialog-probe.py

### Test
All in tests/handoff-recycle-bgwork-dialog.bats, in a new section after :778. The tp_drive helper follows bgcopy-stop.bats:170-172 ($10-$13 plus HF_RCY_TRANSPLANT_CAUSE=limit).

CASE A [RED]: siw_env watcher.
- Assert: sends '1', not '2'; row recycle-bgwork-stopped-watcher with lane=transplant; no recycle-bgwork-answered row.
- Pre-fix it sends '2', which :686-690 pins.

COMPANIONS:
- work sends '2' plus a bgcopy-stop row;
- the kill switch sends '2';
- $13 empty sends '2';
- voluntary cause sends '2';
- explicit cancel sends Esc only;
- [RED] view-off menu sends '1'.

CASE B [RED]: _selfcall_stub (:424-494) with a ONE-SHOT STUB_DIGIT_TO_COMPOSER, STUB_REDIALOG=1 and a low HF_RECYCLE_SHELL_WAIT_S.
- Assert: sends.log reads digit, Ctrl-U, bracketed /exit plus CR, second digit; stub.state reaches 'gone'; a recycle-bgwork-unlanded row exists.
- Do not assert on recycle-dead text: at_shell is never true in this harness (:17-19).

CASE C: operator text plus our digit.
- Assert: one backspace, no Ctrl-U, a recycle-held-draft row, no unconfirm exit.

Run serially. Baselines are 1..47 and 1..11.

## conv=50 :: C2: no owner for 'transplanted, successor never started, source alive'.

THE RAIL TREATS 'MOVED' AS 

C2: no owner for 'transplanted, successor never started, source alive'.

THE RAIL TREATS 'MOVED' AS 'RECOVERED'. The tombstone is written at confirm, before /exit, and three actors retire on it alone:
- lr-reset-poller.sh:1051-1054 retires on .handed-off or lr_transplant_target alone. That breaks the lane's own contract (:1089-1093), so the retry budget (:1094, :1348-1353) never ran. The request retired at 04:31:42 while watcher 77720 was still alive.
- census.py:538-541 has the same rule (and a stale docstring reference at :536).
- lr-fleet.sh:1077-1082 has the same rule.

LIVENESS IS ACCOUNT-BLIND:
- lr-lib.sh:597 drops the account column.
- cc-resume-debt:153-161 proves LIVE through cc-find on any account; it discharged the debt on the husk at 04:32:10 and 04:37:16.
- lr-fleet.sh:1051 recorded recycle-in-place/RECOVERED at 04:19:09Z, 48 s before /exit (skeptic).

NO READER, NO DRIVER:
- never-confirmed (handoff-fire.sh:9853-9865) has no reader, and its mail goes to the husk.
- --husk's only caller is act.py:134-153, and recon is off.
- W5-A (:2057-2101) only logs, and reroute_parked skips transplanted sids before the reset (:1980-1984).
So the acceptance subject, whose request is already retired, stays unowned even after a request-lane fix.

MEASURED (slots):
- lr-lib live calls: holder_count=1; in_cfg(quaternary) rc 1; in_cfg(secondary) = '168 28699'; husk_state(secondary) rc 0.
- Sibling 30c3a88d: in_cfg(target) rc 0, husk rc 1.
- poller.log ticks: 04:31:42, 04:44:45, 04:49:29, 05:04:34.
- Baselines: test_census 24 passed; drill plus bg-not-teammate '1..13' ok; lr-fleet/lr-lib filtered '1..42' ok.

### Fix
One predicate, shared with C3.

A. lr-lib.sh primitives. Hoist lr_move_pid_cfg and lr_move_fold (lr-move-lib.sh:27-30, :52-55) as lr_pid_cfg and lr_cfg_fold. Take the LAST CLAUDE_CONFIG_DIR token (bin/claude-accounts:727) and keep the LR_MOVE_ENV_DIR seam.

B. New lr_successor_state <sid> <source cfg>.
Holder evidence:
- registry rows, with their account column;
- live <cfg>/sessions/<pid>.json rows (the :831-841 and lr-transplant.sh:222-250 pattern);
- --resume leaves classified by lr_pid_cfg.
Target: lr_transplant_target (lock or tombstone).
Tokens:
- successor: a live holder on any store whose physical projects/ differs from the source. Retire.
- moved-on: the target copy no longer ends on its limit (lf_last_is_limit), or it is larger than confirm_len. Retire 'no longer LIMITED'.
- husk <pane> <pid>: all holders are on the source; the target copy equals confirm_len and ends on its limit; the target has no tombstone handing back; lr_husk_state rc 0. The owner dispatches.
- in-flight / unknown: keep, bounded.
- none: today's retire.
Kill switches: LR_SUCCESSOR_GATE=off restores today's behavior byte for byte. LR_HUSK_RETIRE=off maps to retire.

C. Poller request lane.
- rq_stale_reason uses the predicate.
- The call site (:1192-1196) branches:
  - retire;
  - husk: log STRANDED-HUSK, then the normal paced dispatch of 'lr-fleet --one';
  - in-flight: no attempt spent; dispatch or retire after LR_RQ_INFLIGHT_MAX ticks.
- Refund dispatches that end HELD (draft, busy, bg-work), as rq_refund_park does (:1109-1122).
- An exhausted husk request files an agent-side owner row, never the 'unsent draft' page (:1348-1353).
- The wake arm (:1314) never wakes a husk on its source.
- Use printf '%s'.

D. Parked-lane owner. reroute_parked (:1980-1984) and W5-A (:2096-2100) file a hook-shaped request (requested_by stranded-husk) when the state is husk and autorecover.on exists. This is what reaches pane 168.

E. Census parity. census.py uses the same rule and the same evidence. __main__.py:287 excludes kept husk sids from record creation. Fix the stale :536 reference.

F. cc-resume-debt, now REQUIRED:
- _live_once requires the cc-find cfg to fold-equal the debt's meta .cfg;
- _relaunch defers a stranded husk uncounted;
- kill switch CC_RESUME_DEBT_SCOPED_PROOF=off.

### Files
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-lib.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-move-lib.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-reset-poller.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr_recon/census.py
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr_recon/__main__.py
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/bin/cc-resume-debt
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/lr-poller-stranded-husk.bats (new)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/fixtures/lr-stale-parity/cases.json (new)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/lr-lib.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/cc-resume-debt.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr_recon/tests/test_census.py

### Test
1. New tests/lr-poller-stranded-husk.bats.
Harness: lr-poller-bg-not-teammate.bats:18-56.
Fixture: SRC and TGT stores with a tombstone, .handed-off, a /exit stub, a confirm_len copy on TGT, registry row 99168 on claude-secondary, and a sessions/<pid>.json row on SRC.
Cases:
- (a) [RED] source-only husk: not retired; '--one' dispatched; attempts=1; STRANDED-HUSK logged.
- (b) [RED] in-flight: kept, attempts unchanged.
- (c) target holder: retired 'live successor … next4'.
- (d) no holders: retired 'tombstoned'.
- (e) kill switch.
- (f) [RED] past the source reset: dispatched, never woken in place.
- (g) [RED] parked record plus husk: a request is filed.
- (h) [RED] HELD:draft dispatch: attempt refunded.
- (i) LR_HUSK_RETIRE=off: retire.
- (j) registry row lost, session row present: kept.

2. test_census.py.
- [RED] test_stranded_husk_request_is_not_retired.
- Controls: target holder; no holder; cfg='' leaf.
- Kill switch.
- __main__ opens no record for the kept sid.
- test_tombstone_found_across_stores stays green (its fixture has no HANDOFF.json).

3. Shared parity table, cases.json, read by one bats loop and one pytest. Rows include: registry lost with session row present; a holder on a third store; target moved on; round trip.

4. tests/lr-lib.bats: each token, using the LR_MOVE_ENV_DIR seam.

5. tests/cc-resume-debt.bats with FIND_CFG.
- [RED] cfg mismatch stays open.
- Control: cfg match is proven.

## conv=50 :: C3: four entry points, four gates, a refusal loop.
Each gate reads the source's view, and the source

C3: four entry points, four gates, a refusal loop.
Each gate reads the source's view, and the source is the husk.

1. lr-fleet --one.
- lf_transplanted_live counts any holder (lr-fleet.sh:1077-1082).
- lf_nudge picks the first unscoped row (:1199-1200).
- At 04:45 it typed into pane 168 and logged 'nudge-in-place/UNPROVEN … on next4', but pane 168 is on next2.

2. handoff-fire probe.
- It reads the first <sid>.jsonl in store order (:470, :11543-11549), which is the husk stub.
- It returns REFUSED:not-limited and names cc-lr move (:11634-11641).

3. cc-lr recover.
- cc-find classes the stub SESSION, and the refusal says there is nothing to recover (bin/cc-lr:568, :576-579, :358-397).

4. cc-lr move/rotate.
- lru_retired_source cannot tell a forward husk from a round trip (lr-upgrade.sh:952-962, :994).
- That yields hold:retired-source and 'cc-lr repair-markers' (bin/cc-lr:1130), and repair-markers correctly answers KEEP.

lr-handoff's STRANDED verdict prescribes 'lr-fleet --one' (lr-handoff.sh:1963-1977), the path that nudges the husk. None of the four names --husk.

BLOCKER (synthesis, measured): the --husk last read joins .handed-off and the stub (:3216-3256), and hf_transcript_at_rest (:2655-2678) reads the /exit echoes as a turn in flight. Result: HELD:busy.

MEASURED (slots):
- lr_last_api_error: SRC rc 1; TGT 'limit' rc 0.
- cc-find 168 => claude-secondary, LIVE SESSION.
- bundle-20261010T045207Z => REFUSED:not-limited.
- The lock's 'to' equals the tombstone's handed_off_to (~/.claude-quaternary); confirm_len 2902688 equals the quaternary size.
- The bundle launcher's token is past its TTL, so reuse gives token-stale rc 9 (capacity-admit.sh:611-620, :1184-1225).
- Filtered lr-fleet.bats '1..12' ok, and ':996 … is NUDGED' passes today with the successor row on the SOURCE account.
- Not measured: --stale-markers (the classifier denied it).

### Fix
One driver, built on C2's lr_successor_state.

1. lr-fleet routing.
- lf_transplanted_live maps:
  - successor to held/nudge;
  - husk to rc 3;
  - unknown or in-flight to a DEFERRED row;
  - none to stranded.
- At :1624 and :1653, use lr_transplant_target (lock or tombstone). Never pass the source as the target.
- Stub-less source: a husk on another store routes to the husk path, never to wake-in-place (:1606-1608).

2. lf_one (:944-956) routes to lf_husk_recycle inside the same fence and slot.

3. lf_husk_recycle, in order:
- (a) Pane from lr_registry_live_rows_in_cfg(sid, source); lr_husk_state rc 0.
- (b) Take or verify the per-sid run claim outside the poller. '--one' takes none (lr-fleet.bats:1834); only the pane lock guards today (:2994-3006).
- (c) Inside lf_admit_lock_take/release: capacity probe, cc_capacity_token_mint and lf_charge_assign (:577-604, :714, :973-976).
- (d) Re-mint the launcher with lru_mint_launcher (lr-upgrade.sh:1818-1890) hoisted to a shared lib. Never sed-copy a launcher.
- (e) A DRY row.
- (f) Run 'handoff-fire.sh --recycle --transplanted-source --husk --transplant-cause limit --resume-launcher L --resume-cfg <tombstone handed_off_to> --resume-cwd … --source-pane P --source-session SID', with CC_RECYCLE_BGWORK_ANSWER unset.
- (g) A HELD result writes husk-recycle/HELD:<why>, with no page and no 'Send or clear'. The poller re-drives it with a refund.
- (h) rc 0 runs lf_await_relaunch scoped to the target.

4. Scope the remaining account-blind reads: :1051 '_after', lf_await_relaunch (:925) and the lf_nudge pane pick (:1199-1200). This ends the 04:19:09 false RECOVERED.

5. cc-lr move/rotate: at lr-upgrade.sh:994, disp=husk. At bin/cc-lr:1130, hold:husk with the action 'relaunch it in place: cc-lr recover <sid8>'.

6. Probe.
- Print REFUSED:husk before 'echo "limit: NO' (:11634).
- Key it on lr_successor_state, never on 'any <sid>.jsonl at the target'.
- Mirror it at lr-handoff.sh:686-694.
- Map it in classify.py:129, __main__.py:55-58 and :483, and report.py:46.

7. cc-lr recover (:576): SESSION plus husk becomes STRANDED, then 'lr-fleet --one --detach'.

8. AT-REST COMPANION (blocker). In hf_transcript_at_rest (:2655-2678) and lru_at_rest (lr-upgrade.sh:255), kept in step:
- skip isMeta user records;
- read a last user record that starts '<\local-command-stdout>' as at rest.
Keep it narrow: a custom slash command also writes <\command-name> and is followed by a turn (estimated; pin it with a fixture).

Kill switches: LR_HOLDER_SCOPED, LF_HUSK_RECYCLE, LRU_HUSK_DISP, HF_PROBE_HUSK, CC_LR_HUSK_ADMIT, HF_REST_LOCAL_CMD.

### Files
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-fleet.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/bin/cc-lr
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-upgrade.sh (lru_retired_source/:994, lru_at_rest, lru_mint_launcher hoist)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-handoff.sh (:686-694)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/handoff-fire.sh (hf_transcript_at_rest; probe limit arm)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/lr-fleet.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/handoff-fire-recycle-custody.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/lr-upgrade.bats

### Test
tests/lr-fleet.bats fixture changes:
- row() (:132) gets an account argument.
- The 8 successor cases (:972-1063) use claude-tertiary.
- The default lr-handoff stub (:44-60) re-registers on the target; otherwise :275-281 goes red.
- setup sets LF_HF_BIN=absent.

Cases:
- [RED] 186452ed shape: tombstone, .handed-off, non-limit /exit stub, confirm_len copy on TER, source row; --resume-cfg taken from the tombstone.
  - Assert: no SUBMIT; the hf stub argv carries '--recycle --transplanted-source --husk … --resume-cfg $TER --source-pane <row>'; husk-recycle/RECOVERED; the lr-handoff log is empty.
  - Pre-fix, the husk is nudged.
- NEGATIVE: a round-trip stub at the target is never recycled.
- [RED] stub-less source: no SUBMIT.
- [RED] :1051 with only the source row: UNPROVEN, not RECOVERED.

Other suites:
- custody.bats: a REFUSED:husk probe case, and an at-rest case where the joined .handed-off plus /exit stub reads 0.
- lr-upgrade.bats: lru_at_rest parity.
- classify pytest: husk maps to HOLD-HUSK.

Run the whole of lr-fleet.bats serially and assert the plan line and the ok count.

## conv=45 :: C4: the composer gate holds a real draft and hands it to the human.

THE GATE:
- recycle_composer_bl

C4: the composer gate holds a real draft and hands it to the human.

THE GATE:
- recycle_composer_block (handoff-fire.sh:17150-17235) waits 180 s and clears only text that matches a rail receipt (:17186-17205).
- Anything else refuses at :17219-17234, with pages and 'clearing it is not ours to do'. That is the 04:56:18 recycle-held-draft on '[Image#5]'.
- composer_content strips whitespace (:4093). cc_tui_composer_text (cc-tui.sh:174-183) keeps spaces.

THE ONLY EXISTING CARRY is in lr-upgrade.sh (:1107-1147, :1209-1226), and it has three defects:
- A chip reads back as 'carried' while the image is lost: the read-back is space-stripped (:1110, :1143).
- The 300 s successor wait is shorter than the 600 s notification window (:259). This failed on pane 20.
- It runs on the legacy lane only.

UPSTREAM: the probe holds the same drafts (:11790-11793). In a husk, holding protects nothing, because the guard blocks every submit (handed-off-session-guard.sh:3, :203).

MEASURED:
- Skeptic: 'grep -F Image#5' => 04:56:18Z, target_pane 168, prev_sid null.
- Research: cc_tui_composer_text 168 => '[Image #5]'. composer_unintended_class => rc 1, a draft.
- In-memory read-back check: the two compare equal, so a false 'carried'.
- switch results: 7e68ac6b in-place restore proven; 762a6daa successor restore failed.
- Baselines: D6 '1..4', turn-wait '1..14', F5 '1..1'.

### Fix
A. New scripts/lib/composer-carry.sh, built on cc-tui primitives.

composer_carry_save:
- writes draft.txt;
- writes the raw ANSI record through lcs_snap (lr-composer-snapshot.sh:84);
- writes draft.chips, and saves chip bytes through C6's hook;
- checks that the saved text (spaces stripped) equals a stable composer_content read;
- returns rc 0 saved, 1 empty, 2 unreadable, 3 chips unsaved.

composer_carry_restore:
- the lr-upgrade code (:1108-1146), moved, with readiness injected;
- collapses whitespace only next to removed chips;
- never types chip text;
- names each chip with its saved path.

B. Carry arm at :17219. Conditions:
- rcy_cg_rc=1;
- CC_RECYCLE_CARRY_DRAFT is not off;
- remote resume;
- RCY_HUSK=1, OR focus is not 'yes' (the :3123-3126 polarity);
- the same content on two reads.
Then:
- save;
- cc_tui_clear, with read-back;
- RCY_DRAFT_STATE=cleared and export HF_RCY_DRAFT_FILE;
- emit recycle-draft-saved;
- set rcy_cg_rc=0.
Unsaved chips with no --husk keep the hold, and the saved path goes in its own variable.

C. Abort before /exit restores in place.
- Define hf_rcy_draft_exit_restore (set -u safe) before :15402.
- Change the trap to 'fire_cleanup; hf_inflight_release; hf_rcy_draft_exit_restore'.
- After :17533, set RCY_DRAFT_STATE=handed and write an /exit marker.

D. Watcher put-back.
- rcy_draft_carry_back sits beside rcy_debt_settle (:9698) and runs before each engaged exit (:10771, :10818, :10874).
- Readiness: engagement proven, the target at rest on 2 polls, and an empty box.
- HOLD the pane lock throughout (:8477, :10813-10819).
- Bound: stale window + 300 s, successor side only.
- The EXIT trap (:9664) writes 'not-carried' only if the /exit marker exists.
- The dead/never-exited arms put the draft back in place for a non-husk whose old TUI is still alive.
- hf_alarm (:8150) names the saved copy.

E. Probe (:11790-11793). Print 'composer: carry:'. Do not use the bare word 'draft', which classify.py:47-52 maps to HOLD. Pass only when the gate would carry.

F. lr-upgrade uses the lib.
- Chip drafts carry the text plus the named path, instead of a NOTMOVED hold.
- Raise the bound only for the successor side (the serial drainer, :3070).

G. Records.
- Record the ruling superseding decision 6 (LIMIT_RECOVER_FLEET_V2.md:140, :428, :500; rulings.json:326).
- Update lr-drill.sh arm (c) (:320-332, :743-748).

H. Residual, named. The recon census (census.py:231-236, :270-271), cc-lr move (bin/cc-lr:1074, :1129) and lr-move-worker.sh:25 still hold, with no human ask (C5 text). They are a follow-up for this lane.

Kill switch: CC_RECYCLE_CARRY_DRAFT=off.

### Files
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/lib/composer-carry.sh (new)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/lib/lr-composer-snapshot.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/handoff-fire.sh (recycle_composer_block, EXIT trap, hf_carry, probe composer arm, watcher put-back, hf_alarm)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/limit-recover/lr-upgrade.sh (lru_draft_restore and save)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/lr-drill.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/docs/plans/LIMIT_RECOVER_FLEET_V2.md
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/docs/research/lr-fleet-v2-decisions-2026-09-30/rulings.json
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/handoff-recycle-draft-carry.bats (new)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/lr-switch-driver.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/handoff-fire-recycle-custody.bats (F5b/F5c)

### Test
New tests/handoff-recycle-draft-carry.bats, using the turn-wait.bats:21-90 harness, an HF_TUI_LIB stub and fast clocks:
- (a) [RED] unfocused remote text: saved with its spaces, one CLEAR, status 0.
- (b) [RED] --husk '[Image #5]': saved; chips file present; restore rc 1 naming the chip; no KEYS.
- (c) RCY_HUSK=0 chip: refuses, no CLEAR, path named.
- (d) [RED] abort after the clear: restored in place.
- (e) Controls: focused; switch off; not remote; unstable content.
- (f) Trap-string pin.
- (g) Watcher put-back, at rest vs a fresh notification.
- (h) [RED] a disarm before /exit writes no not-carried row.
- (i) The lock is held during the put-back.

Other suites:
- lr-switch-driver D6e [RED]: a chip is never retyped as text. Also run the suite under /bin/bash 3.2.
- custody F5b: unfocused text gives 'composer: carry:'.
- custody F5c [RED under the original proposal]: an unfocused '[Image #5]' with no --husk stays HELD:draft.
- classify pytest: the carry line is not HOLD.
- lr-drill arm (c) stays green.

Assert every plan line.

## conv=55 :: C5: doctrine and no Stop-hook arm made the agent ask.

THE DOCTRINE AND THE RAIL TEXT:
- commands/li

C5: doctrine and no Stop-hook arm made the agent ask.

THE DOCTRINE AND THE RAIL TEXT:
- commands/limit-recover.md:208 says 'A real draft is theirs, and so is the refusal'.
- handoff-fire.sh:17229-17231 pages and prints 'Clear/send the draft, then re-run: $CMD'.
- $CMD is the relaunch line (:3086-3096, measured), not the handoff-fire call.

Copies elsewhere:
- lr-fleet.sh:1264;
- lr-reset-poller.sh:870;
- report.py:58, :61 and :178-185;
- lr-upgrade.sh:2769;
- limit-recover.md:727-728;
- two plan docs.

Overlapping 'GUI-only' exits:
- CLAUDE.global.md:1014 and :1128;
- the installed default CLAUDE.global.slim.md:188 (measured; named by no slot);
- completion-assert.sh:1415.

THE HOOK: anti-deference-nudge.sh has no pane-keystroke arm.
- The 04:56:34Z close 'in pane 168, clear the prompt box (Ctrl-U), then tell me here' abstained 'no-tell'.
- HARD_CORE (:370) at :392 would also exempt 'I don't have permission … please clear'.

MEASURED (skeptic):
- The spliced hook, in memory, fires on the incident and on 13 of 13 positives; shellcheck finds 0.
- The pipefail-sigpipe-lint detector goes from 8 to 10 sites. The allowlist (:12) says 8, and the ratchet may only shrink (:272-276), so it is RED at ship-land.sh:4002.
- E3 turns S1-S6 (approving a force-push prompt, /login, a destructive migration, a value fork, an API key paste) from no-tell to fired.
- Recall: 2 of 23 real handbacks over 30 days.
- Out-of-sample precision: 65127 messages / 2238 candidates / 2 hits, both genuine.

Baseline (research): anti-deference '1..50', 50 ok.

### Fix
(a) DOCTRINE.
- Replace limit-recover.md:193-208 with the research text, and add: 'Never send Ctrl-U to a draft you have not saved; save the text and any [Image #N] file first.'
- State that a kitty pane keystroke is agent-drivable, never a GUI-only step, in:
  - CLAUDE.global.md:1014 and :1128;
  - CLAUDE.global.slim.md:188;
  - CLAUDE.rules.slim.10-session-close.md:184 and :193;
  - completion-assert.sh:1415.

(b) HOOK ARM pane-step-handback, inserted after :236:
- Write the matches with no early-exit consumer (a case guard, or 'grep -iE PAT >/dev/null'), so the lint count stays 8.
- Keep HARD_CORE winning at :392. When has_pane=1, neutralize only the permission-excuse alternations.
- PANE_GENUINE covers:
  - CLASS_C_GENUINE (:380);
  - value-fork and external-info terms;
  - api key, token, secret, credential, login, sign-in, oauth, approv*, permission prompt/dialog, allow, deny, destructive, production, force-push.
- Recall:
  - allow [*_]{0,3} after every anchor;
  - add a relay tell ('send or clear', 'clear/send', and similar, plus draft, composer or prompt box);
  - accept 'this pane' and 'that pane';
  - accept 'press <key> on the … dialog in pane N'.
- Precision: tighten the 'Pane N:' opener.
- Wiring: E1-E7 as researched. Kill switch ANTIDEF_PANE_ASK=off.

(c) REFUSAL TEXT, applied by the L4 owner.
- Re-run command: printf '%q ' "$HF_ORIG_SELF" "${HF_ORIG_ARGV[@]}". It already exists at :13002-13003. Never print $CMD.
- Name an owner only if it exists:
  - the reconciler, only with an open PRE-MOVE record (settle.py:346);
  - a retry ticket, only if one was written;
  - otherwise the poller re-drives (C2).
- Never say 'Nothing is needed from the operator' unless an owner was confirmed.
- With the switch off, print a plain hold.
- Keep the '!! recycle REFUSED after' prefix, the word 'draft' and the class recycle-held-draft.

(d) OTHER COPIES, each with its pinned test:
- lr-upgrade.sh:2769 with lr-upgrade.bats:494;
- report.py:58 with test_report.py:142 and :411;
- lr-fleet.sh:1264;
- lr-reset-poller.sh:870.
residue_needs (report.py:178-185) routes to C4 or C2, never to a needs-human row.

Land atomically with C4, or after it.

### Files
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/commands/limit-recover.md
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/hooks/anti-deference-nudge.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/anti-deference-nudge.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/CLAUDE.global.md
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/CLAUDE.global.slim.md
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/CLAUDE.rules.slim.10-session-close.md
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/hooks/completion-assert.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/docs/plans/LIMIT_RECOVER_ZERO_MEMORY.md
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/lr-doc-banned-transport.bats (or sibling)
- (text applied by owners: handoff-fire.sh:17219-17232 by L4; lr-fleet.sh:1264 and lr-upgrade.sh:2769 by L3; lr-reset-poller.sh:870 and report.py by L2)

### Test
anti-deference-nudge.bats:
- [RED] the incident plus the 13 positives.
- [RED] a fixture of the 23 real handbacks, with a recall floor.
- Silent: the negatives; S1-S6; 'You can type in pane 168 again.'; fenced and quoted copies.
- [RED] the permission excuse fires.
- The reason text and the IDL FIRE_KIND.
- No locale.
- Kill switch.

Lint: 'bash scripts/pipefail-sigpipe-lint.sh' reports 8 sites for the hook.

handoff-recycle-messages.bats [RED]:
- A failed carry prints the HF_ORIG argv and 'Next automated step'.
- None of Clear/send, Send or clear, 'not ours to do'.
- Static grep -c of the four phrases is 0 (3 today).

Doc test:
- 'theirs, and so is the refusal' is absent.
- 'zero human in the loop' and 'pane-step-handback' are present.

## conv=50 :: C6: the [Image#5] chip.

WHERE THE IMAGE LIVES:
- 2.1.293 writes a pasted image at paste time to ${C

C6: the [Image#5] chip.

WHERE THE IMAGE LIVES:
- 2.1.293 writes a pasted image at paste time to ${CLAUDE_CODE_TMPDIR:-/tmp}/claude-<uid>/<sanitized-cwd>/<sid>/images/<id>.<ext> (bundle @200676320, @215296857; research).
- That location is shared across accounts and is under no config dir.
- The chip-to-bytes link (pastedContents) lives only in memory, and no unsent draft is persisted. Typing the chip text back carries no image, so lr-upgrade.sh:1133 loses it.
- --resume keeps the sid, so a successor in the same cwd shares the images dir.
- Possible re-attach route, from bundle reading only: a bracketed paste of an absolute .png path (R9e @202648290).

PROVENANCE, downgraded to 'likely rail-induced (timing)':
- 5.png was born at 04:45:31Z, the same second as the lr-fleet nudge submit at 04:45:31.173Z (history.jsonl:8009).
- cc-tui strips chips only before the CR (cc-tui.sh:604-617) and does not re-read after it (:633-670).
- Counter-evidence: the operator had sent this session screenshots earlier (history.jsonl:8004).
- 4.png is the operator's guard-swallowed image (:8007).

DURABILITY: tmp_cleaner deletes after 3 days.

MEASURED:
- 'stat': 4.png 04:20:05Z, 5.png 04:45:31Z.
- 'shasum' on 5.png => 044daf6331dba9df…; PNG 938x1563.
- No image-cache dir exists. The bundle cleanup deletes other sessions' image-cache dirs, so that absence proves little.
- tmp_cleaner plist: daily at 00:00, 3 days.
- composer-residue has no 168 entry, and old receipts persist (no TTL).
- cc-bats deferred the tests.

### Fix
A. SAVE BYTES ON EVERY DRAFT HOLD (C4 hook composer_carry_attachment_save).
- Put it in, or call it from, lcs_snap (lr-composer-snapshot.sh:84), which lr-fleet.sh:1271, lr-reset-poller.sh:861 and lr_recon/__main__.py:373-395 already call.
- Root precedence:
  1. the LR_CC_TMPDIR seam;
  2. the source pid's env CLAUDE_CODE_TMPDIR;
  3. /tmp.
- Match on cwd-segment preference plus magic bytes.
- On ambiguity, save every candidate and re-attach none. Never pick by newest mtime.
- 'cp -p' plus a manifest {n, src, dst, sha256, bytes, dims}.
- For a husk, also save the images of guard-blocked prompts (4.png here).

B. RE-ATTACH: none until a scratch-pane measurement, never on pane 168. Measure on 2.1.293:
- (a) a non-empty bracketed paste with a clipboard image;
- (b) a bracketed paste of an absolute .png path, with and without a clipboard image, recording chip count, order and new store files.
If it passes:
- identify each chip by its new store file (sha256, then dimensions);
- remove only non-matching chips, by position;
- on doubt, a verified Ctrl-U, the text, and '@<dst>';
- the notify-back states what is in the box and never asks the operator to paste.

C. POST-CR CHIP ON A RAIL SUBMIT (cc-tui.sh near :633). This applies when the pre-gate proved the composer empty.
- Poll for up to 3 s.
- On a chip-only read: save via A, then Ctrl-U with read-back (:624-630).
- Write a receipt only if the scrub fails, keyed by sid and sha256.
- Kill switch CC_TUI_POSTCR_RESIDUE=off.

D. PROVENANCE PREDICATE inside the C4 carry. A chip-only composer whose image was born within 5 s after a rail CR recorded in that pane's run logs is rail residue: saved, named, cleared by the verified clear, not re-attached. Never hand-write a receipt for pane 168.

Kill switches: LR_CARRY_DRAFT_IMAGES=off|nosave.

### Files
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/lib/lr-composer-snapshot.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/lib/composer-carry.sh (attachment hook)
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/scripts/lib/cc-tui.sh
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/cc-tui.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/handoff-recycle-draft-carry.bats
- /Users/chrisren/Development/.worktrees/lr-stranded-husk/tests/lr-switch-driver.bats

### Test
1. cc-tui.bats, hermetic seam.
- Setup: LR_CC_TMPDIR with a fake PNG.
- Assert: saved byte-exact with a manifest.
- Two candidate cwd segments: both saved, reported ambiguous.
- An unreadable seam must fail rather than read the real /private/tmp.
- Pre-fix: status 127.

2. cc-tui.bats [RED], post-CR chip.
- Assert: one Ctrl-U scrub, image saved, no receipt, one CR.
- Sub-case: when the scrub fails, a receipt keyed by sid and sha is written.

3. draft-carry.bats [RED], provenance.
- Setup: chip-only husk draft, image born 1 s after a logged rail CR.
- Assert: saved and named, no KEYS, no paste.

4. [RED] lcs_snap saves the image bytes.

5. lr-switch-driver.bats, with tui_stub and CLIP_IMAGE=1.
- Assert: the chip is never typed as text, and the path is named.

Each runs alone, red before and green after, with its plan line asserted.

## conv=35 :: X1: field-proof sequence for pane 168.
Run it only after all lanes land via /ship and converge with 

X1: field-proof sequence for pane 168.
Run it only after all lanes land via /ship and converge with 'CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh'.
No step needs an operator keystroke.

Variables:
- SID=186452ed-02e5-4749-a4aa-8ece6f9ba1bf
- SRC=~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-195938-17814
- TGT=~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-195938-17814
- IMG=/private/tmp/claude-501/-Users-chrisren-Development--worktrees-wt-cc-195938-17814/$SID/images

### Fix
STEP 0 (NOW, PERISHABLE; a file copy, no pane):
D=~/.reso/limit-recover/drafts/$SID/20261010-preserve; mkdir -m 700 -p "$D"; cp -p "$IMG/4.png" "$IMG/5.png" "$D"/ && shasum -a 256 "$IMG"/{4,5}.png "$D"/{4,5}.png

STEP 1 (READ-ONLY PRECONDITIONS):
- grep -c lr_successor_state ~/.claude/scripts/limit-recover/lr-lib.sh  # >= 1
- grep -c hf_rcy_draft_exit_restore ~/.claude/scripts/handoff-fire.sh  # >= 1
- ps -o pid= -p 28699  # alive
- ps -E -ww -o command= -p 28699 | tr ' ' '\n' | grep '^CLAUDE_CONFIG_DIR='  # ~/.claude-secondary
- bash -c ". ~/.claude/scripts/limit-recover/lr-lib.sh; lr_successor_state $SID ~/.claude-secondary"  # husk 168 28699
- wc -c < "$TGT/$SID.jsonl"  # 2902688
- the lr_last_api_error kind on the TGT copy  # limit
- the at-rest jq over 'cat $SRC/$SID.jsonl.handed-off $SRC/$SID.jsonl'  # must now read at rest
- bash -c ". ~/.claude/scripts/lib/cc-tui.sh; cc_tui_composer_text 168"  # '[Image #5]', kitty get-text only
- bash ~/.claude/scripts/limit-recover/lr-fleet.sh --one $SID --target next4 --source-pane 168 --dry-run  # a husk-recycle DRY row naming the exact argv
Before the dry run: lr-fleet.sh:1518 says a dry run reserves nothing, but the new --one husk path must be read first to confirm it has no side effects. I have not verified that.

STEP 2 (THE RAIL, UNATTENDED):
1. Poller tick (launchd; ticks measured about 5-18 min apart). reroute_parked/W5-A sees husk with autorecover.on and files requests/$SID.json (requested_by stranded-husk). The drain logs STRANDED-HUSK and dispatches 'lr-fleet.sh --one $SID --target next4 --from-daemon --detach'.
2. lr-fleet. lf_husk_recycle:
   - source row 168; lr_husk_state rc 0; run claim taken;
   - admit lock, then the capacity probe for next4. If next4 is capped: parked/capped, and the poller retries;
   - mint a token, charge next4, and lru_mint_launcher writes L.
3. handoff-fire: '/bin/bash ~/.claude/scripts/handoff-fire.sh --recycle --transplanted-source --husk --transplant-cause limit --resume-launcher L --resume-cfg /Users/chrisren/.claude-quaternary --resume-cwd /Users/chrisren/Development/.worktrees/wt-cc-195938-17814 --source-pane 168 --source-session $SID', with CC_RECYCLE_BGWORK_ANSWER unset.
4. Composer gate:
   - the carry arm saves draft.txt, the ANSI snapshot, and 5.png and 4.png;
   - the provenance predicate classes 5.png as rail residue (04:45:31 CR in run one-20261010T044520Z), so it is not re-attached;
   - cc_tui_clear reads back empty.
5. Last read on the joined files: limit, and at rest. Then /exit is typed and read back.
   - Expected: no bg-work dialog. The only task finished at 04:36:58, and the MCP child pid 32928 was not counted as work.
   - If a dialog appears: stop-if-watcher, or keep-work plus bgcopy-stop.
6. Watcher:
   - shell confirmed;
   - relaunch typed: lr-fire-resume.sh next4 … --resume $SID;
   - engagement confirmed by token;
   - nothing to put back; the event names the saved paths.
7. lr-fleet: lf_await_relaunch scoped to quaternary => husk-recycle/RECOVERED. The next poller tick retires the request: 'live successor … next4'.

To skip the wait, the agent (not the operator) may run 'bash ~/.claude/scripts/limit-recover/lr-fleet.sh --one $SID --target next4 --source-pane 168 --detach'. The unattended tick is the stronger proof of C2's owner.

### Files
- /Users/chrisren/.reso/limit-recover/drafts/186452ed-02e5-4749-a4aa-8ece6f9ba1bf/20261010-preserve/
- /private/tmp/claude-501/-Users-chrisren-Development--worktrees-wt-cc-195938-17814/186452ed-02e5-4749-a4aa-8ece6f9ba1bf/images/{4,5}.png
- /Users/chrisren/.claude/cc-registry/168.json
- /Users/chrisren/.reso/limit-recover/poller.log
- /Users/chrisren/.claude/logs/handoffs.jsonl

### Test
STEP 3 (VERIFY, READ-ONLY). Run once at the verdict and again 10 minutes later, as a process census.
- ps -o pid= -p 28699  # empty
- P=$(pgrep -f -- "--resume $SID")  # exactly one
- ps -E -ww -o command= -p $P | tr ' ' '\n' | grep -E '^(CLAUDE_CONFIG_DIR|KITTY_WINDOW_ID)='  # ~/.claude-quaternary, 168
- jq -c '{pid,session_id,account}' ~/.claude/cc-registry/168.json  # P, $SID, claude-quaternary
- jq -r .sessionId ~/.claude-quaternary/sessions/$P.json  # $SID
- tail -n 50 "$TGT/$SID.jsonl" | jq -rc 'select(.type=="assistant")|[.timestamp,(.isApiErrorMessage//false)]' | tail -2  # a fresh non-error turn
- grep $SID ~/.claude/logs/handoffs.jsonl | jq -r '[.ts,.class]|@tsv' | tail -8  # recycle-draft-saved and engaged; no recycle-held-*, no recycle-dead
- shasum -a 256 of the saved images vs the sources  # equal
- grep $SID ~/.reso/limit-recover/poller.log | tail -3  # STRANDED-HUSK, then REQUEST-RETIRED 'live successor … next4'
- grep -c 'Send or clear\|Clear/send' over the run's stderr and pages  # 0

ACCEPTANCE: pid 28699 is gone; one --resume process runs on next4 in kitty window 168; the registry and session rows agree; a fresh turn exists; the draft and images are saved with their paths named; zero operator asks.

