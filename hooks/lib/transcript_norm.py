"""transcript_norm — which transcript records did the operator actually type (truememory §3.14).

The session-index context text was 64% machinery (78 of 122 selected messages were Stop-hook
feedback, skill bodies or peer messages), because its filter dropped only `<`-leading text. The
harness now labels most user records itself, so the test is tiered, most authoritative first:
  1. `origin.kind` — "human" is typed; any other kind (task-notification, auto-continuation) is not.
  2. `promptSource` — "typed" or "queued" is typed; "system" is not.
  3. neither field (older transcripts, teammate sessions): isMeta records are machinery, and the
     text must pass the prefix / XML-envelope test below.
System-reminder blocks are stripped before any text test. `typed_prompt` is cc-suggest-filter's
stricter predicate (string content only), kept byte-for-byte so its corpus stays comparable.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterator
from typing import Any, NamedTuple

# Shapes the harness writes into the user role (measured by bin/cc-suggest-filter, which owns the
# rationale for each entry).
_INJECTED_PREFIXES = (
    "Caveat:",
    "Stop hook feedback:",
    "[Request interrupted",
    "[Image:",
    "[desk-sweep]",
    "Another Claude session sent a message:",
    "A session-scoped Stop hook is now active",
    "API Error:",
    "This session is being continued from a previous conversation",
)
# The fallback tier also drops a shell escape's echo and a skill body; both are isMeta today, but
# the tier exists for records that carry no labels at all.
_FALLBACK_PREFIXES = _INJECTED_PREFIXES + (
    "<bash-input>",
    "Base directory for this skill:",
)
_SYSTEM_REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
# `[\s>]`, not `>`: the peer-message envelope is `<teammate-message teammate_id="…">`, so a pattern
# demanding an immediate `>` matched none of them and left 199-to-1125-word agent briefs in the
# corpus as "typed prompts". Found by hand-auditing a random 30, not by reading the regex.
_XML_ENVELOPE = re.compile(r"\A<[a-z][a-z0-9-]*[\s>]")
_TYPED_SOURCES = ("typed", "queued")
ASSISTANT_CHARS = 500


class Turn(NamedTuple):
    role: str  # "user" | "assistant"
    text: str
    operator: bool  # user turns only: the operator typed it
    offset: int  # byte offset of the NEXT record, so a reader can resume


def _text(record: dict[str, Any]) -> str:
    msg = record.get("message")
    content = msg.get("content", "") if isinstance(msg, dict) else ""
    if isinstance(content, list):
        return " ".join(
            str(c.get("text", ""))
            for c in content
            if isinstance(c, dict) and c.get("type") == "text"
        )
    return str(content)


def operator_text(record: dict[str, Any]) -> str | None:
    """The operator-typed text of a user record (system reminders stripped), or None."""
    if record.get("type") != "user":
        return None
    text = _SYSTEM_REMINDER.sub("", _text(record)).strip()
    if not text:
        return None
    origin = record.get("origin")
    if isinstance(origin, dict) and origin.get("kind"):
        return (
            text if origin.get("kind") == "human" and not text.startswith("<") else None
        )
    source = record.get("promptSource")
    if source:
        return text if source in _TYPED_SOURCES else None
    if record.get("isMeta") or _XML_ENVELOPE.match(text):
        return None
    if any(text.startswith(p) for p in _FALLBACK_PREFIXES):
        return None
    return text


def is_operator(record: dict[str, Any]) -> bool:
    return operator_text(record) is not None


def typed_prompt(record: dict[str, Any]) -> str | None:
    """Return the user-typed text of a transcript record, or None if it was not typed by a human."""
    if record.get("type") != "user" or record.get("isSidechain"):
        return None
    if record.get("userType") not in (None, "external"):
        return None
    content = record.get("message", {}).get("content")
    if isinstance(content, list):
        # A list content block is a tool_result or an expanded slash command — never typing.
        return None
    if not isinstance(content, str):
        return None
    text = _SYSTEM_REMINDER.sub("", content).strip()
    if not text:
        return None
    if _XML_ENVELOPE.match(text):
        return None
    if any(text.startswith(p) for p in _INJECTED_PREFIXES):
        return None
    return text


def iter_turns(path: str, offset: int = 0) -> Iterator[Turn]:
    """User and assistant turns from `offset`. Attachments and tool_result-only turns are dropped."""
    with open(path, "rb") as fh:
        fh.seek(offset)
        for raw in fh:
            offset += len(raw)
            try:
                rec = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            role = rec.get("type")
            if role not in ("user", "assistant"):
                continue
            text = _text(rec).strip()
            if not text:
                continue
            if role == "assistant":
                yield Turn("assistant", text[:ASSISTANT_CHARS], False, offset)
            else:
                op = operator_text(rec)
                yield Turn(
                    "user", op if op is not None else text, op is not None, offset
                )
