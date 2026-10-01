---
status: proposed
---

# W3 build plan: H1 restore-first, then the kitty patch

> **Scope (frozen):** build the path recommended in `judge-verdict.md`. That is H1, C4 revision 2
> with amendments J1-J5: a crash, a kitty restart or a reboot brings every session back with at most
> one command, in its old window group, one row of panes per fullscreen window, with nothing
> resurrected or duplicated, and with lost background work named in each session's inbox and
> re-engaged where there is evidence of it. Then C3's P2 kitty patch, built for the operator to adopt
> at a planned restart. A tmux session layer (H2) is **not** in W3; it has a gate, listed at the end.

All line numbers are **origin/main at 2026-10-01 ~16:30**, 22 commits ahead of the research branch.
Every phase rebases on main before it lands, and re-greps its anchors first, because
`handoff-fire.sh` and the boot-resume chain change several times a day.

## Phase 0: orchestration

**Execution locus per wave.** S = a dispatched session (`scripts/handoff-fire.sh`, one per phase,
its own worktree, `--notify-back` to the W3 lead). Every phase below is S, the default, so none needs
a justification.

| Wave | Phases | Locus | Can run together because | Waits for |
|---|---|---|---|---|
| W3.1 | P1 recycle fork fix · P2 safety rails · P6 kitty patch | S, S, S | disjoint files: `handoff-fire.sh` / `cc-reaper`, `cc-resume-layout.sh` `k()`, `reso-resume-one`, new lock lib / `docs/patches`, `kitty-build-swap.sh` | nothing |
| W3.2 | P3a boot-resume event mode · P3b layout restore mode | S, S | disjoint files (`boot-resume.sh` + `alarm-reboot-prep.sh` + new heartbeat lib / `cc-resume-layout.sh`), joined by the row contract below | P2 |
| W3.3 | P4 recovery delivery | S | owns `cc-resume-classify.py`; edits `reso-resume-one` and `boot-resume.sh` after their earlier owners land | P3a, P2 |
| W3.4 | P5 `cc-restore` and the crash page | S | owns the new `bin/cc-restore`; edits `boot-resume.sh` last | P4 |
| G1 | first planned restart | operator | — | P5 landed |

- **Every fire carries `--goal`:** `'<phase> landed on origin/main — proven by the session running
  and printing <the phase's Verify command> and git ls-tree origin/main -- <its new files>; do not
  touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § <phase>'`.
  The goal evaluator sees only what the session prints, so each phase's Verify line doubles as its
  proof.
- **One owner per shared file at a time.** `boot-resume.sh`: P3a, then P4, then P5.
  `reso-resume-one`: P2, then P4. `cc-resume-layout.sh`: P2, then P3b. `tests/boot-resume.bats`
  follows `boot-resume.sh`.
- **Lead context budget.** The W3 lead fires, awaits and collects; it writes no code. It keeps at
  least 50% of its window. Succession point: after W3.2 has landed and been verified, the lead
  recycles (`handoff-fire.sh --recycle`), with this file and the custody ledger as its state.
- **Task list.** The task tools are off on this account, so the phase table below is the list. Each
  phase's session marks its row and adds its landed sha.
- **Reboot-path flag.** New behaviour on the **reboot** path (P3a, P3b, P4) sits behind
  `~/.claude/autonomy/boot-resume/restore-v2`. Without the file the reboot path behaves as today,
  except for pure fixes, which go live at once. The event path is reached only through the new
  `cc-restore` and is always v2. P5 creates the flag after its own verification passes and names it
  in its ping. Deleting the file is the off switch. Why: `~/.claude` is a symlink farm, so each land
  is live immediately, and the next kalloc reboot (about every 5 days) must not run a half-built
  restore (C4-skeptic-risk #9).

| # | Phase | Wave | State | sha |
|---|---|---|---|---|
| P1 | Recycle never forks a hidden copy | W3.1 | open | |
| P2 | Safety rails | W3.1 | open | |
| P6 | kitty talk-thread patch, built apart from the title band | W3.1 | open | |
| P3a | boot-resume event mode, heartbeat, roster, retire, ledger, capacity | W3.2 | open | |
| P3b | Layout: restore mode, one row, fullscreen by id | W3.2 | open | |
| P4 | Recovery delivery: inbox note, evidence-gated launch nudge | W3.3 | open | |
| P5 | `cc-restore` and the crash and deaf pages, then flip `restore-v2` | W3.4 | open | |

### Row contract between P3a and P3b (fixed here so the two can build in parallel)

- **Input rows.** `boot-resume.sh` pipes rows to `cc-resume-layout.sh --desktops` on stdin
  (`boot-resume.sh:578`). Today a row is `alias sid cwd branch label`, and the layout reads columns
  1-4 (`cc-resume-layout.sh:146-153`, `:241-242`).
- **P3a appends:** 6 `model`, 7 `effort`, 8 `group` (desk key), 9 `slot` (order within the group),
  10 `prompt_file`. Each empty cell is written as `$TSV_PAD`, never left empty (the
  field-collapse guard, `boot-resume.sh:244-256`).
- **The layout** treats a row with only 5 columns exactly as today. The classifier verdict stays the
  last column (`$NF`).
- **New flags:** `--restore` on the layout and `--event` on boot-resume. Neither changes a default.
- **The layout prints one map line per launch:** `cc-resume-layout: map sid=<sid> wid=<wid> oswin=<n>`.
  It goes on stdout, ahead of the existing `verdict=` summary (`:316`). `boot-resume.sh` copies the
  map lines to `$STATE_DIR/last-layout.map`.

## P1: a recycle never forks a hidden copy

- **Goal.** No recycle answers "Move to background and exit" by default. Each answer forks the whole
  conversation into an unregistered background worker. On 10-01 that worker (9aa483e9, 761k tokens)
  woke on its own and edited a successor's brief (C5 E2; C5-skeptic-code K1). Its only "background
  work" was the session's own `cc-await-ping` watcher.
- **Changes:**
  - **Stop our own watchers first.** In the recycle foreground path, before the teardown marker and
    the `/exit` (`scripts/handoff-fire.sh:15734`, `write_teardown_marker "$SID" recycle`), run
    `cc-await-ping --stand-down` for the recycling session's own inbox. That is self-scope, and
    killing one's own watcher is allowed. A watcher-only session then exits without raising the
    dialog at all.
  - **Hold on real work.** At the background-work dialog (`:8892-8945`; the keep-work answer is at
    `:8936-8941`), change the default of `CC_RECYCLE_BGWORK_ANSWER` from `on` to `off`, which is
    today's hold path at `:8943`. Real background work then holds the recycle until it finishes, as
    the 96 measured `recycle-held-bg-work` rows already do. `CC_RECYCLE_BGWORK_ANSWER=on` stays as an
    explicit opt-in to the old fork behaviour.
  - **Record every answer that is still made.** Emit the fork's account, so the cross-account crash
    class (`b363d8e6`, `~/.claude-quaternary/daemon.log:103-105`) can be counted.
- **Do not** chase forks with `claude stop`. It races the fork's wake-up turn, and it is not durable
  (C5-skeptic-code M5; C5-skeptic-risk, fatal flaw point 4).
- **Tests.** Extend `tests/handoff-recycle-bgwork-dialog.bats`:
  - watcher-only background work → stand-down, then `/exit`, no dialog answer;
  - real background work → hold (the `recycle-held-bg-work` row), no `2` sent;
  - `CC_RECYCLE_BGWORK_ANSWER=on` → old behaviour (a mutant pin).

  `tests/handoff-recycle-bg-session.bats` must stay green.
- **Verify.** `bats tests/handoff-recycle-bgwork-dialog.bats tests/handoff-recycle-bg-session.bats`
  prints its `1..N` plan line and no `not ok`. Then, against the live `handoffs.jsonl`:
  `grep -c recycle-bgwork-answered ~/.claude/logs/handoffs.jsonl`, run before and after a week, is
  flat.
- **Risk.** A recycle of a session running a long background build now waits. That is a slower
  recycle, never a lost or duplicated one.
- **Size.** About 100 LOC plus 60 bats lines.

## P2: safety rails (before any new restore code)

- **Goal.** Close the ways a restore can be killed, can hang, or can launch a session twice, before
  anything new runs.
- **Changes:**
  - **Reaper.** Add `boot-resume|cc-restore` to `GARBAGE_WL` (`bin/cc-reaper:713`). The launchd
    restore runs past cc-reaper's 600 s orphan-bash cutoff (`:918`, `:933`; both C2 skeptics).
  - **Bounded `k()`.** Bound the layout's kitty wrapper (`bin/cc-resume-layout.sh:175`) with
    `timeout ${CC_RESUME_K_TIMEOUT:-15}`. Today it is unbounded (C3 census; C4-skeptic-risk #4).
  - **Per-session launch lock.** In `bin/reso-resume-one`, take a per-sid lock before the expect
    program (the spawn is at `:560`; the lock goes ahead of `expect -c` at about `:536`). Use
    `mkdir ~/.claude/autonomy/resume-locks/<sid>.lock`, with a stale-lock rule keyed on the holder
    pid. If a live claude already holds that sid (`lr_holder_count`, `scripts/limit-recover/lr-lib.sh:509-540`),
    exit 5, "held". A launch kitty runs late can then never start a second copy (C4-skeptic-risk #3;
    C2-skeptic-code second pass #2).
  - **New `scripts/lib/restore-lock.sh`:**
    - `restore_lock_take <event-id>`: a global `mkdir` lock plus an `events/<id>.inprogress` claim;
    - `restore_lock_release`;
    - `restore_refuse_under_bats`: refuses any signal when `BATS_TEST_FILENAME` is set. A test once
      reached the live kitty (commit 1deb094d2; C2-skeptic-risk second pass #4).
- **Not here.** The `.start` fix moves to P3a. Landing it alone would let a stale alarm roster (up
  to 24 h old) outrank everything at the next reboot, because today the bug is the only thing
  keeping that roster out (C2-skeptic-code second pass #3).
- **Tests:**
  - `tests/cc-reaper.bats`: a launchd-parented `bash …/boot-resume.sh` older than 600 s is not
    TERMed.
  - `tests/cc-resume-layout-desktops.bats`: a stub kitty that sleeps 30 s returns rc 124 within the
    bound.
  - `tests/reso-resume-one.bats`: a second launch of a locked sid exits 5 and spawns nothing; a stale
    lock is reclaimed.
  - New `tests/restore-lock.bats`.
- **Verify.** `bats tests/cc-reaper.bats tests/cc-resume-layout-desktops.bats tests/reso-resume-one.bats tests/restore-lock.bats`
  prints its `1..N` plan line and no `not ok`.
- **Risk.** A wrong stale-lock rule would hold a legitimate relaunch. The holder-pid check plus
  `kill -0` bounds that.
- **Size.** About 220 LOC plus 180 bats lines.

## P6: kitty talk-thread patch (C3 P2), built apart from the title band

- **Goal.** A kitty build in which an `accept()` error no longer kills the remote-control thread, and
  in which signals (SIGTERM, SIGCHLD reaping) work again. The 2026-10-01 deadlock was that thread
  dying (`child-monitor.c:1821-1826`, `:2058`; evidence in `evidence-kitty610-thread-samples.txt`).
  The signal clobber has already fired on today's kitty 48854 (C3-skeptic-code second pass, claim 5).
- **Changes:**
  - New `docs/patches/kitty-talk-thread-survives-v0.48.2.patch`, three parts:
    - `accept_peer` keeps serving and returns false only for `EBADF`, `ENOTSOCK` or `EINVAL` (the
      listener is gone);
    - it logs the errno with `log_error`, which reaches the unified log; `perror` goes to /dev/null;
    - it backs off on a repeating error (C3-skeptic-code missed risk 4: an error before the dequeue
      can busy-spin).
  - The `loop-utils.c` hunk of upstream `f3fdc21850` (+4/-2).
  - `scripts/kitty-build-swap.sh` (header `:1-30`) gains a build variant that carries this patch
    and the upstream-defects patch **without** the title band. Today one bundle couples them, so a
    no on the band would also drop P2 (C3-skeptic-risk second pass, claim 6).
- **Tests.** A `tests/kitty-build-swap.bats` case: the `--no-band` stage lists exactly the expected
  patches. A source check: the patched `child-monitor.c` contains no `goto end` reachable from an
  `accept_peer` false return, except for the three listener errnos.
- **Verify.** `git -C ~/ktb apply --check <repo>/docs/patches/kitty-talk-thread-survives-v0.48.2.patch && echo APPLIES`.
  Then build the stage with the swap script's existing build verb, and confirm that `strings` of the
  built `fast_data_types.so` shows `still serving`.
- **Risk.** A fourth local patch on 0.48.2. Adoption is the operator's (see operator steps) and
  rides a restart that is happening anyway, never H1's first rehearsal.
- **Size.** About 40 patch lines plus 60 script lines.

## P3a: boot-resume event mode, heartbeat, roster, retire, ledger, capacity

- **Goal.** One script path restores a fleet after a reboot, a planned restart or a crash, from the
  freshest roster. It brings nothing back that ended on purpose, never launches a session twice, and
  waits for capacity instead of shedding.
- **Changes**, all in `scripts/boot-resume.sh` unless marked:
  1. **`--event <epoch> --kind restart|crash [--kitty-pid K] [--roster-dir D] [--plan-only]`.**
     - Parse it before `BOOT` is read (`:219`).
     - In event mode `BOOT` is the event epoch, and `MARKER` becomes
       `$STATE_DIR/events/<K-or-epoch>.done`. `last-boot-epoch` (`:222`, `:441`) is never touched, so
       the per-boot idempotency check at `:239-243` is unchanged.
     - `--plan-only` prints the roster, the retire and ledger decisions and the rows the layout would
       get, then exits 0 without launching anything.
  2. **The `.start` fix, both ends together.**
     - `scripts/alarm-reboot-prep.sh:52` writes the kalloc figure to `reboot-$DAY.kalloc`.
     - `boot-resume.sh:300` reads only the first field of the first line.
     - `tests/alarm-reboot-prep.bats:27` and one paired case run the two scripts together.
  3. **Heartbeat** (new `scripts/lib/restore-heartbeat.sh`, called as step 0 of every 300 s tick,
     before the per-boot early exit at `:239`). Each file is written to a temp name and moved into
     place:
     - `~/.claude/autonomy/heartbeat/hb.roster.json` from `cc-sessions --json`;
     - `hb.start`;
     - `hb.argv.tsv` (pid → `--model`, `--effort`, from `ps -o args=`);
     - `hb.layout.tsv` (sid → OS-window index and position in its tab), from **one** bounded
       `kitten @ ls` (`timeout 5`). If that call fails, the last good layout file is kept.
     - **Freeze for one tick only.** If the row count fell by more than 2, keep the previous roster
       for a single tick (C2-skeptic-code #5; C2-skeptic-risk #5).
  4. **Roster choice.** Take the newest by `.start` among the event snapshot, the heartbeat and the
     alarm roster, and union it with the tombstones whose `kitty_pid` matches (`:296-339`). Relax
     `st < BOOT` at `:302` to `st <= BOOT`, so a heartbeat whose start equals the crash anchor is not
     dropped (C2-skeptic-code second pass #4).
  5. **Retire filter.** Keep main's rule (`:374-438`: `terminal|successor` retire; `recycle` does
     not). Add one thing: when a `recycle` marker's successor is found in
     `~/.claude/logs/handoffs.jsonl` (`recycle-engaged`) and is in the roster or has a transcript
     newer than the marker, drop the old sid. That stops the 3a06361f duplicate case without
     overruling main.
  6. **Launched-once ledger.** `$STATE_DIR/events/<id>/launched`, one sid per map line. A later
     round never relaunches a listed sid. Before each launch, re-check `lr_holder_count` for that row.
  7. **Account headroom.** Read `claude-accounts --json` (or its cache) once. A row on an account at
     its weekly limit is still resumed, but it is flagged so P4 never nudges it. 27 of 32 roster
     sessions sat on two exhausted accounts on 10-01 (C2-skeptic-risk second pass #1).
  8. **Restore capacity mode** (event mode, or reboot with `restore-v2`):
     - export `CC_ADMIT_LOAD_TERM=off` for the layout, a term switch per C18
       (`scripts/lib/capacity-admit.sh:156`, `:1250`);
     - a start gate: wait until load1 divided by the core count is at most
       `CC_RESTORE_START_LOAD` (default 6), for up to 10 min, logging load every 10 s to
       `$STATE_DIR/events/<id>/load.log`, so the login boot-storm value gets measured (judge open
       question 4);
     - mark the event done only at shed=0 or after the deadline; one page per event, not per round.
  9. **Open kitty by path.** Replace `"$OPEN_BIN" -a kitty` (`:582`) with
     `"$OPEN_BIN" -n -a /Applications/kitty.app`. The staged sandbox shares the bundle id
     (C2 §2.1).
  10. **Write the contract columns 6-10** into `ADMITTED` (`:534-548`). Model and effort come from
      `hb.argv.tsv`; with no argv, the defaults stay and the page says so.
- **Tests:**
  - `tests/boot-resume.bats`:
    - event mode never writes `last-boot-epoch`;
    - `--plan-only` launches nothing;
    - the ledger blocks a second launch;
    - roster choice picks the newest of three fixtures;
    - the one-tick freeze;
    - the load-term-off export.
  - `tests/boot-resume-skip-retired.bats`: recycle-with-live-successor is dropped; recycle with no
    successor is kept (main's mutant pin "recycle counts as retirement: not ok 8" still holds for
    the no-successor case).
  - `tests/alarm-reboot-prep.bats`: the `.start` pair.
  - New `tests/restore-heartbeat.bats`. Run it under `/bin/bash` 3.2: launchd uses it (lesson "the
    deployment interpreter is not the one on your PATH").
- **Verify.** `bats tests/boot-resume.bats tests/boot-resume-skip-retired.bats tests/alarm-reboot-prep.bats tests/restore-heartbeat.bats`
  prints its plan line and no `not ok`. Then
  `bash scripts/boot-resume.sh --event "$(date +%s)" --kind restart --roster-dir ~/.claude/autonomy/heartbeat --plan-only`
  prints today's live fleet with zero launches.
- **Risk.** The largest phase, and it touches the launchd path. Everything new except the `.start`
  pair and open-by-path sits behind event mode or `restore-v2`.
- **Size.** About 450 LOC plus 300 bats lines. If the brief passes 150 lines, split it: P3a-i covers
  items 1-4 and 9; P3a-ii covers items 5-8 and 10.

## P3b: layout restore mode, one row per window, fullscreen by id

- **Goal.** Every admitted row is launched, paced, with none shed early. Each kitty OS window holds
  one row of panes and is restored to its old group, and fullscreen is done with kitty's own action.
- **Changes**, all in `bin/cc-resume-layout.sh`:
  1. **`--restore`: wait and retry instead of shedding.**
     - Replace the shed at `:249-252`: a refusal sleeps `CC_RESTORE_WAIT` (30 s) and re-asks for the
       same row, up to `CC_RESTORE_DEADLINE` (30 min), and only then sheds the rest.
     - A launch that failed or timed out at `:268-270` is printed as `maybe sid=…` and re-checked
       after a 20 s settle against the live registry, not counted as `failed`
       (C4-skeptic-risk #3).
  2. **One row per window** (lead finding 2):
     - drop the 2x2 rotate (`:244`, `:276-279`);
     - every pane after the head is `--location=vsplit` next to the previous pane;
     - after `close_window` (`:232-237`), run `k goto-layout --match id:<tab> horizontal`, then
       `layout_action equalize`;
     - raise the `PER_WINDOW` cap from 4 to 6 (`:162`), the operator's 3-6 panes per window.
     - Fix the comments at `:41-46` and in `boot-resume.sh:567-569`, which still say 2x2.
  3. **Group by heartbeat.** When columns 8-9 are present, the planner (`:193-227`) keeps each group
     in its own window, in slot order. Otherwise it falls back to today's project grouping.
  4. **Fullscreen by id** (J2):
     - delete `fs_osa` (`:177-190`) and the marker-title loop (`:290-311`);
     - after all launches, for each window head run
       `k action --match "id:<head>" toggle_fullscreen`, then sleep 3 s, because back-to-back
       toggles are dropped;
     - count `fullscreen_ok` by rc; never re-toggle; a non-zero rc goes into the summary for the page.
  5. **Map lines and the model/effort pass-through.** Emit the map line per launch (row contract).
     Build the launch command (`:257-258`) as
     `env CC_ADMIT_DONE=1 [CC_RESUME_MODEL=<m>] reso-resume-one acct wt sid br [--effort <e>] [--prompt-file <f>]`.
  6. **Focus.** Add `--keep-focus` to each launch, so a restore does not pull focus 32 times
     (C2-skeptic-risk second pass #8).
- **Tests.** `tests/cc-resume-layout-desktops.bats`:
  - a refused admit waits and retries the same row (stub admit refuses twice, then admits);
  - shed happens only at the deadline;
  - a timed-out launch is `maybe`, not `failed`;
  - one-row plan for 5 rows: one head plus 4 vsplits, no `rotate`;
  - `goto-layout horizontal` is sent once per window;
  - groups from columns 8-9 are kept;
  - `toggle_fullscreen` is sent once per window and never twice;
  - map lines appear;
  - a 5-column row behaves as today.

  `tests/kitty-recovery-launch.bats` (the shell root that survives) must stay green.
- **Verify.** `bats tests/cc-resume-layout-desktops.bats tests/kitty-recovery-launch.bats` prints
  its plan line and no `not ok`. Then a printf of five rows (with tab separators) piped to
  `bin/cc-resume-layout.sh --desktops --restore --dry-run` prints one window, one head plus four
  vsplits, and no rotate.
- **Risk.** The layout is live for every reboot. Keep it behind `--restore`, which only event mode
  and a `restore-v2` reboot pass, until P5 flips the flag.
- **Size.** About 250 LOC changed plus 250 bats lines.

## P4: recovery delivery: an inbox note for every session, a launch nudge only with evidence

- **Goal.** Every restored session learns what died, at no cost in turns. Only sessions with real
  open work and quota get a turn, and that turn arrives as a launch argument, not as typing. On
  10-01, 30 of 31 typed prompts did not submit; a later bare-CR pass submitted 28 of them and cost
  6.8M tokens, mostly for "nothing pending".
- **Pilot gate, first task of the phase.** In a private tmux server (`tmux -L sd-pilot-<tag>`, never
  kitty), on one account with quota and a small model:
  1. create a throwaway session with `claude -p` in a `mktemp -d` cwd;
  2. resume it with `CLAUDE_CODE_RESUME_THRESHOLD_MINUTES=525600 claude --resume <sid> "reply PONG-<nonce>"`;
  3. pass if the transcript gains exactly one user record with the nonce and one non-error assistant
     record within 60 s;
  4. clean up: `claude stop`/`rm` nothing else, kill the private server, and delete the throwaway
     registry row and tombstone it created. Unset the `KITTY_*` variables so the pilot never claims
     a pane.

  If the pilot fails, tier 2 below ships as the expect arm reading **only its own buffer** (no
  `get-text`), with transcript confirmation (C4-skeptic-risk #2).
- **Changes:**
  1. **`bin/cc-resume-classify.py`: `WAKE-LOST`.**
     - The verdict means: the transcript tail is a completed turn, but before the anchor the session
       had launched a Workflow, a Monitor or a background Agent with no matching
       `<task-notification>` and no `TaskStop`, or a workflow journal under
       `<cfg>/projects/<slug>/<sid>/` changed within 15 min of the anchor (C2 §2.7).
     - Background shells alone do not qualify: Claude Code already reports them on resume.
     - New `--lost-json PATH` lists each session's lost items. The TSV contract does not change; the
       verdict stays `$NF`.
     - Extend `--selftest` (`:356-404`) with a fixture built from the 10-01 transcripts.
  2. **New `scripts/lib/restore-note.sh`.** For every restored sid, before its launch, it runs
     `cc-notify --mailbox-only <sid> "[restore] kitty was {restarted|lost in a crash}{; the Mac rebooted} at HH:MM. This session was resumed in full. These died with the old process: <lost items>. If any of them still matters, re-run it from disk state; otherwise carry on."`
     `hooks/mailbox-drain.sh session-start` delivers it as context at resume, since that hook runs
     with no matcher.
  3. **`bin/reso-resume-one --prompt-file F`.** Parse it next to `--effort` (`:71`). When given,
     append the prompt as the positional argument after `--resume $sid` on the single spawn line
     (`:560`), so the two paths cannot drift. Confirmation is a non-error assistant record after the
     nonce, logged to the event dir.
  4. **`boot-resume.sh` step 4** (keepalive, `:615-645`). In event mode or under `restore-v2`, do not
     start the keepalive. Instead:
     - write a note for every row;
     - write a prompt file only for `INTERRUPTED` or `WAKE-LOST` rows on accounts with headroom (P3a
       item 7), as contract column 10;
     - prompt text: C2 §2.7's, minus the "/limit-recover" order for `WAKE-LOST` rows, which instead
       name the lost items.

     Outside both modes the keepalive stays as today.
  5. **Fallback for a prompt that did not confirm within 90 s.** Since 15:59 an agent may type into
     local panes (`settings.json:1357`), so the restore may submit through
     `it2_paste_submit_verified` (`scripts/handoff-fire.sh:4180`). Each Enter counts only when a
     re-read of the composer by `get-text` shows it empty afterwards (lead finding 1). Never send a
     blind CR, and never treat rc 0 as submitted.
- **Tests:**
  - `cc-resume-classify.py --selftest` passes the 10-01 fixture.
  - `tests/reso-resume-one.bats`: `--prompt-file` puts the prompt after `--resume <sid>` on the one
    spawn line; with no file the spawn line is byte-identical to today's.
  - New `tests/restore-note.bats`:
    - one note per sid;
    - a line appended before a simulated SessionStart is drained by `mailbox-drain.sh session-start`
      (judge open question 2);
    - no prompt file for an at-rest row or an exhausted account.
  - `tests/boot-resume.bats`: event mode starts no keepalive.
- **Verify.** Print the pilot's result line (nonce: user 1, assistant ≥1). Then
  `python3 bin/cc-resume-classify.py --selftest` prints `N/N passed`, and
  `bats tests/reso-resume-one.bats tests/restore-note.bats tests/boot-resume.bats` prints its plan
  line and no `not ok`.
- **Risk:**
  - A wrong `WAKE-LOST` call wakes a parked session. Mitigations: direct evidence only, never
    transcript age; an off switch `CC_RESTORE_NUDGE=off`; and the note tier covers every session
    anyway.
  - The operator's 08-24 ruling (`cc-resume-classify.py:12-25`) forbids re-pinging at-rest sessions.
    `WAKE-LOST` nudges only sessions with open work, which is what the plan's frozen scope asks for.
- **Size.** About 300 LOC plus 250 bats lines.

## P5: `cc-restore` and the crash and deaf pages, then flip `restore-v2`

- **Goal.** One operator command for a planned or deaf-kitty restart. A crash becomes a page that
  carries the one command. The reboot path switches to v2.
- **Changes:**
  1. **New `bin/cc-restore`**, in Python so cc-reaper leaves it alone. It ports the preserved
     `kitty-restart-resume.py` without its hardcoded pid and paths (`:24`; supervisor `:26-28`).
     - `--restart-kitty --confirm <kitty-pid>`:
       - refuses unless `<kitty-pid>` is the main kitty `ps` shows (no `--instance-group`) and
         `BATS_TEST_FILENAME` is unset;
       - takes the restore lock and the `events/<pid>.inprogress` claim (P2);
       - snapshots the heartbeat into `events/<epoch>/`;
       - waits for in-flight lands for at most `--land-wait` (default 10 min, `--no-wait` to skip);
       - sends SIGTERM, waits 3 s, then sends SIGKILL (signals are dropped on today's 0.48.2;
         C3-skeptic-code second pass);
       - runs `open -n -a /Applications/kitty.app`, waits up to 60 s for the new socket, then runs
         `boot-resume.sh --event <epoch> --kind restart --kitty-pid <pid> --roster-dir events/<epoch>`.
     - `--after-crash`: no kill. Relaunch kitty if none answers, then the same event restore with
       `--kind crash`.
     - `--abort`: stops a running restore and releases the lock.
     - `--dry-run`: prints every step and signals nothing.
  2. **Crash page** (`boot-resume.sh` step 0, after the heartbeat). When the main kitty pid recorded
     in the last heartbeat is gone and no `events/<pid>.done` exists:
     - file **one** `cc-backlog needs "kitty is gone; restore the fleet" --run "cc-restore --after-crash"`
       per pid;
     - **never relaunch on its own.** A deliberate ⌘Q cannot be told apart from a crash
       (C2-skeptic-risk fatal finding), and a crash cluster would loop (C4-skeptic-risk fatal
       finding).
  3. **Deaf page.**
     - Reuse `hf_kitty_queue_depth` (`scripts/handoff-fire.sh:1404`) and its full-queue threshold
       (`CC_KITTY_WEDGED_QUEUE_N`, 128). Do not add a second detector (C3-skeptic-risk M1).
     - Gate it on `sample <pid> 1` showing no `KittyPeerMon` thread.
     - The page says remote control is dead and the sessions are still working, and carries
       `cc-restore --restart-kitty --confirm <pid>`. It never prescribes an immediate restart while
       load per core is above the restore start gate.
  4. **Flip the flag.** After its own verification passes, P5 runs
     `touch ~/.claude/autonomy/boot-resume/restore-v2` and names that in its completion ping.
- **Tests.** New `tests/cc-restore.bats`, which stubs `ps`, `kill`, `open` and boot-resume, never
  the real ones:
  - refuses without `--confirm`, with a wrong pid, and under bats;
  - takes the lock before any signal;
  - `--dry-run` signals nothing;
  - `--abort` releases the lock.

  `tests/boot-resume.bats`: the crash page files once per pid and launches nothing; the deaf page
  fires only with the `sample` gate.
- **Verify.** `bats tests/cc-restore.bats tests/boot-resume.bats` prints its plan line and no
  `not ok`. Then `bin/cc-restore --restart-kitty --confirm "$(pgrep -nx kitty)" --dry-run` prints the
  plan (pid, roster count, ledger path, the commands it would run) and exits 0.
  `ls ~/.claude/autonomy/boot-resume/restore-v2` shows the flag.
- **Risk.** No full rehearsal is possible without ending the fleet, so G1 below is the rehearsal.
  Run it with nothing else changed.
- **Size.** About 350 LOC plus 200 bats lines.

## G1: the first planned restart (the rehearsal)

The operator runs `cc-restore --restart-kitty --confirm <pid>` once, when convenient, with nothing
else changed: no P6 build, no `NSAppSleepDisabled`. Pass criteria:
- every roster session not retired is live in the new kitty (`cc-sessions --json` count);
- 0 duplicates (no sid with two live holders);
- each window holds one row and sits in its old group;
- `events/<epoch>/` holds the ledger, the map lines and the load log.

A session reads these back and writes the result into this file.

## Operator-only steps (not agent work)

1. **Run G1**, the first planned restart, when convenient. The command is
   `cc-restore --restart-kitty --confirm <pid>`; the deaf page prints it with the pid filled in. It
   ends and restores every session.
2. **Adopt the P6 kitty build** at the **second** planned restart, via `scripts/kitty-build-swap.sh`'s
   `swap` verb. It is a no-band variant, so it is a separate decision from the title band. Rollback
   is the inverse swap at another restart.
3. **Optional:** `defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES` (C3 P3). It takes
   effect at the next kitty launch. Do it at the same restart as step 2, never at G1.
4. **File an upstream kitty issue** for the talk-thread exit, an outbound step. No upstream issue
   covers it (C3 §1.4).

## Not in W3: gate for a session layer (H2)

Decide on H2 only after:
1. G1 has passed;
2. a one-session pilot of a real Claude inside a private `tmux -L ccp-pilot` host, run on all four
   accounts, has checked:
   - Shift+Enter (with the kitty `map` and a `SetUserVar` on the pane);
   - the wheel and scrollback;
   - a notification posted from launchd's `Background` session;
   - the replacement for the ancestry oracle;
3. the operator has ruled on scrollback.

If H2 goes ahead it ships as one cutover behind a kill switch, never phased (C1-skeptic-risk).
Re-check C5 (Claude Code's background daemon) on each Claude Code release. It is a candidate again
only if `claude stop` becomes durable and a deliberate close can be told apart from a terminal death.
