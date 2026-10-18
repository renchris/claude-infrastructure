#!/usr/bin/env python3
"""a3_child_timing.py — READ-ONLY. Joins session-start-dispatch.sh runs (transcripts) with the
session-index-start EXIT-trap IDL row (idl.jsonl, 1 s resolution) to time ONE child from outside,
and splits dispatcher durations by whether the conditional config-mirror-assert warning rendered.

dispatch start  = attachment timestamp - durationMs   (harness records the result at completion)
child exit      = first IDL row hook=session-index-start, sid=<sid>, ts >= start-1s
Usage: python3 -I a3_child_timing.py [file_list] [idl_path]
"""

import json, sys, os, datetime as dt, bisect, collections


def ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def main():
    flist = sys.argv[1] if len(sys.argv) > 1 else "/tmp/startup-hooks-census-files.txt"
    idl = (
        sys.argv[2]
        if len(sys.argv) > 2
        else os.path.expanduser("~/.claude/autonomy/idl.jsonl")
    )
    rows = collections.defaultdict(list)
    with open(idl, errors="replace") as fh:
        fh.seek(max(0, os.path.getsize(idl) - 60_000_000))
        fh.readline()
        for line in fh:
            if '"session-index-start"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            rows[r.get("sid", "")].append((ts(r["ts"]), r.get("reason", "")))
    out = []
    for f in (l.strip() for l in open(flist)):
        if not f or "/subagents/" in f:
            continue
        sid = os.path.basename(f)[:-6]
        try:
            fh = open(f, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if "session-start-dispatch" not in line:
                    continue
                try:
                    j = json.loads(line)
                except Exception:
                    continue
                a = j.get("attachment") or {}
                if "session-start-dispatch" not in str(a.get("command", "")) or a.get(
                    "type"
                ) not in ("hook_success", "hook_cancelled"):
                    continue
                d = a.get("durationMs")
                if not isinstance(d, (int, float)) or not j.get("timestamp"):
                    continue
                end = ts(j["timestamp"])
                start = end - d / 1000
                cand = sorted(
                    t for t, _ in rows.get(sid, []) if start - 1.0 <= t <= end + 30
                )
                sis = (cand[0] - start) if cand else None
                sm = ""
                try:
                    sm = (json.loads(a.get("stdout") or "{}") or {}).get(
                        "systemMessage"
                    ) or ""
                except Exception:
                    pass
                out.append((d, sis, "knowledge-layer mirror" in sm, a.get("type")))
    print(
        f"runs={len(out)}  joined-with-session-index-start={sum(1 for o in out if o[1] is not None)}"
    )

    def q(xs, p):
        xs = sorted(xs)
        return (
            round(xs[min(len(xs) - 1, int(p * (len(xs) - 1) + 0.5))], 1) if xs else None
        )

    for lbl, sel in (
        ("dispatch<9s", lambda o: o[0] < 9000),
        ("dispatch>=9s", lambda o: o[0] >= 9000),
    ):
        xs = [o[1] for o in out if sel(o) and o[1] is not None]
        print(
            f"{lbl}: session-index-start exit offset (s) n={len(xs)} p50={q(xs, 0.5)} p90={q(xs, 0.9)} max={q(xs, 1)}"
        )
    late = [o for o in out if o[0] >= 9000 and o[1] is not None]
    print(
        "dispatch>=9s: sis exit offset >=8.5s (near the 9 s bound):",
        sum(1 for o in late if o[1] >= 8.5),
        "/",
        len(late),
    )
    # dispatch overhead = dispatcher duration minus slowest observed child cannot be computed; print
    # the gap between the 9 s bound and dispatch durations that sit in the 9-10.5 s pile.
    pile = [o[0] for o in out if 9000 <= o[0] < 10500]
    print(
        f"9.0-10.5 s pile: n={len(pile)}  (dispatch - 9000) ms p50={q([p - 9000 for p in pile], 0.5)} p90={q([p - 9000 for p in pile], 0.9)}"
    )


if __name__ == "__main__":
    main()
