#!/usr/bin/env python3
# Skeptic re-scan (independent of cache-scan.py). Usage: python3 -I sk-cache-scan.py <acct> <real projects root> <out.tsv>
# Differences from the original scanner on purpose:
#  - does NOT follow symlinks (os.walk followlinks=False) and realpath-dedupes files
#  - keys on message.id, keeps first-record input classes and MAX output_tokens over the records
#  - emits the relative path so cross-account copies of one transcript merge onto one timeline
import json, os, sys, time

acct, root, out = sys.argv[1], sys.argv[2], sys.argv[3]
now = time.time()
cut = now - 7 * 86400
cut_iso = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(cut))
seen_real = set()
files = []
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.endswith(".jsonl"):
            continue
        p = os.path.join(dp, f)
        try:
            if os.path.islink(p):
                continue
            st = os.stat(p)
        except OSError:
            continue
        if st.st_mtime < cut:
            continue
        rp = os.path.realpath(p)
        if rp in seen_real:
            continue
        seen_real.add(rp)
        files.append((p, st.st_size))
nbytes = sum(s for _, s in files)
sys.stderr.write(f"{acct} files={len(files)} bytes={nbytes}\n")
M = {}  # mid -> list
order = []
for p, _ in files:
    rel = p.split("/projects/", 1)[1]
    sub = 1 if "/subagents/" in p else 0
    try:
        fh = open(p, "r", errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            if '"assistant"' not in line or '"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            m = d.get("message") or {}
            u = m.get("usage")
            if not isinstance(u, dict):
                continue
            mid = m.get("id") or d.get("requestId")
            if not mid:
                continue
            ts = d.get("timestamp") or ""
            o = u.get("output_tokens") or 0
            r = M.get(mid)
            if r is None:
                if ts < cut_iso:
                    continue
                c = u.get("cache_creation") or {}
                r = [
                    mid,
                    acct,
                    rel,
                    sub,
                    int(bool(d.get("isSidechain"))),
                    ts,
                    m.get("model") or "",
                    u.get("input_tokens") or 0,
                    u.get("cache_creation_input_tokens") or 0,
                    u.get("cache_read_input_tokens") or 0,
                    c.get("ephemeral_1h_input_tokens") or 0,
                    c.get("ephemeral_5m_input_tokens") or 0,
                    o,
                    o,
                    1,
                    1 if m.get("stop_reason") else 0,
                ]
                M[mid] = r
                order.append(mid)
            else:
                r[13] = max(r[13], o)
                r[14] += 1
                if m.get("stop_reason"):
                    r[15] = 1
with open(out, "w") as w:
    w.write(
        "mid\tacct\trel\tsub\tside\tts\tmodel\tin\tcc\tcr\tcc1h\tcc5m\tout_first\tout_max\tnrec\thas_stop\n"
    )
    for mid in order:
        w.write("\t".join(map(str, M[mid])) + "\n")
sys.stderr.write(f"{acct} DONE messages={len(order)}\n")
