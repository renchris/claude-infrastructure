#!/usr/bin/env python3
"""Replay the working census at past sweep instants, old rule vs the D1.8 rule.

Both rules run over the SAME transcripts as they stood at instant T: every record stamped after T
is ignored, a file born after T does not exist, and a file's "mtime at T" is its newest record
stamp <= T. The new rule is the module's own _file_working/_session_settled, not a re-spelling.
"""

import importlib.machinery, importlib.util, json, os, re, sys
from datetime import datetime

CA = sys.argv[1]
_ld = importlib.machinery.SourceFileLoader("ca", CA)
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", _ld))
_ld.exec_module(ca)
ca.KWORK_TAIL_BYTES = (1 << 40,)  # full reads: history is not in the tail any more
ca.LOG_PATH = "/tmp/kmax-rebase.ca.log"

cfg = json.load(open(sys.argv[2]))
util = sys.argv[3]
INSTANTS = sys.argv[4].split(",")
WIN, HOR = 600.0, 1800.0
TS = re.compile(rb'"timestamp":"([0-9][0-9:.TZ+-]*)"')

logged = {}
for ln in open(util):
    try:
        r = json.loads(ln)
    except ValueError:
        continue
    if r.get("ts", "")[:19] in [i[:19] for i in INSTANTS]:
        logged[(r["ts"][:19], r["acct"])] = r

by_dir = {
    os.path.expanduser(a["config_dir"]).rstrip("/"): a["name"] for a in cfg["accounts"]
}
nxt = next(
    a["name"]
    for a in cfg["accounts"]
    if a["config_dir"].rstrip("/").endswith(".claude-next")
)
by_dir.setdefault(os.path.expanduser("~/.claude"), nxt)
files, seen = [], set()
for d, name in by_dir.items():
    rp = os.path.realpath(os.path.join(d, "projects"))
    if rp in seen:
        continue
    seen.add(rp)
    try:
        slugs = [e for e in os.scandir(rp) if e.is_dir(follow_symlinks=False)]
    except OSError:
        continue
    for slug in slugs:
        for wroot, _d, fns in os.walk(slug.path):
            for fn in fns:
                if not fn.endswith(".jsonl"):
                    continue
                sub = wroot != slug.path
                if sub and not fn.startswith("agent-"):
                    continue
                files.append((name, slug.path, wroot, fn, sub))

t_min = min(ca._iso_epoch(i) for i in INSTANTS) - HOR
cand = []
for name, slugp, wroot, fn, sub in files:
    p = os.path.join(wroot, fn)
    try:
        st = os.lstat(p)
    except OSError:
        continue
    if st.st_mtime < t_min:
        continue
    stamps = sorted(
        t
        for t in (ca._iso_epoch(m.group(1)) for m in TS.finditer(open(p, "rb").read()))
        if t is not None
    )
    cand.append((name, slugp, wroot, fn, sub, p, st, stamps))

rows = []
for inst in INSTANTS:
    T = ca._iso_epoch(inst)
    old = {a["name"]: [0, 0] for a in cfg["accounts"]}
    new = {a["name"]: [0, 0] for a in cfg["accounts"]}
    settled_cache = {}
    for name, slugp, wroot, fn, sub, p, st, stamps in cand:
        if st.st_birthtime > T:
            continue
        le = [t for t in stamps if t <= T]
        if not le:
            continue
        m_at_T = le[-1]
        if T - m_at_T <= WIN:
            old[name][1 if sub else 0] += 1
        sdir = (
            os.path.join(slugp, os.path.relpath(wroot, slugp).split(os.sep)[0])
            if sub
            else None
        )

        def settled(_d=sdir):
            if _d not in settled_cache:
                settled_cache[_d] = ca._session_settled(_d, T)
            return settled_cache[_d]

        if ca._file_working(
            p, m_at_T, st.st_size, T, WIN, sub=sub, settled=settled if sub else None
        ):
            new[name][1 if sub else 0] += 1
    for a in cfg["accounts"]:
        n = a["name"]
        lg = logged.get((inst[:19], n)) or {}
        k = lg.get("k")

        def bound(tp):
            top, s = tp
            return (min(top, k) if isinstance(k, int) else top) + s

        rows.append(
            dict(
                t=inst[11:19],
                acct=n,
                k_panes=k,
                logged_k_work=lg.get("k_work"),
                old_top=old[n][0],
                old_sub=old[n][1],
                old_bounded=bound(old[n]),
                new_top=new[n][0],
                new_sub=new[n][1],
                new_bounded=bound(new[n]),
            )
        )
print(json.dumps(rows))
