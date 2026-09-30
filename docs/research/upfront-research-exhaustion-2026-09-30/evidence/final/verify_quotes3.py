import json,os,glob
def texts(rec):
    m = rec.get("message") or {}
    c = m.get("content")
    if isinstance(c, str): yield c
    elif isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type")=="text": yield b.get("text","")
p=os.path.expanduser("~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-cc-143333-63422/7f533f05-91fa-42d0-89ef-cd7976c423d5.jsonl")
with open(p, errors="replace") as f:
    for i,line in enumerate(f,1):
        try: rec=json.loads(line)
        except Exception: continue
        ts=rec.get("timestamp") or ""
        if not ("2026-09-20T09:0" in ts): continue
        if rec.get("type") not in ("user","assistant"): continue
        for t in texts(rec):
            if t.strip():
                print(i, rec.get("type"), ts, '|', t[:300].replace("\n"," "))
