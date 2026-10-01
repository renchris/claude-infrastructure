# C2: a one-step "restore everything" command built from scripts/boot-resume.sh

Researcher dossier, 2026-10-01, read-only. Every number is labeled **measured** (with the command or file it came from) or **estimated** (with the method). UNMEASURED means not checked.

## Answer first

**Build it. Measured against today's run, C2 restores all three events with zero or one command. It cannot keep anything in flight alive.** Every event still ends every turn, background shell, Monitor, subagent and workflow, and only a one-shot recovery nudge re-engages them. A session layer outside kitty (C1) is the only way to avoid that loss for events (a) and (b).

The run on 2026-10-01 failed for **six** reasons. The restart-result section of the plan names three of them:

1. **Capacity.** The load term refused at 2.05/core, so round 1 launched 10 and shed 22.
2. **Fullscreen.** The title-matched fullscreen read `nomatch` in all 12 of its attempts.
3. **Nudge delivery.** The recovery prompt went out late. When it did go out, **30 of the 31 prompts never reached a transcript.**
4. **Resurrections (new).** The round loop **re-launched 5 sessions that had ended on purpose after their first resume**: 4 had retired themselves and 1 had recycled into a successor. 4 of those duplicates are still alive (panes 12 to 15).
5. **Stacked keepalives (new).** Every round started its own keepalive (3 of them) and filed the same backlog row again (5 pages).
6. **Tombstones are incomplete (new).** Only **19 of 32** sessions left one at the kill. A crash or reboot that has to rely on tombstones would lose 13 sessions.

The design below fixes all six:

- An **`--event` mode** with its own marker. The per-boot marker is never touched.
- **Three triggers:**
  - Reboot: the existing launchd job.
  - Planned restart: `cc-restore --restart-kitty`, one command.
  - Crash: a dead-kitty detector inside the same 300 s launchd tick.
- **Roster sources.** Each restart takes a fresh snapshot. For a crash or reboot, a 5-minute heartbeat roster is unioned with the tombstones.
- **A retire filter and a launched-once ledger**, so nothing is resurrected.
- **Model and effort** carried through to `reso-resume-one --effort` and `CC_RESUME_MODEL`.
- **A restore capacity mode.** The load term is off, a start gate sits at 6/core, and the loop waits and retries instead of shedding.
- **Fullscreen by kitty window id**, read back from CoreGraphics bounds.
- **A new `WAKE-LOST` verdict** in the classifier. It drives a one-shot `/limit-recover` nudge, sent by window id with the Enter key sent separately and confirmed in the transcript.

Time to the full fleet of 32, all estimated:

| Event | Estimate | Method |
|---|---|---|
| Planned restart | about 10 min | measured 12.7 s per pane |
| Crash | about 10 to 15 min | plus detection, at most 300 s |
| Reboot | about 12 min after login | plus the boot-storm wait |

Today's run, measured, took 14.7 min to the last real launch and 20.5 min to the (mostly undelivered) nudge.

---

## 1. What happened today, reconstructed from disk

Sources:
- `/tmp/inboot-2026-10-01/{run.log,supervisor.log,finish.log,state/*}`
- `~/.claude/logs/pane-spawns.jsonl` (caller `cc-resume-layout.sh`, 18:31Z to 18:47Z)
- `~/.claude/autonomy/idl.jsonl` (capacity-admit and boot-resume rows)
- `~/.claude/logs/sessions.log`
- `~/.claude/watchdog/teardown/<sid>.json`
- the 32 transcripts
- the preserved scripts in this directory

### Timeline (local time; the logs are in UTC, add 5 h)

| Time | Event | Evidence |
|---|---|---|
| 13:15:47 | The waiter is armed. A land is in flight (49762) and load is 135.3 on 10 cores. | run.log |
| 13:29:22 | Final roster of 32. SIGTERM to 610, which it ignores. | run.log; `reboot-inboot.start = 1790879362` |
| 13:29:32 | SIGKILL. 610 exits at 13:29:33. | run.log |
| 13:29:34 to 36 | All 32 log `Session ended … reason=other`. Only **19 write a tombstone**. | `grep 'Session ended' sessions.log` → 32 × reason=other; tombstone census → 19 of 32 roster sids |
| 13:29:48 | New kitty 48854 answers. | run.log |
| 13:29:48 to 13:31:28 | The waiter waits for load below 2.0/core (`kitty-restart-resume.py:165-167,301-306`). | run.log "round 1: load 18.9" |
| 13:31:44 to 13:33:40 | **Round 1** admits 10 at 1.64 to 1.91/core (panes 2 to 11). The 11th (68691067) is **refused at 2.05/core > 2.0** (`capacity-admit.sh:1253-1257`). The layout sheds the tail of 22 (`cc-resume-layout.sh:250-252`). Fullscreen succeeds 0 of 3. | idl.jsonl capacity-admit rows; run.log verdict line |
| 13:33:14 / 13:33:39 | **16798199 and 40ebc527 retire themselves**: `handoff-fire.sh self-close --terminal` writes a teardown marker, then the session exits with `reason=prompt_input_exit`. Both had been trying to close before the deadlock and finished the close once kitty answered. | transcripts at 18:32:57Z and 18:33:35Z; `teardown/<sid>.json mode=terminal`; sessions.log |
| 13:34:43 | **Round 2.** 8 are already running (held, rc 5), so "8 of 32 came back" is 10 launched minus 2 self-retired. The first row is refused at 2.25/core and shed=24. | page `undelivered-1790879683`; idl |
| 13:36:16 / 13:36:28 | **3a06361f recycles itself** into successor 90040b85 (pane 6). **4433afc6 retires itself** (goal met). | `teardown` modes recycle and terminal; handoffs.jsonl `recycle-engaged` 18:37:03Z; `cc-registry/6.json` |
| 13:37:03 | **Round 3 re-launches 16798199 (pane 12), a session that had retired.** The next row is refused at 2.04/core. The lead then stops the waiter, and the supervisor never gets past "armed". | pane-spawns; idl; supervisor.log has 1 line |
| 13:38:56 to 13:44:12 | `inboot-finish.py` round 1, at a ceiling of 6/core (`inboot-finish.py:20,61`), admits **all 25** (peak 3.28/core). Those 25 include **3 resurrections**: 3a06361f (p13, a duplicate of its own successor), 40ebc527 (p14) and 4433afc6 (p15). Fullscreen: AX 0 of 7; `kitten @ action --match id:<w> toggle_fullscreen` rc 0 on 7 of 7. | finish.log; idl rows "ceiling 6/core"; pane-spawns |
| 13:43:3x | d86e6bd4 retires itself from pane 25. | teardown marker; sessions.log 13:43:37 |
| 13:47:08 | Finish round 2 **resurrects d86e6bd4** (p39). It retires again at 13:51:38. | pane-spawns; teardown ts 18:51:38Z |
| 13:34 / 13:37 / 13:44 | **Three keepalives start, one per boot-resume run.** The last one (pid 217, markers `/Users/chrisren/Development/agent-context-sync`) nudged pane 32 three times in 74 s. | `~/.reso/keepalive.log`; `ps eww -p 217` |
| 13:50:00 | 31 recovery prompts, every one with `send-text` rc=0. | finish.log |
| 13:57:54 | **Only 1 of the 31 prompts is in a transcript.** That one is d86e6bd4, which was busy, so it was queued at 18:51:40Z. 30 transcripts have no row containing "kitty was restarted at 13:29". | `grep -l 'kitty was restarted at 13:29' ~/.claude-*/projects/*/*.jsonl \| wc -l` → 1 |

### Fate of each of the 32 sessions

| Group | sids | Where it went wrong | Why |
|---|---|---|---|
| Launched in round 1 and kept (6) | 0572baa6 p2, 064beecc p3, 09c26b2b p4, 4726bdf3 p9, 4fff2538 p10, 5fb8968b p11 | Fullscreen only | AX title match `nomatch` (`cc-resume-layout.sh:177-190,298-302`) |
| Shed in round 1, launched by finish (22) | 68691067, 705115e9, 89bdedfa, 8bae4f7f, 90b6aee4, a3669d21, aee9bc26, bb231dfd, bf6674d6, d86e6bd4, dcbd2f8e, f4c84c9d, f8b54aee, 1d6a059a, c28362b6, cd3bd860, 13d7be20, 8e18da3f, c8c2adc0, ddd154a9, 46bc0436, fe370fb2 | Capacity gate, then 3 to 15 min late | Load term 2.0/core; shed-the-tail on the first refusal (`cc-resume-layout.sh:250-252`); the per-run loop sat in load waits |
| Retired after a correct resume (4) | 16798199, 40ebc527, 4433afc6, d86e6bd4 | **Resurrected** into p12, p14, p15 and p39 | The round loop counts "not live in the new kitty" as missing (`kitty-restart-supervisor.py:111-113`, `inboot-finish.py:40-43`). Nothing reads the teardown marker. |
| Recycled after resume (1) | 3a06361f | **A duplicate** in p13, beside its successor 90040b85 in p6 | Same as above. A recycle marker means a successor exists. |
| Nudge (31 targeted) | all except 09c26b2b | 30 of 31 never submitted | `send-text … prompt + "\r"` in one write (`inboot-finish.py:107-119`, `kitty-restart-resume.py:350-362`). The keepalive's split-Enter sends to pane 32 at 13:44 to 13:46 **did** submit (13d7be20 transcript at 18:44:52Z, 18:45:22Z and 18:46:08Z). Mechanism, inferred: kitty `send-text` defaults to `--bracketed-paste disable` (kitty v0.48.2 `kitty/rc/send_text.py`), so the 700-byte burst plus CR reaches Claude Code as one paste-like chunk and the CR does not submit. UNMEASURED directly; no `get-text` was run. |

**Live hazard (report only, nothing touched):**
- Panes 12, 13, 14 and 15 hold resurrected sessions. Pane 13 (3a06361f) shares `film-mvk` with its successor in pane 6.
- About 30 panes may hold an unsubmitted recovery prompt in the composer, and the next keystroke there would submit it. UNMEASURED.

---

## 2. The design

### 2.1 Triggers

| Event | Trigger | Operator action |
|---|---|---|
| Mac reboot | Existing `com.claude.boot-resume` (RunAtLoad + StartInterval 300; `plutil -p ~/Library/LaunchAgents/com.claude.boot-resume.plist`). Mode is already `resume` (`cat ~/.claude/autonomy/boot-resume/mode`). | none |
| Planned kitty restart | **`cc-restore --restart-kitty`** (new `bin/cc-restore`, a port of the preserved `kitty-restart-resume.py`). Python, so `cc-reaper` leaves it alone (`kitty-restart-resume.py:19`). It detaches itself so it survives kitty. | one command |
| Unplanned kitty death (SIGSEGV, as on 2026-09-16, `cc-resume-classify.py:96-104`) | **A dead-kitty detector in the same 300 s tick**, added as step 0 of `boot-resume.sh` ahead of the per-boot early exit at `:237-241`. See below. | none |
| Kitty alive but deaf (today's case) | The tick sees the backlog on `/tmp/kitty-K` at 120 or more on 2 consecutive ticks (`netstat -anv -f unix`, as measured at 128 in `husk-panes-2026-09-30.md:88`). It files **one** `cc-backlog needs` row: "run `cc-restore --restart-kitty`". It never kills: ending 32 live sessions is the operator's call. An opt-in file `~/.claude/autonomy/boot-resume/auto-restart-deaf-kitty` lets the tick run the restart itself. | one command, or zero with opt-in |

**The dead-kitty detector, step 0 of each tick.**

1. Write the heartbeat (2.2).
2. Read the previous heartbeat's main kitty pid K (rows with `kitty_listen_on unix:/tmp/kitty-K` and no `--instance-group`).
3. Proceed only if all of these hold:
   - `kill -0 K` fails, or K's comm is not kitty;
   - K started after boot;
   - no `events/K.done` exists.
4. The event is `crash`. The anchor is the newest of:
   - the tombstone burst whose `kitty_pid == K`;
   - `terminal_crash_epoch()` (`cc-resume-classify.py:116-141`, the `.ips` file);
   - the heartbeat's own `.start`.
5. If no main kitty answers, run `open -n -a /Applications/kitty.app` with a clean env, by path, never `open -a kitty` (`boot-resume.sh:505`; the staged sandbox shares the bundle id, inboot G7). Wait for `kitten @ ls` on the new socket.
6. Exec `boot-resume.sh --event <anchor> --kind crash --kitty-pid K`.

Detection latency is at most 300 s (StartInterval). Lowering it to 60 s is a plist edit the operator would make.

### 2.2 Roster per event, and the `.start` bug

**The `.start` bug.** `alarm-reboot-prep.sh:52` appends `<epoch> kalloc1024_gb=…` to `reboot-$DAY.start`. `boot-resume.sh:298` then strips all whitespace and the guard at `:299` skips the roster (inboot §Answer 1). Fix both ends:
- `alarm-reboot-prep.sh:52` writes `reboot-$DAY.kalloc` instead. Update `tests/alarm-reboot-prep.bats:27`.
- `boot-resume.sh:298` becomes the tolerant reader `st="$(head -n1 "${f%.roster.json}.start" 2>/dev/null | awk '{print $1}')"`.
- Add one bats case that runs the two scripts together.

**Heartbeat (new, every tick).** Write all of the following with tmp + `mv`:
- `~/.claude/autonomy/heartbeat/hb.roster.json` (`cc-sessions --json`; 2.41 s real, 35 rows, zero kitty-socket calls: `/usr/bin/time -p cc-sessions --json`; `grep -c 'kitten\|kitty @' bin/cc-sessions` → 0)
- a one-line `hb.start`
- `hb.argv.tsv`: pid → `--model`/`--effort`, from `ps -o args=`
- `hb.bg.tsv`: the claude pid's non-MCP child processes

Keep the previous file if the row count fell by more than 2, as `kitty-restart-resume.py:229` does, so a snapshot taken mid-shutdown never replaces a good one.

| Event | Roster source, in order | Anchor |
|---|---|---|
| Planned restart | A fresh snapshot taken at the kill, `events/<epoch>/reboot-event.{roster.json,start}`, plus argv and bg | the kill epoch |
| Crash | `hb.roster.json` (5 min old at most) **∪** tombstones with `kitty_pid == K` in the last burst | tombstone burst max, `.ips` time, or hb.start |
| Reboot | alarm-prep roster (with the fix) → `hb.roster.json` ∪ tombstone burst → registry ghosts (`boot-resume.sh:345-366`) | roster `.start` or tombstone max |

The union matters because tombstones alone caught 19 of 32 today (measured; tombstone census for `endedAt ≥ 1790879360`). All 32 logged `reason=other`, but 13 had no tombstone file at all. The cause is UNMEASURED; candidates are the hook's row guard at `session-deregister.sh:41-63` and the SessionEnd hook timeout (10 s) under the SIGHUP storm. On 09-30 the same mechanism caught 19 of 20 (`session-deregister.sh:65-67` comment).

**Retire filter (new, between `boot-resume.sh:447` and `:455`).** Drop a sid when either holds:
- `~/.claude/watchdog/teardown/<sid>.json` (written at `handoff-fire.sh:6992-7013`) has mode `terminal` or `recycle` with `ts` later than the session's last assistant **text** before the anchor;
- `sessions.log` has `Session ended sid=<sid> reason=prompt_input_exit|logout` after the roster `.start`.

A recycle counts as retirement for the **old** sid, because its successor is a different sid that has its own roster row. This corrects the brief at `/tmp/fire-boot-resume-skip-retired.txt` ("A `recycle` marker is NOT retirement"); 3a06361f is the counterexample. Dropped rows go in the page, each with its exact launcher line.

**Launched-once ledger (new).** The ledger is `$STATE_DIR/events/<id>/launched`, one sid per line, appended when the layout prints that sid's `map` line. A later round never relaunches a sid that is in it, whatever its live state. This alone would have stopped all 5 resurrections today.

### 2.3 `--event` mode that never poisons the per-boot marker

`boot-resume.sh` gains `--event <epoch> --kind restart|crash [--kitty-pid K] [--roster-dir D]`.

- **`:217`.** `BOOT` becomes the event epoch, used for windowing and as the classifier anchor. `kern.boottime` is still read, separately, for the registry rule at `:359`.
- **`:220`.** `MARKER` becomes `$STATE_DIR/events/<K-or-epoch>.done`. The `last-boot-epoch` file is neither read nor written in event mode, so the `:238` dedup and the `:286-290` LOWER logic stay per-boot. The 300 s tick kept abstaining today with the private state dir (idl 18:35:34Z and 18:40:34Z `abstained`), so a real-dir event marker is the only new risk, and the separate file name removes it.
- **`:285-290`.** In event mode, `LOWER` is the previous event marker, or the event epoch minus 600 s.
- `CC_BOOTTIME_OVERRIDE` stays, for tests only.

### 2.4 Layout: one fullscreen window per Desktop, by window id

**Fullscreen.** Delete the System Events path: `fs_osa` at `cc-resume-layout.sh:177-190` and the title-marker loop at `:290-309`. After each window's `close_window` (`:232-237`), do the following:

1. Run `k action --match "id:$A" toggle_fullscreen`. That is kitty's `Boss.toggle_fullscreen`, which resolves the OS window from the dispatch context (kitty source `boss.py:1351-1356`; native Space when `macos_traditional_fullscreen` is unset, `glfw.c:1375-1383`). rc 0 on 8 of 8 (finish.log); verified on screen for 4 windows (plan:39).
2. Sleep 3 s, because back-to-back toggles are dropped (`:47-48`).
3. **Read it back:** CG bounds of `platform_window_id` (taken from `kitten @ ls`; reuse the Swift at `:378-391`) must equal a screen frame. `kitten @ ls` has no fullscreen field (kitty `boss.py:524-534`).
4. On a mismatch, retry once with `KITTY_WINDOW_ID=$A k action --self toggle_fullscreen`. Report the read-back count, not the rc.

Doing it per window rather than at the end gives the operator each Desktop as soon as it is ready.

**Map lines.** Print `cc-resume-layout: map sid=<sid> wid=<wid> oswin=<n>` on stdout for each launch (at `:271-276`). `boot-resume.sh` saves them to `last-layout.map`. The ledger and the nudge read that file.

Grouping stays by project, 2x2 (`:192-227`), which is the operator's 2026-09-30 ruling (`:41-44`). Kitty's real title bars are untouched.

### 2.5 `--resume` fidelity

| Field | Today | Change |
|---|---|---|
| sid | kept (`reso-resume-one:560` `--resume $sid`) | none |
| account | config basename → alias (`boot-resume.sh:205-208`); `cfg` from the alias (`reso-resume-one:396-405`) | none |
| model | `opus_latest` from SSOT (`reso-resume-one:172-179`) | Snapshot argv `--model`, falling back to the transcript's last `message.model` (present on assistant records: measured `claude-opus-5-5` × 104 in 0572baa6's tail). Pass `CC_RESUME_MODEL` (`reso-resume-one:173`). |
| effort | `high` default (`:384`) | Snapshot argv `--effort`, passed as `reso-resume-one … --effort <e>` (`:71`). **Do not** take it from the transcript: its top-level `effort` field read `medium` on 301 records of a session the inboot census saw launched `--effort high`, so the field means something else. UNMEASURED. With no argv, keep `high` and say so in the page. |

Plumbing:
- **`boot-resume.sh`.** WINNERS at `:440-443` and ADMITTED at `:469` carry columns 6 and 7. The classifier appends the verdict after all columns (`print(row + "\t" + verdict)`, `cc-resume-classify.py`, main), so `$NF` still reads the verdict.
- **`cc-resume-layout.sh`.** `:242-243` reads columns 6 and 7. `:257-258` builds `'env' 'CC_ADMIT_DONE=1' ['CC_RESUME_MODEL=<m>'] reso-resume-one acct wt sid br [--effort <e>]`.

### 2.6 Restore capacity mode: paced, never shed-and-mark

What was measured:

- After the kill, load fell to about 1.7/core, and 10 staggered resumes pushed it to 2.05. With 25 more at a ceiling of 6/core, it peaked at **3.28/core** with 32 to 47 GB reclaimable and compressor at 2.7% (idl capacity-admit rows 18:31Z to 18:44Z).
- The fleet normally runs at 5 to 13/core (plan:38).
- `capacity-admit.sh:92-103` forbids raising the 2.0 literal: "a fix moves a TERM SWITCH, never a ceiling".

So the restore mode is:

1. **Admission.** The restore caller sets `CC_ADMIT_LOAD_TERM=off` (a term switch, `capacity-admit.sh:1250-1258`). The memory terms (headroom 4 GB, segments 50%) stay on, since they move with the spawn. The `CC_ADMIT_RESTORE_R` active budget (`:1398-1405`) is not used for launches: a resumed idle session is not mid-turn.
2. **Start gate (a wait, never a shed).** Before the first launch, wait until `load1/ncpu ≤ CC_RESTORE_START_LOAD` (default **6**, the ceiling that admitted 25 of 25 today), capped at 10 min. This is what protects the reboot case from the boot storm (load 346 at boot+2 min, `boot-resume.sh:114-117`).
3. **Paced rounds inside the layout.** With `--restore`, `cc-resume-layout.sh:250-252` stops breaking out. A refusal sleeps `CC_RESTORE_WAIT` (30 s) and re-asks for **the same row**, up to `CC_RESTORE_DEADLINE` (30 min), and only then sheds the rest. Pacing stays the 12 s stagger (`:117`).
4. **boot-resume rounds.** In event or restore mode the run marks done only when `shed=0` or the deadline has passed (replacing `:615` and `:649`). One page per event, not per round (5 identical pages and 5 refilings of `ade4387f8a09` today: `ls /tmp/inboot-2026-10-01/state/undelivered-*`).
5. **Nudge pacing.** Nudges, which do make sessions mid-turn, are admitted through the active term with `CC_ADMIT_RESTORE_R=8` (`:1398-1420`).

If C18 must be kept to the letter, the fallback is the caller-scoped `CC_ADMIT_MAX_LOAD_PER_CORE=6` that `inboot-finish.py:61` used. It works (25 of 25), but it contradicts the file's own rule.

### 2.7 Recovery nudge: the WAKE-LOST verdict, targeted by window id

**Verdicts in `cc-resume-classify.py`:**
- `INTERRUPTED`: unchanged (`:216-242`).
- New **`WAKE-LOST`**: the transcript tail is a completed turn (AT-REST), but async work was **open at the anchor**.
- `AT-REST`: gets nothing, which keeps the 2026-08-24 operator ruling (`:12-25`).

`classify()` also returns the list of lost items. They are written to a side file (`--lost-json PATH`) so the TSV contract does not change.

**What counts as open async work.** Only records strictly before the anchor are read, as at `:157-158`.
- A `tool_use` named `Bash` with `run_in_background`, `Agent` with `run_in_background`, `Workflow` or `Monitor`, whose id gets no `<task-notification>` carrying `<tool-use-id>ID</tool-use-id>` before the anchor, and no `TaskStop` of its task id. Formats were measured in today's transcripts:
  - Workflow: `Workflow launched in background. Task ID: wtcaytsys`
  - Monitor: `Monitor started (task bv3wgaxut, …)`
  - Notification: `<task-notification><task-id>…<tool-use-id>…<status>completed`
- Scope it to launches after the session's last process start. The previous resume's own "didn't finish before the previous session ended" notice closes everything before it.
- `<cfg>/projects/<slug>/<sid>/subagents/agent-*.jsonl` or workflow journals with an mtime within 15 min of the anchor (measured: only 09c26b2b had any in the 30 min before 13:29:33, via `find … -newermt`).
- Planned restart only: `hb.bg.tsv` children of the claude pid.

**Calibration fixture (measured today).**
- On resume, Claude Code itself posted `<status>stopped</status> Background shell command didn't finish before the previous session ended` in exactly **10** sessions: 68691067, 89bdedfa, 90b6aee4, f8b54aee, aee9bc26, dcbd2f8e, 09c26b2b, d86e6bd4, 16798199, f4c84c9d. That is a task-notification count over the post-18:29Z transcripts.
- A naive "launched, never notified, last 24 h" rule flagged **24 of 32**.
- The rule must match the 10-session oracle on today's transcripts before it ships.
- Background shells are already reported natively and wake the session, as 16798199 did at 18:32:25Z. Monitors, subagents and workflows have no such notice. UNMEASURED: no lost one was observed today.

**Targeting and delivery (new `scripts/lib/restore-nudge.sh`, one shot, replacing the keepalive in event mode at `boot-resume.sh:539-566`).** For each INTERRUPTED or WAKE-LOST sid, with its wid from `last-layout.map`:

1. **Ownership.** The registry row for the sid has `paneUUID == wid` and `kitty_pid ==` the new kitty.
2. **Idle and not at a prompt.** Read the screen through `it2-kitty session read -s wid` and apply reso-keepalive's `SKIP_RE` (busy, prompt and await fragments, `reso-keepalive:~93-97`).
3. **Send** `^U`, then the text, then **after 0.5 s a separate `\r`**. That is the keepalive shape (`reso-keepalive:231-233`), measured to submit into pane 32. Better still, route it through `handoff-fire.sh:4070 it2_paste_submit_verified`, which pastes only into a composer proven empty and reads the text back before sending Enter. Pane 35's composer held kitty's own terminal replies (`^[P>|kitty(0.48.2)…`, handoffs.jsonl `recycle-held-draft` 18:47:46Z).
4. **Verify in the transcript.** Within 90 s, a user or queue record must contain the nonce line. If not, send one more `\r`; failing that, record `nudge-unconfirmed` in the IDL and the page.
5. **Pace it** through the active term with R=8.
6. Make `reso-keepalive:54` `NUDGE` env-overridable (`CC_KEEPALIVE_NUDGE`).

**Nudge text** (INTERRUPTED adds the bracketed clause; `<lost>` is rendered from `--lost-json`):

> [restore] kitty was {restarted|lost in a crash}{; the Mac rebooted} at HH:MM. This session was resumed in full: same session id, account, model and effort. This message comes from the restore tool, not from the operator. These ran under the old process and died with it: <lost: e.g. 2 background shells (bzrbwj020, …), 1 Monitor (bv3wgaxut), 1 Workflow run (wtcaytsys), 1 background subagent>[, and your last turn was cut off mid-way]. Run /limit-recover now. Read finished results from disk, re-run only what is incomplete (resume workflow runs with resumeFromRunId where the audit says so), and re-arm a watcher or Monitor only if you still need it and no /goal is live. If a ship-land or push was in flight, verify by content (git ls-tree origin/main) before landing again. Then continue the task you were on; do not start new work. If nothing was pending, reply with one line saying so.

### 2.8 File:line change list

| # | File:line | Change |
|---|---|---|
| 1 | `scripts/alarm-reboot-prep.sh:52`; `scripts/boot-resume.sh:298` | Kalloc reading to `.kalloc`; tolerant `.start` reader; paired bats test |
| 2 | `scripts/boot-resume.sh:217-241` | `--event/--kind/--kitty-pid/--roster-dir` parsing; event marker `events/<id>.done`; per-boot marker untouched |
| 3 | `scripts/boot-resume.sh` before `:237` | Step 0: heartbeat writer, dead-kitty detector, deaf-socket page (opt-in auto) |
| 4 | `scripts/boot-resume.sh:295-339` | Event roster dir; heartbeat ∪ tombstone union filtered by `kitty_pid` |
| 5 | `scripts/boot-resume.sh:447-455` | Retire filter (teardown marker, prompt_input_exit) and launched-once ledger |
| 6 | `scripts/boot-resume.sh:440-443,469` | Model/effort columns 6-7 |
| 7 | `scripts/boot-resume.sh:494-516,609-652` | Restore env (load term off, start gate); round loop until shed=0 or deadline; one page per event |
| 8 | `scripts/boot-resume.sh:539-566` | Event mode: `restore-nudge` instead of keepalive |
| 9 | `bin/cc-resume-layout.sh:242-243,257-258` | Model/effort pass-through |
| 10 | `bin/cc-resume-layout.sh:250-252` | `--restore`: wait-and-retry the same row; shed only at the deadline |
| 11 | `bin/cc-resume-layout.sh:177-190,232-237,290-309` | `toggle_fullscreen` by id per window plus CG read-back; delete AX/title; emit `map` lines |
| 12 | `bin/cc-resume-classify.py:154-242,465` | WAKE-LOST, `--lost-json`, the counts key; selftest built from today's 10-session oracle |
| 13 | `scripts/lib/restore-nudge.sh` (new) | Ownership, idle and prompt predicates, verified send, transcript confirmation, R pacing |
| 14 | `bin/reso-keepalive:54` | `CC_KEEPALIVE_NUDGE` override |
| 15 | `bin/cc-restore` (new, Python) | Port of `kitty-restart-resume.py` (main-kitty filter `:94-100`, lands wait `:113-129`, snapshot `:143-150` plus argv and bg, TERM→KILL `:253-269`, relaunch by path `:279-296`), then `boot-resume.sh --event`; `--dry-run` |
| 16 | `tests/` | boot-resume.bats (event marker, `.start`, retire filter, ledger, rounds); cc-resume-layout-desktops.bats (restore wait, map lines, fullscreen stub); classifier selftest; new cc-restore.bats. All run under `/bin/bash` 3.2 for the launchd path. |

---

## 3. Events coverage

| | (a) Terminal crash (kitty dies) | (b) Kitty restart (planned, or a deaf kitty) | (c) Mac reboot |
|---|---|---|---|
| Survives without C1 | Transcripts, /goal (on `--resume`), sid, account, cwd, branch | same | same |
| Dies | In-flight turn, background shells, Monitors, cc-await-ping watchers, subagents, teammates, workflow processes | same | same, plus /tmp |
| Trigger | launchd tick, ≤300 s; zero commands | `cc-restore --restart-kitty`, one command (deaf kitty: the tick pages it; opt-in auto) | launchd RunAtLoad; zero commands |
| Roster | heartbeat (≤5 min) ∪ tombstones (kitty K) | fresh snapshot at the kill | alarm roster (fixed) → heartbeat ∪ tombstones → registry |
| Anchor | `.ips` time, tombstone burst, or hb.start | the kill epoch | roster `.start` or tombstone max |
| Kitty | `open -n -a /Applications/kitty.app` | relaunched by cc-restore | opened by boot-resume (fixed to use the path) |
| Re-engagement | WAKE-LOST and INTERRUPTED nudge once, verified | same | same; /tmp outputs of background tasks are gone, so audits read only `<cfg>/projects` journals |
| Risk of loss | Sessions started less than 5 min before the crash and missing a tombstone | none (a fresh snapshot) | same as (a) when no alarm roster exists |

---

## 4. Time to the full fleet (32 sessions)

| Phase | Restart | Crash | Reboot | Basis |
|---|---|---|---|---|
| Detection | 0 | 0 to 300 s | login | StartInterval 300 (plist) |
| Kill and relaunch | 26 s | about 15 s | not applicable | **measured** 13:29:22 → 13:29:48 (run.log) |
| Start gate | 0 s (1.9/core at 13:31) | 0 s | 2 to 5 min | estimated from load 346 → 89 in 90 s (`boot-resume.sh:115-117`) |
| Launches | 32 × 12.7 s ≈ 6.8 min | same | same, slower under `taskpolicy -c utility` | **measured** 25 launches in 316 s (finish.log 13:38:56 to 13:44:12) |
| Fullscreen | interleaved, about 3 s per window | same | same | finish.log, 3 s spacing |
| Nudges | about 12 × (1 s plus 90 s confirmation), concurrent at R=8: about 3 min | same | same | estimated; today 10 or more sessions qualified |
| **Total** | **about 10 min** | **about 10 to 15 min** | **about 12 min after login** | estimated |

Today, measured: 14.7 min from the kill to the last real launch, and 20.5 min to a nudge that mostly did not land. Of that, about 1.7 min went to the 2.0 load wait and about 5 min to stopping and restarting the round driver.

---

## 5. Build cost (estimated, from the change list)

- **Files touched:** 6 existing (`boot-resume.sh`, `cc-resume-layout.sh`, `cc-resume-classify.py`, `alarm-reboot-prep.sh`, `reso-keepalive`, test suites) and 2 new (`bin/cc-restore`, `scripts/lib/restore-nudge.sh`).
- **Size:** about 750 lines of code (boot-resume +250, layout +80/−50, classifier +120, restore-nudge +120, cc-restore +250, one-liners) and about 450 lines of bats tests.
- **Time:** 3 dispatched sessions, about 2 days. One does the boot-resume event, roster, filter and rounds. One does the layout and the classifier. One does cc-restore and the nudge, including a live dry-run on a private kitty instance.

---

## 6. Risks

1. **C2 does not prevent loss. It recovers.** Every event still kills in-flight turns, and running background jobs re-run from scratch.
2. **The WAKE-LOST detector can misfire either way.** The naive rule flagged 24 of 32 against a native oracle of 10. A false positive nudges a session the operator had parked, which is exactly what the 08-24 ruling forbids. Ship it only after it matches the oracle.
3. **Nudge delivery is the weakest link** (1 of 31 today). The split-Enter shape is proven only through the keepalive into pane 32. Transcript confirmation is mandatory; the send-text rc proved nothing.
4. **The restore itself makes about 100 kitty remote-control calls in 7 min**, against the socket whose `accept()` error kills its thread for good (`husk-panes-2026-09-30.md:85-96`; errno unknown). A second deaf episode mid-restore would strand it. Bound every `k` call and abort to a page.
5. **Load term off during a restore** goes against the boot-storm rationale at `capacity-admit.sh:36-43`. The start gate covers it, but its 6/core value is an estimate taken from one run.
6. **Heartbeat staleness.** A crash within 5 min of a session starting can miss that session if its tombstone is also missing (13 of 32 were missing today, cause UNMEASURED).
7. **Native fullscreen switches Spaces** and steals focus once per window while the operator watches. Expected at a reboot, but noisy during a restart.
8. **Account concurrency.** 32 resumes plus about 12 concurrent recovery turns across 4 accounts; next3 was already "NOT routable (kmax-concurrency)" at 18:44:40Z (handoffs.jsonl).
9. **A live hazard from today** (§1): duplicate 3a06361f in pane 13, 4 resurrected panes, and unsubmitted prompts in composers.

## 7. Open questions and UNMEASURED items

- Why 13 of 32 SessionEnd hooks wrote no tombstone. All 13 had pane ids ≤ 24 in kitty 610.
- Whether the 30 undelivered prompts sit in the composers. Checking needs `kitten @ get-text`, which was not run under this brief's socket limit.
- Whether Claude Code sends a native "did not finish" notice for lost Monitors, Agents and Workflows, as it does for background shells.
- What the transcript's top-level `effort` field means compared with the `--effort` flag.
- Whether `kitten @ action --match id:<w> toggle_fullscreen` acts on the matched OS window or the focused one when the two differ. rc 0 on 8 of 8, plus the plan's visual check on 4.
- The right start-gate value at login. It needs one reboot measured with the gate logging load per 10 s.

Probes used: no `kitten @` calls (0 of the 3 allowed), no tmux experiment, no process signaled. Scratch files written: `/tmp/sd-c2-transcripts.txt` and `/tmp/sd-c2-time.txt`.
