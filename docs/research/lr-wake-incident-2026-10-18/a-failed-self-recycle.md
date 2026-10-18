# (a) Pane 332 "failed self-recycle": session 2e9ed9f2 (personal housing-search session)

Read-only investigation, 2026-10-18 ~13:20 CDT. Times are UTC (Z) unless marked CDT (CDT = Z − 5).
Code is cited at trunk b2a295c94 in this worktree.

## 1. Answer first

Pane 332 was not a self-recycle. It was the second of two `cc-lr move` in-place recycles, both
driven from outside the session: next4→next at 03:36Z and next→next3 at 07:20Z. Both failed the
same way, through a race between the recycle's two halves:

- **What exited claude.** The detached watcher's 60-second nudge typed `/exit` into an idle,
  empty composer (`scripts/handoff-fire.sh:11731-11745`, the `retype` arm). It did this before the
  foreground had decided to exit. That foreground was still in its commit tail (confirm, last
  read, load gate), which takes minutes at load 15-28 per core.
- **What left the bare shell.** The foreground then held on load (`handoff-fire.sh:18601-18603`)
  and called `hf_recycle_hold`. That kills the watcher (`hf_recycle_disarm`, `:3341-3345`) without
  checking again whether claude was already gone. At 03:41 the watcher had already finished the
  relaunch, so no harm was done. At 07:24 it was killed between typing the spell-correction
  "disarm" line and typing the relaunch line. That left pane 332 as the plain zsh you see now.

**Fix:** the watcher may type `/exit` only after the foreground leaves an "exit typed" marker. A
hold must never kill a watcher once its subject is gone, or once the watcher has started typing.
In the longer run, transplant and resume recycles should also use the keystroke-free staged
successor.

The rc 0 in pane 332 is that nudged `/exit` (Claude Code exits cleanly). The session-index
"database is locked" error is unrelated noise. The session came back four hours later in a new
**tab** (window 442, OS window 18). That tab came from a hand-written rescue script that passes
`--tab`, not from any recycle.

## 2. Evidence (MEASURED unless marked)

**Pane 332 today** (`kitten @ ls`, `kitten @ get-text --match id:332`):
- OS window 20, tab 148. Foreground process is `/bin/zsh -l -i` (pid 69320). No claude.
- Scrollback, in order:
  1. `claude` / `◆ routed → next4` / SessionEnd db-locked: the original next4 session, pid 79558,
     ending.
  2. `: hfv-68693-1-23423; unsetopt correct…`: the disarm line typed by watcher 68693.
  3. `: hfv-68693-1-30914; cd … LR_RECORD_ID=move-20261018T030847Z-next4-next-36292-2e9ed9f2 … bash …/bundle-20261018T032852Z/lr-launch-2e9ed9f2-4yrxae.sh`:
     the relaunch on next, pid 39396.
  4. `[lr-fire-resume] session ended (rc 0) — this pane is now an ordinary shell.`
  5. `: hfv-77512-1-18249; unsetopt correct…`: a disarm line typed by watcher 77512. **No relaunch
     line follows it.**
- `hfv-<pid>-<attempt>-<rand>` is the per-attempt echo nonce minted by the watcher (`$$` is the
  watcher's pid; `handoff-fire.sh:4455`).

**Who submitted the two `/exit`s.** The prompt history records both:
- `~/.claude-quaternary/history.jsonl`: `{"display":"/exit",…,"timestamp":1792294717306,…"sessionId":"2e9ed9f2…"}` = **03:38:37Z**.
- `~/.claude/history.jsonl` (next): `{"display":"/exit",…,"timestamp":1792308173602,…}` = **07:22:53Z**.
- The stub records the exit wrote into the retired transcript carry the same times:
  - `file-history-snapshot` at 03:38:37.320Z (`~/.claude-next/projects/-Users-chrisren-Development-personal/2e9ed9f2-….jsonl.handed-off:130`).
  - `history-suppression` at 07:22:53.943Z (same file, tail).
- Close records:
  - `~/.claude/logs/close-records/79558-1792277646.json`: `ended_at 03:38:45Z, exit_code 0, signal ""`.
  - `claude-crashes.jsonl`: pid 39396 `RECYCLE/clean-exit` at 07:23:20Z.

**The foreground never typed `/exit` in either run.** Both attempts ended in `recycle-held-load`
(`~/.claude/logs/handoffs.jsonl:784` and `:895`):
- 03:41:08Z: `load 28.09/core is above the 8/core bound … unconfirm rc 2`, watcher_pid 68693.
- 07:24:33Z: `load 15.72/core … unconfirm rc 2`, watcher_pid 77512.

The load gate runs **before** both exit actuators (`handoff-fire.sh:18597-18603`, before
`hf_exit_signal` at `:18629` and the read-back `/exit` at `:18646`). The foreground's own stderr
(`~/.reso/limit-recover/move/20261018T030847Z-next4-next-36292/2e9ed9f2-….handoff.log`) says:
`!! recycle ABORTED before /exit (held: load) … /exit NOT submitted … The session stays alive`.
That was false: the session had been dead for 2.5 minutes. Its unconfirm was refused with
`{"reason":"source-dead"}`. The operator was not at the pane: precheck showed `focused: no`,
`hid_idle_s` 124 and 1251.

**Watcher timelines** (`$TMPDIR/handoff-recycle-332-1792294596-Vj6PQI.log` and `…-1792308018-59eorR.log`):

| run | watcher armed | confirm (HANDOFF.json `ts`) | `/exit` submitted | watcher saw shell | relaunch typed | foreground hold → watcher killed |
|---|---|---|---|---|---|---|
| next4→next | 03:37:05 | 03:37:29 | 03:38:37 | "after 97s" (~03:38:45) | disarm 03:39:50, cmd 03:39:54 → engaged 03:40:39 | 03:41:08 (watcher already done) |
| next→next3 | 07:20:34 | 07:21:50 | 07:22:53 | "after 125s" | disarm 07:24:22, **cmd never typed** | 07:24:33 (killed mid-typing) |

In both runs `/exit` lands 60-90 s after the watcher's wait loop starts, i.e. at its first nudge
checkpoint. The loop has used wall-clock time since 1376807f4 (2026-10-14), `handoff-fire.sh:11389-11407`.

**Control case** (MEASURED): the 02:24Z attempt (watcher 38311) held on load at 02:25:07, 45 s
after arming, which is before the 60 s checkpoint. Claude stayed alive and the unconfirm returned
rc 0 (`handoffs.jsonl:763-764`; bundle 021942Z verdict NOTMOVED). The race needs the commit tail
to take longer than 60 s.

**Earlier unexplained case** (MEASURED that it was unexplained; the cause is INFERRED to be the
same): commit 475d66ced, pane 7, 2026-10-17. The watcher armed at 07:54:14 and claude exited 0 at
07:55:26 (72 s later) at load ~6/core. The commit message says: *"What ended 65405 at 07:55:26 is
not recorded anywhere on disk (no recycle row, no keystroke log…)"*. The keystroke log does exist:
`history.jsonl`. The `cr` and `retype` nudge arms write no row (`:11729-11745`); only `HELD` is
logged (`:11747-11748`).

**Nudge code** (`handoff-fire.sh:11718-11745`, decision at `:5394-5410`): when the composer is
empty (`""`), the decision is `retype`. At checkpoint 60 the watcher sends `/exit`, reads it back
and sends CR. Nothing checks whether the foreground has typed `/exit` yet, and the watcher starts
before the confirm (comment at `:3516-3517`).

**Disarm** (`:3341-3345`): `kill "$WATCHER_PID"`, no conditions. `hf_recycle_hold` (`:3615-3651`)
calls it with no `hf_recycle_subject_gone` check. Those checks exist only before the last read
(`:18589`), before the debt (`:18615`) and before the typed `/exit` (`:18638`). The last read,
which takes ~3 min at load 15-28/core, and the load gate sit between `:18589` and `:18615` with no
re-check.

**Why the relaunch had to be typed** (`:4546-4558`): `hf_succ_stage` stages only for `fresh`. The
handoff log says `→ successor: resume recycle — not staged; the watcher types the relaunch after
its rails`. The keystroke-free path that made fad30cb7's recycle work flawlessly
(`handoffs.jsonl:1096-1099`, "staged successor claimed … nothing typed") is not available to moves.

**The session-index DB lock** (`hooks/session-index-end.sh:60`, `hooks/lib/session-index-helpers.sh:75`,
`busy_timeout` 5000 ms): a SessionEnd hook failure printed on stderr. Claude still exited 0, and
the close record and relaunch were unaffected. Its only effect is a missing index row for that
SessionEnd. It is unrelated to this failure; it shows up because ~50 claudes contend for the index
at this load.

**Where the session went next:**
- 2e9ed9f2 was transplanted to next3 (HANDOFF.json in `~/.claude-next/…`: `handed_off_to …claude-tertiary`,
  ts 07:21:50Z) and had **no live process from 07:22:53Z to 11:32Z**.
- Bundle 071345Z verdict STRANDED. lr-handoff told the operator `lr-fleet.sh --one 2e9ed9f2 --source-pane 332`
  and "do NOT hand-spawn".
- Instead, session 344 (title "Limit-recover account rotation recycle") wrote `/tmp/lr-rescue/resume-2e9ed9f2.sh`
  ("Rescue launcher: transplanted to next3, relaunch never verified (pane 344…)") and
  `/tmp/lr-rescue/fire-round.sh`, which calls `handoff-fire.sh … --tab --surface-reason "rescue relaunch (capacity-refusal retry)"`.
  The rescue rounds show up as capacity rows (`handoffs.jsonl:957,992-993,1004,1007,1035,1043,1050-1051,1061-1062`)
  and as `surface:"bg-tab"` rows naming panes 426 and 435. Both are plain zsh tabs in OS window 18
  today.
- `lead-crash-watchdog.log:63917`: `06:32:00 CDT registered session=2e9ed9f2 … pane=442`.
- 14:19-14:21Z (09:19 CDT): the session self-recycled **in place** inside 442 (fresh mode, staged
  successor claimed, engaged) and became fad30cb7. Its first prompt carries `HANDOFF-RECYCLE-46715-1792333171-645`
  (`handoffs.jsonl:1095-1099`, `lead-crash-watchdog.log:63984`).

**Leftovers:**
- `~/.reso/limit-recover/locks/2e9ed9f2-….launch` is held by `role claude pid 9481`. `ps -p 9481`
  shows that pid is dead.
- `cc-registry/332.json` is absent.
- `cc-registry/442.json` names fad30cb7 on claude-tertiary, pid 39249, alive.

## 3. Causal chain

1. **Origin.** On 17 Oct at 17:54 CDT the operator typed `claude` in pane 332 (routed → next4) and
   opened 2e9ed9f2. The session was healthy and idle after 00:37Z.
2. **Move 1, next4→next** (fleet `cc-lr move` batch 20261018T030847Z, lr-move-worker → lr-handoff
   → `handoff-fire --recycle`, remote in-place form, `LR_INPLACE_AWAIT=0`):
   - the watcher arms at 03:37:05 and the confirm retires the source at 03:37:29;
   - the foreground's last read runs slowly at load 26/core;
   - **the watcher's 60 s `retype` nudge types `/exit` (03:38:37)** and claude 79558 exits 0;
   - the watcher types the relaunch, and pid 39396 comes up on next and engages (03:40:39);
   - the foreground reaches its load gate at 03:41:08 and holds. The unconfirm refuses
     (source-dead), the disarm kills an already-finished watcher, and the bundle says **STRANDED**,
     which is false. The session is actually alive in 332 on next.
3. **Operator activity on next, 04:45-06:54Z**, in 332: "Good to close?", `/limit-recover to account 4`,
   then `to account 2` (refused: "a healthy session cannot move itself while the reconciler is
   live"). Other movers hold the session (bundles 044942Z, 060040Z, 060147Z, 061130Z, 064056Z, all
   NOTMOVED).
4. **Move 2, next→next3** (batch 20261018T070336Z):
   - the watcher arms at 07:20:34 and the confirm runs at 07:21:50;
   - **the nudge types `/exit` (07:22:53)**, and pid 39396 exits 0;
   - `lr-fire-resume` falls through with "this pane is now an ordinary shell"
     (`lr-fire-resume.sh:1859`, no stage to claim);
   - the watcher sees the shell, folds the stub and types the **disarm line at 07:24:22** (8 s send
     at 14.9/core);
   - the foreground's load gate holds at 07:24:33, and **`hf_recycle_disarm` kills watcher 77512
     before it types the relaunch.**
   - **Visible state (a):** pane 332 is a bare zsh showing a half-finished recycle; the session sits
     transplanted on next3 with no process.
5. **Rescue → tab.** Session 344 runs `/tmp/lr-rescue/fire-round.sh` (`--tab`), which goes through
   the capacity gate (refused several times, then admitted via budget-expired). The launch lands in
   new tab 442 in OS window 18 at 11:32Z, plus earlier rescue tabs 426 and 435 that never held a
   claude. **Visible state (b):** tabs.
6. **Recycle in 442.** At 14:20Z the session self-recycles successfully in place and becomes
   fad30cb7. That is why it now lives in a tab and not in pane 332.

## 4. Immediate remediation (describe only; nothing was done)

1. **Close pane 332** (`kitten @ close-window --match id:332`), after one re-check that its
   foreground is still only `zsh -l -i`. Nothing lives there: 2e9ed9f2 is superseded by fad30cb7,
   which is alive in 442. Do **not** relaunch 2e9ed9f2 anywhere, because that would be a second
   writer on the housing work. The sanctioned verb is `lr-fleet.sh --retire-husks --pane 332`, as
   lr-handoff's STRANDED text names it.
2. **Move fad30cb7 out of the tab.** Window 442 is OS window 18, tab 174. Move it into a split of a
   fullscreen 4-pane OS window, e.g. `kitten @ detach-window --match id:442 --target-tab <tab of a 4-split window>`,
   or recycle it in place into a proper split. This is the same work as item (b).
3. **Close the empty rescue tabs.** Panes 426 and 435 (OS window 18, plain zsh, opened by
   `fire-round.sh`) are covered in b-tabs.md. Retire `/tmp/lr-rescue/*.sh` so no one re-runs a
   `--tab` rescue.
4. **Clear the stale lock.** `locks/2e9ed9f2-….launch` names a dead pid (9481). Commit 09c4fd9b4
   steals it on the next take, so it is harmless, but it is untidy.
5. **Hold off on in-place moves at the current load.** The precheck load hold d58bb81d3, landed
   07:14 CDT, now refuses at more than 8/core before the transplant. Measured load at 13:12 CDT was
   85-120 on 10 cores, so every in-place move will hold. That is correct; let it hold and do not
   bypass it with `CC_FIRE_CAPACITY_GATE=off`.

## 5. Long-term fix

**F1. The nudge needs a handshake (the root cause).** `handoff-fire.sh`:
- `recycle_fire_commit` writes `"$cmdfile.exit-typed"` (epoch) right before the first exit
  actuator, after the subject re-read at `:18615` and the debt, just ahead of `hf_exit_signal` at
  `:18629`.
- In the watcher loop (`:11718-11745`), `cr` and `retype` act only when that marker exists. The
  60/150/300 checkpoints count from the marker's mtime, not from arming. With no marker, the watcher
  keeps waiting; its 600 s bound and the foreground's own hold handle the rest.
- Every nudge that fires emits `recycle-nudge-cr` or `recycle-nudge-retype` with the composer read,
  so an unexplained exit like pane 7 can never be silent again.
- The `retype` rationale ("typed-but-lost transport") only makes sense after the foreground typed
  `/exit`, and the marker states exactly that.

**F2. A hold must not kill a watcher once the subject is gone.**
- In `hf_recycle_hold` (`:3615`), before `hf_recycle_unconfirm`/`hf_recycle_disarm`: if
  `hf_recycle_subject_gone`, call `hf_recycle_subject_yield "at the $1 hold"; return 0` and
  disarm nothing.
- Add the missing re-read between the last read and the load gate (insert at `:18597`).
- Change the hold sentence's "The session stays alive" to be conditional on a live subject. At
  03:41 it was false.

**F3. A watcher that is typing cannot be disarmed.**
- The watcher writes `"$cmdfile.typing"` before `it2_type_verified` and traps TERM while it exists,
  so it finishes the command line.
- `hf_recycle_disarm` (`:3341`) declines to kill when that marker is present and logs
  `recycle-disarm-refused-typing`.

**F4. Keystroke-free delivery for moves.** Extend `hf_succ_stage` (`:4558`) to `transplant`/`resume`.
The consumer (`lr-fire-resume.sh` fall-through at `:1830-1858`, `reso-resume-one`, `cc-close-attrib`)
would run the fold-stub and launch-lock rails at claim time. This takes the typed relaunch off the
move lane entirely, which is the class that keeps stranding under load (pane 44, pane 7, pane 332).

**F5. Rescue by hand cannot open a tab.**
- A `handoff-fire --launcher … --tab` whose launcher resumes a sid with a STRANDED record and a
  known source pane should be refused. Point to `lr-fleet --one <sid> --source-pane <P>`, or
  relaunch into the husk pane itself (the in-place shape the operator wants).
- `--surface-reason "rescue…"` from an agent should be a lint target.

**F6 (hygiene, not causal).** `session-index-end.sh` should skip indexing, or queue it, when
`sqlite3` reports `SQLITE_BUSY` above load N, instead of failing loudly on every SessionEnd under
load.

**Tests that would have caught it:**
- `tests/handoff-recycle-subject-exited.bats`, new case **"watcher nudge does not type /exit before
  the foreground's exit-typed marker"**:
  - set `HF_RECYCLE_SHELL_POLL_S=1` and use a fake `it2` that records sends and reads an empty
    composer;
  - stub `pane_cc_state` to return `cc` for 70 s;
  - assert that no `/exit` send appears with no `.exit-typed` marker, and that exactly one gated
    retype appears 60 s after the marker is created.
  - On trunk this goes red: a `/exit` is sent at about 60 s.
- `tests/handoff-recycle-load-hold.bats`, new case **"a load hold after the subject exited yields
  and never kills the watcher"**:
  - pin the subject to a sleeper pid and kill it inside a stubbed `hf_recycle_last_read`;
  - set `HF_LOAD_PER_CORE=30`;
  - assert rc 0, a `recycle-subject-exited` row, no `recycle-held-load` row, and `WATCHER_PID`
    still alive.
  - On trunk this goes red: held-load fires and the watcher is killed.
- Fixture: scrubbed copies of tonight's two watcher logs, `handoffs.jsonl:780-784,889-895`, and the
  two `history.jsonl` `/exit` rows under `tests/fixtures/move-lane-2026-10-18/pane332/`.

## 6. Confidence

**85%** that the root cause is the watcher's 60 s retype nudge plus a hold that kills the watcher
unconditionally.
- **Measured:** both `/exit` submissions, both foreground holds before the actuators, the kill
  falling between the disarm line and the relaunch line, and the control case holding inside 60 s.
- **Inferred:** that the nudge was the sender. It writes no row, and no other `/exit` typer was
  active on pane 332 (the foreground had not reached its actuators and the operator was idle and
  unfocused).

What would change this:
- **Raises it to ~99%:** a replay of the watcher loop with a fake `it2`, the first test above,
  showing the `/exit` send at 60 s.
- **Lowers it:** a second actor's send to pane 332 at 03:38 or 07:22. Candidates are another
  recycle, `cc-husk-sweep`, or the reconciler; a kitty RC log, if one exists, would show it.
  Another lowering signal: a Claude Code 2.1.293 behaviour that self-submits `/exit` on transcript
  retirement. Unlikely, since `history.jsonl` records it as a typed prompt.

## Adversarial verification

Done read-only at 13:31 CDT. I re-opened every code citation at b2a295c94 and every log row.

**Verdict: NOT REFUTED.** The root cause holds: the watcher's 60 s `retype` nudge exits claude
before the foreground reaches its actuators, and a hold then disarms the watcher with no check.
The race is also wider than one pane (see "Missing"). Adjusted confidence: 88%.

**Checked and correct (MEASURED):**
- Code:
  - `handoff-fire.sh:11718-11745`: the nudge arms. `:5394-5410` (`""` gives `retype`).
  - `:3341-3345`: disarm is an unconditional `kill`. `:3615-3651`: the hold calls unconfirm, then
    disarm, and never checks the subject.
  - Subject re-reads exist only at `:18589`, `:18615` and `:18638`. The last read is `:18594`, the
    load gate `:18601-18603`.
  - `:4558`: only `fresh` gets staged. `:3516` says the watcher is detached before the confirm.
    `lr-fire-resume.sh:1859` is the "ordinary shell" line.
- Logs:
  - `handoffs.jsonl:763-764`, `780-784` and `889-895` say what the doc says. Watcher lstarts are
    03:37:05 and 07:20:34.
  - quaternary `history.jsonl:6197` has `/exit` at 1792294717306 (03:38:37Z). `~/.claude/history.jsonl`
    has `/exit` for 2e9ed9f2 at 1792308173602 (07:22:53Z).
  - Close record: 03:38:45Z rc 0. `claude-crashes.jsonl:6025` has 39396 clean-exit at 07:23:20Z.
  - `/tmp/lr-rescue/fire-round.sh:3` passes `--tab`.
  - `cc-registry/442.json` names fad30cb7, and pid 39249 is alive (`ps`).
- Alternative typers: I grepped `scripts/limit-recover`, `bin`, `hooks` and `scripts/lib` for `/exit`
  sends and found no other actor. Every handoffs row for pane 332 belongs to one of the four known
  attempts. No second sender was found.

**The timing supports the nudge (INFERRED from the code plus MEASURED times).** `waited` is updated
only after each round's sleep (`:11402`). The round that consumes the 60 checkpoint makes up to
four it2 calls, each bounded at 10 s; the pane listing alone took 8 s. Its CR therefore lands
30-65 s after the checkpoint:
- run 1: CR at about waited=90, shell "after 97s";
- run 2: CR at about waited=123, shell "after 125s".

Both fall between the 60 and 150 checkpoints, which is what this mechanism predicts. The doc's
statement that `/exit` "lands 60-90 s after the loop starts" is INFERRED, not measured: the time
the loop started is not logged.

**Corrections:**
1. **F2 as written does not stop the caller.** `hf_recycle_hold` is an exit-1 function, and its
   callers at `:18595` and `:18603` fall through. A `return 0` inside it would run on into the
   load gate, the debt and the actuators. Use `exit 0`, the commit's yield rc, or have
   `recycle_fire_commit` re-read the subject itself before each `hf_recycle_hold` call.
2. **The same hazard has more sites.** 12 other bare `hf_recycle_disarm` calls exist, for example
   the confirm refusals at `:18560` and `:18569`. In run 2 the confirm finished 76 s after arming,
   so the nudge can exit claude *before the source is retired*. F1 covers this. F3 has to guard
   disarm itself, not just the hold.
3. **F1 changes how a dead foreground fails.** Today, if the worker dies after the confirm, the
   nudge "rescues" the session. With the nudge gated, claude stays alive on a retired source:
   `handed-off-session-guard` blocks its prompts until the 600 s bound. The watcher's no-marker
   timeout should therefore unconfirm from `$CMDFILE.confirmed` (the same path as
   `rcy_bgwork_unconfirm`), and a test should cover it.
4. **`hf_recycle_subject_yield` (`:3928`) misattributes the exit.** It says the subject "exited on
   its own". The 5 `recycle-subject-exited` rows on 2026-10-18 (panes 47, 8, 340, 393, 398) are
   probably nudge exits too, and the wording hid the race after 475d66ced.
5. **Remediation item 1 is no longer needed.** Window 332 does not exist at 13:31 CDT
   (`kitten @ ls`: only ids 340 and 344 fall in the range 320-345).

**Missing:**
- **The fleet-wide pattern (MEASURED, jq over handoffs.jsonl):** 10 `recycle-held-load` rows with
  `unconfirm rc 2` (source-dead):
  - pane 20 at 02:08, pane 24 at 02:21;
  - pane 332 at 03:41 and 07:24;
  - panes 1 and 21 at 07:06, pane 390 at 07:19, pane 22 at 07:23;
  - pane 23 at 08:03, pane 242 at 10:39Z.
- **What their watcher logs show:**
  - Panes 20, 24, 21 and 22 log "CONFIRMED at a shell prompt — typing relaunch", and no "relaunch
    typed" follows. That is the same mid-typing kill, and it explains part of item (c).
  - In panes 20, 22 and 242 the watcher answered the background-work dialog `1` (Exit and stop
    tasks) after the nudged `/exit`. The nudge raised that dialog (item d) and stopped tasks for a
    recycle that the foreground then abandoned.
  - The watchers for panes 1, 390 and 23 never saw a shell. They are candidates for the stuck
    dialog, or a `/exit` left in the composer.
- **Pane 22 / 22a76c8a, same batch 070336Z:** `/exit` at 07:22:38Z (history), dialog answered at
  07:23:04, held at 07:23:23 with rc 2. It is also in `/tmp/lr-rescue/next3-batch.tsv`.
- **The 06:12Z self-initiated recycle** (`handoffs.jsonl:810-811`, firing_sid 332, watcher 86284,
  held on load at 48.89/core, rc 0) is missing from the timeline.
- **When the race was exposed.** The `retype` arm dates from 77864768f (2026-08-22). It was exposed
  by three later changes:
  - 1376807f4 (2026-10-14) put the checkpoints on the real clock;
  - 18910dd50 (2026-09-29) added the post-arm last read;
  - 2bb9817d0 (2026-10-11) added the post-arm load gate.

  The design line at `:19398` still assumes the foreground's `/exit` follows the arm "in seconds".
