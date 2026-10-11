# A2 — lane census: move, switch and upgrade failures (2026-10-11T04:06Z, trunk 110ea9a64)

**Answer first.**
- The move lane moved 9 of the 29 rows it drove across its 5 batches (2026-10-06 to 10-11). Leaving out the operator's abort, that is 9 of 23.
- Every move-lane "stood down before confirm" came out FAILED instead of a clean NOTMOVED: 4 of 4 measured. The cause is deterministic. `lr-transplant --phase abort` runs inside `$( )`, so its `$PPID` is the subshell's pid, and it refuses to abort because its own caller, lr-handoff, is "a live actuator". The fleet lane escapes this (9 of 9 aborts succeeded) only because it records no holder. The refusal leaves a stale target transcript, and one of these (4d059264) is still split-brain 22.7 h later.
- Batch 20261011T032613Z: its summary, its mail and its text `--status` all report "done: NOTMOVED=7". Nothing a requester sees says "aborted". The batch runner also ignores the abort file: abort was written at 03:40:58Z, yet the batch admitted at 03:41:16Z, claimed 7 sessions and started 7 workers.
- The upgrade lane's dominant failure is skip churn: 155 `relaunch-surface-unverified` skips, 141 attempt dirs on 2026-10-08. 85a67c70b bounded it. The 2 current stranded husks are labelled "nothing typed" after their /exit had already been typed.
- The switch lane has been dormant since 2026-10-04.

## Census (MEASURED)

Per move batch: summary.json, per-row `<sid>.json`, and `plan.ts`→`admit.json.ts`.

| batch | driven | MOVED | NOTMOVED (cause) | FAILED (cause) | plan→admit | wall |
|---|---|---|---|---|---|---|
| 20261006T060534Z next3→next2 | 7 | 7 | 0 | 0 | 90 s | 434 s |
| 20261010T012444Z next→next2 | 8 | 0 | 3 slot-wait, 3 HELD:exit-readback, 1 still-busy (1800 s) | 1 source-ambiguous (abort refused) | 248 s | 1946 s |
| 20261010T051618Z next2→next | 5 | 0 | 1 HELD:pane:resolver-unavailable, 1 HELD:composer-unreadable | 3 source-ambiguous (abort refused; "kitty is not answering") | 89 s | 528 s |
| 20261010T053236Z next2→next | 2 | 2 | 0 | 0 | 4 s | 237 s |
| 20261011T032613Z next→next4 | 7 | 0 | 6 operator abort, 1 became-limited | 0 | **903 s** | 155 s |

- **Totals.** 29 rows: 9 MOVED, 16 NOTMOVED, 4 FAILED. Husks: 0 STRANDED at verdict time. Duplicate processes: 0 rows with more than 1 holder; all 4 FAILED rows read "1 holder(s) and 2 live transcript(s)".
- **Pane-transport holds** (kitty unreachable, exit-readback, composer, resolver): 9 of the 14 non-abort non-moves. Their cause is covered by `docs/research/recycle-failures-kitty`.
- **Sessions that failed in more than one batch:**
  - 44091255: FAILED, then aborted.
  - 7f70bfc4: slot-wait, then aborted.
  - e582464c: slot-wait, then became-limited.
  - bb1d86c8 and c56c729c: HELD, then MOVED, then aborted.
  - 1c0f7f90, 4d059264, 7f5deb68: MOVED on 10-06, then FAILED on 10-10.
- **Switch lane.** `results/switch-*.json` holds 28 results: 16 SWITCHED, 12 NOTMOVED. The NOTMOVED causes:
  - 6 "the subject took its turn and did not move". One subject replied "I ran the switch. The session has moved…" and was still NOTMOVED.
  - 2 composer-unknown.
  - 1 each: on-target, not-live, background-job budget, submit refused (paste-not-echoed).
  - The last result is dated 2026-10-04T19:32Z, so the lane is dormant.
- **Upgrade lane.**
  - `results/upgrade-*.json` keeps only the latest result per session (56 files): 25 upgraded, 27 skipped, 4 failed.
  - The skip causes are 11 relaunch-surface-unverified, 4 not-live, 4 busy, 2 handoff-fire-refused, 2 composer-unknown, 2 background-job, 1 current, 1 capacity.
  - `upgrade-drain.log` (2244 lines, 422 "drain done") holds every attempt: 155 relaunch-surface-unverified skips, 24 upgraded, 7 handoff-fire refusals, 2 failed-stranded.
  - Attempt dirs by day: 141 on 2026-10-08. The per-session maximum is 18 (0715cd0c, on 09-29); bb1d86c8 had 15 on 10-08.
- **`cc-lr upgrade --report`** (`/usr/bin/time -p`) took real 0.75 s and listed 2 failed (6507a980 and a2601c01, both "stranded", escalated to cc-backlog) and 3 skipped.
- **`cc-lr move --status <batch>`** took real 36.88 s on 032613Z and 28.81 s on 051618Z. Loadavg was 281/267/212 at 04:06Z, from `sysctl vm.loadavg`.
- **Not failure sources.**
  - `fire-claims/`: 27 empty markers, the newest from 2026-10-04.
  - `draft-paged/`: 2 empty markers.
  - `one-slots/`: 0 entries.
  - `resumed/`: 130 receipts.

---

## A2-1 — An in-place recycle that stands down before confirm becomes FAILED and a stale target copy whenever a record id is set (every move-lane row)

- **Symptom.** The recycle held before any confirm (kitty not answering, HELD:unreachable). lr-handoff then calls `lr-transplant --phase abort`, which refuses with `REFUSED (target-held) — the actuator the lock records (pid N) is still running`.
  - The verdict becomes FAILED instead of NOTMOVED (rc 4, not 6).
  - The tombstone, lock and target transcript are left behind, so the move verdict reads `source-ambiguous … 2 live transcript(s)`.
  - The FAILED text says "retry … lr-fleet.sh --one". Prior research (lr-stranded-husk C3 :174) measured that this advice loops: fleet answers "already TRANSPLANTED→next … nothing to do".
- **Frequency (MEASURED).** Move lane: 4 of 4 aborts refused. Fleet `--one` lane: 9 of 9 aborts succeeded. Command: `grep -rhoE "abort refused \(rc …|abort rc 0 withdrew the admit" ~/.reso/limit-recover`, which counts 4 refused and 9 ok. The refusals are 44091255 (10-10 01:35Z) and 1c0f7f90, 4d059264, 7f5deb68 (10-10 05:20Z). The successes are all in `fleet/one-*/detached.log`, 10-01 to 10-11.
- **Root cause.**
  - `scripts/limit-recover/lr-transplant.sh:106`: `LRT_HOLDER_PID="${LR_HOLDER_PID:-$PPID}"`.
  - The admit is invoked directly at `lr-handoff.sh:1555`, so its holder is lr-handoff's own pid.
  - The abort is invoked inside a command substitution at `lr-handoff.sh:1960`: `_lrh_ab_out="$("$LR/lr-transplant.sh" --phase abort … 2>&1)"`. Its `$PPID` is therefore the subshell's pid. `lr-transplant.sh:620-622` sees holder ≠ caller, finds the recorded holder (lr-handoff itself) alive, and refuses.
  - A holder is written only when a record id exists (`lr-transplant.sh:266-267`, `lrt_holder_json` returns early on an empty `RECORD_ID`). The move worker passes `LR_RECORD_ID`/`--record-id` (`lr-move-worker.sh:160-165`) and so does the reconciler (`lr_recon/act.py:56,120`). `lr-fleet.sh:992-1006` passes none, which is why the fleet lane's aborts pass.
  - The comment at `lr-handoff.sh:1951-1953` ("this process is the lock's recorded actuator … abort's live-holder refusals cannot fire on us") states the opposite of what the code does.
- **Fix (S).**
  - Change `lr-handoff.sh:1960` to `_lrh_ab_out="$(LR_HOLDER_PID=$$ "$LR/lr-transplant.sh" --phase abort …)"`. `$$` in a subshell is still lr-handoff's pid. Apply the same to any other custody phase that lr-handoff calls through `$( )`; grep for `lr-transplant.sh" --phase` inside `$(`.
  - Bats test in `tests/lr-transplant-custody.bats`, "custody 8c: the admitting actuator can abort its own admit through a command substitution":
    - a wrapper script runs `--phase admit --record-id R1` directly, then `out="$(lr-transplant.sh --phase abort --record-id R1 2>&1)"`;
    - assert rc 0, target copy gone, lock gone;
    - this is red on trunk (rc 2, `live-actuator`).
  - Existing coverage misses this:
    - custody 8 sets `LR_HOLDER_PID` explicitly (:232).
    - `lr-handoff-flags.bats:389` stubs lr-transplant.
- **Conviction.** 88.
- **Receipts.**
  - The 4 refused pids are lr-handoff's own pids, read from the bundle `events.jsonl` `writer` field: 1c0f7f90 82990 = `lr-handoff.sh:82990`, 7f5deb68 82734, 4d059264 83498, 44091255 37369.
  - bash 3.2 demo: `/bin/bash -c 'x="$(/bin/sh -c "echo \$PPID" 2>&1)"; echo $$ $x'` printed `self=12863 child_ppid=12866`. Run directly, `direct_ppid=12863`.
  - Still split-brain now: `cc-lr move --status 20261010T051618Z-next2-next-50417` shows 4d059264 `FAILED … 1 holder(s) and 2 live transcript(s)`. `ls` shows a 1440932-byte stale copy in `~/.claude/projects/…` next to the 1644392-byte live copy under `~/.claude-secondary`.

## A2-2 — An operator abort is indistinguishable from failure in the summary, the mail and the text status, and the batch runner ignores it

- **Symptom.** Batch 20261011T032613Z:
  - The per-row reasons say "aborted before the move" (4) and "aborted while waiting for a slot" (2), plus 1 "became-limited … Recover it: cc-lr recover e582464c".
  - What the requester sees, in three places:
    - `summary.json`: `{"status":"done","note":"","verdicts":"NOTMOVED=7"}`.
    - The mail in `~/.claude/mailbox/223.md`, forwarded to the session: "cc-lr move … done: NOTMOVED=7; target auth after the batch: ok."
    - The text `cc-lr move --status`: the REASON column is re-derived from disk ("live in pane 12 on the source, one copy"). The recorded reason is dropped, and hold rows show as `pending`.
  - None of the three says "aborted" or carries the became-limited row's "recover it" action.
  - The abort file is dated 22:40:58 local (03:40:58Z), but `admit.json` is 03:41:16Z. The runner still read the router, took 7 claims, ran preseed, started 7 workers, ran 7 fences and 3 capacity probes, and finished at 03:43:45Z (155 s at loadavg ~260).
- **Frequency (MEASURED).** 1 of 1 aborted batches. 1 of 5 batches carried a became-limited row whose action was lost.
- **Root cause.**
  - `lr-move-batch.sh:78-91`: `summary()` counts `.verdict` only and always writes status `done`. The abort file is never read anywhere in lr-move-batch.sh (`grep -n abort` gives 0 hits). Only the worker checks it (`lr-move-worker.sh:94,105,139,153`).
  - `bin/cc-lr:1305-1307`: the text renderer discards field 6 (`recorded_reason`).
  - `bin/cc-lr:1293`: `${rec:-${act:+pending}}` labels hold rows `pending`.
- **Fix (S).**
  - In `lr-move-batch.sh`, after :112: `[ -e "$BDIR/abort" ] && refuse "aborted by the operator before admit"`.
  - In `summary()`, set `status=aborted` when `$BDIR/abort` exists, and count reason classes (`NOTMOVED/aborted=6 NOTMOVED/became-limited=1`).
  - The mail appends each actionable row's own instruction (the `Recover it:` clause).
  - `cmd_move_status` prints the recorded reason when it differs from the re-derived one, and prints `held: <disposition>` instead of `pending` for `act=hold`.
  - Bats:
    - `lr-move-worker.bats`/`lr-move-plan.bats`: a fixture batch with `abort` present before the runner starts gives 0 claims, 0 workers, and `summary.status == "aborted"`.
    - A row fixture with reason "became-limited …" makes the mail text contain `cc-lr recover`.
- **Conviction.** 85.
- **Receipts.** `stat` of the batch dir (`abort` 22:40:58, `admit.json` 22:41:16); `cat summary.json`; `grep "cc-lr move 2026" ~/.claude/mailbox/223.md`; the `cc-lr move --status` output; `bin/cc-lr:1276-1308`.

## A2-3 — The move request waits on the poller tick: 903 s plan→admit when a tick stalls, and the requester sees nothing

- **Symptom.** `cc-lr move` prints "queued for the poller" and kickstarts the poller. Batch 032613Z was admitted 903 s later. The other batches took 4-248 s. Meanwhile the requester had only the queue line.
- **Frequency (MEASURED).** Plan→admit for the 5 batches: 90, 248, 89, 4 and 903 s, from `jq .ts plan.json` vs `admit.json`. 1 of 5 exceeded 5 min.
- **Root cause.**
  - `lr-reset-poller.sh:314` and `:242`: `lrp_move_kick` runs only at tick start and in the EXIT trap.
  - `lr-reset-poller.sh:233-238` (the code's own comment): launchd drops a `kickstart` sent while a tick runs.
  - A tick stuck in the parked loop (`:2127`, ~20 min on 10-11) therefore holds every move request.
- **Fix (M).**
  - Add a dedicated launchd job (`com.reso.lr-move-kick.plist`) with `QueueDirectories=~/.reso/limit-recover/move/requests` that runs only `lrp_move_kick`. It stays detached and owned by launchd, which keeps the "not a child of the session" rule, and the hard-link claim stays as is.
  - `cc-lr move` should also re-check after 60 s and print/mail "not started after 60 s: poller tick pid N running since T".
  - Bats: source the poller in `--dry` mode with a fake `PARKED` loop that sleeps, and assert that the separate kick entry point starts a batch while the poller lock is held.
- **Conviction.** 70. The cause is measured. The QueueDirectories design is inferred, not tried.
- **Receipts.** The latency loop above; `poller.log` "MOVE-BATCH started pid 15968" at 03:41:09Z (from the brief); `lr-reset-poller.sh:286-314`.

## A2-4 — Slot-wait timeouts: a fixed 600 s wait behind actuations that took 351-1023 s, and a FAILED actuation keeps its slot for the 300 s prove window

- **Symptom.** Batch 012444Z: 3 of 8 rows NOTMOVED with `slot-wait: no move slot freed in 600s (width 4)` (6defb493, 7f70bfc4, e582464c), each about 611 s.
- **Frequency (MEASURED).** 3 slot-wait rows out of 29 driven, all in one batch.
- **Root cause.**
  - The 4 slot holders acquired at 01:29:24-26Z.
  - Their `lr-handoff` returned at 01:35:30 (rc 4) and 01:45:00-01:46:46 (rc 6, exit-readback after 15-17 min: the transport cause in recycle-failures-kitty).
  - The waiters' deadline fell at about 01:39:22Z.
  - `lr-move-worker.sh:136-142` has a fixed `LR_MOVE_SLOT_WAIT_S=600`, independent of the actuator's bound.
  - `lr-move-worker.sh:176-195` releases the slot only on a MOVED read (:185) or at `finish` (:62). After `hrc=4` the worker polled for 300 s (`LR_MOVE_PROVE_S`) still holding slot-1 (01:35:30→01:41:07, 337 s), although nothing more is typed into that pane.
- **Fix (S).**
  - Call `lr_swap_slot_release` right after `ev actuated` when `hrc != 0`. The slot guards terminal control streams and boots; a returned non-zero actuator does neither.
  - Extend the slot deadline while any slot holder's worker is alive and has emitted an event within the last 120 s.
  - Bats in `lr-move-concurrency.bats`:
    - set up width 1, with a stub handoff returning rc 4 after 1 s, prove 30 s, and the second worker's slot wait 10 s;
    - assert the second worker reaches `slot`;
    - it is red on trunk.
- **Conviction.** 65. The early-release half is certain from code and timestamps and would have saved 1 of the 3 rows. The other 2 are transport-bound.
- **Receipts.** `jq` timelines of `<sid>.events.jsonl` in move/20261010T012444Z (slot 01:29:24, actuated rc 4 01:35:30, result 01:41:07; slot-wait 01:29:22 to result 01:39:27).

## A2-5 — Husks and duplicates from restarts: 0 duplicate processes; 4 stale transcript copies (A2-1); 2 stranded upgrade husks labelled "nothing typed" after /exit was typed

- **Symptom.**
  - Move: no row ever had more than 1 holder. The 4 FAILED rows have 2 transcripts each; that is A2-1.
  - Upgrade, 6507a980: the drain logged `skipped "/exit sent; old claude pid 81571 still alive after 60 s - watched each run (nothing typed)"`. It later ended `failed stranded (pane 166 at a shell after drainer death; the pane's identity is 1018 s old (> 900 s))` and was escalated to the backlog.
  - Upgrade, a2601c01: `stranded (pane 188 left at a shell; --relaunch-at-shell REFUSED:pane:absent)`. The kitty socket enumerates no window 188.
- **Frequency (MEASURED).**
  - Upgrade: 2 stranded on 2026-10-10 out of 7 upgrade attempts that day, from `ls upgrade | grep 20261010`. All time: 4 failed out of 56 latest results.
  - Move: duplicate processes 0 of 29.
  - Switch: not measurable, because switch results carry no holder count.
- **Root cause.**
  - `lr-upgrade.sh:2689` and `:2341` write "(nothing typed)" on the exit-pending path after `.exit_sent = 1` (:2664). The label is false, and a reader believes the pane was untouched.
  - The stranding, INFERRED: `LRU_SETTLE_TYPE_MAX_AGE_S=900` (`lr-upgrade.sh:112`, applied at :2226) refuses to type into a shell whose identity is older than 900 s. The settle runs only at drain cadence (≥600 s poller interval plus the tick duration), so an old claude that exits between drains can age past 900 s before the next settle.
  - a2601c01's pane was gone. That is not attributable to the lane.
- **Fix (S, for the label).**
  - Reword both sites to `exit-pending: /exit typed; old claude pid N still alive after 60 s`, and mail the requester when exit-pending is first set.
  - Bats in an `lr-upgrade` test: a stub handoff that leaves the old pid alive makes the result reason not contain "nothing typed" and contain "/exit typed".
  - The stranding half needs a watcher-side relaunch, not a drain-side one. That fix is M and unproven here.
- **Conviction.** 80 for the label. 45 for the stranding cause.
- **Receipts.** `grep -nE "6507a980|a2601c01" upgrade-drain.log` (lines 1989, 2050, 2172); `upgrade-state/6507a980….json` `terminal:"stranded"`; `upgrade/a2601c01-20261010T162143Z/relaunch-at-shell.1.log` "REMOTE-PANE-ABSENT".

## Ruled out
- **"The move mail never reached the requester."** It did. `~/.claude/mailbox/223.md` holds the 032613Z mail, plus `[forwarded:223]`. Mail for batches 168 and 180 was also delivered and forwarded. Delivery is not the gap; the content is (A2-2).
- **"The move lane created duplicate live sessions."** Every FAILED/NOTMOVED row had 1 holder (the `lr_move_verdict` P5 path, `lr-move-lib.sh:109-112`).
- **The 2026-10-06 false "done: no rows" mail** (summary `verdicts:"none"` while 7 of 7 MOVED) was the bash-3.2 `$( )` pattern bug. It is fixed in trunk with the leading-paren patterns at `lr-move-batch.sh:80-86`, and the later batches count correctly.
- **The upgrade skip churn as a current defect.** The 141 attempt dirs and 155 surface skips all predate 85a67c70b (2026-10-08T22:01Z, bounded retry). After it there were 3 + 7 attempt dirs over 10-09 and 10-10.
- **The switch lane as a live source.** Its last result is 2026-10-04T19:32Z.
- **fire-claims/, draft-paged/, one-slots/, resumed/.** These are empty markers, stale, or receipts only; there are no failures in them.

## Uncertain
- **Why the 012444Z exit-readback actuations took 15-17 min.** Composer `<unreadable>` under load. This is the transport cause owned by recycle-failures-kitty and was not re-measured here.
- **Whether the reconciler lane (`lr_recon/act.py`, which passes `--record-id`) has hit A2-1.** No "abort refused" appears under `~/.reso/limit-recover/recon` or in `handoffs.jsonl` (grep count 0). Exposure is inferred from code only.
- **The 6507a980 timeline.** When pid 81571 actually exited is not on disk, so the "drain cadence vs. 900 s cap" cause is inferred.
- **The e582464c recovery request** (`requests/e582464c….json`, stop-failure-marker, 03:33:03Z) still has no run. That belongs to the stuck-poller recover lane (other slots).
