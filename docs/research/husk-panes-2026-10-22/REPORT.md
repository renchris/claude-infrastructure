# Three lingering panes, 2026-10-22: what happened and why panes end "partial"

Question (operator): panes 85, 42 and 101 are open with no Claude Code in them. Should each be resumed or
closed, and what is the root reason panes end up like this?

Method: an 8-agent read-only workflow (one investigator per pane, a fleet census, a message audit, a
synthesis, and two skeptics, one on causes and one on the safety of closing). Raw material:
`investigators.md`, `synthesis.md`, `skeptics.md` beside this file. Corrections from the skeptics are
folded in below. Conviction is per cause.

## Verdict

- All three panes should be closed. None holds work: each worktree is clean, its commits are on its trunk,
  and every custody row is returned (re-measured 23:47Z). None should be resumed.
- One session that IS lost has no pane at all: lead `666022fd` (agent-context-sync, account next4). Lane
  K's self-close closed the lead's pane by mistake at 23:16:36Z, while the lead was in the middle of its
  round-23 write-up. That write-up is still uncommitted on disk. The lead should be resumed.
- The common root: **a pane's end state has no owner.** Several components each take one look at the
  moment of death, act once, paint once, and never revisit. So a pane is either closed by the wrong party
  or kept with nobody scheduled to close it, and its screen shows whatever the last writer believed.

## The three panes

| Pane | What really happened | Screen said | Right end state |
|---|---|---|---|
| 85 (570d3917, lane K) | It stalled mid-pytest at 08:17Z, and an unknown sender SIGTERMed it at 09:12Z. Three hours later the lead re-ran it **headless from its own Bash tool**. That run finished and landed the lane (9b8471d4, CI green). Its self-close then closed **the lead's** pane 16 instead of 85. | KILLED, "shell kept for resume", custody and uncommitted-work warnings. All of them were stale by 23:15Z. | Close it. Resume lead 666022fd. |
| 42 (18f95342, reboot-resume wave T2) | It finished cleanly (landed, custody returned) at 03:06Z. kitty's remote control was not answering, so the fullscreen guard could not read the window and returned "kitten-failed". The runner kept the shell. The single close attempt failed, and nothing retried when kitty came back at 04:28Z. | "✅ closed" in the title, but "ended, reason unknown" and "last pane of a fullscreen window" in the body. The last one was false: the window held 3 panes. | Close it. |
| 101 (r23-ra, teammate `ra-shut`) | A teammate split timed out under load (rc 124/EOF). kitty performed it about 5.5 h later. Nobody held the pane id, so no command ever arrived. The pre-`da0f61ce6` runner then turned the pane into a plain shell. | No title at all, and a row truncated to "pane is an ordinary…". | Close it. |

## Root causes (systemic)

1. **Self-close identifies "my pane" from inherited env plus process ancestry** (95%). It reads
   `$KITTY_WINDOW_ID`, and `pane_ownership` answers "mine" if the pane's process is anywhere above the
   caller. A `claude -p` started inside another session's pane therefore owns that session's pane, and its
   terminal self-close types `/exit` into the other session and closes it. The watcher re-checks nothing
   before typing (`scripts/handoff-fire.sh` `self_pane_id` ~:2384, `pane_ownership` ~:2491, the self-close
   target ~:14684, the watcher ~:11670). Stamp adoption accepted the
   lead's own *outgoing* fire marker as proof of ownership: `fired_marker_is_mine` greps the transcript bare
   (~:8915-8927), while `oi_marker_inbound` (`hooks/lib/origin-identity.sh:192-215`), which was built to
   reject exactly that, is never used on this path. *Skeptic correction:* the stale `16.json` stamp is a
   hygiene hazard (156 open stamps predate the running kitty), not the gate that admitted this close.
2. **Every close is one attempt at the moment of death** (95%). When kitty is deaf at that instant, or a
   later fact makes the pane closeable (custody returned, work landed, finished elsewhere), nothing durable
   tries again. The retry drainer handles only teammate rows. Self-close rows never expire. A
   never-launched pane writes no exit record, so `cc-pane-close` refuses it forever.
3. **Late splits under a stalled kitty** (90%, mostly fixed by `da0f61ce6`). The residual case is a guard
   that cannot read kitty at the deadline, which is cause 2.
4. **No single final writer for a pane's screen** (95%). Up to four writers paint at different moments: Claude
   Code's exit text, `cc-pane-runner`, the guard's stderr and the watchdog. The title is chosen before the
   close is decided, and nothing repaints. Raw internals reach the screen (exit 143, `state=UNKNOWN
   types=None`, "external-sigterm"), and so does jargon ("custody", "fleet launch line"). Every guard
   failure is reported as "last pane of a fullscreen window"
   (`bin/cc-pane-runner:277-281`, `bin/kitty-fullscreen-guard:754-755,989-994`,
   `hooks/lead-crash-watchdog.sh:1933,1991-2005`).
5. **A peer's death never reaches the lead that holds its custody** (85%). The designed channel,
   `scripts/custody-deathwatch.sh`, did not run once on 10-22, because autonomy-sweep's own time bound
   stops each tick before it reaches that phase. Its liveness check also counts a husk pane as alive. Left
   without a signal, the lead fell back on an unwrapped headless resume, which triggered cause 1.
6. **The one real loss produced no true signal.** The killed lead was logged "RECYCLE clean-exit" with no
   page. The headless run's end was paged as "suspected-oom-large-context", which was false.
7. Fired panes start in the originator's directory (`--cwd=current`), so a kept shell shows another
   session's branch and dirty marker. This is cosmetic.

Open: who sent the 09:12:40Z SIGTERM to 570d3917 (`sig_reached_wrapper=TERM`). It is in neither cc-reaper
nor kill-gate logs, and bash-commands.log for that day starts at 10:24Z.

## Fixes

Ranked, with file:line and the failing test each needs, in `synthesis.md` (F1-F8) and corrected by
`skeptics.md`. Implementation plan: `docs/plans/pane-end-of-life-2026-10-22.md`.
