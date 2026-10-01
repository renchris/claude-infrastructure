# C4: hybrids, with cost

Research dossier, 2026-10-01, candidate C4. Read-only apart from this file. Experiments ran only on
private tmux servers (`-L sd-probe-c4-{on,off,pace}`) with `sh`/`sleep` as dummy panes. All three
were killed and their socket files removed (`tmux -L … ls` => `no server running`; `ls
/private/tmp/tmux-501 | grep -c sd-probe-c4` => `0`). The scratch copy of kitty `screen.c` was deleted.
I made 0 of 3 allowed `kitten @` calls, signaled nothing, and did not launch `claude`. Every number
is labeled **measured** (with its command) or **estimated** (with its method). UNMEASURED means not
checked.

## Answer

**Build H1 now: C2's restore with every skeptic fix, plus C3's safe prevention items, plus a
recovery nudge that the launcher types into its own child at launch. Keep a session layer (H2, tmux)
as a gated second phase, and only after a one-session pilot and an operator ruling on scrollback.**

- **Why H1 first.** It is the only hybrid that covers all three events within days. It does not
  change how the operator works in kitty, and it needs no agent to act on a live session.
  - A reboot is survivable only from disk, so every hybrid needs C2's resume anyway.
  - Of the 2026-10-01 failures, H1 fixes all six: shed-the-tail, fullscreen, nudge delivery,
    resurrections, stacked keepalives and missing tombstones. It also removes the likely trigger
    of the forced restart (C3's P1, S2, then P2).
  - What H1 cannot do is keep in-flight work alive. Turns, background Bash, Monitors, subagents and
    workflows still die on every event and are only re-engaged.
- **New finding that changes C2's nudge design.** The repo already ships a launch-time prompt
  injector. `lr-fire-resume.sh:1248-1259` waits for READY or a composer that reads EMPTY, then sends
  `^U`, the text, and a separately verified CR (`lr_submit_cr`, `:1035`), all from the launcher's own
  `expect`.
  - This is not a remote shell write by an agent, so the classifier never sees it. It also makes
    zero kitty `send-text` calls.
  - Porting it into `reso-resume-one` (spawn at `:560`) replaces C2's `restore-nudge.sh`. That
    remedies the 30-of-31 failed deliveries and the `[Remote Shell Writes]` denial of
    2026-10-01T19:13:40Z together.
- **Why the session layer waits.** H2 (tmux, from C1) is the only measured way to survive (a) and (b)
  with in-flight work intact. Its skeptics show it has no safe halfway state. The frozen
  `KITTY_LISTEN_ON` and `KITTY_WINDOW_ID` break the control plane after the first "free" kitty
  restart. So it must ship as one cutover:
  - ESTIMATED from the skeptics' file counts: 3,000-5,000 LOC over 2-4 weeks.
  - Its scrollback cost is real but softer than C1-risk said. New measurement: with tmux's
    alternate screen turned off (`smcup@:rmcup@`), kitty's own scrollback receives paced output in
    full (60 of 60 lines). Bursts are lossy (23 of 100 lines), so tmux's history remains the
    complete record.
- **A third survival option nobody costed: Claude Code's own background-session daemon (H3).** It is
  a vendor pty broker. Measured live now: supervisor pid 9780 has **ppid 1** at PRI 31, with
  `bg-pty-host` workers under it. So it already lives outside kitty.
  - The repo's own research shows it conflicts with this fleet on four points:
    - it strips `KITTY_WINDOW_ID` and `ITERM_SESSION_ID`;
    - `/exit` only detaches;
    - backgrounding forks to a new session id;
    - recycles are refused by design (`handoff-fire.sh:4935-4975`).
  - Today it is a watch item, not a build.
- **Null option (H0).** Today's scripts are one-offs: `OLD_KITTY = 610`, `D = "/tmp/inboot-2026-10-01"`,
  `NEW = 48854`. Re-running them as a runbook would repeat the measured outcome: 8 of 32 sessions on
  the first pass, 5 resurrections, 30 of 31 nudges unsubmitted, about 25 min, and several manual
  steps.

**Ranking.** H1 > H2-after-H1 > H0 > H3. Conviction that H1, built as specified below, meets the
goal with net benefit: **62**. The goal here is no manual rebuild for any of the three events. What
holds the number down:
- The goal's spirit is survival, and H1 only restores.
- Nobody can rehearse a restore end to end without killing the fleet.

## New evidence from this pass (command => output)

### E1. What the auto-mode classifier refuses, from `~/.claude/logs/permission-denied.jsonl` (531 rows; python scan of `input_head`)

| Date (UTC) | Action an agent tried | Result |
|---|---|---|
| 2026-09-09T07:06:15Z | `tmux kill-session -t lr-resume-9e3074fc` ("retiring an idle orphan") | Blocked by classifier |
| 2026-09-16T22:00:08Z | `kitty @ send-key --match id:5 enter` into another session | Blocked |
| 2026-09-26T19:03:05Z | `cc-teardown 732 --done-evidence …` | "judged this action dangerous" |
| 2026-09-26T22:07:11Z | `kitty @ send-text --match id:814 '…Continue the work…\r'` | "judged this action dangerous" |
| 2026-10-01T16:40:09Z, 16:45:03Z | `cc-pane-close --pane 55 --pane 69 --pane 76` (husks) | Blocked |
| 2026-10-01T19:13:40Z | the lead's loop that re-sent the restore prompt via `kitten @ … get-text`/send | **`[Remote Shell Writes]`** |
| 2026-09-10T02:57:52Z, 2026-09-26T06:11:56Z | `handoff-fire.sh self-close --terminal` (its own pane) | Blocked (rare) |

- Memory note `auto-mode-classifier-denies-acting-on-a-live-session.md` (measured 2026-09-04): the
  boundary is "the TARGET being a live Claude session, not the verb". `kill <claude pid>`,
  `cc-teardown` and `cc-notify … /exit` were refused; `kill` of a `cc-await-ping` watcher was allowed.
- **Self-retirement is allowed.** `~/.claude/watchdog/teardown/*.json` by mode and month (python
  counter) shows **535 `terminal` and 382 `recycle`** markers in September, against 3 denials.
- The classifier judges only agents' tool calls. A launchd job, the operator's command, or a
  launcher's `expect` typing into its own child is never judged, so every hybrid below is designed
  to need no agent action on a live session.

### E2. The nudge can be delivered at launch, by the launcher

- `scripts/limit-recover/lr-fire-resume.sh:1248-1259`: on `$re_ready`, it does `sleep 0.3; send
  "\025"; sleep 0.2; send -- $prompt_b; lr_submit_cr`. On quiet with no READY, it types **only** if
  `lr_screen` reads `EMPTY`. A parked menu means "NOTHING was sent" (`:1272-1296`).
- `bin/reso-resume-one:560` already `spawn`s claude inside `expect`, and `:712` execs the shell
  afterwards. Adding the same READY arm is a port, not new design.
- The vendor CLI also documents `claude -r "<session>" "query"` ("Resume session by ID or name",
  code.claude.com/docs/en/cli-reference), and the 2.1.284 binary carries the `[prompt]` argument
  (`strings` => `[prompt]`, `Your prompt`). Two things are UNMEASURED on this box: whether the
  positional prompt survives `reso-resume-one`'s resume-threshold dialog, and whether it is
  submitted rather than drafted. The expect port is the proven path.

### E3. tmux and kitty scrollback (private servers, python pty client, `TERM=xterm-kitty` with kitty's terminfo)

| Variant | `\e[?1049h` sent to kitty | 100-line burst: lines reaching kitty | 60 lines, 50 ms apart |
|---|---|---|---|
| tmux default | 1 (alternate screen) | 23 of 100, one `CSI S` | not run |
| `terminal-overrides ',xterm-kitty:smcup@:rmcup@'` | **0** | **23 of 100** | **60 of 60**, scrolled by LF at the bottom row |

- kitty v0.48.2 `screen.c:2241-2246` (`screen_index`) and `:2261-2267` (`screen_scroll`) add a
  scrolled-off line to history when `linebuf == main_linebuf && margin_top == 0`. Fetched from
  raw.githubusercontent.com/kovidgoyal/kitty/v0.48.2/kitty/screen.c.
- So without the alternate screen, kitty's own scrollback gets whatever tmux forwards. tmux coalesces
  bursts into a redraw, so lines can be missing. Claude's real output pattern is UNMEASURED.

### E4. Claude Code's background daemon is already running outside kitty (read-only `ps`, roster read)

- `ps -o pid,ppid,pri,etime,ucomm -p 9780,10027,10130,10202` => supervisor `9780 1 31 22:24
  claude.exe`. Its children `10027` and `10130` are `claude bg-pty-host …`, both at PRI 31.
  `~/.claude-next/daemon/roster.json` holds `supervisorPid 9780` and one worker for
  `9aa483e9-cb26…`, with keys including `ptySock`, `rendezvousSock` and `decModes`.
- Docs (code.claude.com/docs/en/agent-view): "Background sessions don't need any terminal open to
  keep working". `daemon stop --keep-workers` lets a new supervisor reconnect. "Attached sessions
  always render in fullscreen mode … Scroll with `PgUp`, `PgDn`, or the mouse wheel." A reboot stops
  them; within 48 h they show `failed`, and attach or reply restarts them. There is one supervisor
  per `CLAUDE_CONFIG_DIR`.
- The repo's measured conflicts:
  - the `dNe` denylist strips `KITTY_WINDOW_ID`, `ITERM_SESSION_ID`, `TMUX` and `TERM_PROGRAM`
    (`docs/research/bg-session-semantics-2026-09-25.md` Q1);
  - `/exit` and Ctrl+C detach, and only `/stop` ends a session (Q3);
  - backgrounding is `--resume <parent>.jsonl --fork-session`, a new sid (Q5);
  - `handoff-fire.sh:4935-4975` (`hf_bg_hosted`) refuses to recycle a bg-hosted session;
  - `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` is set on purpose at `lr-fire-resume.sh:1093-1106` and
    `lr_recon/act.py:70`.

### E5. Pinning `listen_on` to a fixed path is not free

- kitty `boss.py:230-237` (local copy `/tmp/kittysrc/kitty_boss.py`) runs `s.bind(address)` with no
  prior unlink. On failure, kitty runs with no socket ("Invalid listen_on", `:428-432`).
- `handoff-fire.sh:1216-1219` records that "a socket file outlives a SIGKILLed kitty".
- So a fixed `unix:/tmp/kitty-main` would let frozen `KITTY_LISTEN_ON` values survive a restart. But
  the relauncher must unlink the stale file first. Today's line is `kitty.conf:147 listen_on
  unix:/tmp/kitty-{kitty_pid}`. This matters only to H2.

### E6. Counts re-measured (`grep -rl` over bin scripts hooks lib; `wc -l`)

43 files read `KITTY_WINDOW_ID`, 32 read `KITTY_LISTEN_ON|KITTY_PID`, and 49 call `kitty @|kitten @`.
`bin/it2-kitty` is 1,523 lines and `scripts/handoff-fire.sh` 16,118. These match both C1 skeptics.

## The hybrids

### H0: null. Keep the preserved scripts as a runbook.

- **Design and migration.** The operator runs `kitty-restart-resume.py`, then `inboot-finish.py`,
  then fixes what they missed by hand. No launch path changes, and ergonomics are unchanged.
- **Classifier.** The kill is the operator's. Re-sending nudges and closing the 4 resurrected panes
  and the duplicate 3a06361f are agent-refused (E1), so each is another operator step.
- **Coverage.**
  - (a) Manual rebuild.
  - (b) Manual. Measured: 8 of 32 on the first pass, 14.7 min to the last launch, plus 13.6 min of
    land wait (C2 §1; C2-skeptic-risk #11).
  - (c) Boot-resume runs with the `.start` bug live (`alarm-reboot-prep.sh:52` vs
    `boot-resume.sh:298-299`), and the 2.0/core shed applies (`cc-resume-layout.sh:252`).
- **Cost.** Zero build, but the scripts need editing before each event
  (`kitty-restart-supervisor.py:26-28`, `kitty-restart-resume.py:24`, `inboot-finish.py:17-19`). It
  fails the "one command at most" constraint, so it is a baseline only.

### H1 (recommended now): prevent and restore. C3's safe subset, hardened C2, and a launch-time nudge.

**Design, in the order it lands.**

1. **The C2 core, with every skeptic fix** (C2 §2, C2-skeptic-code, C2-skeptic-risk):
   - **`.start` fix.**
     - `alarm-reboot-prep.sh:52` writes `reboot-$DAY.kalloc` instead.
     - `boot-resume.sh:298` becomes a tolerant first-field reader.
     - Add a paired bats case.
   - **`--event` mode.**
     - It writes `events/<K>.done` and never touches `last-boot-epoch`.
     - It takes an **in-progress claim and a global restore lock before any SIGTERM**
       (C2-skeptic-risk #3).
   - **Roster.**
     - A planned restart takes a fresh snapshot.
     - A crash or reboot uses the 5-minute heartbeat (`cc-sessions --json`, which makes 0 kitty
       calls) unioned with tombstones.
     - The heartbeat may freeze for **one tick only** (C2-skeptic-code #5).
   - **Retire filter and launched-once ledger.**
     - A recycle counts as retirement only when its successor is in the roster, or has a transcript
       newer than the marker (C2-skeptic-risk #4).
     - Before each launch, re-check `lr_holder_count` (`lr-lib.sh:509-540`) per row (C2-skeptic-risk
       #2).
   - **Restore capacity mode.**
     - `CC_ADMIT_LOAD_TERM=off`, which is a term switch per the C18 rule at `capacity-admit.sh:156`.
     - A 6/core start gate.
     - `cc-resume-layout.sh:252` stops shedding the tail. It waits and retries the same row up to a
       deadline.
   - **Fullscreen.**
     - Use `kitten @ action --match id:<w> toggle_fullscreen` after the layout completes. Do not
       interleave it with launches; that is untested (C2-skeptic-code #2).
     - Read back with AX `AXFullScreen` on the new kitty pid, not CoreGraphics bounds. The notch
       makes bounds read 9 of 9 fullscreen windows as failures (C2-skeptic-code #1).
     - Delete `fs_osa` (`:177`).
   - **Model and effort** carried into `reso-resume-one --effort` and `CC_RESUME_MODEL`.
   - **One-command planned restart.** `bin/cc-restore --restart-kitty` (Python, so `cc-reaper` leaves
     it alone) with a bounded land wait. It is operator-run.
   - **Reaper.** Add `boot-resume` to `GARBAGE_WL` (`bin/cc-reaper:713`), or run the event restore
     from Python (C2-skeptic-code #3).
   - **Crash trigger.** It fires only on a **pid-matched kitty `.ips`**
     (`cc-resume-classify.py:116-141`), and otherwise only pages. It sits behind its own
     operator-created opt-in file, with a documented off switch. A deliberate ⌘Q never relaunches
     anything (C2-skeptic-risk fatal finding).
2. **Launch-time nudge (new; replaces C2 §2.7's send-text delivery).**
   - `reso-resume-one` gains `--prompt-file F`. Its expect program types the prompt with
     `lr-fire-resume.sh`'s READY/EMPTY arm and `lr_submit_cr` (E2).
   - `boot-resume.sh` writes one prompt file per INTERRUPTED or WAKE-LOST sid. `cc-resume-layout.sh:257`
     appends `--prompt-file`.
   - Confirmation is an **assistant** record after the nonce, not the user record (C2-skeptic-risk
     #7).
   - WAKE-LOST ships only after it matches the 10-session oracle. The oracle covers background shells
     only (C2-skeptic-code #7).
   - Result: no agent and no kitty socket are involved in delivery, and the about 31 `send-text`
     calls per restore disappear.
3. **C3 prevention, ordered so that no layer makes things worse** (C3 skeptics):
   - **S2 first.** `bin/kitty-rc`: a lockf semaphore with N=4, plus a breaker whose `deaf-until`
     **expires**. Point the existing seams at it (`CC_KITTY_BIN`, `CC_TERM_KITTY`, …). Leave the lint
     for later.
   - **P1 next.** The fd-headroom `watcher`. Test it once in the staged kitty (operator-owned, kdw4),
     because config rollback cannot detach a loaded watcher (C3-skeptic-risk note 7).
   - **S1 as advisory only.**
     - It writes its flag only after `sample <pid> 1` shows no `KittyPeerMon`.
     - Its page says "remote control dead; sessions still working; run `cc-restore --restart-kitty`
       when convenient". It never prescribes an immediate kill.
   - **P2 and P3** (talk thread keeps serving, the `f3fdc21850` backport, `NSAppSleepDisabled`). They
     ride the first planned `cc-restore` or the staged-build swap, so they cost no extra restart.

**(1) Launch-path migration.** Only path (ii), which the restore uses, moves.
`bin/reso-resume-one` gains the prompt arm next to `spawn` (`:560`) plus option parsing, and
`bin/cc-resume-layout.sh:257-258` passes `--prompt-file`, model and effort. Path (i)
`bin/cc-pane-runner` and path (iii) `claude()` (`lib/claude-launcher.zsh:221`, `~/.zshrc:451`) do
not change.

**(2) Classifier.** No agent action on a live session is required. The restart is one operator
command, and the crash trigger is an opt-in launchd job. The launcher types the nudge into its own
child. The ledger and holder re-check prevent duplicates, so nothing needs closing. An agent running
`cc-restore` would likely be refused (it ends 32 sessions), and by design that command is the
operator's.

**(3) Ergonomics.** Unchanged: real title bars, drag, the 2x2 grid, kitty scrollback and copy.
Native fullscreen switches Spaces once per window during a restore (C2 risk 7).

**(4) Coverage.**
- (a) Zero commands when the `.ips` evidence and opt-in exist. Otherwise a page and one command.
  Estimated 10-15 min to the full fleet.
- (b) One command. Estimated about 25 min, including the land wait. Prevention lowers its frequency.
- (c) Zero commands at login. Estimated about 12 min after login.
- In-flight work is lost on all three and re-engaged once by the launch-time nudge.

**(5) Cost (estimated).** C2's change list is about 750 LOC plus 450 bats (C2 §5). The
launch-time-nudge port adds about 80 and removes `restore-nudge.sh` (-120). The skeptic fixes add
about 120. C3's S2, P1 and S1 add about 290 (C3 §5).
- About 1,100-1,300 LOC and about 650 bats lines.
- About 10 files touched: `boot-resume.sh`, `cc-resume-layout.sh`, `reso-resume-one`,
  `cc-resume-classify.py`, `alarm-reboot-prep.sh`, `cc-reaper`, plus new `cc-restore`, `kitty-rc`,
  the fd watcher, and the S1 watchdog with its plist.
- About 5-6 dispatched sessions over 3-4 days.

### H2 (gated phase 2): H1 plus a tmux session layer, shipped as one cutover

**Design.** This is C1 variant (a), with both C1 skeptics' required changes:
- one server per session (`tmux -L ccp-<id>`) on an owned config;
- `remain-on-exit failed` or a `pane-died` hook;
- `focus-events on`;
- `mouse on` with wheel bindings, or `smcup@:rmcup@` (E3);
- a `SetUserVar cc_host` OSC from the host, so the Shift+Enter `map` covers hand-opened panes;
- `cc-reattach` that probes liveness (`tmux -L <id> ls`) and **never creates** a session;
- `env -u KITTY_*` in the pane command;
- `CC_PANE_ID` as the only identity.

Optionally, a fixed `listen_on` path with an unlink-before-relaunch step in `cc-restore` (E5). Host,
shim arm, identity strip and the readers' migration land **together, behind a kill switch**
(C1-skeptic-risk "what would have to be true" 1-6). C2/H1 still owns reboots, and it launches into
hosts.

**Gate before any build.** Run a one-session pilot with a real Claude in a private host, from a
session the operator authorizes; an agent typing a `claude` launch was refused as [Create Unsafe
Agents] (memory note above). It checks Shift+Enter, scrollback under `tui: default`, keychain on all
4 accounts, and `osascript` from the launchd `Background` session (C1-skeptic-code missed risk 2).
The gate also needs an operator ruling on scrollback.

**(1) Launch-path migration.**
- (i) `bin/it2-kitty` `split` wraps `zsh -l -i -c 'exec cc-pane-runner'` in a host. `cc-pane-runner:77`
  (`_id="${KITTY_WINDOW_ID:-}"`) and `:330` move to `CC_PANE_ID`. So do `:192`, `:268` and `:281`.
- (ii) `cc-resume-layout.sh:266` `-- zsh -ic "$cmd; exec zsh -i"` becomes `-- cc-tmux-host <id> --
  zsh -ic …`. `reso-resume-one:712`'s shell fallback stays, inside the host.
- (iii) Both `claude()` definitions (`lib/claude-launcher.zsh:221`, `~/.zshrc:451`) re-exec through
  the host when `$TMUX` is unset. `~/.zshrc:694-695` (`ITERM_SESSION_ID` only when `cc-in-kitty`
  passes), `bin/it2-wrapper:88-98` and `bin/cc-in-kitty` must accept a host (C1-skeptic-code claim 5).

**(2) Classifier.** For (a) and (b), no agent action on a live session is needed: the processes
survive, and reattach starts nothing. Ending a hosted session is `tmux kill-session`/`kill-server`,
which is refused for agents (E1, 2026-09-09). Self-close and recycle go through `handoff-fire.sh`
as today, and the classifier judges the outer command (C1-skeptic-risk #15). New hazard:
`hooks/teammate-auto-shutdown.sh:211` `tmux kill-pane -t %N` would target the lead's own pane.

**(3) Ergonomics.** Kept: real title bars, drag, `cmd+d`, the move menu, fullscreen, the 2x2 grid.
Changed: ⌘W becomes "detach" unless `kitty-confirm-close` offers "end session". tmux history is
complete, but kitty's own scrollback is lossy under bursts even with the override (E3: 23 of 100).
OSC 52 copy is forwarded only while attached. Colors fall to 256 unless `CLAUDE_CODE_TMUX_TRUECOLOR`
is set (C1-skeptic-code #11).

**(4) Coverage.**
- (a) and (b) are lossless for the life of each tmux server: in-flight turns, Monitors, subagents
  and workflows survive (C1 E1, replicated twice). Recovery is `cc-reattach`: one command, or zero
  if hooked to kitty start.
- (c) Same as H1.
- New loss mode: a tmux `fatal("accept failed")` on ENOMEM kills that session (`server.c:389`).

**(5) Cost (estimated from the skeptics' counts).** 59 non-test files read a kitty identity signal.
143 test files fixture kitty-shaped ids. `it2-kitty` is 1,523 lines.
- About 3,000-5,000 LOC.
- About 10-15 sessions over 2-4 weeks, after H1.
- Value is zero until the cutover.
- Rollback ends every hosted session, which is operator-only.

### H3 (watch, do not build): H1 plus Claude Code's background daemon as the session layer

**Design.**
- Each kitty pane runs `claude attach <id>`. Sessions run under the per-account supervisor (E4).
- After a kitty death, `cc-reattach` runs `claude attach` per pane.
- After a reboot, H1's boot-resume either `claude respawn`s failed workers (within 48 h) or
  re-resumes them.

**Why not now** (repo measurements and vendor docs):
- Identity is stripped, so `teammateMode: iterm2` (settings `:1305`, all 4 dirs) throws on teammate
  spawn (C1 E3 `FYt`), and every pane-keyed hook loses its address.
- Backgrounding forks the sid (bg-semantics Q5), and `/exit` only detaches, so recycles are refused
  (`handoff-fire.sh:4960-4975`). The repo turns agent view off in its recovery launchers
  (`lr-fire-resume.sh:1093`).
- 2.1.284 has no shell-side prompt send. There are four supervisors, one per config dir. Whether a
  `--origin transient` daemon outlives a kitty SIGKILL that also kills its spawning client is
  UNMEASURED: pid 9780 with ppid 1 shows only that it detaches.

**Per point:**
- **(1) Migration:** all three paths move to `--bg` plus `attach`. Recycle and self-close must be
  rebuilt around `/stop`.
- **(2) Classifier:** `claude stop <id>` on a live session is presumably refused like `cc-teardown`
  (UNMEASURED).
- **(3) Ergonomics:** title bars and drag are kept. Attach is always the fullscreen TUI (PgUp, PgDn,
  wheel), so kitty scrollback holds nothing.
- **(4)/(5):** (a) and (b) likely survive; (c) uses vendor `respawn` plus H1. The cost is estimated
  at about H2's identity migration plus a recycle redesign. Revisit if a release keeps the sid on
  background and passes pane env through.

## Events coverage

| | (a) Terminal crash | (b) Kitty restart (planned or deaf) | (c) Mac reboot |
|---|---|---|---|
| **H0** | manual rebuild; in-flight lost | manual; 8/32 first pass, about 25 min (measured) | boot-resume with `.start` bug and 2.0/core shed |
| **H1** | 0 commands (opt-in, `.ips`-gated), else 1; in-flight lost, nudged at launch | 1 command (`cc-restore --restart-kitty`); prevention (S2, P1, then P2) cuts frequency; in-flight lost | 0 commands at login; in-flight lost |
| **H2** (after H1) | **survives**; `cc-reattach` (0-1 command) | **survives**; a restart becomes cheap | same as H1, launching into hosts |
| **H3** (watch) | likely survives (UNMEASURED); `claude attach` per pane | same | vendor `respawn` within 48 h, plus H1 |

## Agent actions on live sessions each hybrid needs

| Action | H0 | H1 | H2 | H3 |
|---|---|---|---|---|
| Restart or kill kitty | operator (agent kill of live sessions refused, memory 2026-09-04) | operator's one command | rarely needed | rarely needed |
| Type a recovery nudge into another session | needed; **refused** (E1) | not needed: the launcher types into its own child | not needed for (a)/(b) | not possible from shell in 2.1.284 |
| Close duplicates or husks | needed; **refused** (`cc-pane-close`, E1) | not needed (ledger, holder re-check) | `tmux kill-session` **refused** (E1) | `claude stop` presumably refused |
| Session ends itself (self-close, recycle) | allowed (917 vs 3, E1) | same | same, via the tmux arm | `/exit` detaches; needs a `/stop` arm |

## Sequencing and total cost

1. **Days 1-4, H1 (about 5-6 sessions).**
   - Order:
     - S1: `.start` fix and reaper whitelist.
     - S2: event mode, lock, roster, heartbeat, retire filter, ledger.
     - S3: layout restore mode and AX fullscreen.
     - S4: launch-time nudge plus WAKE-LOST against the oracle.
     - S5: `cc-restore`, plus a gated crash trigger that lands **last**, behind its opt-in.
     - S6: `kitty-rc` breaker, then P1 after the sandbox test, then S1 advisory.
   - Everything new sits behind opt-in files. `~/.claude` is a symlink farm, so a land is live at
     once (C2-skeptic-risk #7).
2. **First planned restart.** The operator runs `cc-restore --restart-kitty`. P2 and P3 ride along,
   and so does the staged-build decision if the operator makes it. This is H1's first real
   rehearsal.
3. **Gate.** Run the H2 pilot (1 authorized session) and get the operator's scrollback ruling.
   Re-check H3 against each Claude Code release.
4. **If the gate passes, H2** as one cutover: about 10-15 sessions over 2-4 weeks.

**Total (estimated):**
- H1 alone: about 1,200 LOC, 5-6 sessions, 3-4 days.
- H1 plus H2: about 4,000-6,000 LOC, 15-20 sessions, 3-5 weeks.

## Risks

1. **H1 restores and does not preserve.** Every event still ends in-flight turns and background
   work. Re-engagement depends on WAKE-LOST accuracy (24 naive against an oracle of 10) and on the
   launch-time nudge.
2. **No rehearsal of a full restore** is possible without ending the fleet. The first real run is the
   next incident or planned restart (C2-skeptic-risk #11).
3. **The launch-time nudge** inherits `lr-fire-resume`'s version coupling on the READY regex. Its
   EMPTY-screen fallback parks safely, so the failure is "not typed", not "typed into a menu".
4. **A restore makes about 100 kitty RC calls.** S2's gate and bounded calls are prerequisites, so a
   restore cannot re-kill the new kitty's talk thread.
5. **P1 runs in-process in kitty and cannot be unloaded** by a config rollback, so it needs a
   sandbox test first. P2 is a fourth local patch on 0.48.2.
6. **H2's halfway state is worse than today.** Partial landing must be impossible: one cutover, a
   kill switch, tested rollback.
7. **The operator constraint and a newer finding disagree on layout.** The brief fixes 2x2. The
   restart lead's addendum (`C2-addendum-lead-findings.md` item 2) reports "one row of panes". Keep
   the layout parameterized and ask; I do not re-litigate it here.
8. **Account concurrency and quota.** About 12 nudged first turns rewrite cold caches. Estimated
   about 5M tokens (C2-skeptic-risk #10).

## Open questions (UNMEASURED)

- Does `claude --resume <sid> "<prompt>"` submit the prompt after `reso-resume-one`'s resume-threshold
  dialog in 2.1.284? It would be simpler than the expect port.
- Real Claude under tmux with `smcup@:rmcup@`: how much of a session's output reaches kitty's
  scrollback (E3 measures only dummy output)?
- Does a transient vendor daemon (E4) survive the SIGKILL of the kitty whose pane started it? Does
  it keep `bg-pty-host` screen state for a fresh `claude attach`?
- Does the P1 watcher load into a running kitty on `auto_reload_config`? (C3 open question 2.)
- Why did 14 of 32 sessions write no tombstone, skewed to the quaternary account? Until that is
  known, H1's crash and reboot rosters lean on the heartbeat.

---

# Revision 2 (second pass, 2026-10-01 about 15:40-16:15 CDT)

This file already held the first pass above (untracked, so not recoverable from git). The worker rules
forbid overwriting, so this revision is **appended**. **Where the two disagree, this revision wins.**
The first pass above is kept as the record that the C4 skeptics reviewed.

This pass took in the C5 dossier, both C4 skeptics, the second skeptic passes on C1, C2, C3 and C5, and
19 commits that main gained after this branch was cut. Probes:
- **kitty:** 0 of 3 allowed `kitten @` calls. Nothing was signaled, typed into or launched, and
  `claude` was not run.
- **Experiment:** one private tmux server, `-L sd-probe-c4r2`, with `sh`/`sleep` dummies. It was killed
  and its socket file removed: `ls /private/tmp/tmux-501 | grep -c sd-probe-c4r2` => `0`.

## Answer (revision 2)

**Build H1 now, as revised below. It is restore-first, built on main's live code, and it pages before
it nudges.** If a session layer is ever built, it should be tmux (C1, H2), not Claude Code's background
daemon (C5, H3). Build it only after H1 has carried one real restore and the operator has ruled on a
one-session pilot. Keep H0 (today's scripts) only as the baseline H1 must beat.

- **Why restore first, now with frequency data.** Of the three events, the one a session layer cannot
  help with (reboot) is at least as common as the ones it can. Over the 62 days from Jul 31:
  - `last reboot` shows **11 reboot records** (measured). Several come in pairs on the same day.
  - The kitty window id dropped back to 2-6 **5 times** outside a reboot: 08-09 20:51Z, 08-10 07:04Z,
    09-10 00:02Z, 09-19 17:06Z and 10-01 18:31Z (estimated from id resets in
    `~/.claude/logs/pane-spawns.jsonl`, python scan, with those near a `last reboot` row excluded; the
    log's kitty rows start 08-07).
  - So about two-thirds of all events are reboots, which only disk resume survives. H1 is needed on
    every path. A session layer would add in-flight survival on roughly a third of events, at 3-4x
    H1's cost.
- **What changed in H1 since the first pass** (each change is cited below):
  - The nudge is now a **page by default**. The launch-time nudge goes out only with direct evidence of
    open work *and* account headroom, and never reads another pane through the kitty socket.
  - The crash path **pages with one command** instead of relaunching on its own.
  - H1 now **builds on main**, which has moved under C2: retire filter, close-on-clean-exit, and a
    deaf-kitty detector.
  - It adds **restore locks, a per-session launch lock, a test guard and a bounded `k()`**, landed
    before `cc-restore`.
  - It fixes the background-fork hazard **at its source**.
  - Of C3 it keeps only **P2 plus the signal-handling backport**, in a build kept separate from the
    title-band decision.
- **Head to head, C1 beats C5 as a session layer for this fleet** (table below).
  - Under tmux, `/exit` still ends the session and closes the pane. Measured in the private probe:
    after the pane's command exited the server was gone, and the client printed `[exited]`.
  - Under C5, `/exit`, double Ctrl+C and Ctrl+D only detach, and `claude stop` did not stay stopped
    (`~/.claude-quaternary/daemon.log:55-56`: killed 16:52:30Z, re-claimed 16:56:46Z; C5-skeptic-risk).
  - With 719 `prompt_input_exit` ends since 09-01 (C5-skeptic-risk), that inversion is not an edge
    case.
- **Conviction that revised H1 meets the goal with net benefit: 57.** Points come off because:
  - H1 restores rather than preserves, and in-flight work dies on every event;
  - the first full rehearsal is still a real restart;
  - the classifier boundary has proved wider and less consistent than the first pass assumed.

## What changed since the first pass (command => output)

**R1. Main moved under every candidate.** `git log --oneline HEAD..main | wc -l` => `19`.
`git -C ~/Development/claude-infrastructure rev-parse --abbrev-ref HEAD` => `main` at `9615d31fb`, so
the live layer is main. Cites below are `git show main:<path>` line numbers. Relevant lands:
- `ba04df7b3` (13:57): the boot-resume retire filter skips `terminal|successor` markers and states that
  "`recycle` is not a retirement" (`boot-resume.sh:374-406`).
- `6347b1731` (14:42): `reso-resume-one` now reaps claude's status and closes the pane on a clean exit
  with no recycle pending (`:716-751`; recycle check `:745`; shell fallback moved to `:753`).
- `e66bf5760`, `7fe0e98af` (14:51): `hf_kitty_queue_depth` (`handoff-fire.sh:1404`) calls a queue of
  128 "stuck" (`:1425`), and owed recycles re-run once kitty answers.
- Unchanged and still live: shed-the-tail (`cc-resume-layout.sh:250-252`), failed-launch `continue`
  (`:269`), `.start` writer (`alarm-reboot-prep.sh:52`) against reader (`boot-resume.sh:300-302`), and a
  `GARBAGE_WL` without `boot-resume` (`cc-reaper:713`).

**R2. The first pass's two headline mechanisms were wrong** (both C4 skeptics, re-read here).
- The ported `lr-fire-resume` injector reads the screen through `it2 session read` → `kt get-text`. So it
  is not socket-free, and it adds about 10 calls per nudged pane during the restore.
- E5 is refuted: kitty's `kitten __atexit__` unlinks the socket even after a SIGKILL (`/tmp/kitty-610` is
  gone).
- The `.ips` crash gate would not have fired on 10-01: a hang followed by SIGKILL writes no report
  (`ls ~/Library/Logs/DiagnosticReports | grep -ic kitty` => 0, per C4-skeptic-code).

**R3. The nudge buys little and costs a lot** (C2-skeptic-risk, second pass, measured from
transcripts).
- When 28 stale prompts were finally submitted at 20:16Z, the next 10 minutes cost **6.8M cache-write
  tokens**.
- **14 of the 18** sessions that could run a turn replied that nothing was pending, and one woke a
  PARKED session.
- 27 of the 32 roster sessions sat on two accounts at their weekly limit. So a restore must gate on
  account headroom, and the default must be a page.

**R4. The classifier boundary is wider than "acting on a live session"** (`~/.claude/logs/permission-denied.jsonl`,
536 rows, python scan).
- `2026-10-01T20:14:48Z`: a **read-only** `kitten @ get-text --match id:11 …` (an agent checking that pane
  11 had submitted) => `[Remote Shell Writes]`.
- `18:19:36Z`: `python3 /tmp/kitty-restart-supervisor.py --dry-run` => "judged this action dangerous".
- `20:24:45Z`: an agent's attempt to add an environment line naming the kitty panes as the operator's
  own => `[Self-Modification]`.
- Main's plan (`docs/plans/kitty-deadlock-recovery-2026-10-01.md:41`) concludes that agent pane access
  "needs operator-added allow rules (`Bash(kitten @:*)` …) plus an `autoMode.environment` line … That
  request is with the operator."
- Design rule that follows: **no hybrid may need an agent to read, type into, close or stop another
  session.** Only these may do it:
  - launchd jobs;
  - the operator's one command;
  - a launcher acting on its own child;
  - a session acting on itself (535 `terminal` and 382 `recycle` self-markers in September, first pass
    E1).

**R5. How a session ends under tmux, measured** (private `-L sd-probe-c4r2`; a python pty client running
`tmux attach`, standing in for the kitty pane):

| Event, as C1 would see it | Client exit code | Client's last output | Session afterwards |
|---|---|---|---|
| Pane command exits 0 (claude `/exit`) | 0 | `[exited]` | server gone (`ls` => no server running) |
| `detach-client` | 0 | `[detached (from session b)]` | alive |
| SIGHUP to the client (kitty pane closed, or kitty died) | 1 | — | alive (`has-session` rc 0) |
| `kill-session` while attached | 0 | `[exited]` | gone |

- So C1's host can tell "the session ended" from "the viewer went away" with one `has-session` after
  `attach` returns. It can close the kitty pane only in the first case, which matches main's
  close-on-clean-exit rule (R1).
- A ⌘W still reads as a SIGHUP, the same as a kitty crash. The operator's close dialog has to make
  "end" explicit. That limit is shared with C5, but C1's end verb (`kill-server`) is local and durable.

**R6. The scrollback cost of a session layer was overstated.**
- `~/.zshrc:284` exports `CLAUDE_CODE_NO_FLICKER=1` ("no-flicker renderer with mouse support"), and
  C5-skeptic-risk found it in 37 of 37 live sessions (`ps eww` loop).
- C5's dossier (E6) treats this renderer as already fullscreen. If so, kitty's native scrollback for a
  Claude pane is already thin today, and C1's alternate-screen loss changes little.
- UNMEASURED directly: I did not read a live pane's kitty history, to save socket calls.

## The hybrids (revised)

### H0, null baseline: today's `/tmp` scripts as a runbook

- **Design.** None: no build, and the launch paths are unchanged.
- **Coverage.** (a) and (b) need a manual rebuild with hand edits: `OLD_KITTY = 610`
  (`kitty-restart-supervisor.py:28`), `D = "/tmp/inboot-2026-10-01"` (`kitty-restart-resume.py:24`).
  (c) runs boot-resume with the `.start` bug and the 2.0/core shed.
- **Measured outcome on 10-01.**
  - 8 of 32 sessions came back on the first pass, and 5 were resurrected.
  - 29 of 31 prompts were unsent at 14:40. They were submitted only by the operator's second
    `/tmp/submit-recovery-prompts.sh` run at about 15:20 (plan `:41`).
  - The agent's attempts were refused (R4).
- **Classifier.** It needs agents to type into, read and close other panes, which is refused (R4,
  first-pass E1). Every step is the operator's.
- **Verdict.** It fails "one command at most" on every event.

### H1, build now: restore-first on main, page-first, C3's P2 at a later restart

Slices, in landing order. Each lands behind an opt-in file and each is live at once, since `~/.claude`
is a symlink farm.

**A. Fork hazard at its source** (independent; from C5 E2 and both C5 skeptics).
- When the recycle watcher sees the "Background work is running" dialog (`pane_bgwork_key`,
  `handoff-fire.sh:4390`), it answers `2` only when the background work is real. A session's own
  `cc-await-ping` inbox watcher does not count; in 9aa483e9 that watcher was all the fork carried.
- For a watcher-only case, the recycling session stops its own watcher before `/exit`. That is
  self-scope: killing a `cc-await-ping` was allowed (first-pass E1 memory note).
- Each fork that is still made gets recorded with its account, so the 13d7be20 → quaternary
  cross-account crash (`daemon.log:103-105`) is visible.
- **Do not** chase forks with `claude stop`. It races the fork's wake-up turn (C5-skeptic-code M5) and
  is not durable.

**B. Safety rails before any new restore code** (C2-skeptic-risk second pass #4; C2-skeptic-code second
pass #2; C4-skeptic-risk #3, #4).
- `.start`: `alarm-reboot-prep.sh:52` writes the kalloc figure to a sibling file, and
  `boot-resume.sh:300` reads only the first field. Add a paired bats case.
- `boot-resume` goes into `GARBAGE_WL` (`cc-reaper:713`).
- `cc-restore` and any test refuse to signal when `BATS_TEST_FILENAME` is set. They signal only a pid
  that `ps` shows as the main kitty, and they take a `mkdir` restore lock plus
  `events/<K>.inprogress` **before** the kill.
- `reso-resume-one` takes a per-sid launch lock next to `spawn` (`:560`). A launch that kitty runs late
  then cannot start a second copy.
- Bound `k()` (`cc-resume-layout.sh:175`) with `timeout`.

**C. Restore mode** (C2 §2.5, with both C2 skeptics' fixes):
- `CC_ADMIT_LOAD_TERM=off` (`capacity-admit.sh:1115`) plus a 6/core start gate. Wait and retry replaces
  the shed-the-tail at `cc-resume-layout.sh:250-252`.
- A failed or timed-out launch at `:269` is recorded as "maybe launched" and re-checked after a settle
  delay. It is not dropped.
- **Account headroom gate.** An account at its weekly limit is resumed with no nudge and listed in the
  page.
- **Roster.** Take the newest source of three: snapshot, heartbeat or alarm roster
  (C2-skeptic-code second pass #3).
- **Retire filter.** Keep main's rule (`boot-resume.sh:374-406`). Add one thing: resolve the successor
  from `handoffs.jsonl` `recycle-engaged`, so 3a06361f-style duplicates stop without overruling main.
- **Fullscreen.** `kitten @ action --match id:<w> toggle_fullscreen` after the layout completes. A failed
  read-back pages and never re-toggles (C4-skeptic-risk #5).
- **Layout.** Keep it parameterized: the 2x2 constraint versus the addendum's "one row" is the
  operator's call.

**D. Recovery: page first, then a narrow nudge at launch.**
- The page lists, per session, what died: background shells, Monitors, workflow journals and
  `cc-await-ping` watchers (C4-skeptic-risk #6).
- A nudge goes out only with direct evidence of open work **and** headroom. It is delivered as
  `claude --resume <sid> "<prompt>"` from `reso-resume-one`'s `spawn` line (`:560`). This is documented
  in the CLI reference, and the 2.1.284 binary has `.argument("[prompt]",…)` (C4-skeptic-code).
- It lands only after one operator-authorized pilot shows that the prompt is submitted after the
  resume-threshold dialog. An agent launching `claude` was refused as [Create Unsafe Agents].
- If the pilot fails, the fallback is the expect arm, reading **only expect's own buffer** and
  confirming via the transcript. It makes no `get-text` call.
- A nudge counts as confirmed only on a non-error assistant record (C2-skeptic-code second pass #6).

**E. One operator command and the triggers.**
- `bin/cc-restore --restart-kitty`. It makes one short SIGTERM attempt, then SIGKILL; kitty 48854
  already ignores signals (C3-skeptic-code second pass, claim 5). Its land wait is bounded, and it has
  `--abort`.
- **(a) Crash.** The 300 s tick sees no main kitty process and **pages** `cc-restore --after-crash`.
  There is no automatic relaunch: a deliberate ⌘Q cannot be told apart (C2-skeptic-risk fatal), and a
  crash cluster would loop (C4-skeptic-risk fatal). An opt-in auto mode can come later, with a cap of
  one per 2 h and a minimum uptime for the new kitty.
- **(c) Reboot.** The existing plist (RunAtLoad) runs at login, as today, and needs zero commands.

**F. Prevention, at restarts already happening** (C3, both second passes).
- P2 is the `accept_peer` keep-serving patch, an errno log and the loop-utils signal backport. It is
  built **separately from the title band** (`kitty-build-swap.sh` couples them today). It is adopted at
  the second planned restart, never at H1's first rehearsal.
- P1 only as "if EMFILE", under a new file name per attempt.
- S1 is diagnosis-only, on main's `hf_kitty_queue_depth`. It never prescribes a restart while load per
  core is above the restore ceiling.
- S2 (breaker) is deferred until its rc contract is pinned (C3-skeptic-risk M2).

**The five costing questions for H1:**
1. **Launch-path migration.**
   - Path (ii) changes: `reso-resume-one` gets the launch lock at `:560`, the positional prompt, and
     model/effort passed in. `cc-resume-layout.sh:250-252`, `:266` and `:269` change.
   - Path (i), `cc-pane-runner` (`:77`, `:312` eval, `:102` fallback), does not change.
   - Path (iii), `claude()` (`lib/claude-launcher.zsh:221`, `~/.zshrc:451`), does not change.
2. **Classifier.** No agent action on another live session. The kill is the operator's command, the
   reboot is launchd, and the nudge is the launcher's own child. Self-retirement is unchanged.
3. **Ergonomics.** Unchanged: title bars, drag, Desktops, scrollback, copy. A restore switches Spaces
   once per window, and Desktop assignment is re-packed unless the heartbeat also records desk and slot
   (optional; one bounded `ls` per tick).
4. **Coverage.** In-flight work is lost on every event.
   - (a): a page plus one command.
   - (b): one command.
   - (c): zero commands.
5. **Cost.** See "Sequencing and total cost".

### H2, gated phase 2: H1 plus a tmux host per session (C1), as one cutover

- **Design.** C1 variant (a), with every skeptic condition:
  - one server per session on an owned config;
  - `remain-on-exit off`, plus a host that runs `has-session` after `attach` and closes the kitty pane
    only when the server is gone (R5);
  - `cc-reattach` that probes with `ls` and never creates a session;
  - `env -u KITTY_*` in the pane;
  - `CC_PANE_ID` as the identity, **and a replacement for the ancestry oracle**:
    - `pane_ownership` (`handoff-fire.sh` "THE PROCESS TREE IS THE EVIDENCE");
    - `lr_recon` (`observe_rows.py:288-298`, `evidence.py:132-141`);
    - `cc-in-kitty`, `it2-wrapper`, `cc-sessions`, `kitty-confirm-close` (C1-skeptic-code second pass
      #1; C1-skeptic-risk);
  - a reaper for finished hosts and a supervisor for a host whose server vanished;
  - the ⌘W dialog gains an explicit "end session" that runs `tmux -L ccp-<id> kill-server`.
- **Launch-path migration.**
  - (i) `cc-pane-runner:77,192,268,330` move from `KITTY_WINDOW_ID` to `CC_PANE_ID`, and `it2-kitty`
    `split` wraps it in the host.
  - (ii) `cc-resume-layout.sh:266` becomes `-- cc-tmux-host <id> -- zsh -ic …`, and
    `reso-resume-one:745` reads `CC_PANE_ID`.
  - (iii) Both `claude()` definitions re-exec through the host when `$TMUX` is unset.
    `~/.zshrc:694-695` must accept a host.
- **Classifier.** (a) and (b) need no agent action: reattach starts nothing. Ending another session with
  `tmux kill-session` is refused (09-09T07:06:15Z), so ends stay self-scope or operator-only.
- **Ergonomics.**
  - Kept: title bars, drag, the grid, fullscreen.
  - ⌘W becomes detach unless "end" is chosen.
  - Shift+Enter needs a kitty `map` plus a user var on every pane.
  - Scrollback: tmux history, with PgUp/PgDn. That is near today's state (R6).
  - Colors need `CLAUDE_CODE_TMUX_TRUECOLOR`.
- **Coverage.** (a) and (b) survive with in-flight work, and one `cc-reattach` brings the panes back.
  (c) is H1's. New loss mode: a tmux `fatal()` on a non-EMFILE accept error kills that one session.

### H3, not recommended: H1 plus Claude Code background sessions (C5)

- **Launch-path migration.** All three paths go through `cc-bg-launch`, then `exec claude attach`:
  - (i) `cc-pane-runner:312`;
  - (ii) `reso-resume-one:560` becomes `--bg --resume`;
  - (iii) `claude()`.
- **Further migration.**
  - Recycle and self-close are rebuilt around `/stop`, since `hf_bg_hosted` refuses them today
    (`handoff-fire.sh:5070`).
  - `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` has to come out of `lr-fire-resume.sh:1093`, which brings the
    exit dialog's `2` back fleet-wide (C5-skeptic-code M4).
- **Classifier.** `claude stop` on another session is UNMEASURED and likely refused (R4). Typing `/stop`
  into one's own attach pane is self-scope.
- **Ergonomics.**
  - Kept: title bars and drag.
  - Claude's own titles did not come through attach. The test was confounded by a weekly-exhausted
    account, but 29 of 33 bars carry them today.
  - `←` opens an account-wide picker.
  - ⌘W, `/exit`, ^C^C and ^D^D all detach.
- **Coverage.** (a) and (b) survive (measured once, idle worker). For (c), attach auto-continues every
  interrupted turn with no gate.
- **Why not.** The close inversion and the non-durable stop are structural.

### Head to head: C1 (tmux host) against C5 (vendor background daemon)

| Property | C1 tmux host | C5 `--bg` + `claude attach` |
|---|---|---|
| (a)/(b) survival | measured, replicated 3 times (C1 E1 + both skeptics) | measured once, on an idle worker on an exhausted account (C5 E5) |
| (c) reboot | none; needs H1 | none; attach auto-continues interrupted turns, ungated |
| `/exit` in the session | ends claude, then the pane, then the server (R5) | detaches only; `/stop` ends it |
| Operator closes the pane | SIGHUP = detach; dialog can `kill-server` (local, durable) | detach; `claude stop` re-claimed after 4 min 16 s |
| Session id | unchanged | exit dialog forks a new id; cross-account crash measured (b363d8e6) |
| Identity | ours (`CC_PANE_ID`); 52 ancestry-oracle files to migrate | stripped by vendor denylist; daemon env frozen by whoever starts it |
| Memory for 32 sessions | about 0.4-1.2 GB (12-38 MB per server, C1 skeptics) | about 3 GB of pty hosts alone; 6-9 GB with clients (estimated, C5 skeptics) |
| Blast radius of one fault | one session (`server.c:384-389` fatal) | a plain `daemon stop` kills the whole account (measured 09-27) |
| Retire while detached | never | 60 s grace under memory pressure, so Monitor-only sessions are shed during an outage |
| Vendor coupling | tmux 3.6a; config is ours | undocumented `roster.json` and `jobs/*`; 3 binary moves in September |
| Cost after H1 (estimated) | 3,500-6,000 LOC | 2,500-5,000 LOC plus a `/stop` redesign of recycle |
| **Verdict** | **preferred, if a layer is built** | watch item only |

## Events coverage (revised)

| | (a) Terminal crash | (b) Kitty restart, planned or deaf | (c) Mac reboot |
|---|---|---|---|
| **H0** | manual rebuild; in-flight work lost | manual; 8 of 32 on the first pass (measured) | boot-resume with the `.start` bug and the 2.0/core shed |
| **H1** | page, then 1 command; in-flight lost; listed in the page | 1 command; in-flight lost; P2 lowers how often | 0 commands at login; in-flight lost |
| **H2** (after H1) | survives; `cc-reattach` (1 command, or 0 if hooked to kitty start) | survives | as H1 |
| **H3** | survives (measured once) | survives | attach restarts every interrupted turn, ungated |

## Agent actions on another live session, per hybrid

| Action | H0 | H1 | H2 | H3 |
|---|---|---|---|---|
| Kill or restart kitty | operator; agent dry-run refused (18:19:36Z) | operator's one command | rarely needed | rarely needed |
| Read another pane | needed; refused (20:14:48Z) | not needed | not needed | not needed |
| Type or submit a nudge | needed; refused (19:13:40Z) | not needed: launcher's own child | not needed for (a)/(b) | not possible from the shell |
| Close duplicates or husks | needed; refused (16:40:09Z) | prevented by locks and the ledger | `kill-session` refused (09-09) | `claude stop` UNMEASURED |
| End itself | allowed | allowed | allowed, as `/exit` | needs a `/stop` arm |

## Sequencing and total cost (estimated: C2 §5 and C3 §5 LOC, plus the skeptics' deltas; sessions at about 200-300 LOC each)

1. **Day 1.** Slice A, the fork fix: about 80 LOC, 1 session. Slice B, the rails: about 250 LOC plus
   bats, 2 sessions.
2. **Days 2-4.**
   - Slice C, restore mode, headroom and retire merge: about 500 LOC, 2 sessions.
   - Slice D: page about 150 LOC; positional prompt about 40 LOC after the pilot (expect fallback
     +250); 1-2 sessions.
   - Slice E, `cc-restore` and the crash page: about 350 LOC, 1-2 sessions.
3. **First planned restart.** The operator runs `cc-restore --restart-kitty` **with nothing else
   changed**. That is H1's rehearsal.
4. **Week 2.** Slice F: P2 build plus S1 diagnosis, about 100 LOC plus the C patch, 1 session. P2 is
   adopted at the second planned restart.
5. **Gate for H2.**
   - A one-session pilot authorized by the operator, on all 4 accounts. It checks Shift+Enter, titles,
     scrollback, the Background-session notification and the identity replacement.
   - Then an operator ruling.
   - If yes: a 3-6 week cutover behind a kill switch.

**Totals.**
- **H1:** about 1,400-1,900 LOC plus about 800 bats lines, about 12 files, 7-9 sessions, 5-7 working
  days.
- **H1 + H2:** about 5,000-8,000 LOC, 22-34 sessions, 5-8 weeks.
- **H1 + H3:** a comparable LOC range, plus ongoing vendor-churn upkeep.

## Risks (revised)

1. **H1 never preserves in-flight work.** The page makes the loss visible but does not undo it. About
   a third of events (kitty-only) are where H2 would have saved it.
2. **The first full restore is still live.** A dry run on a private kitty was refused (18:19:36Z).
   Slice B's rails and the "nothing else changed" rule limit the blast, but do not remove it.
3. **Main keeps moving** under `handoff-fire.sh` and `boot-resume.sh`: 54 commits in 7 days touched
   handoff-fire or it2-kitty (C3-skeptic-risk M5). Every slice must rebase on main, not on this
   branch.
4. **Positional-prompt behavior is unproven** through `reso-resume-one`'s dialog. Until the pilot
   passes, a nudge ships only as the budgeted expect fallback or not at all.
5. **Tombstones fail most on restored panes**: 12 of 14 layout-made panes left none
   (C2-skeptic-code second pass #5). After the first restore, the heartbeat carries the crash and
   reboot rosters.
6. **The classifier is inconsistent.** One agent `send-text '\r'` was allowed at 20:14:21Z, and a
   read-only `get-text` was refused 27 s later. No design here relies on either outcome.
7. **Layout conflict.** The brief fixes 2x2, while the restart lead's addendum says one row. Slice C
   keeps it a parameter.

## Open questions (UNMEASURED)

- Does `claude --resume <sid> "<prompt>"` submit after `reso-resume-one`'s resume-threshold dialog in
  2.1.284?
- Will the operator add the allow rules and the `autoMode.environment` line that the plan requests
  (`:41`)? If so, H0's manual steps become agent-runnable. H1 does not depend on it.
- How much kitty scrollback does a `NO_FLICKER` Claude pane hold today (R6)? That sets the true
  scrollback cost of H2.
- Why did 14 of 32 sessions write no tombstone, clustered on layout-made panes?
- Which errno killed kitty's talk thread? EMFILE is now put at 45% or less (C3 second passes). This
  decides whether P1 is worth shipping at all.
