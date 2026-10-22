#!/usr/bin/env python3
"""sheet.py <out.png> <title> <capture.json[:label]>... [--last N]

Round 4: lay several saved pyte screens (narrow-probe.py's captures/*.json) side by side as ONE
screen dump, each under a label row and separated by a 2-column gutter, and snap it to a PNG with
/tmp/narrow-design/snap.py --screen. Each tile keeps its own width, so a tile's right edge is its
pane's right edge (marked by the gutter's `│`). --last N keeps only each screen's bottom N rows
(the band and composer), so tall panes stay readable side by side.
Run with /tmp/acct-probe/venv/bin/python.
"""

import json, os, subprocess, sys

a = sys.argv[1:]
last = None
if "--last" in a:
    i = a.index("--last")
    last = int(a[i + 1])
    del a[i : i + 2]
out, title, specs = a[0], a[1], a[2:]
tiles = []
for sp in specs:
    path, _, label = sp.partition(":")
    d = json.load(open(path))
    rows = d["rows"]
    if last:
        rows = rows[-last:]
    label = label or os.path.basename(path).rsplit(".", 1)[0]
    tiles.append((d["cols"], label, rows))
H = max(len(r) for _, _, r in tiles) + 1
GUT = [[" ", "default", False], ["│", "f85149", False]]
sheet = [[] for _ in range(H)]
for ti, (cols, label, rows) in enumerate(tiles):
    lab = [[c, "79c0ff", True] for c in label[:cols].ljust(cols)]
    body = [lab] + [(r + [[" ", "default", False]] * cols)[:cols] for r in rows]
    body += [[[" ", "default", False]] * cols] * (H - len(body))
    for y in range(H):
        sheet[y] += body[y] + (GUT if ti < len(tiles) - 1 else [])
W = len(sheet[0])
tmp = out + ".screen.json"
json.dump({"cols": W, "rows": sheet}, open(tmp, "w"), ensure_ascii=False)
r = subprocess.run(
    [
        "/tmp/acct-probe/venv/bin/python",
        "/tmp/narrow-design/snap.py",
        "--screen",
        tmp,
        out,
        "--title",
        title,
        "--session",
        "r4sheet-" + os.path.basename(out).replace(".", "-"),
    ],
    capture_output=True,
    text=True,
)
os.remove(tmp)
print(out if r.returncode == 0 else r.stderr)
