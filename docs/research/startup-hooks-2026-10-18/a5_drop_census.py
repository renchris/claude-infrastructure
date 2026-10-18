#!/usr/bin/env python3
"""a5_drop_census.py — silent-drop fault-tree census for SessionStart hooks (axis A5).

READ-ONLY. Reads main-session transcripts (default list /tmp/startup-hooks-census-files.txt; subagent
transcripts excluded), keeps every attachment whose hookEvent is SessionStart, groups them per
SessionStart event (toolUseID), and counts each drop path the A5 report enumerates:

  P1  harness timeout kill        hook_cancelled (any SessionStart hook), by command and source
  P2  dispatcher child kill       dispatcher durationMs >= bound (9000 ms) => >=1 child killed
  P3  dispatcher 9500 cap         merged additionalContext length == 9500 (cut from the end)
  P4  harness 10000 cap           any single hook's context >= 10000 chars
  P5  non-zero exit / error       hook_non_blocking_error, hook_error_during_execution, hook_blocking_error
  P6  async stderr / exit         async_hook_response with stderr or exitCode != 0 (never shown, never sent)
  P7  async systemMessage         async_hook_response whose response carries systemMessage/additionalContext
  P8  async delivery lag          async_hook_response timestamp minus the event's first record
  P9  missing dispatcher record   event with no dispatcher success/cancel record (printed nothing / not run)
  P10 leaked raw JSON             dispatcher context containing '"systemMessage"' or '"hookSpecificOutput"'
  P11 board missing               dispatcher ran on startup/clear/resume but systemMessage lacks the board

Usage: python3 -I a5_drop_census.py [file_list]
"""

import collections
import json
import statistics
import sys
from datetime import datetime

DISPATCH = "session-start-dispatch.sh"
BOUND_MS = 9000
CAP = 9500
HARNESS_CAP = 10000


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))
    return xs[k]


def short(cmd):
    if not cmd:
        return "?"
    return cmd.replace("~/.claude/hooks/", "")


def ctx_of(stdout):
    """Return (additionalContext, systemMessage, is_json) from a hook's stdout."""
    s = (stdout or "").strip()
    if not s:
        return "", "", False
    try:
        j = json.loads(s)
    except Exception:
        return s, "", False
    if not isinstance(j, dict):
        return s, "", False
    hso = j.get("hookSpecificOutput") or {}
    c = hso.get("additionalContext") if isinstance(hso, dict) else ""
    return (c or ""), (j.get("systemMessage") or ""), True


SINCE = None  # epoch seconds; --since ISO (default: none). Long-lived transcripts carry older events.


def main():
    global SINCE
    argv = sys.argv[1:]
    if "--since" in argv:
        i = argv.index("--since")
        SINCE = ts(argv[i + 1])
        del argv[i : i + 2]
    flist = argv[0] if argv else "/tmp/startup-hooks-census-files.txt"
    print("since:", SINCE)
    files = [l.strip() for l in open(flist) if l.strip() and "/subagents/" not in l]
    events = (
        collections.OrderedDict()
    )  # (file, toolUseID) -> list of attachments with ts
    asyncs = []  # (file, ts, attachment)
    first_ts_by_file = {}
    for f in files:
        try:
            fh = open(f, "r", errors="replace")
        except Exception:
            continue
        with fh:
            for line in fh:
                if '"SessionStart' not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                a = r.get("attachment") or {}
                if a.get("hookEvent") != "SessionStart":
                    continue
                t = ts(r.get("timestamp", ""))
                if SINCE and (t is None or t < SINCE):
                    continue
                if a.get("type") == "async_hook_response":
                    asyncs.append((f, t, a))
                    continue
                tid = a.get("toolUseID")
                if tid == "SessionStart":  # merged hook_additional_context row
                    tid = "__ctx__"
                key = (f, tid)
                events.setdefault(key, []).append((t, a))

    out = []
    P = lambda *x: out.append(" ".join(str(y) for y in x))

    # source per event
    src = {}
    ev_first = {}
    for key, rows in events.items():
        if key[1] == "__ctx__":
            continue
        names = [
            a.get("hookName", "")
            for _, a in rows
            if a.get("hookName", "").startswith("SessionStart:")
        ]
        src[key] = names[0].split(":", 1)[1] if names else "?"
        tss = [t for t, _ in rows if t]
        ev_first[key] = min(tss) if tss else None
    real = [k for k in events if k[1] != "__ctx__"]
    P("files", len(files), "| SessionStart events (toolUseID groups)", len(real))
    P("events by source", dict(collections.Counter(src[k] for k in real)))

    # P1 hook_cancelled
    canc = collections.Counter()
    canc_src = collections.Counter()
    canc_events = set()
    canc_dur = collections.defaultdict(list)
    for k in real:
        for _, a in events[k]:
            if a.get("type") == "hook_cancelled":
                c = short(a.get("command"))
                canc[(c, bool(a.get("timedOut")), a.get("timeoutMs"))] += 1
                canc_src[(c, src[k])] += 1
                canc_events.add(k)
                if a.get("durationMs") is not None:
                    canc_dur[c].append(a["durationMs"])
    P("\n[P1] hook_cancelled records (command, timedOut, timeoutMs): count")
    for (c, to, tm), n in canc.most_common():
        d = canc_dur.get(c, [])
        P(
            f"  {c:45s} timedOut={to} timeoutMs={tm}: {n}  dur p50={pct(d, 50)} max={max(d) if d else None}"
        )
    P("  by (command, source):", dict(canc_src))
    P("  events with >=1 cancelled hook:", len(canc_events), "of", len(real))

    # P5 errors
    errs = collections.Counter()
    err_samples = {}
    for k in real:
        for _, a in events[k]:
            ty = a.get("type", "")
            if ty in (
                "hook_non_blocking_error",
                "hook_error_during_execution",
                "hook_blocking_error",
            ):
                c = short(a.get("command"))
                errs[(ty, c)] += 1
                err_samples.setdefault(
                    (ty, c), (a.get("stderr") or a.get("content") or "")[:200]
                )
    P("\n[P5] error records:", sum(errs.values()))
    for (ty, c), n in errs.most_common():
        P(f"  {ty} {c}: {n}  sample={err_samples[(ty, c)]!r}")

    # dispatcher + per-hook stats
    dd = []
    bound_events = set()
    disp_rec = 0
    cap_hit = 0
    over_bound = 0
    leaked = 0
    ctx_lens = []
    no_disp = collections.Counter()
    board_missing = collections.Counter()
    board_present = collections.Counter()
    sm_lens = []
    harness_cap = collections.Counter()
    per_hook_ctx = collections.defaultdict(list)
    per_hook_dur = collections.defaultdict(list)
    for k in real:
        rows = events[k]
        has_disp = False
        for _, a in rows:
            c = short(a.get("command"))
            if a.get("type") == "hook_success":
                ctx, sm, isj = ctx_of(a.get("stdout"))
                per_hook_ctx[c].append(len(ctx))
                if a.get("durationMs") is not None:
                    per_hook_dur[c].append(a["durationMs"])
                if len(ctx) >= HARNESS_CAP:
                    harness_cap[c] += 1
                if DISPATCH in (a.get("command") or ""):
                    has_disp = True
                    disp_rec += 1
                    d = a.get("durationMs")
                    if d is not None:
                        dd.append(d)
                        if d >= BOUND_MS:
                            over_bound += 1
                            bound_events.add(k)
                    ctx_lens.append(len(ctx))
                    if len(ctx) == CAP:
                        cap_hit += 1
                    if '"systemMessage"' in ctx or '"hookSpecificOutput"' in ctx:
                        leaked += 1
                    sm_lens.append(len(sm))
                    if src[k] in ("startup", "clear", "resume"):
                        if ("CLAUDE MAX" in sm) or (
                            "ACCOUNTS" in sm.upper() and "%" in sm
                        ):
                            board_present[src[k]] += 1
                        else:
                            board_missing[src[k]] += 1
            elif a.get("type") == "hook_cancelled" and DISPATCH in (
                a.get("command") or ""
            ):
                has_disp = True
        if not has_disp:
            no_disp[src[k]] += 1

    P(
        "\n[P2] dispatcher hook_success records:",
        disp_rec,
        "| durationMs >= 9000 (>=1 child killed):",
        over_bound,
    )
    if dd:
        P(
            "  dispatcher durationMs p50/p75/p90/p95/p99/max:",
            [pct(dd, p) for p in (50, 75, 90, 95, 99)],
            max(dd),
        )
    P(
        "[P3] merged context == 9500 (cap hit, tail cut):",
        cap_hit,
        "| ctx len p50/p95/max:",
        pct(ctx_lens, 50),
        pct(ctx_lens, 95),
        max(ctx_lens) if ctx_lens else None,
    )
    P("[P4] any hook context >= 10000:", dict(harness_cap))
    P(
        "[P9] events with NO dispatcher record (silent run, killed pre-record, or not registered):",
        dict(no_disp),
    )
    P("[P10] dispatcher context with raw child JSON leaked:", leaked)
    P(
        "[P11] dispatcher ran (startup/clear/resume) and systemMessage has board:",
        dict(board_present),
        "| lacks board:",
        dict(board_missing),
    )
    P(
        "  systemMessage len p50/max:",
        pct(sm_lens, 50),
        max(sm_lens) if sm_lens else None,
    )
    P(
        "\nper-hook stdout context chars (records that printed) p50/p95/max, dur p50/p95/max:"
    )
    for c in sorted(per_hook_ctx):
        x = per_hook_ctx[c]
        d = per_hook_dur.get(c, [])
        P(
            f"  {c:45s} n={len(x):4d} ctx {pct(x, 50)}/{pct(x, 95)}/{max(x)}  dur {pct(d, 50)}/{pct(d, 95)}/{max(d) if d else None}"
        )

    # P6/P7/P8 async
    P("\n[P6-P8] async_hook_response SessionStart records:", len(asyncs))
    stderr_kinds = collections.Counter()
    nz = collections.Counter()
    tomodel = collections.Counter()
    lags = []
    # lag: async ts minus the latest SessionStart event first-ts in same file that precedes it
    ev_by_file = collections.defaultdict(list)
    for k, t0 in ev_first.items():
        if t0:
            ev_by_file[k[0]].append(t0)
    for f, t, a in asyncs:
        se = (a.get("stderr") or "").strip()
        if se:
            first = se.splitlines()[0]
            tag = first.split("]")[0] + "]" if first.startswith("[") else first[:60]
            stderr_kinds[tag] += 1
        if a.get("exitCode") not in (0, None):
            nz[a.get("exitCode")] += 1
        resp = a.get("response") or {}
        if isinstance(resp, dict):
            hso = resp.get("hookSpecificOutput") or {}
            if resp.get("systemMessage"):
                tomodel["systemMessage"] += 1
            if isinstance(hso, dict) and hso.get("additionalContext"):
                tomodel["additionalContext"] += 1
        if t and ev_by_file.get(f):
            prev = [x for x in ev_by_file[f] if x <= t]
            if prev:
                lags.append(t - max(prev))
    P("  stderr non-empty by first-line tag:")
    for k, n in stderr_kinds.most_common(25):
        P(f"    {n:5d}  {k}")
    P("  exitCode != 0:", dict(nz))
    P(
        "  response routed to MODEL context (systemMessage/additionalContext):",
        dict(tomodel),
    )
    if lags:
        P(
            "  delivery lag s (async record ts - event start) p50/p90/max:",
            round(pct(lags, 50), 1),
            round(pct(lags, 90), 1),
            round(max(lags), 1),
            "n=",
            len(lags),
        )
    union = canc_events | bound_events
    P(
        "\n[UNION] events with a harness cancel OR dispatcher >= bound:",
        len(union),
        "of",
        len(real),
        "| harness-cancel only:",
        len(canc_events - bound_events),
        "| bound only:",
        len(bound_events - canc_events),
        "| both:",
        len(canc_events & bound_events),
    )
    print("\n".join(out))


if __name__ == "__main__":
    main()
