# Skeptic review: slot f2-f4-exit-residue (pane 134: the `<unreadable>` read-back, the DELs that were never sent, the `/exit` left in the box)

Read-only. I typed into, sent to or signalled no pane or process. The reads I used:
- `kitty @ ls`;
- `it2 session read -s 134 -n 12` (02:57:51Z: the box reads `❯ ` and is empty);
- `ps`;
- `git show <sha>:…` into `/tmp/skf24/`;
- jq/python over the logs and transcripts.

Scratch files: my harness `/tmp/skf24/h/run.sh` (it stubs `hf_bounded` to `tail -n N <fixture>`) and the extracted parsers `/tmp/skf24/h/cc-<sha>.sh`.

## Bottom line

I tried to refute all three claims and could not. The mechanism is now backed by more than the slot's synthetic fixtures. It holds on **two real captures** and on a **fleet-wide before/after split** that the slot did not use. The slot did miss three things:

1. **The cause is a regression with a known onset.** It went live 39 minutes before F2.
2. **0584f0720's receipt arm has never run in the field and has no test.** The only field scrub ran on a receipt that a session wrote by hand.
3. **Fixes 1 and 5 rest on premises the evidence contradicts.** The menu is not drawn below the box at any measured width, and lr-upgrade's clear is not receipt-less "any box" scrubbing.

## New evidence the slot did not use

### E1. Onset of the regression (measured: shared-checkout reflog, `git merge-base --is-ancestor`, `grep` of each live blob)

| Live sha (reflog, UTC) | `selector(line[i])` loop (rule vi) / `gb` rule (v) present? |
|---|---|
| 4b3f73ade (10-10 23:39:28Z) | no / no |
| **41cc634df (10-10 23:46:32Z)** | **yes / yes**: first live sha that contains f14b42653 (vi) and 9e56493ec (v) |
| e667558fc (00:20:03Z), 1b2b93357 | yes / yes (`@e667558fc:4068-4072, 4078`) |
| 0584f0720 (01:48:30Z), b68fa8a25 | yes, plus a slash exemption above the box only (`@b68fa8a25:4074-4086, 4092`) |

Exit read-backs in `~/.claude/logs/handoffs.jsonl` (measured with python over the file):
- **Before the onset, same day:** panes 3 (12:18Z), 8 (15:17Z) and 7 (23:09Z) all submitted `/exit`. Each shows a bgwork row, a successor claim or engaged afterwards.
- **Between onset and fix (23:46Z to 01:48Z):** **4 of 4** exit read-backs held with `'<unreadable>'`. They were panes 134 (00:25:47Z), 168 (00:47:22Z), 206 (01:24:00Z) and 2 (01:28:24Z).
- **After the fix:** pane 168 (01:59Z) and pane 4 (115 columns, claude-293, 02:46:14Z bgwork dialog) both submitted.

One earlier hold had a different signature: pane 11 at 10-10 05:50:33Z read back `''`, not `<unreadable>`. It predates the rule and is unrelated.

### E2. Two real screens with `/exit` typed, replayed through three parsers (measured: `/tmp/skf24/h/run.sh`)

| Real capture | 4b3f73ade (pre-onset) | e667558fc (F2/F3) | b68fa8a25 (F4/HEAD) |
|---|---|---|---|
| Pane 168, 38 columns, claude **2.1.293**, menu ABOVE the box. Read 00:57:18Z by session 197b48ee (transcript `~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-lr-stranded-husk/197b48ee-….jsonl` line 2317). This is 10 minutes after 168's hold, so the menu **stays open while the residue sits there** | rc=0 `/exit` | **rc=1 UNKNOWN** | rc=0 `/exit` |
| Throwaway window 214, about 156 columns, claude **2.1.291** (`/opt/homebrew/bin/claude`, package.json 2.1.291), menu ABOVE the box. File `/tmp/slashprobe/exit-typed.ansi.txt`, captured at 01:33:50Z by session c1081576 (`bash-commands.log`) | rc=0 `/exit` | **rc=1 UNKNOWN** | rc=0 `/exit` |

In both captures the menu pointer is `❯` followed by an ASCII space (0x20), not U+00A0 (measured with `od -c`). Window 214's `after-del` capture shows that five DELs remove `/exit` and close the menu.

### E3. 0584f0720's receipt arm has never run, and nothing tests it

- **No hold has fired it.** Since 01:48Z there have been 0 `recycle-held-exit-readback` rows (handoffs.jsonl).
- **The one field scrub used a hand-written receipt.** At pane 168 (`recycle-residue-scrubbed`, 01:59:15Z) the receipt was **written by hand**. `bash-commands.log` at 01:58:25Z, session 197b48ee, shows `printf … "/exit" > ~/.claude/logs/composer-residue/168`.
- **No test covers it.** `grep -rn 'HF_EXIT_RB_UNDO\|no DELs sent' tests/` finds nothing. Custody test 7 (`tests/handoff-fire-recycle-custody.bats:628-646`) checks DEL counts for `/exi` and `/exitab`. It never checks the operator text or the receipt, which is why it passed at e667 while the hold printed "five DELs sent".

## Verdicts

### Claim 1: F2 was caused by the slash-menu row above the box matching selector() at e667. CONFIRMED, 90%

- **Code at the live sha.** `selector()` @e667558fc:4068-4071 matches any `❯` at indent 1-4. The loop @4078 exits 9. `hf_exit_readback` @3323 maps that to `<unreadable>`.
- **Pane 134 read EMPTY a few seconds before `/exit`.** The order is the freshness re-read @e667558fc:17905-17923, then `hf_succ_stage` @17980 (row `recycle-successor-staged` 00:25:42Z), then `recycle_fire_commit` @17983. So the only change between the empty read and the UNKNOWN read is the typed `/exit`.
- **E1 and E2 make the mechanism observed, not just inferred.** It holds on real 2.1.293 and 2.1.291 screens and in a 4-of-4 cluster that begins exactly at 41cc634df.
- **Still inferred:** no screen of pane 134 at 00:25Z exists.
- **Alternatives considered and rejected:**
  - *A kitty read failure:* rejected. The gate read fine seconds earlier, and the probe answered.
  - *A mid-turn render:* rejected. F3 read UNKNOWN while the session was idle (transcript has no records between 01:21:21.9Z and 01:24:41.8Z, measured).
  - *Menu drawn BELOW the box (the `gb` rule):* rejected. HEAD would then not have read `/exit` at F4, nor at 168 or pane 4.
- **Refinement:** the defect is a **regression introduced by f14b42653 (rule vi) and live from 23:46:32Z.** f14b42653 claimed "0 of 1,001 snapshots change". Its corpus had no screen with `/exit` typed, so the flip could not show.

### Claim 2: no DELs were sent, the "five DELs" text was hard-coded, and no receipt was written. CONFIRMED, 97%

- **Code.** @e667558fc:3331-3333 has DELs only in `*/exit)`. @17368 is the literal text.
- **Transcript.** Line 2831 (00:25:47.672Z) holds the full false line. Line 2835 (00:25:53Z) has "so it removed what it had typed".
- **No receipt.** `ls ~/.claude/logs/composer-residue/` shows no `134`.
- **Added harm the slot did not note:** the same 00:25:53Z message told the operator to "Type `/clear` in this pane". With `/exit` still in the box, that would have merged into `/exit/clear`.
- **"Already fixed" holds only in part. Two false sentences survive at HEAD:**
  - `hf_recycle_hold` @b68fa8a25:3203 still prints "recycle ABORTED **before /exit** … /exit NOT submitted", but `/exit` was typed.
  - The resume-debt abandon reason @b68fa8a25:17380 still says "nothing submitted, **session untouched**".
- Per E3, the new `HF_EXIT_RB_UNDO` text and the receipt are untested and have never run in the field.

### Claim 3: `/exit` stranded from 00:25:47Z until the operator removed it; F3 read UNKNOWN; F4 held it as a draft. CONFIRMED, 90% (the "already fixed" part: PLAUSIBLE)

**Direct evidence:**
- F4's row (02:23:36Z) shows a HEAD parse reading `over '/exit'`.
- The session's 02:23:45Z message says "left the text `/exit` sitting in this pane's input box … Please delete it".
- The operator's 02:26:49Z prompt (`origin.kind=human`) quotes that message and has no `/exit` prefix.
- The pane-168 capture (E2) shows the menu stays drawn while the residue sits, which explains F3's 180 s UNKNOWN at rest. Panes 168 and 206 repeat the F3 shape.
- **Pane 2 repeats F2→F4 independently:** exit-readback at 01:28:24Z (e667), then `recycle-held-draft … over '/exit'` at 02:26:12Z (HEAD).

**Inferred:**
- "Nothing else typed." `bash-commands.log` 00:25-02:27Z only covers commands run through the Bash tool. It shows no send to 134; the only sends went to window 214. it2-kitty keeps no send log.
- "The operator removed it."

**Two corrections to the slot's text:**
- **The submit danger needs a second keypress.** The session nearly always had a cc-await-ping background task running:
  - br2y6u2nv until 01:20:16Z;
  - bj0akekfz 01:20:25-01:24:41Z;
  - blf06ihwo 01:24:55-02:20:10Z;
  - bl6bj10jt from 02:23:42Z.

  With a task running, `/exit` raises the background-work dialog. That happened on this same session at F1 ("jobs=watcher") and on pane 4 at 02:46Z. So the most likely path is Enter, then the dialog default ("Exit and stop tasks"), then rc 0, then `rr_close_on_clean_exit` (`~/.reso/bin/reso-resume-one:967-990`) closes the pane, because the lock was released at the hold. That is estimated from code and not exercised. The danger is real, but it takes two keypresses outside short gaps.
- **"Ctrl-U clearing a box with the menu open has not been measured" is too strong.** The 168 scrub went from intent@11s to scrubbed at elapsed_s 14, about 3 s. That fits a single Ctrl-U round (estimated: each Ctrl-U+DEL fallback round costs about 1 s or more). Window 214 also shows five DELs clear it (measured capture).

**"Already fixed by 0584f0720" is only PLAUSIBLE:**
- The parse fix and the receipt-matched scrub are field-proven.
- The automatic receipt that makes the scrub reachable is not (E3).

## Objections to the proposed fixes

1. **Rank 1 (exempt slash rows BELOW the box, and accept ❯+NBSP): demote it. It is not safe to justify now.**
   - It loosens rule (v). That rule stops typing into a dialog drawn under an echoed composer-shaped prompt.
   - The loosening is for a shape no capture shows. Measured above with an ASCII space: 38 columns (2.1.293) and about 156 columns (2.1.291). HEAD also read `/exit` at 115 columns (pane 4, 2.1.293).
   - The slot already found the above-box exemption fails open on a `/`-led dialog option (`w37-above-slashpath-dialog`, reproduced: rc 0 at HEAD). Extending it below doubles that exposure.
   - Its tests would pin made-up layouts. Do it only after a real capture shows a below-box menu, for example on the remaining 2.1.284 install (1 process running, measured with `ps`).
2. **Rank 2 (post-hold re-read and scrub, honest text, retry ticket): keep it, but change it.**
   - (a) A `composer_content` re-read would not have helped F2: at e667 it stays UNKNOWN. At HEAD the F2 shape never holds. So (a) covers only transient unreadable reads. lr-upgrade already does this structurally: `lru_clear_own_exit` runs only when its own handoff-fire run held on `exit-readback` (`scripts/limit-recover/lr-upgrade.sh:2321, 2674`). Port that pattern, but read with the guarded parser so a Ctrl-U never lands in a real dialog.
   - (b) This is the highest-value part. Also fix "ABORTED before /exit" (@3203) and "session untouched" (@17380).
   - The retry ticket is bounded (`RETRY_MAX=3`, `hooks/boundary-handoff.sh:173`). It is still F3's 3×180 s churn with wake mail when the box does not parse, so write it only when the hold left a receipt that a parse could match.
   - Its tests are correctly red before the fix. Also add the missing assertions on the receipt and the text in custody test 7. Right now that test would pass a false message again.
3. **Rank 3 (tall-path and LR_SCREEN_SH exemption):** harmless but speculative. No evidence shows CC keeps the menu open once arguments follow a command. Low priority.
4. **Rank 4 (measure): half done already.**
   - The two real captures in E2 exist. `/tmp/slashprobe` is ephemeral, so copy both into `tests/fixtures/` now.
   - As written, the test would pass at HEAD by construction, so it proves nothing. Also assert e667558fc (or f14b42653) gives UNKNOWN on the same files, so the fixture is shown to tell the two parsers apart.
   - Probes must type without Enter and never accept a suggestion. A PTY probe that submitted `/model` persisted to the shared settings.json (lr-stranded-husk REPORT:818).
5. **Rank 5 (lr-upgrade attribution): the premise is wrong as stated.**
   - `lru_clear_own_exit` does not scrub "any box reading exactly `/exit`". Both call sites are gated on `HFE_HOLD=exit-readback` from the run it just made. That is the structural attribution the residue design allows at the mangle site (`@b68fa8a25:4706-4724`).
   - Requiring a receipt would add nothing for HEAD-era holds, and it would strand residue from older ones.
   - The valid part is the missing guards (v)/(vi) in `cc_tui_composer` (`scripts/lib/cc-tui.sh:186-205`). With a real dialog above a `/exit` box, it would send a Ctrl-U to the dialog.

## What would change these numbers

- **Claim 1 drops below 70%** if a capture of pane 134 or of a 2.1.293 pane at 37-57 columns showed no `❯` row after typing `/exit`, or showed the row below the box.
- **Claim 1 rises to about 97%** with a 2.1.293 capture at 57×62 that matches E2.
- **Claim 3 drops** given any logged write to pane 134 between 00:25Z and 02:20Z. Candidates are a launchd nudge or a carry putback; neither has a log I could find.

## Measurements run

- `bats tests/composer-tall-readback.bats` (hermetic: it sets HOME to a temp dir and sets `IT2_WRAPPER_NO_KITTY=1`): plan `1..21`, 21 ok, 0 not ok, exit 0.
- The slot's `/tmp/f2f4/harness.sh` gave the same results as the slot reported:
  - w37-above: e667 rc 1, HEAD rc 0;
  - w37-below: rc 1 on both;
  - tall-goal-menu-above: rc 1 on both;
  - slashpath-dialog: HEAD rc 0.
- `/tmp/f2f4/scrub-sim.sh`: HEAD is_ours yes, scrub rc 0, one `\025`; e667 is_ours no, rc 2. In this simulation the box clears after one Ctrl-U by construction.
