"""tokens.py over real record shapes (tests/fixtures/lr-recon/jsonl) plus hand-built user records."""

import json
import os
import tempfile
import unittest
from typing import Any, Dict, List

from lr_recon import tokens

JSONL = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "..",
    "..",
    "..",
    "tests",
    "fixtures",
    "lr-recon",
    "jsonl",
)
TOKEN = "lr-run:2026-09-29T0417Z:9f3a2b"


def _fixture(name: str) -> str:
    with open(os.path.join(JSONL, name), encoding="utf-8") as fh:
        return fh.readline().strip()


def _user(content: Any, **extra: Any) -> str:
    rec: Dict[str, Any] = {
        "type": "user",
        "isSidechain": False,
        "message": {"role": "user", "content": content},
    }
    rec.update(extra)
    return json.dumps(rec)


META = json.dumps({"type": "last-prompt", "lastPrompt": "x"})
SPLIT = (
    "please continue "
    + TOKEN[:24]
    + '</pasted_content>\n<pasted_content id="2">'
    + TOKEN[24:]
    + " thanks"
)
NOTIF = "<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>"


class TokensCase(unittest.TestCase):
    def _write(self, lines: List[str]) -> str:
        fd, path = tempfile.mkstemp(suffix=".jsonl")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        self.addCleanup(os.unlink, path)
        return path

    def _offset_of(self, lines: List[str], idx: int) -> int:
        return sum(len(line.encode("utf-8")) + 1 for line in lines[:idx])

    def test_split_token_found(self) -> None:
        lines = [
            META,
            _user("unrelated"),
            _user(SPLIT),
            _fixture("assistant-turn.jsonl"),
        ]
        path = self._write(lines)
        self.assertNotIn(
            TOKEN, SPLIT
        )  # the literal scan the legacy path used misses it
        self.assertEqual(tokens.find_token(path, TOKEN), self._offset_of(lines, 2))

    def test_split_token_in_text_block_list(self) -> None:
        lines = [META, _user([{"type": "text", "text": SPLIT}])]
        self.assertEqual(
            tokens.find_token(self._write(lines), TOKEN), self._offset_of(lines, 1)
        )

    def test_token_at_or_before_min_offset_ignored(self) -> None:
        lines = [META, _user(TOKEN), _fixture("assistant-turn.jsonl")]
        path = self._write(lines)
        at = self._offset_of(lines, 1)
        self.assertEqual(tokens.find_token(path, TOKEN, 0), at)
        self.assertIsNone(tokens.find_token(path, TOKEN, at))  # strictly greater
        self.assertIsNone(tokens.find_token(path, TOKEN, at + 1))

    def test_token_outside_user_record_ignored(self) -> None:
        attach = json.dumps({"type": "attachment", "attachment": {"prompt": TOKEN}})
        self.assertIsNone(tokens.find_token(self._write([META, attach]), TOKEN))

    def test_notification_only_turn(self) -> None:
        lines = [
            META,
            _user(TOKEN),
            _fixture("api-error-529.jsonl"),
            _user(NOTIF),
            _fixture("assistant-turn.jsonl"),
        ]
        path = self._write(lines)
        off = self._offset_of(lines, 1)
        self.assertEqual(tokens.last_assistant_after(path, off), "notification")
        self.assertFalse(tokens.nonerror_after(path, off))

    def test_queued_notification_with_prompt_is_ours(self) -> None:
        """947-e: the token and a queued notification land together; the turn answers both."""
        lines = [META, _user(TOKEN), _user(NOTIF), _fixture("assistant-turn.jsonl")]
        path = self._write(lines)
        off = self._offset_of(lines, 1)
        self.assertEqual(tokens.last_assistant_after(path, off), "ok")
        self.assertTrue(tokens.nonerror_after(path, off))

    def test_system_reminder_and_origin_kind_are_notifications(self) -> None:
        for rec in (
            _user("<system-reminder>x</system-reminder>"),
            _user("background done", origin={"kind": "task-notification"}),
        ):
            lines = [
                META,
                _user(TOKEN),
                _fixture("api-error-529.jsonl"),
                rec,
                _fixture("assistant-turn.jsonl"),
            ]
            self.assertEqual(
                tokens.last_assistant_after(
                    self._write(lines), self._offset_of(lines, 1)
                ),
                "notification",
            )

    def test_error_kinds(self) -> None:
        cases = {
            "death-quota-limits.jsonl": "limit",
            "death-quota-limits-seven-day.jsonl": "limit",
            "authentication-failed.jsonl": "authentication_failed",
            "authentication-failed-not-logged-in.jsonl": "authentication_failed",
            "api-error-529.jsonl": "server_529",
            "assistant-turn.jsonl": "ok",
        }
        for name, want in cases.items():
            lines = [META, _user(TOKEN), _fixture(name)]
            path = self._write(lines)
            off = self._offset_of(lines, 1)
            self.assertEqual(tokens.last_assistant_after(path, off), want, name)
            self.assertEqual(tokens.nonerror_after(path, off), want == "ok", name)

    def test_none_and_torn_line(self) -> None:
        lines = [META, _user(TOKEN), '{"type":"assistant","mess']  # mid-write tail
        path = self._write(lines)
        self.assertEqual(
            tokens.last_assistant_after(path, self._offset_of(lines, 1)), "none"
        )

    def test_nonerror_before_later_error(self) -> None:
        """An ok turn then a limit: row 2 reads the LAST verdict, row 5 still sees the ok turn."""
        lines = [
            META,
            _user(TOKEN),
            _fixture("assistant-turn.jsonl"),
            _user("more"),
            _fixture("death-quota-limits.jsonl"),
        ]
        path = self._write(lines)
        off = self._offset_of(lines, 1)
        self.assertEqual(tokens.last_assistant_after(path, off), "limit")
        self.assertTrue(tokens.nonerror_after(path, off))


if __name__ == "__main__":
    unittest.main()
