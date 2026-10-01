# Judge verdict: how Claude Code sessions survive a kitty crash, a kitty restart or a Mac reboot

W2 of `docs/plans/kitty-deadlock-recovery-2026-10-01.md`, judged 2026-10-01 by the finishing session
(the workflow's own judge stage never ran: its lead ran out of weekly quota at 15:52). Inputs: the five
dossiers in this folder (C1, C2 + addendum, C3, C4 with its revision 2, C5), all ten skeptic reports
(both passes of each), the four findings the W2 lead relayed at 16:00, and four checks run here
(listed at the end). Every claim below cites the report that measured it.

**What a conviction means here:** the probability that the option, built as specified, gets the
fleet through the events it claims to cover without a manual rebuild, and leaves the operator better
off. An unrefuted fatal flaw caps it. An unmeasured load-bearing claim lowers it. Researcher and
skeptic numbers were weighed against each other, not averaged.

## Recommendation

**Build H1, restore-first, now: 62%.** H1 is C4's revision-2 hybrid with the five amendments below.
It turns all three events into zero or one command and stops the 2026-10-01 failure modes. It does
not keep in-flight work alive: turns, background shells, Monitors, subagents and workflows still die
and are re-engaged afterwards.

**Second: C3's kitty patch (P2), adopted at a planned restart.** It keeps kitty's remote-control
thread serving after an `accept()` error and restores signal handling (backport of upstream
`f3fdc21850`). Its claims hold at 60%; adopting it needs the operator to swap in a build.

**Not now, gated: a tmux session layer (H2), 35%.** It is the only measured way to keep in-flight
work alive through a kitty death. Decide on it only after three things: H1 has carried one real
restore, a one-session pilot with a real Claude passes, and the operator has ruled on scrollback.

**Do not build:**
- Claude Code's background daemon as the session layer (C5/H3, 15%).
- C1's phased migration (30%).
- C2's zero-command crash relaunch.
- C3's S1 restart page and S2 breaker as specified.
- Any recovery nudge whose main path is typing into a pane.

Why restore comes before survival, in numbers: over the 62 days from 2026-07-31 there were **11
reboots** against **5 kitty-only restarts** (C4 rev 2, R-frequency: `last reboot` plus window-id
resets in `pane-spawns.jsonl`). Only disk state survives a reboot, so every path needs H1's restore
anyway. A session layer would add in-flight survival on about a third of events, at 3-4 times H1's
cost.

## Rank table

| Rank | Option | Events claimed | Conviction | One-line verdict |
|---|---|---|---|---|
| 1 | **H1 restore-first** (C4 rev 2 plus amendments J1-J5) | (a) page plus 1 command, (b) 1 command, (c) 0 commands; in-flight work lost but listed and re-engaged | **62** | Build now |
| 2 | **C3 P2 alone** (kitty patch, adopted at a restart) | prevents the 10-01 trigger: the talk thread keeps serving; SIGTERM and child reaping work again | **60** | Build the patch now; operator adopts at the second planned restart |
| 3 | **H2**: H1 then a tmux host per session, as one cutover | (a), (b) survive with in-flight work intact; (c) as H1 | **35** | Gate on pilot plus scrollback ruling; do not build in W3 |
| 4 | C2 as specified (restore command) | all three by restore | **40** | Superseded by H1, which carries its sound parts |
| 5 | C3 as specified (P1, P2, P3, S1, S2) | prevention only, no survival | **35** | Keep P2; drop or rework the rest |
| 6 | C1 as specified (tmux, phased) | (a), (b) | **30** | Phase 1 alone is worse than today |
| 7 | C5 / H3 (vendor background daemon) | (a), (b); (c) ungated auto-continue | **15** | Watch item only |
| 8 | H0 null (keep today's `/tmp` scripts as a runbook) | (a), (b) by hand | **10** | Baseline H1 must beat |

The table ranks by recommendation, not by raw conviction. C2 as specified scores higher than H2,
but H1 contains everything sound in C2, so C2 has no standalone place.

## Per candidate: what survived the skeptics and what died

### H1, restore-first (C4 revision 2), 62

**Survived.**
- The `.start` bug is real and still live. `alarm-reboot-prep.sh:52` appends `kalloc1024_gb=…`, and
  `boot-resume.sh:300` (main) rejects the line. Re-measured by all four C2 skeptic passes.
- So are shed-the-tail at `cc-resume-layout.sh:249-252`, the resurrections, the stacked keepalives and
  the capacity refusal at 2.05/core. All stand on every pass.
- Fullscreen by window id works where the title match failed: `toggle_fullscreen` returned rc 0 on 8
  of 8 windows, and kitty source `rc/action.py:61-69` acts on the matched window (C2-skeptic-code).
- `boot-resume` is missing from `GARBAGE_WL` (`bin/cc-reaper:713`). A reboot restore runs past
  600 s, so cc-reaper would kill it. Both C2 skeptics.
- Revision 2 already folds in the fixes the C4 skeptics said would earn 62-65:
  - the crash path pages instead of relaunching on its own, which removes both scoped fatal flaws:
    a deliberate ⌘Q looks like a crash (C2-skeptic-risk), and a crash cluster would loop
    (C4-skeptic-risk);
  - a restore lock is taken before any kill, and a per-session launch lock guards the spawn;
  - the layout's `k()` wrapper is bounded;
  - a launch that timed out is recorded as "maybe launched";
  - the nudge goes in as a launch argument and reads no screen;
  - main's retire filter (ba04df7b3) is kept, plus a successor lookup.

**Died, from the first-pass H1.**
- "No kitty socket in delivery." The ported `lr-fire-resume` injector reads the screen through
  `it2 session read`, which is `kt get-text` (both C4 skeptics).
- E5's premise that "a socket file outlives SIGKILL". kitty's `__atexit__` helper unlinks it (C4-skeptic-code).
- The `.ips`-gated zero-command crash restore. The 10-01 event wrote no `.ips` file.
- "Fixes missing tombstones." H1 only works around them with the heartbeat; the cause is unknown.

**Still unmeasured, and why it holds the number at 62:**
- Whether `claude --resume <sid> "<prompt>"` submits the prompt. The resume dialog is already
  suppressed at its source: `reso-resume-one` exports `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=525600`
  (main `:180-221`, `:547`). That makes submission likely, but nobody has run it.
- The 6/core start gate at a login boot storm. That ceiling never bound on 10-01 (C2-skeptic-code #9).
- A full restore cannot be rehearsed without ending the fleet. The first planned restart is the rehearsal.
- 14 of 32 sessions wrote no tombstone, 12 of 14 of them on panes the layout made (C2-skeptic-code,
  second pass). So the heartbeat roster carries crashes and reboots.
- H1 restores and never preserves. That keeps the number under 70 however well it is built.

**Amendments added by this verdict (J1-J5):**
- **J1. Layout: one row of panes per window, not 2x2.** Lead finding 2 settles C4's open layout
  question: each kitty OS window is fullscreen on its own Desktop with its panes side by side in one
  row (`goto-layout horizontal`). Window groups come from the heartbeat when it recorded them (desk
  and slot from one bounded `kitten @ ls` per 5-minute tick), so a restore puts sessions back where
  the operator left them. Project grouping is the fallback. This also answers C2-skeptic-risk #8:
  today every restore re-packs the Desktops and the operator's spatial map is lost.
- **J2. Fullscreen: toggle once per window after the layout finishes; never re-toggle on a failed
  read-back.**
  - All three read-backs proposed so far are blind on this Mac. CoreGraphics bounds misread 9 of 9
    fullscreen windows on the notched display (C2-skeptic-code #1). AX lists only the current Space
    (plan:39, C4-skeptic-risk #5). `screencapture` of another Desktop returns a stale frame (lead
    finding 3).
  - So report the rc, page on a non-zero rc, and delete `fs_osa` (`cc-resume-layout.sh:177-190`)
    together with its marker-title loop (`:290-311`).
- **J3. Re-engagement in three tiers, cheapest first.**
  1. *Every* restored session gets a restore note in its own inbox before launch:
     `cc-notify --mailbox-only <sid> "<what died>"`. `hooks/mailbox-drain.sh session-start` runs at
     every SessionStart with no matcher (checked in `settings.json`), so the note lands as context
     when the session resumes. That costs no turn and no typing.
  2. Only a session with direct evidence of open work also gets a turn. Evidence means an unclosed
     Workflow, Monitor or background-Agent launch, or a live workflow journal, and the account must
     have headroom. The turn arrives as the positional prompt on `reso-resume-one`'s spawn line.
  3. The typed fallback is now allowed (lead finding 4) but is proven only by re-reading the composer
     after each key press (lead finding 1: `send-text` arrives as a bracketed paste, and a first
     `send-key enter` pass exited 0 in 29 panes while submitting none).

  Why the tiers: on 10-01, 28 late-submitted prompts cost 6.8M cache-write tokens in 10 minutes, and
  14 of the 18 sessions that could reply said nothing was pending (C2-skeptic-risk, second pass).
  The plan's frozen scope still asks for workflows and background work to be re-engaged with no
  manual re-prompting, so sessions with real open work do get the turn.
- **J4. The classifier no longer constrains the design; the kill stays the operator's.** Since
  15:59, `settings.json:1357` lets agents read, type into, submit, recycle and close the operator's
  local kitty panes, and `:1320` takes them out of "Remote Shell Writes" (lead finding 4, read
  here). So duplicate cleanup and submit verification no longer need the operator. Killing kitty,
  which ends every session, is not among the listed verbs. `cc-restore --restart-kitty` stays a
  one-command operator act carrying `--confirm <kitty-pid>`.
- **J5. Build on main.** Main is 22 commits ahead of this branch, 6 of them in the restore chain
  (`git log HEAD..origin/main`). The build plan cites main's line numbers. Main's retire rule
  ("`recycle` is not a retirement", `boot-resume.sh:374-438`) stays; H1 adds only the successor
  lookup.

### C3 P2 alone, 60

**Survived.** The mechanism is now measured twice, not inferred.
- kitty 0.48.2 `child-monitor.c:1821-1826` returns false on any `accept()` error except EINTR, and
  `:2058` then runs `goto end`. Nothing restarts the thread.
- The two preserved `sample` runs of pid 610 show the talk thread `KittyPeerMon` (Thread_8855)
  present at 2026-09-30 22:17 and absent at 2026-10-01 11:57 and 12:02. The thread lists are copied
  into `evidence-kitty610-thread-samples.txt` in this folder, because /tmp does not survive a reboot.
- v0.49.2 and master still carry the same path (all three C3 reports).
- The signal clobber (`loop-utils.c:84`) has already fired on today's kitty 48854, whose talk
  thread is still alive. Its zombie children went 1 → 4 → 5 between 15:13 and 15:22
  (C3-skeptic-code, second pass). Only P2's backport or kitty 0.49.x cures that, so SIGTERM is dead
  weight on every restart path today.

**Died.**
- "EMFILE, 75%." It is now 45% or lower: the broken-pipe trend shows the main thread draining peers
  right up to 02:06:47 CDT (both C3 skeptics).
- P1's day-one live adoption. `auto_reload_config` reloads through SIGUSR1, and that signal is now
  dropped (C3-skeptic-code, second pass).
- S1's "11 hours to 2 minutes." Detection already took about a minute. What cost the hours was
  telling a dead thread from a deaf one, plus nobody able to act. S1 can also mislabel a starved but
  live thread, because the PRI-4 clamp covers every thread of a backgrounded kitty
  (`ps -M -p 94453` showed all 7 threads at 4T).
- S2's rc 124. It collides with handoff-fire's "may have launched" contract (C3-skeptic-risk M2).

**Conditions.**
- Back off on a repeating error. An error raised before the dequeue would otherwise busy-spin
  (C3-skeptic-code missed risk 4).
- Build P2 separately from the title-band bundle. `kitty-build-swap.sh` couples the two today, so a
  no on the band would also drop P2.
- Adopt it at the second planned restart, never at H1's first rehearsal.

### H2, H1 then a tmux session layer, 35

**Survived.**
- Survival through a kitty death is replicated three times: a pane outlives its client's SIGKILL and
  a closed pty (C1 E1 plus both C1 skeptics).
- tmux discards output to a viewer that stops reading (`tty.c:220-240`). A starved kitty, by
  contrast, stops reading pane ptys and blocks claude's writes (`child-monitor.c:1667`; C1-skeptic-code,
  second pass).
- A host can tell "session ended" from "viewer went away" with one `has-session` after `attach`
  returns (C4 rev 2, R5).

**Died.** C1's own design as written:
- `remain-on-exit on` contradicts the dossier's own exit claim (refuted by measurement);
- `cc-reattach` enumerates socket files that outlive their servers;
- the build size: 52 ancestry-oracle files, `pane_ownership`, `lr_recon`, `it2-wrapper`,
  `cc-sessions` and `kitty-confirm-close`, none of them in the dossier's list;
- phased delivery. Inside a host, `it2-kitty session list` exits 3 on day one (C1-skeptic-risk), so
  phase 1 alone is worse than today.

**Unmeasured and load-bearing:**
- a real Claude under tmux (Shift+Enter, the wheel, scrollback);
- every session moving into launchd's `Background` session, which matters to 57 `osascript`
  callers;
- the cost: 3,500-6,000 LOC over weeks.

**Lead finding 4 changes nothing here.** Ending a hosted session is a tmux verb, not a kitty pane
verb.

### C2 as specified, 40

**Survived.** The forensics: 8 to 9 of 10 claims stand on all four skeptic passes. H1 inherits
every part that survived.

**Died, or carries an unrefuted scoped fatal flaw:**
- The zero-command crash trigger cannot tell a crash from a deliberate quit, and it names no off
  switch (both C2-skeptic-risk passes).
- Its retire rule contradicts main's landed and mutant-pinned rule.
- Its nudge delivery, `send-text` followed by a CR, is refuted outright: 30 of 31 prompts did not
  submit, and lead finding 1 adds that a separate `send-key` did not submit either.
- It has no restore lock (C2-skeptic-code, second pass #2).
- It nudges accounts that are at their weekly limit (27 of the 32 roster sessions sat on two such
  accounts).

### C3 as specified, 35

P2 survives (see above). The rest:
- P1 is "only if EMFILE" (45% or lower).
- P3 needs a kitty relaunch.
- S1 and S2 as specified can turn a deaf episode that would have healed into an outage we cause
  (C3-skeptic-risk, both passes). The fleet made 405 commits while remote control was dead, so a
  degraded fleet was still productive.
- C3 never claims survival, which is why it is a complement and not an answer.

### C1 as specified, 30

The mechanism survived and the design did not (see H2). Standalone it also leaves reboots, about
two-thirds of events, exactly as bad as 10-01.

### C5 / H3, 15

**Survived.** A bg worker outlives its attach client (measured once, on an idle worker). Our own
recycle created the hidden fork 9aa483e9: every slash dispatch on 10-01 pairs 1:1 with a recycle
that answered `2` (C5-skeptic-code K1).

**The unrefuted fatal flaw** (C5-skeptic-risk): closing no longer stops a session, and stopping does
not stay stopped.
- `/exit`, ^C^C, ^D^D, ⌘W and a kitty quit all detach. There were 719 `prompt_input_exit` ends since
  09-01, and under C5 each would become a headless worker.
- `claude stop` came back on its own 4 min 16 s later (`~/.claude-quaternary/daemon.log:55-56`).

**Also measured:**
- A cross-account fork crashed (`b363d8e6`).
- `jobs/*/state.json` does not show liveness.
- No launcher can pin the daemon's environment (C5-skeptic-code M1-M3).

**Kept from C5:** the fork hazard is real and is fixed at its source in H1 (Phase 1 of the build
plan).

### H0 null, 10

- Today's scripts hardcode `OLD_KITTY = 610` and `D = "/tmp/inboot-2026-10-01"`, so each run needs
  hand edits first.
- The measured outcome: 8 of 32 sessions on the first pass, 5 resurrections, 29 of 31 prompts unsent
  for 2.5 hours, about 25 minutes including the land wait.
- Lead finding 4 lets an agent drive it now, which saves the operator steps. It does not fix the
  outcome.

## Open questions, in the order the build hits them

1. Does `claude --resume <sid> "<prompt>"` submit the prompt on 2.1.284 with the dialog suppressed?
   Build-plan Phase 4 opens with a one-session pilot in a private tmux server.
2. Does `hooks/mailbox-drain.sh` deliver a line appended before the resume? The `.seen` cursor
   should let it through. A Phase 4 bats case pins it.
3. Why do layout-made panes lose their tombstones (12 of 14)? H1 does not depend on the answer.
4. The right start-gate ceiling at a login boot storm. Phase 3a logs load every 10 s until it is
   measured.
5. Which errno killed the talk thread? Only P2's `log_error` line will say.

## Checks run by this verdict

- `git log --oneline HEAD..origin/main` → 22 commits; 6 touch the restore chain (ba04df7b3,
  6347b1731, e66bf5760, b57cd7457, 4fad69e1d, eee5cf8c5).
- `grep -n 'kitten @\|autoMode\|environment' ~/.claude/settings.json` → `:190-191` allow
  `kitten @`; `:1320` and `:1357` carry the 2026-10-01 local-pane ruling (lead finding 4 confirmed).
- `git show origin/main:bin/reso-resume-one` → the dialog suppression at `:180-221` and `:547`, and
  the spawn at `:560`.
- `settings.json` SessionStart hooks → `~/.claude/hooks/mailbox-drain.sh session-start` with
  `matcher=None`.
- `grep -c KittyPeerMon` on the three surviving /tmp `sample` files → 1, 0, 0 (preserved in
  `evidence-kitty610-thread-samples.txt`).
