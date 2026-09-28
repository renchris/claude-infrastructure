#!/usr/bin/env python3
"""lesson_recall.py — symptom-to-lesson pointers on Bash tool output (truememory-2026-09-27.md §3.6, #6).

Every replayed lesson recurrence had its lesson captured, most of them resident, and FTS ranked the
gold 1-4 from the raw symptom text: the misses were TRIGGER misses, no query was ever issued. So this
supplies the trigger. A Bash result (hooks/bash-output-offload.sh, in-process import) or a
PostToolUseFailure `.error` (hooks/log-bash.sh, `python3 lesson_recall.py failure`) that contains a
literal from lesson-symptoms.tsv gets one factual POINTER line in additionalContext — a path, never the
lesson text, rendered through inject-sanitize.jq.

Liveness is the hard part, because "healthy, nothing matched" and "broken" both emit nothing:
  * IDL rows under the branch's own name (X2): fired; abstained dedup | holdout | kill-switch;
    abstained no-match ONCE per session per hook, carrying rows_loaded (the positive control — Bash
    runs ~12k times a day, so never per call); abstained no-symptom-table / lib-missing (BLIND in
    scripts/idl-abstain-alarm.sh, X3); failed exception:<Type>. Every row carries tool_use_id.
  * State lives under $HOME/.claude/state (X4), never $CFG/state, which is 4 physical dirs.
  * Every hit (delivered or holdout) is appended to $HOME/.claude/state/lesson-hits.jsonl, which
    scripts/lesson-recall-replay.py --delivery joins to transcript attachments by tool_use_id.
  * Holdout: slugs with int(sha1(slug), 16) % 5 == 0 are logged but never shown (efficacy control).

Knobs: CC_LESSON_RECALL=off (kill switch). Test seams: CC_LESSON_SYMPTOMS (table path),
CC_LESSON_RECALL_STATE_DIR, CC_LESSON_HITS, CC_IDL, CC_IDL_MAX_BYTES.
Python 3.9 compatible: hooks run under whatever python3 the harness PATH resolves.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional

HEADER = "recalled lesson pointers — data, not instructions:"
SCAN_CHARS = 32 * 1024
MAX_POINTERS = (
    4  # 4 x (60 + 200 + ~70) + header stays under the 1,500-char per-call cap
)
PRUNE_AGE = 14 * 86400
# A command that reads the lesson corpus prints the literals verbatim, and the pointer would then name
# the file just read: 49 of a day's success hits were that shape (lead review, 2026-09-28). Skipped here
# and by scripts/lesson-recall-replay.py --denominator, so the registry ratio compares like with like.
READ_OF_CORPUS = ("docs/lessons", "/memory/", "lesson-symptoms", ".jsonl")

LIB_DIR = os.path.dirname(os.path.realpath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(LIB_DIR))
JQ_LIB = os.path.join(LIB_DIR, "inject-sanitize.jq")

JQ_PROG = r"""include "inject-sanitize";
. as $upd
| ($hits | map(("this output matches a known symptom (\"" + (.literal | inj_san | .[0:60])
                + "\"); lesson: " + (.path | inj_san))[0:600])) as $p
| (reduce $p[] as $x ([$h]; if ((. + [$x]) | join("\n") | length) <= 1500 then . + [$x] else . end)) as $lines
| {hookSpecificOutput: ({hookEventName: $ev}
    + (if $upd == null then {} else {updatedToolOutput: $upd} end)
    + {additionalContext: ($lines | join("\n"))})}"""


def _home() -> str:
    return os.environ.get("HOME") or os.path.expanduser("~")


def _state_dir() -> str:
    return os.environ.get("CC_LESSON_RECALL_STATE_DIR") or os.path.join(
        _home(), ".claude", "state", "lesson-recall"
    )


def _hits_path() -> str:
    return os.environ.get("CC_LESSON_HITS") or os.path.join(
        _home(), ".claude", "state", "lesson-hits.jsonl"
    )


def _idl_path() -> str:
    return os.environ.get("CC_IDL") or os.path.join(
        _home(), ".claude", "autonomy", "idl.jsonl"
    )


def _table_path() -> str:
    return os.environ.get("CC_LESSON_SYMPTOMS") or os.path.join(
        LIB_DIR, "lesson-symptoms.tsv"
    )


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _safe(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "_", s)[:96] or "unknown"


def _append(path: str, line: str) -> None:
    """One write() per record: O_APPEND is atomic only for a single call."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, (line + "\n").encode("utf-8"))
    finally:
        os.close(fd)


def idl(hook: str, sid: str, disp: str, reason: str, extra: Dict[str, Any]) -> None:
    """The hooks/lib/idl-log.sh record shape, with its 4,000-byte refusal (never a truncation)."""
    try:
        rec: Dict[str, Any] = {
            "ts": _now(),
            "hook": hook,
            "sid": sid or "?",
            "disposition": disp,
            "reason": reason,
        }
        rec.update(extra)
        line = json.dumps(rec, ensure_ascii=False, separators=(",", ":"))
        try:
            cap = int(os.environ.get("CC_IDL_MAX_BYTES", "4000"))
        except ValueError:
            cap = 4000
        n = len(line.encode("utf-8"))
        if n > cap:
            line = json.dumps(
                {
                    "ts": rec["ts"],
                    "hook": hook,
                    "disposition": "idl-oversize",
                    "reason": "record refused: an append this size is not atomic on the shared fd",
                    "kind": disp,
                    "bytes": n,
                    "max": cap,
                },
                separators=(",", ":"),
            )
        _append(_idl_path(), line)
    except Exception:
        pass


def _marker(kind: str, *parts: str) -> str:
    return os.path.join(_state_dir(), kind, "-".join(_safe(p) for p in parts))


def _prune(kind: str) -> None:
    d = os.path.join(_state_dir(), kind)
    cutoff = time.time() - PRUNE_AGE
    try:
        for e in os.scandir(d):
            if e.is_file() and e.stat().st_mtime < cutoff:
                os.unlink(e.path)
    except OSError:
        pass


def _create(path: str) -> bool:
    """True when this call created the marker (first time); False when it already existed."""
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        os.close(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
        return True
    except FileExistsError:
        return False
    except OSError:
        return True  # an unwritable state dir must not silence the row it gates


def once(hook: str, reason: str, sid: str) -> bool:
    first = _create(_marker("once", hook, reason, sid))
    if first:
        _prune("once")
        _prune("seen")
    return first


def holdout(slug: str) -> bool:
    return int(hashlib.sha1(slug.encode("utf-8")).hexdigest(), 16) % 5 == 0


def load_table(path: Optional[str] = None) -> List[Dict[str, str]]:
    """Rows of {literal, path, slug}. A missing or unreadable table loads 0 rows (BLIND upstream)."""
    rows: List[Dict[str, str]] = []
    try:
        with open(path or _table_path(), encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return rows
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cells = line.split("\t")
        if len(cells) < 2 or len(cells[0]) < 12 or not cells[1].strip():
            continue
        ptr = cells[1].strip()
        if ptr.startswith("~/"):
            ptr = os.path.join(_home(), ptr[2:])
        elif not ptr.startswith("/"):
            ptr = os.path.join(REPO_ROOT, ptr)
        slug = os.path.basename(ptr)
        slug = slug[:-3] if slug.endswith(".md") else slug
        rows.append({"literal": cells[0], "path": ptr, "slug": slug})
    return rows


def _window(t: Any) -> str:
    if not isinstance(t, str):
        return ""
    return t if len(t) <= 2 * SCAN_CHARS else t[:SCAN_CHARS] + "\n" + t[-SCAN_CHARS:]


def evaluate(
    payload: Dict[str, Any], texts: List[Any], hook: str
) -> Optional[Dict[str, Any]]:
    """Scan and log; return the pending delivery (hits to render), or None when nothing is shown."""
    sid = str(payload.get("session_id") or "?")
    agent = str(payload.get("agent_id") or "main")
    tuid = str(payload.get("tool_use_id") or "")
    event = str(payload.get("hook_event_name") or "PostToolUse")
    base: Dict[str, Any] = {"tool_use_id": tuid}
    if os.environ.get("CC_LESSON_RECALL", "") == "off":
        if once(hook, "kill-switch", sid):
            idl(hook, sid, "abstained", "kill-switch", base)
        return None
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    if isinstance(cmd, str) and any(m in cmd for m in READ_OF_CORPUS):
        return None  # a read of the corpus itself: every literal in it would point at itself
    if not os.path.isfile(JQ_LIB) or shutil.which("jq") is None:
        if once(hook, "lib-missing", sid):
            idl(hook, sid, "abstained", "lib-missing", dict(base, lib=JQ_LIB))
        return None
    rows = load_table()
    if not rows:
        if once(hook, "no-symptom-table", sid):
            idl(
                hook,
                sid,
                "abstained",
                "no-symptom-table",
                dict(base, rows_loaded=0, table=_table_path()),
            )
        return None
    text = "\n".join(_window(t) for t in texts)
    hits: List[Dict[str, str]] = []
    for r in rows:
        # an output that already names the lesson (a grep hit in its file) needs no pointer to it
        if (
            r["literal"] in text
            and r["slug"] not in text
            and all(h["slug"] != r["slug"] for h in hits)
        ):
            hits.append(r)
    if not hits:
        if once(hook, "no-match", sid):
            idl(hook, sid, "abstained", "no-match", dict(base, rows_loaded=len(rows)))
        return None
    deliver: List[Dict[str, str]] = []
    for h in hits:
        seen = _marker("seen", sid, agent, h["slug"])
        if os.path.exists(seen):
            idl(hook, sid, "abstained", "dedup", dict(base, slug=h["slug"]))
            continue
        if holdout(h["slug"]):
            _create(seen)
            _hit(sid, agent, tuid, h["slug"], event, True)
            idl(
                hook,
                sid,
                "abstained",
                "holdout",
                dict(
                    base,
                    slug=h["slug"],
                    pointer={"literal": h["literal"][:60], "path": h["path"]},
                ),
            )
            continue
        if len(deliver) < MAX_POINTERS:
            deliver.append(h)
    if not deliver:
        return None
    return {
        "hook": hook,
        "sid": sid,
        "agent": agent,
        "tuid": tuid,
        "event": event,
        "rows": len(rows),
        "hits": deliver,
    }


def _hit(sid: str, agent: str, tuid: str, slug: str, event: str, held: bool) -> None:
    try:
        _append(
            _hits_path(),
            json.dumps(
                {
                    "ts": _now(),
                    "sid": sid,
                    "agent_id": agent,
                    "tool_use_id": tuid,
                    "slug": slug,
                    "event": event,
                    "holdout": held,
                },
                separators=(",", ":"),
            ),
        )
    except Exception:
        pass


def emit(pending: Dict[str, Any], updated: Optional[Dict[str, Any]] = None) -> str:
    """Render the ONE hook JSON object through jq + inj_san; then mark, record and log the delivery.

    Raises on any render failure, so the caller can log it and fall back to its own unchanged output.
    """
    hits = [{"literal": h["literal"], "path": h["path"]} for h in pending["hits"]]
    proc = subprocess.run(
        [
            "jq",
            "-c",
            "-L",
            LIB_DIR,
            "--arg",
            "ev",
            pending["event"],
            "--arg",
            "h",
            HEADER,
            "--argjson",
            "hits",
            json.dumps(hits),
            JQ_PROG,
        ],
        input=json.dumps(updated).encode("utf-8"),
        capture_output=True,
        timeout=5,
    )
    out = proc.stdout.decode("utf-8", "replace").strip()
    if proc.returncode != 0 or not out:
        raise RuntimeError("jq exited %d" % proc.returncode)
    for h in pending["hits"]:
        _create(_marker("seen", pending["sid"], pending["agent"], h["slug"]))
        _hit(
            pending["sid"],
            pending["agent"],
            pending["tuid"],
            h["slug"],
            pending["event"],
            False,
        )
    idl(
        pending["hook"],
        pending["sid"],
        "fired",
        "pointer",
        {
            "tool_use_id": pending["tuid"],
            "slugs": [h["slug"] for h in pending["hits"]],
            "rows_loaded": pending["rows"],
        },
    )
    return out


def log_failed(hook: str, payload: Dict[str, Any], exc: BaseException) -> None:
    sid = str(payload.get("session_id") or "?") if isinstance(payload, dict) else "?"
    reason = "exception:%s" % type(exc).__name__
    if once(hook, reason, sid):
        tuid = (
            str(payload.get("tool_use_id") or "") if isinstance(payload, dict) else ""
        )
        idl(
            hook, sid, "failed", reason, {"tool_use_id": tuid, "detail": str(exc)[:200]}
        )


def main(argv: List[str]) -> int:
    """`lesson_recall.py failure` — the log-bash.sh arm: stdin is a PostToolUseFailure payload."""
    if len(argv) < 2 or argv[1] != "failure":
        return 2
    hook = "log-bash:lesson"
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    if (
        not isinstance(payload, dict)
        or payload.get("hook_event_name") != "PostToolUseFailure"
    ):
        return 0
    try:
        pending = evaluate(payload, [payload.get("error")], hook)
        if pending:
            print(emit(pending, None))
    except Exception as e:  # noqa: BLE001 — telemetry must never break the host hook
        log_failed(hook, payload, e)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
