# C1 skeptic review: operator risk

Skeptic pass on `C1-session-layer.md` (tmux host per session, kitty as a restartable viewer). Lens: what
adopting C1 costs or breaks for the operator, and the scenario where it makes the next incident worse.
Read-only. Experiments ran only on private tmux servers `-L sd-probe-skeptic{,2,3}` with dummy
processes; all three were killed and their socket files removed. **0 of 3** allowed `kitten @ ls`
calls were used. `claude` was never launched. Upstream sources were fetched to `/tmp/sd-skeptic-risk/`.

## Answer

**The survival mechanism is real, but C1 as designed and phased makes the next kitty incident worse
before it makes it better.** Three things drive that:

1. **It has no safe halfway state.** C1 breaks three facts the repo's protective tools rely on:
   - claude runs under its kitty pane;
   - a registry id appears in kitty's pane list;
   - `KITTY_*` env names the live kitty.

   The first phase that puts a live session in a host breaks all three. The dossier ships the
   identity migration last (phase 3). Until then, the first "free" kitty restart leaves every
   surviving session with a dead control plane. It also leaves sessions that cc-sessions hides at
   once and deletes from the registry after 24 h.
2. **It adds failure modes that kill sessions instead of deafening a socket.** tmux turns an
   unhandled `accept()` errno into `exit(1)`, which takes the session down. Dead servers also leave
   socket files behind (measured), and the start-or-attach host turns a stale socket into a new
   launch.
3. **Some ergonomics are lost on day one with no designed replacement.** Kitty's scrollback, search
   and pager go blank: tmux puts kitty on the alternate screen (measured). ⌘W silently becomes
   "detach" and stops ending the session.

**Fatal flaw:** none that cannot be engineered away. **Recommended conviction: 35** (dossier: 55).
The drop comes from the zero-value-until-complete migration, an irreversible rollback, and the
measured contradictions below. Survival under (a) and (b) is not in dispute.

## Verdicts on the dossier's claims

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Pane survives client SIGKILL and pty close; reattach redraws | **stands** | Dossier E1 (measured). Nothing here contradicts it. Caveat: survival now depends on the tmux server's own health (see #4). |
| 2 | A viewer that stops reading cannot stall claude | **stands** | Dossier E1. Its benefit is conditional: the dossier itself marks "does kitty stop reading ptys at PRI 4" UNMEASURED (C1:53-54). |
| 3 | The control plane leaves kitty's PRI-4 band | **stands** | Dossier E2 ps readings. Showing a pane (launch viewer, fullscreen, move) still needs kitty's socket (C1:199-201). |
| 4 | tmux recovers from EMFILE and ECONNABORTED; one server per session bounds a fatal accept to one session | **weakened** | Fetched tmux 3.6a `server.c:380-389`: only EAGAIN, EINTR and ECONNABORTED are skipped, and ENFILE/EMFILE back off; anything else calls `fatal()`. `log.c:140-152`: `fatal()` calls `exit(1)`. `man 2 accept` (this box) lists **ENOMEM**, which is unhandled. Under kitty the same class of error deafened the socket and the sessions lived (husk-panes-2026-09-30.md:91). Under C1 it kills the session. The one-per-session isolation holds only for independent faults: a systemic cause (memory pressure) hits every server that accepts during the episode, and censuses, readbacks and `list-clients` identity lookups (C1:193-194) connect to all 32. ENOMEM on this box is UNMEASURED. Kitty's errno is unknown. |
| 5 | As configured, tmux breaks teammate spawning with a thrown error | **stands** | Dossier E3. |
| 6 | Auto mode plus `$TMUX` selects TmuxBackend and disables in-process teammates | **stands** | Dossier E3. |
| 7 | One kitty `map` line makes Shift+Enter work | **stands (mechanism); risk understated** | The map is keyed on `--when-focus-on var:cc_host`, so every viewer launch path must pass `--var cc_host` (cc-reattach, it2 split, hand-opened windows, ⌘D). A viewer opened any other way silently **submits** a half-written prompt. Behavior with a real Claude is UNMEASURED (C1:123-124). |
| 8 | OSC title, OSC 52, paste, mouse and sync pass through | **stands** | Dossier E4 (measured). OSC 52 emitted while detached is dropped. |
| 9 | Pane env is frozen at server start, so kitty identity goes stale after a restart | **stands; understated** | It is not only `KITTY_WINDOW_ID`. Frozen `KITTY_LISTEN_ON` names the dead kitty's socket. Three code paths turn that into a dead control plane (see the next three rows). Net: every surviving session's recycle, self-close and viewer launch fails until phase 3 lands. |
| 9a | it2-kitty uses the inherited socket | **(sub-finding)** | `bin/it2-kitty:375`: `sock="${CC_TERM_KITTY_TO:-${KITTY_LISTEN_ON:-}}"`. |
| 9b | handoff-fire never probes for a live socket | **(sub-finding)** | handoff-fire's live-socket probe runs only when `KITTY_WINDOW_ID` is empty (`handoff-fire.sh:1234`). |
| 9c | cc-kitty-socket returns the dead socket | **(sub-finding)** | `bin/cc-kitty-socket:57-60` takes its fast path whenever the inherited socket file exists, and "a socket file outlives a SIGKILLed kitty" (`handoff-fire.sh:1216-1219`). |
| 10 | Kitty 0.48.2 sessions only replay launch commands | **stands** | Dossier E5. |
| 11 | Memory and CPU cost is small | **stands** | Dossier E7 (measured). The fleet CPU figure is ESTIMATED. |
| 12 | Hand-opened path: "On exit, `exit-empty` ends the server and the pane returns to its prompt" (C1:215) | **refuted** | Measured with `remain-on-exit on` + `exit-empty on` (the dossier's own config, C1:184), pane cmd `echo; sleep 1; exit 0`. After 3 s: `list-panes` ⇒ `pane_dead=1 status=0`; `list-sessions` ⇒ `s1: 1 windows`; screen ⇒ `Pane is dead (status 0, …)`. Every clean `/exit` leaves a server holding a dead pane, and its kitty viewer shows that instead of a prompt. That is a new kind of husk no sweep knows. It also defeats cc-pane-runner's close-on-exit fix and handoff-fire's "pane already gone" branch (`handoff-fire.sh:8359`). |
| 13 | `cc-reattach` enumerates `/tmp/tmux-501/ccp-*`, and the host attaches if the server exists, otherwise creates (C1:177-179, :203) | **weakened** | Measured: after a natural exit-empty exit, `tmux ls` ⇒ `no server running`, yet `os.path.exists(socket)` ⇒ `True`; same after `kill-server`. Every ended session leaves a socket. A naive enumerate-then-host pass then **creates** a fresh session in a dead slot. If the host re-reads its `cc-hosts/*.json` command, it relaunches a deliberately ended session and bypasses capacity admission and the live-holder dedup. That is the dossier's own objection to kitty sessions (C1:140-142). The same holds for any replay of the viewer command (kitty `startup_session`, a saved session). |
| 14 | "Today's dedup … already sees a live tmux-hosted claude" (C1:219-220) | **weakened** | Mechanism: see Scenario 1, step 2. |
| 14a | The registry leg | **(sub-finding)** | `lr_holder_count` (`scripts/limit-recover/lr-lib.sh:509-540`) is registry rows checked with `kill -0`, unioned with `ps` leaves whose argv holds `--resume <sid>`. The ps leg sees only `--resume` launches. Fresh fires rely on the registry row, which cc-sessions deletes after 24 h under C1. Once it is gone, H(sid)=0 and a second writer becomes possible. |
| 15 | Agent operations stay classifier-bound and "unchanged" (C1:258-259) | **stands** | The classifier judges the outer command (`handoff-fire.sh …`), not the shim's inner `kill-server`. Unchanged as claimed. |

## The scenario where adopting C1 makes the next incident worse

Setup: phase 1 (host, viewer, reattach) is live, as the dossier phases it. Kitty 0.48.2's remote-control
thread dies again (the same unfixed `accept_peer` path). The operator restarts kitty because C1 made
that "free", then runs `cc-reattach`. All 32 claude processes survive. Then:

1. **Every survivor loses its own control plane.** Frozen `KITTY_LISTEN_ON` points at the dead
   socket (rows 9a-9c). Recycles, handoffs, self-closes and fires from inside sessions all fail, so
   the 2026-10-01 deadlock returns with live sessions that cannot retire. Today a kitty restart at
   least clears that state; under C1 it persists for the life of each process.
2. **cc-sessions stops seeing the sessions.** The design exports both `CC_PANE_ID=ccp-<id>` and
   `ITERM_SESSION_ID=w0t0p0:ccp-<id>` (C1:179-180).
   - `hooks/session-register.sh:173` keys the registry row on `CC_PANE_ID` first.
   - `:203-207` records `surface=pane` whenever `ITERM_SESSION_ID` is set.
   - `bin/cc-sessions:326-327` marks a pane row stale when its id is missing from `it2 session
     list`, and kitty never lists `ccp-*`.
   - `:328-333` with `RETAIN_S` = 24 h (`:276`) then **deletes** the row.

   Result: cc-notify cannot address any hosted session, and after a day the second-writer guard
   (row 14a) goes blind for fresh fires. Sessions that survive kitty restarts are exactly the ones
   that live past 24 h.
3. **cc-husk-sweep sees 32 husks.** `has_claude_under` walks 4 generations below the kitty pane pid
   (`bin/cc-husk-sweep:177-191`, used at `:421`). Under C1 that pid is a tmux client, and claude
   runs under a ppid-1 server, so every pane is a husk candidate.
   - Its only guard against live sessions is `is_live_sid`, which reads cc-sessions (`:200-205`),
     and step 2 empties that.
   - The scrollback arm then mines the viewer's screen for `claude --resume <sid>` text.
   - `--resume` types `nocorrect … claude --resume <sid>` plus CR through the viewer into a **live
     composer** (`type_line`, `:394-409`). The echo-verify passes, because the text really is in
     the composer.
   - The DESK-down page tells the operator to run exactly that command
     (`hooks/lead-crash-watchdog.sh:1256`).

   End to end this is UNMEASURED: a chain read from code, with its preconditions stated.
4. **Fires during the deaf window run headless and unseen.** The design says a fired session "still
   starts and runs headless, and a viewer is attached later" (C1:201). Step 2 hides those sessions
   from cc-sessions too, so they burn quota with nobody watching.

Today the same incident costs a restart and a resume. Under phase-1 C1 it costs a fleet that is
alive but cannot be managed, plus invisible sessions and a sweep aimed at live composers.

## Missed risks (not in the dossier's list)

- **Scrollback is lost on day one.**
  - Measured: a tmux client attached with `TERM=xterm-kitty` sent `ESC[?1049h`
    (`smcup ?1049h present: True`), so kitty sits on the alternate screen. Kitty's own scrollback,
    search and pager hold nothing, and `it2 read -n N` readers that expect history get one screen.
  - The config `unbind -a` + `prefix None` (C1:184-185) removes tmux's default mouse and copy-mode
    bindings.
  - `~/.config/kitty/kitty.conf:208` records that Claude "grabs the mouse", so the wheel goes to claude, not to
    tmux. Nothing in the design reaches history above one 2x2 quadrant.
  - Muscle-memory cost: certain. Replacement: not designed.
- **A bare `tmux` inside a session targets the session itself.** Measured in a private pane:
  `SOCK=/private/tmp/tmux-501/sd-probe-skeptic3_PANE=%0` and
  `TMUX=/private/tmp/tmux-501/sd-probe-skeptic3,57797,0`. Two consequences:
  - `hooks/teammate-auto-shutdown.sh:211` runs `tmux kill-pane -t "$pane"` for any `%N` id. Under
    C1, `%0` is the lead's own claude.
  - Any agent experiment that forgets `-L` and runs `tmux kill-server` ends its own session.
    Today the same command hits an idle default server.
- **There is no rollback path.** Recycles `respawn-pane` in place (C1:184), so hosts never drain.
  Backing C1 out means ending every live session, which is operator-only under the classifier: the
  manual mass rebuild the operator is trying to avoid.
- **Build cost is understated** (measured with grep and wc):
  - `bin/it2-kitty` is **1,523** lines, against a ~400 LOC tmux arm estimate.
  - **143** test files reference `KITTY_WINDOW_ID`, `kitty @`, `kitten @` or `it2-kitty`. All of
    them encode kitty-shaped identifiers, and a second id space must be fixtured in its real shape.
  - The dossier budgets ~400 LOC of new bats and none of this. Time to value, ESTIMATED from these
    counts: weeks, not 2-3 days.
  - Under the dossier's own rule (C1:245-246, "keep kitty-only behavior as the default path until
    the shim passes"), value is zero until then.
- **C1 changes how sessions die at shutdown, which C2 depends on (UNMEASURED).** Tombstones rely
  on each session's SessionEnd running during kitty's quit SIGHUP burst ("all 19 roster sessions
  … inside 4 seconds", `hooks/session-deregister.sh:66-71`). Under C1, quitting kitty only detaches.
  Sessions die later, when launchd tears down tmux at logout. Nobody has measured whether
  SessionEnd still completes there. If it does not, boot-resume's last-burst detection misses the
  fleet.
- **Closing a kitty window becomes detach, everywhere.** It changes the operator's ⌘W, and it
  changes every automated closer (`teammate-orphan-pane-close.sh:134`, `pane-close-retry.sh:224`,
  `kitty-confirm-close`). Each of those now leaves a running, invisible session instead of a closed
  one, unless every closer is re-pointed at `kill-server`.
- **Keychain auth (UNMEASURED).** There are published reports of Claude Code inside tmux on macOS
  re-prompting for login when the tmux server's security session is not the current Aqua session
  ([junyi.dev](https://www.junyi.dev/en/posts/tmux-keychain/)). Servers started from a kitty pane
  are probably fine. Servers created by launchd agents (C2's boot-resume into hosts,
  desk-invariant respawns) need a real-claude test across all 4 accounts before adoption.
- **Checked and dropped (one-armed check avoided):**
  - macOS `tmp_cleaner` deletes only `-type f` (`/usr/libexec/tmp_cleaner`), so tmux sockets are
    not reaped by it.
  - cc-reaper's garbage arm whitelists `tmux` and any subtree holding a live claude
    (`bin/cc-reaper:551`, `:713`).
  - The kitty wheel-to-arrow conversion on the alternate screen (`mouse.c:1560-1565`,
    `keys.c:315-329`) does not hit claude panes, because claude enables mouse tracking. It still
    hits bare-shell panes, as Up-arrow history recall.

## What would have to be true to restore conviction

1. Ship host, shim tmux arm (including `session list` emitting `ccp-*`) and the identity strip
   (`env -u KITTY_*` in the pane command) **as one cutover**, behind a kill switch, never phased.
2. Use `remain-on-exit failed`, or a per-respawn setting, and re-measure #12.
3. Make reattach probe liveness (`tmux -L <id> ls` rc) and never create a session.
4. Teach cc-husk-sweep, cc-sessions and every closer that a host is live.
5. Test one real Claude in a host for Shift+Enter, scrollback UX and keychain on all 4 accounts.
6. Get an operator ruling on scrollback before any build, since it is the one cost that cannot be
   engineered away.
