# Goal-arm read-back: does the tall-box fallback still fail closed on a modal?

Slot: modal fail-closed (question 2). The question: catalogue every captured modal or non-composer screen, then run each one through design D1. Run each alone and under realistic and hostile transcript padding, at windows 24 and 120. Report any modal screen that D1 reads as rc 0, and EMPTY above all. Also confirm that every non-modal composer fixture reads the same as it does today.

## Deviation: the fix landed while this slot ran

Commit `373bb4230` ("a tall wrapped /goal reads back as itself") landed on this branch during the run, at 17:16 local. The worktree's `scripts/handoff-fire.sh` now carries a fallback of its own. It differs from the brief's D1 in three ways:

- **(iv) is looser.** Blank rows inside the box are accepted.
- **There is a new rule (v).** If a `❯ <digits>.` selector appears anywhere *below* the bottom border, the read is UNKNOWN.
- **The big window defaults to 200.** The brief's D1 used 120.

So this slot measures three readers side by side:

| reader | what it is |
|---|---|
| **BASE** | `composer_content` at `16b6b441f`, the code before the fix, extracted verbatim from `git show` |
| **D1** | the brief's D1, written as a wrapper around BASE: `/tmp/gar/modal-harness/v2/lib2.sh` `composer_content_d1` |
| **LANDED** | `composer_content` at `373bb4230`, extracted verbatim; run at MAX=200 (its default) and at MAX=120 |

An earlier harness pass sourced the live worktree file and so ran LANDED where it meant to run BASE. Its results (`/tmp/gar/modal-harness/out/results.tsv`, `/tmp/gar/modal-harness/v2/out/results.tsv`) are superseded and are not cited below.

## Answer

1. **D1 never makes a modal read EMPTY that did not already read EMPTY.** Over 351 modal rows (39 screens × 9 paddings), measured with `v2/run2.sh`, D1 and LANDED have 49 EMPTY rows each. All 49 come through the unchanged common path, and BASE has the same 49. LANDED at MAX=120 and at MAX=200 agree on all 729 rows.
2. **D1 does add 10 new MATCH verdicts on modal screens. LANDED adds the same 10.** A MATCH means the read-back equals the pasted /goal, so the CR would be sent.
   - **M31, all 9 paddings.** This is a synthetic version of a measured real shape: CC 2.1.260 draws the bgwork exit dialog **above a composer that stays visible** (real captures M15 and M16). With the 472-char /goal in a 32-column composer below the dialog, BASE says UNKNOWN. D1 and LANDED read the whole payload and say MATCH. Rule (v) does not catch it, because the selector sits *above* the box, not below it.
   - **M08 (the real 2.1.284 trust dialog) under pH.** pH is a contrived Ink-overflow ghost: a column-0 rule, then `❯`, then the payload's last 11 rows, sitting directly on top of the dialog's top rule. D1 and LANDED read 259 chars, and `paste_readback_ok`'s tail-anchored form accepts that as proof. Rule (v) does not catch it either, because the trust dialog's cursor row is `❯ No, exit`, with no digit.
3. **The fail-closed property is already broken in BASE, the pre-fix code, on real and fixture screens.** This is independent of D1:
   - **Real 2.1.260 captures M15 and M16** (`tests/fixtures/teammate-probe/captures/p1-run2*/`): a live "Background work is running" dialog above an empty composer reads **EMPTY** at N=24, in every padding.
   - **M32** (the same shape with a short `/goal reply with DONE` in the composer) reads **MATCH**.
   - **Short border-less dialog fixtures under realistic padding pA** read **EMPTY**: M11, M12, M18, M25, M26, M28, M29, M34, M35, M36. The cause is that BASE treats an *indented* rule pair as a box: tool output that prints an empty composer (`  ⎿  ────` / `     ❯ ` / `     ────`) counts as one.
   - **The landed test's own hostile transcript makes two real fixtures MATCH through the common path:** `trust-dialog-2.1.284` and `resume-return-menu-2.1.284.RECONSTRUCTED`. The transcript is a `$B` rule, then `❯ /goal row1`, then `  row2`, then the modal, and both read `/goalrow1row2`. I re-enacted `tests/composer-tall-readback.bats` @test "every real modal fixture, alone and under a hostile transcript, never reads EMPTY or as the payload" outside bats (`v2/batsrepro/repro.sh`), with the same extraction, transport, `mk_hostile` and assertions. As written, that test should fail on its first fixture. The test at L170 ("a paste that lands in a modal under a hostile transcript gets NO CR (rc 4)") uses the same trust-dialog screen and should fail too. **Not run under bats:** cc-bats refused, with both slots held, one of them a concurrent run of this same file from this worktree. So this is a re-enactment, not a bats result.
4. **Non-modal composer fixtures read exactly as BASE does, except where they should change.** All 297 non-tall rows (33 screens × 9 paddings) are identical to BASE under both D1 and LANDED (measured). The tall fixtures (C50, C51, C60, C61, C63, C64) go from UNKNOWN to the correct content. D1 and LANDED disagree only on a tall box containing a truly empty row (C62, C74): D1 says UNKNOWN, LANDED reads it. A tall box whose `❯` sits at column 1 (C73, cc-tui fixture style) stays UNKNOWN under both.
5. **A cheap hardening closes every modal EMPTY and MATCH in this corpus, including the pre-existing ones.** It is a set of three structural vetoes, and it costs no composer verdict in the fixtures or the snapshot corpus. Details in §6. It is modelled in Python, not implemented in bash.

## 1. Method

- **Harness:** everything is under `/tmp/gar/modal-harness/v2/`. Nothing in the repo was edited, and no pane was read or typed into.
  - `build.py` builds the screens and paddings.
  - `lib2.sh` holds the three readers.
  - `one.sh` runs one reader on one screen.
  - `run2.sh` runs everything; results go to `out/results2.tsv` (729 rows).
  - `out/verdict-matrix.md` and `hardened_model.py` produce §4 and §6.
- **Transport:** `/tmp/gar/it2stub`, which returns `tail -n N` of the file, or of `<file>.ansi` when called with `--ansi`.
- **Payloads tested for MATCH** with the landed `paste_readback_ok` (exact form, ≥64-char tail form, placeholder form):
  - GOAL: the 472-char pane-203 /goal, from `/tmp/gar/modal-harness/goal-payload.txt`.
  - ECHO: a 160-char /goal used inside the hostile paddings.
  - SHORT: `/goal reply with DONE`.
- **Paddings:** transcript rows placed above each screen. Blank rows become `"  "` in pE through pH, because real captures carry whitespace-only rows: M14 has 5 and M21 has 3, counted with a Python whitespace count.

| pad | content above the screen |
|---|---|
| p0 | nothing |
| pA-realistic | ×3: an assistant message with a **markdown rule at column 2**; tool output `  ⎿  ────` that prints an **EMPTY composer** (`     ❯ `, `     ────`, footer); an **echoed prior user prompt** `❯ please look…` at column 0 with a 2-space continuation; `⎿` tool output; `✻ Thinking…` |
| pB-ghostframe-col0 | a column-0 ghost composer frame (rule / `❯ ` / rule / footer) above pA |
| pC-ADV-emptyghost-abuts | pA, then a column-0 rule and a bare `❯ `, directly on top of the screen |
| pD-ADV-goalecho-abuts | pA, then a column-0 rule and a 3-row echoed `/goal` (ECHO), directly on top of the screen |
| pE-ws-margins+ghost+echo | pB + pD, with blank rows rendered as `"  "` |
| pF-colzero-rule-then-echo-ws | pA, then a column-0 rule, an echoed prompt and an indented row, `"  "` blanks |
| pG-ADV-tallgoal-ghost-head | pA, then the *first* 12 rows of the tall GOAL composer (rule, `❯`, continuations): an Ink overflow ghost |
| pH-ADV-tallgoal-ghost-tail | the same, but the *last* 12 rows, with `❯` forced onto the first one |

## 2. Catalogue of modal and non-composer screens

- **Geometry measured by:** `/tmp/gar/modal-harness/analyze.py`.
- **"borders":** rows that composer_content's `border()` accepts (contains 12×`─`, or `──…─` from column 0). Each is given as `rROW/-FROM_BOTTOM@cCOL`.
- **"glyph":** every `❯` (U+276F), with its column.
- **Not found as screens:** item `2ee30f87c370`'s own samples were not saved. Its disproof is summarised in `docs/lessons/empty-vs-no-surface.md` as "`borders=0` on all 7 samples of the pre-wait for modal panes". That agrees with the real captures M21, M22 and M24 below. The snapshot stores `~/.claude/logs/composer-snapshots` and `~/.claude-next/logs/composer-snapshots` mirror each other (1,057 files each). Each holds 12 modal files, and those are 4 distinct screens (checked with `cmp`).

| id | source | kind | lines | borders | ❯ glyph |
|---|---|---|---|---|---|
| M01 | tests/fixtures/lr-recon/screens/bgwork-dialog-2.1.284.txt | real, 2.1.284 | 13 | 1 [r3/-11@c0] | r1@c0 (echoed `❯ /exit`), r9@c2 (selector) |
| M02 | …/bgwork-dialog-2.1.284-agent-view-off.txt | real, 2.1.284 | 12 | 1 [r3/-10@c0] | r1@c0, r9@c2 |
| M03 | …/bgwork-dialog-2.1.284-29col.RECONSTRUCTED.txt | reconstructed | 17 | 1 [r3/-15@c0] | r1@c0, r11@c2 |
| M04 | …/bgwork-dialog-2.1.284-40col.RECONSTRUCTED.txt | reconstructed | 14 | 1 [r3/-12@c0] | r1@c0, r10@c2 |
| M05 | …/bgwork-dialog-2.1.284-80col.RECONSTRUCTED.txt | reconstructed | 13 | 1 [r3/-11@c0] | r1@c0, r9@c2 |
| M06 | …/resume-return-menu-2.1.284.RECONSTRUCTED.txt | reconstructed | 10 | 1 [r1/-10@c0] | r6@c2 (`❯ 1.`) |
| M07 | …/settings-error-dialog-2.1.114.txt | real, 2.1.114 | 14 | 0 | r11@c2 |
| M08 | …/trust-dialog-2.1.284.txt | real, 2.1.284 | 16 | 1 [r1/-16@c0] | r13@c1 (`❯ No, exit`: no digit) |
| M09 | …/resume-picker-2.1.284.txt | real, 2.1.284 | 11 | 3 [r1@c0, r3@c3 `╭`, r5@c3 `╰`] | r8@c2 |
| M10 | tests/fixtures/selfclose-exit-dialogs/bgwork.txt | fixture | 15 | 0 | r11@c3 |
| M11 | …/selfclose-exit-dialogs/nudge.txt | fixture | 7 | 0 | none |
| M12 | …/selfclose-exit-dialogs/panel-draft.txt | fixture | 7 | 0 | r4@c3 |
| M13 | …/selfclose-exit-dialogs/panel-list.txt | fixture | 13 | 0 | r9@c3 |
| M14 | tests/fixtures/teammate-probe/captures/p1-run1-exitmodal/pane-before.txt | real | 84 | 1 [r71/-14@c0] | r6@c0, r69@c0 (echoed `❯ /exit`), r80@c2 |
| M15 | …/p1-run2-exitmodal/pane-before.txt | real, 2.1.260 | 90 | 3 [r65/-26@c0 dialog rule; r80/-11, r82/-9 composer] | r74@c2 (selector), **r81@c0 (empty composer under the dialog)** |
| M16 | …/p1-run2/lead-pane.after-exit.txt | real, 2.1.260 | 93 | 3 [r68/-26, r83/-11, r85/-9 @c0] | r77@c2, **r84@c0** (dialog still up, composer under it) |
| M17×4 | tests/pane-modal.bats L39/L51/L72/L92 (mcp/trust/hook-ask/perm-ask) | fixture, boxed `╭─╮` | 7–13 | 2 [`╭` top, `╰` bottom, @c1] | none |
| M18 | tests/cc-tui.bats L262 screen_menu | fixture | 3 | 0 | r2@c1 |
| M19 | tests/handoff-recycle-bgwork-dialog.bats L52 (= handoff-recycle-bgcopy-stop.bats L136) | fixture | 12 | 0 (one lone `─` row is not a border) | r8@c3 |
| M20 | tests/lr-fire-resume-pane-ui.bats L118 menu.txt (and lr-fire-resume-submit L374) | fixture | 5 | 2 [r2/-4@c0, r5/-1@c0] | r3@c2 (`❯ 1.` *inside* the box) |
| M21 | ~/.claude/logs/composer-snapshots/20261010T0314{22,25,28,31}Z-win175.txt | real (narrow bgwork) | 62 | 0 | r54@c3 |
| M22 | …/20260902T00533{8,41,43,45}Z-win197.txt | real (narrow hook ask) | 44 | 0 | r39@c1 |
| M23 | …/20260808T11092{8,9}Z-win704.txt | real (wide hook ask) | 38 | 1 [r23/-16@c0] | r35@c1 (`❯ 1. Yes`) |
| M24 | …/20260808T11092{8,9}Z-win712.txt | real (wide hook ask) | 18 | 0 | r15@c1 |
| M25 | tests/fire-engagement.bats L945 stub trust output | fixture | 4 | 0 | none |
| M26 | tests/fire-engagement.bats L980 stub hook-ask output | fixture | 6 | 0 | none |
| M27 | tests/cc-tui.bats L261 screen_torn | fixture | 4 | 1 [r2/-3@c0] | r3@c1 |
| M28 | docs/research/exit-bgwork-dialog-2026-09-10/README.md | doc excerpt | 10 | 0 | r6@c3 |
| M29 | docs/research/selfrecycle-agentview-off-2026-09-30/README.md | doc excerpt | 7 | 0 | r6@c3 |
| M34 | docs/research/subagent-lifecycle-2026-09-19/P-probes.md | doc excerpt | 10 | 0 | r6@c2 |
| M35 | docs/research/breaking-the-ceiling-2026-08-19/B1-VERIFY.md | doc excerpt | 4 | 0 | r4@c0 (`❯ 1. Yes` at column 0: as transcribed) |
| M36 | docs/research/selfrecycle-agentview-off-2026-09-30/pane48/p2-latebg.txt | probe log, re-indented | 4 | 0 | r2@c6 |
| M30 | synthetic: tall permission dialog | synthetic | 40 | 1 [r3/-38@c0] | r37@c1 |
| M31 | synthetic: the M15 shape with the 472-char /goal in a 32-column composer under the dialog | synthetic | 43 | 3 [r3/-41 dialog; r18/-26, r41/-3 composer] | r10@c2, r19@c0 |
| M32 | synthetic: the M15 shape, short composer `/goal reply with DONE` | synthetic | 22 | 3 [-20, -5, -3] | r10@c2, r19@c0 |
| M33 | synthetic: the M15 shape, empty composer, 32 columns | synthetic | 22 | 3 [-20, -5, -3] | r10@c2, r19@c0 |

The shapes, as seen in the captures:

- **The dialog's own frame.** CC 2.1.x dialogs (bgwork, trust, hook ask, resume menu) draw **one** column-0 full-width rule as their top edge and no bottom rule. Some carry an echoed `❯ /exit` at column 0 just above that rule (M01–M05, M14). Their own `❯` cursor sits at column 1–3.
- **The composer's glyph.** In every real capture the composer's `❯` is at column 0 (M15, M16, pane 203). The cc-tui.bats fixtures put it at column 1.
- **Narrow panes.** Dialogs in narrow real panes (M21, M22) show **no border at all** in the window, so every reader gives UNKNOWN.
- **Dialog above the composer.** On 2.1.260 (M15, M16) the dialog renders **above a composer that stays visible**. That composer's two borders are the last two in the window.

## 3. D1's decision path per screen

Measured: `run2.sh`, the `d1path` column.

| abbreviation | meaning |
|---|---|
| com | common path (two borders in the small window, byte-identical to BASE) |
| sb0 / sb2 | fallback not entered: 0 or ≥2 borders in the small window |
| noTop | no border above in the big window |
| ii / iii / iv | rejected by that D1 rule |
| FB | fallback accepted |

Paddings 0–8 are p0, pA, pB, pC, pD, pE, pF, pG, pH.

```
M01 bgwork 2.1.284          noTop ii    ii    com   com   com   com   iv    iv
M02 bgwork viewoff          noTop com   com   com   com   com   com   iv    iv
M03/M04/M05 (RECON)         noTop ii    ii    com   com   com   com   iv    iv
M06 resume-return RECON     noTop com   com   com   com   com   com   com   com
M07 settings-error          sb0   sb0   sb0   ii    ii    ii    ii    sb0   sb0
M08 trust 2.1.284           noTop ii    ii    com   com   com   com   FB    FB
M09 resume-picker           com   (all 9)
M10/M13 selfclose           sb0   sb0   sb0   ii    ii    ii    ii    sb0   sb0
M11/M12/M18/M25/M26/M29/M35/M36   sb0 com com com com com com ii ii
M14 run1 exitmodal          noTop ii    ii    iv    iv    iv    iv    iv    iv
M15/M16 run2 (real)         com   (all 9)
M17×4 boxed, M20 menu-in-box, M32, M33   com (all 9)
M19 bats bgwork             sb0   ii    ii    ii    ii    ii    ii    sb0   sb0
M21/M22/M30                 sb0   (all 9)
M23 win704 hook ask         noTop ii    ii    iv    iv    iv    iv    iv    iv
M24 win712                  sb0   sb0   sb0   ii    ii    ii    ii    sb0   sb0
M27 cc-tui torn             noTop com   com   com   com   com   com   com   com
M28/M34 doc excerpts        sb0   com   com   com   ii    ii    ii    ii    ii
M31 synthetic               FB    (all 9)
```

Tally over the 351 modal rows: com 186, ii 62, sb0 60, iv 22, FB 11, noTop 10. Every rule does work:

- **(ii) is the main fallback guard on hostile transcripts.** In realistic transcripts the nearest rule above a dialog is an *indented* one: a markdown rule, or a composer printed in tool output.
- **(iv)** rejects the real M14 and M23 shapes, which have `⏺`/`❯ /exit` rows or a truly empty row between the ghost rule and the dialog.
- **(iii)** was never the deciding rule on a modal row. On composers it is the rule that rejects C73 (glyph at column 1).

## 4. Verdict matrix: BASE@24, D1 (24→120) and LANDED (24→200)

Measured: `run2.sh`, generated as `out/verdict-matrix.md`.

- **Cell codes:** U = UNKNOWN; T = non-empty text that matches no payload; **E** = EMPTY; **M:X** = the read-back proves payload X; T(/exit) = reads `/exit`.
- **Single code:** BASE, D1 and LANDED agree.
- **"→":** the fallback changed the verdict.

| screen | p0 | pA | pB | pC | pD | pE | pF | pG | pH |
|---|---|---|---|---|---|---|---|---|---|
| M01 bgwork 2.1.284 | U | U | U | T(/exit) | T | T | T | U | U |
| M02 bgwork viewoff | U | T | T | T(/exit) | T | T | T | U | U |
| M03–M05 RECON | U | U | U | T(/exit) | T | T | T | U | U |
| M06 resume-return RECON | U | T | T | **E** | **M:ECHO** | **M:ECHO** | T | T | **M:GOAL** |
| M07 settings-error | U | U | U | U | U | U | U | U | U |
| M08 trust 2.1.284 | U | U | U | **E** | **M:ECHO** | **M:ECHO** | T | U → T (D1 and landed) | U → **M:GOAL** (D1 and landed) |
| M09 resume-picker | T | T | T | T | T | T | T | T | T |
| M10, M13 selfclose | U | U | U | U | U | U | U | U | U |
| M11, M12 selfclose | U | **E** | **E** | T | T | T | T | U | U |
| M14 run1 exitmodal | U | U | U | U | U | U | U | U | U |
| **M15 run2 (real)** | **E** | **E** | **E** | **E** | **E** | **E** | **E** | **E** | **E** |
| **M16 run2 (real)** | **E** | **E** | **E** | **E** | **E** | **E** | **E** | **E** | **E** |
| M17×4 boxed | T | T | T | T | T | T | T | T | T |
| M18 cc-tui menu | U | **E** | **E** | T | T | T | T | U | U |
| M19 bats bgwork | U | U | U | U | U | U | U | U | U |
| M20 menu-in-box | T | T | T | T | T | T | T | T | T |
| M21–M24 real snapshots | U | U | U | U | U | U | U | U | U |
| M25, M26 fire-engagement | U | **E** | **E** | T | T | T | T | U | U |
| M27 cc-tui torn | U | T | T | T | T | T | T | T | T |
| M28, M34 doc excerpts | U | **E** | **E** | T | U | U | U | U | U |
| M29, M35, M36 excerpts | U | **E** | **E** | T | T | T | T | U | U |
| M30 tall permission | U | U | U | U | U | U | U | U | U |
| **M31 dialog above TALL /goal** | U → **M:GOAL** | U → **M:GOAL** | U → **M:GOAL** | U → **M:GOAL** | U → **M:GOAL** | U → **M:GOAL** | U → **M:GOAL** | U → **M:GOAL** | U → **M:GOAL** |
| M32 dialog above short /goal | **M:SHORT** | **M:SHORT** | **M:SHORT** | **M:SHORT** | **M:SHORT** | **M:SHORT** | **M:SHORT** | **M:SHORT** | **M:SHORT** |
| M33 dialog above empty composer | **E** | **E** | **E** | **E** | **E** | **E** | **E** | **E** | **E** |

Counts over the 351 modal rows (measured, `results2.tsv`):

| reader | UNKNOWN | EMPTY | MATCH | real-capture rows that read EMPTY |
|---|---|---|---|---|
| BASE@24 | 165 | 49 | 19 | 19 of 108 |
| BASE@120, the naive fix (just widen the window) | 28 | **63** | not computed | 27 of 108 |
| D1 | 154 | 49 | 29 | 19 |
| LANDED@200 = LANDED@120 | 154 | 49 | 29 | 19 |

The naive fix is worse on both fronts: it reads EMPTY on 14 more modal rows than BASE.

## 5. Non-modal composer fixtures

The set has 42 screens × 9 paddings = 378 rows:

- **The C01–C18 handoff-composer-gate.bats shapes**, rebuilt with its `mk_screen` and `mk_labeled_screen`: empty, the `Try "…"` placeholder, faint suggestion, unfaint `I`, truecolor draft, draft + faint hint, labeled top empty and with a draft, label cut short, rule-like draft rows, coloured border, a `Try "` prefix draft, `[Pasted text #1 +9 lines]`, draft + chip, short /goal, draft merge, no borders, empty screen.
- **The 6 lr-recon composer screens.**
- **The 4 it2-kitty agent-pane fixtures.**
- **The teammate panes at idle.**
- **Pane 203**, plain and ANSI.
- **The cc-tui.bats `screen_empty`, `screen_draft` and `screen_paste`**, with the glyph at column 1.
- **Synthetic tall drafts.**

Results (measured, `run2.sh`):

- **Non-tall screens (33 screens, 297 rows): D1 equals BASE@24 on 297/297, and LANDED equals BASE@24 on 297/297.** That covers EMPTY for the empty, placeholder, faint and coloured-border boxes, and the exact text for drafts, chips and labeled borders. UNKNOWN stays UNKNOWN for the cut-short label, no borders and empty screen.
- **Tall screens:**
  - C50 and C51 (pane 203), C63 (synthetic 32-col /goal), C60 (tall draft), C61 (tall draft under a labeled top), C64 (draft + chip): **UNKNOWN → the exact content** under D1 and LANDED, in all 9 paddings. Pane 203 reads the 472-char payload and `paste_readback_ok` proves GOAL.
  - **C62 and C74** (a tall box with one truly empty row): **D1 says UNKNOWN** (rule iv, row 11 and row 9), **LANDED reads the content**. Under pE through pH, where the blank is `"  "`, both read the content. A /goal is one line, so this only matters for operator drafts that contain blank lines; D1 fails closed there.
  - **C73** (tall /goal with `❯` at column 1): UNKNOWN under both (rule iii). Real CC draws the glyph at column 0, so this matters only if a future build indents it.
- **The win527 teammate panel** (`tests/fixtures/composer-tall/win527-teammate-panel.txt`): UNKNOWN alone and under the hostile transcript, re-enacted.

## 6. Hardening that would close the remaining holes

This is a Python model (`v2/hardened_model.py`). I have not implemented it in bash. Apply three vetoes to whichever box the reader chose, on the common path **and** on the fallback, and answer UNKNOWN when any fires:

- **(ii\*)** The box's top border must start at column 0. D1 rule (ii), extended to the common path.
- **(a)** No `❯` anywhere below the bottom border. A composer's footer never holds one; a dialog under an echoed prompt always does, with or without a digit (the trust dialog's `❯ No, exit`).
- **(b)** No row with `❯` at indent 1–4 above the top border. That is the selector of a dialog drawn above a visible composer, as in M15, M16 and M31–M33.

What the model shows:

- **Modal rows:** of 351, 0 EMPTY and 0 MATCH remain, down from 49 EMPTY and 29 MATCH under LANDED. All 351 are UNKNOWN or non-matching text.
- **Composer fixtures:** no verdict flips, except on the UNKNOWN-by-design screens C09 (under pA and pB) and C17 and C18 (under pA–pF). BASE misread those as text or EMPTY because of the padding's indented rule pair, and the vetoes return them to UNKNOWN.
- **Snapshot corpus cost:** measured on the 1,057 close-guard snapshots in `~/.claude/logs/composer-snapshots` with a Python re-implementation of `border()` (`v2/corpus_probe.py` plus an inline variant). 90 snapshots parse a box in the 24-row window. Of those 90, 0 have a top border off column 0, 0 have a first row not starting `❯` at column 0, 0 have `❯` below the bottom border, and 0 have an indented `❯` above the top. **0 of 90 would flip.**
- **Caveat on the corpus:** it is mostly idle panes. It cannot show the cost of veto (b) on an echoed user prompt that starts with a digit list (`❯ 1. …` at column 0 is *not* vetoed, since that is indent 0). Nor can it show the cost on a CC build that indents its composer glyph.

## 7. Other concerns

- **The two reads are not atomic.** D1 and LANDED read the small window and then the big one. A dialog can appear between the two reads. Rule (i) (same bottom row) catches only a shift of the bottom border. The static-file harness cannot test this. Taking the small-window verdict from the tail of the big read itself would remove the race.
- **The tail form of `paste_readback_ok`.** A box of ≥64 chars that is a suffix of the payload counts as proof. That is what turns M08+pH into a MATCH. Any composer-shaped ghost holding the end of the payload (an Ink overflow, or a scrolled, height-capped composer re-drawn with `❯` on its first visible row) gets the same treatment. Rule (iii) is the only guard here: a scrolled composer whose first visible row is a continuation row is rejected by it.
- **The window size makes no difference.** MAX=120 and MAX=200 gave identical verdicts on all 729 rows (LANDED, measured).
- **Severity of M31 and M15 for the /goal arm specifically.** These are estimates from the captures, not measurements:
  - The dialog-above-composer layout was measured on CC 2.1.260 for the exit dialog only, which needs `/exit` to be submitted, and the arm never types `/exit`.
  - The 2.1.284 permission and trust dialogs replace the composer (M01, M08, M23).
  - So M31 needs a dialog that keeps the composer on screen to open while a tall /goal sits unsubmitted.
  - If that happens, the CR selects the dialog's default: "Exit and stop tasks", or "Yes" on a permission ask.
  - The same exposure already exists for any short payload (M32) and for the EMPTY pre-check (M15/M16 read EMPTY), so a paste there would go into the dialog.
