#!/usr/bin/env python3
"""banner-beat-views.py — one isolated, immediately-playing view per micro-event.

THE PROBLEM THIS SOLVES. The beats live at t=3, 13, 36 and ~48 s on a 240 s master period, and the
timeline is load-anchored (§ SYNTHESIS), so examining THE OVERLAP means loading the banner and
waiting 36 seconds for it — and then waiting the rest of the loop to see it again. Reviewing four
beats that way costs minutes per pass, which is why they were being judged from prose instead of
from the artifact.

THE MECHANISM. The assets already carry per-element phase in `--d` and take a global seek from
`--fz`, with `animation-delay: calc(var(--d,0s) + var(--fz,0s))` (banner-shots.sh § freeze). Setting
`--fz` on the root therefore seeks the whole composition while preserving every authored stagger.
banner-shots.sh additionally pins `animation-play-state: paused` because it wants one still frame;
this script deliberately does NOT, so each view *plays live* from its own beat the moment it loads.

So a beat's view is the same asset with one injected rule. No re-render, no second source of truth,
and nothing about the beat's own timing is restated here — get the window wrong and the view simply
shows the wrong moment, which is visible rather than silent.

Each panel is 838 px wide, the re-measured README column (scripts/banner-column-width.py), because
§ THE PICK requires judging at rendered size rather than at 1:1 of the art grid.

  scripts/banner-beat-views.py                          # v6c, all beats, to a temp dir
  scripts/banner-beat-views.py --asset assets/banner/v6a-long-night.svg
  scripts/banner-beat-views.py --out /tmp/beats --open
"""

from __future__ import annotations

import argparse
import pathlib
import shutil
import subprocess
import sys

# Beat windows are declared in tools/banner/gen.py RARE_EVENTS; these mirror the shipped set and the
# lead-in is how far BEFORE the window each view starts, so the entry is on screen rather than
# already over. A beat is easiest to read from just before it begins.
BEATS = [
    {
        "key": "ambient",
        "name": "AMBIENT — the control",
        "window": (0.0, 0.0),
        "lead": 0.0,
        "look": "No beat. This is what 91% of the loop looks like: stride, scroll, drifting cloud "
        "bands, the print strip. Judge every beat below against THIS, because a beat that reads "
        "the same as ambient is absent however green the gate is.",
        "mech": "the resting state",
    },
    {
        "key": "refusal",
        "name": "THE REFUSAL",
        "window": (3.0, 8.0),
        "lead": 1.0,
        "look": "A post arrives riding the ground. The bar drops across the path, the world pulls "
        "BACK exactly one print pitch, and the creature re-steps into a print it already made — a "
        "returned turn is redoing a step. Then it makes the lost ground up above nominal.",
        "mech": "completion-assert.sh refuses a false 'done'",
    },
    {
        "key": "ask",
        "name": "THE ASK",
        "window": (13.0, 22.0),
        "lead": 1.0,
        "look": "Nothing arrives. The world rate goes to ZERO for 6 s, ears up, gaze parked "
        "straight out — then 3 s at treble to repay the stop. The clouds keep drifting: the ground "
        "is the gauge, and a session blocked on a human stops its progress, not the world.",
        "mech": "a class-C decision waits with no default",
    },
    {
        "key": "overlap",
        "name": "THE OVERLAP",
        "window": (36.0, 44.25),
        "lead": 1.0,
        "look": "The print pitch HALVES for 12 prints — two walkers' worth of record — so the foot "
        "lands on every second print and the mismatch is the tell. Exits by re-registration. This "
        "is the beat the legibility audit named the designated sacrifice: purest idea, lowest "
        "visibility. Decide it here.",
        "mech": "self-close --successor overlaps rather than touches",
    },
    {
        "key": "visitor",
        "name": "VISITOR (demoted, not deleted)",
        "window": (48.5, 57.0),
        "lead": 1.5,
        "look": "The peek/peer/cheer machinery, still present but pushed past any realistic dwell. "
        "Present so the co-presence question can be judged on the artifact — O1 reverses the "
        "never-co-present principle, so this is the nearest thing to a preview of two creatures "
        "sharing the frame.",
        "mech": "carried, pending the spec owner's ruling",
    },
]

COLUMN = 838  # re-measured README column


def seek(svg_text: str, t: float, *, paused: bool = False) -> str:
    """Same additive seek as banner-shots.sh, but LIVE unless explicitly paused."""
    play = "animation-play-state:paused !important;" if paused else ""
    override = (
        f'<style id="__seek">svg{{--fz:-{t:g}s}}'
        f"*{{animation-delay:calc(var(--d,0s) + var(--fz,0s)) !important;{play}}}</style>"
    )
    i = svg_text.rfind("</svg>")
    if i == -1:
        sys.exit("banner-beat-views: no closing </svg>")
    return svg_text[:i] + override + svg_text[i:]


def page(asset_name: str, beats: list[dict]) -> str:
    panels = []
    for b in beats:
        w0, w1 = b["window"]
        span = (
            "resting state" if w1 == 0 else f"{w0:g}–{w1:g}s &#183; {w1 - w0:g}s long"
        )
        start = max(0.0, w0 - b["lead"])
        panels.append(f"""
    <section class="beat" id="{b["key"]}">
      <header>
        <div class="ttl">
          <h2>{b["name"]}</h2>
          <p class="mech">{b["mech"]}</p>
        </div>
        <div class="meta">
          <span class="win">{span}</span>
          <span class="seek">seeked to t={start:g}s</span>
          <button class="replay" data-key="{b["key"]}">Replay</button>
        </div>
      </header>
      <div class="stage"><img src="{b["key"]}.svg" width="{COLUMN}" alt="{b["name"]}"></div>
      <p class="look">{b["look"]}</p>
    </section>""")

    return f"""<!doctype html>
<meta charset="utf-8">
<title>Micro-events — one view each</title>
<style>
  :root {{
    color-scheme: dark;
    --ink:#e8e3dc; --dim:#9aa0ab; --faint:#6d7480;
    --bg:#0b0e14; --card:#11151d; --line:#242b38;
    --clawd:#D77757; --warm:#f4ead8;
    --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,monospace;
  }}
  :root[data-scheme="light"] {{
    color-scheme: light;
    --ink:#1c1f26; --dim:#555c68; --faint:#7d858f;
    --bg:#f4ead8; --card:#fffdf8; --line:#e0d5c2;
  }}
  * {{ box-sizing:border-box }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
    font:400 15px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif; }}
  .wrap {{ max-width:{COLUMN + 80}px; margin:0 auto; padding:40px 40px 96px }}
  .top {{ display:flex; justify-content:space-between; align-items:flex-end;
    gap:24px; padding-bottom:20px; border-bottom:1px solid var(--line); margin-bottom:8px }}
  h1 {{ font:600 20px/1.25 var(--mono); letter-spacing:.02em; margin:0 0 6px }}
  .sub {{ margin:0; color:var(--dim); font-size:13.5px; max-width:62ch }}
  .sub code {{ font:400 12.5px var(--mono); color:var(--clawd) }}
  .controls {{ display:flex; gap:8px; flex:none }}
  button {{ font:500 12px var(--mono); letter-spacing:.04em; color:var(--ink);
    background:var(--card); border:1px solid var(--line); border-radius:6px;
    padding:7px 12px; cursor:pointer }}
  button:hover {{ border-color:var(--clawd); color:var(--clawd) }}
  button:focus-visible {{ outline:2px solid var(--clawd); outline-offset:2px }}
  .beat {{ padding:34px 0; border-bottom:1px solid var(--line) }}
  .beat:last-child {{ border-bottom:0 }}
  header {{ display:flex; justify-content:space-between; align-items:flex-start;
    gap:20px; margin-bottom:14px; flex-wrap:wrap }}
  h2 {{ font:600 13px var(--mono); letter-spacing:.16em; margin:0; color:var(--clawd) }}
  #ambient h2 {{ color:var(--faint) }}
  .mech {{ margin:4px 0 0; font-size:13px; color:var(--dim); font-style:italic }}
  .meta {{ display:flex; align-items:center; gap:10px; flex:none }}
  .win, .seek {{ font:500 11.5px var(--mono); letter-spacing:.03em;
    padding:4px 9px; border-radius:5px; border:1px solid var(--line) }}
  .win {{ color:var(--ink) }}
  .seek {{ color:var(--faint) }}
  .stage {{ background:var(--card); border:1px solid var(--line); border-radius:8px;
    overflow:hidden; line-height:0 }}
  .stage img {{ display:block; width:100%; height:auto }}
  .look {{ margin:14px 0 0; max-width:70ch; color:var(--dim); font-size:14px }}
  .foot {{ margin-top:40px; color:var(--faint); font-size:12.5px; font-family:var(--mono) }}
  @media (prefers-color-scheme: light) {{
    :root:not([data-scheme]) {{
      color-scheme: light;
      --ink:#1c1f26; --dim:#555c68; --faint:#7d858f;
      --bg:#f4ead8; --card:#fffdf8; --line:#e0d5c2;
    }}
  }}
  @media (prefers-reduced-motion: reduce) {{ * {{ animation:none !important }} }}
</style>
<div class="wrap">
  <div class="top">
    <div>
      <h1>Micro-events — one view each</h1>
      <p class="sub">Every panel is <code>{asset_name}</code> with the timeline seeked to its own
      beat, so each one plays the moment it loads. Nothing waits for t=36&thinsp;s.
      Shown at <code>838px</code>, the real README column.</p>
    </div>
    <div class="controls">
      <button id="scheme">Day / night</button>
      <button id="all">Replay all</button>
    </div>
  </div>
{"".join(panels)}
  <p class="foot">A beat that looks identical to AMBIENT is absent, however green the gate is
  &#183; scripts/banner-beat-views.py</p>
</div>
<script>
  const bust = img => {{
    const base = img.src.split('?')[0];
    img.src = base + '?r=' + Date.now();
  }};
  document.querySelectorAll('.replay').forEach(b =>
    b.addEventListener('click', () =>
      bust(document.querySelector('#' + b.dataset.key + ' img'))));
  document.getElementById('all').addEventListener('click', () =>
    document.querySelectorAll('.stage img').forEach(bust));
  document.getElementById('scheme').addEventListener('click', () => {{
    const r = document.documentElement;
    const dark = getComputedStyle(r).colorScheme.includes('dark');
    r.dataset.scheme = dark ? 'light' : 'dark';
    // An SVG-as-image resolves prefers-color-scheme against THIS document, so the
    // images must be refetched for the new scheme to take (§ S3).
    requestAnimationFrame(() =>
      document.querySelectorAll('.stage img').forEach(bust));
  }});
</script>
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--asset", default="assets/banner/v6c-dusk-line.svg")
    ap.add_argument("--out", default="")
    ap.add_argument("--only", default="", help="comma-separated beat keys")
    ap.add_argument("--open", action="store_true", help="open the page when done")
    a = ap.parse_args()

    src = pathlib.Path(a.asset)
    if not src.is_file():
        sys.exit(f"banner-beat-views: no such asset: {src}")
    svg = src.read_text()
    if "var(--fz" not in svg:
        sys.exit(
            f"banner-beat-views: {src.name} has no --fz seam, so it cannot be seeked.\n"
            "  Rebuild it with tools/banner/gen.py — a silently unseeked view would show t=0 "
            "for every beat and look like four identical panels."
        )

    out = pathlib.Path(a.out) if a.out else pathlib.Path("/tmp/banner-beats")
    out.mkdir(parents=True, exist_ok=True)

    wanted = [k.strip() for k in a.only.split(",") if k.strip()]
    beats = [b for b in BEATS if not wanted or b["key"] in wanted]
    if not beats:
        sys.exit(
            f"banner-beat-views: --only matched nothing; keys are "
            f"{', '.join(b['key'] for b in BEATS)}"
        )

    for b in beats:
        start = max(0.0, b["window"][0] - b["lead"])
        (out / f"{b['key']}.svg").write_text(seek(svg, start))

    index = out / "index.html"
    index.write_text(page(src.name, beats))
    shutil.copy(src, out / src.name)

    print(f"banner-beat-views: {len(beats)} view(s) from {src.name} -> {index}")
    for b in beats:
        w0, w1 = b["window"]
        start = max(0.0, w0 - b["lead"])
        print(f"  {b['key']:9s} window {w0:6.2f}-{w1:<6.2f} seek t={start:g}s")
    if a.open:
        subprocess.run(["open", str(index)], check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
