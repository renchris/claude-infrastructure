#!/usr/bin/env python3
"""Did the title band MOVE when the content under it scrolled?

Three statistics, because the obvious one is wrong in both directions:

  * body_rows_pct  -- the POSITIVE CONTROL. The share of content rows that changed at all. If the
    scroll did not actually happen, this is ~0 and the band's stillness proves nothing.
  * edges_same     -- THE CLAIM, stated directly. The row just above the band, the band's first and
    last rows, and the row just below it, all byte-identical. A band that moved by even one pixel
    changes at least one of these; a band that merely re-drew its own text changes none of them.
  * band_rows_pct  -- a supporting figure, not the verdict. A cell-drawn band re-renders its glyphs
    when the pane's activity marker changes, flipping a handful of antialiasing pixels inside the
    text while the band itself is nailed in place (measured: 17 pixels, 8 of 45 rows touched, both
    edges identical). Requiring zero here would fail a working band, and requiring "any row
    changed" was the first version of this check and did exactly that.

A PIXEL fraction is not usable as the control either: a terminal row is mostly background, so a
scroll that moves every line of text changes only ~1.5% of sampled pixels. Rows are the right unit
for "did it scroll", pixels are the right unit for "how much of the band re-drew".

Prints three space-separated values; exits 1 if the band moved.
"""

import sys

from PIL import Image

before_png, after_png, bands_txt = sys.argv[1], sys.argv[2], sys.argv[3]
a = Image.open(before_png).convert("RGB")
b = Image.open(after_png).convert("RGB")
bands = eval(open(bands_txt).read())
if len(bands) < 2:
    print("0 0 0")
    raise SystemExit(2)

W, H = a.size
pa, pb = a.load(), b.load()


def row_changed(y: int) -> bool:
    return any(pa[x, y] != pb[x, y] for x in range(0, W, 2))


def pct_rows(rows) -> float:
    rows = list(rows)
    return 100.0 * sum(1 for y in rows if row_changed(y)) / len(rows) if rows else 0.0


def pct_pixels(rows) -> float:
    tot = ch = 0
    for y in rows:
        for x in range(0, W, 2):
            tot += 1
            if pa[x, y] != pb[x, y]:
                ch += 1
    return 100.0 * ch / tot if tot else 0.0


y0, y1 = bands[0]
band_rows = range(y0, y1 + 1)
body_rows = range(y1 + 3, bands[1][0] - 3)
edges = [y for y in (y0 - 1, y0, y1, y1 + 1) if 0 <= y < H]
edges_same = 0 if any(row_changed(y) for y in edges) else 1

print(f"{pct_rows(body_rows):.1f} {pct_pixels(band_rows):.2f} {edges_same}")
raise SystemExit(0 if edges_same else 1)
