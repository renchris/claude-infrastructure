# j: why new `claude` launches hang. Phase breakdown, root cause, and who loads secd

Written 2026-10-04 at 02:05 CDT, read-only. MEASURED means a command output or file on this box. INFERRED means reasoning from code or timing.

## Answer first

1. **The hang is not slowness, and the bg-spare daemon has nothing to do with it.** Four `claude` launches are frozen right now. Each has used about 0.13 s of CPU in total and has never registered a session:
   - pid 53373: 43 min
   - pid 3040: 40 min
   - pid 3121: 13 min
   - pid 4780: 13 min

   Because each has used ~0 CPU, this is an unbounded block, not CPU starvation. (MEASURED: `ps -o time` shows 0:00.13 for each; there is no `~/.claude*/sessions/<pid>.json` for any of them.)
2. **Where they block.** The main thread waits inside a synchronous keychain call, `SecItemCopyMatching`. The path runs `std::call_once` → claude.exe → `SecItemCopyMatching_ios` → `securityd_send_sync_and_do` → `mach_msg` wait on **secd** (MEASURED: `hang-4780.sample`). Nothing in the process sets a timeout on it.
3. **The call is Claude Code loading the system CA store.** CC 2.1.284 defaults its certificate stores to `Ee=["bundled","system"]`. Its function `It()` then calls `tls.getCACertificates("system")`. Bun answers that once per process (`call_once`) with a keychain query for certificates. That query goes through secd. (MEASURED from the strings of the 2.1.284 binary: `function Ht(){let e=a.CLAUDE_CODE_CERT_STORE ... return Ee}` and `Ee=["bundled","system"]`. The match between this code and the sampled stack is INFERRED, but the call_once + SecItemCopyMatching shape fits only this path.) The OAuth token read is a different path: it uses the `security` CLI with a 2 s timeout and a 30 s cache, falls back to stale data, and is bounded.
4. **Why secd does not answer: priority inversion under CPU saturation.**
   - In secd (pid 578), 84 XPC handler threads (priority 37) are parked in `semaphore_wait_trap`. At the same time, 5 threads at **priority 4 (background QoS) are in state R**: runnable but almost never scheduled.
   - secd got 0.46 s of CPU in 30 s (1.5 %).
   - The parked count keeps growing: 66, then 73 (lead's samples), then 84 (mine). Requests arrive faster than they are served.
   - The only work visible is sqlite3_step / NSKeyedUnarchiver item decoding.
   - With load 100–270 at default priority, background-QoS threads get almost no CPU. Every SecItem client therefore queues behind them, including the startup of every new claude.exe.

   (MEASURED: `ps -M -p 578`; `/tmp/concurrency-scale/j-secd-now.sample`; two `ps -o time` readings 30 s apart.)
5. **Before it became a deadlock, the same stall showed up as slowness.** Session ca3b517d (pid 21502, launched 00:26 CDT) sat **179.7 s** between process start and its first SessionStart hook. It then spent 35.5 s in hooks, so it became usable about 215 s after launch. The 4 current launches have not finished at all as load kept rising.
6. **SessionStart hooks are a secondary cost: 2–35 s, always bounded.** The hooks run in parallel, so the span is set by the slowest one. Across the full 12+-hook sessions (n=69, last 24 h), the startup span was p50 ≈ 2.5 s and p95 7.8 s, with a maximum of 35.5 s. Under load, hooks get cancelled at 16–35 s even though their nominal timeouts are 5–10 s, so timeout enforcement itself slips.

## Phase table: from typing `claude` to the first usable prompt

| # | Phase | What runs | Measured duration | Evidence |
|---|---|---|---|---|
| 0 | zsh interactive init (new pane) | `~/.zshrc`, gitstatus, iTerm integration | 0.76 / 0.87 s (n=2, load 65–88) | MEASURED `time zsh -i -c exit`. `zsh -ic` printed "gitstatus failed to initialize" under load (cosmetic). |
| 1 | Router | `claude-accounts --route interactive --max-wait 0 --max-age 600` (python3), then account map, then a detached charge | not timed: running it appends a route row. Cache-only by design, so INFERRED ≈ python cold start, about 0.3–1 s under load | `lib/claude-launcher.zsh:85`; the `--max-wait 0` contract at `:19-23` rules out a sweep, a lock wait or a keychain read on this path. |
| 2 | Worktree claim | `_cc_route_check`: `git rev-parse`; in an opted-in primary checkout, `worktree-pool.sh claim` | not timed (it would create a worktree). Measured earlier as an intermittent tail when the pool runs dry | `lib/claude-launcher.zsh:286-310`; COLD_START_100P.md §0 C3 |
| 3 | Config-mirror sync and resume pin | `_cc_resume_pin`, `_cc_sync_account "$_cfg"` | not separated. Shell start of pid 21502 (00:25:56) to the `cc-close-attrib` exec (00:26:24) was 28 s, but that includes the operator typing | `whence -f _claude_pinned` |
| 4 | `cc-close-attrib` wrapper | three `date` calls, `--settings` merge, FIFO/tee setup, then a backgrounded exec | about 0 s (the wrapper and binary have the same `lstart` second) | ps lstart for 21205 and 21502 |
| 5 | **Binary boot up to session registration** | Bun init, settings, **system CA load (SecItemCopyMatching → secd)**, keychain token prefetch, setup screens, registry write | normal: 1.2–2.8 s (n=8 older live sessions). Under load at 23:15–01:00 CDT: 4.5, 4.1, 2.1, 7.6, 8.6 s. Outlier **181.4 s** (ca3b517d). Now **∞** (4 processes, 13–43 min, 0.13 s CPU) | MEASURED: `sessions/<pid>.json` `startedAt − procStart`; hang-4780.sample |
| 6 | SessionStart hooks (parallel) | 12 user hooks plus 5 single-hook groups, plus project hooks (e.g. reso `mcp-auth-guard.sh`) | span across the 12+-hook sessions (n=69/24 h): p50 ≈ 2.5 s, p95 ≈ 7.8 s, max 35.5 s. 18 `hook_cancelled` records in 24 h | MEASURED `/tmp/concurrency-scale/j_hooks.py` over transcript `hook_success.durationMs` |
| 7 | First usable prompt | REPL accepts a turn once the hooks settle | process start to hooks done: 2.9, 4.4, 7.7, 10.3, 13.9, 16.4 s, then **215 s**, ordered as load rose through the night | `j_live.py` join |

Slowest hooks, p50 / p95 / max in seconds (n is the number of records):

| Hook | n | p50 | p95 | max |
|---|---|---|---|---|
| escalation-watch | 69 | 1.57 | 9.03 | 16.8 |
| config-mirror-assert | 69 | 2.71 | 6.87 | 22.4 |
| setup-task-symlinks | 69 | 1.31 | 5.57 | 11.1 |
| activation-watch | 69 | 1.29 | 5.53 | 11.1 |
| dod-persist | 44 | 1.24 | 5.28 | 16.2 |
| mailbox-drain | 27 | 1.58 | 5.19 | 5.6 |
| session-start.sh | 69 | 1.37 | 5.04 | 22.4 |
| session-index-start | 6 | 6.66 | 17.1 | 17.1 |

`net-context-stamp` printed 0.05–0.20 s even though it has no timeout set. All hooks that ran past their timeouts were seen in ca3b517d and fork 56c02192, while load was high.

Note on the "span p50 0.16 s" over all 137 startups: about 70 of them are bg or headless sessions that run only a `printf` hook. Use the 12+-hook figures above.

## Ranked causes

1. **Unbounded synchronous secd query during CC startup (root cause of the true hang).**
   - The default `CLAUDE_CODE_CERT_STORE` includes `system`, so every claude.exe process does one certificate enumeration through secd on its main thread, with no timeout.
   - When secd stalls, the launch freezes before it ever registers a session. No UI, error or hook appears.
   - Evidence: the four 0-CPU unregistered processes; hang-4780.sample; the `Ee`/`Ht`/`It` code.
2. **secd starved by load: a background-QoS DB worker holds everyone else up.**
   - 5 runnable priority-4 threads, 84 parked handlers and 1.5 % CPU (MEASURED).
   - The queue only drains when load drops. That is why the 00:26 launch completed after 180 s and the 01:20–01:51 launches have not.
   - What owns the system's CPU (load 150–270, about 40 % sys) is a sibling axis (a/b/e/g files), not this one.
3. **SessionStart hook fan-out under CPU contention: 2–35 s, bounded.**
   - A turn is not accepted until the slowest hook finishes or is cancelled.
   - Cancellation overshoots the nominal timeout by 2–3x under load: dod-persist (5 s timeout) was cancelled at 16.2 s; session-start.sh (10 s) at 22.4 s.
4. **Ruled out, or not on the interactive path:**
   - **bg-spare daemon.** pid 87268 is not a stale spare. It is a spare that was claimed at 02:30Z by a slash command (`daemon.log:174 bg claimed-spare 032aa97f (slash)`). It is a live background session in `wt-cc-142226-72029`: tty ttys007 is the pty-host's pty, it has 10+ Bash children and an ms365 MCP, and `claude attach 032aa97f` (pid 90282) is attached to it.
     - The current unclaimed spares (e7df3091 for quaternary, 39bfa9cf for next) sit idle at 0 % CPU, listening on their claim sockets.
     - Only `claude attach` connects to the `control.sock` files (lsof -U peer match).
     - Spares are claimed only by daemon dispatch (`bg claimed-spare (shell|slash|fleet)`, `K7r` fleet_view_dispatch), never by a typed `claude`.
     - Its 1.9 GB RSS is a 10-hour working session. The kill switch exists if it is ever wanted: `tengu_bg_spare_enable` (GrowthBook) and `daemonColdStart` / `CLAUDE_CODE_DAEMON_COLD_START`.
   - **Token keychain read.** It is bounded: `security find-generic-password` with `timeout:2000`, a `dXn=30000` ms cache and stale-serve. It uses the legacy securityd, not secd (the unified log of `security[33442]` shows only `SecKeychainSearch*` calls).
   - **Instructions size.** It loads at the first turn, after startup, so it is not on the hang path (not measured further).

## Who loads secd (lead's refocus question a)

From the unified log, `log show --last 30m --predicate 'process=="secd"'`, filtered to connection, insert, update and delete events (MEASURED, `/tmp/concurrency-scale/j-secd-log30.txt`):

- **Headless Chrome started by `agent-browser`** accounts for most new secd peers in the window:
  - 8 or more instances in 30 min (peer pids 98366, 98517, 75415, 39354, 7579, 70284, 2868, 17068, 33442, resolved through `log show --predicate processID==…`).
  - Each runs with a fresh `--user-data-dir=$TMPDIR/agent-browser-chrome-<uuid>`.
  - Each pairs with an `[com.apple.securityd:item] inserted` event: 7 inserts in 30 min.
  - Live ones have agent-browser as parent (pids 78205, 61320, 57731).
  - INFERRED: Chrome creates a per-profile keychain item on each fresh profile. These are writes, which need the DB writer lock.
- **claude.exe at startup**: one system-CA enumeration per process (pids 3121 and 4780 appear as peers). Typed-launch rate is low: 1–7 wrapper launches per hour, 48 in 24 h (close-records). On top of that come daemon bg dispatches (31 claimed spares since daemon start, plus spare respawns) and any headless `claude` a script starts.
- **Not via secd**:
  - `bin/claude-accounts` (`:535` `security find-generic-password`, 10 s timeout), `cc-relogin:333` and `handoff-fire.sh:9884` use the legacy CLI path. They do suffer under the same load: `claude-accounts.log` has 537 `keychain-error path=timeout` lines, the latest at 06:17–06:18Z with 34–50 s elapsed on all 4 accounts.
  - CC sessions' token reads (CLI) also take the legacy path.
- **Unattributed.** Long-lived XPC clients such as CKKS/iCloud keychain, Dia, accountsd and cloudd do not show up as new connections. They could hold some of the 84 parked requests. Attributing them needs `spindump` or root `lsmp`, which this brief rules out.

**(b) Did the queue rebuild?** secd has **not** been restarted yet: pid 578 is still running, started 30 Sep 15:29. The latest sample (02:01 CDT) has 84 parked threads, up from 66 and 73, so the queue is still growing. Re-check after the operator restarts it with `pgrep -x secd`; `sample <pid> 1 -file f`; `grep -c semaphore_wait_trap f`; `ps -M -p <pid>` to look for priority-4 R threads. Prediction (INFERRED): if load stays above about 60, the queue rebuilds within minutes, because the cause is CPU starvation of background QoS, not a corrupt secd state. If load falls, it drains and the 4 hung launches complete by themselves.

## Fixes

| # | Fix | Where | Owner | Effect |
|---|---|---|---|---|
| F1 | Export `CLAUDE_CODE_CERT_STORE=bundled` for every claude launch, which removes the system-CA SecItem query | `_claude_pinned` in `~/.zshrc:457` (next to `export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`), or `~/.claude/bin/cc-close-attrib` before the exec at ~`:314`. Setting it in `env` of `settings.json` also works but is the operator's file. | rc or wrapper: agent-drivable through a migration. `settings.json` `env`: operator only | Takes secd off the startup critical path. Risk: a TLS-intercepting proxy would need `NODE_EXTRA_CA_CERTS`; none is configured (all 4 `settings.json` env blocks are empty for CA/TLS). **Not yet verified by a live launch.** Verify with one launch: `CLAUDE_CODE_CERT_STORE=bundled` plus `CLAUDE_CODE_DEBUG_LOGS`, then grep "CA certs: stores=bundled". |
| F2 | Launch watchdog: if `~/.claude*/sessions/<pid>.json` has not appeared within N seconds (for example 20) of the exec, print `◆ claude pid X stalled pre-registration for Ns (likely secd/keychain); see …` to the pane's stderr and record it in a jsonl. Never kill. | `cc-close-attrib` (it already has the child pid and a backgrounded exec) | agent-drivable | Turns a silent hang into a named one. |
| F3 | Throttle agent-browser's fresh-profile Chrome launches: reuse one persistent `--user-data-dir` (or a pool) instead of a new temp dir per launch | agent-browser invocation and its config (the `agent-browser` skill) | agent-drivable | Removes the recurring secd inserts (≈14 per hour seen). |
| F4 | Upstream: do the system-CA load off the main thread, with a timeout, or lazily | Anthropic or Bun | upstream | The real fix for item 1. File it with hang-4780.sample. |
| F5 | Hooks: fold the 12 hooks into one dispatcher process, or mark non-gating ones `async`. Candidates by p95: escalation-watch, config-mirror-assert, setup-task-symlinks, activation-watch, dod-persist, session-index-start | `~/.claude*/settings.json` `.hooks.SessionStart` | **operator-only** (settings.json); the hook scripts themselves are agent-drivable | Caps the 7.8 s p95 and 35 s tail. |
| F6 | Give `net-context-stamp.sh` an explicit `timeout` | settings.json | operator-only | Hygiene; it measured 0.2 s or less. |
| F7 | Reduce the load itself (fewer concurrent sessions or agent-browser instances while load is above about 60); a cap on live sessions | fleet policy | operator / sibling axes | It is the only thing that unwedges secd's background-QoS worker. |

## Adversarial pass (gaps checked)

- *"The hung processes are just CPU-starved, not blocked."* Refuted: 0.13 s CPU in 13–43 min, sleeping state, and the main thread in `mach_msg`.
- *"The bg-spare daemon is the blocker."* Refuted with lsof and daemon.log evidence (above).
- *"The CA-store attribution could be wrong (it could be the token read)."* The token read uses `security` CLI subprocesses (`OSe`) with `timeout:2000`, not an in-process SecItem call, and it is not wrapped in call_once. Residual risk: the claude.exe frame (+0x559580) is unsymbolicated, so this stays INFERRED until F1 has been run once under load.
- *Not done (brief limits):* timing the router and worktree-claim phases (both write state), and naming the long-lived secd clients (needs root).

Artifacts in `/tmp/concurrency-scale/`:
- `j_hooks.py`, `j_hook_rows.json`: hook spans
- `j_live.py`: process start to registration to hooks
- `j-secd-now.sample`: secd, 84 parked threads
- `j-secd-log30.txt`, `j-peerlog.txt`, `j-peers.txt`: secd clients
- `j-lsofU.txt`: unix sockets
