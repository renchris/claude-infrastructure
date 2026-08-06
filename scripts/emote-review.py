#!/usr/bin/env python3
"""emote-review.py — ONE page showing every candidate clawd micro-event, all playing at once.

WHY THIS EXISTS, in the operator's own words from the previous round of this work:

    "we need to have all of the microevents individually shown so we dont have to wait how many
     minutes to see all of them"
    "ensure we just have one to reference at, im getting lost of what to look at for latest changes"

Both complaints are about the same thing — a review surface that costs time to use is a review
surface that gets skipped, and judgements then get made from prose instead of from the artwork. So
every candidate is on this page, playing, from the moment it loads, and the page is built to be
REGENERATED rather than edited.

    python3 scripts/emote-review.py --open

THREE DECISIONS WORTH KNOWING ABOUT, because each was forced by something rather than chosen:

1. PANELS ARE `<img>`, NOT INLINE `<svg>`. This is not a preference, it is the only correct option.
   Every candidate's SVG carries `gen.clawd_sprite`'s class names — `.bob`, `.legA`, `.eOpen`,
   `.armsGate` — so all of them are IDENTICAL across candidates. Inlined into one document, each
   panel's `<style>` block would apply to every other panel: one creature's sneeze would drive all
   twenty-odd creatures at once. `<img>` gives each SVG its own style scope, which is exactly the
   isolation this needs. It also happens to be the mode GitHub itself renders these in.

2. THE THEME TOGGLE SHOWS FORCED RENDERS, AND THAT IS VERIFIED RATHER THAN ASSUMED. A self-theming
   asset answers to the READER's OS, so a page cannot ask it to show its other half — CSS on this
   page cannot reach inside an `<img>`. So the generator also emits a forced-dark and a forced-light
   file per candidate, and the toggle swaps between them. The obvious risk is that a forced render
   quietly stops matching what actually ships; it is closed by construction (one definition of the
   light palette, emitted wrapped or unwrapped) and checked by rendering: the forced-light file and
   the shipping file under a light OS compare at ZERO differing pixels, while forced-light against
   forced-dark differs by 1.66M — so the check can fail, and does not.

3. PANELS RENDER AT 332 px, WHICH IS THE HONEST SIZE. That is the width at which a 760-unit stage
   puts the creature at exactly the 115x84 CSS px it occupies in the shipped README banner. There is
   a magnify control, but it is opt-in and labelled, because this project has already shipped a
   defect that was invisible at 3x and wrong at the real size.
"""

from __future__ import annotations

import argparse
import html
import subprocess
import sys
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "banner"))

import emotes  # noqa: E402

# Category order and the one-line framing each group gets. Ordered fun-first deliberately: the
# operator's steer is that being representative of the repo is a BONUS and that a forced or cryptic
# beat is worse than a simple charming one, so the charming ones are what a reader meets first.
CATEGORY_ORDER = [
    (
        "Idle life",
        "The creature alone, doing nothing in particular. The cheapest beats to build and the "
        "easiest to like — nothing here needs explaining to anybody.",
    ),
    (
        "Reactions",
        "Something happens to it. Each one is an arrest of the walk followed by a single legible "
        "change of posture, because that is what reads at this size.",
    ),
    (
        "The world",
        "It meets a thing, or another of its kind. Relationships are carried by co-location, by "
        "synchrony and by entering or leaving frame — never by a line drawn between two things.",
    ),
    (
        "What it does",
        "Beats that evoke something claude-infrastructure genuinely does. This is the bonus tier: "
        "kept only where the beat is still fun with no explanation attached.",
    ),
]


def data_uri(svg_path: Path) -> str:
    """An SVG as a `data:` URI, percent-encoded rather than base64.

    Percent-encoding costs roughly 10-20% on this content where base64 costs a flat 33%, and it
    leaves the payload legible in devtools, which matters when the thing being debugged is the
    artwork itself.
    """
    txt = svg_path.read_text(encoding="utf-8")
    return "data:image/svg+xml," + urllib.parse.quote(txt, safe="")


CSS = """
:root{
  --bg:#0d0f14; --panel:#151922; --edge:#252c3a; --ink:#e8eaf0; --dim:#8b93a7;
  --accent:#D77757; --chip:#1d2431; --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px rgba(0,0,0,.28);
}
html[data-scheme="light"]{
  --bg:#f6f4f1; --panel:#fffefc; --edge:#e2dcd3; --ink:#221e1a; --dim:#6d655c;
  --chip:#f0ece6; --shadow:0 1px 2px rgba(60,45,30,.08),0 8px 24px rgba(60,45,30,.10);
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--bg); color:var(--ink);
  font:15px/1.55 ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,sans-serif;
  -webkit-font-smoothing:antialiased;
}
.wrap{max-width:1180px;margin:0 auto;padding:44px 28px 96px}
header h1{font-size:30px;letter-spacing:-.02em;margin:0 0 8px;font-weight:650}
header p{color:var(--dim);margin:0 0 4px;max-width:74ch}
.rule{height:1px;background:var(--edge);margin:30px 0 26px}

/* the control bar sticks, because on a 27-panel page the toggles are otherwise 3 screens away */
.bar{
  position:sticky;top:0;z-index:20;display:flex;gap:10px;align-items:center;flex-wrap:wrap;
  padding:12px 0;margin-bottom:6px;background:color-mix(in srgb,var(--bg) 88%,transparent);
  backdrop-filter:blur(10px);border-bottom:1px solid var(--edge);
}
button{
  font:inherit;font-size:13px;color:var(--ink);background:var(--chip);
  border:1px solid var(--edge);border-radius:8px;padding:6px 12px;cursor:pointer;
}
button:hover{border-color:var(--accent)}
button[aria-pressed="true"]{background:var(--accent);border-color:var(--accent);color:#fff}
.count{color:var(--dim);font-size:13px;margin-left:auto}

h2{font-size:13px;letter-spacing:.09em;text-transform:uppercase;color:var(--accent);
   margin:38px 0 4px;font-weight:650}
h2+p{color:var(--dim);margin:0 0 18px;max-width:76ch;font-size:14px}

/* Columns are a FIXED 332px, never `1fr`. With `minmax(332px,1fr)` the tracks stretch to fill the
   row — measured at 358px — and the panel is then no longer the size this page claims it is. The
   whole argument for reviewing here rather than at a comfortable magnification is that 332px is
   exactly the creature's README size; a grid that silently adds 8% would quietly retire that. */
.grid{display:grid;gap:22px;justify-content:start;
      grid-template-columns:repeat(auto-fill,332px)}
body.big .grid{grid-template-columns:838px}
body.big figure{contain-intrinsic-size:838px 900px}

figure{margin:0;background:var(--panel);border:1px solid var(--edge);border-radius:14px;
       overflow:hidden;box-shadow:var(--shadow);content-visibility:auto;
       contain-intrinsic-size:332px 420px}
/* content-visibility lets the browser skip rendering panels that are off screen. It is the only
   mitigation that reaches an <img>-embedded SVG at all: page CSS and getAnimations() cannot cross
   that boundary, so pausing an individual panel's animation from here is impossible by design. */
figure img{display:block;width:100%;height:auto;background:#000}
html[data-scheme="light"] figure img{background:#fff}
img.light{display:none}
html[data-scheme="light"] img.dark{display:none}
html[data-scheme="light"] img.light{display:block}

figcaption{padding:14px 16px 16px}
.hd{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap;margin-bottom:10px}
.hd b{font-size:15px;letter-spacing:.01em}
.chip{font-size:10px;letter-spacing:.07em;text-transform:uppercase;color:var(--dim);
      border:1px solid var(--edge);border-radius:999px;padding:2px 7px}
.acts{display:grid;grid-template-columns:auto 1fr;gap:3px 10px;font-size:13px}
.acts dt{color:var(--accent);font-size:10px;letter-spacing:.07em;text-transform:uppercase;
         padding-top:3px}
.acts dd{margin:0;color:var(--ink);opacity:.9}
.tie{margin-top:11px;padding-top:10px;border-top:1px dashed var(--edge);
     font-size:12.5px;color:var(--dim)}
.tie b{color:var(--dim);font-weight:600;letter-spacing:.05em;font-size:10px;
       text-transform:uppercase;display:block;margin-bottom:2px}

/* A candidate carrying an unresolved reservation. Deliberately the loudest thing in the panel,
   because the defect this closes is that the question was invisible on the one page where it gets
   settled — the reservation lived in an autonomy decision record, and nobody reads a JSON store
   while looking at artwork. Accent-tinted rather than red: this is an open question, not a fault. */
figure.flagged{border-color:color-mix(in srgb,var(--accent) 55%,var(--edge))}
.flag{margin-top:11px;padding:10px 12px;border-radius:9px;font-size:12.5px;
      background:color-mix(in srgb,var(--accent) 12%,transparent);
      border:1px solid color-mix(in srgb,var(--accent) 40%,transparent)}
.flag b{color:var(--accent);font-weight:650;letter-spacing:.06em;font-size:10px;
        text-transform:uppercase;display:block;margin-bottom:3px}
.chip.q{color:var(--accent);border-color:color-mix(in srgb,var(--accent) 55%,var(--edge))}
/* The filter is OPT-IN and starts off, because the ruling being deferred to this page was
   explicitly "see every candidate before cutting" — a page that opened pre-filtered to the two
   under question would decide by framing what it was built to let the eye decide. */
body.onlyq figure:not(.flagged){display:none}
body.onlyq section:not(:has(figure.flagged)){display:none}
footer{margin-top:56px;padding-top:22px;border-top:1px solid var(--edge);
       color:var(--dim);font-size:13px}
code{font:12.5px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--chip);
     padding:1px 5px;border-radius:5px}
@media (prefers-reduced-motion:reduce){.bar{position:static}}
"""

JS = """
const root=document.documentElement, body=document.body;
const bScheme=document.getElementById('t-scheme'), bBig=document.getElementById('t-big');
const bQ=document.getElementById('t-q');
function scheme(v){root.dataset.scheme=v;bScheme.setAttribute('aria-pressed',v==='light');
  bScheme.textContent=v==='light'?'Light':'Dark';}
scheme(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark');
bScheme.onclick=()=>scheme(root.dataset.scheme==='light'?'dark':'light');
bBig.onclick=()=>{const on=body.classList.toggle('big');bBig.setAttribute('aria-pressed',on);};
if(bQ)bQ.onclick=()=>{const on=body.classList.toggle('onlyq');bQ.setAttribute('aria-pressed',on);};
"""


def build_page(out: Path, svg_dir: Path) -> Path:
    groups: dict[str, list[emotes.Emote]] = {}
    for e in emotes.EMOTES:
        groups.setdefault(e.category, []).append(e)

    # Any category a pack invented that is not in CATEGORY_ORDER still gets rendered, at the end.
    # Dropping it silently would hide whole candidates from the review, and a review surface that
    # can be quietly incomplete is worse than none.
    ordered = list(CATEGORY_ORDER) + [
        (k, "") for k in sorted(groups) if k not in {c for c, _ in CATEGORY_ORDER}
    ]

    esc = html.escape
    sections = []
    for cat, blurb in ordered:
        items = sorted(groups.get(cat, []), key=lambda x: x.window[0])
        if not items:
            continue
        cards = []
        for e in items:
            d = data_uri(svg_dir / f"{e.key}.dark.svg")
            lt = data_uri(svg_dir / f"{e.key}.light.svg")
            tie = (
                f'<div class="tie"><b>what it evokes</b>{esc(e.tie)}</div>'
                if e.tie
                else ""
            )
            flag = (
                f'<div class="flag"><b>open question — cut or keep?</b>{esc(e.review)}</div>'
                if e.review
                else ""
            )
            cards.append(
                f'<figure id={e.key!r} class="{"flagged" if e.review else ""}">'
                f'<img class="dark" src="{d}" alt="{esc(e.title)}: {esc(e.showcase)}" '
                f'width="{emotes.STAGE_W}" height="{emotes.STAGE_H}" loading="lazy">'
                f'<img class="light" src="{lt}" alt="" aria-hidden="true" '
                f'width="{emotes.STAGE_W}" height="{emotes.STAGE_H}" loading="lazy">'
                f"<figcaption>"
                f'<div class="hd"><b>{esc(e.title)}</b>'
                f'<span class="chip">{esc(e.cls)}</span>'
                f'<span class="chip">{e.dur:.1f}s</span>'
                # The reservation itself sits at the foot of the caption, which is the right place
                # to READ it and the wrong place to FIND it — a reader scrolling twenty-seven
                # panels never gets to the bottom of one. The chip is the scan affordance.
                + ('<span class="chip q">open question</span>' if e.review else "")
                + "</div>"
                f'<dl class="acts">'
                f"<dt>entry</dt><dd>{esc(e.entry)}</dd>"
                f"<dt>show</dt><dd>{esc(e.showcase)}</dd>"
                f"<dt>exit</dt><dd>{esc(e.exit)}</dd>"
                f"</dl>{tie}{flag}</figcaption></figure>"
            )
        sections.append(
            "<section>"
            + f"<h2>{esc(cat)}</h2>"
            + (f"<p>{esc(blurb)}</p>" if blurb else "")
            + f'<div class="grid">{"".join(cards)}</div>'
            + "</section>"
        )

    n = len(emotes.EMOTES)
    flagged = [e for e in emotes.EMOTES if e.review]
    nq = len(flagged)
    # Named in the header rather than left to be discovered by scrolling. A reservation the reader
    # has to find is one they can finish the page without ever meeting.
    qline = (
        "<p><b>{} candidate{} carry an open cut-or-keep question</b> — {}. Each is outlined, "
        "chipped <i>open question</i>, and carries its author's reservation at the foot of its "
        "caption. They are shown here, unfiltered and in place, deliberately: the ruling was "
        "deferred to this page precisely so it could be made against every candidate rather than "
        "against the two in isolation.</p>".format(
            nq,
            "" if nq == 1 else "s",
            ", ".join(esc(e.title) for e in flagged),
        )
        if nq
        else ""
    )
    page = (
        "<!doctype html><html lang='en' data-scheme='dark'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>clawd micro-events — {n} candidates</title>"
        f"<style>{CSS}</style></head><body><div class='wrap'>"
        "<header><h1>clawd micro-events</h1>"
        f"<p>{n} candidate beats, each a self-contained {emotes.EMOTE_P:g}-second loop with a "
        f"beginning, a middle and an end. Every panel is playing right now and they share one "
        f"period, so they are all at the same moment of their own story.</p>"
        "<p>Panels render at <b>332&nbsp;px</b> — the width that puts the creature at exactly the "
        "size it has in the README banner. Magnify to inspect, but judge at this size.</p>"
        + qline
        + "</header>"
        "<div class='bar'>"
        "<button id='t-scheme' aria-pressed='false'>Dark</button>"
        "<button id='t-big' aria-pressed='false'>Magnify</button>"
        + (
            f"<button id='t-q' aria-pressed='false'>Open questions ({nq})</button>"
            if nq
            else ""
        )
        + f"<span class='count'>{n} candidates &middot; regenerate with "
        f"<code>scripts/emote-review.py</code></span>"
        "</div>"
        '<div class="rule"></div>'
        + "".join(sections)
        + "<footer>Generated by <code>scripts/emote-review.py</code> from "
        "<code>tools/banner/emotes.py</code>, which imports the sprite and palette from "
        "<code>tools/banner/gen.py</code> — so nothing here can drift from the shipping banner. "
        "The two theme renders are forced copies for review; the asset that ships is self-theming "
        "and follows your OS. Under <code>prefers-reduced-motion</code> every loop freezes at its "
        "0% state, which is composed to be a still worth looking at.</footer>"
        f"</div><script>{JS}</script></body></html>"
    )
    out.write_text(page, encoding="utf-8")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, default=Path("/tmp/emote-review"))
    ap.add_argument(
        "--open", action="store_true", help="open the page when it is built"
    )
    args = ap.parse_args()

    svg_dir = args.out / "svg"
    svg_dir.mkdir(parents=True, exist_ok=True)
    emotes.load_packs()
    made = emotes.build_all(svg_dir, ("auto", "dark", "light"))

    page = build_page(args.out / "index.html", svg_dir)
    size = page.stat().st_size
    print(f"\n{len(made)} candidates → {page}  ({size / 1024:.0f} KB, self-contained)")
    if args.open:
        subprocess.run(["open", str(page)], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
