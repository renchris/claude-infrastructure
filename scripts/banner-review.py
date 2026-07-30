#!/usr/bin/env python3
"""banner-review.py — THE one page. Everything open on the banner, in one place.

WHY THIS EXISTS. Reviewing this artwork had spread across five separate generated pages — beat views,
storyboards, height comparisons, a parallax page, a sky A/B — each correct, each in its own temp
directory, and collectively impossible to navigate. The operator's words: *"ensure we just have one to
reference at, im getting lost of what to look at for latest changes."* A review surface nobody can find
their way around is not a review surface.

So this is the SINGLE entry point, and it is deliberately built to be regenerated rather than edited:

    scripts/banner-review.py --open

THE ONE RULE IT KEEPS. Every panel renders at **838 px**, the measured README column, and nothing here
emits a magnified crop. A defect that only exists at shipping size can only be found at shipping size —
the moon read as a crescent at 3x while being an eclipse at 838.

WHAT IS AND IS NOT LIVE. The page labels each section by what it actually is, because conflating a
storyboard with a shipped beat is how this track lost a day. Live animation says LIVE; a still says
STILL; a proposal says PROPOSAL. Sections whose subject sits on an unlanded branch say so and name it.
"""

from __future__ import annotations

import argparse
import html
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
COLUMN = 838
PICK = "v6c-dusk-line"

# How far BEFORE its window each beat's panel starts, so the entry is on screen rather than already
# over. A beat is easiest to read from just before it begins.
LEAD = 1.0

# Editorial note per beat, keyed by the generator's own name. NO WINDOWS HERE — they are read out of
# gen.py's RARE_EVENTS (see read_beats). A previous version of the per-beat surface kept its own copy
# of the windows while claiming it didn't; a beat was later withdrawn and two were re-timed, the
# copies went stale, and the affected panels rendered plain ambient — which looks exactly like a
# BROKEN BEAT rather than a stale reviewer. A review surface that can drift from its subject is worse
# than no review surface.
BEAT_NOTES: dict[str, tuple[str, str]] = {
    "rSummon": (
        "THE SUMMONING",
        "A dons a hat and summons a SMALLER second clawd — the binary's own in-session creature. A "
        "hands over the brief, B hands back the finished work, B removes ITSELF. Watch that the two "
        "never overlap and that nothing detaches from A while it hops.",
    ),
    "rRefuse": (
        "THE REFUSAL",
        "The ground reverses — progress being undone. Carries a predicted misread: it can read as a "
        "rendering glitch rather than as a reversal. No operator ruling on this one yet.",
    ),
    "rAsk": (
        "THE ASK",
        "The world stops and the creature looks at you. Now BLINKS through the stop, so stillness no "
        "longer reads as a dead image. This is the beat the parallax fix also touches — one ground "
        "band used to keep creeping through the stop.",
    ),
    "rOverlap": (
        "THE OVERLAP",
        "WITHDRAWN by operator ruling — a pitch change in ~6 px footprints, invisible at 838. "
        "Machinery kept; one name restores it.",
    ),
    "peek": (
        "THE VISITOR (peek)",
        "ON HOLD by operator ruling — 'silly'. Machinery kept.",
    ),
    "peer": ("THE PEER", "WITHDRAWN — two same-size clawds read as a render error."),
    "rCheer": ("THE CHEER", "WITHDRAWN — arms-up is the measured horns failure."),
}


def git_show(rev: str, path: str, dest: pathlib.Path) -> bool:
    """Materialise one path at one revision. Returns False if that rev has no such path."""
    r = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{rev}:{path}"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return False
    dest.write_text(r.stdout, encoding="utf-8")
    return True


def read_beats() -> list[dict]:
    """Read every beat's window out of gen.py's own RARE_EVENTS, and which ones this variant EMITS.

    PARSED, not imported: gen.py raises partway through a bare module exec, and a tool whose job is to
    review the build must not depend on running it.

    `emitted` matters as much as the window. A beat declared in RARE_EVENTS but absent from the
    variant's `events` renders as plain ambient — indistinguishable from a broken beat unless the
    panel says so. This is the same distinction that made four red-proof fixtures silently stop
    proving anything.
    """
    import ast

    tree = ast.parse((ROOT / "tools" / "banner" / "gen.py").read_text(encoding="utf-8"))
    windows: dict[str, tuple[float, float]] = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name) and t.id == "RARE_EVENTS":
                    windows = dict(ast.literal_eval(node.value))
    emitted: set[str] = set()
    # the variant's own `events` tuple, found by walking the Art(...) call that carries our key
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        kw = {k.arg: k.value for k in node.keywords if k.arg}
        key = kw.get("key")
        if isinstance(key, ast.Constant) and key.value == PICK and "events" in kw:
            try:
                emitted = set(ast.literal_eval(kw["events"]))
            except Exception:
                emitted = set()
    if not windows:
        sys.exit("banner-review: could not read RARE_EVENTS out of gen.py")
    out = []
    for name, (w0, w1) in sorted(windows.items(), key=lambda kv: kv[1][0]):
        label, note = BEAT_NOTES.get(name, (name, ""))
        out.append(
            {
                "name": name,
                "label": label,
                "note": note,
                "w0": w0,
                "w1": w1,
                "emitted": name in emitted,
            }
        )
    return out


def seek(svg_text: str, t: float) -> str:
    """Seek the whole composition to `t` while preserving every authored per-element stagger.

    The assets carry per-element phase in `--d` and take a global seek from `--fz`, with
    `animation-delay: calc(var(--d,0s) + var(--fz,0s))`. Setting `--fz` on the root therefore moves
    the clock without flattening the stagger — a flat `animation-delay:-Ts` would screenshot a
    deliberately staggered population in LOCKSTEP, which is a more convincing lie than an obviously
    broken render.

    Deliberately does NOT pause: each panel PLAYS LIVE from its own beat the moment it loads. That is
    the whole point — the beats sit at 3.4, 17 and 26 s on a 240 s loop, so seeing all of them by
    waiting costs minutes per pass, which is why they were being judged from prose.
    """
    if "var(--fz" not in svg_text:
        sys.exit(
            "banner-review: this asset has no --fz seam, so it cannot be seeked. Rebuild it with "
            "tools/banner/gen.py — a silently unseeked panel would show t=0 for every beat and make "
            "every one of them look absent."
        )
    override = (
        f'<style id="__seek">svg{{--fz:-{t:g}s}}'
        f"*{{animation-delay:calc(var(--d,0s) + var(--fz,0s)) !important}}</style>"
    )
    i = svg_text.rfind("</svg>")
    if i == -1:
        sys.exit("banner-review: no closing </svg>")
    return svg_text[:i] + override + svg_text[i:]


def rev_exists(rev: str) -> bool:
    return (
        subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "--verify", "--quiet", rev],
            capture_output=True,
        ).returncode
        == 0
    )


def shoot(
    svg: pathlib.Path, scheme: str, t: float, out: pathlib.Path
) -> pathlib.Path | None:
    d = out / f".s-{svg.stem}-{scheme}-{t:g}"
    d.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(
        [
            str(ROOT / "scripts" / "banner-shots.sh"),
            str(svg),
            "--times",
            f"{t:g}",
            "--scheme",
            scheme,
            "--bg",
            scheme,
            "--width",
            str(COLUMN),
            "--out",
            str(d),
        ],
        capture_output=True,
        text=True,
    )
    shots = sorted(d.glob("*.png"))
    if r.returncode != 0 or not shots:
        return None
    final = out / f"{svg.stem}-{scheme}-{t:g}.png"
    final.write_bytes(shots[-1].read_bytes())
    shutil.rmtree(d, ignore_errors=True)
    return final


CSS = """
:root{color-scheme:dark light}
*{box-sizing:border-box}
body{margin:0;background:#0d1117;color:#e6edf3;
     font:15px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
.wrap{max-width:%(w)spx;margin:0 auto;padding:40px 40px 140px}
h1{font-size:28px;margin:0 0 8px;letter-spacing:-.015em}
h2{font-size:21px;margin:0 0 6px;letter-spacing:-.01em}
.lede{color:#9198a1;margin:0 0 30px;max-width:74ch}
nav{position:sticky;top:0;background:#0d1117ee;backdrop-filter:blur(8px);
    border-bottom:1px solid #30363d;padding:12px 0;margin:0 0 40px;z-index:9}
nav a{color:#58a6ff;text-decoration:none;margin-right:20px;font-size:14px}
nav a:hover{text-decoration:underline}
section{margin:0 0 84px;border-top:1px solid #30363d;padding-top:28px;scroll-margin-top:64px}
.ask{color:#f0b72f;font-weight:600;margin:0 0 12px}
.detail{color:#9198a1;margin:0 0 24px;max-width:74ch}
.detail code,td code{background:#161b22;padding:1px 5px;border-radius:4px;font-size:13px}
figure{margin:0 0 30px}
figcaption{display:flex;gap:10px;align-items:baseline;margin:0 0 9px;flex-wrap:wrap}
.nm{font-weight:600}
.tag{font:12px ui-monospace,Menlo,monospace;color:#7d8590;background:#161b22;
     border:1px solid #30363d;border-radius:999px;padding:2px 9px;white-space:nowrap}
.live{color:#3fb950;border-color:#2ea04344}
.still{color:#8b949e}
.bad{color:#f85149;border-color:#f8514944}
.good{color:#3fb950;border-color:#2ea04344}
.held{color:#d29922;border-color:#9e6a0344}
img{display:block;width:%(col)spx;max-width:100%%;height:auto;border-radius:6px}
.lightpane{background:#fff;border-radius:6px}
table{border-collapse:collapse;margin:20px 0;font-size:14px;width:100%%}
th,td{text-align:left;padding:6px 16px 6px 0;border-bottom:1px solid #21262d;vertical-align:top}
th{color:#9198a1;font-weight:600}
.k{font:13px ui-monospace,Menlo,monospace}
.box{background:#161b22;border-left:3px solid #f0b72f;padding:13px 18px;margin:0 0 28px;
     border-radius:0 6px 6px 0}
.box.stop{border-left-color:#f85149}
.box.ok{border-left-color:#3fb950}
.miss{color:#7d8590;font-style:italic}
.foot{color:#7d8590;font-size:13px;border-top:1px solid #30363d;padding-top:20px;margin-top:60px}
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default="")
    ap.add_argument("--open", action="store_true")
    args = ap.parse_args()
    out = (
        pathlib.Path(args.out)
        if args.out
        else pathlib.Path(tempfile.mkdtemp(prefix="banner-review-"))
    )
    out.mkdir(parents=True, exist_ok=True)

    asset = f"assets/banner/{PICK}.svg"
    trunk = "origin/main"

    # Live assets, copied in so the page is self-contained and can be reopened later.
    live: dict[str, str | None] = {}
    for label, rev in (
        ("trunk", trunk),
        ("motion", "banner/parallax-fix"),
        ("sky", "banner/sky-ab"),
    ):
        if not rev_exists(rev):
            live[label] = None
            continue
        p = out / f"{label}.svg"
        live[label] = p.name if git_show(rev, asset, p) else None
    # working tree = whatever this branch currently is (the cloud seal, today)
    cur = out / "current.svg"
    cur.write_bytes((ROOT / asset).read_bytes())

    stills: dict[str, str | None] = {}
    for name, src, scheme, t in (
        ("cur_dark", cur, "dark", 60),
        ("cur_light", cur, "light", 60),
        ("trunk_dark", out / "trunk.svg", "dark", 60),
        ("sky_dark", out / "sky.svg", "dark", 60),
    ):
        stills[name] = None
        if src.exists():
            got = shoot(src, scheme, t, out)
            stills[name] = got.name if got else None

    def fig(
        png: str | None, cap: str, tags: list[tuple[str, str]], light: bool = False
    ) -> str:
        if not png:
            return f"<p class=miss>[{html.escape(cap)} — not rendered: its branch is absent from this clone]</p>"
        t = "".join(f"<span class='tag {c}'>{html.escape(x)}</span>" for x, c in tags)
        pane = " class=lightpane" if light else ""
        return (
            f"<figure><figcaption><span class=nm>{html.escape(cap)}</span>{t}</figcaption>"
            f"<div{pane}><img src='{png}' width='{COLUMN}' alt='{html.escape(cap)}'></div></figure>"
        )

    def anim(svg: str | None, cap: str, tags: list[tuple[str, str]]) -> str:
        if not svg:
            return f"<p class=miss>[{html.escape(cap)} — branch absent from this clone]</p>"
        t = "".join(f"<span class='tag {c}'>{html.escape(x)}</span>" for x, c in tags)
        return (
            f"<figure><figcaption><span class=nm>{html.escape(cap)}</span>{t}</figcaption>"
            f"<img src='{svg}' width='{COLUMN}' alt='{html.escape(cap)}'></figure>"
        )

    # ── one live, pre-seeked panel per micro-event ────────────────────────────────────────────────
    # Seeked copies of the SAME asset, one per beat. No re-render and no second source of truth: the
    # windows come from the generator, and the only difference between panels is the injected --fz.
    beats = read_beats()
    base_svg = cur.read_text(encoding="utf-8")
    chunks: list[str] = []
    for b in beats:
        start = max(0.0, b["w0"] - LEAD)
        fname = f"beat-{b['name']}.svg"
        (out / fname).write_text(seek(base_svg, start), encoding="utf-8")
        dur = b["w1"] - b["w0"]
        tags = [(f"{b['w0']:g}-{b['w1']:g}s", "still"), (f"{dur:g}s long", "still")]
        tags.append(
            ("LIVE — playing now", "live")
            if b["emitted"]
            else ("NOT IN THIS BUILD", "bad")
        )
        chunks.append(
            f"<figure><figcaption><span class=nm>{html.escape(b['label'])}</span>"
            + "".join(f"<span class='tag {c}'>{html.escape(x)}</span>" for x, c in tags)
            + f"<span class=tag>{b['name']}</span></figcaption>"
            + (f"<p class=detail>{html.escape(b['note'])}</p>" if b["note"] else "")
            + f"<img src='{fname}' width='{COLUMN}' alt='{html.escape(b['label'])}'></figure>"
        )
    beat_panels = "".join(chunks)

    p: list[str] = [
        "<!doctype html><meta charset=utf-8>",
        "<title>Banner review — the one page</title>",
        f"<style>{CSS % {'w': COLUMN + 90, 'col': COLUMN}}</style>",
        "<div class=wrap>",
        "<h1>Banner review — the one page</h1>",
        f"<p class=lede>Everything open on the hero banner, at the real <strong>{COLUMN} px</strong> "
        f"README column. Regenerate with <code>scripts/banner-review.py --open</code>; there is no "
        f"other page to check. Each section says what it <em>is</em> — LIVE animation, a STILL, or a "
        f"PROPOSAL — because treating a storyboard as a shipped beat cost this track a day.</p>",
        "<nav><a href='#decide'>Needs your call</a>"
        "<a href='#motion'>Ground motion</a>"
        "<a href='#cloud'>Cloud seam</a>"
        "<a href='#moon'>Moon</a>"
        "<a href='#grain'>Grain</a>"
        "<a href='#beats'>Beats</a></nav>",
        # ── what needs a decision ──
        "<section id=decide><h2>Needs your call</h2>",
        "<div class=box><strong>Four open decisions.</strong> Everything below is either evidence for "
        "one of these or a landed fact.<ol>"
        "<li><strong>Ground motion</strong> — apply the derived parallax + tf0 fix? Changes visible "
        "motion. Built and proven, held on <code>banner/parallax-fix</code>.</li>"
        "<li><strong>The moon</strong> — I recommend REJECTING the rebuild; trunk's moon is better. "
        "Measured 3.6× brighter.</li>"
        "<li><strong>Grain</strong> — a dark-only decision; in light it measures 3 levels, i.e. "
        "nothing.</li>"
        "<li><strong>Star opacity</strong> — <code>STAR_FAINT_OP</code> 0.34 / 0.42 / 0.50.</li>"
        "</ol></div>",
        "<table><tr><th>item</th><th>state</th><th>where</th></tr>"
        "<tr><td>red-proof fixtures (7 stale)</td><td class=k>LANDED</td><td class=k>trunk</td></tr>"
        "<tr><td>cloud 1px seam</td><td class=k>FIXED, landing</td><td class=k>this branch</td></tr>"
        "<tr><td>parallax + tf0 warp</td><td class=k>BUILT, HELD</td><td class=k>banner/parallax-fix</td></tr>"
        "<tr><td>moon / starfield rebuild</td><td class=k>HELD — regression</td><td class=k>feat/banner-sky-craft</td></tr>"
        "<tr><td>O1 THE SUMMONING</td><td class=k>LIVE on trunk</td><td class=k>3.4-13.0s</td></tr>"
        "<tr><td>the other 7 beats</td><td class=k>STORYBOARD ONLY</td><td class=k>not animation</td></tr>"
        "</table></section>",
        # ── ground motion ──
        "<section id=motion><h2>Ground motion — before / after</h2>",
        "<p class=ask>Apply the parallax + tf0 fix?</p>",
        "<p class=detail>Both panels animate. Watch the <strong>dark band along the bottom</strong> "
        "against the <strong>dashes and tufts just under the horizon</strong>. Top: they move at the "
        "same speed, so the ground reads as one flat sheet. Bottom: near clearly outruns far. Also at "
        "<code>t = 26–32 s</code> the world stops for THE ASK — in the top panel one band keeps "
        "creeping through the stop at 32 px/s while everything else freezes byte-exact.</p>",
        anim(
            live["trunk"],
            "BEFORE — ships on trunk",
            [
                ("LIVE", "live"),
                ("fgb 96 · tf1 80 · tf0 96", "bad"),
                ("nearest = farthest", "bad"),
            ],
        ),
        anim(
            live["motion"],
            "AFTER — the derived table",
            [
                ("LIVE", "live"),
                ("fgb 128 · tf1 80 · tf0 64", "good"),
                ("2.00x near:far", "good"),
                ("HELD", "held"),
            ],
        ),
        "<table><tr><th>layer</th><th>depth</th><th>before</th><th>after</th><th>period</th><th>wraps/P</th></tr>"
        "<tr><td class=k>fgb</td><td>nearest</td><td class=k>96</td><td class=k><b>128</b></td><td class=k>P/16 = 15 s</td><td class=k>16</td></tr>"
        "<tr><td class=k>tf1</td><td>middle</td><td class=k>80</td><td class=k>80</td><td class=k>P/10 = 24 s</td><td class=k>10</td></tr>"
        "<tr><td class=k>tf0</td><td>farthest</td><td class=k>96</td><td class=k><b>64</b></td><td class=k>P/8 = 30 s</td><td class=k>8</td></tr>"
        "<tr><td class=k>fprs</td><td>footprints</td><td class=k>96</td><td class=k>96</td><td class=k>STRIP_PERIOD</td><td class=k>12</td></tr></table>"
        "<p class=detail>Footprints deliberately stay at 96 = <code>STRIP_V</code>, so the print lock's "
        "anchor and the stride lock never move — the lock still reads 0.000000 px over 480 stride "
        "boundaries.</p></section>",
        # ── cloud seam ──
        "<section id=cloud><h2>The cloud seam — fixed</h2>",
        "<div class='box ok'><strong>You reported this.</strong> A cloud looked cut in half by a pixel "
        "width, and the hairline flickered with whatever was behind it. Two abutting shapes do not "
        "composite to full coverage: every cloud run sits at a fractional x, so the shared edge falls "
        "inside a device pixel and <code>a + b(1−a) &lt; 1</code> leaves sky showing through. It "
        "crawled because scrolling changes the sub-pixel phase every frame.</div>",
        "<p class=detail>Fixed by overlapping each run into its neighbour by 0.75 art px inside "
        "<code>merge_runs</code> — the chokepoint every skyline passes through, so cloud bodies, lit "
        "crowns and the foreground band are all covered. 42 of 42 joins now sealed, 0 exact-abut.</p>",
        fig(
            stills["cur_dark"],
            "CURRENT — seam sealed",
            [("STILL", "still"), ("t=60s", "still"), ("42/42 joins sealed", "good")],
        ),
        # ── moon ──
        "<section id=moon><h2>The moon — reject the rebuild</h2>",
        "<p class=ask>Recommendation: keep trunk's moon. The rebuild is a regression.</p>",
        "<p class=detail>Measured on a single horizontal scanline through the moon's centre, no "
        "averaging. Trunk peaks at <strong>193</strong> with a smooth glow falloff; the rebuild is a "
        "flat plateau at <strong>48–54</strong> across the whole disc — it lost 3.6× its luminance and "
        "became a dark ball ringed by blocky concentric bands. Horn direction only applies to the "
        "rebuilt moon, so that knob is moot if this is rejected.</p>",
        fig(
            stills["trunk_dark"],
            "TRUNK — ships today",
            [("STILL", "still"), ("peak 193", "good"), ("keep this", "good")],
        ),
        fig(
            stills["sky_dark"],
            "feat/banner-sky-craft — the rebuild",
            [("STILL", "still"), ("peak 54", "bad"), ("HELD", "held")],
        ),
        "</section>",
        # ── grain ──
        "<section id=grain><h2>Grain and stars</h2>",
        "<p class=ask>Grain is a DARK-mode decision. Star opacity is still open.</p>",
        "<p class=detail>Measured at 838 px: removing grain changes <strong>10 levels over 66.5%</strong> "
        "of the dark frame, but only <strong>3 levels</strong> in light — where it is effectively "
        "invisible, so dropping it there is free and retires half the last SVG filter's forever-paint. "
        "The spec's handed-down &ldquo;±4 levels&rdquo; was wrong in both directions. Star opacity "
        "touches 0.1% of the canvas at up to 36 levels.</p>",
        fig(
            stills["cur_light"],
            "CURRENT — light scheme",
            [("STILL", "still"), ("grain measures 3 levels here", "still")],
            light=True,
        ),
        "</section>",
        # ── beats ──
        "<section id=beats><h2>The beats — what is actually built</h2>",
        "<div class='box stop'><strong>Three beats are LIVE. Seven are storyboards and do not animate.</strong> "
        "Live on trunk: <strong>rSummon</strong> THE SUMMONING (3.4–13.0 s), <strong>rRefuse</strong> "
        "(17.0–22.0 s), <strong>rAsk</strong> (26.0–35.0 s, now blinking so its stop no longer reads as "
        "a stalled image). THE OVERLAP and the visitor beats are withdrawn by your ruling — machinery "
        "kept, one name restores each.</div>",
        "<p class=detail>Every micro-event below is its <strong>own live panel, already seeked to its "
        "own window and playing the moment the page loads</strong> — so you see all of them at once "
        "instead of waiting out a 240 s loop to catch each one. Each panel starts "
        f"{LEAD:g} s before its beat so the entry is on screen rather than already over. Windows are "
        "read from the generator's own <code>RARE_EVENTS</code>, and a beat this variant does not emit "
        "is labelled NOT IN THIS BUILD rather than quietly rendering as ambient.</p>",
        beat_panels,
        anim(
            live["trunk"],
            "the full loop as it ships — P = 240 s, everything in sequence",
            [("LIVE", "live"), ("trunk", "good")],
        ),
        "</section>",
        "<p class=foot>Generated by <code>scripts/banner-review.py</code>. Assets are copied in, so this "
        "directory stays viewable after branches move. Never run "
        "<code>scripts/banner-apply-header.sh</code> — the README edit is the operator's alone.</p></div>",
    ]

    idx = out / "index.html"
    idx.write_text("\n".join(p), encoding="utf-8")
    print(f"{idx}")
    for k, v in stills.items():
        if v is None:
            print(f"  note: {k} not rendered (branch absent)", file=sys.stderr)
    if args.open:
        subprocess.run(["open", str(idx)], check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
