import json, os, sys, time, pickle, hashlib, re, collections
from datetime import datetime

# independent re-scan (skeptic of lever long-parallel). read-only over transcripts; writes only the pickle below.
acct, root, sample_mod = (
    sys.argv[1],
    sys.argv[2],
    int(sys.argv[3]),
)  # sample_mod=1 -> all sessions; 16 -> keep 15/16 of sessions
NOW = time.time()
CUT = NOW - 7 * 86400


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def keep(sid):
    if sample_mod <= 1:
        return True
    return int(hashlib.md5(sid.encode()).hexdigest()[:4], 16) % sample_mod != 0


def ucls(d, txt):
    t = txt.lstrip()
    o = d.get("origin")
    ok = o.get("kind") if isinstance(o, dict) else o
    if t.startswith("<task-notification>"):
        m = re.search(r"<summary>(.*?)</summary>", t, re.S)
        s = re.sub(r"\s+", " ", m.group(1)) if m else ""
        return "tn", s[:120]
    if ok == "peer" or t.startswith("Another Claude session sent"):
        return "peer", ""
    if t.startswith("<teammate-message"):
        return "teammate", ""
    if t.startswith("Stop hook feedback"):
        return "stophook", t[19:60]
    if d.get("turnOrigin") == "scheduled" or d.get("scheduledTaskId"):
        return "scheduled", ""
    if t.startswith("Goal check-in"):
        return "goalcheck", ""
    if d.get("isMeta"):
        return None
    if (
        ok == "human"
        or d.get("promptSource") in ("typed", "queued")
        or t.startswith("<command-name>")
    ):
        return "human", t[:40]
    if not t or t.startswith(("<bash-", "<local-command")):
        return None
    return "other", t[:40]


reqs = {}
files = []
xfile = 0
xkind = 0
nb = 0
nrec = 0
tl = collections.defaultdict(list)
skipped_sessions = set()
kept_sessions = set()
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.endswith(".jsonl"):
            continue
        p = os.path.join(dp, f)
        try:
            st = os.stat(p)
        except OSError:
            continue
        if st.st_mtime < CUT:
            continue
        rel = os.path.relpath(p, root).split(os.sep)
        sub = "subagents" in rel
        sid = rel[1] if sub and len(rel) > 2 else f[:-6]
        if not keep(sid):
            skipped_sessions.add(sid)
            continue
        kept_sessions.add(sid)
        kind = ("wf" if "workflows" in rel else "sub") if sub else "main"
        fi = len(files)
        files.append((p, kind, sid))
        nb += st.st_size
        with open(p, "rb") as fh:
            for line in fh:
                if not (
                    b'"type":"assistant"' in line
                    or (not sub and b'"type":"user"' in line)
                ):
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                ty = d.get("type")
                if ty == "assistant":
                    m = d.get("message") or {}
                    u = m.get("usage")
                    mid = m.get("id") or d.get("requestId")
                    if not u or not mid or m.get("model") == "<synthetic>":
                        continue
                    t = ts(d.get("timestamp", ""))
                    if t is None or t < CUT:
                        continue
                    nrec += 1
                    tools = [
                        x.get("name")
                        for x in (m.get("content") or [])
                        if isinstance(x, dict) and x.get("type") == "tool_use"
                    ]
                    r = reqs.get(mid)
                    if r is not None:
                        r[5] = max(r[5], u.get("output_tokens", 0) or 0)
                        if tools:
                            r[10] = r[10] + tools
                        if r[8] != fi:
                            xfile += 1
                            if files[r[8]][1] != kind:
                                xkind += 1
                        continue
                    cc1 = (u.get("cache_creation") or {}).get(
                        "ephemeral_1h_input_tokens", 0
                    ) or 0
                    reqs[mid] = [
                        t,
                        u.get("input_tokens", 0) or 0,
                        u.get("cache_creation_input_tokens", 0) or 0,
                        cc1,
                        u.get("cache_read_input_tokens", 0) or 0,
                        u.get("output_tokens", 0) or 0,
                        kind,
                        sid,
                        fi,
                        bool(d.get("isSidechain")),
                        tools,
                        m.get("model"),
                    ]
                elif ty == "user" and not sub:
                    ct = (d.get("message") or {}).get("content")
                    if isinstance(ct, list):
                        if any(
                            isinstance(x, dict) and x.get("type") == "tool_result"
                            for x in ct
                        ):
                            continue
                        txt = " ".join(
                            x.get("text", "")
                            for x in ct
                            if isinstance(x, dict) and x.get("type") == "text"
                        )
                    else:
                        txt = ct if isinstance(ct, str) else ""
                    t = ts(d.get("timestamp", ""))
                    if t is None:
                        continue
                    c = ucls(d, txt)
                    if c:
                        tl[sid].append((t, c[0], c[1]))
out = {
    "reqs": list(reqs.values()),
    "files": files,
    "tl": dict(tl),
    "xfile_dup_records": xfile,
    "xkind_dup_records": xkind,
    "bytes": nb,
    "records": nrec,
    "kept_sessions": len(kept_sessions),
    "skipped_sessions": len(skipped_sessions),
    "sample_mod": sample_mod,
}
pickle.dump(out, open(f"/tmp/usage-audit/skeptic-lp/{acct}.pkl", "wb"))
print(
    acct,
    "DONE files",
    len(files),
    "GB %.2f" % (nb / 1e9),
    "records",
    nrec,
    "deduped",
    len(reqs),
    "xfile",
    xfile,
    "xkind",
    xkind,
    "sessions kept",
    len(kept_sessions),
    "skipped",
    len(skipped_sessions),
    flush=True,
)
