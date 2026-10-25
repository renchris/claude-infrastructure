#!/usr/bin/env python3
"""build_cases.py — D3 keepalive eval cases from production transcripts, all four projects roots.

One case per main-session idle gap: the request that ended a turn, the moment its Stop landed, and
what happened next (the next turn's opener, an exit, or the window's end). This is the reviewer
pipeline that produced the reference cases (G2.json: rv/rscan.py -> rsim.py -> rjobs.py, imported
under ~/.claude/hillclimb/_imports/lean-idle-rv), folded into one streaming pass per transcript,
with three changes, each because the original only had to run once:
  * the window is a parameter (default: the 28 d ending now), not two epochs in the source;
  * a turn opener is classified as it is read, so no 700-char opener text is held in memory;
  * each case carries its background-job intervals (`jobs`), so busy/watcher can be evaluated at
    any wake time a candidate tries; busy2/watch2 at stop+3300 are kept for the reference engine.
`alive` (a censored terminal gap whose session is still running) was a hand-made pid snapshot;
here it is "transcript written within the last 10 min of the build", stated rather than hidden.

Rules kept from the reviewer pipeline, because the reproduction depends on them:
  * a message id belongs to its EARLIEST file (by mtime) — account transplants copy whole trees;
  * a transcript counts only if any record has entrypoint=cli (interactive main sessions);
  * a gap is a rebuild when the next request's context is ≥ 60% of the previous one and its cache
    write is ≥ half the previous context; `saved` is that write minus the context's own growth;
  * background jobs end at their task-notification (by tool-use id or task id) or a TaskStop/
    KillShell naming them; a launch whose tool_result is an error or a denial is dropped; an
    unknown end is "done 1 h after launch" (busy2) or "alive to the session's end" (busy2_ub).

usage: python3 -I build_cases.py [--days 28] [--end EPOCH] [--start EPOCH] --out cases.jsonl
Stdout: one JSON summary line. Stdlib only, Python 3.9-safe.
"""

import argparse
import bisect
import collections
import json
import os
import re
import sys
import time
from datetime import datetime

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - 3.8
    ZoneInfo = None

HOME = os.path.expanduser("~")
ROOTS = (
    ("next", ".claude-next"),
    ("next2", ".claude-secondary"),
    ("next3", ".claude-tertiary"),
    ("next4", ".claude-quaternary"),
)
WAKE, SETTLE, TTL = 3300.0, 20.0, 3600.0
ALIVE_S = 600
TUID = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")
TID = re.compile(r"<task-id>([^<]+)</task-id>")
STAT = re.compile(r"<status>([a-z_]+)</status>")
IDRX = re.compile(
    r"(?:with ID|Task ID|task_id|agentId|agent ID)[:=]?\s*`?\"?([A-Za-z0-9_-]{5,40})"
)
ENDED = re.compile(
    r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] Session ended sid=([0-9a-f-]+) reason=(\S+)"
)


def roots():
    """(acct, projects dir) for the four accounts; CC_LEVER_EVAL_ROOTS="acct=dir,..." overrides."""
    env = os.environ.get("CC_LEVER_EVAL_ROOTS")
    if env:
        return [tuple(x.split("=", 1)) for x in env.split(",") if "=" in x]
    return [(a, os.path.join(HOME, d, "projects")) for a, d in ROOTS]


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


def content_text(c):
    """→ (is_tool_result, text)"""
    if isinstance(c, str):
        return False, c
    if isinstance(c, list):
        out = []
        for b in c:
            if isinstance(b, dict):
                if b.get("type") == "tool_result":
                    return True, ""
                if b.get("type") == "text":
                    out.append(b.get("text") or "")
        return False, " ".join(out)
    return False, ""


def job_kind(name, bi):
    bg = bool(bi.get("run_in_background"))
    if name == "Bash" and bg:
        return "watch" if "cc-await-ping" in str(bi.get("command", "")) else "bash"
    if name == "Monitor":
        return "watch"
    if name in ("Agent", "Task") and bg:
        return "agent"
    if name == "Workflow":
        return "workflow"
    return None


def scan_file(path, lo, hi):
    """One pass over a transcript. → dict or None (no cli entrypoint)."""
    reqs, opens, other, jobs, res, stops, nt_tu, nt_tid = {}, [], [], {}, {}, {}, {}, {}
    cli = False
    with open(path, "rb") as fh:
        for raw in fh:
            try:
                r = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(r, dict) or r.get("isSidechain"):
                continue
            t = ep(r.get("timestamp")) if isinstance(r.get("timestamp"), str) else None
            if t is None:
                continue
            if r.get("entrypoint") == "cli":
                cli = True
            typ = r.get("type") or "?"
            msg = r.get("message") if isinstance(r.get("message"), dict) else {}
            if typ in ("user", "queue-operation") and b"<task-notification>" in raw:
                s = raw.decode("utf-8", "ignore")
                for x in TUID.findall(s):
                    nt_tu[x] = min(t, nt_tu.get(x, t))
                for x in TID.findall(s):
                    nt_tid[x] = min(t, nt_tid.get(x, t))
            content = msg.get("content")
            if typ == "assistant":
                u = msg.get("usage")
                if isinstance(u, dict) and msg.get("model") != "<synthetic>":
                    for b in content if isinstance(content, list) else []:
                        if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                            continue
                        nm = b.get("name")
                        bi = b.get("input") if isinstance(b.get("input"), dict) else {}
                        if nm in ("TaskStop", "KillShell", "KillBash"):
                            k = bi.get("task_id") or bi.get("shell_id") or bi.get("id")
                            if k:
                                stops[str(k)] = min(t, stops.get(str(k), t))
                            continue
                        kd = job_kind(nm, bi)
                        if kd and b.get("id") and b["id"] not in jobs:
                            jobs[b["id"]] = (t, kd)
                    rid = r.get("requestId") or msg.get("id") or r.get("uuid")
                    o = u.get("output_tokens") or 0
                    if rid in reqs:
                        x = reqs[rid]
                        x[4] = max(x[4], o)
                        x[5] = t
                    else:
                        ctx = (
                            (u.get("input_tokens") or 0)
                            + (u.get("cache_creation_input_tokens") or 0)
                            + (u.get("cache_read_input_tokens") or 0)
                        )
                        reqs[rid] = [
                            t,
                            ctx,
                            u.get("cache_creation_input_tokens") or 0,
                            rid,
                            o,
                            t,
                        ]
                    continue
                other.append((t, "assistant_nousage"))
                continue
            if typ == "user":
                if isinstance(content, list):
                    for b in content:
                        if (
                            isinstance(b, dict)
                            and b.get("type") == "tool_result"
                            and b.get("tool_use_id")
                        ):
                            cc = b.get("content")
                            cs = cc if isinstance(cc, str) else json.dumps(cc)
                            m = IDRX.search(cs)
                            bad = (
                                bool(b.get("is_error"))
                                or "Permission for this action was denied" in cs[:300]
                                or "<tool_use_error>" in cs[:200]
                                or "hook error" in cs[:200]
                            )
                            res[b["tool_use_id"]] = (m.group(1) if m else None, bad)
                tr, txt = content_text(content)
                if tr:
                    other.append((t, "tool_result"))
                elif r.get("isMeta"):
                    other.append((t, "user_meta"))
                else:
                    opens.append((t, txt[:200]))
                continue
            if typ == "system":
                lab = "sys:" + str(r.get("subtype") or "?")
            elif typ == "attachment":
                a = r.get("attachment") if isinstance(r.get("attachment"), dict) else {}
                lab = "att:" + str(a.get("type") or "?")
            else:
                lab = "top:" + typ
            other.append((t, lab))
    if not cli:
        return None
    # job intervals (rjobs.py rules)
    J = []
    for tu, (js, kd) in jobs.items():
        tid, bad = res.get(tu, (None, False))
        if bad:
            continue
        ends = []
        if tu in nt_tu:
            ends.append(nt_tu[tu])
        if tid and tid in nt_tid:
            ends.append(nt_tid[tid])
        if tid and tid in stops:
            ends.append(stops[tid])
        J.append((js, min(ends) if ends else None, kd))
    return dict(
        reqs=[x for x in reqs.values() if lo <= x[0] <= hi + 3600],
        opens=[x for x in opens if lo <= x[0] <= hi + 3600],
        other=[x for x in other if lo <= x[0] <= hi + 3600],
        jobs=J,
        jobkinds={tu: kd for tu, (_js, kd) in jobs.items()},
    )


def session_ends(path):
    ends = collections.defaultdict(list)
    tz = ZoneInfo("America/Chicago") if ZoneInfo else None
    try:
        fh = open(path, errors="ignore")
    except OSError:
        return ends
    with fh:
        for line in fh:
            m = ENDED.match(line)
            if m:
                d = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
                ends[m.group(2)].append((d.replace(tzinfo=tz) if tz else d).timestamp())
    return ends


def okind(txt, jobs_by_tu):
    if txt.startswith("<task-notification>"):
        if "peer mail" in txt[:90]:
            return "mail"
        if "Goal check-in" in txt[:120]:
            return "goal"
        m = TUID.search(txt)
        if m and m.group(1) in jobs_by_tu:
            sm = STAT.search(txt)
            return "job:" + jobs_by_tu[m.group(1)] + ":" + (sm.group(1) if sm else "?")
        if "Monitor event" in txt[:120]:
            return "job:watch"
        return "notif"
    if txt.startswith("<command-") or txt.startswith("<local-command"):
        return "cmd"
    if txt.startswith("Stop hook feedback"):
        return "stopfb"
    return "prompt"


def running(J, t, kinds, last, ub):
    return any(
        kd in kinds
        and js <= t < (je if je is not None else (last if ub else js + 3600))
        for js, je, kd in J
    )


def gaps_of(acct, fsid, f, L, S, E, ends, alive, mt):
    """rsim.py gap construction over one transcript's owned requests L (sorted)."""
    out = []
    n = len(L)
    Ot = sorted(o[0] for o in f["opens"])
    O_ = sorted(f["opens"])
    OT = sorted(f["other"])
    allw = sorted(Ot + [o[0] for o in OT])
    stops = [o[0] for o in OT if o[1] in ("sys:turn_duration", "sys:stop_hook_summary")]
    away = [o[0] for o in OT if o[1] == "sys:away_summary"]
    J = f["jobs"]
    jobs_by_tu = f["jobkinds"]
    last_t = L[-1][5]
    later = [0] * n
    c = 0
    for i in range(n - 1, -1, -1):
        later[i] = c
        c += 1
        if i > 0 and L[i][1] < 0.6 * L[i - 1][1]:
            c = 0

    def stop_after(i, end):
        j = bisect.bisect_left(stops, L[i][5])
        return (
            stops[j]
            if j < len(stops) and stops[j] < end and stops[j] < L[i][5] + 600
            else L[i][5] + 2
        )

    open_idx = []
    for i in range(n - 1):
        j = bisect.bisect_right(Ot, L[i][5])
        if j < len(Ot) and Ot[j] <= L[i + 1][0]:
            open_idx.append((i, j))
    real = [(i, j, okind(O_[j][1], jobs_by_tu)) for i, j in open_idx]
    real = [x for x in real if x[2] != "stopfb"]
    prev_kind = {}
    for q, (i, j, kind) in enumerate(real):
        i2 = real[q + 1][0] if q + 1 < len(real) else n - 1
        prev_kind[i2] = kind
    ex = sorted(ends.get(fsid, []))

    def gap(i, end, term, end_kind):
        p = L[i]
        st = p[0]
        if not (S <= st <= E):
            return
        stop = stop_after(i, end)
        j = bisect.bisect_right(allw, stop + SETTLE)
        kt = (
            allw[j]
            if j < len(allw) and allw[j] <= stop + WAKE and allw[j] < end
            else None
        )
        a0 = bisect.bisect_right(away, stop)
        rec = away[a0] if a0 < len(away) and away[a0] < end else None
        exits = [t for t in ex if st < t < end]
        ctx = p[1]
        nxt = None
        if not term:
            r = L[i + 1]
            nxt = r[0]
            reb = int(ctx > 0 and r[1] >= 0.6 * ctx and r[2] >= 0.5 * ctx)
            saved = max(0, min(ctx, r[2] - max(0, r[1] - ctx))) if reb else 0
            lt = later[i + 1] + 1
        else:
            reb = saved = lt = 0
        wt = stop + WAKE
        gj = [
            [round(js, 3), None if je is None else round(je, 3), kd]
            for js, je, kd in J
            # every job that can be running at any wake time a candidate may try (wake_s ≤ TTL),
            # even past a short gap's end: busy2 above is read at stop+3300 regardless
            if js < max(end, stop + TTL) and (je is None or je > stop)
        ]
        out.append(
            dict(
                case_id="%s:%d" % (fsid, int(stop)),
                acct=acct,
                sid=fsid,
                st=st,
                stop=stop,
                end=end,
                nxt=nxt,
                dur=end - st,
                term=term,
                end_kind=end_kind,
                exit=exits[0] if exits else None,
                ctx=ctx,
                reb=reb,
                saved=saved,
                kill=kt,
                rec=rec,
                later=lt,
                busy2=running(J, wt, ("bash", "agent", "workflow"), last_t, False),
                busy2_ub=running(J, wt, ("bash", "agent", "workflow"), last_t, True),
                watch2=running(J, wt, ("watch",), last_t, False),
                feat_at=wt,
                jobs=gj,
                last=last_t,
                prev=prev_kind.get(i, ""),
                mt=mt,
                alive=alive,
            )
        )

    for i, j in open_idx:
        gap(i, Ot[j], False, "open")
    e2 = [t for t in ex if t >= last_t - 5]
    gap(n - 1, e2[0] if e2 else E, True, "exit" if e2 else "censored")
    return out


def build(S, E, sessions_log=None, now=None):
    """→ (cases, meta). Raises OSError naming the root when a projects root cannot be read."""
    now = now or time.time()
    lo = S - 3 * 86400
    files = []
    roots_read = {}
    for acct, root in roots():
        try:
            dirs = os.listdir(root)
        except OSError as e:
            raise OSError("projects root unreadable: %s (%s): %s" % (acct, root, e))
        nfile = 0
        for d in dirs:
            pd = os.path.join(root, d)
            if not os.path.isdir(pd):
                continue
            for fn in os.listdir(pd):
                if not fn.endswith(".jsonl"):
                    continue
                p = os.path.join(pd, fn)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                if st.st_mtime >= S:
                    files.append((acct, p, st.st_mtime))
                    nfile += 1
        roots_read[acct] = nfile
    F = []
    for acct, p, mt in files:
        f = scan_file(p, lo, E)
        if f is not None and f["reqs"]:
            F.append((acct, os.path.basename(p)[:-6], mt, f))
    occ = collections.defaultdict(list)
    for k, (_a, _s, _m, f) in enumerate(F):
        for x in f["reqs"]:
            occ[x[3]].append(k)
    owner = {rid: min(v, key=lambda k: F[k][2]) for rid, v in occ.items()}
    ends = session_ends(sessions_log or os.path.join(HOME, ".claude/logs/sessions.log"))
    cases = []
    for k, (acct, fsid, mt, f) in enumerate(F):
        L = sorted(x for x in f["reqs"] if owner[x[3]] == k)
        if not L or not any(S <= x[0] <= E for x in L):
            continue
        cases.extend(gaps_of(acct, fsid, f, L, S, E, ends, now - mt < ALIVE_S, mt))
    n55 = sum(
        1
        for g in cases
        if not g["term"] and g["nxt"] is not None and g["nxt"] - g["st"] >= WAKE
    )
    meta = dict(
        schema=2,
        flow="d3_keepalive",
        start=S,
        end=E,
        window_s=E - S,
        built_at=now,
        roots=roots_read,
        files=len(files),
        cli_files=len(F),
        cases=len(cases),
        main_gaps_55min=n55,
        by_acct=dict(collections.Counter(g["acct"] for g in cases)),
    )
    return cases, meta


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--days", type=float, default=28.0)
    ap.add_argument("--end", type=float, default=None)
    ap.add_argument("--start", type=float, default=None)
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    if a.start is not None:
        S = a.start
        E = a.end if a.end is not None else S + a.days * 86400
    else:
        E = a.end if a.end is not None else time.time()
        S = E - a.days * 86400
    cases, meta = build(S, E)
    tmp = a.out + ".tmp%d" % os.getpid()
    with open(tmp, "w") as fh:
        for g in cases:
            fh.write(json.dumps(g, separators=(",", ":")) + "\n")
    os.replace(tmp, a.out)
    print(json.dumps(meta, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
