# Slot glance: which line 1 reads correctly at a glance (question a)

Date 2026-10-10. Read-only research slot. Scratch instruments: `/tmp/cvf-glance/{census,bcheck,d3yes,glyphs,render}.py`, `/tmp/cvf-glance/judge.sh`, mockup sources `/tmp/cvf-glance/m/*`.

## Answer

Put the verdict on line 1 of every terminal (✅ or 👤) close, with a verdict glyph: `✅ Good to close — …` or `❌ Not good to close — …`. Relay the ledger rung verbatim on line 2. This is design A with C's verdict glyph, called **A′** below. Enforce it in the hook with a narrow floor, not a position window. The floor blocks only the contradiction: a close whose verdict is no while line 1 reads as done. Two existing arms then need small accommodations, because today they would block the A′ close and pass the misleading one:

- D3 blocks 34.2% of honest no-lines once they move to line 1.
- D6 `line-1-rung` would fail every ❌ line 1.

Conviction: **85%** that A′ beats B and C. **75%** that ❌ is the right glyph for no.

## What was measured

All figures are measured. They come from `python3 -I /tmp/cvf-glance/census.py 30`, which reuses `scripts/measure-closes.py`'s corpus walk and close extraction. The corpus is 30 days across five roots, including `~/.claude-next4`, with `~/.claude-next` deduplicated by realpath. That is 4,921 transcripts, of which **5,216 closes carry an explicit `good to close: yes|no`**. The population is every turn-final close with a verdict, not only the closes D6 can reach. The ✅/👤 line-1 subset is used as a proxy for those.

| Fact | Value |
|---|---|
| Verdicts | 3,435 no · 1,781 yes |
| Verdict position | line 2: 4,233 · line 3: 401 · line 4: 90 · line 5+: 463 · **line 1: 29** |
| No-closes whose line 1 carries ✅ (the screenshot defect) | **297 / 3,435 (8.6%)**. That is 21.4% of all ✅-line-1 closes (297 of 1,386) |
| 👤 on line 1 | 253 yes / 268 no, a coin flip. 329 of 521 say "done" on line 1 |
| No-closes in the ✅/👤 line-1 subset whose line 1 reads done (`bcheck.py`) | **303 / 565 (53.6%)** |
| Verdict on line 2 with no blank line before it, so it renders inside line 1's paragraph | 2,856 / 4,233 (67.5%) |
| Line-1 length in chars, median / p75 / p90 | 128 / 159 / 205. 87.9% are longer than 85 chars |
| D3 replay: existing no-lines moved to line 1 | **1,175 / 3,435 (34.2%) would be blocked** |
| D3 replay: existing yes-lines moved to line 1 | 215 / 1,781 (12.1%). Top tokens: "yours" 135, "still open" 22. 103 of the 215 have the token only after `follow-on:` |

**Screenshot geometry (measured from `~/.reso/close-shape/two-closes-2026-10-10.png`).** The panes are about 57 columns wide, with 55 text columns after the `● ` gutter. The brief assumed about 85. The renderer in `render.py` reproduces the left close's six visual rows exactly as the screenshot shows them, so the mockups below are calibrated. At 55 columns the median line 1 wraps to three rows.

**Exact source text** (from the transcripts, not from the image):

- Left close, session 44091255, 16:15:41Z: line 1 and the verdict are separated by a single `\n`. Claude Code renders that as a new row with no gap, so both sit in one visual block.
- Right close, quaternary 3bd7aa3b: has a blank line between them. Its line 1, `✅ Yes, it's safe to close.`, is already verdict-first in all but name.

## The glance test

What the eye takes in first is the leftmost glyph's colour, then the first 3–6 words. The ✅ is the only coloured mark at the head of each message, so it is read before any word.

| Shape | First cue, no-case | First cue, yes-case | Yes and no distinguishable at a glance? | Wrapping | Rung info lost |
|---|---|---|---|---|---|
| Status quo | green ✅ + "Complete … nothing to do" | green ✅ + "Yes, it's safe to close" | **No.** Both are green and done-worded. The no is word 4 of visual row 3 | the verdict lands on row 3 of 6 | none |
| B (rung kept on line 1) | green ✅ + "Not good to close" | green ✅ + rung clause | **No.** The glyph contradicts the words. B is only coherent if the glyph changes, and then it is C | answer in row 1 | the clause is replaced |
| C (one combined line) | red ❌ + "Not good to close" | green ✅ + "Good to close" | Yes on row 1. But a **second green ✅ reappears on row 3** inside the same paragraph | about 3 rows at 57 columns; the rung is truncated to a suffix | the rung's state clause and work clause shrink to "ledger: ✅ …" |
| **A′** (verdict first, rung on line 2) | red ❌ + "Not good to close" | green ✅ + "Good to close" | **Yes.** Colour and the first word differ ("Not" vs "Good"). The rung sits below a blank row, labelled | answer always in row 1, whatever the width | none (the rung is verbatim on line 2) |

**Why "Not good to close" rather than "Good to close: no".** With the label form, the first three words of both closes are identical ("Good to close"), and the polarity is word 4. That is the same failure in miniature. Both forms already satisfy `close_shape_missing` (verified by running `judge.sh` on LA and RA), so the template can lead with "Not" and the legacy label forms stay accepted.

## Which glyph a no should carry

| Glyph | Verdict | Reason |
|---|---|---|
| **❌** U+274C | **Use** | The conventional opposite of ✅. Red, X-shaped, and needs no VS16 selector (`east_asian_width` = W, the same as ✅). It is not in the ledger's rung vocabulary (✅ ⛔ 🔧 📦 🚀 👤 📤). In the repo it means only "fails / not eligible" (`bin/cc-eligible`, lint scripts), which fits a "no" answer. Corpus use on line 1 today: 0. |
| 🛑 | second | "Stop, don't close" is semantically exact. But it is a red octagon, which at one-cell size is close in colour and shape to ⛔. |
| 🔶 | third | Distinct colour, but it encodes nothing that reads as "no". |
| ⛔ | **reject** | It means "Blocked — need your call". Many no-verdicts are owned by a peer or by this session (left close: pane 182 and this pane). ⛔ would tell the operator a decision waits on them when none does. |
| none | reject | An absent green mark is a weaker cue than a present red one, and D6 and the new floor both need a token to anchor on. |
| ⏳ | reject | Already taken by /wrap's "working or idling" axis and the gates' todo rows. |

Risk, stated rather than measured: a red ❌ may push models away from honest no-verdicts. The yes:no ratio in the corpus after rollout is the falsifier.

Consistency point: the rule already defines ✅ as "a safe-to-close assertion, not a vibe" (`CLAUDE.rules.slim.10-session-close.md:9`). So the verdict ✅ means exactly what the rung ✅ is documented to mean, and a rung ✅ sitting on a no-close contradicts the rule's own definition.

## Act marker, the other rungs, blank lines

- **CC_ACT_WINDOW=3.** A′ order is verdict (1), rung (2), `▶` (3). That is the same count as today's rung (1), verdict (2), `▶` (3), so D7 compliance does not move. C frees a slot (`▶` on line 2) but pays for it with the second ✅. Blank lines are not counted, so a blank row after line 1 costs nothing.
- **Scope of verdict-first** is exactly where a verdict slot already exists: terminal ✅/👤 closes after written work, the D6 population. ⛔, 🔧, 📦 and 🚀 closes keep the rung on line 1 and need no verdict. Their glyphs do not read as done, and ⛔ is itself the "no, needs you" answer. One wording edge: `📦 Done, but only on a branch`, and corpus lines like `📦 … is complete and live`, lead with done-words. D6 does not reach these, so they stay a prose-only concern.
- **👤 yes-close:** `✅ Good to close — …` on line 1, then `👤 My side is done & landed — N steps need you` on line 2. The operator's steps stay visible on line 2 and in the OPERATOR block.
- **Blank line after line 1:** recommend it in the template, because 67.5% of closes today weld the verdict into line 1's paragraph. Do not enforce it: that is shape-adjacent, and a false FAIL is worse.

## Replay of the current hooks

Command: `bash /tmp/cvf-glance/judge.sh`, which replicates D3's `CA_SETTLED`/`CA_RETRACT`, D6's containment test and `close_shape_missing`/`close_act_missing` sourced from `hooks/lib/close-shape.sh`.

| Mockup | D3 | verdict | D6 line-1-rung (✅) |
|---|---|---|---|
| L0, the real left close | pass | ok | pass. **The misleading close passes every arm today** |
| LA (A′ no-case) | **BLOCK** ("good to close" + "still open") | ok | **MISS** |
| LB (B) | BLOCK | ok | pass |
| LC (C) | BLOCK | ok | pass (contains ✅) |
| RA (A′ yes-case) | pass | ok | pass |
| RA with a follow-on that is "yours" | **BLOCK** | ok | pass |

Accommodations A′ needs. These belong to the question (c) slot and are listed here only so the recommendation is complete:

1. **D3:** exempt a line 1 that carries a negative verdict. The pattern `not good to close|good to close\W*no\b` matches 3,435 of 3,435 no-lines (measured). For a yes verdict line, judge `CA_RETRACT` only before `follow-on:`, or replace it with a narrow "the verdict value contains both yes and no" hedge test. Without one of these, 12.1% of yes-lines become new false FAILs.
2. **D6:** test rung containment over the first two non-blank lines instead of line 1 alone.
3. **The new floor (the operator's actual ask):** when the verdict is no, block if line 1 contains ✅, or if line 1 does not carry the negative verdict and matches `✅|complete|nothing (left|more|else)? to do|safe to close|^…yes|all done`. Replay (`bcheck.py`): it fires on **303 of 565 no-closes in the ✅/👤 subset, and on 0 yes-closes**, so it can never block the right-hand close. One false-positive class seen in the sample: `📦 Not safe to close: …`. Add `not safe to close` to the negative pattern.
4. Prose and templates (`close_shape_template`, `close_act_template`'s "line 1 = the ledger rung readout", `commands/wrap.md:174`, and the S1/S2 slot table) must swap S1 and S2. That is the question (e) slot.

A position window (`CC_VERDICT_WINDOW=1`) is not recommended as the floor. Only 29 of 5,216 closes put the verdict on line 1 today, so it would block about 99% of honest closes until the template takes hold. The contradiction floor blocks only the misleading ones.

## Mockups (rendered at the measured 57-column width; `render.py`)

Legend: `●` is Claude Code's message bullet, and each row is one terminal row. In the A′ yes mockup, the rung's work clause is illustrative.

**LEFT, status quo (the screenshot, reproduced row for row)**
```
● ✅ Complete & live on trunk — nothing to do. The
  reconciler is now in act mode, cut over this session.
  Good to close: no — the FLEET_V2 programme still has
  two open steps, and pane 182 will mail this pane before
  it lands its change to the reconciler. If this pane
  closes, that mail goes nowhere.
```
**LEFT, A′ (recommended)**
```
● ❌ Not good to close — two FLEET_V2 steps are still
  open, and pane 182 will mail this pane before it lands
  its reconciler change (I review it); closing now drops
  that mail.

  Ledger: ✅ Complete & live on trunk — the reconciler is
  in act mode, cut over this session.
```
**LEFT, B**
```
● ✅ Not good to close — two FLEET_V2 steps are still
  open, and pane 182 will mail this pane before it lands
  its reconciler change (I review it); closing now drops
  that mail.
```
**LEFT, C**
```
● ❌ Not good to close — two FLEET_V2 steps are still
  open and pane 182 will mail this pane before landing
  its reconciler change · ledger: ✅ complete & live on
  trunk
```
**RIGHT, status quo** (B leaves the yes-case unchanged)
```
● ✅ Yes, it's safe to close. This session has no open
  work.

  Good to close: yes. Nothing of mine is open. Follow-on:
  none new.
```
**RIGHT, A′ (recommended)**
```
● ✅ Good to close — nothing of mine is open; follow-on:
  none new.

  Ledger: ✅ Complete & live on trunk — research gate row
  15 checked; the repo is unchanged.
```
**RIGHT, C**
```
● ✅ Good to close — nothing of mine is open; follow-on:
  none new · ledger: ✅ complete & live on trunk
```
**👤 no-close with an act, A′ (D7 window is still satisfied: `close_act_missing` returns ok)**
```
● ❌ Not good to close — 2 steps need you before this
  pane's work is real; both are below.
  👤 My side is done & landed — 1 runnable now, 1 needs
  your call.
  ▶ Run this:
  `cc-do 27b7e8f0c9aa`
```

The `Ledger:` prefix on line 2 is optional. It moves the rung's green ✅ off the start of the row and labels it as repository state rather than the verdict. D6 containment tolerates the prefix.

## Ranked recommendation

1. **A′: verdict-first, ❌/✅ verdict glyph, rung verbatim on line 2, blank row after line 1 (recommended in the template), plus the contradiction floor.** Conviction **85%**. It is the only shape whose first cue (colour and first word) separates yes from no in both screenshot cases at any width, and it loses no rung information. It keeps the act window, and the Pyramid "governing thought first" order holds for every terminal close. Its costs: one extra line of redundancy on ✅-yes closes (two ✅ glyphs), and the D3/D6 accommodations.
2. **C: one combined line.** About 10%. It shares A′'s first cue and needs no D6 change (it contains the rung). But the second ✅ returns inside the wrapped paragraph, the rung is compressed, and line 1 grows to about 3 rows.
3. **B: rung kept on line 1, done-words forbidden.** About 5%. A green ✅ leading "Not good to close" fails the glance test it exists to pass. Made coherent, it becomes C.

Glyph for no: **❌ (75%)**, then 🛑, then 🔶. ⛔ is rejected because it would misread as "your call".

## Concerns and deviations

- The brief stated about 85 columns. The screenshot measures about 57, with 55 text columns. Mockups at both widths were checked, and the conclusions hold at both.
- The corpus population is every close with a verdict, not D6-eligible origin closes; the ✅/👤 line-1 subset stands in for those. Ledger RUNG is not recorded in transcripts, so the line-1 glyph substitutes for it.
- In the left case, `operator-readout.sh` can render `✅ SAFE TO CLOSE — nothing of mine is open` from git beside a model-written no. It did not appear in the screenshot, which suggests `CERT_WROTE` was not 0 on that turn, but it is the same glance hazard. That is for question (c).
- The ledger emits ✅ "nothing to do" from git while the task is still open: the left close's FLEET_V2 steps. That is question (b). A′ makes the ledger's ✅ harmless at a glance but does not make it true.
