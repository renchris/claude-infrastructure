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

So a beat's view is the same asset with one injected rule. No re-render and no second source of truth:
**the windows are read out of `tools/banner/gen.py`'s own `RARE_EVENTS`, never restated here.**

That was not true of the first version, and the way it failed is the reason this paragraph exists. It
carried its own copy of the windows while this docstring claimed it didn't. When a beat was later
withdrawn and two others re-timed, the copies went stale and the affected panels rendered plain
ambient — which looks exactly like a *broken beat* rather than a stale reviewer, i.e. the tool would
have made a correct build look defective. A review surface that can drift from its subject is worse
than no review surface. Windows now come from the generator; a beat the generator does not emit is
labelled **NOT IN THIS BUILD** instead of quietly rendering ambient (which covers both a globally withdrawn beat and one this variant simply never declared); and a beat in `RARE_EVENTS` that has no
editorial note here still gets a panel, so a newly-added beat appears without anyone editing this file.

The generator is **parsed, not imported** — `tools/banner/gen.py` raises partway through a bare
module exec, and a tool whose job is to review the build must not depend on running it.

Each panel is 838 px wide, the re-measured README column (scripts/banner-column-width.py), because
§ THE PICK requires judging at rendered size rather than at 1:1 of the art grid.

  scripts/banner-beat-views.py                          # v6c, all beats, to a temp dir
  scripts/banner-beat-views.py --asset assets/banner/v6a-long-night.svg
  scripts/banner-beat-views.py --out /tmp/beats --open
"""

from __future__ import annotations

import argparse
import ast
import pathlib
import shutil
import subprocess
import sys

# `lead` is how far BEFORE the window a view starts, so the entry is on screen rather than already
# over; a beat is easiest to read from just before it begins. This is a property of REVIEWING a beat,
# not of the beat, so it lives here — unlike the beat's story, which does not.
#
# THE STORY USED TO LIVE HERE TOO, in a hand-maintained `NOTES` dict, and it rotted exactly the way
# this file's own docstring says the WINDOWS rotted before them. The windows were de-duplicated into
# gen.py; the notes beside them were not, so the rot just moved house: `rShoot` and `rTrace` shipped
# on 2026-07-30 and every panel this tool drew for them read "no editorial note yet — added to gen.py
# after this file was written", which is the review surface describing two live beats as unwritten.
# The story now comes from `gen.BEAT_STORY` through the same parse as the windows, so a beat and its
# reason cannot drift apart, and `assert_every_beat_tells_a_story` refuses a build where one is
# missing.
LEAD = {"rCheer": 1.5}
LEAD_DEFAULT = 1.0

# What the mechanism line says when a beat names none. The two cases are NOT the same absence and the
# review page must not render them alike: a SKY beat is silent about the system on purpose, while a
# WITHDRAWN one is silent because the argument for its cause failed.
_NO_MECHANISM = {
    "SKY": "nothing — a sky occurrence says nothing about the system, by design",
    "WITHDRAWN": "none that survived review — the beat is withdrawn, its machinery kept",
    "NARRATIVE": "unnamed (the generator's story gate refuses this)",
}

AMBIENT = {
    "key": "ambient",
    "name": "AMBIENT — the control",
    "window": None,
    "lead": 0.0,
    "emitted": True,
    "mech": "the resting state",
    "look": "No beat. This is what most of the loop looks like: stride, scroll, drifting cloud bands, "
    "the print strip. Judge every beat below against THIS, because a beat that reads the same as "
    "ambient is absent however green the gate is.",
}


def read_beats(gen: pathlib.Path) -> list[dict]:
    """Read RARE_EVENTS + the emitted set out of gen.py by PARSING it.

    Not by importing: gen.py raises partway through a bare module exec, and a tool whose job is to
    review the build must not depend on running it. Fails loud if either name is missing, because
    silently falling back to a local copy is the exact drift this function exists to remove.
    """
    tree = ast.parse(gen.read_text())
    found: dict[str, object] = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for tgt in node.targets:
            if isinstance(tgt, ast.Name) and tgt.id in (
                "RARE_EVENTS",
                "ALWAYS_EMITTED",
                "BEAT_STORY",
            ):
                try:
                    found[tgt.id] = ast.literal_eval(node.value)
                except ValueError:
                    pass
    windows = found.get("RARE_EVENTS")
    emitted = found.get("ALWAYS_EMITTED")
    story = found.get("BEAT_STORY")
    if not isinstance(windows, dict):
        sys.exit(
            f"banner-beat-views: could not read RARE_EVENTS from {gen}. The windows live there and "
            "are deliberately not duplicated here — fix the parse rather than restoring a local copy."
        )
    if not isinstance(story, dict):
        sys.exit(
            f"banner-beat-views: could not read BEAT_STORY from {gen}. Each beat's cause, behaviour "
            "and exit live there and are deliberately not duplicated here — fix the parse rather "
            "than restoring a local copy. That copy is what went stale last time."
        )
    emitted_set = (
        set(emitted) if isinstance(emitted, (list, tuple, set)) else set(windows)
    )

    out = [AMBIENT]
    for name, win in sorted(windows.items(), key=lambda kv: kv[1][0]):
        # No local fallback. `assert_every_beat_tells_a_story` refuses to build a beat that has no
        # story, so a missing one here means this tool is reading a generator older than the gate —
        # and inventing placeholder prose for it is what produced the panels that described two live
        # sky beats as "no editorial note yet".
        s = story.get(name)
        if not isinstance(s, dict):
            sys.exit(
                f"banner-beat-views: {name} is in RARE_EVENTS but has no BEAT_STORY entry in {gen}. "
                "The generator's own gate refuses that combination, so this is a stale generator or "
                "a failed parse — not a beat to paper over."
            )
        out.append(
            {
                "key": name,
                "name": s["label"],
                "window": (float(win[0]), float(win[1])),
                "lead": LEAD.get(name, LEAD_DEFAULT),
                "emitted": name in emitted_set,
                "kind": s["kind"],
                "mech": s["mechanism"] or _NO_MECHANISM[s["kind"]],
                "look": f"CAUSE — {s['cause']}. BEHAVIOUR — {s['behaviour']}. "
                f"EXIT — {s['exit']}.",
            }
        )
    return out


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
        win = b["window"]
        if win is None:
            span, start = "resting state", 0.0
        else:
            w0, w1 = win
            span = f"{w0:g}\u2013{w1:g}s &#183; {w1 - w0:g}s long"
            start = max(0.0, w0 - b["lead"])
        withdrawn = (
            ""
            if b.get("emitted", True)
            else '<span class="wd">NOT IN THIS BUILD</span>'
        )
        panels.append(f"""
    <section class="beat" id="{b["key"]}">
      <header>
        <div class="ttl">
          <h2>{b["name"]}</h2>
          <p class="mech">{b["mech"]}</p>
        </div>
        <div class="meta">
          <span class="win">{span}</span>{withdrawn}
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
  .wd {{ font:600 10.5px var(--mono); letter-spacing:.1em; padding:4px 8px;
    border-radius:5px; color:#e0a03a; border:1px solid #6b4f1d; background:#241c0c }}
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
    ap.add_argument(
        "--gen",
        default="tools/banner/gen.py",
        help="generator to read RARE_EVENTS from (never duplicated here)",
    )
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

    all_beats = read_beats(pathlib.Path(a.gen))
    wanted = [k.strip() for k in a.only.split(",") if k.strip()]
    beats = [b for b in all_beats if not wanted or b["key"] in wanted]
    if not beats:
        sys.exit(
            f"banner-beat-views: --only matched nothing; keys are "
            f"{', '.join(b['key'] for b in all_beats)}"
        )

    for b in beats:
        start = 0.0 if b["window"] is None else max(0.0, b["window"][0] - b["lead"])
        (out / f"{b['key']}.svg").write_text(seek(svg, start))

    index = out / "index.html"
    index.write_text(page(src.name, beats))
    shutil.copy(src, out / src.name)

    print(f"banner-beat-views: {len(beats)} view(s) from {src.name} -> {index}")
    for b in beats:
        if b["window"] is None:
            print(f"  {b['key']:9s} ambient control        seek t=0s")
            continue
        w0, w1 = b["window"]
        start = max(0.0, w0 - b["lead"])
        print(f"  {b['key']:9s} window {w0:6.2f}-{w1:<6.2f} seek t={start:g}s")
    if a.open:
        subprocess.run(["open", str(index)], check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
