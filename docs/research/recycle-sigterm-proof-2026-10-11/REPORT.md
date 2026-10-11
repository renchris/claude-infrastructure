# SIGTERM proof for REPORT fix 10 — Claude Code 2.1.293, 2026-10-11

Wave W6 of `docs/plans/RECYCLE_KITTY_FIXES.md`. Measurement and doc only; no code changed.

## Answer

**Yes, with one exception: build fix 10.** A SIGTERM to the pinned claude pid of a session at rest
ends it the way `/exit` does on every axis a recycle depends on. In 9 of 9 at-rest runs claude
exited 143, the transcript was appended and never truncated, the background shell was stopped, the
staged successor was claimed with nothing typed and no revoke, the real crash watchdog logged
`RECYCLE deliberate-teardown`, and the wrapper kept the window.

**The exception: SessionEnd hooks ran in only 4 of the 9 at-rest runs.** In the other 5 claude was
gone 1.35-1.44 s after the signal with no SessionEnd hook started. The cause is not identified
(two hypotheses were tested and refuted, below). Fix 10 must therefore not depend on any
SessionEnd side effect. Nothing the recycle needs was lost in those 5 runs: the successor was
still claimed and the watchdog still read RECYCLE.

**Two changes are needed to the implementation in `1ac887d20`** (branch `fix/recycle-gaps-kitty`,
unlanded), which this proof was asked to check: raise `HF_EXIT_SIGNAL_GRACE_S` above Claude Code's
own shutdown bound, and do not stand the inbox watcher down before the signal. Details in
§ Recipe.

## Verdict per assertion

| # | Assertion | Verdict | Evidence (at rest, n=9) |
|---|---|---|---|
| 1 | Exit code is 143 | **PASS** 9/9 | close-record `exit_code:143, signal:"15"`, `sig_reached_wrapper:""` (the signal reached claude only) |
| 2a | Transcript holds every record up to `end_turn` | **PASS** 9/9 | pre-signal copy is a byte prefix of the post-signal file; 0 unparseable lines; 4-10 records appended |
| 2b | SessionEnd hooks ran | **FAIL** 4/9 | ran in r3, r7, r8, r9; not started in r1, r2, r4, r5, r6 |
| 3 | Background shell is gone | **PASS** 9/9 | both pids of the `sleep 1800` shell dead 5 s after exit; the transcript gains the task's `queue-operation` notice |
| 4 | Staged successor is claimed by the consumer | **PASS** 9/9 | `<tty>.cmd` renamed `<tty>.claimed.<wrapper pid>`, no `.revoked`; the successor ran in the same tty and window |
| 5 | Not classed a crash once a marker exists | **PASS** 9/9 | real watchdog ledger: `RECYCLE deliberate-teardown`; control with no marker: `CRASH external-sigterm` |
| 6 | Wrapper does not close the window on 143 | **PASS** 9/9 | window still present after exit; `cc-close-attrib` printed `session ended (rc 143) — running the staged successor` |

Mid-turn (the thing not to do), n=1: the same 143, claim and RECYCLE verdict, but the turn is
destroyed. See § Mid-turn.

## Setup

- Machine: 10 cores, 1-minute load 440-537 during the runs (44-54 runnable per core), about 46
  concurrent claude processes. This is the F1 regime the fix is meant to survive.
- Each run created one kitty tab with `kitty @ launch --type=tab --keep-focus` and closed it with
  `kitty @ close-window --match id:<its own id>`. Windows 251, 253-263. No other pane was typed
  into, signalled or closed. Nothing was typed into the probe panes either: the prompt rode on argv.
- Launch line (`evidence/r1/launch-line.txt`): `zsh -l -i -c 'claude --session-id <uuid> "<prompt>"; print rc; sleep 300'`.
  The real `claude()` launcher routed the account and ran `bin/cc-close-attrib` around
  `~/.claude-293/.../claude` (Sonnet 5.5, effort low). The trailing `sleep 300` keeps the tab alive
  so a close initiated by the wrapper would be visible.
- Fixture at rest: last assistant record `stop_reason:end_turn`, then `stop_hook_summary` and
  `turn_duration`, transcript size stable for 12 s, and one background shell (`sleep 1800`) running
  as a child of claude.
- Then, in order: copy the transcript; stage a successor with `lib/pane-successor.sh`
  `cc_pane_successor_stage` (a `.cmd` that writes a file, meta naming a live watcher process with
  its lstart in `TZ=UTC LC_ALL=C` form and `pane` = the kitty window id); write the teardown marker
  in the shape `scripts/handoff-fire.sh` `write_teardown_marker` emits for a recycle (sid key,
  `mode:"recycle"`); re-read the pid's lstart; `kill -TERM <pid>`; poll with no KILL escalation.
- Harness: `evidence/harness.sh.txt`. Per-run raw output: `evidence/<run>/RESULT.txt`, `harness.log`,
  `close-record.json`, `stage-post.txt`, `successor-ran`, `post-tail-types.txt`,
  `debug-shutdown-excerpt.txt` (r2 onward, from `--debug-file`).

## Raw results

| Run | Window | Exit | Latency (s) | Transcript lines | SessionEnd | Claimed | Watchdog |
|---|---|---|---|---|---|---|---|
| r1 | 251 | 143 | 1.354 | 50 → 55 | no | yes | RECYCLE |
| r2 | 253 | 143 | 1.439 | 46 → 51 | no | yes | RECYCLE |
| r3 | 254 | 143 | 4.932 | 63 → 67 | yes (7 hooks + probe) | yes | RECYCLE |
| r4 | 255 | 143 | 1.380 | 54 → 61 | no | yes | RECYCLE |
| r5 | 256 | 143 | 1.350 | 54 → 64 | no | yes | RECYCLE |
| r6 | 257 | 143 | 1.364 | 54 → 64 | no | yes | RECYCLE |
| r7 | 258 | 143 | 4.032 | 55 → 64 | yes (7 hooks) | yes | RECYCLE |
| r8 | 259 | 143 | 4.957 | 54 → 63 | yes (7 hooks) | yes | RECYCLE |
| r9 | 263 | 143 | 5.884 | 59 → 63 | yes (7 hooks + probe) | yes | RECYCLE |
| m2 (mid-turn) | 261 | 143 | 5.221 | 33 → 37 | yes | yes | RECYCLE |

r7 and r8 ran with the probe session's inbox watcher stood down first, and r7's signal therefore
landed on a turn that had just started (§ SessionEnd). The watchdog column is the real daemon's row
in `~/.claude/logs/claude-crashes.jsonl` (`evidence/real-watchdog-ledger.tsv`), not only the
`--classify` entrypoint.

### 1. Exit code

`evidence/r1/close-record.json`: `"exit_code":143,"signal":"15","sig_reached_wrapper":"","record_state":"closed","successor_claim":"…/ttys057.claimed.93486"`.
The same in all ten runs. The pane printed Claude Code's own `Resume this session with: claude --resume <sid>`
banner before the successor ran (`evidence/r1/screen-post.txt`).

The status the pane's shell sees is **0, not 143**, when a successor is claimed: `cc-close-attrib`
execs the successor, so the launcher returns the successor's status (`shell_rc=rc=0` in every
`RESULT.txt`). Anything that needs the 143 must read the close-record.

### 2a. Transcript

For every run, `head -c <pre size> post | cmp - pre` is equal and every line of the post file
parses. The records the shutdown appended in r1: `bridge-session`, `cost-state`, `last-prompt`,
`cost-state`, `queue-operation` (the background task's kill notice, timestamped at the signal).

### 2b. SessionEnd hooks

Evidence a run's hooks ran: a `Session ended sid=<sid> reason=other` row in
`~/.claude/logs/sessions.log`, the pane's `cc-registry` row removed, and from r2 onward the
`SessionEnd:other [<hook>] completed with status 0` lines in the debug log
(`evidence/r9/debug-shutdown-excerpt.txt` shows all 7 configured hooks plus the probe hook).
Evidence they did not: none of those, the registry row still present, and a debug log that ends
at `Hook SessionStart:startup (SessionStart) error: status code 137` with claude gone 0.3 s later
(`evidence/r4/debug-shutdown-excerpt.txt`).

What is and is not established:

- The binary's SIGTERM handler calls the same `shutdown()` as every other exit, and that function
  calls `executeSessionEndHooks` with reason `other` and a budget of
  `max(1500 ms, min(longest SessionEnd hook timeout, 60 s))`, which is 10 s with this machine's
  settings (read from the 2.1.293 binary at offsets 192,234,133 and 195,031,506). So the skip is
  not a signal path that omits the call.
- **Refuted: the probe hook flag.** r5 passed `--settings` with a SessionEnd hook and skipped; r9
  passed it and ran.
- **Refuted: a live inbox watcher forces the skip.** All 5 skipped runs had the 4-hour
  `mailbox-wake-arm.sh` → `cc-await-ping` SessionStart hook alive as a child of claude, and r3
  (no watcher) ran its hooks. But r9 and m2 had the watcher alive, logged the same `status code 137`
  line, and ran every hook.
- **Not measured: whether a typed `/exit` skips them too.** The brief forbids typing a slash
  command into a probe pane. The field rate for typed-`/exit` recycles is 34 of the last 40
  `recycle-engaged` predecessors with a `Session ended` row (`evidence/typed-exit-sessionend-baserate.tsv`),
  so `/exit` is not at 100% either, and the two rates are not comparable (different sessions,
  different loads).

What a skipped SessionEnd leaves behind, measured in r1: the pane's `cc-registry/<pane>.json` row
still names the dead session (the successor's SessionStart overwrites it), `watchdog/cp-<sid>.count`
remains, no `sessions.log` row, and the session index is not closed. The crash watchdog takes its
"LEAD CRASH detected" path instead of "pid file gone" and still classes the death RECYCLE
(`evidence/r1/real-watchdog.txt` against `evidence/r3/real-watchdog.txt`).

### 3. Background shell

`evidence/r1/tree-pre.txt` lists the `zsh -c … sleep 1800` shell and its `sleep` under claude;
`RESULT.txt` line A3 has `bg_pids_alive_after=''` in all ten runs.

### 4. Successor claim

`evidence/r1/stage-post.txt`: `ttys057.claimed.93486` and `ttys057.json`, no `.cmd`, no `.revoked`.
The claimant pid is the `cc-close-attrib` wrapper. `evidence/r1/successor-ran`:
`SUCCESSOR-RAN label=r1 tty=/dev/ttys057 kitty_window=251 at 2026-10-11T06:40:44Z`, 3 s after the
signal. The claim does not depend on SessionEnd: it happened in all 5 runs that skipped the hooks.

### 5. Crash classification

Reader: `hooks/lead-crash-watchdog.sh` `classify_death`. Exit 143 makes `map_exit_class` return
no class, so the close-record arm falls through to arm 1.5, which accepts a `<sid>.json` marker
younger than 30 minutes in `~/.claude/watchdog/teardown/` whatever its mode.

- With the marker: `RECYCLE deliberate-teardown`, from both `--classify <sid> <pid> <epoch>` and the
  live daemon (10 of 10 ledger rows, `exit_code:"143"`).
- Control, same death, `CC_TEARDOWN_DIR` pointed at an empty directory: `CRASH external-sigterm`.

The sid key alone is enough for a 143. The pid key `1ac887d20` adds is harmless and unused on this
path: `retired_by_desk` reads it only for `mode:"teardown"`, and only a 137 reaches that arm.

### 6. Window close

- `cc-close-attrib` `_cca_close_pane` requires `CC_CLOSE_PANE_ON_EXIT=1` **and** exit 0. The pane
  environment had it unset and the code was 143. Observed: the window was still listed by
  `kitty @ ls` after claude exited, with the tail command running, in all ten runs.
- `bin/reso-resume-one` `rr_close_on_clean_exit` returns "keep the shell" for any status but 0.
  Its expect program derives the status from `wait`: a child that **exits** 143 yields 143, and a
  child **killed** by a signal yields 1. Measured offline with the same Tcl
  (`spawn sh -c {exit 143}` → 143; `{kill -TERM $$}` → `CHILDKILLED SIGTERM` → 1; `{exit 0}` → 0).
  Claude handles SIGTERM and exits 143, and `cc-close-attrib` re-exits with that code, so the
  resume wrapper sees 143 and takes the successor arm.
- **Not measured live: the expect resume chain.** `reso-resume-one` refused the probe at its
  capacity gate (`load 444.39 on 10 cores = 44.44/core > ceiling 2.0/core`, exit 9,
  `evidence/e1/`). The gate was not overridden. The two bullets above are code read plus the offline
  Tcl check; `proof-sigterm-2.1.293.md` beside the root-cause report reached the same reading.

## Mid-turn: what not to do

m2 sent the SIGTERM while a foreground Bash tool call was running. Claude exited 143 in 5.2 s, the
tool's process was killed, the successor was claimed, and the watchdog read RECYCLE. The transcript
is intact as a file but ends on an assistant `tool_use` with no `tool_result`
(`unanswered tool_use: 1`): the turn's work is lost and nothing marks it as interrupted. The signal
gives no warning and no dialog, so the at-rest proof is the only guard. Do not send it mid-turn.

## Recipe for fix 10

1. Prove the transcript at rest with the existing reads, and run the background-work census. The
   signal skips the "background tasks are running" dialog and kills them.
2. Stage the successor with `cc_pane_successor_stage` and confirm it is ours. Write
   `watcher_lstart` in `TZ=UTC LC_ALL=C ps -o lstart=` form.
3. Pin the claude pid by pid and lstart from the pane's process-tree closure. Never use
   `kitty @ signal-child`.
4. Write the recycle teardown marker keyed on the session id immediately before the signal.
5. Re-read the lstart, then `kill -TERM <pid>`. SIGTERM only: never SIGINT (exit 0 reads as a clean
   exit), never KILL (137 reads as `killed-oom-or-force` unless the marker is `mode:"teardown"`).
6. Wait for the pid to go. Measured 1.35-5.9 s at 44-54 runnable per core.
7. Type nothing. The consumer claims the stage on any exit code.

`1ac887d20` implements steps 1-7 this way. Two changes:

- **`HF_EXIT_SIGNAL_GRACE_S` defaults to 10 s, which is shorter than Claude Code's own shutdown
  bound.** `shutdown()` arms a failsafe of `max(5 s, SessionEnd budget + 5 s)` = 15 s here, and
  the SessionEnd stage alone may use 10 s. A run that needs 11 s is reported
  `exit-signal-ignored`, the watcher is disarmed, and the commit's own hold text says what follows:
  "Should it exit later, its pane returns to a shell with no relaunch". That is a strand caused by
  the hold. Once SIGTERM is delivered the exit is certain and bounded by the failsafe, so wait at
  least 30 s and keep the successor staged while waiting. The longest measured here was 5.9 s; the
  root-cause report cites 88 s for the exit flush at load 221.
- **Do not stand the predecessor's inbox watcher down before the signal.** `cc-await-ping --stand-down`
  makes the `asyncRewake` SessionStart hook exit 2, and Claude Code starts a turn on it. r7:
  stand-down at 06:53:56, a `user` record at 06:53:59.555, signal at 06:54:00. The at-rest proof
  was stale by the time the signal landed. Leave the watcher alone; the shutdown kills it.

Two things for the implementer to know, neither a blocker:

- The pin reads `~/.claude*/sessions/<pid>.json`. That row existed for the probe (r9:
  `{"pid":73745,…,"kind":"interactive","status":"shell"}`) and for 36 of 40 live tty-attached claude
  processes at the time of the census (`evidence/sessrows.sh.txt`). The other 4 would fall back to the
  typed `/exit`, which is the commit's designed behavior.
- Treat SessionEnd as best effort (§ 2b). If a recycle needs the registry row cleared or the
  session index closed, `handoff-fire.sh` has to do it itself.

## Not done

- No `/exit` control run (typing a slash command into a probe pane was out of bounds).
- The expect resume chain was not exercised live (capacity gate refusal, not overridden).
- The cause of the SessionEnd skip is open. The debug logs of the five skipped and four clean
  runs are summarized in `evidence/<run>/debug-shutdown-excerpt.txt`.
- `adopt.json` exit-handoff behavior under a signal was not examined.
