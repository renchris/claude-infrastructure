---
status: in-progress
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

## Amendment 2026-10-04: reconciliation and the resume-in-place bar

> **Why this section exists.** The operator's bar is now "resume in place, as if nothing had interrupted", and that includes a hard restart of the Mac. This section does three things. It checks the plan against origin/main `a652077cc` (2026-10-04). It adds the gaps between the plan and that bar. It folds in the critic's review. Where this section conflicts with anything above, this section wins. Line numbers are on `a652077cc`. Every phase still re-greps its anchors before it lands.

### A. Where each phase stands

| Phase | State now | Evidence sha | Residual scope |
|---|---|---|---|
| P1 recycle fork | **Superseded.** Its default (hold background work) and its rule against `claude stop` (:89-98) reverse operator decision 75ea14d27d0f, "stop the copy at once, keep its tasks". Do not build it and do not rebase `w3-p1`. | `5cd333f16` on main implements the ruling. `fdcf221e3` is on branch `w3-p1`, is not on main, and is 154 commits behind (measured: `git merge-base --is-ancestor`, `git rev-list --count`). | Becomes **P1b** (§D). In resume mode the stop is skipped (`scripts/handoff-fire.sh:9459`). Live log since the stop landed: 34 `recycle-bgwork-answered` rows and 0 `recycle-bgcopy-stop` rows (measured: `grep -c ~/.claude/logs/handoffs.jsonl`). P1's Verify metric (:107-108) is void. |
| P2 safety rails | **Partly built, uncommitted.** Nothing is on main. | None on main. The work in progress is in `/Users/chrisren/Development/.worktrees/w3-p2` (branch `w3-p2` at `d8caa076e`): 4 files, +65/-2, last edited 10-02 (measured: `git diff --stat`, `stat`). | Rebase that work. Its whitelist line conflicts with `21f7e515d` at `bin/cc-reaper:716`, and its layout hunk predates `fbbf04784`. Not started: the launch fence in `reso-resume-one`, `scripts/lib/restore-lock.sh`, and their bats. Amended in §C. |
| P6 kitty patch | **Built, not landed.** | `716322ed5` on `w3-p6`; `git merge-tree` against main is clean (measured). The patch applies to `~/ktb` (measured: `apply --check`). `~/ktb-noband/kitty.app` contains `still serving`; `/Applications/kitty.app.staged` is still the 09-30 band build (measured: `strings \| grep -c`). | Land the branch, run its bats on main, then `stage --no-band`. Upstream v0.49.2 and master still end the talk thread on any `accept()` error (checked 10-04 with `gh api` and the raw `child-monitor.c`), so P6 is still needed. |
| P3a boot-resume event mode | Not started. | None. `1965c7e6d` added `same_boot()` and the `last-boot-uuid` marker, which the plan does not handle, and moved anchors by +16 to +38 lines. | All 10 items, split into P3a-i and P3a-ii (§D). |
| P3b layout restore mode | Not started. | None. Related commits: `bf55a8fc6` (the horizontal layout is enabled; prerequisite met), `a1e4490ae` (`layout_action equalize` does nothing in a horizontal tab and rings the bell), `fbbf04784` (+2 lines). | All six items, amended in §D. |
| P4 recovery delivery | Not started. | None. Reusable on main: `cc-notify --mailbox-only`, `bin/cc-wake` (`a86efec80`), and the kitty-epoch box seal (`9cf121e54`). | All items, plus gaps 7, 9, 10, 12, 13, 15, 18 and 19. |
| P5 `cc-restore` | Not started. | None. Since `49d153596`, `cc-backlog needs` requires `--class`. | All items. P5 no longer creates `restore-v2` (§C, item 3). |

The phase table near the top of this file is superseded by §D.

### B. Gaps against the bar that no phase covered

**Heartbeat files (P3a-i).** All are written atomically (temp file, then `mv`) into `~/.claude/autonomy/heartbeat/<bootuuid>/<kitty-pid>/`:
- `hb.roster.json`
- `hb.start`
- `hb.session.tsv`: sid → account (newest transcript), model, effort, permission mode, branch
- `hb.kitty-ls.json`: the whole tree from one bounded `kitten @ ls`
- `hb.bg.tsv`: for each claude pid, the argv of its non-MCP children, live `.watching` pids, agent-browser sessions and listening ports
- `hb.roles.tsv`: role → sid

| # | Lost today | Sev | Phase | File-level scope |
|---|---|---|---|---|
| 1 | **Which sessions come back after a hard power-off.** The alarm roster cannot be read (`.start` bug, `boot-resume.sh:333`). Tombstones need SessionEnd, which a power-off never runs. The registry fallback caps at 4 sessions (`:137-138`), so at most 4 of 18 live sessions return (measured). | high | P3a-i | `scripts/boot-resume.sh`, `scripts/alarm-reboot-prep.sh:52`, new `scripts/lib/restore-heartbeat.sh`. Heartbeat, `.start` pair, newest-roster choice, and registry rows whose `startedAt` is after `hb.start` all land in **one commit**, live without the flag (§C, item 3). |
| 2 | **Split tree, tab index, windows with more than 6 panes, non-Claude panes.** Live now: 5 windows holding 6/4/4/3/2 panes, one of them not Claude (measured: `kitten @ ls`). | medium | captured by P3a-i; replayed by **P7** | `bin/cc-resume-layout.sh`: replay each tab's `layout_state` pairs (orientation and bias) and its tab index from `hb.kitty-ls.json`. Reopen non-Claude panes as shells in their cwd. One row per window becomes the fallback, used only when no tree was recorded. |
| 3 | **The display each window was on, and the order of the Spaces.** This Mac has 3 displays (measured). | medium | P7 | `restore-heartbeat.sh` writes `hb.displays.tsv`, mapping `platform_window_id` to a display with the Swift at `cc-resume-layout.sh:379-394`. On restore, move each window's head to its display (System Events, as at `:516-538`), then `toggle_fullscreen` in the recorded order. |
| 4 | **Proof that the full conversation came back.** | low | P3b | `cc-resume-layout.sh`: a `maybe` row counts as restored only once its transcript has gained a `SessionStart:resume` record. |
| 5 | **The account.** A stale roster puts a session back on an account it has left; exhausted accounts leave sessions idle. | medium | P3a-ii, **P8** | `boot-resume.sh`: take the account from the newest transcript (`transcript_mtime`, `:197-202`). `bin/cc-restore-rebind`: after `events/<id>.done`, hand exhausted-account rows that are INTERRUPTED or WAKE-LOST to `scripts/limit-recover/lr-fleet.sh --one <sid> --target auto --detach`. |
| 6 | **Model and effort changed mid-session.** | medium | P3a-i, P3a-ii | Read them from the last non-synthetic assistant record, using argv only as a fallback, and write them to columns 6-7. |
| 7 | **Permission mode.** Hard-coded to `auto` at `bin/reso-resume-one:560`. | medium | P3a-i, P3a-ii, P4 | Capture the last `permission-mode` entry and add contract column 11, `permission_mode`. P4 adds `--permission-mode` to `reso-resume-one` (falling back to `auto` only when the mode is unknown) and the pass-through at `cc-resume-layout.sh:257-258`. |
| 8 | **The branch of a worktree that was reaped.** | low | P3a-i, P3a-ii | Record `git -C <cwd> rev-parse --abbrev-ref HEAD` each tick and fill column 4 from it. |
| 9 | **A live `/goal` that never runs again.** 1 of 18 live sessions holds one (measured). | high | P4 | `bin/cc-resume-classify.py`: a last `goal_status` with `met:false` at the anchor counts as open work (the rule of `goal_live_for_sid`, near `scripts/handoff-fire.sh:7948`). Such a row gets the note, plus a nudge if its account has quota. |
| 10 | **Armed `cc-await-ping` watchers.** 13 live (measured: `ps`). | high | captured by P3a-i; P4 | Classifier: a watcher launch with no matching notification, or a `.watching` pid alive at the last tick, is WAKE-LOST evidence. The note says "re-arm cc-await-ping unless a /goal is live". |
| 11 | **Notify-back links, and the custody debts they discharge.** 2 rows have been open since 10-01 (measured). | high | **P8** | `bin/cc-restore-rebind`: from the map lines, write `<old pane key>.forward` → new address, using the existing writer in `hooks/lib/mailbox-pending.sh:570-617` (sourced, not edited). Bats: an open custody row is discharged after a forwarded DONE. |
| 12 | **Background Bash still running at the cut.** 2 ship-land and 2 bats live (measured). | high | captured by P3a-i; P4 | Reverses plan :329: background shells now count as WAKE-LOST evidence, because 7 of 10 sessions given the native notice never acted on it (C2-skeptic-code.md:32). A row with a ship-land gets "check `git ls-tree origin/main` before landing again". |
| 13 | **Monitors, subagents and workflow runs.** | medium | P4 | The note names each lost run id together with its `resumeFromRunId` call. |
| 14 | **The turn in progress.** | medium | P4 | As planned: a launch-argument prompt, and no keepalive. |
| 15 | **Agent Teams teammates.** | medium | P4 | The classifier reads the non-lead members of `~/.claude-*/teams/*/config.json` at the anchor. The note lists them and points to limit-recover's Teams respawn. |
| 16 | **`cc-roles` bindings** (desk, docs-lead, drain-lead, opus55-lead). | medium | captured by P3a-i; P8 | `cc-restore-rebind` runs `cc-roles claim <role> --pane <new> --force` for each role whose session was restored. |
| 17 | **Scrollback.** | low | not in W3 | H2 gate item 3 (operator ruling). |
| 18 | **agent-browser sessions.** | low | captured by P3a-i; P4 | The note names each session and its URL. |
| 19 | **Dev servers.** | low | captured by P3a-i; P4 | The note names the listening ports, found with `lsof -iTCP -sTCP:LISTEN` on the session's descendants. |
| 20 | **The kalloc and zombie record.** | medium | R0, P3a-i, P5 | R0 (§D). The `.kalloc` sibling file. `cc-restore` writes the kalloc reading and the zombie count into `events/<epoch>/`. |
| — | **Login tokens.** | — | none | They survive in the login keychain. |

### C. The critic's amendments

| # | Finding | Verdict | Folded into |
|---|---|---|---|
| 1 | Event mode exits as "already processed", because `same_boot()` checks `last-boot-uuid` first (`boot-resume.sh:258-276`). | Holds (re-read on main). | P3a-i: event mode bypasses `same_boot()`, uses its own `mark_processed`, and never writes `last-boot-epoch` or `last-boot-uuid`. Add a bats case where the overridden uuid equals the marker. |
| 2 | A single heartbeat file overwrites the pre-crash roster. | Holds. | P3a-i: heartbeat directories keyed `<bootuuid>/<kitty-pid>/`, never overwritten across either key, pruned after 7 days; the one-tick freeze is dropped. Roster = newest heartbeat plus registry rows started after it. P3a-ii: the retire filter adds the successor it finds. P5: when it detects a crash, it copies the last good heartbeat into `events/<pid>/`. |
| 3 | Changes that go live at once make today's path worse mid-build, and P5 turns the flag on before G1. | Mostly holds. | Drop `-n`: opening by path alone fixes the bundle-id problem. The `k()` bound is 15 s only under `--restore`; the default path gets 120 s. P5 does not create the flag (§E). The kalloc reboot comes first, as R0. **Not adopted:** keeping the `.start` pair behind the flag. It ships live in the same commit as the heartbeat and newest-roster choice, so a heartbeat at most 300 s old outranks the 24 h alarm roster. Without that, a reboot during the build restores at most 4 sessions (gap 1). |
| 4 | "Wait for capacity" does not wait: the budget admits on the 3rd refusal in a row (`capacity-admit.sh:1579`). | Holds (re-read on main). | P3b: re-ask with `_CC_ADMIT_PROBE=1`, which is not charged to the budget. Cap busy sessions with `CC_ADMIT_RESTORE_R`. Launch idle rows first, and rows with a prompt (column 10) last, once load per core is back under the gate. |
| 5 | Restore clients can push kitty past its 256 fd soft limit (C3-socket-robustness.md:19-24). | Partly holds. | P3b and P5: one `k` call in flight at a time, a 30 s backoff after a timeout, and stop the restore if kitty's fd count passes 180. The 8192 fd-limit watcher is not adopted at G1, which stays a single change; it rides the P6 adoption restart. |
| 6 | P2 adds a third per-session lock, keyed on reusable pids, that the reconciler cannot see. | Holds. | P2: `reso-resume-one` takes the existing reconciler fence instead of a new `resume-locks/` directory: `lr_recon_may_act <sid> reso-resume-one always` in `scripts/limit-recover/lr-recon-fence.sh`, which already keys holders on pid plus lstart. `restore-lock.sh` stamps the pid, lstart and boot uuid. |
| 7 | Sessions come back on the wrong account, and exhausted ones sit idle. | Holds. | Gap 5 (P3a-ii, P8). |
| 8 | Keychain stalls, and the launch skips `cc-close-attrib`. | Mostly holds. | P2: spawn through `bin/cc-close-attrib` with `CLAUDE_CODE_CERT_STORE=bundled` set explicitly, failing open as `lr-fire-resume.sh:747-762` does. P3b: re-check `maybe` rows by `lr_holder_count` for at least 240 s. Warming the token is not adopted until it is measured. |
| 9 | The no-band build breaks the swap script and the draggable titles. | Mostly superseded by `w3-p6`. That branch adds `build --no-band`, the `patched-noband` probe and a clean `~/ktb-noband` tree, and a no-band swap leaves the ⌘⇧B link alone. | P6: `kitty-build-swap.sh status` exits non-zero when the ⌘⇧B ON link points at the band config but the live bundle does not probe `patched` (the cask-upgrade case). P5's preflight runs that check and refuses on failure. |
| 10 | The bar needs items the plan defers: non-Claude panes, the operator's dragged layout, permission mode, a G1 that only counts sessions, and an untested detach. | Holds. | Gaps 2, 3 and 7. P5 adds `cc-restore --compare <event-dir>` and a bats case showing the restart runs in a new session (`start_new_session`, as `kitty-restart-resume.py:391` does). |

### D. Revised waves, ownership and goals

Every build phase runs as **S**: a dispatched session via `scripts/handoff-fire.sh`, in its own worktree, with `--notify-back` to the W3 lead.

| Wave | Phase | Locus | Owns while it runs | Waits for |
|---|---|---|---|---|
| R0 | kalloc reboot, restored by hand with `/resume-sessions` | operator | — | before W3.2 lands. kalloc 4.24 GB (measured by the gap pass, `zprint`); the 6 GB alarm is about 1.7-2.3 days away (critic's estimate) |
| W3.1 | P1b | S | `scripts/handoff-fire.sh`, `tests/handoff-recycle-bgcopy-stop.bats`, `docs/plans/kitty-deadlock-recovery-2026-10-01.md` (line 28 only) | nothing |
| W3.1 | P2 | S | `bin/cc-reaper`, `tests/cc-reaper.bats`, `bin/cc-resume-layout.sh`, `tests/cc-resume-layout-desktops.bats`, `bin/reso-resume-one`, `tests/reso-resume-one.bats`, new `scripts/lib/restore-lock.sh`, new `tests/restore-lock.bats` | nothing |
| W3.1 | P6 | S | `docs/patches/kitty-talk-thread-survives-v0.48.2.patch`, `scripts/kitty-build-swap.sh`, `tests/kitty-build-swap.bats` | nothing |
| W3.2 | P3a-i | S | `scripts/boot-resume.sh`, `tests/boot-resume.bats`, `scripts/alarm-reboot-prep.sh`, `tests/alarm-reboot-prep.bats`, new `scripts/lib/restore-heartbeat.sh`, new `tests/restore-heartbeat.bats` | P2 |
| W3.2 | P3b | S | `bin/cc-resume-layout.sh`, `tests/cc-resume-layout-desktops.bats` | P2 |
| W3.2 | P8 | S | new `bin/cc-restore-rebind`, new `tests/cc-restore-rebind.bats`, its fixtures | nothing (builds on the contract fixed here) |
| W3.2b | P3a-ii | S | `scripts/boot-resume.sh`, `tests/boot-resume.bats`, `tests/boot-resume-skip-retired.bats` | P3a-i |
| W3.3 | P4 | S | `bin/cc-resume-classify.py`, its fixtures, new `scripts/lib/restore-note.sh`, new `tests/restore-note.bats`, `bin/reso-resume-one`, `tests/reso-resume-one.bats`, `scripts/boot-resume.sh` (step 4), `tests/boot-resume.bats`, `bin/cc-resume-layout.sh` (`:257-258` only) | P3a-ii, P3b |
| W3.4 | P5 | S | new `bin/cc-restore`, new `tests/cc-restore.bats`, new `scripts/lib/kitty-queue.sh`, `scripts/handoff-fire.sh` (the source line only), `tests/handoff-recycle-kitty-precheck.bats`, `scripts/boot-resume.sh`, `tests/boot-resume.bats`, `install.sh` (link) | P4, P8 |
| W3.4 | P7 | S | `bin/cc-resume-layout.sh`, `tests/cc-resume-layout-desktops.bats`, `scripts/lib/restore-heartbeat.sh`, `tests/restore-heartbeat.bats` | P4, P3a-ii |
| G1 | first planned kitty restart (§E) | operator | — | P5, P7 |
| G2 | first planned Mac restart with `restore-v2` on | operator | — | G1 passed and flag on |
| — | adopt the P6 build, plus the fd-limit watcher | operator | — | a planned restart after G2 |

**Order of owners for shared files:**
- `handoff-fire.sh`: P1b, then P5.
- `reso-resume-one`: P2, then P4.
- `cc-resume-layout.sh`: P2, then P3b, then P4, then P7.
- `boot-resume.sh` and `tests/boot-resume.bats`: P3a-i, then P3a-ii, then P4, then P5.
- `restore-heartbeat.sh`: P3a-i, then P7.

**Row contract change.** Column 11 is `permission_mode`, padded with `$TSV_PAD` like columns 6-10. The map-line `verdict=` anchor is now `cc-resume-layout.sh:318`, and the pipe is `boot-resume.sh:616`.

**Scope changes per phase** (the original sections still apply wherever these lines are silent):
- **P1b.**
  - Let `rcy_bgcopy_stop` run when `RCY_RESUME_SID` is set (`:9459`). Take the pre-answer size on the source transcript before lr-transplant's fold-stub appends to it. Never stop a copy whose uuid equals the resumed sid.
  - Add `acct=`/`cfg=` to `recycle-bgwork-answered` (`:9467`) and to the not-found and failed lines of `rcy_bgcopy_stop` (`:5770`).
  - Live check: every `recycle-bgwork-answered` row is followed by a `recycle-bgcopy-stop` row for the same `watcher_pid` reading `stopped`.
  - Not here: `hf_recycle_standdown`, which needs an operator ruling first, and retiring the `w3-p1` branch, which is an operator git action.
- **P2.**
  - The W3 lead first asks session 2205cb66 (backlog b7ce699affec) to commit the `w3-p2` work. Its worktree `wt-b7ce699affec` is gone, so if there is no answer, P2 carries `git -C /Users/chrisren/Development/.worktrees/w3-p2 diff` over by hand.
  - Reaper: add `boot-resume|cc-restore` next to `reso-keepalive` at `bin/cc-reaper:716`.
  - `k()`: use the work-in-progress `kb()` wrapper, default 120 s.
  - `reso-resume-one`: take the fence (§C, item 6). When `lr_holder_count` (`lr-lib.sh:526`) is 1 or more, exit 5. Release the fence before `:749-751` and before `exec $SHELL` at `:753`, and add a trap for abnormal exit. Spawn through `cc-close-attrib` (§C, item 8).
  - `restore_refuse_under_bats` follows `handoff-fire.sh:686`.
- **P6.**
  - Rebase `716322ed5` and run its bats on main; `0e0bdae86` changed `KITTY_PID` inheritance.
  - Add the band-link check (§C, item 9).
  - After landing, run `scripts/kitty-build-swap.sh stage --no-band`.
  - Check with b7ce699affec first, to avoid a double land.
- **P3a-i.**
  - P3a items 1-4 and 9, with §C items 1 and 2 and the heartbeat files in §B.
  - Step 0 runs before `if same_boot` (`:269`). The reader at `:333` takes the first field of the first line. `-lt` becomes `-le` at `:335`. `:620` becomes `open -a /Applications/kitty.app`, with no `-n`. `--roster-dir` defaults to the newest heartbeat directory.
  - The bats suite runs under `/bin/bash` 3.2.
- **P3a-ii.** P3a items 5-8 and 10, behind `--event` or `restore-v2`.
  - `recycle-engaged` rows carry no successor sid, so derive the successor from the pane, the roster, or a transcript newer than the marker.
  - Take the account from the newest transcript.
  - Write columns 6-11 into `ADMITTED` (`:569-584`), and copy the map lines into `last-layout.map` and `events/<id>/`.
- **P3b.** Everything behind `--restore`.
  - Even out pane sizes with `reset_window_sizes` (`scripts/kitty-equalize.py`), never `layout_action equalize`.
  - Send `goto-layout` with `--match window_id:<head>`, because launch returns a window id, not a tab id.
  - Keep `fs_osa` and the marker loop for the default path.
  - Apply §C items 4, 5 and 8, and gap 4.
  - Pass columns 6-7 only. Columns 10-11 are P4's.
- **P8.**
  - New `bin/cc-restore-rebind <event-dir> [--dry-run]`, idempotent, logging each act to `<event-dir>/rebind.log`.
  - It covers gaps 5, 11 and 16. P5 wires it in to run after `events/<id>.done`.
- **P4.** As planned, plus:
  - the gaps assigned to it in §B;
  - notes go through `cc-notify --mailbox-only --no-wake`, because `f37f2be9a` now wakes idle panes by default;
  - the drain test runs under the `9cf121e54` seal;
  - the fallback tries `bin/cc-wake` before `it2_paste_submit_verified` (`handoff-fire.sh:4184`);
  - the typing ruling anchor is `~/.claude/settings.json:1328`, and step 4 is now at `boot-resume.sh:654-682`.
- **P5.** As planned, plus:
  - the crash page passes `--class needs-human` and shares its title with the stuck-kitty row at `handoff-fire.sh:13087-13091`, so one wedge files one row;
  - `hf_kitty_queue_depth` moves into `scripts/lib/kitty-queue.sh`, and `tests/handoff-recycle-kitty-precheck.bats:114` keeps working;
  - `--confirm` checks for the main kitty itself, never with `pgrep -nx`;
  - add `--compare` and the detach test;
  - add a `restore-v2.plan` mode: boot-resume runs v2 `--plan-only`, bypassing `same_boot()`, into `events/<id>/plan.txt`;
  - **P5 never creates `restore-v2`.**
- **P7.** Gaps 2 and 3, restore mode only, plus a new `--tree FILE` option.

**Goals.** Bats runs serially. A pass needs the `1..N` line, N `ok` lines and no `not ok`, because a plan line alone does not prove a run.

```
P1b: --goal 'P1b landed on origin/main — proven by the session running and printing bats tests/handoff-recycle-bgcopy-stop.bats tests/handoff-recycle-bgwork-dialog.bats tests/handoff-recycle-bg-session.bats (1..N, N ok, no not ok) and git merge-base --is-ancestor <land sha> origin/main && echo LANDED; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § Amendment 2026-10-04 P1b'
P2:  --goal 'P2 landed on origin/main — proven by the session running and printing bats tests/cc-reaper.bats tests/cc-resume-layout-desktops.bats tests/reso-resume-one.bats tests/restore-lock.bats (1..N, N ok, no not ok) and git ls-tree origin/main -- scripts/lib/restore-lock.sh tests/restore-lock.bats; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § P2 and § Amendment 2026-10-04 P2'
P6:  --goal 'P6 landed on origin/main — proven by the session running and printing bats tests/kitty-build-swap.bats (1..N, N ok, no not ok), git -C ~/ktb apply --check <repo>/docs/patches/kitty-talk-thread-survives-v0.48.2.patch && echo APPLIES, scripts/kitty-build-swap.sh status showing staged patched-noband, and git ls-tree origin/main -- docs/patches/kitty-talk-thread-survives-v0.48.2.patch; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § P6 and § Amendment 2026-10-04 P6'
P3a-i: --goal 'P3a-i landed on origin/main — proven by the session running and printing bats tests/boot-resume.bats tests/alarm-reboot-prep.bats tests/restore-heartbeat.bats (heartbeat suite under /bin/bash 3.2; 1..N, N ok, no not ok), then bash scripts/boot-resume.sh --event "$(date +%s)" --kind restart --plan-only listing the live fleet with 0 launches and shasum of last-boot-epoch and last-boot-uuid unchanged before and after, and git ls-tree origin/main -- scripts/lib/restore-heartbeat.sh; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § P3a and § Amendment 2026-10-04 P3a-i'
P3b: --goal 'P3b landed on origin/main — proven by the session running and printing bats tests/cc-resume-layout-desktops.bats tests/kitty-recovery-launch.bats (1..N, N ok, no not ok), then five tab-separated rows piped to bin/cc-resume-layout.sh --desktops --restore --dry-run printing one window, one head plus four vsplits, one goto-layout, no rotate and no layout_action equalize, and git merge-base --is-ancestor <land sha> origin/main && echo LANDED; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § P3b and § Amendment 2026-10-04 P3b'
P8:  --goal 'P8 landed on origin/main — proven by the session running and printing bats tests/cc-restore-rebind.bats (1..N, N ok, no not ok), bin/cc-restore-rebind --dry-run <fixture event dir> listing forwards, role claims and lr-fleet handoffs, and git ls-tree origin/main -- bin/cc-restore-rebind tests/cc-restore-rebind.bats; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § Amendment 2026-10-04 P8'
P3a-ii: --goal 'P3a-ii landed on origin/main — proven by the session running and printing bats tests/boot-resume.bats tests/boot-resume-skip-retired.bats (1..N, N ok, no not ok), then the --plan-only run printing 11 columns per row with the account taken from the newest transcript, and git merge-base --is-ancestor <land sha> origin/main && echo LANDED; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § P3a and § Amendment 2026-10-04 P3a-ii'
P4:  --goal 'P4 landed on origin/main — proven by the session running and printing the pilot line (nonce: user 1, assistant >=1), python3 bin/cc-resume-classify.py --selftest N/N passed, bats tests/reso-resume-one.bats tests/restore-note.bats tests/boot-resume.bats tests/cc-resume-layout-desktops.bats (1..N, N ok, no not ok) and git ls-tree origin/main -- scripts/lib/restore-note.sh tests/restore-note.bats; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § P4 and § Amendment 2026-10-04 P4'
P5:  --goal 'P5 landed on origin/main — proven by the session running and printing bats tests/cc-restore.bats tests/boot-resume.bats tests/handoff-recycle-kitty-precheck.bats (1..N, N ok, no not ok), bin/cc-restore --restart-kitty --dry-run printing the main kitty pid, roster count, ledger path and commands with exit 0, ls ~/.claude/autonomy/boot-resume/restore-v2 reporting no such file, and git ls-tree origin/main -- bin/cc-restore scripts/lib/kitty-queue.sh tests/cc-restore.bats; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § P5 and § Amendment 2026-10-04 P5'
P7:  --goal 'P7 landed on origin/main — proven by the session running and printing bats tests/cc-resume-layout-desktops.bats tests/restore-heartbeat.bats (1..N, N ok, no not ok), then bin/cc-resume-layout.sh --desktops --restore --dry-run --tree <newest hb.kitty-ls.json> printing the same window count, panes per window, split orientation and display as a live kitten @ ls, and git merge-base --is-ancestor <land sha> origin/main && echo LANDED; do not touch files owned by another open phase; brief at docs/research/session-durability-2026-10/W3-build-plan.md § Amendment 2026-10-04 P7'
```

### E. G1: first planned restart (operator runbook)

**Before you start (2 min).**
- Every row from P2 through P8 in §D has a landed sha.
- `ls ~/.claude/autonomy/boot-resume/restore-v2` reports no such file.
- Nothing else changes at G1: no P6 swap and no `NSAppSleepDisabled`. Kitty stays on stock 0.48.2. **Do not upgrade to 0.49.2.** The reconciliation found it fixes only the signal half: the talk thread still dies on any `accept()` error (v0.49.2 `child-monitor.c:1995-1999`, `:2260`; checked 2026-10-04). A cask upgrade also drops the local patches and leaves the ⌘⇧B link pointing at a build without the band.
- Preview, read-only: `~/.claude/bin/cc-restore --restart-kitty --dry-run`. It prints the main kitty pid, the N sessions it will restore, the windows it plans (panes, split and display for each), the sessions it will leave retired, and the ledger path. Check that N matches the panes you expect.

**Start: one command, run from Terminal.app** (not kitty, so you can watch it while kitty is down):

```
~/.claude/bin/cc-restore --restart-kitty --confirm <pid from the preview>
```

**What you will see:**
1. `lock taken event=<epoch>`, then `heartbeat copied`.
2. `waiting for K in-flight lands` (at most 10 min). Kitty has not been touched yet.
3. Every kitty window closes, then one new kitty opens. Its socket can take up to 60 s.
4. `load` lines every 10 s until load per core is under the gate.
5. Windows fill one at a time in their old splits, each on its old display. Each pane shows `claude --resume` with the full conversation. Idle sessions come first and sessions with open work come last. Focus does not jump.
6. Each window goes fullscreen, about 3 s apart.
7. Each session's first context is a `[restore] kitty was restarted at HH:MM …` note. Sessions with open work take one turn by themselves; sessions at rest stay quiet.
8. The last line is `cc-restore: verdict=RESTORED restored=N/N maybe=0 dup=0 shed=0 events=~/.claude/autonomy/boot-resume/events/<epoch>`. For 18 sessions, expect about 5-15 min (estimated: 12 s pacing per launch plus the 10 min ceiling on the load gate).

**How to abort:**
- Before kitty closes (steps 1-2): press Ctrl-C, or run `cc-restore --abort`. Nothing has been signalled.
- After kitty closes: `cc-restore --abort` stops new launches and releases the lock. Sessions already back stay as they are. Run `cc-restore --after-crash` later to bring back the rest; the ledger and the fence prevent duplicates.
- If `cc-restore` itself has died: run `open -a /Applications/kitty.app`, then `cc-restore --after-crash`. As a last resort, use `/resume-sessions`.

**Pass check.** Run `cc-restore --compare ~/.claude/autonomy/boot-resume/events/<epoch>`. It prints one line per session comparing before and after: account, model, effort, permission mode, window, position and display. It also prints the duplicate count and the rebind lines (forwards and roles). G1 passes when every line matches, `dup=0` and `maybe=0`. A session writes the result into this file. If anything differs, leave the flag off and send the compare output to the W3 lead.

**Then turn on the reboot path** (only after a pass):

```
touch ~/.claude/autonomy/boot-resume/restore-v2.plan && launchctl kickstart gui/$(id -u)/com.claude.boot-resume
```

Read `events/<id>/plan.txt`. If it lists the live fleet with the right layout, run `mv ~/.claude/autonomy/boot-resume/restore-v2.plan ~/.claude/autonomy/boot-resume/restore-v2`. Deleting that file turns the reboot path off again. G2, a planned Mac restart with the flag on, is the first test of the operator's literal case, and it uses the same `--compare`.

### F. Phase ledger (kept by the W3 lead)

This table replaces the phase table near the top of the file. Only the W3 lead edits it. A sha is recorded only after `git merge-base --is-ancestor <sha> origin/main` succeeds and `git ls-tree origin/main` shows the phase's files.

| Phase | Wave | State | Pane / branch | Landed sha |
|---|---|---|---|---|
| P1b | W3.1 | landed, content-verified | 250 / `w3-p1b` | `973ea82f4` |
| P2 | W3.1 | landed, content-verified | 251 / `w3-p2-land` | `f40fad0d1` (feat), tests `558191bc8` `583170c62` `1f44391ec` |
| P6 | W3.1 | landed, content-verified; no-band build staged at `/Applications/kitty.app.staged` (adopting it is the operator's) | 258 / `w3-p6-land` | `35979ed78` (patch, build --no-band), `e1bb2624c` (band-link check) |
| P8 | W3.2 (no dependency, fired early) | landed, content-verified | 261 / `w3-p8` | `4b8915441` (feat), tests `fd50f450b` `4bbbb0dc1` |
| P3a-i | W3.2 | landed, content-verified | 266 / `w3-p3a-i` | `bfdb948ef` |
| P3b | W3.2 | landed, content-verified | 267 / `w3-p3b` | `96a0591dc` (feat), `6b30ad551` (fix), tests `124f51717` `760e13771` |
| P3a-ii | W3.2b | landed, content-verified | 271 / `w3-p3a-ii` | `c483b8401` (feat), `6aa13bf1f` `3bfb4b9ad` `472ba14c4` (fixes) |
| P4 | W3.3 | landed, content-verified | 276 / `w3-p4` | `c410b5657` (classifier), `4f912ce85` (reso-resume-one), `f1dc36226` (boot-resume, restore-note) |
| P5 | W3.4 | fired 2026-10-05; its `/goal` arrived as pasted text and did not arm, so it runs on its brief and the custody hooks | 285 / `w3-p5` | |
| P7 | W3.4 | fired 2026-10-05 | 286 / `w3-p7` | |
| P4b | W3.4 (added by the lead) | fired 2026-10-05: a lost self-armed watcher alone no longer makes a row WAKE-LOST (§ G, P4) | 287 / `w3-p4b` | |

### G. Findings from the build (for later phases)

- **2026-10-04, P8. Notify-back forwards are silently not written under kitty.** `mailbox_write_forward` (`hooks/lib/mailbox-pending.sh`) refuses kitty's decimal pane keys, so `handoff-fire.sh`'s `write_forward_for` writes no forward under kitty today. `cc-restore-rebind` works around it by writing the same pointer through the lib's own validators (`writer=local` in `rebind.log`). Gap 11 is therefore only half closed until the lib accepts decimal keys.
- **2026-10-04, P8. A forward on a reused kitty window id can hijack mail.** kitty reuses window ids after a restart, so a forward on an old decimal key would capture mail meant for whichever new session gets that id. Rebind refuses keys that a restored window or another registry row holds, but a forward written now has no expiry. The fix is a drain-side clear in `mailbox-pending.sh` or `mailbox-drain`, which no W3 phase owns yet. P5 wires rebind into `cc-restore`, so it is the phase to carry it unless the lead assigns it elsewhere.
- **2026-10-04, P2. `reso-resume-one`'s fence waits up to `CC_RESUME_FENCE_WAIT_S`=20 s on a held lock**, because `boot-resume-launch` and `cc-resume-debt` hold it while opening the kitty window, and kitty does not pass their environment through.
- **2026-10-04, lead. Under memory pressure, ship-land reports a sentinel SIGKILL as a code RED (exit 6).** The compressor sentinel (`retrip-over-debt`) killed gate children for about an hour while fseventsd held a 61 GB footprint. Every land failed with "test-hermeticity RED" or "selftest FAILED", and none named a file. Check land output for `Killed: 9` before treating an exit 6 as a code failure.
- **2026-10-05, P3b. A `maybe` row confirmed by holder count and `SessionStart:resume` gets no map line**, because its window id is unknown. P4, P5, P7 and `cc-restore-rebind` must not assume one map line per restored sid. The layout's summary line now also carries `maybe=` and `stopped=`.
- **2026-10-05, P3b. `boot-resume.sh:567-569`'s comment still says 2x2**; whichever phase next owns `boot-resume.sh` (P4) corrects it.
- **2026-10-05, P3a-i. Event mode restores only from a heartbeat** (no heartbeat means exit 3, `no-heartbeat`). `--kind crash` picks the newest heartbeat whose kitty is dead, unless `--kitty-pid` or `--roster-dir` is given. On a new boot the tick runs after DETECT, because `cc-sessions` sweeps registry rows that have been dead for more than 24 h. P5's `cc-restore` builds on these rules.
- **2026-10-05, lead. The forward-expiry fix goes to P5, with two added files.** P5 also owns `hooks/lib/mailbox-pending.sh` and `hooks/mailbox-drain.sh` (and their bats) while it runs. It adds the drain-side clear first, then lets `mailbox_write_forward` accept kitty's decimal keys, which closes the other half of gap 11. No other open phase touches those files.
- **2026-10-05, P3a-ii. `tests/capacity-admit-coverage.bats` test 22 greps `boot-resume.sh` for the shed condition and its message on one line.** Splitting them turned P3a-ii's first land red (fixed in `3bfb4b9ad`). P4 and P5 edit `boot-resume.sh` next, so they keep each shed arm on one line.
- **2026-10-05, P3a-ii. `--kind restart` took its heartbeat tick after the caller's event epoch**, so `hb.start` was later than the event and a restart could not restore from its own snapshot (measured live: exit 3, `no-heartbeat`). Fixed in `472ba14c4`: the pick's upper bound is now the later of the event and the tick clock. P5's `cc-restore` passes `$(date +%s)` as the event and relies on this.
- **2026-10-05, P3a-ii. P8's fixture turned a trunk guard red.** `tests/fixtures/cc-restore-rebind/event/rows.tsv` holds raw 0x1f padding bytes on 5 lines, which fails `tests/tsv-field-collapse.bats` "no padding sentinel is ever left in a tracked source file as a raw byte". P8 has closed, so the lead assigns the fix to P5, which wires rebind in: P5 also owns `tests/fixtures/cc-restore-rebind/**` and `tests/cc-restore-rebind.bats`, and builds the padded rows at test setup with `$'\037'` instead of storing the raw byte. The other red in that file (the reader census in `bin/cc-dispatch`) is not W3's.
- **2026-10-05, P4. Pilot passed** (nonce `879eb69a`: user 1, assistant 2, in 6 s), so the nudge is a launch argument, not typing.
- **2026-10-05, P4. The typed-prompt fallback has no paste entry point.** `it2_paste_submit_verified` is reachable only inside `handoff-fire.sh`, so `restore-note.sh`'s paste arm abstains (`no-verified-paste-entry-point`); the `cc-wake` arm works. Assigned to P5, which owns `handoff-fire.sh` next: add `paste-verified <pane> <prompt-file>`, and `restore-note.sh` picks it up by itself.
- **2026-10-05, P4. Gap 10 narrowed.** A live `.watching` pid alone is not WAKE-LOST evidence, because `mailbox-wake-arm.sh` arms one at every SessionStart; it only confirms a watcher the session launched itself.
- **2026-10-05, P4 and lead. A self-armed watcher alone no longer earns a turn (P4b).** On the live fleet 10 of 18 sessions read WAKE-LOST, 8 of them only for their own `cc-await-ping`, which SessionStart re-arms without a turn. Lead's ruling (conviction above 90%, on P4's own goal that only real open work gets a turn): such a row keeps the watcher in its note and gets no nudge.
- **2026-10-05, P4.** A session cold by the clock but inside a long call is WAKE-LOST only when `hb.session.tsv` shows it alive with work open. `hb.bg.tsv` holds no agent-browser URL or owner sid, so the note takes the URL from the session's own transcript and names only sessions it can attribute.
