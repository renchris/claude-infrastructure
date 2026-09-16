#!/usr/bin/env python3
"""Find the overlay title bands by diffing an OFF capture against an ON capture.

Two rules, both load-bearing, both learned by getting them wrong:

  * Only rows INSIDE the terminal content area count. A window capture includes the macOS
    window chrome, and the chrome legitimately re-renders between two captures taken seconds
    apart (focus ring, traffic lights), so an unfiltered diff reports chrome rows as the first
    "band" and every coordinate derived from it lands in the title bar of the OS window.
  * A band must be one CELL tall. The feature's whole claim is that it occupies exactly one
    cell, so a run of changed rows that is not cell-height is evidence of a defect, not a band,
    and must not be silently accepted as one.

Prints the bands on one line as "y0..y1 h=N ..." and, when a fourth argument is given, writes
them to that path as a python-eval-able list of (y0, y1) pairs. Exits 1 if it finds none, so a
caller can use it directly as "did the band draw?".
"""
import sys
from PIL import Image

off_png, on_png, cell_h = sys.argv[1], sys.argv[2], int(sys.argv[3])
out_path = sys.argv[4] if len(sys.argv) > 4 else None
CHROME_PX = int(sys.argv[5]) if len(sys.argv) > 5 else 50   # rows of macOS chrome to ignore

a = Image.open(off_png).convert('RGB')
b = Image.open(on_png).convert('RGB')
if a.size != b.size:
    print(f'size mismatch {a.size} vs {b.size}', file=sys.stderr); raise SystemExit(1)
W, H = a.size
pa, pb = a.load(), b.load()
changed = [y for y in range(CHROME_PX, H) if any(pa[x, y] != pb[x, y] for x in range(0, W, 2))]

runs = []
if changed:
    s = p = changed[0]
    for y in changed[1:]:
        if y == p + 1:
            p = y
        else:
            runs.append((s, p)); s = p = y
    runs.append((s, p))

bands = [(y0, y1) for y0, y1 in runs if abs((y1 - y0 + 1) - cell_h) <= 2]
other = [(y0, y1) for y0, y1 in runs if (y0, y1) not in bands]
if out_path:
    open(out_path, 'w').write(repr(bands))
if bands:
    print(' '.join(f'{y0}..{y1} h={y1 - y0 + 1}' for y0, y1 in bands))
if other:
    print('OTHER ' + ' '.join(f'{y0}..{y1}' for y0, y1 in other), file=sys.stderr)
raise SystemExit(0 if bands else 1)
