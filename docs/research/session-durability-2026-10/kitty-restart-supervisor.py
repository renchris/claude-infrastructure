#!/usr/bin/env python3
"""kitty-restart-supervisor: the zero-human backstop for /tmp/kitty-restart-resume.py.

  python3 /tmp/kitty-restart-supervisor.py --dry-run             read-only: shows what it would watch
  python3 /tmp/kitty-restart-supervisor.py --confirm supervise   arm it (detaches, survives kitty)

Waits for the restart waiter (the pid in /tmp/inboot-2026-10-01/waiter.pid, or the one given with
--waiter) to exit, then makes the outcome complete without a human:
  * kitty 610 still running (the waiter aborted before signalling) -> nothing touched; notify only.
  * kitty 610 gone and no new kitty -> relaunch kitty (open -n, clean environment).
  * any roster session not running in the new kitty -> more boot-resume rounds, load-paced,
    for up to 90 min, then prompt each newly resumed session once to run /limit-recover.
  * the lead session (09c26b2b) not back -> open ONE fresh recovery lead in the new kitty with
    /tmp/inboot-2026-10-01/FALLBACK-PROMPT.md, so the task list resumes without anyone typing.
Log: /tmp/inboot-2026-10-01/supervisor.log. Python, not bash, so bin/cc-reaper leaves it alone.
"""

import importlib.util, json, os, re, subprocess, sys, time

spec = importlib.util.spec_from_file_location("krr", "/tmp/kitty-restart-resume.py")
krr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(krr)

D = krr.D
SLOG = os.path.join(D, "supervisor.log")
LEAD_SID = "09c26b2b-dd82-4cf2-b884-395d02cbddf1"
REPO = os.path.join(krr.HOME, "Development/claude-infrastructure")
OLD_KITTY = 610


def roster_sids():
    p = os.path.join(D, "roster-sids.txt")
    if os.path.exists(p):
        return [s for s in open(p).read().split() if s]
    try:
        return [
            r["session_id"]
            for r in json.load(open(os.path.join(D, "reboot-inboot.roster.json")))
            if r.get("session_id")
        ]
    except (OSError, ValueError):
        return []


def new_kitty():
    for k in krr.main_kitty():
        if k[0] != OLD_KITTY:
            sock = "unix:/tmp/kitty-%d" % k[0]
            rc, _, _ = krr.sh([krr.KITTEN, "@", "--to", sock, "ls"], timeout=10)
            if rc == 0:
                return k[0], sock
    return None, None


def prompted_sids():
    done = set()
    for f in ("run.log", "supervisor.log"):
        try:
            for ln in open(os.path.join(D, f)):
                m = re.search(
                    r"recovery prompt -> pane \S+ \(([0-9a-f]{8})\): rc=0", ln
                )
                if m:
                    done.add(m.group(1))
        except OSError:
            pass
    return done


def live_in(pid):
    return {
        r.get("session_id"): r
        for r in (krr.roster() or [])
        if r.get("kitty_pid") == pid
    }


def run(waiter):
    krr.notify("supervisor armed: backstop for the kitty restart")
    while waiter and krr.alive(waiter):
        time.sleep(10)
    krr.log("waiter %s has exited" % waiter)
    time.sleep(5)
    if krr.alive(OLD_KITTY):
        krr.notify(
            "supervisor: kitty was not restarted (the waiter stopped first); fleet untouched"
        )
        return 0
    pid, sock = new_kitty()
    if not pid:
        krr.log("no new kitty answering; relaunching")
        krr.sh(
            ["/usr/bin/open", "-n", "-a", "/Applications/kitty.app"],
            env=krr.clean_env(),
        )
        for _ in range(180):
            pid, sock = new_kitty()
            if pid:
                break
            time.sleep(1)
    if not pid:
        krr.notify(
            "supervisor FAILED: no kitty answering after relaunch; see %s" % SLOG
        )
        return 5
    krr.log("new kitty %d on %s" % (pid, sock))
    sids = roster_sids()
    marker = os.path.join(krr.STATE, "last-boot-epoch")
    t0 = time.time()
    while time.time() - t0 < 90 * 60:
        live = live_in(pid)
        missing = [s for s in sids if s not in live]
        krr.log("missing %d of %d" % (len(missing), len(sids)))
        if not missing:
            break
        t1 = time.time()
        while not krr.load_ok()[0] and time.time() - t1 < 600:
            time.sleep(20)
        if os.path.exists(marker):
            os.remove(marker)
        env = krr.clean_env(
            {
                "CC_BOOTTIME_OVERRIDE": str(int(time.time())),
                "CC_BOOT_RESUME_MODE": "resume",
                "CC_BOOT_RESUME_STATE_DIR": krr.STATE,
                "CC_BOOT_RESUME_ROSTER_DIR": D,
                "CC_TERM_KITTY_TO": sock,
            }
        )
        rc, out, err = krr.sh(["/bin/bash", krr.BOOT_RESUME], timeout=1800, env=env)
        krr.log("supervisor round: boot-resume rc=%d" % rc)
        time.sleep(90)
    live = live_in(pid)
    missing = [s for s in sids if s not in live]
    with open(os.path.join(D, "missing.txt"), "w") as fh:
        fh.write("\n".join(missing) + ("\n" if missing else ""))
    prompt = krr.PROMPT.format(hm=time.strftime("%H:%M"))
    done = prompted_sids()
    for sid, r in live.items():
        if sid in sids and sid[:8] not in done and str(r.get("paneUUID", "")).isdigit():
            rc, _, _ = krr.sh(
                [
                    krr.KITTEN,
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
            krr.log(
                "recovery prompt -> pane %s (%s): rc=%d" % (r["paneUUID"], sid[:8], rc)
            )
    if LEAD_SID not in live:
        cmd = 'cd %s && claude "$(cat %s)"' % (
            REPO,
            os.path.join(D, "FALLBACK-PROMPT.md"),
        )
        rc, _, err = krr.sh(
            [
                krr.KITTEN,
                "@",
                "--to",
                sock,
                "launch",
                "--type=os-window",
                "--cwd",
                REPO,
                "--title",
                "recovery lead",
                "/bin/zsh",
                "-l",
                "-i",
                "-c",
                cmd,
            ],
            timeout=30,
        )
        krr.log(
            "lead %s not back: opened a fresh recovery lead rc=%d %s"
            % (LEAD_SID[:8], rc, err.strip()[:120])
        )
    krr.notify(
        "supervisor done: %d of %d sessions back%s"
        % (
            len(sids) - len(missing),
            len(sids),
            "" if LEAD_SID in live else "; recovery lead opened",
        )
    )
    return 0 if not missing else 6


def main(argv):
    waiter = None
    if "--waiter" in argv:
        waiter = int(argv[argv.index("--waiter") + 1])
    elif os.path.exists(os.path.join(D, "waiter.pid")):
        waiter = int(open(os.path.join(D, "waiter.pid")).read().strip() or 0) or None
    if argv[:1] == ["--dry-run"]:
        krr.log(
            "would wait for waiter pid %s (alive=%s), then check kitty %d, %d roster sessions, lead %s"
            % (
                waiter,
                bool(waiter and krr.alive(waiter)),
                OLD_KITTY,
                len(roster_sids()),
                LEAD_SID[:8],
            )
        )
        return 0
    if argv[:1] == ["--_run"]:
        return run(waiter)
    if argv[:2] == ["--confirm", "supervise"]:
        if not (waiter and krr.alive(waiter)):
            krr.log("no live waiter to supervise (give --waiter <pid>); not armed")
            return 3
        logf = open(SLOG, "ab", 0)
        p = subprocess.Popen(
            [
                sys.executable,
                os.path.abspath(__file__),
                "--_run",
                "--waiter",
                str(waiter),
            ],
            start_new_session=True,
            stdout=logf,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            env=krr.clean_env(),
        )
        krr.log(
            "ARMED: supervisor pid %d watching waiter %d. Log: %s"
            % (p.pid, waiter, SLOG)
        )
        return 0
    sys.stderr.write(
        "usage: %s --dry-run | --confirm supervise [--waiter PID]\n" % sys.argv[0]
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
