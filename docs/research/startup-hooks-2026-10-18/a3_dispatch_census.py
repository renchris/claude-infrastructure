#!/usr/bin/env python3
"""a3_dispatch_census.py — per-child attribution of session-start-dispatch.sh runs (axis A3).

READ-ONLY. Reads the transcript list (default /tmp/startup-hooks-census-files.txt), pulls every
attachment whose command is session-start-dispatch.sh, and for each run records duration, source,
merged-context length and which CHILD signatures are present in its stdout. A child that always
prints (setup-plan-symlinks, setup-task-symlinks, session-start.sh MCP line, accounts-board on
non-compact) and is ABSENT in a run is a child the 9 s per-child bound killed (or that failed).

Usage: python3 -I a3_dispatch_census.py [file_list] [--rows out.tsv]
"""

import json, sys, statistics, collections

SIG = {  # child -> (channel, predicate on (ctx, sm))
    "recycle-failed-inject": lambda c, s: "RECYCLE FAILED" in c,
    "session-start(MCP)": lambda c, s: "MCP:" in c or "MCP " in c[:200],
    "setup-plan-symlinks": lambda c, s: "Plans: " in c,
    "setup-task-symlinks": lambda c, s: "Tasks: " in c,
    "session-index-start": lambda c, s: "Session index" in c,
    "frontier-status": lambda c, s: "Frontier:" in c,
    "accounts-board": lambda c, s: "CLAUDE MAX" in s or "accounts board" in s,
    "activation-watch": lambda c, s: "activation" in s.lower(),
    "escalation-watch": lambda c, s: "escalation" in s.lower() or "sweep" in s.lower(),
    "config-mirror-assert": lambda c, s: "mirror" in s.lower(),
}


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))
    return xs[k]


def main():
    args = sys.argv[1:]
    rows_out = None
    if "--rows" in args:
        i = args.index("--rows")
        rows_out = args[i + 1]
        del args[i : i + 2]
    flist = args[0] if args else "/tmp/startup-hooks-census-files.txt"
    files = [l.strip() for l in open(flist) if l.strip() and "/subagents/" not in l]
    runs = []
    for f in files:
        try:
            fh = open(f, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if "session-start-dispatch" not in line:
                    continue
                try:
                    a = json.loads(line).get("attachment") or {}
                except Exception:
                    continue
                if "session-start-dispatch" not in str(a.get("command", "")):
                    continue
                t = a.get("type")
                if t not in (
                    "hook_success",
                    "hook_cancelled",
                    "hook_error",
                    "hook_non_blocking_error",
                ):
                    continue
                out = a.get("stdout") or ""
                ctx, sm = "", ""
                try:
                    j = json.loads(out) if out.strip() else {}
                    ctx = (j.get("hookSpecificOutput") or {}).get(
                        "additionalContext"
                    ) or ""
                    sm = j.get("systemMessage") or ""
                except Exception:
                    ctx = out
                runs.append(
                    {
                        "file": f,
                        "type": t,
                        "src": str(a.get("hookName", "")).split(":")[-1],
                        "ms": a.get("durationMs"),
                        "timedOut": bool(a.get("timedOut")),
                        "ctx_len": len(ctx),
                        "sm_len": len(sm),
                        "kids": {k: bool(p(ctx, sm)) for k, p in SIG.items()},
                    }
                )
    ok = [
        r
        for r in runs
        if r["type"] == "hook_success" and isinstance(r["ms"], (int, float))
    ]
    canc = [r for r in runs if r["type"] == "hook_cancelled"]
    print(
        f"dispatcher records: {len(runs)}  success-with-ms: {len(ok)}  cancelled: {len(canc)}"
    )
    ms = [r["ms"] for r in ok]
    for p in (50, 75, 90, 95, 99):
        print(f"  p{p}: {pct(ms, p)} ms")
    print(f"  max: {max(ms) if ms else None} ms")
    print(
        f"  >=9000ms: {sum(1 for x in ms if x >= 9000)}  >=10000: {sum(1 for x in ms if x >= 10000)}"
        f"  >=11000: {sum(1 for x in ms if x >= 11000)}  >=12000: {sum(1 for x in ms if x >= 12000)}"
    )
    print("cancelled durations:", sorted(r["ms"] for r in canc if r["ms"] is not None))
    print("by source:", collections.Counter(r["src"] for r in runs))

    # presence of always-printing children, split by duration band
    bands = [
        ("<8s", lambda x: x < 8000),
        ("8-9s", lambda x: 8000 <= x < 9000),
        (">=9s", lambda x: x >= 9000),
    ]
    print(
        "\nchild presence rate by dispatcher-duration band (success runs, non-compact for accounts-board):"
    )
    hdr = "child".ljust(24) + "".join(b.ljust(18) for b, _ in bands)
    print(hdr)
    for k in SIG:
        cells = []
        for b, pred in bands:
            sel = [
                r
                for r in ok
                if pred(r["ms"]) and (k != "accounts-board" or r["src"] != "compact")
            ]
            n = len(sel)
            y = sum(1 for r in sel if r["kids"][k])
            cells.append(f"{y}/{n}".ljust(18))
        print(k.ljust(24) + "".join(cells))

    # missing-set signature among >=9s runs (which always-printers are absent)
    always = [
        "session-start(MCP)",
        "setup-plan-symlinks",
        "setup-task-symlinks",
        "accounts-board",
    ]
    miss = collections.Counter()
    for r in ok:
        if r["ms"] >= 9000:
            m = tuple(
                k
                for k in always
                if not r["kids"][k]
                and not (k == "accounts-board" and r["src"] == "compact")
            )
            miss[m] += 1
    print("\nmissing always-printer sets among >=9s runs:")
    for m, n in miss.most_common():
        print(f"  {n:4d}  {m or '(none missing)'}")
    miss2 = collections.Counter()
    for r in ok:
        if r["ms"] < 9000:
            m = tuple(
                k
                for k in always
                if not r["kids"][k]
                and not (k == "accounts-board" and r["src"] == "compact")
            )
            miss2[m] += 1
    print("missing always-printer sets among <9s runs (baseline: non-kill absences):")
    for m, n in miss2.most_common():
        print(f"  {n:4d}  {m or '(none missing)'}")

    cl = [r["ctx_len"] for r in ok]
    print(
        f"\nmerged ctx chars: p50 {pct(cl, 50)} p90 {pct(cl, 90)} max {max(cl) if cl else None}"
        f"  >=9500 (cap hit): {sum(1 for x in cl if x >= 9500)}"
    )
    sl = [r["sm_len"] for r in ok]
    print(
        f"systemMessage chars: p50 {pct(sl, 50)} p90 {pct(sl, 90)} max {max(sl) if sl else None}"
    )
    if rows_out:
        with open(rows_out, "w") as o:
            o.write(
                "file\ttype\tsrc\tms\ttimedOut\tctx_len\tsm_len\t"
                + "\t".join(SIG)
                + "\n"
            )
            for r in runs:
                o.write(
                    "\t".join(
                        map(
                            str,
                            [
                                r["file"],
                                r["type"],
                                r["src"],
                                r["ms"],
                                r["timedOut"],
                                r["ctx_len"],
                                r["sm_len"],
                            ]
                            + [int(r["kids"][k]) for k in SIG],
                        )
                    )
                    + "\n"
                )


if __name__ == "__main__":
    main()
