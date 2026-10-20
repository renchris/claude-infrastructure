# 02 · Timeline forensics: the 2026-10-20 next3 weekly-cap recovery

Axis: rebuild the recovery per session from disk, sort every minute lost into a blocker class, and measure how long a reconciler pass takes under this load.
Read at 2026-10-20 ~04:20-04:30Z. Everything here was read only: no pane was typed into, no process was signalled, nothing under `~/.claude*` was edited.

## 0. Sources and how the timestamps work

| Source | What it gives | Clock trap |
|---|---|---|
| `~/.reso/limit-recover/recon/events.jsonl` (lines with t >= 1792460000) | reconciler events | `spawn` rows carry the pass's frozen `now`, not the moment they were written (`act.py:342-350`, `T.Event(t=now, ev="spawn")`). They show up out of order, after rows written later. Every other row the daemon writes uses `time.time()` (`__main__.py:125-130`). |
| `recon/sessions/<sid>.json` | `timeline.*`, `close.death` (the limit record's uuid@timestamp), `seen`, attempts | `detected`/`planned`/`busy_at`/`updated_at` are also pass `now` values |
| `recon/launch.log` | one row per move spawn, `t` = pass `now` | same as `spawn` |
| `recon/actlogs/<sid8>.<attempt>.<actuator>.log` | full lr-handoff stderr per attempt | no timestamps; paired with the bundle events |
| `~/.reso/limit-recover/<sid>/bundle-<UTC>/events.jsonl` | lr-handoff / lr-fire-resume stage stamps (placed, focus, precheck, gate, recycle-armed, verdict) | the bundle directory name is the moment lr-handoff created it |
| `~/.claude/logs/handoffs.jsonl` | recycle watcher rows (intent, staged, nudge, exit-signal, claimed, engaged) with a `phases` string | |
| `$TMPDIR/handoff-recycle-<pane>-<epoch>-*.log` | the watcher's own log | |
| `move/20261020T024813Z-…-78304/`, `move/20261020T030423Z-…-15173/` | move-lane batches for the 4 idle sessions | worker `events.jsonl` in ms epochs |
| `fleet/one-20261020T*` and `poller.log` | the hook lane (lr-reset-poller → `lr-fleet --one`) | |
| `recon/restarts.jsonl`, `recon/watchdog.log`, `recon/heartbeat` | daemon restarts and step gaps | |

Every number below is **measured** from these files (named) unless it is marked **estimated**. All times are UTC on 2026-10-20.

## 1. Headline

- **9 sessions, 4 lanes, 2 daemon restarts.** 5 of the 9 were limited by the weekly cap. They went to the reconciler (`origin=cc-lr`, requester sid f6ec3532). The other 4 were idle and went to the move lane (`cc-lr move`, 2 batches). 2 of the 4 idle ones then became limited while the move lane held them on load and fell through to the hook lane. The reconciler restarted twice in the middle of moves (03:23:17 and 03:53:16; `restarts.jsonl` rows pid 47282 and 38189).
- **State at the end of the read window (04:19Z):**
  - 3 fully recovered:
    - d7eb73d2: ENGAGED 03:53:31, CLOSED 04:09:32.
    - ceff45c5 and 9240c6a9: MOVED and engaged 03:58:17-19. They were idle, so no prompt was owed.
  - 2 relaunched on the new account but **with their continue prompt NOT typed**:
    - e80b61f4: 04:04:07 `READY-NOT-SEEN … prompt NOT typed`.
    - 7aae55e1: 04:14:48, same message.
    - Both records read `RELAUNCHED/UNPROMPTED`.
  - 4 not recovered: db755a94, 769b7294, 3e929a81, 3d1d988a.
  - The brief's "5 of 9 back by 04:14" counts the two UNPROMPTED sessions as back.
- **Where the 793 session-minutes went:**
  - Measured: limit time (or move request time) up to recovery, or up to 04:19:00 for the 4 still open.
  - Estimated: which blocker class each interval belongs to.
  - The 2 biggest classes are the **move lane's load wait (19%)** and the **reconciler's pass cadence (19%)**.
  - Next come **actuator wall time under load (13%)**, **hook-origin records that only the 10-min poller can drive (9%)**, **placer timeouts (8%)** and **HELD:busy (8%)**.
  - The CPU brake is only 3.9%, and only through a side effect explained in §4.2.
  - The capacity probe is 2.7%.
- **One reconciler pass took a median of about 8 minutes at load1 250-350.** It was 4.9-12.8 min across the 9 complete passes from 02:31 to 03:53. The daemon's designed gap between passes is 3 s (`__main__.py:57`, `ACTIVE_FAST_S`). Everything the reconciler does happens once per pass: detection, placement, admission, reaping an actuator's exit, retry. So each retry costs about one pass.
- **Corrections to the brief (measured):**
  1. The CPU brake did **not** refuse every pass. `admit-refused cpu` appears exactly twice (02:54:18 7aae55e1, 02:54:19 db755a94). It refused only the *second and later* member in a pass, because `decide()` is called with the pass's frozen `now`, so the 20 s anti-starvation floor reads `now - last_admit_at = 0` (§4.2).
  2. Admissions did happen while the probe was erroring. d7eb73d2 was admitted in the 02:46:14 pass and 7aae55e1 in the 02:54:50 pass, right after `probe-error` refusals. So the drip, or an occasional probe answer, did open. The event log cannot tell which, because refusals are only logged when their reason changes (`__main__.py:1222-1236`).
  3. The "sessions sat WAIT_DATA ~30 min" were the 2 **hook-origin, plan-only** records (3e929a81, 3d1d988a). The reconciler never places or drives these while `recon/autorecover.on` is absent (`__main__.py:1006`, `census.py:349`, `act.py:456`). It is absent: `ls ~/.reso/limit-recover/recon/autorecover.on` => No such file.
  4. **New blocker class, not in the brief:** a reconciler restart re-stamps every open record's move claim to the new pid (`__main__.py:1744`, `store.claim_restamp`). The actuator spawned by the *old* daemon then finds a "foreign" claim holder and refuses its own recycle **after** the transplant: `!! --recycle REFUSED: another actuator holds session e80b61f4's move claim (pid 47282, lr-reconciler)` (actlog e80b61f4.1.R.log), and the same with pid 38189 for 7aae55e1.2.R.log. That cost 2 attempts and 25.9 min.
  5. WAIT_RESET (fixed in 31f4242e0) cost **0 min** in this incident. None of the 7 reconciler records has WAIT_RESET in `close.seen`.

## 2. Load during the incident (measured)

The `load1` value from each `place` event in `events.jsonl`, for 10 cores:

| UTC | 02:36 | 02:43 | 02:53 | 03:06 | 03:14 | 03:20 | 03:34 | 03:41 | 03:49 | 03:55 | 03:59 | 04:08 | 04:11 | 04:12 | 04:13 | 04:15 | 04:18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| load1 | 253 | 300 | 329 | 347 | 294 | 259 | 257 | 158 | 176 | 192 | 203 | 363 | 263 | 144 | 120 | 102 | 84 |

The move workers' samples tell the same story (`move/*/<sid>.events.jsonl`): 32.8-34.2/core at 02:51, 36.2-38.0/core at 03:01, and 37.4-37.7/core at 03:06. From 04:11 on, load fell to 8.4-14/core, and every actuation in that window was much faster (§5). By the repo's own rule, *verify under the load that caused it*, the fast tail is a fact about lower load, not a cure.

## 3. Per-session reconstruction

`limit` is the timestamp of the limit record, from `close.death` in the record or `precheck limit: kind=limit at …` in the actlog. "Recovered" is the first engaged turn on the target account (handoffs.jsonl `recycle-engaged`).

### 3.1 d7eb73d2 (pane 853:32, reso-web-app) → next. Recovered.
- **Limit:** 02:32:26.023Z (`close.death`).
- **Detected:** pass now 02:31:55. **Planned:** 02:36:53, but the first placer call in pass P-1 timed out at 02:36:27 (`place … rc=124 cause=timeout n=3 dur=120.3s load1=253`). The P0 placer answered at 02:43:15 (`dur=88.2s`).
- **02:43:56:** `admit-refused probe-error`.
- **P1, now 02:46:14:**
  - Admitted, by drip or by a probe answer.
  - Its placer timed out again (02:53:20).
  - `jobs-recorded` at 02:54:13, then the spawn was written: **R pid 98869, 8 min after the pass started**.
- **Attempt 1, R:**
  - bundle 02:59:11 (5.0 min after spawn)
  - `placed` 03:03:59
  - focus/precheck 03:12:24, which was **8.4 min for the precheck**
  - **HELD:pane:resolver-unavailable** 03:12:29: `no terminal control socket answered at all` (d7eb73d2.1.R.log)
  - 18.3 min wall time, ending NOTMOVED rc 6.
- **The exit was reaped late:** `adopted exited` 03:13:16, `R rc=6 → RETRY/BACKOFF` 03:19:19. `next_eligible_at` 03:16:04.
- **No spawn in P4 or P5.** P5 was killed by the 03:23:17 restart.
- **P6, now 03:23:43:**
  - 7aae55e1 was evaluated first and refused `probe-error` at 03:35:33.
  - Then d7eb73d2 was admitted (`jobs-recorded` 03:36:00).
  - So the **spawn landed 12.3 min after the pass started**.
- **Attempt 2, R:**
  - bundle 03:36:48, placed 03:39:26, focus 03:42:48, gate 03:42:55 (token), recycle-armed 03:44:11
  - watcher: `recycle-intent` 03:46:24 (phases `gates@94s … intent@131s`), staged 03:47:55
  - watcher waited for the foreground's `exit-committed`: `commit … after 310s` (handoff-recycle-32 log)
  - SIGTERM 03:52:32, successor claimed 03:52:54, user record carrying the token 03:52:53, **recycle-engaged 03:53:31**
- **Limit to recovered: 81.1 min.** CLOSED 04:09:32 (`release`, `terminal.proof row5:token>=confirm_len`).

### 3.2 7aae55e1 (pane 853:38, personal) → next2. Relaunched, prompt NOT typed.
- **Limit:** 02:32:11.433Z.
- **Admission and placement:**
  - Same P-1 placer timeout and P0 plan as d7eb73d2.
  - `admit-refused probe-error` 02:44:27.
  - P1: `admit-refused cpu` at 02:54:18, because d7eb73d2 had taken that pass's admission.
- **P2, now 02:54:50:**
  - The census reached it at 03:00:57 (6.1 min into the pass).
  - The placer timed out at 03:06:30 (rc 124, 120.8 s, load1 347).
  - Then it was admitted, and the spawn was written between 03:06:30 and 03:08:24.
- **Attempt 1, R:**
  - bundle 03:12:57, placed 03:13:43
  - **HELD:composer-unreadable** 03:15:34 (7aae55e1.1.R.log: `precheck composer: unreadable`)
- **Exit reaped** `R rc=6 → BACKOFF/BACKOFF` 03:19:19.
- **After the 03:23 restart:** P6 refused `probe-error` at 03:35:33. P7 did not spawn it.
- **Attempt 2, R** (P8, now 03:43:17; written after its placer timeout at 03:49:05):
  - bundle 03:51:41, placed 03:52:34, focus 03:54:54 (OK), gate 03:54:55, recycle-armed 03:56:26
  - **03:58:56 HELD:unknown**: `!! --recycle REFUSED: another actuator holds session 7aae55e1's move claim (pid 38189, lr-reconciler)` (7aae55e1.2.R.log)
  - pid 38189 is the daemon that started at 03:53:16. lr-transplant `--phase abort` rc 0 withdrew the copy.
- **Exit reaped** 04:04:25. P13 refused `probe-error` at 04:08:51; 769b7294 took that pass's admission.
- **Attempt 3, R** (P14, now 04:09:35):
  - bundle 04:11:21, placed 04:11:40, focus 04:12:23, armed 04:13:08, staged 04:13:47, SIGTERM 04:14:27, claimed 04:14:37
  - **04:14:48 READY-NOT-SEEN, `screen reads UNKNOWN after 8s quiet — prompt NOT typed`**
  - `recycle-engaged` 04:15:16 (`a real assistant turn within 6s`), then `r-in-place … live in its own window 853:38 on next2 after R` at 04:16:49
  - The record is `RELAUNCHED/UNPROMPTED`.
- **Limit to relaunch: 103.1 min.** The continue prompt was still owed at 04:19.

### 3.3 db755a94 (pane 853:41, startup-hooks-impl) → next4. NOT recovered.
- **Limit:** a12f383a@02:31:39.017Z. A second limit record followed at 02:55:28.007Z (db755a94.1.R.log `kind=limit at 2026-10-20T02:55:28.007Z`), so the session was still being prompted on the capped account.
- **Admission:**
  - `admit-refused probe-error` 02:44:58.
  - `admit-refused cpu` 02:54:19 in P1, still standing in P2. It is not logged again because the reason did not change.
  - Admitted in P3 (now 03:08:24).
- **Attempt 1, R:**
  - bundle 03:16:06, placed 03:18:47, focus 03:20:03, gate 03:20:04, transplant done, recycle-armed 03:20:40
  - watcher `recycle-intent` 03:24:39 (phases `gates@69s kitty-probe@74s self-id@74s intent@239s`)
  - the watcher's pane probe failed: `listing rc=124 in 13s … pane-NO-ANSWER` (handoff-recycle-41-1792466679 log), then `recycle-held-unreachable` 03:28:11
  - lr-transplant `--phase abort` rc 0 at 03:32:51, NOTMOVED
- **Never re-driven:**
  - The record is left at `PRE-MOVE`, substate `None`, attempt 1.
  - `RECON-DEFECT PRE-MOVE/None` at 03:43:08, 03:51:29, 03:56:24 and 03:59:58.
  - `refire … by=cc-lr` at 04:06:15 produced no spawn up to 04:19.
  - This is the "post-transplant rollback" bug. Its fix 20368fc85 was committed at 04:12:50Z, after the running daemon started (03:53:16), so it was not loaded.
- **Open for 107.3 min** at the 04:19:00 cutoff.

### 3.4 769b7294 (pane 853:48, wt-cc-202108-60703, `root_shape=shell`) → next or next2. NOT recovered.
- **Limit:** 02:40:06.777Z. Record detected 02:46:14 (P1 now); `rebucket LIMITED` written 03:00:57 (P2).
- **Placement:**
  - P1 placer (n=2: this session and e80b61f4) timed out at 02:53:20.
  - P2 placer timed out at 03:06:30 (`kept=2 misses=2`).
  - Placed in P3 (planned 03:08:24).
- **Attempts:** 4 reconciler A attempts plus 2 hook-lane `lr-fleet --one` runs. **Every one that reached the precheck held on `HELD:busy`:**
  - The reason, from 769b7294.1.A.log: `precheck bg_work: unknown (limited, but a turn is in flight after the limit)`.
  - A #1: bundle 031606Z, verdict 03:20:21
  - A #2: spawn now 03:43:17, verdict 03:54:13
  - A #3: spawn now 04:00:02, verdict 04:11:04
  - A #4: spawn now 04:13:45, verdict 04:18:18
  - fleet one-031303Z: HELD:busy 03:18:36
  - fleet one-032012Z: PARKED, because the router did not answer: `rank.timing` shows `rc=3 wall_ms=29640` and then `rc=3 wall_ms=23782`. Its rank call only started at 03:30:06, 10 min after the dispatch at 03:20:12.
- **Two actuators ran on this session in the same second.** Bundle 031605Z came from lr-fleet and bundle 031606Z from the reconciler, a duplicate actuation. Both held, so there was no harm this time.
- **Open for 98.9 min** at 04:19:00.

### 3.5 e80b61f4 (pane 853:55, macapp-extract) → next. Relaunched, prompt NOT typed.
- **Limit:** f6345dff@02:45:03.203Z. A second limit followed at 02:53:04.772Z (e80b61f4.1.R.log).
- **Placement:** placer timeouts in P1 and P2 (same as 769b7294). Planned 03:08:24. `admit-refused restore-r (active 18 + in flight 4 + 1 vs R 22)` at 03:15:41 cost only 13 s, because the next pass started at 03:15:54.
- **Attempt 1, R** (now 03:15:54, written about 03:20:45):
  - bundle 03:20:51, placed 03:21:20
  - **focus 03:32:51: the precheck took 11.5 min**, and the kitty probe needed 2 tries: `the control socket /tmp/kitty-853 did not accept a connection: the probe's own 3s bound fired`
  - gate 03:32:52, recycle-armed 03:35:03
  - **03:38:22 HELD:unknown**: `--recycle REFUSED: another actuator holds session e80b61f4's move claim (pid 47282, lr-reconciler)`. That is the daemon started at 03:23:17.
- **After the attempt:** exit reaped 03:39:43 and 03:46:56. P8 refused `probe-error` at 03:51:07. P9 was killed by the 03:53:16 restart.
- **Attempt 2, R** (P10, now 03:53:21; `jobs-recorded` 03:56:14):
  - bundle 03:56:35, placed 03:57:12, focus 03:58:51, armed 03:59:01, staged 03:59:44
  - foreground `exit-committed after 213s`, SIGTERM 04:03:43
  - **04:04:07 READY-NOT-SEEN, prompt NOT typed**
  - successor claimed 04:04:48, `recycle-engaged … a real assistant turn within 0s` 04:06:14, `r-in-place` 04:10:29
  - The record is `RELAUNCHED/UNPROMPTED`.
- **Limit to relaunch: 81.2 min.**

### 3.6 ceff45c5 (pane 24) and 9240c6a9 (pane 31). Idle, move lane → next2. Recovered.
- **Batch 1**, requested 02:48:13:
  - admitted 02:48:39, workers started 02:49:59
  - claim and fence took about 1 min (bash under load)
  - `load-wait` from 02:51:23 (ceff45c5) and 02:51:58 (9240c6a9): `load 33.83/core above the 20/core recycle bound; waiting up to 600s`
  - **NOTMOVED HELD:load** at 03:01:03 and 03:01:37: `load 38.02/core stayed above the 20/core recycle bound for 605s; nothing touched`
- **Batch 2**, requested 03:04:23:
  - `load-wait … waiting up to 3600s` from 03:06:35
  - the wait ended at 03:34:22-23, after **27.8 min**. Load dipped under 20/core; the 03:41 placer read load1 158.
- **Actuation:** actuated 03:35:28-33, bundle 03:36:43, placed 03:37:51-56, **focus 03:43:59 and 03:44:03 (6 min of precheck)**, armed 03:46:10-12.
- **Watcher:** `recycle-intent` 03:50:25 (`gates@172s … intent@252s`), staged 03:51:33-35, nudges at 60 and 150 s (`no exit-committed marker`), SIGTERM 03:54:27, claimed 03:55:11-15, **engaged 03:58:17-19**, MOVED 03:58:48-51.
- **Request to recovered: 70.1 min**, of which 37.6-38.2 min was load wait.

### 3.7 3e929a81 (pane 20) and 3d1d988a (pane 30). Idle, then limited while waiting. NOT recovered.
- Both were in batches 1 and 2 with the same HELD:load history as §3.6.
- **While batch 2 sat in `load-wait`, both hit the cap on next3:**
  - 3e929a81 at 03:13:21.361Z
  - 3d1d988a at 03:19:58.832Z
  - (`close.death`, and `requested_by: stop-failure-marker` in `requests/<sid>.json`)
- At 03:34:29-36 the workers finished `NOTMOVED: became-limited … Recover it: cc-lr recover <sid>`.
- **The reconciler created hook-origin records** (detected 03:15:54 and 03:23:43) with `plan_only: true`. They sit `WAIT_DATA` since 03:43:17. Because `recon/autorecover.on` is absent, the reconciler will never act on them. The cohort status still says `next_action: "the reconciler retries"` (`cohorts/next3-7d-1792497600.json`), which is misleading.
- **The hook lane (lr-reset-poller, StartInterval 600):**
  - At 03:20:04-08 the poller saw `RUN-CLAIM-HELD` (the batch-2 workers held the claims) and kept the requests "for re-check when it ends".
  - Its next tick that dispatched anything started at **04:10:17**. `poller.log` has `TICK start` only at 03:20:00 and 04:10:17 in this window. A tick runs much longer than its 600 s interval under this load (the 03:20 tick was still writing at 03:59).
  - 3e929a81: `lr-fleet --one` at 04:10:47, router `rc=3` twice (6.4 s, then 16.1 s), PARKED at 04:14:20.
  - 3d1d988a: `lr-fleet --one` at 04:10:36, rank 04:12:54 (31.6 s), bundle 04:13:52, gate 04:16:31, recycle-armed 04:17:43, then `!! recycle ABORTED: the terminal did not answer the watcher's pane probe for 30`, HELD:unreachable (results row 04:26:26).
- **Open for 90.8 min each** from the move request, and about 59-66 min from their own limit, at 04:19:00.

## 4. Mechanisms, with evidence

### 4.1 Pass cadence (the multiplier on everything)

I rebuilt the passes from three markers:
- **Pass start:** the `now` stamps (spawn rows, launch.log, record `detected`, `planned`, `busy_at`, `updated_at`).
- **Pass interior:** the `time.time()` rows inside each pass (rebind, rebucket, place, own, admit-refused, jobs-recorded).
- **Pass end:** `RECON-DEFECT`, which `_invariant` writes at the end of a pass.

| Pass | Start (now) | End (last row in pass) | Duration | Placer | Notes |
|---|---|---|---|---|---|
| P-1 | 02:31:55 | ~02:36:50 | **~4.9 min** | 120.3 s **timeout** (load 253) | detection of the first 3 |
| P0 | 02:36:53 | 02:44:58+ | **>=8.1 min** | 88.2 s answered | census row (rebind) at 02:40:42, **3.8 min after start**; 3 probe-errors 31 s apart (02:43:56, 02:44:27, 02:44:58) |
| P1 | 02:46:14 | 02:54:19+ | **>=8.1 min** | 120.2 s **timeout** | 1 admission (d7eb73d2), the rest refused `cpu` |
| P2 | 02:54:50 | 03:06:30+ | **>=11.7 min** | 120.8 s **timeout** (load 347) | census row (rebucket) at 03:00:57, **6.1 min after start** |
| P3 | 03:08:24 | 03:15:41 | **7.3 min** | 51.4 s | 2 spawns (db755a94 R, 769b7294 A) |
| P4 | 03:15:54 | ~03:20:46 | **4.9 min** | 56.8 s | e80b61f4 R |
| P5 | ~03:20:49 | killed ~03:23:17 | (lost) | | daemon restart 1 (34812 → 47282) |
| P6 | 03:23:43 | 03:36:31 | **12.8 min** | 106.0 s | 26 s from process start to first pass (lstart 03:23:17); 2 probe-errors |
| P7 | ~03:36:34 | 03:43:08 | **~6.6 min** | 85.2 s | no spawn |
| P8 | 03:43:17 | 03:51:29 | **8.2 min** | 120.3 s **timeout** | 2 spawns |
| P9 | ~03:51:32 | killed ~03:53:16 | (lost) | | daemon restart 2 (47282 → 38189) |
| P10 | 03:53:21 | 03:56:24 | 3.1 min | 42.2 s | |
| P11 | ~03:56:27 | 03:58:07 | 1.7 min | — | **abstained**: `ps degraded: … timed out at 40s` |
| P12 | ~03:58:10 | 03:59:58 | 1.8 min | 18.7 s | |
| P13 | 04:00:02 | ~04:09:33 | **9.5 min** | 120.1 s **timeout** (load 363) | |
| P14-P17 | 04:09:35 to 04:15:5x | | 1.1-2.1 min each | 21.7-75.7 s | load 102-144 |

- **Measured, 9 complete passes 02:31-03:53 at load1 253-347:** median about 8.1 min, range 4.9-12.8 min. The design gap between passes is 3 s.
- **Of 17 `place` calls, 6 hit their bound (rc 124).** Placer time inside passes, 02:31-04:19, was 1289 s, summed from the `dur=` fields in `events.jsonl` (python sum of the 17 `place` rows).
- **The observe/census phase alone took 3.8-6.1 min (P0, P2).** It is bounded per `ps` call at 40 s (`observe.py:84-100`). When `ps` times out, the whole pass abstains (P11).
- **The heartbeat measures steps, not passes:** `max_step_gap_s 120.06` at 04:08:17 is the placer step (`recon/heartbeat`). So the watchdog sees a healthy step cadence while a pass takes minutes.
- **Consequences, all measured:**
  - Detection and placement happen at least one pass after the limit.
  - A failed actuator's exit is **reaped about one pass late:**
    - d7eb73d2: exited 03:12:29, reaped 03:19:19
    - db755a94: exited 03:32:51, reaped 03:39:25
    - 7aae55e1: exited 03:58:56, reaped 04:04:25
  - A retry costs a full pass plus its actuation.

### 4.2 CPU brake: really a one-admission-per-pass limiter

- **The code:**
  - `_dispatch` passes the pass's `now` into `_admit` (`__main__.py:1220`).
  - `_admit` passes it into `Admission.decide` (`__main__.py:1114-1124`).
  - `decide` sets `self.last_admit_at = now` (`admit.py:287`).
  - `cpu_ok` allows a member when `load1/ncpu <= max(2.5, L_open)` or when `now - last_admit_at >= 20` (`admit.py:143-150`).
- **What that means:** inside one pass, after the first admission, `now - last_admit_at == 0`. Every later member is refused `cpu` whenever load is above the frozen `L_open`.
- **Measured:**
  - P1 admitted d7eb73d2, then refused 7aae55e1 (02:54:18) and db755a94 (02:54:19).
  - db755a94 stayed refused through P2, and was only admitted in P3.
  - Cost: 7aae55e1 8.6 min, db755a94 22.2 min.
- **The floor's design intent, "at least one admission per 20 s" (`admit.py:40`), became one per pass, about 8 min.** The drip has the same per-pass clock: `DRIP_EVERY_S = 30` is compared against the pass `now` (`admit.py:276-283`).
- **A restart resets all of `Admission`** (refusal run, drip clock, `L_open`), so the drip needs 3 fresh refusals again.

### 4.3 Capacity probe timeouts

- **The probe is a `bash -c 'source capacity-admit.sh; cc_capacity_probe …'` under a 30 s bound** (`admit.py:58-66`, `admit.py:182-199`).
- **The refusal rows sit about 30 s apart:**
  - 02:43:56 → 02:44:27 → 02:44:58
  - 03:35:33 → 03:36:00 (jobs-recorded) → 03:36:31
  - That spacing means the 30 s bound fired. This is an inference: until ed5614054 (03:59:15Z, "an admission refusal says whether the probe timed out or errored") the log did not say which.
- **Each refused probe costs 30 s of pass wall time and pushes that member to the next pass.**
- **`mint_token` is a second bash under the same 30 s bound** (`admit.py:204-222`).
- **Measured cost in this incident: 21.4 min (2.7%).**

### 4.4 Placer timeouts

- **The bound is `place_timeout = clamp(30 × load1/(4 × ncpu), 30, 120)`** (`plan.py:296-302`). At load1 >= 160 on 10 cores it is pinned at 120 s, and 6 of 17 calls still hit it.
- **A miss leaves the movers unplaced for that pass:**
  - 769b7294 and e80b61f4 each lost P1+P2: **22.2 min each**.
  - The first 3 sessions lost P-1.
- **The hook lane's router hit the same wall:** `claude-accounts: --max-wait expired mid-sweep; no answer (exit 3)`, which parked 769b7294 (03:32:28) and 3e929a81 (04:14:20).

### 4.5 Move lane HELD:load

- **The rule:** `lr-move-worker.sh:334-351` waits while `load1/ncpu > 20` (the precheck bound, `mw_load_bound`). The wait is 600 s by default, or up to `UNTIL` (3600 s for batch 2). Past the deadline it finishes NOTMOVED `HELD:load`.
- **Measured:** batch 1 (all 4 sessions) ended on HELD:load after 605-613 s, and batch 2 waited 27.7-28.2 min.
- **The asymmetry:**
  - The reconciler's lr-handoff precheck reads `precheck load: not gated (the relaunch is staged in the pane, keystroke-free)` (every actlog).
  - So the same kind of move ran through the reconciler lane at 25-37/core while the move lane refused it.
  - The two moves that eventually ran from the move lane (03:35-03:58) succeeded.
- **Biggest single class: 151.6 min (19.1%).**
- **Second-order cost:** it held 3e929a81 and 3d1d988a on the capped account long enough for both to become limited (03:13, 03:19). That moved them into a lane that took another 36 min to dispatch (§3.7).

### 4.6 Kitty unreachable

Three attempts were lost to a kitty control socket that did not answer:
- **d7eb73d2 #1:** the precheck found `REMOTE-PANE-RESOLVER-UNAVAILABLE`.
- **db755a94 #1:** the watcher's `it2 session list --json` gave `rc=124 in 13s`. This was after the transplant, so lr-transplant had to abort it.
- **3d1d988a (fleet):** the same watcher probe failure.

Notes:
- e80b61f4 #1 needed a second kitty probe (`3s bound fired … tries=2`), and its precheck took 11.5 min.
- Total: **44.5 min (5.6%)**.
- These holds are counted as retries ("a retry is safe"), but each retry costs a pass plus a full actuation (§4.1).

### 4.7 Composer / busy

- **Composer:** 7aae55e1 #1 held `HELD:composer-unreadable` (8.1 min). On the next attempt the composer read `empty`.
- **Busy:** 769b7294 held `HELD:busy` on all 6 attempts across 2 lanes. The reason, `bg_work: unknown (limited, but a turn is in flight after the limit)`, says its transcript has turns after the limit record.
  - Hypothesis, not checked against its transcript: something keeps prompting it. Its pane root is `zsh` and its root shape is `shell`. The repeated limit records on db755a94 and e80b61f4 show the same pattern.
  - This is the biggest single-session sink: **64.0 min**.

### 4.8 Reconciler bugs

- **Post-transplant rollback leaves PRE-MOVE/None (db755a94):** 46.1 min and still open. There are 4 `RECON-DEFECT` rows, and an operator `refire` at 04:06:15 did not bring it back.
- **WAIT_RESET** (31f4242e0): 0 min here, as noted in §1.

### 4.9 Reconciler restart → claim re-stamp → self-refusal (new)

- **The mechanism:**
  - `_startup` re-stamps every open record's claim with the new daemon's pid (`__main__.py:1739-1744`).
  - handoff-fire's `hf_recycle_claim_foreign` treats a live claim holder that is not this process or one of its ancestors as foreign (`handoff-fire.sh:2660-2680`), and refuses the recycle (`handoff-fire.sh:16259-16262`).
  - An actuator spawned by the dead daemon is no longer a descendant of the new one.
- **Measured hits:**
  - e80b61f4 #1: restart 03:23:17, refused 03:38:22 with pid 47282
  - 7aae55e1 #2: restart 03:53:16, refused 03:58:56 with pid 38189
  - Both had **already transplanted** and had to abort.
- **Cost: 25.9 min**, plus the 2 passes the restarts killed (P5, P9).
- **Hypothesis on cause:** the restarts came 10-11 min after lr_recon commits 31f4242e0 (03:13:29Z) and e6bbd0465 (03:41:57Z). No restart reason is on disk: the watchdog only logs `holder changed`, and `kills=` is empty.

### 4.10 Actuator wall time under load

- Every lr-handoff stage is bash and takes minutes at 25-37/core:
  - bundle → placed: 0.3-4.8 min
  - placed → focus (the precheck): 0.7-11.5 min
  - armed → watcher intent: 2.2-4.2 min (`phases intent@131-253s`)
- **The watcher then waits for the foreground's `exit-committed`** before the SIGTERM: 310 s (d7eb73d2), 213 s (e80b61f4), and about 174 s (ceff45c5 and 9240c6a9).
- **The same pipeline at load 12-14/core took 5.7 min end to end** (7aae55e1 #3).
- **lr-fleet startup was 2.3-10 min before its first router call** (fleet `rank.timing`).
- **Total, counting only successful or still-running attempts: 101.9 min (12.8%).** The time inside failed attempts is booked to the class that failed them.

## 5. Every attempt (12 reconciler spawns, 2 move-lane moves, 4 fleet runs)

| sid | # | lane/act | pass now | bundle | placed | focus | armed | outcome @ | outcome |
|---|---|---|---|---|---|---|---|---|---|
| d7eb73d2 | 1 | recon R | 02:46:14 | 02:59:11 | 03:03:59 | 03:12:24 | — | 03:12:29 | HELD:pane:resolver-unavailable |
| 7aae55e1 | 1 | recon R | 02:54:50 | 03:12:57 | 03:13:43 | 03:15:33 | — | 03:15:34 | HELD:composer-unreadable |
| db755a94 | 1 | recon R | 03:08:24 | 03:16:06 | 03:18:47 | 03:20:03 | 03:20:40 | 03:32:51 | HELD:unreachable (watcher, post-transplant abort) |
| 769b7294 | 1 | recon A | 03:08:24 | 03:16:06 | 03:18:38 | 03:20:20 | — | 03:20:21 | HELD:busy |
| 769b7294 | f1 | fleet | 03:13:03 | 03:16:05 | — | — | — | 03:18:36 | HELD:busy |
| e80b61f4 | 1 | recon R | 03:15:54 | 03:20:51 | 03:21:20 | 03:32:51 | 03:35:03 | 03:38:22 | HELD:unknown (claim re-stamped by restart) |
| 769b7294 | f2 | fleet | 03:20:12 | — | — | — | — | 03:32:28 | PARKED (router rc 3 ×2) |
| ceff45c5 | 1 | move | (actuate 03:35:28) | 03:36:43 | 03:37:56 | 03:43:59 | 03:46:12 | 03:58:19 | **MOVED, engaged** |
| 9240c6a9 | 1 | move | (actuate 03:35:33) | 03:36:43 | 03:37:51 | 03:44:03 | 03:46:10 | 03:58:17 | **MOVED, engaged** |
| d7eb73d2 | 2 | recon R | 03:23:43 | 03:36:48 | 03:39:26 | 03:42:48 | 03:44:11 | 03:53:31 | **ENGAGED** (prompt submitted 03:52:53) |
| 7aae55e1 | 2 | recon R | 03:43:17 | 03:51:41 | 03:52:34 | 03:54:54 | 03:56:26 | 03:58:56 | HELD:unknown (claim re-stamped by restart) |
| 769b7294 | 2 | recon A | 03:43:17 | 03:51:35 | 03:51:54 | 03:54:13 | — | 03:54:13 | HELD:busy |
| e80b61f4 | 2 | recon R | 03:53:21 | 03:56:35 | 03:57:12 | 03:58:51 | 03:59:01 | 04:06:14 | relaunched, **prompt NOT typed** (READY-NOT-SEEN 04:04:07) |
| 769b7294 | 3 | recon A | 04:00:02 | 04:09:35 | 04:09:49 | 04:11:04 | — | 04:11:04 | HELD:busy |
| 7aae55e1 | 3 | recon R | 04:09:35 | 04:11:21 | 04:11:40 | 04:12:23 | 04:13:08 | 04:15:16 | relaunched, **prompt NOT typed** (READY-NOT-SEEN 04:14:48) |
| 3d1d988a | f1 | fleet | 04:10:36 | 04:13:52 | — | 04:16:12 | 04:17:43 | 04:26:26 | HELD:unreachable (watcher) |
| 3e929a81 | f1 | fleet | 04:10:47 | — | — | — | — | 04:14:20 | PARKED (router rc 3 ×2) |
| 769b7294 | 4 | recon A | 04:13:45 | 04:16:08 | 04:16:24 | 04:18:15 | — | 04:18:18 | HELD:busy |

Tally (measured):
- 18 attempts.
- **3 delivered a working session** (d7eb73d2 #2, ceff45c5, 9240c6a9).
- 2 relaunched without their prompt.
- 13 failed:
  - 5 HELD:busy
  - 3 kitty
  - 2 restart-claim
  - 2 router PARKED
  - 1 composer
- Of the 13 failures, **3 happened after a transplant** and cost an abort (db755a94, e80b61f4 #1, 7aae55e1 #2).

## 6. Minutes lost per blocker class

Method:
- Each session's span (limit or move request → recovered, or → 04:19:00) is cut into back-to-back intervals, and each interval is given one class.
- The script that does the cutting and summing is `/tmp/f02/agg.py`, run with `python3 -I`. It checks that the intervals leave no gaps.
- Interval edges are measured timestamps from §3. The **class assignment is estimated**: it is a judgment about which blocker held the session in that interval.
- Time inside a *failed* actuation is booked to the class that failed it. "Pass cadence" is waiting for the next pass, or for the dispatch point inside the current one.

| Class | Minutes | Share |
|---|---|---|
| move HELD:load (lr-move-worker 20/core wait) | 151.6 | 19.1% |
| pass cadence (5-13 min passes, late reap, restart-killed passes) | 149.6 | 18.9% |
| actuator wall time under load (successful/ongoing attempts) | 101.9 | 12.8% |
| plan-only hook records / poller tick cadence | 72.4 | 9.1% |
| placer / router timeout | 64.6 | 8.1% |
| HELD:busy (769b7294) | 64.0 | 8.1% |
| reconciler bug PRE-MOVE/None (db755a94) | 46.1 | 5.8% |
| kitty unreachable | 44.5 | 5.6% |
| CPU brake (one admission per pass) | 30.8 | 3.9% |
| reconciler restart → claim self-refusal | 25.9 | 3.3% |
| capacity probe timeout | 21.4 | 2.7% |
| operator re-issue of the move batch | 12.4 | 1.6% |
| composer unreadable | 8.1 | 1.0% |
| **Total** | **793.3** | |

Per session (min): d7eb73d2 81.1 · 7aae55e1 103.1 · db755a94 107.3+ · 769b7294 98.9+ · e80b61f4 81.2 · ceff45c5 70.1 · 9240c6a9 70.1 · 3e929a81 90.8+ · 3d1d988a 90.8+ (+ = still open at 04:19:00).

Read-across (estimated):
- About 41% of the lost time comes from **things that are slow, not things that refuse**: pass cadence, actuator wall time and poller cadence together are 323.9 min.
- About 34% comes from **load-shaped gates and bounds**: move HELD:load, placer timeout, CPU brake and probe timeout are 268.4 min, and every one of them fires *because* the box is at 25-37/core.
- The remaining 25% is correctness defects and per-session holds (PRE-MOVE/None, restart claim, kitty, busy, composer: 188.6 min) plus the operator's re-issue of the move batch (12.4 min).
- Under the operator's premise (load never drops), the load-shaped gates never clear on their own.

## 7. Caveats

- `admit-refused` is logged only when its reason changes, so a refusal that repeated across passes shows up once. The "cpu brake" minutes for db755a94 in P2 are inferred from no change in reason plus no spawn.
- Whether P1/P2 admissions were drip or a probe answer cannot be told from disk.
- Pass ends are bracketed by the last row written in each pass. A pass that wrote nothing after its placer has an end that is a lower bound (marked `>=`).
- The recovered/not-recovered status is as of 04:19:00. 3d1d988a's fleet outcome (04:26:26) was read later and is included as a fact about that attempt.
- The two "engaged" watcher rows for e80b61f4 and 7aae55e1 contradict the bundle's `READY-NOT-SEEN … prompt NOT typed`. The record reads `RELAUNCHED/UNPROMPTED`. I did not resolve which turn the watcher saw.

## Skeptic review

An adversarial re-check, read at 2026-10-20 04:35-04:50Z. Nothing was written except this section: no pane, process, launchd job or credential was touched.

The doc's code citations match the tree that daemon 34812 ran, which was before 31f4242e0. Measured with `git show 31f4242e0~1:<file> | grep -n`:
- `place_timeout` is at line 296.
- `cpu_ok` is at 143.
- `claim_restamp` is at 1744.
- `decide(` is at 1114.

On main today these lines have moved to 312, 150, 1748 and 1118.

**Two facts that several verdicts below rely on (both measured):**
- **The load series.** `~/.claude/logs/convoy-gauge.jsonl` gives load1 at these times:

  | UTC | 02:46 | 03:00-03:10 | 03:34 | 03:36-03:53 | 03:59 | 04:01 | 04:05 | 04:08 | 04:11 | 04:16 | 04:18 | 04:22 |
  |---|---|---|---|---|---|---|---|---|---|---|---|---|
  | load1 | 340 | 372-377 | 212 | 140-182 | 198 | 247 | 370 | 359 | 156 | 97 | 87 | 159 |

- **The recovery daemons run demoted.**
  - `ps -o pid,pri -p 51148` (the reconciler, same plist as the incident daemons) => PRI 20.
  - Both lr-reset-poller pids => PRI 20.
  - `ps -A -o pri= | sort -n | uniq -c` => 697 processes at PRI 31.
  - The plist sets no `ProcessType` (`scripts/limit-recover/com.reso.lr-reconciler.plist`).
  - 51148 used `0:25.19` of CPU in `18:03` of elapsed time (`ps -o time,etime`). That is 2.3% of one core, at load 191-206.
  - `watchdog.log` rows from 10-19 show the same daemon design getting `CPU +1.87s over the last 196s (load 327…)`.
  - ed5614054's commit message measured the capacity probe by hand at 1.5-4.9 s, and at 18.3 s under `taskpolicy -c utility` at load 154.
  - The in-pane launcher, by contrast, runs at PRI 31. lr-fire-resume pids 2279 and 2538 are PRI 31, with a parent chain that runs up to kitty 853.
  - So "load" in this doc really means load multiplied by the daemon's demoted priority. This is a hypothesis with strong support: the incident-time pids are gone, so their PRI could not be read directly.

### Findings

| # | Verdict | Evidence |
|---|---|---|
| F1 "only 3 of 9 recovered; the brief's 5 overcounts" | **REFUTED** | (1) By this doc's own definition (§3: "Recovered is the first engaged turn on the target account, handoffs.jsonl `recycle-engaged`"), both count: e80b61f4 engaged 04:06:14 and 7aae55e1 engaged 04:15:16. (2) Their transcripts show real work. e80b61f4 on `~/.claude-next`: assistant turns from 04:04:16 ("This session was restarted on another account… Checking whether the sweep process survived"); it restarted its sweep at 04:04:32 and was still working at 04:34-04:35. 7aae55e1 on `~/.claude-secondary`: peer mail at 04:14:53, tool calls 04:15:10-48, then "✅ Good to close: yes. The ice-maker answer is committed" at 04:15:56. So 5 of 9 were working by 04:16, as the brief said. What stands: the prompt was literally not typed, the records still read RELAUNCHED/UNPROMPTED, and the 4 open sessions are correct. |
| F2 pass cadence about 8 min | **CONFIRMED** (two corrections) | Start-to-start times from the `now` stamps (02:36:53 → 02:46:14 → 02:54:50 → 03:08:24) make P0 9.4, P1 8.6 and P2 13.6 min. So the range is 4.9-13.6 and the median about 8.3; the doc's `>=` lower bounds understate it. `ACTIVE_FAST_S=3.0` is confirmed at `__main__.py:57`. Correction 1: an exit is *seen* within the same pass but *scored* in the next one (d7eb73d2 `adopted exited` 03:13:16 in P3, `R rc=6` 03:19:19 in P4). Correction 2: the cause is the demoted daemon at this load (see above), not load alone. `python3 -I /tmp/f02/agg.py` reproduces 149.6 min and a 793.3 min total. The class split is an estimate. |
| F3 the CPU brake is one admission per pass | **CONFIRMED** (one nuance) | The code matches. `L_open = max(load1,load5)/ncpu` is frozen at ACTIVE entry (`admit.py:128`), so the brake binds only while load stays above that entry level. P3 (03:08:24, 27-29/core) and P8 (03:43:17, 15-18/core) each admitted **two** first-turn actuators; `A` is in `FIRST_TURN` (`__main__.py:1051`). Each restart rebuilds `Admission()` and re-freezes `L_open`, so no `cpu` refusal appears after 02:54:19. |
| F4 admissions were granted while the probe errored | **CONFIRMED** (one refinement) | For P6 the log *can* answer the drip-or-probe question. After the 03:23:17 restart the refusal run starts at 0. Only one probe refusal (7aae55e1 at 03:35:33) came before d7eb73d2 was admitted (`jobs-recorded` 03:36:00, 27 s later). The drip needs `DRIP_AFTER = 3` (`admit.py:44`), so that admission was a real probe answer. Inside P6 the probe went timeout, answer, timeout. P1 cannot be decided: `page_due` is set at `admit.py:293`, but no code under `lr_recon/` reads it (grep), so the drip leaves no page trail. |
| F5 move-lane 20/core wait, 151.6 min | **CONFIRMED** | Batch events read `load 38.02/core … for 605s` (ceff45c5) and `37.56/core … 609s` (3e929a81), and batch 2 shows `waiting up to 3600s`. `handoff-fire.sh:13836-13837` prints `not gated` for a staged relaunch. Both idle sessions were capped by their own background-task notifications: 3e929a81 notification 03:13:18 → limit 03:13:21, and 3d1d988a 03:19:57 → 03:19:58. Minor: d7eb73d2.1.R.log has no `precheck load` line, because it parked at the resolver first. |
| F6 a restart re-stamps the claim, and the actuator refuses its own recycle | **CONFIRMED** | `__main__.py:1739-1744` → `store.py:369-379` stamp `runs/by-sid/<sid>.active` (`store.py:265-266`). That is the directory `hf_recycle_claim_foreign` reads (`handoff-fire.sh:2660-2680`). `grep -r 'move claim (pid' recon/actlogs` finds exactly these 2 hits. The interaction is new: the restamp has existed since b24e57ba8 (09-29) and the claim check landed in 467c9c45c (10-18). A third restart came at 04:31:18 (pid 51148, `restarts.jsonl`), 18.5 min after 20368fc85. Restart-after-fix-commit is now 3 for 3. |
| F7 plan-only hook records and the poller | **CONFIRMED** | `ls recon/autorecover.on` → No such file. The global `autorecover.on` exists (dated Sep 29). `poller.log` `TICK start` at 02:25:35, 03:20:00 and 04:10:17, gaps of 54.4 and 50.3 min. The 02:25 tick was still writing at 03:13 and the 03:20 tick at 03:59. The cohort file's `next_action` reads "the reconciler retries" for both. |
| F8 placer/router timeouts | **CONFIRMED** (corrections) | 17 `place` rows, dur sum 1289.2 s (re-summed). Of the 6 rc=124 rows, one is `dur=63.4s timeout=63s load1=84` (04:18:23): a 63 s bound at 8.4/core, not 120 s. After the window there were more misses: 04:20:39 at load1 89 (66 s bound) and 04:25:15 at 163. The placer misses even at 8-9/core because `plan.py:312-318` shrinks the bound with the instantaneous load1. That is counter-evidence to a load-only cause. Fleet `rank.timing` stamps are end times: try 2 is stamped 27 s after try 1, whose wall time was 29.6 s. So 769b7294's rank started at about 03:29:36, and fleet startup was 1.8-9.4 min, not 2.3-10. |
| F9 kitty, PRE-MOVE/None, HELD:busy, WAIT_RESET | **CONFIRMED** (cause of busy corrected) | The counts hold. **The HELD:busy is a false hold, and nothing was prompting 769b7294.** Its transcript has no turn after the 02:40:06 limit. Row 611 of 612 is an isMeta user record "A session-scoped Stop hook is now active…", timestamped **2026-10-19T15:15:16Z** and written *after* the limit, just before `turn_duration` (`durationMs 41116984`, the 11.4 h `/goal` turn). It is the only copy of that row in the file. `hf_transcript_at_rest` (`handoff-fire.sh:2978`) reads it as `user -` and returns rc 1, so `hf_bg_work_gate` holds HELD:busy (`:3226-3233`). It is not a `<task-notification>`, so `hf_dead_source_notification` cannot release it. The 6th attempt was still held at 04:46. Kitty: 3d1d988a's watcher probe failed at about 04:22, while load1 was 87-159 (8.7-16/core), so kitty silence is not only a high-load effect. PRE-MOVE/None is an old class: the first rows of `events.jsonl` (t=1791223695, 10-05) are already `RECON-DEFECT PRE-MOVE/None`. WAIT_RESET: 0 min is confirmed; it is absent from the `close.seen` of all 7 records. |
| F10 actuation takes 10-23 min under load | **CONFIRMED** | e80b61f4 #1 bundle: placed 03:21:20 → focus 03:32:51. Exit-committed waits: 310 s (pane 32), 213 s (55) and 172 s (24 and 31, which the doc gives as "about 174"); only 41 s for pane 38 at 10-12/core. The fleet startup correction is under F8. |

### Levers

| # | Verdict | Evidence |
|---|---|---|
| L1 admit on real elapsed time, or as a batch | **WEAKENED** | The mechanism is right, but `time.time()` alone still keeps a 20 s floor counted from the previous *decision*. In P1 the next decide came 5 s after `jobs-recorded` (02:54:13 → 02:54:18). A 2nd or 3rd member clears that floor only if probe plus mint take 20 s or more: a 30 s probe timeout does, but a fast answer (1.5-4.9 s by hand) may not. The drip's 30 s clock (`admit.py:289`) gates the same way. So "db755a94 ~22 min earlier" is an upper bound (estimated). The batch variant would work. Under a load that never drops, a brake keyed to the frozen L_open is arbitrary: it opened after every restart. Safety bounds hold: BootSlots floor 2, cap `LR_BOOT_MAX` 12 (`admit.py:306-318`), plus the pacer. The payoff is small: 30.8 min (estimated). |
| L2 move admission, placement and reaping out of the serial loop | **WEAKENED** | Pass time is subprocess time inside a PRI-20 daemon that gets about 2% of a core (measured above). Splitting the loop inside the same demoted process will not shrink the observe phase (3.8-6.1 min) or the placer (120 s bound). Two cheaper parts reach the same goal. First, actuators are direct children of the daemon (`ps` showed defunct pid 1293 with ppid 51148), so `waitpid`/SIGCHLD can reap a non-orphaned actuator without a ps pass. Second, un-demote the daemon: ed5614054 measured 1.5-4.9 s vs 18.3 s. The concurrency risk is real: there was already a duplicate actuation (bundles 031605Z and 031606Z on 769b7294). The 149.6 min is an estimate and would not all come back. |
| L3 do not re-stamp, or match the claim by record | **WEAKENED** | The diagnosis is confirmed. Option (a), no restamp, leaves a dead-pid holder, and the poller steals those: `poller.log` 03:20:12 `RUN-CLAIM-DEAD-HOLDER 769b7294 … verdict=stolen-dead-holder`, then a dispatch. That opens a window for a second driver. Option (b), match on record: the env carries `LR_RECORD_ID` and `LR_ATTEMPT` (`act.py:57-59`), and the claim stores `record_id` (`store.py:375-377`) but not the attempt. record_id is the same across attempts (every event row ends `a1`), so "record_id plus attempt" needs a schema change or the spawn nonce. A variant that fits today's data is to re-stamp the claim to the pid of the adopted live actuator, which is an ancestor of handoff-fire. Restarts follow fix deploys (3 for 3), so this recurs whenever a fix lands mid-incident. |
| L4 drop the move lane's 20/core wait | **CONFIRMED** | d4260ae3c (10-19 23:56Z) made the worker wait on the precheck bound "so it no longer walks into a final precheck HELD:load". Wave S, e2d0cee07 (10-20 00:09Z, 13 min later), made that precheck skip load for staged relaunches (`handoff-fire.sh:13826-13837`), and the move lane does stage (handoffs `staged` 03:51:33-35). So the wait now guards a gate that no longer fires. Safety evidence above 20/core in this incident is n=1: e80b61f4 #2 went staged 03:59:44 → SIGTERM 04:03:43 → engaged 04:06:14 while load1 went 198 → 247 → 370. Every other successful recycle finished at 10-20/core. F1's strand was the *typed* transport at 42-45/core (`load-hold-bound.md:24,74`). |
| L5 let the reconciler drive hook-origin cohort members | **CONFIRMED** (risk restated) | The global `autorecover.on` exists, so the poller lane already acts on these sessions with no human involved. The reconciler driving them changes which lane drives, not whether a human approves. The real risk is two drivers at once (the 03:20:12 poller dispatch of 769b7294 → duplicate bundles). A simpler variant: the worker's `became-limited` verdict already says `cc-lr recover <sid>`; doing that automatically sets origin to cc-lr (`census.py:349`). |
| L6 load and test the PRE-MOVE/None fix | **CONFIRMED** (post-window) | The 04:31:18 restart (pid 51148) loaded 20368fc85. Events: 04:31:53 `rolled-back … R rc=None → RETRY/BACKOFF`, then spawn `R pid=1293` (now 04:32:17). That attempt then ended `HELD:composer-unreadable` (db755a94.2.R.log, written 04:44Z). So the re-drive works, but the session was still open at 04:46. |

### Open questions: answers found

1. **What prompts capped sessions:** harness notifications, not a person. db755a94 got a `/goal` "Goal check-in" at 02:55:25. e80b61f4 got a goal check-in at 02:52:15 and a Monitor "expired" notice at 02:53:03. 769b7294 was not prompted at all; see F9.
2. **Which turn the watcher saw:** real turns triggered by notifications and peer mail that were queued up and delivered on relaunch (04:04:16 for e80b61f4, 04:15:09 for 7aae55e1).
3. **What caused the restarts:** still not on disk. All 3 restarts follow an lr_recon commit by 10-18.5 min.
4. **Drip or probe answer:** P6 was a probe answer (F4). P1 and P2 cannot be decided.
