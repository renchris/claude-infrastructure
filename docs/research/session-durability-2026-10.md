# Session durability: how Claude Code sessions should survive a kitty crash, a kitty restart or a Mac reboot

Research wave W2 of `docs/plans/kitty-deadlock-recovery-2026-10-01.md`, 2026-10-01. Five candidate
designs each got a researcher and two skeptics (each skeptic ran twice), then a judge. Detail:
[judge verdict](session-durability-2026-10/judge-verdict.md) ·
[W3 build plan](session-durability-2026-10/W3-build-plan.md) · dossiers and skeptic reports in
[session-durability-2026-10/](session-durability-2026-10/).

## Answer

**Build restore-first (H1) now, at 62% conviction.** A crash then costs a page plus one command, a
planned or deaf-kitty restart costs one command, and a reboot costs nothing. Sessions come back:
- in their old window groups, as one row of panes per fullscreen Desktop;
- with nothing that retired itself resurrected;
- with no session launched twice;
- with a note in each session's own inbox naming the background work that died.

Sessions with evidence of open work also get one recovery turn, passed as a launch argument rather
than typed into the pane.

**What H1 cannot do:** keep in-flight work alive. Every event still ends running turns, background
shells, Monitors, subagents and workflows; H1 re-engages them afterwards. Only a session layer
outside kitty could preserve them, and it is not worth building yet. Over the last 62 days there were
11 reboots against 5 kitty-only restarts, and no session layer survives a reboot, so restore is needed
on every path while a layer would help on about a third of events, at 3-4 times the cost.

## Ranked options

| Rank | Option | Conviction | Decision |
|---|---|---|---|
| 1 | **H1 restore-first**: C2's restore command, hardened by every skeptic finding, on main's live code, page-first, with an evidence-gated launch nudge | **62%** | **Build first** (build-plan phases P1-P5) |
| 2 | **C3 P2 kitty patch**: kitty's remote-control thread keeps serving after an `accept()` error, and signal handling is restored | **60%** | **Build second** (P6, in parallel); the operator adopts it at the second planned restart |
| 3 | H2: H1 plus a tmux host per session, as one cutover | 35% | Not now. Gate: H1 has carried one real restore, a real-Claude pilot passes, and the operator rules on scrollback |
| 4 | C2 restore command as specified | 40% | Superseded by H1, which keeps its sound parts and drops its auto-relaunch on crash |
| 5 | C3 socket fixes as specified (P1, P3, S1, S2 beyond P2) | 35% | Keep P2 only. The fd-limit watcher works only if the errno was EMFILE (now ≤45%); the restart page and breaker can cause outages |
| 6 | C1 tmux session layer, phased | 30% | Do not build as designed: its first phase leaves hosted sessions unable to recycle or self-close |
| 7 | C5 Claude Code background daemon as the session layer | 15% | Do not build. Closing a pane no longer stops a session, and `claude stop` was seen to come back after 4 min |
| 8 | Null: keep today's `/tmp` scripts as a runbook | 10% | Baseline only. They hardcode pid 610 and brought back 8 of 32 sessions on the first pass |

A conviction is the probability that the option, built as specified, gets the fleet through the
events it claims to cover without a manual rebuild, with net benefit. Fatal flaws cap it, and
unmeasured load-bearing claims lower it.

## What to build, in order

1. **First, in parallel (wave W3.1):**
   - **P1.** A recycle never forks a hidden copy of the session. Stand down the session's own
     watchers before `/exit`, and hold on real background work.
   - **P2.** Safety rails: the reaper whitelist, a bounded kitty call, a per-session launch lock, a
     global restore lock, and a guard against signals under bats.
   - **P6.** The kitty patch, built apart from the title band.
2. **Then (W3.2):**
   - **P3a.** `boot-resume.sh --event` mode, the 5-minute heartbeat roster, the `.start` fix,
     resolving recycle successors, the launched-once ledger, an account-headroom flag, and restore
     capacity mode (load term off, start gate at 6 per core, wait instead of shed).
   - **P3b**, in parallel. The layout script gains retry-instead-of-shed, one row per window
     restored to its old group, and fullscreen through kitty's own action.
3. **Then (W3.3) P4.** The inbox note for every restored session, plus the launch nudge for sessions
   whose classifier verdict shows lost open work. This phase opens with a one-session pilot.
4. **Then (W3.4) P5.** `cc-restore --restart-kitty --confirm <pid>`, the crash and deaf-kitty pages
   (no automatic relaunch), and the switch that moves reboots onto the new path.
5. **The operator's rehearsal (G1):** one planned restart with nothing else changed.

Estimated size: about 1,700 LOC plus 1,300 bats lines, across 7 dispatched sessions.

## What not to build

- **No automatic relaunch on crash.** A deliberate ⌘Q looks the same as a crash, and a crash cluster
  would loop.
- **No recovery prompt typed into panes as the main path.** `send-text` arrives as a bracketed paste,
  and a first `send-key enter` pass submitted none of 29 panes while exiting 0.
- **No fullscreen read-back that re-toggles.** Every read-back tried so far is blind on this Mac.
- **No restart page keyed on socket counts alone.**
- **No C5 migration and no phased tmux migration.**

## Findings this research adds

- **The kitty deadlock is proven.** kitty's remote-control thread was alive at 22:17 on 09-30 and gone
  by 11:57 on 10-01. Two preserved `sample` runs show it, copied to
  `session-durability-2026-10/evidence-kitty610-thread-samples.txt` because /tmp does not survive a
  reboot.
- **The same bug hit today's kitty.** It also drops signals, which is why SIGTERM was ignored and
  zombies piled up, and it has already fired on today's kitty 48854.
- **Our own recycle caused the hidden duplicate session (9aa483e9).** It answered "Move to background
  and exit", which forked a 761k-token copy that later acted on stale authority.
- **Recovery prompts mostly cost and rarely recover.** When 28 stale prompts were finally submitted
  they cost 6.8M cache-write tokens, and 14 of the 18 sessions that could reply had nothing pending.
  Hence: an inbox note for every session, and a turn only where there is evidence of open work.
- **Agents may now drive the operator's local kitty panes.** Since 15:59 `settings.json:1357` allows
  it, so the restore needs no operator for cleanup or for verifying a submit. Killing kitty, which
  ends every session, stays the operator's one command.
