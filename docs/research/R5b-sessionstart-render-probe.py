import os,pty,sys,time,select
P=sys.argv[1]
pid,fd=pty.fork()
if pid==0:
    os.chdir(P)
    os.environ["CLAUDE_CONFIG_DIR"]=os.path.expanduser("~/.claude-tertiary")
    os.environ["TERM"]="xterm-256color"
    os.execv(os.path.expanduser("~/.claude-220/node_modules/.bin/claude"),
             [os.path.expanduser("~/.claude-220/node_modules/.bin/claude"),
              "--setting-sources","project","--model","claude-haiku-4-5-20251001"])
buf=b""; t0=time.time()
while time.time()-t0 < 14:
    r,_,_=select.select([fd],[],[],0.4)
    if r:
        try: d=os.read(fd,65536)
        except OSError: break
        if not d: break
        buf+=d
os.write(fd,b"\x03"); time.sleep(0.4); os.write(fd,b"\x03"); time.sleep(0.6)
try:
    while True:
        r,_,_=select.select([fd],[],[],0.3)
        if not r: break
        d=os.read(fd,65536)
        if not d: break
        buf+=d
except OSError: pass
os.kill(pid,9); os.waitpid(pid,0)
open(P+"/pty.out","wb").write(buf)
for m in (b"ZZTOPLEVELZZ",b"ZZNESTEDZZ",b"ZZADDCTXZZ"):
    print(m.decode(), "RENDERED" if m in buf else "absent", "count=",buf.count(m))
print("alt-screen ESC[?1049h:", buf.count(b"\x1b[?1049h"))
