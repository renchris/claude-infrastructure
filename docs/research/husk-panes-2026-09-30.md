# Husk panes after the 2026-09-30 reboot: why seven panes sat at a bare shell

Measured 2026-10-01 03:17–03:50Z by a 12-agent forensic workflow: six investigators, each followed by an adversarial verifier at xhigh effort. Scratch evidence: `/tmp/husk-forensics/`. That location is volatile, so the load-bearing lines are quoted below.

**Operator contract:** a session that recycles or hands off resumes into Claude Code in the same pane. A session that closes closes its pane. A pane left at a bare shell after Claude exits is a defect in either case.

## Answer

Of 39 kitty windows, seven are husks. Only one of the seven (pane 55) was killed. Five were Agent-Team teammates their leads retired on purpose, and one was an ordinary operator `/exit`. They are all husks because of one structural fact: **nothing closes a pane from inside after Claude exits.** `bin/cc-pane-runner:46-51,83,211` execs `zsh -l -i` when its command returns, and the `claude()` launcher runs Claude as a child of the window's login shell. A pane therefore closes only if an *external* close through kitty remote control succeeds. Tonight every such close either timed out against an intermittently unresponsive kitty socket or was never attempted. A retry exists only on the self-close path after `/exit` (4 tries within about 48 s). No path keeps a durable retry, and no alarm reaches anyone.

## Census (kitty pid 610, `kitten @ ls` rc=0 at 03:25:53Z, process table at 03:19Z and 03:26Z)

| pane | sid | account | role | how it ended (UTC) | why the pane stayed |
|---|---|---|---|---|---|
| 33 | 74148f20 | tertiary | teammate lt-wrap of lead 4726bdf3 (pane 32) | graceful exit 01:55:41Z, 1.9 s after the lead's shutdown_request | vendor close refused by the it2-kitty composer guard (kitty `ls` timed out, UNKNOWN); TeammateIdle close deferred on "tool in flight" and never retried |
| 57 | 210a2d21 | tertiary | teammate heat-rebase of lead c82dd5b9 | graceful exit after shutdown_request 01:40:21Z | vendor paneId `[invalid id]`; teammate-auto-shutdown close rc=124 (20:39:08 CDT) |
| 58 | 019f2c02 | next | teammate acct-routing of lead 6a000e4a (pane 56) | exit 01:26:02.27Z, 4m20s after shutdown_request; no SessionEnd ran | teammate-auto-shutdown close rc=124 (20:16:58 CDT); vendor close refused (UNKNOWN) |
| 59 | efbb2abe | next | teammate reapguard of lead 6a000e4a | exit 01:26:02.37Z, 100 ms after 58; no SessionEnd | close rc=124 (20:13:20 CDT); vendor close refused |
| 60 | cac9f716 | tertiary | teammate landing-shots of lead c82dd5b9 | graceful exit after shutdown_request 01:53:44Z | vendor paneId `[invalid id]`; TeammateIdle deferred on "tool in flight"; no close attempted |
| 55 | c82dd5b9 | tertiary | fired wave-2 lead w2-reso-review, `/goal` live | **SIGTERM 02:26:08Z, exit 143 at 02:26:12Z, by devserver-gc** | nothing relaunches or closes a killed lead's pane; the death page went nowhere |
| 44 | 6912e153 | next | operator-opened window (`/bin/zsh -l`), /limit-recover session | operator typed /exit or ^D at 00:32:17Z (prompt_input_exit) after "Good to close? yes" | a plain shell window; nothing closes it after a deliberate exit |

The banners on 58 and 59 read `unlanded:7`. That was true when they were painted (01:26:52Z). The commits landed at 21:15:30 CDT, so the banners are stale; the sweep's `clean` is correct.

## Root causes and defects

1. **devserver-gc killed a live lead.** FIXED in `5a673c141`. `scripts/devserver-census.sh` reap_pid matched the full `ps -o command=` of each parent against `*"pnpm"*" dev"*`. The lead's ~26 KB brief in argv matched, so the walk TERMed `68633 68787 …`: the cc-close-attrib wrapper and claude. `has_live_owner` keys on cwd and missed it, because the lead's cwd was a different worktree from its server's. At the time, the lead had been blocked for 1942 s on an unanswered permission prompt (`git push --force-with-lease … origin landing-overview-wip`).
2. **No pane closes from inside.** `bin/cc-pane-runner` falls back to an interactive shell after any exit, and the `claude()` launcher returns to the login shell. Every close depends on kitty remote control.
3. **kitty remote control is intermittently unresponsive.** It does not accept connections for 10–60 s at a time: netstat Recv-Q 101, then bursts of accepts about 60 s apart. Each failed call hits the client's hard 10 s read timeout. Episodes: 01:40:43–02:35:39Z and 03:08–03:22Z. These are ruled out: a stuck client, the 256-peer limit, backlog overflow, and App Nap (kitty was the focused app for the first episode). The episodes loosely track machine load (1-min load 58–266 on 10 cores). That link is inferred, not proven.
4. **Teammate closers each make one attempt and give up.** Three closers are involved: `hooks/teammate-auto-shutdown` (rc=124, and the failure page is damped), the vendor's lead-side close (paneId `[invalid id]`, or a refusal from the composer guard in `bin/it2-kitty` when `kt ls` times out), and the SessionEnd orphan-pane closer (`hooks/session-end.sh:36-84` → `scripts/teammate-orphan-pane-close.sh`). The last one looks the member up in a team `config.json` the vendor has already rewritten, so it finds nothing. None of them retries.
5. **Self-close aborted on an unreachable kitty and never retried.** Between 01:40 and 02:36Z, 10 `self-close --terminal` attempts read `it2 session list` rc=124 as "pane UNREACHABLE" and aborted before `/exit` (safe). Five sessions still hold panes they meant to close: **32, 48, 56, 62, 63**. Nothing durable records this.
6. **lead-crash-watchdog paints a retired teammate as KILLED.** It has no teammate arm, and teammates launch without cc-close-attrib, so they have no close record. The result is a "Resume it here" banner on a pane that should be closed. Its desk page fails rc=3 on every death (no desk role file), and so do all 32 handoff-alarm records (31 at rc3, 1 at rc124).
7. **The close-verdict reader is contaminated.** `cc-husk-sweep` close_of and the watchdog's `pane_last_close` grep the whole JSONL for `Good to close: [a-z]*`. In a session that never wrote a close, the last match comes from the CLAUDE.md instructions attachment ("An honest `Good to close: no …`"), so the verdict reads `no` / RESUME.
8. **cc-husk-sweep names the wrong session** for 57, 60 (both resolved to the dead lead c82dd5b9) and 44 (resolved to a 5 s headless permission-gate transcript). The causes compound:
   - the scrollback regex accepts only a bare `claude --resume`, never the watchdog's `claudeN --resume` (:206/:210);
   - `it2-kitty session read` ignores `-n` and returns only the visible screen;
   - a failed read falls through silently (:201);
   - the transcript fallback takes the newest non-live jsonl in the cwd, skips nothing already claimed, and runs no sid dedup before `--resume`;
   - the launcher defaults to `claude` (the wrong account) for tertiary sessions;
   - R_CWD is the shell's cwd, not the session's;
   - the sweep never reads the watchdog's exact `registered session=… tty=… pane=N` lines;
   - a pane-list failure prints "no husk panes" and exits 0;
   - it would RESUME retired teammates.

   Today, plain `--resume` would type c82dd5b9's resume line into three panes.
9. **Recycle messages mislead.** A recycle-dead alarm says "/exit landed … holds NO claude" even when its own probe read `cc`. An unreadable composer is logged as `recycle-held-draft`, and a resolver rc3 abort emits no outcome row (pane 3 at 02:36:07Z).
10. **Mutating kitty calls may run late (inferred).** A request whose client already timed out stays queued and is read later, so `send-text` or `close-window` retries can double-deliver.

## Fix plan (the follow-on session works this; items 1 and 2 from the list above have their own owners)

- **F-a, close from inside.** When the runner's or launcher's claude child exits with intent CLOSE (teammate shutdown approved, self-close terminal, operator `/exit` in a pane the fleet launched), exit the pane instead of exec'ing a shell. A recycle keeps the shell: it must stay disabled while a recycle intent is pending. This removes the dependency on kitty remote control for closing.
- **F-b, durable retries.** A failed teammate close, or a self-close that read UNREACHABLE, writes a durable row and retries once `kitty @ ls` answers. Never damp a close failure into silence. Treat rc 124 on a mutating verb as "may still execute": re-read state before retrying.
- **F-c, watchdog.** Add a RETIRED class for a teammate exit after a shutdown_request (keyed on `--agent-id` or the transcript's `teamName`). Its banner says "close this pane", not Resume. `pane_last_close` reads assistant text only. The death page needs a destination that exists.
- **F-d, cc-husk-sweep.** Add a watchdog-registration arm first. Read the full scrollback (fix the `it2-kitty` `-n` handling). Return UNKNOWN when the read fails. Remove the transcript lottery as an identity source. Take the launcher and cwd from the transcript's real store. Add a teammate verdict that never resumes. A list failure exits 2. close_of reads assistant text only.
- **F-e, recycle messages.** Pick the alarm text by verdict, add `recycle-held-unreachable`, and give every abort an outcome row.

## Open

- Who or what ended 58 and 59 together at 01:26:02Z, 4m20s after their shutdown, without SessionEnd running.
- What stalls kitty's accept loop. The next episode needs a live `ps -M -p 610` and `sample` capture.
- The session-index SessionEnd hook fails with "database is locked (5)" on several exits. This was seen, not investigated.

## Second round, 2026-10-01: panes 55, 69 and 76 after F-a to F-e landed

Three husks were still open after the fix wave landed (F-e `476712b2f`, F-b `7eb551b39` `f57055245` `3156c4dcd` `aa1e2deb5` `107755b5b`, F-a `74baff1ee`, F-c `b6bf10c0c`, F-d `bbc40d207`). All three ended before those fixes were live, so they show the pre-fix failure, plus two defects the wave had not covered. Evidence: `~/.claude/logs/teammate-lifecycle.log` lines 32205-32295, `lead-crash-watchdog.log` registrations, and each session's transcript.

| pane | session | what it was | why it stayed open |
|---|---|---|---|
| 76 | b531a87b | teammate husk-fa of this wave | Its first idle close (00:16 local) fired while it was **still working**, waiting on an auto-backgrounded bats run through a Monitor watch. That close timed out (rc 124, kitty stalled), but the hook still removed the teammate's worktree. The real close after its shutdown approval (00:18) timed out again; the page was damped and nothing retried. |
| 69 | 5ea2497e | teammate trunk-reds of lead 918b909f | Retired normally; the idle close timed out (rc 124, 00:26:45 local), page damped, no retry. |
| 55 | c82dd5b9 | wave-2 lead killed by devserver-gc | Never meant to close. Its orchestrator later abandoned its custody as collected (03:59Z), but nothing could close a pane on that ground. The operator could only press Ctrl-D. |

### Defects found, and fixed in this round

1. **The idle closer reaped working teammates.** `_tool_in_flight`'s background arm in `hooks/teammate-auto-shutdown.sh` recognised only `run_in_background: true` launches. The live transcript corpus also holds 2,818 foreground Bash calls that the harness **moved to the background** at their timeout, and 646 Monitor watches. Both outlive their tool call and finish with the same `<tool-use-id>` notification. husk-fa was on exactly that pair (worktree removed under a running suite), and husk-fc's pane was closed at 23:54 while its process lived on. Fixed: the launch set is read off the result text for all three shapes.
2. **The retry queue had no working clock.** The drainer ran only at the end of the 600 s `teammate-reap-alarm` launchd job. launchd never starts a job while its previous instance lives, and the chained `assignee-pane-residency.sh` held one instance (pid 5152) for 4h52m. Fixed in `107755b5b`: every SessionEnd that finds a row also kicks the drainer, rate-limited to once per 5 minutes.
3. **Every pane close needed kitty remote control,** which refused connections (`connection refused` on `/tmp/kitty-610`, a full accept backlog) for over an hour on 2026-10-01. So neither agents nor the drainer could close anything, and this lane's own `self-close --terminal` aborted (safely, with a durable row). Fixed: `bin/cc-pane-close` closes a pane by SIGHUP to its window shell (kitty closes a window when its process exits). It has four fail-closed gates: identity by watchdog registration plus window start time; nothing live; a teammate, an assistant `Good to close: yes`, or a custody abandon/return after registration; no uncommitted work. Handing the drainer's teammate rows to it whenever kitty is deaf is written and tested but NOT landed: the auto-mode classifier refused its commit, so it waits for the operator.

### Still open

- Why kitty's accept loop stalls (unchanged from the first round's Open list). The SIGHUP path removes the dependency for closing, but not for typing, so recycles and the `/exit` of a self-close still need the socket.
- A killed lead whose work is later ruled done still carries a "Resume it here" banner until it is closed. `cc-pane-close` closes it, but nothing repaints it. The pane-72 successor owns this.

## Third round, 2026-10-01 12:02 CDT: kitty's remote-control thread is gone, not stalled

Found while investigating why the right-click move menu stopped appearing (the menu's first step is `kitty @ ls`). The live capture the Open list asked for:

- `netstat -anv -f unix`: **128** connections queued on `/tmp/kitty-610`, every one holding its unread 80- or 101-byte `kitty @` request. 128 is the listen backlog, so further connects fail at once with `connection refused`. Load average 108.
- `sample 610 3` (raw file was in /tmp and is not kept; the thread list is copied here): threads Main (idle in `mach_msg`), `KittyChildMon` (in `poll`), NSEventThread, CVDisplayLink, DiskCacheWrite. **No `KittyPeerMon`.** That is the thread that accepts and serves remote-control peers.
- kitty 0.48.2 `child-monitor.c` `accept_peer()`: any `accept()` error other than `EINTR` returns false, and `talk_loop` then does `goto end`. The thread exits for good. The socket stays bound and listening, `talk_thread_started` stays true so nothing restarts it, and the `perror` line goes to kitty's stderr, which is `/dev/null`.

So this episode is not a stall. Remote control is dead until kitty restarts. The errno is unknown because the only record went to `/dev/null`. The listen socket is blocking, which rules out `EAGAIN`. kitty held 56 fds against launchd's soft limit of 256, and kitty never raises that limit. `EMFILE` would need about 200 peers held at once, which `PEER_LIMIT` (256, checked only after `accept`) permits under a fleet-wide burst. `ECONNABORTED` and `ENOBUFS` under memory pressure remain possible. A throwaway-kitty reproduction (ulimit 64, flood of idle connections) was written but refused by the permission layer, so the mechanism is read from source, not reproduced.

The earlier "stalls of 10–60 s" were a different, recoverable state: the thread was alive and slow. Each stall builds the queue, and every queued client that times out and gives up is another chance for an `accept()` error that ends the thread.

What follows: anything that needs `kitty @` (the move menu, recycles, typed `/exit`, `kitty-confirm-close`) stays broken until kitty restarts. The move menu now says so on screen instead of doing nothing (`bin/kitty-pane-menu` `alert_unreachable`). The upstream fix is a single line in `accept_peer`: treat a failed `accept()` as "skip this peer", not "stop serving".
