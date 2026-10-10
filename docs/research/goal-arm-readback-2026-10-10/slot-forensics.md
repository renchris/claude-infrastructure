# Goal-arm read-back: why each "mangled" arm saw `<unreadable>`

Slot: forensics (question 1). I read logs, transcripts, screen captures and the kitty tree. I typed nothing into any pane and edited no repo file. Scratch files are in `/tmp/gar-slot/`.

**Note on HEAD.** HEAD moved while this slot ran. The pre-fix code is `16b6b441f`. The fix is `373bb4230` and the docs commit is `67cfb0c58`. Every "OLD" replay below runs `composer_content`, `_paste_newlines` and `paste_readback_ok` taken from `git show 16b6b441f:scripts/handoff-fire.sh`. Every "NEW" replay runs the same three functions from `HEAD`.

## 0. Answer

- **All five "mangled" rows are the same event.** All 8 read-backs returned rc 1, which is UNKNOWN. None of them is a content mismatch.
- **Four of the five are fully explained by geometry, with measured pane widths:** 175, 176, 202 and 203.
  - The wrapped `/goal` made the composer body 21 to 25 rows tall.
  - The footer under the bottom border was 2 rows.
  - So the top border sat 25 to 29 rows from the bottom of the screen. That is outside the 24-line read window.
  - The window held only the bottom border, so the awk found fewer than two borders and exited 9. That gives rc 1 and `<unreadable>`.
  - Replaying each screen through the pre-fix code gives rc 1. The post-fix code gives an exact MATCH.
- **Pane 70 is undetermined.** No width record survives for it. It would fail by geometry only at ≤23 columns (2-row footer) or ≤25 columns (3-row footer).
- **Hypotheses (b) mid-turn rendering, (c) wrong region and (d) timing explain none of the four measured rows.** Section 4 gives the reasons.
- **Separation.**
  - Goal length alone does not separate mangled from set: mangled goals are 347 to 583 chars, set goals 308 to 650.
  - Pane width alone does not separate them either: set row 162 was about 32 columns, and so was mangled row 203.
  - **Body rows at the pane's actual width** do separate them. Every mangled row with measured geometry has its top border at 25 or more rows from the bottom. No set row with any geometry evidence is shown to have had more than 24. Most were at 13 to 20.
- **Each failure crossed the line by a small margin.** 175 needed 29 columns and had 28. 202 needed 38 and had 37.
- **Same-tab contrasts point the same way.**
  - Pane 4's tab: the 7th column (162) armed. The 8th (175) and the 9th (176) failed. After pane 4 was detached into its own window, the next fire (181) armed.
  - Pane 195's tab: the 4th column (195) armed. The 6th (202) and the 7th (203) failed.

## 1. Population (measured: `jq` over `~/.claude/logs/handoffs.jsonl`)

The ledger covers 2026-10-06T23:27:59Z to 2026-10-10T18:33:24Z. It has been rotated, so older rows are gone.

It holds 55 `goal-arm` rows:

| verdict | rows |
|---|---|
| set | 47 |
| mangled | 5 |
| unverified | 3 |
| held | 0 |
| abstained | 0 |

- All 5 mangled rows read `saw: <unreadable>`.
- The 3 unverified rows are panes 108, 112 and 128. Two of them carry goals over 800 chars (805 and 902), so they took the paste-chip path. They are not part of this question.
- Older residue receipts show the same `<unreadable>` shape before this ledger starts: pane 25 at 2026-10-06T06:27:07Z (a 642-char goal from `fire-lr-zero-memory.txt`) and pane 2 at 2026-09-17. The source is `~/.claude/logs/composer-residue/`.

## 2. Method

1. **Goal text.** I took each fire's exact `--goal` argument from the firing session's Bash `tool_use` in its transcript (`/tmp/gar-slot/allgoals.py`, which parses with `shlex`, across 426 transcripts). I joined it to each ledger row through the `prompt_file` of the `self-retire-peer` row just before it. For recycles, the goal is carried over from the original fire.
2. **Wrap model.** I used `wrap-ansi(text, cols-4, {hard: true, trim: false})` on `"/goal " + cond` (`/tmp/gar-slot/wrap2.py`). I validated it before use: it reproduces, row for row, the composer of four independent real screens:
   - the full pane-203 capture (22 rows at 32 columns);
   - the full pane-202 operator screenshot (21 rows at 37 columns);
   - the last 12 rows of a read of pane 175 at 28 columns;
   - the last 9 rows of a read of pane 176 at 24 columns.

   The `trim: true` variant and widths of `cols-2`, `cols-3` and `cols-5` each fail at least one of the four (`/tmp/gar-slot/fit.py`). So the task's "ceil((len+2)/(cols-4))" is the right text width, but a character-count estimate undercounts rows. Word wrap loses about 15 to 25% of each row.
3. **Geometry sources.**
   - The firing session's own `kitty @ get-text` reads of the new pane, taken seconds after the arm (`/tmp/gar-slot/screens.py`).
   - The operator's screenshot `<session tmp>` (= `~/.reso/goal-arm/unsubmitted-goal-2026-10-10.png`).
   - The pane-203 capture.
   - Transcript `kitty @ ls` output (`/tmp/gar-slot/geo.py`).
   - Status-line screens captured in any transcript (`/tmp/gar-slot/status_scan.py`).
   - `~/.claude/logs/pane-spawns.jsonl` (split anchors) and the current kitty tree.

   The kitty layout is `splits`, and `bin/it2-kitty` has equalized each tab on every split since `96d1f5219` (2026-09-19). So a tab with n columns gives each pane about (W − (n − 1))/n columns. On the 62-line display that day, W was about 230. Measured pairs: 57 = 4 columns, 37 = 6, 32 = 7, 28 = 8, 24 = 9. The display has since changed: every pane now reads 46 lines, and the tabs are about 155 columns wide.
4. **Replay.** I built a 62-line screen for each case (`/tmp/gar-slot/mkscreen.py`): filler and spinner rows, the top border, the modelled body, the bottom border, and a footer of 2 or 3 rows. I served it with `/tmp/gar/it2stub` and ran it through `/tmp/gar-slot/replay.sh` (OLD vs NEW). The real pane-203 capture was replayed as is.

**Rule (measured on the replays).** With the 24-line window and a 2-row footer, the pre-fix parse succeeds iff body ≤ 20 rows. With a 3-row footer, iff body ≤ 19.

## 3. Per-row table: the five mangled arms

"Top border" is that border's row counted up from the screen bottom, with a 2-row footer. The 24-line window reaches row 24.

| pane · ledger ts | goal chars (raw / stripped) | width × lines at arm | width source | body rows | top border | cols needed to pass (2-row / 3-row footer) | OLD replay (24 lines) | NEW replay | (a) geometry | (b) mid-turn | (c) wrong region | (d) timing |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **70** · 2026-10-08T00:57:02Z | 347 / 298 | **unknown** | none survives (no capture, no `ls`, no screenshot, no snapshot) | 25 at 23 cols, 20 at 25, 17 at 28 (model) | 25 / 24 / 21 | 24 / 26 | rc 1 at 23 (f2), at 25 (f3) and at 23 (f3); rc 0 MATCH at 25 (f2) and at 28 | MATCH at all | **undetermined** | not shown | no | not excluded |
| **175** · 2026-10-10T02:47:32Z | 453 / 387 | **28 × 62** | measured: the firing session `d41d9684`'s `kitty @ get-text --match id:175` at 02:47:40Z (+8 s), border = 28 × `─`. The 62 lines come from a close-guard snapshot at 03:14Z. | 21 (model; its last 12 rows equal the real read) | **25** | 29 / 30 | rc 1 `<unreadable>` | rc 0, 387 chars, MATCH | **confirmed** | no | no | no |
| **176** · 2026-10-10T02:52:00Z | 437 / 375 | **24 × 62** | measured: `d41d9684`'s `kitty @ get-text --match id:176` at 02:52:11Z (+11 s), border = 24 | 25 (model; its last 9 rows equal the real read) | **29** | 29 / 29 | rc 1 | rc 0, 375, MATCH | **confirmed** | no | no | no |
| **202** · 2026-10-10T18:17:39Z | 583 / 509 | **37 × 62** | measured: the operator's screenshot at 18:24Z, before pane 203's split at 18:26:47Z. The longest row is `docs/plans/TEAMMATE_TEARDOWN_VERD` (33 = 37 − 4). No split landed in tab 2 between 18:16:43Z and 18:24Z. At 18:28Z the width was 32 (transcript `kitty @ ls`) after the 7th column arrived. | **21** (counted on the screenshot, and equal to the model) | **25** | 38 / 39 | rc 1 | rc 0, 509, MATCH | **confirmed** | no (see §4) | no | no |
| **203** · 2026-10-10T18:27:40Z | 544 / 472 | **32 × 62** | measured: the lead's capture `evidence/pane203-midturn-32col.plain.txt`, and `kitty @ ls` at 18:28:23Z | **22** (real capture) | **26** | 37 / 38 | rc 1 (the real capture itself) | rc 0, 472, MATCH | **confirmed** | no | no | no |

**Pane 70 in detail.**

- Its goal (347 chars) is short. It fails only at ≤23 columns with a 2-row footer, or ≤25 with a 3-row footer. That needs about 10 or more columns on a 230-column tab, or about 7 or more on a 155-column one.
- Nothing records pane 44's tab at 00:56Z on 2026-10-08.
- **Pane 71** (01:37Z, 330 chars) was split from the same pane 44 forty minutes later and armed `set`. It needed ≥23 columns.
  - If 70 failed by geometry, 71 landed one column narrower than 70 was, unless a column closed in between.
  - So hypothesis (a) for 70 requires an unlogged close between 00:57Z and 01:37Z. That is possible, because operator closes are not logged, but it is unproven.
- The session's transcript shows one oddity: a Bash call was issued at 00:56:54Z and returned at 00:57:11Z.
  - It took 17 s, against 1 to 3 s for every other call in that session.
  - So it overlapped the whole read-back window, which closed at 00:57:02Z.
  - The session was in auto mode, and `permission-denied.jsonl` has no row for it. Nothing shows a permission dialog was up.
  - A dialog would also read `<unreadable>`, so this is noted, not concluded.

## 4. Hypotheses (b), (c) and (d) on the measured rows

- **(b) Mid-turn rendering: not the cause.**
  - Every fresh-fire arm runs straight after engagement is proven by an assistant turn. So all 5 mangled arms and every fresh-fire `set` arm were mid-turn: 195, 197 and 204 armed mid-turn and passed.
  - Mid-turn chrome (spinner, `⎿ Tip:` rows) renders **above** the top border, so it does not move the top border relative to the screen bottom.
  - What can add rows **below** the box is footer chrome. The operator's 18:24Z screenshot of 202 shows a 4-row footer with a `○ teammate-teardown-ve…` workflow row. That session's first `Workflow` call was at 18:20:21Z, after the 18:17:39Z arm.
  - The reads at +8 s (175) and +11 s (176) and the 203 capture all show a 2-row footer. The lead's "3-row footer" was not seen in any capture I found.
  - Footer chrome can only lower the threshold. It is not needed for any of the four.
- **(c) Wrong region: no.** rc 1 means the 24-line window held fewer than two borders. The box was on screen, just above the window, which is (a).
  - Wrong pane or wrong box: the same pane id had parsed as an EMPTY 1-row composer moments earlier (the pre-paste gate passed, or nothing would have been pasted).
  - Each post-arm read of that pane shows the composer holding the pasted `/goal` and no modal (175 and 176 reads, the 202 screenshot, the 203 capture).
- **(d) Timing: no.**
  - The geometry is static across the 8 polls (8 × 0.5 s settle plus read time), and the composer is unchanged at +8 s, +11 s and minutes later.
  - The replay of a static screen fails deterministically.
  - A kitty RPC timeout would also yield `<unreadable>`: `kitty @ ls` timed out twice in this slot today (measured), and load was 12.36 per core at 202's fire (ledger). But a timeout is stochastic. It cannot explain 8 of 8 failures on four rows whose pre-paste reads succeeded.
  - The 2026-09-03 comment in `handoff-fire.sh` calls the residual failures "stochastic and mode-independent". On this evidence they are deterministic per (goal length, pane width, footer). Fires land in tabs of varying width, which is why the failures looked random.

## 5. Sample of set rows (17): does "top border outside 24" separate?

- "Need" is the smallest width at which the body stays ≤20 rows (2-row footer) or ≤19 rows (3-row footer) at every wider width.
- "Width evidence" is the best available, and its kind is labelled.
- "Top border" is computed at that width with a 2-row footer.

| pane · ts | chars | need (f2 / f3) | width evidence | body rows / top border at that width | consistent with (a)? |
|---|---|---|---|---|---|
| 138 · 10-09 15:46Z | 423 | 31 / 31 | ≥57, **estimated** from a measured probe: 57 at 16:46Z after 3 more splits from 138, so ≤4 columns at the arm | 9 / 13 | yes |
| 143 · 10-09 16:33Z | 488 | 30 / 32 | ~57, **estimated**: firing pane 135 measured 76 (3 columns) at 16:20Z, and 143 was the 4th | 11 / 15 | yes |
| 159 · 10-09 21:17Z | 410 | 27 / 29 | **no record** (pane 4's tab) | — (20 / 24 at 28) | yes iff ≤8 columns |
| 162 · 10-10 00:40Z | 468 | 30 / 31 | ~32, **estimated**: pane 4's tab had 7 columns just before 175 (175's measured 28 = 8 columns) | 19 / 23 | yes, 1-row margin |
| 8 (recycle) · 10-10 02:28Z | 448 | 30 / 32 | ≤76 (8, 12 and 148 were live) | — | yes iff ≤7 columns |
| 181 · 10-10 04:47Z | 391 | 28 / 29 | ~114, **estimated**: pane 4 was detached to its own OS window at 04:33Z (pane-spawns), so 181 was the 2nd column | 4 / 8 | yes |
| 182 · 10-10 05:10Z | 530 | 33 / 35 | ≥57, **estimated**: 57 measured at 17:50Z with the same 4 windows | 11 / 15 | yes |
| 193 · 10-10 15:02Z | 416 | 28 / 29 | ~45, **estimated**: tab 5 = 8, 12, 148, 183 and 193 | 11 / 15 | yes |
| 8 (recycle) · 10-10 15:18Z | 448 | 30 / 32 | ~45, **estimated**, same tab | 13 / 17 | yes |
| 194 · 10-10 16:01Z | 476 | 30 / 32 | ~45, **estimated** (7, 113, 134, 4 and 194) | 13 / 17 | yes |
| 195 · 10-10 16:19Z | 440 | 29 / 30 | ~57, **estimated**: tab 2 = 2, 3, 16 and 195. 6 columns were measured at 18:17Z, after 2 more arrivals | 9 / 13 | yes |
| 196 · 10-10 16:29Z | 421 | 28 / 30 | 37 to 45, **estimated** | 15 / 19 (at 37) | yes |
| 197 · 10-10 16:37Z | 478 | 30 / 32 | 32 to 45, **estimated** | 16 / 20 (at 37) | yes |
| 204 · 10-10 18:33Z | 413 | 28 / 29 | ~37, **estimated**: 6 windows in tab 4 at the 21:56Z heartbeat, all created by then | 14 / 18 | yes |
| 108 · 10-08 17:27Z | 528 | 34 / 35 | **no record** (pane 4's tab) | — | yes iff ≤6 columns |
| 108 (recycle) · 10-08 18:17Z | 650 | 40 / 41 | **no record** | — | yes iff ≤5 columns; the tightest constraint in the sample |
| 71 · 10-08 01:37Z | 330 | 23 / 23 | **no record** (pane 44's tab, the sibling of 70) | — | yes iff ≥23 columns |

**Result.** No set row has evidence of a top border beyond 24. Twelve rows with width estimates sit at rows 8 to 23; the tightest are 162 (23 at about 32 columns) and 197 (20 at 37). Five rows have no width estimate and are consistent only under a bound I cannot check (159, 8 at 02:28Z, both 108 rows, and 71). Of those, 108 at 18:17Z and 71 are the ones to watch. The four measured mangled rows sit at rows 25 to 29.

So, on the measurable subset, "top border outside the 24-line window" separates mangled from set perfectly. It is also the only one of the four hypotheses that predicts which arms fail.

## 6. Limits

- **Pane 70's width is not recorded anywhere I could find.** I searched transcripts, close-guard snapshots, `pane-spawns` and the heartbeat. The heartbeat keeps only the latest tree, and there are no local Time Machine snapshots. Its row stays undetermined.
- **Every set-row width is an estimate from the equalize model plus a nearby measured probe.** Operator closes are not logged, so a column count can only be bounded on one side.
- **Footer height at the exact poll instant is inferred, not observed.** The evidence is the reads at +8 s and +11 s, and the absence of any workflow or background row before 202's 18:20:21Z `Workflow` call. Every conclusion above holds with a 2-row footer, and a taller footer only makes a failure more likely.
