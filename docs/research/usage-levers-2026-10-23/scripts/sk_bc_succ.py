#!/usr/bin/env python3
# Classify 7d main sessions by first real user prompt; measure successor (recycle/handoff) re-prime vs fresh.
import csv, json, re, collections
from datetime import datetime

CUT7 = datetime.fromisoformat("2026-10-17T02:30:00+00:00").timestamp()
ACCTS = ["next", "next2", "next3", "next4"]
PAT = re.compile(
    r"self-recycle|resumed by a deterministic|predecessor|handoff|hand-off|successor|recycled",
    re.I,
)


def first_prompt(p):
    try:
        with open(p, "rb") as f:
            for n, line in enumerate(f):
                if n > 400:
                    break
                if b'"type":"user"' not in line[:1500]:
                    continue
                if b'"tool_result"' in line:
                    continue
                r = json.loads(line)
                if r.get("isMeta"):
                    continue
                c = (r.get("message") or {}).get("content")
                if isinstance(c, list):
                    c = " ".join(b.get("text", "") for b in c if isinstance(b, dict))
                if not isinstance(c, str):
                    continue
                if c.startswith("<command-name>") or c.startswith("<local-command"):
                    continue
                return c[:600]
    except Exception:
        return None
    return None


sess = collections.defaultdict(list)
paths = {}
for a in ACCTS:
    for line in open("/tmp/usage-audit/sk_bc_rows_%s.tsv.files" % a):
        fi, sz, p = line.rstrip("\n").split("\t", 2)
        paths[(a, int(fi))] = p
    with open("/tmp/usage-audit/sk_bc_rows_%s.tsv" % a) as f:
        r = csv.reader(f, delimiter="\t")
        next(r)
        for x in r:
            if x[1] != "m":
                continue
            sess[(a, int(x[2]))].append(
                (
                    float(x[3]),
                    int(x[6]) + int(x[7]) + int(x[10]),
                    int(x[7]),
                    int(x[10]),
                    int(x[11]),
                    int(x[12]),
                )
            )
cls = collections.Counter()
stats = collections.defaultdict(lambda: collections.defaultdict(list))
examples = collections.defaultdict(list)
for k, L in sess.items():
    L.sort()
    if L[0][0] < CUT7:
        continue  # only sessions that START in the 7d window
    fp = first_prompt(paths[k]) or ""
    c = "successor" if PAT.search(fp[:600]) else "fresh"
    if fp.startswith("<task-notification>"):
        c = "task-notification-first"
    cls[c] += 1
    if len(examples[c]) < 4:
        examples[c].append(fp[:160].replace("\n", " "))
    s = stats[c]
    s["first_ctx"].append(L[0][1])
    s["first_cc"].append(L[0][2])
    if len(L) >= 10:
        s["ctx10"].append(L[9][1])
    if len(L) >= 30:
        s["ctx30"].append(L[29][1])
    s["peak"].append(max(x[1] for x in L))
    s["nreq"].append(len(L))
    s["turns"].append(sum(x[5] for x in L))


def q(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(p * len(v)))] if v else -1


print("7d-starting main sessions by class:", dict(cls))
for c, s in stats.items():
    print("\n[%s]" % c)
    for m in ("first_ctx", "first_cc", "ctx10", "ctx30", "peak", "nreq", "turns"):
        v = s[m]
        print(
            "  %-9s n=%4d p25=%7d p50=%7d p75=%7d p90=%7d"
            % (m, len(v), q(v, 0.25), q(v, 0.5), q(v, 0.75), q(v, 0.9))
        )
    for e in examples[c]:
        print("   ex:", e)
