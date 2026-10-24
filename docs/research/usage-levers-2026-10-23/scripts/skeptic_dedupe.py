#!/usr/bin/env python3
# Skeptic pass 2 (read-only): global requestId dedupe across ALL files and accounts.
# Re-reads the file list from skeptic_perfile.jsonl, keeps first occurrence of each requestId
# (in the 7d window), and reports per agentType: file-summed vs globally-unique requests/tokens,
# plus per-request baseline from each file's first request (unique files only = files whose
# first rid was not already seen).
import json, collections, time, datetime, statistics

CUT_ISO = json.load(open("/tmp/usage-audit/skeptic_scan_summary.json"))["cutoff"]
files = [json.loads(l) for l in open("/tmp/usage-audit/skeptic_perfile.jsonl")]
seen = {}
per = collections.defaultdict(lambda: collections.Counter())
dupfile = 0
uniq_first = collections.defaultdict(
    list
)  # agentType -> list of (first ctx, window req)
dup_by_proj = collections.Counter()
for fi, rec in enumerate(files):
    at = rec["agentType"]
    p = rec["path"]
    proj = p.split("/projects/")[1].split("/")[0]
    first_rid = None
    nd = 0
    nu = 0
    with open(p, "rb") as fh:
        fseen = set()
        for raw in fh:
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
            rid = r.get("requestId") or m.get("id")
            if first_rid is None:
                first_rid = rid
            if (r.get("timestamp") or "") < CUT_ISO:
                continue
            if rid in fseen:
                continue
            fseen.add(rid)
            cr = u.get("cache_read_input_tokens") or 0
            cc = u.get("cache_creation_input_tokens") or 0
            ccd = u.get("cache_creation") or {}
            c5 = ccd.get("ephemeral_5m_input_tokens") or 0
            c1 = ccd.get("ephemeral_1h_input_tokens") or 0
            i = u.get("input_tokens") or 0
            o = u.get("output_tokens") or 0
            P = per[at]
            P["sum_req"] += 1
            P["sum_cr"] += cr
            if rid in seen:
                nd += 1
                P["dup_req"] += 1
                P["dup_cr"] += cr
                continue
            seen[rid] = fi
            nu += 1
            P["u_req"] += 1
            P["u_cr"] += cr
            P["u_cc5"] += c5
            P["u_cc1h"] += c1
            P["u_inp"] += i
            P["u_out"] += o
    if nd:
        dupfile += 1
        dup_by_proj[(rec["acct"], proj, at)] += nd
    f = rec.get("first")
    if f and nu > 0 and (first_rid not in seen or seen.get(first_rid) == fi):
        uniq_first[at].append((f[0] + f[1] + f[2], f[2], nu))

res = {
    "cutoff": CUT_ISO,
    "files_with_dups": dupfile,
    "by_type": {k: dict(v) for k, v in per.items()},
    "top_dup_sources": [[list(k), n] for k, n in dup_by_proj.most_common(15)],
}
fs = {}
for at, L in uniq_first.items():
    ctx = sorted(x[0] for x in L)
    if not ctx:
        continue
    fs[at] = {
        "files": len(L),
        "p50_first_ctx": ctx[len(ctx) // 2],
        "p10": ctx[len(ctx) // 10],
        "p90": ctx[(9 * len(ctx)) // 10],
        "first_cr0_share": round(sum(1 for x in L if x[1] == 0) / len(L), 3),
        "req_weighted_first_ctx_mean": round(
            sum(x[0] * x[2] for x in L) / max(1, sum(x[2] for x in L))
        ),
        "req": sum(x[2] for x in L),
    }
res["first_ctx"] = fs
json.dump(res, open("/tmp/usage-audit/skeptic_dedupe.json", "w"), indent=1)
print("DONE")
