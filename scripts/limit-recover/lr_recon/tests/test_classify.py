"""classify.py: allowlist classes, fingerprint normalisation, escalation and re-arm (§7.2)."""

import unittest
from typing import Dict

from lr_recon import classify as C
from lr_recon import types as T


def rec() -> T.Record:
    return T.Record(sid="s1", record_id="recon:c:s1:1")


class Fingerprint(unittest.TestCase):
    def test_bang_line_normalised(self) -> None:
        a = C.fingerprint(
            "EXITING",
            "DETERMINISTIC",
            "noise 1\n!! pane 42 gone at /tmp/x.123/y\nmore",
            1,
            "abc",
        )
        b = C.fingerprint(
            "EXITING", "DETERMINISTIC", "!! pane 7 gone at /var/folders/q/z", 2, "abc"
        )
        self.assertEqual(a, b)
        self.assertEqual(a, "EXITING|DETERMINISTIC|!! pane N gone at <path>|abc")

    def test_no_bang_uses_rc_and_last_line(self) -> None:
        fp = C.fingerprint(
            "MOVED", "DETERMINISTIC", "first\nerror: port 5123 in ~/x/y\n\n", 3, "s"
        )
        self.assertEqual(fp, "MOVED|DETERMINISTIC|rc=3 error: port N in <path>|s")
        self.assertNotEqual(
            fp,
            C.fingerprint(
                "MOVED", "DETERMINISTIC", "first\nerror: port 1 in ~/z", 4, "s"
            ),
        )
        self.assertEqual(C.fingerprint("P", "C", "", 5, "s"), "P|C|rc=5|s")

    def test_sha_and_phase_distinguish(self) -> None:
        self.assertNotEqual(
            C.fingerprint("A", "X", "!! e", 1, "s1"),
            C.fingerprint("A", "X", "!! e", 1, "s2"),
        )
        self.assertNotEqual(
            C.fingerprint("A", "X", "!! e", 1, "s"),
            C.fingerprint("B", "X", "!! e", 1, "s"),
        )


class Classify(unittest.TestCase):
    CASES = {
        "TRANSIENT": [
            "kitty @ ls: RPC timed out",
            "surface rc 3",
            "pane resolved to no tty",
            "no claude process appeared within 90s",
            "lock busy: held by 123",
            "router exit 5",
            "usage 429",
            "swallowed Enter",
            "killed watcher",
            "cc_tui_submit verdict MANGLED",
            "background dialog reappeared",
        ],
        "WAIT": [
            "no routable target: all walled",
            "capacity refused",
            "every account limited",
            "router exit 3",
            "TARGET-LIMITED",
            "TARGET-AUTH",
        ],
        "HOLD": [
            "foreign draft in composer",
            "background work running",
            "live subagents on idle move",
            "HELD:team",
            "composer unreadable",
            "parked menu",
            "repo is bare",
            "iTerm2 pane",
        ],
        "IMPOSSIBLE": [
            "launcher-rooted session",
            "headless session",
            "cwd gone: /tmp/w",
        ],
    }

    def test_allowlists(self) -> None:
        for cls, texts in self.CASES.items():
            for t in texts:
                with self.subTest(text=t):
                    self.assertEqual(C.classify(t, 1), cls)
                    self.assertIn(cls, T.ERROR_CLASSES)

    def test_everything_else_is_deterministic(self) -> None:
        self.assertEqual(
            C.classify("!! unexpected token in bundle", 2), "DETERMINISTIC"
        )
        self.assertEqual(C.classify("router exit 7", 7), "DETERMINISTIC")

    def test_killed_rc_is_transient(self) -> None:
        for rc in (124, 137, 143, -9, -15):
            self.assertEqual(C.classify("", rc), "TRANSIENT")


class NotMoved(unittest.TestCase):
    def test_table(self) -> None:
        self.assertEqual(C.map_notmoved("not-limited", "limited"), ("NOT_NEEDED", ""))
        self.assertEqual(C.map_notmoved("not-limited", "idle"), ("WAIT", "WAIT_DATA"))
        self.assertEqual(C.map_notmoved("teammate", "limited"), ("NOT_NEEDED", ""))
        self.assertEqual(C.map_notmoved("draft", "limited"), ("HOLD", "HOLD-DRAFT"))
        self.assertEqual(C.map_notmoved("pane-not-cc", "limited"), ("EXITED", ""))
        self.assertEqual(
            C.map_notmoved("pane-not-cc", "limited", pane_at_shell=False),
            ("TRANSIENT", ""),
        )
        self.assertEqual(C.map_notmoved("bg-work", "idle"), ("HOLD", "HOLD-BGWORK"))
        self.assertEqual(C.map_notmoved("unreadable", "limited"), ("TRANSIENT", ""))
        self.assertEqual(
            C.map_notmoved("capacity", "limited"), ("WAIT", "WAIT_CAPACITY")
        )
        self.assertEqual(C.map_notmoved("router", "limited"), ("WAIT", "WAIT_SLOT"))
        self.assertEqual(C.map_notmoved("router:5", "limited"), ("TRANSIENT", ""))
        for _, sub in [
            C.map_notmoved(r, "limited")
            for r in ("draft", "bg-work", "capacity", "router")
        ]:
            self.assertIn(sub, T.PRE_MOVE_SUBSTATES)


class Failures(unittest.TestCase):
    def test_transient_never_escalates(self) -> None:
        r = rec()
        got = [
            C.apply_failure(r, "TRANSIENT", "fp", "kitty timeout", 100.0 * i)
            for i in range(1, 31)
        ]
        self.assertFalse(r.escalated)
        self.assertEqual(r.attempts_by_class["TRANSIENT"], 30)
        pages = [i + 1 for i, d in enumerate(got) if d == "BACKOFF_PAGE"]
        self.assertEqual(pages, [6, 18, 30])
        self.assertEqual(
            [C.backoff_s(n) for n in range(1, 9)], [10, 30, 60, 120, 240, 300, 300, 300]
        )
        self.assertEqual(r.next_eligible_at, 3000.0 + 300)

    def test_deterministic_escalates_on_second_same_fp(self) -> None:
        r = rec()
        self.assertEqual(C.apply_failure(r, "DETERMINISTIC", "fp1", "d", 10.0), "RETRY")
        self.assertFalse(r.escalated)
        self.assertEqual(
            C.apply_failure(r, "DETERMINISTIC", "fp1", "d", 20.0), "ESCALATED"
        )
        self.assertTrue(r.escalated)
        assert r.last_error is not None
        self.assertEqual(
            (r.last_error.cls, r.last_error.fingerprint, r.last_error.at),
            ("DETERMINISTIC", "fp1", 20.0),
        )

    def test_different_fingerprints_do_not_escalate(self) -> None:
        r = rec()
        for i in range(6):
            self.assertEqual(
                C.apply_failure(r, "DETERMINISTIC", "fp%d" % i, "d", float(i)), "RETRY"
            )
        self.assertFalse(r.escalated)

    def test_transient_between_breaks_consecutive(self) -> None:
        r = rec()
        C.apply_failure(r, "DETERMINISTIC", "fp", "d", 1.0)
        C.apply_failure(r, "TRANSIENT", "t", "d", 2.0)
        self.assertEqual(C.apply_failure(r, "DETERMINISTIC", "fp", "d", 3.0), "RETRY")

    def test_wait_and_hold_are_not_attempts(self) -> None:
        r = rec()
        C.apply_failure(r, "DETERMINISTIC", "fp", "d", 1.0)
        self.assertEqual(
            C.apply_failure(r, "WAIT", "w", "no routable target", 2.0), "WAIT"
        )
        self.assertEqual(C.apply_failure(r, "HOLD", "h", "draft", 3.0), "HOLD")
        self.assertEqual(
            r.attempts_by_class, {"DETERMINISTIC": 1, "WAIT": 1, "HOLD": 1}
        )
        self.assertEqual(
            C.apply_failure(r, "DETERMINISTIC", "fp", "d", 4.0), "ESCALATED"
        )

    def test_impossible(self) -> None:
        r = rec()
        self.assertEqual(
            C.apply_failure(r, "IMPOSSIBLE", "i", "headless", 1.0), "IMPOSSIBLE"
        )
        self.assertFalse(r.escalated)


class Rearm(unittest.TestCase):
    BASE: Dict[str, str] = {
        "scripts_sha": "a",
        "repo": "bare=false;wt=2",
        "eligible": "n1,n2",
        "pane_proc": "123@Mon",
        "lock_holder": "77",
        "load_below": "0",
    }

    def escalated(self) -> T.Record:
        r = rec()
        C.apply_failure(r, "DETERMINISTIC", "fp", "d", 1000.0)
        C.apply_failure(r, "DETERMINISTIC", "fp", "d", 1000.0)
        self.assertTrue(r.escalated)
        return r

    def test_rearms_at_15_minutes(self) -> None:
        r = self.escalated()
        self.assertFalse(C.should_rearm(r, 1899.0, self.BASE, dict(self.BASE)))
        self.assertTrue(C.should_rearm(r, 1900.0, self.BASE, dict(self.BASE)))
        self.assertTrue(C.should_rearm(r, 1900.0, {}, {}))

    def test_rearms_on_each_input_change(self) -> None:
        r = self.escalated()
        for key in self.BASE:
            with self.subTest(key=key):
                now = dict(self.BASE)
                now[key] = now[key] + "x"
                self.assertTrue(C.should_rearm(r, 1001.0, now, self.BASE))
        gone = dict(self.BASE)
        del gone["lock_holder"]  # the holder died and the key vanished
        self.assertTrue(C.should_rearm(r, 1001.0, gone, self.BASE))
        self.assertFalse(C.should_rearm(r, 1001.0, self.BASE, {}))

    def test_not_escalated_never_rearms(self) -> None:
        self.assertFalse(C.should_rearm(rec(), 1e9, {"a": "1"}, {"a": "2"}))

    def test_rearm_gives_one_refire(self) -> None:
        r = self.escalated()
        C.rearm(r, 2000.0)
        self.assertFalse(r.escalated)
        self.assertNotIn("DETERMINISTIC", r.attempts_by_class)
        self.assertEqual(r.next_eligible_at, 2000.0)
        self.assertEqual(
            C.apply_failure(r, "DETERMINISTIC", "fp", "d", 2001.0), "ESCALATED"
        )
        C.rearm(r, 3000.0)
        self.assertEqual(
            C.apply_failure(r, "DETERMINISTIC", "new", "d", 3001.0), "RETRY"
        )


if __name__ == "__main__":
    unittest.main()
