# Measure what a real self-recycle turn costs: for every main-session tool_use whose Bash command runs
# handoff-fire.sh with --recycle (not --dry-run), count the requests and output tokens from the turn
# start (last non-tool_result user record) up to and including that request. Streaming, read-only.
import json, os, statistics, sys
from datetime import datetime
S, E = (float(x) for x in open("/tmp/usage-audit/w4/window").read().split())
def ts(s):
    try: return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception: return None
res = []
for acct in (".claude-next", ".claude-secondary", ".claude-tertiary", ".claude-quaternary"):
    root = os.path.expanduser("~/" + acct + "/projects")
    for dp, dn, fn in os.walk(root, followlinks=True):
        if "/subagents" in dp: continue
        for f in fn:
            if not f.endswith(".jsonl"): continue
            p = os.path.join(dp, f)
            try:
                if os.stat(p).st_mtime < S: continue
                fh = open(p, "rb")
            except OSError: continue
            reqs = {}; order = []; opener_ts = None
            with fh:
                for line in fh:
                    head = line[:1500]
                    if b'"type":"user"' in head:
                        if b'"tool_result"' not in line:
                            reqs = {}; order = []
                        continue
                    if b'"assistant"' not in head or b'"usage"' not in line: continue
                    try: r = json.loads(line)
                    except Exception: continue
                    if r.get("type") != "assistant" or r.get("isSidechain"): continue
                    m = r.get("message") or {}; u = m.get("usage") or {}
                    k = r.get("requestId") or m.get("id")
                    ctx = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
                    if k not in reqs:
                        reqs[k] = [ctx, 0, u.get("cache_creation_input_tokens") or 0]; order.append(k)
                    reqs[k][1] = max(reqs[k][1], u.get("output_tokens") or 0)
                    for b in m.get("content") or []:
                        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Bash":
                            c = str((b.get("input") or {}).get("command", ""))
                            if "handoff-fire" in c and "--recycle" in c and "--dry-run" not in c and "--source-pane" not in c:
                                t = ts(r.get("timestamp", ""))
                                if t and S <= t <= E:
                                    L = [reqs[x] for x in order]
                                    res.append((len(L), sum(x[1] for x in L), L[0][0], sum(x[2] for x in L)))
print("self-recycle calls in window: %d" % len(res))
if res:
    n = [x[0] for x in res]; o = [x[1] for x in res]; c0 = [x[2] for x in res]; w = [x[3] for x in res]
    q = lambda v, pc: sorted(v)[min(len(v) - 1, int(pc * len(v)))]
    print("requests in the recycling turn: median %d p25 %d p75 %d p90 %d" % (statistics.median(n), q(n, .25), q(n, .75), q(n, .9)))
    print("output tokens in that turn: median %d p90 %d" % (statistics.median(o), q(o, .9)))
    print("cache-write tokens in that turn: median %d p90 %d" % (statistics.median(w), q(w, .9)))
    print("context at the turn's first request: median %d" % statistics.median(c0))
