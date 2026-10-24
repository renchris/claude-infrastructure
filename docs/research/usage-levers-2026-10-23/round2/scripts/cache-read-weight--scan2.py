#!/usr/bin/env python3
# Read-only transcript scanner for the cache-read meter refit (r2/cache-read-weight).
# usage: python3 -I scan.py <acct> <projects_dir> <cutoff_iso> <out_tsv>
# One row per billed response, de-duplicated WITHIN the account on requestId (fallback message.id).
# Output tokens are taken from the FINAL record of the response (file order); first and max are kept
# as diagnostics. Input / cache classes are taken from the first record and checked against later ones.
import sys, os, json, time
from datetime import datetime

acct, root, cutoff_iso, out_path = sys.argv[1:5]
cut = datetime.fromisoformat(cutoff_iso.replace("Z", "+00:00")).timestamp()


def ts_epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


files = []
for dp, dn, fn in os.walk(root):  # no followlinks: only memory/ dirs are symlinked
    for f in fn:
        if f.endswith(".jsonl"):
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime >= cut:
                files.append((p, st.st_size, st.st_birthtime, st.st_mtime))

t0 = time.time()
nbytes = 0
bad = 0
mism = 0
seen = set()
nrows = 0
xfile_dups = 0
FMT = "%s\t%d\t%s\t%.3f\t%.3f\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%s\t%d\t%s\n"
out = open(out_path, "w")
out.write(
    "acct\tfile\tkind\tts\tts_last\treq\tmodel\tinp\tcc\tcc5\tcc1\tcr\tout_first\tout_final\tout_max\tnrec\tside\tspeed\tweb\tnonmsg_iter\tadvisor\tsid\tmism\tmid\n"
)
for fi, (p, sz, bt, mt) in enumerate(files):
    kind = "s" if "/subagents/" in p else "m"
    local = {}
    try:
        fh = open(p, "rb")
    except OSError:
        continue
    with fh:
        for line in fh:
            nbytes += len(line)
            if b'"usage"' not in line or b'"assistant"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                bad += 1
                continue
            if r.get("type") != "assistant":
                continue
            m = r.get("message") or {}
            u = m.get("usage")
            if not isinstance(u, dict):
                continue
            te = ts_epoch(r.get("timestamp", ""))
            if te is None or te < cut:
                continue
            key = r.get("requestId") or m.get("id") or r.get("uuid")
            o = u.get("output_tokens") or 0
            inp = u.get("input_tokens") or 0
            cc = u.get("cache_creation_input_tokens") or 0
            cr = u.get("cache_read_input_tokens") or 0
            if key in local:
                rr = local[key]
                rr[13] = o  # final record's output
                if o > rr[14]:
                    rr[14] = o
                rr[15] += 1
                rr[4] = te  # last ts
                if (inp, cc, cr) != (rr[7], rr[8], rr[11]):
                    rr[22] = 1
                continue
            ccb = u.get("cache_creation") or {}
            stu = u.get("server_tool_use") or {}
            its = u.get("iterations") or []
            nonmsg = sum(
                1
                for it in its
                if isinstance(it, dict) and it.get("type") not in (None, "message")
            )
            rr = [
                acct,  # 0
                fi,  # 1
                kind,  # 2
                te,  # 3 first ts
                te,  # 4 last ts
                key,  # 5
                m.get("model", ""),  # 6
                inp,  # 7
                cc,  # 8
                ccb.get("ephemeral_5m_input_tokens") or 0,  # 9
                ccb.get("ephemeral_1h_input_tokens") or 0,  # 10
                cr,  # 11
                o,  # 12 first output
                o,  # 13 final output
                o,  # 14 max output
                1,  # 15 nrec
                1 if r.get("isSidechain") else 0,  # 16
                u.get("speed") or "",  # 17
                (stu.get("web_search_requests") or 0)
                + (stu.get("web_fetch_requests") or 0),  # 18
                nonmsg,  # 19
                (1 if r.get("advisorModel") else 0) + (2 if r.get("serverClassifierRequest") else 0) + (4 if m.get("stop_reason") == "tool_use" else 0) + (8 if m.get("stop_reason") == "end_turn" else 0) + (16 if (r.get("entrypoint") or "") not in ("cli", "") else 0),  # 20 flags
                r.get("sessionId") or "",  # 21
                0,  # 22 class mismatch across records
                m.get("id") or "",  # 23
            ]
            local[key] = rr
    for k, rr in local.items():
        if k in seen:
            xfile_dups += 1
            continue  # same response copied into another file of this account (fork/resume): count once
        seen.add(k)
        nrows += 1
        mism += rr[22]
        out.write(FMT % tuple(rr))

out.close()
with open(out_path + ".files", "w") as ff:
    for fi, (p, sz, bt, mt) in enumerate(files):
        ff.write(
            "%d\t%d\t%.3f\t%.3f\t%s\n" % (fi, sz, bt, mt, os.path.relpath(p, root))
        )
sys.stderr.write(
    "DONE acct=%s files=%d bytes=%.2fGB rows=%d xfile_dups=%d mism=%d badlines=%d secs=%.1f\n"
    % (
        acct,
        len(files),
        nbytes / 1e9,
        nrows,
        xfile_dups,
        mism,
        bad,
        time.time() - t0,
    )
)
