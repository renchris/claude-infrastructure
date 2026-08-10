# Verification — the two kinds of defect, and why only one is checkable

## The split

**Machine-checkable:** structural validity, off-palette colour, type below the floor, off-slide
geometry, contrast, sibling drift, missing notes. All facts about the file. `verify.py` checks
them and an agent with no design judgment can act on the result.

**Eye-only:** collisions, a rule landing on text, ragged wrapping, emphasis on the wrong mark,
optical imbalance. **Nothing in `verify.py` can see any of these.**

> A green verify means the deck is not **broken**. It does not mean the deck is **good**.
> In this package's first build, five slides out of ten had the accent rule struck through the
> headline. All ten passed every structural check.

## The loop

```bash
# 1. build
python3 build_deck.py

# 2. mechanical gate — zero errors required
PYTHONPATH=~/.claude/skills/kpmg-deck/assets python3 -m kpmg_deck.verify deck.pptx kpmg

# 3. render
bash ~/.claude/skills/kpmg-deck/scripts/render.sh deck.pptx render 110

# 4. contact sheet, then LOOK with the Read tool
magick montage render/slide-*.png -tile 2x -geometry 620x349+6+6 -background '#888888' contact.png
```

Read the contact sheet first — it is the only view that exposes **inconsistency between
slides**, which is invisible one slide at a time. Then open any suspect slide at full size; a
10pt overlap is not resolvable on a contact sheet.

## What to look for, in order

1. **Collisions.** Any two elements touching. Most common between a headline and the element
   below it, and between a label and its caption.
2. **A rule or line on text** rather than clearing it.
3. **Clipped text.** A box too short for its content clips silently — no error anywhere.
4. **Ragged wrapping.** A one-word last line; a headline breaking mid-phrase.
5. **Emphasis on the wrong mark.**
6. **Sibling drift.** The same archetype looking different on two slides.
7. **Optical balance.** Bottom-heavy or lopsided slides.

## The renderer

LibreOffice headless → PDF → `pdftoppm`. Chosen because it needs no macOS Automation consent and
no GUI session, unlike driving PowerPoint via AppleScript.

**Known fidelity differences — do not report these as defects:**

- Font substitution when the named face is absent (Liberation Sans for Arial); metrics are close
  but not identical.
- Slightly different text layout at the sub-point level.
- Gradient banding and shadow softness render differently.
- Native charts are re-laid-out entirely — one of several reasons `charts.py` draws from shapes.

If a discrepancy matters, open the file in PowerPoint itself. LibreOffice is the fast loop, not
the final authority.

## Checking for "[Repaired]" without a human

`verify.check_package()` catches the four documented causes — corrupt members, malformed XML,
orphaned relationship ids, missing content-type entries — before PowerPoint ever sees the file.
A clean `check_package` plus a successful LibreOffice conversion is strong evidence; opening in
PowerPoint once before delivery is the confirmation.

## Extending the checks

Add to `verify.py` when a defect class is genuinely mechanical. Resist adding checks that need
judgment — a warning nobody can act on trains people to ignore the report, and a report nobody
reads catches nothing. The `empty shapes` check was narrowed to text boxes for exactly this
reason: flagging every autoshape's unused text frame made the output 90% noise.
