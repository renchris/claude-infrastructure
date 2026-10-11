# Why in-place self-recycle failed four times on one kitty pane (panes 44 and 134, 2026-10-09 → 10-11)

## Answer

The four failures have **two root causes, not one.**

- **F1 (pane 44) is a transport failure under extreme load, on code from before the keystroke-free relaunch existed.** Every one of the 16 typed-relaunch attempts failed because the it2→kitty round trips ran at or near their 10 s bound at a load of about 45 runnable processes per core. The alarm then went to a role that does not exist (`desk`, rc 3). The phone leg is unwired, and the sweep that banners alarms self-bounded for two hours. So the first operator-visible signal was one aggregate banner at 07:06Z (2 am local). **Conviction 70%** on the transport cause; the skeptic rates it PLAUSIBLE, because no per-attempt record exists. **Conviction 85%** on the alarm chain.
- **F2, F3 and F4 (pane 134) are one regression and its residue.** `f14b42653` added a "dialog drawn above the composer" rule. From 23:46Z on 10-10, that rule read Claude Code's slash-command suggestion row (`❯ /exit  Exit the CLI`, which opens as soon as `/exit` is typed) as a dialog.
  - **F2:** the read-back of our own `/exit` came back `<unreadable>`. By design no DELs were sent, but the hold message said "five DELs sent" and no residue receipt was written, so `/exit` stayed in the operator's input box.
  - **F3:** that residue kept the menu open, so the box read UNKNOWN for 30 s mid-turn. The deferral took that to mean "mid-turn" and deferred, and then the box read UNKNOWN for 180 s with the session idle.
  - **F4:** the parser fix `0584f0720` was live by then, so the box correctly read `/exit`. With no receipt, the gate rightly refused it as somebody's draft.
  - Measured across the fleet: **4 of 4 `/exit` read-backs held with `<unreadable>` between 23:46Z and 01:48Z**, against 0 before and 0 after. Panes 168, 206 and 2 replayed the same F2→F3/F4 sequence independently.
  - **Conviction: F2 90%, F3 85%, F4 90%.**

Both causes are already fixed at the actuating line. F1's is fixed by the `recycle-keystrokeless` program; F2-F4's is fixed by `0584f0720`, live since 01:48Z. What remains are the gaps that turned each defect into a stranded or blocked pane:

- an alarm with no reader;
- a hold message that lied;
- a deferral that cannot tell a static unreadable screen from a running turn;
- six divergent copies of the composer parser;
- an exit actuator that types into the composer at all.

The ranked fixes are below.

## Evidence timeline

Live-layer sha per failure, from the shared checkout's reflog. `~/.claude/scripts/*` symlinks into that checkout, and local time is UTC-5.

| # | When (UTC) | Pane | Live sha | Recorded outcome |
|---|---|---|---|---|
| F1 | 10-09 04:55-05:03 | 44 | `bc471e0b6` | /exit landed, shell confirmed, spell-correction disarm failed ×2, relaunch write failed ×2 → `recycle-dead`; alarm `push=refused-rc3` |
| F2 | 10-11 00:25 | 134 | `e667558fc` | successor staged → `recycle-held-exit-readback`: `/exit read back as '<unreadable>'` |
| F3 | 10-11 01:20-01:24 | 134 | `1b2b93357` (handoff-fire.sh byte-identical to `e667558fc`) | `recycle-deferred-turn` → `recycle-turn-ended` (+16 s) → `recycle-held-unreachable` (180 s) |
| F4 | 10-11 02:20-02:23 | 134 | `b68fa8a25` (includes `0584f0720`, live 01:48Z) | `recycle-held-draft ... over '/exit'` |

All four are the same Claude Code session, `6defb493-e229-4318-b0ab-86e7167c39e3` (account dir `~/.claude-next`). It was resumed from pane 44 into pane 134 at 05:12Z on 10-09, under `reso-resume-one` → `expect`.

Slot reports (each claim carries file:line@sha or a log quote):

- `slot-f1-relaunch.md`, with `skeptic-f1-relaunch.md`
- `slot-f2-f4-exit-residue.md`, with `skeptic-f2-f4-exit-residue.md`
- `slot-f3-defer-watcher.md`, with `skeptic-f3-defer-watcher.md`
- `slot-primitive.md` (Q5)
- `slot-reader-sweep.md` (all composer-parser copies × widths)

## Root cause per failure

### F1, pane 44: the relaunch write failed twice — Conviction 70% (cause, PLAUSIBLE), 85% (alarm chain)

**Cause.** At `bc471e0b6` the watcher had only a typed relaunch: 2 rounds × 2 lines × 4 attempts = 16 bracketed-paste attempts, each verified by one echo read.

- Each attempt is two kitty RC calls inside it2-kitty. Each call is bounded at 15 s internally, under an outer `hf_bounded` bound of 10 s.
- `capacity-alarm.jsonl` shows load_1m between 422 and 454 on 10 cores across the window.
- The 449 s from claude's exit to the alarm spread over 54-70 bounded it2 calls gives **6-8 s per call**. The same call takes 0.2 s today.
- A late echo on a healthy transport would have taken 80-100 s. That rules it out as the sole cause.
- The final `session list` failed outright ("pane unknown").
- Two things were ruled out by measurement:
  - **Width and wrapping:** the 69-char disarm line failed exactly like the 559-char launch line, and the matcher passes at 30-115 columns.
  - **zsh spell-correction:** the typed lines are builtins and cannot be corrected. Its "could not disarm" lines are a symptom of the same transport failure.
- **Not determined:** whether kitty-side lateness or watcher-side process starvation dominated. There was no per-attempt telemetry before `f4b297310`.

**Skeptic corrections** (`skeptic-f1-relaunch.md`):

- **No line was submitted.** zsh history holds both nonce lines for 27 of 29 typed relaunches that night, and none for this watcher (`hfv-22463`). So the zero is strong evidence.
- **kitty's backlog is measured.** boot-resume-launch's `kitty @ launch` for window 134 timed out at about 05:03:31Z, yet kitty forked the window at 05:12:38Z (`ps -o lstart` of root pid 18273). That is **9 minutes after the client gave up**.
- **The call arithmetic cannot separate two readings.** Corrected to 38-86 bounded calls, the window gives about 5-11 s per call, which fits two things:
  - nearly every call timed out, so the failure *is* the transport;
  - calls completed in about 5-6 s, but the echo failed the verify.
- **A co-cause the slot dismissed for the wrong reason.**
  - The relaunch was typed into a **cold `zsh -l -i`** that `lr-fire-resume.sh:1537-1558` execs after claude exits; the predecessor was a cc-lr upgrade resume.
  - With p10k instant prompt, that shell echoes `^U` and the paste markers literally while `.zshrc` loads. That fails the **focused suffix rule** for both lines (measured, `/tmp/skf1/echoctl-check.sh`).
  - HEAD names this state `paste-end-echo`.
  - It can explain early attempts, not the whole 6.5 minutes.
- **The failure began after about 04:56Z.** The listing and the two background-work exchanges at 04:55:41-51Z worked at the same load.

**Why the operator never heard.**

- `hf_alarm` pushed `cc-notify --role desk`, and no `desk` role exists, so the call returned rc 3 (`role-unset`). 19 of the 20 alarm verdicts on disk are `refused-rc3`.
- The phone fallback is inert: no Pushover credentials are configured.
- The only push consumer is `autonomy-sweep.sh`'s `ladder_v2`, which runs at the end of a tick. Ten consecutive ticks from 05:05Z to 06:56Z self-bounded before reaching it.
- The first banner, at 07:06:39Z, was an aggregate ("368 pages, 192 alarms …") with no command in it.
- operator-readout did count the record in its `◆` line (87 `fired` rows between 05:03Z and 16:00Z), but only as one unit among hundreds.
- The operator was awake: he asked for this recycle at 04:53:22Z. A per-record banner at 05:03Z had a real chance; 02:06 local did not.
- His first message afterwards came at 15:44:04Z, 10 h 41 min after the alarm. Meanwhile the session had been auto-resumed at 05:12:41Z in window 134 with no prompt.
- Sources: `slot-f1-relaunch.md` §(d) and `skeptic-f1-relaunch.md`.

**Already fixed, and what is not.** The `recycle-keystrokeless` program (live 20:11Z on 10-09) did two things:

- it stages a keystroke-free successor that the pane's own consumer claims after `/exit`;
- it hardens and instruments the typed fallback.

But the typed fallback is still reached whenever nobody claims the stage. That happened in 4 of the 9 exits since it landed, all on panes whose consumer process started before the deploy. Under F1's load, that fallback would probably still fail (`slot-f1-relaunch.md` §(c)).

At HEAD the alarm goes by sid when the desk role is absent. For a relaunch failure, that sid is the predecessor that just exited, so the alarm is a mailbox write to a dead session.

### F2, pane 134: `/exit read back as '<unreadable>'` — Conviction 90%

**Cause.** `selector()` in `composer_content` (`git show e667558fc:scripts/handoff-fire.sh`:4068-4071) matches any `❯` at indent 1-4. The loop at :4078 then exits 9 ("dialog above a live composer") → UNKNOWN. `hf_exit_readback` (:3323) maps that to `<unreadable>`.

- That rule arrived with `f14b42653` and went live at 23:46:32Z, 39 minutes before F2.
- The freshness re-read had found the box **empty** seconds earlier, and the only change between the two reads is the typed `/exit`.
- Two real captures with `/exit` typed and the menu above the box read UNKNOWN at `e667558fc`, and `/exit` both before the rule (`4b3f73ade`) and at HEAD:
  - pane 168, 38 columns, CC 2.1.293;
  - a throwaway window, about 156 columns, CC 2.1.291.
- The menu pointer is `❯` followed by an ASCII space (`od -c`).
- Sources: `skeptic-f2-f4-exit-residue.md` E1-E2 and `slot-reader-sweep.md` §0.

**The DELs (Q2).**

- `hf_exit_readback` (@e667:3331-3333) sends DELs only when the read ends in `/exit`, so an `<unreadable>` read correctly sent none.
- `recycle_fire_commit` (@e667:17368) printed a hard-coded "five DELs sent to take our /exit back out".
- The session relayed that to the operator as "it removed what it had typed". It also told him to type `/clear` into a box still holding `/exit`.
- Nothing verified removal: the hold path has no re-read, the watcher was disarmed, and no retry ticket was written.
- `0584f0720` made the text truthful (`HF_EXIT_RB_UNDO`) and added a receipt on unreadable reads. But at HEAD:
  - `hf_recycle_hold` (:3203) still says "ABORTED before /exit … /exit NOT submitted";
  - the resume-debt reason (:17380) still says "session untouched";
  - neither the new text nor the receipt has a test or a field run. The only field scrub (pane 168, 01:59Z) used a hand-written receipt.

**Not the reso expect-wrapper lesson.**

- Pane 134's claude does run under `expect` on an inner pty (ttys035). `pane_cc_state`'s descendant closure sees it, so the pane reads `cc`, and the recycle correctly typed `/exit` rather than a shell line.
- The 2026-08-06 class ("probe types a shell command into a live composer") is closed at entry (`slot-primitive.md` §5).

### F3, pane 134: deferred, then "composer UNREADABLE for 180s" — Conviction 85%

**Cause.** F2's `/exit` was still in the box, so the slash menu stayed drawn. Pane 168's capture shows the menu stays up while the residue sits, more than an hour later on pane 2.

`composer_content` at the same sha read UNKNOWN on every poll. The self-recycle path treats any UNKNOWN inside its own tool call as "mid-turn":

- `recycle_composer_block` @e667:17567, 17597-17602;
- `hf_recycle_defer_eligible` @e667:4518 never asks why the read is UNKNOWN.

So it deferred. `recycle_turn_wait` correctly found the turn over 16 s later (transcript `turn_duration` 01:21:21.9Z). The child then spent the full 180 s gate on an idle session and a static screen. The transcript has **no records** between 01:21:21.9Z and 01:24:41.8Z.

The decisive differential:

- the gate, block, defer and turn-wait functions are byte-identical between F3's sha and F4's sha;
- `composer_content`'s slash exemption is the only change;
- F4 read `/exit` on the same box.

Pane 206 ran the same sequence four minutes later, and the operator's screenshot of it showed `/exit` unsubmitted with the slash menu open. All 3 known deferrals ever recorded ended `held-unreachable` at rest on a static parser defect; none reached /exit. Sources: `slot-f3-defer-watcher.md` §2-3 and `skeptic-f3-defer-watcher.md` §1-2.

**The watcher (Q4) did not cause F3.** cc-await-ping `bj0akekfz` completed at 01:24:41.8Z. That was 9 s **after** the hold, and it was woken by the hold's own `RECYCLE-HELD` mail.

The rail's false wording ("could not be read while the turn was running", @HEAD:17620) led the session to blame the watcher. At F4 it then stood the watcher down "so it can't wake the session mid-wait". On a deferred path, that very task-notification counts as a new prompt and holds the recycle. So the misattribution is not cosmetic.

**Structural conflict, answered.**

- An armed watcher does not break a deferral. Its stop-if-watcher arm already answers the background-work dialog at /exit (F1 shows it working live).
- Standing the watcher down before a deferral would itself create the "new prompt" that holds the deferral. The comment at @HEAD:10526-10527 names this effect.
- The real gap is different. After a deferred turn ends, the self lane has **no last-moment at-rest or new-prompt re-read** before /exit (`rcy_rest_tx` is set only for same-account and focused-remote, @HEAD:17950-17952). Any turn that starts during the child's composer gate, which can last up to 180 s, can be interrupted by /exit. That includes an operator prompt.

### F4, pane 134: held as a draft over '/exit' — Conviction 90%

**Cause.**

- The box held F2's residual `/exit`, which `0584f0720`'s parser now reads correctly.
- No receipt existed for pane 134: `~/.claude/logs/composer-residue/` has none, because F2 predates the receipt arm.
- So `composer_residue_is_ours` (@HEAD:17572) failed, and `recycle_composer_block` refused the box as somebody's draft (@HEAD:17677). That is correct by design.

**Evidence the box held F2's text, not new typing:**

- `bash-commands.log` shows no send to pane 134 between 00:25Z and 02:27Z;
- the transcript has no prompt between 00:25:57Z and 01:20:16Z;
- the session's 02:23:45Z message asked the operator to delete the `/exit`, and his 02:26:49Z prompt carries no `/exit` prefix.

Pane 2 independently repeated F2→F4: exit-readback at 01:28:24Z, then held-draft over `/exit` at 02:26:12Z.

**The danger the brief named is real, but it takes two key presses.**

- After the F2 hold, the staged successor was revoked (`ttys032.revoked`, 00:25:47Z), the watcher was killed and the resume debt was abandoned.
- Enter in that box would most likely raise the background-work dialog, because a watcher task was nearly always running.
- Its default, "Exit and stop tasks", gives rc 0. `reso-resume-one`'s `rr_close_on_clean_exit` (:967-990) then closes the pane, with no successor and no debt.
- This is estimated from the code and was not exercised.

Pane 134's box reads empty now (read-only, 02:31Z and 02:57Z).

## Ranked fixes

Line numbers are at HEAD `b68fa8a25`. Each test is written to be red before the fix. The skeptics checked each test against the suite's stubs.

1. **DONE, landed by another session as `0e882c9ac` while this report was being written**, with `tests/recycle-exit-residue.bats` (5 cases) and the real 2.1.291 capture as a fixture. Its rationale is `docs/research/recycle-exit-residue-2026-10-10.md`. It also accepts a pointer followed by U+00A0, and its third case covers fix 2's receipt-and-scrub path. The original text of this fix follows for the record: **Land the narrowed slash exemption already written on `fix-recycle-exit-residue`.**
   - Problem: `0584f0720` exempts *any* `❯ /…` row above the box. With the menu open, a CR submits the **highlighted** row, so a box holding `/exit` under a menu highlighting another command reads `/exit`, and the CR runs the other command.
   - Where: `scripts/handoff-fire.sh` `selector()` :4074-4085.
   - Test: `tests/composer-tall-readback.bats`, a case where the highlighted command differs from the box's command → UNKNOWN. Also pin both real captures (`/tmp/slashprobe/exit-typed.ansi.txt`, which is ephemeral, and the branch's `slash-menu-exit-2.1.291.txt`) under `tests/fixtures/`, and assert that `f14b42653`'s parser reads them UNKNOWN, so the fixture provably separates the two parsers.
2. **Make an UNKNOWN read straight after our own `/exit` count as receipted residue, and fix the two remaining false sentences.**
   - Problem: the HEAD receipt is consulted only when the box parses, so any UNKNOWN shape after `/exit` still strands it. Examples: a menu below the box, a tall box with the menu above, a pointer followed by U+00A0.
   - Where:
     - the receipt-match logic, `composer_residue_is_ours` :4745 and `recycle_composer_block` :17571-17609: allow a time-bounded "own /exit, unreadable" receipt to trigger `composer_scrub_verified`, which is read-back verified and holds if the box never clears;
     - the false text in `hf_recycle_hold` :3203 ("ABORTED before /exit") and the resume-debt reason :17380 ("session untouched").
   - Test: `tests/handoff-fire-recycle-custody.bats` test 7 (:628-646) asserts DEL counts only. Add three assertions:
     - the operator-facing text for an `<unreadable>` read says no DELs were sent and the `/exit` may still be in the box;
     - the receipt file exists;
     - the next gate scrubs it.
   - Today no test greps `HF_EXIT_RB_UNDO` or "no DELs sent".
   - **Status at trunk `cc863bdaf`:** the receipt-and-scrub half is now tested (`tests/recycle-exit-residue.bats`, "an unreadable read-back types nothing, receipts its /exit, and the deferred retry clears it"). The false text survives, now at `scripts/handoff-fire.sh:3203` ("ABORTED before /exit") and `:17391` ("session untouched").
3. **Defer only on a turn-shaped UNKNOWN, and hold a static one fast under its own class.**
   - Where: `recycle_composer_gate` :4208 (today every UNKNOWN maps to rc 2), `recycle_composer_block` :17577-17620, `hf_recycle_defer` :4549.
   - The reason must travel as a **distinct exit code**: every caller captures the read with `$(…)`, so an exported variable would be lost.
   - Defer on no-read and no-box. On dialog-above, glyph-below or tall-rejected, hold after one probe as `recycle-held-unreadable-static`, naming the shape.
   - Test: `tests/handoff-recycle-turn-wait.bats`. Use the real 2.1.291 capture with `HF_COMPOSER_SLASH_MENU=off` (a field shape) at rest, with a dead caller pid and an `end_turn` transcript. Count `session read` calls in the `hf_bounded` stub; `HF_SLEEP` will not work, because the gate uses `/bin/sleep` at :4217. Assert the static class. Red on HEAD.
4. **Add a self-lane last-moment re-read after a deferred turn ends.**
   - Where: :17950-17952. When `RCY_DEFERRED=1`, set `rcy_rest_tx` to the deferring transcript and add `hf_new_prompt_since <defer t0>`.
   - Test: eval `recycle_fire_armed` as `tests/handoff-recycle-expect-probe.bats:266` does. Append a user record after `recycle-turn-ended`, then assert `recycle-held-busy`/`-new-prompt` and that the `recycle_fire_commit` stub was **not reached**. A "no SEND:/exit" assertion passes before the fix.
5. **Make the deferral's wording true.**
   - Where: :4607 "composer unreadable mid-turn" and :17620 "could not be read while the turn was running" (at trunk `cc863bdaf`: :4618 and :17631). When `RCY_DEFERRED=1` the child runs after the turn has ended.
   - Test: assert on the retry ticket's `.why` written by `hf_recycle_retry_ticket`. A `NOTIFY:` line never appears under that suite's `hf_bounded` stub, so an assertion on it passes before the fix.
6. **Capture the screen on every `held-unreachable` and `held-exit-readback`.**
   - Write it through the existing `scripts/lib/lr-composer-snapshot.sh` facility, mode 0600 and bounded. None of F2 or F3 has a screen witness, and one capture would have made the diagnosis immediate.
   - Where: `rcy_composer_unreadable` :4435 and `hf_recycle_hold` :3199.
   - Test: the turn-wait suite asserts the snapshot carries the fixture's rows.
7. **Page post-/exit strands directly, and address them to something with a reader (F1).**
   - Where: `hf_alarm` :8434-8500 and its relaunch-failed and dead callers :10977-10983.
   - For the classes `recycle-relaunch-failed`, `recycle-dead` and surface-gone: post one OS banner per record, instead of mailing a dead predecessor's sid or a missing `desk` role.
     - The banner carries a **short handle** (the alarm id or recovery-packet path), not the command: `lr-page`'s OS leg caps text at 200 characters (`scripts/limit-recover/lr-page.sh:16-19`), and F1's line was 559.
     - Issue it **before** the 10 s cc-notify push and the debt settle.
     - Only 4 strand-class records exist from 10-03 to 10-10, so page fatigue is low.
   - In `scripts/autonomy-sweep.sh`, run a strand-only rung **before phase 0a**, not merely before 0b (around `sweep_yield` :422; `ladder_v2` :2432). Phase 0a alone overran in the post-F1 ticks (`elapsed_s` 893 and 413).
   - Tests:
     - `tests/handoff-alarm-records.bats`: a relaunch-failed alarm with a dead sid yields exactly one page through a stubbed `LR_PAGE_OSASCRIPT_BIN`;
     - a second case where the OS leg fails, asserting the record says so;
     - a sweep case whose phase 0a overruns still writes an `os-banner` row for a seeded strand record.
   - Wiring Pushover is the operator's step, and is not required for the banner.
8. **Make the staged successor claimable by every interactive pane (F1's residual).**
   - Problem: 4 of 9 exits fell back to typing, because the shell that regained the tty was not a consumer, or was started before the consumer code went live.
   - Where: a zsh `precmd` claim in the `scripts/kitty-setup.sh` rc block, calling `cc_pane_successor_take` (`scripts/lib/pane-successor.sh`).
   - Gate the hook on a fork-free `[[ -e …/<tty>.cmd ]]`: `take` forks jq and ps, and this runs at every prompt in every pane.
   - It does not cover a shell started before the rc change, so it shrinks the revoke-then-type case rather than closing it.
   - Test: an interactive `zsh -i` on a pty with a staged successor claims it within one prompt cycle, and no `recycle-successor-revoked` row is written. Add negative cases: the same tty with a different window id, a dead watcher, an expired TTL, and nothing forked when nothing is staged.
8b. **Do not type `/exit` under extreme load when the post-exit path will have to type (F1).**
   - Today a recycle is exempt from the capacity gate (`scripts/handoff-fire.sh:8303-8305`, :12636). F1 typed `/exit`, the point of no return, at about 45 runnable per core.
   - Hold or defer the `/exit` when load per core is above a bound **and** the successor stage was refused or cannot be claimed.
   - Test: with a stubbed load above the bound and a refused stage, assert a hold row and no `/exit` sent. With a staged, claimable successor, assert the recycle proceeds.
9. **Converge the six composer-parser copies onto the guarded one.**
   - Problem: `0584f0720` patched only `composer_content`. The copies without dialog guards read a background-work dialog above an empty box as **EMPTY**, measured on real 2.1.260 captures:
     - `cc_tui_composer*` (`scripts/lib/cc-tui.sh`:158-205);
     - `lcs_draft_rows` (`scripts/lib/lr-composer-snapshot.sh`:52-58);
     - lr_recon `observe.py` `composer_state`;
     - `bin/it2-kitty` `composer_state` (:1417-1443).
   - `cc_tui_submit` (cc-tui.sh:526) types through that copy for `lr-reset-poller`, `lr-fleet`, `lr_recon act.py` and handoff-fire's own transplant carry (:4263-4364). A payload character that is a dialog hotkey could act on the dialog.
   - `lr-fire-resume.sh` LR_SCREEN_SH (:854, :878) carries the pre-fix selector. Port fix 1's narrowed rule there, never `0584f0720`'s.
   - Test: one parametrized bats suite that extracts every copy and runs the shared corpus from `slot-reader-sweep.md` §3. Assert UNKNOWN for dialog-over-empty in every copy.
10. **Stop typing the exit at all: SIGTERM the pinned claude pid once the transcript is at rest and the successor is staged.** This is the primitive recommended for Q5, at Conviction 75%, gated on one proof.
    - What it removes: every composer actuator in F2-F4 (typed `/exit`, read-back, DEL undo, residue) and the background-work dialog keys from F1.
    - Why it should work: CC 2.1.293's SIGTERM handler runs the same `shutdown()` as `/exit` (binary scan; `docs/research/team-inplace-upgrade-2026-09-23/q1-lead-exit.md` §6). `bin/cc-teardown:889-902` already does marker → `kill -TERM` → poll → KILL with an lstart pin.
    - Where: `recycle_fire_commit` :17370 replaces `hf_exit_readback` with a teardown marker plus a pinned `kill -TERM`. Keep the composer read as a draft guard only.
    - Gate before building: a throwaway-pane proof on 2.1.293 that SIGTERM at rest leaves the transcript intact, gets the staged successor claimed, stops the background shell, and is not classified as a crash once the marker exists. That proof must be run from a session allowed to create and close its own scratch pane; this research session is not.
    - Risk: a SIGINT path would read as a clean exit and trigger `rr_close_on_clean_exit`. Use SIGTERM (exit 143), and make the consumer treat the recycle marker as the reason for the exit.
    - `/clear` + paste is refuted for automation (2026-07-03 incident; `slot-primitive.md` §3c).

## What would change these numbers

- **F2, F3 and F4 drop below 70%** if a capture of pane 134 between 00:25Z and 02:20Z shows no `❯ /` row above the box, or if any logged write to pane 134 between 00:25Z and 02:20Z turns up.
- **F2 and F3 rise to about 97%** with a 2.1.293 capture at pane 134's geometry with `/exit` typed, taken in a throwaway pane.
- **F1's transport cause** would move with per-attempt `recycle-type-attempt` rows from a reproduction at a load above 40 per core. If those showed sends under 1 s with no echo, a late echo, or the instant-prompt echo failing the suffix rule, would be back in play. A record of pane 44's focus state at 04:56-05:03Z would also move it.

## Build results (2026-10-11, branch `fix/recycle-gaps-kitty`)

Every ranked fix except 8 and 8b is built and tested. Each new test was run red against the pre-fix
script and green after.

| Fix | What is now true | Tests (new) |
|---|---|---|
| 1 | Already landed as `0e882c9ac` before this build; not redone. | — |
| 2 | An exit-readback hold says `/exit` **was typed**, whether DELs were sent, and, on an `<unreadable>` read, that the `/exit` may still be in the box with a residue receipt written. The resume-debt reason no longer says "session untouched". No keystroke goes into an unreadable box: under a dialog it would be taken as the dialog's answer. | `handoff-fire-recycle-custody.bats` 7, 7b |
| 2 (consumers) | `lr-upgrade.sh lru_hf_evidence`, `lr-handoff.sh`'s held-after-confirm branch and `lr_recon/settle.py _RCY_HELD` read all three hold forms (`ABORTED before /exit`, `HELD after /exit was TYPED`, `HELD after SIGTERM`). Before, the new wording read as no hold, so lr-upgrade skipped `lru_clear_own_exit` and lr-handoff fell to STRANDED. | `lr-handoff-flags.bats` (2 hold-form cases), `lr-upgrade-settle.bats` S11a2, `test_settle.HoldLineForms` (2) |
| 3 | `composer_content` exits **3** for a static unreadable shape (dialog above, glyph below, tall rejected) and 1 for a turn-shaped one. The gate confirms static after two identical reads; the checksum stops at the box's bottom border, so a ticking status line still confirms and a spinner above the box does not. A static screen holds at once as `recycle-held-unreadable-static`, naming the shape, with no deferral and no 180 s wait. | `handoff-recycle-turn-wait.bats`: F3 static hold, own-`/exit` receipt wording, exit code carries the shape, ticking status line vs spinner |
| 4 | A deferred self-recycle re-reads the session at the last moment before `/exit`; a turn or a new prompt since the deferral holds it. | `handoff-recycle-turn-wait.bats` (deferred re-read cases) |
| 5 | The deferral's row and the retry ticket no longer say "while the turn was running" on the child that runs after the turn ended. | `handoff-recycle-turn-wait.bats` fix 5 ticket `.why` |
| 6 | Held-unreachable, held-exit-readback and the static hold keep a 0600 screen witness through `lr-composer-snapshot.sh`, named in the row; the store keeps the newest 50 `held-` captures and never prunes the reconciler's own. | `handoff-recycle-turn-wait.bats` fix 6 (snapshot, bound, outside kitty) |
| 7 | `recycle-relaunch-failed`, `recycle-relaunch-refused` and `recycle-dead` post one OS banner per record through `lr-page.sh`, before the push. The banner leads with the packet or record handle (≤ 200 chars) and says "is stranded", or "needs attention" when claude is still running. The record carries `paged=`. `autonomy-sweep.sh` runs a strand rung **before** phase 0a that banners an unpaged, unseen strand record once, across ticks. | `handoff-alarm-records.bats` STRAND PAGE (7); `autonomy-sweep.bats` strand rung (6, including an overrun tick and a late-rung mutant control) |
| 9 | Superseded: session 216's wave landed the convergence of all five parser copies as `04f9be43a` (`tests/composer-parser-parity.bats`, 21 cases) while this build ran. Its own parser commits were dropped at rebase; trunk's suite covers every case they added. | — |
| 10 | When the last read proved the session at rest, our successor is staged, and exactly one claude on the pane's tree is pinned by session row and start time, the recycle stops claude with `kill -TERM` instead of typing `/exit`. It waits 30 s (Claude Code's own shutdown failsafe is 15 s), never sends KILL, and holds as `exit-signal-ignored` if claude outlives the wait. The teardown marker carries the pid, so the 143 reads as RECYCLE. Anything else, or `HF_EXIT_ACTUATOR=typed`, types `/exit` as before. In practice only fresh-mode recycles stage a successor, so the signal path serves the deferred self-recycle lane; same-account, focused-remote and resume recycles still type. | `handoff-fire-recycle-custody.bats` 16a-16f; `lead-crash-watchdog.bats` signal-exit marker; structural pin in `handoff-recycle-custody.bats` 6 updated to anchor on the signal |

**Gate proof for fix 10.** `proof-sigterm-2.1.293.md` (scratch panes this build created and closed)
passed all four conditions. Session 216's independent proof
(`docs/research/recycle-sigterm-proof-2026-10-11/REPORT.md`) passed the built design 9/9 and set the 30 s grace.

**Not built here.** Fix 8 (a zsh `precmd` claim of the staged successor) is session 216's W3. Fix 8b
(hold `/exit` under extreme load when the successor cannot be claimed) is session 216's, to fire after
this lands.

**Suites run on the merged branch** (plan line asserted): `autonomy-sweep` 98/98,
`handoff-fire-recycle-custody` 52/52, `handoff-composer-gate` 60/60, `lr-handoff-flags` 50/50,
`lead-crash-watchdog` 44/44, `handoff-alarm-records` 27/27, `lr-upgrade-settle` 22/22,
`composer-tall-readback` 21/21, `composer-parser-parity` 21/21, `handoff-recycle-draft-carry` 19/19,
`lr-page` 16/16, `handoff-recycle-expect-probe` 12/12, `handoff-recycle-custody` 7/7,
`recycle-exit-residue` 5/5, `lr_recon.tests.test_settle` 53 OK. `handoff-recycle-turn-wait` was 24/24
in a low-load window and 24/25 after the witness-bound test was added, at load ~300: the red is test 6,
"a NEW PROMPT after the deferral", which also passed only 1 of 3 runs on trunk `origin/main` at the
same load (load ~460), so it is a pre-existing load flake, not this build. Bare shellcheck: 0 findings
on `handoff-fire.sh`, `autonomy-sweep.sh`, `lr-handoff.sh` and `lr-upgrade.sh`.
