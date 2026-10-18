#!/usr/bin/env python3
"""a8_child_timing.py — axis A8: per-CHILD end time for dispatcher children that leave a sid-keyed
trace, joined to the dispatcher run of the same session.

READ-ONLY. Sources:
  - dispatcher runs: SessionStart attachments of session-start-dispatch.sh in the transcript list
    (sid = transcript file uuid; start = record ts - durationMs).
  - session-index-start.sh writes ONE IDL row per invocation from an EXIT trap
    (hooks/session-index-start.sh:14-17): {"ts", "hook":"session-index-start", "sid",
    "disposition", "reason":"exit:<rc>"}. ts has 1 s resolution.
For each dispatcher run the child's (row ts - dispatcher start) bounds its runtime from above, to
+/- 1 s. A run with no row, or a row with exit:143 (SIGTERM), is a child the watchdog killed.

Usage: python3 -I a8_child_timing.py [file_list] [idl_path]
"""

import json, sys, os, collections
from datetime import datetime


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    return xs[max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))]


def main():
    flist = sys.argv[1] if len(sys.argv) > 1 else "/tmp/startup-hooks-census-files.txt"
    idl = (
        sys.argv[2]
        if len(sys.argv) > 2
        else os.path.expanduser("~/.claude/autonomy/idl.jsonl")
    )
    runs = []  # (sid, start, ms, timedOut)
    for path in open(flist).read().split():
        sid = os.path.basename(path).rsplit(".", 1)[0]
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if "session-start-dispatch" not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                a = r.get("attachment") or {}
                if a.get("type") not in ("hook_success", "hook_cancelled"):
                    continue
                if "session-start-dispatch" not in str(a.get("command", "")):
                    continue
                t = ts(r.get("timestamp", ""))
                ms = a.get("durationMs")
                if t is None or ms is None:
                    continue
                runs.append((sid, t - ms / 1000.0, int(ms), bool(a.get("timedOut"))))
    sids = {s for s, _, _, _ in runs}
    rows = collections.defaultdict(list)  # sid -> [(ts, disposition, reason)]
    with open(idl, errors="replace") as fh:
        for line in fh:
            if '"session-index-start"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("hook") != "session-index-start" or r.get("sid") not in sids:
                continue
            t = ts(r.get("ts", ""))
            if t is not None:
                rows[r["sid"]].append((t, r.get("disposition"), r.get("reason")))
    found = []
    missing = 0
    killed = 0
    reasons = collections.Counter()
    band = collections.defaultdict(list)
    for sid, st, ms, to in runs:
        cand = [x for x in rows.get(sid, []) if st - 2 <= x[0] <= st + 40]
        if not cand:
            missing += 1
            band["dispatch>=9s" if ms >= 9000 else "dispatch<9s"].append(None)
            continue
        t, disp, rsn = min(cand, key=lambda x: x[0])
        reasons[rsn] += 1
        if rsn == "exit:143":
            killed += 1
        d = t - st
        found.append(d)
        band["dispatch>=9s" if ms >= 9000 else "dispatch<9s"].append(d)
    print(
        f"dispatcher runs: {len(runs)}  with a session-index-start IDL row: {len(found)}  no row: {missing}"
    )
    print(f"row reasons: {dict(reasons)}")
    print(
        f"child end - dispatcher start (s, 1 s resolution): p50={pct(found, 50):.1f} p75={pct(found, 75):.1f} "
        f"p90={pct(found, 90):.1f} p99={pct(found, 99):.1f} max={max(found):.1f}"
    )
    print(
        f"  >=8s: {sum(1 for d in found if d >= 8)}  >=9s: {sum(1 for d in found if d >= 9)}"
    )
    for k, xs in sorted(band.items()):
        ys = [x for x in xs if x is not None]
        print(
            f"  {k}: n={len(xs)} no-row={sum(1 for x in xs if x is None)} "
            f"p50={pct(ys, 50) if ys else None} p90={pct(ys, 90) if ys else None} "
            f">=8.5s={sum(1 for y in ys if y >= 8.5)}"
        )


if __name__ == "__main__":
    main()
