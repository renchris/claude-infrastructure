#!/usr/bin/env python3
"""A7 prior-art: compare SessionStart startup span before and after migration 0056, load-binned.

Read-only. Reads transcript jsonl files (paths on stdin, one per line), groups SessionStart hook
records by toolUseID (one batch = one SessionStart firing), and for each batch computes:
  span_ms   = max durationMs over hook_success/hook_cancelled records of SYNC hooks in that batch
  cancels   = list of hook commands with hook_cancelled
  n_records = number of hook records with a durationMs
Load = capacity-alarm.jsonl load_1m at the nearest sample at or before the batch's first timestamp
(current file + the 2026-10-09 rotation, gz).

KNOWN BIAS (inherited, see brief): hook_success with durationMs is recorded only when a hook prints
something, so span is a lower bound when the slowest hook printed nothing.

Usage: python3 -I a7_era_compare.py < filelist        (prints a JSON summary)
Era boundary: migration 0056 applied 2026-10-04T21:06:41Z (backup dir stamp 20261004160641, CDT).
"""

import bisect, gzip, json, os, sys
from datetime import datetime, timezone

ERA_CUT = datetime(2026, 10, 4, 21, 6, 41, tzinfo=timezone.utc)
ASYNC = {
    "pre-session-validate.sh",
    "lead-crash-watchdog.sh",
    "session-register.sh",
    "live-session-registry.sh",
    "net-context-stamp.sh",
    "mailbox-wake-arm.sh",
}


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def load_series():
    pts = []
    home = os.path.expanduser("~/.claude/logs")
    srcs = [
        os.path.join(home, "capacity-alarm.jsonl.20261009T015023Z.gz"),
        os.path.join(home, "capacity-alarm.jsonl"),
    ]
    for p in srcs:
        if not os.path.exists(p):
            continue
        op = gzip.open if p.endswith(".gz") else open
        with op(p, "rt", errors="replace") as fh:
            for line in fh:
                if '"load_1m"' not in line:
                    continue
                try:
                    r = json.loads(line)
                    pts.append((ts(r["ts"]).timestamp(), float(r["load_1m"])))
                except Exception:
                    pass
    pts.sort()
    return [p[0] for p in pts], [p[1] for p in pts]


def base(cmd):
    c = (cmd or "").strip()
    b = c.split("/")[-1]
    return b


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = max(0, min(len(xs) - 1, int(round(p / 100.0 * len(xs) + 0.5)) - 1))
    return xs[k]


def main():
    lt, lv = load_series()
    batches = {}
    for path in sys.stdin:
        path = path.strip()
        if not path or "/subagents/" in path:
            continue
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"hookEvent":"SessionStart"' not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                a = r.get("attachment") or {}
                if a.get("hookEvent") != "SessionStart":
                    continue
                tid = a.get("toolUseID") or (
                    r.get("sessionId", "") + r.get("timestamp", "")[:16]
                )
                key = (r.get("sessionId"), tid)
                b = batches.setdefault(
                    key,
                    {
                        "t0": r.get("timestamp"),
                        "src": a.get("hookName", ""),
                        "durs": {},
                        "cancel": [],
                        "types": set(),
                        "cwd": r.get("cwd", ""),
                    },
                )
                if r.get("timestamp") and r["timestamp"] < b["t0"]:
                    b["t0"] = r["timestamp"]
                b["types"].add(a.get("type"))
                cmd = base(a.get("command", ""))
                d = a.get("durationMs")
                if a.get("type") in (
                    "hook_success",
                    "hook_cancelled",
                    "hook_error",
                    "hook_non_blocking_error",
                ) and isinstance(d, (int, float)):
                    b["durs"][cmd] = max(d, b["durs"].get(cmd, 0))
                if a.get("type") == "hook_cancelled":
                    b["cancel"].append(cmd)
    rows = []
    for (sid, tid), b in batches.items():
        try:
            t = ts(b["t0"])
        except Exception:
            continue
        sync = {k: v for k, v in b["durs"].items() if k not in ASYNC}
        if not sync:
            continue
        i = bisect.bisect_right(lt, t.timestamp()) - 1
        load = lv[i] if i >= 0 and t.timestamp() - lt[i] < 900 else None
        era = "pre0056" if t < ERA_CUT else "post0056"
        rows.append(
            {
                "sid": sid,
                "t": b["t0"],
                "era": era,
                "src": b["src"],
                "load": load,
                "span": max(sync.values()),
                "nsync": len(sync),
                "durs": sync,
                "cancel": b["cancel"],
                "board": "hook_system_message" in b["types"],
                "dispatch": "session-start-dispatch.sh" in sync,
            }
        )
    out = {"n_batches": len(rows), "groups": {}}
    # full-registration batches only: pre era needs >=5 sync printers, post era needs the dispatcher
    for era in ("pre0056", "post0056"):
        for lo, hi in ((0, 50), (50, 150), (150, 300), (300, 10000)):
            sel = [
                r
                for r in rows
                if r["era"] == era
                and r["load"] is not None
                and lo <= r["load"] < hi
                and (r["nsync"] >= 5 if era == "pre0056" else r["dispatch"])
            ]
            if not sel:
                continue
            sp = [r["span"] / 1000.0 for r in sel]
            out["groups"][f"{era} load[{lo},{hi})"] = {
                "n": len(sel),
                "p50": pct(sp, 50),
                "p90": pct(sp, 90),
                "p95": pct(sp, 95),
                "max": max(sp),
                "batches_with_cancel": sum(1 for r in sel if r["cancel"]),
                "board_rendered": sum(1 for r in sel if r["board"]),
            }
    # per-hook cancels by era
    cz = {}
    for r in rows:
        for c in r["cancel"]:
            cz.setdefault(r["era"], {}).setdefault(c, 0)
            cz[r["era"]][c] += 1
    out["cancels_by_era"] = cz
    out["n_by_era"] = {
        e: sum(1 for r in rows if r["era"] == e) for e in ("pre0056", "post0056")
    }
    json.dump(out, sys.stdout, indent=1, sort_keys=True)
    print()
    if os.environ.get("A7_ROWS"):
        with open(os.environ["A7_ROWS"], "w") as fh:
            for r in rows:
                fh.write(json.dumps(r) + "\n")


if __name__ == "__main__":
    main()
