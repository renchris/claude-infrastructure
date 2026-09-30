"""observe.py / observe_rows.py: hermetic census tests — fake ps, fake kitten, temp home (§C3)."""

import glob
import json
import os
import shutil
import stat
import subprocess
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

    def test_a_row_shared_through_a_symlinked_sessions_dir_is_the_accounts(self):
        # W5b canary 1: ~/.claude-next/sessions -> ~/.claude/sessions (one login). The row was read
        # as ~/.claude first, which maps to no account, and lr-handoff refused every `next` move.
        h = tempfile.mkdtemp(prefix="lr-rows-")
        try:
            os.makedirs(os.path.join(h, ".claude", "sessions"))
            with open(os.path.join(h, ".claude", "sessions", "531.json"), "w") as fh:
                json.dump({"sessionId": SIDB, "pid": 531, "kind": "interactive"}, fh)
            os.makedirs(os.path.join(h, ".claude-next"))
            os.symlink(
                os.path.join(h, ".claude", "sessions"),
                os.path.join(h, ".claude-next", "sessions"),
            )
            rows = R.read_session_rows(h, procs_of())
            self.assertEqual(
                [(c, r["sessionId"]) for c, r in rows],
                [(os.path.join(h, ".claude-next"), SIDB)],
            )
        finally:
            shutil.rmtree(h, ignore_errors=True)

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

    def test_a_non_ascii_draft_is_a_draft(self):
        """D6.8: only ❯ and U+00A0 are chrome. 12.1% of real prompts carry non-ASCII; a draft
        written wholly in it used to read EMPTY, which let /exit merge into it."""
        box = "x\n%s\n\u276f\u00a0%s\n%s\n" % ("─" * 20, "%s", "─" * 20)
        for text in ("日本語のメモ", "🚀", "café → prod", "ok 日本語"):
            self.assertEqual(O.composer_from_screen(box % text), "draft", text)
        self.assertEqual(O.composer_from_screen(box % ""), "empty")
        self.assertEqual(O.composer_from_screen(box % "\u00a0 \u00a0"), "empty")
        self.assertEqual(
            O.composer_from_screen(box % 'Try "fix the \u00e9 bug"'), "empty"
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

    def test_canary_sees_only_its_listed_sids(self):
        # W5b: a canary daemon's census drops every real session before a bucket can exist
        p = T.Paths(lr_root="/nx", root="/nx/recon-canary", canary=frozenset({SIDA}))
        s = O.observe(
            p,
            self.home.dir,
            run=FakeRun(),
            glob_fn=fake_glob,
            lstat_fn=fake_lstat,
            kitten="k",
            now=1.0,
        )
        self.assertEqual(sorted(s.sessions), [SIDA])
        self.assertIn(SIDB, s.rig_refused)
        self.assertIn(SIDBG, s.rig_refused)
        # CONTROL: the same census without a canary set sees them all
        s = self.snap()
        self.assertIn(SIDB, s.sessions)
        self.assertEqual(s.rig_refused, [])

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


# ── W7a: a ps read that survives load, and a census the pass may not decide on ────────────────────


class FlakyPs(FakeRun):
    """FakeRun whose first /bin/ps calls follow ``script``: "timeout", "rc" (exit 1), "empty"
    (exit 0, no output) or "ok"; once the script is spent every call is the normal fixture."""

    def __init__(self, script, clock=None, **kw):
        super().__init__(**kw)
        self.script, self.clock = list(script), clock

    def __call__(self, argv, **kw):
        if argv[0] == "/bin/ps" and self.script:
            how = self.script.pop(0)
            if how == "timeout":
                self.calls.append((argv, kw))
                if self.clock is not None:
                    self.clock[0] += kw["timeout"]
                raise subprocess.TimeoutExpired(argv, kw["timeout"])
            if how in ("rc", "empty"):
                self.calls.append((argv, kw))
                return SimpleNamespace(returncode=1 if how == "rc" else 0, stdout="")
        return super().__call__(argv, **kw)

    def ps_calls(self):
        return [kw["timeout"] for argv, kw in self.calls if argv[0] == "/bin/ps"]


class PsRead(unittest.TestCase):
    def test_a_retry_saves_a_timed_out_read(self):
        stats = {}
        procs, ttys = O.read_ps(FlakyPs(["timeout"]), bound=20.0, stats=stats)
        self.assertEqual((procs, ttys), O.read_ps(FakeRun(), bound=20.0))
        self.assertEqual(stats["attempts"], 2)

    def test_empty_output_and_a_failed_exit_are_retried(self):
        for how in ("empty", "rc"):
            stats = {}
            procs, _ = O.read_ps(FlakyPs([how]), bound=20.0, stats=stats)
            self.assertIn(503, procs)
            self.assertEqual(stats["attempts"], 2, how)

    def test_the_tty_read_is_retried_too(self):
        for how in ("timeout", "empty"):
            stats = {}
            _, ttys = O.read_ps(FlakyPs(["ok", how]), bound=20.0, stats=stats)
            self.assertEqual(ttys[501], "ttys001")
            self.assertEqual(stats["attempts"], 2, how)

    def test_a_first_try_success_is_one_attempt(self):
        stats = {}
        O.read_ps(FakeRun(), bound=20.0, stats=stats)
        self.assertEqual(stats["attempts"], 1)

    def test_two_failures_raise_naming_both(self):
        run = FlakyPs(["timeout", "rc"])
        with self.assertRaises(RuntimeError) as cm:
            O.read_ps(run, bound=33.0)
        self.assertIn("timed out at 33s", str(cm.exception))
        self.assertIn("exited 1", str(cm.exception))
        self.assertEqual(run.ps_calls(), [33.0, 33.0])  # exactly one retry
        with self.assertRaises(RuntimeError) as cm:
            O.read_ps(FlakyPs(["empty", "empty"]), bound=20.0)
        self.assertIn("no rows", str(cm.exception))

    def test_the_budget_caps_each_try_and_skips_a_retry_it_cannot_afford(self):
        clock = [0.0]
        run = FlakyPs(["timeout", "timeout"], clock=clock)
        with self.assertRaises(RuntimeError) as cm:
            O.read_ps(run, bound=40.0, budget=30.0, clock=lambda: clock[0])
        self.assertEqual(run.ps_calls(), [30.0])  # capped at the budget, no retry
        self.assertIn("ps budget spent", str(cm.exception))
        clock = [0.0]
        run = FlakyPs(["timeout"], clock=clock)
        O.read_ps(run, bound=40.0, budget=60.0, clock=lambda: clock[0])
        self.assertEqual(
            run.ps_calls()[:2], [40.0, 20.0]
        )  # the retry gets what is left
        # CONTROL: 5 s left is still a try (PS_MIN_CALL_S), 4.9 s is not
        clock = [0.0]
        run = FlakyPs(["timeout"], clock=clock)
        O.read_ps(run, bound=40.0, budget=45.0, clock=lambda: clock[0])
        self.assertEqual(run.ps_calls()[:2], [40.0, 5.0])

    def test_the_bound_grows_with_load_per_cpu(self):
        self.assertEqual(O.ps_bound(lambda: (0.0, 0.0, 0.0), ncpu=10), 20.0)
        self.assertEqual(O.ps_bound(lambda: (50.0, 0.0, 0.0), ncpu=10), 30.0)
        self.assertEqual(O.ps_bound(lambda: (1000.0, 0.0, 0.0), ncpu=10), 40.0)

    def test_an_unreadable_load_keeps_the_flat_bound(self):
        def boom():
            raise OSError("no loadavg")

        self.assertEqual(O.ps_bound(boom, ncpu=10), 20.0)

    def test_each_try_is_bounded_by_the_bound(self):
        run = FakeRun()
        O.read_ps(run, bound=27.0)
        self.assertEqual({kw["timeout"] for _a, kw in run.calls}, {27.0})


def _trust_snap(n_claude, n_claude_panes):
    procs = {
        600 + i: T.ProcRow(600 + i, 1, "S+", L, "/x/claude.exe")
        for i in range(n_claude)
    }
    procs[1] = T.ProcRow(1, 0, "Ss", L, "/sbin/launchd")
    panes = {
        "500:%d" % i: T.PaneObs(500, i, "unix:/tmp/kitty-500", state="claude")
        for i in range(n_claude_panes)
    }
    panes["500:99"] = T.PaneObs(500, 99, "unix:/tmp/kitty-500", state="shell")
    return T.Snapshot(wall=1.0, uptime_raw=0.0, procs=procs, panes=panes)


class Trust(unittest.TestCase):
    def test_ps_degraded_is_untrusted_and_names_why(self):
        s = T.Snapshot(wall=1.0, uptime_raw=0.0, degraded=["ps"])
        s.degraded_why["ps"] = "/bin/ps pid=,tty=: timed out at 40s"
        self.assertEqual(
            O.untrusted(s, None), "ps degraded: /bin/ps pid=,tty=: timed out at 40s"
        )

    def test_zero_claude_procs_while_kitty_shows_claude_is_untrusted(self):
        self.assertIn(
            "ps read 0 claude procs while kitty shows claude in 1 panes",
            O.untrusted(_trust_snap(0, 1), None),
        )
        self.assertTrue(O.untrusted(_trust_snap(1, 3), None))

    def test_ps_seeing_half_of_kittys_claude_panes_is_trusted(self):
        self.assertEqual(O.untrusted(_trust_snap(1, 2), None), "")
        self.assertEqual(O.untrusted(_trust_snap(0, 0), None), "")

    def test_a_collapse_against_the_previous_pass_is_untrusted(self):
        self.assertEqual(
            O.untrusted(_trust_snap(7, 0), 30),
            "claude procs fell from 30 to 7 in one pass",
        )
        self.assertTrue(
            O.untrusted(_trust_snap(1, 0), 8)
        )  # the floor itself can collapse
        self.assertTrue(O.untrusted(_trust_snap(0, 0), 8))

    def test_a_drop_to_a_quarter_or_from_below_the_floor_is_trusted(self):
        self.assertEqual(O.untrusted(_trust_snap(7, 0), 28), "")  # exactly a quarter
        self.assertEqual(O.untrusted(_trust_snap(0, 0), 7), "")  # below the floor
        self.assertEqual(O.untrusted(_trust_snap(0, 0), None), "")  # first pass


class ObserveUnderLoad(unittest.TestCase):
    """observe() over a flaky ps, on Observe's fixture home (borrowed, so its tests do not re-run)."""

    setUp = Observe.setUp
    tearDown = Observe.tearDown
    snap = Observe.snap

    def test_a_retried_read_is_a_normal_census(self):
        normal = self.snap()
        s = self.snap(run=FlakyPs(["timeout"]))
        self.assertEqual(s.degraded, [])
        self.assertEqual(
            (sorted(s.panes), sorted(s.sessions)),
            (sorted(normal.panes), sorted(normal.sessions)),
        )
        self.assertEqual(O.untrusted(s, O.claude_count(normal)), "")
        self.assertEqual((normal.ps_attempts, s.ps_attempts), (1, 2))
        self.assertIn("· ps took 2 tries", O.census_line(s))
        self.assertNotIn("tries", O.census_line(normal))

    def test_a_failed_read_records_why(self):
        s = self.snap(run=FlakyPs(["timeout", "timeout"]))
        self.assertEqual((s.degraded, s.procs, s.panes), (["ps"], {}, {}))
        self.assertIn("timed out at", s.degraded_why["ps"])
        self.assertTrue(O.untrusted(s, None).startswith("ps degraded: /bin/ps"))


if __name__ == "__main__":
    unittest.main()
