#!/usr/bin/env python3
"""W7c STEP 0: what background work does the exit dialog count at a self-recycle's /exit?

Arms (each a fresh, throwaway Claude Code under a PTY, rendered with pyte):
  control   idle session, /exit                       -> must exit with no dialog
  fgbash    a FOREGROUND Bash `sleep 45` in flight, /exit typed mid-call (the self-recycle shape)
  fgdone    same, but /exit typed only after the Bash call has RETURNED and the turn has ended
  bgbash    a run_in_background `sleep 600`, idle, /exit

Usage: probe.py <claude-binary> <config-dir> <cwd> <arm> <agent_view: off|on>
Prints DIALOG=yes|no EXITED=yes|no and the full rendered screen at the /exit.
"""

import os, sys, pty, select, time, signal, fcntl, termios, struct
import pyte

COLS, ROWS = 110, 40
BORDER = "─" * 12
HDR = "Background work is running"


def screen_text(sc):
    return "\n".join(l.rstrip() for l in sc.display)


def composer(sc):
    lines = [l.rstrip() for l in sc.display]
    idx = [i for i, l in enumerate(lines) if BORDER in l]
    if len(idx) < 2:
        return None
    b1, b2 = idx[-1], idx[-2]
    if b1 - b2 < 2:
        return None
    body = "".join(lines[b2 + 1 : b1])
    t = "".join("".join(c for c in body if 32 <= ord(c) < 127).split()).lstrip(">")
    if t.startswith('Try"'):
        return ""  # 2.1.284 renders a placeholder in an empty composer
    return t


def drain(fd, st, sec):
    end = time.time() + sec
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.15)
        if not r:
            continue
        try:
            d = os.read(fd, 65536)
        except OSError:
            return "eof"
        if not d:
            return "eof"
        st.feed(d.decode("utf-8", "replace"))
    return "ok"


def alive(pid):
    try:
        p, _ = os.waitpid(pid, os.WNOHANG)
        return p == 0
    except ChildProcessError:
        return False


def call_in_flight(root):
    """Is a `bash wait45.sh` running anywhere under the claude pid? Returns its pid or None."""
    import subprocess

    rows = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,args="], capture_output=True, text=True
    ).stdout
    kids, args = {}, {}
    for ln in rows.splitlines():
        parts = ln.split(None, 2)
        if len(parts) < 2:
            continue
        pid, ppid = int(parts[0]), int(parts[1])
        kids.setdefault(ppid, []).append(pid)
        args[pid] = parts[2] if len(parts) > 2 else ""
    todo, seen = [root], set()
    while todo:
        p = todo.pop()
        for c in kids.get(p, []):
            if c in seen:
                continue
            seen.add(c)
            todo.append(c)
            if "wait45.sh" in args.get(c, "") and "zsh" not in args.get(c, ""):
                return c
    return None


def send_prompt(fd, st, msg):
    os.write(fd, b"\x1b[200~" + msg.encode() + b"\x1b[201~")
    drain(fd, st, 1.5)
    os.write(fd, b"\r")


def run(binary, cfg, cwd, arm, view):
    sc = pyte.Screen(COLS, ROWS)
    st = pyte.Stream(sc)
    env = dict(os.environ)
    for k in (
        "CLAUDE_CODE_CHILD_SESSION",
        "ITERM_SESSION_ID",
        "KITTY_WINDOW_ID",
        "CC_PANE_ID",
        "CLAUDE_CODE_SESSION_ID",
        "CLAUDE_CODE_DISABLE_AGENT_VIEW",
    ):
        env.pop(k, None)
    if view == "off":
        env["CLAUDE_CODE_DISABLE_AGENT_VIEW"] = "1"
    env["CLAUDE_CONFIG_DIR"] = cfg
    env["TERM"] = "xterm-256color"
    env["COLUMNS"], env["LINES"] = str(COLS), str(ROWS)
    argv = [
        binary,
        "--model",
        "haiku",
        "--settings",
        '{"disableAllHooks":true}',
        "--allowedTools",
        "Bash(sleep:*)",
        "--allowedTools",
        "Bash(bash wait45.sh)",
    ]
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execve(binary, argv, env)
    out = {
        "arm": arm,
        "view": view,
        "dialog": "no",
        "exited": "no",
        "note": "",
        "screen": "",
    }
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        t0 = time.time()
        trusted = False
        while time.time() - t0 < 150:
            drain(fd, st, 1.0)
            txt = screen_text(sc)
            if not trusted and ("trust" in txt.lower() and "folder" in txt.lower()):
                os.write(fd, b"\r")
                trusted = True
                continue
            if composer(sc) == "":
                break
        else:
            out["note"] = "never reached an empty composer"
            out["screen"] = screen_text(sc)
            return out
        drain(fd, st, 2.0)
        if arm in ("fgbash", "fgdone"):
            send_prompt(
                fd,
                st,
                "Use the Bash tool (foreground, NOT run_in_background) to run exactly: "
                "bash wait45.sh (with a timeout of 120000 ms). After it returns reply with the single word RETURNED.",
            )
            t1 = time.time()
            seen = False
            while time.time() - t1 < 120:
                drain(fd, st, 1.0)
                cp = call_in_flight(pid)
                if cp:
                    out["call_pid"] = cp
                    seen = True
                    break
            if not seen:
                out["note"] = "the foreground Bash never appeared"
                out["screen"] = screen_text(sc)
                return out
            if arm == "fgbash":
                drain(fd, st, 5.0)  # well inside the 45 s call
                out["note"] = "exit typed %.0fs after the Bash call rendered" % 5
            else:
                t2 = time.time()
                done = False
                while time.time() - t2 < 150:
                    drain(fd, st, 2.0)
                    if "RETURNED" in screen_text(sc) and composer(sc) == "":
                        done = True
                        break
                if not done:
                    out["note"] = "the call never returned"
                    out["screen"] = screen_text(sc)
                    return out
                drain(fd, st, 3.0)
        elif arm == "bgbash":
            send_prompt(
                fd,
                st,
                "Use the Bash tool with run_in_background set to true to run exactly this "
                "command: sleep 600 . Do nothing else and reply with the single word STARTED.",
            )
            t1 = time.time()
            started = False
            while time.time() - t1 < 150:
                drain(fd, st, 2.0)
                if "STARTED" in screen_text(sc) and composer(sc) == "":
                    started = True
                    break
            if not started:
                out["note"] = "background task never confirmed started"
                out["screen"] = screen_text(sc)
                return out
            drain(fd, st, 3.0)
        out["pre_exit_screen"] = screen_text(sc)
        os.write(fd, b"/exit")
        drain(fd, st, 1.5)
        os.write(fd, b"\r")
        drain(fd, st, 6.0)
        txt = screen_text(sc)
        out["dialog"] = "yes" if HDR in txt else "no"
        out["screen"] = txt
        if arm == "fgbash" and out["dialog"] == "yes":
            # The shipped watcher's order: with the dialog STILL UP and nothing sent, wait for the
            # call to end; then Esc (Stay), clear our /exit if Esc left it, and /exit again at once.
            out["call_alive_at_dialog"] = call_in_flight(pid) is not None
            t3 = time.time()
            while time.time() - t3 < 120 and call_in_flight(pid):
                drain(fd, st, 1.0)
            out["call_ended_after_s"] = round(time.time() - t3)
            out["dialog_still_up_when_call_ended"] = HDR in screen_text(sc)
            out["returned_after_esc"] = "n/a (waited with dialog up)"
            os.write(fd, b"\x1b")
            drain(fd, st, 0.7)
            out["after_esc"] = screen_text(sc)
            c = composer(sc)
            out["composer_after_return"] = c
            if c:  # our first /exit may still sit there — clear it
                os.write(fd, b"\x7f" * 12)
                drain(fd, st, 1.0)
            os.write(fd, b"/exit")
            drain(fd, st, 1.5)
            os.write(fd, b"\r")
            drain(fd, st, 6.0)
            out["retype_screen"] = screen_text(sc)
            out["retype_dialog"] = "yes" if HDR in out["retype_screen"] else "no"
        drain(fd, st, 6.0)
        time.sleep(1.0)
        out["exited"] = "no" if alive(pid) else "yes"
        return out
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except Exception:
            pass
        try:
            os.close(fd)
        except Exception:
            pass


if __name__ == "__main__":
    b, c, w, arm, view = sys.argv[1:6]
    r = run(b, c, w, arm, view)
    print(
        "ARM=%s VIEW=%s DIALOG=%s EXITED=%s NOTE=%s"
        % (r["arm"], r["view"], r["dialog"], r["exited"], r["note"])
    )
    for k in ("call_pid", "call_alive_at_dialog", "call_ended_after_s", "dialog_still_up_when_call_ended", "composer_after_return", "retype_dialog"):
        if k in r:
            print("%s=%s" % (k.upper(), r[k]))
    for k in ("pre_exit_screen", "screen", "after_esc", "retype_screen"):
        if k in r:
            print("---- %s ----" % k)
            print(r[k])
