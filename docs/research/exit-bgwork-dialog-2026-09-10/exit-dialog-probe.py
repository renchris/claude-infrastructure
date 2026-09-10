#!/usr/bin/env python3
"""Does /exit raise the background-work dialog, and which option actually EXITS?

  arm "control"  no background work  -> /exit must exit (the negative arm: an
                                        instrument that cannot see a clean exit
                                        cannot say anything about a blocked one)
  arm "1" / "2"  start a background shell, /exit, answer with that key
  arm "none"     start a background shell, /exit, answer nothing (the incident)

Prints: DIALOG=yes|no  EXITED=yes|no  plus the dialog's rendered lines.
"""
import os, sys, pty, select, time, signal, fcntl, termios, struct
import pyte
COLS, ROWS = 100, 34
BORDER = "─" * 12
HDR = "Background work is running"

def screen_text(sc):
    return "\n".join(l.rstrip() for l in sc.display)

def composer(sc):
    lines = [l.rstrip() for l in sc.display]
    idx = [i for i, l in enumerate(lines) if BORDER in l]
    if len(idx) < 2: return None
    b1, b2 = idx[-1], idx[-2]
    if b1 - b2 < 2: return None
    body = "".join(lines[b2+1:b1])
    return "".join("".join(c for c in body if 32 <= ord(c) < 127).split())

def drain(fd, st, sec):
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.15)
        if not r: continue
        try: d = os.read(fd, 65536)
        except OSError: return "eof"
        if not d: return "eof"
        st.feed(d.decode("utf-8", "replace"))
    return "ok"

def alive(pid):
    try:
        p, _ = os.waitpid(pid, os.WNOHANG)
        return p == 0
    except ChildProcessError:
        return False

def run(binary, cfg, cwd, arm):
    sc = pyte.Screen(COLS, ROWS); st = pyte.Stream(sc)
    env = dict(os.environ)
    for k in ("CLAUDE_CODE_CHILD_SESSION", "ITERM_SESSION_ID", "KITTY_WINDOW_ID", "CC_PANE_ID"):
        env.pop(k, None)
    env["CLAUDE_CONFIG_DIR"] = cfg; env["TERM"] = "xterm-256color"
    env["COLUMNS"], env["LINES"] = str(COLS), str(ROWS)
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execve(binary, [binary], env)
    out = {"arm": arm, "dialog": "no", "exited": "no", "note": "", "screen": ""}
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        t0 = time.time()
        while time.time() - t0 < 120:
            drain(fd, st, 1.0)
            if composer(sc) == "": break
        else:
            out["note"] = "never reached an empty composer"; return out
        if arm != "control":
            msg = ("Use the Bash tool with run_in_background set to true to run exactly this "
                   "command: sleep 600 . Do nothing else and reply with the single word STARTED.")
            os.write(fd, b"\x1b[200~" + msg.encode() + b"\x1b[201~")
            drain(fd, st, 1.5); os.write(fd, b"\r")
            t1 = time.time(); started = False
            while time.time() - t1 < 240:
                drain(fd, st, 2.0)
                txt = screen_text(sc)
                if "STARTED" in txt and composer(sc) == "":
                    started = True; break
            if not started:
                out["note"] = "background task never confirmed started"
                out["screen"] = screen_text(sc); return out
            drain(fd, st, 3.0)
        os.write(fd, b"/exit"); drain(fd, st, 1.5); os.write(fd, b"\r")
        drain(fd, st, 6.0)
        txt = screen_text(sc)
        out["dialog"] = "yes" if HDR in txt else "no"
        out["screen"] = txt
        if arm in ("1", "2", "3"):
            os.write(fd, arm.encode())
            drain(fd, st, 8.0)
            time.sleep(0.5)
            if not alive(pid):
                out["note"] = "digit alone EXITED"
            else:
                out["note"] = "digit alone did NOT exit; sending CR"
                out["screen_after_digit"] = screen_text(sc)
                os.write(fd, b"\r")
                drain(fd, st, 10.0)
            out["screen"] = screen_text(sc)
        else:
            drain(fd, st, 8.0)
        time.sleep(1.0)
        out["exited"] = "no" if alive(pid) else "yes"
        return out
    finally:
        try: os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0)
        except Exception: pass
        try: os.close(fd)
        except Exception: pass

if __name__ == "__main__":
    b, c, w, arm = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    r = run(b, c, w, arm)
    print("ARM=%s DIALOG=%s EXITED=%s NOTE=%s" % (r["arm"], r["dialog"], r["exited"], r["note"]))
    print("---- screen ----"); print(r["screen"])
