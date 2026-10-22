#!/usr/bin/env python3
"""Narrow-pane probe for the accounts board band (and, with --readout, the /accounts readout) in
REAL Claude Code: start at 80 columns, resize through 40 34 30 27 22 20 17 15 12 and back to 80,
and after every step dump the whole terminal screen (colours kept) and snap it to a PNG.

usage: narrow-probe.py <arm: band|trunk> <rows: fx|live> <out dir> [--rows N] [--readout]
                       [--widths 80,40,...]
  band   this checkout's bin/claude-accounts (producer) + mods/accounts-readout
  trunk  `git show origin/main:` copies of bin/claude-accounts and mods/accounts-readout (TRUNK_REF
         overrides the ref); hooks/accounts-board.sh is this checkout's (asserted equal to trunk's)
  fx     the width-sweep bats FIXTURE rows (tests/accounts-width-sweep.bats: a 61-char account
         name, a stale row, a wire-rejected 5h at 100%, a login cliff)
  live   the shape of a live account cache (NARROW_LIVE_CACHE, default
         /tmp/narrow-design/synth/cache.json, read only): its four rows and window, every *_at
         shifted by (now - its ts) so the countdowns read as they did when it was swept
  --rows N     pane height (default 45)
  --readout    after the band (and its first prompt), have the model run the /accounts readout
               over the same rows, then sweep the same widths again with the readout on screen

Method, as docs/research/accounts-board-band-2026-10-21/board-probe.py: a real pty.fork() of
Claude Code 2.1.293 (~/.claude-293), TIOCSWINSZ for the geometry (the kernel sends SIGWINCH), pyte
as the terminal. Settings come from --settings only (`--setting-sources project`, empty project
dir), so no fleet hook runs and no shared settings file is touched; no slash command is typed. A
fresh board is produced for each run by the arm's producer over the chosen rows, into scratch
(CC_ACCOUNTS_BOARD, CC_PANE_DIR, HOME, the account config and its cache all under
/tmp/narrow-verify/probe/<arm>-<rows>/), so the live fleet's files are never read or written.

The screen is ONE persistent pyte terminal, resized at the same instant as the pty, so each
capture is what a terminal of that size shows after Claude Code's own repaint (it repaints the
whole frame on SIGWINCH). Each step also types two letters into the prompt and reads them back
(then deletes them), to show the input is still usable at that width.

The measure, per step: the expected values are read off the producer's widest grid by its own
header columns (as tests/accounts-width-sweep.bats test 11 does). On screen, each account's name
must appear whole, and its 5h used, 5h reset, weekly used and weekly reset must each sit whole
inside ONE screen row, in that order after the name. Also counted: ellipses, rows that run to
the right edge, whether the band is taller than the screen, whether the picks block is visible,
whether the prompt input echoes. Writes captures/*.json|txt|png and verdict.json to <out dir>.
Needs: pyte (/tmp/acct-probe/venv), agent-browser (for the PNGs), /tmp/narrow-design/snap.py.
"""

import fcntl, json, os, pty, re, select, shutil, struct, subprocess, sys, termios, time
import unicodedata

import pyte

sys.path.insert(0, "/tmp/narrow-design")
import snap  # noqa: E402  (dump_screen, and snap.py --screen for the PNG)

a = sys.argv[1:]


def opt(name, default):
    if name in a:
        i = a.index(name)
        v = a[i + 1]
        del a[i : i + 2]
        return v
    return default


ROWS = int(opt("--rows", "45"))
WIDTHS = [
    int(x) for x in opt("--widths", "80,40,34,30,27,22,20,17,15,12,80").split(",")
]
READOUT = "--readout" in a
if READOUT:
    a.remove("--readout")
# Round 4: the readout sweep may use its own widths (the brief asks for 40 and 20 only)
RWIDTHS = [int(x) for x in opt("--readout-widths", "").split(",") if x] or None
ARM, DATA, OUT = a[0], a[1], os.path.abspath(a[2])
assert ARM in ("band", "trunk") and DATA in ("fx", "live"), a

CLAUDE = os.path.expanduser("~/.claude-293/node_modules/.bin/claude")
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SNAP_PY = ["/tmp/acct-probe/venv/bin/python", "/tmp/narrow-design/snap.py"]
LIVE_CACHE = os.environ.get("NARROW_LIVE_CACHE", "/tmp/narrow-design/synth/cache.json")
P = f"/tmp/narrow-verify/probe/{ARM}-{DATA}" + os.environ.get(
    "NARROW_TAG", ""
)  # scratch per run
CAP = OUT
SGR = re.compile(r"\x1b\[[0-9;]*m")
LONG = "next-quaternary-extremely-long-account-name-for-width-testing"

if os.path.isdir(P):
    shutil.rmtree(P)  # this run's own scratch only
for d in (
    OUT,
    CAP,
    f"{P}/work",
    f"{P}/board",
    f"{P}/pane",
    f"{P}/sh-empty",
    f"{P}/home",
    f"{P}/state",
    f"{P}/arm",
):
    os.makedirs(d, exist_ok=True)
BOARD = f"{P}/board/board.txt"

# ── the arm: whose producer and whose mod ────────────────────────────────────────────────────
if ARM == "trunk":
    ref = os.environ.get("TRUNK_REF", "origin/main")
    git = lambda *x: subprocess.run(
        ["git", "-C", REPO, *x], capture_output=True, check=True
    )
    open(f"{P}/arm/claude-accounts", "wb").write(
        git("show", f"{ref}:bin/claude-accounts").stdout
    )
    tar = git("archive", ref, "mods/accounts-readout").stdout
    subprocess.run(["tar", "-x", "-C", f"{P}/arm"], input=tar, check=True)
    BIN, MOD_DIR = f"{P}/arm/claude-accounts", f"{P}/arm/mods/accounts-readout"
    same = subprocess.run(
        [
            "git",
            "-C",
            REPO,
            "diff",
            "--quiet",
            ref,
            "--",
            "hooks/accounts-board.sh",
            "hooks/relay-verbatim.sh",
        ]
    )
    assert same.returncode == 0, (
        "the hooks differ from trunk: this arm would mix versions"
    )
else:
    # Round 4: a SNAPSHOT of this checkout's producer and mod, taken at the start, so a sibling
    # editing the worktree mid-run (or the mod's hot reload) cannot mix two versions in one run.
    shutil.copy(
        os.path.join(REPO, "bin", "claude-accounts"), f"{P}/arm/claude-accounts"
    )
    shutil.copytree(
        os.path.join(REPO, "mods", "accounts-readout"),
        f"{P}/arm/mods/accounts-readout",
        ignore=shutil.ignore_patterns("node_modules", ".git"),
    )
    BIN, MOD_DIR = f"{P}/arm/claude-accounts", f"{P}/arm/mods/accounts-readout"
    # Round 4 experiment, scratch copy only: NARROW_ROOM_FULL=1 lets the mod fill all `maxRows`
    # rows instead of keeping the cue row free, to test whether a tree of exactly maxRows rows
    # shows whole (no `↓ N more`) on Claude Code 2.1.293.
    # Round 5: the mod itself now fills `maxRows` (room = maxRows), so this patch applies only to
    # a mod from before it.
    if (
        os.environ.get("NARROW_ROOM_FULL") == "1"
        and "maxRows - 1 - headRows" in open(f"{MOD_DIR}/hooks/ladder.ts").read()
    ):
        lp = f"{MOD_DIR}/hooks/ladder.ts"
        t = open(lp).read()
        t2 = t.replace("maxRows - 1 - headRows", "maxRows - headRows").replace(
            "maxRows > 0 ? maxRows - 1 : Infinity", "maxRows > 0 ? maxRows : Infinity"
        )
        assert t2 != t and "maxRows - 1" not in t2, "ladder.ts room expressions moved"
        open(lp, "w").write(t2)
HOOK = os.path.join(REPO, "hooks", "accounts-board.sh")
RELAY = os.path.join(REPO, "hooks", "relay-verbatim.sh")


def _sha(path):
    import hashlib

    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]


PROVENANCE = {
    "bin/claude-accounts": _sha(BIN),
    "hooks/accounts-board.sh": _sha(HOOK),
    "hooks/relay-verbatim.sh": _sha(RELAY),
    **{
        f"mods/accounts-readout/{os.path.relpath(os.path.join(d, f), MOD_DIR)}": _sha(
            os.path.join(d, f)
        )
        for d, _, fs in os.walk(MOD_DIR)
        for f in fs
        if f.endswith((".ts", ".tsx", ".json"))
    },
}

# ── the rows, written as a cache the producer and the readout both read ──────────────────────
now = time.time()
if DATA == "fx":
    src = open(os.path.join(REPO, "tests", "accounts-width-sweep.bats")).read()
    fx = re.search(r"FIXTURE='\n(.*?)'\n", src, re.S).group(1)
    ns = {}
    exec(
        "from datetime import datetime, timedelta, timezone\n"
        + "\n".join(ln[4:] if ln.startswith("    ") else ln for ln in fx.splitlines()),
        ns,
    )
    rows, window, ts = ns["rows"], {}, now - 75
    names = [r["acct"] for r in rows]
    accts = [(r["acct"], r["launcher"], f"x{i}") for i, r in enumerate(rows)]
else:
    from datetime import datetime, timedelta

    c = json.load(open(LIVE_CACHE))
    shift = now - 75 - c["ts"]

    def mv(v):
        if isinstance(v, str) and re.match(r"^\d{4}-\d\d-\d\dT", v):
            try:
                return (
                    datetime.fromisoformat(v) + timedelta(seconds=shift)
                ).isoformat()
            except ValueError:
                return v
        if isinstance(v, dict):
            return {k: mv(x) for k, x in v.items()}
        if isinstance(v, list):
            return [mv(x) for x in v]
        return v

    rows = [
        {
            k: (
                mv(v)
                if k.endswith("_at") or isinstance(v, (dict, list))
                else (
                    v + shift
                    if k.endswith(("_as_of", "_read_at", "_sids_at"))
                    and isinstance(v, (int, float))
                    else v
                )
            )
            for k, v in r.items()
        }
        for r in c["rows"]
    ]
    window, ts = mv(c.get("window") or {}), now - 75
    names = [r["acct"] for r in rows]
    accts = [(r["acct"], r.get("launcher") or "claude", r["acct"]) for r in rows]

real = json.load(open(os.path.join(REPO, "accounts.json")))
CFG, CACHE = f"{P}/state/acct.json", f"{P}/state/cache.json"
json.dump(
    {
        "keychain_account": "test",
        "oauth_scopes": "x",
        "usage_endpoint": "http://127.0.0.1:9/never",
        "token_endpoint": "http://127.0.0.1:9/never",
        "user_agent": "test",
        "claude_bin": "/nonexistent/claude",
        "model_config_ssot": "/nonexistent/model-config.yaml",
        "dia_local_state": "/nonexistent/LS",
        "cache_file": CACHE,
        "cache_ttl_s": real["cache_ttl_s"],
        "lock_wait_s": real["lock_wait_s"],
        "cache_grace_s": real["cache_grace_s"],
        "login_warn_h": real["login_warn_h"],
        "frontier": real["frontier"],
        "router": real["router"],
        "accounts": [
            {
                "name": n,
                "config_dir": f"/tmp/narrow-probe-nonexistent-{x}",
                "launcher": l,
                "email": f"{x}@example.com",
                "mailbox": f"{x}@example.com",
                "dia_profile": x,
            }
            for n, l, x in accts
        ],
    },
    open(CFG, "w"),
)
ROWSF = f"{P}/state/rows.json"
json.dump({"ts": ts, "rows": rows, "window": window}, open(ROWSF, "w"))

# The board, from the arm's producer: the same three functions keepwarm calls, over these rows.
DRIVER = r"""
import json, sys
ns = {"__name__": "narrow_probe"}
exec(compile(open(sys.argv[1]).read(), sys.argv[1], "exec"), ns)
cfg = ns["load_cfg"](need_claude_bin=False)
d = json.load(open(sys.argv[2]))
rows, wj, q = d["rows"], d["window"], d["ts"]
json.dump({"ts": q, "rows": rows, "window": wj, "cfg_key": ns["_cfg_key"](cfg)}, open(cfg["cache_file"], "w"))
print(ns["write_board"](cfg, ns["_render_board"](cfg, rows, wj, True, quota_ts=q),
      sig=ns["_board_sig"](rows), producer="narrow-probe",
      variants=ns["_board_variants"](cfg, rows, wj, True, quota_ts=q),
      ladder=ns["_board_ladder"](cfg, rows, wj, True, quota_ts=q)))
"""
penv = {
    **os.environ,
    "CLAUDE_ACCOUNTS_JSON": CFG,
    "CC_ACCOUNTS_BOARD": BOARD,
    "HOME": f"{P}/home",
    "CC_STARTUP_HEALTH_DIR": f"{P}/sh-empty",
    "CLAUDE_CODE_SESSION_ID": "",
    "CC_IDENTITY_FILE": "/nonexistent",
}
kw = subprocess.run(
    ["python3", "-c", DRIVER, BIN, ROWSF], env=penv, capture_output=True, text=True
)
assert kw.stdout.strip() == BOARD, kw.stdout + kw.stderr
LADDER = json.load(open(BOARD + ".ladder.json"))
shutil.copy(BOARD + ".ladder.json", f"{OUT}/board.ladder.json")
# What the snapshot mod's own bandLayout picks over this ladder, per band width and height (the
# measured maxRows: 10 / 17 / 30 rows on a 30 / 45 / 70-row pane), for summarize.py to compare.
_pred = subprocess.run(
    [
        "bun",
        os.path.join(HERE, "predict.ts"),
        f"{MOD_DIR}/hooks/ladder.ts",
        f"{OUT}/board.ladder.json",
    ],
    capture_output=True,
    text=True,
)
open(f"{OUT}/mod-prediction.json", "w").write(
    _pred.stdout or json.dumps({"error": _pred.stderr})
)

# The readout wrapper (--readout): the arm's renderer with get_data() replaced by these rows. Its
# name carries `claude-accounts`, so relay-verbatim.sh and the mod treat it as the readout.
WRAP = f"{P}/claude-accounts-probe"
open(WRAP, "w").write(f"""#!/bin/bash
# probe-only: the /accounts readout over {ROWSF}, from {BIN}
export CLAUDE_ACCOUNTS_JSON={CFG} HOME={P}/home CC_IDENTITY_FILE=/nonexistent
exec python3 - {BIN} "$@" <<'PY2'
import subprocess, sys
src = open(sys.argv[1]).read()
anchor = "rows, wj, cached, prev = get_data(cfg, fresh, no_heal, max_wait, max_age)"
new = src.replace(anchor, "_d = json.load(open({ROWSF!r})); rows, wj, cached, prev = "
                          "_d['rows'], _d['window'], True, None")
assert new != src, "anchor moved"
p = subprocess.run([sys.executable, "-c", new] + sys.argv[2:], capture_output=True, text=True)
sys.stderr.write(p.stderr); sys.stdout.write(p.stdout); sys.exit(p.returncode)
PY2
""")
os.chmod(WRAP, 0o755)


# ── the expected values: the widest grid, read by its own header columns ──────────────────────
def expected(L):
    wide = [SGR.sub("", x).replace("\xa0", " ") for x in L["variants"][-1]["lines"]]
    hi = next(
        i for i, l in enumerate(wide) if re.search(r"\b(account|acct)\s+live\b", l)
    )
    ends = [m.end() for m in re.finditer(r"\b(used|resets)\b", wide[hi])][:4]
    want = {}
    for l in wide[hi + 1 :]:
        if not l.strip():
            break
        toks = l[3:].split()
        n = (
            toks[0]
            if toks[0] in names
            else next(
                (
                    x
                    for x in names
                    if toks[0].endswith("…") and x.startswith(toks[0][:-1])
                ),
                None,
            )
        )
        if n:
            want[n] = [re.findall(r"(\S+(?: \d+[hm])?)$", l[:e])[0] for e in ends]
    assert set(want) == set(names), (want, names)
    return want


WANT = expected(LADDER)
RWANT = [None]
json.dump(WANT, open(f"{OUT}/expected.json", "w"), indent=1, ensure_ascii=False)

# ── Claude Code ──────────────────────────────────────────────────────────────────────────────
settings = {
    "hooks": {
        "SessionStart": [{"hooks": [{"type": "command", "command": HOOK}]}],
        "PostToolUse": [
            {"matcher": "Bash", "hooks": [{"type": "command", "command": RELAY}]}
        ],
    },
    "permissions": {"allow": [f"Bash({WRAP}:*)"]},
}
args = [
    CLAUDE,
    "--setting-sources",
    "project",
    "--settings",
    json.dumps(settings),
    "--model",
    "claude-haiku-5-5",
    "--plugin-dir",
    MOD_DIR,
]

pid, fd = pty.fork()
if pid == 0:
    os.chdir(f"{P}/work")
    os.environ.update(
        {
            "TERM": "xterm-256color",
            "CC_ACCOUNTS_BOARD": BOARD,
            "CC_PANE_DIR": f"{P}/pane",
            "CC_STARTUP_HEALTH_DIR": f"{P}/sh-empty",
            # Round 4: NARROW_STALE_S / NARROW_HARD_S set the mod's staleness bands for this run
            # only. A full sweep outlives the default 300 s, after which the mod puts a stale head
            # over the band; a large value measures the fresh band at every width, 1 forces the head.
            **(
                {"CC_BOARD_STALE_S": os.environ["NARROW_STALE_S"]}
                if os.environ.get("NARROW_STALE_S")
                else {}
            ),
            **(
                {"CC_BOARD_HARD_S": os.environ["NARROW_HARD_S"]}
                if os.environ.get("NARROW_HARD_S")
                else {}
            ),
        }
    )
    # Nothing of the launching session leaks in: its ids, its messaging socket, its child marker
    # (which turns transcript saving off and adds a footer row). CLAUDE_CONFIG_DIR (the login) and
    # CLAUDE_CODE_NO_FLICKER (the operator's fullscreen renderer) are kept on purpose.
    for k in list(os.environ):
        if k in ("CLAUDECODE", "CLAUDE_PID", "CC_PANE_COLS") or (
            k.startswith("CLAUDE_CODE_")
            and k not in ("CLAUDE_CODE_NO_FLICKER", "CLAUDE_CODE_EAGER_FLUSH")
        ):
            os.environ.pop(k, None)
    os.execv(CLAUDE, args)

scr = pyte.Screen(WIDTHS[0], ROWS)
stream = pyte.ByteStream(scr)
raw = bytearray()


def setsize(cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, cols, 0, 0))
    scr.resize(ROWS, cols)


def pump(sec):
    t = time.time()
    while time.time() - t < sec:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                d = os.read(fd, 65536)
            except OSError:
                return
            if not d:
                return
            raw.extend(d)
            stream.feed(d)


def lines():
    return [ln.rstrip().replace("\xa0", " ") for ln in scr.display]


def settle(quiet, cap):
    """Read until the screen has not changed for `quiet` seconds (at most `cap`)."""
    t0, last, t_last = time.time(), None, time.time()
    while time.time() - t0 < cap:
        pump(0.2)
        cur = lines()
        if cur != last:
            last, t_last = cur, time.time()
        elif time.time() - t_last >= quiet:
            return


def wait_for(pat, sec):
    t = time.time()
    while time.time() - t < sec:
        pump(0.5)
        if re.search(pat, "\n".join(lines())):
            return True
    return False


def cells(t):
    return sum(
        0
        if unicodedata.combining(c)
        else 2
        if unicodedata.east_asian_width(c) in ("W", "F")
        else 1
        for c in t
    )


# CC cuts its own cue at 17 columns ("↑ 1 more · ↓ 26 …"), so the count alone marks it
CUE = re.compile(r"[↑↓] \d+")
LEAD = re.compile(r"^[\s➤ᵍ⎿]*")
VALS = ["5h_used", "5h_reset", "wk_used", "wk_reset"]


def prompt_row(rs):
    """The input row: the last row starting with the prompt glyph."""
    idx = [i for i, r in enumerate(rs) if re.match(r"^\s*❯", r)]
    return idx[-1] if idx else None


def rule_row(rs):
    """The composer's top rule: the last-but-one full rule above the prompt row."""
    pr = prompt_row(rs)
    if pr is None:
        return len(rs)
    up = [i for i in range(pr) if re.fullmatch(r"─{4,}", rs[i].strip())]
    return up[-1] if up else pr


def band_region(rs):
    """(top, bottom) of the band on screen: from its first `➤` row to the cue or the rule."""
    end = rule_row(rs)
    # Round 4: the band's top row carries its `[-]` collapse mark, a head (`⚠ stale 6m`) included
    top = next((i for i in range(end) if rs[i].rstrip().endswith("[-]")), None)
    if top is None:
        top = next((i for i in range(end) if rs[i].lstrip().startswith("➤")), None)
    if top is None:
        return None
    cue = next((i for i in range(top, end) if CUE.search(rs[i])), None)
    return top, (cue if cue is not None else end)


def logical(rs):
    """Rows with a hyphen-broken word re-joined (a 61-char name wraps at its hyphens)."""
    out = []
    for r in rs:
        if (
            out
            and out[-1].endswith("-")
            and r.strip()
            and not r.strip().startswith("-")
        ):
            out[-1] = out[-1] + r.strip()
        else:
            out.append(r)
    return out


def head_name(row):
    t = LEAD.sub("", row).split()
    if not t:
        return None
    for n in names:
        if t[0] == n or (
            t[0].endswith("…") and n.startswith(t[0][:-1]) and len(t[0]) > 2
        ):
            return n
    return None


def accounts(rs, want=None):
    want = want or WANT
    """Per account: its name row (whole or …-cut) and each of its four values found WHOLE inside
    one row of its own block, in order (5h used, 5h reset, weekly used, weekly reset)."""
    lr = logical(rs)
    starts = {}
    for i, r in enumerate(lr):
        n = head_name(r)
        if n and n not in starts:
            starts[n] = i
    acc = {}
    for n in names:
        if n not in starts:
            acc[n] = {"name": "absent", **{k: False for k in VALS}, "whole": False}
            continue
        i = starts[n]
        seg = [lr[i]]
        for r in lr[i + 1 :]:
            if not r.strip() or head_name(r) or CUE.search(r):
                break
            seg.append(r)
        blob, pos, got = "\n".join(seg), 0, {}
        first = LEAD.sub("", lr[i]).split()[0]
        pos = blob.index(first) + len(first)
        for k, v in zip(VALS, want[n]):
            # Round 4: a countdown counts whole as `4h 43m` (the grid) or `4h43m` (the narrow
            # forms print it as one token); the oracle used to read the latter as missing.
            pat = r"[ ]?".join(re.escape(x) for x in v.split(" "))
            m = re.compile(r"(?<!\S)" + pat + r"(?!\S)").search(blob, pos)
            got[k] = bool(m)
            if m:
                pos = m.end()
        nm = "whole" if first == n else "cut…"
        acc[n] = {"name": nm, **got, "whole": nm == "whole" and all(got.values())}
    return acc


def readout_region(rs):
    """The readout under its shell-command row, down to the model's reply."""
    end = next((i for i, r in enumerate(rs) if r.startswith("⏺ BRAVO")), rule_row(rs))
    heads = [i for i in range(end) if re.search(r"Ran \d+ shell command", rs[i])]
    return (heads[-1] + 1 if heads else 0), end


def readout_want():
    """Expected values for the readout: its OWN ladder (it renders minutes after the board)."""
    lads = [
        f
        for f in os.listdir(f"{P}/pane")
        if f.endswith(".ladder.json") and "board" not in f
    ]
    if not lads:
        return None
    f = max((os.path.join(f"{P}/pane", x) for x in lads), key=os.path.getmtime)
    return expected(json.load(open(f)))


def measure(rs, cols, band=True):
    reg = band_region(rs) if band else readout_region(rs)
    sub = rs[reg[0] : reg[1]] if reg else []
    acc = accounts(sub, None if band else (RWANT[0] or WANT))
    cue = [r.strip() for r in rs if CUE.search(r)]
    return {
        "cols": cols,
        "region_rows": len(sub),
        "accounts": acc,
        "visible_all_whole": all(v["whole"] for v in acc.values()),
        "values_all_whole": all(all(v[k] for k in VALS) for v in acc.values()),
        "ellipsis_rows": [r for r in sub if "…" in r],
        "edge_rows": [r for r in sub if cells(r) >= cols],
        "cue": cue,
        "picks_visible": bool(re.search(r"desk(\s|\([^)]*\))*→", "\n".join(sub)))
        and bool(re.search(r"general\s*→", "\n".join(sub))),
        "prompt_row": prompt_row(rs),
    }


def norm(rs):
    """A window's rows less the band's [-] collapse mark, which rides its top row."""
    return [r.replace("[-]", "   ").rstrip() for r in rs]


GAPS = [0]


def stitch(pages):
    """Join scrolled windows of one band by their overlap."""
    acc = list(pages[0])
    for p in pages[1:]:
        k = next(
            (k for k in range(min(len(acc), len(p)), 0, -1) if acc[-k:] == p[:k]), 0
        )
        GAPS[0] += (
            k == 0
        )  # a step that jumped past the window: rows never seen (counted)
        acc += p[k:]
    return acc


def scroll_band(name, cols):
    """Scroll the band to its end by the mouse wheel over it (as the operator would), else by the
    keyboard (ctrl+x tab focuses the band, then page down), stitching every window; then return
    to the top and to the composer. Returns (method, stitched rows, pages)."""
    rs = lines()
    reg = band_region(rs)
    if reg is None:
        settle(1.5, 10)
        rs = lines()
        reg = band_region(rs)
    if reg is None:
        return None, [], 0, False
    top, bot = reg
    win = bot - top
    pages, dumps = [norm(rs[top:bot])], [snap.dump_screen(scr)["rows"][top:bot]]
    method, reached = None, [False]
    for attempt in ("wheel", "keys"):
        if attempt == "keys":
            os.write(fd, b"\x18")
            pump(0.2)
            os.write(fd, b"\t")
            pump(1.0)
        still = 0
        for _ in range(80):
            if attempt == "wheel":
                os.write(fd, f"\x1b[<65;{max(1, cols // 2)};{top + 2}M".encode())
            else:
                os.write(fd, b"\x1b[B" * max(1, win // 3))
            settle(0.6, 6)
            now_rs = lines()
            reg = band_region(now_rs) or (rule_row(now_rs) - win, rule_row(now_rs))
            b = next((i for i in range(len(now_rs)) if CUE.search(now_rs[i])), reg[1])
            page = norm(now_rs[b - win : b])
            if page == pages[-1]:
                still += (
                    1  # a loaded machine can lag a step: three quiet steps is the end
                )
                if still >= 3:
                    reached[0] = method is not None
                    break
                continue
            still = 0
            pages.append(page)
            dumps.append(snap.dump_screen(scr)["rows"][b - win : b])
            method = attempt
            # no end test on the cue: at 15 columns and under CC cuts its own cue to "↑ 10 more · ↓ …"
        if method:
            break
    json.dump(
        snap.dump_screen(scr),
        open(f"{CAP}/{name}-scrolled-end.json", "w"),
        ensure_ascii=False,
    )
    open(f"{CAP}/{name}-scrolled-end.txt", "w").write("\n".join(lines()))
    order_png.append(f"{name}-scrolled-end")
    # back to the top, and the composer
    if method == "wheel":
        for _ in range(60):
            os.write(fd, f"\x1b[<64;{max(1, cols // 2)};{top + 2}M".encode() * 3)
            pump(0.15)
    else:
        os.write(fd, b"\x1b[H" + b"\x1b[A" * 400)
        pump(1.0)
        os.write(fd, b"\x1b")
    pump(1.5)
    GAPS[0] = 0
    full = stitch(pages)
    # the stitched band as one screen dump, for its own PNG (row text keys the overlap)
    rows_d, seen = [], []
    for pg, dp in zip(pages, dumps):
        k = next(
            (k for k in range(min(len(seen), len(pg)), 0, -1) if seen[-k:] == pg[:k]), 0
        )
        seen += pg[k:]
        rows_d += dp[k:]
    json.dump(
        {"cols": cols, "rows": rows_d},
        open(f"{CAP}/{name}-band-whole.json", "w"),
        ensure_ascii=False,
    )
    order_png.append(f"{name}-band-whole")
    return method, full, len(pages), reached[0]


steps, order, order_png = {}, [], []


def scroll_transcript(name, cols):
    """Round 4: the readout has no height cap and can be taller than the screen, so wheel the
    transcript UP from the bottom until it stops moving, stitch the views (newest at the bottom),
    write `*-transcript-whole.*`, and wheel back down. Pages are the rows above the composer."""
    end = rule_row(lines())
    pages = [norm(lines()[:end])]
    dumps = [snap.dump_screen(scr)["rows"][:end]]
    still = 0
    for _ in range(60):
        os.write(fd, f"\x1b[<64;{max(1, cols // 2)};3M".encode() * 3)
        settle(0.6, 6)
        e2 = rule_row(lines())
        pg = norm(lines()[:e2])
        if pg == pages[-1]:
            still += 1
            if still >= 3:
                break
            continue
        still = 0
        pages.append(pg)
        dumps.append(snap.dump_screen(scr)["rows"][:e2])
    for _ in range(60):
        os.write(fd, f"\x1b[<65;{max(1, cols // 2)};3M".encode() * 3)
        pump(0.15)
    pump(1.5)
    acc, accd = list(pages[0]), list(dumps[0])
    gaps = 0
    for pg, dp in zip(pages[1:], dumps[1:]):
        k = next(
            (k for k in range(min(len(acc), len(pg)), 0, -1) if pg[-k:] == acc[:k]), 0
        )
        gaps += k == 0
        acc = pg[: len(pg) - k] + acc
        accd = dp[: len(dp) - k] + accd
    open(f"{CAP}/{name}-transcript-whole.txt", "w").write("\n".join(acc))
    json.dump(
        {"cols": cols, "rows": accd},
        open(f"{CAP}/{name}-transcript-whole.json", "w"),
        ensure_ascii=False,
    )
    order_png.append(f"{name}-transcript-whole")
    reg = readout_region(acc)
    sub = acc[reg[0] : reg[1]]
    a2 = accounts(sub, RWANT[0] or WANT)
    return {
        "pages": len(pages),
        "stitch_gaps": gaps,
        "rows": len(acc),
        "accounts": a2,
        "all_whole": all(v["whole"] for v in a2.values()),
        "ellipsis_rows": [r for r in sub if "…" in r],
        "edge_rows": [r for r in sub if cells(r) >= cols],
    }


def capture(name, cols, band=True, check_input=True):
    pump(0.5)
    rs = lines()
    json.dump(
        snap.dump_screen(scr), open(f"{CAP}/{name}.json", "w"), ensure_ascii=False
    )
    open(f"{CAP}/{name}.txt", "w").write("\n".join(rs))
    order_png.append(name)
    m = measure(rs, cols, band)
    if band and any("↓" in c for c in m["cue"]):
        method, full, npages, at_end = scroll_band(name, cols)
        open(f"{CAP}/{name}-band-whole.txt", "w").write("\n".join(full))
        acc = accounts(full)
        m["scroll"] = {
            "method": method,
            "pages": npages,
            "reached_end": at_end,
            "stitch_gaps": GAPS[0],
            "band_rows": len(full),
            "reachable_all_whole": all(v["whole"] for v in acc.values()),
            "reachable": acc,
            "ellipsis_rows": [r for r in full if "…" in r],
            "edge_rows": [r for r in full if cells(r) >= cols],
        }
        back = band_region(lines())
        m["scroll"]["back_at_top"] = bool(back) and lines()[
            back[0]
        ].lstrip().startswith("➤ ")
    if not band:
        m["transcript"] = scroll_transcript(name, cols)
    if check_input:
        os.write(fd, b"zq")
        pump(1.5)
        after = lines()
        pr = prompt_row(after)
        m["input_echo"] = pr is not None and "zq" in after[pr]
        os.write(fd, b"\x7f\x7f")
        pump(1.0)
    steps[name] = m
    order.append(name)


# Startup took 8-40 s on the loaded desk (2026-10-22), so the folder-trust prompt is answered
# whenever it shows, never on a fixed clock: a late prompt left to the first resize step read
# the step's own keys as "No, exit".
# NARROW_START_S widens the bound (round 3: two runs at load ~250 drew 0 bytes in 150 s).
START_S = int(os.environ.get("NARROW_START_S", "90"))
wait_for(r"trust this folder|\d+%", START_S)
if "trust this folder" in "\n".join(lines()):
    os.write(fd, b"\x1b[B")
    pump(0.5)
    os.write(fd, b"\r")
setsize(WIDTHS[0])
ok_start = wait_for(r"\d+%", max(60, START_S // 2))
if (
    not ok_start
):  # measured 2026-10-22: a keychain read blocked startup for minutes under load
    os.kill(pid, 9)
    sys.exit(
        f"Claude Code drew no board ({len(raw)} bytes) (startup blocked?): no verdict"
    )
pump(3)
# Round 4: NARROW_IDLE_S idles at the first width before the sweep, so the band ages past the
# mod's stale band (300 s) with a board that was FRESH at start (the hook's band path) and the
# mod's own stale head is what gets measured.
pump(float(os.environ.get("NARROW_IDLE_S", "0")))

for i, cols in enumerate(WIDTHS):
    setsize(cols)
    pump(2)
    settle(1.5, 15)
    capture(f"band-{i:02d}-{cols}", cols)

os.write(fd, b"Reply with only the word ALPHA.")
pump(1)
os.write(fd, b"\r")
ok_prompt = wait_for(r"⏺ ALPHA", 120)
pump(3)
capture("band-after-prompt", WIDTHS[-1], check_input=False)

ok_readout = None
if READOUT:
    os.write(
        fd,
        (
            f"Run exactly this one shell command and nothing else, then reply with only "
            f"the word BRAVO: {WRAP} --readout --no-agents --max-wait 0"
        ).encode(),
    )
    pump(1)
    os.write(fd, b"\r")
    ok_readout = wait_for(r"⏺ BRAVO", 180)
    pump(4)
    RWANT[0] = readout_want()
    json.dump(
        RWANT[0],
        open(f"{OUT}/expected-readout.json", "w"),
        indent=1,
        ensure_ascii=False,
    )
    lads = [
        f
        for f in os.listdir(f"{P}/pane")
        if f.endswith(".ladder.json") and "board" not in f
    ]
    if lads:
        shutil.copy(
            max((os.path.join(f"{P}/pane", x) for x in lads), key=os.path.getmtime),
            f"{OUT}/readout.ladder.json",
        )
    for i, cols in enumerate(RWIDTHS or WIDTHS):
        setsize(cols)
        pump(2)
        settle(1.5, 15)
        capture(f"readout-{i:02d}-{cols}", cols, band=False, check_input=False)

os.write(fd, b"\x03")
pump(0.5)
os.write(fd, b"\x03")
pump(1)
try:
    os.kill(pid, 9)
except OSError:
    pass
os.waitpid(pid, 0)
open(f"{CAP}/raw.bin", "wb").write(bytes(raw))

# PNGs, after the session (agent-browser is slow; the screens were dumped at capture time)
for name in order_png:
    subprocess.run(
        SNAP_PY
        + [
            "--screen",
            f"{CAP}/{name}.json",
            f"{CAP}/{name}.png",
            "--title",
            f"{ARM} arm, {DATA} rows, {ROWS} rows tall, {name}",
            "--session",
            f"narrow-probe-{ARM}-{DATA}{os.environ.get('NARROW_TAG', '')}",
        ],
        capture_output=True,
    )

band = {
    k: v for k, v in steps.items() if k.startswith("band-") and k != "band-after-prompt"
}
reach = lambda v: (
    v["visible_all_whole"] or bool(v.get("scroll", {}).get("reachable_all_whole"))
)
verdict = {
    "arm": ARM,
    "rows": DATA,
    "cc": "2.1.293",
    "pane_rows": ROWS,
    "widths": WIDTHS,
    "ladder_cells": [v["cells"] for v in LADDER["variants"]],
    "provenance_sha256_16": PROVENANCE,
    "stale_s": os.environ.get("NARROW_STALE_S") or "default (300)",
    "turns_ok": {
        "band_drawn": ok_start,
        "first_prompt": ok_prompt,
        "readout": ok_readout,
    },
    "expected": WANT,
    "steps": steps,
    "band_gone_after_prompt": steps["band-after-prompt"]["region_rows"] == 0,
    "band_every_value_whole_reachable_every_width": all(
        reach(v) for v in band.values()
    ),
    "band_every_value_whole_visible_without_scroll": {
        k: v["visible_all_whole"] for k, v in band.items()
    },
    "band_no_ellipsis_every_width": all(
        not v["ellipsis_rows"] and not v.get("scroll", {}).get("ellipsis_rows")
        for v in band.values()
    ),
    "input_echo_every_width": all(v.get("input_echo") for v in band.values()),
}
json.dump(verdict, open(f"{OUT}/verdict.json", "w"), indent=1, ensure_ascii=False)
print(f"verdict arm={ARM} rows={DATA} pane_rows={ROWS} turns={verdict['turns_ok']}")
for k in order:
    v = steps[k]
    sc = v.get("scroll")
    bad = [n[:12] for n, x in v["accounts"].items() if not x["whole"]]
    print(
        f"  {k:20s} visible_whole={v['visible_all_whole']!s:5s} bad={bad} "
        f"ell={len(v['ellipsis_rows'])} edge={len(v['edge_rows'])} cue={v['cue']} "
        f"picks={v['picks_visible']} input={v.get('input_echo')}"
        + (
            f" | scroll={sc['method']} pages={sc['pages']} band_rows={sc['band_rows']} "
            f"reach_whole={sc['reachable_all_whole']} ell={len(sc['ellipsis_rows'])} "
            f"edge={len(sc['edge_rows'])} back_top={sc['back_at_top']}"
            if sc
            else ""
        )
    )
