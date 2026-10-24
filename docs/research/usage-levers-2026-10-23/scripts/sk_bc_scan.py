#!/usr/bin/env python3
# Skeptic scanner (big-context lever). Read-only over transcripts; writes one TSV per account.
# usage: python3 -I sk_bc_scan.py <acct> <projects_dir> <cutoff_iso> <out_tsv>
import sys, os, json, time
from datetime import datetime, timezone

acct, root, cutoff_iso, out_path = sys.argv[1:5]
cut = datetime.fromisoformat(cutoff_iso.replace("Z", "+00:00")).timestamp()


def ts_epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


files = []
for dp, dn, fn in os.walk(root, followlinks=True):
    for f in fn:
        if f.endswith(".jsonl"):
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime >= cut:
                files.append((p, st.st_size))

t0 = time.time()
nbytes = 0
nlines_bad = 0
with open(out_path, "w") as out:
    out.write(
        "acct\tkind\tfile\tts\treq\tmodel\tinp\tcc\tcc5\tcc1h\tcr\tout\tturn\tside\n"
    )
    for fi, (p, sz) in enumerate(files):
        kind = "s" if "/subagents/" in p else "m"
        rows = {}
        order = []
        pending_turn = 1  # first request in a file counts as a turn start
        try:
            fh = open(p, "rb")
        except OSError:
            continue
        with fh:
            for line in fh:
                nbytes += len(line)
                if b'"type":"user"' in line[:1500] or b'"type": "user"' in line[:1500]:
                    if b'"tool_result"' not in line:
                        pending_turn = 1
                    continue
                if b'"usage"' not in line or b'"assistant"' not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    nlines_bad += 1
                    continue
                if r.get("type") != "assistant":
                    continue
                m = r.get("message") or {}
                u = m.get("usage")
                if not isinstance(u, dict):
                    continue
                te = ts_epoch(r.get("timestamp", ""))
                if te is None or te < cut:
                    pending_turn = 0
                    continue
                key = r.get("requestId") or m.get("id") or r.get("uuid")
                o = u.get("output_tokens") or 0
                if key in rows:
                    rr = rows[key]
                    if o > rr[9]:
                        rr[9] = o
                    continue
                ccb = u.get("cache_creation") or {}
                rr = [
                    te,
                    key,
                    m.get("model", ""),
                    u.get("input_tokens") or 0,
                    u.get("cache_creation_input_tokens") or 0,
                    ccb.get("ephemeral_5m_input_tokens") or 0,
                    ccb.get("ephemeral_1h_input_tokens") or 0,
                    u.get("cache_read_input_tokens") or 0,
                    0,
                    o,
                    pending_turn,
                    1 if r.get("isSidechain") else 0,
                ]
                pending_turn = 0
                rows[key] = rr
                order.append(key)
        for k in order:
            rr = rows[k]
            out.write(
                "%s\t%s\t%d\t%.3f\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n"
                % (
                    acct,
                    kind,
                    fi,
                    rr[0],
                    rr[1],
                    rr[2],
                    rr[3],
                    rr[4],
                    rr[5],
                    rr[6],
                    rr[7],
                    rr[9],
                    rr[10],
                    rr[11],
                )
            )
with open(out_path + ".files", "w") as ff:
    for fi, (p, sz) in enumerate(files):
        ff.write("%d\t%d\t%s\n" % (fi, sz, p))
sys.stderr.write(
    "DONE acct=%s files=%d bytes=%.2fGB badlines=%d secs=%.1f\n"
    % (acct, len(files), nbytes / 1e9, nlines_bad, time.time() - t0)
)
