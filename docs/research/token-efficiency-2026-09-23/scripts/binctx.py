#!/usr/bin/env python3
"""binctx.py PATTERN [radius] [maxhits] — print +-radius bytes around each (deduped) occurrence of PATTERN in the CC 2.1.280 binary. Read-only."""
import sys,re
B='/Users/chrisren/.claude-280/node_modules/@anthropic-ai/claude-code/bin/claude.exe'
data=open(B,'rb').read()
pat=sys.argv[1].encode(); r=int(sys.argv[2]) if len(sys.argv)>2 else 600; mx=int(sys.argv[3]) if len(sys.argv)>3 else 5
seen=set(); n=0; i=0; total=data.count(pat)
print(f"# total occurrences: {total}")
while n<mx:
    i=data.find(pat,i)
    if i<0: break
    s=data[max(0,i-r):i+r]
    h=hash(s[r-100:r+100])
    if h not in seen:
        seen.add(h); n+=1
        print(f"==== @{i} ====")
        print(s.decode('utf-8','replace'))
    i+=len(pat)
