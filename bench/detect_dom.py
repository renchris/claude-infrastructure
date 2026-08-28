#!/usr/bin/env python3
"""Deterministic design-defect detector over a captured layout snapshot.

These are general design-system lint rules -- rhythm, grid, scale, token
conformance, contrast, overflow, target size, alignment. They are deliberately
written against the page's OWN dominant convention rather than against a list of
the injected defects, so the corpus is not being marked by its own answer key.
The clean control is the guard on that: a rule that fires on clean.html is
overfitted or noisy, and its findings elsewhere are worth nothing.

The interesting output is not the hit rate. It is rule 6's third answer. Where a
backdrop is a gradient or an image, there is no second operand for a contrast
ratio, and this returns INDETERMINATE rather than a pass. Every silent "pass"
that should have been indeterminate is a defect shipped, and that is the precise
seam where a pixel-reading layer stops being optional.

Usage: python3 detect_dom.py <corpus-dir>
"""

from __future__ import annotations

import collections
import json
import math
import pathlib
import re
import sys

GRID = 8
CONTRAST_MIN = 4.5
CONTRAST_MIN_LARGE = 3.0
TARGET_MIN = 44.0
# Rendered geometry is fractional and shifts with device-scale rounding. Without a
# band, a control authored at exactly 44px flips to a defect when the capture
# config changes -- measured: 44.0 unpinned vs 43.x with --force-device-scale-factor.
TARGET_TOL = 0.75
INTERACTIVE = {"button", "a", "input", "select", "textarea"}

RGB_RE = re.compile(r"rgba?\(([^)]+)\)")


def parse_rgb(s: str):
    """-> (r,g,b,a) or None when the value carries no colour (transparent/none)."""
    m = RGB_RE.search(s or "")
    if not m:
        return None
    parts = [p.strip() for p in m.group(1).replace("/", " ").split(",")]
    if len(parts) == 1:
        parts = m.group(1).split()
    try:
        vals = [float(p.rstrip("%")) for p in parts[:4]]
    except ValueError:
        return None
    if len(vals) == 3:
        vals.append(1.0)
    return tuple(vals)


def px(v: str) -> float:
    try:
        return float(str(v).replace("px", "").strip())
    except (ValueError, AttributeError):
        return 0.0


def rel_lum(r, g, b):
    def ch(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(fg, bg):
    l1, l2 = rel_lum(*fg[:3]), rel_lum(*bg[:3])
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def hexof(rgb) -> str:
    return "#%02X%02X%02X" % tuple(int(round(c)) for c in rgb[:3])


def mode_of(values):
    """Dominant value, plus how dominant. A convention only exists if most agree."""
    if not values:
        return None, 0.0
    c = collections.Counter(values)
    top, n = c.most_common(1)[0]
    return top, n / len(values)


class Page:
    def __init__(self, snap: dict):
        self.els = snap["elements"]
        self.by_path = {e["path"]: e for e in self.els}

    def parent_of(self, el):
        p = el["path"].rsplit(" > ", 1)
        return self.by_path.get(p[0]) if len(p) > 1 else None

    def backdrop(self, el):
        """Resolve the effective backdrop colour behind an element.

        Returns (rgb, 'ok') when a solid colour is found, or (None, reason) when
        the honest answer is that no single colour exists.
        """
        cur = el
        depth = 0
        while cur is not None and depth < 12:
            img = (cur["styles"].get("background-image") or "none").strip()
            if img != "none":
                return None, f"backdrop is an image/gradient on {cur['path']}"
            c = parse_rgb(cur["styles"].get("background-color", ""))
            if c and c[3] > 0.99:
                return c, "ok"
            if c and 0 < c[3] <= 0.99:
                return None, f"backdrop is semi-transparent on {cur['path']}"
            cur = self.parent_of(cur)
            depth += 1
        return (255, 255, 255, 1.0), "ok"  # document canvas


RULES = (
    "spacing-rhythm",
    "grid-violation",
    "type-scale",
    "token-drift",
    "contrast",
    "overflow",
    "touch-target",
    "misalignment",
)


def find(snap: dict, tokens: dict) -> tuple[list[dict], dict]:
    """-> (findings, census). The census is the DENOMINATOR.

    A false-positive count with no subject count is a number about a corpus, not
    about a detector: 0 findings over 40 subjects and 0 over 40,000 are the same
    line of output and wildly different evidence. Every rule therefore reports
    how many subjects it actually examined, and `fp_budget.py` states the budget
    per 1,000 subject-checks rather than per run.
    """
    pg = Page(snap)
    els = pg.els
    out: list[dict] = []
    census = dict.fromkeys(RULES, 0)

    def rep(rule, target, detail, severity="medium", **extra):
        out.append(
            {
                "rule": rule,
                "target": target,
                "detail": detail,
                "severity": severity,
                **extra,
            }
        )

    text_els = [e for e in els if e["text"]]

    # --- 1. spacing rhythm: gaps between siblings should share one value ------
    groups = collections.defaultdict(list)
    for e in els:
        p = pg.parent_of(e)
        if p:
            groups[p["path"]].append(e)
    for parent_path, kids in groups.items():
        if len(kids) < 3:
            continue
        kids = sorted(kids, key=lambda k: k["rect"]["x"])
        gaps = [
            round(kids[i + 1]["rect"]["x"] - kids[i]["rect"]["right"], 1)
            for i in range(len(kids) - 1)
        ]
        gaps = [g for g in gaps if g >= 0]
        if len(gaps) < 2:
            continue
        m, share = mode_of(gaps)
        if m is None or share < 0.5:
            continue
        census["spacing-rhythm"] += len(gaps)
        for i, g in enumerate(gaps):
            if abs(g - m) > 1.0:
                rep(
                    "spacing-rhythm",
                    kids[i + 1]["path"],
                    f"gap {g}px breaks the {m}px rhythm used by its siblings "
                    f"under {parent_path}",
                )

    # --- 2. grid adherence: spacing values should be multiples of the unit ----
    for e in els:
        census["grid-violation"] += 4
        for side in ("margin-top", "margin-left", "margin-bottom", "margin-right"):
            v = px(e["styles"].get(side))
            if v and v % GRID != 0 and v not in (1.0, 2.0, 4.0) and v < 100:
                rep(
                    "grid-violation",
                    e["path"],
                    f"{side} is {v:g}px, not a multiple of the {GRID}px grid",
                    "low",
                )

    # --- 3. type scale: font sizes must come from the DECLARED scale ---------
    # This rule used to infer the scale from the page's own histogram -- a size
    # used twice was a step, a size used once was a defect. That is not a type
    # scale, it is a popularity contest, and it convicts the least-used heading
    # on every page. It survived on this corpus only because a glyph happened to
    # share the section heading's 16px; the control failed the instant it did
    # not. A scale is declared by a design system or it is not knowable from one
    # page, so where nothing declares one this abstains, ONCE, and the router
    # takes it from there.
    declared = tokens.get("type_scale")
    sizes = sorted({px(e["styles"]["font-size"]) for e in text_els})
    census["type-scale"] += len(text_els)
    if not declared:
        rep(
            "type-scale-indeterminate",
            "<page>",
            f"no type scale is declared for this app, so none of the "
            f"{len(sizes)} sizes in use ({', '.join(f'{s:g}' for s in sizes)}) "
            f"can be judged conformant or drifted. Requirement UNVERIFIED",
            "high",
            cause="no type scale is declared for this app",
        )
    else:
        steps = sorted(float(s) for s in declared)
        for e in text_els:
            s = px(e["styles"]["font-size"])
            if s in steps:
                continue
            near = min(steps, key=lambda x: abs(x - s))
            d = abs(s - near)
            # Same doctrine as rule 5: a near-miss to a step is drift, a size far
            # from every step is an undeclared decision. Only the first is a bug.
            if d <= 3:
                rep(
                    "type-scale",
                    e["path"],
                    f"font-size {s:g}px is {d:g}px off the declared scale "
                    f"{[f'{x:g}' for x in steps]}; nearest step is {near:g}px",
                )

    # --- 4. radius conformance ----------------------------------------------
    radii = [
        px(e["styles"]["border-radius"])
        for e in els
        if px(e["styles"]["border-radius"]) > 0
    ]
    m, share = mode_of(radii)
    if m and share >= 0.4:
        census["token-drift"] += len(els)
        for e in els:
            r = px(e["styles"]["border-radius"])
            # A pill/circle is a deliberate shape, not radius drift.
            if (
                r > 0
                and abs(r - m) > 0.5
                and r < min(e["rect"]["w"], e["rect"]["h"]) / 2
            ):
                rep(
                    "token-drift",
                    e["path"],
                    f"border-radius {r:g}px differs from the page's dominant {m:g}px",
                    "low",
                )

    # --- 5. colour token conformance ----------------------------------------
    palette = {
        v.upper() for k, v in tokens.items() if isinstance(v, str) and v.startswith("#")
    }
    seen = {}
    for e in els:
        for prop in ("color", "background-color"):
            c = parse_rgb(e["styles"].get(prop, ""))
            if not c or c[3] < 0.99:
                continue
            h = hexof(c)
            seen.setdefault(h, []).append((e["path"], prop))
    census["token-drift"] += sum(len(u) for u in seen.values())
    for h, uses in seen.items():
        if h in palette:
            continue
        # Near-miss to a token is drift; far-from-any-token is an undeclared colour.
        best, dist = None, 1e9
        for t in palette:
            tr = tuple(int(t[i : i + 2], 16) for i in (1, 3, 5))
            hr = tuple(int(h[i : i + 2], 16) for i in (1, 3, 5))
            d = math.dist(tr, hr)
            if d < dist:
                best, dist = t, d
        if dist <= 12:
            for path, prop in uses:
                rep(
                    "token-drift",
                    path,
                    f"{prop} {h} is {dist:.1f} away from token {best}; almost certainly "
                    f"meant to be the token",
                    "low",
                )

    # --- 6. contrast, with an honest third answer ---------------------------
    for e in text_els:
        fg = parse_rgb(e["styles"]["color"])
        if not fg:
            continue
        census["contrast"] += 1
        bg, why = pg.backdrop(e)
        size = px(e["styles"]["font-size"])
        weight = e["styles"].get("font-weight", "400")
        large = size >= 24 or (
            size >= 18.66 and weight in ("700", "bold", "800", "900")
        )
        need = CONTRAST_MIN_LARGE if large else CONTRAST_MIN
        if bg is None:
            # `cause` is the collapse key, emitted as a FIELD rather than left in
            # the prose. Ninety-five abstentions are not ninety-five questions --
            # every text run on one gradient is one question -- and a router that
            # had to regex this sentence to discover that would be re-deriving a
            # fact this layer already knew.
            rep(
                "contrast-indeterminate",
                e["path"],
                f"cannot compute a ratio: {why}. Requirement {need}:1 is UNVERIFIED "
                f"for this text",
                "high",
                cause=why,
            )
            continue
        ratio = contrast(fg, bg)
        if ratio < need:
            rep(
                "contrast",
                e["path"],
                f"{ratio:.2f}:1 against {need}:1 required ({hexof(fg)} on {hexof(bg)})",
                "high",
            )

    # --- 7. overflow / clipping ---------------------------------------------
    census["overflow"] += len(els)
    for e in els:
        ov = " ".join(
            [e["styles"].get("overflow", ""), e["styles"].get("overflow-y", "")]
        )
        if "hidden" in ov and e["scroll"]["h"] > e["scroll"]["ch"] + 1:
            rep(
                "overflow",
                e["path"],
                f"content is {e['scroll']['h']}px tall inside a {e['scroll']['ch']}px "
                f"box with overflow hidden; text is clipped",
                "high",
            )

    # --- 8. touch-target size -----------------------------------------------
    for e in els:
        role = e["tag"] in INTERACTIVE
        if not role:
            continue
        census["touch-target"] += 1
        w, h = e["rect"]["w"], e["rect"]["h"]
        if h < TARGET_MIN - TARGET_TOL or w < TARGET_MIN - TARGET_TOL:
            rep(
                "touch-target",
                e["path"],
                f"{w:.0f}x{h:.0f}px is under the {TARGET_MIN:.0f}px minimum target",
                "high",
            )

    # --- 9. near-miss alignment ---------------------------------------------
    edges = collections.Counter(round(e["rect"]["x"], 1) for e in els)
    strong = {x for x, n in edges.items() if n >= 3}
    census["misalignment"] += len(els)
    for e in els:
        x = round(e["rect"]["x"], 1)
        if x in strong:
            continue
        for s in strong:
            if 0 < abs(x - s) <= 2.0:
                rep(
                    "misalignment",
                    e["path"],
                    f"left edge at {x}px is {abs(x - s):.1f}px off the shared "
                    f"{s}px edge used by {edges[s]} other elements",
                )
                break
    return out, census


def run(corpus: pathlib.Path) -> tuple[dict, dict]:
    manifest = json.loads((corpus / "manifest.json").read_text())
    tokens = manifest["tokens"]
    snaps = corpus / "snapshots"
    results, censuses = {}, {}
    for f in sorted(snaps.glob("*.json")):
        results[f.stem], censuses[f.stem] = find(json.loads(f.read_text()), tokens)
    return results, censuses


def main(corpus: pathlib.Path) -> None:
    results, censuses = run(corpus)
    (corpus / "findings_dom.json").write_text(json.dumps(results, indent=1))
    (corpus / "census_dom.json").write_text(json.dumps(censuses, indent=1))

    ctrl = results.get("clean", [])
    print(
        f"CONTROL clean.html -> {len(ctrl)} finding(s)"
        f"{'  <-- rules are noisy, see below' if ctrl else '  (clean, rules are quiet)'}"
    )
    for c in ctrl:
        print(f"    [{c['rule']}] {c['target']}: {c['detail'][:90]}")
    print()
    baseline = {(c["rule"], c["target"], c["detail"]) for c in ctrl}
    for name, fs in results.items():
        if name == "clean":
            continue
        novel = [f for f in fs if (f["rule"], f["target"], f["detail"]) not in baseline]
        print(f"{name:24} {len(novel):2d} novel finding(s)")
        for f in novel[:4]:
            print(f"    [{f['rule']:24}] {f['target'][:46]:46} {f['detail'][:74]}")


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "corpus/out").resolve())
