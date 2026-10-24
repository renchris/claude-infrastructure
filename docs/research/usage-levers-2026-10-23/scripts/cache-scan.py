import json, sys, os, time, gzip

# Re-saved copy of the scanner that produced rows-<acct>.tsv.gz (the original /tmp/usage-audit/scan.py
# was overwritten by a sibling worker after launch). Usage: python3 -I cache-scan.py <acct> <config>/projects <out.tsv.gz>
acct, root, out = sys.argv[1], sys.argv[2], sys.argv[3]
now = time.time()
cut = now - 7 * 86400
cut_iso = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(cut))
files = []
for dp, dn, fn in os.walk(root, followlinks=True):
    for f in fn:
        if f.endswith(".jsonl"):
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except:
                continue
            if st.st_mtime >= cut:
                files.append((p, st.st_size))
tot = sum(s for _, s in files)
sys.stderr.write(f"{acct} files={len(files)} bytes={tot}\n")
seen = set()
n = 0
o = gzip.open(out, "wt")
o.write(
    "acct\tfile\tsub\tside\tts\tmodel\teffort\tver\tin\tcc\tcr\tout\tcc1h\tcc5m\tmiss\tevents\n"
)
for p, _ in files:
    sub = 1 if "/subagents/" in p else 0
    ev = set()
    try:
        fh = open(p, errors="replace")
    except:
        continue
    for line in fh:
        if '"type":"assistant"' not in line:
            try:
                d = json.loads(line)
            except:
                continue
            t = d.get("type")
            if t == "attachment":
                a = d.get("attachment")
                if isinstance(a, dict):
                    ev.add("att:" + str(a.get("type")))
            elif t == "system":
                ev.add("sys:" + str(d.get("subtype")))
            elif t == "user":
                if d.get("isCompactSummary"):
                    ev.add("compact_summary")
                if d.get("isMeta"):
                    ev.add("meta")
            continue
        try:
            d = json.loads(line)
        except:
            continue
        if d.get("type") != "assistant":
            continue
        m = d.get("message") or {}
        u = m.get("usage")
        if not u:
            continue
        rid = d.get("requestId") or m.get("id")
        if rid in seen:
            continue
        seen.add(rid)
        ts = d.get("timestamp") or ""
        if ts < cut_iso:
            ev = set()
            continue
        c = u.get("cache_creation") or {}
        diag = m.get("diagnostics") or d.get("diagnostics")
        miss = ""
        if isinstance(diag, dict) and diag.get("cache_miss_reason"):
            miss = json.dumps(diag["cache_miss_reason"], separators=(",", ":"))
        o.write(
            "\t".join(
                map(
                    str,
                    [
                        acct,
                        p,
                        sub,
                        int(bool(d.get("isSidechain"))),
                        ts,
                        m.get("model"),
                        d.get("effort") or "",
                        d.get("version") or "",
                        u.get("input_tokens") or 0,
                        u.get("cache_creation_input_tokens") or 0,
                        u.get("cache_read_input_tokens") or 0,
                        u.get("output_tokens") or 0,
                        c.get("ephemeral_1h_input_tokens") or 0,
                        c.get("ephemeral_5m_input_tokens") or 0,
                        miss,
                        ",".join(sorted(ev)),
                    ],
                )
            )
            + "\n"
        )
        ev = set()
        n += 1
o.close()
sys.stderr.write(f"{acct} DONE rows={n}\n")
