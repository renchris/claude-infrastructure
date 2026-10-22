#!/usr/bin/env python3
"""Fold the narrow-probe runs under captures/ into verdict.json and a markdown table (stdout).

For every band step: the band's cells (the pane less CC's 5-column collapse handle), the ladder
layout pickFit hands it, how many of the band's rows CC shows before its "↓ N more" cue, which
accounts have all four values whole on that first screen, whether every value is reachable by
scrolling the band, ellipses, and tokens the layout carries whole that came out split on screen
(a word broken mid-word, or a bound countdown broken at its NBSP). Re-derived from the saved
screens, so it can be re-run without Claude Code.
"""

import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "captures")
SGR = re.compile(r"\x1b\[[0-9;]*m")
GUTTER = 5  # bodyColumns = columns - COLLAPSE_HANDLE_COLUMNS (CC 2.1.293)


def pick_fit(L, cells):
    best = L["variants"][0]
    for v in L["variants"]:
        if v["width"] <= cells:
            best = v
    return best


def split_tokens(variant, rows):
    text = [r.rstrip() for r in rows]
    bad = []
    for ln in variant["lines"]:
        for tok in SGR.sub("", ln).split(" "):
            t = tok.replace("\xa0", " ").strip()
            if len(t) < 2:
                continue
            if not any(t in r for r in text):
                bad.append(t)
    return bad


def run_rows(run):
    v = json.load(open(os.path.join(CAP, run, "verdict.json")))
    L = json.load(open(os.path.join(CAP, run, "board.ladder.json")))
    out = []
    for name, s in v["steps"].items():
        m = re.match(r"(band|readout)-(\d\d)-(\d+)$", name)
        if not m:
            continue
        kind, cols = m.group(1), int(m.group(3))
        row = {
            "run": run,
            "arm": v["arm"],
            "rows": v["rows"],
            "pane_rows": v["pane_rows"],
            "surface": kind,
            "cols": cols,
            "step": name,
        }
        acc = s["accounts"]
        row["first_screen_whole"] = [n for n, a in acc.items() if a["whole"]]
        row["first_screen_missing"] = [n for n, a in acc.items() if not a["whole"]]
        row["ellipsis_rows"] = len(s["ellipsis_rows"])
        if kind == "band":
            cells = cols - GUTTER
            var = pick_fit(L, cells)
            row.update(
                band_cells=cells,
                layout=var["cells"],
                layout_lines=len(var["lines"]),
                window_rows=s["region_rows"],
                cue=s["cue"][0] if s["cue"] else "",
                input_echo=s.get("input_echo"),
            )
            txt = open(os.path.join(CAP, run, f"{name}.txt")).read().split("\n")
            row["picks_visible"] = bool(
                re.search(r"desk(\s|\([^)]*\))*→", "\n".join(txt))
            ) and bool(re.search(r"general\s*→", "\n".join(txt)))
            sc = s.get("scroll")
            whole_f = os.path.join(CAP, run, f"{name}-band-whole.txt")
            if sc:
                full = (
                    open(whole_f).read().split("\n") if os.path.exists(whole_f) else []
                )
                row.update(
                    scroll=sc["method"],
                    scroll_complete=bool(sc.get("reached_end"))
                    and not sc.get("stitch_gaps")
                    and len(full) >= len(var["lines"]),
                    band_rows=len(full),
                    reachable_all_whole=sc["reachable_all_whole"],
                    band_ellipsis_rows=len(sc["ellipsis_rows"]),
                    split_tokens=split_tokens(var, full)[:8],
                )
            else:
                row.update(
                    scroll=None,
                    scroll_complete=True,
                    band_rows=s["region_rows"],
                    reachable_all_whole=s["visible_all_whole"],
                    band_ellipsis_rows=len(s["ellipsis_rows"]),
                    split_tokens=split_tokens(var, txt)[:8],
                )
        out.append(row)
    return v, out


# ── Round 4 (2026-10-22): judge each screen against the ladder variant actually drawn ─────────
# The round-1 oracle (narrow-probe.py `accounts`) parses one account per row block, so it reads
# the dense card form (two accounts side by side) as missing. Round 4 instead (a) finds which
# ladder variant Claude Code drew, by matching the screen's band rows to every variant's lines,
# and (b) checks the first screen by token multiset: every account's four expected values (the
# widest grid's own columns, countdowns spacing-insensitive) must appear as whole tokens in the
# band rows above the alerts, and every account name must appear whole. Re-derived from saved
# screens, so it can be re-run without Claude Code.
MAXROWS = {30: 10, 45: 17, 70: 30}  # measured on CC 2.1.293 (README, Round 1)
CUE = re.compile(r"[↑↓] \d+")
ALERT = re.compile(
    r"^\s*([✖▲△↻]|Not enough|Fable window|Quota read|read[ \xa0]\d|read at)"
)
CD = re.compile(r"^\d+[hdm]$")


def plain(line):
    return SGR.sub("", line).replace("\xa0", " ").rstrip()


def r4_region(rs):
    pr = [i for i, r in enumerate(rs) if re.match(r"^\s*❯", r)]
    pr = pr[-1] if pr else len(rs)
    up = [i for i in range(pr) if re.fullmatch(r"─{4,}", rs[i].strip())]
    end = up[-1] if up else pr
    top = next((i for i in range(end) if rs[i].rstrip().endswith("[-]")), None)
    if top is None:
        top = next((i for i in range(end) if rs[i].lstrip().startswith("➤")), None)
    if top is None:
        return [], None
    cue = next((i for i in range(top, end) if CUE.search(rs[i])), None)
    sub = [
        r.replace("[-]", "   ").rstrip()
        for r in rs[top : (cue if cue is not None else end)]
    ]
    if cue is None:
        while sub and not sub[-1].strip():
            sub.pop()
    return sub, (rs[cue].strip() if cue is not None else "")


def tokens(rows):
    out = []
    for r in rows:
        t = [x.strip(",;()") for x in re.sub(r"^[\s➤ᵍ]*", "", r).split()]
        i = 0
        while i < len(t):
            if (
                i + 1 < len(t)
                and CD.match(t[i])
                and CD.match(t[i + 1])
                and t[i][-1] in "hd"
            ):
                out.append(t[i] + t[i + 1])
                i += 2
            else:
                out.append(t[i])
                i += 1
    return out


def value_rows(rows):
    """The rows above the first alert / forecast / read-clock row (the account values live there)."""
    i = next((i for i, r in enumerate(rows) if ALERT.match(r) and i > 0), len(rows))
    return rows[:i]


def values_check(rows, want):
    from collections import Counter

    have = Counter(tokens(value_rows(rows)))
    need = Counter(v.replace(" ", "") for vs in want.values() for v in vs)
    missing = need - have
    joined = "\n".join(rows)
    dehy = re.sub(r"-\n\s*", "-", joined)  # a long name wraps at its hyphens
    names_missing = [
        n
        for n in want
        if not re.search(r"(?<![\w-])" + re.escape(n) + r"(?![\w-])", dehy)
    ]
    return sorted(missing.elements()), names_missing


PICK = re.compile(r"(desk|general|gen|fable)\b[^→\n]*?→\s*(\S+)")


def pick_targets(L):
    """Round 6: the picks' target accounts, read off the widest variant's `➤ … → X` rows."""
    wide = [plain(x) for x in L["variants"][-1]["lines"]]
    out = []
    for l in wide:
        if not l.strip():
            break
        for m in PICK.finditer(l):
            if m.group(2) not in out:
                out.append(m.group(2))
    return out


def picks_check(rows, targets):
    """Round 6: every pick target sits on the first screen whole, right after a `→` or `use`
    (forms: `desk·general·fable → next2`, `all lanes → next2`, `use next2`, `gen → next`)."""
    j = "\n".join(rows)
    return [
        t
        for t in targets
        if not re.search(r"(→|\buse)\s+" + re.escape(t) + r"(?![\w-])", j)
    ]


def match_variant(sub, L, pred):
    """(head rows, variant) whose lines the band's rows reproduce; prefer the mod's prediction."""
    found = []
    for v in L["variants"]:
        V = [plain(x) for x in v["lines"]]
        for h in range(0, 7):
            n = min(len(sub) - h, len(V))
            if n <= 0:
                continue
            if sub[h : h + n] == V[:n] and (len(sub) - h <= len(V)):
                found.append((h, v))
                break
    if not found:
        return None, None
    for h, v in found:
        if (
            pred
            and v["cells"] == pred.get("cells")
            and bool(v.get("dense")) == pred.get("dense")
        ):
            return h, v
    found.sort(key=lambda hv: (hv[0], -len(hv[1]["lines"])))
    return found[0]


def r4_rows(run):
    d = os.path.join(CAP, run)
    v = json.load(open(os.path.join(d, "verdict.json")))
    L = json.load(open(os.path.join(d, "board.ladder.json")))
    want = json.load(open(os.path.join(d, "expected.json")))
    try:
        predall = json.load(open(os.path.join(d, "mod-prediction.json")))
    except (OSError, ValueError):
        predall = {}
    H = v["pane_rows"]
    mr = MAXROWS.get(H)
    out = []
    for name, s in v["steps"].items():
        m = re.match(r"(band|readout)-(\d\d)-(\d+)$", name)
        if not m:
            continue
        kind, cols = m.group(1), int(m.group(3))
        rs = open(os.path.join(d, f"{name}.txt")).read().split("\n")
        row = {
            "run": run,
            "data": v["rows"],
            "pane_rows": H,
            "surface": kind,
            "cols": cols,
            "step": name,
        }
        if kind == "readout":
            tw = os.path.join(d, f"{name}-transcript-whole.txt")
            T = open(tw).read().split("\n") if os.path.exists(tw) else rs
            endb = next((i for i, r in enumerate(T) if r.startswith("⏺ BRAVO")), len(T))
            heads = [
                i
                for i, r in enumerate(T[:endb])
                if re.search(r"Ran \d+ shell command", r)
            ]
            sub = T[(heads[-1] + 1 if heads else 0) : endb]
            rw = os.path.join(d, "expected-readout.json")
            rwant = json.load(open(rw)) if os.path.exists(rw) else None
            miss, nmiss = values_check(sub, rwant or want)
            rl = L
            if os.path.exists(os.path.join(d, "readout.ladder.json")):
                rl = json.load(open(os.path.join(d, "readout.ladder.json")))
            row.update(
                readout_rows=len(sub),
                screen_rows=H,
                values_missing=miss,
                names_missing=nmiss,
                ellipsis_rows=sum("…" in r for r in sub),
                hardbreak_rows=[r.strip() for r in sub if "↩" in r],
                edge_rows=sum(len(r) >= cols for r in sub),
                pred=predall.get(f"readout:{cols}"),
                transcript_stitched=os.path.exists(tw),
            )
            out.append(row)
            continue
        sub, cue = r4_region(rs)
        pred = predall.get(f"{mr}:{cols}") if mr else None
        h, var = match_variant(sub, L, pred)
        whole_f = os.path.join(d, f"{name}-band-whole.txt")
        whole = None
        if os.path.exists(whole_f):
            whole = [r.rstrip() for r in open(whole_f).read().split("\n")]
            while whole and not whole[-1].strip():
                whole.pop()
        body = sub[h:] if h is not None else sub
        miss, nmiss = values_check(body, want)
        vend = None
        if var is not None:
            V = [plain(x) for x in var["lines"]]
            vend = len(value_rows(V))  # rows the picks + every account's values take
        row.update(
            band_cells=cols - 5,
            maxrows=mr,
            drawn=(
                None
                if var is None
                else {
                    "cells": var["cells"],
                    "width": var["width"],
                    "dense": bool(var.get("dense")),
                    "lines": len(var["lines"]),
                }
            ),
            head_rows=h,
            pred=pred,
            matches_prediction=bool(
                var is not None
                and pred
                and var["cells"] == pred.get("cells")
                and bool(var.get("dense")) == pred.get("dense")
            ),
            window_rows=len(sub) + (1 if cue else 0),
            shown_rows=len(sub),
            cue=cue,
            band_rows=(h + len(var["lines"]))
            if var is not None
            else (len(whole) if whole else len(sub)),
            value_rows=vend,
            first_screen_values_missing=miss,
            first_screen_names_missing=nmiss,
            first_screen_all=not miss and not nmiss,
            first_screen_picks_missing=picks_check(body, pick_targets(L)),
            ellipsis_rows=sum("…" in r for r in (whole or sub)),
            hardbreak_rows=[r.strip() for r in (whole or sub) if "↩" in r],
            ink_rewrapped=var is None,
            input_echo=s.get("input_echo"),
            whole_matches_variant=(
                None
                if whole is None or var is None
                else whole[h:] == [plain(x) for x in var["lines"]]
            ),
        )
        if var is None and pred:
            # what the mod meant to draw, and which of its tokens did not survive whole on screen
            cand = next(
                (
                    x
                    for x in L["variants"]
                    if x["cells"] == pred.get("cells")
                    and bool(x.get("dense")) == pred.get("dense")
                ),
                None,
            )
            if cand:
                row["split_tokens"] = split_tokens(cand, whole or sub)[:12]
        out.append(row)
    return v, out


def r4_main(runs):
    table, meta = [], {}
    for r in runs:
        v, rows = r4_rows(r)
        meta[r] = {
            "turns_ok": v["turns_ok"],
            "pane_rows": v["pane_rows"],
            "data": v["rows"],
            "stale_s": v.get("stale_s"),
            "band_gone_after_prompt": v["band_gone_after_prompt"],
            "provenance_sha256_16": v.get("provenance_sha256_16"),
        }
        table += rows
    return meta, table


def r4_print(table):
    print(
        "| data | pane (cols×rows) | band cells | drawn layout (lines) | head | rows shown / maxRows | first screen: picks + all 4 accounts' 5h & wk used/reset | ellipsis | renderer ↩ breaks | Ink re-wrap | input |"
    )
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for t in table:
        if t["surface"] != "band":
            continue
        dr = t["drawn"]
        lay = (
            f"{'dense' if dr['dense'] else 'full'} {dr['cells']} ({dr['lines']})"
            if dr
            else "no variant matches"
        )
        miss = t["first_screen_values_missing"]
        nm = t["first_screen_names_missing"]
        first = (
            "yes"
            if t["first_screen_all"]
            else (
                "NO: "
                + ", ".join(
                    [f"{len(miss)} value(s) below fold"] * bool(miss)
                    + [f"names {', '.join(n[:10] for n in nm)}"] * bool(nm)
                )
            )
        )
        print(
            f"| {t['data']} | {t['cols']}×{t['pane_rows']} | {t['band_cells']} | {lay} | {t['head_rows'] or 0} "
            f"| {t['shown_rows']}{' + ' + t['cue'] if t['cue'] else ''} / {t['maxrows']} | {first}"
            + (
                f"; picks missing {t['first_screen_picks_missing']}"
                if t.get("first_screen_picks_missing")
                else ""
            )
            + " "
            f"| {t['ellipsis_rows']} | {len(t['hardbreak_rows'])} | {'YES ' + ', '.join(t.get('split_tokens', [])[:4]) if t['ink_rewrapped'] else 'no'} "
            f"| {'ok' if t['input_echo'] else t['input_echo']} |"
        )
    print()
    print(
        "| data | pane | readout rows (stitched) | every value + name whole | ellipsis | renderer ↩ breaks | edge rows |"
    )
    print("|---|---|---|---|---|---|---|")
    for t in table:
        if t["surface"] == "readout":
            ok = not t["values_missing"] and not t["names_missing"]
            print(
                f"| {t['data']} | {t['cols']}×{t['pane_rows']} | {t['readout_rows']} | {'yes' if ok else 'NO ' + str(t['values_missing'][:4] + t['names_missing'])} "
                f"| {t['ellipsis_rows']} | {len(t['hardbreak_rows'])} | {t['edge_rows']} |"
            )


def main():
    runs = sorted(
        d
        for d in os.listdir(CAP)
        if os.path.exists(os.path.join(CAP, d, "verdict.json"))
    )
    r4 = [r for r in runs if r.startswith("r4")]
    runs = [r for r in runs if not r.startswith("r4")]
    table, meta = [], {}
    for r in runs:
        v, rows = run_rows(r)
        meta[r] = {
            "turns_ok": v["turns_ok"],
            "pane_rows": v["pane_rows"],
            "band_gone_after_prompt": v["band_gone_after_prompt"],
        }
        table += rows
    r4meta, r4table = r4_main(r4)

    # The operator's bar (round 4 brief), over the fresh-board sweeps only: live-shaped rows show
    # everything on the first screen at >= 30 rows and >= 17 columns; fixture rows show every
    # account value on the first screen at >= 45 rows and >= 27 columns (alerts may scroll).
    def _bar(run_prefix, min_rows, min_cols):
        cells = [
            t
            for t in r4table
            if t["surface"] == "band"
            and t["run"] in [f"{run_prefix}-rows{h}" for h in (30, 45, 70)]
            and t["pane_rows"] >= min_rows
            and t["cols"] >= min_cols
        ]
        fails = [
            f"{t['cols']}x{t['pane_rows']}" for t in cells if not t["first_screen_all"]
        ]
        return {"checked": len(cells), "pass": not fails, "fails": fails}

    r4bar = {
        "live >=30 rows, >=17 cols": _bar("r4-live", 30, 17),
        "fixture >=45 rows, >=27 cols": _bar("r4-fx", 45, 27),
    }
    json.dump(
        {
            "cc": "2.1.293",
            "runs": meta,
            "steps": table,
            "round4": {"bar": r4bar, "runs": r4meta, "steps": r4table},
        },
        open(os.path.join(HERE, "verdict.json"), "w"),
        indent=1,
        ensure_ascii=False,
    )
    print(
        "| run | pane | band cells → layout (lines) | rows shown before cue | accounts whole on first screen | all values reachable by scroll | ellipsis rows | split tokens | input |"
    )
    print("|---|---|---|---|---|---|---|---|---|")
    for t in table:
        if t["surface"] != "band":
            continue
        miss = t["first_screen_missing"]
        first = (
            "all 4"
            if not miss
            else f"{4 - len(miss)} of 4 (missing {', '.join(m[:14] for m in miss)})"
        )
        reach = ("yes" if t["reachable_all_whole"] else "NO") + (
            "" if t["scroll_complete"] else " (scroll incomplete)"
        )
        print(
            f"| {t['run']} | {t['cols']}×{t['pane_rows']} | {t['band_cells']} → {t['layout']} ({t['layout_lines']}) "
            f"| {t['window_rows']}{' + ' + t['cue'] if t['cue'] else ''} | {first} | {reach} "
            f"| {t['band_ellipsis_rows']} | {', '.join(t['split_tokens'][:4]) or '—'} | {'ok' if t['input_echo'] else t['input_echo']} |"
        )
    print()
    print("| run | pane | readout accounts whole on the live screen | ellipsis rows |")
    print("|---|---|---|---|")
    for t in table:
        if t["surface"] == "readout":
            miss = t["first_screen_missing"]
            print(
                f"| {t['run']} | {t['cols']}×{t['pane_rows']} | "
                f"{'all 4' if not miss else f'{4 - len(miss)} of 4 on screen'} | {t['ellipsis_rows']} |"
            )


if __name__ == "__main__":
    if "--r4" in sys.argv:
        # `--prefix r5` judges a later round's runs (captures/r5-*) the same way (round 5)
        _pre = (
            sys.argv[sys.argv.index("--prefix") + 1] if "--prefix" in sys.argv else "r4"
        )
        _runs = sorted(
            d
            for d in os.listdir(CAP)
            if d.startswith(_pre + "-")
            and os.path.exists(os.path.join(CAP, d, "verdict.json"))
        )
        _meta, _table = r4_main(_runs)
        r4_print(_table)
        if "--write" in sys.argv:
            # Round 6: merge this round's runs, bar and steps into verdict.json under
            # `round<N>` (from the prefix), keeping every earlier round's keys as they are.
            def _bar6(data, min_rows, min_cols, need_picks):
                cells = [
                    t
                    for t in _table
                    if t["surface"] == "band"
                    and t["data"] == data
                    and t["run"].endswith(f"-rows{t['pane_rows']}")
                    and t["pane_rows"] >= min_rows
                    and t["cols"] >= min_cols
                ]
                fails = [
                    f"{t['cols']}x{t['pane_rows']}"
                    for t in cells
                    if not t["first_screen_all"]
                    or (need_picks and t["first_screen_picks_missing"])
                ]
                return {"checked": len(cells), "pass": not fails, "fails": fails}

            vp = os.path.join(HERE, "verdict.json")
            V = json.load(open(vp))
            V["round" + _pre.lstrip("r")] = {
                "bar": {
                    "live >=30 rows, >=17 cols (picks + every value)": _bar6(
                        "live", 30, 17, True
                    ),
                    "fixture >=45 rows, >=27 cols (every value)": _bar6(
                        "fx", 45, 27, False
                    ),
                },
                "runs": _meta,
                "steps": _table,
            }
            json.dump(V, open(vp, "w"), indent=1, ensure_ascii=False)
    else:
        main()
