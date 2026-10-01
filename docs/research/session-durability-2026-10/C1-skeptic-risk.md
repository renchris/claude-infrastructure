# C1 skeptic review: operator risk (second pass)

This is a skeptic pass on `C1-session-layer.md`: a tmux host per session, with kitty as a viewer that
can be restarted. The lens is what C1 costs or breaks for the operator, and the scenario where it
makes the next incident worse.

This pass rewrites the first one in place. The first pass is recoverable with `git show
55753e737:docs/research/session-durability-2026-10/C1-skeptic-risk.md`. I re-checked every
load-bearing line it cited and kept, weakened or dropped each claim on that basis.

Conditions of this pass:
- Read-only apart from this file.
- Probes ran only on private servers `tmux -L sd-probe-c1risk` and `-L sd-probe-c1risk2`, with
  `sh`/`bash`/`sleep` as dummy processes. Both servers are dead and their sockets removed.
- The `sd-probe-c5` socket belongs to another agent and was left untouched.
- **0 of 3** allowed `kitten @ ls` calls were used. `claude` was never launched.

## Answer

**The survival property is real, but C1 as designed and phased makes the next kitty incident worse
before it makes anything better.** Phase 1 alone has negative value.

The first pass said hosted sessions lose their control plane *after a kitty restart*. It is worse:
they lose it **on day one**. Measured inside a private tmux pane, with kitty 48854 alive and
healthy, `it2-kitty session list` exits **3** ("refusing to drive kitty from a pane that is not
kitty's"), because `cc-in-kitty` fails by ancestry (`bin/it2-kitty:230-238`). About 63 lines of
handoff-fire go through `it2`/`it2-kitty`, against 8 direct `kitty @` calls (grep counts).

The same session is also:
- hidden by cc-sessions;
- unbindable by the limit-recover reconciler;
- warned about wrongly by the ⌘W dialog.

**Fatal flaw: none.** A single cutover could engineer each defect away. The dossier's own plan,
though, phases the cutover (C1:239-246), and phasing is where the operator gets hurt.

**Recommended conviction: 38** (dossier 55, code skeptic 48, first risk pass 35). I raised the
first pass's 35 because I checked four of its claims and they do not hold as stated: husk-sweep
resume runs only by hand, the shutdown concern partly fails a measurement, rollback is a drain
rather than impossible, and the `%N` kill is moot. I lowered the dossier's 55 because day-one
control-plane loss and limit-recovery blindness are measured or read directly from code.

## Verdicts on the dossier's key claims

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | The pane survives client SIGKILL and pty close, and reattach redraws | **stands** | Dossier E1, replicated by the code skeptic. Mine adds that when the server dies, the pane is hung up: SIGTERM to my server ⇒ server gone in <0.3 s, pane's `HUP` trap ran (`HUP-start`, `HUP-done`). Survival is exactly as good as the server's health. |
| 2 | A viewer that stops reading cannot stall Claude | **stands** | Dossier E1, and tmux `tty.c` drops output to slow clients (code skeptic). The benefit is conditional: kitty stalling today's ptys is UNMEASURED (C1:53-54). |
| 3 | The control plane leaves kitty's PRI-4 band | **weakened** | The PRI readings are real, but in phases 1-2 the control plane is not *moved*, it is *cut*. Inside a host, `it2-kitty` refuses (rc 3, measured above), and launching viewers still needs kitty's socket (C1:199-201). |
| 4 | tmux recovers from EMFILE/ECONNABORTED; any other errno is fatal; one server per session bounds that | **weakened** | Fetched 3.6a `server.c:380-389`, and `log.c:140-152` `fatal()` ⇒ `exit(1)`. My probe shows a server death hangs up its claude. Kitty's equivalent fault (husk-panes-2026-09-30.md:85-96) killed only the RC thread and every session lived. Under C1 the same class of fault kills sessions. "One session" holds only for independent faults: a box-wide ENOMEM hits every server that accepts during the episode (`man 2 accept` lists ENOMEM, per the code skeptic). |
| 5 | As configured, tmux breaks teammate spawning | **stands; understated** | Beyond the thrown error, the frozen `KITTY_WINDOW_ID` sends it2-wrapper into its kitty branch. `cc-in-kitty` then fails, and the call falls through to the real iTerm2 CLI (`bin/it2-wrapper:111-129`, `REAL_IT2=~/Library/Python/3.11/bin/it2`, which exists; iTerm2 not running per `pgrep`). Whether that fails cleanly or wakes iTerm2 (the 2026-08-07 class, `bin/cc-kitty-socket:6-8`) is UNMEASURED. I did not run it. |
| 6 | Auto mode plus `$TMUX` selects TmuxBackend | **stands (moot)** | `teammateMode` is pinned to `iterm2`. |
| 7 | One kitty `map` makes Shift+Enter work | **stands (mechanism); risk understated** | `var:cc_host` exists only on viewers made with `launch --var`, so hand-opened panes submit on Shift+Enter (code skeptic). For the operator this means a half-written multi-line instruction gets submitted to an autonomous agent. Behavior with a real Claude is UNMEASURED. |
| 8 | OSC title, OSC 52, paste, mouse and sync pass through | **stands; consequence missed** | Two independent captures show the attach stream opens with `ESC[?1049h`. Kitty sits on the alternate screen, so kitty's scrollback, search and `it2 read --extent all` (`bin/it2-kitty:1465-1466`) lose all history above one screen. |
| 9 | The pane env freezes at server start | **stands; understated** | Two consequences beyond `KITTY_WINDOW_ID`. The registry's `kitty_pid` is read from the frozen `KITTY_LISTEN_ON` (`hooks/session-register.sh:354-360`). And `cc-kitty-socket`'s fast path returns a dead socket whenever its file exists (`:57-60`), which it does after SIGKILL (`handoff-fire.sh:1216-1219`). handoff-fire probes for a live socket only when `KITTY_WINDOW_ID` is empty (`:1234`). |
| 10 | Kitty sessions replay layout and commands only | **stands** | Dossier E5. |
| 11 | Memory and CPU cost is small | **weakened** | The code skeptic measured 12,272 KB per server, and the design sets `history-limit 10000`. ESTIMATED total is about 1.9 GB, still minor next to 20.7 GB of claude. |
| 12 | "On exit, exit-empty ends the server and the pane returns to its prompt" (C1:213-215) | **refuted** | Replicated with the dossier's own `remain-on-exit on` + `exit-empty on`, after `exit 0`: `a: 1 windows`, `pane_dead=1 status=0`, screen `Pane is dead (status 0 …)`. |
| 13 | `cc-reattach` enumerates `/tmp/tmux-501/ccp-*` (C1:202-207) | **weakened** | Sockets outlive their servers. After `kill-server`: `no server running` but `socket exists: yes`. After the SIGTERM death: `socket left: yes`. Within a boot, enumeration lists dead hosts unless each is probed. Across a reboot this is harmless: 1 of ~1,344 `/private/tmp` entries predates the 15:26 boot, and its ctime is after boot, so /tmp is wiped at boot (ESTIMATED from `stat`). |
| 14 | "Today's dedup … already sees a live tmux-hosted claude" (C1:219-220) | **weakened** | `lr_holder_count` = registry live rows ∪ `--resume` leaves (`lr-lib.sh:509-540`, used at `boot-resume-launch.sh:288-292`). **9 of 38** live claude processes have no `--resume` in their argv (ps count), so only their registry row protects them. cc-sessions deletes that row for hosted sessions (missed risk 2). |

## The scenario where adopting C1 makes the next incident worse

**Setup.** Phase 1 is live as the dossier orders it (host + viewer + reattach). Some sessions are
hosted. Kitty's RC thread dies again through the unfixed `accept_peer` path.

1. **Before the incident, the hosted sessions were already broken, and invisible.**
   - Their recycles, self-closes and teammate spawns were refused (it2-kitty rc 3, measured).
   - `cc-sessions` lists no hosted session. The row is keyed `CC_PANE_ID` first
     (`session-register.sh:173`). `surface=pane` is recorded whenever `ITERM_SESSION_ID` is set
     (`:203-207`), and the host exports it.
   - Kitty never lists `ccp-*`, so the row is marked stale on the first look (`cc-sessions:326-327`).
   - The row is deleted once the session is more than 24 h old (`:328-333`).
   - Measured today: 0 of 42 registry rows are older than 24 h, because the 2026-09-30 reboot and
     today's restart reset the fleet. C1 exists to remove that reset.
2. **The operator restarts kitty ("free" under C1) and runs `cc-reattach`.** Every survivor's
   frozen `KITTY_LISTEN_ON` names the dead socket (row 9), so even the 8 direct `kitty @` calls fail.
   Today a kitty restart clears a deadlock. Under C1 it does not clear for the survivors: they stay
   live and unable to retire for the rest of their lives.
3. **The restart tooling from 2026-10-01 counts every survivor as missing.**
   `inboot-finish.py:41,96` and `kitty-restart-resume.py:340` count a session as "back" only if its
   `kitty_pid == NEW`, and survivors carry the old pid (row 9).
   - inboot-finish reruns boot-resume for up to 12 rounds (`:39`).
   - What stands between those rounds and a second writer is `lr_holder_count`. For non-`--resume`
     sessions older than 24 h it reads 0 (rows 14 and 1 above).
   - This chain is read from code; the end-to-end run is UNMEASURED.
4. **Usage-limit recovery goes blind for hosted sessions.** `lr_recon` binds a claude pid to a
   pane by walking ppids to a kitty window root (`observe_rows.py:288-297`). A hosted claude's
   chain is tmux server → launchd, so it never reaches one. `_identity_match` then returns False
   ("no relaunch typed on a guess", `evidence.py:132-142`). Measured: 47 of 191 per-session
   limit-recover dirs were touched in the last 7 days, so these are routine, not edge, events.
5. **Fires during the deaf window run headless** (C1:201), and cc-sessions hides them (step 1).

**Net.** Today this incident costs a restart and a resume. Under phase-1 C1 it costs a fleet that is
alive but unmanageable, invisible sessions spending quota, a restart tool that may launch second
writers, and no limit recovery.

## Missed risks (not in the dossier's risk list)

1. **Day-one control-plane loss, not post-restart loss** (measured, above). Phase 1 cannot ship
   without phase 2, so time to value is all three phases, and the dossier says to keep kitty-only
   as the default until then (C1:245-246). Until cutover, C1 delivers nothing for events (a)/(b).
2. **cc-sessions hides hosted sessions and then deletes their rows.** cc-notify, the husk sweep's
   liveness guard (`cc-husk-sweep:200-205`) and the second-writer check all read that view.
3. **Limit recovery is blind** (scenario step 4). Neither `lr_recon` nor `cc-sessions` is in the
   build list (C1:231-240).
4. **⌘W loses its warning and stops ending sessions.**
   - `kitty-confirm-close` names a pane's jobs from kitty's `foreground_processes`
     (`:262-286`). Under C1 that is the `tmux attach` client. `tmux` is not in `_PASSTHROUGH`
     (`:255`), so the dialog says "This pane is running: tmux".
   - The "A Claude Code session is running here. Closing … ends it" warning (`:314-320`) therefore
     never appears.
   - Clicking Close then *detaches* (`:341`). A session with an armed /goal keeps spending,
     unseen and absent from cc-sessions.
5. **A tmux fatal turns a deaf-socket event into a session death** (row 4). Nothing in the design
   watches for a host whose server vanished. That session then needs a disk resume, and its
   SessionEnd writes a `reason=other` tombstone (`session-deregister.sh:78`).
6. **"Restart is free" still needs the operator.** On 2026-10-01 the restart was a
   `--confirm`-gated script handed to the operator (plan:25). Whether the auto-mode classifier lets
   an agent SIGKILL a kitty that no longer holds sessions is UNMEASURED. Until it is, "zero steps"
   means one operator step.
7. **Rollback is a drain, not a switch.** Recycles `respawn-pane` in place (C1:184), so hosts never
   empty on their own. Backing out needs a kill switch that routes recycles back to kitty, plus the
   tmux arm kept alive until the last host ends. Ending hosts early is operator-only under the
   classifier.
8. **Scrollback is lost on day one** (row 8). Claude 2.1.284 itself prints "tmux detected · scroll
   with PgUp/PgDn" in this state (code skeptic, binary `Ivo()`). This is the one cost that needs an
   operator ruling before any build.
9. **The DESK-DOWN page may not post.** It is an `osascript display notification` sent from a hook
   inside the session (`lead-crash-watchdog.sh:1256`), described as the liveness-free channel.
   Under C1 that hook runs in launchd's `Background` session (code skeptic measured
   `launchctl managername` ⇒ `Background`). Whether it still posts is UNMEASURED; I did not
   probe it, because a test notification would land on the operator's screen.
10. **The build surface is larger than budgeted** (measured with grep and wc):
    - 143 test files reference kitty identity or control;
    - 61 non-test files read a kitty identity signal;
    - `bin/it2-kitty` is 1,523 lines.

    Not in the build list: `it2-wrapper`, `cc-in-kitty`, `cc-sessions`, `cc-husk-sweep`,
    `kitty-confirm-close`, `lr_recon/*`, and session-register's `surface` rule. "2-3 days" is
    optimistic; weeks is more likely (ESTIMATED from these counts).

### First-pass claims weakened or dropped on re-check

- **Husk sweep typing into live composers:** weakened. No automated caller runs
  `cc-husk-sweep --resume`. Only pages advise it (`lead-crash-watchdog.sh:1196,1256,1478`). It is
  still a hazard when someone follows the page.
- **`teammate-auto-shutdown.sh:211` `tmux kill-pane %N` hitting the lead:** dropped as low
  probability. `%N` ids arise only under TmuxBackend, and `teammateMode` is pinned to `iterm2`.
- **Shutdown tombstones lost:** weakened. Measured: tmux turns its own SIGTERM into a SIGHUP for
  the pane within 0.3 s, and a 2 s handler completed, which is the same shape as kitty's quit. What
  remains UNMEASURED is that tombstones are written at launchd's teardown rather than at the
  app-quit phase, under an unknown SIGKILL deadline. boot-resume takes the last burst within 120 s
  (`boot-resume.sh:111,315-335`).
- **Stale sockets relaunching ended sessions after a reboot:** dropped, because /tmp is wiped at
  boot (row 13). Within a boot it still applies.

## What would restore conviction

1. One cutover, behind a kill switch: the host, the shim's tmux arm (`session list` emitting
   `ccp-*`), `env -u KITTY_*` in the pane, and fixes to `it2-wrapper`/`cc-in-kitty`, `cc-sessions`,
   `lr_recon` and `kitty-confirm-close`.
2. Fix the restart tools: count survivors by live pid, not `kitty_pid == NEW`.
3. `cc-reattach` probes with `has-session` and never creates a session. Replace `remain-on-exit
   on` with a `pane-died` hook.
4. Add a supervisor that notices a vanished host server.
5. Run one real Claude in a host on all 4 accounts. Check Shift+Enter, wheel and scrollback, and
   whether the Background-session notification posts.
6. Get an operator ruling on scrollback before any build.
