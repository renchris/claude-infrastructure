import json,os,glob
def texts(rec):
    m = rec.get("message") or {}
    c = m.get("content")
    if isinstance(c, str): yield c
    elif isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type")=="text": yield b.get("text","")
def scan(pat_glob, needles):
    for p in glob.glob(os.path.expanduser(pat_glob)):
        for n in needles:
            with open(p, errors="replace") as f:
                for i,line in enumerate(f,1):
                    try: rec=json.loads(line)
                    except Exception: continue
                    if rec.get("type") not in ("user","assistant"): continue
                    for t in texts(rec):
                        if n.lower() in t.lower():
                            k=t.lower().find(n.lower())
                            print(os.path.basename(p)[:8], p.split('/')[3][:14], i, rec.get("type"), rec.get("timestamp"), '|', t[max(0,k-200):k+200].replace("\n"," "))
                            break
scan("~/.claude*/projects/*/7f533f05*.jsonl", ["waves are built", "session's* state", "described my session"])
scan("~/.claude*/projects/*/61853387*.jsonl", ["killing and restarting", "Killed and relaunched"])
