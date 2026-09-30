#!/usr/bin/env python3
"""dl-route — does an operator step belong in dl (the real-world deadline store), and in what form?

Called by `cc-backlog needs` (BACKLOG_MASTER W0 ledger-admission.7). A step is a REAL-WORLD ACT when
its project is `personal`, or its first word is a dl verb and it carries an external clock (a
--lost/--since/--resurface/--activate-when, or a YYYY-MM-DD in the text). For such a step this builds
the candidate item with dl's own build_item() and runs dl's own admit(), so the verdict is dl's, not a
re-implementation of it (memory: make-the-actuator-the-arbiter). It never writes to the dl store.

Prints one JSON object: {"real_act", "admitted", "cap_full", "reason", "line"}. `line` is the exact
`dl add …` command, present only when admit() accepted the candidate.
"""

from __future__ import annotations

import argparse
import importlib.machinery
import importlib.util
import json
import os
import re
import shlex
import sys

DATE = re.compile(r"\b(20\d\d-\d\d-\d\d)\b")


def load_dl():
    path = os.environ.get("CC_BACKLOG_DL_MODULE") or os.path.join(
        os.path.dirname(os.path.realpath(__file__)), "..", "..", "bin", "dl"
    )
    loader = importlib.machinery.SourceFileLoader("dl_route_dl", path)
    spec = importlib.util.spec_from_loader("dl_route_dl", loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["dl_route_dl"] = mod
    loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", required=True)
    ap.add_argument("--project", default="")
    ap.add_argument("--kind", default="")
    ap.add_argument("--lost")
    ap.add_argument("--since")
    ap.add_argument("--resurface")
    ap.add_argument("--activate-when", dest="activate_when")
    ap.add_argument("--class", dest="cls")
    ap.add_argument("--usd", type=float)
    ap.add_argument("--text", default="")
    ap.add_argument("--domain", default="")
    ap.add_argument("--source", action="append", default=[])
    ap.add_argument("--replaces")
    a = ap.parse_args()

    out = {
        "real_act": False,
        "admitted": False,
        "cap_full": False,
        "reason": "",
        "line": "",
    }
    dl = load_dl()
    title = a.title.strip()
    first = re.split(r"\W+", title, 1)[0].lower()
    date = DATE.search(title)
    clock = (
        a.lost
        or a.since
        or a.resurface
        or a.activate_when
        or (date.group(1) if date else None)
    )
    if a.project != "personal" and not (first in dl.VERBS and clock):
        print(json.dumps(out))
        return 0
    out["real_act"] = True
    kind = a.kind or (
        "someday"
        if (a.activate_when or a.resurface) and not (a.lost or date)
        else "decay"
        if a.since and not (a.lost or date)
        else "hard"
    )
    lost = a.lost or (date.group(1) if (date and kind in dl.DATED) else None)
    ns = argparse.Namespace(
        id=None,
        title=title,
        kind=kind,
        lost=lost,
        since=a.since,
        resurface=a.resurface,
        cls=a.cls,
        usd=a.usd,
        text=a.text,
        owner="operator",
        domain=a.domain or "admin",
        source=a.source or ["cc-backlog:needs"],
        phone=False,
        falsifier=None,
        void_if=None,
        activate_when=a.activate_when,
        recur=None,
        bundle=None,
        effort=None,
    )
    try:
        item = dl.build_item(ns)
        dl.admit(item, phone=False, replaces=a.replaces)
    except Exception as exc:  # dl.Refused, or a malformed date
        out["reason"] = str(exc)
        out["cap_full"] = "at its cap" in str(exc)
        print(json.dumps(out))
        return 0
    parts = ["dl", "add", "--kind", kind]
    for flag, val in (
        ("--lost", lost),
        ("--since", a.since if kind == "decay" else None),
        ("--resurface", a.resurface),
        ("--activate-when", a.activate_when),
        ("--class", a.cls),
        ("--usd", None if a.usd is None else ("%g" % a.usd)),
        ("--text", a.text or None),
        ("--domain", ns.domain),
        ("--owner", "operator"),
        ("--replaces", a.replaces),
    ):
        if val:
            parts += [flag, str(val)]
    for s in ns.source:
        parts += ["--source", s]
    parts.append(title)
    out["admitted"] = True
    out["line"] = " ".join(shlex.quote(p) for p in parts)
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
