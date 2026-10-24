#!/usr/bin/env python3
# Collect session-move evidence (read-only): tombstones (<sid>.HANDOFF.json next to the source
# transcript), lr-transplant locks (~/.reso/limit-recover/locks/*.lock with from/to/ts/ts_first/chain),
# and scan retired source transcripts (*.jsonl.handed-off*) for the requestIds they hold.
# Writes moves.tsv (sid, ts, from, to, src) and retired_rows.tsv (acct, sid, req, ts).
import os, json, glob
from datetime import datetime

H = os.path.expanduser("~")
DIRS = {
    H + "/.claude": "next",
    H + "/.claude-next": "next",
    H + "/.claude-secondary": "next2",
    H + "/.claude-tertiary": "next3",
    H + "/.claude-quaternary": "next4",
}
ROOT = {
    "next": H + "/.claude/projects",
    "next2": H + "/.claude-secondary/projects",
    "next3": H + "/.claude-tertiary/projects",
    "next4": H + "/.claude-quaternary/projects",
}
OUT = "/tmp/usage-audit/r2/cache-read-weight/"
CUT = datetime.fromisoformat("2026-08-09T00:00:00+00:00").timestamp()


def acct_of(p):
    p = (p or "").rstrip("/")
    for d, a in DIRS.items():
        if p == d or p.startswith(d + "/"):
            return a
    return None


def T(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


ev = set()
ntomb = nlock = 0
for a, root in ROOT.items():
    for proj in os.listdir(root):
        pd = os.path.join(root, proj)
        try:
            names = os.listdir(pd)
        except OSError:
            continue
        for n in names:
            if n.endswith(".HANDOFF.json"):
                try:
                    d = json.load(open(os.path.join(pd, n)))
                    to = acct_of(d.get("handed_off_to"))
                    ev.add((n[: -len(".HANDOFF.json")], T(d["ts"]), a, to, "tomb"))
                    ntomb += 1
                except Exception:
                    pass
for p in glob.glob(H + "/.reso/limit-recover/locks/*.lock"):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    sid = d.get("sid")
    if not sid:
        continue
    nlock += 1
    f, t = acct_of(d.get("from")), acct_of(d.get("to"))
    if d.get("ts"):
        ev.add((sid, T(d["ts"]), f, t, "lock"))
    ch = [acct_of(x) for x in (d.get("chain") or [])]
    if d.get("ts_first") and len(ch) >= 2:
        ev.add((sid, T(d["ts_first"]), ch[0], ch[1], "lock_first"))
with open(OUT + "moves.tsv", "w") as o:
    o.write("sid\tts\tfrom\tto\tsrc\n")
    for e in sorted(ev):
        o.write("%s\t%.0f\t%s\t%s\t%s\n" % e)
# retired source transcripts
nret = nrow = 0
with open(OUT + "retired_rows.tsv", "w") as o:
    o.write("acct\tsid\treq\tts\n")
    for a, root in ROOT.items():
        for p in glob.glob(root + "/*/*.jsonl.*"):
            try:
                if os.stat(p).st_mtime < CUT:
                    continue
            except OSError:
                continue
            nret += 1
            sid = os.path.basename(p).split(".jsonl")[0]
            seen = set()
            with open(p, "rb") as fh:
                for line in fh:
                    if b'"usage"' not in line or b'"assistant"' not in line:
                        continue
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if r.get("type") != "assistant":
                        continue
                    m = r.get("message") or {}
                    k = r.get("requestId") or m.get("id")
                    if not k or k in seen:
                        continue
                    seen.add(k)
                    try:
                        te = T(r.get("timestamp", ""))
                    except Exception:
                        continue
                    o.write("%s\t%s\t%s\t%.3f\n" % (a, sid, k, te))
                    nrow += 1
print(
    "tombstones",
    ntomb,
    "locks",
    nlock,
    "events",
    len(ev),
    "retired files",
    nret,
    "retired rows",
    nrow,
)
