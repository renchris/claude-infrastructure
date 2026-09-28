#!/usr/bin/env python3
"""design_gate.py: the design half of VERIFY. It reads the page's own layout record (window.__layout(t): every text box
and every rule the frame drew, in 1080p CSS px) at the start, middle and last frame of every shot plus every 6th frame,
and fails on the defects of the 2026-09-28 rejection that encoding checks cannot see:

  D1 text crossed by a line     no text box may touch a rule/border segment (with the stroke's own width + 2 px)
  D2 text on text               the clause and the card lines may not overlap any other text box
  D3 unreadable type            every drawn text >= 28 px at 1080p; the clause and the card's name >= 40 px,
                                the card's other lines >= 36 px (1080p is the size the film is judged at)
  D4 out of frame               the clause and card lines lie wholly inside the frame, clear of the top tenth
  D5 mid-transform text         a moving shape may never cover a text box (the smeared-card defect)
  D6 invariant                  every pane frame has its prompt-bar rule at the same height, starting at the same x

Worked example from the claude-infrastructure v3 film (skills/launch-film/design-gate.md). W, H, M, YR and D6 are
that film's constants (its invariant: a prompt-bar rule at y=612 from x=150); change them per film.
Usage: python3 design_gate.py  (from work/v3; drives ../render.mjs). Prints one line per failure, then DESIGN PASS
or DESIGN FAIL (n); exit 1 on failure."""

import json
import subprocess
import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))
W, H, M, YR = 1920, 1080, 150, 612
film = json.load(open(os.path.join(HERE, "shots.json")))
fps = film["fps"]
ts = set()
for s in film["shots"]:
    a, b = round(s["t0"] * fps), round(s["t1"] * fps) - 1
    ts |= {a, (a + b) // 2, b}
ts |= set(range(0, round(film["duration"] * fps), 6))
ts = sorted(ts)
expr = "JSON.stringify([%s].map((n) => __layout(n / %d)))" % (
    ",".join(map(str, ts)),
    fps,
)
out = subprocess.run(
    ["node", "render.mjs", "eval", "--dpr", "1", "--page", "v3/index.html", expr],
    cwd=os.path.dirname(HERE),
    capture_output=True,
    text=True,
)
if out.returncode != 0:
    print(out.stderr[-2000:])
    sys.exit(2)
frames = json.loads(json.loads(out.stdout.strip().splitlines()[-1]))

fails = []


def fail(f, what):
    fails.append(what)
    if len(fails) <= 40:
        print(f"FAIL t={f['t']:.3f} [{f['kind']}] {what}")


def hit(a, b, pad=0):
    return (
        a["x"] < b["x"] + b["w"] + pad
        and b["x"] < a["x"] + a["w"] + pad
        and a["y"] < b["y"] + b["h"] + pad
        and b["y"] < a["y"] + a["h"] + pad
    )


n_text = 0
for f in frames:
    T = f["texts"]
    n_text += len(T)
    for L in f["lines"]:
        seg = {
            "x": min(L["x1"], L["x2"]),
            "y": min(L["y1"], L["y2"]) - L["w"] / 2,
            "w": abs(L["x2"] - L["x1"]),
            "h": abs(L["y2"] - L["y1"]) + L["w"],
        }
        for t in T:
            if hit(t, seg, 2):
                fail(
                    f,
                    f"D1 text {t['role']} at ({t['x']:.0f},{t['y']:.0f}) touches a line at y={L['y1']:.0f}",
                )
    for i, t in enumerate(T):
        if t["role"] in ("clause", "card"):
            for j, u in enumerate(T):
                if i != j and hit(t, u):
                    fail(
                        f,
                        f"D2 {t['role']} text overlaps {u['role']} text at ({u['x']:.0f},{u['y']:.0f})",
                    )
            if (
                t["x"] < 0
                or t["x"] + t["w"] > W - 40
                or t["y"] < 0.10 * H
                or t["y"] + t["h"] > H
            ):
                fail(
                    f,
                    f"D4 {t['role']} text outside the frame's safe area: x {t['x']:.0f}..{t['x'] + t['w']:.0f}, y {t['y']:.0f}",
                )
        floor = 28
        if t["role"] == "clause":
            floor = 40
        if t["role"] == "card":
            floor = 36
        if t["px"] < floor - 1e-6:
            fail(f, f"D3 {t['role']} type {t['px']:.1f} px < {floor} px at 1080p")
    if f["kind"] == "card" and not any(
        t["role"] == "card" and t["px"] >= 40 for t in T
    ):
        fail(f, "D3 the card has no name >= 40 px")
    for r in f["rects"]:
        if r.get("moving"):
            for t in T:
                if hit(t, r):
                    fail(
                        f,
                        f"D5 a moving shape covers text at ({t['x']:.0f},{t['y']:.0f})",
                    )
    if f["kind"] == "pane":
        if not any(
            abs(L["y1"] - YR) < 0.01
            and abs(min(L["x1"], L["x2"]) - M) < 0.01
            and max(L["x1"], L["x2"]) >= W / 2
            for L in f["lines"]
        ):
            fail(
                f,
                "D6 the prompt-bar rule is not at the invariant (y=612, from x=150)",
            )
print(
    f"design gate: {len(frames)} frames, {n_text} text boxes, {sum(len(f['lines']) for f in frames)} line segments checked"
)
print("DESIGN PASS" if not fails else f"DESIGN FAIL ({len(fails)})")
sys.exit(1 if fails else 0)
