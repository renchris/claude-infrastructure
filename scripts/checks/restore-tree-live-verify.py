#!/usr/bin/env python3
"""restore-tree-live-verify — prove, against a REAL kitty, that a restore puts every pane back in its
recorded split position, and that cc-relayout moves running panes back without restarting them.

Run it:  python3 scripts/checks/restore-tree-live-verify.py [--keep]

WHY OUT OF CI. The planner can be checked offline (tests/cc-resume-layout-tree-replay.bats), but
whether kitty BUILDS that tree — --next-to, --bias, the order panes arrive in, the kitten that sets
the tree exactly — only a running kitty can say, and `kitty @` exits 0 on a no-op. The falsifier is
the tree kitty itself reports in `kitty @ ls` (layout_state.pairs), compared leaf by leaf, with axis
and bias, against the tree it reported for the fixture.

  1 FIXTURE  two OS windows: one 6-pane tab of mixed vsplit/hsplit with biases 30/60/25 and a shell
             pane, one window with two tabs; `kitty @ ls` of it, with a roster and a displays file
             beside it, is the recorded tree a heartbeat would have written
  2 RESTORE  bin/cc-resume-layout.sh --desktops --restore --tree <that> against this kitty, every
             session but one (a clean exit) resumed by a stub launcher; then the restored tree is
             diffed against the record: expected = the record with the clean exit left out
  3 RELAYOUT the restored panes are scattered (moved across tabs and OS windows, a bias changed),
             then bin/cc-relayout --apply puts them back; diffed the same way, and every moved
             pane's process id must be unchanged (moved, not restarted)

Prints `restore-tree-live-verify: <phase> mismatches=N` per phase and a final `verdict=pass|fail`.

 ── SAFETY: THIS SCRIPT MUST NEVER REACH THE OPERATOR'S OWN KITTY ──────────────────────────────
   S1 its world is RUN_ROOT under ~/Development/.worktrees, nothing inside the checkout
   S2 its socket is RUN_ROOT/k.sock, outside the /tmp/kitty-* glob bin/cc-kitty-socket scans
   S3 every kitty call, and every tool it runs, gets KITTY_LISTEN_ON / KITTY_PID / KITTY_WINDOW_ID
      removed and an explicit --to, so an inherited address can never drive the operator's terminal
   S4 no display placement and no fullscreen: the swift probe is pointed at nothing for the restore
      and the recorded displays say windowed; System Events is never asked to move anything
   S5 teardown is `close-window --match all` on its own socket; no signals
"""

import json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
import kitty_tree as kt  # noqa: E402

ROOT = os.path.expanduser("~/Development/.worktrees/rpl-kitty-verify")
SOCK = os.path.join(ROOT, "k.sock")
TO = "unix:" + SOCK
CFG, CACHE, ZDOT = (os.path.join(ROOT, d) for d in ("cfg", "cache", "zdot"))
REC = os.path.join(ROOT, "record")
KITTY = os.environ.get("KITTY_BIN") or "/Applications/kitty.app/Contents/MacOS/kitty"
CONF = """\
allow_remote_control yes
initial_window_width 1400
initial_window_height 800
remember_window_size no
confirm_os_window_close 0
macos_quit_when_last_window_closed yes
enabled_layouts splits:equalize_on_window_close=yes,horizontal,stack
"""
assert not SOCK.startswith("/tmp/kitty-"), "S2"
assert len(SOCK) < 100, "AF_UNIX path too long"


def env(**extra):
    e = {
        k: v
        for k, v in os.environ.items()
        if k not in ("KITTY_LISTEN_ON", "KITTY_PID", "KITTY_WINDOW_ID")
    }  # S3
    e.update(
        KITTY_CONFIG_DIRECTORY=CFG, KITTY_CACHE_DIRECTORY=CACHE, ZDOTDIR=ZDOT, **extra
    )
    return e


def kit(*a):
    return subprocess.run(
        [KITTY, "@", "--to", TO, *a],
        capture_output=True,
        text=True,
        env=env(),
        timeout=30,
    )


def log_pane_spawn(surface, pane, detail):
    """Every pane this verifier creates leaves a row (scripts/pane-spawn-coverage-lint.sh)."""
    lib = os.path.join(REPO, "scripts", "lib", "pane-spawn-log.sh")
    if os.path.isfile(lib):
        subprocess.run(
            ["/bin/bash", lib, "log", surface, "kitty", str(pane), ROOT, detail],
            env=dict(env(), CC_SPAWN_CALLER="restore-tree-live-verify"),
            timeout=10,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def launch(*a, surface="split", detail=""):
    r = kit("launch", "--keep-focus", *a)
    wid = (r.stdout or "").strip()
    if not wid.isdigit():
        sys.exit("launch failed: %s %s" % (a, r.stderr))
    log_pane_spawn(surface, wid, detail or "restore-tree-live-verify fixture")
    return int(wid)


def ls():
    r = kit("ls")
    if r.returncode != 0:
        sys.exit("kitty @ ls failed: %s" % r.stderr)
    return json.loads(r.stdout)


def alive():
    return os.path.exists(SOCK) and kit("ls").returncode == 0


def kitty_pid():
    """The sandbox kitty's pid: the one process holding its listening socket."""
    out = subprocess.run(["/usr/sbin/lsof", "-t", SOCK], capture_output=True, text=True).stdout.split()
    return out[0] if out else ""


def teardown():
    if alive():
        kit("close-window", "--match", "all")
    for _ in range(40):
        if not alive():
            break
        time.sleep(0.25)
    if os.path.exists(SOCK):
        try:
            os.unlink(SOCK)
        except OSError:
            pass


def up():
    for d in (CFG, CACHE, ZDOT, REC):
        os.makedirs(d, exist_ok=True)
    open(os.path.join(CFG, "kitty.conf"), "w").write(CONF)
    open(os.path.join(ZDOT, ".zshrc"), "w").write(
        ""
    )  # zsh -ic in a restored pane starts bare and fast
    if os.path.exists(SOCK):
        os.unlink(SOCK)
    subprocess.Popen(
        [
            "nohup",
            "python3",
            "-c",
            "import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])",
            KITTY,
            "--config",
            os.path.join(CFG, "kitty.conf"),
            "--listen-on",
            TO,
            "--instance-group",
            "rpl-verify",
            "--directory",
            cwd("a1"),
        ]
        + pane_cmd("a1"),
        stdout=open(os.path.join(ROOT, "kitty.stderr"), "w"),
        stderr=subprocess.STDOUT,
        env=env(),
    )
    for _ in range(240):
        if alive():
            return
        time.sleep(0.25)
    sys.exit("sandbox kitty never answered; see %s/kitty.stderr" % ROOT)


def sid(name):
    return "00000000-0000-4000-8000-%012x" % int.from_bytes(name.encode(), "big")


def cwd(name):
    d = os.path.join(ROOT, "cwd", name)
    os.makedirs(d, exist_ok=True)
    return d


def pane_cmd(name):
    return [
        "/bin/sh",
        "-c",
        "printf 'fixture %s\\n' " + sid(name) + "; exec /bin/sleep 86400",
    ]


# ── 1. FIXTURE ──────────────────────────────────────────────────────────────────────────────────
def fixture():
    ids = {}
    w0 = ls()
    ids["a1"] = w0[0]["tabs"][0]["windows"][0]["id"]

    def split(name, how, anchor, bias=None, shell=False):
        a = [
            "--location=" + how,
            "--match",
            "window_id:%d" % ids[anchor],
            "--next-to",
            "id:%d" % ids[anchor],
            "--cwd",
            cwd(name),
        ]
        if bias:
            a += ["--bias", str(bias)]
        ids[name] = launch(
            *(a + ([] if shell else pane_cmd(name))),
            detail="fixture %s %s next-to %s" % (name, how, anchor),
        )

    split("a2", "vsplit", "a1", 30)
    split("a3", "hsplit", "a2", 60)
    split("a4", "vsplit", "a1")
    split("a5", "hsplit", "a4", 25)
    split("a6", "hsplit", "a3", shell=True)
    ids["b1"] = launch(
        "--type=os-window",
        "--cwd",
        cwd("b1"),
        *pane_cmd("b1"),
        surface="os-window",
        detail="fixture b1",
    )
    split("b2", "vsplit", "b1", 70)
    split("b3", "vsplit", "b2")
    ids["b4"] = launch(
        "--type=tab",
        "--match",
        "window_id:%d" % ids["b1"],
        "--cwd",
        cwd("b4"),
        *pane_cmd("b4"),
        surface="tab",
        detail="fixture b4",
    )
    split("b5", "hsplit", "b4", 40)
    time.sleep(1.0)
    data = ls()
    json.dump(data, open(os.path.join(REC, "hb.kitty-ls.json"), "w"))
    roster = [
        {
            "session_id": sid(n),
            "paneUUID": str(w),
            "account": "next2",
            "cwd": cwd(n),
            "name": n,
        }
        for n, w in ids.items()
        if n != "a6"
    ]
    json.dump(roster, open(os.path.join(REC, "hb.roster.json"), "w"))
    with open(os.path.join(REC, "hb.displays.tsv"), "w") as fh:
        for o in data:
            fh.write(
                "\t".join(
                    map(
                        str,
                        [
                            o["platform_window_id"],
                            "VERIFY-DISPLAY",
                            0,
                            0,
                            3000,
                            2000,
                            0,
                            40,
                            40,
                            1400,
                            800,
                        ],
                    )
                )
                + "\n"
            )
    return ids, data


def expected(data, ids, drop):
    """The recorded tree per (os window, tab), leaves as sid (or shell:<cwd>), `drop` left out."""
    name_of = {w: n for n, w in ids.items()}
    rec_cwd = {w["id"]: w.get("cwd") for o in data for t in o["tabs"] for w in t["windows"]}
    out = []
    for t in kt.ls_tabs(data):

        def lab(w):
            n = name_of.get(w)
            if n is None or n in drop:
                return None
            return "shell:" + (rec_cwd.get(w) or "?") if n == "a6" else sid(n)

        tree = kt.relabel(t["tree"], lab)
        if tree is not None:
            out.append({"os_window": t["os_window"], "tab": t["tab"], "tree": tree})
    return out


def live_trees(data, sid_of_wid):
    out = []
    cwd_of = {
        w["id"]: w.get("cwd") for o in data for t in o["tabs"] for w in t["windows"]
    }
    for t in kt.ls_tabs(data):
        out.append(
            dict(
                t,
                lab=kt.relabel(
                    t["tree"],
                    lambda w: sid_of_wid.get(w) or ("shell:" + (cwd_of.get(w) or "?")),
                ),
            )
        )
    return out


def compare(phase, want, have):
    """Each recorded tab must be one live tab with the same tree; tabs of one recorded OS window must
    share one live OS window, in recorded order. Returns the mismatch count and prints each."""
    bad = []
    by_leaf = {}
    for t in have:
        for leaf in kt.leaves(t["lab"]):
            by_leaf[leaf] = t
    seen_os = {}
    for r in want:
        first_leaf = kt.leaves(r["tree"])[0]
        t = by_leaf.get(first_leaf)
        if t is None:
            bad.append(
                "os %s tab %s: pane %s not found live"
                % (r["os_window"], r["tab"], first_leaf)
            )
            continue
        d = kt.diff(r["tree"], t["lab"])
        bad += ["os %s tab %s: %s" % (r["os_window"], r["tab"], x) for x in d]
        prev = seen_os.get(r["os_window"])
        if prev is not None:
            if prev[0] != t["os_window"]:
                bad.append(
                    "os %s tab %s: in live OS window %s, its sibling tab is in %s"
                    % (r["os_window"], r["tab"], t["os_window"], prev[0])
                )
            elif prev[1] >= t["tab"]:
                bad.append(
                    "os %s tab %s: tab order differs" % (r["os_window"], r["tab"])
                )
        seen_os[r["os_window"]] = (t["os_window"], t["tab"])
    for x in bad:
        print("  MISMATCH %s: %s" % (phase, x))
    print(
        "restore-tree-live-verify: %s mismatches=%d (%d tab(s) compared)"
        % (phase, len(bad), len(want))
    )
    return len(bad)


# ── 2. RESTORE ──────────────────────────────────────────────────────────────────────────────────
def restore(ids, kpid):
    stub = os.path.join(ROOT, "stub-resume-one")
    open(stub, "w").write(
        "#!/bin/sh\n# stands in for reso-resume-one: holds the pane open, its sid in argv\nexec /bin/sleep 86400\n"
    )
    os.chmod(stub, 0o755)
    rows = os.path.join(ROOT, "rows.tsv")
    with open(rows, "w") as fh:
        for n in ids:
            if n not in ("a6", "b3"):
                fh.write("next2\t%s\t%s\t-\n" % (sid(n), cwd(n)))
    os.makedirs(os.path.join(ROOT, "hb-empty"), exist_ok=True)
    e = env(
        CC_TERM_KITTY=KITTY,
        CC_RESUME_ONE_BIN=stub,
        CC_ADMIT_GATE="off",
        CC_ADMIT_IDL=os.path.join(ROOT, "idl.jsonl"),
        CC_RESUME_STAGGER="0",
        CC_RESTORE_WAIT="0",
        CC_RESTORE_K_BACKOFF="1",
        CC_RESTORE_FS_GAP="0",
        CC_RESTORE_FS_VERIFY="0",
        CC_RESTORE_MAYBE_S="0",
        CC_RESTORE_MAYBE_POLL="0",
        CC_DESKTOP_SETTLE="0",
        CC_SWIFT_BIN="/nonexistent",
        CC_RESTORE_KITTY_PID=kpid,
        CC_HEARTBEAT_DIR=os.path.join(ROOT, "hb-empty"),
    )
    r = subprocess.run(
        [
            "/bin/bash",
            os.path.join(REPO, "bin", "cc-resume-layout.sh"),
            "--desktops",
            "--restore",
            "--tree",
            os.path.join(REC, "hb.kitty-ls.json"),
            "--to",
            TO,
            "--file",
            rows,
        ],
        capture_output=True,
        text=True,
        env=e,
        timeout=900,
    )
    open(os.path.join(ROOT, "restore.out"), "w").write(r.stdout)
    open(os.path.join(ROOT, "restore.err"), "w").write(r.stderr)
    print(
        "\n".join(
            "  " + l
            for l in r.stdout.splitlines()
            if "tree-verify" in l or "verdict=" in l or "layout " in l
        )
    )
    sid_of = {}
    for line in r.stdout.splitlines():
        if line.startswith("cc-resume-layout: map "):
            f = dict(p.split("=", 1) for p in line.split()[2:])
            sid_of[int(f["wid"])] = f["sid"]
    return r.returncode, sid_of


# ── 3. RELAYOUT ─────────────────────────────────────────────────────────────────────────────────
def scatter(sid_of):
    """Move restored panes out of place the way a crash recovery leaves them: across tabs, into a
    new OS window, and one bias changed. Returns {wid: pid} before."""
    data = ls()
    pid = {w["id"]: w.get("pid") for o in data for t in o["tabs"] for w in t["windows"]}
    wid_of = {s: w for w, s in sid_of.items()}
    tabs = {t["tab"]: t for t in kt.ls_tabs(data)}
    tab_of = {w: t["tab"] for t in tabs.values() for w in t["windows"]}
    a5, b2, a2, b5 = (wid_of[sid(n)] for n in ("a5", "b2", "a2", "b5"))
    kit(
        "detach-window", "--match", "id:%d" % a5, "--target-tab", "id:%d" % tab_of[b2]
    )  # a pane into another window
    kit("detach-window", "--match", "id:%d" % b5)  # a pane into a new OS window
    kit("detach-window", "--match", "id:%d" % a2, "--target-tab", "id:%d" % tab_of[b2])
    kit(
        "detach-window",
        "--match",
        "id:%d" % a2,
        "--target-tab",
        "id:%d" % tab_of[wid_of[sid("a1")]],
    )  # back, at the wrong place
    kit("resize-window", "--match", "id:%d" % wid_of[sid("a1")], "--increment", "8")
    time.sleep(1.0)
    return pid


def relayout(kpid):
    r = subprocess.run(
        [
            sys.executable,
            os.path.join(REPO, "bin", "cc-relayout"),
            "--to",
            TO,
            "--tree",
            os.path.join(REC, "hb.kitty-ls.json"),
            "--kitty-pid",
            kpid,
            "--apply",
        ],
        capture_output=True,
        text=True,
        env=env(),
        timeout=600,
    )
    open(os.path.join(ROOT, "relayout.out"), "w").write(
        r.stdout + "\n--- stderr\n" + r.stderr
    )
    print("\n".join("  " + l for l in r.stdout.splitlines()))
    return r.returncode


def main():
    keep = "--keep" in sys.argv
    if alive():
        sys.exit(
            "a verifier kitty is already answering on %s — run teardown or wait" % SOCK
        )
    shutil.rmtree(os.path.join(ROOT, "cwd"), ignore_errors=True)
    up()
    fails = 0
    try:
        kpid = kitty_pid()
        ids, data = fixture()
        want = expected(data, ids, drop={"b3"})
        rc, sid_of = restore(ids, kpid)
        print("  restore rc=%s mapped=%d" % (rc, len(sid_of)))
        after = ls()
        new_tabs = [
            t
            for t in live_trees(after, sid_of)
            if not set(t["windows"]) & set(ids.values())
        ]
        fails += compare("restore", want, new_tabs) + (rc != 0)
        json.dump(after, open(os.path.join(ROOT, "after-restore.ls.json"), "w"))
        if os.path.exists(os.path.join(REPO, "bin", "cc-relayout")):
            # the fixture panes go, so only the restored ones are left to put back
            for w in ids.values():
                kit("close-window", "--match", "id:%d" % w)
            time.sleep(0.5)
            before = scatter(sid_of)
            rrc = relayout(kpid)
            final = ls()
            json.dump(final, open(os.path.join(ROOT, "after-relayout.ls.json"), "w"))
            fails += compare("relayout", want, live_trees(final, sid_of)) + (rrc != 0)
            now = {
                w["id"]: w.get("pid")
                for o in final
                for t in o["tabs"]
                for w in t["windows"]
            }
            restarted = [w for w in sid_of if before.get(w) != now.get(w)]
            print(
                "restore-tree-live-verify: relayout restarted=%d of %d"
                % (len(restarted), len(sid_of))
            )
            fails += len(restarted)
        else:
            print("restore-tree-live-verify: relayout SKIPPED (bin/cc-relayout absent)")
    finally:
        if not keep:
            teardown()
    print("restore-tree-live-verify: verdict=%s" % ("pass" if fails == 0 else "fail"))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
