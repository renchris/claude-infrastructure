# Variant of selfrecycle_cost.py that also records the turn's opener, to split recycle-only turns
# (opener is a /handoff command) from work turns that end in a recycle. Read-only, streaming.
import json, os, statistics
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
            reqs = {}; order = []; opener = ""
            with fh:
                for line in fh:
                    head = line[:1500]
                    if b'"type":"user"' in head:
                        if b'"tool_result"' not in line:
                            reqs = {}; order = []
                            try:
                                r = json.loads(line); c = (r.get("message") or {}).get("content")
                                if isinstance(c, list): c = " ".join(b.get("text", "") for b in c if isinstance(b, dict))
                                opener = (c or "")[:300] if isinstance(c, str) else ""
                            except Exception: opener = ""
                        continue
                    if b'"assistant"' not in head or b'"usage"' not in line: continue
                    try: r = json.loads(line)
                    except Exception: continue
                    if r.get("type") != "assistant" or r.get("isSidechain"): continue
                    m = r.get("message") or {}; u = m.get("usage") or {}
                    k = r.get("requestId") or m.get("id")
                    if k not in reqs:
                        reqs[k] = [0, 0]; order.append(k)
                    reqs[k][1] = max(reqs[k][1], u.get("output_tokens") or 0)
                    for b in m.get("content") or []:
                        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Bash":
                            c = str((b.get("input") or {}).get("command", ""))
                            if "handoff-fire" in c and "--recycle" in c and "--dry-run" not in c and "--source-pane" not in c:
                                t = ts(r.get("timestamp", ""))
                                if t and S <= t <= E:
                                    L = [reqs[x] for x in order]
                                    kind = "handoff-cmd" if "<command-name>/handoff" in opener else ("hook" if opener.startswith(("Stop hook feedback", "⟳", "⚑", "⚠", "<task-notification")) else "other")
                                    res.append((kind, len(L), sum(x[1] for x in L)))
for kind in ("handoff-cmd", "hook", "other", "all"):
    v = [x for x in res if kind == "all" or x[0] == kind]
    if not v: continue
    n = [x[1] for x in v]; o = [x[2] for x in v]
    print("%-12s calls %3d  requests median %s  output median %s" % (kind, len(v), statistics.median(n), statistics.median(o)))
