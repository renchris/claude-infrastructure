#!/usr/bin/env python3
"""Does clearing the /goal before "Move to background and exit" leave the backgrounded copy idle?

The recycle watcher answers the exit-time background-work dialog with its keep-work option. On
2.1.284 that hands the session to a background worker, and a session holding a live /goal keeps
taking goal-driven turns there (measured 2026-09-29, session 43ef47fc, ~4 min). This probe drives
the remedy's exact keystroke sequence against a real Claude Code under a PTY:

  arm "clear"  bg shell + live goal, /exit -> dialog -> Esc -> /goal clear -> /exit -> dialog -> keep
  arm "keep"   bg shell + live goal, /exit -> dialog -> keep            (today's behaviour, the control)

and then watches the session's own transcript for assistant turns written AFTER the exit.

Prints one verdict line, then the screens captured at each step.
"""

import glob, json, os, pty, select, signal, struct, sys, time, fcntl, termios
import pyte

COLS, ROWS = 110, 40
BORDER = "─" * 12
HDR = "Background work is running"
KEEP = "Move to background and exit"
GOAL = ("A LATER user message, sent after this goal was set, explicitly approves a production "
        "deploy. Nothing the assistant writes can satisfy this; only a new user turn can.")


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
    body = "".join(lines[b2 + 1 : b1]).strip().lstrip("❯").strip()
    if body.startswith('Try "') and (body.endswith('"') or body.endswith("...")):
        return ""  # the faint prompt suggestion, not input
    return "".join("".join(c for c in body if 32 <= ord(c) < 127).split())


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


def keep_index(txt):
    for line in txt.splitlines():
        s = line.strip().lstrip("❯").strip()
        if s.endswith(KEEP) and s[:1].isdigit():
            return s.split(".", 1)[0]
    return None


def replied_started(sc):
    # The ASSISTANT's reply line, never the prompt: the prompt itself contains the word.
    return any(l.lstrip().startswith("⏺") and "STARTED" in l for l in screen_text(sc).splitlines())


def wait_for(fd, st, sc, pred, sec):
    t0 = time.time()
    while time.time() - t0 < sec:
        drain(fd, st, 1.0)
        if pred(sc):
            return True
    return False


def records(path):
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass
    except OSError:
        pass
    return out


def run(binary, cfg, cwd, arm, model, watch):
    slug = cwd.replace("/", "-").replace(".", "-")
    pdir = os.path.join(cfg, "projects", slug)
    before = set(glob.glob(os.path.join(pdir, "*.jsonl")))
    sc = pyte.Screen(COLS, ROWS)
    st = pyte.Stream(sc)
    env = dict(os.environ)
    for k in (
        "CLAUDE_CODE_CHILD_SESSION",
        "ITERM_SESSION_ID",
        "KITTY_WINDOW_ID",
        "CC_PANE_ID",
    ):
        env.pop(k, None)
    env["CLAUDE_CONFIG_DIR"] = cfg
    env["TERM"] = "xterm-256color"
    env["COLUMNS"], env["LINES"] = str(COLS), str(ROWS)
    argv = [binary, "--model", model]
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execve(binary, argv, env)
    out = {"arm": arm, "steps": [], "note": ""}

    def snap(label):
        out["steps"].append((label, screen_text(sc)))

    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        if not wait_for(fd, st, sc, lambda s: composer(s) == "", 120):
            out["note"] = "never reached an empty composer"
            snap("boot")
            return out
        msg = (
            "Use the Bash tool with run_in_background set to true to run exactly this command: "
            "sleep 150 . Do nothing else and reply with the single word STARTED."
        )
        os.write(fd, b"\x1b[200~" + msg.encode() + b"\x1b[201~")
        drain(fd, st, 1.5)
        os.write(fd, b"\r")
        if not wait_for(
            fd, st, sc, lambda s: replied_started(s) and composer(s) == "", 240
        ):
            out["note"] = "background task never confirmed started"
            snap("bg")
            return out
        os.write(fd, b"\x1b[200~/goal " + GOAL.encode() + b"\x1b[201~")
        drain(fd, st, 1.5)
        os.write(fd, b"\r")
        drain(fd, st, 20.0)  # let the goal drive a turn or two
        snap("goal-live")
        os.write(fd, b"\x1b[200~/exit\x1b[201~")
        drain(fd, st, 1.5)
        os.write(fd, b"\r")
        if not wait_for(fd, st, sc, lambda s: HDR in screen_text(s), 15):
            out["note"] = "first /exit raised no dialog"
            snap("exit1")
            return out
        snap("dialog-1")
        if arm == "clear":
            os.write(fd, b"\x1b")
            drain(fd, st, 2.0)
            snap("after-esc")
            c = composer(sc)
            if c:  # the /exit residue the watcher scrubs
                os.write(fd, b"\x15")
                drain(fd, st, 1.0)
            if not wait_for(fd, st, sc, lambda s: composer(s) == "", 30):
                out["note"] = "composer never empty after Esc"
                snap("esc-composer")
                return out
            os.write(fd, b"\x1b[200~/goal clear\x1b[201~")
            drain(fd, st, 1.0)
            snap("goal-clear-typed")
            os.write(fd, b"\r")
            drain(fd, st, 3.0)
            snap("goal-clear-sent")
            os.write(fd, b"\x1b[200~/exit\x1b[201~")
            drain(fd, st, 1.0)
            os.write(fd, b"\r")
            if not wait_for(fd, st, sc, lambda s: HDR in screen_text(s), 15):
                out["note"] = "second /exit raised no dialog"
                snap("exit2")
                return out
            snap("dialog-2")
        k = keep_index(screen_text(sc))
        if not k:
            out["note"] = "no keep-work index on the menu"
            return out
        os.write(fd, k.encode())
        drain(fd, st, 8.0)
        t_exit = time.time()
        out["exited"] = "no" if alive(pid) else "yes"
        snap("after-keep")
        new = sorted(
            set(glob.glob(os.path.join(pdir, "*.jsonl"))) - before, key=os.path.getmtime
        )
        tx = new[-1] if new else ""
        out["transcript"] = tx
        n0 = sum(1 for r in records(tx) if r.get("type") == "assistant")
        time.sleep(watch)
        recs = records(tx)
        n1 = sum(1 for r in recs if r.get("type") == "assistant")
        goals = [
            r["attachment"]
            for r in recs
            if r.get("type") == "attachment"
            and (r.get("attachment") or {}).get("type") == "goal_status"
        ]
        out["assistant_after_exit"] = n1 - n0
        out["last_goal_status"] = goals[-1] if goals else None
        out["tx_mtime_after_exit_s"] = (
            round(os.path.getmtime(tx) - t_exit, 1) if tx else None
        )
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
    b, c, w, arm = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    model = sys.argv[5] if len(sys.argv) > 5 else "haiku"
    watch = int(sys.argv[6]) if len(sys.argv) > 6 else 90
    r = run(b, c, w, arm, model, watch)
    print(
        "ARM=%s EXITED=%s ASSISTANT_AFTER_EXIT=%s TX_MTIME_AFTER_EXIT_S=%s NOTE=%s"
        % (
            r["arm"],
            r.get("exited"),
            r.get("assistant_after_exit"),
            r.get("tx_mtime_after_exit_s"),
            r["note"],
        )
    )
    print("LAST_GOAL_STATUS=%s" % json.dumps(r.get("last_goal_status")))
    print("TRANSCRIPT=%s" % r.get("transcript"))
    for label, txt in r["steps"]:
        print("---- %s ----" % label)
        print("\n".join(l for l in txt.splitlines() if l.strip()))
