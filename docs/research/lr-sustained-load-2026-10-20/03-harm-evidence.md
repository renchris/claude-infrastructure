# 03 — Harm evidence: why the limit-recover load gates exist, and whether the harm is real at 15-40/core

Read-only research, 2026-10-20 ~04:00-04:35Z, during and just after the next3 weekly-cap incident.
**M** = measured (command or file named). **R** = read (file:line or commit). **I** = inferred or hypothesis.
All load figures are 1-minute load average; "/core" divides by `hw.ncpu` = 10.

## 1. Answer

1. **Load average itself is not the harm in any measured record.** Every recovery failure that was blamed on load
   in the incident traces to one of three things that are not load: (a) the recovery machinery runs in a
   **lower CPU band (PRI 20)** than the work loading the box (PRI 31); (b) a kitty 0.48.2 control-socket bug;
   (c) a gate that refused. At PRI 31 the same reads are fast at 14-20/core (§3).
2. **The single biggest mechanism is the band, and it is measured.** At load 140-203 (14-20/core), live A/B
   from this session:

   | Read (what the rail does) | PRI 31 (default band) | PRI 20 (`taskpolicy -c utility`, the band the daemon actually runs in) |
   |---|---|---|
   | `/bin/ps -axo pid=,ppid=,stat=,lstart=,args=` (the reconciler's census read) | 0.22-0.37 s | **16.5-25.6 s** |
   | `python3 -I -c 'import json,os'` (interpreter start, as for `--place`) | 0.20-0.30 s | **11.4-15.3 s** |
   | `kitten @ --to unix:/tmp/kitty-853 ls` (the pane resolver's read) | **0.07-0.08 s** | 3.2-7.5 s |
   | `kitty @ --help` (client start only, no socket) | 0.07-0.08 s | 4.0-4.3 s |

   (M: `bash /tmp/h03-band.sh`, 4 runs at load1 140.6-166.1; `bash /tmp/h03-kitty.sh`, 2 runs at load1 201.5-203.5.)
   The live reconciler is PRI 20 (M: `ps -o pid,pri,nice -p 38189` => `38189 20 0 … python -m lr_recon`), and so are
   the `lr-handoff.sh` and `handoff-fire.sh --recycle` it spawned (M: same `ps`, pids 23381, 23429, 46913, 53799 at PRI 20),
   while 706 processes, including every claude session, sit at PRI 31 (M: `ps -axo pri | sort -n | uniq -c`).
   The kitty server answered a full `ls` in 70 ms at 20/core. **So at that load the "terminal did not answer in 10 s"
   was the PRI 20 client, not kitty.**
3. **Which gates protect against a real, load-dependent harm.** None of them, as currently placed, protects against a
   harm that *load per core* causes. Two protect real harms that are correlated with load but caused by something else:

   | Gate | What it protects | Harm real? | Caused by load itself? | Verdict |
   |---|---|---|---|---|
   | handoff-fire recycle hold, commit 24/core (`d4260ae3c`) | a **typed** relaunch failing after `/exit` (F1) | Yes, once (F1, 2026-10-09, 42-45/core) | No: kitty RC backlog/transport plus a PRI 20 typer; 0 typing failures in 39 lines at 8-32/core | Real but narrow. Moot for staged (keystroke-free) relaunches, which the code already exempts |
   | handoff-fire precheck 20/core | same as above, earlier | as above | No | Already skips staged moves (`scripts/handoff-fire.sh:13836-13837`) |
   | **lr-move-worker load wait, 20/core** (`lr-move-worker.sh:299-351`) | a *copy* of the precheck | Only for typed relaunches | No | **Folklore since Wave S.** It still holds staged moves. This is what held all 4 idle sessions in the incident |
   | reconciler CPU brake `max(2.5, L_open)`/core, floor 1 per 20 s (`admit.py:143-150`) | "restore, don't grow" past the pre-limit operating point | No measured harm. 2.5/core is the uncalibrated alarm line (one fatal reading at 2.53/core was a memory panic) | n/a | **Folklore.** It is a rate limiter (1 per 20 s), and it refused only 2 of 11 in the incident |
   | capacity probe 30 s runner bound (`admit.py:58-66`) | memory terms (headroom ≥4 GB, segments ≤50%) | Memory harm is real (panics) | No: memory, not load. Headroom was 24-26 GB, segments 9-12% throughout | Real gate. **The 30 s bound on a PRI 20 child is the failure** (8 of 11 incident refusals) |
   | placer timeout 120 s → WAIT_DATA | nothing (a timeout is not a refusal) | n/a | n/a | Symptom of the band, not a gate |
   | `BootSlots` AIMD "failed at load 40+" (`admit.py:292-295`) | boot storms | The cited event was a 90 s *detection window* expiring at load ~40 *total* (~4/core), "the window was too short, not the relaunch wrong" | No | **Folklore.** `on_wave` is never called, so the AIMD never adapts. It is a fixed 6 |
   | `LR_MOVE_SLOTS` 4 (`lr-move-lib.sh:233-235`) | kitty RPC streams and overlapping boots | Unmeasured above 4 ("the largest overlap in 49 boots on record") | No | Unmeasured, not refuted. Width is not a load gate |
   | pacer 3 per account (`admit.py:159-176`) | API burst / 529s | 0/40 failures at N≤6; the "529 band" came from GH#62426, not here | No (API side) | Unmeasured above 6 |
   | kitty resolver 10 s bound → `HELD:pane:resolver-unavailable` | kitty main thread / talk thread | Talk-thread `accept()` death is real: a kitty 0.48.2 bug that killed 31 sessions on 10-01 | No: deaf kitty seen at 4.4/core too | Real hazard, but a code bug. The 10 s bound mostly measures the PRI 20 client (item 2) |

4. **Measured failure rate vs load does exist, and it does not rise with load where the band is not involved.**
   - Recycles that engaged: 17 of 17 at 32-67/core (M, §4.2).
   - Typed relaunch lines: 39 submitted, 0 failed at 8-32/core (R, H).
   - All 9 `recycle-dead` rows are launcher admission refusals, not boots or typing (M).
   - Rates that do rise with load are the ones produced by the PRI 20 rail. For example, placer timeouts run
     0/174 below 8/core and 12/30 at 16/core and above (M, §4.3).

## 2. Method and sources

- Gate provenance came from code comments, commit messages, and the plan and research docs they cite. Each claim
  was traced to its first measured instance.
- `git log main --no-merges -S load -- scripts/limit-recover scripts/lib/capacity-admit.sh scripts/handoff-fire.sh`
  gave 259 non-checkpoint commits. Their messages were read wherever a load bound was introduced or moved
  (`2bb9817d0`, `d58bb81d3`, `5d5743449`, `d4260ae3c`, `e2d0cee07`, `5a144f2e6`, `17962edb6`, `ed5614054`,
  `19eaebf7a`, `e66bf5760`).
- Live state was read only:
  - `~/.reso/limit-recover/recon/events.jsonl`: 28,325 rows, 232 `place` events, which carry `load1`;
  - `~/.claude/logs/handoffs.jsonl`: 1,082 rows, from 2026-10-17;
  - `~/.reso/load.jsonl*`: 131,331 points since 2026-10-02, 12 s cadence;
  - `~/.claude/logs/capacity-alarm.jsonl`;
  - `~/.reso/limit-recover/move/*/*.json`.
- Scripts used: `/tmp/h03-place.sh` (placer outcome × load bucket), `/tmp/h03-join.py` (handoffs rows joined to the
  nearest load sample within 120 s), and `/tmp/h03-band.sh` and `/tmp/h03-kitty.sh` (the band A/B).
- The A/B ran only reads: `ps`, a python no-op, `kitten @ ls`, and `kitty @ --help`.

## 3. The cross-cutting cause: the recovery rail runs one band below the load

### 3.1 What the band is (R + M)

- `man launchd.plist`, `ProcessType`: "If left unspecified, the system will apply light resource limits to the job,
  throttling its CPU usage and I/O bandwidth." (M: `man launchd.plist | col -b | grep -A22 'ProcessType <string>'`.)
- `scripts/limit-recover/com.reso.lr-reconciler.plist` has no `ProcessType` key (R, whole file). The installed copy
  matches (M: `plutil -p ~/Library/LaunchAgents/com.reso.lr-reconciler.plist`). `com.reso.lr-reset-poller` is in the
  same state (R: `17962edb6` message).
- Children inherit the clamp, and it is a one-way ratchet: "`taskpolicy -a` from a utility-clamped parent stays at 20"
  (R: `scripts/limit-recover/lr-reset-poller.sh:251`; memory `darwin-qos-band-mechanics.md`).
- So every placer, capacity probe, `lr-handoff.sh`, `handoff-fire.sh`, watcher, `it2-kitty` and `kitten @` client the
  reconciler or the move lane starts runs at PRI 20 (M: §1 item 2 `ps` rows).
- The relaunched **claude itself is not clamped**. It starts in the pane, as a kitty child (M: in-pane
  `expect … LR_CFG` pid 29897 at PRI 31).

### 3.2 Prior measurements of the same mechanism (R)

| When | What | Source |
|---|---|---|
| 2026-10-08 | research-router warm workers at PRI 20: hedge-on fallback 34/150 vs 119/150 at load 106-275; fixed by `ProcessType Interactive` (read back PRI 31/37) | `6d84fa3a6`, `a5d6bd21f` |
| 2026-10-18 | move lane at PRI 20 against 755 processes at PRI 31: "a nominal 5 s wait took 41-50 s, the recycle precheck 163 s"; verdict reads 604-685 s after rc 6 against a 20 s bound | `docs/research/lr-inplace-immediacy-2026-10-18/REPORT.md:22,68,154-165`; `raw/F-load-rail-cost.md:89` |
| 2026-10-18 | fix built but **staged, not loaded**: `com.reso.lr-move-kick` (ProcessType Interactive) | `17962edb6`; M: `ls ~/Library/LaunchAgents \| grep -i lr-` lists only reconciler, rig, watchdog and reset-poller |
| 2026-10-20 03:35-03:55Z | capacity probe: "six probe-error refusals at load 149-260 blocked five first turns, while by hand the same probe answered 0 or 9 in 1.5-4.9 s (18.3 s under taskpolicy -c utility at load 154)" | `ed5614054` message |
| 2026-09-22 | router `KWORK_BUDGET_S` "was sized in the wrong QoS band" | `1d82892d4` subject |
| 2026-10-11 | 133 `taskpolicy -b` evidence-GC runs "sat runnable for hours" at load 400-600 | `lr-reset-poller.sh:344-349` |

### 3.3 Today's A/B (M, §1 item 2)

At 14-20/core, the default band pays about 2-3× on a short read, compared with an idle box (I: `ps` ~0.1 s idle is
assumed, not measured here). The PRI 20 band pays **50-100×** on the same read. Every bound in the rail was sized
for the first case and runs in the second:

| Bound | Value | Source |
|---|---|---|
| kitty resolver | 10 s | brief; `bin/it2-kitty:269` `"$TIMEOUT_BIN" "$TIMEOUT_S"` |
| probe runner | 30 s | `admit.py:62` |
| `ps` read | 40 s | M: 29 `abstain` events "ps degraded: /bin/ps … timed out at 40s", the latest at 2026-10-20T03:58:07Z |
| placer | 120 s | `events.jsonl` place rows |

### 3.4 Cost of raising the band (R)

- The move rail's own CPU was "about 1.4-1.8% of box CPU" at load 168-614 (`raw/F-load-rail-cost.md` §Answer).
- The reconciler was 0.4% (`raw/F-load-rail-cost.md` §2 table, `lr-reconciler` 364 CPU-s of 96,640).
- So putting the rail at PRI 31 adds no measurable load. It only stops the rail from losing every scheduling
  contest (I, from those shares).

## 4. Failure rate vs load: every measured table found

### 4.1 Typed relaunch (the F1 harm the recycle hold exists for) (R)

- `docs/research/lr-inplace-immediacy-2026-10-18/raw/H-typed-relaunch-vs-load.md` §1:
  - post-telemetry attempts: 39 of 40 submitted;
  - the only failed attempt was at **5.74/core**, and its retry submitted;
  - 8-16/core: 3/3; 16-32/core: 3/3; 32+: no samples.
- `decisions/load-hold-bound.md` §3a, 2026-10-18:
  - 33 of 33 typed lines above 8/core submitted on the first attempt, max 31.84/core;
  - "typed lines above 8/core stand at 39 submitted and 0 failed … the 8-32 failure rate is below about 14% (95%)".
- The one load-tracked failure is F1, pane 44, 2026-10-09 at 42-45/core (`recycle-failures-kitty-2026-10-10/REPORT.md:48-75`):
  - "kitty forked the window at 05:12:38Z, **9 minutes after the client gave up**";
  - "the listing and the two background-work exchanges at 04:55:41-51Z worked at the same load";
  - "Not determined: whether kitty-side lateness or watcher-side process starvation dominated".
  - The watcher was detached at PRI 20 (I: same launch path as §3.1).
- **The gate is now the bigger harm.** On 2026-10-18, 8 of 11 STRANDED move verdicts directly followed a commit-time
  load hold of the same session. "Every session where the hold did not intervene MOVED"
  (`decisions/load-hold-bound.md` §3c).

### 4.2 Recycle outcomes joined to load, 2026-10-17 → 2026-10-20T04:23Z (M: `python3 -I /tmp/h03-join.py … 2026-10-17`)

| load/core | recycle-intent | recycle-engaged | recycle-successor-claimed (keystroke-free) | recycle-dead | held-unreachable (kitty) | held-load (the gate) |
|---|---|---|---|---|---|---|
| 0-4 | 3 | 2 | 3 | 0 | 0 | 0 |
| 4-8 | 8 | 6 | 1 | 0 | **2** | 0 |
| 8-16 | 35 | 19 | 16 | 4 | 0 | **21** |
| 16-24 | 18 | 9 | 6 | 3 | 2 | 5 |
| 24-32 | 23 | 14 | 13 | 1 | 1 | 8 |
| 32-48 | 11 | 10 | 10 | 1 | 3 | 2 |
| 48+ | 10 | 7 | 6 | 0 | 0 | 2 |

- **17 recycles engaged at 32-67/core.** The highest was 66.7/core at 2026-10-18T06:41:51Z, with elapsed 121-462 s
  (M: `-v` listing).
- **All 9 `recycle-dead` are launcher admission refusals** ("launcher REFUSED: term=active", or `FAILED:relaunch:gate`)
  (M: `jq -r 'select(.class=="recycle-dead")|.detail' … | grep -c -E 'REFUSED|refus'` => 9).
- **Kitty deafness is not load-ordered.** 2 of 9 came at 4.4 and 4.8/core (2026-10-17T21:01Z, socket
  `/tmp/kitty-44163` "accepted a connection" but did not answer).
- The held-load column is the gate's own output. Its densest band (8-16/core, 21 rows) is exactly where 0 typing
  failures were measured.
- Caveat (I): engaged and intent rows are bucketed at their own timestamps, so ratios are approximate. n is small
  above 32/core.

### 4.3 Placer outcome × load (M: `bash /tmp/h03-place.sh` over all 232 `place` events since 2026-10-05)

| load/core | n | answered | timeout (rc 124) | mean dur | max dur |
|---|---|---|---|---|---|
| 0-4 | 62 | 62 | 0 | 3.9 s | 23.9 s |
| 4-8 | 112 | 112 | 0 | 4.1 s | 14.4 s |
| 8-16 | 28 | 26 | 2 | 23.4 s | 89.6 s |
| 16-24 | 11 | 8 | 3 | 46.2 s | 120.3 s |
| 24-32 | 12 | 6 | 6 | 91.0 s | 120.7 s |
| 32+ | 7 | 4 | 3 | 91.0 s | 120.8 s |

- This is the one clean rate-vs-load curve in the record, and it measures a PRI 20 python process.
- A cache-only `--place` (`LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md:190`) needs about 4 s at low load. Interpreter start
  alone is 11-15 s at PRI 20 under load (§1).
- I (hypothesis, not measured): at PRI 31 the placer would answer in seconds at 30/core. Measuring it needs a
  read-only `--place` run in both bands.
- The bound is also not fixed: incident rows show `timeout=63s`/`66s` at load1 84-89, which timed out at 8-9/core
  (M: incident event list, 04:18-04:20Z).

### 4.4 The box-level record (R)

- **No load threshold separates the box's deaths from the loads it survived.** The only death with a reading was 2.53/core,
  and that was a memory panic, with 14 of 15 survived readings above it. "2.0/core … separates *in use* from *idle*"
  (`docs/research/max-load-per-core-derivation-2026-08-25.md:16-31`).
- The 8/core value is "a runaway circuit-breaker set above the whole survived population"
  (`load-ceiling-derivation-2026-08-24.md` §1 item 4), not a failure point. The recycle hold inherited 8 from it:
  "The 8/core commit bound was ship-land's gate factor, never typing data" (`d4260ae3c`).
- **Lag proxy.** 10 s sentinel ticks ≥5 s late: 1.0% at load 40-80, 3.3% at 80-160 and 15.6% at ≥160
  (`concurrency-scale-2026-10-04/README.md:46`). That is degradation, not failure. The sentinel's own band was not
  recorded (open question).
- Lesson already in the repo: "the postland reds look load-caused and are not … the discriminator is RETRIES"
  (`.claude/rules/agent-operating-lessons-situational.md:49`). Also: a transient fault "leaves only STANDING properties
  available to explain it" (`:170`). Load is the standing property here.

## 5. Gate by gate: origin, the harm claimed, the resource actually involved

### G1. Reconciler CPU brake (`scripts/limit-recover/lr_recon/admit.py:39-40,143-150`)

- **Origin.** Design §C6 gate 2, "CPU brake at the pre-limit operating point … a floor of one admission per 20 s, so
  nothing starves" (`docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md:212`). Added in `5a144f2e6`.
- **Harm claimed.** None measured. The rationale is "restoring is allowed; growth is refused" (`:207-210`).
- **The 2.5/core floor.** It is the "2.5 alarm line [that] is uncalibrated: 2.53 was fatal once and 5.98 was survived"
  (`concurrency-scale-2026-10-04/README.md`, Bottleneck model).
- **Incident.** It refused 2 of the 11 admission refusals (M: `jq … admit-refused` => `cpu 2, probe-error 8, restore-r 1`).
  With the 20 s floor (`admit.py:149-150`) it cannot block. It can only pace to 1 per 20 s.
- The brief's "refused every pass" is not what the events show. The probe was the refuser.
- **Verdict.** Folklore as a harm gate. It is harmless as a pacer at 1 per 20 s, and redundant with the pacer.

### G2. Capacity probe and its 30 s runner (`admit.py:58-66,182-199`; `scripts/lib/capacity-admit.sh`, 1,851 lines)

- **Harm protected.** Memory. Headroom ≥4 GB and compressor segments ≤50%. "The load term stays off"
  (`ARCHITECTURE.md:216`). The memory harm is real: both 09-16 panics came at compressor segments 100%
  (`concurrency-scale README` §1 item 4).
- **Incident.** Memory was fine: headroom 24.0-25.8 GB, segments 9.1-12.4% from 02:31Z to 04:29Z (M: `jq` over
  `capacity-alarm.jsonl`).
- The refusals were the runner's 30 s bound firing on a PRI 20 bash that sources a 1,851-line library (`ed5614054`).
- **Verdict.** The gate is real. Its failure mode is band starvation, which turns a fast memory read into a refusal.
  Also, the drip (`admit.py:270-283`) counts probe *timeouts* as refusals, so 3 timeouts are needed before any drip.

### G3. Placer timeout → WAIT_DATA (events `place … rc=124`)

- **Harm protected.** None. A placer that does not answer is not evidence that any account is full.
- **Resource.** A PRI 20 python cold start plus the claude-accounts work (§4.3).
- **Verdict.** A symptom of the band.

### G4. Move-worker load wait (`scripts/limit-recover/lr-move-worker.sh:299-351`)

- **Origin.** R7 (`5d5743449`): "load/core above handoff-fire's recycle bound is waited out before the slot". The
  comment cites F1: "/exit typed at ~45 runnable per core stranded pane 44" (`:299-301`). It says it "MUST stay in
  step with" handoff-fire's bound (`:305-306`).
- **What changed.** Wave S (`e2d0cee07`, committed 2026-10-20T00:09Z, before the incident; deployed: M `grep -c
  hf_succ_rails ~/.claude/scripts/handoff-fire.sh` => 5) made every move stage its relaunch keystroke-free. handoff-fire's
  precheck now says "load: not gated (the relaunch is staged in the pane, keystroke-free)"
  (`scripts/handoff-fire.sh:13831-13837`).
- **The worker's copy got no such exemption** (M: `grep -n -i 'stag\|keystroke' lr-move-worker.sh` finds no staged
  check; `load_over` at `:335-340` reads only the bound).
- **Incident.** All four idle sessions of batch `20261020T024813Z-next3-next2-78304` ended "NOTMOVED HELD:load — load
  36.23-38.02/core stayed above the 20/core recycle bound for 605-613s; nothing touched" (M:
  `grep HELD:load ~/.reso/limit-recover/move/*/*.json`).
- **Verdict.** Folklore since Wave S. The harm it guards (a typed relaunch) no longer happens on these moves.

### G5. handoff-fire recycle load hold: commit 24/core, precheck 20/core

- **Origin.** `2bb9817d0` (fix 8b): "F1 typed /exit at ~45 runnable per core, then failed 16 times to type the relaunch
  through a kitty RC transport at its 10 s bound". It started at 8/core, which was ship-land's factor. It was raised to
  24/20 in `d4260ae3c` on the 33/33 data.
- **Resource.** kitty RC transport, plus a typer that was itself starved (I: PRI 20 watcher). It is not load per se:
  "the listing and the two background-work exchanges at 04:55:41-51Z worked at the same load"
  (`recycle-failures-kitty-2026-10-10/REPORT.md:74`).
- **Verdict.** A real but narrow harm: a typed relaunch over a deaf or backlogged kitty. It is already exempt when
  staged. The remaining risk is the fallback when a stage is refused (4 of 9 exits fell back after the first deploy,
  `REPORT.md:92`).

### G6. BootSlots AIMD and the move-lane slots (`admit.py:292-410`; `lr-move-lib.sh:233-235`)

- **Origin.** "the resource that failed at load 40+ on 2026-09-19" (`ARCHITECTURE.md:581`). The cited event, verbatim:
  "**(2)** engagement window — `relaunch typed but no claude process appeared within 90s` on a box at load 40+, i.e.
  **the window was too short, not the relaunch wrong**" (`docs/plans/LIMIT_RECOVER_100P.md:391`).
- Load 40 *total* is 4/core. The same entry reports the probe "at 4–5/core".
- **So the origin is a detection timeout at 4/core.** Nothing in the record shows a boot that failed because of load.
- Boot time does grow. 59 s → ~170 s typed→engaged as load1 went 23-43 → 119-150 (`limit-recover-zero-memory-2026-10-06/slots/skeptic-safety.md:9`),
  measured by a PRI 20 watcher (I: confounded with the band).
- Boot hangs (15-46 min) were a secd keychain query from Bun's system-CA load, starved because secd's background-QoS
  threads get no CPU at load 100-270 (`concurrency-scale-2026-10-04/j-startup-hang.md` items 1-4). This is now removed
  by `CLAUDE_CODE_CERT_STORE=bundled` in settings (M: `grep CERT_STORE ~/.claude/settings.json
  ~/.claude-secondary/settings.json` => both `"bundled"`; also `bin/cc-close-attrib:198`).
- **The AIMD is dead code.** `on_wave` has no caller outside tests (M: `grep -rn on_wave scripts/limit-recover | grep -v /tests/`
  => only its definition at `admit.py:378`), so the limit is a constant 6.
- **Verdict.** Folklore as a load harm. It is a fixed concurrency width (6, and 4 in the move lane) that was never
  measured above 4.

### G7. Per-account pacer (3)

- **Verdict.** API burst protection: "limiter behaviour unmeasured above N=6 (0/40 failures at N≤6)". The 529 band
  "was never measured here; it came from GH#62426" (`ARCHITECTURE.md:213`). Not a load gate.

### G8. Restore budget R and the launcher active ceiling (8)

- **What they are.** Policy terms that count concurrency, not harm detectors. The ceiling `floor(ncpu × 0.8)` = 8 counts
  CPU-active turns (`19eaebf7a`). No measured failure point sits behind 8 (§4.4).
- **Incident.** This is the only gate that produced dead recycles: 9 of 9 `recycle-dead` (§4.2).
- Moves are exempt (`LR_ADMIT_MODE=swap`, `decisions/load-hold-bound.md` §1).

### G9. Kitty resolver 10 s bound → `HELD:pane:resolver-unavailable`, "composer unreadable", post-transplant rollback

- **Real hazard.** A kitty 0.48.2 talk-thread `accept()` death wedged kitty 610 and killed 31 sessions on 10-01
  (`load-root-cause-2026-10-17/H-kitty-zombies.md:52`). A patched bundle is staged at `/Applications/kitty.app.staged`
  (M: exists). The running kitty is "0.48.2", started 2026-10-18 19:40 local (M: `kitty --version`; `ps -o lstart -p 853`).
  Whether the running binary is the patched build was not determined.
- **Incident.** At 20/core the kitty server answered `ls` in 0.07 s. A PRI 20 client took 3.2-7.5 s for the same call,
  and 4 s just to start (§1). it2-kitty adds bash forks around each call at the same band.
- An incident row shows where the time went:
  - `recycle-held-unreachable` at 2026-10-20T04:23:25Z, 16.5/core;
  - phases "gates@76s kitty-probe@77s self-id@77s intent@249s tty@258s detach@310s", so 172 s between self-id and intent
    were spent in PRI 20 bash before the watcher's probe failed (M: handoffs row).
- **Verdict.** A real but different hazard (a code bug, also seen at 4.4/core). At 14-20/core the 10 s non-answers are
  mostly the band (I: strong, from the A/B; not proven for every incident row).

### G10. Memory terms

- **Verdict.** Real harm (panics), not load. Keep them. Read them cheaply and at the right band (`sysctl`/`vm_stat`
  need no 1,851-line source).

## 6. Real harms correlated with load (so a design does not over-correct)

- **secd at background QoS starves** at load 100-270 and blocks any `SecItemCopyMatching` caller with no timeout
  (`j-startup-hang.md`).
  - Bun's CA load: mitigated (bundled).
  - OAuth reads: bounded at 2 s with a 30 s cache (`j-startup-hang.md` item 3).
  - "0 auth failures in handoffs.jsonl since 2026-10-04T16:50Z" (`slots/x-hostile-reviewer.md:50`).
  - Residual: any other keychain path at boot (I).
- **kitty-side backlog.** `kitty @ launch` was fulfilled 9 min late on 10-09 at 42-45/core (F1). Today's 70 ms answer
  at 20/core does not cover 40+/core (I).
- **Hook timeouts overshoot 2-3× under load**: cancelled at 16-35 s against 5-10 s nominal (`concurrency-scale README` resources table).
- **Boot time at PRI 31** stretches with load: binary boot 1.2-2.8 s normal, 4.5-8.6 s under load (`j-startup-hang.md` phase table).
  Any fixed engagement window must scale, or be event-driven, not pass/fail.

## 7. Levers this evidence supports (none applied; this axis is read-only)

1. **Run the rail at PRI 31.** Add `ProcessType Interactive` to `com.reso.lr-reconciler` (and `lr-reset-poller`, or
   load the already-staged `com.reso.lr-move-kick`, `17962edb6`). Every child inherits the band.
   - Expected effect (estimated from §1): placer, probe, `ps` and kitty reads move from 11-25 s to ≤1 s at 14-20/core.
   - This removes the probe-error, WAIT_DATA, resolver-unavailable and ps-abstain classes as far as the band causes
     them.
   - Cost: about 0.4-1.8% of box CPU (§3.4).
   - This is an operator activation, because it changes a launchd job.
2. **Give the move worker Wave S's staged exemption.** In `lr-move-worker.sh` `load_over`, skip the wait when
   `CC_PANE_SUCCESSOR` is on and the successor lib loads, exactly as `handoff-fire.sh:13836` does. That would have
   actuated the 4 idle sessions held for 605-613 s.
3. **Stop treating a probe timeout as a refusal.** Read the memory terms directly (cheap `sysctl`) when the library
   probe times out. Alternatively, count `probe-timeout` (now labelled, `ed5614054`) toward the drip immediately.
4. **Delete or demote the CPU brake** to a plain pacer. It has no harm behind it, and its 20 s floor already makes it a
   rate limit.
5. **Treat `BootSlots` as a fixed width**, honestly named. Either wire `on_wave` from measured engaged times taken at
   PRI 31, or drop the AIMD claim.
6. **Make every remaining load-scaled bound event-driven.** Engagement windows and resolver bounds should wait on the
   event (claimed successor, process appeared), not on a wall clock sized for an idle box.

## 8. What would move these conclusions

- A PRI 31 A/B of the actual placer (`claude-accounts --place`, read-only) and of `cc_capacity_probe` at ≥30/core.
- Recycle-engaged and typed rows at 40+/core *after* the rail runs at PRI 31. If kitty-side failures then appear at
  40+, G5's bound has a real (kitty) basis there.
- Confirmation that a launchd `ProcessType Interactive` job and its children read back PRI 31/37. This was measured
  once for `com.claude.research-classifier-warm` (`lr-inplace-immediacy REPORT.md:163-164`), not for the reconciler.

## Skeptic review

Adversarial re-check, 2026-10-20 04:34-05:00Z, read-only. Load during the re-check was 171-222 (17-22/core)
(M: `sysctl -n vm.loadavg`). Code was re-read on the live main checkout
`/Users/chrisren/Development/claude-infrastructure` @ `20368fc85`. The deployed `~/.claude` copies of
`lr-move-worker.sh` and `handoff-fire.sh` are byte-identical to it (M: `diff -q` => no output). Line numbers
below are main's, so a few differ from the worktree lines cited above (for example, `on_wave` is `admit.py:390`
on main and `:378` here).

### Fresh measurements made for this review (all read-only)

- **Band A/B, re-run in reverse order** (utility first, then default) to rule out an order or cache effect.
  Inline `/usr/bin/time -p`, 3 runs at load1 182-222:
  - `ps -axo pid=,ppid=,stat=,lstart=,args=`: utility **8.16-12.74 s**, default 0.24-0.34 s;
  - `python3 -I -c 'import json,os'`: utility **2.82-6.06 s**, default 0.08-0.83 s.
- **kitty RC** (`kitten @ --to unix:/tmp/kitty-853 ls`), 2 runs at load1 197-199: utility **2.17-3.40 s**,
  default **0.06-0.07 s**.
- **Placer components**, 2 runs at load1 171-178:
  - compiling `bin/claude-accounts` (11,629 lines; a script run as `__main__` is recompiled on every start):
    utility **8.63-11.56 s**, default 0.14-0.44 s;
  - its census `ps -wwEo pid=,command=`: utility **8.94-18.73 s**, default 1.45-2.67 s.
- **Box state.**
  - `top -l 2 -n 0` => `55.46% user, 44.53% sys, 0.0% idle`, so the CPU is fully saturated, and 44% of it is kernel time.
  - The chip is an M1 Max (M: `sysctl hw.perflevel0/1.physicalcpu` => 8 P-cores, 2 E-cores).
  - `ps -axo pri | uniq -c` => 665 at PRI 31 and 126 at PRI 20.
- **The new reconciler** (pid 51148, started 04:31:18Z by launchd, ppid 1):
  - 10 `ps -o pri` samples => 3×20 and 7×46. `ps -M` => `20T`.
  - Its lr-handoff children 1293, 1299 and 37708 sit at PRI 20.
  - The installed plist still has no `ProcessType` (M: `plutil -p`).
  - Reading: the base band is 20, and 46 is a transient boost. **One `ps` sample can mislead.** Sample several
    times, or read `ps -M`.

Ratios measured here are about 7-57×, not the 50-100× this file states. The absolute gap is still decisive: about
3-19 s at PRI 20 against 0.06-2.7 s at PRI 31, at 17-22/core.

### Verdicts on the findings

**F1. The band, not load, is the dominant cause of the incident's timeouts. CONFIRMED (ratio overstated).**
- The reverse-order A/B reproduces the effect, and every timed-out class in the incident sits on a band-sensitive read:
  - the probe-error: R `ed5614054` says the probe answered by hand in 1.5-4.9 s but took 18.3 s under utility;
  - the placer: compile plus `ps -wwE` alone is 18-30 s at PRI 20, measured above;
  - the ps abstains;
  - the resolver: see F2.
- `man launchd.plist` confirms that an unspecified ProcessType gets "light resource limits … throttling its CPU usage
  and I/O bandwidth".
- **Stronger precedent that this file missed.** `f1a62145d`: after `a5d6bd21f` moved the warm job to
  `ProcessType Interactive`, E1k run 3 measured **0/150 fallbacks in both arms at load 118-471, median 382**. That is
  ~38/core, with workers at PRI 31-37. Run 2, at PRI 20 and lower load, had 34/150 and 119/150. The
  commit message says: "the PRI fix, not the hedge". This is the only measurement in the repo of the band
  fix working at 25-47/core.
- **Correction.** This file's summary reads `6d84fa3a6` as "PRI 20 warm workers failed 34/150 vs 119/150". That
  pair compares hedge-on with hedge-off, and both arms ran at PRI 20. It is evidence of starvation, not a band A/B.
  The band A/B is run 2 against run 3.

**F2. kitty answers in 70 ms; the 10 s "terminal did not answer" is the PRI 20 client. CONFIRMED, and stronger than
stated.**
- Re-measured: the server answers in 0.06-0.07 s at ~20/core, and the utility client takes 2.2-3.4 s.
- **New evidence: the incident's "would not even accept a connection" verdict is itself a band artifact.**
  - `kitty_socket_accepting` runs `/usr/bin/python3 -c …` under a **3 s** bound (`scripts/handoff-fire.sh:1458-1482`).
  - Any non-zero result, including rc 124 from that bound, is read as "not accepting"
    (`:2867`, `:2874`, `:2926`).
  - At PRI 20, python start alone measured 2.8-15 s, so the bound can fire before `connect()` is ever called.
  - d7eb73d2's `HELD:pane:resolver-unavailable` (actlog `recon/actlogs/d7eb73d2.1.R.log`, bundle event at
    2026-10-20T03:12:24Z, 36/core) is this path.
- The watcher log for the 04:23:25Z row shows `it2 session list --json` rc=124 in 12 s against a 10 s bound
  (M: `/var/folders/…/handoff-recycle-30-1792470113-9ABLep.log`).
- **Weak link.** "172 s between self-id@77s and intent@249s spent in PRI 20 bash" is an inference.
  `handoff-fire.sh:16326-19483` is evidence and fence reading, not a wait, and nothing timed it.
- **Low-load deafness.** The three low-load held-unreachable rows (4.4, 4.8 and 19.7/core) were all on the *old*
  kitty `/tmp/kitty-44163`, which was replaced by 853 on 10-18. This fits the 0.48.2 talk-thread bug, not load.

**F3. The move-worker load wait is folklore since Wave S. CONFIRMED.**
- Code:
  - `lr-move-worker.sh:335-340` `load_over` reads only the bound;
  - `handoff-fire.sh:13836-13837` has the staged exemption;
  - `d4260ae3c` (worker waits on the precheck) was committed at 23:56Z, **13 minutes before** Wave S
    `e2d0cee07` (00:09:22Z). The copy predates the exemption.
- Small inaccuracy: `grep -i 'stag|keystroke'` does match comments at `:6` and `:226-232` (draft handling). None of
  them is a staged check.
- **The staged path is live at load.** Since Wave S, 8 `recycle-successor-staged` rows and 8 `-claimed` rows, with 0
  revoked or typed fallbacks (M: `jq` over handoffs.jsonl ≥ 00:09Z). Claims landed at 15-19/core
  (03:52:54Z at load1 151.75, 03:55:15Z at 193.33). There are also 12 `precheck load: not gated (the relaunch is
  staged …)` lines in `recon/actlogs/*` (M: `grep -h | uniq -c`).
- **The harm was larger than this file says.**
  - The second batch, `move/20261020T030423Z-next3-next2-15173`, sat in `load-wait` from 03:06 to 03:34Z (28 min).
  - During that wait 2 of the 4 sessions turned `became-limited` (3d1d988a, 3e929a81) and fell out of the idle lane.
  - The other two MOVED only at 03:58Z, with wall 3179-3192 s.

**F4. Recycles succeed at very high load. CONFIRMED, with a survivorship caveat.**
- Re-run of `/tmp/h03-join.py`: the counts match exactly, and all 9 `recycle-dead` rows are `launcher REFUSED`.
- Across all 29 handoff classes, intent→engaged does not fall with load: 54% at 8-16/core, 91% at 32-48 and 70%
  at 48+.
- **Caveat.** At 24/core and above, the commit hold lets only *staged* relaunches through. So the 17 engaged at
  32-67/core say that staged relaunches survive load. They say nothing about typed ones, which have n=0 above
  32/core apart from F1.
- What does rise with load is the launcher's `refused` share: 33% at 0-8/core and 65% at 32-48 (M: same join). That
  is a gate output (`term=active`), not a harm.

**F5. BootSlots' "failed at load 40+" is a 90 s window at ~4/core, and the AIMD is dead. CONFIRMED.**
- `LIMIT_RECOVER_100P.md:391` reads verbatim "the window was too short, not the relaunch wrong", and item (3) of
  the same entry is "4–5/core".
- `grep -rn on_wave scripts/limit-recover bin | grep -v /tests/` => only `admit.py:390`.
- `__main__.py` uses only `acquire` and `release` (`:1090-1131`). The limit stays `min(6, LR_BOOT_MAX=12)`.

**F6. The CPU brake did not block; the probe did (8 of 11). WEAKENED: the conclusion holds, the counting does not.**
- **The method is invalid.** `admit-refused` is written only when a record's refusal *reason changes*
  (`lr_recon/__main__.py:1229`: `if rec.close.get("admit_refused") != why`). So 8/2/1 counts reason
  transitions, not passes or time. Event rows cannot confirm or refute the brief's "refused every pass".
- **The conclusion still holds, from code and durations.**
  - `cpu_ok` (`admit.py:150-157`) passes once 20 s have elapsed since the last admission, or since ACTIVE entry.
  - Per-sid timelines (M: `jq` on events.jsonl since 02:23Z):
    - 7aae55e1: `probe-error` 02:44:27 → `cpu` 02:54:18 → spawn 02:54:50, so the brake cost about 32 s;
    - d7eb73d2: own 02:43:15 → spawn 02:46:14.
  - db755a94 sat from `cpu` at 02:54:19 to spawn at 03:08:24 (14 min), and no event explains why. With no admission
    in between (M: `launch.log`), the 20 s floor makes a brake refusal impossible after about 02:55:10. The
    likely blocker is the placer: `place … rc=124` at 02:53:20Z and 03:06:30Z put the record in WAIT_DATA, and that
    path is silent. Hypothesis, not proven.
- Memory re-read (M: `jq` over `capacity-alarm.jsonl`, 02:31-04:30Z, n=35): headroom **20.96-27.40 GB**,
  seg_pct **9.0-15.2%**. That is far from 4 GB and 50%.
- All 35 rows read `"verdict":"ALARM"`, purely because `load_per_core` exceeds `load_alarm_per_core` 2.5 (M: last
  row, 21.30 vs 2.5). Under the operator premise that alarm is permanent noise.

**F7. Placer timeouts rise with load, but measure a PRI 20 python. CONFIRMED (medium).**
- Re-run of `/tmp/h03-place.sh`: 237 events now, with the same shape. 0/174 below 8/core; 14/35 at 16/core and
  above.
- The two largest CPU components of `--place` are band-sensitive (measured above): 18-30 s at PRI 20 against
  1.6-3.1 s at PRI 31.
- Components the band does *not* fix (R `bin/claude-accounts`):
  - a network usage fetch, `urlopen(timeout=12)` (`:1727`);
  - parallel `security find-generic-password` reads bounded at 8 s (`:7452`, `:7496-7500`, `:7611-7613`), which
    go through secd. secd's background-QoS starvation (`j-startup-hang.md:16-21`) does not depend on the caller's
    band.
- At PRI 31 a worst case of roughly 3 + 12 + 8 s still fits 120 s (I).
- **Counter-sample.** Durations are noisy against load1:
  - 04:18-04:20Z timed out at 8.4-8.9/core, on *shrunk* bounds of 63-66 s;
  - 04:32-04:33Z answered in 14-18 s at 19.8-21.7/core.
  - So load1 is a weak predictor of a single run.

**F8. The per-core constants were never derived from a failure. CONFIRMED.**
- `max-load-per-core-derivation-2026-08-25.md:16-31,44-50`: five deaths and one load reading (2.53/core, below 14 of
  15 survived readings).
- `load-ceiling-derivation-2026-08-24.md:32-33,196-208`: 8.0 is "a runaway circuit-breaker".
- `d4260ae3c`: "ship-land's gate factor, never typing data".
- The panic postmortems name compressor-segment exhaustion with watchdogd starved:
  - `panic-2026-08-24-fifth-watchdog.md:59`: `compressor_exhausted` with 16.4 GB available;
  - `panic-iterm2-coalition-2026-07-31.md:23-28`.

**F9. The real load-correlated harms are specific resources. CONFIRMED, with additions.**
- `CLAUDE_CODE_CERT_STORE=bundled` covers **all five** config dirs, not two:
  - `.claude-next`, `-tertiary` and `-quaternary` `settings.json` are symlinks to `~/.claude/settings.json` (M: `ls -la`);
  - `bin/cc-close-attrib:198` defaults it.
- The list omits **kernel-side stalls**, which the band may not cure:
  - 44.5% sys time at load 200 (M: `top`);
  - `bin/claude-accounts:829-836` records a SIGKILLed `ps` "stuck in the kernel" that returned after 1,226 s at
    load 330.
  - Whether a PRI 31 caller escapes that is unmeasured (I).
- It also omits secd starvation of `security` calls in the placer (F7).

### Verdicts on the levers

**L1. Run the rail at PRI 31 (Interactive on the reconciler and reset-poller, or load `lr-move-kick`). CONFIRMED.**
- This is the best-evidenced lever:
  - today's A/B, which reproduces;
  - `f1a62145d`: 0/300 fallbacks at a median of 38/core after the same plist change.
- Safety caveats this file did not state:
  - (a) `lr-move-batch.sh:335-339` deliberately clamps the switch census back to `utility` ("a census is 19-27
    CPU-s"). Any heavy census the reconciler runs should keep that clamp, or the rail stops being 0.4-1.8% of CPU.
  - (b) Loops paced by their own slowness will run more passes at PRI 31, which means more CPU. Unmeasured.
  - (c) It does not touch kitty-side backlog at 40+/core (F1, 2026-10-09) or secd.
  - (d) The move workers in this incident were started by `lr-reset-poller` (`lr-reset-poller.sh:232-243` claims
    `request.claimed.json`), so fixing only the reconciler plist leaves the idle lane at PRI 20.
- It needs operator `launchctl` activation and a PRI readback, sampled more than once (see the 20/46 flicker above).

**L2. Give the move worker the staged exemption. WEAKENED: the mechanism is right, the stated effect is
overstated.**
- It is safe. The fallback is the 24/core commit hold, stage refusals are 0/8 since Wave S, and a post-transplant
  rollback is now re-offered (`20368fc85`).
- But "the 4 idle sessions would have actuated immediately" assumes the rest of the worker path answers at
  36-38/core, and that path runs at PRI 20.
  - At 03:12Z (36/core) the R lane's PRI 20 precheck parked d7eb73d2 on exactly the 3 s python connect probe (F2).
  - Even at 15-19/core the second batch's actuate step took 19 min (03:35:33 → 03:54:35).
- Without L1 for the move lane (`lr-move-kick`), the likely result is `HELD:pane:resolver-unavailable` in place of
  `HELD:load` (I). Ship L2 together with L1.

**L3. A probe timeout is not a capacity refusal. CONFIRMED.**
- Memory was never close to binding (F6).
- Main already labels `probe-timeout` separately (`admit.py:209`), but it still counts toward `DRIP_AFTER = 3`
  (`:44`, `:282-296`).
- Caveat: the direct `sysctl`/`vm_stat` read must itself run at a band where it answers. At PRI 20 even `ps` took
  8-25 s, so L3 is most robust together with L1.
- "8 of 11 refusals" should be restated as durations (F6).

**L4. Retire the CPU brake as a harm gate; name BootSlots a fixed width. CONFIRMED (low impact).**
- No harm sits behind either.
- The brake's measured cost in the incident is about 32 s (7aae55e1). The 20 s floor caps it, so removing it buys
  little latency. The rationale fix is the main value.
- Keep the pacer, R and the memory probe.

**L5. Replace wall-clock windows with event waits. WEAKENED for kitty RC; sound for boot windows.**
- The repo records that kitty 0.48.2's `kitty @` has **no `--response-timeout`**: "the client gives up on its own
  schedule and a bigger hf_bounded window buys no extra waiting" (`handoff-fire.sh:2894-2896`).
- So for the resolver and watcher reads, a longer or event-driven outer wait does not help. A starved client still
  times out internally, and only the band (L1) or a retry at a different moment helps.
- For engagement and boot windows, an event wait plus a liveness signal is right (`skeptic-safety.md:9` growth,
  `100P.md:391`).

### Open questions answered or narrowed

- **Q6 ("refused every pass"):** events.jsonl cannot answer it, because it is deduped per reason
  (`__main__.py:1229`). The 20 s floor (`admit.py:157`) rules it out after the first 20 s.
- **Q2 (Interactive readback):** still unmeasured for the reconciler. `f1a62145d` shows workers at PRI 31-37 under
  an Interactive launchd job at load 118-471.
- **Q1 (placer at PRI 31):** narrowed. The two band-sensitive components were measured (about 18-30 s → about 2-3 s).
  The network and keychain sub-calls are bounded at 12 s and 8 s and are not band-dependent.
