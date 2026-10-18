#!/usr/bin/env python3
"""a1_census.py — read-only run-time census of SessionStart hooks from Claude Code transcripts.

Axis A1 of docs/research/startup-hooks-2026-10-18/. Executes NO hook. Reads only:
  * the transcript list (default /tmp/startup-hooks-census-files.txt), main transcripts only;
  * ~/.claude/autonomy/idl.jsonl (+ newest rotated .gz) — independent "this hook ran" rows written by
    desk-brief-inject.sh (sync, G1), session-index-start.sh and session-start.sh (dispatcher children);
  * ~/.claude/telemetry/net-context.jsonl — independent "ran" row written by net-context-stamp.sh (async);
  * ~/.claude/logs/capacity-alarm.jsonl — ~1/min load_1m / load_per_core samples (the only timestamped
    load series on the machine).

Usage:  python3 -I a1_census.py [--files LIST] [--since ISO] [--json OUT.json]
Prints a plain-text report on stdout. Every number it prints is MEASURED from those inputs.

Event model. All records of one SessionStart firing share attachment.toolUseID (hook_success,
hook_cancelled, hook_system_message); hook_additional_context carries toolUseID "SessionStart" and
is attached to the event whose record precedes it in file order. A record's timestamp is written when
that hook FINISHES, so start ~= timestamp - durationMs (verified: sibling hooks of one event agree to
a few ms, i.e. the harness spawns all sync hooks of all matcher groups at the same instant).
KNOWN BIAS: hook_success (with durationMs) is written only when the hook printed something.
"""

import argparse, gzip, json, os, re, statistics, subprocess, sys
from collections import Counter, defaultdict
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
SYNC_REG = {  # current registration (jq '.hooks.SessionStart' ~/.claude/settings.json), timeout ms
    "~/.claude/hooks/dod-persist.sh": 5000,
    "~/.claude/hooks/desk-brief-inject.sh": 5000,
    "~/.claude/hooks/mailbox-drain.sh session-start": 5000,
    "~/.claude/hooks/session-start-dispatch.sh": 12000,
}
DISPATCH = "~/.claude/hooks/session-start-dispatch.sh"
DOD = "~/.claude/hooks/dod-persist.sh"
MBX = "~/.claude/hooks/mailbox-drain.sh session-start"
MIGRATION_0056 = "2026-10-04T18:04:31Z"  # efb8f3133 committed 13:04:31-05:00


def ts(s):
    if not s:
        return None
    s = s.replace("Z", "+00:00")
    if re.search(r"\.\d+\+", s):
        head, rest = s.split(".", 1)
        frac, tz = rest.split("+", 1)
        s = f"{head}.{(frac + '000000')[:6]}+{tz}"
    return datetime.fromisoformat(s).timestamp()


def iso(t):
    return (
        datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        if t
        else "-"
    )


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = (len(xs) - 1) * p / 100.0
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def dist(xs):
    if not xs:
        return "n=0"
    f = lambda v: f"{v / 1000:.1f}s"
    return (
        f"n={len(xs)} p50={f(pct(xs, 50))} p75={f(pct(xs, 75))} p90={f(pct(xs, 90))} "
        f"p95={f(pct(xs, 95))} p99={f(pct(xs, 99))} max={f(max(xs))}"
    )


def short(cmd):
    c = cmd or "?"
    m = re.match(r"~/\.claude/hooks/(\S+)(.*)", c)
    if m:
        return m.group(1) + m.group(2)
    return "[project] " + c[:50].replace("\n", " ")


def cfgdir(path):
    m = re.match(re.escape(HOME) + r"/(\.claude[^/]*)/", path)
    return m.group(1) if m else "?"


def load_rg(files, pattern):
    """Yield (path, json_record) for lines matching pattern; one rg pass over all files."""
    out = defaultdict(list)
    for i in range(0, len(files), 200):
        chunk = files[i : i + 200]
        p = subprocess.run(
            ["rg", "-N", "-H", "--null", "--no-heading", "-e", pattern, *chunk],
            capture_output=True,
        )
        for raw in p.stdout.split(b"\n"):
            if not raw:
                continue
            path, _, line = raw.partition(b"\0")
            try:
                out[path.decode()].append(json.loads(line))
            except Exception:
                pass
    return out


def first_turn(path, limit=600):
    """First user record ts and first assistant record ts and first instructions attachment ts."""
    u = a = ins = None
    try:
        with open(path, "rb") as fh:
            for n, line in enumerate(fh):
                if n > limit:
                    break
                if (
                    b'"type":"user"' not in line
                    and b'"type":"assistant"' not in line
                    and b'"instructions"' not in line
                ):
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                t = ts(r.get("timestamp"))
                if r.get("type") == "user" and u is None and not r.get("isMeta"):
                    u = t
                elif r.get("type") == "assistant" and a is None:
                    a = t
                elif (
                    r.get("type") == "attachment"
                    and (r.get("attachment") or {}).get("type") == "instructions"
                    and ins is None
                ):
                    ins = t
                if a is not None:
                    break
    except OSError:
        pass
    return u, a, ins


def read_jsonl(path, gz=False):
    op = gzip.open if gz else open
    try:
        with op(path, "rt", errors="replace") as fh:
            for line in fh:
                try:
                    yield json.loads(line)
                except Exception:
                    pass
    except OSError:
        return


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", default="/tmp/startup-hooks-census-files.txt")
    ap.add_argument(
        "--since", default=None, help="ISO; only events starting at/after this"
    )
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    since = ts(a.since) if a.since else None
    files = [l.strip() for l in open(a.files) if l.strip() and "/subagents/" not in l]

    recs = load_rg(files, '"hookName":"SessionStart')

    # ---------- build events ----------
    events = []  # dict per firing
    for path in files:
        rows = recs.get(path, [])
        by_tu = {}
        order = []
        last = None
        for r in rows:
            at = r.get("attachment") or {}
            typ = at.get("type")
            tu = at.get("toolUseID")
            t = ts(r.get("timestamp"))
            if typ == "hook_additional_context":
                ev = last
                if ev is None:
                    continue
                c = at.get("content")
                ev["ctx_chars"] = (
                    sum(len(x) for x in c) if isinstance(c, list) else len(c or "")
                )
                ev["ctx_t"] = t
                continue
            if typ == "async_hook_response":
                ev = last
                if ev is None:
                    continue
                ev["async"].append(
                    {
                        "t": t,
                        "stderr": at.get("stderr") or "",
                        "stdout": at.get("stdout") or "",
                        "exit": at.get("exitCode"),
                    }
                )
                continue
            if tu not in by_tu:
                ev = {
                    "path": path,
                    "cfg": cfgdir(path),
                    "sid": os.path.basename(path)[:-6],
                    "source": (at.get("hookName") or "SessionStart:?").split(":", 1)[
                        -1
                    ],
                    "hooks": {},
                    "sysmsg": 0,
                    "ctx_chars": 0,
                    "ctx_t": None,
                    "async": [],
                    "version": r.get("version"),
                    "entry": r.get("entrypoint"),
                    "cwd": r.get("cwd"),
                }
                by_tu[tu] = ev
                order.append(ev)
            ev = by_tu[tu]
            last = ev
            if typ == "hook_system_message":
                ev["sysmsg"] += 1
                ev["sysmsg_t"] = t
                continue
            if typ in (
                "hook_success",
                "hook_cancelled",
                "hook_error",
                "hook_blocking_error",
            ):
                cmd = at.get("command")
                d = at.get("durationMs")
                so = at.get("stdout") or ""
                ctxlen = smlen = 0
                if so.strip().startswith("{"):
                    try:
                        j = json.loads(so)
                        ctxlen = len(
                            (
                                (j.get("hookSpecificOutput") or {}).get(
                                    "additionalContext"
                                )
                            )
                            or ""
                        )
                        smlen = len(j.get("systemMessage") or "")
                    except Exception:
                        ctxlen = len(so)
                elif so.strip():
                    ctxlen = len(so)
                ev["hooks"][cmd] = {
                    "t": t,
                    "d": d,
                    "status": typ,
                    "timedOut": at.get("timedOut"),
                    "timeoutMs": at.get("timeoutMs"),
                    "ctx": ctxlen,
                    "sm": smlen,
                    "stderr": len(at.get("stderr") or ""),
                }
                if cmd == DISPATCH and so.strip().startswith("{"):
                    try:
                        j = json.loads(so)
                        ev["disp_ctx"] = (j.get("hookSpecificOutput") or {}).get(
                            "additionalContext"
                        ) or ""
                        ev["disp_sm"] = j.get("systemMessage") or ""
                    except Exception:
                        pass
        for i, ev in enumerate(order):
            starts = [
                h["t"] - h["d"] / 1000
                for h in ev["hooks"].values()
                if h["t"] and h["d"] is not None
            ]
            ends = [h["t"] for h in ev["hooks"].values() if h["t"]]
            ev["start"] = min(starts) if starts else None
            ev["start_spread_ms"] = (
                (max(starts) - min(starts)) * 1000 if len(starts) > 1 else None
            )
            ev["end"] = (
                max(ends + ([ev["ctx_t"]] if ev["ctx_t"] else []))
                if ends
                else ev["ctx_t"]
            )
            ev["span_ms"] = (
                (ev["end"] - ev["start"]) * 1000 if ev["start"] and ev["end"] else None
            )
            ev["first_in_file"] = i == 0
        events.extend(order)

    if since:
        events = [e for e in events if e["start"] and e["start"] >= since]
    post = [e for e in events if e["start"] and e["start"] >= ts(MIGRATION_0056)]

    out = []
    P = out.append
    P(
        f"# A1 census — {len(files)} main transcripts, {sum(1 for f in files if recs.get(f))} with >=1 SessionStart record"
    )
    P(
        f"events (SessionStart firings): {len(events)}; post-0056 (start >= {MIGRATION_0056}): {len(post)}"
    )
    P(
        f"event window: {iso(min(e['start'] for e in events if e['start']))} .. {iso(max(e['start'] for e in events if e['start']))}"
    )
    P(
        "by source: "
        + ", ".join(
            f"{k}={v}" for k, v in Counter(e["source"] for e in events).most_common()
        )
    )
    P(
        "by config dir: "
        + ", ".join(
            f"{k}={v}" for k, v in Counter(e["cfg"] for e in events).most_common()
        )
    )
    P(
        "by entrypoint: "
        + ", ".join(
            f"{k}={v}" for k, v in Counter(e["entry"] for e in events).most_common()
        )
    )
    P(
        "by version: "
        + ", ".join(
            f"{k}={v}" for k, v in Counter(e["version"] for e in events).most_common(8)
        )
    )

    # ---------- per-command durations ----------
    P(
        "\n## 1. Per-command durationMs (hook_success + hook_cancelled; cancelled durations included)"
    )
    per = defaultdict(list)
    per_src = defaultdict(lambda: defaultdict(list))
    per_cfg = defaultdict(lambda: defaultdict(list))
    cancels = Counter()
    seen = Counter()
    over = defaultdict(list)
    for e in events:
        for cmd, h in e["hooks"].items():
            if h["d"] is None:
                continue
            per[cmd].append(h["d"])
            per_src[cmd][e["source"]].append(h["d"])
            per_cfg[cmd][e["cfg"]].append(h["d"])
            seen[cmd] += 1
            if h["status"] == "hook_cancelled":
                cancels[cmd] += 1
                if h["timeoutMs"]:
                    over[cmd].append(h["d"] - h["timeoutMs"])
    for cmd in sorted(per, key=lambda c: -len(per[c])):
        P(f"- {short(cmd)}: {dist(per[cmd])}; cancelled(timedOut)={cancels[cmd]}")
        if over[cmd]:
            P(f"    kill overshoot past timeoutMs: {dist(over[cmd])}")
        if len(per[cmd]) >= 20:
            for s, xs in sorted(per_src[cmd].items(), key=lambda kv: -len(kv[1])):
                P(f"    source={s}: {dist(xs)}")
            for c, xs in sorted(per_cfg[cmd].items(), key=lambda kv: -len(kv[1])):
                P(f"    cfg={c}: {dist(xs)}")

    # ---------- dispatcher thresholds ----------
    dd = per.get(DISPATCH, [])
    if dd:
        P(
            f"\ndispatcher runs with duration > 9.0s (>= one child hit CC_SSD_BOUND_S and was killed, output dropped): "
            f"{sum(1 for x in dd if x > 9000)}/{len(dd)} ({100 * sum(1 for x in dd if x > 9000) / len(dd):.0f}%)"
        )
        P(
            f"dispatcher runs > 12.0s registration (whole output lost): {sum(1 for x in dd if x > 12000)}"
        )
        P(
            f"dispatcher runs in (9.0s, 9.6s] (bound fired, then merge+exit): {sum(1 for x in dd if 9000 < x <= 9600)}"
        )

    # ---------- presence / silent vs never-ran ----------
    P(
        "\n## 2. Presence of sync-hook records per post-0056 STARTUP event (bias: success recorded only if it printed)"
    )
    idl = defaultdict(lambda: defaultdict(list))  # sid -> hook -> [ts]
    idl_paths = [os.path.join(HOME, ".claude/autonomy/idl.jsonl")]
    gzs = sorted(
        p
        for p in os.listdir(os.path.join(HOME, ".claude/autonomy"))
        if re.match(
            r"idl\.jsonl\.\d{8}T\d{6}Z\.gz$", p
        )  # NOT the idl.jsonl.chain.* series
    )
    rot = []
    for g in gzs[-2:]:  # two newest rotations ~= the 5 days before the live file
        rot.extend(read_jsonl(os.path.join(HOME, ".claude/autonomy", g), gz=True))
    for r in rot + list(read_jsonl(idl_paths[0])):
        h = r.get("hook")
        if h in (
            "desk-brief-inject",
            "session-index-start",
            "session-start:memory-snapshot",
        ):
            idl[r.get("sid")][h].append(ts(r.get("ts")))
    netc = defaultdict(list)
    for r in read_jsonl(os.path.join(HOME, ".claude/telemetry/net-context.jsonl")):
        netc[r.get("session")].append(ts(r.get("ts")))
    idl_min = min(
        (t for s in idl.values() for v in s.values() for t in v), default=None
    )
    P(
        f"(independent ran-evidence: idl.jsonl rows from {iso(idl_min)}; net-context.jsonl rows={sum(len(v) for v in netc.values())})"
    )

    def near(lst, t, lo=-5, hi=90):
        return [x for x in lst if t is not None and x is not None and lo <= x - t <= hi]

    st = [e for e in post if e["source"] == "startup" and e["start"]]
    st_idl = [e for e in st if idl_min and e["start"] >= idl_min + 60]
    P(
        f"post-0056 startup events: {len(st)}; of which inside idl coverage: {len(st_idl)}"
    )
    pres = Counter()
    for e in st:
        for cmd in (DISPATCH, DOD, MBX):
            h = e["hooks"].get(cmd)
            pres[
                (
                    cmd,
                    "success"
                    if h and h["status"] == "hook_success"
                    else ("cancelled" if h else "absent"),
                )
            ] += 1
    for cmd in (DISPATCH, DOD, MBX):
        P(
            f"- {short(cmd)}: success={pres[(cmd, 'success')]} cancelled={pres[(cmd, 'cancelled')]} absent(no record)={pres[(cmd, 'absent')]}"
        )
    # desk-brief-inject never prints on this machine (role file absent) -> ran-evidence only via idl
    dbi = Counter()
    dbi_lat = []
    six = Counter()
    six_lat = []
    for e in st_idl:
        d = near(idl[e["sid"]]["desk-brief-inject"], e["start"])
        dbi["ran" if d else "no-idl-row"] += 1
        if d:
            dbi_lat.append((min(d) - e["start"]) * 1000)
        s = near(idl[e["sid"]]["session-index-start"], e["start"])
        disp = e["hooks"].get(DISPATCH)
        key = (
            "disp-" + (disp["status"].replace("hook_", "") if disp else "absent")
        ) + ("/six-row" if s else "/no-six-row")
        six[key] += 1
        if s:
            six_lat.append((min(s) - e["start"]) * 1000)
    P(
        f"- desk-brief-inject.sh (sync, prints nothing unless desk role): idl row present={dbi['ran']} absent={dbi['no-idl-row']}; "
        f"completion offset from event start (idl ts has 1s resolution, so +-1s): {dist(dbi_lat)}"
    )
    P(
        "- dispatcher outcome x session-index-start idl row (a dispatcher CHILD; row = child finished):"
    )
    for k, v in sorted(six.items()):
        P(f"    {k}: {v}")
    P(f"  session-index-start completion offset from event start: {dist(six_lat)}")
    # sessions with zero SessionStart record
    none = [f for f in files if not recs.get(f)]
    P(f"\ntranscripts with NO SessionStart record at all: {len(none)}")
    nr = Counter()
    for f in none:
        sid = os.path.basename(f)[:-6]
        ran = bool(idl.get(sid)) or bool(netc.get(sid))
        nr[
            "has ran-evidence (silent?)"
            if ran
            else "no ran-evidence (hooks never ran / disabled)"
        ] += 1
    for k, v in nr.items():
        P(f"    {k}: {v}")
    P(
        "    cwd prefixes: "
        + ", ".join(
            f"{k}={v}"
            for k, v in Counter(
                re.sub(
                    r"-[0-9a-z]{6,}.*", "-*", f.split("/projects/")[1].split("/")[0]
                )[:48]
                for f in none
            ).most_common(5)
        )
    )

    # ---------- critical path ----------
    P("\n## 3. Critical path (post-0056 events with a start estimate)")
    spread = [e["start_spread_ms"] for e in post if e["start_spread_ms"] is not None]
    P(
        f"start-time spread across timed sync hooks of one event (0 => all spawned together): {dist(spread)}"
    )
    spans = [e["span_ms"] for e in post if e["span_ms"]]
    P(
        f"event span (earliest start -> last record incl. additional_context): {dist(spans)}"
    )
    lastc = Counter()
    for e in post:
        hs = [(h["t"], c) for c, h in e["hooks"].items() if h["t"]]
        if hs:
            lastc[short(max(hs)[1])] += 1
    P(
        "hook finishing LAST (critical path) per event: "
        + ", ".join(f"{k}={v}" for k, v in lastc.most_common())
    )
    gap = [
        (e["ctx_t"] - max(h["t"] for h in e["hooks"].values() if h["t"])) * 1000
        for e in post
        if e["ctx_t"] and any(h["t"] for h in e["hooks"].values())
    ]
    P(
        f"additional_context written after last hook record by: {dist([g for g in gap if g >= 0])} (negatives={sum(1 for g in gap if g < 0)})"
    )
    # first-turn wait: prompt supplied before hooks finished
    waits = []
    preprompt = 0
    instr_after = []
    asst_before_end = 0
    firsts = [
        e for e in post if e["first_in_file"] and e["source"] == "startup" and e["end"]
    ]
    for e in firsts:
        u, asst, ins = first_turn(e["path"])
        if ins:
            instr_after.append((ins - e["end"]) * 1000)
        if u and u < e["end"]:
            preprompt += 1
            waits.append((e["end"] - max(u, e["start"])) * 1000)
            if asst and asst < e["end"]:
                asst_before_end += 1
    P(
        f"startup events whose first user prompt was already queued before hooks finished: {preprompt}/{len(firsts)}"
    )
    P(
        f"  hook-imposed wait on that queued prompt (end - max(prompt, start)): {dist(waits)}"
    )
    P(
        f"  first assistant record BEFORE hooks finished (would disprove blocking): {asst_before_end}"
    )
    P(
        f"instructions attachment written after hooks end by: {dist([x for x in instr_after if x >= 0])} (negatives={sum(1 for x in instr_after if x < 0)})"
    )

    # ---------- timeouts: bursts and load ----------
    P("\n## 4. Timeouts/cancels in time; load cross-check")
    canc = sorted(
        (h["t"], short(c), e["sid"][:8], e["cfg"])
        for e in events
        for c, h in e["hooks"].items()
        if h["status"] == "hook_cancelled"
    )
    P(f"cancelled records: {len(canc)} across {len({x[2] for x in canc})} sessions")
    # cluster: consecutive cancels within 300 s
    clusters = []
    for c in canc:
        if clusters and c[0] - clusters[-1][-1][0] <= 300:
            clusters[-1].append(c)
        else:
            clusters.append([c])
    P(
        f"clusters (gap <= 300s): {len(clusters)}; sizes: {sorted((len(c) for c in clusters), reverse=True)}"
    )
    for cl in sorted(clusters, key=len, reverse=True)[:8]:
        P(
            f"    {iso(cl[0][0])}..{iso(cl[-1][0])} n={len(cl)} sessions={len({x[2] for x in cl})} hooks={dict(Counter(x[1] for x in cl))}"
        )
    # load join
    load = []
    for r in read_jsonl(os.path.join(HOME, ".claude/logs/capacity-alarm.jsonl")):
        t = ts(r.get("ts"))
        if t and r.get("load_1m") is not None:
            load.append(
                (t, r.get("load_1m"), r.get("load_per_core"), r.get("sessions"))
            )
    load.sort()
    import bisect

    lt = [x[0] for x in load]

    def load_at(t):
        i = bisect.bisect_left(lt, t)
        best = None
        for j in (i - 1, i):
            if 0 <= j < len(load) and abs(load[j][0] - t) <= 180:
                if best is None or abs(load[j][0] - t) < abs(best[0] - t):
                    best = load[j]
        return best

    P(
        f"load samples (capacity-alarm.jsonl): {len(load)}, {iso(load[0][0]) if load else '-'} .. {iso(load[-1][0]) if load else '-'}"
    )
    bins = [(0, 2), (2, 5), (5, 10), (10, 20), (20, 35), (35, 1e9)]
    rows = defaultdict(lambda: {"d": [], "to": 0, "n": 0, "any_cancel": 0, "gt9": 0})
    unj = 0
    for e in post:
        if not e["start"]:
            continue
        L = load_at(e["start"])
        if not L:
            unj += 1
            continue
        lpc = L[2] if L[2] is not None else L[1] / 10
        b = next(b for b in bins if b[0] <= lpc < b[1])
        r = rows[b]
        r["n"] += 1
        h = e["hooks"].get(DISPATCH)
        if h and h["d"] is not None:
            r["d"].append(h["d"])
            if h["d"] > 9000:
                r["gt9"] += 1
            if h["status"] == "hook_cancelled":
                r["to"] += 1
        if any(x["status"] == "hook_cancelled" for x in e["hooks"].values()):
            r["any_cancel"] += 1
    P(
        f"post-0056 events joined to a load sample within 180s: {sum(r['n'] for r in rows.values())} (unjoined {unj})"
    )
    P(
        "load/core bin | events | events w/ any cancel | dispatcher >9s | dispatcher timeout | dispatcher duration"
    )
    for b in bins:
        r = rows[b]
        if r["n"]:
            P(
                f"  [{b[0]},{b[1] if b[1] < 1e8 else 'inf'}) | {r['n']} | {r['any_cancel']} ({100 * r['any_cancel'] / r['n']:.0f}%) | {r['gt9']} | {r['to']} | {dist(r['d'])}"
            )
    # hourly
    hr = defaultdict(lambda: [0, 0])
    for e in post:
        if e["start"]:
            k = iso(e["start"])[:13]
            hr[k][0] += 1
            if any(x["status"] == "hook_cancelled" for x in e["hooks"].values()):
                hr[k][1] += 1
    hot = sorted(((v[1], k, v[0]) for k, v in hr.items() if v[1]), reverse=True)[:10]
    P(
        "hours with most events-with-cancel (hour: cancel-events/all-events): "
        + ", ".join(f"{k}Z:{c}/{n}" for c, k, n in hot)
    )

    # ---------- async hooks ----------
    P("\n## 5. async_hook_response records (async SessionStart hooks)")
    asy = [(e, x) for e in events for x in e["async"]]
    P(
        f"records: {len(asy)} over {len(events)} events; none carries command/durationMs/hookName-per-hook (keys: exitCode hookEvent hookName processId response stderr stdout type)"
    )
    sig = Counter()
    lag = defaultdict(list)
    for e, x in asy:
        s = x["stderr"]
        k = (
            "session-register: bash 'Killed: 9' job notice"
            if "session-register.sh" in s and "Killed" in s
            else "pre-session-validate: version WARNING"
            if "pre-session-validate" in s
            else ("stdout-only" if not s and x["stdout"] else "other: " + s[:60])
        )
        sig[(k, x["exit"])] += 1
        if e["start"] and x["t"]:
            lag[k].append((x["t"] - e["start"]) * 1000)
    for (k, ex), v in sig.most_common():
        P(f"- {k} exit={ex}: {v}; written after event start by {dist(lag[k])}")
    # async ran-evidence for net-context-stamp
    nc = Counter()
    for e in st:
        nc[
            "row" if near(netc.get(e["sid"], []), e["start"], -5, 120) else "no-row"
        ] += 1
    P(
        f"net-context-stamp.sh (async) ran-evidence per post-0056 startup event: {dict(nc)}"
    )

    # ---------- tokens ----------
    P("\n## 6. Context size (model-billed) per event")
    cc = [e["ctx_chars"] for e in post if e["ctx_chars"]]
    if cc:
        P(
            f"additionalContext chars per event: n={len(cc)} mean={statistics.mean(cc):.0f} p50={pct(cc, 50):.0f} p90={pct(cc, 90):.0f} max={max(cc)}; "
            f"events with none: {sum(1 for e in post if not e['ctx_chars'])}"
        )
    per_ctx = defaultdict(list)
    per_sm = defaultdict(list)
    for e in post:
        for c, h in e["hooks"].items():
            if h["status"] == "hook_success":
                per_ctx[short(c)].append(h["ctx"])
                per_sm[short(c)].append(h["sm"])
    for c in sorted(per_ctx, key=lambda k: -sum(per_ctx[k])):
        xs = per_ctx[c]
        P(
            f"- {c}: ctx chars mean={statistics.mean(xs):.0f} p90={pct(xs, 90):.0f} max={max(xs)} (n={len(xs)}); systemMessage chars mean={statistics.mean(per_sm[c]):.0f}"
        )
    P(
        f"events with a hook_system_message: {sum(1 for e in post if e['sysmsg'])}/{len(post)}; "
        f"post-0056 startup events WITHOUT one (board not rendered): {sum(1 for e in st if not e['sysmsg'])}"
    )

    # ---------- 7. which dispatcher child is dropped? (signature lines in the merged output) ----------
    P(
        "\n## 7. Dispatcher children: signature presence in the merged output, by dispatcher duration"
    )
    sigs = {
        "session-start.sh (MCP: line)": lambda c, s: "MCP:" in c,
        "setup-plan-symlinks.sh (Plans:)": lambda c, s: "Plans:" in c,
        "setup-task-symlinks.sh (Tasks:)": lambda c, s: "Tasks:" in c,
        "frontier-status.sh (Frontier:)": lambda c, s: "Frontier:" in c,
        "session-index-start.sh (Session index:)": lambda c, s: "Session index" in c,
        "accounts-board.sh (board in systemMessage)": lambda c, s: (
            "CLAUDE MAX" in s or "accounts-keepwarm" in s or "account" in s.lower()
        ),
    }
    dbuck = [(0, 8000), (8000, 9000), (9000, 9600), (9600, 12000), (12000, 1e9)]
    tab = defaultdict(lambda: Counter())
    nb = Counter()
    for e in post:
        h = e["hooks"].get(DISPATCH)
        if not h or h["status"] != "hook_success" or "disp_ctx" not in e:
            continue
        b = next(b for b in dbuck if b[0] <= h["d"] < b[1])
        nb[b] += 1
        for name, f in sigs.items():
            if f(e["disp_ctx"], e["disp_sm"]):
                tab[name][b] += 1
    hdr = " | ".join(
        f"[{b[0] / 1000:.1f},{b[1] / 1000 if b[1] < 1e8 else 'inf'})s n={nb[b]}"
        for b in dbuck
    )
    P(f"child signature present (count / successful dispatcher runs in bucket): {hdr}")
    for name in sigs:
        P(
            f"- {name}: "
            + " | ".join(
                f"{tab[name][b]}/{nb[b]}"
                + (f" ({100 * tab[name][b] / nb[b]:.0f}%)" if nb[b] else "")
                for b in dbuck
            )
        )
    # >12 s successes (harness timer itself late)
    late = [
        (iso(e["start"]), e["sid"][:8], e["hooks"][DISPATCH]["d"])
        for e in post
        if DISPATCH in e["hooks"]
        and e["hooks"][DISPATCH]["status"] == "hook_success"
        and (e["hooks"][DISPATCH]["d"] or 0) > 12000
    ]
    P(
        f"dispatcher SUCCESS records with durationMs > 12000 (timeout registered, not enforced on time): {late}"
    )
    late5 = Counter(
        short(c)
        for e in post
        for c, h in e["hooks"].items()
        if h["status"] == "hook_success"
        and h["d"]
        and c in SYNC_REG
        and h["d"] > SYNC_REG[c]
    )
    P(
        f"sync SUCCESS records whose durationMs exceeds their registered timeout, by hook: {dict(late5)}"
    )

    # ---------- 8. config dir controlled for load ----------
    P(
        "\n## 8. Dispatcher duration by config dir WITHIN load/core bins (confound check)"
    )
    cl = defaultdict(list)
    for e in post:
        h = e["hooks"].get(DISPATCH)
        L = load_at(e["start"]) if e["start"] else None
        if not h or h["d"] is None or not L:
            continue
        lpc = L[2] if L[2] is not None else L[1] / 10
        b = "lpc<5" if lpc < 5 else ("5<=lpc<20" if lpc < 20 else "lpc>=20")
        cl[(e["cfg"], b)].append(h["d"])
    for k in sorted(cl):
        P(f"- {k[0]} {k[1]}: {dist(cl[k])}")
    # dod-persist absence by cwd that DID produce dod output elsewhere
    dod_cwds = {
        e["cwd"]
        for e in post
        if DOD in e["hooks"] and e["hooks"][DOD]["status"] == "hook_success"
    }
    ab = Counter()
    for e in st:
        if DOD not in e["hooks"]:
            ab[
                "absent, cwd produced dod output in another event"
                if e["cwd"] in dod_cwds
                else "absent, cwd never produced dod output"
            ] += 1
    P(f"dod-persist absence split: {dict(ab)}")
    mb_cwds = None  # mailbox-drain output is per-session mail, not per-cwd: no comparable split
    # net-context-stamp completion offset (async)
    off = []
    for e in st:
        n = near(netc.get(e["sid"], []), e["start"], -5, 600)
        if n:
            off.append((min(n) - e["start"]) * 1000)
    P(
        f"net-context-stamp.sh (async) row ts minus event start (1s resolution): {dist(off)}"
    )

    # ---------- 9. startup storms: co-starting sessions ----------
    P(
        "\n## 9. Startup storms: other SessionStart firings (all config dirs) starting within +-30 s"
    )
    starts = sorted(e["start"] for e in post if e["start"])
    import bisect as _b

    cs = defaultdict(lambda: {"n": 0, "canc": 0, "d": []})
    for e in post:
        if not e["start"]:
            continue
        k = (
            _b.bisect_right(starts, e["start"] + 30)
            - _b.bisect_left(starts, e["start"] - 30)
            - 1
        )
        b = "0" if k == 0 else ("1-2" if k <= 2 else ("3-5" if k <= 5 else ">=6"))
        cs[b]["n"] += 1
        if any(x["status"] == "hook_cancelled" for x in e["hooks"].values()):
            cs[b]["canc"] += 1
        h = e["hooks"].get(DISPATCH)
        if h and h["d"] is not None:
            cs[b]["d"].append(h["d"])
    for b in ("0", "1-2", "3-5", ">=6"):
        r = cs[b]
        if r["n"]:
            P(
                f"- co-starters {b}: events={r['n']} with-cancel={r['canc']} ({100 * r['canc'] / r['n']:.0f}%) dispatcher {dist(r['d'])}"
            )
    P(
        "NOTE: the corpus holds only main transcripts modified in the window; sessions on other "
        "machines/accounts outside the list are not counted, so co-starter counts are a LOWER bound."
    )

    print("\n".join(out))
    if a.json:
        slim = [{k: v for k, v in e.items() if k not in ("async",)} for e in events]
        with open(a.json, "w") as fh:
            json.dump(slim, fh)


if __name__ == "__main__":
    main()
