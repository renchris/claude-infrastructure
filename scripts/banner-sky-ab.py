#!/usr/bin/env python3
"""banner-sky-ab.py — render the sky's open knobs side by side, at the real column width.

WHY THIS EXISTS. Three sky decisions are parameterised rather than decided (§ "The three sky
decisions are now single named knobs"): the moon's horn direction, the sky `grain`, and the faint
star tier's opacity. All three are visible art on the operator's own README, all three are
one-constant flips, and all three had been argued in prose. The operator has asked repeatedly to
decide by LOOKING. So this script turns each knob into a real render rather than a paragraph.

THE ONE RULE IT ENFORCES. Every panel is **838 px wide** — the re-measured README column
(scripts/banner-column-width.py) — and nothing here ever emits a magnified crop. That rule is not
decoration: the first earthshine build closed the moon's silhouette so it read as an eclipse rather
than a crescent at 838 px, and the 3x comparison PASSED it. A defect that only exists at shipping
size can only be found at shipping size.

HOW A KNOB IS FLIPPED. The generator's own source is patched textually, then executed — so what is
rendered is what the operator would get by editing that one line, not an approximation of it. Every
substitution ASSERTS it matched exactly once before the build runs. A source-patching tool makes the
patched line an API: re-indent it or change its spelling and a silent no-op would otherwise render
two identical panels and report them as a difference. `--verify` exists for the same reason — it
re-reads the emitted PNGs and fails if a pair is byte-identical, because two identical images are
the exact signature of a patch that did not apply.

    scripts/banner-sky-ab.py --out /tmp/sky-ab           # all three knobs, then open index.html
    scripts/banner-sky-ab.py --knob grain --out /tmp/ab  # one knob
"""

from __future__ import annotations

import argparse
import hashlib
import html
import importlib.util
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
GEN = ROOT / "tools" / "banner" / "gen.py"
SHOTS = ROOT / "scripts" / "banner-shots.sh"

COLUMN = 838  # the re-measured README column; every panel renders at exactly this
VARIANT = "v6c-dusk-line"  # § THE PICK
AMBIENT_T = (
    60.0  # past the last rare-event window (rCheer ends 54.5s), so no beat is on canvas
)


# ── the knobs ─────────────────────────────────────────────────────────────────────────────────────
# Each option is (label, scheme, [(old_source, new_source), ...], note). An empty patch list is the
# as-shipped control, which every knob must have — without a control there is nothing to compare to.
KNOBS: dict[str, dict] = {
    # THE HORN-DIRECTION KNOB IS GONE, and its absence is the record of a bigger reversal.
    # It parameterised `MOON_LIT_DEG` on the rebuilt crescent — and that whole moon construction was
    # REVERTED (§ "The sky-craft moon is a REGRESSION against what ships"): measured on a raw centre
    # scanline at 838 px it peaked at 54 against trunk's 195, a flat plateau where a crescent should
    # be. Trunk's moon is a masked disc with no lit-limb bearing to turn, so there is no constant
    # here to flip. Deleted rather than left pointing at a name that no longer exists: this script
    # asserts every substitution matches exactly once, so a stale knob is a hard failure on every
    # run, and a knob that cannot render both sides is not a decision anyone can take by looking.
    "grain": {
        "title": "Sky grain — the last SVG filter",
        "question": "Keep the feTurbulence grain, or drop it?",
        "detail": (
            "The grain is the last remaining SVG filter: <code>feTurbulence</code> over the "
            "full-width sky. In an <code>&lt;img&gt;</code> it can never pause off-screen, so it "
            "paints forever. The banded dithering now supplies that texture deliberately, which is "
            "the argument for dropping it. It is ±4 measured levels, so look for whether the sky "
            "goes flat without it — and note removing it changes every variant, not just this one."
        ),
        "options": [
            ("grain ON — ships today (dark)", "dark", [], "DUSK.grain = 0.060"),
            (
                "grain OFF (dark)",
                "dark",
                [("grain=0.060,", "grain=0.0,")],
                "DUSK.grain = 0.0",
            ),
            ("grain ON — ships today (light)", "light", [], "DAWN.grain = 0.032"),
            (
                "grain OFF (light)",
                "light",
                [("grain=0.032,", "grain=0.0,")],
                "DAWN.grain = 0.0",
            ),
        ],
    },
    "stars": {
        "title": "Starfield — the faint tier's opacity",
        "question": "How loud should the majority of the stars be?",
        "detail": (
            "<code>STAR_FAINT_OP</code> carries ~70% of the field. It reads quiet at 838 px, which "
            "is either restraint working as briefed or a field that has gone too far. Do not go "
            "past ~0.55: there the majority tier meets the middle tier and the three magnitude "
            "classes stop being separable — the exact failure the tiers were introduced to fix."
        ),
        "options": [
            ("0.34 — ships today, restraint", "dark", [], "STAR_FAINT_OP = 0.34"),
            (
                "0.42 — more present, hierarchy intact",
                "dark",
                [("STAR_FAINT_OP = 0.34", "STAR_FAINT_OP = 0.42")],
                "STAR_FAINT_OP = 0.42",
            ),
            (
                "0.50 — approaching the old density",
                "dark",
                [("STAR_FAINT_OP = 0.34", "STAR_FAINT_OP = 0.50")],
                "STAR_FAINT_OP = 0.50",
            ),
        ],
    },
}


def patched_source(patches: list[tuple[str, str]]) -> str:
    """Apply each substitution to gen.py's source, asserting every one matched EXACTLY once.

    The assertion is the whole point. A `.replace()` that silently matches nothing produces a build
    identical to the control, and two identical panels labelled A and B is worse than no comparison
    at all — it reads as "the knob makes no difference".
    """
    src = GEN.read_text(encoding="utf-8")
    for old, new in patches:
        hits = src.count(old)
        if hits != 1:
            raise SystemExit(
                f"banner-sky-ab: the patch anchor {old!r} matches {hits} times in "
                f"{GEN.relative_to(ROOT)}, expected exactly 1. The constant was renamed, "
                f"re-spelled or re-indented, so this comparison would render two identical "
                f"panels and report them as a difference. Fix the anchor, do not loosen it."
            )
        src = src.replace(old, new)
    return src


def build_svg(patches: list[tuple[str, str]], dest: pathlib.Path) -> None:
    """Execute a patched copy of the generator and write the chosen variant's SVG.

    Executed from a file inside the real tools/banner directory, not from a string: gen.py resolves
    paths relative to its own location, and a module exec'd from elsewhere would silently read a
    different tree.
    """
    src = patched_source(patches)
    with tempfile.NamedTemporaryFile(
        "w", suffix=".py", dir=GEN.parent, delete=True, encoding="utf-8"
    ) as tmp:
        tmp.write(src)
        tmp.flush()
        spec = importlib.util.spec_from_file_location("banner_gen_ab", tmp.name)
        assert spec is not None and spec.loader is not None
        mod = importlib.util.module_from_spec(spec)
        # Registered BEFORE exec: @dataclass resolves its own class's module out of sys.modules, so
        # a gen.py loaded by path alone dies inside the decorator rather than anywhere near the
        # cause. (Same reason banner-gate-redproof.py does this.)
        sys.modules["banner_gen_ab"] = mod
        try:
            spec.loader.exec_module(mod)
            art = next(a for a in mod.VARIANTS if a.key == VARIANT)
            dest.write_text(mod.build(art), encoding="utf-8")
        finally:
            sys.modules.pop("banner_gen_ab", None)


def shoot(svg: pathlib.Path, scheme: str, out_dir: pathlib.Path) -> pathlib.Path:
    """Screenshot the asset at the real column width, frozen at an ambient timestamp.

    Frozen rather than live: the knobs are all static sky, so a moving frame would add a difference
    the operator is not being asked about. AMBIENT_T sits past every rare-event window so no beat is
    on canvas competing for attention.
    """
    subprocess.run(
        [
            str(SHOTS),
            str(svg),
            "--times",
            str(AMBIENT_T),
            "--scheme",
            scheme,
            "--bg",
            scheme,
            "--width",
            str(COLUMN),
            "--out",
            str(out_dir),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    shots = sorted(out_dir.glob("*.png"))
    if not shots:
        raise SystemExit(f"banner-sky-ab: no PNG produced for {svg.name} ({scheme})")
    return shots[-1]


def render_knob(name: str, out: pathlib.Path) -> list[dict]:
    knob = KNOBS[name]
    panels: list[dict] = []
    for idx, (label, scheme, patches, note) in enumerate(knob["options"]):
        stem = f"{name}-{idx}"
        svg = out / f"{stem}.svg"
        build_svg(patches, svg)
        shot_dir = out / f".shots-{stem}"
        shot_dir.mkdir(exist_ok=True)
        png = shoot(svg, scheme, shot_dir)
        final = out / f"{stem}.png"
        final.write_bytes(png.read_bytes())
        panels.append(
            {
                "label": label,
                "scheme": scheme,
                "note": note,
                "png": final.name,
                "sha": hashlib.sha256(final.read_bytes()).hexdigest()[:12],
                "control": not patches,
            }
        )
        print(f"  {label}  →  {final.name}  ({final.stat().st_size:,} B)")
    return panels


def verify(name: str, panels: list[dict]) -> list[str]:
    """Two panels that hash identically mean the flip did nothing — report it, never render it.

    Compared WITHIN a scheme only: a dark and a light panel differing is not evidence about the knob.
    """
    problems = []
    by_scheme: dict[str, list[dict]] = {}
    for p in panels:
        by_scheme.setdefault(p["scheme"], []).append(p)
    for scheme, group in by_scheme.items():
        seen: dict[str, str] = {}
        for p in group:
            if p["sha"] in seen:
                problems.append(
                    f"{name}/{scheme}: {p['label']!r} renders BYTE-IDENTICAL to "
                    f"{seen[p['sha']]!r} — the knob had no effect at this size"
                )
            seen[p["sha"]] = p["label"]
    return problems


PAGE_CSS = """
:root{color-scheme:dark light}
*{box-sizing:border-box}
body{margin:0;background:#0d1117;color:#e6edf3;
     font:15px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
.wrap{max-width:%(w)spx;margin:0 auto;padding:48px 40px 120px}
h1{font-size:26px;margin:0 0 6px;letter-spacing:-.01em}
.sub{color:#9198a1;margin:0 0 44px}
section{margin:0 0 76px;border-top:1px solid #30363d;padding-top:30px}
h2{font-size:20px;margin:0 0 4px}
.q{color:#f0b72f;margin:0 0 10px;font-weight:600}
.detail{color:#9198a1;margin:0 0 26px;max-width:70ch}
.detail code{background:#161b22;padding:1px 5px;border-radius:4px;font-size:13px}
figure{margin:0 0 30px}
figcaption{display:flex;gap:12px;align-items:baseline;margin:0 0 9px;flex-wrap:wrap}
.name{font-weight:600;font-size:15px}
.tag{font:12px ui-monospace,Menlo,monospace;color:#7d8590;
     background:#161b22;border:1px solid #30363d;border-radius:999px;padding:2px 9px}
.tag.ctl{color:#3fb950;border-color:#2ea04326}
img{display:block;width:%(col)spx;max-width:100%%;height:auto;border-radius:6px}
.light-pane{background:#fff;padding:0;border-radius:6px}
.warn{background:#3d1d1d;border:1px solid #f85149;border-radius:6px;padding:14px 18px;margin:0 0 34px}
.foot{color:#7d8590;font-size:13px;border-top:1px solid #30363d;padding-top:22px}
"""


def page(sections: list[tuple[str, list[dict]]], problems: list[str]) -> str:
    out = [
        "<!doctype html><meta charset=utf-8>",
        "<title>Banner sky — the three open knobs at 838px</title>",
        f"<style>{PAGE_CSS % {'w': COLUMN + 80, 'col': COLUMN}}</style>",
        "<div class=wrap><h1>The three sky knobs, at the real README column</h1>",
        f"<p class=sub>Every panel below is <strong>{COLUMN} px wide</strong> — the measured README "
        f"column — and frozen at t={AMBIENT_T:g}s, past every beat, so nothing is moving and nothing "
        f"else is on canvas. Variant <code>{VARIANT}</code>. No crops and no magnification: a defect "
        f"that only exists at shipping size can only be found at shipping size.</p>",
    ]
    if problems:
        out.append(
            "<div class=warn><strong>These pairs did not differ:</strong><br>"
            + "<br>".join(html.escape(p) for p in problems)
            + "</div>"
        )
    for name, panels in sections:
        knob = KNOBS[name]
        out.append(
            f"<section><h2>{html.escape(knob['title'])}</h2>"
            f"<p class=q>{html.escape(knob['question'])}</p>"
            f"<p class=detail>{knob['detail']}</p>"
        )
        for p in panels:
            tag = "tag ctl" if p["control"] else "tag"
            pane = " class=light-pane" if p["scheme"] == "light" else ""
            out.append(
                f"<figure><figcaption><span class=name>{html.escape(p['label'])}</span>"
                f"<span class='{tag}'>{html.escape(p['note'])}</span>"
                f"<span class=tag>{p['sha']}</span></figcaption>"
                f"<div{pane}><img src='{p['png']}' width='{COLUMN}' "
                f"alt='{html.escape(p['label'])}'></div></figure>"
            )
        out.append("</section>")
    out.append(
        "<p class=foot>Generated by <code>scripts/banner-sky-ab.py</code>. Each option is the "
        "generator's own source with one constant changed — every substitution asserts it matched "
        "exactly once, and identical hashes in a pair are reported above rather than shown as a "
        "difference.</p></div>"
    )
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default="", help="output dir (default: a temp dir)")
    ap.add_argument(
        "--knob", default="", help=f"one of {', '.join(KNOBS)} (default: all three)"
    )
    ap.add_argument("--open", action="store_true", help="open index.html when done")
    args = ap.parse_args()

    names = [args.knob] if args.knob else list(KNOBS)
    for n in names:
        if n not in KNOBS:
            print(
                f"banner-sky-ab: unknown knob {n!r}; have {', '.join(KNOBS)}",
                file=sys.stderr,
            )
            return 2

    out = (
        pathlib.Path(args.out)
        if args.out
        else pathlib.Path(tempfile.mkdtemp(prefix="sky-ab-"))
    )
    out.mkdir(parents=True, exist_ok=True)

    sections, problems = [], []
    for n in names:
        print(f"{KNOBS[n]['title']}:")
        panels = render_knob(n, out)
        problems += verify(n, panels)
        sections.append((n, panels))

    index = out / "index.html"
    index.write_text(page(sections, problems), encoding="utf-8")
    print(f"\n{index}")
    if args.open:
        subprocess.run(["open", str(index)], check=False)
    if problems:
        print("\nbanner-sky-ab: FAIL — a knob had no visible effect:", file=sys.stderr)
        for p in problems:
            print(f"  · {p}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
