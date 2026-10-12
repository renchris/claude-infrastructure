import ctypes, ctypes.util, subprocess, time, re, os, collections
t0=time.time()
pids=[int(x) for x in subprocess.run(["pgrep","-x","claude.exe|claude|node"],capture_output=True,text=True,timeout=20).stdout.split()]
t1=time.time()
libc=ctypes.CDLL(ctypes.util.find_library("c"),use_errno=True)
CTL_KERN,KERN_ARGMAX,KERN_PROCARGS2=1,8,49
def argmax():
    mib=(ctypes.c_int*2)(CTL_KERN,KERN_ARGMAX); v=ctypes.c_int(); sz=ctypes.c_size_t(4)
    libc.sysctl(mib,2,ctypes.byref(v),ctypes.byref(sz),None,0); return v.value
AM=argmax()
def procargs(pid):
    mib=(ctypes.c_int*3)(CTL_KERN,KERN_PROCARGS2,pid); buf=ctypes.create_string_buffer(AM); sz=ctypes.c_size_t(AM)
    if libc.sysctl(mib,3,buf,ctypes.byref(sz),None,0)!=0: return None
    raw=buf.raw[:sz.value]; argc=int.from_bytes(raw[:4],"little"); parts=[p for p in raw[4:].split(b"\0") if p]
    return argc, [p.decode("utf-8","replace") for p in parts]
c=collections.Counter(); n=0; fail=0
for p in pids:
    r=procargs(p)
    if r is None: fail+=1; continue
    argc,parts=r; exe,argv,env=parts[0],parts[1:1+argc],parts[1+argc:]
    a0=argv[0] if argv else ""
    if not (a0=="claude" or a0.endswith("/claude") or a0.endswith("claude.exe")): continue
    head=[t for t in argv[1:7] if t.startswith("-")]
    kind="headless" if ("-p" in head or "--print" in head) else "interactive"
    d=next((e.split("=",1)[1] for e in reversed(env) if e.startswith("CLAUDE_CONFIG_DIR=")),"~/.claude")
    c[(os.path.basename(d.rstrip("/")),kind)]+=1; n+=1
t2=time.time()
print(f"pgrep {len(pids)} pids in {t1-t0:.2f}s; procargs2 for all in {t2-t1:.2f}s; claude={n} fail={fail}")
for k,v in sorted(c.items()): print(v,k)
