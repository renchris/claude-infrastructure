"""Target-copy reads that feed §4.2 rows 2-5: where this attempt's submit token landed, and what the
last assistant turn after it was.

WHY SPLIT-TOLERANT (W0 finding a). The paste wrapper splits the submit token across
`</pasted_content>` (3d42fa49, and 3 of the 4 panes of the 09-29 04:17 cohort); a literal substring
scan missed a session that had in fact engaged and wrote a false FAILED:submit. So both the user
text and the token are normalised the same way — wrapper tags and ALL whitespace deleted — before
the substring test.

WHY NOTIFICATION IS ITS OWN VERDICT. A turn that answers a `<task-notification>` (or a
`<system-reminder>`) is a real, non-error assistant turn that our prompt did not cause: the 751/815
false RECOVEREDs and the 405-c shape. A turn only counts as ours when at least one non-notification
prompt arrived since the previous assistant record (947-e: the token and a queued notification land
in the same millisecond, and the turn answers both).

Api-error kinds come from THE limit predicate, lr_predicate.classify_record, never a local regex.
"""

import json
import os
import re
import sys
from typing import Any, Callable, Dict, Iterator, Optional, Tuple

try:
    import lr_predicate
except ImportError:  # run as lr_recon.* from scripts/limit-recover or from elsewhere
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import lr_predicate

# lr_predicate is untyped; pin the one entry point this module relies on to its real shape.
_classify: Callable[[Dict[str, Any]], Dict[str, Any]] = lr_predicate.classify_record

_PASTE_TAG_RE = re.compile(r"</?pasted_content[^>]*>")
_WS_RE = re.compile(r"\s+")
NOTIFICATION_PREFIXES = ("<task-notification>", "<system-reminder>")

# lr_predicate kinds → T.TARGET_LAST. org_blocked is an account that cannot serve (auth-shaped);
# "other" is an unnamed api error, retried like a server fault rather than read as success.
_KIND_MAP = {
    "limit": "limit",
    "auth_cliff": "authentication_failed",
    "org_blocked": "authentication_failed",
    "server_529": "server_529",
    "server_error": "server_error",
    "network": "network",
    "other": "server_error",
}


def normalise(text: str) -> str:
    """Delete paste-wrapper tags and every whitespace char (W0 a)."""
    return _WS_RE.sub("", _PASTE_TAG_RE.sub("", text))


def _records(path: str) -> Iterator[Tuple[int, Dict[str, Any]]]:
    """(byte offset of line start, parsed record) for each main-chain JSON line. A torn or
    non-JSON line is skipped: the file is live and its last line may be mid-write."""
    offset = 0
    with open(path, "rb") as fh:
        for raw in fh:
            start, offset = offset, offset + len(raw)
            try:
                rec = json.loads(raw)
            except ValueError:
                continue
            if isinstance(rec, dict) and not rec.get("isSidechain"):
                yield start, rec


def _user_text(rec: Dict[str, Any]) -> Optional[str]:
    """The prompt text of a user record, or None when it is only tool results / not a prompt."""
    msg = rec.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [
            b.get("text")
            for b in content
            if isinstance(b, dict)
            and b.get("type") == "text"
            and isinstance(b.get("text"), str)
        ]
        return "".join(p for p in parts if p) if parts else None
    return None


def _user_kind(rec: Dict[str, Any]) -> Optional[str]:
    """ "prompt" | "notification" for a user record that opens a turn; None for tool results and
    meta records, which never change who the next assistant turn answers."""
    if rec.get("type") != "user" or rec.get("isMeta"):
        return None
    text = _user_text(rec)
    if text is None:
        return None
    origin = rec.get("origin")
    okind = origin.get("kind") if isinstance(origin, dict) else None
    if (isinstance(okind, str) and "notification" in okind) or text.lstrip().startswith(
        NOTIFICATION_PREFIXES
    ):
        return "notification"
    return "prompt"


def find_token(path: str, token: str, min_offset: int = 0) -> Optional[int]:
    """Byte offset of the first user record at offset > ``min_offset`` whose text carries ``token``
    after normalisation. Strictly greater, matching row 5's "offset greater than confirm_len"; a
    transcript's first line is metadata, never a submitted prompt."""
    want = normalise(token)
    if not want:
        return None
    for off, rec in _records(path):
        if off <= min_offset or rec.get("type") != "user":
            continue
        text = _user_text(rec)
        if text is not None and want in normalise(text):
            return off
    return None


def _turns_after(path: str, offset: int) -> Iterator[Tuple[Dict[str, Any], bool]]:
    """(assistant record, answers-a-prompt) for each assistant record after ``offset``. The record
    AT ``offset`` is the submit record, so the first turn after it answers a prompt."""
    answers_prompt = True
    turn_closed = (
        False  # an assistant record has been seen since the last opening user record
    )
    for off, rec in _records(path):
        if off <= offset:
            continue
        kind = _user_kind(rec)
        if kind is not None:
            answers_prompt = (kind == "prompt") or (answers_prompt and not turn_closed)
            turn_closed = False
        elif rec.get("type") == "assistant":
            turn_closed = True
            yield rec, answers_prompt


def _verdict(rec: Dict[str, Any], answers_prompt: bool) -> str:
    kind = _classify(rec).get("kind")
    if kind is not None:
        return _KIND_MAP.get(kind, "server_error")
    return "ok" if answers_prompt else "notification"


def last_assistant_after(path: str, offset: int) -> str:
    """The T.TARGET_LAST verdict of the last assistant record after ``offset`` ("none" if none)."""
    last: Optional[Tuple[Dict[str, Any], bool]] = None
    for turn in _turns_after(path, offset):
        last = turn
    return "none" if last is None else _verdict(*last)


def nonerror_after(path: str, offset: int) -> bool:
    """True iff a non-error assistant record that answers a prompt (not a notification) follows."""
    return any(_verdict(rec, ours) == "ok" for rec, ours in _turns_after(path, offset))
