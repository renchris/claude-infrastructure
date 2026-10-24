#!/usr/bin/env python3
# Pair each recycle successor (first non-meta user prompt carries HANDOFF-RECYCLE-*) with its predecessor.
# Join 1: the brief's "LEDGER AT RETIREMENT (wrap-ledger.sh --machine, session <uuid>)" line.
# Join 2: handoffs.jsonl recycle-engaged row (prev_sid) within [brief-60s, brief+900s] (ledger rotates).
# Join 3: a session in the same cwd whose Bash ran `--recycle` within 30 min before the brief.
# usage: python3 -I pairs.py <workdir>  -> pairs.jsonl
import glob, json, os, re, sys
from datetime import datetime

W = sys.argv[1]
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
LEDGER = re.compile(r"LEDGER AT RETIREMENT \([^)]*session (" + UUID + r")")


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def text_of(c):
    if isinstance(c, list):
        return "\n".join(
            b.get("text", "")
            for b in c
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return c if isinstance(c, str) else ""


R = [json.loads(l) for f in glob.glob(os.path.join(W, "idx.*.jsonl")) for l in open(f)]
by_sid = {}
for r in R:
    k = r["sessionId"] or r["sid"]
    # a transplanted session can exist as a copy in two roots: keep the bigger file
    if k not in by_sid or r["size"] > by_sid[k]["size"]:
        by_sid[k] = r
eng = []
for l in open(os.path.expanduser("~/.claude/logs/handoffs.jsonl")):
    try:
        x = json.loads(l)
    except Exception:
        continue
    if (
        x.get("class") == "recycle-engaged"
        and x.get("engaged") is True
        and x.get("prev_sid")
    ):
        eng.append(x)

out = open(os.path.join(W, "pairs.jsonl"), "w")
stats = dict(
    succ=0,
    j1=0,
    j2=0,
    j3=0,
    none=0,
    pred_missing=0,
    j1_j2_agree=0,
    j1_j2_both=0,
    j1_j3_agree=0,
    j1_j3_both=0,
)
for k, s in by_sid.items():
    if not any(m.startswith("HANDOFF-RECYCLE-") for m in s["markers"]):
        continue
    stats["succ"] += 1
    full = None
    with open(s["path"], "rb") as fh:
        for line in fh:
            if b'"type":"user"' in line[:3000] and b'"tool_result"' not in line:
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("isMeta"):
                    continue
                t = text_of((r.get("message") or {}).get("content"))
                if "HANDOFF-RECYCLE-" in t:
                    full = t
                    break
    bts = ep(s["fp_ts"] or "")
    j1 = None
    m = LEDGER.search(full or "")
    if m:
        j1 = m.group(1)
    j2 = None
    best = None
    for x in eng:
        d = (ep(x["ts"]) or 0) - (bts or 0)
        if -60 <= d <= 900 and x["prev_sid"] != k and (best is None or abs(d) < best):
            best, j2 = abs(d), x["prev_sid"]
    j3 = None
    best = None
    for r in by_sid.values():
        if r is s or r["cwd"] != s["cwd"]:
            continue
        for ts, cmd, _ in r["recycle_cmds"]:
            d = (bts or 0) - (ep(ts or "") or 0)
            if 0 <= d <= 1800 and (best is None or d < best):
                best, j3 = d, (r["sessionId"] or r["sid"])
    pred = j1 or j2 or j3
    for nm, v in (("j1", j1), ("j2", j2), ("j3", j3)):
        if v:
            stats[nm] += 1
    if j1 and j2:
        stats["j1_j2_both"] += 1
        stats["j1_j2_agree"] += int(j1 == j2)
    if j1 and j3:
        stats["j1_j3_both"] += 1
        stats["j1_j3_agree"] += int(j1 == j3)
    if not pred:
        stats["none"] += 1
    elif pred not in by_sid:
        stats["pred_missing"] += 1
    p = by_sid.get(pred) if pred else None
    out.write(
        json.dumps(
            dict(
                succ=k,
                succ_path=s["path"],
                succ_acct=s["acct"],
                cwd=s["cwd"],
                brief_ts=s["fp_ts"],
                brief_len=len(full or ""),
                pred=pred,
                join="j1" if j1 else "j2" if j2 else "j3" if j3 else None,
                pred_path=p["path"] if p else None,
                pred_acct=p["acct"] if p else None,
                pred_cwd=p["cwd"] if p else None,
                pred_ts_last=p["ts_last"] if p else None,
                pred_first_prompt=(p["first_prompt"] or "")[:200] if p else None,
                succ_first_prompt=(s["first_prompt"] or "")[:300],
            )
        )
        + "\n"
    )
print(json.dumps(stats))
