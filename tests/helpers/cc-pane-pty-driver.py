# The keys typed at a held pane, through a real pty whose foreground group is the runner
# (tests/cc-pane-runner-hold.bats, arm "A1t pty"). Run as: python3 -I <this file> <runner>.
# Driven by python's pty module, not script(1): macOS script refuses a non-tty stdin
# ("tcgetattr/ioctl: Operation not supported on socket") and exits at once, so it cannot be typed
# into from a test.
#
# NO PTY CHILD OUTLIVES THIS DRIVER (incident 2026-10-25, ~/incident-2026-10-25/RCA.md §1). The
# version inline in the bats file exited after its budget without killing its child: the master
# closed under a runner that ignored HUP, the runner's painter then slept in an open of the slave
# waiting for a carrier, and a later kill of the runner by pid left /dev wedged for 9 h. So every exit
# path, a timeout, an exception, SIGTERM, SIGALRM or SIGHUP included, runs `reap()`: it kills the
# child's whole process group (pty.fork makes the child a session and group leader) WHILE THE MASTER
# IS STILL OPEN, reaps it, waits for the group to empty, and only then closes the master. The child's
# pid goes to $T/pty-child-pid at once, so the bats teardown can kill the group if this process is
# itself SIGKILLed. Seam: PTY_DRIVER_START_S, the start-up budget (default 30 s).
import json
import os
import pty
import select
import signal
import sys
import time

T, runner = os.environ["T"], sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", runner])
with open(T + "/pty-child-pid", "w") as f:
    f.write("%d\n" % pid)
reaped = None  # the child's wait status once waitpid has collected it


def reap():
    global reaped
    for s in (signal.SIGTERM, signal.SIGALRM, signal.SIGHUP, signal.SIGINT):
        signal.signal(s, signal.SIG_IGN)  # a second signal must not cut the reap short
    try:
        os.killpg(pid, signal.SIGKILL)
    except OSError:
        pass
    if reaped is None:
        try:
            reaped = os.waitpid(pid, 0)[1]
        except OSError:
            pass
    end = (
        time.time() + 5
    )  # the group's other members are reparented and reaped by launchd
    while time.time() < end:
        try:
            os.killpg(pid, 0)
        except OSError:
            break
        time.sleep(0.05)
    try:
        os.close(fd)
    except OSError:
        pass


def on_signal(signum, _frame):
    sys.exit("driver ended by signal %d" % signum)


for s in (signal.SIGTERM, signal.SIGALRM, signal.SIGHUP, signal.SIGINT):
    signal.signal(s, on_signal)


def drain():  # an exited child leaves the master readable at EOF forever: b"" ends the drain
    while select.select([fd], [], [], 0)[0]:
        try:
            if not os.read(fd, 4096):
                return
        except OSError:
            return


def tail():
    try:
        return json.load(open(T + "/pane-exit/289.json")).get("tail")
    except Exception:
        return None


def ended():
    global reaped
    p, st = os.waitpid(pid, os.WNOHANG | os.WUNTRACED)
    if p == 0:
        return None
    if not os.WIFSTOPPED(st):
        reaped = st
    return st


def main():
    end = time.time() + float(
        os.environ.get("PTY_DRIVER_START_S", "30")
    )  # bash + stubs under load
    while tail() != "hold:fs":
        drain()
        time.sleep(0.1)
        st = ended()
        if st is not None:
            sys.exit("ended before holding: wait status %d, tail %r" % (st, tail()))
        if time.time() > end:
            sys.exit(
                "never held: tail %r, guard calls %r"
                % (
                    tail(),
                    os.path.exists(T + "/guard-log") and open(T + "/guard-log").read(),
                )
            )
    for ch in (b"\x03", b"\x1c", b"\x1a"):
        os.write(fd, ch)
        time.sleep(0.3)
        drain()
        st = ended()
        if st is not None:
            sys.exit("ended or stopped by %r: wait status %d" % (ch, st))
    open(T + "/release", "w").close()
    t0 = time.time()
    end = t0 + 30
    while True:
        drain()
        st = ended()
        if st is not None:
            break
        if time.time() > end:
            sys.exit("still held 30 s after release: tail %r" % tail())
        time.sleep(0.1)
    print("exit=%d after %ds" % (os.waitstatus_to_exitcode(st), time.time() - t0))


try:
    main()
finally:
    reap()
