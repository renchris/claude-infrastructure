"""observe.py / observe_rows.py: hermetic census tests — fake ps, fake kitten, temp home (§C3)."""

import glob
import json
import os
import shutil
import stat
import tempfile
import unittest
from types import SimpleNamespace

from lr_recon import observe as O
from lr_recon import observe_rows as R
from lr_recon import types as T

L = "Tue Sep 29 11:19:17 2026"
SIDA, SIDB, SIDC = (
    "aaaa1111-0000-4000-8000-000000000001",
    "bbbb2222-0000-4000-8000-000000000002",
    "cccc3333-0000-4000-8000-000000000003",
)
SIDBG, SIDD = (
    "dddd4444-0000-4000-8000-000000000004",
    "eeee5555-0000-4000-8000-000000000005",
)
SNAP = "/h/.claude/shell-snapshots/snapshot-zsh-1.sh"

# pid, ppid, stat, lstart, args
PROCS = [
    (1, 0, "Ss", L, "/sbin/launchd"),
    (500, 1, "S", L, "/Applications/kitty.app/Contents/MacOS/kitty"),
    (501, 500, "Ss", L, "-zsh"),
    (502, 501, "S+", L, "/x/node_modules/.bin/claude --resume " + SIDA),
    (503, 502, "S+", L, "/x/claude.exe --resume " + SIDA),
    (504, 503, "S", L, "/bin/zsh -c source " + SNAP + " && eval 'pnpm test'"),
    (505, 504, "S", L, "node test runner"),
    (510, 500, "Ss", L, "-zsh"),
    (530, 500, "Ss", L, "/bin/zsh -l"),
    (531, 530, "S+", L, "/x/claude.exe"),
    (
        532,
        531,
        "S",
        L,
        "/bin/zsh -c source " + SNAP + " && eval 'cc-await-ping --timeout 3300'",
    ),
    (533, 532, "S", L, "/h/.claude/bin/cc-await-ping --timeout 3300"),
    (534, 532, "S", L, "tail -f /tmp/x"),
    (535, 531, "S", L, "/bin/bash /h/.claude/hooks/stop-hook.sh"),
    (540, 1, "S", L, "/x/claude.exe"),
    (541, 540, "S", L, "/bin/zsh -c source " + SNAP + " && eval 'bash w.sh'"),
    (542, 541, "S", L, "bash w.sh"),
    (543, 542, "S", L, "/bin/bash scripts/ship-land.sh --auto"),
    (550, 1, "Z", L, "(claude.exe)"),
    (560, 1, "S", L, "/usr/bin/python3 fake.py"),
    (570, 1, "S", L, '/x/claude.exe daemon run --spawned-by {"pid":531,"sid":"q"}'),
    (571, 570, "S", L, "/x/claude.exe --bg"),
]
TTYS = {501: "ttys001", 510: "ttys002", 530: "ttys003"}


def ps_text(procs=PROCS, pad_day=False):
    out = []
    for pid, ppid, st, ls, args in procs:
        if pad_day:
            ls = ls.replace("Sep 29", "Sep  9")
        out.append("%5d %5d %-4s %s     %s" % (pid, ppid, st, ls, args))
    return "\n".join(out) + "\n"


def w(wid, pid, focused, fg, cwd="/w", title="t"):
    return {
        "id": wid,
        "pid": pid,
        "is_focused": focused,
        "cwd": cwd,
        "title": title,
        "foreground_processes": [
            {"pid": p, "cmdline": c.split(), "cwd": cwd} for p, c in fg
        ],
    }


LS = [
    {
        "id": 1,
        "is_focused": True,
        "tabs": [
            {
                "id": 1,
                "is_focused": True,
                "windows": [
                    w(
                        1,
                        501,
                        True,
                        [(503, "/x/claude.exe --resume " + SIDA)],
                        cwd="/w/a",
                    ),
                    w(2, 510, False, [(510, "-zsh")]),
                ],
            }
        ],
    },
    {
        "id": 2,
        "is_focused": False,
        "tabs": [
            {
                "id": 2,
                "is_focused": True,
                "windows": [
                    w(3, 530, True, [(531, "/x/claude.exe")], cwd="/w/b"),
                ],
            }
        ],
    },
]


class FakeRun:
    def __init__(self, ps=None, ls=None, fail=()):
        self.ps, self.ls, self.fail, self.calls = ps or ps_text(), ls, set(fail), []

    def __call__(self, argv, **kw):
        self.calls.append((argv, kw))
        if "ps" in self.fail and argv[0] == "/bin/ps":
            raise OSError("no ps")
        if argv[0] == "/bin/ps":
            if "pid=,tty=" in argv:
                body = "".join("%5d %s\n" % (p, TTYS.get(p, "??")) for p, *_ in PROCS)
            else:
                body = self.ps
            return SimpleNamespace(returncode=0, stdout=body)
        if argv[1:3] == ["@", "--to"]:
            if "kitty" in self.fail:
                return SimpleNamespace(returncode=1, stdout="")
            return SimpleNamespace(
                returncode=0, stdout=json.dumps(self.ls if self.ls is not None else LS)
            )
        raise AssertionError(argv)


SOCK = stat.S_IFSOCK | 0o755
TMP = {
    "/tmp/kitty-500": SOCK,
    "/tmp/kitty-482": stat.S_IFLNK | 0o755,
    "/tmp/kitty-560": SOCK,
    "/tmp/kitty-999": SOCK,
    "/tmp/kitty-pane-menu.compile.log": stat.S_IFREG | 0o644,
}


def fake_lstat(path):
    if path not in TMP:
        raise FileNotFoundError(path)
    return SimpleNamespace(st_mode=TMP[path])


def fake_glob(pattern):
    if pattern.startswith("/tmp/kitty-"):
        return sorted(TMP)
    return glob.glob(pattern)


def procs_of(rows=PROCS):
    return {p: T.ProcRow(p, pp, st, ls, a) for p, pp, st, ls, a in rows}


class Home:
    """A temp home with accounts.json, registry rows and session rows."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="lr-observe-")
        self.put(
            ".claude/accounts.json",
            {
                "accounts": [
                    {"name": "next", "config_dir": "~/.claude-next"},
                    {"name": "next2", "config_dir": "~/.claude-secondary"},
                    {"name": "next3", "config_dir": "~/.claude-tertiary"},
                ]
            },
        )
        reg = ".claude/cc-registry/"
        self.put(
            reg + "1.json",
            {
                "session_id": SIDA,
                "pid": 503,
                "account": "claude-secondary",
                "name": "alpha",
                "cwd": "/w/a",
                "paneUUID": "1",
                "surface": "pane",
                "lstart": "local-time-ignored",
            },
        )
        self.put(
            reg + "2.json",
            {
                "session_id": SIDB,
                "pid": 531,
                "account": "claude",
                "name": "beta",
                "cwd": "",
                "paneUUID": "3",
                "surface": "pane",
            },
        )
        self.put(
            reg + "3.json",
            {
                "session_id": SIDC,
                "pid": 540,
                "account": "claude-tertiary",
                "name": "gamma",
                "cwd": "/w/c",
                "paneUUID": "w0t0p0:0A1B2C3D-1111-2222-3333-444455556666",
            },
        )
        self.put(
            reg + "4.json",
            {"session_id": SIDD, "pid": 999, "account": "claude-next", "name": "stale"},
        )
        self.put(reg + "5.json", ["not", "a", "row"])
        self.put(
            ".claude-secondary/sessions/503.json",
            {"sessionId": SIDA, "pid": 503, "kind": "interactive"},
        )
        self.put(
            ".claude/sessions/531.json",
            {"sessionId": SIDB, "pid": 531, "kind": "interactive", "cwd": "/w/b"},
        )
        self.put(
            ".claude-next/sessions/571.json",
            {"sessionId": SIDBG, "pid": 571, "kind": "bg", "cwd": "/w/b"},
        )
        self.put(".claude-next/sessions/777.json", {"sessionId": "ffff", "pid": "777"})
        self.put(
            ".claude-next/sessions/888.json", {"sessionId": "gggg0000", "pid": 888}
        )
        self.put(".claude-next/sessions/tok.json", ["peer-token"])
        self.put(".claude-next/sessions/531.abc.key", "secret")

    def put(self, rel, data):
        path = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(data if isinstance(data, str) else json.dumps(data))

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


class PsParsing(unittest.TestCase):
    def test_lstart_args_zombie(self):
        procs, ttys = O.read_ps(FakeRun(ps=ps_text(pad_day=True)))
        self.assertEqual(
            procs[504].lstart, "Tue Sep 9 11:19:17 2026"
        )  # padded day collapsed
        self.assertEqual(len(procs[504].lstart.split()), 5)
        self.assertEqual(
            procs[504].args, "/bin/zsh -c source " + SNAP + " && eval 'pnpm test'"
        )
        self.assertTrue(procs[550].zombie)
        self.assertEqual(ttys[501], "ttys001")
        self.assertNotIn(1, ttys)  # "??" is no tty

    def test_ps_env_and_keywords(self):
        run = FakeRun()
        O.read_ps(run)
        argv, kw = run.calls[0]
        self.assertIn("pid=,ppid=,stat=,lstart=,args=", argv)
        self.assertEqual((kw["env"]["TZ"], kw["env"]["LC_ALL"]), ("UTC", "C"))


class Kitty(unittest.TestCase):
    def test_socket_filter(self):
        socks = O.kitty_sockets(procs_of(), fake_glob, fake_lstat)
        self.assertEqual(
            socks, ["unix:/tmp/kitty-500"]
        )  # symlink, log, non-kitty, dead all dropped

    def test_panes_focus_state_shape(self):
        panes = {
            p.window_id: p
            for p in O.panes_from_ls("unix:/tmp/kitty-500", 500, LS, procs_of(), TTYS)
        }
        self.assertTrue(panes[1].is_focused)
        self.assertFalse(panes[2].is_focused)
        self.assertFalse(panes[3].is_focused)  # its OS window is not focused
        self.assertEqual(
            (panes[1].state, panes[2].state, panes[3].state),
            ("claude", "shell", "claude"),
        )
        self.assertEqual((panes[1].root_shape, panes[3].root_shape), ("shell", "shell"))
        self.assertEqual(
            (panes[1].tty, panes[1].root_lstart, panes[1].kitty_lstart),
            ("ttys001", L, L),
        )

    def test_launcher_root_and_unknown(self):
        data = [
            {
                "is_focused": True,
                "tabs": [
                    {
                        "is_focused": True,
                        "windows": [
                            w(9, 531, True, [(531, "/x/claude.exe")]),
                            w(8, 510, False, [(505, "vim x")]),
                        ],
                    }
                ],
            }
        ]
        panes = {
            p.window_id: p for p in O.panes_from_ls("s", 500, data, procs_of(), {})
        }
        self.assertEqual(panes[9].root_shape, "launcher")
        self.assertEqual(panes[8].state, "unknown")

    def test_kitten_bin(self):
        self.assertEqual(O.kitten_bin({"LR_KITTEN_BIN": "/k"}), "/k")
        self.assertEqual(O.kitten_bin({}, exists=lambda p: True), O.KITTEN_APP)
        self.assertEqual(
            O.kitten_bin({}, exists=lambda p: False, which=lambda n: None), "kitten"
        )

    def test_ls_failure_degrades(self):
        deg = []
        self.assertIsNone(
            O.kitty_ls(
                "unix:/tmp/kitty-500", FakeRun(fail={"kitty"}), kitten="k", degraded=deg
            )
        )
        self.assertEqual(deg, ["kitty:unix:/tmp/kitty-500"])


class Tree(unittest.TestCase):
    def test_bind_by_ppid(self):
        roots = {501: (500, 1), 530: (500, 3)}
        self.assertEqual(O.bind(503, procs_of(), roots), (500, 1))
        self.assertEqual(O.bind(530, procs_of(), roots), (500, 3))
        self.assertIsNone(O.bind(540, procs_of(), roots))

    def test_resume_leaf_drops_wrapper(self):
        self.assertEqual(R.resume_leaves(procs_of())[SIDA], [503])

    def test_holder_dedup(self):
        srcs = [
            ("session-row", "/c2", 503, "interactive"),
            ("registry", "/c9", 503, ""),
            ("resume-argv", "", 503, ""),
            ("registry", "", 999, ""),
        ]
        hs = R.holders_for(srcs, procs_of(), {501: (500, 1)})
        self.assertEqual(len(hs), 1)
        self.assertEqual(
            (hs[0].src, hs[0].cfg, hs[0].pane), ("session-row", "/c2", (500, 1))
        )


class Background(unittest.TestCase):
    def setUp(self):
        self.p = procs_of()
        self.k = R.children_map(self.p)

    def test_shell_with_work(self):
        bw = R.bg_work_for([503], self.p, self.k, [])
        self.assertEqual(
            [(b.kind, b.pid, b.watcher_only, b.ship_land) for b in bw],
            [("shell", 504, False, False)],
        )

    def test_watcher_only_and_hook_ignored(self):
        bw = R.bg_work_for([531], self.p, self.k, [])
        self.assertEqual(
            [(b.pid, b.watcher_only) for b in bw], [(532, True)]
        )  # 535 hook bash: nothing

    def test_ship_land_grandchild(self):
        self.assertTrue(R.bg_work_for([540], self.p, self.k, [])[0].ship_land)

    def test_bg_row_host(self):
        self.assertEqual(R.bg_host_pid(571, self.p), 531)
        bw = R.bg_work_for([531], self.p, self.k, [(531, self.p[571])])
        self.assertIn(("bg-row", 571), [(b.kind, b.pid) for b in bw])


class Rows(unittest.TestCase):
    def setUp(self):
        self.home = Home()

    def tearDown(self):
        self.home.cleanup()

    def test_session_row_shape_filter(self):
        rows = R.read_session_rows(self.home.dir, procs_of())
        self.assertEqual(
            sorted(r["sessionId"] for _, r in rows), sorted([SIDA, SIDB, SIDBG])
        )

    def test_account_fold(self):
        amap = R.acct_cfg_map(self.home.dir)
        h = self.home.dir
        self.assertEqual(amap["next2"], os.path.join(h, ".claude-secondary"))
        self.assertEqual(R.acct_of_cfg(os.path.join(h, ".claude"), amap), "next")
        self.assertEqual(R.acct_of_cfg(os.path.join(h, ".claude-next"), amap), "next")
        self.assertEqual(R.acct_of_cfg("/elsewhere", amap), "")
        self.assertEqual(
            R.registry_cfg("claude-secondary", h, amap),
            os.path.join(h, ".claude-secondary"),
        )
        self.assertEqual(
            R.registry_cfg("next3", h, amap), os.path.join(h, ".claude-tertiary")
        )


class Composer(unittest.TestCase):
    """composer_from_screen over W0's captured frames: only a real box reads empty."""

    FIX = os.path.join(
        os.path.dirname(os.path.realpath(__file__)),
        "..",
        "..",
        "..",
        "..",
        "tests",
        "fixtures",
        "lr-recon",
        "screens",
    )

    def frame(self, name):
        with open(os.path.join(self.FIX, name), encoding="utf-8") as fh:
            return fh.read()

    def test_w0_frames(self):
        want = {
            "composer-empty-2.1.284.txt": "empty",
            "composer-empty-2.1.114.txt": "empty",
            "composer-resumed-2.1.284.txt": "empty",
            "composer-draft-2.1.284.txt": "draft",
            "bgwork-dialog-2.1.284.txt": "unknown",
            "trust-dialog-2.1.284.txt": "unknown",
        }
        for name, state in want.items():
            self.assertEqual(O.composer_from_screen(self.frame(name)), state, name)

    def test_a_faint_suggestion_is_not_a_draft_but_plain_text_is(self):
        box = "x\n%s\n❯ %s\n%s\n" % ("─" * 20, "%s", "─" * 20)
        self.assertEqual(
            O.composer_from_screen(box % "\x1b[2mship the film\x1b[22m"), "empty"
        )
        self.assertEqual(O.composer_from_screen(box % "ship the film"), "draft")
        self.assertEqual(
            O.composer_from_screen(box % "\x1b[38;2;1;2;3mship\x1b[0m"), "draft"
        )


class Observe(unittest.TestCase):
    def setUp(self):
        self.home = Home()

    def tearDown(self):
        self.home.cleanup()

    def snap(self, run=None, **kw):
        return O.observe(
            None,
            self.home.dir,
            run=run or FakeRun(),
            glob_fn=fake_glob,
            lstat_fn=fake_lstat,
            kitten="k",
            now=1.0,
            **kw,
        )

    def test_full_census(self):
        seen = []
        s = self.snap(
            transcript_fn=lambda c, d, sid: (
                seen.append((c, d, sid)) or T.TranscriptObs(path=sid)
            )
        )
        self.assertEqual(s.degraded, [])
        self.assertEqual(sorted(s.panes), ["500:1", "500:2", "500:3"])
        a, b, c = s.sessions[SIDA], s.sessions[SIDB], s.sessions[SIDC]
        self.assertEqual(
            (a.pid, a.pane, a.acct, len(a.holders)), (503, (500, 1), "next2", 1)
        )
        self.assertEqual([x.kind for x in a.bg_work], ["shell"])
        self.assertEqual((b.acct, b.pane, b.cwd), ("next", (500, 3), "/w/b"))
        self.assertEqual(
            sorted((x.kind, x.watcher_only) for x in b.bg_work),
            [("bg-row", False), ("shell", True)],
        )
        self.assertEqual((c.pane, c.registry_name), (None, "iterm:gamma"))
        self.assertTrue(c.bg_work[0].ship_land)
        self.assertTrue(s.sessions[SIDBG].holders[0].bg)
        self.assertEqual(s.sessions[SIDD].holders, [])
        self.assertEqual(a.transcript.path, SIDA)
        self.assertIn((a.cfg, "/w/a", SIDA), seen)
        line = O.census_line(s)
        self.assertIn("3 panes on 1 kitty sockets", line)
        self.assertIn("degraded: none", line)

    def test_ps_failure_never_raises(self):
        s = self.snap(run=FakeRun(fail={"ps"}))
        self.assertEqual((s.degraded, s.sessions, s.panes), (["ps"], {}, {}))

    def test_kitty_failure_no_panes_no_iterm_guess(self):
        s = self.snap(run=FakeRun(fail={"kitty"}))
        self.assertEqual(s.degraded, ["kitty:unix:/tmp/kitty-500"])
        self.assertEqual(s.panes, {})
        self.assertEqual(
            s.sessions[SIDA].registry_name, "alpha"
        )  # unbound, but not called iterm

    def test_rig_mode_refuses_every_sid_without_a_rig_row(self):
        self.home.put(
            ".claude/cc-registry/1.json",
            dict(
                session_id=SIDA,
                pid=503,
                account="claude-secondary",
                name="alpha",
                cwd="/w/a",
                paneUUID="1",
                surface="pane",
                rig=True,
            ),
        )
        s = self.snap(rig=True)
        self.assertEqual(sorted(s.sessions), [SIDA])
        self.assertIn(SIDB, s.rig_refused)  # a registry row without the tag
        self.assertIn(SIDBG, s.rig_refused)  # a session row only
        self.assertEqual(s.sessions[SIDA].pane, (500, 1))
        self.assertEqual(self.snap(rig=False).rig_refused, [])
        # W5 rig 0c95685d: a sid the daemon owns stays visible when its row loses the tag
        s = self.snap(rig=True, rig_keep=frozenset({SIDB}))
        self.assertIn(SIDB, s.sessions)
        self.assertNotIn(SIDB, s.rig_refused)
        self.assertIn(SIDBG, s.rig_refused)

    def test_rig_mode_from_env(self):
        self.assertTrue(O.rig_mode({"LR_RECON_RIG": "1"}))
        self.assertTrue(O.rig_mode({"LR_RIG": "1"}))
        self.assertFalse(O.rig_mode({"LR_RIG": "0"}))
        self.assertFalse(O.rig_mode({}))

    def test_transcript_failure_degrades(self):
        def boom(c, d, sid):
            raise ValueError(sid)

        s = self.snap(transcript_fn=boom)
        self.assertIn("transcript:" + SIDA, s.degraded)


if __name__ == "__main__":
    unittest.main()
