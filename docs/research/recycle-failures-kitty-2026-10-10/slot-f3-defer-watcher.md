# Slot F3: pane 134, 2026-10-11 01:20-01:24Z. The deferred self-recycle that held "composer UNREADABLE for 180s", and the cc-await-ping watcher

Read-only research. Live sha for F3: `1b2b93357`. Its `scripts/handoff-fire.sh` is byte-identical to `e667558fc` (measured: `cmp` of the two `git show` blobs reported IDENT). Line numbers below are `@e667558fc` unless they say `@HEAD` (`b68fa8a25`).

## Verdict

**The lead hypothesis is CONFIRMED in its core, with one correction.**

* **Confirmed.** F3 was not a mid-turn problem. Here is the chain:
  1. F2 (00:25Z) typed `/exit`. Its read-back was `<unreadable>`, so it sent no DELs and left no residue receipt, and the `/exit` stayed in the box.
  2. With that text in the box, the slash-command suggestion row `❯ /exit … Exit the CLI` sat above the box. `composer_content` at the live sha read that row as a dialog option, which gives rc 1 (UNKNOWN). It did so on every poll: during the 30 s first look inside the tool call, and through the whole 180 s gate after the turn had ended.
  3. The self-recycle path treats "UNKNOWN on a self-recycle inside a tool call" as "mid-turn". It deferred, the turn-end detector correctly fired 16 s later, and the gate then spent 180 s on a screen whose unreadability had nothing to do with the turn.
* **Refuted.** The watcher did NOT complete and start a turn during the 180 s window. CC was idle for the whole window. cc-await-ping `bj0akekfz` completed at 01:24:41.8Z, 9 s AFTER the hold (01:24:32Z). It was woken by the hold's own `RECYCLE-HELD` wake mail. The watcher was how the hold got delivered; it did not cause the failure. The session's own explanation at 01:24:47Z ("the inbox watcher woke this session mid-wait") is a misattribution. The rail's false wording led the agent to it (see §5).

Conviction: **85%**.

## 1. What the deferral treats as "mid-turn" and what "turn ended" means (code @e667558fc; unchanged at HEAD except for line drift)

* **The deferral trigger, `recycle_composer_block` (17539).**
  * For a self-recycle that `hf_recycle_defer_eligible` accepts, the gate gets a short first look: `rcy_cg_first=${CC_RECYCLE_TURN_WAIT_PROBE_S:-30}` (17567).
  * If `recycle_composer_gate` returns rc 2 (UNKNOWN on every poll, 4194-4216), the block calls `hf_recycle_defer "$tty"` (17597-17602).
* **Eligibility, `hf_recycle_defer_eligible` (4518).** The deferral is allowed when all of these hold:
  * the kill switch `CC_RECYCLE_TURN_WAIT` is not off;
  * the run is not already the deferred child;
  * it is not a remote recycle and not resume mode;
  * `hf_invoking_call_pid` finds the tool call that is running it.
* **So the "mid-turn" signal is only this:** a self-recycle, run from its own tool call, whose composer read UNKNOWN for 30 s.
  * It never reads the transcript and never classifies why the read is UNKNOWN.
  * Being inside its own tool call is always true for a self-recycle, so "mid-turn" is true by construction. What is assumed, and never checked, is that the turn **caused** the unreadable read.
  * The row text says so outright: `"composer unreadable mid-turn on a self-recycle"` (4593).
* **What "turn ended" means, `recycle_turn_wait` (4478-4516), rc 0.** Two things must hold, polled every 3 s:
  * (a) the caller pid has exited (`kill -0` fails);
  * (b) `hf_transcript_at_rest` returns 0 (2655), meaning the last main-thread user/assistant record is an assistant `end_turn`, an api-error, or a stale task-notification, with trailing local-command triples skipped.
* Both must stay true for a settle window of `CC_RECYCLE_TURN_SETTLE_S:-10` s. A new non-meta user prompt since t0 (`hf_new_prompt_since`, 4456) gives rc 3 (held-new-prompt). The composer box is consulted only when the transcript is unreadable (4499).
* **"Turn ended" is a transcript stop_reason plus quiescence test.** It is not a screen test. Nothing after it asks whether the screen still looks the same as when the read was UNKNOWN.
* **What the deferred child runs after rc 0: `recycle_fire_gated`, i.e. `recycle_composer_block` again.**
  * Now `RCY_DEFERRED=1`, so it is no longer eligible and gets the full `CC_RECYCLE_DRAFT_WAIT:-180` s.
  * rc 2 then leads to `rcy_composer_unreadable gate` (4421-4433), which emits `recycle-held-unreachable` "composer UNREADABLE for 180s".
  * Then comes `hf_recycle_retry_ticket … "the composer could not be read while the turn was running"` (17606).

## 2. Timeline 00:25-02:23Z

Sources:
* (T) the transcript `~/.claude-next/projects/-Users-chrisren-Development--worktrees-wt-pool-7/6defb493-….jsonl`, lines 2825-2910, read with `jq`;
* (E) `~/.claude/logs/handoffs.jsonl`, filtered to `target_pane=="134"`;
* (D) the defer log `handoff-recycle-defer-134-nqgVri`;
* (W) the watcher output `/private/tmp/claude-501/…/tasks/bj0akekfz.output`.

| UTC | source | event |
|---|---|---|
| 00:25:25 | T | the F2 recycle tool call starts (inside a turn) |
| 00:25:30 to 00:25:42 | E | F2 `recycle-intent` (00:25:30), then `recycle-successor-staged` (00:25:42). To reach /exit, F2 passed the composer gate and the freshness re-read, so **the composer read EMPTY twice inside the tool call, mid-turn, at this sha, on this pane.** |
| 00:25:47 | E | F2 `recycle-held-exit-readback` "the /exit read back as '<unreadable>'". At e667558fc, `hf_exit_readback` (3316-3336) sends DELs only when the text ends in `/exit`. `<unreadable>` does not, so **nothing was removed**, and no `composer_residue_record` existed on that path (it was added by 0584f0720). |
| 00:25:53 | T | end_turn. The agent was told that the rail "removed what it had typed" (false). |
| 00:25:57 to 01:20:16 | T | **no records**. The session was idle for 54 min with `/exit` in the box. |
| 01:20:16 | T | task-notification: the earlier watcher `br2y6u2nv` failed (verdict=timeout). A turn starts. |
| 01:20:25 | T | the agent re-arms `cc-await-ping --timeout 3300 --interval 15` as background task `bj0akekfz` |
| 01:20:27 / 01:20:32 | T | end_turn. The Stop hook "FREE WIN … recycle" (isMeta) continues the turn. |
| 01:20:37 | T | Bash `handoff-fire.sh --recycle …` (the F3 call) |
| 01:20:43 | E | `recycle-intent` (phases `gates@1s kitty-probe@1s self-id@1s intent@6s`: kitty answered) |
| 01:20:43 to 01:21:14 | E | 30 s first look, UNKNOWN on every poll |
| 01:21:14 | E | `recycle-deferred-turn`, waiter pid 20340 |
| 01:21:15 | T | tool result: "recycle DEFERRED … END YOUR TURN NOW" |
| 01:21:16.8 | T | assistant end_turn |
| 01:21:21.9 | T | `stop_hook_summary`, `turn_duration`. **The turn is over** (no Stop feedback; a watcher was already armed, so the WAKE FLOOR stayed silent). |
| 01:21:30 | E, D | `recycle-turn-ended` "the turn ended 16s after the call". The arithmetic fits: the caller exited around 01:21:15, then the 10 s settle at 3 s polls. |
| 01:21:30 to 01:24:32 | T | **zero transcript records. CC idle for the entire 180 s gate.** |
| 01:24:32 | E, D | `recycle-held-unreachable` "composer UNREADABLE for 180s". D: retry ticket attempt 1, "wake mail verdict=delivered". |
| 01:24:32 | W | `2026-10-10T20:24:32-0500 [recycle-watcher] RECYCLE-HELD: your self-recycle was held (the composer could not be read while the turn was running) …` then `cc-await-ping: verdict=ping key=134 elapsed=256s` |
| 01:24:41.8 | T | task-notification: `bj0akekfz` "completed (exit code 0)". A new turn starts. **This is 9 s after the hold.** |
| 01:24:47 | T | agent: "the inbox watcher woke this session mid-wait, so the turn wasn't over … I'm not starting another watcher". **False on both counts.** |
| 01:24:51 / 01:24:55 | T | Stop hook WAKE FLOOR blocks; the agent re-arms watcher `blf06ihwo` (3300 s) |
| 02:20:10 | T | `blf06ihwo` times out, which wakes the turn that runs F4 |
| 02:23:36 | E | F4 `recycle-held-draft` "… over '/exit'". At b68fa8a25 the same box now **parses**, and its content is exactly `/exit`. |

## 3. Why the composer read UNKNOWN: a one-change differential

* **What changed between F3 and F4.**
  * Between the F3 sha (e667558fc) and the F4 sha (b68fa8a25), `composer_content` changed in one way only: the slash-menu exemption in `selector()`. Measured: `diff` of the extracted functions from the two `git show` blobs.
  * The gate, block, defer and turn-wait functions are identical (the same diff printed nothing for them).
  * `git log e667558fc..b68fa8a25 -- scripts/handoff-fire.sh scripts/lib/cc-tui.sh bin/it2-kitty` lists only `0584f0720`.
* **What happened in between.** Nothing typed into pane 134 between F2 and F4: F3 typed nothing, and no user prompt in T submits `/exit`. So the `/exit` F4 read is F2's residue, still in place at F3.
* **Measured on synthetic screens.** I ran the extracted `composer_content` from each sha over hand-built 37-column screens, with a stub it2 that cats the file (`/tmp/f3scratch/run.sh`):

| screen shape | @e667558fc (F3 live) | @b68fa8a25 (F4 live / HEAD) |
|---|---|---|
| `/exit` in box, slash menu row `  ❯ /exit  Exit the CLI` **above** the box | rc 1 UNKNOWN | rc 0 `/exit` |
| `/exit` in box, the same menu **below** the box | rc 1 UNKNOWN | rc 1 UNKNOWN (the `gb` rule, 4074) |
| `/exit` in box, no menu | rc 0 `/exit` | rc 0 `/exit` |
| empty box under a `✻ Working…` line (mid-turn) | rc 0 empty | rc 0 empty |

* **What the field results imply.** F3 read UNKNOWN at rest and F4 read `/exit`. The only shape that gives both results is "menu above the box". This is exactly the 0584f0720 / lr-stranded-husk C7 defect (pane 168, 38 columns: `docs/research/lr-stranded-husk-2026-10-10/REPORT.md:837,848`).
* **Replication on 10-11 (E, measured with `jq` over handoffs.jsonl).** Every `recycle-held-unreachable` that day was on a pane that had just taken a pre-fix `recycle-held-exit-readback`:
  * pane 168: exit-readback at 00:47:22, then unreachable at 01:11:52, 01:24:27, 01:37:08 and 01:49:39; fixed code engaged at 02:00:10.
  * pane 134: exit-readback at 00:25:47, unreachable at 01:24:32.
  * pane 206: exit-readback at 01:24:00, then 12 s later intent, `recycle-deferred-turn` (01:24:45), `turn-ended` 18 s later (01:25:03), and `held-unreachable` (01:28:06). **This is the F3 sequence again on an independent pane.**
* **The deferral's success rate.** Since 2026-10-05 the store holds exactly 2 `recycle-deferred-turn` rows (panes 134 and 206), and both ended `held-unreachable` at rest. Measured: 0 of 2 deferrals reached /exit.
* **Precedent: the deferral was born from the same misdiagnosis.**
  * It was added by 4948721bc (2026-10-05 14:47 -0500) for reso pane 254.
  * 56 minutes later, a1434bb25 (15:43 -0500) says: "the deferral worked ('the turn ended after 27s'), and the composer gate then refused after 180 s … on a session at rest … [a labeled border]. That, not the running turn, is what refused the three recycles of that pane today."
  * The premise "while that call runs the pane often shows no composer box to read" (comment at 4440-4442) was never re-measured afterwards.
  * F2 at 00:25Z contradicts it on this pane: the box read EMPTY mid-turn.
  * Estimated from E: since 10-05 at least 15 self-form intents passed the composer gate (12 `successor-staged` plus 3 `held-exit-readback`), each read from inside its own tool call.

**Gap that lowers conviction.** No screen of pane 134 from 01:20-01:24Z exists:
* there is no composer-residue receipt for 134;
* the defer log and the gate record no screen.

Also, the pane measures **57x62 now** (`kitty @ ls`, measured), not the 37x62 the brief recorded, so the geometry at F3 time is unproven. Whether a 62-row pane opens the menu above the box rests on the F4 differential, not on a capture.

## 4. Q3: does the armed cc-await-ping watcher structurally conflict with a deferred self-recycle?

* **In F3: no.**
  * The watcher was armed (01:20:25) before the recycle, with a 3300 s timeout, and fired on mail only.
  * The only mail was the rail's own `RECYCLE-HELD` (W), sent after the hold.
  * F3 would have failed identically with no watcher: the residue alone decides it, and pane 206 shows the same sequence.
  * "Would it have failed anyway because of the `/exit` residue": **yes**. "Does the watcher independently break deferral": **not in this incident**.
* **Is there code that stands the watcher down before a deferred recycle?** No. `hf_recycle_defer` (4535-4598) does not touch `.watching` or the watcher task.
* **Should there be?** No.
  * Stopping the watcher completes its background task, and the harness then delivers a task-notification. That is a new prompt, so `hf_new_prompt_since` gives rc 3 (held-new-prompt), and the deferral holds itself.
  * The stop-if-watcher comment names this exact effect: "standing the watcher down first completes its task and wakes the session for a full turn" (`scripts/handoff-fire.sh:10526-10527@HEAD`).
  * Mail that wakes the watcher during the 300 s wait is genuinely new work, so holding on it is the right polarity (that is what `hf_new_prompt_since` is for).
* **The watcher at /exit time is already handled.**
  * The /exit raises the background-work dialog. The watcher's stop-if-watcher arm answers "Exit and stop tasks" when the jobs are watcher-only (`10533-10574@HEAD`).
  * F1 proves the self lane does this live: `recycle-bgwork-stopped-watcher … jobs=watcher shipland=no pids=38547; lane=self` (logs/handoffs-events.jsonl, 2026-10-09T04:55:51Z).
* **A real structural gap (not exercised by F3).** After `recycle_turn_wait` returns 0, nothing on the self lane re-checks the transcript or new prompts before /exit.
  * The last-moment at-rest re-read covers only same-account and focused-remote: `rcy_rest_tx` is set at `17950-17952@HEAD`.
  * So a ping, or the watcher's own 3300 s timeout, that wakes a turn between `turn-ended` and the /exit gets that turn interrupted by /exit.
  * The window is the gate's first read plus arming plus the freshness read. Estimated at about 10-16 s from F2's phases `tty@5s … detach@16s`.
  * Impact is bounded: cc-await-ping does not consume the mail (W: "nothing was consumed here"), so the successor's mailbox-drain renders it.
* **Goal-live session (estimated, not observed).** Session 6defb493 had no `/goal` in its last 400 lines (measured: grep count 0).
  * Under a live goal, an unmet evaluation blocks the deferring turn's Stop. Its feedback is isMeta, which is not a "new prompt", so the transcript stays in flight.
  * The likely outcome is `recycle-held-busy` at 300 s, not a stray /exit. Untested; it needs a fixture before anyone relies on it.
* **The WAKE FLOOR** (`hooks/session-continue.sh:625-900@HEAD`) has no abstain for "a deferred recycle is pending on this pane". In F3 it was moot: a watcher was armed, so it stayed silent at 01:21:21.
  * After the hold, it forced a re-arm at 01:24:51, which is correct: the session stays alive.
  * That re-armed watcher's timeout (02:20:10) is what woke the F4 turn.

## 5. Q4: is "composer unreadable means mid-turn" sound at HEAD?

**No.** At HEAD the inference is unchanged (`recycle_composer_block` 17553, `hf_recycle_defer` 4549, `rcy_composer_unreadable` 4435). 0584f0720 removed one cause of UNKNOWN; it did not change the inference. UNKNOWN (`exit 9`) at HEAD still lumps together several cases.

**Causes of UNKNOWN that are static, and would not clear at turn end:**
* a real dialog above the box (`❯ 1.` options), and the trust or resume pickers;
* a `❯` below the bottom border (the `gb` rule, 4088). This includes a slash menu drawn under the box: measured synthetic, still UNKNOWN at HEAD. Whether CC 2.1.293 draws it below in wider panes is unverified;
* a labeled border cut short by a narrower pane;
* a teammate panel `╭──╮`;
* a tall box rejected by (i)-(vi);
* an empty read of a tail-only box.

**Causes that could plausibly be turn-related or transient:**
* no box at all (an empty screen, or a box scrolled off);
* a read that returned nothing (kitty stalled).

**What goes wrong with each kind of cause:**
* For the static causes, the deferral spends up to 30 s + 16 s + 180 s and ends `held-unreachable` with a retry ticket whose re-run hits the same screen.
* The wording is then false in three places:
  * `recycle-deferred-turn` "composer unreadable mid-turn" (4607);
  * the foreground message "cannot be read while this tool call runs";
  * the child's ticket and wake mail "the composer could not be read while the turn was running" (17620@HEAD). The child runs after the turn has ended.
* That last string is what the agent read at 01:24:41. It is why it blamed the watcher and refused to re-arm (T, 01:24:47).
* Separately, the limit-recover copy of the locator still has the pre-0584f0720 `selector` (`scripts/limit-recover/lr-fire-resume.sh:854,878@HEAD`). The comment at handoff-fire `4119-4125@HEAD` says the two "carry the same rule", and they have drifted.

## 6. Fixes, ranked (none applied; read-only slot)

1. **Defer only on a turn-shaped UNKNOWN, and fail fast on a static one.**
   * Change: `composer_content` exports a reason (`HF_CC_WHY` = `noread|nobox|dialog-above|glyph-below|tall-rejected|tail-empty`).
   * `recycle_composer_block` defers only on `noread|nobox`.
   * The deferred child, if its first post-turn read gives the same static reason, holds after one short probe with a distinct class, e.g. `recycle-held-unreadable-static`, naming the shape. It no longer burns 180 s.
   * Where: `scripts/handoff-fire.sh` `composer_content` 4045, `recycle_composer_block` 17577-17620, `hf_recycle_defer` 4549.
   * Test: `tests/handoff-recycle-turn-wait.bats`, new case. SCREEN = a box with a `  ❯ 1. Exit and stop tasks` row above it, at rest, with a dead CALLER_PID and an end_turn transcript. Assert:
     * no `recycle-deferred-turn` row, or else the child holds within the probe (count `HF_SLEEP` calls);
     * the class names the static shape;
     * nothing is in SENT_LOG.
   * It is RED on HEAD, which defers and waits the full DRAFT_WAIT.
2. **Capture the screen on every `held-unreachable`.** Write the plain last ~30 rows, mode 0600, into the fire or defer log. F3 has no screen witness, and one capture would have made the diagnosis immediate.
   * Where: `rcy_composer_unreadable` 4435@HEAD.
   * Test: the same suite asserts that the log carries the fixture's rows.
3. **Make the deferred child's wording true.** When `RCY_DEFERRED=1`, say "after the turn ended" (reason string 17620@HEAD; row text 4607).
   * Test: assert that the ticket reason and the `NOTIFY:` line in EVENTS do not contain "while the turn was running" for the deferred child.
4. **Add a self-lane last-moment re-read.**
   * Where: `17950@HEAD`. When `RCY_DEFERRED=1`, set `rcy_rest_tx` to the deferring transcript, and add `hf_new_prompt_since <turn-ended epoch>`.
   * Test: stub `recycle_fire_commit`, append a `<task-notification>` user record to TX after `recycle-turn-ended`. Assert `recycle-held-busy` or `recycle-held-new-prompt`, and no `SEND:/exit`.
5. **Port the slash-menu exemption to `lr-fire-resume.sh` LR_SCREEN_SH (854, 878@HEAD), and settle the menu-below shape with a real capture before deciding the `gb` rule.**
   * Test: extend the `[RED] SLASH-COMMAND menu` case in `tests/composer-tall-readback.bats` to the LR_SCREEN_SH extraction that suite already does (line 213).

F3's specific cause (the menu above the box) is **already fixed by 0584f0720**, which has been live since 01:48Z.
* Its `composer_residue_record` on an unreadable read-back also stops new uncleared `/exit` residue.
* It cannot receipt residue left by pre-fix runs, so F4's held-draft over F2's `/exit` falls outside it (F4 slot).

## 7. Tests run (measured)

* `bats tests/handoff-recycle-turn-wait.bats`: plan `1..14`, 14 ok, exit 0.
* `bats tests/composer-tall-readback.bats`: plan `1..21`, 21 ok, exit 0.
* Neither suite has a case where an UNKNOWN persists, for a static reason, after the turn has ended. That is the F3 shape.

## 8. What would change the conviction (85%)

* **Down:**
  * a capture of pane 134 from 01:20-01:24Z showing no menu above the box, or a different UNKNOWN shape;
  * evidence that the box was cleared between 00:25 and 01:20 and refilled before 02:20;
  * a kitty read failure around 01:21-01:24 (the 01:20:43 probe answered, and 168's gate read in the same minutes).
* **Up:** a controlled read of a 57- or 37-column, 62-row pane with `/exit` typed (an operator-run probe; this slot may not type) showing the menu drawn above the box.
