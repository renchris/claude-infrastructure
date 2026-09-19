#!/usr/bin/env python3
"""kitty-equalize-verify — prove, against a REAL kitty, that panes even themselves out.

Run it:  python3 scripts/checks/kitty-equalize-verify.py

WHY THIS EXISTS RATHER THAN A UNIT TEST. `kitty @ action` exits 0 on an unknown action name AND on
an action that resolves to no tab, so a return code cannot tell a working equalize from a silent
no-op — that is exactly how `--match` looks correct while doing nothing. The only honest falsifier
is the COLUMN WIDTHS kitty reports in `kitty @ ls`, which needs a running terminal. So this is an
out-of-CI verifier, and tests/kitty-equalize-arrival.bats pins the structure it cannot.

  A  removal  four panes at 114/57/28/28, detach one -> 76/76/76      (kitty does this itself)
  B  arrival  move a pane in -> 114/57/28/28 -> 45/45/45/45/45        (the --self call)
  C  control  --match instead of --self leaves the destination untouched, rc 0, empty stderr
  D  control  a third, uninvolved tab is not touched by either

 ── SAFETY: THIS SCRIPT MUST NEVER REACH THE OPERATOR'S OWN KITTY ──────────────────────────────
 ~/.config/kitty/kitty.conf is a SYMLINK into the shared checkout and the live kitty runs a
 `kitten __watch_conf__` child that reloads it ~100ms after ANY write there. The rules below are
 the ones scripts/kitty-drag-w4.sh established, enforced here as refusals rather than intentions:
   S1 writes nothing under ~/.config/kitty and nothing inside the checkout; its world is RUN_ROOT
   S2 its socket is /tmp/keq-verify.sock — deliberately OUTSIDE the /tmp/kitty-* glob that
      bin/cc-kitty-socket scans and that kitty-pane-title-overlay.py chokes on when it finds two
   S3 every kitty call unsets KITTY_LISTEN_ON / KITTY_PID / KITTY_WINDOW_ID and passes an explicit
      --to, so a bare inherited address can never make it drive the operator's terminal
   S4 it sends NO signals; teardown is `close-window --match all`
   S5 it is safe to re-run
"""
import json, os, subprocess, sys, time

ROOT, SOCK = "/tmp/keq-verify", "/tmp/keq-verify.sock"
CFG, CACHE = os.path.join(ROOT, "cfg"), os.path.join(ROOT, "cache")
KITTY = os.environ.get("KITTY_BIN") or "/Applications/kitty.app/Contents/MacOS/kitty"
CONF = """\
allow_remote_control yes
initial_window_width 1600
initial_window_height 900
confirm_os_window_close 0
macos_quit_when_last_window_closed yes
enabled_layouts splits:equalize_on_window_close=yes,stack
"""

assert not SOCK.startswith("/tmp/kitty-"), "S2: socket must stay outside the /tmp/kitty-* glob"

def env(**extra):
    e = {k: v for k, v in os.environ.items()
         if k not in ("KITTY_LISTEN_ON", "KITTY_PID", "KITTY_WINDOW_ID")}   # S3
    e.update(KITTY_CONFIG_DIRECTORY=CFG, KITTY_CACHE_DIRECTORY=CACHE, **extra)
    return e

def kit(*a, **extra):
    return subprocess.run([KITTY, "@", "--to", f"unix:{SOCK}", *a],
                          capture_output=True, text=True, env=env(**extra))

HERE = os.path.dirname(os.path.abspath(__file__))


def log_pane_spawn(surface: str, pane: str, detail: str) -> None:
    """One row per terminal surface this verifier CREATES.

    The sandbox is a real kitty with real panes, so `no row ⇒ not from this tree` would be false
    without these — scripts/pane-spawn-coverage-lint.sh blocks the land for exactly that, and it
    is right to: the log has one writer, so this shells out to its CLI mode rather than
    re-implementing a row that a later schema change would leave behind.

    Best-effort: a verifier must never fail on its own bookkeeping.
    """
    lib = os.path.join(HERE, "..", "lib", "pane-spawn-log.sh")
    if not os.path.isfile(lib):
        return
    try:
        subprocess.run(["/bin/bash", lib, "log", surface, "kitty", pane, ROOT, detail],
                       env=dict(os.environ, CC_SPAWN_CALLER="kitty-equalize-verify"), timeout=10,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception:
        pass


def launch(*a, surface="split", detail=""):
    """Every spawn in this file goes through here, so instrumentation cannot be half-applied."""
    r = kit("launch", *a)
    wid = (r.stdout or "").strip()
    log_pane_spawn(surface, wid, detail or f"kitty-equalize-verify {' '.join(a)}")
    return r


def alive(): return kit("ls").returncode == 0
def tabs():
    return [(o["id"], [w["columns"] for w in t["windows"]])
            for o in json.loads(kit("ls").stdout) for t in o["tabs"]]
def widths(osw):
    return next((c for i, c in tabs() if i == osw), [])
def spread(c): return (max(c) - min(c)) if c else 0

def teardown():
    if os.path.exists(SOCK) and alive():
        kit("close-window", "--match", "all")
    for _ in range(40):
        if not alive(): break
        time.sleep(0.25)
    if os.path.exists(SOCK):
        try: os.unlink(SOCK)
        except OSError: pass

def up():
    os.makedirs(CFG, exist_ok=True); os.makedirs(CACHE, exist_ok=True)
    open(os.path.join(CFG, "kitty.conf"), "w").write(CONF)
    subprocess.Popen(["nohup", "python3", "-c",
                      "import os,sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])",
                      KITTY, "--listen-on", f"unix:{SOCK}", "--instance-group", "keqverify",
                      "--start-as", "minimized", "--directory", ROOT, "sh", "-c", "exec $SHELL"],
                     stdout=open(os.path.join(ROOT, "kitty.stderr"), "w"),
                     stderr=subprocess.STDOUT, env=env())
    for _ in range(80):
        if alive(): return
        time.sleep(0.25)
    sys.exit(f"sandbox never came up; see {ROOT}/kitty.stderr")

def split(wid):
    kit("focus-window", "--match", f"id:{wid}")
    r = launch("--location=vsplit", "--match", f"window_id:{wid}", "--cwd", ROOT,
               detail="verifier vsplit beside the fixture head")
    time.sleep(0.35)
    return int(r.stdout.strip())

def chain(head, n):
    ids = [head]
    for _ in range(n - 1):
        ids.append(split(ids[-1]))
    time.sleep(0.4)
    return ids

def main():
    fails = []
    def check(name, cond, detail):
        print(f"  {'PASS' if cond else 'FAIL'}  {name}: {detail}")
        if not cond: fails.append(name)

    teardown(); os.makedirs(ROOT, exist_ok=True); up(); time.sleep(0.6)
    head = int(json.loads(kit("ls").stdout)[0]["tabs"][0]["windows"][0]["id"])
    A = chain(head, 4)
    B = chain(int(launch("--type=os-window", "--cwd", ROOT, surface="os-window",
                         detail="verifier destination window").stdout.strip()), 4)
    C = chain(int(launch("--type=os-window", "--cwd", ROOT, surface="os-window",
                         detail="verifier control window (must stay untouched)").stdout.strip()), 3)
    kit("focus-window", "--match", f"id:{A[0]}"); time.sleep(0.4)
    c_before = widths(3)

    print("A  removal — the tab a pane LEAVES (kitty's own equalize_on_window_close)")
    before = widths(1)
    kit("detach-window", "--match", f"id:{A[-1]}", "--target-tab", f"window_id:{B[0]}")
    time.sleep(0.8)
    check("source equalizes", spread(widths(1)) == 0, f"{before} -> {widths(1)}")

    print("B/C  arrival — the tab a pane ARRIVES in")
    d_before = widths(2)
    kit("action", "--match", f"id:{A[-1]}", "layout_action", "equalize"); time.sleep(0.6)
    check("--match is a no-op (control)", widths(2) == d_before,
          f"{d_before} -> {widths(2)}  (rc 0, empty stderr — this is why rc is never asserted)")
    kit("action", "--self", "layout_action", "equalize", KITTY_WINDOW_ID=str(A[-1])); time.sleep(0.6)
    check("--self equalizes the destination", spread(widths(2)) == 0, f"{d_before} -> {widths(2)}")

    print("D  scope + focus")
    check("uninvolved tab untouched", widths(3) == c_before, f"{c_before} -> {widths(3)}")
    foc = [o["id"] for o in json.loads(kit("ls").stdout) if o.get("is_focused")]
    check("focus never moved", foc == [1], f"focused os-window {foc} (must stay 1, never the destination)")

    teardown()
    print(f"\nVERDICT: {'PASS — panes even themselves out on both paths' if not fails else 'FAIL: ' + ', '.join(fails)}")
    return 1 if fails else 0

if __name__ == "__main__":
    sys.exit(main())
