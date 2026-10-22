import json, os, pty, select, struct, fcntl, termios, time, pyte
CLAUDE = os.path.expanduser("~/.claude-293/node_modules/.bin/claude")
settings = {"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "/tmp/abb-order/hook.sh"}]}]}}
args = [CLAUDE, "--setting-sources", "project", "--settings", json.dumps(settings), "--model", "claude-haiku-5-5", "--plugin-dir", "/tmp/abb-order/mod"]
pid, fd = pty.fork()
if pid == 0:
    os.chdir("/tmp/abb-probe/work"); os.environ["TERM"] = "xterm-256color"
    for k in ("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID"): os.environ.pop(k, None)
    os.execv(CLAUDE, args)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 120, 0, 0))
scr = pyte.Screen(120, 50); st = pyte.ByteStream(scr)
def pump(s):
    t = time.time()
    while time.time() - t < s:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return
            if not d: return
            st.feed(d)
pump(8)
if "trust this folder" in "\n".join(scr.display): os.write(fd, b"\x1b[B"); pump(0.5); os.write(fd, b"\r"); pump(8)
open("/tmp/abb-order/out/screen.txt", "w").write("\n".join(l.rstrip() for l in scr.display))
os.write(fd, b"\x03"); pump(0.5); os.write(fd, b"\x03"); pump(1)
try: os.kill(pid, 9)
except OSError: pass
os.waitpid(pid, 0)
