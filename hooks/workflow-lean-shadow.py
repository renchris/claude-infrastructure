#!/usr/bin/env python3
"""PreToolUse hook on Workflow — LOG ONLY. It never denies, never asks, prints nothing on stdout and
exits 0 on every path, its own failures included.

WHY (docs/plans/USAGE_LEVERS.md W1.3; docs/research/usage-levers-2026-10-23/round2/REPORT.md). A
read-only Workflow slot run as the default agent loads CLAUDE.md, rules, memory and skills; the same
slot as `agentType: 'workflow-lean'` starts ~84% cheaper at equal correctness. A deny-mode hook that
refuses an agent() call without agentType is the candidate enforcement, but round 2 put its saving
at 65% conviction and found that the 2026-10-04 "deny" was a 5 s hook TIMEOUT that let the workflow
run anyway. So before anything denies, this hook measures, per agent() call:
  - the verdict a deny-mode hook would reach: has-agent-type | would-deny | keep-default | unknown
  - what a rewrite would add (`agentType: 'workflow-lean'`), or nothing
  - whether the slot's brief names commit / ship / Skill / MCP (such a slot keeps the default agent:
    workflow-lean has no Skill, Agent or MCP tools and is not for commits or lands)
  - the hook's own latency against the 5 s timeout (wall from main(), plus process CPU, which
    includes interpreter start-up)

W6 (decision re-research 2026-10-24) adds what a deny would need to be safe: `resume_from_run_id`
(a deny obeyed on a resume re-runs the finished slots), `script_sha` and `repeat_in_session` (how
many earlier rows of this session carried the same script), and a `/* needs-default */` comment
inside an agent() call, which the would-deny verdict honors as keep-default.

W7+ S3 (plan § W7+ §2 D2 "Arm", §3 "Telemetry rows", §6 on UTC and 2 KB rows), still log-only:
  - `ts` is UTC with a Z suffix (rows before S3 carry a local offset such as -0500);
  - `acct`, the config dir running the hook;
  - `lineage` / `lineage_src` and `arm`, lever D2's arm for the lineage root (salt_D2), from
    hooks/lib/lever_flags.py; resolved read-only (write=False), so this hook never writes lever state.
    At pct 0 every unit is ctrl, and nothing here reads the arm to decide anything;
  - `follows_deny`: whether this session's previous Workflow row was a would-deny (null when there is
    none in the log's tail), with `prev_tool_use_id`, `prev_gap_s` and `prev_same_script` — the
    edited-resubmit signal D2's compliance metric is scored from.
Each row is ONE write() of at most 2 KB, so concurrent appends stay whole: past that the slot list is
compacted to (line, verdict, agent_type), then dropped (`slots_shed`).

One JSON row per Workflow call to $HOME/.claude/logs/workflow-lean-shadow.jsonl. The brief text is
never logged, only its length and the markers.

The parser is a small JS scanner, not a JS parser: it skips strings, template literals (with nested
${...}), and comments, finds `agent(` at an identifier boundary (not `x.agent(`), and splits the
call's top-level arguments. A brief or options object it cannot read statically (a variable, a
spread) is `unknown`, never guessed into either verdict.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import signal
import sys
import time
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

TIMEOUT_S = 5  # the registered hook timeout (migrations/0078); a hook past it lets the call through
SELF_BOUND_S = 3  # abandon parsing well inside it, and log that instead
REWRITE = "agentType: 'workflow-lean'"
MARKERS = {
    "commit": re.compile(r"\bcommit(s|ted|ting)?\b", re.I),
    "ship": re.compile(r"/ship\b|\bship(s|ped|ping)?\b|\bship-land\b", re.I),
    "skill": re.compile(r"\bskills?\b", re.I),
    "mcp": re.compile(r"\bmcp\b|mcp__", re.I),
}
IDENT = re.compile(r"[A-Za-z0-9_$]")
NEEDS_DEFAULT = re.compile(r"\bneeds-default\b")
LOG_TAIL_BYTES = 4_000_000  # repeat_in_session and follows_deny scan this much of the log's end
MAX_ROW = 2048  # one write() at most this many bytes (lever_flags.MAX_ROW)


class Bounded(Exception):
    pass


def skip_quoted(src: str, i: int) -> int:
    """src[i] is ' or " : return the index after the closing quote."""
    q, i = src[i], i + 1
    while i < len(src):
        c = src[i]
        if c == "\\":
            i += 2
            continue
        if c == q or c == "\n":
            return i + 1
        i += 1
    return i


def skip_template(
    src: str, i: int, parts: Optional[List[str]] = None
) -> Tuple[int, bool]:
    """src[i] is a backtick: return (index after it, whether it interpolates). Static text is
    appended to parts when given."""
    i += 1
    interp = False
    buf: List[str] = []
    while i < len(src):
        c = src[i]
        if c == "\\":
            buf.append(src[i : i + 2])
            i += 2
            continue
        if c == "`":
            i += 1
            break
        if c == "$" and src.startswith("${", i):
            interp = True
            i = walk(src, i + 2, "}") + 1
            continue
        buf.append(c)
        i += 1
    if parts is not None:
        parts.append("".join(buf))
    return i, interp


def skip_comment(src: str, i: int) -> Optional[int]:
    if src.startswith("//", i):
        j = src.find("\n", i)
        return len(src) if j < 0 else j
    if src.startswith("/*", i):
        j = src.find("*/", i + 2)
        return len(src) if j < 0 else j + 2
    return None


def walk(src: str, i: int, closer: str) -> int:
    """Walk code from i to the index of the unmatched closer (or len(src))."""
    depth = 0
    while i < len(src):
        c = src[i]
        j = skip_comment(src, i)
        if j is not None:
            i = j
            continue
        if c in "'\"":
            i = skip_quoted(src, i)
            continue
        if c == "`":
            i, _ = skip_template(src, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0 and c == closer:
                return i
            depth -= 1
        i += 1
    return i


def split_args(src: str, i: int) -> Tuple[List[str], int]:
    """src[i] is the '(' of a call: return its top-level argument texts and the index after ')'."""
    args: List[str] = []
    start, depth, i = i + 1, 0, i + 1
    while i < len(src):
        c = src[i]
        j = skip_comment(src, i)
        if j is not None:
            i = j
            continue
        if c in "'\"":
            i = skip_quoted(src, i)
            continue
        if c == "`":
            i, _ = skip_template(src, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                args.append(src[start:i])
                return [a for a in args if a.strip()], i + 1
            depth -= 1
        elif c == "," and depth == 0:
            args.append(src[start:i])
            start = i + 1
        i += 1
    args.append(src[start:i])
    return [a for a in args if a.strip()], i


def agent_calls(src: str) -> List[Tuple[int, List[str]]]:
    """(offset, argument texts) for every `agent(` call in code (not in strings or comments)."""
    out: List[Tuple[int, List[str]]] = []
    i = 0
    while i < len(src):
        c = src[i]
        j = skip_comment(src, i)
        if j is not None:
            i = j
            continue
        if c in "'\"":
            i = skip_quoted(src, i)
            continue
        if c == "`":
            # a template's ${...} is code too, and agent() calls live there in map callbacks
            k = i + 1
            while k < len(src) and src[k] != "`":
                if src[k] == "\\":
                    k += 2
                    continue
                if src.startswith("${", k):
                    end = walk(src, k + 2, "}")
                    out.extend(
                        (k + 2 + off, a) for off, a in agent_calls(src[k + 2 : end])
                    )
                    k = end + 1
                    continue
                k += 1
            i = k + 1
            continue
        if src.startswith("agent", i) and (
            i == 0 or not (IDENT.match(src[i - 1]) or src[i - 1] == ".")
        ):
            k = i + 5
            if k < len(src) and IDENT.match(src[k]):
                i = k
                continue
            while k < len(src) and src[k] in " \t\r\n":
                k += 1
            if k < len(src) and src[k] == "(":
                args, end = split_args(src, k)
                out.append((i, args))
                i = k + 1  # nested agent() calls inside the arguments are still found
                continue
        i += 1
    return out


def brief_text(arg: str) -> Tuple[str, str]:
    """(kind, static text) of an agent() brief: literal | template | interpolated | opaque."""
    parts: List[str] = []
    s = arg.strip()
    i, interp, code = 0, False, False
    while i < len(s):
        c = s[i]
        if c in "'\"":
            j = skip_quoted(s, i)
            parts.append(s[i + 1 : j - 1])
            i = j
        elif c == "`":
            i, ip = skip_template(s, i, parts)
            interp = interp or ip
        elif c in " \t\r\n+()":
            i += 1
        else:
            code = True
            i += 1
    if not parts:
        return "opaque", ""
    if code or interp:
        return "interpolated", "".join(parts)
    return ("template" if s.startswith("`") else "literal"), "".join(parts)


def options(arg: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
    """(agentType, label) of an agent() options argument. agentType is None when absent, the
    literal value when set to a string, and "opaque" when it cannot be read (a variable, a spread)."""
    if arg is None:
        return None, None
    s = arg.strip()
    if not s.startswith("{"):
        return "opaque", None
    body = s[1 : walk(s, 1, "}")]
    label_m = re.search(r"""\blabel\s*:\s*(['"`])((?:(?!\1).){0,200})\1""", body)
    label = label_m.group(2)[:80] if label_m else None
    # top-level keys only: blank out nested brackets and strings first
    flat: List[str] = []
    i, depth = 0, 0
    while i < len(body):
        c = body[i]
        if c in "'\"`":
            j = skip_quoted(body, i) if c != "`" else skip_template(body, i)[0]
            flat.append(body[i:j] if depth == 0 else " ")
            i = j
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif depth == 0:
            flat.append(c)
        i += 1
    top = "".join(flat)
    m = re.search(
        r"""(?:^|[,{\s])['"]?agentType['"]?\s*(:\s*(['"`])([^'"`]*)\2|:|(?=[,}\s]|$))""",
        top,
    )
    if m:
        if m.group(3) is not None:
            return m.group(3), label
        return "opaque", label
    if "..." in top:
        return "opaque", label
    return None, label


def comment_marker(args: List[str]) -> bool:
    """True when a comment (not a string) inside the call's arguments says needs-default."""
    for a in args:
        i = 0
        while i < len(a):
            c = a[i]
            j = skip_comment(a, i)
            if j is not None:
                if NEEDS_DEFAULT.search(a[i:j]):
                    return True
                i = j
                continue
            if c in "'\"":
                i = skip_quoted(a, i)
                continue
            if c == "`":
                i, _ = skip_template(a, i)
                continue
            i += 1
    return False


def slot_row(src: str, off: int, args: List[str]) -> Dict[str, Any]:
    kind, text = brief_text(args[0]) if args else ("opaque", "")
    agent_type, label = options(args[1] if len(args) > 1 else None)
    markers = {k: bool(rx.search(text)) for k, rx in MARKERS.items()}
    needs_default = comment_marker(args)
    if agent_type is not None and agent_type != "opaque":
        verdict, rewrite = "has-agent-type", None
    elif needs_default:
        verdict, rewrite = "keep-default", None
    elif agent_type == "opaque" or kind == "opaque":
        verdict, rewrite = "unknown", None
    elif any(markers.values()):
        verdict, rewrite = "keep-default", None
    else:
        verdict, rewrite = "would-deny", REWRITE
    return {
        "line": src.count("\n", 0, off) + 1,
        "label": label,
        "agent_type": agent_type,
        "brief": kind,
        "brief_chars": len(text),
        "markers": markers,
        "needs_default": needs_default,
        "verdict": verdict,
        "rewrite": rewrite,
    }


def script_source(ti: Dict[str, Any], cwd: str) -> Tuple[str, Optional[str]]:
    if isinstance(ti.get("script"), str):
        return "script", ti["script"]
    for key, paths in (
        ("scriptPath", [ti.get("scriptPath")]),
        (
            "name",
            [
                os.path.join(d, ".claude", "workflows", f"{ti.get('name')}{ext}")
                for d in (cwd, os.path.expanduser("~"))
                for ext in (".js", ".mjs", "")
            ]
            if isinstance(ti.get("name"), str)
            else [],
        ),
    ):
        for p in paths:
            if isinstance(p, str) and os.path.isfile(p):
                with open(p, encoding="utf-8", errors="replace") as fh:
                    return key, fh.read()
        if ti.get(key):
            return key, None
    return "none", None


def history(log: str, sid: Any, sha: Optional[str]) -> Tuple[int, Optional[Dict[str, Any]]]:
    """(earlier rows of this session with the same script sha, this session's latest row) from the
    log's tail."""
    if not isinstance(sid, str) or not sid:
        return 0, None
    try:
        with open(log, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - LOG_TAIL_BYTES))
            raw = fh.read()
    except OSError:
        return 0, None
    n, prev, needle = 0, None, json.dumps(sid).encode()
    for ln in raw.split(b"\n"):
        if needle not in ln:
            continue
        try:
            r = json.loads(ln)
        except ValueError:
            continue
        if not isinstance(r, dict) or r.get("session_id") != sid:
            continue
        prev = r
        if sha and r.get("script_sha") == sha:
            n += 1
    return n, prev


def ts_epoch(ts: Any) -> Optional[float]:
    """Epoch of a row's ts: UTC Z (S3 on) or a local offset (earlier rows); None when unparsable."""
    if not isinstance(ts, str):
        return None
    try:
        return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S%z").timestamp()
    except ValueError:
        return None


def lever_arm(sid: Any) -> Dict[str, Any]:
    """lineage, lineage_src and the D2 arm of the lineage root; empty when the lib is unavailable."""
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib"))
        import lever_flags as lf  # noqa: E402 — the hook must run even when the lib is missing

        if not isinstance(sid, str) or not lf._safe(sid):
            return {"lineage": None, "lineage_src": None, "arm": lf.arm("D2", "-")}
        root, src = lf.resolve_lineage(sid, write=False)
        return {"lineage": root, "lineage_src": src, "arm": lf.arm("D2", root)}
    except Bounded:
        raise
    except Exception as e:
        return {"lineage": None, "lineage_src": None, "arm": None,
                "arm_error": f"{e.__class__.__name__}: {e}"[:120]}


def encode(row: Dict[str, Any]) -> Optional[bytes]:
    """The row as one line of at most MAX_ROW bytes, shedding slot detail first; None if it cannot fit."""
    def enc(r: Dict[str, Any]) -> bytes:
        return (json.dumps(r, separators=(",", ":")) + "\n").encode("utf-8")

    line = enc(row)
    if len(line) <= MAX_ROW or "slots" not in row:
        return line if len(line) <= MAX_ROW else None
    compact = [
        {"line": s.get("line"), "verdict": s.get("verdict"),
         "agent_type": (s.get("agent_type") or None) and str(s.get("agent_type"))[:40]}
        for s in row["slots"]
    ]
    line = enc(dict(row, slots=compact, slots_shed="compact"))
    if len(line) <= MAX_ROW:
        return line
    rest = {k: v for k, v in row.items() if k != "slots"}
    line = enc(dict(rest, slots_shed="all"))
    return line if len(line) <= MAX_ROW else None


def main() -> None:
    t0 = time.monotonic()
    now = time.time()
    row: Dict[str, Any] = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "hook": "workflow-lean-shadow",
        "v": 3,
        "acct": os.path.basename(
            (os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")).rstrip("/")
        ),
    }
    log = os.path.join(
        os.path.expanduser("~"), ".claude", "logs", "workflow-lean-shadow.jsonl"
    )
    try:
        data = json.load(sys.stdin)
        ti = data.get("tool_input") or {}
        rid = ti.get("resumeFromRunId")
        row.update(
            session_id=data.get("session_id"),
            tool_use_id=data.get("tool_use_id"),
            cwd=data.get("cwd")[:300] if isinstance(data.get("cwd"), str) else data.get("cwd"),
            tool_name=data.get("tool_name"),
            resume_from_run_id=rid if isinstance(rid, str) and rid else None,
        )
        row.update(lever_arm(row["session_id"]))
        source, src = script_source(ti, data.get("cwd") or os.getcwd())
        row["source"] = source
        sha = (
            hashlib.sha256(src.encode("utf-8", "replace")).hexdigest()
            if src is not None
            else None
        )
        n_rep, prev = history(log, row["session_id"], sha)
        row["follows_deny"] = None if prev is None else prev.get("would_deny") is True
        if prev is not None:
            pe = ts_epoch(prev.get("ts"))
            row["prev_tool_use_id"] = prev.get("tool_use_id")
            row["prev_gap_s"] = None if pe is None else round(now - pe, 1)
            row["prev_same_script"] = bool(sha) and prev.get("script_sha") == sha
        if src is None:
            row["parse"] = "unresolved"
        else:
            row["script_chars"] = len(src)
            row["script_sha"] = sha
            row["repeat_in_session"] = n_rep
            slots = [slot_row(src, off, args) for off, args in agent_calls(src)]
            row["parse"] = "ok"
            row["calls"] = len(slots)
            row["calls_without_agent_type"] = sum(
                1 for s in slots if s["agent_type"] is None
            )
            counts: Dict[str, int] = {}
            for s in slots:
                counts[s["verdict"]] = counts.get(s["verdict"], 0) + 1
            row["verdicts"] = counts
            row["would_deny"] = counts.get("would-deny", 0) > 0
            row["slots"] = slots
    except Bounded:
        row["parse"] = "self-bounded"
    except Exception as e:  # never let a parse failure become a hook failure
        row["parse"] = "error"
        row["error"] = f"{e.__class__.__name__}: {e}"[:200]
    row["latency_ms"] = {
        "wall": round((time.monotonic() - t0) * 1000, 2),
        "cpu": round(time.process_time() * 1000, 2),
        "timeout_s": TIMEOUT_S,
    }
    line = encode(row)
    if line is None:
        return
    try:
        os.makedirs(os.path.dirname(log), exist_ok=True)
        fd = os.open(log, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
        try:
            os.write(fd, line)  # one write(): O_APPEND keeps concurrent rows whole
        finally:
            os.close(fd)
    except OSError:
        pass


def _bound(_sig: int, _frm: Any) -> None:
    raise Bounded()


if __name__ == "__main__":
    if os.environ.get("CC_WORKFLOW_SHADOW") != "off":
        try:
            signal.signal(signal.SIGALRM, _bound)
            signal.alarm(SELF_BOUND_S)
            main()
        except BaseException:  # noqa: BLE001 — log-only: no path may block or fail the call
            pass
        finally:
            signal.alarm(0)
    sys.exit(0)
