# (d) The "Background work is running" modal (pane 350) and the unsent `/exit` (pane 384)

Investigated 2026-10-18 13:10-13:25 CDT (18:10-18:25Z), read-only. Code at trunk b2a295c94.

## 1. Answer first

Both `/exit`s came from the same place. The **recycle watcher's 60 s nudge in handoff-fire.sh**
(`__recycle`, the `retype` arm at `scripts/handoff-fire.sh:11733-11746`) typed them. lr-upgrade,
lr-fire-resume and the move worker's own code typed nothing. The watcher is detached **before** the
foreground's pre-`/exit` gates run: the freshness re-read, the last read, and the load hold. Under
load 8-15/core those gates took 80-270 s. Since commit 1376807f4 (2026-10-14) the watcher's clock
counts wall seconds, so its 60 s checkpoint now fires inside that window. It reads an empty composer,
decides "typed-but-lost /exit, retype", and types the **first** `/exit` itself.

The foreground then holds on load. It SIGTERMs the watcher (`hf_recycle_disarm`) and reports
"nothing was typed, a retry is safe", which is false. Pane 350 got a submitted `/exit` that raised
the background-work modal, and the only process that answers that modal had just been killed. Pane
384 got an `/exit` that was typed but never submitted. Five batches later the move worker's
draft-carry saved that `/exit` as the operator's draft and typed it back into the successor on
next3.

**The fix:** the watcher must not type until the foreground has committed (a marker written just
before `/exit`). The foreground must not report "nothing typed" without reading the watcher's
journal. The carry and the planner must treat an exact `/exit` and the bg-work modal as rail
artefacts, not as a draft or "busy".

## 2. Evidence (MEASURED unless marked)

### Pane 350 (f06b5e9b, next, "Home folder dev cleanup treemap")
- Batch `move/20261018T143348Z-next-next3-33124/`, row disposition `move`. `f06b5e9b….events.jsonl`:
  `actuate` at 14:34:05Z, `actuated rc 6`, result `NOTMOVED: HELD:load — live in pane 350 … (lr-handoff rc 6)`.
- `f06b5e9b….handoff.log`: precheck `composer: empty` and `bg_work: watcher shipland=no pids=4168`.
  Then `recycle armed for 350: watcher pid 13148 … (log: …/T//handoff-recycle-350-1792334181-U2KomH.log)`.
  Then `!! recycle ABORTED before /exit (held: load): load 8.72/core … /exit NOT submitted, watcher
  disarmed`, and finally `nothing was typed, a retry is safe`.
- `f06b5e9b….watcher.json`: `armed_at 2026-10-18T14:36:33Z`. `~/.claude/logs/handoffs.jsonl`: `recycle-intent`
  14:36:21Z, `recycle-held-load` 14:37:52Z. **So the watcher was alive about 79 s, which covers the 60 s
  checkpoint.** The watcher log has only its 4 pane-probe lines. The `retype` and `cr` arms log
  nothing (`handoff-fire.sh:11731-11746`).
- Transcript `~/.claude-next/projects/-Users-chrisren-Development--worktrees-wt-cc-192325-42328/f06b5e9b….jsonl`:
  - 14:18:51Z: the session started `cc-await-ping --timeout 3300` as a background shell (task b0qrw6t9v).
  - 14:18:56Z: it reported "✅ Good to close: yes".
  - 15:13:51Z: the task's completion arrived only as a `queue-operation`, meaning it was queued.
    The 18:15Z screen showed "Background task update waiting while this panel is open". So the modal
    was already up before 15:13:51Z, which puts its opening between 14:18:56Z and 15:13:51Z. That
    brackets the 14:37:33Z nudge (INFERRED as the moment).
- Screen at 18:15:33Z (`kitten @ get-text --match id:350`): "Background work is running / shell ·
  …cc-await-ping --timeo… / ❯ 1. Exit and stop tasks 2. Move to background and exit 3. Stay".
- Three later batches never named the modal:
  - `20261018T153246Z…80099` and `…165110Z…66862` read the row as `wait:composer-unknown`. Each waited
    3600 s and ended `NOTMOVED still-busy:composer-unknown after 3600s; nothing touched`. Neither paged.
  - `…180746Z…6778` was still `waiting` when read.
  - Cause: `bin/cc-lr:1272` maps `composer-unknown` to `wait`, and `lr-upgrade.sh:1080` turns an
    unreadable `lru_composer` into `composer-unknown`. Neither calls `pane_bgwork_dialog`
    (`hooks/lib/pane-modal.sh:256`).
- **Live-state change:** at 18:18:49Z a sibling agent in this workflow (session 94747d64, in
  `~/.claude/logs/bash-commands.log`) ran `_pane_bgwork_index "Stay"` and then `kitten @ send-text
  --match id:350 -- "$i"`. The transcript records the `/exit` local command at 18:18:57Z, and the
  session took a turn at 18:19:11Z. Pane 350 is now live with an empty composer.

### Pane 384 (98e6f890, sevenrooms-bridge, now next3)
- Batch `move/20261018T070336Z-next-next3-37630/`, row `move`.
  - `98e6f890….handoff.log`: precheck `composer: empty`, `bg_work: none`. Then `recycle armed for
    384: watcher pid 25216`, then `!! recycle ABORTED before /exit (held: load): load 15.30/core`,
    then "nothing was typed".
  - handoffs.jsonl: intent 07:22:03Z, held-load 07:25:02Z. `watcher.json armed_at 07:22:45Z`. **The
    watcher was alive about 137 s: past the 60 s checkpoint, short of the 150 s one.**
- From the next batch (`20261018T083110Z`) through `…143348Z`, the 384 row reads `hold:draft` in
  `plan.json` (5 batches).
- `…153246Z`, `…164032Z`, `…164953Z`: `98e6f890….draft` contains `<epoch>\t/exit` (od -c), and
  events show `draft-carry "5 chars; the recycle saves and clears it and retypes it unsent in the
  successor"`.
- `…164953Z…26890` MOVED 384 at 16:51:51Z. Watcher log `handoff-recycle-384-1792342242-5zUnQ7.log`
  ends `→ carry: the unsent text from before the move is back in pane 384's box, unsent (copy in
  ~/.reso/limit-recover/drafts/98e6f890…/20261018T165042Z); 5 chars as read`. In that dir,
  `draft.txt` and `typeback.txt` both contain `/exit`. handoffs.jsonl has `recycle-composer-returned`
  at 16:51:54Z.
- **So the `/exit` in the successor's box was retyped by the draft-carry. Nothing sent Enter, by
  design.** The slash menu was open only because the composer began with `/`. No mover pressed
  Enter onto the menu.
- Live state: at 18:15:49Z the operator submitted a new message in 384 (transcript), so the `/exit`
  was cleared by hand (INFERRED). The composer reads empty now.

### The same race elsewhere (it also feeds symptom c, bare shells)
- Watcher log `handoff-recycle-22-1792308005-1PnSKI.log`: `bgwork@139s: the /exit raised the
  background-work dialog; stop-if-watcher answered '1'`. Then `pane 22 CONFIRMED at a shell prompt
  after 161s — typing relaunch`. The foreground held on load at 07:23:23Z, `unconfirm rc 2`, about
  20 s **after** the watcher's `/exit` had already exited claude.
- `handoff-recycle-332-1792308018-59eorR.log`: claude exited and the shell was confirmed at 125 s. The
  `disarm` line was typed at 07:24:22Z, then the foreground held on load at 07:24:33Z and killed the
  watcher before the `cmd` line. The batch reported `STRANDED 2e9ed9f2: no live process holds the
  session`.
- handoffs.jsonl, 2026-10-17/18: of 33 held/aborted recycles with an attempt id, **27 held 60 s or
  more after their intent row**. All are `recycle-held-load`, on panes 47, 20, 8, 24, 332, 1, 21,
  390, 393, 22, 23, 340, 242, 10, 246, 377, 384, 350. The method is jq/awk over the ts deltas, and
  intent precedes the watcher's arm by 10-40 s, so this is an upper bound on exposure.
- Sweep at about 18:22Z, `kitten @ get-text` on all 35 windows: none currently shows the bg-work
  modal or a `❯ /exit` composer.

## 3. Causal chain

```
cc-lr move --until-idle (operator / sessions 401, 344 …)
 └ lr-move-batch → lr-move-worker (swap slot) → lr-handoff → handoff-fire --recycle (foreground)
     1. precheck: composer empty, bg_work …                         [handoff.log]
     2. transplant + confirm; DETACH watcher __recycle              [handoff-fire.sh:19152]
        watcher: wall clock t0, nudge latches 60/150/300 s          [:11375-11407, 1376807f4]
     3. freshness re-read (:19209), recycle_fire_commit → last read (:18595)
        → load gate (:18601) … 80-270 s at 8-15 load/core
          ║ meanwhile, at watcher t=60 s: recycle_nudge_decision → composer "" → `retype`
          ║   types /exit, sleeps 1 s, reads back:                  [:11733-11746]
          ║   (a) read == "/exit" → CR → claude runs /exit
          ║        · bg shell running → MODAL; the watcher's bgwork arm answers it 15 s later …
          ║        · no bg shell → claude exits → watcher types relaunch …
          ║   (b) read != "/exit" (echo slower than 1 s under load) → no CR, NO undo, no log
     4. load > 8/core → hf_recycle_hold load → hf_recycle_disarm = kill WATCHER_PID   [:3341]
        prints "ABORTED before /exit … nothing was typed, a retry is safe"           [:3635]
Result:
 (a)+bg  → 350: modal up with nobody to answer it; planner sees composer-unknown and waits 3×3600 s
 (a)     → 332/22: claude gone, relaunch cut off mid-typing → bare shell (symptom c)
 (b)     → 384: `/exit` left in the box → 5 batches hold:draft → draft-carry saves "/exit"
           as a draft (composer-intent.sh:45-80 has no /exit class) → typed back unsent into
           the successor at 16:51:54Z, slash menu open
```

The mover did the following after each timeout:
- **350:** each batch ended `NOTMOVED … nothing touched`, with no page and no modal detection. The
  batch log just says `done`.
- **384:** five batches held on "draft" (no page), then the carry moved the residue forward.
- **Foreground:** told every caller "a retry is safe".
- **Nobody** cleared the box, answered the modal, or paged.

## 4. Immediate remediation (describe, do not do)

1. **Pane 350:** already answered "Stay" at 18:18:49Z, so the session is alive. Batch `…180746Z…6778`
   is still waiting to move it to next3. The session itself ran `cc-lr switch --target next4
   --dry-run` at 18:19:20Z. Pick one mover: either let the batch wait for idle, or `touch
   ~/.reso/limit-recover/move/20261018T180746Z-next-next3-6778/abort` if the operator now wants next4.
   Do not run both.
2. **Pane 384:** the composer is empty and the session is live on next3. Nothing to do.
3. **Hold loaded recycles:** until the code fix lands, run with `CC_RECYCLE_DRAFT_*` untouched and set
   `HF_RECYCLE_HOLD_LOAD_PER_CORE=off` only if you accept typed relaunches at high load. Better, avoid
   firing moves above 8/core (load was 17.5/core at 14:27Z per batch 132615Z). A cheaper interim
   guard is `CC_RECYCLE_VANISH_CHECK` untouched plus setting the watcher's first nudge later.
   Currently there is no env knob for `rcy_nudge_left`. **Code change needed.**
4. **Re-sweep for leftovers:**
   - Panes 47, 20, 8, 24, 1, 21, 390, 393, 23, 340, 242, 10, 246, 377: check each for a bare shell
     with an open resume debt (`cc-lr status <sid>`). A shell with an open debt gets `cc-lr recover
     <sid>`.
   - A composer reading exactly `/exit` gets one Ctrl-U with read-back (`cc_tui_clear`).
   - A bg-work modal gets "Stay" if the move is not wanted now, or "1 Exit and stop tasks" only when
     the sole job is `cc-await-ping` *and* a watcher is armed to relaunch.

## 5. Long-term fix

**F1. The watcher never types before the foreground commits.** `scripts/handoff-fire.sh`
- Just before `hf_exit_readback` / `hf_exit_signal` in `recycle_fire_commit` (around :18630, after
  the load gate and debt open), write `$RCY_RUN_DIR/exit-committed` (epoch). Write
  `$RCY_RUN_DIR/exit-aborted` inside `hf_recycle_hold` before `hf_recycle_disarm` (:3615).
- In the watcher's nudge (:11718), when `exit-committed` is absent, the decision is `precommit` (no
  keystroke, emit `recycle-nudge-precommit`). On `exit-aborted`, the watcher exits cleanly. The
  bgwork arm (:11409+) also requires `exit-committed`, or a `/exit` it can attribute to the
  foreground.
- Recommended: start the watcher's clock (`rcy_wait_t0`, :11375) at `exit-committed`, not at
  detach. Then 60/150/300 s mean "after our `/exit`", which is what the nudge doctrine
  (`:5385-5393`, "typed-but-lost /exit") assumes.

**F2. Disarm proves rather than assumes.** `hf_recycle_disarm` (:3341) must read the watcher log or
journal before claiming "nothing typed". If it shows `bgwork@` or `CONFIRMED at a shell` or a
`type-attempt`, the recycle has passed its point of no return. Do not kill the watcher or unconfirm
then. Let it finish, or page "recycle committed by the watcher during the hold".
`hf_recycle_hold` (:3626-3636) must word its claim from that read. The retype arm must log
(`emit_recycle_event recycle-nudge-retype`). On a read-back mismatch it sends the same five-DEL undo
or `composer_residue_record "$RSID" "/exit"` that `hf_exit_readback` (:3780-3790) already does.

**F3. Exit path, deterministic** (the brief's a/b/c):
- **(a)** Before `/exit`, stop or background the session's own bg tasks. Prefer `hf_exit_signal`
  (SIGTERM, :3795+), which skips the modal; today it runs only with a staged successor. Otherwise
  keep the watcher alive through the modal and answer it via `pane_bgwork_stop_choice` /
  `pane_bgwork_choice` (`hooks/lib/pane-modal.sh:268-276`).
- **(b)** Verify the exit by pid (`kill -0` on the row pid plus lstart) within N s.
- **(c)** On failure, if the screen shows the bg-work modal, press the "Stay" index. If the composer
  reads exactly `/exit`, send Ctrl-U and read back empty. This is `lru_exit_scrub` from
  `lr-upgrade.sh:2314-2323`, lifted into a shared lib. Then page with the pane, sid, and what was
  undone.

**F4. Do not carry or wait on rail artefacts.**
- `scripts/lib/composer-intent.sh:45-80`: add class `rail-exit` for an exact `/exit` (and
  `/exit<digit>`), so `lr-move-worker.sh:239-249` clears it with `cc_tui_clear` instead of carrying
  it (:254-256). handoff-fire's carry needs the same rule (the `rcy_carry` path that wrote
  `drafts/…/typeback.txt`).
- `lr-upgrade.sh:1080` / `bin/cc-lr:1272`: when `lru_composer` is unreadable, test
  `pane_bgwork_dialog` and emit `bg-work-dialog`, not `composer-unknown`. `bin/cc-lr` should map it
  to `hold:bg-work-dialog` with a page, never `wait`. A modal is not idleness that time will bring.
- `lr-move-worker.sh:143-162`: a wait loop that sees the same non-`move` disposition for its whole
  budget pages once at timeout instead of `finish NOTMOVED … nothing touched` silently.

**Tests that would have caught it**
- `tests/handoff-recycle-nudge-precommit.bats` (new):
  - Stub `composer_content` empty, stub `pane_cc_state` = `cc`, `HF_RECYCLE_SHELL_POLL_S=1`, and do
    not create `exit-committed`.
  - Run the watcher for 65 s of fake clock. Assert zero `session send` calls carrying `/exit`.
  - Create `exit-committed`, advance the clock, and assert exactly one retype.
- Update `tests/handoff-composer-gate.bats:250`. "empty composer → retype" is currently pinned
  unconditionally, so that test enshrined the bug.
- `tests/handoff-recycle-hold-after-watcher-commit.bats`: the watcher journal shows `CONFIRMED at a
  shell` and the load gate returns 1. Assert no SIGTERM to the watcher, no unconfirm, and no
  "nothing was typed".
- `tests/composer-intent.bats`: `composer_unintended_class "/exit"` gives `rail-exit`, rc 0.
- `tests/lr-rejected-source-moves.bats` (or new): a fixture screen from
  `tests/fixtures/lr-recon/screens/bgwork-dialog-2.1.284.txt` makes the census disposition
  `bg-work-dialog`, and the plan gives `hold`, not `wait`.

## 6. Confidence

- **82%**, MEASURED:
  - the watcher was alive past 60 s on both panes;
  - the foreground held before ever typing (its log says so, and `hf_exit_readback` is reached only
    after the load gate);
  - 384's successor `/exit` came from the draft-carry (`typeback.txt`);
  - panes 22 and 332 show the watcher acting during a foreground hold.
- INFERRED:
  - the exact moment and arm of the nudge (the retype arm logs nothing);
  - for 384, that the 1 s read-back missed the echo under 15/core.
- **Would raise it:** a `ps`/`bash-execution.log` line showing `it2 session send -s 350 /exit` from
  pid 13148 around 14:37:33Z, or a rig run of the watcher with an empty composer and no commit.
- **Would lower it:** evidence that the foreground typed `/exit` (an `exit:` line in handoff.log), or
  that an operator or agent typed into 350/384 between 14:36 and 15:13Z / 07:22 and 08:31Z (none
  found in bash-commands.log).

## Adversarial verification

Verified 2026-10-18 18:20-18:32Z, read-only (no keystrokes, no batch writes). **Verdict: NOT refuted.**
The root cause holds. While this check ran, the same race happened again on pane 350. That is
direct evidence, and it outweighs every inference above. Some citations, one metric and the
remediation need corrections.

### What I re-checked against the code (MEASURED, by `sed -n`/`grep -n` at b2a295c94)
- **Watcher detached before the gates.** `detach … __recycle` is at `scripts/handoff-fire.sh:19152`.
  The freshness re-read is at :19203-19225. `recycle_fire_commit` is called at :19309, and inside it
  the order is: transplant confirm, then the last read at :18594-18596, then the load hold at
  :18601-18604, then `hf_exit_signal` at :18629, then `hf_exit_readback` at :18646. Correct.
- **The watcher loop does not wait for the foreground.** It starts right after `pane_proof`
  (:11190), and `rcy_wait_t0` is set at :11375. Nothing in between waits for a commit.
- **The retype arm.** At :11733-11746 the arm types `/exit`, sleeps 1 s, reads the box back, and
  sends CR only on an exact `/exit`. It sends no undo, writes no residue receipt, and emits no
  event. The other two outcomes do log: `HELD` echoes and emits `recycle-nudge-held` (:11748-11749).
  So a missing HELD line means `cr` or `retype` ran.
- **Wall clock.** `git show 1376807f4` (2026-10-14) replaces `waited=$((waited+rcy_poll))` with
  `$(date +%s) - rcy_wait_t0`. Correct.
- **Line refs that are correct:** `hf_recycle_disarm` (:3340-3344, a bare `kill`); `bin/cc-lr:1272`;
  `lr-upgrade.sh:1080`; `pane-modal.sh:256/268/276`; `composer-intent.sh:45-80`, where a 5-char
  `/exit` falls past the stray rule into "draft"; `lr-move-worker.sh:143-162` and `:239-256`;
  `hf_exit_readback` (:3764-3792).

### Elimination: who else could have typed the /exit (MEASURED)
- **Pane 22.** The 150 s nudge logged `HELD (unknown)` at 161 s
  (`handoff-recycle-22-1792308005-1PnSKI.log`). The bgwork arm saw the dialog at 139 s
  (07:23:04Z, row `recycle-bgwork-stopped-watcher`). The foreground held on load at 07:23:23Z, so
  it never reached its own `/exit` (:18646). No other code path sends `/exit` to a pane: grep of
  `"/exit"` sends in handoff-fire, the self-close arm at :10720, and `bash-commands.log`. So the
  silent 60 s arm (`retype`, then CR) is the only candidate.
- **Pane 332.** No HELD line was logged, and claude exited by 125 s. This matches the same arm.
- **Panes 350 and 384.** No agent typed into either pane in those windows. I searched
  `bash-commands.log` from 14:20Z to 15:13Z for `send-text`/`session send`. The 384 transcript
  shows the session at rest from 06:50:33Z to 16:51:54Z, with no operator turn.

### NEW: the incident repeated live on pane 350 (MEASURED)
- Batch `20261018T180746Z-next-next3-6778` fired 350 once the "Stay" answer made the session idle.
- Its handoff.log shows precheck `composer: empty` and `bg_work: watcher … pids=…`, then watcher
  pid 91248 armed (`handoff-recycle-350-1792347897-EHjnGS.log`, which has only its 4 probe lines).
- handoffs.jsonl: `recycle-intent` at 18:24:57Z, `detach@18s`, `recycle-held-load 8.71/core` at
  18:26:21Z. The watcher was alive about 82 s.
- The verdict again said "nothing was typed, a retry is safe".
- `kitten @ get-text --match id:350` at about 18:30Z shows **the "Background work is running" modal
  again** (cc-await-ping, "❯ 1. Exit and stop tasks").
- The transcript is back on next only: `.HANDOFF.json.unconfirmed` 18:25:53Z, and
  `locks/…unconfirmed-20261018T182621Z`. **So the bare session on next is the only copy, and nobody
  will answer its modal.**
- So §2's "sweep at 18:22Z: no modal" and §4 item 1 ("let the batch wait for idle") are stale.
  Item 1 is the action that re-triggered the incident.

### Corrections
1. **The exposure metric.** §2 says 27/33 holds came ≥60 s after intent. Measured from the watcher's
   own `detach@` phase instead (`python3 -I /tmp/lrv-exposure.py` over handoffs.jsonl, joining
   intent `ts - intent@` with the held row's `detach@`), **24 of 33** held recycles had a watcher
   alive ≥60 s. Subtract the 3-8 s pane probe and a few borderline rows (64-70 s) drop out. The
   per-pane figures: 350 had 82 s (twice), 384 had 141 s, 22 had 187 s and 332 had 241 s.
2. **Where the false sentence comes from.** "Nothing was typed, a retry is safe" is not printed by
   `hf_recycle_hold` (:3635). That function prints "/exit NOT submitted". The sentence is the verdict
   string at `scripts/limit-recover/lr-handoff.sh:2026`. F2 must fix both, and lr-move-worker relays
   the lr-handoff string.
3. **The function name in F3(c).** The function at `lr-upgrade.sh:2318` is `lru_clear_own_exit`;
   `lru_exit_scrub` does not exist.
4. **The test at `tests/handoff-composer-gate.bats:250`.** It tests the pure
   `recycle_nudge_decision`, and "empty means retype" is still the right answer for that function.
   The bug is in the caller (:11718), which never asks whether the foreground committed. Keep the
   unit test, and pin the gate in the new watcher-level test, unless F1 adds a commit argument to
   the decision function.
5. **The co-causes are newer than 1376807f4.**
   - The load hold that disarms after a long-lived watcher came in `2bb9817d0` (2026-10-11). Before
     it, nothing held after arm for minutes.
   - The precheck load hold (`d58bb81d3`, 2026-10-18 05:31Z) uses the same 8/core bound as the commit
     gate. On 350 the precheck passed at 7.36 and the commit gate held at 8.72. With no hysteresis,
     a box hovering near 8/core turns every move into this race.
   - The draft carry that moved 384's `/exit` forward is `78d47b174` (2026-10-18 10:39Z). The batches
     before it read `hold:draft`; from 153246Z on they read `draft`. That matches §2.
6. **The pre-gate window is mostly the confirm.** Most of the 80-270 s is `lr-transplant --phase
   confirm` (350's confirm JSON prints after `armed`), plus the wake guard. The three reads are the
   smaller part. The conclusion is unchanged.

### Missing items
- **Live state, describe only.**
  - Pane 350 is at the modal now. Its only copy is on next, and no watcher is alive. The right
    answer is the "Stay" index (read off the screen with `_pane_bgwork_index "Stay"`), never "1",
    because no relaunch is armed.
  - Then abort batch 180746Z (`touch …/move/20261018T180746Z-next-next3-6778/abort`). Its rows
    7df606ba (pane 374, wait:mid-turn) and a3da0696 (pane 3, wait:background-job) can re-run the
    same race when they go idle. a3da0696 has a background job, so it would get the modal.
  - Do not re-drive any move while load is above about 7/core until F1 lands.
- **The simplest F1 variant: delete the retype arm.** After F1, an empty composer with claude alive
  after a committed, read-back-verified `/exit` means the `/exit` was already consumed. Retyping is
  speculative and could double-queue. A lost CR leaves `/exit` in the box, which the `cr` arm
  covers. If the arm stays, it should call `hf_exit_readback`, which brings the undo and the
  receipt, as the self-close arm already does at :10720.
- **F1 needs a pre-commit bound.** A watcher waiting for `exit-committed` must exit when the
  foreground pid is dead and no marker exists. Otherwise a foreground killed by SIGKILL or a crash
  leaves a watcher that waits forever and holds the pane lock.
- **Kill before the slow unconfirm.** `hf_recycle_hold` runs `hf_recycle_unconfirm`, which takes
  seconds, before `hf_recycle_disarm`. That lengthens the window in which the watcher acts on a
  recycle the foreground has already decided to hold. Disarm, or signal `exit-aborted`, first.
- **Hysteresis.** Make the precheck bound (d58bb81d3) stricter than the commit bound, for example
  6 versus 8/core. A pass then rarely flips to a hold minutes later.
- **The root of the load hold.** The commit gate holds only because the move lane stages no
  successor (`hf_recycle_load_gate` returns 0 when `hf_succ_ours_staged`). `hf_exit_signal` also
  requires a staged successor (:3869-3871). If move/resume recycles staged one, both the hold and
  the typed `/exit` would go away: SIGTERM skips the modal and stops the background shell.
- **The self-close watcher was not audited.** `__selfclose` / `sc_exit_unblock` (:10692-10725) has
  its own empty-composer retype at `waited ≥ 40`. I did not check whether its foreground also gates
  after detach. That is open for symptom c.
- **The census.** `lr-upgrade.sh:746` (the upgrade census) has the same `composer-unknown` fallback
  as :1080, and F4's `pane_bgwork_dialog` test belongs there too. `lr-upgrade.sh:2215` maps
  `(held: bgwork` to `wait`, which is the same "a modal is not idleness" error.

### Do the fixes break anything?
- **F1-F4 close no pane** and never discard the only copy of a session.
- **F2's "let the watcher finish"** after `CONFIRMED at a shell` is safer than today: killing it
  then is exactly what stranded 332.
- **F4's `rail-exit` class** could clear an `/exit` that an operator typed and left unsent. The
  cost is a 5-character retype.

**Confidence after verification: 90%.** The live repeat on 350 under the same preconditions removes
most of the inference. What remains INFERRED: for 384, that the 1 s read-back missed rather than a
lost CR. A trace of `it2 session send` calls in the watcher would settle it.
