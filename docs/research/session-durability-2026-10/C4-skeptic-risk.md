# C4 skeptic, operator-risk lens (2026-10-01)

This is a read-only review of `C4-hybrids.md`. Every number is labeled **measured** (with its command) or
**estimated** (with its method). UNMEASURED means not checked.

## Answer first

**H1 is still the right first build, and nothing here refutes C4 as a whole. As specified, though,
H1 has a hole that makes a crash cluster worse than today, and one of its headline claims is false.
Recommended conviction: 54 (the dossier says 62).**

- **The scoped fatal flaw: the zero-command crash trigger has no cap on repeat restores.**
  - The launched-once ledger and `events/K.done` are both per event, and every relaunched kitty is a
    new K.
  - The stock kitty crashed 4 times in 75 s on 2026-09-16. Armed, H1 would mass-resume and nudge the
    fleet into a kitty that keeps crashing, about every 5 min with no end.
- **Refuted: "no kitty socket is involved in delivery".** The `lr-fire-resume` arm C4 ports reads the
  screen through `it2 session read`, which is `kitty @ get-text --extent all`. Each nudged session can
  make 1 to 9 calls, in the restore window that C2's skeptic already called the most fragile.
- **A new interaction that only appears in a hybrid.**
  - C3's breaker makes calls fail fast. The layout then drops each failed row (`failed++; continue`),
    which is a new way to shed rows.
  - A launch that timed out but that kitty runs later can start a second copy of the session. Neither
    the ledger nor the holder check can see it.
- **C4's own order is inconsistent.** Risk 4 calls the S2 breaker a prerequisite for any restore. The
  sequencing lands `cc-restore` (session S5) before the breaker (session S6).

## Verdicts on the key claims

| # | Claim | Verdict | Evidence (re-measured here) |
|---|---|---|---|
| 1 | The classifier refuses agents acting on other live sessions, including `tmux kill-session`; self-retirement is allowed | **stands** | Python scan of `~/.claude/logs/permission-denied.jsonl`: 531 rows. 09-09T07:06:15 `tmux kill-session -t lr-resume-9e3074fc` "Blocked by classifier"; 09-26T22:07:11 send-text and 10-01T16:40:09 `cc-pane-close` "judged this action dangerous"; 10-01T19:13:40 `[Remote Shell Writes]`. Teardown markers for 2026-09 (python counter over `~/.claude/watchdog/teardown/*.json`): terminal 535, recycle 382. |
| 2 | A launch-time injector already exists, and porting it into reso-resume-one gives a nudge with no agent, no send-text and no kitty socket | **weakened. The "no kitty socket" half is refuted.** | The no-agent and no-send-text halves hold: the arm uses expect `send` (`lr-fire-resume.sh:1248-1259`). But its safety reads go through kitty: `lr_screen` (`:1009-1015`) runs `LR_SCREEN_SH`, which calls `"$LR_IT2" session read -s "$LR_PANE" -n 24` (`:834`), where `LR_IT2=$HOME/.claude/bin/it2` (`:803`). That reaches `kt get-text --match id:… --extent all` (`bin/it2-kitty:1466`), bounded at 15 s (`it2-kitty:95`). `lr_submit_cr` polls it up to 8 times (`:1037`), then sends the CR unconfirmed (`:1060`). See missed risk 2. |
| 3 | With tmux's alternate screen off, kitty's own scrollback gets paced output in full; bursts are lossy | **stands, but the figure is not a constant** | My private run (`tmux -L sd-probe-c4risk`, `status off`, the same `smcup@:rmcup@` override, python pty client, `seq 1 100` burst) drew **46, 77 and 99** distinct lines for 24-, 40- and 60-row clients, against C4's 23 of 100. Paced at 50 ms, 98 of 100. My count is lines drawn, not lines kept in kitty's history, so it is an upper bound. How much is lost depends on pane height and timing. The operator's scrollback ruling still needs the real-Claude pilot. |
| 4 | The vendor background daemon is a pty broker outside kitty that conflicts with fleet identity | **stands** (not re-measured) | Not re-measured. It is a watch item and costs nothing to keep watching. |
| 5 | H1 touches only launch path (ii); H2 must migrate all three | **stands** | Spawn at `reso-resume-one:560`, READY arm at `:632`, shell fallback at `:712`. `~/.reso/bin/reso-resume-one` is a symlink into the checkout (`ls -la`), so a land goes live at once. Callers: cc-resume-layout, boot-resume(-launch), handoff-fire, cc-resume-debt (`grep -rln`). |
| 6 | H0 fails the one-command rule | **stands** | `kitty-restart-supervisor.py:26-30` hardcodes `LEAD_SID` and `OLD_KITTY = 610`. |
| 7 | A fixed `listen_on` path needs an unlink before relaunch; this matters only to H2 | **stands** | `ps -p 94453` shows the staged sandbox on a fixed `--listen-on unix:/tmp/kdw4.sock`. But `scripts/kitty-build-swap.sh:8-20` adopts by renaming the bundle and keeps `kitty.conf:147`'s pid-templated path, so H1's relaunch stays correct after a swap. |

## Fatal flaw (scoped to the zero-command crash trigger, not to H1)

**Nothing caps how many crash restores run in a row.**
- C2's detector fires on any main kitty K that is dead, started after boot, and has no
  `events/K.done` (`C2-restore-command.md:107-118`).
- The ledger is `$STATE_DIR/events/<id>/launched` (`C2:150`), so it is per event.
- C4 adds a pid-matched `.ips` gate and an opt-in. Neither limits repetition, and every relaunched
  kitty has a new pid, so each crash is a new event with an empty ledger.

**Precedent (measured, from the record):** `kitty-title-band-crash-population-2026-09-16.md:3-13`
lists 5 SIGSEGVs of the stock `/Applications/kitty.app` in one day: 13:56:59, 13:57:17, 13:58:06,
13:58:14 and 20:13:49.
- Four of them fell inside 75 s, which means each relaunch died within seconds.
- The family is "near-NULL dereferences reached from Python" (`cfunction_call`). kitty runs remote
  control commands in Python, and a restore makes about 100 of them (C4 risk 4) plus the nudge's
  get-text calls.

**What would happen if this repeats with the trigger armed:**
- Each 300 s tick relaunches kitty and starts resuming about 32 sessions.
- The next crash kills them mid-boot, and the cycle repeats.
- Each cycle can also nudge about 12 sessions, at about 5M tokens of cold-cache rewrites per cycle
  (estimated, C2-skeptic-risk #10).

Today, by contrast, a crash cluster costs one operator decision.

**Fix:**
- Allow one auto-restore per window (say 2 h). A second crash inside the window only pages.
- Before launching anything, require the new kitty to have stayed up for N minutes.
- Count crashes per boot. After the second, stop launching until the operator acts.

## Scenarios where adopting C4/H1 makes the next incident worse (missed risks)

1. **Crash loop.** See the fatal flaw above.
2. **The ported nudge brings back socket load and can stall each resumed TUI.**
   - Each nudged session makes 1 get-text call when the draft paints at once, and up to 8 in
     `lr_submit_cr`, plus 1 in the quiet arm. Estimated: 12 to 108 calls for about 12 nudges, or up
     to about 280 for 31.
   - Each call is `--extent all`, a full scrollback dump on kitty's main thread (`it2-kitty:1466`).
   - Each call is a blocking `exec`, up to 15 s, during which expect does not read claude's output.
     The repo has measured that this stalls the TUI: "the resumed transcript went silent for 246 s"
     (`lr-fire-resume.sh:994-998`).
   - When the S2 breaker is open, `lr_screen` returns UNKNOWN. The quiet arm then parks without
     typing, and the submit arm sends a blind CR.
   - So under load the nudges fail silently. That is exactly when restores happen.
   - Fix options:
     - Read readiness only from expect's own buffer and confirm only through the transcript probe,
       which never touches kitty.
     - Or keep `lr_screen` but give it its own call budget and count it in risk 4.
3. **The breaker plus the layout loop sheds rows, and an unknown-outcome launch duplicates a session.**
   - The breaker writes `deaf-until = now+30s` after any timeout (`C3-socket-robustness.md:253`).
   - A failed launch is `failed=$((failed + 1)); continue` (`cc-resume-layout.sh:266-268`). H1's
     wait-and-retry fixes only the capacity refusal (`:250-252`).
   - At a 12 s stagger (`:117`), each breaker trip drops about 2 to 3 rows (estimated: 30 s / 12 s).
   - The other direction: a launch that timed out on the client may still run later inside kitty.
     `handoff-fire.sh:1011-1015` records exactly this: "the 0.8s retry created a SECOND one".
   - The ledger is written only from a printed map line (`C2:150,172`), and `lr_holder_count` counts
     live processes only (`lr-lib.sh:509-535`), so a queued, not-yet-run launch reads 0.
   - `reso-resume-one` itself has no per-sid lock: `grep -n -i 'holder|lockf|launch.lock'` gives
     0 hits.
   - Fix:
     - Treat a timed-out launch as "maybe launched": record it in the ledger, and re-check after a
       settle delay.
     - Take a per-sid launch lock inside `reso-resume-one`, so the child refuses to start a second
       copy whenever kitty finally runs it.
4. **Order inversion and an unbounded wrapper.**
   - The layout's `k()` has no timeout (`cc-resume-layout.sh:175`).
   - C4's sequencing lands S5 (`cc-restore`) on about day 3-4, and only then S6, the breaker
     (`C4:375-376`). That contradicts its own risk 4 (`:399-400`).
   - Until S6 lands, a planned restart into a slow new kitty can hang the restore indefinitely.
   - The labels also collide: "S6: … then S1 advisory" uses S1 both as a session and as a C3 item.
     A dispatched builder can mis-read that.
   - Fix: land the breaker, or at least a bounded `k()`, before `cc-restore`, and rename the session
     slices.
5. **The AX read-back may be blind to exactly the windows it checks.**
   - `docs/plans/kitty-deadlock-recovery-2026-10-01.md:39`, measured by the restart lead: "AX lists
     only windows on the current Desktop".
   - After `toggle_fullscreen`, each window moves to its own Space. An `AXFullScreen` read-back on
     the kitty pid may therefore report 8 or 9 failures, just as the CoreGraphics read-back did
     (C2-skeptic-code #1). If a failed read-back triggers a re-toggle, it undoes good fullscreens.
   - UNMEASURED: I did not call the AX API, to avoid a TCC prompt nobody could answer.
   - Fix: on a failed read-back, page only and never re-toggle, until a cross-Space read is measured.
6. **"Re-engaged once" is weakest for the most valuable lost state.**
   - The WAKE-LOST oracle covers background shells only (C2-skeptic-code #7). Nothing detects a
     session whose turn ended while it waited on a Workflow, a teammate, a Monitor or a
     `cc-await-ping` watcher.
   - Widening the rule nudges sessions the operator had parked, which the 08-24 ruling forbids
     (`C2:309`).
   - So exactly the sessions that lost the most work stay asleep, and nothing reports it.
   - Fix: write a per-event "lost async work, not nudged" list into the restore page, so the
     operator sees which sessions they are.
7. **P1's sandbox test lands on the operator's pending decision.**
   - C4 tests P1 "in the staged kitty (operator-owned, kdw4)". That instance is the title-band sitting
     (`scripts/kitty-sitting.sh:15`; pid 94453 is running).
   - Loading a watcher needs a config reload plus new windows (C3-skeptic-risk, note 7). That mutates
     the instance the operator is evaluating and confounds the yes or no.
   - P2 "rides the staged-build swap", so the socket fix is tied to the title-band decision. If the
     operator says no, P2 has no way in.
   - Fix: test P1 in a throwaway instance group that the builder launches, and only with the
     operator's go-ahead.
8. **The first real restore mixes too many first-time changes.**
   - The first planned `cc-restore` is H1's first rehearsal (C4:379-381). P2 (a 4th local patch), P3
     (`NSAppSleepDisabled`) and possibly the bundle swap all ride on it.
   - If it fails, nobody can tell which change caused it, and rolling back P2 means another restart
     (C3-skeptic-risk missed risk 4).
   - Fix: make the first `cc-restore` run with nothing else changed.
9. **The fleet is unprotected during the build (minor).**
   - The next kalloc reboot is due about 5 days after today's (`alarm-reboot-prep.sh:5-9`), which is
     inside or just after the 3-4-day build. Each land goes live at once, so the next event may run
     against a partly landed H1.
   - "Operator-created" opt-in files are plain files that nothing technically guards. The existing
     protection is a procedure: the activation script the operator ran on 09-30 (transcript
     `4dfb5f08…`, 23:36Z).

## What C4 gets right (for balance)

- It keeps the title bars, drag, fullscreen per Desktop and kitty's scrollback untouched, and it
  needs no agent action on a live session.
- It folds in every C2 and C3 skeptic fix: expiring flag, `sample` gate (feasible on the stock
  build: `sample 610 3` listed its threads, `husk-panes-2026-09-30.md:89`), reaper whitelist,
  holder re-check, opt-in that lands last.
- It gates H2 behind a pilot and one cutover, and its own measurements show a half-landed H2 is
  worse than today.
- Reboots are the most frequent event (a kalloc reboot about every 5 days), and H1 covers them
  first. That is the right priority.

## Recommended conviction: 54

- The direction (H1 now, H2 gated, H3 watch) holds.
- Points come off for four things:
  - the false "no socket" claim, whose fix changes the nudge design;
  - the uncapped crash loop on the zero-command path;
  - the breaker and layout interaction (lost rows, possible duplicates), which no source dossier
    covers;
  - the order inversion between `cc-restore` and the breaker.
- With a restore-rate cap, a socket-free nudge (or a budgeted one), "maybe launched" handling plus
  a child-side launch lock, and the breaker landing before `cc-restore`, 62 to 65 would be fair.

## Probes and deviations

- **kitty socket:** 0 of 3 allowed `kitten @` calls. Nothing was signaled, typed into or launched.
  `claude` was not run.
- **Experiment:** one private tmux server, `tmux -L sd-probe-c4risk`, running `sh`, `seq` and
  `sleep` dummies. I killed it, and `tmux -L sd-probe-c4risk ls` gives `no server running`. Its
  socket file was removed, and `ls /private/tmp/tmux-501 | grep -c sd-probe-c4risk` gives 0.
- **Read-only checks:**
  - `ps` on pids 48854 and 94453;
  - `codesign -dv` on both kitty bundles;
  - a listing of `~/Library/Logs/DiagnosticReports`: 0 kitty `.ips` files remain, so the 09-15 and
    09-16 reports have rotated out;
  - python scans of `permission-denied.jsonl`, the teardown markers and one transcript.
- **Writes:** this file only.
