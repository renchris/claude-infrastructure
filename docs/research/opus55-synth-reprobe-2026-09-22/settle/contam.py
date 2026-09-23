import json, glob, os, sys
W = sys.argv[1]
labels = {}
for l in open(os.path.join(W, "journal.jsonl")):
    r = json.loads(l)
    if r.get("type") == "started": labels[r["agentId"]] = r.get("label")
for f in sorted(glob.glob(os.path.join(W, "agent-*.jsonl"))):
    aid = os.path.basename(f)[6:-6]; lab = labels.get(aid, aid)
    if not (str(lab).startswith("arm:") or str(lab).startswith("rerun:")): continue
    raw = open(f).read()
    hits = raw.count("opus55-synth-reprobe")
    outside = []; nbash = 0
    for l in raw.splitlines():
        r = json.loads(l)
        if r.get("type") != "assistant": continue
        for c in (r.get("message") or {}).get("content") or []:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                inp = json.dumps(c.get("input"))
                if c.get("name") == "Bash": nbash += 1
                if "/Users/" in inp or "claude-infrastructure" in inp or "~/" in inp or "$HOME" in inp:
                    outside.append((c.get("name"), inp[:160]))
    print(f"{lab:32s} key-string={hits} bash={nbash} outside-snapshot={len(outside)}")
    for o in outside: print("     ", o)
