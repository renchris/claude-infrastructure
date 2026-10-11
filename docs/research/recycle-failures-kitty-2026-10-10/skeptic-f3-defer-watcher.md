# Skeptic review: slot F3 (defer + watcher), pane 134, 2026-10-11 01:20-01:24Z

This review is read-only. Nothing was typed into, sent to or signalled in any pane or process. The only reads used were `kitty @ ls`, `ps`, `stty -f <tty> size`, `git show`, `jq` and `grep`. The scratch files are in `/tmp/skeptic-f3/` and are ephemeral; every result is reproduced below. The report under review is `slot-f3-defer-watcher.md`, in this directory.

Live sha at F3: `1b2b93357`. Its `scripts/handoff-fire.sh` is byte-identical to `e667558fc`. Measured with `md5 -r` of the `git show` blobs: both are `46e7ee64…`. Line numbers are `@e667` (e667558fc) or `@HEAD` (b68fa8a25).

## Verdicts

| # | Claim | Verdict | Conviction |
|---|---|---|---|
| 1 | F3 = F2's un-removed `/exit` + the slash-menu row above the box, which `selector()` @e667 reads as a dialog, giving UNKNOWN. The deferral reads that UNKNOWN as "mid-turn" and the child then waits 180 s on a static screen | **CONFIRMED**, with corrections (§2) | 85% (unchanged) |
| 1b | The watcher did NOT start a turn in the gate window; it was woken by the hold's own mail | **CONFIRMED** (observed) | 97% |
| 2 | Q3: no watcher conflict in F3. Structural gap: the self lane has no last-moment at-rest or new-prompt re-read once the deferred turn has ended | **CONFIRMED**, but the window is understated (§3) | 80% |

I tried to refute each claim and could not. The decisive link is still inferred: no screen of pane 134 from 01:20-01:24Z exists. I found three new pieces of evidence that make the mechanism stronger (§1). I also found two errors in the supporting detail (§2) and four test assertions that would pass before the fix (§4).

## 1. New evidence I measured, which the slot did not have

**(a) A real capture of the menu-above shape.** Until now it rested on synthetic screens.

* Source: branch `fix-recycle-exit-residue` (commit `fb63f154e`, **not on trunk**). It carries `tests/fixtures/recycle-exit-residue/slash-menu-exit-2.1.291.txt`, a live capture of a throwaway CC 2.1.291 pane with `/exit` typed and no Enter. Its rows:
  * row 17: `  ❯ /exit                                  Exit the CLI`
  * rows 18-19: `/context …` and `/usage-credits …`
  * then the rule, `❯ /exit`, the rule, and the footer.
* The pane was **wide**: the menu rows are not wrapped and run to 468 bytes. So the menu opens ABOVE the box whatever the width. That closes most of the geometry gap the slot names in §3 ("57x62 now … geometry at F3 time is unproven").
* I ran the extracted `composer_content` from each sha over it with a stub `it2` that honours `-n` like bin/it2-kitty (`/tmp/skeptic-f3/run.sh`, `/tmp/skeptic-f3/fakeit2`). Results:

| screen | e667558fc (F3) | b68fa8a25 (F4/HEAD) | fb63f154e (unlanded tightening) |
|---|---|---|---|
| real 2.1.291 capture, menu above | rc=1 UNKNOWN | rc=0 `/exit` | rc=0 `/exit` |
| 57-col pane-134 shape, menu above, `✻` spinner (mid-turn) | rc=1 | rc=0 `/exit` | rc=0 `/exit` |
| same, at rest | rc=1 | rc=0 `/exit` | rc=0 `/exit` |
| same, menu below the box | rc=1 | rc=1 | rc=1 |
| same, no menu, footer `⏵⏵ auto mode on · 1 shell` | rc=0 `/exit` | rc=0 `/exit` | rc=0 `/exit` |

**(b) The same incident was observed directly on a sibling pane, inside the same 4 minutes.**
* Pane 206 ran the identical sequence: exit-readback `<unreadable>` 01:24:00Z, deferred-turn 01:24:45, turn-ended 01:25:03, held-unreachable 01:28:06Z.
* The operator then screenshotted it: "`/exit` sitting UNSUBMITTED in the composer with Claude Code's slash-command menu open (`/exit Exit the CLI` highlighted)". Source: the brief of fix session c1081576, transcript `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-fix-recycle-exit-residue/c1081576-….jsonl` line 12.
* That session's root-cause doc (`git show fb63f154e:docs/research/recycle-exit-residue-2026-10-10.md`, §(d)) lists pane 134's 00:25:47 → 01:21:14 → 01:24:32 sequence as the same cause.

**(c) Kitty reads were working during the F3 window, so a terminal read stall is ruled out.**
* Pane 206's `recycle-successor-staged` at 01:23:54Z needed its composer gate to read **EMPTY**, inside F3's 01:21:30-01:24:32 gate. Source: `~/.claude/logs/handoffs.jsonl`.
* Pane 168's gate ran in the same minutes (01:21:22 → 01:24:27) and also read UNKNOWN over its own pre-fix `/exit` residue. At 01:59:15, with the fixed code, it read `'/exit'` and scrubbed it (`recycle-residue-scrubbed`).

**The defect existed only for a short window.** The dialog-above `selector()` rule was added by `f14b42653` (2026-10-10 17:43 -0500). Measured: `git log -S'function selector(s' -- scripts/handoff-fire.sh` lists only that commit, and its parent has 0 matches. So the F3 trigger existed only from that deploy until 0584f0720 went live at about 01:48Z. Every deferral in the live store falls inside that window.

## 2. Claim 1: what holds, and what needs correcting

Re-checked and holding:

* **Nothing removed F2's `/exit`.**
  * `hf_exit_readback` @e667:3316-3335 sends DELs only in `case */exit)` (3331-3333). `<unreadable>` matches nothing.
  * The hold text is hard-coded "five DELs sent…" (@e667:17368).
  * `hf_recycle_hold` (@e667:3199) only unconfirms and emits.
  * `bash-commands.log` holds no send to pane 134 between 00:25Z and 02:27Z (measured: grep over 1,442 lines).
  * The transcript has no user prompt between 00:25:57 and 01:20:16.
* **The gate code is identical at F3 and F4.**
  * Measured: md5 of each extracted function @e667 vs @b68 is SAME for recycle_composer_gate, recycle_composer_block, hf_recycle_defer, hf_recycle_defer_eligible, recycle_turn_wait, hf_transcript_at_rest, hf_new_prompt_since, rcy_composer_unreadable, recycle_fire_gated and hf_invoking_call_pid.
  * Only `composer_content` (the selector exemption) and `hf_exit_readback` differ.
  * The other commit in `e667558fc..b68fa8a25 -- scripts/ bin/ hooks/` is `76b028d3e` (chime player and hooks/notify.sh), which is unrelated.
* **The F3 UNKNOWN could not have come from the running watcher.** F2 at the same sha had watcher `br2y6u2nv` running (armed 00:25:01) and its gate read EMPTY mid-turn (successor-staged 00:25:42).
  * The other F3/F4 screen differences are mid-turn vs at rest (F3's first look was mid-turn too), and the watcher stopped by F4's own call at 02:20:27.
  * Neither difference draws a `❯ /` row, and those rows are the only thing the e667→b68 diff changes.
* **The turn-end arithmetic is consistent.**
  * Defer log: "caller pid 93183", "the turn ended after 16s".
  * Transcript: last record of the deferring turn `turn_duration` 01:21:21.900Z; next record 01:24:41.810Z (measured: `jq` over the transcript, 00:25-02:21Z).
  * CC was idle for the whole 01:21:30-01:24:32 gate.
* **The deferral only fires on UNKNOWN in its own tool call.** The trigger is rc 2 from the 30 s first look (@e667:17567, 17597-17603). `hf_recycle_defer_eligible` (@e667:4518) never classifies the UNKNOWN, and the row text says "mid-turn" (@e667:4593).

Corrections:

1. **"Both deferrals since 10-05" overstates the window.** The live store's first row is `2026-10-06T23:27:59Z` (measured: `head` of handoffs.jsonl; there is no rotated file). The 10-05 founding case (reso pane 254) is outside the store, but commit `a1434bb25` documents that it was refused at rest by a labeled-border parser defect. So the count is **0 of 3 known deferrals reached /exit**, and all 3 were static parser defects. That makes the slot's point stronger.
2. **A footnote on "UNKNOWN on every poll".** `recycle_composer_gate` (@e667:4194-4205) returns 2 when no poll read EMPTY and the **last** poll was UNKNOWN. It does not prove that every poll was UNKNOWN. This is harmless here, because the parser is deterministic over a static screen.
3. **"Already fixed by 0584f0720" is incomplete.**
   * 0584f0720 exempts any `❯ /…` row at indent 1-4. With the menu open, a CR submits the **highlighted** row, not the box. So a box holding `/exit` under a menu highlighting another command reads `/exit`, and the CR that follows runs the other command.
   * `fb63f154e` (branch `fix-recycle-exit-residue`, **unlanded**: `git branch -a --contains` lists only that branch and `ship/backup-fb63f154e`) narrows the exemption to "the highlight names the box's own command".
   * The slot's residual-gap list omits both the fail-open and the pending fix.
4. **The F3 shape can still recur at HEAD.** When the screen after `/exit` is any UNKNOWN shape (menu below, `❯`+U+00A0, tall box with menu), the 0584f0720 receipt is never consulted: `composer_residue_is_ours` needs a readable box, and the gate's first read is empty. The deferral then repeats the F3 sequence. The slot names "menu below" but does not tie it back to this receipt.

## 3. Claim 2 (Q3): what holds, and the window it understates

Holding:
* `hf_recycle_defer` (@e667:4535-4598) never touches the watcher.
* The self lane answers a watcher-only background-work dialog with stop-if-watcher (@HEAD:10496-10498, scoped to `RCY_CALLER_PID`; the deferred child passes `RCY_DEFER_CALLER_PID` @HEAD:17843). F1's row `recycle-bgwork-stopped-watcher … jobs=watcher … lane=self` (2026-10-09T04:55:51Z) shows it working live.
* The last-moment at-rest read is set only for `--same-account` (a remote mode; set at @HEAD:13431) and for a focused remote (@HEAD:17950-17952).
* `RCY_DEFERRED` is read in only two places (@HEAD:4535 eligibility, 17843 caller pid). Measured with `grep -n RCY_DEFERRED`.
* Watcher bj0akekfz: armed 01:20:25. Its output reads `2026-10-10T20:24:32-0500 [recycle-watcher] RECYCLE-HELD …` then `verdict=ping … elapsed=256s`. The task-notification is at 01:24:41.8Z.

Understated:
* **The window is not "about 10-16 s".** It runs from turn-ended to /exit, and that includes the deferred child's **whole composer gate**: `CC_RECYCLE_DRAFT_WAIT:-180` s, whenever the first read is not EMPTY.
* Worst case: the box holds an operator draft after the turn ends, and the operator submits it during the gate. The box then reads EMPTY, the gate passes, and the freshness re-read passes (the box is empty mid-turn). /exit then interrupts the operator's fresh turn.
* That is exactly the turn the same-account comment says must not be killed (@HEAD:17941-17944).
* "Impact is bounded" holds for peer mail, which cc-await-ping does not consume. It does not hold for an operator prompt or a real background-task notification.
* **The false wording already changed the agent's behaviour once.** At 02:20:26Z (F4's turn) the agent wrote "First I'll stop this pane's inbox watcher, so it can't wake the session in the middle of the wait like last time". Stopping it produced task-notification `bn0eki9vx` at 02:20:33Z. On a deferred path, that record counts as a new prompt (`hf_new_prompt_since` @e667:4456-4469) and holds the recycle. So the misattribution is not only cosmetic.

## 4. Objections to the proposed fixes

* **Fix 1 (`HF_CC_WHY`): the mechanism cannot work as written.**
  * Every call site captures the read through command substitution:
    * `c="$(composer_content …)"` @HEAD:4211, 4681, 4689;
    * `rcy_cg_c="$(recycle_composer_gate …)"` @HEAD:17585, 17588, 17924.
  * A variable exported inside `$( … )` never reaches the caller. The reason has to travel as a distinct exit code through `recycle_composer_gate` (which maps every UNKNOWN to rc 2 today), or through a side file.
  * The proposed test counts the probe "via HF_SLEEP calls", but `recycle_composer_gate` sleeps with a hard-coded `/bin/sleep` (@HEAD:4217). The suite also already sets `CC_RECYCLE_DRAFT_WAIT=2`, so 180 s against a short probe is invisible. Count the `session read` calls in the `hf_bounded` stub instead, or raise DRAFT_WAIT and bound the wall time.
  * The assertion "no deferral, OR the child holds within the probe" is weak; only the class assertion makes the test RED.
  * Use a field shape as the fixture: the real 2.1.291 capture with `HF_COMPOSER_SLASH_MENU=off`, or menu-below. A `❯ 1. Exit and stop tasks` dialog at rest has no field case.
  * Safety: the change only adds holds and never types. One cost: a transient dialog mid-turn (a permission prompt on a parallel tool call) would now hold at once instead of deferring. That costs liveness, not safety.
* **Fix 2 (screen capture): safe, and its test is RED before the fix.**
  * Reuse the existing `~/.claude/logs/composer-snapshots/` facility (`scripts/lib/lr-composer-snapshot.sh`) rather than adding a format.
  * The screen can hold an operator's draft, so keep it at mode 0600 and bounded.
* **Fix 3 (wording): half its test passes before the fix.**
  * The wake mail goes out as `hf_bounded "${CC_NOTIFY_BIN…}" --from recycle-watcher …` (@HEAD:4422). In `tests/handoff-recycle-turn-wait.bats` the `hf_bounded` stub returns 1 for anything that is not `session read|send`, and logs nothing; `CC_NOTIFY_BIN` points at a missing file. So no `NOTIFY:` line ever appears, and "the NOTIFY line does not contain …" passes on HEAD.
  * Assert instead on the ticket JSON `.why` (written by `jq` in `hf_recycle_retry_ticket`, which is extracted into the suite), and extend the stub to log the mail text.
* **Fix 4 (self-lane last-moment re-read): needed, and more valuable than the slot argues (§3).**
  * The "no `SEND:/exit`" assertion passes before the fix: with `recycle_fire_commit` stubbed, nothing can type `/exit`. Assert instead that the stub's marker was **not** reached, plus the hold class.
  * The block lives in `recycle_fire_armed` (@HEAD:17686), which this suite stubs out whole. The test needs the pattern from `tests/handoff-recycle-expect-probe.bats:266`, which evals `recycle_fire_armed`.
  * Use the deferral epoch `t0` rather than the turn-ended epoch. It is more conservative and matches `recycle_turn_wait`.
  * Safety: holds only. Nothing in `recycle_fire_armed` or `recycle_fire_commit` mails the pane before /exit (measured: grep for notify returns nothing), so the check cannot trip on the rail's own mail.
* **Fix 5 (port the exemption to `lr-fire-resume.sh`): do not port 0584f0720's rule.** It is the fail-open in §2 item 3. Port fb63f154e's narrowed rule, or nothing.
  * The exit-residue doc says lr-fire-resume reads a resume prompt it typed and "never types a slash command", so the port has no field case.
  * The "settle menu-below with a real capture" step is partly done: the 2.1.291 capture shows the menu above in a wide pane.
  * Any further capture must come from a throwaway CC pane, never a live session.
* **Missing from the fix list:**
  * land or review `fb63f154e`;
  * an UNKNOWN read straight after our own `/exit` should be treated as receipted residue at the next gate, instead of deferring. Without that, the F3 sequence recurs at HEAD for every shape in §2 item 4.

## 5. Tests run (measured)

* `bats tests/handoff-recycle-turn-wait.bats`: plan `1..14`, 14 ok, exit 0. The suite has no case where a static UNKNOWN persists after the turn ends; the slot's observation stands.

## 6. What would change these verdicts

* **Claim 1, down:** a capture of pane 134 between 01:20 and 01:24Z with no `❯ /` row above the box, or evidence that pane 134's box was cleared and refilled between 00:25Z and 02:20Z.
* **Claim 1, up (to about 95%):** a 2.1.293 capture at pane 134's geometry with `/exit` typed, taken in a throwaway pane.
* **Claim 2, down:** evidence that CC queues, rather than executes, an `/exit` typed during a turn the operator has just submitted.
