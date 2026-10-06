# q5b — clock waits in the rotation path (2026-10-06)

Scope: every fixed sleep or poll interval between "operator asks for a rotation" and "verdict
written", what event each stands in for, and whether that event is directly observable.
Tags: MEASURED (I ran the command), READ (source or record), INFERRED (arithmetic across records).
Paths are relative to the checkout `/Users/chrisren/Development/.worktrees/lr-zero-memory`.
The nine scripts cited are byte-identical to the deployed copies under `~/.claude/` that produced
the records (MEASURED: `cmp -s` on each, 9 of 9 same), so line numbers apply to the recorded run.

Sample behind every measured timing: one batch, 7 idle moves next3 to next2,
`~/.reso/limit-recover/move/20261006T060534Z-next3-next2-64630` (n=7 moves, n=1 batch).

## 1. Answer

- Always-paid fixed clock time on the move lane is **23.7 s per move** (READ, sum of defaults in
  table 3). Median measured move was **174.6 s** actuate to result (MEASURED, n=7, range
  118.3-217.4). Fixed clocks are 14% of a move.
- Two of the five fixed waits (15 s process hold, 5 s stable dwell) prove the same fact twice in
  series; the 15 s one sits inside the slot-holding window, so it also delays the next wave.
- The largest single clock-shaped wait is not a sleep: the request sat **89 s** waiting for the
  launchd poller to start a new tick (MEASURED, n=1).
- Most of the remaining time is not a clock wait at all and is not timestamped: 68 s inside
  lr-handoff before the bundle (wave 1, n=4), 71 s and 120 s between the watcher's type instant
  and the launcher reaching its gate (panes 16, 15), 23-69 s from READY to the engaged row against
  a 15 s hold (n=7: 23, 23, 28, 29, 31, 33, 69).
- Memory did not bind in this batch: 8 of 8 kernel-safety reads admitted with reclaimable
  32.98-34.75 GB against a 4 GB floor and swap segments 4.33-4.50% against a 90% ceiling (READ,
  `~/.claude/autonomy/idl.jsonl`, callers lr-move-batch and lr-move-worker, 06:07:04Z-06:09:55Z).

## 2. Measured timeline of the batch

| Segment | Seconds | Kind | Receipt |
|---|---|---|---|
| request written to batch runner start | 89 | MEASURED | `request.claimed.json` ts 1791266734 = 06:05:34Z; `poller.log:72885` "MOVE-BATCH started" 06:07:03Z |
| admit, preseed, fan-out | 3 | MEASURED | `admit.json` 06:07:04Z, `workers.tsv` mtime 06:07:07Z |
| wave 1 (4 moves) actuate to result | 174.0-174.9 | MEASURED | `<sid>.events.jsonl` t_ms, 4 files |
| wave 2 (3 moves) slot wait | 166.7-167.2 | MEASURED | `slot-wait` to `slot` events, 3 files |
| wave 2 actuate to result | 118.3, 207.5, 217.4 | MEASURED | same |
| last result to `summary.json` (router re-read plus guard check) | 44 | INFERRED | last result t0+386.7 s = 06:13:33Z; summary 06:14:17Z |
| request to summary | 523 | INFERRED | 06:05:34Z to 06:14:17Z |

Inside one wave-1 move (pane 2, session 7f5deb68; the other three wave-1 moves match within 3 s
except the launcher gate, which was 9 s later on panes 4 and 12):

| Step | Wall time (Z) | Delta s | Kind |
|---|---|---|---|
| lr-handoff starts | 06:07:07.9 | 0 | MEASURED (`actuate` event) |
| bundle dir minted (lr-handoff.sh:968-970) | 06:08:16 | 68 | READ (bundle name `bundle-20261006T060816Z`) |
| probe and admit done | 06:08:28 | 12 | READ (bundle `events.jsonl`) |
| handoff-fire starts; watcher detached | 06:08:29; 06:08:40 | 1; 11 | READ (`handoffs.jsonl` phases `detach@11s`) |
| lr-handoff returns | 06:08:55.7 | 16 | MEASURED (`actuated` event) |
| launcher at its gate, claude spawned | 06:09:16 | 20 | READ (`gate-exempt`, `relaunch-typed` rows) |
| TUI READY | 06:09:18 | 2 | READ (`READY` row) |
| watcher engaged row | 06:09:51 | 33 | READ (`handoffs.jsonl` recycle-engaged) |
| worker first proof | 06:09:55.2 | 4 | MEASURED (`proof-first`) |
| worker result | 06:10:02.8 | 7.6 | MEASURED (`result`) |

Other measured facts used below:
- Claude spawn to READY: 2, 5, 5, 5, 4, 5, 4 s (READ, 7 bundles). The actual boot is 2-5 s.
- Shell confirmed after 9, 12, 12, 12, 13 poll rounds with no dialog (n=5) and 16, 17 with the
  background-work dialog (n=2) (READ, 7 watcher logs in `$TMPDIR/handoff-recycle-*.log`).
- 15 nominal 1 s rounds took 21 s and 33 s of wall time (INFERRED: `detach@4s` to
  `recycle-bgwork-stopped-watcher` elapsed 25 s and 37 s, panes 15 and 16). A round is 1.4-2.2 s.
- `proof-first` to `result`: 7.4, 7.6, 7.6, 7.6, 7.7, 7.8, 10.0 s (MEASURED, n=7).
- Poll body costs now (MEASURED, `python3` timing loop, n=3-5 each, box at load averages
  91.74 / 70.50 / 58.83 from `uptime` at 06:37Z, 1,173 processes, 10 CPUs):
  `ps -axo pid=,ppid=` 56 ms; `ps -axww -o args=` 163 ms; 30 registry rows through `jq` 277 ms;
  `grep -F <sid> idl.jsonl | jq` 281 ms (the file is 24.4 MB).

## 3. Move lane: every clock wait (cc-lr move, batch, worker, lr-handoff, recycle, launcher)

Signal column: file = a create, remove or append the waiter can stat; process = a pid appearing or
exiting; screen = readable only through a terminal screen read; none = a settle or a rate limit.

| # | Wait | Default s | file:line | Event it stands in for | Direct signal | Paid | Typing-safety |
|---|---|---|---|---|---|---|---|
| A1 | poller hop: `launchctl kickstart` without `-k`, self-overlap lock skips, interval 600 | 0 to one tick | bin/cc-lr:1338-1340; com.reso.lr-reset-poller.plist:37; lr-reset-poller.sh:207-233, 273-301 | a batch request file exists | file | always, cost 0 only when no tick is running | no |
| A2 | cc-lr move report poll, bound 600 | 3 | bin/cc-lr:1238, 1362 | `<sid>.json` appears | file | always, operator-facing only | no |
| A3 | batch admit lock poll, bound 90 | 1 | lr-move-batch.sh:114-121 | another batch left the admit section | file (dir) | contention | no |
| A4 | batch watch poll; 1 s after a dead worker; census every 20 | 2 | lr-move-batch.sh:215, 224, 230 | a worker exited or wrote its result | file, process | always (quantizes batch close) | no |
| A5 | worker claim wait, 30 tries | 0.5 | lr-move-worker.sh:79-84 | runner re-stamped the claim | file | usually 0 sleeps (spawn to claimed 0.1-0.3 s, n=7) | no |
| A6 | worker idle wait: 5 s poll over 20 s census, two consecutive `move` | 20-45 after idle | lr-move-worker.sh:103-115; lr-move-batch.sh:224-229 | the turn ended and stayed ended | file (transcript at rest) | `wait:*` rows only (0 of 7) | pre-filter; the last read at handoff-fire.sh:3182 is the guard |
| A7 | worker slot wait, bound 600, width 4 | 2 | lr-move-worker.sh:121-126; lr-move-lib.sh:182-207 | a slot dir was released | file (dir), process | moves beyond the width (3 of 7 waited 167 s) | no |
| A8 | worker prove poll and same-pid dwell, bounds 300 and 20 | 2 poll, 5 dwell | lr-move-worker.sh:158-178 | P1-P7 true; relaunch did not die at boot | file, process | **always: 5 fixed** plus up to 2 polls | no |
| A9 | wake guard: hold if woke under 30 s ago; sleep up to 30 twice | 0 or up to 30 | lr-handoff.sh:1501-1512; handoff-fire.sh:3086-3101, 16345, 16359 | terminal and TUI settled after wake | none beyond `kern.waketime` | only within 30 s of a wake | yes |
| A10 | lr-handoff git lock, 21 tries | 0.5 | lr-handoff.sh:813-843 | lock dir removed | file | `pool/*` branch only | no |
| A11 | focus gate gap between two composer reads, run 3 times | 10 each, 30 total | lr-lib.sh:1107-1121; handoff-fire.sh:11242, 16777, 3185 | the operator is not typing | screen; HID idle seconds are read and logged | focused pane only (0 of 7) | **yes** |
| A12 | draft wait, 15 s poll | up to 180 | handoff-fire.sh:3871-3882, 16582-16592 | the draft was submitted or cleared | screen | draft present only | **yes** |
| A13 | `await_armed` (25 ticks), `await_pane_proof` (90 ticks) | 0.2 | handoff-fire.sh:1902-1909, 1933-1943 | watcher wrote `armed:` and `pane-reachable:` | file (log line) | always, 0.2-1 s | gate yes, interval no |
| A14 | `/exit` read-back, sleep before each of up to 3 reads | **0.5** | handoff-fire.sh:3284-3303 | composer painted `/exit` | screen | **always: 0.5 fixed** | **yes** |
| A15 | watcher shell poll, bound 600 | 1 | handoff-fire.sh:9475, 9607-9612 | old claude exited, foreground group is the shell | process | always (up to one round) | affirmative read yes, interval no |
| A16 | background-work dialog look, floor 3 | every 15 rounds | handoff-fire.sh:9591-9593, 9646-9653 | `/exit` raised the dialog | screen | 2 of 7 moves; cost 21 s and 33 s wall | answer is read off the screen; cadence no |
| A17 | pane-vanished look; nudges at 60, 150, 300 | every 15 rounds | handoff-fire.sh:9609, 9616, 9629-9632 | pane was destroyed; `/exit` stranded | screen (listing) | slow exits only | no |
| A18 | shell-prompt settle, literal with no seam | **2** | handoff-fire.sh:10011 | zsh finished precmd and is reading | none (process state is a proxy) | **always: 2 fixed** | partly (mangled paste, not wrong pane) |
| A19 | type-verify settles, 2 lines; 3 s between 2 outer tries | **0.12 + 0.5 per line = 1.24** | handoff-fire.sh:3677-3724, 10065-10068 | terminal echoed the paste | screen (read straight after) | **always: 1.24 fixed** | verify yes, fixed settle no |
| A20 | boot wait: 0.5 tick, pane read every 6 ticks; alarm at 60; 5 s ticks to 180 | 3 nominal per pane read | handoff-fire.sh:10110-10196 | launcher spawned claude or refused | file (`relaunch.rc`, run `events.jsonl` rows), process | always (quantization); each tick also greps the 24.4 MB IDL | no-retype rule yes, cadence no |
| A21 | engagement-by-process hold; 3 s poll; bound 180 | **15** | handoff-fire.sh:10233-10254 | relaunch survived boot | file (launcher READY row, lr-fire-resume.sh:1275-1277), process | **always: 15 fixed** (7 of 7 "alive 15s past boot") | no (nothing is typed after it) |
| A22 | launcher git lock, bound 30 | 0.5 | lr-fire-resume.sh:404-418 | lock dir removed | file | worktree missing only | no |
| A23 | launcher quiet budget | 8 | lr-fire-resume.sh:977, 1213, 1280-1314 | frame settled though READY never matched | screen | fallback only (READY matched 7 of 7) | yes |
| A24 | menu arms: 1 s before answer, 1 s per Down, 10 s read-back | 1-12 | lr-fire-resume.sh:1174, 1185, 1226, 1239, 1255 | select mounted, selector on the right option | screen | menu rendered only | **yes** |
| A25 | prompt inject settles; submit poll 30 to 180 | 0.3, 0.2 | lr-fire-resume.sh:1270-1272, 1342-1464 | composer mounted; prompt record in transcript | screen; file | prompted resumes, not the move lane | yes |
| A26 | reply drain, 20 ms steps | about 0.06 | lr-fire-resume.sh:1521-1523 | queued terminal replies read | none | always, negligible | no |

Always-paid fixed sum, idle unfocused pane with a free slot: A14 0.5 + A18 2 + A19 1.24 + A21 15 +
A8 5 = **23.74 s** (READ). Expected poll quantization on top is about 5 s nominal (A13, A15, A20,
A8), more under load because a round costs 1.4-2.2 s.

Coupling that matters more than the sum (READ): the slot is released at the first MOVED read
(lr-move-worker.sh:168); MOVED needs P7, resume debt not open (lr-move-lib.sh:145-146); the debt
is discharged only after the 15 s hold (handoff-fire.sh:10245-10249). So A21 is inside every
slot-hold, and A8's 5 s dwell then re-proves a process that has already been alive 15 s.

## 4. Recover pool and drainer: clock waits

| # | Wait | Default s | file:line | Event | Direct signal | Paid |
|---|---|---|---|---|---|---|
| B1 | capacity wait poll, bound 120 | 20 | lr-fleet.sh:546-578 | capacity terms cleared | none (kernel counters) | refusal only |
| B2 | admit lock poll, bound 600 | 0.2 | lr-fleet.sh:603-633 | holder left | file | contention |
| B3 | router `--max-wait`, one retry at 15 | 3 | lr-fleet.sh:734-749 | fresh quota reading | the router's own | conditional |
| B4 | relaunch proof poll, bound 240 | 5 | lr-fleet.sh:918-936 | registry row for the sid appears | file | always on recover |
| B5 | nudge engage poll, bound 120 | 5 | lr-fleet.sh:1231-1238 | assistant turn | file | nudge path |
| B6 | `--one` slot poll, bound 900, cap 2 | 10 | lr-fleet.sh:1381-1412 | slot dir released | file | more than 2 at once |
| B7 | pool reap poll, cap 2 | 0.2 | lr-fleet.sh:1362, 1435-1448 | child exited | process | always, small |
| C1 | gap between drained requests | 10 | lr-upgrade.sh:88, 2395 | none: a spacing rule | none | always, (N-1) x 10 |
| C2 | prove hold; 5 s gap, 3 tries | 15 | lr-upgrade.sh:1897-1906 | relaunch survived boot | file, process | always |
| C3 | switch verdict polls | 5 | lr-upgrade.sh:1070, 1236, 1709 | registry flip, transcript at rest | file | always |
| C4 | draft-restore settle; wait 300 | 3 | lr-upgrade.sh:1055, 1086 | image chip rendered | screen | draft restore only |
| C5 | retype gap; 2 s poll for 30; max 5 | 20 | lr-upgrade.sh:86, 2077-2078 | launcher took the line | process | failure |
| C6 | engage poll, bound 200 | 5 | lr-upgrade.sh:2104-2111 | assistant turn | file | always |

## 5. Which waits must stay

Shortening these risks typing into a busy or wrong pane, or answering the wrong menu option:
A11 focus gap, A12 draft wait, A14 `/exit` read-back, A24 menu arms, A9 wake guard, and the
affirmative reads inside A13, A15, A19, A23 (the reads, not their intervals).

Not typing-safety (proof, pacing or reporting): A1, A2, A4, A7, A8, A16 cadence, A17, A20 cadence,
A21, B4, B6, B7, C1, C3, C6.

## 6. What the tests pin

- No test asserts the 15 s hold default, the 5 s dwell or the 2 s settle value (MEASURED:
  `grep -nE "PROC_HOLD_S:-|LR_MOVE_STABLE_S|STABLE_S:-|shell-prompt settle|HF_ENGAGE_PROC_HOLD_S" tests/*.bats`
  returns two lines, the seam and the anchor below).
- `tests/handoff-recycle-custody.bats:140` drives `HF_ENGAGE_PROC_HOLD_S=0`; the seam exists.
- `CC_RECYCLE_BGWORK_EVERY_S=3` is what 6 test sites run (MEASURED, `grep -c`: 4 in
  handoff-fire-recycle-custody.bats, 1 in handoff-recycle-bgwork-dialog.bats, 1 in
  handoff-recycle-bgcopy-stop.bats); 3 is the floor in source.
- The comment text `shell-prompt settle after claude exits` is a range anchor in
  `tests/handoff-recycle-remote-resume.bats:780`; editing that line needs the anchor kept.
- Boot-wait seams are exercised at `RCY_BOOT_IVL_S=0.2`, `RCY_BOOT_PANE_EVERY=1` (7 and 10 sites).

## 7. Alternatives considered

- Collapse the three focus-gate runs to one: rejected here, it is the only guard against an
  operator typing between probe and `/exit`, and no focused pane was in the sample.
- Start the batch runner straight from cc-lr instead of through the poller: rejected,
  `bin/cc-reaper:938` TERMs any launchd-parented bash older than 600 s whose argv misses the
  whitelist (docs/lessons/detached-bash-is-reaped-after-ten-minutes.md).
- Replace the shell poll with a kqueue exit notification: the poll already checks before it
  sleeps, so the saving is under one round per move.

## 8. Uncertainties

- n=1 batch. Every measured duration comes from one run on one night.
- The 68 s before the bundle (wave 1 only, all four ending within 2 s of each other; wave 2 took
  under 1 s) has no sleep in lr-handoff.sh:1-968 except the `pool/*` git lock. Cause not found.
- Panes 15 and 16 reached the launcher gate at 06:12:38Z, 71 s and 120 s after their watchers
  recorded the type instant; both had the background-work dialog. Cause not found. Watcher logs
  carry no timestamps, so the stall cannot be placed between the type, the shell and the launcher.
- Load during the batch was not recorded; the 91.74 reading is from 06:37Z.
- `bin/cc-reaper:718` whitelists `lr-reset-poller` but not `lr-move-batch`, `lr-move-worker` or
  the `handoff-fire.sh __recycle` watcher. Oldest move-lane process in this batch was 434 s, and
  the reaper log shows 0 such kills on 10-04 to 10-06, so the exposure is inferred from the rule's
  shape only. A batch needing more than three waves at about 175 s each would cross 600 s.
