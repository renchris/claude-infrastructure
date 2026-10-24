import json, sys, re
CUT="2026-09-29T00:00:00Z"
for line in open(sys.argv[1], encoding="utf-8"):
    r=json.loads(line)
    if r["ts"]>=CUT or r.get("decision")!="ask" or "confirm intent" not in (r.get("reason") or ""): continue
    rm=r["reason"].split(" ",1)[0]
    h=r.get("host")
    if rm!=r.get("method") or h in ("mozilla","$h","research-agent",None,"unknown-host.example.org") or not h or "." not in h and h not in ("localhost",):
        print(r["ts"], "|", r.get("method"), "|", h, "|", r["reason"][:70], "|", r["cmd_redacted"][:230].replace("\n"," "))
