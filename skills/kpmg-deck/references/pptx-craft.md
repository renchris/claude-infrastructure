# PPTX craft — what is reachable, and how not to trigger "[Repaired]"

Read this when you hit a python-pptx limit or a deck opens with a repair dialog. Full research:
`lakehouse-lecture/docs/research/KPMG-BRAND-2026-08-08/B1-pptx-ceiling.md`.

## The "[Repaired]" dialog

PowerPoint offers to repair a file when schema validation trips, and it "repairs" by
**discarding the offending content** — so the deck opens with slides silently missing. In front
of a room, this is the failure everything here exists to prevent.

**The causes, in the order they actually occur:**

1. **Schema element order.** OOXML complex types are `xsd:sequence`, not `xsd:all`. An `<a:ln>`
   placed before `<a:solidFill>` inside `<a:spPr>` is invalid even though both are legal
   children. This is by far the most common cause of a hand-built defect.
2. **Orphaned relationship ids.** A slide references `rId5` that its `.rels` does not define.
   The classic source is deleting a slide by removing the `<p:sldId>` without dropping the
   relationship — which is exactly what naive delete-slide recipes do.
3. **Missing content-type entries.** A part in the package with no `Default` (by extension) or
   `Override` in `[Content_Types].xml`.
4. Duplicate shape ids, invalid EMU values, namespace mistakes, malformed comment parts.

**The safety recipe:**

- **Never hand-write or string-template OOXML.** Add slides only by cloning a layout:
  `prs.slides.add_slide(prs.slide_layouts[i])`.
- **Insert elements in schema order.** Use `insert_element_before(el, *successors)` with the
  successor list from the published sequence — never a bare `append`. `oxml.py` documents the
  sequences it relies on next to the functions that use them.
- **Run `verify.check_package()`** before shipping. It checks all four causes above.
- **Work on a copy.** Never overwrite a template.

The element sequences that matter:

```
a:spPr    xfrm, custGeom|prstGeom, [fill], ln, effectLst, effectDag, scene3d, sp3d, extLst
a:ln      [fill], prstDash, round|bevel|miter, headEnd, tailEnd, extLst
a:rPr     ln, [fill], effectLst, ..., latin, ea, cs, sym, hlinkClick, ..., rtl, extLst
a:bodyPr  prstTxWarp, noAutofit|normAutofit|spAutoFit, scene3d, sp3d|flatTx, extLst
a:tcPr    lnL, lnR, lnT, lnB, lnTlToBr, lnBlToTr, cell3D, [fill], headers, extLst
```

## What python-pptx cannot do, and the escape in `oxml.py`

| Need | API? | Function |
|---|---|---|
| Transparency on a fill | none | `set_fill(..., alpha=)` |
| Gradient with >2 stops or free positions | 2-stop only | `set_gradient(stops, angle)` |
| Line alpha / dash | partial | `set_line(...)` |
| Remove the theme's inherited shadow | none | `clear_effects`, `theme.flatten_effect_styles` |
| Deliberate shadow | none | `set_shadow(...)` |
| Letter-spacing (tracking) | none | `set_tracking(run, pt)` |
| Text alpha (ghosting) | none | `set_text_alpha(run, a)` |
| Kill the banded-blue table style | none | `strip_table_style(table)` |
| Table cell borders | none | `set_cell_border(cell, edge, ...)` |
| Delete / reorder a slide | none | `delete_slide`, `move_slide` |
| Slide background gradient | 2-stop only | `set_slide_background(...)` |

**Two traps found empirically, both of which produce valid XML and wrong output:**

- `set_text_alpha` must read the run's existing colour **before** clearing the fill. Clear first
  and the colour reads back unset, defaulting to black — so white ghosted text renders near-black
  on a dark ground. No structural check catches it.
- `strip_table_style` must **also** clear every cell border and fill explicitly. Removing the
  style reference alone leaves the renderer's own default black 1pt grid.

## The theme part

`theme1.xml` is the one part of a `.pptx` that can be **replaced outright** without repair risk:
a single self-contained part, stable schema, no relationships, no ids to keep consistent.

Rewriting it is what makes `schemeClr` references resolve to brand values. Without it, a deck
that correctly references `accent1` renders in Office's stock blue-grey. Both halves are needed:
reference the theme *and* rewrite the theme.

**python-pptx does not model the theme part** — it loads as a generic `Part` with raw bytes, not
an lxml tree. Consequence: any helper that parses `part.blob` on entry and serialises on exit
**cannot be composed**. Two such helpers in sequence each parse the original bytes, so the second
discards the first's edits — producing a deck with brand colours and stock fonts, valid
throughout, with no error anywhere. Parse once, mutate, write once (`theme.ThemeDoc`).

## Fonts

`fsType` in the OS/2 table governs embedding. `0x0004` = **Preview & Print only** — the font
cannot legally travel in an editable `.pptx`. Most corporate display faces are restricted this
way, which is why the Office-safe face is usually correct rather than a compromise.

**Never name a typeface the delivery machine lacks.** PowerPoint substitutes silently, the
substitute has different advance widths, and every measured text box re-flows — on the presenting
machine, after every check passed on the building one. `Deck._resolve_fonts` checks availability
and falls back, logging which it used.

## Autofit is not a solution

`MSO_AUTO_SIZE.TEXT_TO_FIT_SHAPE` on generated text does approximately nothing: PowerPoint
computes the `<a:normAutofit fontScale=>` value at **edit** time, inside the application, so a
generated file carries whatever you wrote and nothing recomputes it until a human opens that box.

Even if it worked it would be the wrong lever. Hierarchy is encoded by size ratio; autofit
changes one element's size to solve a local overflow, silently breaking that ratio, and sibling
slides shrink by different amounts. Measure first, then cut words.
