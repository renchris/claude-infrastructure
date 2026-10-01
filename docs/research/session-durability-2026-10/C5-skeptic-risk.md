# C5 skeptic, operator-risk lens (2026-10-01)

This is a read-only review of `C5-cc-native-bg-sessions.md`. Every number is labeled **measured** (with
its command) or **estimated** (with its method). UNMEASURED means not checked. I made 1 of the 3 allowed
`kitten @ ls` calls. I did not launch `claude`, start a tmux server, or signal anything. I wrote one
temp file (`/tmp/sd-c5risk-ls.json`, the ls output) and deleted it.

## Answer first

**The dossier's facts hold up. Its "pilot it" recommendation does not survive the operator-risk lens.
Recommended conviction: 18 (the dossier says 30).**

- **Fatal flaw for C5 as the session layer: closing a pane no longer stops the session.** A bg worker
  survives a kitty death because nothing the pane does can reach it. For the same reason it survives
  every deliberate close: `/exit`, double Ctrl+C, double Ctrl+D, Cmd+W, kitty quit, and cc-teardown
  killing the pane's process. The worker then runs headless and acts on its own. On top of that,
  `claude stop` is not durable (measured below).
- **The incident C5 would make worse:** a half-migrated pilot account at the next kitty jam (scenario
  below).
- **The "do now" hazard fix only bounds the hazard.** It races the fork's own wake-up turn, and it
  misses forks that land on another account's daemon. That second case was measured today.
- **The cost is understated by about 2-3x.** The dossier counts 10-12 files. The repo has 43 non-test
  files keyed on `KITTY_WINDOW_ID` and 61 keyed on the registry.

## Verdicts on the key claims

| # | Claim | Verdict | Evidence (re-measured here unless noted) |
|---|---|---|---|
| 1 | Our recycle created 9aa483e9. No auto-resume, no self-acting spare | **stands** | `roster.json` → `workers.9aa483e9.dispatch` = `source:"slash"`, `launch.mode:"resume"` (python read). `jobs/9aa483e9/state.json` → `state done, tokens 761285, detail "session handoff complete; successor holds brief in pane 4"`. `handoff-fire.sh:4280-4292` is `pane_bgwork_key`, as cited. |
| 2 | The duplicate is a hazard, invisible to registry and cc-sessions | **stands, and the class is wider** | `grep -h -E 'bg (claimed-spare\|spawned) [0-9a-f]{8} \(slash\)' ~/.claude-*/daemon.log \| wc -l` → **18**. `grep -l 9aa483e9 ~/.claude/cc-registry/*.json` → 0 of 47 rows. `handoffs.jsonl` since 09-17 (python tally): **9** `recycle-bgwork-answered`. A second one today **lost** its work instead of duplicating it (missed risk 3). |
| 3 | A bg session survives the death of its attach terminal, and re-attach redraws it | **stands as process survival. Weakened as "Monitors live on"** | Not re-run, because the brief bars launching `claude`. The process tree is re-measured: `ps -axo pid,ppid,pgid,…` → pty hosts 10027/10130 and workers have their own pgids, and daemon 9780 has ppid 1. But a worker loses its exemption from retire as soon as its attacher dies: `retireIfSettled` returns `attached` only while `this.attachers.size>0` (2.1.284 strings, `/tmp/sd-c5-strings.txt`). Under memory pressure or a version-stale respawn, `drainableMonitors` count as settled and are drained (same function). So during a kitty outage, Monitor-only sessions are exactly the ones that get shed. |
| 4 | The daemon lives while any worker lives, and idle-exits 5 s after the last one | **stands** | `grep -h 'shutting down' ~/.claude-*/daemon.log` → every `idle_exit` line reads `leases=0, live_workers=0`. |
| 5 | One daemon per config dir. A plain `daemon stop` kills every worker | **stands, and it matters more than stated** | Quaternary log lines 58-60: `shutdown requested via control socket` → `live_workers=1` → `bb4e00d0 (killed)`. That stop was the remedy for a job that **came back after `claude stop`** (missed risk 2). Under C5, the same remedy kills every session on the account. |
| 6 | A reboot leaves jobs dead, and the daemon does not restart them | **stands. The restore path is worse than C2's** | `~/.claude-next/daemon.log`: `20:25:46Z shutting down (cause=signal … live_workers=1)` → `05:45:17Z bg adopt: adopted=0 respawned=0 dead=1`. Vendor docs (code.claude.com/docs/en/agent-view, fetched) say an opened session "continues the interrupted response from where it left off". So a mass attach restarts every interrupted turn, with no nudge gate. Past 48 h, the docs require "Press enter again to resume" in agent view, which is a manual step per session. |
| 7 | Pane identity is lost, and the daemon env is frozen | **stands** | `ps eww -p 9780` → `KITTY_WINDOW_ID=4`, `KITTY_LISTEN_ON=unix:/tmp/kitty-48854`, `CC_RR_SID=09c26b2b…`. `ps eww -p 10156` → the same, minus `KITTY_WINDOW_ID`, plus `SESSION_KIND=bg`. Severity is lower than implied: `CC_RR_SID` is read only inside reso-resume-one's expect (`bin/reso-resume-one:504,542`). |
| 8 | Attach keeps kitty's title bars. Claude's OSC title did not pass through | **weakened** | Drag and layout are plausible but UNMEASURED in kitty. The 0-OSC result is **confounded**: the probe ran on quaternary, which was weekly-exhausted ("You've hit your weekly limit", dossier E5), so no topic title could be generated. The impact is understated. `kitten @ ls` (call 1 of 3, python classifier on the titles): **29 of 33** pane bars carry Claude's own title (`✳ Kitty deadlock recovery handoff`, `◐ Session durability research`, …). That is the operator's at-a-glance board. Restoring it by `kitty @ set-window-title` moves title traffic onto the socket that jammed. Scrollback **stands**: `CLAUDE_CODE_NO_FLICKER=1` is set in 37 of 37 live sessions (`ps eww` loop) and comes from `~/.zshrc:284`. |
| 9 | Only 2.1.260+ has attach. The fleet is all 2.1.284 | **stands** (versions not re-run) | `pgrep -f claude-284/…/claude` → 37 to 39 processes. Install-dir dates (`ls -ld ~/.claude-2??`): 260 on Sep 3, 280 on Sep 22, 284 on Sep 28. That is 3 binary moves in September, and each one is a daemon/worker version-skew event (missed risk 7). |
| 10 | Idle retire: 8 h with remote control, 1 h otherwise, 60 s under pressure. Attached and pinned are exempt | **stands** | Re-read in `retireIfSettled`: reasons `attached`, `host-managed`, `pinned`, `recent-adopt`, `recent-input`. Log lines `bg retire …: idle-prompt, idle 8h` appear ×5 in four logs (grep). |
| — | Build cost: 10-12 files, 1,200-1,800 LOC, 5-8 sessions | **weakened (likely 2-3x low)** | `grep -rl KITTY_WINDOW_ID bin scripts hooks lib` (non-test) → **43 files, 45,528 lines**. `grep -rl cc-registry` → **61**. The change list omits all 5 `limit-recover/lr-*` files, `cc-teardown` (1,331 lines; it kills the pane's pid, at `:896`), `kitty-confirm-close`, `cc-pane-close`, `cc-notify`, and 6 hooks that run inside the worker (`mailbox-drain`, `session-beat`, `session-end`, `stop-failure-marker`, `lead-crash-watchdog`, `teammate-auto-shutdown`). The 2-3x figure is estimated from the file-count ratio. |

## Fatal flaw: closing no longer stops, and stop does not stay stopped

**1. Today, every stop control the operator and the agents have is a pane-side act.** Under C5, every
one of them becomes a detach.
- Vendor docs: "Detaching never stops a background session: `←`, `Ctrl+Z`, `/exit`, and double
  `Ctrl+C` or double `Ctrl+D` all leave it running. To end a session from inside it, run `/stop`."
- Cmd+W goes through `bin/kitty-confirm-close`, which tells the operator "A Claude Code session is
  running here. Closing this pane ends it" (`:313-318`). Under C5 that is false.
- `sessions.log` since 09-01 (grep and uniq) shows **719** `reason=prompt_input_exit` ends, about 23
  per day. Every one of them would become a live headless worker.

**2. cc-attach cannot fix this.** A deliberate close and a kitty crash both reach the attach client as
the same SIGHUP. Stopping the worker on SIGHUP would throw away the survival C5 exists to provide. The
operator's in-TUI keys (`/exit`, ^C^C, ^D^D) are consumed by the attach client itself.

**3. A headless worker acts on its own.** Measured on 9aa483e9: it was claimed at 19:17:33Z, woke on a
`<task-notification>` at 19:23:14Z, and ran TaskCreate ×4, `cc-notify 41` ×2, `cc-notify 4`, and an
append to another session's brief. Under C5 that is the outcome of an ordinary close of any session that
has a Monitor or a background Bash running. Remote control is on, so the retire window is up to 8 h.

**4. `claude stop` is not durable (measured).** `~/.claude-quaternary/daemon.log:55-56`:
`16:52:30Z bg settled bb4e00d0 (killed)` → `16:56:46Z bg claimed-spare bb4e00d0 (fleet)`.
- The stopped job came back 4 min 16 s later. `lr-upgrade.sh:964-975` records that "the conversation
  ran on two accounts at once".
- `:1079` still ends that path with a manual `claude stop` instruction for the operator, and the
  measured cleanup at 19:07:59Z was a whole-daemon stop.
- C5 rebuilds recycle and self-close around `/stop`, so this is a core primitive, not an edge case.
- What triggered the `fleet` re-claim: UNMEASURED.

## The incident C5 makes worse

**The setup:** a pilot on one account, then the next kitty jam (same class as 2026-10-01).

1. **Before the jam.** The pilot sessions cannot be recycled.
   - `hf_bg_hosted` refuses (`handoff-fire.sh:4960-4970`).
   - `verify_self_pane` proves "which pane am I" from the process tree (`:1986-2010`), and a worker's
     tree runs to the daemon, never to kitty.
   - `teammateMode: iterm2` is set in all 4 dirs (grep) and throws without a pane id (C4-hybrids.md:329).
   - Fleet-wide there were 145 `recycle-intent` and 96 `recycle-held-bg-work` events in 2 weeks
     (handoffs.jsonl tally). An estimated quarter of those land on the pilot account, and none can
     complete.
2. **The jam.** The operator kills kitty, as on 10-01.
   - The interactive accounts die and are restored as today.
   - The pilot workers keep running headless.
   - The new kitty reuses low window ids. Measured: kitty 48854 has ids 1, 2, 4, 6, 9 (`kitten @ ls`),
     and the registry row `32.json` pins `kitty_pid 48854`.
   - Any worker that wakes before `cc-reattach` runs sends cc-notify or send-text to pane ids that now
     name other sessions, because its context still says "notify pane 4".
3. **The rebuild.**
   - The operator either runs a second command (`cc-reattach`) next to the C2 restore, or a timer runs it.
   - A timer would also reopen panes the operator had closed on purpose, because those workers are
     still alive.
   - If two kittys are up (the staged kdw4 instance exists today, pid 94453), the multi-attach and
     size-fight semantics are UNMEASURED.
4. **The rollback.** Abandoning the pilot means a `claude stop` per job (operator-only, and not durable,
   see point 4 above) and then interactive resumes. Those go through `capacity-admit.sh`, which is the
   gate that shed 24 of 32 rows on 10-01.

## What the dossier gets right (credit)

- (a) and (b) are real process-level survival with no claude launch, so kitty-restart failures 1 and 3
  drop out.
- The fork mechanism of 9aa483e9 is correct.
- "Don't migrate now" is the right call.
- With no title pass-through, a `CC-DESK-n` marker would actually stick, which helps failure 2.

## Missed risks

1. **The stop inversion** (fatal flaw above). It also means `kitty-confirm-close` and the dialog's
   promise must change.
2. **`claude stop` is non-durable** (bb4e00d0, 4 min 16 s), and the only measured remedy is an
   account-wide daemon stop.
3. **Cross-account dispatch loses work (measured today).**
   - `handoffs.jsonl` 19:59:55Z: a recycle of pane 32 (sid 13d7be20, row `account: claude-tertiary`)
     answered `2`.
   - `~/.claude-quaternary/daemon.log:103-105`: `bg claimed-spare b363d8e6 (slash)` →
     `settled (crashed): source session …/.claude-quaternary/projects/…/13d7be20….jsonl not found`.
   - The transcript is in `~/.claude-tertiary` (`ls`). The carried background work died, and the
     dossier's hazard fix would search the wrong roster.
   - C5's `--bg --resume` under limit-recover account moves can fail the same way. The cause of the
     wrong-account dispatch is UNMEASURED.
4. **The hazard fix races its target.**
   - The task notification that empties `inFlight.tasks` is the same event that starts the fork's
     turn (9aa483e9 woke at 19:23:14Z and acted within its first turn).
   - A stop keyed on `tasks == 0` either kills that turn mid-tool-call or arrives after the acts.
   - It also keys on undocumented `roster.json` fields.
   - Holding the recycle (96 holds show the path exists) or a per-recycle
     `CLAUDE_CODE_DISABLE_BG_EXIT_HANDOFF=1` removes the fork instead of chasing it.
5. **Agent view is one key away.**
   - Docs: "`←` on an empty prompt, or `/exit` … return to agent view."
   - The attach process does not exit, so cc-attach's loop never fires.
   - The pane then lists every session on that account, and Enter on a stopped row resumes it.
   - That gives resurrection or double-attach from a stray keystroke. Whether this caused the
     bb4e00d0 `fleet` re-claim is UNMEASURED.
6. **The title board is lost or moved onto the jam point** (verdict 8). 29 of 33 bars are live today.
7. **Version skew per upgrade.** There were 3 binary moves in September. A new `~/.claude-NNN` does not
   change the old binary on disk, so `respawnIfIdleStale` does not fire. A newer client talking to an
   older per-account daemon is UNMEASURED.
8. **Monitors are shed exactly during outages** (verdict 3). Swap is off on this box
   (`sysctl vm.swapusage` → total 0.00M), and it has a history of memory-axis panics
   (`panic-compressor-2026-08-05.md`).
9. **The reboot path auto-continues interrupted turns** (verdict 6), so there is no per-session
   quota or appropriateness gate. Past 48 h it needs per-row Enters.
10. **Memory and process overhead.**
    - Measured: each `bg-pty-host` is about 95 MB (`ps -axo rss,command`, 2 hosts), the daemon is
      195 MB, and an idle spare is 131 MB.
    - The attach client's RSS is UNMEASURED.
    - Estimated for 32 sessions (pty hosts plus attach clients at spare-size, plus 3-4 daemons and
      their spares): **+6-9 GB**, on top of today's 20.9 GB across 39 claude processes (measured, same
      `ps`).
    - That is 64 more processes, plus a 32-client attach burst with no capacity gate on the
      kitty-restart path.

## Recommended conviction: 18

- Keep C5 as a watch item.
- Do not pilot it on a live account. Every sizable gap is above: stop inversion, non-durable stop,
  pilot sessions that cannot recycle, cross-account dispatch, and a cost that is 2-3x low.
- Fix the existing fork hazard at its source (hold, or disable the exit handoff for recycles), not
  by chasing forks.
- What would raise conviction:
  - a measured, durable `claude stop` (no re-claim within 1 h);
  - a vendor hook that can tell a deliberate close from a terminal death;
  - a non-confounded title pass-through test on an account with quota.
