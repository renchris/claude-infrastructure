# Slot: the composer reader across widths and copies (a measurement)

Worktree HEAD b68fa8a25. Measured 2026-10-11 02:30-02:50Z. Read-only: nothing was typed into any
pane. The harness and corpus live in `/tmp/rsw/` (ephemeral; see §8 to regenerate). Every number
below is **measured** with a named command unless it is labelled *estimated*.

## 0. Answer

1. **F2 and F3 are one reader verdict, and 0584f0720 fixes it.** At e667558fc and 1b2b93357,
   `composer_content` returns UNKNOWN (rc 1) on every screen that has `/exit` (or `/e`) in the box
   and Claude Code's slash-command menu drawn above it. That holds at every width I tested (32, 37,
   38, 45 and 57 columns, plus a **real 2.1.293 capture taken live tonight from pane 2**). Its
   dialog-above rule reads the menu's highlighted row `  ❯ /exit   Exit the CLI` as a dialog option.
   The menu **stays open as long as `/exit` sits in the box, through later turns**: pane 2 still
   shows it more than an hour after its own held recycle. So once F2 left `/exit` in pane 134,
   every later read there was UNKNOWN. That covers F3's `recycle-deferred-turn` ("composer
   unreadable mid-turn") and its `recycle-held-unreachable` ("UNREADABLE for 180s"). At b68fa8a25
   the same screens read `/exit`.
2. **F4 is not a reader fault.** At b68fa8a25 the reader correctly returns `/exit`. The hold comes
   from attribution: F2 ran before 0584f0720, so no residue receipt was written (e667558fc sends
   DELs only when the read ENDS in `/exit`, and it writes no receipt). With no receipt,
   `composer_residue_is_ours 134 /exit` fails and `recycle_composer_block` holds the box as a draft.
   This **confirms the lead's hypothesis**. Pane 2 shows the whole F2→F4 sequence a second time,
   on the same code generations (§5).
3. **There are six reader copies, not three.** 0584f0720 patched one. The copies diverge on four
   axes. Two of the divergences can read **EMPTY where the human-correct verdict is UNKNOWN**, so
   keystrokes would go to a dialog:
   - (a) The cc-tui, lr-composer-snapshot, lr_recon/observe.py and it2-kitty copies have **no
     dialog guards at all**. They read EMPTY when a background-work dialog sits above an empty box,
     on both real 2.1.260 captures and the synthetic ones.
   - (b) **0584f0720's own exemption is too wide.** At HEAD, any `❯ /…` row at indent 1-4 above
     the box is exempt, whatever the box holds. A dialog whose highlighted option starts with `/`
     (synthetic: a path picker) now reads EMPTY, where e667558fc read UNKNOWN. I found no CC dialog
     that renders such an option, so this is latent.
4. **One residual false-UNKNOWN at HEAD.** A slash menu drawn BELOW the box trips the `gb` rule
   ("a ❯ under the last border is a dialog", handoff-fire.sh:4088), which 0584f0720 did not exempt.
   5 of 5 synthetic widths read UNKNOWN. I have **not** observed CC 2.1.293 drawing the menu below.
   Both real observations (pane 2 at 57x62, pane 168 at 38 columns) are above.

## 1. The copies (HEAD; hashes across the four failure shas)

I extracted each function at bc471e0b6, e667558fc, 1b2b93357 and b68fa8a25 and hashed it
(`/tmp/rsw/extract.sh`, md5). Only two copies changed in that window:

| # | Copy | Location @HEAD | Changed across F1..F4 shas? |
|---|---|---|---|
| A | `composer_content` | scripts/handoff-fire.sh:4045-4201 | yes: 72 lines @bc471e0b6 → 149 @e667558fc = @1b2b93357 → 157 @b68fa8a25 |
| B | `cc_tui_composer` / `_text` / `_rows` | scripts/lib/cc-tui.sh:158-235 | no (same md5 at all four) |
| C | `lcs_draft_rows` | scripts/lib/lr-composer-snapshot.sh:48-82 | no |
| D | `LR_SCREEN_SH` (bash program run by expect) | scripts/limit-recover/lr-fire-resume.sh:842-917 | 38 lines @bc471e0b6 → 76 @e667558fc, then unchanged |
| E | `composer_from_screen` | scripts/limit-recover/lr_recon/observe.py:359-378 | no |
| F | `composer_state` (close guard; different design) | bin/it2-kitty:883-1110 | no |

The brief listed three copies. D, E and F are also composer readers. cc-tui.sh:20-26 says its parse
is "pinned" to A by tests/cc-tui.bats. That parity test (tests/cc-tui.bats:530-557, and :712 for
D) compares only four screens: `empty draft nobox placeholder`. None of the divergences below can
turn it red.

## 2. Behavioural divergences at HEAD (from the code, then confirmed by the matrix in §4)

| Axis | A handoff-fire | B cc-tui | C lcs | D LR_SCREEN_SH | E observe.py | F it2-kitty |
|---|---|---|---|---|---|---|
| Read | `it2 session read -n 24 --ansi`, plain fallback (:4058-4059) | `kitty get-text --extent screen --ansi` (cc-tui.sh:191) | file | `it2 session read -n 24` **plain only** (:848) | `get-text --extent screen --ansi` | `get-text --ansi` |
| Border | 12-run **or labelled rule** (:4067-4071) | same | same | **12-run only** (:877, index) | **12-run only** (:368) | count ≥ max(20, cols/2) or `@token` label (:1027-1045) |
| `❯` under last border ⇒ UNKNOWN (`gb`) | yes (:4086-4088) | **no** | **no** | yes (:855) | **no** | n/a |
| Indented top border ⇒ UNKNOWN | yes (:4091) | **no** | **no** | yes | **no** | no |
| Dialog row above box ⇒ UNKNOWN | yes, **slash rows exempt** (:4074-4085, 4092) | **no** | **no** | yes, **no slash exemption** (:854, 878) plus a global `❯ N.` ⇒ MENU (:852) | **no** | **no** |
| Tall / capped box (bottom border, no top) | 200-row re-read with shape checks (:4129-4166); tail-only never EMPTY (:4198) | n/a (reads whole screen) | n/a | 200-row re-read (:873-896) | n/a | n/a |
| Faint (SGR 2) dropped | yes | yes | yes | **no** (plain read ⇒ faint suggestion = DRAFT) | yes | yes |
| `Try "…"` placeholder dropped | yes | yes | **no** (quoted as a row) | yes | yes | n/a (faint) |

## 3. Corpus

95 screens. Each has a plain `.txt`, plus an `.ansi` where one exists (`/tmp/rsw/fx/`).

- **Real, live tonight (read-only `it2 session read -n 62 [--ansi]`):** pane 2 (57c,
  **`/exit` + slash menu above**, CC 2.1.293), 134 (57c, empty; the brief's 37c was its width at
  failure time), 206 (30c), 11 and 124 (45c), 4 (115c), and 168 (57c). Pane 168 changed between my
  two reads: the 62-row capture shows a live tool-permission dialog `❯ 1. Yes`, so its expected
  verdict is UNKNOWN.
- **Real, from the repo:** goal-arm evidence `pane203-midturn-32col` (ansi+plain); composer-tall
  `pane203-tall-goal`, `capped-scrolled-2.1.293-46row`, `trust-dialog-18col`,
  `win527-teammate-panel`; all 15 `tests/fixtures/lr-recon/screens/*`; and the two real 2.1.260
  background-work-dialog-above-composer captures (`teammate-probe/captures/p1-run2*`).
- **Synthetic (`/tmp/rsw/genfx.py`):** escape styles copied byte-for-byte from the live pane-2
  ANSI capture: border `38:2:136:136:136`, box row `❯\xa0`, slash text `38:2:177:185:249`,
  highlighted menu row `22;1` bold, other menu rows grey `153`. Each state is rendered at
  32/37/38/45/57 columns with the footer cut to width:
  - S01 empty
  - S02 `/exit` + menu above
  - S03 `/exit` + menu **below** (hypothetical)
  - S04 `/e` + menu above
  - S05 one-line draft
  - S06 wrapped multi-line draft
  - S07 background-work dialog above an empty box
  - S08 mid-turn spinner, empty box
  - S09 mid-turn spinner + menu above + `/exit` (the F3 state)
  - S10 faint suggestion
  - S11 `/exit` with no menu
  - S12 dialog below the box
  - S13/S14 labelled top border (45/57)
  - S15 a dialog whose highlighted option starts with `/` (hypothetical path picker)

The real pane-2 screen (plain, rows 47-62 of the 62-row read) is the first real capture of this
shape anywhere on disk. `grep -rl "Exit the CLI"` over docs/, tests/, composer-snapshots/ and
composer-residue/ found only prose and the reconstructed 0584f0720 test.

```
  The recycle is still held on the /exit text sitting in

  ❯ /exit                 Exit the CLI
    /context              Visualize current context
                          usage as a colored grid
    /usage-credits        Configure usage credits or
                          request them from your admin…
─────────────────────────────────────────────────────────
❯ /exit
─────────────────────────────────────────────────────────
  (2) #2 7f5deb68 40% · wt-cc-141442-81738 (d93c6654e)…
  ⏵⏵ auto mode on · 1 shell
```

## 4. Results (state × copy × width)

Command: `bash /tmp/rsw/matrix.sh && python3 -I /tmp/rsw/classify.py`. Each copy runs as extracted
from the named sha, through a stub that honours `-n N` as `tail -n N` (bin/it2-kitty:1478-1488 does
the same) and serves the `.ansi` file for `--ansi`.

Legend:
- **ok**: matches what a human reads.
- **U**: false UNKNOWN (the screen is readable; the result is a stuck pane, which is the safe
  direction).
- **E!**: reads EMPTY where the correct verdict is UNKNOWN or text (dangerous).
- **T~**: reads a draft over a dialog (refuses, so safe, but wrong).
- **D~**: reads a draft over an empty box (stuck).

The synthetic states behaved identically at all five widths unless a width is named.

| State | hf@bc471e0b6 (F1) | hf@e667558fc (F2,F3) | hf@b68fa8a25 (F4, HEAD) | B cc-tui | C lcs | D LR_SCREEN | E observe | F it2-kitty |
|---|---|---|---|---|---|---|---|---|
| **real pane 2, `/exit` + menu above, 57c** | ok `/exit` | **U** | ok `/exit` | ok | ok | **U** | ok | ok |
| S02 `/exit` + menu above (32-57c) | ok | **U ×5** | ok | ok | ok | **U ×5** | ok | ok |
| S09 mid-turn + menu above + `/exit` | ok | **U ×5** | ok | ok | ok | **U ×5** | ok | ok |
| S04 `/e` + menu above | ok | **U ×5** | ok | ok | ok | **U ×5** | ok | ok |
| S03 `/exit` + menu **below** (hypothetical) | ok | **U ×5** | **U ×5** | ok | ok | **U ×5** | ok | ok |
| S11 `/exit`, no menu | ok | ok | ok | ok | ok | ok (DRAFT) | ok | ok |
| S01 empty, S08 mid-turn empty, real 30/45/57/115c empties | ok | ok | ok | ok | ok | ok | ok | ok |
| S05 draft, S06 wrapped draft | ok | ok | ok | ok | ok | ok | ok | ok |
| S10 faint suggestion | ok | ok | ok | ok | ok | **D~ ×5** | ok | ok |
| **real 2.1.260 bg-work dialog above composer (×2)** | **E!** | ok | ok | **E!** | **E!** | ok (MENU) | **E!** | **E! ×2** |
| S07 bg-work dialog above (32-57c) | **E! ×5** | ok | ok | **E! ×5** | **E! ×5** | ok (MENU) | **E! ×5** | **E! ×5** |
| S12 dialog below box | T~ ×5 | ok | ok | T~ ×5 | T~ ×5 | ok | T~ ×5 | T~ ×5 |
| S15 `/`-option dialog above (hypothetical) | **E!** | ok | **E! ×2** | **E!** | **E!** | ok | **E!** | **E!** |
| S13 labelled top, empty, 45c | ok | ok | ok | ok | ok | **U** | **U** | **U** |
| S14 labelled top + menu above + `/exit`, 45c | ok | **U** | ok | ok | ok | **U** | **U** | **U** |
| real resume picker | T~ | ok | ok | T~ | T~ | ok | T~ | ok |
| real win527 teammate panel (38c) | ok | ok | ok | T~ | T~ | ok | T~ | ok |
| real lr-recon empty with `Try "…"` (plain only) | ok | ok | ok | ok | D~ | ok | ok | D~ (plain fixture lacks faint) |
| real 2.1.293 trust 18c, settings/trust/bg-work lr-recon dialogs, live pane 168 permission dialog | ok | ok | ok | ok | ok | ok | ok | ok |
| real tall /goal 32c, mid-turn 32c, capped 46-row | U, U, ok | ok | ok | ok | ok | ok | ok | ok |

Flagged cells per copy, out of 95 screens:

| Copy | Flagged | What they are |
|---|---|---|
| hf@F1 | 17 | |
| hf@F2/F3 | 23 | 21 are slash-menu U |
| hf@HEAD | 7 | 5 menu-below U, 2 S15 E! |
| cc-tui | 16 | 9 E! |
| lcs | 18 | |
| LR_SCREEN | 29 | 21 slash U, 5 faint D~, 3 labelled U |
| observe | 18 | |
| it2-kitty | 20 | |

**Historical corpus.** I ran A@e667558fc, A@HEAD, the prototype in §7, B and D over all 1,060
saved snapshots in `~/.claude/logs/composer-snapshots/` (1,001 txt + 59 ansi; `/tmp/rsw/snaprun.sh`):

- A@HEAD reads 970 UNKNOWN, 28 EMPTY and 62 TEXT.
- **A@e667558fc and A@HEAD differ on 0.** No saved snapshot contains a slash menu.
- B differs from A@HEAD on 1 (win527, UNKNOWN→TEXT).
- D differs on 12. All 12 are agent-labelled borders such as `───────── @bin-sweep ──`; 11 are
  EMPTY→UNKNOWN and 1 is TEXT→UNKNOWN.

## 5. Mapping to the failures

- **F2 (pane 134, 00:25:47Z, live e667558fc).** Event: `recycle-held-exit-readback "the /exit read
  back as '<unreadable>'"` (handoffs.jsonl row 1121). `hf_exit_readback` (handoff-fire.sh:3316
  @e667558fc) types `/exit` and then reads 3 times through `composer_content`. The 37-column S02
  and S09 rows read U at e667558fc. On '<unreadable>' that sha sends DELs only in the `*/exit)`
  arm and writes no receipt. Its hold text was hard-coded ("five DELs sent to take our /exit back
  out", @e667558fc:17368), which is the false claim in the transcript (`grep 'five DELs'` on the
  session jsonl). **So `/exit` stayed in pane 134's box with the menu open.**
- **F3 (01:21:14Z → 01:24:32Z, live 1b2b93357, composer_content byte-identical to e667558fc).**
  `recycle-deferred-turn "composer unreadable mid-turn"`, then the turn ended at +16 s, then
  `recycle-held-unreachable "composer UNREADABLE for 180s"`. The defer log
  (`handoff-recycle-defer-134-nqgVri`) shows the gate refusing for 180 s "no box rendered". That
  is S09/S02 reading U for the whole wait, because the menu persists. The cc-await-ping turn does
  not change the reader's verdict; S08 vs S09 shows the spinner is not the cause, the menu is.
- **F4 (02:23:36Z, live b68fa8a25).** `recycle-held-draft "… over '/exit'"`. A@HEAD reads `/exit`
  (S02/S09/pane 2: ok), and `composer_residue_is_ours` (handoff-fire.sh:4745-4751) needs
  `~/.claude/logs/composer-residue/134`. The brief says that file does not exist, and
  `ls ~/.claude/logs/composer-residue/` confirms it (files: 137 175 176 2 202 203 25 70). The hold
  is correct for an unattributed `/exit`.
- **Independent replication on pane 2 (CC 2.1.293, 57x62):**
  - `01:28:24Z recycle-held-exit-readback '<unreadable>'` (live 1b2b93357; handoffs.jsonl row 1146).
  - `02:26:12Z recycle-held-draft over '/exit'` (live b68fa8a25; row 1164).
  - The screen read at about 02:35Z still shows `/exit` + menu (above).
  - Its residue file `2` holds only a 2026-09-17 `<unreadable>`, which can never match `/exit`.
- **F1 (pane 44, live bc471e0b6).** Nothing in this slot touches F1. Its `/exit` was confirmed and
  the failure came after it, at the relaunch write. The F1-era reader lacked every dialog guard
  (17 flagged cells, 7 of them E!), but no F1 event depends on a composer read.
- **Live state now:** pane 134 reads EMPTY (its `/exit` was removed after F4). **Pane 2 still holds
  the rail's `/exit` with the menu open.** Its own session has told the operator to "press Enter
  on that /exit to finish the recycle … or delete the text".

## 6. Blast radius: which callers read through which copy

Call sites from `grep -n`, with enclosing functions resolved by awk:

- **A, handoff-fire `composer_content` (patched):**
  - `hf_exit_readback` :3323
  - `recycle_composer_gate` :4211. Also reached through `hf_focus_gate` → `lr_focus_gate`, which
    gets `_hf_focus_composer` as its reader (:3161-3172).
  - `recycle_turn_wait` :4513 (the **deferral**)
  - `recycle_nudge_decision` :4624
  - `composer_scrub_verified` :4681/4689/4696
  - `it2_paste_submit_verified` :4931/4948 (the **goal-arm** and paste path)
  - the watcher in `hf_canary_hook` :10244/10280/10314/10343/10355/10694 (post-/exit nudge and
    scrub)
  - `pre_fire_account_sweep` :12181
  - `recycle_composer_block` :17571 (**held-draft**)
- **B, cc-tui (unpatched, no dialog guards):**
  - **handoff-fire's own transplant carry**: `cc_carry_save` :4263, `cc_tui_clear` :4284,
    `cc_tui_composer` :4289, `cc_carry_putback` :4326/:4364
  - scripts/lib/composer-carry.sh :51/124/133/137/144/159
  - **lr-upgrade** :572/1213/1216/1254/2180/2186
  - **lr-lib `lr_focus_composer`** :1196-1206, the default reader of `lr_focus_gate`, which
    **lr_recon act.py:226-235** calls
  - `cc_tui_submit` (cc-tui.sh:526), used by **lr-reset-poller** :956/1479, **lr-fleet** :1233,
    **lr_recon act.py** :207-235, and `it2 session tui-submit` (bin/it2-kitty:1494-1530)

  cc_tui_submit has no modal check before it types besides this parse: `grep modal cc-tui.sh`
  returns only comments, and `_cc_tui_torn_composer` runs only after an UNKNOWN.
- **C, lcs:** snapshot writers only (lr-fleet :1283, lr-reset-poller :879, lr_recon __main__ :384).
  It types nothing, so the blast radius is the record only.
- **D, LR_SCREEN_SH:** lr-fire-resume's expect program (`lr_screen`, :1061-1068). Its verdict
  gates the CR after its own prompt is injected and the DRAFT-MINE re-Enter rescue. The **resume
  launcher of panes 2, 168 and (via reso-resume-one) 134** all run CC under `expect`
  (`kitty @ ls` foreground_processes).
- **E, observe.py `composer_state`:** lr_recon `__main__` :529/:541. It decides the "affirmatively
  EMPTY" idle fan-out bucket, which then types through B.
- **F, it2-kitty `composer_state`:** the close guard (bin/it2-kitty:1417-1443). EMPTY there allows
  a close. Over a dialog above an empty box, no draft is lost (*estimated*: low harm).

**So the recycle deferral, held-draft, exit read-back and goal-arm paths all use the patched copy
A.** The limit-recover typing paths use the unguarded copy B, through cc_tui_submit,
lr_focus_gate, lr_recon and lr-upgrade. So does handoff-fire's transplant carry, and E feeds the
same bucket. For B and E, a background-work dialog above an empty box reads EMPTY on real 2.1.260
captures. *Estimated* consequence: cc_tui_submit's read-back would withhold the CR because the
payload never echoes into the box. But the paste itself is delivered to the dialog, and a payload
character that is a dialog hotkey (`1` = "Exit and stop tasks") could act on it. Not measured: I
sent nothing.

## 7. A tighter slash rule, prototyped and measured (in /tmp only)

`/tmp/rsw/cc-proto.txt` changes A in two places:

1. The selector-above exemption (:4083) applies only when the box's own first row begins with `/`
   after the `❯\xa0`. The menu exists only while the box text starts with `/`.
2. The `gb` rule (:4088) accepts `❯` rows under the bottom border only when every one of them is
   such a slash row and the box starts with `/`.

Measured effects:
- **95-screen corpus:** 7 verdicts change. 5 S03 menu-below go U→`/exit`, and 2 S15 go
  EMPTY→UNKNOWN. Nothing else changes, including real pane 2 (`/exit`), S07 and S12 (UNKNOWN), and
  S02, S04 and S09.
- **1,060 snapshots:** 0 verdicts change.
- `bats tests/composer-tall-readback.bats` @HEAD (unmodified): plan `1..21`, 21 ok.

## 8. Reproduce

```
bash /tmp/rsw/extract.sh                         # copies @ each sha → /tmp/rsw/*-<sha>.*
python3 -I /tmp/rsw/genfx.py                     # synthetic corpus → /tmp/rsw/fx
bash /tmp/rsw/matrix.sh && python3 -I /tmp/rsw/classify.py
bash /tmp/rsw/snaprun.sh                         # 1,060 historical snapshots
```

## 9. Conviction, and what would change it

- F2 is the slash-menu-above verdict of A@e667558fc: **90%**. Measured on a real 2.1.293 capture
  and at five widths, with pane 2 replicating it on the same shas. I have no capture of pane 134's
  own screen at 00:25Z. Evidence that its box read empty or carried a real dialog then would
  lower this.
- F3's 180 s UNREADABLE is the same persisting menu: **85%**. Pane 2 shows the menu persisting
  for more than an hour across turns. A capture of pane 134 at 01:21-01:24Z without the menu would
  refute it.
- F4 is attribution, not reading: **90%**. A@HEAD reads `/exit`, and the residue file is absent.
- The menu is never drawn below the box in 2.1.293: **unmeasured**. 2 of 2 real observations show
  it above. One capture of a below-box menu would make the `gb` gap live.
- A CC dialog with a `/`-leading highlighted option exists: **~15%** (*estimated*; none is known
  to me or found in the fixtures). One existing would make 0584f0720 a live wrong-EMPTY.
