#!/usr/bin/env python3
# Skeptic re-scan (read-only). Independent of fullscan.py/headscan.py.
# For every transcript modified in the last 7d (+1d margin on mtime), parse assistant records with usage.
# Per file: agentType (from sibling .meta.json), workflowPhase/description, first usage record (any time),
# window requests (dedupe by requestId within file), sums, cache_creation 5m/1h split, models.
# Global: requestId -> list of (acct, kind) to detect cross-file duplication.
import json, os, sys, time, datetime, collections

ACCTS = {
    "next": "~/.claude-next",
    "next2": "~/.claude-secondary",
    "next3": "~/.claude-tertiary",
    "next4": "~/.claude-quaternary",
}
NOW = time.time()
CUT = NOW - 7 * 86400
CUT_ISO = datetime.datetime.fromtimestamp(CUT, datetime.timezone.utc).strftime(
    "%Y-%m-%dT%H:%M:%S"
)
out = open("/tmp/usage-audit/skeptic_perfile.jsonl", "w")
rid_files = collections.defaultdict(int)
rid_kinds = {}
dup_cross = collections.Counter()
nbytes = 0
roots = set()
for acct, base in ACCTS.items():
    root = os.path.realpath(os.path.expanduser(base + "/projects"))
    if root in roots:
        print("dup root", root)
        continue
    roots.add(root)
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if not f.endswith(".jsonl"):
                continue
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime < CUT - 86400:
                continue
            kind = "sub" if "/subagents/" in p else "main"
            meta = {}
            if kind == "sub":
                mp = p[:-6] + ".meta.json"
                try:
                    meta = json.load(open(mp))
                except Exception:
                    meta = {}
            rec = {
                "acct": acct,
                "kind": kind,
                "path": p,
                "agentType": meta.get("agentType", "main" if kind == "main" else "?"),
                "desc": (meta.get("description") or "")[:60],
                "phase": meta.get("workflowPhase"),
                "wf": "/workflows/" in p,
                "first": None,
                "first_ts": None,
                "req": 0,
                "inp": 0,
                "cc": 0,
                "cc5": 0,
                "cc1h": 0,
                "cr": 0,
                "out": 0,
                "models": {},
                "maxctx": 0,
            }
            seen = set()
            try:
                fh = open(p, "rb")
            except OSError:
                continue
            with fh:
                for raw in fh:
                    nbytes += len(raw)
                    if b'"usage"' not in raw or b'"assistant"' not in raw:
                        continue
                    try:
                        r = json.loads(raw)
                    except Exception:
                        continue
                    if r.get("type") != "assistant":
                        continue
                    m = r.get("message") or {}
                    u = m.get("usage")
                    if not isinstance(u, dict):
                        continue
                    i = u.get("input_tokens") or 0
                    c = u.get("cache_creation_input_tokens") or 0
                    cr = u.get("cache_read_input_tokens") or 0
                    o = u.get("output_tokens") or 0
                    if rec["first"] is None:
                        rec["first"] = [i, c, cr, o]
                        rec["first_ts"] = r.get("timestamp")
                    ts = r.get("timestamp") or ""
                    if ts < CUT_ISO:
                        continue
                    rid = r.get("requestId") or m.get("id")
                    if rid in seen:
                        continue
                    seen.add(rid)
                    rid_files[rid] += 1
                    k = rid_kinds.get(rid)
                    if k is None:
                        rid_kinds[rid] = (acct, kind)
                    else:
                        dup_cross[(k[0] + "|" + k[1], acct + "|" + kind)] += 1
                    rec["req"] += 1
                    rec["inp"] += i
                    rec["cc"] += c
                    rec["cr"] += cr
                    rec["out"] += o
                    ccd = u.get("cache_creation") or {}
                    rec["cc5"] += ccd.get("ephemeral_5m_input_tokens") or 0
                    rec["cc1h"] += ccd.get("ephemeral_1h_input_tokens") or 0
                    mod = m.get("model") or "?"
                    rec["models"][mod] = rec["models"].get(mod, 0) + 1
                    ctx = i + c + cr
                    if ctx > rec["maxctx"]:
                        rec["maxctx"] = ctx
            out.write(json.dumps(rec) + "\n")
out.close()
dups = sum(1 for v in rid_files.values() if v > 1)
json.dump(
    {
        "cutoff": CUT_ISO,
        "bytes": nbytes,
        "unique_rids": len(rid_files),
        "rids_in_multiple_files": dups,
        "dup_cross": {f"{a}->{b}": n for (a, b), n in dup_cross.items()},
    },
    open("/tmp/usage-audit/skeptic_scan_summary.json", "w"),
    indent=1,
)
print("DONE")
