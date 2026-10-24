#!/usr/bin/env python3
# Independent reviewer scanner (read-only). One row per response, de-duplicated within the account
# on requestId (fallback message.id). Scans *.jsonl AND retired *.jsonl.* (handed-off) files.
# usage: python3 -I rscan.py <acct> <projects_root> <cutoff_iso> <out_tsv>
import sys, os, json, time
from datetime import datetime

acct, root, cut_iso, outp = sys.argv[1:5]
cut = datetime.fromisoformat(cut_iso).timestamp()


def te(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


files = []
for dp, dn, fn in os.walk(root):
    for f in fn:
        if f.endswith(".jsonl") or ".jsonl." in f:
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime >= cut:
                files.append(p)
t0 = time.time()
G = {}
nb = 0
for p in files:
    kind = "s" if "/subagents/" in p else "m"
    retired = 0 if p.endswith(".jsonl") else 1
    L = {}
    try:
        fh = open(p, "rb")
    except OSError:
        continue
    with fh:
        for line in fh:
            nb += len(line)
            if b'"assistant"' not in line or b'"usage"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("type") != "assistant":
                continue
            m = r.get("message") or {}
            u = m.get("usage")
            if not isinstance(u, dict):
                continue
            t = te(r.get("timestamp", ""))
            if t is None or t < cut:
                continue
            model = m.get("model", "")
            if model == "<synthetic>":
                continue
            k = r.get("requestId") or m.get("id")
            if not k:
                continue
            ntool = sum(
                1
                for c in (m.get("content") or [])
                if isinstance(c, dict) and c.get("type") == "tool_use"
            )
            o = u.get("output_tokens") or 0
            if k in L:
                x = L[k]
                x[8] = max(x[8], o)
                x[9] += ntool
                continue
            cb = u.get("cache_creation") or {}
            its = u.get("iterations") or []
            xin = xout = 0
            for it in its:
                if isinstance(it, dict) and it.get("type") not in (None, "message"):
                    xin += (
                        (it.get("input_tokens") or 0)
                        + (it.get("cache_read_input_tokens") or 0)
                        + (it.get("cache_creation_input_tokens") or 0)
                    )
                    xout += it.get("output_tokens") or 0
            L[k] = [
                t,
                model,
                kind,
                u.get("input_tokens") or 0,
                cb.get("ephemeral_5m_input_tokens") or 0,
                cb.get("ephemeral_1h_input_tokens") or 0,
                u.get("cache_creation_input_tokens") or 0,
                u.get("cache_read_input_tokens") or 0,
                o,
                ntool,
                1 if r.get("serverClassifierRequest") else 0,
                u.get("speed") or "",
                xin,
                xout,
                retired,
            ]
    for k, x in L.items():
        if k in G:
            y = G[k]
            y[0] = min(y[0], x[0])
            y[8] = max(y[8], x[8])
            y[9] = max(y[9], x[9])
            y[10] = max(y[10], x[10])
            y[14] = min(y[14], x[14])
        else:
            G[k] = x
with open(outp, "w") as f:
    f.write(
        "req\tts\tmodel\tkind\tinp\tcc5\tcc1\tcc\tcr\tout\tntool\tclf\tspeed\txin\txout\tretired_only\n"
    )
    for k, x in G.items():
        f.write(
            k
            + "\t"
            + "\t".join(("%.3f" % v) if i == 0 else str(v) for i, v in enumerate(x))
            + "\n"
        )
sys.stderr.write(
    "DONE %s files=%d GB=%.2f uniq=%d secs=%.0f\n"
    % (acct, len(files), nb / 1e9, len(G), time.time() - t0)
)
