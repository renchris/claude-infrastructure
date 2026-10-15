#!/usr/bin/env python3
"""kitty_tree.py — one model of a kitty Splits tab, shared by the restorer, cc-relayout and the tests.

A TREE is a leaf (any hashable label: a kitty window id, a session id, a plan key) or a pair
{"h": bool, "b": float, "one": TREE, "two": TREE}, exactly the shape of kitty's own Pair
(kitty 0.48.2 kitty/layout/splits.py:30-52): h is `horizontal` (side by side, `one` on the left),
b is `bias`, the share of `one`. kitty serializes `horizontal` only when False and `bias` only when
not 0.5; the leaves of `layout_state.pairs` are WINDOW GROUP ids, mapped to window ids through
`layout_state.all_windows.window_groups`.

Why one shared model: the planner's own self-check compared shapes with every leaf printed as "p",
so a plan that put the right shape around the WRONG sessions passed it. Every comparison here
carries leaf identity, and bias within BIAS_TOL.

CLI (used by bin/cc-resume-layout.sh and bin/cc-relayout; the library is the contract):
  kitty_tree.py tabs <ls.json>                 one JSON line per tab: {os_window, platform_window_id,
                                               tab, layout, tree (window ids), windows}
"""

import json
import sys

BIAS_TOL = 0.005


def is_pair(n):
    return isinstance(n, dict) and "one" in n and "two" in n


def leaves(n):
    if n is None:
        return []
    return leaves(n["one"]) + leaves(n["two"]) if is_pair(n) else [n]


def first(n):
    return first(n["one"]) if is_pair(n) else n


def from_pairs(pairs, group_windows=None):
    """kitty's serialized pairs → TREE. group_windows maps a group id to its window ids; a group
    leaf becomes its first window id (overlays sit on top of it and are not panes of their own)."""

    def conv(x):
        if x is None or isinstance(x, bool):
            return None
        if isinstance(x, int):
            if group_windows is None:
                return x
            ws = group_windows.get(x) or []
            return ws[0] if ws else None
        if not isinstance(x, dict):
            return None
        a, b = conv(x.get("one")), conv(x.get("two"))
        if a is None or b is None:
            return (
                a if b is None else b
            )  # a half-empty pair is its one child, as kitty lays it out
        try:
            bias = float(x.get("bias", 0.5))
        except (TypeError, ValueError):
            bias = 0.5
        return {
            "h": x.get("horizontal", True) is not False,
            "b": bias,
            "one": a,
            "two": b,
        }

    return conv(pairs)


def to_pairs(n):
    """TREE → kitty's serialized pairs (the root is always a pair, as kitty's pairs_root is)."""

    def conv(x):
        if not is_pair(x):
            return x
        out = {}
        if not x["h"]:
            out["horizontal"] = False
        if abs(x["b"] - 0.5) > 1e-12:
            out["bias"] = x["b"]
        out["one"] = conv(x["one"])
        out["two"] = conv(x["two"])
        return out

    if n is None:
        return {}
    return conv(n) if is_pair(n) else {"one": n}


def relabel(n, f):
    """Map every leaf through f; a leaf f maps to None is left out and its sibling takes the pair's
    space — what kitty itself does when a window closes (Pair.remove_windows + collapse)."""
    if n is None:
        return None
    if not is_pair(n):
        return f(n)
    a, b = relabel(n["one"], f), relabel(n["two"], f)
    if a is None or b is None:
        return a if b is None else b
    return {"h": n["h"], "b": n["b"], "one": a, "two": b}


def append_row(n, extra):
    """Put leaves the recorded tree does not know to the right of it, each beside the previous."""
    for x in extra:
        n = x if n is None else {"h": True, "b": 0.5, "one": n, "two": x}
    return n


def diff(a, b, path="root", tol=BIAS_TOL):
    """Every difference between two TREEs as a list of strings; [] means identical."""
    pa, pb = is_pair(a), is_pair(b)
    if not pa and not pb:
        return [] if a == b else ["%s: pane %r != %r" % (path, a, b)]
    if pa != pb:
        return [
            "%s: %s != %s"
            % (
                path,
                "pair" if pa else "pane %r" % (a,),
                "pair" if pb else "pane %r" % (b,),
            )
        ]
    out = []
    if a["h"] != b["h"]:
        out.append(
            "%s: axis %s != %s"
            % (path, "vsplit" if a["h"] else "hsplit", "vsplit" if b["h"] else "hsplit")
        )
    if abs(a["b"] - b["b"]) > tol:
        out.append("%s: bias %.4f != %.4f" % (path, a["b"], b["b"]))
    return (
        out
        + diff(a["one"], b["one"], path + ".one", tol)
        + diff(a["two"], b["two"], path + ".two", tol)
    )


def sig(n):
    if not is_pair(n):
        return str(n)
    b = "" if abs(n["b"] - 0.5) < BIAS_TOL else ":%.3f" % n["b"]
    return "%s%s(%s,%s)" % ("H" if n["h"] else "V", b, sig(n["one"]), sig(n["two"]))


def split_at(n, anchor, new, horizontal, bias_pct):
    """One `kitty @ launch --location=vsplit|hsplit --next-to <anchor> [--bias P]`, as kitty 0.48.2
    does it (splits.py:629-660): the anchor's leaf becomes a pair (anchor, new); --bias is the NEW
    window's share in percent, so the pair's bias (the share of `one`) is 1 - P/100."""
    if not is_pair(n):
        if n != anchor:
            return n
        b = (
            0.5
            if bias_pct in (None, "", 0)
            else 1 - max(0.0, min(abs(float(bias_pct)), 100.0)) / 100
        )
        return {"h": horizontal, "b": b, "one": n, "two": new}
    return dict(
        n,
        one=split_at(n["one"], anchor, new, horizontal, bias_pct),
        two=split_at(n["two"], anchor, new, horizontal, bias_pct),
    )


def ls_tabs(data):
    """`kitty @ ls` → [{os_window, platform_window_id, tab, layout, tree, windows}] per tab."""
    out = []
    for o in data if isinstance(data, list) else []:
        for t in o.get("tabs") or []:
            wins = [w.get("id") for w in t.get("windows") or [] if isinstance(w, dict)]
            st = t.get("layout_state") or {}
            gl = (st.get("all_windows") or {}).get("window_groups") or []
            gw = {
                g.get("id"): [w for w in g.get("window_ids") or [] if w in wins]
                for g in gl
            }
            if st.get("class") == "Splits" and isinstance(st.get("pairs"), dict) and gw:
                tree = from_pairs(st["pairs"], gw)
            else:
                tree = append_row(None, [ws[0] for ws in gw.values() if ws] or wins)
            out.append(
                {
                    "os_window": o.get("id"),
                    "platform_window_id": o.get("platform_window_id"),
                    "tab": t.get("id"),
                    "layout": t.get("layout"),
                    "tree": tree,
                    "windows": wins,
                }
            )
    return out


def main(argv):
    if len(argv) == 3 and argv[1] == "tabs":
        with open(argv[2]) as fh:
            for t in ls_tabs(json.load(fh)):
                print(json.dumps(t))
        return 0
    sys.stderr.write(__doc__.split("CLI", 1)[1])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
