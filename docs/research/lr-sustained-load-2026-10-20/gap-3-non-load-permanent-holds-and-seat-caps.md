# Gap 3: holds that do not depend on load and have no bounded release, and seat caps

Read-only research, 2026-10-20, about 05:30-06:10Z. Nothing was typed, signalled, launched or mutated.

**Code base.** Line numbers are from `/Users/chrisren/Development/claude-infrastructure` at **HEAD `c82a349ce`**.
The brief named `58885750c`, but main moved during the run: `git reflog main` => `c82a349ce main@{2026-10-20 00:27:59 -0500}`, which is 05:27:59Z. Where the two commits differ, both are named.

**Labels.** M = measured (the command or script is named). E = estimated (the method is named). H = hypothesis, not verified.

**Helper scripts.** All are read-only and live under `/tmp/gap3/`:

| Script | What it does |
|---|---|
| `recs.py` | survey of the reconciler records |
| `evs.py` + `episodes.py` | hold episodes, from per-sid bundle and move-batch `events.jsonl` |
| `seats.py` | seat pressure, from `account-utilization.jsonl` |
| `peak.py`, `peak2.py` | post-move subagent concurrency |
| `prefix.py` + `test_rest.sh` | cut a transcript at a hold time, then replay the at-rest predicate at `58885750c` and at HEAD |
| `midturn.sh` | the same replay for the move lane's mid-turn rows |
| `nextprompt.py` | the first human prompt after a hold |

---

## 0. Answer

1. **The brief's premise "KMAX 8" is stale.**
   - `~/.claude/accounts.json` => `"KMAX": 24` (`accounts.json:46`), and `KMAX_RESIDENT` is 40.
   - It changed in `23ea68c5c` "chore(accounts): KMAX 8 -> 24, operator ruling 2026-10-04" (M, `git log -G KMAX -- accounts.json`).
   - The comment at `bin/claude-accounts:3967` describes the 2026-09-25 state.

2. **Under KMAX 24, the seat cap does not bind on measured concurrency.**
   - Over 1,409 sweeps since 10-04 with a measured `k_work`, no sweep had every uncapped account short of 19 free seats, let alone 1 (M, `seats.py`).
   - The seat cap stops being a rate limit and becomes three **structural** defects in the mover's *weight*:
     - **(a) A weight above KMAX can never be placed.** `bin/claude-accounts:6621` checks `cap[a] - placed_w[a] < w`, and `cap ≤ KMAX` (`:6566`). This hit 5 movers since 10-01 (weights 11, 11, 18 at KMAX 8; 35 and 65 at KMAX 24). All 5 were rescued by *another* recovery path.
     - **(b) The weight counts subagent transcripts written AFTER the death.** `plan._fresh` (`plan.py:86-88`) tests `death - mtime <= 600` and has no lower bound. Examples: 7046d8d0 got w=65 = 1 + 59 + 5 post-death files, and 5507881f got w=20 against 8 in-window files (M).
     - **(c) The label hides the cause.** `kmax-concurrency` is printed for "the mover is heavier than this account's free seats" (`:6567`, `:6622`). Every seat refusal also leaves no event: `grep -c kmax-concurrency recon/events.jsonl` => 0, and `grep -c WAIT_SLOT` => 0 (M).

3. **mover_weight overcharges at the tail, but the premise "a resumed lead restarts none" is wrong.**
   - Of the 18 weighted movers that engaged since 10-01, 12 peaked at ≥5 concurrent subagents within 60 min of engagement. **The peak never exceeded 12** (M, `peak2.py`).
   - db755a94 (w=19) relaunched a 12-agent Workflow **1 s after engagement** (05:17:14Z). It did so because the handoff prompt told it "18 waiting agent(s)" (M, transcript).
   - Its real cost was 13 seats (lead + 12), not 19. 7046d8d0 (w=65) peaked at 10, and 00b363d4 (w=35) at 12.

4. **HELD:busy on a limited session was false in every measured case: 4 episodes and 16 held runs since 10-01.**
   - On a limited session, the transcript's newest record was 135 s to 4 h old at the hold. A turn on a rejected account ends in a limit error within about 4 s (`handoff-fire.sh:3160-3163`).
   - 14 of the 16 runs are the replayed-goal shape. Replay of the same bytes: at `58885750c` the predicate says in flight (rc 1); at HEAD `c82a349ce` it says at rest (rc 0) (M, `test_rest.sh`).
   - Episode durations were 2, 139, 245 and 298 min: median about 192 min, max 298 min (M).
   - **The HEAD fix does not cover the reconciler's own copy, `lr_recon/transcript.py:264-281`.** That copy still has none of the skip rules.

5. **HOLD-COMPOSER is a catch-all with no page.**
   - It is absent from `T.MAX_AGE_S` (`types.py:117-129`), so `report.max_age_deadline` returns None (`report.py:190-191`).
   - Its age clock restarts every 120 s re-probe cycle (`settle.py:333-342` + `:412-424`).
   - Every held-after-confirm reason that is not in `RCY_HELD_SUB` maps to it (`settle.py:486`).
   - Of the 18 `HOLD-COMPOSER` transitions in `events.jsonl`, **0 were a composer condition**: 12 were HELD:busy and 6 were `HELD:load` after the confirm (M, actlogs).

6. **`plan_only` is a real permanent hold, but only for census-origin limited sessions.**
   - `recon/autorecover.on` is absent (M, `ls ~/.reso/limit-recover/recon/`).
   - Hook-origin plan-only limited records are rescued by the poller lane: 29 were moved by another path, median 13 min.
   - The 9 census-origin limited records had no other owner. 6 of them waited until they were answered in place at the reset: median 357 min, max 3,695 min (M, `recs.py`).

7. **The remaining classes are rare or empty.**
   - **HELD:team:** 0 real holds since 10-01. The one `REROUTE-SKIP held:team` came 65 min after that session had already moved.
   - **IMPOSSIBLE after REARM_CAP:** 1 (762a6daa, 10-04).
   - **HELD:draft:** 4 lr-handoff episodes (median 129 min, max 482 min), plus one poller episode of 6 h 00 m. In none of them does a later human prompt show the draft was real; indeterminate, not proven false.

---

## 1. Q1: the holds that are not load-keyed and have no bounded release

"Bounded release" means the hold ends by itself within a known time *and* the session then proceeds. A page is not a release.

### 1.1 Reconciler (`scripts/limit-recover/lr_recon/`)

| # | Hold | Where | How it ends | Pages? | Bounded? |
|---|---|---|---|---|---|
| R1 | **HOLD-COMPOSER** (`busy`, `unknown`, `unreachable`, and every unlisted held-after-confirm reason) | `classify.py:139-140` (`busy`/`unknown`); `settle.py:65-74` (`RCY_HELD_SUB`), `:108-112` (`_hold_substate` default), `:483-486` (`_held_after_confirm` default `"HOLD-COMPOSER"`); REPROBED `settle.py:60`, `REPROBE_S=120` `:28`, `reprobe` `:412-424`; `_hold` `:333-342` | The precheck stops saying busy, or the source resets (`settle.cohort_exit`) | **Never.** Not in `MAX_AGE_S` (`types.py:117-129`), so `report.py:190-191` returns None | **No** |
| R2 | **HOLD-DRAFT** (census) | `census.py:236-241` (limited), `:295-296` (idle); actuator path `classify.py:141-142` | The composer reads empty (`observe.composer_from_screen`, `observe.py:400-423`, has no junk classifier and no staleness test) | Max age 900 s (`types.py:121`), then hourly | **No.** There is no draft carry on this path: `LRH_CARRY_DRAFT` is set only by `lr-move-worker.sh:464`, and `lr-handoff.sh:1486` honours it only `--in-place` |
| R3 | **HELD:team** | `census.py:204-210`; `act.py:466-468` (`team-live`); `settle.py:55-58` (`TEAM_ABSORBS`, `TEAM_EXIT_PASSES=2`) | The members exit, or the source resets and the lead is continued in place (decision 4) | 600 s *after the reset* (`types.py:128`, `report.py:196-197`) | Only by the reset, which for a weekly cap is up to 7 days away |
| R4 | **HOLD-BGWORK** | `census.py:227-234` | The job ends. Since 10-13 a job on a server-rejected account does not hold unless it is ship-land (`census.py:254-268` `source_rejected`) | 1200 s, or 3600 s for ship-land (`types.py:123,130`) | By job end only. Ship-land ends by itself; any other job on a non-rejected account does not |
| R5 | **WAIT_SLOT `kmax-concurrency`** | weight `plan.py:153-156` (+ `_fresh` `:86-88`, `movers` `:227`); placer `bin/claude-accounts:6566-6567`, `:6621-6623`; state `plan.py:411`; phantom `plan.py:446` | Free seats ≥ weight on some account. **Never** when weight > KMAX | At `eta + 600` (`report.py:196-197`). `eta` is the nearest fact reset among the zeroing accounts (`claude-accounts:6640-6646`), so hours (db755a94: 25,661 s) | **No** when w > KMAX; otherwise only while seats free |
| R6 | WAIT_SLOT `k-unmeasured` (adjacent, load-correlated) | `claude-accounts:6555-6558` (cap 0 on every account when the reconciler's `kwork` is None); `plan.py:138-150` (None for every account whenever `ps` or `registry` is degraded) | The next undegraded census | Same as R5 | No, while `ps` keeps timing out (30 `abstain ps degraded` events since 10-07, M) |
| R7 | **plan_only** (daemon-origin record without `recon/autorecover.on`) | `census.py:345-349` (`merge_origin`); `__main__.py:218-223` (`zero_human`); `act.py:456-457` (`plan-only` refusal); `__main__.py:1020`, `:1041` | Another lane acts (hook requests via the poller), a cc-lr request promotes it, or the source resets | No page for plan-only as such | **No** for census-origin limited sessions, which have no other owner |
| R8 | **IMPOSSIBLE after REARM_CAP** | `classify.py:21-26`, `:189-212`; `__main__.py:756-771`; then `__main__.py:306-311` + `census.py:78-81` (`handled_death`) skip the sid for that death for good | "Released to the other recovery paths", but nothing hands it to one | Page (IMPOSSIBLE) | **No**: the reconciler never re-drives that death |
| R9 | HOLD:iterm, census IMPOSSIBLE (`no-transcript`, `cwd-gone`, `headless`) | `census.py:194-203` | Never automatically ("relaunch by hand") | At once | No (by design) |

### 1.2 lr-handoff / handoff-fire precheck (shared by reconciler A/R, poller fleet and move lane)

| # | Hold | Where | How it ends |
|---|---|---|---|
| P1 | **HELD:busy** (limited, "a turn is in flight after the limit") | `handoff-fire.sh:3234-3249` over `hf_transcript_at_rest` `:2978-3042`. Notification release `hf_dead_source_notification` `:3195-3222`, which covers only an all-`<task-notification>` tail | The predicate reads at rest. HEAD skips a replayed goal (`:2988-2995`, `:3017`) |
| P2 | HELD:mid-turn (voluntary) | `handoff-fire.sh:3250-3258` | Same predicate |
| P3 | HELD:draft | lr-handoff precheck; passed only with `LRH_CARRY_DRAFT=1 && --in-place` (`lr-handoff.sh:1480-1488`) | The composer is empty, or the move lane carries the draft |
| P4 | HELD:bg-work:ship-land, HELD:bg-work:other | `handoff-fire.sh:3260-3274` (rejected-source release `:3224-3233`) | The job ends |
| P5 | HELD:team | `hf_team_live` `handoff-fire.sh:3286+` | The members exit |

### 1.3 Reset poller (`lr-reset-poller.sh`)

| # | Hold | Where | How it ends |
|---|---|---|---|
| Q1 | NUDGE-HELD HELD:draft / focus | `lr-reset-poller.sh:1190-1196`, `:1211-1215`; paged once via `lrp_draft_hold` `:1130` (`~/.reso/limit-recover/draft-paged/`) | The composer empties. Re-tried every tick, no bound |
| Q2 | REROUTE-SKIP held:team | `lr-reset-poller.sh:2466` | The source reset |

### 1.4 Idle move lane (`lr-move-worker.sh`; voluntary moves, so the sessions are not capped)

| # | Hold | Where | How it ends |
|---|---|---|---|
| M1 | `still-busy:<mid-turn\|background-job\|unread\|subagents-in-flight\|composer-unknown>` | `lr-move-worker.sh:139-176` | Bounded *give-up* at `UNTIL` (3600 s), a page once if nothing changed (`:165-173`), and no successor owner |
| M2 | HELD:draft for a `[Pasted text #N]` | `lr-move-worker.sh:290-292` | Never (its content cannot be carried) |
| M3 | HELD:no-shell (launcher-rooted pane, `--no-replace`) | `lr-handoff.sh:1496-1503`, passed by `lr-move-worker.sh:467` | Never. Paged once per pane (operator ruled the hold stays) |
| M4 | `became-limited` | `lr-move-worker.sh:200` | Hands to a human: "Recover it: cc-lr recover" |

---

## 2. Q2: counts, durations and false holds since 10-01

**Data sources.**

| Source | Range |
|---|---|
| `recon/sessions/*.json` | 130 records detected ≥ 10-01 |
| per-sid `~/.reso/limit-recover/<sid>/bundle-*/events.jsonl` and `move/*/<sid>.events.jsonl` | 4,151 lines, 180 sids, 09-20 to 10-20 |
| `move/*/<sid>.json` | 41 MOVED since 10-01 |
| `recon/events.jsonl{,.1}` | 09-30 to 10-20 |
| `recon/actlogs/` | 7-day retention, 50 logs |
| `poller.log` | |

**Episode rule** (`episodes.py`).
- A run's verdict is its `HELD:<x>` precheck or recycle state.
- An episode starts at the first held run and ends at the first later run of the same sid that armed or typed a relaunch.
- If no such run follows, the episode is "censored" at its last held run.

### 2.1 HELD:busy (limited sessions)

M, `episodes.py -v`, `prefix.py` + `test_rest.sh`.

| sid | held runs | first hold → end | duration | newest-record age at hold | replay `58885750c` → HEAD | shape |
|---|---|---|---|---|---|---|
| 1aa4e1c1 | 1 | 10-02 01:53Z → answered in place 01:55Z | ~2 min | 135 s | 1 → 0 | replayed goal (isMeta, ts 00:49:39 after the 01:51:12 limit) |
| 14233392 | 2 | 10-13 01:48Z → armed 05:53Z | 245 min | 142 s | 0 → 0* | `<task-notification>` after limit (fixed 10-13) |
| c23e89f1 | 5 | 10-18 07:43Z → in place after reset 12:41Z | 298 min | 58 min to 4.0 h | 1 → 0 | replayed goal (ts 06:22:22 after the 06:46:06 limit) |
| 769b7294 | 8 | 10-20 03:18Z → confirmed 05:37:09Z | 139 min (limit → confirm 177 min) | 38 min to 2.6 h | 1 → 0 | replayed goal (ts 2026-10-19T15:15:16 after the 02:40:06 limit) |

\* The jq at-rest test computes the stale-notification age against the *current* clock, so a replay cannot reproduce 14233392's hold-time verdict. At the hold, the notification was 142 s old, which is under the 600 s window, so it read in flight.

**Count.** 4 episodes and 16 held runs. Median duration about 192 min (E, the midpoint of 139 and 245), max 298 min (M).

**False holds.**
- **16 of 16 runs** fail the physics test. On a session whose last assistant record is the limit error, no turn can stay in flight for minutes: any prompt gets the 429 back within ~4 s (`handoff-fire.sh:3160-3163`, "its reply lands 3.5-4.0 s later"). The newest record was 135 s to 4 h old at every hold (M).
- **14 of 16** (1aa4e1c1, c23e89f1, 769b7294) are cleared on the same bytes by HEAD's replayed-goal skip (M).

**What actually released them.**
- 769b7294's attempt 8 started at 05:25:20Z. Its precheck read `bg_work: none` after `c82a349ce` reached the live checkout at 05:27:59Z (M: `recon/actlogs/769b7294.8.A.log`, `git reflog main`). It was confirmed at 05:37:09Z.
- Attempt 7, at 05:15:55-05:17:07Z, still read HELD:busy (M). The commit's *author* time of 05:00:33Z is not when it went live.

**Not covered by the HEAD fix.** The reconciler's own predicate `lr_recon/transcript.py:264-281` (`_at_rest`) skips nothing: no goal replay, no local-command triple, no block-cap, no stale notification (M, read).
- It gates idle fan-out eligibility (`census.py:282-292`), which is off by default (`LR_IDLE_FANOUT`). Limited movers do not use it.
- A third copy of the rule set is a drift risk (H).

### 2.2 HOLD-COMPOSER (reconciler)

M, `grep HOLD-COMPOSER recon/events.jsonl` => 18 transitions in 7 sessions, 10-13 to 10-20. Joined to `recon/actlogs/<sid>.<n>.<A|R>.log`.

| Underlying verdict | transitions | sessions |
|---|---|---|
| HELD:busy (precheck) | 12 | 14233392 ×1, c23e89f1 ×5, 769b7294 ×6 |
| `recycle ABORTED before /exit (held: load) … unconfirm rc 0` → `RCY_HELD_SUB.get("load", "HOLD-COMPOSER")` (`settle.py:486`) | 6 | 6069b9d3, 2ee922eb ×3, 5759497b, 3e929a81 (load 9.9-29.1/core against the 8/core bound) |
| a composer condition | **0** | |

- **False:** 18/18 by label, because none was about the composer. 12/18 were the false busy of §2.1.
- **Age.** The hold age never accumulates: `_hold` keeps `since` only when `rec.wait.reason == sub`, but `reprobe` sets `wait=None` (`settle.py:422`) and the next placement sets `wait=None` (`plan.py:390`).
- **Cycles.** 769b7294 cycled 6 times between 03:23 and 05:17Z with no page (M, events).

### 2.3 HELD:draft

**lr-handoff precheck:** 4 episodes (M, `episodes.py`).

| sid | span | duration | held runs |
|---|---|---|---|
| 492a787a | 10-01 21:17 → 23:31Z | 134 min | 2 |
| 762a6daa | 10-04 09:08 → 17:10Z | 482 min | 2 |
| c56c729c | 10-11 16:59 → 19:04Z | 125 min | 1 |
| 1bf14662 | 10-18 01:58Z | censored | 1 |

Median 129 min, max 482 min.

**Poller:** 762a6daa logged 56 `NUDGE-HELD … HELD:draft` lines from 09:48:39Z to 15:48:56Z on 10-04 (6 h 00 m). Operator HID idle at those reads was 7,089-9,756 s and more, so nobody was at the keyboard (M, `poller.log`).

**Move lane:** 2 `HELD:draft` rows (wall 1,372 s) and 4 `draft-carry` events. The lane carries drafts; all 4 carries were for 98e6f890 (5 chars) (M).

**Reconciler census HOLD-DRAFT:** 0 records since 10-01 (M, `recs.py`).

**False?** Indeterminate. `nextprompt.py` finds no human prompt after the hold that could be the draft being sent:
- 762a6daa: the next user record is a machine-typed `[operator-ruling cc-lr-switch …]` at 15:53Z.
- 492a787a and 1bf14662: none.
- c56c729c: 13 h later.

So the drafts were never submitted from that box, but whether they were real text cannot be shown afterwards.

### 2.4 HELD:team

- Reconciler: 0 records with `HELD:team` in `close.seen` (M, `recs.py`).
- lr-handoff: 0 `HELD:team` verdicts (M, `grep -rho HELD:team` over bundles, which matches only prose in salvage files).
- Poller: 1 `REROUTE-SKIP held:team` (6261c2ab, 10-17 08:12:17Z). That session had already been `REQUEST-RETIRED — transplanted` at 07:07:40Z, so it was not a real hold (M, `poller.log`).

### 2.5 WAIT_SLOT / kmax-concurrency

25 records since 10-01 have `WAIT_SLOT` in `close.seen` (M). Placement reasons are not persisted: `recon/plans/<cohort>.json` keeps only the last placement, and `place` events carry no per-sid reason. So a seat-cap hold is not separable from WAIT_SLOT caused by `recovery-weekly-thin` or `recovery-5h-thin`.

| Weight | records | detection → close |
|---|---|---|
| w = 1 | 11 | median 192 min, max 6,239 min (idle, plan-only) |
| w > 1 | 14 | median 20 min, max 394 min |

Detection → close is an upper bound on time in WAIT_SLOT.

**Structurally unplaceable** (w > KMAX at the time): 5 records.

| sid | weight | KMAX then | date | rescued by another path in |
|---|---|---|---|---|
| b671b47e | 18 | 8 | 10-04 | 11 min |
| ca3b517d | 11 | 8 | 10-04 | 11 min |
| 884aa5bc | 11 | 8 | 10-04 | 21 min |
| 00b363d4 | 35 | 24 | 10-11 | 13 min |
| 7046d8d0 | 65 | 24 | 10-13 | 19 min |

All 5 are "engaged on …, moved there by another recovery path" (M). The rescuing paths (poller/fleet `--account auto`) rank and do not charge weight.

**db755a94** (M, events + `account-assignments.jsonl`):
- It was placed on next4 at 02:43:25Z with `w=19`, so next4 then had ≥19 free.
- Its phantom was refreshed 15 times up to 05:17:09Z.
- After the 04:50:58 `R rc=6 → BACKOFF`, the placer answered at 04:53, 05:00 and 05:05 without placing it (lead obs #6: `kmax-concurrency`, eta 25,661 s). R was re-spawned at 05:06:50Z, and it engaged at 05:17:13Z.
- So the seat hold cost about 13 min (04:53 → 05:06).
- **H: the record's own phantom charged its re-placement.** The w=19 phantom on next4 was last written at 04:49:07Z with `ttl_s 1200`, so it was live to 05:09:07Z. `apply_assignments` (`claude-accounts:4512-4537`) has no self-exemption, so the mover's own 19 seats counted against its re-placement on next4. Not verified: the 05:06:50 R spawn reused the existing target without a fresh `--place`, so expiry of the phantom is not the only possible release.

### 2.6 plan_only

M, `recs.py`. 111 of 130 records since 10-01 are plan-only: 64 idle and 47 limited. `recon/autorecover.on` is absent; `~/.reso/limit-recover/autorecover.on` is present (ruling 2026-09-28).

| origin | fate | n | detection → close |
|---|---|---|---|
| hook | moved by another path | 29 | median 13 min, max 1,315 |
| hook | in place / reset | 8 | median 66, max 220 |
| hook | resume debt | 1 | 156 |
| **census** | **in place / reset** | **6** | **median 357, max 3,695** |
| census | moved by another path | 2 | median 38, max 66 |
| census | resume debt | 1 | 343 |

Census-origin limited sessions have no hook request and are never acted on. In 6 of 9 cases they waited out the limit, up to 2.6 days (46bc0436, 10-01 → 10-04).

**False?** By definition none was "busy". Each was a capped session that nothing moved.

### 2.7 IMPOSSIBLE after REARM_CAP, and escalations

M, `events.jsonl{,.1}`.
- `rearm-cap` since 10-01: **1**. 762a6daa had 4 re-arms from 10-04 22:06 to 22:51Z, then `rearm-cap` at 23:06Z. Its present record is a later one (`NOT_NEEDED dead-before-claim`).
- Other re-arms: b102f5af ×1 (10-18 08:03Z), 5759497b ×1 (10-18 13:16Z).
- This escalation is bounded in time (4 × 15 min). But the terminal IMPOSSIBLE then marks the death handled (`__main__.py:306-311`), so the reconciler never re-drives it. Nothing hands it to another lane.

### 2.8 Idle move lane (context: these sessions are not capped)

M, `move/*/<sid>.json` since 10-01: 41 MOVED against 61 `still-busy:*` give-ups (background-job 21, unread 18, mid-turn 17, subagents 3, composer-unknown 2), each after about 3,600 s. Also: 1 HELD:no-shell episode (9f6593c5, 7 runs, 660 min, censored), 3 `became-limited`, and 2 HELD:draft.

**Replay of the 18 mid-turn rows** (M, `midturn.sh`):
- 0 flipped between the old and HEAD predicates, so none were replayed goals.
- **d7eb73d2 and 7df606ba read "in flight" for 2.8-10.6 h.** Their tail is a Bash `tool_use` with no `tool_result` (d7eb73d2: a `git push` at 07:06:34Z, still unanswered at 17:51Z).
- That is a permission prompt or a hung tool. The transcript cannot tell which; only the screen can (H). By transcript the turn is "busy", but nothing is running.

---

## 3. Q3: seat caps under maximum concurrency

### 3.1 How often every uncapped account is at or above the cap

M, `seats.py` over `~/.claude/logs/account-utilization.jsonl` since 10-01 (4,079 sweeps).
- **Uncapped** = `auth=ok`, not stale, `session_pct<100`, `weekly_pct<100`.
- **free** = `KMAX - k_work`. Phantoms are not logged there, so free is an **upper bound**.
- This is claude-accounts' `k_work`; the reconciler passes its own `kwork` to `--place` (same rule per `plan.py:118-121`).

| era | sweeps | measured | k_work unmeasured fleet-wide | w=1 blocked | w=2 | w=5 | w=10 | w=19 |
|---|---|---|---|---|---|---|---|---|
| KMAX 8 (10-01 → 10-04 16:50Z) | 814 | 536 | 264 | 8 (1.5%) | 14 (2.6%) | 56 (10.4%) | 536 (100%, structural) | 536 (100%) |
| KMAX 24 (10-04 → 10-20) | 3,265 | 1,409 | **1,843 (56%)** | 0 | 0 | 0 | 0 | 0 |

`k_work` per uncapped account under KMAX 24: median 0, p90 3, max 21 (n = 5,401 account-rows).

**Reading.**
- Under KMAX 24 the cap has not bound a weight-1 or a weight-19 mover on any measured sweep.
- The binding seat failures are: weight > KMAX (structural); the mover's own phantom (H, §2.5); and **unmeasured** concurrency.
- During the incident, `k_work` was None on 104 of 108 account-rows from 02:26 to 05:33Z. Resident panes (`k_native`) were next 8-11, next2 14-17 and next4 2-3 (M).
- When the *reconciler's* census degrades, `--place` gives every account cap 0 (`k-unmeasured`, `claude-accounts:6555-6558`).

### 3.2 Does mover_weight overcharge?

**Method.** M, `peak2.py`: for each weighted record that engaged, peak concurrent subagent transcripts (first/last record timestamps) in the 60 min after engagement.

| sid | weight | peak after move | weight − (1+peak) |
|---|---|---|---|
| 7046d8d0 | 65 | 10 | +54 |
| 00b363d4 | 35 | 12 | +22 |
| 5507881f | 20 | 12 | +7 |
| db755a94 | 19 | 12 | +6 |
| b671b47e | 18 | 12 | +5 |
| 6069b9d3 | 16 | 8 | +7 |
| 5759497b | 13 | 4 | +8 |
| 3df4b1b4 | 12 | 2 | +9 |
| 14233392 | 12 | 11 | 0 |
| 884aa5bc | 11 | 10 | 0 |
| ca3b517d | 11 | 6 | +4 |
| e131c8d2 | 9 | 5 | +3 |
| 58d3640a | 6 | 8 | −3 |
| 1aa4e1c1 | 3 | 10 | −8 |
| others (4) | 4-6 | 1-2 | +1 to +4 |

**Findings.**
- **Resumed leads do restart fan-out.** 12 of 18 peaked at ≥5. The premise in lead obs #6, "restarts none of them on its own", is contradicted.
- **db755a94's restart was prompt-driven, not automatic.** At 05:16:36Z the handoff prompt said "The handoff audit found 0 gap(s) and 18 waiting agent(s)". The lead replied "Round 2 died … all 18 agents failed", then launched a Workflow at 05:17:14Z. 12 agents started at 05:17:14-15Z and 2 more at 05:25:41 and 05:27:35Z, with peak 12 concurrent (M, transcript `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-startup-hooks-impl/db755a94-….jsonl`).
- **Its added concurrency after 05:17Z was 13** (lead + 12), against a charge of 19.
- **The peak never exceeds 12** in 18 movers. H: a per-Workflow concurrency ceiling; not verified against Claude Code's source.
- **The weight undercharges** short-window fan-out that restarts larger (1aa4e1c1: w=3, peak 10).
- **Cause of the tail overcharge: the `_fresh` defect.** It has no lower bound, so files written after the death count:
  - 7046d8d0: 59 in-window + 5 post-death → 65.
  - 5507881f: 8 in-window, weight 20.
  - 00b363d4: 34 in-window, weight 35. The source store held 295 post-death files by now; the weight froze at the first placement because `rec.weight = p.weight or rec.weight`, `plan.py:379` (M, mtimes vs `timeline.detected`).

---

## 4. Q4: bounded escalations that never wait for load and never risk lost work

Each one uses a per-record clock that survives re-probes: `close.hold_since[<class>]`, set once and cleared only on a non-hold outcome. Call it `W_hard`.

### E1. HELD:busy (and HOLD-COMPOSER's busy half): replace the transcript shape test with physics

- **Rule.** A limited session (its last assistant record is the limit error, and the source fact is rejected and not contradicted) is **at rest** when the newest main-thread record is older than `T_quiet` (60 s; a reply lands in ~4 s).
- **Exception.** A trailing `<bash-input>` with no `<bash-stdout>`, which is a local `!` command that can really run.
- This subsumes three shape patches: the replayed goal (`c82a349ce`), the dead-source notification (10-13) and the block-cap. It would have released 16 of 16 runs since 10-01 at their first read (M, §2.1 ages ≥135 s).
- **Lost work:** none. Nothing can be running on a rejected account with no record in 60 s except the `!` case, which is excepted.
- Port the HEAD skip rules into `lr_recon/transcript.py:_at_rest` too.

### E2. HOLD-COMPOSER bookkeeping

- Map `load`, `exit-readback` and `unknown` explicitly in `RCY_HELD_SUB` (`settle.py:65-74`, `:486`) so the substate tells the truth. A load hold belongs to the deadline override of axis 05, not to a composer re-probe.
- Add HOLD-COMPOSER to `MAX_AGE_S` (for example 900 s).
- Make `_hold`'s `since` survive `reprobe` and `PLANNED`, by keeping it in `close.hold_since`.
- Effect: the 769b7294-class hold pages at 15 min instead of never.

### E3. HOLD-DRAFT on the limited path: carry, do not hold

- Reuse the move lane's draft gate on the reconciler and poller paths: `lr-move-worker.sh:254-296` plus `LRH_CARRY_DRAFT=1`. The gate runs: stale test (box unchanged 120 s, or HID idle ≥120 s) → junk classes cleared with read-back → real text carried unsent by `hf_rcy_carry`.
- **Lost work:** none for typed text, since it is retyped unsent.
- **`[Pasted text #N]`** cannot be carried. After `W_hard`, page with an operator-visible verdict naming the pane and the paste. Do not clear it.
- The poller's 6 h `NUDGE-HELD` loop (762a6daa) would have carried at the first read: HID idle was already ≥7,089 s.

### E4. Seat caps

1. **Fix `_fresh`.** Count only `death - 600 ≤ mtime ≤ death` (`plan.py:86-88`). This removes the post-death inflation: 65→60 and 20→9 (M, file mtimes).
2. **Clamp the weight.**
   - Use `w_eff = min(w, KMAX)` always, so no mover is structurally unplaceable.
   - After `W_hard` in WAIT_SLOT, use `w_eff = max(1, best target's free seats)`.
   - A resumed lead's fan-out is the lead's own choice, and the measured peak was ≤12 against KMAX 24.
   - Risk: transient overcommit on one account, which the target's own `k_work` corrects on the next pass.
3. **Exempt the mover's own phantom** on re-placement: pass its assign id to `--place` and skip that id in `assignment_counts` (`claude-accounts:4512-4537`).
4. **Name the cause and leave a trail.** Use `mover-heavier-than-free(w=19, best free=N on <acct>)` instead of `kmax-concurrency` (`:6567`). Write one `place-miss sid reason eta` event per unplaced mover.
5. **Soften the handoff prompt.** It should say "N agents were in flight; re-run only what is still needed", not a bare "18 waiting agent(s)", which invites a full relaunch (H, untested).

### E5. plan_only census-origin limited records

Either the operator creates `recon/autorecover.on` (D1.9 says it is the operator's to create), or a census-origin **limited** plan-only record past `W_hard` writes a hook-equivalent request for the poller lane, so that some lane owns it. The poller lane rescued hook-origin records with a median of 13 min (M).

### E6. IMPOSSIBLE after REARM_CAP

At rearm-cap, write a request for the poller or fleet lane and include the next step in the page. That turns "released" into "handed to a named owner". Optionally let a later cc-lr request re-open the death (H: today `handled_death` skips it, `__main__.py:306-311`).

### E7. HELD:team

Keep the hold (decision 4). At `W_hard`, rather than at reset+600 s, page an operator-visible verdict naming the members and the reset ETA, because a weekly reset can be days away. A cross-account team move remains v2.

### E8. A pending tool_use for hours (idle lane, d7eb73d2)

After `W_hard`, read the pane once:
- A permission dialog → page with the dialog text.
- A running process → leave it.

The transcript alone cannot decide this, so it should not be held as "mid-turn" forever.

---

## 5. Open questions

1. Does Claude Code cap concurrent Workflow agents at 12? This bears on capping `w_eff` at 1 + 12.
2. Was the 04:53-05:06Z WAIT_SLOT of db755a94 caused by its own live phantom? `--place` reasons are not logged, so only a reproduction with a fixture ledger can settle it.
3. What fraction of WAIT_SLOT records were seat-capped rather than `recovery-*-thin`? This needs per-sid placement reasons, which are not persisted (E4.4).
4. Are held drafts real operator text? A screen snapshot of the box at hold time (`close.draft_text` exists only on the HOLD-DRAFT census path) would settle it.
5. Is `T_quiet = 60 s` safe for `/compact` or other slash commands issued after a limit? They call the API and should fail as fast, but this is unmeasured.
