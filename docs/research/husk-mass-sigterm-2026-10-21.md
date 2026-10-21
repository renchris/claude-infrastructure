# Mass SIGTERM and 9 husk panes, 2026-10-21 10:24:40 CDT

Question: why are so many panes "partially closed" (Claude Code gone, pane still open, title
`⛔ KILLED <sid8>`), and is that intended?

## Verdict

- **The kill was unintended.** One agent's own cleanup line misfired into a machine-wide pattern kill,
  and the guard built for exactly that shape missed it.
- **The open pane is intended.** A session that dies on a signal keeps its shell so it can be resumed
  in place. Nothing resumes it automatically: the policy is to page, not to auto-recover.

Conviction 95%. Method: a 9-agent read-only workflow (six independent hypotheses, a synthesis and two
skeptics). Neither skeptic refuted the finding. Each claim below was then re-checked by hand.

## What happened

1. At 15:24:35Z the fired lane `e18a6a7c` (reso `w2-edge-cache`, account next2) ran a single Bash call
   that did a multi-line `git commit -m "…"` and then
   `pkill -f "next start" -P $(lsof -ti tcp:3026 | head -1)`. It is logged in its transcript
   (tool_use `toolu_01QDNAjm3GiicLgaU1s9Gz6V`) and in `~/.claude/logs/bash-commands.log`. Commit
   `6c1ae8c` is stamped 10:24:39 CDT. The first exit 144 fired at 15:24:40.239Z.
2. macOS `pkill` uses BSD getopt, which stops reading options at the first operand. So `-P <pid>` was
   not a scope. Both words became extra patterns OR'd with "next start". Measured read-only:
   `pgrep -f zz_nomatch -P` selects 2 processes, while `pgrep -P 1 -f zz_nomatch` selects 0.
3. `-P` is a substring of `HANDOFF-PING`. Every fired session's brief contains that token, and
   `handoff-fire.sh` passes the brief in argv to both `claude` and its `cc-close-attrib` wrapper. All 9
   sessions whose argv carried such a brief got SIGTERM (exit 143, `sig_reached_wrapper=TERM`):
   - the six B13 r22 lanes (panes 460-465);
   - 4da72f17 (pane 27);
   - c9bdd035 (pane 369);
   - the tm-upstream W5 lead 95d2333c (pane 453).

   Every survivor's argv lacks `-P`: the leads were launched without that token or relaunched with
   `--resume`. pkill also spares its own ancestors, so the caller lived.
4. Every Bash-tool shell carries `pwd -P` in its argv. So every in-flight Bash call and background
   watcher on the box died at the same instant with exit 144, including the surviving leads' inbox
   watchers.
5. When lead 95d2333c died, Claude Code's team cleanup closed its 6 teammate panes (454-459 and 466) at
   15:24:44-46Z. That brings the total to 15 dead sessions and 9 husk panes.

Ruled out with measurements: limit-recover (reconciler passes all quiet, shed off, no actuator ran),
the supervisor and teardown tools (no teardown marker, no sweep in the window), account and auth
tools (next2 at 16% weekly, next4 at 30%), the operator's `!` command (it ran at 10:18), and the
`account-recovery-lane.bats` run (UTC 10:24, five hours earlier).

## Why the guard missed it

`hooks/validate-bash.sh` has had an inert-flag deny for this exact shape since the 2026-08-09
incident, when `pkill -f "next dev" -P $$` killed 3 sessions. It also has a live kill-selection
gate. Both gates, and the empty-selector gate, open only when a quote-stripped copy (`CMD_NOQ`) shows
`pkill` in command position. That copy was produced by `sed`, which works one line at a time:

- The commit message's closing quote sat on a later line.
- `sed` paired it with the opening quote of `"next start"`.
- That erased `; pkill -f ` from the copy.
- No gate opened, and the command ran.

## Fix (this change)

- `vb_strip_quotes` is an awk quote-state scan whose state carries across lines and that handles
  `$(` nested in double quotes. It now builds `CMD_NOQ`. The old `sed` copy is appended to it, so a
  gate opens if either copy shows a kill (fail toward opening; every verdict re-reads the raw text).
- Regressions are in `tests/pkill-scope.bats`: the verbatim incident command, an apostrophe inside a
  multi-line message, a multi-line message that only mentions a kill, and a kill inside `"$( )"`.
- `tests/fixtures/validate-bash-sites.tsv` was re-pinned for the line shift (+36).

## Husk design: intended, and where it falls short

- **Pane stays open by design.** `bin/cc-pane-runner` closes a pane only on rc 0 or rc 75. Any other
  rc prints "shell kept for resume". `lead-crash-watchdog` then paints `KILLED` and
  `▶ cc-husk-sweep --pane N` into the pane. `docs/research/husk-panes-pkill-selection-2026-09-04.md`
  states the decision: the fix is preventing the kill, and closing the pane would destroy the
  resume point.
- **No auto-resume, by policy.** `scripts/boot-resume.sh` Ruling #1 says the supervisor pages and
  never auto-recovers.
- **Gap: the custody lead is never told its lanes died.** The watchdog prints "pane 10 holds custody
  · tell it" into the dead pane, but nothing delivers that to pane 10. The B13 lead kept waiting for
  pings from six dead lanes.
- **Gap: the death pages did not reach the operator.** They resolved to `notify_rc=3` (unresolvable)
  and fell back to a Notification Center post (`autonomy/idl.jsonl`, 15:25:04Z onward).

## Recurrence

This is the 4th incident of the same class: a pattern kill matching sibling sessions through the
briefs in their argv.

| Date | Command | Damage |
|---|---|---|
| 2026-08-09 | `pkill -f "next dev" -P $$` (same trailing `-P`) | 3 sessions |
| 2026-08-25 | `pkill -f cc-await-ping` | 1 session |
| 2026-09-04 | `pkill -f cc-await-ping` | 5 sessions |
| 2026-10-21 | this incident | 9 sessions + 6 teammates |

The inert-flag deny had blocked this shape 10 times between 2026-09-23 and 2026-10-19. It failed only
when a multi-line quoted string came before the kill. A multi-line commit message followed by a kill
is a common agent idiom.

Structural options not taken here, because each is a larger change:
- Stop passing the brief in argv (pass it by file), or rename `HANDOFF-PING` so it has no `-<letter>`
  substring. Either shrinks what any `pkill -f` can match.
- Add an execution-time `pkill` shim that refuses an option-shaped word after the pattern.
