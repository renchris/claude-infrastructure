# Goal-arm read-back: skeptic slot

Brief: try to refute (a) the root cause (a 24-row read window cannot see the top border of a tall composer) and (b) design D1 (a bigger window, read only when the small one shows a bottom border and no top, and a box accepted only if it is shaped like a composer). Then compare D1 with D2 (read the whole visible screen) and D3 (raise the window to about 80 rows), and name the smallest change that keeps the fail-closed property.

The code moved while I worked. I tested four readers side by side:

- **today**: `composer_content` at 16b6b441f, with N = 24.
- **D3**: the same function with N = 80.
- **D2**: the same function over the whole screen file.
- **D1**: the committed versions, 373bb4230 and then **bdc2f865b**. bdc2f865b is the current HEAD and is what the verdicts below refer to.

**Method.** I typed nothing into any pane. Pane screens were read only with `kitty @ get-text` and `kitty @ ls`. Scratch files are in `/tmp/gar-skeptic/` (`bin/readers.sh`, `bin/mk.py`, `screens/K*.txt`, `results-K.tsv`, `corpus-d2.tsv`). Note that this directory already held another agent's files from 13:40 (`analyze.py`, `ls.json`, `screens/11.*` and others). I left them untouched.

---

## 0. Short answer

| question | verdict |
|---|---|
| (a) Is the 24-row geometry the root cause? | **It survives for 4 of the 5 mangled rows.** Pane 70 is not explained by geometry, as the forensics slot also found. The commit message of 373bb4230 says "All 5 … are this shape", which overclaims; REPORT.md's table is accurate. |
| (a) Is the composer height-capped (the comment near `paste_readback_ok`)? | **The "~10 body rows" claim is refuted for CC 2.1.293 on 62-row panes.** Pane 203 shows 22 rows and pane 202 shows 21, both unscrolled. Whether a larger cap exists is **unmeasured**. |
| (a) Does a goal taller than the screen still fail after D1? | **Yes. It also fails after D2 and D3.** At today's live geometry (21×46) a payload of about 645 or more raw chars overflows the screen (estimated). No design that only changes the window can read it. |
| (b) Can D1 fail open? | My one realistic-looking fail-open was a trust dialog, whose selector has no number, under an echoed prompt (K5). The lead found the same hole independently, and **bdc2f865b closes it** (`❯` under the last border means a dialog, on both paths). The remaining fail-open is the dialog-above-composer shape (K6). D2 and D3 share it, and the code before the fix already had it for short composers. |
| (b) Can D1 fail closed on a healthy composer? | Yes, in one shape that matters: a composer that is **capped and scrolled** (K1, K4b). Check (iii) needs `❯` on the first row, so D1 says UNKNOWN where D2 and D3 match through the tail form. This only matters if CC caps above about 20 rows, which is unmeasured. Other cases (bash mode, soft-wrap, label-wrapped tops, footers of 24 or more rows) fail closed exactly as before. |
| D2 and D3 | **Refuted as property-preserving.** K14 uses a physically consistent 24×62 screen, the real 2026-10-10 background-work dialog of pane 175. That dialog's top rule is `▔` (U+2594), not `─`. With an assistant message quoting an empty composer higher on screen, D2 and D3 read **EMPTY**, while today and D1 read UNKNOWN. |
| Smallest change that keeps the property | **D1 as landed in bdc2f865b.** D2 and D3 are smaller diffs but do not keep the property. |
| Conviction for D1 (bdc2f865b) as the design | **80%**. The 20% is mostly the unmeasured CC height cap (§1.2), plus the shared dialog-above-composer shape (§2.3). |

---

## 1. (a) The root cause

### 1.1 Each mangled row

All 5 `goal-arm` mangled rows say `saw: <unreadable>` (measured: `grep '"class":"goal-arm"' ~/.claude/logs/handoffs.jsonl`). Tally: 47 set, 5 mangled, 3 unverified.

| pane | my evidence | verdict |
|---|---|---|
| 203 | `evidence/pane203-midturn-32col.plain.txt`, re-run through today's code: rc 1 at N = 24, MATCH at N ≥ 26 (measured, `bin/readers.sh`) | geometry |
| 202 | I counted rows on the operator's screenshot `~/.reso/goal-arm/unsubmitted-goal-2026-10-10.png`. **21 body rows**, head visible (unscrolled). **4 footer rows**: status, mode, blank, and a workflow progress row. So the top border is 27 rows from the bottom (measured by eye on the image). | geometry |
| 175 | The close-guard snapshot `20261010T031422Z-win175.txt` (27 min after the arm) is **24 columns × 62 rows** (measured: `wc -l` and the longest stripped row). The forensics slot puts the width at 28 at arm time, from the firing session's own `get-text` +8 s. | geometry (one column short) |
| 176 | forensics slot: 24 columns, 29 rows | geometry |
| 70 | No width record survives (forensics slot). The 347-char goal fails by geometry only at ≤25 columns. Pane 71, split 40 min later, armed fine at ≥23 columns. A Bash call in that session took 17 s (00:56:54Z to 00:57:11Z) and covered the whole read-back window. | **undetermined.** A blocking dialog fits the evidence as well as geometry does, and a dialog is exactly the case where UNKNOWN is correct. **Do not "fix" pane 70.** |

Every recorded read-back was `<unreadable>`, and none was a content mismatch. That fits geometry and also fits a modal. So for pane 70 the geometry claim rests on inference, not measurement.

### 1.2 The "height-capped, follows the cursor" claim

The claim is in `scripts/handoff-fire.sh` around lines 4506 and 4578, and in `scripts/lib/cc-tui.sh` line 311. It came from 94aa89bc6 (2026-08-25), which inferred a cap of about 10 body rows from a read-back that started mid-word at offset 85.

The 2026-10-10 evidence is two independent observations, pane 203's capture and pane 202's screenshot. Both show 21 to 22 body rows, **unscrolled** (the first row is `❯ /goal …`), in 62-row panes running CC 2.1.293. The binary was `~/.claude-293/node_modules/.bin/claude` for panes 202, 203, 8 and 206 (measured: `kitty @ ls` foreground processes).

So the ~10-row cap does not hold today. **Whether any cap exists, and at what height, is unmeasured.** I could not settle it, for two reasons:

- My attempt to read the CC 2.1.293 bundle for the input-height logic was **denied by the auto-mode classifier**.
- The brief forbids typing into a pane to test it.

A public web search found no documented cap. The comments are stale either way.

**Why it matters for D1.** If CC caps the box at a height above about 20 rows and scrolls to the cursor, the first visible row is a two-space continuation, not `❯`. D1's (iii) then refuses the box (K1 and K4b in §2), while D2 and D3 return the tail and `paste_readback_ok`'s tail form matches. If the cap is 20 rows or less, the box fits in 24 rows, the common path handles it, and D1 never runs. **The one measurement that would settle this:** read, without typing, any pane whose composer holds a draft of 40 or more rows, or the next tall arm, and see whether the first box row is `❯`.

### 1.3 Geometry moves, and longer goals still fail after D1

**Measured with `kitty @ ls` at about 22:00Z:** panes 2–4, 7 and 195–205 are now **21×46**. Pane 203 was 32×62 at 18:28Z. The same pane changed width and height within hours.

At 21×46 the live screens show the composer's bottom border with 4 rows under it (measured: `kitty @ get-text`, panes 202 and 203).

**Thresholds, estimated** with a greedy word wrap at width − 2. It is calibrated on pane 203: 544 raw chars give 22 rows at 32 columns, and so did CC. Chars are raw, as in the ledger's `condition N chars`.

| pane | today (24 rows, 2-row footer) fails from | the box overflows the whole screen from (4-row footer + 1 spinner row) |
|---|---|---|
| 21×46 | ~340 | **~645** |
| 24×46 | ~395 | ~765 |
| 28×46 and wider, any height | ~465 / 520 / 625 (at 28 / 32 / 37 columns) | above 800, where the paste collapses to a one-row chip anyway |

The ledger has 4 of 55 conditions of 600 chars or more: 618, 633, 639 and 650 (measured, same grep).

At 21×46 a 700-char payload (K4) reads UNKNOWN in **every** design, because without a cap the top border is off-screen and kitty's alternate screen has no scrollback. So D1 fixes the incident band from about 340 to 645 chars at today's geometry. The band from about 645 to 800 stays MANGLED unless the condition is short. `commands/handoff.md` already asks for a pointer: "Keep COND a POINTER". A pre-fire check could compare the payload with the target pane's capacity and say so loudly.

---

## 2. (b) Screens built to break D1, D2 and D3

All rows below are measured with `/tmp/gar-skeptic/bin/readers.sh <screen> <payload>`, saved in `results-K.tsv`.

- **MATCH** means `paste_readback_ok` accepts the read, so a CR would be sent.
- **EMPTY** means the pre-paste gate would type.
- D1 is bdc2f865b. 373bb4230 differs only on K5, K5s and H2, all three MATCH there.

| screen | what it is | today | D3 (80) | D2 (screen) | D1 |
|---|---|---|---|---|---|
| K0 | pane-203 capture (32×62) | UNKNOWN | MATCH | MATCH | MATCH |
| K1 | capped composer scrolled to the cursor (head off; 32×62) | UNKNOWN | MATCH (tail) | MATCH (tail) | **UNKNOWN** (iii) |
| K4b | same at 21×46, 700 chars | UNKNOWN | MATCH (tail) | MATCH (tail) | **UNKNOWN** (iii) |
| K4 | 700 chars at 21×46, no cap, top border off-screen | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN |
| K4c | the 472-char goal at 21×46 (fits, 4-row footer) | UNKNOWN | MATCH | MATCH | MATCH |
| K2 | tall multi-paragraph draft, blank rows `""` | UNKNOWN | TEXT | TEXT | TEXT |
| K3 | 1-row empty composer over 23 footer rows (19 teammates listed) | UNKNOWN | EMPTY | EMPTY | EMPTY (bottom border just inside 24; with 20 or more teammates D1 → UNKNOWN) |
| K3b | tall goal over 7 teammates | UNKNOWN | MATCH | MATCH | MATCH |
| K7 | labelled top rule over a tall goal | UNKNOWN | MATCH | MATCH | MATCH |
| K8 | bash-mode (`!`) tall draft | UNKNOWN | TEXT | TEXT | UNKNOWN |
| K10 | pane-203 capture soft-wrapped one column narrower (31) | UNKNOWN | TEXT (no match) | TEXT (no match) | UNKNOWN |
| K12 | tall composer of blank lines only | UNKNOWN | EMPTY | EMPTY | EMPTY (it really is a composer) |
| K13 | payload row starting with spaces | UNKNOWN | TEXT | TEXT | TEXT |
| **K14** | **real 24×62 bgwork dialog (`▔` rule) of pane 175, top 8 transcript rows replaced by an assistant message quoting an empty composer** | UNKNOWN | **EMPTY** | **EMPTY** | UNKNOWN |
| K14b | same quote placed just above the dialog | UNKNOWN | **EMPTY** | **EMPTY** | UNKNOWN |
| K5 | col-0 rule + echoed `/goal` (22 rows) + blank + trust-style dialog, selector without a number | UNKNOWN | MATCH | MATCH | UNKNOWN (373bb4230: **MATCH**) |
| K5b | same, numbered selector | UNKNOWN | MATCH | MATCH | UNKNOWN |
| K5c | same, dialog taller than 24 rows | UNKNOWN | MATCH | MATCH | UNKNOWN |
| K5s / H2 | short echo over a dialog (the bats hostile shape) | **MATCH** | MATCH | MATCH | UNKNOWN (373bb4230: **MATCH**) |
| K6 | real 2.1.284 bgwork dialog body ABOVE a visible tall goal composer | UNKNOWN | MATCH | MATCH | MATCH |

### 2.1 How realistic each construction is (measured on 215 unique non-empty screens)

The 215 screens are both close-guard snapshot stores, deduplicated, plus 27 live panes captured with `kitty @ get-text --ansi`, the repo's screen fixtures and the pane-203 evidence.

- **The composer prompt is `❯` followed by U+00A0, and transcript echoes and dialog selectors use `❯` followed by an ordinary space.**
  - Every live composer is `❯ ` (27 of 27).
  - 64 of 64 column-0 rules followed by a `❯` row are `❯ `.
  - 0 column-0 rules are followed by an echo (`❯ `).
  - The 6 rows that start with `❯ ` are transcript echoes (5 fixture `❯ /exit` rows, 1 live). The live one sits under a 1-space padding row on a grey background, not under a rule.
  - So the K5 family, the only fail-open D1 had, has **0 natural occurrences**. bdc2f865b now refuses it anyway.
  - Optional hardening: make (iii) require `❯ `. That kills the whole echo family by construction, and if CC ever changes the glyph spacing it fails closed.
- **Blank rows inside a real multi-paragraph draft render as `""` (length 0), not as two spaces.** Measured on a live 156-column operator draft; I took only its structure and recorded no text. So the brief's original (iv) ("every row two-space indented") would have refused real drafts. The committed (iv) accepts blank rows, which is correct. The image chip renders as an indented `  [Image #1]` row inside the box (same screen), so it passes (iv).
- **0 of 55 unique healthy composers have a `❯` anywhere under the bottom border** (measured). bdc2f865b's `gb` check on the common path therefore changes no measured healthy verdict. Two shapes I could not observe:
  - CC's slash-command typeahead open under a `/goal` box. Pane 203's capture and pane 202's screenshot both show no typeahead after the paste.
  - A user statusline that draws `❯`. That would turn every read on the pane into UNKNOWN: fail closed, but a loss of liveness.
- **The 2.1.293 background-work dialog's top rule is `▔` (U+2594), not `─`.** It appears in 8 snapshots, from 2026-10-03 and 2026-10-10 (measured: `grep -l '▔▔▔'`). So the bottom of that screen has no border for any reader. Only D2 and D3 then fall back to whatever two `─` rows sit higher up, which is K14. An assistant quoting a composer is ordinary in this repo, where sessions debug composer screens. Whether 2.1.293 *permission* dialogs also use `▔` is unmeasured. The only permission-dialog snapshots in the corpus are from August, and they use `─`. If they do use `▔`, D2 and D3 are exposed on every permission screen.
- **Corpus replay, today vs D2:** 213 non-empty files in `~/.claude/logs/composer-snapshots` (784 of the 997 are 0 bytes). Exactly 1 verdict changes: win527, UNKNOWN → 586-char TEXT, which is non-empty and so holds (measured: `bin/corpus.sh`, `corpus-d2.tsv`). The corpus therefore shows no natural instance of K14. The hazard is constructed, but the screen is physically consistent: 62 rows, a real dialog and a real transcript.
- **The harness pads of the modal-failclosed slot overstate D2's exposure.** `/tmp/gar/modal-harness/padded/*` stacks 72 transcript rows *above* full-height modal screens. A real kitty alternate screen cannot show those rows. So their "today at 120 reads EMPTY" rows (22 of 186 realistic-pad rows flip from UNKNOWN to EMPTY under D2 and D3, measured) are not evidence by themselves. K14 is the physically consistent version of the same hazard.

### 2.2 The fail-closed property was not fully held before the fix either

K5s and H2 build the bats file's own hostile shape: a short echo of the payload under a column-0 rule, then a dialog. The **pre-fix 24-row code reads it as MATCH** (measured), and so did 373bb4230's common path. bdc2f865b is the first version that refuses it.

Two things follow:

- The property "a modal never reads EMPTY or as the payload, even under a hostile transcript" is something D1 now holds and the code before it did not.
- Earlier, `tests/composer-tall-readback.bats` "every real modal fixture, alone and under a hostile transcript …" would have been red against 373bb4230 on the trust fixture. I replayed it outside bats (`bin/batsrepl.sh`), because cc-bats deferred my run on load (2 roots, so a deferral, not a result). The replay gives UNKNOWN for all 9 fixtures at bdc2f865b.

### 2.3 What no design closes: a dialog drawn above a visible composer

Pre-existing screen shapes show it: M15 (`teammate-run2-exitmodal-WITH-COMPOSER`, a real capture) and M33.

- The composer stays on screen under the dialog, so every reader reads the composer truthfully. It is EMPTY today for a short composer, and MATCH under D1, D2 and D3 for a tall one (K6, M31).
- Whether keystrokes go to the dialog or to the composer is a focus question no screen read answers. Check (v) only looks *under* the bottom border, so it cannot see a selector above the box.
- D1 widens this from short composers to tall ones. It is not new.
- For the /goal arm it needs a dialog to appear within the ~4 s read-back window of a freshly engaged session. The only dialog captured in this shape comes from `/exit`, so this is unlikely on the arm path.
- Follow-up, not part of this fix: refuse when a dialog footer such as `Enter to confirm` or a `❯ N.` selector appears anywhere above the box. Measure that against the 55 healthy screens first.

---

## 3. D1 vs D2 vs D3

| | D1 (bdc2f865b) | D2: drop `-n` (visible screen) | D3: `-n 80` |
|---|---|---|---|
| size | about 45 lines in `composer_content`, about 30 in `LR_SCREEN_SH`; a second read only on the fallback | one token (keep `FIRE_COMPOSER_READLINES` as an opt-in) | one constant |
| incident band (≈340–645 chars at 21×46; ≈520–800 at 32×62) | fixed | fixed | fixed |
| capped and scrolled tall box (K1, K4b; only if CC caps above ~20 rows) | **UNKNOWN** | MATCH (tail) | MATCH (tail) |
| box taller than the screen (K4) | UNKNOWN | UNKNOWN | UNKNOWN |
| rule-less dialog under a quoted or printed composer (K14) | UNKNOWN | **EMPTY** | **EMPTY** |
| echo-over-dialog constructions (K5*, H2) | UNKNOWN | MATCH | MATCH |
| dialog above a visible composer (K6) | MATCH | MATCH | MATCH |
| scrollback (CC in `/tui default`, main screen) | may read 200 rows of scrollback, but takes the *nearest* border above the live bottom and needs (ii)–(v), so stale frames are not reached | visible screen only, by construction | may read scrollback with no shape checks |
| same window as cc-tui, lcs, it2-kitty and observe.py | no | yes. Those copies therefore carry K14 today (not tested here; flagged) | no |

**Answer: D1.** D2 and D3 trade about 70 lines for an EMPTY verdict on a dialog screen. EMPTY is the direction that types a paste into a single-key prompt, where the payload's digits (`1..N`, `143`) are option keys. For the recycle gate it also types `/exit` plus a CR into a dialog whose default is "1. Exit and stop tasks".

D1's gate, which needs a bottom border inside the bottom 24 rows, is itself load-bearing. It is why D1 never falls back to transcript rules when the bottom element has no `─` rule. Any later "simplify to read the whole screen" change loses that.

## 4. Recommendations, in priority order

1. **Keep D1 as in bdc2f865b.**
2. **Measure the 2.1.293 composer height cap, read-only.** If it scrolls above ~20 rows, add a tail-only acceptance to the fallback: first row a continuation row, top a column-0 rule, (iv) and (v) hold. That read may satisfy only `paste_readback_ok`'s tail form and must **never** count as EMPTY. Until then, the current 21×46 panes are covered only up to the cap.
3. **Make the band D1 cannot reach loud.** If the payload's estimated rows plus about 7 exceed the target pane's lines (from `kitty @ ls`), warn before pasting. Keep goal conditions to pointer length (≤ ~300 chars).
4. **Correct the overclaim** in 373bb4230's message (pane 70 is undetermined), and the stale "height-capped (~10 body rows)" comments in `handoff-fire.sh` and `cc-tui.sh`.
5. **Optional:** have (iii) require `❯ `. Port D1's shape checks, or at least the "no border near the bottom ⇒ UNKNOWN" gate, to the whole-screen copies, which carry K14 today. That is a separate change with its own blast radius, as the siblings slot says.

## 5. Deviations and incidents (stated plainly)

- **I ran the user's `claude` zsh function once by accident** (`claude --version 2>/dev/null | head -2`, inside a locate command). It printed nothing.
  - `CLAUDE_CONFIG_DIR` and `CC_ACCOUNT_PINNED` were set in my shell, so the routing and launch-recording branch should have been skipped, and `_claude_pinned --version` ran instead.
  - `~/.claude/route/route.jsonl` has `interactive desk -> none` and `launch pinned` rows at 21:57:11Z and 21:57:12Z. I could not confirm whether they are mine, because inspecting the helper functions further was denied by the classifier.
  - The operator should treat those two rows as possibly spurious.
- The auto-mode classifier denied three things: reading the CC binary, printing full ledger rows, and grepping session transcripts. I did not work around any denial. The cap question (§1.2) is open because of the first.
- `bin/batsrepl.sh` removed its own `mktemp` directory under `/tmp/gar-skeptic/` once. That was the only removal. A later `bash -c` debug call was blocked by the removal safety check and did not run.
- No repo file was edited except this one.
