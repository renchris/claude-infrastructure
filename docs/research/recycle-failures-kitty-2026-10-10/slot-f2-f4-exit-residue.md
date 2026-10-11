# Slot F2 + F4 (pane 134): the unreadable /exit read-back, the DELs that were claimed but never sent, and the /exit left in the box

Read-only research. Nothing was typed into, sent to or signalled in any pane or process. Reads used: `kitty @ ls`, `it2 session read -s 134 -n 14` (no `--ansi`, no send), `ps`, `stty -f <tty> size` (a TIOCGWINSZ read). Scratch work is under `/tmp/f2f4/` (harness, fixtures, results). It is ephemeral, and every result is reproduced below.

Live sha per failure (from the brief, and checked here): F2 ran e667558fc. F4 ran b68fa8a25. `cmp` shows `scripts/handoff-fire.sh` is byte-identical at 0584f0720 and b68fa8a25, and at 1b2b93357 and e667558fc (measured: `cmp` of `git show <sha>:scripts/handoff-fire.sh`).

## Verdict

**The lead hypothesis is CONFIRMED. Conviction 88%.** Two points are refined, and two residual gaps are new.

| Claim in the hypothesis | Verdict | Strongest evidence |
|---|---|---|
| At e667, the "❯ /exit …" suggestion row above the box was read as a dialog, so composer_content returned UNKNOWN and the read-back was `<unreadable>` | Confirmed on fixtures; consistent in the field. No screen of 134 was captured at 00:25Z | §1 table. The F3 idle-window UNKNOWN (§2). F4 read `/exit` once the parser was fixed |
| hf_exit_readback sent NO DELs | Confirmed (code) | `hf_exit_readback` @e667558fc:3331-3333: DELs only in `*/exit)` |
| The hold message hard-coded "five DELs sent" | Confirmed (code + transcript) | @e667558fc:17368; transcript line 2831 |
| No residue receipt was written | Confirmed | No `composer_residue_record` in hf_exit_readback @e667; `~/.claude/logs/composer-residue/` has no `134` file |
| The /exit sat in the box from 00:25Z until at least 02:23Z | Confirmed. It was removed between 02:23:56Z and 02:26:49Z, most likely by the operator | §2 timeline |
| At F4, with 0584f0720 live, the gate read `/exit` and refused it as a draft because no receipt existed | Confirmed | handoffs.jsonl 02:23:36Z `recycle-held-draft … over '/exit'`; §4 simulation |

Refinements:

- **The F2 false claim did harm.** The session repeated it to the operator at 00:25:53Z: "it removed what it had typed". It then explained F3 wrongly as "the inbox watcher woke this session mid-wait". The timestamps refute that: the hold was at 01:24:32Z and the wake at 01:24:41Z.
- **Pane 134's claude does run under `expect`** (reso-resume-one). However, the reso lesson (a shell command typed into a live composer) did NOT recur. See §5.

New residual gaps at HEAD, in §6:

- The slash-menu exemption covers only the menu drawn ABOVE the box, in the 24-row path.
- A menu drawn BELOW the box, a pointer followed by U+00A0, or a tall box with the menu above all still read UNKNOWN. In each of those cases the HEAD receipt can never match, so the /exit strands again.

---

## 1. composer_content at e667558fc vs HEAD on a slash-menu screen (measured)

**Method.** `/tmp/f2f4/harness.sh <hf copy> <fixture>` evals `composer_content()` extracted with `sed -n '/^composer_content() {/,/^}/p'` from `git show <sha>:scripts/handoff-fire.sh`. It stubs `hf_bounded` to serve `tail -n N <fixture>`, honouring `-n` as bin/it2-kitty does, and prints `rc=<n> [content]`.

**Fixtures.** `/tmp/f2f4/gen/mkfx.py` builds them from three sources:

- the pane-168 layout pinned in tests/composer-tall-readback.bats (`[RED] the SLASH-COMMAND menu above a narrow box…`);
- pane 134's real footer;
- its real box, read live at 02:31Z: `❯ ` plus U+00A0 between two `─` rules, with footer rows `(1) #134 6defb493 47% · wt-pool-7 …` and `⏵⏵ auto mode on · 1 shell`.

The menu rows are `  ❯ /exit          Exit the CLI` followed by wrapped `/export` and `/extra-usage` rows. `bats-168` is the bats test's own screen, unchanged.

Results (measured, `/tmp/f2f4/results.txt`):

| fixture | e667558fc (F2's code) | HEAD b68fa8a25 (F4's code) |
|---|---|---|
| bats-168 (38-col pane 168 screen) | rc=1 [] UNKNOWN | rc=0 [/exit] |
| w30/w37/w38/w45/w57/w80, menu ABOVE | rc=1 UNKNOWN (all 6) | rc=0 [/exit] (all 6) |
| w30…w80, menu BELOW the box | rc=1 UNKNOWN (all 6) | **rc=1 UNKNOWN (all 6)** |
| w30…w80, no menu | rc=0 [/exit] | rc=0 [/exit] |
| w37 above, `/clear` and `/goal` | rc=1 UNKNOWN | rc=0 [/clear], [/goal] |
| w37 above, pointer `❯`+U+00A0 instead of space | rc=1 UNKNOWN | **rc=1 UNKNOWN** |
| w37 above, real dialog row `❯ 1. Exit and stop tasks` (control) | rc=1 | rc=1 (guard kept) |
| w37 above, synthetic dialog option starting with "/" (`❯ /Users/x/proj`) | rc=1 | **rc=0 [/exit] (fail-open on a hypothetical dialog)** |
| tall `/goal …` box (top border outside 24 rows) + menu above | rc=1 | **rc=1 UNKNOWN** (tall path selector @b68fa8a25:4141 has no exemption) |
| 15 real modal/composer fixtures in tests/fixtures/lr-recon/screens | — | 0 verdict flips vs e667 (measured, same harness) |
| resume picker with its `❯` row edited to `❯ /goal ship…` | rc=1 | rc=1 (stays UNKNOWN, for its non-box shape) |

**Mechanism at e667.** `selector()` @e667558fc:4068-4071 matches any `❯` at indent 1-4. The loop `for (i = 1; i < b2; i++) if (selector(line[i])) exit 9` @e667558fc:4078 turns the suggestion row into "a dialog drawn ABOVE a live composer", which is UNKNOWN. `hf_exit_readback` @e667558fc:3323 maps UNKNOWN to `HF_EXIT_RB_TEXT="<unreadable>"` on all 3 reads (0.5 s apart).

**HEAD.** `selector()` @b68fa8a25:4074-4085 returns 0 when the text after `❯` starts with `/` (kill switch `HF_COMPOSER_SLASH_MENU=off`).

Suite run (measured): `bats tests/composer-tall-readback.bats` prints `1..21` with 21 `ok` and 0 `not ok` (exit 0).

## 2. What pane 134's box held between 00:25Z and 02:23Z, and who touched it

Sources:

- handoffs.jsonl (live; the 13-row evidence copy is identical for 134);
- session transcript `~/.claude-next/projects/-Users-chrisren-Development--worktrees-wt-pool-7/6defb493-….jsonl`, lines 2825-3052;
- `~/.claude/logs/bash-commands.log`;
- `~/.claude/run/pane-successor/`.

| UTC | Source | Event |
|---|---|---|
| 00:25:25 | transcript | Session runs `handoff-fire.sh --recycle` from its own Bash tool (a self-recycle, mid-turn) |
| 00:25:42 | handoffs.jsonl | `recycle-successor-staged` for ttys032, watcher 29108. The pre-/exit composer gate passed, so the box was proven readable and EMPTY |
| ~00:25:45 | inferred | `/exit` typed with no CR (`hf_exit_readback` @e667:3320) |
| 00:25:47 | handoffs.jsonl | `recycle-held-exit-readback` "the /exit read back as '<unreadable>'; unconfirm rc n/a" |
| 00:25:47 | stat | `~/.claude/run/pane-successor/ttys032.revoked` ctime **2026-10-10T19:25:47-0500 = 00:25:47Z**, so the stage was revoked in the same second (measured: `stat -f %Sc`) |
| 00:25:47.672 | transcript L2831 tool_result | "`!! recycle ABORTED before /exit (held: exit-readback): the composer read back '<unreadable>', not '/exit' — five DELs sent to take our /exit back out — /exit NOT submitted, watcher disarmed …`", plus "`→ resume-debt abandon: rc 0`" |
| 00:25:53 | transcript (assistant) | "It couldn't confirm what was typed into this pane's input box, **so it removed what it had typed**". The false claim was relayed as fact |
| 00:25:57 to 01:20:16 | transcript | **No records at all**: no operator prompt, no tool call. An Enter on the box would have exited the session, and any typing would have shown up merged with the /exit in the next prompt. Neither happened |
| 01:20:16 | transcript | A background task-notification (cc-await-ping timeout) starts a turn. That is not composer input |
| 01:20:37 to 01:21:21 | transcript, events | F3: the recycle is deferred to the turn's end; the turn ends at 01:21:21.9 |
| 01:21:30 to 01:24:32 | handoffs.jsonl | F3 gate: **composer UNREADABLE for 180 s while the session was IDLE**. No transcript record falls between 01:21:21.9 and 01:24:41.8. On e667 code, an idle box holding a plain `/exit` reads `/exit` (fixture w*-none). UNKNOWN for 180 s needs a selector-shaped `❯` row on screen, which fits the suggestion menu still rendering under the residual `/exit` |
| 01:24:41 | transcript | The next task-notification turn, 9 s **after** the hold. The session's "the inbox watcher woke this session mid-wait" (01:24:47) is refuted |
| 01:48 | brief | 0584f0720 goes live |
| 02:20:33 to 02:23:36 | handoffs.jsonl | F4 on HEAD code: `recycle-held-draft … over '/exit'; the box is untouched` |
| 02:23:45 | transcript | Session: "a failed restart attempt left the text `/exit` sitting in this pane's input box … Please delete it" |
| 02:26:49 | transcript | Operator prompt starts with `"Heads-up: …`, with no `/exit` prefix, so the box had been emptied before typing |
| ~02:31 | it2 read (measured) | Box reads `❯ ` (empty). kitty `@ ls`: 134 = 57 cols x 62 lines; `stty -f /dev/ttys035 size` = `62 57` |

Nothing other than F2 typed into the pane, and nothing cleared it before about 02:24Z:

- `bash-commands.log` 00:00-02:59Z has no `send`, `send-text` or `-s 134` write to pane 134. The only hits are reads.
- `bin/cc-notify` never types; its comments at :37 and :197 say the `session send` transport is gone.
- F3 printed "Nothing was typed". F4 typed nothing (held-draft).
- `cc-await-ping --stand-down` signals watcher pids; it does not type.
- The only removal is the operator's, between 02:23:56Z and 02:26:49Z (estimated from the prompt text, not observed).

The pane width at 00:25Z is unrecorded. The brief says 37, and it measures 57 now. This does not matter here: e667 read UNKNOWN at every tested width from 30 to 80 with the menu above.

## 3. Why nothing verified the removal (Q3)

At e667 and still at HEAD, the exit-readback hold path has **no post-hold re-read**:

1. `hf_exit_readback` @b68fa8a25:3316-3341 returns 1 right after its `case`. The `*/exit)` arm sends five DELs and does not read back. The `*)` arm, new at HEAD, only writes a receipt.
2. `recycle_fire_commit` @b68fa8a25:17379-17383 abandons the resume debt and calls `hf_recycle_hold`.
3. `hf_recycle_hold` @:3199-3205 unconfirms, disarms (kills the watcher), emits one row, prints one line and exits 1.

No retry ticket is written on this path, and the watcher is dead. Its 60/150/300 nudges at :10244, :10280 and :10315, which would act on a box reading exactly `/exit`, cannot run.

At e667 the only output was the false "five DELs sent" text (@e667558fc:17368). HEAD replaces it with `HF_EXIT_RB_UNDO`, which says "no DELs sent (the read did not end in /exit)" (@b68fa8a25:3331, :17382). That is true. It still does not say that our `/exit` is probably still in the box and is receipted for the next gate. A reader can still infer "box clean".

Removal is left entirely to the next recycle's gate (§4). Nothing schedules that gate.

## 4. F4 traced again at HEAD (Q4)

**With a HEAD receipt.** Had F2 run on HEAD, the `*)` arm @b68fa8a25:3335-3338 would have written `~/.claude/logs/composer-residue/134` = `<ts>\t/exit`. The key `id="${1##*:}"` equals `$SID` on kitty.

The next `recycle_composer_block` would then do this:

- read the box with the fast-path `composer_content` @:17571 and get `/exit` (menu above, fixed parser);
- match it with `composer_residue_is_ours` @:17572 and skip the 180 s wait;
- run `composer_scrub_verified` @:17598-17609, which sends Ctrl-U (`\x15`), re-reads, and succeeds only when the box reads EMPTY. That is read-back verified (§:4678-4704).

Simulated with HEAD's functions (measured, `/tmp/f2f4/scrub-sim.sh`):

- **Box clears after Ctrl-U:** receipt matches, gate reads `/exit`, `is_ours: yes`, `scrub_verified rc=0`, 1 key sent (`\025`). The recycle proceeds.
- **Box never clears:** 12 rounds (24 keys: Ctrl-U plus DEL), then rc=1, then `recycle-held-draft "own-residue scrub FAILED"`. The loop is bounded and refuses.
- **The same receipt on e667's parser:** gate read rc=1, `is_ours: no`, `scrub_verified rc=2`, nothing sent. On F2-era code a receipt alone would not have helped.

Caveat (unmeasured): whether Ctrl-U clears the line while CC's suggestion menu is open. The scrub's read-back makes a wrong guess safe (it holds) but not successful.

**Actual F4.** No receipt existed, measured by `ls ~/.claude/logs/composer-residue/`: files exist for 137, 175, 176, 2, 202, 203, 25, 70, and none for 134. So `/exit` was treated as somebody's draft. The carry arm declined ("only a transplanted remote recycle carries the prompt box"), and `recycle-held-draft` was correct by design (@b68fa8a25:17677).

**Is a lone `/exit` submit-dangerous? Yes.** After the hold:

- the stage was revoked (ttys032.revoked, ctime 00:25:47Z);
- watcher 29108 was killed by `hf_recycle_disarm` @:3027-3031. `cc_pane_successor_take` would refuse anyway, because it needs a live watcher with a matching lstart (lib/pane-successor.sh:150-158);
- the resume debt was abandoned (transcript: "resume-debt abandon: rc 0").

If anyone had pressed Enter, CC would have run /exit, and claude would exit 0 through cc-close-attrib, then expect, then reso-resume-one. There, `rr_close_on_clean_exit` (~/.reso/bin/reso-resume-one ~960-985) closes the pane on rc 0 when `cc_pane_recycle_pending` finds no live recycle lock (lib/pane-recycle-pending.sh:27-55), and the hold had released that lock. So **the kitty window would most likely have closed, with no successor and no open debt** (estimated from code; not exercised).

The successor was correctly revoked, so no stale relaunch could fire. The risk is losing the pane, not a wrong relaunch.

## 5. Is this the reso expect-wrapper lesson recurring? (Q5) — No

Pane 134's foreground processes (measured, `kitty @ ls`, `ps`):

- the root is `zsh -ic 'env CC_ADMIT_DONE=1 reso-resume-one next …wt-pool-7 6defb493…'` (pid 18273, ttys032, started 2026-10-09 05:12:38Z, about 9 minutes after F1 stranded pane 44);
- `bash reso-resume-one` (18794);
- `expect -c …` (19771);
- `cc-close-attrib … ~/.claude-293/…/claude` (19783), on inner pty **ttys035**.

So claude IS under expect, on its own pty. Pane 168 is the same shape under lr-fire-resume.

The lesson's defect was a `ps -t <window tty>` probe that missed claude and typed a **shell command** into a live composer. In F2 the recycle correctly saw a live CC and typed `/exit`, the intended keystroke. It failed only on the read-back parse.

Expect is not implicated in the rendering either:

- reso-resume-one forwards SIGWINCH (comment at :810);
- the inner and outer pty sizes agree (`62 57` on both, measured);
- expect's scripted `send`s (:850-861) fire only on startup dialogs before `interact`.

## 6. Is the slash-menu fix complete? (Q6) — Not entirely

1. **Menu BELOW the box: still UNKNOWN at HEAD.** In the `gb` rule @b68fa8a25:4086/4088, any `❯` under the last border is a dialog, and it has no slash exemption. If CC 2.1.293 draws the menu below in any geometry, the HEAD flow is: read-back UNKNOWN, then receipt `/exit`, then hold. Every later gate also reads UNKNOWN, `is_ours` never matches, and the /exit strands exactly as in F2/F4, only now as `held-unreachable`. Where CC draws the menu (above or below) as a function of rows and columns is **unmeasured**. The field evidence is pane 168 at 38 cols and pane 134 at F4, both consistent with ABOVE.
2. **Pointer plus U+00A0: UNKNOWN.** `sub(/^ +/, "", r)` strips ASCII spaces only, and the composer's own prompt uses `❯`+U+00A0. The field proofs (168 recovered; 134 read `/exit` at F4) suggest the menu pointer uses an ASCII space on 2.1.293, but no raw capture was taken.
3. **Tall path:** `selector()` @b68fa8a25:4141-4144 (the rc 8 widened read, check (vi)) has no exemption. A long `/goal …` box with the menu above reads UNKNOWN (measured). Whether CC shows the menu once arguments follow the command is unmeasured.
4. **Sibling copies.** None were patched, and only one needed it:
   - `scripts/lib/cc-tui.sh` (`cc_tui_composer_rows` :186-205) and `scripts/lib/lr-composer-snapshot.sh` (`lcs_draft_rows` :52-58) never had rules (v) and (vi). They read `/exit` with the menu above, with it below, **and with a real dialog above** (measured: rc 0 `/exit` on all three fixtures).
   - `scripts/limit-recover/lr-fire-resume.sh` LR_SCREEN_SH has the same unexempted selector at :854 and :878. That only matters if a resume prompt starts with `/`.
   - `lr-upgrade.sh` `lru_clear_own_exit` (:2172-2187) scrubs any box reading exactly `/exit` **without a receipt**, via cc_tui_composer. Its attribution policy is inconsistent with handoff-fire's receipt-only rule.
5. **New fail-open edge (theoretical).** A real dialog whose highlighted option text starts with `/` (for example a path) drawn above a live box now reads as the box (fixture `w37-above-slashpath-dialog` gives rc 0). No such CC dialog is known. The resume picker stays UNKNOWN for its non-box shape.

## Conviction and what would change it

Overall 88%. By part:

- the code path, no-DELs, the false message and no receipt: 97-99%;
- the box held F2's /exit through F4: 95%;
- the specific trigger at 00:25Z being the suggestion row ABOVE the box: about 85%. It is inferred from same-version pane 168, the F3 idle UNKNOWN and F4's `/exit` read; no 134 screen exists from 00:25Z.

It would drop below 70% if a PTY or scratch-pane capture of CC 2.1.293 at 37-57 x 62 showed the menu drawn BELOW the box. HEAD would then not have read `/exit` at F4, and the F4 read would need another explanation. It would also drop if a capture showed no `❯` pointer on suggestion rows.

It would rise to about 97% with a capture of a 2.1.293 pane after typing `/exit` at 37 and 57 columns (throwaway pane only).
