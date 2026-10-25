# S06 — telemetry from disk: sizing the mid-turn move problem

Slot S06-telemetry-from-disk. Written 2026-10-25 ~07:20Z (02:20 CDT). Read-only: the only file written
outside `/tmp/mtam/S06/` is this one. Every number below is **measured** by the named command unless
labelled **estimated**. All scripts are in `/tmp/mtam/S06/` and are re-runnable with `python3 -I`.

## 0. Where the move lane writes (from source, not from prior reports)

| what | path | source |
|---|---|---|
| state root | `${LR_STATE_DIR:-$HOME/.reso/limit-recover}` | `bin/cc-lr:78`, `scripts/limit-recover/lr-move-lib.sh:23` |
| one batch | `<state>/move/<YYYYmmddTHHMMSSZ>-<from>-<to>-<pid>/` | `lr-move-lib.sh:24` (`lr_move_dir`) |
| plan (rows with `disposition`, `act`, `idle_s`) | `<batch>/plan.json` | `bin/cc-lr:1710` |
| per-session verdict | `<batch>/<sid>.json` `{verdict, reason, wall_s, ...}` | `lr-move-worker.sh:68-73` (`finish`) |
| per-stage telemetry | `<batch>/<sid>.events.jsonl` `{stage,t_ms,detail}` | `lr-move-lib.sh:463`, `lr-move-worker.sh:6` |
| shared idle census for waiters | `<batch>/snap.tsv` + `snap.ts`, one census per `LR_MOVE_SNAP_S` (default 20 s) | `lr-move-batch.sh:323-350` |
| batch summary line | `<batch>/batch.log` | `lr-move-batch.sh` |

Verdict vocabulary: `MOVED`, `MOVED-NEW-PANE`, `MOVED-UNREGISTERED`, `NOTMOVED`, `STRANDED`, `FAILED`
(`lr-move-lib.sh:111-119`). Disposition vocabulary comes from `cl_move_rows` (`bin/cc-lr:1284-1454`):
`move`, `wait:<busy-kind>`, `hold:<why>`. Busy kinds come from the census in
`lr-upgrade.sh:1082-1103`: `mid-turn` = `! lru_at_rest <transcript>`, where at-rest means the last
non-sidechain user/assistant record is a finished assistant turn (`lr-upgrade.sh:263-293`).
A `wait:*` row waits until the census calls it `move` on **two consecutive** snapshots, else it ends
`NOTMOVED still-busy:<kind> after <budget>s` (`lr-move-worker.sh:218-256`). `hold:*` rows are never
driven, so they get no `<sid>.json`.

The lane's first batch on disk is 2026-10-06 (count by day:
`ls ~/.reso/limit-recover/move | sed 's/T.*//' | sort | uniq -c` → 10-06:1, 10-10:3, 10-11:25, 10-13:4,
10-17:6, 10-18:38, 10-20:2, 10-24:3, 10-25:4; 86 batches + `requests/`). The predecessor lane's
records (`~/.reso/limit-recover/switch/`, 47 entries, 2026-09-27..10-04) use a different vocabulary
(SWITCHED/NOTMOVED) and are NOT counted here.

## 1. Outcome counts, all-time and last 7 days

Commands:
```
timeout 60 python3 -I /tmp/mtam/S06/agg_moves.py     # plan rows joined to <sid>.json verdicts
timeout 60 python3 -I /tmp/mtam/S06/reasons.py       # verdict x reason-class from <sid>.json only
timeout 60 python3 -I /tmp/mtam/S06/waitend.py       # wait-end events (budget exhausted) + successful waits
```
Run at 2026-10-25T07:10Z; the 7-day cut is batch timestamp >= 2026-10-18T07:10Z.

### 1a. Verdicts (result files `<sid>.json`, `reasons.py`)

| verdict | all-time (n=305) | last 7 d (n=92) |
|---|---|---|
| MOVED | 56 | 23 |
| NOTMOVED | 224 | 66 |
| FAILED | 13 (source-ambiguous 12, P2 environment 1) | 0 |
| STRANDED | 12 (`no live process holds the session`) | 3 |

(`agg_moves.py` counts FAILED 14 because one sid appears twice in a plan; the result-file count of 13
is authoritative.) Plan rows with no result: 228 `hold:*` all-time (46 in 7 d), 7 still waiting.

NOTMOVED by reason class, all-time / last 7 d:
`HELD:load` 35/20 · `still-busy:mid-turn` 21/19 · `still-busy:background-job` 21/10 ·
`still-busy:unread` 18/0 · `REFUSED` 17/0 · `aborted while waiting for idle` 17/3 · `slot-wait` 14/2 ·
`claim-held` 13/0 · `batch refused: target-unverified` 13/0 · `HELD:unreachable` 8/0 ·
`HELD:no-shell` 7/6 · `HELD:pane` 6/0 · `HELD:composer-unreadable` 5/0 · `HELD:exit-readback` 4/0 ·
`aborted before the move` 4/0 · `HELD:unknown` 3/1 · `still-busy:subagents-in-flight` 3/0 ·
`became-limited` 3/2 · `still-busy:composer-unknown` 2/2 · others 1 each.

### 1b. By plan disposition (the five named reasons), `agg_moves.py`

| disposition | all-time rows → outcome | last 7 d rows → outcome |
|---|---|---|
| wait:mid-turn | 35 → MOVED 2, NOTMOVED 30 (still-busy 22, aborted 5, HELD 2, REFUSED 1), waiting 3 | 23 → MOVED 1, NOTMOVED 19 (still-busy 17), waiting 3 |
| wait:background-job | 50 → MOVED 1, NOTMOVED 45 (still-busy 33, aborted 7, other 5), waiting 4 | 14 → MOVED 1, NOTMOVED 12 (still-busy 11), waiting 1 |
| wait:subagents-in-flight | 15 → NOTMOVED 15 (still-busy 8, aborted 4, claim-held 2, refused 1) | 1 → NOTMOVED 1 |
| hold:goal-live | 45 → never driven (no result) | 4 → never driven |
| wait:self | 4 → MOVED 2, NOTMOVED 2 | 4 → MOVED 2, NOTMOVED 2 |

All `wait:*` + `hold:goal-live` rows all-time: 149 rows, **5 MOVED (3.4%)**; excluding the 7 still
waiting, 5/142. For contrast, rows planned `move` (already idle): 199 → MOVED 49, NOTMOVED 125
(mostly HELD:load / slot-wait / refusals), FAILED 13, STRANDED 12.

Successful waits (`waitend.py`, seconds from `waiting` to `actuate`): 0e2799a9 wait:mid-turn 122 s;
f06b5e9b wait:self 213 s; 6f8d7bd2 wait:self 101 s; d7eb73d2 wait:background-job 887 s;
516b9da9 wait:mid-turn 3316 s.

Budget-exhausted waits with a `wait-end` event (the event is recent, so only 4 exist): 2a707a01
(2026-10-24, 3600 s, **151 snapshots, every one `mid-turn`**), and tonight 15f652bd and 502bd860
(1800 s, **56 snapshots each, every one `mid-turn`**), 88fc8283 (56 snapshots, started
`subagents-in-flight`, changed but never two consecutive `move`). 1800 s / 56 snapshots = one census
per ~32 s measured cadence (vs the 20 s nominal), so a session must be at rest for roughly 32-64 s
to be called `move` twice.

## 2. Tonight (from 2026-10-25T06:30Z = 01:30 CDT)

Four batches (`agg_moves.py` TONIGHT section; `batch.log`, `snap.tsv`, `events.jsonl` per batch):

**A. `20261025T063826Z-next-next3-20095`** (admitted 06:38:30Z, done 07:08:53Z: `MOVED=7 NOTMOVED=3 (NOTMOVED/still-busy=3)`)
- MOVED (idle at plan time, `move`): panes 2 79076bcf, 20 87a4411d, 47 85c040d1, 117 f27965bc, 262 1bede217, 272 3d1dc252 (wall 82-171 s).
- pane 307 0e2799a9 `wait:mid-turn` (idle_s 15) → MOVED after 122 s of waiting, wall 202 s.
- panes 217 15f652bd and 271 502bd860 `wait:mid-turn`, pane 301 88fc8283 `wait:subagents-in-flight` → NOTMOVED `still-busy:mid-turn after 1800s` (56 snapshots, never at rest twice).
- panes 216 2b3becea, 274 7396b781, 309 06457213 `hold:goal-live` → not driven.

**B. `20261025T065010Z-next-next4-1496`** (06:50:12Z; aborted 07:10:21Z): pane 314 30729231 (the requester)
`wait:self`, budget 3600 s → NOTMOVED `aborted while waiting for idle` after 1193 s; its snapshots read `mid-turn`.

**C. `20261025T065251Z-next-next4-13375`** (06:52:53Z, 5 workers; budget 1800 s → deadline ~07:22:53Z)
- panes 7 43e6eb4b and 67 794296f2 (`move`, idle_s 50009 / 49956) → MOVED (wall 76 / 81 s).
- panes 216 2b3becea `wait:mid-turn`, 274 7396b781 `wait:background-job`, 309 06457213 `wait:mid-turn` → still `(waiting)` at 07:18:19Z; latest snap (07:09:53Z) still `mid-turn`/`background-job`/`mid-turn`.
- panes 217, 271, 301, 314 `hold:in-flight` (batch A's / B's workers still held their claims) → not driven.

**D. `20261025T065455Z-next2-next4-76502`** (06:54:56Z, 1 worker; deadline ~07:24:56Z)
- pane 194 2a707a01 `wait:mid-turn` → still waiting at 07:18:19Z; snap 07:17:08Z `mid-turn`. Same sid exhausted a 3600 s wait yesterday with 151/151 `mid-turn`.
- pane 303 cf477fab `hold:goal-live`, pane 258 b172dd75 `hold:stale-row` → not driven.

Net tonight toward next4: **2 MOVED** (both idle 13.9 h), **0** of the 7 busy/goal sessions moved.

**Update after the deadlines** (one bounded wait on the result files, read 07:24:01Z and 07:24:58Z):
- C closed 07:23:14Z `done: MOVED=2 NOTMOVED=3 (NOTMOVED/still-busy=3)`: 309 06457213 and 216 2b3becea
  `still-busy:mid-turn after 1800s` (**57/57 snapshots `mid-turn`**, paged "unchanged for 1800s");
  274 7396b781 `still-busy:background-job after 1800s` (57 snapshots, first `background-job`, changed,
  never two consecutive `move`).
- D: 194 2a707a01 `still-busy:mid-turn after 1800s` (**67/67 snapshots `mid-turn`**, paged).
- Tonight's totals over all four batches: driven `wait:*` rows 9 → MOVED 1 (0e2799a9, after 122 s),
  NOTMOVED 8 (7 still-busy, 1 aborted); `hold:goal-live` rows 4, never driven; `move` rows 8 → MOVED 8.
  Exhausted waits tonight read 56-67 snapshots each; 5 of the 7 read `mid-turn` on every snapshot.

## 3. Idle-gap distribution and mid-turn fraction

### Method
1. Physical stores (realpath): `~/.claude/projects` (also `~/.claude-next/projects`, a symlink to it),
   `~/.claude-secondary/projects`, `~/.claude-tertiary/projects`, `~/.claude-quaternary/projects`
   (distinct directories). Command: `stat -f '%HT %Y'` + `os.path.realpath` per store.
2. Recent top-level transcripts (depth 2 only, so subagent sidechains are excluded), per store, in parallel:
   `timeout 60 find /Users/chrisren/.<store>/projects -mindepth 2 -maxdepth 2 -name '*.jsonl' -mmin -720 -exec stat -f '%m %z %N' {} + > /tmp/mtam/S06/recent-<store>.txt`
   → 38 + 6 + 16 + 33 = 93 files, all rc=0.
3. `timeout 60 python3 -I /tmp/mtam/S06/idlegap.py 20 /tmp/mtam/S06/recent-*.txt` (also run with 40).
   Turn end = non-sidechain assistant record with `message.stop_reason` in {end_turn, stop_sequence}
   (the same thing `lru_at_rest` keys on). Idle gap = from that record to the next non-sidechain
   user/assistant record. The record that ends the gap is classified: `human` (origin.kind=human,
   promptSource=typed, or `<bash-input>`), `task-notification`, `peer-message` (origin peer /
   "Another Claude session…"), `stop-hook` ("Stop hook feedback"), `goal`, `assistant-direct` (an
   assistant record with no user record between — a hook-forced continuation), `meta-other`.
   Mid-turn fraction = 1 - idle time / window, window = last 3 h (04:15Z-07:15Z) clipped to the
   transcript's first record, trailing idle counted up to now.
4. `timeout 60 python3 -I /tmp/mtam/S06/enders.py <20 files>` — what ends each gap, with gap seconds.
5. `timeout 60 python3 -I /tmp/mtam/S06/span.py <file…>` — first/last record and stop_reason census.
6. `timeout 60 python3 -I /tmp/mtam/S06/toolshare.py 20 /tmp/mtam/S06/recent-*.txt` — share of mid-turn spent inside tool execution.

### Results (20 most recently modified, run 07:15Z)
- Gaps n=268: **p10 0.0 s, p50 6.3 s, p90 1573 s** (all enders pooled).
- Automated-ended gaps n=258: p10 0.0, p50 5.6, p90 1487 s. Human-ended gaps **n=10 only**:
  p10 17.2, p25 70.9, p50 174, p75 533, p90 1714 s.
- What ended the 268 gaps: task-notification 78, assistant-direct 64, stop-hook 60, peer-message 52,
  human 10, goal 3, meta 1. **96% of turn restarts are automated, not the operator.**
- Fraction of gaps >= 40 s: 0.41 overall, 0.80 of human-ended.
- Wall-weighted over the 20 sessions, last 3 h incl. trailing idle (window 170,679 session-s):
  **mid-turn 0.668**, idle 0.332, idle inside gaps >= 40 s 0.330 (nearly all idle time sits in long gaps).
- Per session (mid-turn fraction, last 3 h): 11 of 20 are >= 0.998 (15f652bd, 2a707a01, ba56f290,
  28a7b735 have **zero** end_turn records in their whole transcript); the rest 0.05-0.92.
- Sessions stuck tonight: 15f652bd 336/336 assistant records `tool_use` since 2026-10-25T01:34Z
  (a /goal session — one turn for 5.7 h); 2a707a01 365/365 `tool_use` since 2026-10-24T06:08Z;
  502bd860 5 end_turns in 305; 2b3becea/06457213 1.0 mid-turn last 3 h; 7396b781 is only 0.10
  mid-turn by transcript — its block is a background job, not the turn.
- Operator typing mid-turn: queue-operation `remove` with reason `absorbed_mid_turn` is present in
  every sample transcript (1-74 each); most are task-notifications; human enqueues are a handful.
- Inside mid-turn time, tool execution (assistant tool_use → its tool_result) = **0.90** of
  tool+model time (**estimated**: crude, counts only the first of parallel tool calls); tool-exec
  durations n=1237 p50 3 s, p90 477 s, p99 596 s, max 5528 s. I.e. a "mid-turn" session is mostly
  sitting in a tool call with no API request in flight.
- 40-session run (includes sessions that ended, so it is biased toward idle): human-ended gaps
  n=104 p10 21 s, p50 245 s, p90 15,266 s; wall-weighted mid-turn 0.42.

### Reading against the standing constraint "idle never happens because the operator replies within seconds"
- The "never idle" half holds for the sessions that matter: 0 of 7 busy/goal sessions moved tonight;
  three 1800 s waits saw 56/56 `mid-turn` snapshots; 11/20 recent sessions are >= 99.8 % mid-turn.
- The "operator replies within seconds" mechanism does **not** hold in this sample: human-ended gaps
  have p50 174 s (n=10) / 245 s (n=104). The gaps that close in seconds are closed by task
  notifications, Stop-hook feedback, peer messages and /goal continuations; several sessions never
  end a turn at all. A design keyed on "catch the human pause" would fail for the same reason the
  lane does.
- Sampling bias: "20 most recently modified" selects active sessions; idle sessions (like the two
  that moved, idle 13.9 h) are under-represented.

## 4. Live sessions per account now

Commands (one process scan only; pid/lstart/comm, no argv, no env):
```
timeout 60 /bin/ps -ax -o pid=,lstart=,comm= > /tmp/mtam/S06/ps-once.txt   # 07:16:16Z, 2161 rows
timeout 60 python3 -I /tmp/mtam/S06/census.py   # joins ~/.claude/cc-registry/*.json (pid+lstart) with that snapshot
```
Registry `lstart` is UTC; `ps` lstart is local CDT; the join accepts either (+5 h).
Result: 40 claude/claude.exe processes; live registry rows by account:
**next 6, next2 2, next3 9, next4 19** (36 total) + 4 claude processes with no live registry row.
Stale registry rows (pid gone or reused): next 5, next2 2, next3 13, next4 1.
Still on next: panes 216, 217, 271, 274, 301, 309 (exactly tonight's unmoved busy/goal rows). On next2:
194 (2a707a01, waiting) and 303 (cf477fab, hold:goal-live).
Observation, not investigated: pane 314's registry row now names a different sid (58ec5fef, next4,
lstart 07:11:36Z) than the 30729231 requester whose wait:self was aborted at 07:10:21Z.
The recon `sessions/` files are recovery records (phase/terminal), not a live census, so they were
not used for this count; `recon/readout.line` at 07:15Z read "2 cohorts open · 0 moving · 4 waiting".

## Commands index (all wrapped in timeout <= 60)
- path discovery: `grep -ohE '(\$HOME|~|\$\{HOME\})/\.claude[...]' scripts/limit-recover/*.sh bin/cc-lr`; `grep -n 'STATE=\|lr_move_dir' bin/cc-lr scripts/limit-recover/lr-move-*.sh`
- `/tmp/mtam/S06/agg_moves.py`, `reasons.py`, `waitend.py` (section 1-2)
- `find … -mindepth 2 -maxdepth 2 -mmin -720` per store (section 3), `idlegap.py`, `enders.py`, `span.py`, `toolshare.py`, `peek.py`, `peek2.py`
- `ps` once + `census.py` (section 4)
