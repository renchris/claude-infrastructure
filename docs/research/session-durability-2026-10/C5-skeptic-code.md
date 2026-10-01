# C5 skeptic report: code and evidence lens

Skeptic for C5 (Claude Code background sessions as the session layer), 2026-10-01. Read-only.
I made 0 `kitten @` calls, launched no `claude`, and signaled nothing. I wrote two CPU-sample
files in /tmp (`/tmp/sd-c5sk-t0.txt`, `t1.txt`) and then deleted them; this report is my only
other write. "Measured" means I re-ran the read-only command named. UNMEASURED means not checked.

## Answer

**C5 is not refuted, and it has no fatal flaw.** The two facts it rests on hold up when I re-run
them:

- The daemon, the pty hosts and the workers sit outside any terminal. `ps` shows daemon 9780 as
  `Ss`, ppid 1, tty `??`, and its spawner 38588 is gone.
- Our own recycle created the hidden fork. All 4 slash dispatches today line up 1:1 with a recycle
  that answered `2`.

But several supporting claims are thinner than the dossier says, and I found five integration
problems it missed. Three of them are measured:

1. Moving a session to another account (lr-transplant) has already crashed a bg fork.
2. `jobs/*/state.json` does not show whether a job is alive.
3. The daemon's environment cannot be pinned by a launcher.

Recommended conviction: **25** (the dossier gave itself 30).

## Verdicts on the key claims

**K1. Our own recycle created 9aa483e9: STANDS, and the evidence is stronger than the dossier's.**
- The watcher log says `answered '2' (Move to background and exit)`. Measured with `cat
  /var/folders/0s/.../T/handoff-recycle-4-1790882230-Tqk19k.log`.
- `~/.claude-next/daemon.log:49` reads `19:17:33.582Z bg claimed-spare 9aa483e9 (slash)`.
- `roster.json` `workers.9aa483e9.dispatch` reads `{source:"slash", launch:{mode:"resume",
  sessionId:".../09c26b2b-….jsonl", fork:true}}`. Measured with python json.
- Cited lines check out: `pane_bgwork_key` is at handoff-fire.sh:4280 and the "NOTHING LEFT TO
  DRIVE" comment is at :8533.
- New: every slash dispatch today pairs with a recycle log that answered `2` (`grep -l
  "answered '2'"` plus each file name's epoch): 05:04→`0ad2deb9`, 05:44→`03a7cd27`,
  19:17→`9aa483e9`, 19:59→`b363d8e6` (all Z).
- `03a7cd27` and `77aa4929` carry `detail: "Recycling this pane…"` in `state.json`.
- Small correction: the spare was not "pre-warmed". The daemon started at 33.407, the spare was
  spawned at 33.487 and claimed at 33.582, 95 ms later.

**K2. The fork is a hazard that no view could see: STANDS on the hazard, WEAKENED on "invisible".**
- The transcript confirms the sequence: 19:17:37Z `SessionStart:fork`; 19:23:14.876Z
  `<task-notification>`; TaskCreate ×4; 19:25:18Z the append to `/tmp/recycle-72-successor.txt`;
  19:25:57Z `cc-notify 41` and `cc-notify 4`; 19:26:18Z it stood down.
- `tokens: 761285`. `grep -l 9aa483e9 ~/.claude/cc-registry/*.json | wc -l` => 0.
- `grep -E 'bg (claimed-spare|spawned) [0-9a-f]{8} \(slash\)' ~/.claude-*/daemon.log | wc -l` => 18.
- Worse than reported: the append wrote a **wrong** diagnosis into the successor's brief ("a
  'fresh-context' recycle was not fresh"). The fork then had to send a "CORRECTION" over cc-notify.
- The carried task that woke it was the lead's own inbox watcher. Tool use
  `toolu_011GDNX7UX7bowPNQyfvHg6Y` in 09c26b2b's transcript, at 18:54:51Z, is
  `cc-await-ping --timeout 3300 --interval 15`, which watches pane 4's mailbox. Pane 4 now belongs
  to the successor. So the "land" kept alive here was a watcher on someone else's mail, not work.
- Not invisible:
  - `~/.claude/sessions/10156.json` has `"kind":"bg","jobId":"9aa483e9"`.
  - `cc-context` listed it. The fork found itself there at 74% (19:24:38Z).
  - Only the pane-keyed registry and `cc-sessions` were blind.

**K3. A bg session survives the terminal's death, and re-attach restores it: WEAKENED (scope).**
- I re-measured the process facts: `ps -o pid,ppid,pgid,tty,stat`, and `lsof -p 10027` =>
  `6u /dev/ptmx`, `7u /dev/ttys068`, `10u …1e4d8daa.pty.sock`.
- The E5 log trail matches: quaternary `daemon.log:114` claimed and `:116` settled (killed).
- The experiment did not test what the summary claims:
  - The worker was on a weekly-exhausted account, and it was `idle`/`blocked` when the server was
    killed. No turn, background Bash, Monitor or subagent was in flight, so "in-flight work keeps
    running" is **inferred**.
  - The E5 daemon was started by the agent's own Bash, not from inside the tmux server that was
    killed. So "daemon born inside the dying terminal" was not tested. Daemon 9780, born in kitty
    pane 4 and now `Ss`/ppid 1, is good indirect evidence.

**K4. The daemon stays up while a worker lives, exits 5 s after the last one, and spares do not
count: STANDS.**
- `grep -h 'shutting down' ~/.claude-*/daemon.log` tallies to 13 `idle_exit leases=0 live=0`,
  1 `shutdown_op live=1` and 2 `signal live=1`.
- Spare host 62173 was alive when daemon 61988 exited (quaternary `daemon.log:115-118`).
- 9780's etime is 01:14:18 and its `--spawned-by` names pid 38588. Measured with `ps`.

**K5. One daemon per config dir, and a plain `daemon stop` kills every worker: STANDS.**
- Quaternary `daemon.log:58-60` reads `shutdown requested via control socket` →
  `cause=shutdown_op … live_workers=1` → `bg settled bb4e00d0 (killed)`.
- `--keep-workers` reconnect is docs-only. Both `bg adopt:` lines in all logs read `adopted=0`.

**K6. A reboot leaves bg jobs dead, and the daemon does not restart them: STANDS as a claim. The
design built on it is WEAKENED (see M2).**
- `sysctl -n kern.boottime` => Sep 30 15:26:06.
- next `daemon.log`: `20:25:46Z … cause=signal … live_workers=1`, then
  `2026-10-01T05:45:17.863Z bg adopt: adopted=0 respawned=0 dead=1`.
- `77aa4929` reads `failed`. tertiary 2026-09-17 has the same adopt line.
- `Service install is disabled in this version` is in the binary.
- Partial support for "attach restarts a stopped job", which the dossier missed: quaternary
  `daemon.log:55-56` shows `bb4e00d0 (killed)` at 16:52:30Z, then `claimed-spare bb4e00d0 (fleet)`
  at 16:56:46Z. That is a killed job restarted under the same id. The restart path after a reboot
  is still UNMEASURED.

**K7. Pane identity is lost, and the daemon's env is frozen: STANDS, with one weak example.**
- `ps eww` on 9780 shows `KITTY_WINDOW_ID=4` and `KITTY_LISTEN_ON=unix:/tmp/kitty-48854`.
- On 10156 it shows `KITTY_PID=48854`, `CC_RR_SID=09c26b2b…`, `CLAUDE_CODE_SESSION_KIND=bg`, no
  `KITTY_WINDOW_ID`, and `TERM=xterm-256color`.
- Line citations:
  - session-register.sh:173 is right.
  - The lineage fallback is the `if` at **:184-188**; lines 181-183 are comments.
  - hf_bg_hosted at handoff-fire.sh:4960 is right.
- The `CC_RR_SID` example is weak, because 09c26b2b is the fork's own parent. Better evidence: the
  **unclaimed** spare 10202 already carries `CC_RR_SID=09c26b2b…` and
  `KITTY_LISTEN_ON=unix:/tmp/kitty-48854`. Measured with `ps eww -p 10202`. Whichever session claims
  it next inherits the lead's env (an in-process overlay is UNMEASURED).
- `CC_RR_SID`'s only consumer is bin/reso-resume-one:504/542, so the stale socket matters more.
  cc-kitty-socket:57-59 trusts an inherited `KITTY_LISTEN_ON` whenever the path is still a socket
  file.

**K8. Attach keeps kitty's title bars, and Claude's OSC title did not pass through: WEAKENED.**
- I re-counted `/tmp/sd-c5-attach.raw` (18,319 bytes) with python `re`: `ESC[>5u` ×**3** and
  `ESC[<u` ×**3** (the dossier says 5 each). The rest match: `?2004h` 4, `?1004h` 3, `?1000h` 6,
  `?1006h` 6, `?2026h` 18, OSC 0/2 0. OSC 8 appears ×2, so OSC is not filtered in general.
- The zero-title result is confounded. The worker could not call the model (weekly limit), so the
  auto-name that drives the title never ran.
- Title-bar drag: kitty v0.48.2 `mouse.c` sends title-bar presses to
  `handle_window_title_bar_mouse` ahead of child mouse reporting (fetched raw source). The live
  kitty check is UNMEASURED.

**K9. Only 2.1.260 and later have attach and respawn: WEAKENED (minor, not load-bearing).**
- Absence from `--help` is not proof of absence. The 2.1.215 and 2.1.220 binaries contain
  `bg-pty-host` (10 hits), the `"attach"`/`"respawn"` tokens, `bg adopt:`, and the attach help
  text "returns to agent view, Ctrl+Z drops back to your shell" (`strings | grep -c`).
- The live fleet is on 2.1.284: 31 `.claude-284/.bin/claude` processes plus 1 `claude.exe`
  (measured with `ps -axo command`). The dossier counted 33 in an earlier snapshot.

**K10. Idle unattached workers retire after 8 h, 1 h, or 60 s under pressure: WEAKENED.**
- The constants exist once each in `/tmp/sd-c5-strings.txt`: `ar=3600000`, `sr=28800000`,
  `Je=60000`.
- Counter-example, measured: tertiary `59aeaf2b` (state `blocked`, unattached, `bridgeSessionId`
  set) lived from 2026-09-29T21:19Z to the reboot at 2026-09-30T20:25:46Z
  (`uptime=83194s, live_workers=1`) with no retire line.
- `retireIfSettled` also has exemptions the dossier does not list: `in-progress`, `no-state`,
  `host-managed` and `recent-adopt`.
- So blocked forks can live until the reboot, not just 8 h.

**K11 (design). Reattach needs no claude launch, so no capacity gate and no nudge: WEAKENED.**
- `claude attach` is itself a `claude.exe` process, one per pane: 32 starting at once at today's
  load (`vm.loadavg` = 200/178/118 on 10 cores). Its cost is UNMEASURED.
- C5 overhead, measured with `ps -o rss`: each bg-pty-host 94,608-99,152 KB, each daemon
  195,136 KB, each idle spare 131,616 KB.
- Estimate (32 × ~97 MB): about 3 GB of extra RSS for the pty hosts alone, before any attach clients.
- CPU is not the problem: in a 20 s `ps time` delta the idle bg worker used 7.0%, against 6.7-14.8%
  for interactive sessions, and the hosts and the daemon used 0.1-0.2%.
- The `cc-attach` re-attach loop exists only in prose. Per bg-session-semantics-2026-09-25.md Q3:
  - `←` switches to the agent view inside the same client.
  - A clean detach (`/exit`, `/stop`) relaunches `claude agents` (`zZ({args:["agents"]})`).
  - So the wrapper never gets control back, and the pane is left on an account-wide picker.

## Fatal flaw

None found. Nothing I measured contradicts survival of (a) or (b) at the process level, and the
dossier already says not to migrate the fleet now.

## Missed risks

- **M1. Moving a session to another account breaks bg jobs (measured).**
  - Quaternary `daemon.log:105` reads `bg settled b363d8e6 (crashed): source session
    …/.claude-quaternary/…/13d7be20-….jsonl not found`.
  - The recycle of pane 32 (`handoff-recycle-32-1790884771-DUD9El.log`) logged `folded a re-created
    source stub … via lr-transplant`.
  - The quaternary copy is now `13d7be20-….jsonl.handed-off` (14:59-15:00 CDT); the live copy is
    under `~/.claude-tertiary`.
  - Because there is one daemon per account, every /limit-recover move becomes: stop the job in
    daemon A, start a new job in daemon B, give it a new id, rewrite the bg-map row. The dossier
    never covers this.
- **M2. `jobs/*/state.json` does not show liveness (measured).**
  - It holds the session's own last status. tertiary `59aeaf2b` still reads `blocked`: its mtime is
    Sep 29 16:21, its process died at the reboot, and no tertiary daemon has started since.
  - `74f00ab1` and secondary `967a1469` read `blocked` although their logs show them retired and
    `settled (done)`.
  - A reboot path that keys on `failed`/`stopped` misses jobs until some client starts that
    account's daemon and runs adopt. E4's "daemon-free disk roster" is unsafe.
- **M3. No launcher can pin the daemon's environment.**
  - 4 of today's 5 daemon starts came from an interactive pane's exit dialog: next 05:45Z and
    19:17Z, quaternary 05:05Z and 19:59Z.
  - Spares are started with the env of whoever started the daemon (spare 10202, K7).
  - "cc-bg-launch is the only thing that may start the daemon" can be enforced only if every other
    session gets `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF=1` and never opens the agent view. That is
    untested.
- **M4. C5 has to undo the current mitigation.**
  - The binary describes `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` as disabling "`claude agents`, `--bg`,
    /background, the on-demand daemon".
  - lr-fire-resume.sh:1093 and lr_recon/act.py:70 set it precisely to remove the keep-work option.
  - C5 sessions cannot run with it, so the dialog's `2` comes back wherever it is unset.
- **M5. The proposed hazard fix races the hazard.**
  - The carried task's completion *is* the wake. Here the fork's first output came 28 s after the
    notification (19:23:14.876Z → 19:23:42.645Z).
  - "Stop once inFlight.tasks == 0" therefore fires just as the fork starts acting.
  - The measured case carried only an inbox watcher. Stop the fork at once, or Esc out of the
    dialog when the only background work is a watcher.
- **M6. Detaching lands in the agent list.** The picker covers the whole account, and `attachers`
  is a set, so two panes can attach the same session, or a pane can attach the wrong one.
- **M7. Respawn flags point at short-lived paths.** `a5c0ee39`'s `respawnFlags` name a file that no
  longer exists (`os.path.exists` => False). A late respawn would start without that settings or
  MCP file.
- **M8. The kitty socket is still the actuator plane.** `cc-reattach` (`kitty @ launch`), recycle
  (typing `/stop`) and pane close all still go through the kitty socket that jammed today. C5 makes
  killing kitty cheap; it does not stop kitty from going deaf.

## Recommended conviction

**25.** It is a sound survival layer for (a) and (b), and it is no better than C2 for (c).
Integrating it is harder than the dossier's estimate: M1, M2, M3 and M6 each add work to
handoff-fire.sh and the limit-recover tooling, so 1,200-1,800 LOC is probably low (estimate, by
counting the subsystems touched). The independent hazard fix should be redesigned per M5 before
anyone builds it.
