"""gap-3 E1: a limited session is at rest once it has been quiet for LIMITED_QUIET_S, whatever user
records trail the limit error, except a local `!` command that has not printed yet."""

import datetime
import json
import os
import unittest

from lr_recon import transcript as X

FIX = os.path.join(
    os.path.dirname(os.path.realpath(__file__)),
    *[".."] * 4,
    "tests",
    "fixtures",
    "lr-recon",
    "jsonl",
)


def fixture(name):
    with open(os.path.join(FIX, name)) as fh:
        return fh.read().rstrip("\n") + "\n"


def epoch(iso):
    return datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()


def user(text, ts, **kw):
    return (
        json.dumps(
            dict(
                {
                    "type": "user",
                    "timestamp": ts,
                    "message": {"role": "user", "content": text},
                },
                **kw,
            )
        )
        + "\n"
    )


LIMIT = fixture("death-quota-limits.jsonl")
LIMIT_AT = epoch(json.loads(LIMIT)["timestamp"])
# 769b7294's shape: the goal arm re-appended after "Goal paused", stamped with the ARM's older time
REPLAY = user(
    "A session-scoped Stop hook is now active with condition: wave 3 is landed",
    "2026-09-28T15:15:16.000Z",
    isMeta=True,
)
NOTIF = user(
    "<task-notification>a background task ended</task-notification>",
    "2026-09-29T04:00:00.000Z",
)


def at_rest(body, now):
    return X._at_rest(body.encode(), now)


class LimitedAndQuiet(unittest.TestCase):
    def test_a_replayed_goal_after_the_limit_is_at_rest_once_quiet(self):
        self.assertTrue(at_rest(LIMIT + REPLAY, LIMIT_AT + 135))
        self.assertFalse(at_rest(LIMIT + REPLAY, LIMIT_AT + 30))  # inside the window

    def test_a_notification_after_the_limit_is_at_rest_once_quiet(self):
        newest = epoch("2026-09-29T04:00:00.000Z")
        self.assertTrue(at_rest(LIMIT + NOTIF, newest + X.LIMITED_QUIET_S))
        self.assertFalse(at_rest(LIMIT + NOTIF, newest + 10))

    def test_a_pending_local_bash_command_stays_in_flight(self):
        bash = user("<bash-input>sleep 600</bash-input>", "2026-09-29T04:00:00.000Z")
        self.assertFalse(at_rest(LIMIT + bash, LIMIT_AT + 3600))
        out = user(
            "<bash-stdout></bash-stdout><bash-stderr></bash-stderr>",
            "2026-09-29T04:10:00.000Z",
        )
        self.assertTrue(at_rest(LIMIT + bash + out, LIMIT_AT + 3600))

    def test_only_a_limit_error_counts_not_any_error(self):
        """A 529 is retried by the next prompt, which then runs as long as any turn."""
        e529 = fixture("api-error-529.jsonl")
        at = epoch(json.loads(e529)["timestamp"])
        self.assertFalse(
            at_rest(e529 + user("go on", "2026-09-22T00:57:00.000Z"), at + 3600)
        )

    def test_a_trailing_prompt_after_a_healthy_turn_is_still_in_flight(self):
        body = fixture("assistant-turn.jsonl") + fixture("user-prompt.jsonl")
        self.assertFalse(at_rest(body, epoch("2026-09-29T01:44:15.403Z") + 86400))

    def test_observe_transcript_passes_its_clock(self):
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "s.jsonl")
            with open(p, "w") as fh:
                fh.write(LIMIT + REPLAY)
            self.assertTrue(X.observe_transcript(p, now=LIMIT_AT + 600).at_rest)
            self.assertFalse(X.observe_transcript(p, now=LIMIT_AT + 5).at_rest)


if __name__ == "__main__":
    unittest.main()
