import json, sys, collections, glob, os
c = collections.Counter()
files = sorted(glob.glob(os.path.expanduser("~/.claude-tertiary/projects/*/*.jsonl")), key=os.path.getmtime)[-60:]
files += sorted(glob.glob(os.path.expanduser("~/.claude-tertiary/projects/*/*/subagents/**/*.jsonl"), recursive=True), key=os.path.getmtime)[-200:]
for p in files:
    kind = "s" if "/subagents/" in p else "m"
    seen = set()
    for l in open(p, "rb"):
        if b'"assistant"' not in l or b'"usage"' not in l: 
            if b'"permissionMode"' in l:
                try: c[(kind, "permMode", json.loads(l).get("permissionMode"))] += 1
                except Exception: pass
            continue
        r = json.loads(l); m = r.get("message") or {}
        k = r.get("requestId")
        if k in seen: continue
        seen.add(k)
        c[(kind, "entry", r.get("entrypoint"))] += 1
        c[(kind, "clf", bool(r.get("serverClassifierRequest")))] += 1
        c[(kind, "stop", m.get("stop_reason"))] += 1
for k, v in sorted(c.items(), key=str): print(k, v)
