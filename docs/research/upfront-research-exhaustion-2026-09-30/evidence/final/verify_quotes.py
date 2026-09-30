import json,sys,os
checks = [
 ("~/.claude-quaternary/projects/-Users-chrisren-Development--worktrees-wt-cc-143333-63422/7f533f05-91fa-42d0-89ef-cd7976c423d5.jsonl", ["safe to close", "0 of 7 waves"]),
 ("~/.claude-quaternary/projects/-Users-chrisren-Development-voiceink/ba08cab8-7b28-438a-a981-61c101a5c080.jsonl", ["not the shape of a converging", "10 → 7 → 2", "Do you deem it 100.00"]),
 ("~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/989f6dbf-0216-45d0-a061-f998c29ab27c.jsonl", ["nobody has re-read the finished document", "no take-backs", "One check remains"]),
 ("~/.claude-next/projects/-Users-chrisren-Development-reso-web-app/5245ce63-eb3a-4037-91e2-a8e38b3bf6d8.jsonl", ["Correcting my earlier", "instead of recalling it"]),
 ("~/.claude-quaternary/projects/-Users-chrisren-Development-claude-infrastructure/7c395da7-fbbe-4123-8bd5-2456787d12c3.jsonl", ["Each fix adds more machinery", "23"]),
 ("~/.claude-quaternary/projects/-Users-chrisren-Development-voiceink/61853387-c813-4727-83f9-2139b1e2b36d.jsonl", ["ALWAYS fix until 100.00", "worth killing and restarting"]),
]
def texts(rec):
    m = rec.get("message") or {}
    c = m.get("content")
    if isinstance(c, str): yield c
    elif isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type")=="text": yield b.get("text","")
for path, needles in checks:
    p=os.path.expanduser(path)
    for n in needles:
        hits=[]
        with open(p, errors="replace") as f:
            for i,line in enumerate(f,1):
                try: rec=json.loads(line)
                except Exception: continue
                if rec.get("type") not in ("user","assistant"): continue
                for t in texts(rec):
                    if n in t:
                        k=t.find(n)
                        hits.append((i, rec.get("type"), rec.get("timestamp"), t[max(0,k-160):k+220].replace("\n"," ")))
                        break
        print("##", os.path.basename(p)[:8], repr(n), "hits", len(hits))
        for h in hits[:2]: print("   ", h)
