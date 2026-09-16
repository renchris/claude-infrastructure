# Sample pane titles fast over the RC socket directly (one connection, no process spawns).
import socket, json, time, sys, collections
SOCK='/tmp/kitty-597'
def rc(cmd):
    s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(3); s.connect(SOCK)
    payload=b'\x1bP@kitty-cmd'+json.dumps(cmd).encode()+b'\x1b\\'
    s.sendall(payload)
    buf=b''
    while b'\x1b\\' not in buf:
        d=s.recv(65536)
        if not d: break
        buf+=d
    s.close()
    i=buf.find(b'@kitty-cmd'); j=buf.find(b'\x1b\\', i)
    return json.loads(buf[i+len('@kitty-cmd'):j].decode())
hist=collections.defaultdict(list)
N=int(sys.argv[1]); DT=float(sys.argv[2])
t0=time.time()
for k in range(N):
    r=rc({"cmd":"ls","version":[0,48,2],"no_response":False,"payload":{}})
    data=r.get('data')
    d=json.loads(data) if isinstance(data,str) else data
    for osw in d:
        for tab in osw['tabs']:
            for w in tab['windows']:
                hist[w['id']].append(w.get('title'))
    time.sleep(DT)
dur=time.time()-t0
print("sampled %d times over %.2fs (%.0f ms interval)"%(N,dur,dur/N*1000))
for wid,titles in sorted(hist.items()):
    ch=sum(1 for a,b in zip(titles,titles[1:]) if a!=b)
    print("  win %-4s %2d changes / %.2fs = %5.2f title-changes/s  distinct=%d  e.g. %r"%(
        wid, ch, dur, ch/dur, len(set(titles)), titles[0][:36]))
