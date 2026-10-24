#!/usr/bin/env python3
# Controls: fresh (non-successor) sessions in a cwd that also hosts a recycle pair, each paired with the
# most recent OTHER main session in that cwd that was last active before the control's first prompt and
# within MAXGAP_H hours of it (the "pseudo-predecessor": what a new session in the same tree could re-read).
# usage: python3 -I controls.py <workdir> <maxgap_h>  -> controls.jsonl, stage2 path list
import glob, json, os, sys
from datetime import datetime

W, MAXGAP_H = sys.argv[1], float(sys.argv[2])
KW = (
    "handoff",
    "recycle",
    "predecessor",
    "successor",
    "continuation",
    "continuing",
    "you are continuing",
    "resumed by",
    "inheriting",
)


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


R = [json.loads(l) for f in glob.glob(os.path.join(W, "idx.*.jsonl")) for l in open(f)]
by_sid = {}
for r in R:
    k = r["sessionId"] or r["sid"]
    if k not in by_sid or r["size"] > by_sid[k]["size"]:
        by_sid[k] = r
pairs = [json.loads(l) for l in open(os.path.join(W, "pairs.jsonl"))]
pair_cwds = {p["cwd"] for p in pairs if p["pred_path"]}
by_cwd = {}
for k, r in by_sid.items():
    by_cwd.setdefault(r["cwd"], []).append(r)
ctl = []
for cwd in pair_cwds:
    L = by_cwd.get(cwd, [])
    for c in L:
        fp = c["first_prompt"] or ""
        if not fp or c["markers"] or any(k in fp.lower() for k in KW):
            continue
        t0 = ep(c["fp_ts"] or "")
        if t0 is None:
            continue
        best, bp = None, None
        for o in L:
            if o is c:
                continue
            tl = ep(o["ts_last"] or "")
            if tl is None or tl >= t0:
                continue
            if t0 - tl <= MAXGAP_H * 3600 and (best is None or t0 - tl < best):
                best, bp = t0 - tl, o
        if bp:
            ctl.append(
                dict(
                    ctl=c["sessionId"] or c["sid"],
                    ctl_path=c["path"],
                    cwd=cwd,
                    fp_ts=c["fp_ts"],
                    prev=bp["sessionId"] or bp["sid"],
                    prev_path=bp["path"],
                    gap_s=best,
                    ctl_first_prompt=fp[:200],
                    prev_is_recycle_succ=bool(bp["markers"]),
                )
            )
with open(os.path.join(W, "controls.jsonl"), "w") as f:
    for c in ctl:
        f.write(json.dumps(c) + "\n")
paths = set()
for p in pairs:
    if p["pred_path"]:
        paths.add(p["succ_path"])
        paths.add(p["pred_path"])
for c in ctl:
    paths.add(c["ctl_path"])
    paths.add(c["prev_path"])
with open(os.path.join(W, "stage2.paths"), "w") as f:
    f.write("\n".join(sorted(paths)) + "\n")
print("pair cwds", len(pair_cwds), "controls", len(ctl), "stage2 paths", len(paths))
