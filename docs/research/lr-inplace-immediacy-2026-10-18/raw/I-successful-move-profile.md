# I: where the time goes in a successful in-place move (actuate → MOVED)

Worker I, 2026-10-18. Read-only: no `cc-lr`, `lr-*.sh`, `handoff-fire.sh`, kitty or launchctl was run. Helpers are in `/tmp/lri-i/`
(`phases.py` builds the tables below, `tx_ts_window.py` reads transcript records, `glob_cost.sh` times one read-only glob).
**[m]** = measured (the source is named), **[e]** = estimated (the method is named). All times are UTC. File:line refers to this
worktree at `2a2d64a19`. The rows ran older code through the `~/.claude/scripts → ~/Development/claude-infrastructure` symlinks:
`handoff-fire.sh` at `a1434bb25` (Oct 6) and `7c5256c54` (Oct 10). Where an old line matters it is given as `oct6:NNNN`.

**Short answer.** In all 9 rows the verdict waits on the **resume-debt discharge**, not on the registry row. The watcher
discharges the debt only after a fixed 15 s "alive twice" hold, and its boot detector is slow to see claude. The registry row
was there ~20-70 s earlier **[e]**. Across the 9 rows the time goes to three blocks:
- the pre-/exit chain: median 78 s (range 14-102 s);
- /exit → relaunch spawn: median 35 s (20-149 s);
- spawn → debt discharged: median 35 s (24-75 s).

Even with every phase at its best measured value, the current design adds up to **~67 s [e]**. Getting under 60 s needs
structural removals (§4), not tuning.

The lead's "175-215 s" covers 8 of the 9 rows. 4d059264 took **118.4 s [m]** (actuate 16.1 + prove 102.2).

---

## 1. Per-row phase table

### 1a. Timestamps (UTC, `python3 -I /tmp/lri-i/phases.py`)

| row | actuate | bundle | placed | precheck done | admit done | hf intent | armed | debt open | SessionEnd | actuated | **spawn** | 1st record | hooks done | READY | **debt discharged** | proof-first | result |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 7f5deb68 | 06:07:07.9 | 06:08:16 | 06:08:18 | 06:08:28 | 06:08:29 | 06:08:37 | 06:08:41 | 06:08:50 | 06:08:54 | 06:08:55.7 | 06:09:16 | (06:09:17 SS) | - | 06:09:18 | 06:09:52 | 06:09:55.2 | 06:10:02.8 |
| 1c0f7f90 | 06:07:08.2 | 06:08:16 | 06:08:18 | 06:08:28 | 06:08:29 | 06:08:37 | 06:08:41 | 06:08:50 | 06:08:57 | 06:08:58.3 | 06:09:16 | 06:09:19.4 | - | 06:09:21 | 06:09:53 | 06:09:55.1 | 06:10:02.8 |
| 893204d3 | 06:07:08.6 | 06:08:16 | 06:08:18 | 06:08:28 | 06:08:30 | 06:08:37 | 06:08:41 | 06:08:50 | 06:08:53 | 06:08:53.8 | 06:09:25 | 06:09:28.9 | 06:09:32.6 | 06:09:30 | 06:09:53 | 06:09:55.2 | 06:10:02.8 |
| 840ca76c | 06:07:08.8 | 06:08:16 | 06:08:18 | 06:08:28 | 06:08:29 | 06:08:37 | 06:08:42 | 06:08:50 | 06:08:56 | 06:08:58.3 | 06:09:25 | 06:09:29.1 | 06:09:32.7 | 06:09:30 | 06:09:54 | 06:09:55.1 | 06:10:02.8 |
| 4d059264 | 06:09:55.6 | 06:09:56 | 06:09:57 | 06:10:02 | 06:10:03 | 06:10:05 | 06:10:07 | 06:10:10 | 06:10:12 | 06:10:11.7 | 06:10:30 | 06:10:32.3 | - | 06:10:34 | 06:11:45 | 06:11:46.3 | 06:11:54.0 |
| deaa242a | 06:09:55.7 | 06:09:56 | 06:09:57 | 06:10:02 | 06:10:03 | 06:10:05 | 06:10:07 | 06:10:10 | none¹ | 06:10:12.2 | 06:12:39 | 06:12:42.2 | 06:12:46.7 | 06:12:44 | 06:13:15 | 06:13:23.2 | 06:13:33.1 |
| 404651b1 | 06:09:55.7 | 06:09:56 | 06:09:57 | 06:10:02 | 06:10:03 | 06:10:05 | 06:10:07 | 06:10:10 | none¹ | 06:10:11.7 | 06:12:39 | 06:12:41.0 | 06:12:46.4 | 06:12:43 | 06:13:14 | 06:13:15.8 | 06:13:23.2 |
| bb1d86c8 | 05:32:44.0 | 05:32:45 | 05:32:48 | 05:33:06 | 05:33:10 | 05:33:23 | 05:33:34 | 05:34:02 | 05:34:10 | 05:34:09.7 | 05:34:51 | (05:34:54 SS) | - | - | 05:35:15 | 05:35:29.9 | 05:35:46.9 |
| c56c729c | 05:32:44.0 | 05:32:46 | 05:32:56 | 05:33:10 | 05:33:15 | 05:33:33 | 05:33:37 | 05:34:02 | none¹ | 05:34:09.8 | 05:35:06 | 05:35:10.0 | 05:35:11.7 | 05:35:13 | 05:35:33 | 05:35:46.9 | 05:36:01.0 |

¹ These rows had a background mailbox watcher (`precheck bg_work: watcher` in `<sid>.handoff.log`), so /exit raised the
background-work dialog. The old transcript shows the "Exit and stop tasks" answer landing as a `queue-operation`
task-notification at **06:10:29.2 / 06:10:40.5 / 05:34:15.7 [m]**: debt open +19 s, +30 s and +14 s. No SessionEnd line was
logged for these rows.

**Sources (every column measured):**

| column | source | code that writes it |
|---|---|---|
| actuate, actuated, proof-first, result | `<batch>/<sid>.events.jsonl` (ms) | — |
| bundle | bundle dir name `bundle-<TS>` | `lr-handoff.sh:1016` |
| placed, precheck done | bundle `events.jsonl` `placed/assign` and `admitted/gate` | `lr-handoff.sh:1529`, `:1492` |
| admit done | `stat` mtime of bundle `transplant.json` | — |
| hf intent | epoch in the watcher-log name `handoff-recycle-<pane>-<epoch>-*` taken from `<sid>.handoff.log` | `handoff-fire.sh:18482` `ts=$(date +%s)` right after `hf_phase intent` |
| armed | `<sid>.watcher.json` `armed_at` | `:18948` |
| debt open | resume-debt ledger `~/.claude/autonomy/resume-debt/*.jsonl` `kind:open`, provenance "about to type /exit" | `:18392` |
| SessionEnd | `~/.claude/logs/sessions.log` "Session ended … reason=prompt_input_exit", CDT converted to UTC | — |
| spawn | bundle `events.jsonl` `relaunch-typed`, i.e. the expect spawn of claude | `lr-fire-resume.sh:1212` |
| 1st record | target transcript's first record of the new process (`history-suppression restored_owner_mismatch` or `queue-operation`) | — |
| (SS) | where the transcript has no new record: `sessions.log` "Session started in <cwd>" | — |
| hooks done | last `hook_additional_context` attachment (sync SessionStart hooks finished) | — |
| READY | bundle `events.jsonl` | `lr-fire-resume.sh:1559` |
| debt discharged | resume-debt ledger `kind:return` "recycle engaged" | watcher, `handoff-fire.sh:12034` |

Other markers **[m]**:
- **Confirm tombstone** (`HANDOFF.json` mtime): 06:08:44 for wave 1 (3 s after armed) and 06:10:08 for deaa242a and 404651b1.
- **Old claude's last transcript write** (`.jsonl.handed-off` mtime, ≈ process exit or the watcher's stub fold): wave 1
  06:09:03-04, which is SessionEnd +6-11 s and spawn −13 to −21 s. Not available for the Oct-10 rows or 4d059264 (later
  moves overwrote them).
- **Load** (`qos-census.jsonl` loadavg1 on 10 cores, `sysctl hw.ncpu`): 160 = 16/core at 06:12:32 Oct 6, and 54.7 =
  5.5/core at 05:35:26 Oct 10.

### 1b. Durations (s) **[m]** (differences of the timestamps above; second resolution except the ms columns)

| phase | 7f5deb68 | 1c0f7f90 | 893204d3 | 840ca76c | 4d059264 | deaa242a | 404651b1 | bb1d86c8 | c56c729c | median |
|---|---|---|---|---|---|---|---|---|---|---|
| actuate → bundle (lr-handoff pre-bundle) | **68.1** | **67.8** | **67.5** | **67.2** | 0.4 | 0.3 | 0.3 | 1.0 | 2.0 | 1.0 |
| bundle → placed (lr-audit.py, git log, manifest) | 2 | 2 | 2 | 2 | 1 | 1 | 1 | 3 | 10 | 2 |
| placed → precheck done (`--probe-recycle-preconditions`) | 10 | 10 | 10 | 10 | 5 | 5 | 5 | 18 | 14 | 10 |
| precheck → transplant admit done | 1 | 1 | 2 | 1 | 1 | 1 | 1 | 4 | 5 | 1 |
| admit → hf intent (launcher mint, hf start, gates, kitty-probe, self-id) | 8 | 8 | 7 | 8 | 2 | 2 | 2 | 13 | 18 | 8 |
| intent → armed (tty, detach, heartbeat) | 4 | 4 | 4 | 5 | 2 | 2 | 2 | 11 | 4 | 4 |
| armed → debt open (composer gate, confirm, last read, wake/load gates) | 9 | 9 | 9 | 8 | 3 | 3 | 3 | 28 | 25 | 9 |
| **= actuate → debt open (pre-/exit chain)** | **102.1** | **101.8** | **101.5** | **101.2** | **14.4** | **14.3** | **14.3** | **78.0** | **78.0** | **78.0** |
| debt open → /exit landed (= worker `actuated`) | 5.7 | 8.3 | 3.8 | 8.3 | 1.7 | 2.2 | 1.7 | 7.7 | 7.8 | 5.7 |
| **debt open → relaunch spawn** (exit, watcher post-exit, launcher) | **26** | **26** | **35** | **35** | **20** | **149** | **149** | **49** | **64** | **35** |
| spawn → new claude's first record (boot) | (1 SS) | 3.4 | 3.9 | 4.1 | 2.3 | 3.2 | 2.0 | (3 SS) | 4.0 | 3.4 |
| first record → SessionStart sync hooks done | - | - | 3.7 | 3.6 | - | 4.5 | 5.4 | - | 1.7 | 3.7 |
| **spawn → debt discharged** (watcher boot detect + 15 s hold + rails) | **36** | **37** | **28** | **29** | **75** | **36** | **35** | **24** | **27** | **35** |
| discharge → proof-first (2 s poll + verdict compute) | 3.2 | 2.1 | 2.2 | 1.1 | 1.3 | 8.2 | 1.8 | 14.9 | 13.9 | 2.2 |
| proof-first → result (5 s stable + polls) | 7.6 | 7.7 | 7.6 | 7.7 | 7.6 | 10.0 | 7.5 | 17.0 | 14.2 | 7.7 |
| ACTUATE (actuate → actuated) | 107.8 | 110.0 | 105.2 | 109.5 | 16.1 | 16.5 | 16.0 | 85.7 | 85.9 | 85.9 |
| PROVE (actuated → result) | 67.1 | 64.5 | 69.0 | 64.5 | 102.2 | 200.9 | 191.5 | 97.2 | 111.2 | 97.2 |
| **TOTAL (actuate → result)** | **174.9** | **174.6** | **174.3** | **173.9** | **118.4** | **217.4** | **207.5** | **182.9** | **197.1** | **182.9** |

The ACTUATE/PROVE split hides the structure. `actuated` fires when lr-handoff returns just after /exit is read back
(`LR_INPLACE_AWAIT=0`). So "actuate" is the pre-/exit chain, and "prove" contains the whole exit, relaunch, boot and
engagement.

Not measurable, because the sources are gone:
- The watcher logs: TMPDIR keeps only epochs ≥ 1792045422 (Oct 14), checked with `ls $TMPDIR/handoff-recycle-*`.
- The `handoffs.jsonl` rows for these attempts (trimmed; 0 matches in `handoffs.jsonl` and in every archive found by
  `find / -name 'handoffs*.jsonl*'`).
- The registry rows (overwritten by later sessions in the same panes).

## 2. The three largest phases

### 2.1 The pre-/exit chain: actuate → debt open. Median 78 s, range 14-102 s [m]. Load-sensitive, plus one unexplained stall

What runs, in order:
- `lr-move-worker.sh:160-172` starts `lr-handoff.sh`.
- Before the bundle: argv, intent, transcript tail and tier reads, `git status` (`lr-handoff.sh:636-707`, `:912-1016`).
- `lr-audit.py` (`:1020`).
- `lrh_precheck`, which runs `handoff-fire --probe-recycle-preconditions` (`:1405`).
- `lr-transplant --phase admit` (`:1593`).
- The launcher mint, then `handoff-fire --recycle`: gates, kitty-probe, self-id (`handoff-fire.sh:15405-15435`), intent and
  tty (`:18481-18525`), detach, `await_armed` and `await_pane_proof` (`:18926-18975`, 0.2 s polls).
- `recycle_fire_commit` (`:18275-18440`): confirm (lr-transplant re-copy), last read, `hf_wake_guard`, load gate, debt open.

None of this is a fixed sleep: the only sleeps on the path are 0.2 s polls and the conditional wake guard. It is serial
process work, so it is load-sensitive. Wave 2 at 16/core did the whole chain in **14.3 s [m]**.

The outlier is wave 1's **68 s before the bundle [m]**. All four lr-handoffs stamped `bundle-20261006T060816Z` in the same
second, and the code before `lr-handoff.sh:1016` has no lock or sleep on this path. The git lock at `:868` applies only to
`pool/*` branches, and no "branch was" line was logged. Cause unidentified. A box-wide stall is consistent with the evidence
**[e]** (7 workers spawned at 06:07:06-08; load 16/core four minutes later).

Removable or overlappable:
- **`lr-audit.py`, 1-10 s [m].** It builds the ingest prompt's audit, and `--no-prompt` sends no prompt.
- **The precheck probe, 5-18 s [m].** It re-reads the pane, composer and subagents, which handoff-fire then reads again in
  its own gates, composer gate (`:18988`) and last read (`:3490`).
- **The transplant admit** could run during the precheck.
- **Startup cost:** each of the 4+ processes parses its own large script (handoff-fire.sh is 19,771 lines).

### 2.2 debt open → relaunch spawn: median 35 s, 20-149 s [m]. Partly fixed, partly load-sensitive

**/exit lands.** `hf_exit_readback` (`handoff-fire.sh:3594-3608`) waits 0.5 s up to 3 times plus kitty send/read. SessionEnd
fired 2-8 s after the debt opened **[m]**.

**Claude exits.** It runs 7 synchronous SessionEnd hooks with timeouts of 5-10 s (`~/.claude/settings.json`). Measured
SessionEnd → last transcript write is **6-11 s [m]** (wave 1). The code comment at `:3646-3648` says shutdown's failsafe is
15 s and SessionEnd alone may take 10 s.

**The watcher sees the shell** (`:11222-11227`, `at_shell` every 1 s). Then it:
- folds a re-created source stub with `lr-transplant --phase fold-stub` (`:11676-11700`);
- sleeps a fixed 2 s settle (`:11730`; oct6:10011);
- takes the launch lock and runs the holder census (`:11806-11830`);
- types the line with echo verification (`it2_type_verified`, `:11836`); the `sleep 3` at `:11842` runs only after a failed
  round.

**The pane's shell runs the launcher.** Then `lr-fire-resume.sh` starts up. It re-runs `lr-preseed-env.sh`
(`lr-fire-resume.sh:701-706`), because `LR_PRESEED_DONE` is set only for lr-handoff (`lr-move-worker.sh:168`) and the minted
launcher does not carry it. It then reaches the spawn (`:1212`).

Old claude's last write → spawn was **13-21 s [m]** (wave 1). On Oct 16 at 2-3/core, comparable resume recycles
(f4dfdbda, 538db399, 5423f92a, in `handoffs.jsonl` and `sessions.log`) went **typed → SessionStart in 3-6 s [m]**.

**Background-work dialog rows (deaa242a, 404651b1, c56c729c): 64-149 s [m].**
- The watcher looks for the dialog only on its bgwork tick: `CC_RECYCLE_BGWORK_EVERY_S=15` (`:11197`; oct6:9591).
- In the Oct 6/10 code `waited` was a **sum of sleeps, not wall time** (`waited=$((waited+rcy_poll))`, oct6:9612 and
  oct10:10048; it is wall time now at `:11227`). So every checkpoint landed later than its nominal second by the cost of each
  `at_shell` read.
- The stop answer landed at +14, +19 and +30 s **[m]**. The spawn still came 50-130 s after that **[m]**: deaa242a and
  404651b1 both spawned at 06:12:38-39. Cause unresolved without the watcher logs. Candidate: a stranded /exit released only
  by the 60/150 s nudge latch (`:11215`, `:11544-11575`; oct6:9609, oct6:9846-9864) **[e]**.
- Surviving Oct 16-17 watcher logs from current code show answer → exit in about 5 s **[m]** (`handoff-recycle-25-1792288395`:
  bgwork@23s, exited @28s).

**Fixed parts here:** the 2 s settle, the 1 s shell poll, the 0.5 s readbacks, and the 15 s bgwork tick for dialog rows.
**Load-sensitive parts:** the SessionEnd hooks, typing over kitty RC, and launcher startup.

### 2.3 spawn → debt discharged: median 35 s, 24-75 s [m]. One fixed 15 s hold plus a slow detector

The watcher's boot loop (`:11946-11963`) ticks every 0.5 s (`RCY_BOOT_IVL_S`). Its cheap tty-scoped `ps` cannot see claude,
because claude runs on expect's nested pty (comment at `:11889-11892`). So detection waits for the `pane_cc_state` read every
6th tick (`RCY_BOOT_PANE_EVERY=6`, `:11898`), and missing it runs to the 60 s boot bound (`:11894`) and then to 5 s polls
(`:11977`).

Once claude is up, `HF_ENGAGE_BY_PROCESS=1` (set by the worker, `lr-move-worker.sh:167`) runs `rcy_pp_up`. That is a
machine-wide `ps` for `--resume <sid>` (`:12022-12025`), followed by a **fixed `sleep 15`** (`HF_ENGAGE_PROC_HOLD_S`,
`:12018`, `:12029`; oct6:10234), a second `ps`, then mail, the event row and `cc-resume-debt discharge` (`:12032-12034`). A
failed first read costs `sleep 3` (`:12039`).

The new claude itself was up fast:
- first transcript record 2.0-4.1 s after spawn **[m]**;
- sync SessionStart hooks done 1.7-5.4 s later **[m]**;
- READY 2-5 s after spawn **[m]**.

So spawn → discharge (24-37 s) − 15 s hold leaves **9-22 s [e]** of detection lag plus rails. 4d059264's 75 s fits a boot
loop that never saw claude in its 60 s window: 60 + 15 = 75 **[e]**. The surviving Oct 17 pane-7 watcher log shows that
failure: `INDETERMINATE:boot — no claude on /dev/ttys011 … 111s after the relaunch was typed`, followed later by
`relaunch process up` **[m]**.

**Why this phase gates the verdict.** `lr_move_verdict` P7 (`lr-move-lib.sh:146`) refuses while the debt is
`open|retrying|escalated`. The worker therefore cannot see MOVED until the watcher discharges, and proof-first followed the
discharge by 1-15 s in every row **[m]**.

Two survival checks run back to back: the watcher's 15 s hold, then the worker's own "same pid twice, 5 s apart"
(`LR_MOVE_STABLE_S`, `lr-move-worker.sh:197`).

The last 7.5-17 s (proof-first → result **[m]**) is 5 s of stable wait plus 2 s polls (`:208`) plus verdict compute. The
event spacing gives about 2 s per verdict at 16/core and 5-6 s at 5.5/core **[e]**. One cost is `lr_session_location`, which
globs every project dir in 5 stores (`lr-move-lib.sh:13-21`); it took **7.3-7.6 s per call at load 30/core today [m]**
(`/tmp/lri-i/glob_cost.sh`, uptime load 297-313).

## 3. The three specific questions

**New claude, relaunch → registry row.**
- For these rows it is not retained (rows overwritten).
- Proxy: on 52 live rows today, process `lstart` → registry file birth (= `startedAt`) has **median 4 s, p90 11-12 s,
  max 17 s [m]** (`~/.claude/cc-registry/*.json`, `stat -f %B`). The writer is `hooks/session-register.sh`, which runs async
  with a 5 s timeout (settings.json SessionStart).
- On the 9 rows, SessionStart began 1-4 s after spawn [m] and the sync hooks ended 3.7-9.5 s after spawn [m]. So the row
  landed about **spawn + 4 s (1-17) [e]**, which is 20-70 s before the debt discharge. **The registry row is not on the
  critical path; P7 is.**

**Claude exit → relaunch line sent.**
- Not directly measured: the watcher logs are gone.
- Bounds [m]: old claude's last write → lr-fire-resume spawn is 13-21 s (wave 1), and SessionEnd → spawn is 18-41 s on the
  non-dialog rows.
- Inside that: ≤1 s shell poll, 2 s fixed settle, fold-stub, launch lock and holder census, typing with echo verify (send
  0.2-0.6 s [m], the `recycle-type-attempt` rows of Oct 16), then launcher and lr-fire-resume startup including the preseed
  re-run.
- The Oct 16 proxies show the watcher typing about **5 s after the shell [e]** (log "CONFIRMED at a shell prompt after
  15-20s" vs `recycle-type-attempt` at 28-33 s from T0).

### Fixed sleeps and poll intervals on the actuate → result path

All current file:line.

| # | where | value | when it bites |
|---|---|---|---|
| 1 | `handoff-fire.sh:1981-1987` `await_armed` | 0.2 s poll (≤5 s) | every move |
| 2 | `handoff-fire.sh:1990-2000` `await_pane_proof` | 0.2 s poll, bound (10+3+5)×5 ticks = 18 s | every move |
| 3 | `handoff-fire.sh:18988` composer freshness gate `(…, 0, 1)` | 0 s wait, 1 s interval | every move |
| 4 | `handoff-fire.sh:3275-3290` `hf_wake_guard` (`LR_WAKE_GUARD_S=30` from `lr-move-worker.sh:166`) | sleeps up to 30 s | only within 30 s of a wake |
| 5 | `handoff-fire.sh:3600` `hf_exit_readback` | 0.5 s × up to 3 | every move |
| 6 | `handoff-fire.sh:18430` typed-/exit fallback | `osascript delay 2` per retry | readback off or failed |
| 7 | `handoff-fire.sh:11213/11227` exit-wait poll `HF_RECYCLE_SHELL_POLL_S` | 1 s (sum-of-sleeps clock in oct6/oct10) | every move |
| 8 | `handoff-fire.sh:11197` bgwork-dialog tick `CC_RECYCLE_BGWORK_EVERY_S` | 15 s | rows with a background job |
| 9 | `handoff-fire.sh:11175` | `sleep 2` | after a bgwork digit |
| 10 | `handoff-fire.sh:11089` | ≤`CC_RECYCLE_SELFCALL_WAIT_S` 60 s | self-call dialog only |
| 11 | `handoff-fire.sh:11215` nudge latches | 60 / 150 / 300 s | a stranded /exit |
| 12 | `handoff-fire.sh:11730` shell-prompt settle | **2 s** | every move |
| 13 | `handoff-fire.sh:11755-11756` claim grace / max | 20 s / 120 s (load-scaled) | staged (fresh) recycles only, not this lane |
| 14 | `handoff-fire.sh:11842` typing retry | `sleep 3` | failed typing round |
| 15 | `handoff-fire.sh:11894-11898` boot loop | 0.5 s tick, pane read every 6 ticks, 60 s bound (load-scaled), then 5 s polls to 180 s | every move |
| 16 | `handoff-fire.sh:12018/12029` engagement by process `HF_ENGAGE_PROC_HOLD_S` | **15 s** | every move (`HF_ENGAGE_BY_PROCESS=1`) |
| 17 | `handoff-fire.sh:12039` | `sleep 3` | process not up at the first read |
| 18 | `lr-move-worker.sh:208` `LR_MOVE_PROVE_POLL_S` | 2 s | every move |
| 19 | `lr-move-worker.sh:197` `LR_MOVE_STABLE_S` | **5 s** | every move |
| 20 | `lr-fire-resume.sh:1552-1554` | 0.3 / 0.2 s settles | prompt path; READY only, so not on this verdict's path |

There are no sleeps on lr-handoff's in-place path. `LRH_KITTY_SETTLE_S=4` at `lr-handoff.sh:221` is spawn-path only.

Per move, the unconditional fixed time is **≈ 15 + 5 + 2 + 2 (one prove poll) + ≈1.5 (readback) + ≈0.5-1 (shell poll)
≈ 26 s [e]**, plus 15 s on rows with a background job.

## 4. What can go, and the floor

**Current design, every phase at its best measured value:**
pre-/exit 14.3 (4d059264) + debt → spawn 20 (4d059264) + spawn → discharge 24 (bb1d86c8) + discharge → proof-first 1.1
(840ca76c) + proof-first → result 7.5 (404651b1) = **~67 s [e]**, a sum of best measured phases. The best whole row measured is
118 s.

At low load (2-3/core), the comparable Oct 16 resume recycles went handoff-fire start → engaged in 58-65 s **[m]**
(`handoffs.jsonl`). Adding a best-case lr-handoff prefix (~8 s) and the worker proof (~9 s) gives **~75-80 s [e]**. The current
design cannot reach 60 s.

The current code may differ: `2a2d64a19` adds a subject pin, a load gate, the exit-signal attempt, a launch lock and a holder
census, none of which is in these measurements. The load gate holds a resume-mode recycle above 8/core (`:3788-3793`), so the
Oct 6 rows (16/core) would now be HELD.

**Removals, largest first, with estimated savings [e]:**

1. **Decouple the verdict from the 15 s watcher hold (saves ~15-20 s).** P7 makes the worker wait for the watcher's
   `sleep 15` before it can even start its own 5 s stability check. Either the watcher discharges as soon as the
   `--resume` process is up and the worker's 5 s check proves survival, or P7 accepts "open with a live watcher whose
   `rcy_pp_up` holds". One survival check is enough.
2. **Boot detection by `rcy_pp_up`, not the pane read (saves ~5-15 s typical, ~45 s in the 4d059264 case).** The machine-wide
   `ps` for `--resume <sid>` already exists (`:12022`). The 0.5 s tick could use it directly, instead of the pane read every
   6th tick that misses expect's nested pty.
3. **Keystroke-free relaunch and signal exit for resume-mode moves (saves ~10-20 s; also lifts the load hold).**
   - Today `hf_succ_stage` stages only `fresh` recycles (`:4385-4388`); resume mode gets the typed /exit, the 2 s settle and
     the typed relaunch.
   - `hf_exit_signal` (`:3694`) requires a staged successor. Its comment cites ~1 s exit at rest (`:3625-3631`; not
     re-measured here).
   - Measured comparison: claim within ~5 s of exit in the Oct 16-17 logs [m], versus 13-21 s exit → spawn here.
   - Carry `LR_PRESEED_DONE` into the launcher too, which saves the preseed re-run in the pane (unmeasured).
4. **Answer the background-work dialog at once (saves 14-30 s on dialog rows).** The precheck already records
   `bg_work: watcher pids=…`, so the 15 s tick could fire on the first poll, or SIGTERM (#3) could kill the watcher job.
5. **Trim the pre-/exit chain (saves ~5-30 s, load-dependent).**
   - Skip `lr-audit.py` under `--no-prompt` (1-10 s).
   - Fold the precheck probe into handoff-fire's own reads (5-18 s).
   - Run the admit alongside the precheck.
   - Find the wave-1 68 s stall before relying on any of these numbers.
6. **Cheaper verdict reads (saves 2-10 s).** Check the two known transcript paths (source and target config dir), not a glob
   over 5 stores per 2 s poll.

**Floor after 1-4 (and 5 where cheap), median-case [e]:**

| phase | estimate | basis |
|---|---|---|
| pre-/exit chain | ~9-10 s | wave 2's measured 14.3 s minus the audit and the duplicate reads |
| SIGTERM exit at rest | ~1-3 s | — |
| staged successor claim + lr-fire-resume to spawn | ~3-6 s | the 3-6 s typed → SessionStart proxy |
| spawn → registry row | ~4 s | median, 52 rows |
| worker stability + one poll + verdict | ~7-8 s | — |
| **total** | **≈ 25-30 s** | — |

At the slow end (registry row 12-17 s, 5.5/core like Oct 10, precheck 14-18 s) it is **≈ 45-55 s [e]**. So **under 60 s
needs #1, #2 and #3 together**, plus #4 on panes with a background job. The pre-/exit chain also has to stay near its 14 s
best, which it did not in 2 of the 3 batches.

**Concerns:**
- (a) The 68 s wave-1 stall and the 50-130 s post-stop gap on dialog rows are unexplained. Their watcher logs and
  `handoffs.jsonl` rows are gone.
- (b) Batch-level only, not part of a single move: the slot width 4 makes later rows queue behind the first wave's
  proof-first. Wave 2 waited **167 s [m]** in slot-wait (06:07:08 → 06:09:55), longer than its own move.
