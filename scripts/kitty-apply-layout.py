#!/usr/bin/env python3
# kitty-apply-layout.py — give a Splits tab an EXACT tree (axis, bias, pane order) over the panes it
# already holds, without restarting any of them.
#
#   kitty @ [--to SOCK] kitten --match id:<any pane of the tab> <abs path>/kitty-apply-layout.py <spec.json>
#
# spec.json: {"pairs": <kitty serialized pairs whose leaves are kitty WINDOW ids>, "result": <path>}
# The kitten writes {"ok": true|false, "why": …, "tab": id, "have": [...], "want": [...]} to "result",
# and prints the same JSON on stdout. Either says only what the kitten
# did; the verdict a caller should act on is the read-back of `kitty @ ls` (scripts/lib/kitty_tree.py).
#
# WHY A KITTEN (2026-10-15, after the 00:01:27 crash recovery came back in different pane positions):
# kitty has no remote command that sets a tab's split tree. Splits.set_layout_state (kitty 0.48.2
# kitty/layout/splits.py:980-1004) does, but kitty only calls it for a tab built from a session file
# (tabs.py:363). A kitten runs inside kitty with the boss, so it can call it on a live tab — the
# same route scripts/kitty-equalize.py takes for reset_window_sizes. set_layout_state refuses unless
# the new tree names exactly the tab's current window groups, so it can neither drop nor invent a
# pane; this file refuses earlier still, with the difference written down.
import json
from typing import Any

from kittens.tui.handler import result_handler


def main(args: list[str]) -> None:
    pass


def _write(path: str, obj: dict) -> str:
    # `kitty @ kitten` prints a str the handler returns (rc/kitten.py:43-44); the file serves a
    # caller that dispatched through `@ action`, which returns nothing.
    if path:
        try:
            with open(path, "w") as fh:
                json.dump(obj, fh)
        except OSError:
            pass
    return json.dumps(obj)


@result_handler(no_ui=True)
def handle_result(
    args: list[str], answer: str, target_window_id: int, boss: Any
) -> str:
    spec_path = args[1] if len(args) > 1 else ""
    try:
        with open(spec_path) as fh:
            spec = json.load(fh)
    except (OSError, ValueError) as e:
        return _write(
            spec_path + ".result", {"ok": False, "why": "spec unreadable: %s" % e}
        )
    res = spec.get("result") or spec_path + ".result"
    w = boss.window_id_map.get(target_window_id)
    tab = boss.tab_for_id(w.tab_id) if w is not None else None
    if tab is None:
        return _write(
            res, {"ok": False, "why": "no tab holds window %s" % target_window_id}
        )
    layout = tab.current_layout
    if layout.name != "splits":
        return _write(
            res,
            {
                "ok": False,
                "why": "tab %s is in layout %s, not splits" % (tab.id, layout.name),
                "tab": tab.id,
            },
        )

    # window ids → the group ids kitty's pairs are written in
    gid: dict[int, int] = {}
    for g in tab.windows.iter_all_layoutable_groups():
        for win in g:
            gid[win.id] = g.id

    def conv(x: Any) -> Any:
        if isinstance(x, int):
            if x not in gid:
                raise KeyError(x)
            return gid[x]
        if isinstance(x, dict):
            return {k: (conv(v) if k in ("one", "two") else v) for k, v in x.items()}
        return x

    try:
        pairs = conv(spec.get("pairs") or {})
    except KeyError as e:
        return _write(
            res,
            {
                "ok": False,
                "why": "window %s is not in tab %s" % (e.args[0], tab.id),
                "tab": tab.id,
            },
        )

    def gids(x: Any) -> list:
        if isinstance(x, int):
            return [x]
        if isinstance(x, dict):
            return gids(x.get("one")) + gids(x.get("two"))
        return []

    want = gids(pairs)
    have = sorted({g.id for g in tab.windows.iter_all_layoutable_groups()})
    if sorted(want) != have:
        return _write(
            res,
            {
                "ok": False,
                "why": "the tree names other panes than the tab holds",
                "tab": tab.id,
                "have": have,
                "want": sorted(want),
            },
        )
    # pairs_root learns of a newly attached group only in do_layout (splits.py:612-621), so lay out
    # first; set_layout_state itself never lays out (splits.py:980-1004).
    tab.relayout()
    ok = layout.set_layout_state(
        {"pairs": pairs, "opts": layout.layout_opts.serialized()}, lambda g: g
    )
    if ok:
        tab.relayout()
    return _write(
        res,
        {
            "ok": bool(ok),
            "why": "" if ok else "set_layout_state refused",
            "tab": tab.id,
        },
    )
