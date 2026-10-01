#!/usr/bin/env python3
"""kitty-restart-resume — restart the stuck main kitty and bring every Claude session back, hands-off.

  python3 /tmp/kitty-restart-resume.py --dry-run                 read-only preview, changes nothing
  python3 /tmp/kitty-restart-resume.py --confirm restart-kitty   arm it (detaches, survives kitty)

What the armed run does, in order (log: /tmp/inboot-2026-10-01/run.log, macOS notifications at each step):
  1. Snapshots the live session roster (cc-sessions --json) every 15 s while it waits.
  2. Waits until no ship-land.sh is running (a land is never cut mid-push), up to 4 h.
  3. Quits ONLY the main kitty (pid checked: /Applications/kitty.app, no --instance-group) with
     SIGTERM, then SIGKILL after 10 s if it is still alive. No dialog. The sandbox kitty is untouched.
  4. Relaunches kitty (open -n, clean environment) and waits for its control socket to answer.
  5. Resumes every roster session through scripts/boot-resume.sh in rounds, waiting for load to fall
     between rounds, until nothing is shed (at most 8 rounds). Same session ids, accounts and /goals.
  6. Sends each resumed session one recovery prompt: run /limit-recover to re-run unfinished
     subagents and workflow runs and re-arm needed watchers, then continue.
What it cannot undo: every live session's in-flight turn and background jobs end at step 3.
Conversations are not lost (transcripts are on disk; --resume restores them).
Written as Python, not bash, because bin/cc-reaper TERMs launchd-parented bash older than 600 s.
"""

import json, os, re, subprocess, sys, time

D = "/tmp/inboot-2026-10-01"
STATE = os.path.join(D, "state")
LOG = os.path.join(D, "run.log")
HOME = os.path.expanduser("~")
KITTY_EXE = "/Applications/kitty.app/Contents/MacOS/kitty"
KITTEN = "/Applications/kitty.app/Contents/MacOS/kitten"
SESSIONS = os.path.join(HOME, ".claude/bin/cc-sessions")
BOOT_RESUME = os.path.join(HOME, ".claude/scripts/boot-resume.sh")
CONFIRM = "restart-kitty"
PROMPT = (
    "kitty was restarted at {hm}; this session was resumed in full (same session id, same account). "
    "Everything that ran in the background under the old process died with it: Bash background jobs, "
    "Monitor watches, cc-await-ping watchers, in-flight subagents and Dynamic Workflow runs. Run "
    "/limit-recover now: read finished results from disk, re-run only what is incomplete (resume workflow "
    "runs with resumeFromRunId where the audit says so), and re-arm a watcher only if you still need it "
    "and no /goal is live. If a ship-land was in flight, verify by content (git ls-tree origin/main) "
    "before landing again. Then continue where you left off; if nothing was pending, reply with one "
    "line saying so."
)


def log(msg):
    line = "%s %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)


def notify(msg):
    subprocess.run(
        [
            "/usr/bin/osascript",
            "-e",
            'display notification "%s" with title "kitty restart"'
            % msg.replace('"', "'"),
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    log("NOTIFY " + msg)


def sh(argv, timeout=60, env=None):
    try:
        p = subprocess.run(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            env=env,
        )
        return (
            p.returncode,
            p.stdout.decode("utf-8", "replace"),
            p.stderr.decode("utf-8", "replace"),
        )
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def kitties():
    """[(pid, args, lstart)] for every process whose executable is kitty."""
    rc, out, _ = sh(["/bin/ps", "-axo", "pid=,lstart=,args="])
    res = []
    for ln in out.splitlines():
        # lstart prints as "Wed 30 Sep 15:29:01 2026" on this box (day before month): accept any order.
        m = re.match(r"\s*(\d+)\s+(\w{3}\s+\S+\s+\S+\s+[\d:]+\s+\d{4})\s+(.*)$", ln)
        if m and m.group(3).split()[0].endswith("/MacOS/kitty"):
            res.append((int(m.group(1)), m.group(3), m.group(2)))
    return res


def main_kitty():
    c = [
        k
        for k in kitties()
        if k[1].split()[0] == KITTY_EXE and "--instance-group" not in k[1]
    ]
    return c


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def lands():
    """pids whose PROGRAM is ship-land.sh (argv[0], or argv[1] under a shell). Never `pgrep -f`,
    which also matches every session whose brief merely mentions ship-land.sh (the same rule as
    scripts/alarm-reboot-prep.sh:54-60)."""
    rc, out, _ = sh(["/bin/ps", "-axo", "pid=,args="])
    res = []
    for ln in out.splitlines():
        parts = ln.split()
        if len(parts) < 2 or not parts[0].isdigit():
            continue
        a0, a1 = parts[1], (parts[2] if len(parts) > 2 else "")
        if re.search(r"(^|/)ship-land\.sh$", a0) or (
            re.search(r"(^|/)(ba|z|da)?sh$", a0)
            and re.search(r"(^|/)ship-land\.sh$", a1)
        ):
            res.append(int(parts[0]))
    return res


def roster():
    rc, out, _ = sh([SESSIONS, "--json"], timeout=60)
    if rc != 0:
        return None
    try:
        d = json.loads(out)
    except ValueError:
        return None
    return d if isinstance(d, list) else None


def save_roster(rows):
    tmp = os.path.join(D, ".roster.tmp")
    with open(tmp, "w") as fh:
        json.dump(rows, fh)
    os.replace(tmp, os.path.join(D, "reboot-inboot.roster.json"))
    with open(os.path.join(D, ".start.tmp"), "w") as fh:
        fh.write("%d\n" % int(time.time()))
    os.replace(os.path.join(D, ".start.tmp"), os.path.join(D, "reboot-inboot.start"))


def clean_env(extra=None):
    keep = ("HOME", "PATH", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "LC_ALL")
    env = {k: os.environ[k] for k in keep if k in os.environ}
    env.setdefault(
        "PATH", "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    )
    env["PATH"] = os.path.join(HOME, ".claude/bin") + ":" + env["PATH"]
    if extra:
        env.update(extra)
    return env


def load_ok():
    l1 = os.getloadavg()[0]
    return l1 / (os.cpu_count() or 1) < 2.0, l1


def preflight():
    ok = True
    mk = main_kitty()
    if len(mk) != 1:
        log(
            "✗ expected exactly one main kitty (%s, no --instance-group), found %s"
            % (KITTY_EXE, mk)
        )
        ok = False
    else:
        pid = mk[0][0]
        log(
            "main kitty pid %d, started %s, socket /tmp/kitty-%d %s"
            % (
                pid,
                mk[0][2],
                pid,
                "present" if os.path.exists("/tmp/kitty-%d" % pid) else "ABSENT",
            )
        )
    others = [k for k in kitties() if not mk or k[0] != mk[0][0]]
    log(
        "other kitty instances (left untouched): %s"
        % ([(k[0], k[2]) for k in others] or "none")
    )
    rows = roster()
    if rows is None:
        log("✗ cc-sessions --json failed")
        ok = False
    else:
        log("live sessions in the roster: %d" % len(rows))
    log("lands in flight now: %s" % (lands() or "none"))
    good, l1 = load_ok()
    log(
        "load %.1f on %d cores (%s)"
        % (
            l1,
            os.cpu_count() or 0,
            "under 2.0/core" if good else "over 2.0/core; resume waits",
        )
    )
    for p in (SESSIONS, BOOT_RESUME, KITTEN):
        if not os.path.exists(p):
            log("✗ missing %s" % p)
            ok = False
    return ok, (mk[0] if len(mk) == 1 else None), others


def run():
    notify("armed: waiting for lands to finish before restarting kitty")
    ok, mk, others = preflight()
    if not ok or not mk:
        notify("ABORTED before touching kitty: preflight failed (see %s)" % LOG)
        return 3
    old_pid = mk[0]
    sandbox = {k[0]: k[2] for k in others}
    best, idle_checks, t0 = None, 0, time.time()
    while True:
        rows = roster()
        if rows is not None and (best is None or len(rows) >= len(best) - 2):
            best = rows
            save_roster(rows)
        if lands():
            idle_checks = 0
        else:
            idle_checks += 1
        if idle_checks >= 2:
            break
        if time.time() - t0 > 4 * 3600:
            notify("ABORTED: lands still in flight after 4 h; kitty untouched")
            return 3
        time.sleep(15)
    sids = [r.get("session_id") for r in best or [] if r.get("session_id")]
    log("final roster: %d session(s)" % len(sids))
    with open(os.path.join(D, "roster-sids.txt"), "w") as fh:
        fh.write("\n".join(sids) + "\n")
    pids = [r.get("pid") for r in best or [] if isinstance(r.get("pid"), int)]
    # Re-verify the target at the last moment: still the same main kitty.
    mk2 = main_kitty()
    if len(mk2) != 1 or mk2[0][0] != old_pid or mk2[0][2] != mk[2]:
        notify("ABORTED: the main kitty changed while waiting; nothing signalled")
        return 3
    notify("restarting kitty now (%d sessions will be resumed)" % len(sids))
    os.kill(old_pid, 15)
    log("SIGTERM -> %d" % old_pid)
    for _ in range(10):
        if not alive(old_pid):
            break
        time.sleep(1)
    if alive(old_pid):
        os.kill(old_pid, 9)
        log("still alive after 10 s: SIGKILL -> %d" % old_pid)
    for _ in range(30):
        if not alive(old_pid):
            break
        time.sleep(1)
    if alive(old_pid):
        notify("FAILED: kitty %d did not exit; nothing relaunched" % old_pid)
        return 4
    log("kitty %d exited" % old_pid)
    for k in kitties():
        if k[0] in sandbox and sandbox[k[0]] != k[2]:
            log("⚠ sandbox kitty %d start time changed" % k[0])
    for _ in range(60):
        if not any(alive(p) for p in pids):
            break
        time.sleep(1)
    log("old session processes still alive: %d" % sum(1 for p in pids if alive(p)))
    before = {k[0] for k in kitties()}
    sh(["/usr/bin/open", "-n", "-a", "/Applications/kitty.app"], env=clean_env())
    new_pid, sock = None, None
    for _ in range(120):
        for k in main_kitty():
            if k[0] not in before:
                new_pid = k[0]
        if new_pid:
            sock = "unix:/tmp/kitty-%d" % new_pid
            rc, _, _ = sh([KITTEN, "@", "--to", sock, "ls"], timeout=10)
            if rc == 0:
                break
        time.sleep(1)
    else:
        notify(
            "FAILED: new kitty did not answer on its socket within 2 min (pid %s)"
            % new_pid
        )
        return 5
    log("new kitty pid %d answers on %s" % (new_pid, sock))
    notify("kitty is back; resuming sessions")
    marker = os.path.join(STATE, "last-boot-epoch")
    for rnd in range(1, 9):
        t1 = time.time()
        while True:
            good, l1 = load_ok()
            if good or time.time() - t1 > 900:
                break
            time.sleep(20)
        log("round %d: load %.1f" % (rnd, l1))
        if os.path.exists(marker):
            os.remove(marker)
        env = clean_env(
            {
                "CC_BOOTTIME_OVERRIDE": str(int(time.time())),
                "CC_BOOT_RESUME_MODE": "resume",
                "CC_BOOT_RESUME_STATE_DIR": STATE,
                "CC_BOOT_RESUME_ROSTER_DIR": D,
                "CC_TERM_KITTY_TO": sock,
            }
        )
        rc, out, err = sh(["/bin/bash", BOOT_RESUME], timeout=1800, env=env)
        log(
            "round %d: boot-resume rc=%d %s"
            % (rnd, rc, (out + err).strip().splitlines()[-1:] or "")
        )
        verdict = ""
        try:
            verdict = [
                l
                for l in open(os.path.join(STATE, "last-layout.out"))
                if "verdict=" in l
            ][-1].strip()
        except (OSError, IndexError):
            pass
        log("round %d: %s" % (rnd, verdict or "no layout verdict"))
        m = re.search(r"shed=(\d+)", verdict)
        if not m or m.group(1) == "0":
            break
        time.sleep(30)
    time.sleep(90)
    rows = roster() or []
    live = {r.get("session_id"): r for r in rows if r.get("kitty_pid") == new_pid}
    missing = [s for s in sids if s not in live]
    with open(os.path.join(D, "missing.txt"), "w") as fh:
        fh.write("\n".join(missing) + ("\n" if missing else ""))
    prompt = PROMPT.format(hm=time.strftime("%H:%M"))
    sent = 0
    for sid in sids:
        r = live.get(sid)
        if not r or not str(r.get("paneUUID", "")).isdigit():
            continue
        rc, _, _ = sh(
            [
                KITTEN,
                "@",
                "--to",
                sock,
                "send-text",
                "--match",
                "id:%s" % r["paneUUID"],
                prompt + "\r",
            ],
            timeout=15,
        )
        sent += rc == 0
        log("recovery prompt -> pane %s (%s): rc=%d" % (r["paneUUID"], sid[:8], rc))
    notify(
        "done: %d of %d sessions back, %d prompted to recover; missing list in %s/missing.txt"
        % (len(sids) - len(missing), len(sids), sent, D)
    )
    return 0 if not missing else 6


def main(argv):
    os.makedirs(STATE, exist_ok=True)
    if argv[:1] == ["--dry-run"]:
        ok, mk, _ = preflight()
        log(
            "DRY RUN: nothing signalled, nothing written outside %s. Preflight %s."
            % (D, "OK" if ok else "FAILED")
        )
        return 0 if ok else 3
    if argv[:1] == ["--_run"]:
        return run()
    if argv[:2] == ["--confirm", CONFIRM]:
        ok, mk, _ = preflight()
        if not ok:
            log("preflight failed; not armed")
            return 3
        logf = open(LOG, "ab", 0)
        p = subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "--_run"],
            start_new_session=True,
            stdout=logf,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            env=clean_env(),
        )
        log(
            "ARMED: detached waiter pid %d (python, survives kitty). Log: %s"
            % (p.pid, LOG)
        )
        log(
            "It restarts kitty by itself once no land is running; watch for macOS notifications."
        )
        return 0
    sys.stderr.write("usage: %s --dry-run | --confirm %s\n" % (sys.argv[0], CONFIRM))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
