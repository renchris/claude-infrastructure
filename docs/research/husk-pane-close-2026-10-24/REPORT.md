# Husk pane close: pane 289 (2026-10-24), report

Sources: the seven mapper files in `maps/` (selfclose, closer, painter, sweep, history, lifecycle, recycle), three designs, a judge's merge and three red teams. I re-checked the key citations in HEAD: `bin/cc-pane-runner:100-105, :255-349, :560-579`, `bin/cc-pane-close:405-560`, `bin/cc-pane-verdict:69-111`, `bin/cc-husk-sweep:505-612`, `scripts/pane-close-retry.sh:55-70, :270-330`. Everything was read-only. Every number is labelled: measured (with the command or mapper) or estimated (with the method).

## 1 Verdict

Pane 289 held a session that ended correctly. It became a bare shell for two reasons:
- The runner treated a temporary fullscreen-guard refusal as final and exec'd a shell. The runner is the one process that can close a pane with no socket and no gates.
- Four other components then re-judged the dead pane with four different rule sets, and they disagreed.

The fix makes `bin/cc-pane-runner` the only owner of a pane's end:
- It closes by default.
- When the guard refuses, it holds: it stays as the window's process, re-asks the guard, and exits once a close is safe.
- It keeps a shell only for a reason written into the pane's exit record.

Every fleet launch and in-place relaunch is rooted in the runner. Inner launchers return their exit code instead of exec'ing their own shells. A smaller third phase corrects the verdicts for panes that are still kept (crash keeps and operator windows).

Pane 289 needs nothing now:
- Session 0e2799a9 closed it by hand at 01:46:25Z (`bash-commands.log:216670`).
- Measured: `cc-husk-sweep --json` at 03:06Z found 0 husks among 43 panes (`it2 session list --json | jq length`).

## 2 Root causes

### 2.1 Pane 289 timeline

| UTC | Event | Evidence |
|---|---|---|
| 23:23:13 | 289 split into OS window 25 (panes_before 2) | pane-spawns.jsonl:5706 |
| 23:30:21 | Pane 287 closes; 289 is now alone in window 25 | kitty-pane-actions.jsonl:1439 |
| 23:51:57 | Custody returned by originator pane 13 | `cc_pane_custody 289 1792884203` returns `collected … return` |
| 23:53:22 | Self-close types `/exit`. The last text was "Good to close: yes" | /tmp/handoff-selfclose-289-1792885988.log |
| 23:53:36 | claude exits rc 0, claude_started true | run/pane-exit/289.json, ts 1792886016 |
| 23:53:36.772 | Runner's guard reads panes 1, FS types [4], onscreen false, so refused-fs. The runner writes a husk row, paints DONE and execs zsh | kitty-pane-actions.jsonl:1441; cc-pane-runner:322-342, then :579, then :104 |
| 23:53:38 | The self-close watcher's close hits the same refusal: STILL-PRESENT-rc70, a husk-fs alarm and a second husk row | close-attrib.jsonl:1256; kitty-pane-actions.jsonl:1442; handoff-fire.sh:11854-11918 |
| 23:55:00 | Watchdog sees dirty:138 and paints CANTTELL. Its reason=ended overwrites guard-fullscreen | lead-crash-watchdog.sh:1664-1671, :1997, :2132-2150 |
| 00:00:13 to 01:38:50 | 21 drainer attempts: 9 gate-4 "personal holds 138 uncommitted change(s)", 12 rc 124 with no output | measured: `grep 'husk pane=289 ' pane-close-retry.log`; pane-close.jsonl:394-402 |
| 00:00:14 | Recompute paints "resume 7555024a / stopped mid-task · 138 unsaved files / ▶ cc-husk-sweep --resume --yes --pane 289" | cc-pane-verdict:86-87; pane-say ts 1792886414 |
| 00:16:58 | Pane 293 split into window 25. The guard would now answer safe-not-last, but nothing asks it again | pane-spawns.jsonl |
| 01:45:55 | Drainer drops the row: "tty typed in since  — operator owns it" (first_ts empty) | pane-close-retry.log:25942; pane-close-retry.sh:279 |
| 01:46:25 | Closed by hand with `kitty @ close-window --match id:289` | bash-commands.log:216670 |

The "3 panes, not fullscreen" view came after the refusal:
- Placement added panes 293, 295 and 296 to window 25.
- A read-only CGS read at about 01:55Z still showed FS [4] with onscreen=False (selfclose map).

### 2.2 Why 289 stayed in between

1. **The runner turns a temporary refusal into a permanent shell.** The refusal branch writes a husk row and returns "keep". `_fallback` then execs `${SHELL:-/bin/zsh} -l -i` (cc-pane-runner:322-342, :579, :104). The guard itself is correct: emptying a fullscreen last pane crashes kitty (kitty-fullscreen-guard:4-9).
2. **The code calls refused-fs "a fixed fact"** (handoff-fire.sh:1875, :11818; it2-kitty:88, :1665). So the watcher stops after one attempt (:11854-11857).
3. **The hand-off re-judges the session against the whole checkout.**
   - Gate 4 runs `git status --porcelain | grep -c .` over the shared cwd (cc-pane-close:508-512).
   - Measured (closer map): the session's own 2 files were clean (`session_dirty_mine` rc 1), and 562 of 563 dirty paths (counted with `-uall`) predate the session.
   - `--allow-dirty` is never carried: hf_husk_row :2251 does not record it, and grep finds 0 readers.
   - Gate 4 runs before the guard (:519-520), which hid refused-fs from the drainer's ⌘W hold arm (pane-close-retry.sh:315).
4. **The painter inverts what the closer said.**
   - cc-pane-verdict:86-87 maps "uncommitted change" to RESUME. But the closer only reaches gate 4 after gate 3 has found the session meant to end (cc-pane-close:489-507).
   - The painted `--resume` does nothing: the sweep skips COLLECTED panes (cc-husk-sweep:607), and the sweep said COLLECTED (:563).
5. **No single owner.**
   - The runner and the watcher both tried to close the pane and both queued husk rows within 2 s.
   - The watchdog overwrote the reason.
   - The drainer finally dropped the row and left the false RESUME on record. Measured: `jq -r .state run/pane-verdict/1881-289.json` returns RESUME.

### 2.3 Why the class recurs

- **A kept shell is the fail-closed default.**
  - Seven tails exec a shell: cc-pane-runner:104; reso-resume-one:236 and :1216; lr-fire-resume.sh:2304; pane-successor.sh:240 and :341; kitty-split-cwd.sh:38.
  - Three launch wrappers end in `|| exec zsh -i`: boot-resume-launch.sh:258; cc-resume-layout.sh:1053 and :1359.
  - The rule behind them is at boot-resume-launch.sh:240-242.
- **The end state is worked out again, never recorded.** Each of these has its own rules: the watcher, the runner, cc-pane-close gates 3-4, the sweep's verdict_of plus its overrides, the watchdog's pane_verdict_text, and recompute. The session's own decision is never treated as the authority.
- **Facts read at the moment of death are frozen.** Nothing re-reads them when the window changes.
- **A second husk family comes from lr-fire-resume.**
  - It never closes after rc 0 (:2276-2304).
  - The watchdog takes the tty from the claude pid (:2299), which under `expect` is an inner pty. It wrongly concludes "closed", so there is no paint, no husk row and no closer.
- **Each round patches the last fixture.**
  - The 08-04 rule against checking dirt across the whole tree was fixed only in reap-guard (5cd17f5da), then rebuilt as gate 4 (d150099dd).
  - Measured (history map, git log grep): 139 husk-related commits since 2026-07-20.

## 3 Live prevalence

| Metric | Value | How |
|---|---|---|
| Live husk panes | 0 of 43 | measured: cc-husk-sweep --json + it2 session list, 03:06Z |
| Latent husks (registered tty ≠ window tty) | 7: panes 2, 5, 7, 47, 67, 11, 12 | measured, recycle map, about 01:55Z |
| Stale paint records | 11 in run/pane-verdict | measured: ls \| wc -l; all 11 are gone panes (sweep map) |
| Self-close episodes, 14 days | 82; 16 STILL-PRESENT; 14 husks, all fullscreen last-pane refusals | measured, selfclose map |
| rc70 self-closes that became husks | 10 of 10 | measured, selfclose map |
| Runner guard verdicts since 10-15 | 390; 36 refused (13 refused-fs, 22 kitten-failed, 1 refused-unknown), each became a shell | measured, lifecycle map (jq) |
| lr-fire-resume "ordinary shell" paints since 10-19 | 7; 6 real husks; 5 of 6 had said "Good to close: yes" | measured, recycle map |
| Panes with pane-close rows in this kitty generation | 39, all should have closed | estimated, sweep map |
| rc70 husk lifetime | median about 1h28m; 289 was 1h53m; 165 was 8h17m | 289 and 165 measured; median estimated over 8 episodes |
| Gate-4 refusals ever | 9 rows, all pane 289 | measured: jq on pane-close.jsonl |
| Drainer rc 124 | 25 attempts on 6 panes | measured, closer map |
| Painter vs sweep | 1 of 1 RESUME paints was COLLECTED in the sweep; 5 of 12 watchdog "killed" paints had said "Good to close: yes" | measured, painter map |

## 4 The fix

The invariant: a fleet pane is in exactly one of four states.
- **Running.**
- **Closed.**
- **Kept:** a shell, with the reason recorded in `pane-exit/<wid>.json` as `tail=kept:recycle|crash|kill-switch|not-a-session|operator|fallback`.
- **Held:** only the last pane of a native-fullscreen window. A held pane is owned, labelled honestly, and closes itself.

### Phase 1: hold instead of a shell, one closer (ships alone)

**1.1 Runner refusal branch** (cc-pane-runner `_close_pane` :322-342). When `CC_PANE_HOLD` is not 0:
- write tail=held:guard-fs or held:guard-unreadable;
- paint `_verdict --state "${_PV_STATE:-DONE}" --guard held|unreadable`;
- enter the hold.

`CC_PANE_HOLD=0` restores today's behaviour, so it is the rollback.

**1.2 The hold.** The runner execs `exec -a cc-pane-held /bin/bash /dev/fd/3 3<<<"$_HOLD_BODY"`. The body is the `declare -f` text captured in memory when the runner starts, so it is never re-read from disk. Its inputs travel in env.
- Measured (`/tmp/husk-report-probe/p.sh`, /bin/bash 3.2.57): comm and command read `cc-pane-held /dev/fd/3`, with no "claude" in argv. A TERM trap kept it alive, and it exited 0 only through the sanctioned path.
- The body starts with `set +u`.
- Signals:
  - INT, QUIT, TSTP and TERM go to a handler that logs and continues. A handler is used rather than SIG_IGN because handlers reset on exec.
  - HUP exits 0, because kitty is already closing the window.
  - An EXIT trap execs a login shell with tail=kept:fallback unless the sanctioned flag is set.
- Loop: run the guard with `--mode refuse --scope pane --tool cc-pane-hold`, resolved as at :303-313.
- Release: two rc-0 reads at least 10 s apart, then tail=closed and `exit 0`.
- Backoff: 5 s rising to 60 s for refused-fs; 30 s rising to 300 s for unreadable.
- Repaint and log only when the verdict changes.
- No tty reads. The banner reads "done · closes itself when this window gets another pane · ⌘W closes it now".

**1.3 Exit record** (`_pane_exit_record` :426, contract :377-443). Add tail, tail_ts, pid, lstart, kitty_pid, and root_pid. root_pid is found by walking $PPID while the comm is login or kitten, as pane-successor.sh:310-317 does.
- Why: measured with ps, all 8 sampled runners have a `/usr/bin/login` parent.
- A reader trusts the record only when either:
  - kitty @ ls window.pid equals root_pid and kitty_pid matches; or
  - kitty is deaf, and `ps -p pid -o lstart=,comm=` matches the recorded values.

**1.4 One closer.**
- The watcher polls the record for up to 20 s before its close loop (handoff-fire.sh:11831).
- If tail is closed or held:*, it logs and skips hf_close_pane, the husk-fs alarm (:11900) and hf_husk_row (:11918).
- Panes with no record take today's path.
- Reword the "fixed fact" comments at handoff-fire.sh:1875 and :11818, and it2-kitty:88 and :1665.

**1.5 Readers.**
- These already stand down when they see the cc-pane-held name: the drainer's shell_only (:421), the watchdog's pane_procs_are_shells (:1640, so no paint at :2045), and cc-pane-close gate 2.
- cc-husk-sweep does not, because has_claude_under (:206-219) matches `*claude*`. Add a HELD verdict before :547 that `--resume` (:601-610) never selects, and test the argv[0] basename instead of the whole line.

**1.6 ⌘W without a dialog.** In kitty-confirm-close `is_busy` (:250-258), a pane is not busy when cc-pane-held is present and every other foreground entry is the window root or a login/shell name. Measured (red team 3): kitty lists the root `/bin/zsh` in 10 of 10 runner windows.

**1.7 No false RESUME.**
- The gate-4 refusal line (:511) names the gate-3 fact.
- Recompute (:86-87) maps:
  - close=yes or a self-close stamp to DONE with "stuck";
  - teammate-only or abandon-only to CANTTELL;
  - never to RESUME.
- `--resume` is printed only when the sweep would select that pane.
- Add a `held` text next to :96-101.

**1.8 Teammate signal exits.** A teammate verb (`--agent-id`) that exits 143 or 137 goes to `_close_pane` (:257-278) instead of `_kept_line`. Evidence: panes 141 and 142 both exited 143 at the same second on 10-23.

**Phase 1 deletes from the default path:**
- the runner's guard-* husk rows and their shell path (:330-341);
- the watcher's outside close, alarm and husk row for runner panes;
- the uncommitted → RESUME mapping.

### Phase 2: one tail, every pane rooted in the runner

**2.1** `_launch` (:569) exports `CC_PANE_RUNNER_PID=$$`.

**2.2 lr-fire-resume.sh:2253-2304 and reso-resume-one:1131-1216.**
- Under the runner, using the ancestor walk from pane-successor.sh:244-256 (up to 6 hops): run `cc_pane_successor_exec "$claimed" 0`, or `exit "$rc"`. Delete rr_close_on_clean_exit and the "ordinary shell" tail.
- When an operator typed the launcher (not under the runner): keep the shell (ruling 337e100f5c71).
- First, audit both launchers so neither returns 0 on a refusal or capacity path. Add one test per refusal exit code.

**2.3 Root every launch in the runner argv** (handoff-fire.sh:1326, it2-kitty:1358-1363):
- boot-resume-launch.sh:258;
- cc-resume-layout.sh:1053 and :1359;
- kitty-split-launch.sh:146-149;
- lr-lib.sh:1343-1345: refuse instead of launching bare.

Retire the rule at boot-resume-launch.sh:240-242. Recycle stays covered by kept:recycle (cc-pane-runner:295) and by staged successors.

**2.4 Re-root in-place relaunches.** Each of these runs `[ -x "$R" ] && exec env CC_PANE_CMD=<line> CC_PANE_CMD_INTERACTIVE=1 /bin/bash "$R"` at the root shell:
- the typed recycle line (handoff-fire.sh:3769-3785);
- `--relaunch-at-shell` (:14136-14234);
- cc-husk-sweep's typed resume (:612-625);
- the precmd successor (pane-successor.sh:279-284, :232-241).

**2.5 Placement** (pane-placement.sh `_ccp_decide` :114-170). A window holding only a held pane:
- counts 0 toward the cap (:126-131);
- ranks first in step 2 (:155-165), ahead of minting a new window;
- takes at most one placement per hold.

Rig containment is unchanged.

**2.6 Close lock.** A `(kitty_pid, os_window_id)` mkdir lock in kitty-fullscreen-guard, held from verdict until the window reads not-found. The runner close, the hold and zshexit all use it.

**2.7 Tests.** Add a launch-site lint. Invert the SURVIVABILITY pins (kitty-recovery-launch.bats:459-505, handoff-recycle-pane-survives.bats:528-570).

**Phase 2 deletes:**
- about 52 lines of lr-fire-resume tail;
- about 86 lines of reso-resume-one close and tail;
- three `|| exec zsh -i` wrappers;
- the lr-lib bare fallback;
- the survivability rule;
- pane-successor.sh:236-240's trailing shell.

### Phase 3: truthful verdicts for what is still kept

**3.1 Final-turn close reader** (a prerequisite for 3.2 and 3.4). It replaces transcript_facts (:342-367), pane_last_close (:1677-1711) and facts_of (:452-507).
- "yes" counts only when it is in the last main-chain assistant text, with no later user record or tool_use, and no open tool window.
- This also fixes a live bug: a stale yes in a clean worktree passes gate 3 today.
- Measured by red team 1: 5 sessions in 4 days had later prompts and calls after their last yes.

**3.2 `session_work_at_risk`** (session-writes.sh), bounded to 5 s with `GIT_OPTIONAL_LOCKS=0`.
- Order: session_dirty_mine; then dirt_unreachable_by_session with an end_epoch argument (open windows end at end_epoch; files modified after it count as foreign only when bg=0); then dirt_edited_by_live_peer, as in completion-assert.sh:979-980. rc 2 means unknown.
- It replaces cc-pane-close:509-512, sweep work_of (:507-514) and watchdog pane_work_state (:1664-1671).
- Refuse only on mine or unknown, naming the session's own count.
- The unlanded check keys on origin/HEAD or the default branch, never origin/main.

**3.3 Record the session's decision.**
- record_close_succession (handoff-fire.sh:10200-10217) records allowDirty and workAtClose.
- Gate 4 honours allowDirty.
- hf_husk_row (:2251-2259) passes the sid.
- Needed because: 7555024a had bg=1, an open window and a write by another session after it exited, so 3.2 alone returns unknown for it.

**3.4 Watchdog.** The crash branch (:2005-2030) uses 3.1 (fixes D3). The RECYCLE branch reads custody (fixes D1).

**3.5 pane-close-retry.sh.**
- Read first_ts before pcq_remove (:279).
- When the operator takes a pane over, repaint it neutral and delete its paint record.
- Reap paint records for panes that no longer exist.

**3.6 Census as its own launchd job.** The drainer exits at :64 when its queue is empty, so the census cannot live there.
- It takes its own bounded `kitty @ ls`.
- It covers only runner-rooted windows.
- It pages once for a shell nobody owns after 2 ticks, and for any hold older than 6 h.
- kept:* exemptions expire.
- If kitty is deaf, it falls back to exit records plus `ps -t`.

**Deferred:** lib/pane-fate.sh; transcript resolution from records (the 11.05 s glob behind rc 124); the watchdog's outer-tty identity.

**Size (estimated from the judge's sizing plus the red-team additions):** Phase 1 about +170 lines in 7 files; Phase 2 about +50/−200; Phase 3 about +160/−70; tests about +450.

**Estimated outcome for 289:** it holds at 23:53:36Z and the watcher stands down. It releases at about 00:17:10-00:18Z, after 293 joins. Measured actual: 1h53m, closed by hand.

### Tests

How to run them:
- under /bin/bash 3.2, with `/bin/bash -n`;
- each test RED on HEAD, and a named mutant must fail it;
- serially;
- the ratchets: test-afunix-path-lint, test-hermeticity-lint, bats-assert-liveness-fix and shellcheck.

**Pane 289 replay** (`tests/pane-289-replay.bats`). One fixture:
- a shared checkout (no remote, master) with 138 dirty paths that belong to other sessions and predate the session, plus one write after the exit;
- a transcript whose own 2 paths are clean, ending in "Good to close: yes", with bg=1 and an open final window;
- a custody return and a stamp with allowDirty.

Three arms:
- **A, runner path.** A claude stub exits 0 and the guard stub returns 3, 3, 0, 0.
  - Assert: exit 0; tail goes held:guard-fs, then closed; comm is cc-pane-held; no husk row; no RESUME, "stopped mid-task" or `--resume` anywhere; the git stub is never called.
  - Mutant: a hold that exits on rc 3.
- **B, non-runner path.**
  - `cc-pane-close --dry-run`: WOULD CLOSE.
  - Recompute of the old 138 line: DONE, with no `--resume`.
  - Sweep: COLLECTED or DONE.
  - Watchdog: DONE.
  - Mutant: restore :86-87.
- **C, boundary.** No stamp plus SIGTERM gives CANTTELL: held, never RESUME, never closed.

**Phase 1:**
- Hold behaviour: 3,3,0,0 exits 0; rc 4 keeps waiting; `CC_PANE_HOLD=0` takes the old path; a forced error gives kept:fallback.
- A script(1) pty test: ^C, ^\, ^Z and TERM do not end the hold; HUP does; a mutant with no traps fails.
- A hold survives the runner file being replaced mid-hold.
- `CC_PANE_HOLD=0` is set in the no-command-closes and exit75-closes suites.
- The watcher stands down with a login-wrapped fixture.
- The queue and watchdog stand down on a cc-pane-held process.
- The sweep reports HELD.
- ⌘W closes with the two-entry foreground list.
- A teammate exit 143 under refusal holds.
- The no-command path paints NOTHING.

**Phase 2:**
- lr-fire-resume and reso-resume-one hand back their exit code.
- The successor claim adds no trailing shell.
- Relaunch lines start with `exec env CC_PANE_CMD=`.
- The launch-site lint.
- Placement fills held windows first.
- The two-closer lock.
- The inverted pins.

**Phase 3:**
- A stale yes followed by SIGTERM: refuse.
- A crashed teammate with its own uncommitted edits: refused.
- A live peer's edits do not count as the session's own.
- A lint for `status --porcelain` and `origin/main..HEAD`.
- Census silences and pages.

## 5 Red-team breaks and answers

| # | Break (severity) | Answer |
|---|---|---|
| R1 | A signal kills the bash hold, login exits, and kitty crashes (critical; RT1, RT2) | Handlers for INT, QUIT, TSTP and TERM; HUP exits; EXIT-trap fallback. The TERM case is measured. INT must be proven in the pty test, because the probe ran in the background, where INT is ignored. SIGKILL is the same as today's kept zsh. |
| R2 | Re-exec from disk fails at the worst moment (medium) | The body runs from memory via /dev/fd/3 (measured), with `set +u` and the EXIT fallback. |
| R3 | The trust rule can't match, because the window pid is login (high; RT2, RT3) | root_pid plus lstart, and ps when kitty is deaf. Measured: 8 of 8 runners have a login parent. |
| R4 | The keypress read fails with EIO in interactive mode; the sweep's Ctrl-U wakes the hold (medium) | No tty reads; ⌘W only; the sweep's HELD verdict ships in Phase 1. |
| R5 | The "all foreground is cc-pane-held" predicate never holds (medium) | The predicate in 1.6. |
| R6 | argv contains "claude" (low) | argv is `cc-pane-held /dev/fd/3`. |
| R7 | A gate-4 refusal does not prove the session meant to end (teammate, abandon) (medium) | 1.7 names the gate-3 fact. |
| R8 | A stale yes closes a session killed mid-task (high) | 3.1 ships first. |
| R9 | bg=1 leaves 7555024a "unknown" (medium) | 3.3 records the stamp. A bg>0 session with no stamp stays CANTTELL (arm C). |
| R10 | The census never runs (high) | Its own launchd job (3.6). |
| R11 | Operator shells page; a stale kept:* exempts a pane forever (low) | Scoped to runner-rooted windows; exemptions expire. |
| R12 | Relaunches are not rooted in the runner (medium) | 2.4. |
| R13 | A teammate exiting 143 leaves a shell (medium) | 1.8. |
| R14 | Two closers race and both see "not last" (low; already measured today: 11 same-count pairs within 5 s) | Two reads 10 s apart, the per-window lock, one placement per hold. The residual remains until the guard can check and close in one kitty call. |
| R15 | Wrong banner or state (low) | Repaint on change; `${_PV_STATE:-DONE}`. |
| R16 | A live peer's edits are counted as the session's own (low) | Chain dirt_edited_by_live_peer. |
| R17 | Polling while kitty is deaf (low) | 30 s to 300 s backoff; log only on change. |

**Residual risks:**
- An off-screen fullscreen last pane stays held until something is placed in its window or the operator presses ⌘W (the 363/476 shape). It is labelled honestly and paged at 6 h, but it is still visible.
- SIGKILL of a held pane crashes kitty, the same as today.
- Running panes, including the 7 latent ones, keep their old code until relaunched.

## 6 Rejected alternatives

- **B (pane-fate library) as the primary fix.** It removes none of the 14 fullscreen husks or the 6 lr-fire-resume husks. It would be a 260-line single point of failure, and its git status cost feeds rc 124. Deferred.
- **C alone.** Its exit-130 key branch can empty a fullscreen last pane. It relies on a sentinel file. It leaves nine shell tails. Its rename mechanism is adopted.
- **claude as the window root.** That crashes kitty when the last session in a window ends.
- **L1 (move the pane, or leave fullscreen).** A move empties the window. Leaving fullscreen moves the operator's Space (kitty-lastpane-move-2026-10-19 §1). The guard never relaxes for off-screen windows.
- **L2 (drainer re-test) and L3 (carry --allow-dirty in the husk row).** Superseded by the hold. L3 survives only as the stamp field in 3.3.
- **L5 (placement ignores husks).** Replaced by filling held windows first.
- **A keypress-to-shell hold.** EIO in interactive mode, and it makes ^C a crash vector.
- **SIG_IGN.** It is inherited across exec.
- **Dropping gate scoping.** Crash keeps and non-runner panes still reach gate 4.
