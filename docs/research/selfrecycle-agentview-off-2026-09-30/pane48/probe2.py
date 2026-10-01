#!/usr/bin/env python3
"""W7c step 0b: the foreground tool call as the dialog's subject, and the Esc + re-/exit cure.

A foreground Bash runs `sh -c 'touch M1; sleep S; touch M2'`. Arms:
  early   /exit typed 0.3 s after M1                         (call just started)
  late    /exit typed 4 s after M1 (call still running); once M2 exists (call returned) + 4 s,
          Esc (Stay) then /exit again                         (the proposed cure)
  after   /exit typed 5 s after M2 (call returned)            (the cure's premise)
  latebg  like late, but a run_in_background `sleep 600` was started in an earlier turn: the
          re-/exit must raise the dialog AGAIN (the cure must still hold for real work)
Hooks disabled; CLAUDE_CODE_DISABLE_AGENT_VIEW=1; never sends a digit.
"""

import os, sys, time

sys.path.insert(0, os.path.dirname(__file__))
import probe as P
import pty, fcntl, termios, struct, signal
import pyte


def main(binary, cfg, cwd, arm, S=12):
    sc = pyte.Screen(P.COLS, P.ROWS)
    st = pyte.Stream(sc)
    env = dict(os.environ)
    for k in list(env):
        if (
            k.startswith(("CLAUDE_CODE_", "ITERM_", "KITTY_", "CC_"))
            or k == "CLAUDECODE"
        ):
            env.pop(k, None)
    env.update(
        CLAUDE_CONFIG_DIR=cfg,
        TERM="xterm-256color",
        COLUMNS=str(P.COLS),
        LINES=str(P.ROWS),
        CLAUDE_CODE_DISABLE_AGENT_VIEW="1",
    )
    argv = [
        binary,
        "--model",
        "haiku",
        "--settings",
        '{"disableAllHooks":true}',
        "--allowedTools",
        "Bash(sleep:*)",
        "Bash(sh:*)",
    ]
    m1, m2 = "/tmp/w7c-probe/%s.m1" % arm, "/tmp/w7c-probe/%s.m2" % arm
    for m in (m1, m2):
        try:
            os.unlink(m)
        except FileNotFoundError:
            pass
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execve(binary, argv, env)
    T0 = time.time()
    log = []

    def cp(tag):
        d = P.dialog_block(sc)
        log.append(
            "[%s] t=%.1fs DIALOG=%s EXITED=%s"
            % (
                tag,
                time.time() - T0,
                "yes" if d else "no",
                "no" if P.alive(pid) else "yes",
            )
        )
        if d:
            log.append(
                "    "
                + "\n    ".join(l for l in d.split("\n") if "·" in l or "." in l[:12])
            )

    def exit_():
        os.write(fd, b"/exit")
        P.drain(fd, st, 0.3)
        os.write(fd, b"\r")

    def watch(n):
        for _ in range(n):
            P.drain(fd, st, 2.0)
            cp("watch")
            if not P.alive(pid):
                return True
        return False

    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", P.ROWS, P.COLS, 0, 0))
        t = time.time()
        while time.time() - t < 120:
            P.drain(fd, st, 1.0)
            if P.composer(sc) == "":
                break
        P.drain(fd, st, 8.0)
        if arm == "latebg":
            P.send(
                fd,
                st,
                "Use the Bash tool with run_in_background set to true to run exactly: sleep 600 . "
                "Do nothing else and reply with the single word OK.",
            )
            t = time.time()
            while time.time() - t < 120:
                P.drain(fd, st, 1.5)
                if (
                    P.composer(sc) == ""
                    and "OK" in P.text(sc).split("single word OK.")[-1]
                ):
                    break
            P.drain(fd, st, 3.0)
            cp("bg-started")
        P.send(
            fd,
            st,
            "Use the Bash tool in the foreground (not background) to run exactly: "
            "sh -c 'touch %s; sleep %d; touch %s' . Then reply with one word."
            % (m1, S, m2),
        )
        t = time.time()
        while time.time() - t < 120 and not os.path.exists(m1):
            P.drain(fd, st, 0.1)
        if not os.path.exists(m1):
            print("NON-VERDICT: M1 never appeared")
            print(P.text(sc))
            return
        cp("m1")
        if arm == "early":
            P.drain(fd, st, 0.3)
            exit_()
            cp("exit-typed")
            watch(6)
        elif arm in ("late", "latebg"):
            P.drain(fd, st, 4.0)
            cp("pre-exit")
            exit_()
            P.drain(fd, st, 2.0)
            cp("exit-typed")
            t = time.time()
            while time.time() - t < 60 and not os.path.exists(m2):
                P.drain(fd, st, 0.5)
            cp("m2-call-returned")
            P.drain(fd, st, 4.0)
            cp("m2+4s")
            if P.alive(pid) and P.dialog_block(sc):
                os.write(fd, b"\x1b")
                P.drain(fd, st, 2.0)
                cp("after-esc")
                comp = P.composer(sc)
                log.append("    composer after Esc: %r" % comp)
                if comp == "/exit":
                    for _ in range(5):
                        os.write(fd, b"\x7f")
                    P.drain(fd, st, 0.5)
                exit_()
                P.drain(fd, st, 1.0)
                cp("re-exit-typed")
                watch(5)
        elif arm == "after":
            t = time.time()
            while time.time() - t < 60 and not os.path.exists(m2):
                P.drain(fd, st, 0.5)
            P.drain(fd, st, 5.0)
            cp("m2+5s")
            exit_()
            watch(5)
        if P.alive(pid) and P.dialog_block(sc):
            os.write(fd, b"\x1b")
            P.drain(fd, st, 2.0)
            cp("final-esc")
        print("\n".join(log))
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
        except Exception:
            pass


if __name__ == "__main__":
    b, c, w, arm = sys.argv[1:5]
    print("ARM=%s" % arm)
    main(b, c, w, arm)
