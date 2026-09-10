#!/usr/bin/env python3
"""The PROPOSED algorithm, measured: a bounded, read-back-VERIFIED scrub.

  repeat up to N rounds:  send Ctrl-U; re-read composer; if unchanged, send BS
  succeed only when the composer reads EMPTY; otherwise refuse (never guess)

Reports rounds consumed per payload shape, so the bound can be set from data.
"""
import os, sys, pty, select, time, signal, subprocess, fcntl, termios, struct
import pyte
COLS, ROWS = 100, 30
BORDER = "─" * 12
PAYLOADS = [
    ("short-1line", "SCRUBPROBEXYZ short single line payload"),
    ("multiline-3", "SCRUBPROBEXYZ line one\nline two here\nline three tail"),
    ("multiline-8", "SCRUBPROBEXYZ l1\n" + "\n".join("payload line %d" % i for i in range(2, 9))),
    ("big-chip",    "SCRUBPROBEXYZ " + "\n".join("condition line %02d of a long goal payload" % i for i in range(1, 26))),
    ("goal-1line",  "/goal land item 1ea55b6ad9f3 - proven by the bats suite; do not force-push"),
]
def composer(s):
    lines = [l.rstrip() for l in s.display]
    idx = [i for i, l in enumerate(lines) if BORDER in l]
    if len(idx) < 2: return None
    b1, b2 = idx[-1], idx[-2]
    if b1 - b2 < 2: return None
    body = "".join(lines[b2+1:b1])
    return "".join("".join(c for c in body if 32 <= ord(c) < 127).split())
def drain(fd, st, sec):
    end = time.time() + sec
    while time.time() < end:
        r,_,_ = select.select([fd],[],[],0.15)
        if not r: continue
        try: d = os.read(fd, 65536)
        except OSError: return
        if not d: return
        st.feed(d.decode("utf-8","replace"))
def run(binary, cfg, cwd, label, payload, maxrounds):
    sc = pyte.Screen(COLS, ROWS); st = pyte.Stream(sc)
    env = dict(os.environ); env.pop("CLAUDE_CODE_CHILD_SESSION", None)
    env["CLAUDE_CONFIG_DIR"]=cfg; env["TERM"]="xterm-256color"
    env["COLUMNS"],env["LINES"]=str(COLS),str(ROWS)
    pid, fd = pty.fork()
    if pid==0:
        os.chdir(cwd); os.execve(binary,[binary,"--permission-mode","plan"],env)
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH",ROWS,COLS,0,0))
        t0=time.time()
        while time.time()-t0 < 45:
            drain(fd, st, 1.0)
            if composer(sc)=="": break
        else: return (label,"NO-COMPOSER",-1,None)
        os.write(fd, b"\x1b[200~"+payload.encode()+b"\x1b[201~")
        drain(fd, st, 3.0)
        before = composer(sc)
        if not before: return (label,"PASTE-NOT-VISIBLE",-1,None)
        prev = before
        for rnd in range(1, maxrounds+1):
            os.write(fd, b"\x15")
            drain(fd, st, 1.2)
            cur = composer(sc)
            if cur == "":
                os.write(fd, b"Z"); drain(fd, st, 1.2)
                return (label, before, rnd, "CLEARS" if composer(sc)=="Z" else "FALSE-EMPTY")
            if cur == prev:                       # Ctrl-U made no progress: eat the newline
                os.write(fd, b"\x7f")
                drain(fd, st, 1.2)
                cur = composer(sc)
                if cur == "":
                    os.write(fd, b"Z"); drain(fd, st, 1.2)
                    return (label, before, rnd, "CLEARS" if composer(sc)=="Z" else "FALSE-EMPTY")
            prev = cur
        return (label, before, maxrounds, "REFUSE(not-empty:%s)" % str(prev)[:24])
    finally:
        try: os.kill(pid, signal.SIGKILL); os.waitpid(pid,0)
        except Exception: pass
        try: os.close(fd)
        except Exception: pass
def main():
    b,c,w = sys.argv[1],sys.argv[2],sys.argv[3]
    mx = int(sys.argv[4]) if len(sys.argv)>4 else 12
    ver = subprocess.run([b,"--version"],capture_output=True,text=True).stdout.strip()
    print("### %s   bounded verify-scrub, max %d rounds" % (ver, mx))
    print("%-13s %-36s %-7s %s" % ("payload","composer BEFORE","rounds","verdict"))
    for lab,pl in PAYLOADS:
        l,bf,r,v = run(b,c,w,lab,pl,mx)
        print("%-13s %-36s %-7s %s" % (l,str(bf)[:35],r,v)); sys.stdout.flush()
main()
