#!/usr/bin/env python3
"""lr-audit — disk-truth audit of a Claude Code session's delegated work.

Classifies every Dynamic Workflow agent slot, bare subagent, AND team assignee
session (implicit-team teammates) from on-disk artifacts (journal.jsonl,
agent-*.jsonl, run summary JSON, lead transcript, teams/<t>/config.json,
teammate transcripts, brief-declared deliverable paths) so a recovering session
re-runs exactly what is incomplete and never "bridges" gaps from memory.
Verdicts are mechanical; semantic judgment (vacuous-suspect review) is left to
the invoking model.

Teammate ground rule (incident 2026-07-18, team session-44f5331d): the lead's
"Teammate failed" notification is NOT ground truth — teammates retry past a
429, finish, and their SendMessage/report handshake to the lead fails anyway
("SendMessage isn't available in this subagent context"). The ONLY dependable
completion evidence is the deliverable on disk: brief-declared output paths
written during the member's tenure, worktree commits, or wip checkpoint refs.

Verdicts (per unit):
  COMPLETE             journaled result / clean final assistant turn, above floors
  COMPLETE_UNDELIVERED completed on disk but its result never reached the lead
                       transcript (lead killed first) -> READ from disk, no re-run
  COMPLETE_SALVAGED    StructuredOutput validated in the agent's own jsonl but
                       never journaled (killed after SO) -> payload usable
  VACUOUS_SUSPECT      mechanically complete but below signal floors -> model review
  PARTIAL              substantive work, no result -> re-run (salvage as seed only)
  NULL                 killed at/near spawn (limit / 529 / api error) -> re-run
  INTERRUPTED          TaskStop / user interrupt -> re-run unless salvaged
  UNVERIFIABLE         artifacts missing/contradictory -> surface, never guess
  RUNNING              (teammates only) recent activity, no terminal state ->
                       wait; never respawn over a live member

Exit codes: 0 = no gaps, 1 = gaps present, 2 = usage/artifact error.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

TAIL_BYTES = 128 * 1024
LIMIT_PREFIXES = (
    ("session", "You've hit your session limit"),
    ("weekly", "You've hit your weekly limit"),
    ("monthly_spend", "You've hit your monthly spend limit"),
)
SERVER_529 = "API Error: Server is temporarily limiting requests"
RESET_RE = re.compile(
    r"resets (?:([A-Z][a-z]{2} \d{1,2}) at )?(\d{1,2}(?::\d{2})?(?:am|pm)) \(([^)]+)\)"
)
RUNID_RE = re.compile(r"wf_[a-z0-9]{8}-[a-z0-9]{2,4}")
MONTHS = {
    m: i + 1
    for i, m in enumerate(
        [
            "Jan",
            "Feb",
            "Mar",
            "Apr",
            "May",
            "Jun",
            "Jul",
            "Aug",
            "Sep",
            "Oct",
            "Nov",
            "Dec",
        ]
    )
}

GAP_VERDICTS = {"PARTIAL", "NULL", "INTERRUPTED", "UNVERIFIABLE", "VACUOUS_SUSPECT"}

# Teammate (assignee-session) audit -----------------------------------------
TEAM_ACTIVE_WINDOW_S = 300  # last transcript activity newer than this = RUNNING
# Absolute file paths (with an extension) declared inside a teammate brief —
# the mechanical deliverable contract ("Write the FULL report ... to /…/x.md").
PROMPT_PATH_RE = re.compile(
    r"(?<![\w@.~-])(/(?:[\w.@+~-]+/)+[\w.@+~-]+\.[A-Za-z0-9]{1,8})"
)


def jline(line):
    try:
        return json.loads(line)
    except (json.JSONDecodeError, ValueError):
        return None


def content_items(msg):
    c = (msg or {}).get("content")
    if isinstance(c, str):
        return [{"type": "text", "text": c}]
    return c if isinstance(c, list) else []


def text_of(msg):
    return " ".join(
        i.get("text", "") for i in content_items(msg) if i.get("type") == "text"
    )


def tail_records(path, n=6):
    """Last n parseable records without reading the whole file."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            f.seek(max(0, size - TAIL_BYTES))
            chunk = f.read().decode("utf-8", errors="replace")
    except OSError:
        return []
    lines = [ln for ln in chunk.splitlines() if ln.strip()]
    out = []
    for ln in lines[-n:]:
        obj = jline(ln)
        if obj:
            out.append(obj)
    return out


def parse_reset(text, event_ts_iso):
    m = RESET_RE.search(text)
    if not m or ZoneInfo is None:
        return None
    date_part, time_part, tzname = m.groups()
    try:
        tz = ZoneInfo(tzname)
        base = datetime.fromisoformat(event_ts_iso.replace("Z", "+00:00")).astimezone(
            tz
        )
        tm = time_part.replace("am", " am").replace("pm", " pm")
        hh_mm, ampm = tm.rsplit(" ", 1)
        hh, mm = (hh_mm.split(":") + ["0"])[:2]
        hour = int(hh) % 12 + (12 if ampm == "pm" else 0)
        if date_part:
            mon, day = date_part.split()
            cand = base.replace(
                month=MONTHS[mon],
                day=int(day),
                hour=hour,
                minute=int(mm),
                second=0,
                microsecond=0,
            )
            if cand < base:
                cand = cand.replace(year=cand.year + 1)
        else:
            cand = base.replace(hour=hour, minute=int(mm), second=0, microsecond=0)
            if cand <= base:
                cand += timedelta(days=1)
        return cand.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    except (ValueError, KeyError, OSError):
        return None


def classify_limit_text(text):
    if text.startswith(SERVER_529):
        return "server_529"
    for kind, prefix in LIMIT_PREFIXES:
        if text.startswith(prefix):
            return kind
    return "other_api_error"


def scan_agent_jsonl(path):
    """Single streaming pass over one agent jsonl. Returns stats dict."""
    st = {
        "lines": 0,
        "tool_uses": 0,
        "so_input": None,
        "so_success": False,
        "prompt_head": "",
        "model": None,
        "final_text": None,
        "end_turn": False,
        "api_error": None,
        "interrupted": False,
        "last_ts": None,
        "last_kind": None,
    }
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                if not raw.strip():
                    continue
                st["lines"] += 1
                obj = jline(raw)
                if not obj:
                    continue
                st["last_ts"] = obj.get("timestamp") or st["last_ts"]
                typ = obj.get("type")
                msg = obj.get("message") or {}
                if typ == "user":
                    st["last_kind"] = "user"
                    if st["lines"] == 1 or (not st["prompt_head"] and msg):
                        head = text_of(msg)
                        if head:
                            st["prompt_head"] = head[:400]
                    for it in content_items(msg):
                        if it.get("type") == "tool_result":
                            body = it.get("content")
                            btxt = (
                                body
                                if isinstance(body, str)
                                else " ".join(
                                    x.get("text", "")
                                    for x in body or []
                                    if isinstance(x, dict)
                                )
                            )
                            if "Structured output provided successfully" in btxt:
                                st["so_success"] = True
                    # Structural only: the harness injects the interrupt marker as a
                    # bare user TEXT item. Substring checks over tool_result bodies
                    # false-positive when an agent merely READS a transcript that
                    # contains these markers.
                    for it in content_items(msg):
                        if it.get("type") == "text" and it.get(
                            "text", ""
                        ).strip().startswith("[Request interrupted by user"):
                            st["interrupted"] = True
                elif typ == "assistant":
                    if obj.get("isApiErrorMessage"):
                        st["api_error"] = {
                            "error": obj.get("error"),
                            "status": obj.get("apiErrorStatus"),
                            "text": text_of(msg)[:300],
                        }
                        st["last_kind"] = "api_error"
                        continue
                    mdl = msg.get("model")
                    if mdl and mdl != "<synthetic>":
                        st["model"] = st["model"] or mdl
                    kinds = {it.get("type") for it in content_items(msg)}
                    for it in content_items(msg):
                        if it.get("type") == "tool_use":
                            st["tool_uses"] += 1
                            if it.get("name") == "StructuredOutput":
                                st["so_input"] = it.get("input")
                    ftxt = text_of(msg)
                    if ftxt:
                        st["final_text"] = ftxt
                    # Turns split across records: precedence tool_use > text > thinking
                    if "tool_use" in kinds:
                        st["last_kind"] = "assistant_tool_use"
                    elif ftxt:
                        st["last_kind"] = "assistant_text"
                    else:
                        st["last_kind"] = "assistant_thinking"
                    st["end_turn"] = msg.get("stop_reason") == "end_turn"
    except OSError as e:
        st["read_error"] = str(e)
    return st


def slot_verdict(st, has_journal_result, result_obj):
    """Mechanical verdict for one workflow slot (or bare subagent w/o journal)."""
    evid = []
    if has_journal_result:
        rbytes = len(json.dumps(result_obj)) if result_obj is not None else 0
        if st["lines"] < 8 or st["tool_uses"] < 2 or rbytes < 120:
            evid.append(
                f"floors: lines={st['lines']} tool_uses={st['tool_uses']} result_bytes={rbytes}"
            )
            return "VACUOUS_SUSPECT", evid
        return "COMPLETE", evid
    if st.get("api_error"):
        kind = classify_limit_text(st["api_error"].get("text", ""))
        evid.append(f"api_error[{kind}]: {st['api_error'].get('text', '')[:140]}")
        return "NULL", evid
    if st["interrupted"]:
        evid.append("interrupted (TaskStop / user)")
        if st["so_success"] and st["so_input"] is not None:
            evid.append("StructuredOutput validated pre-interrupt -> salvaged")
            return "COMPLETE_SALVAGED", evid
        return "INTERRUPTED", evid
    if st["so_success"] and st["so_input"] is not None:
        evid.append("StructuredOutput validated but never journaled (killed on return)")
        return "COMPLETE_SALVAGED", evid
    if st["lines"] <= 5:
        evid.append(f"killed at spawn ({st['lines']} lines, no error record)")
        return "NULL", evid
    evid.append(
        f"substantive but unresulted (lines={st['lines']} tool_uses={st['tool_uses']})"
    )
    return "PARTIAL", evid


def scan_lead_transcript(path):
    """Stream the lead transcript once: limit events, delivered ids, workflow calls."""
    out = {
        "limit_events": [],
        "delivered_tool_ids": set(),
        "workflow_calls": [],
        "delivered_runids": set(),
        "last_model": None,
        "last_ts": None,
        "agent_tool_uses": {},
        "line_count": 0,
        "compact_summaries": 0,
    }
    last_model = None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                if not raw.strip():
                    continue
                out["line_count"] += 1
                obj = jline(raw)
                if not obj:
                    continue
                out["last_ts"] = obj.get("timestamp") or out["last_ts"]
                typ = obj.get("type")
                if typ == "summary":
                    out["compact_summaries"] += 1
                msg = obj.get("message") or {}
                if typ == "assistant":
                    if (
                        obj.get("isApiErrorMessage")
                        and obj.get("error") == "rate_limit"
                    ):
                        text = text_of(msg)
                        kind = classify_limit_text(text)
                        if kind not in ("server_529", "other_api_error"):
                            out["limit_events"].append(
                                {
                                    "kind": kind,
                                    "text": text[:200],
                                    "timestamp": obj.get("timestamp"),
                                    "resets_at_utc": parse_reset(
                                        text, obj.get("timestamp") or ""
                                    ),
                                    "interrupted_model": last_model,
                                }
                            )
                        continue
                    mdl = msg.get("model")
                    if mdl and mdl != "<synthetic>":
                        last_model = mdl
                        out["last_model"] = mdl
                    for it in content_items(msg):
                        if it.get("type") != "tool_use":
                            continue
                        if it.get("name") == "Workflow":
                            inp = it.get("input") or {}
                            out["workflow_calls"].append(
                                {
                                    "tool_use_id": it.get("id"),
                                    "name": inp.get("name"),
                                    "scriptPath": inp.get("scriptPath"),
                                    "resumeFromRunId": inp.get("resumeFromRunId"),
                                    "has_args": "args" in inp,
                                    "args": inp.get("args"),
                                }
                            )
                        elif it.get("name") == "Agent":
                            inp = it.get("input") or {}
                            out["agent_tool_uses"][it.get("id")] = {
                                "description": inp.get("description"),
                                "prompt_head": (inp.get("prompt") or "")[:200],
                            }
                elif typ == "user":
                    for it in content_items(msg):
                        if it.get("type") == "tool_result":
                            tid = it.get("tool_use_id")
                            if tid:
                                out["delivered_tool_ids"].add(tid)
                            body = it.get("content")
                            btxt = (
                                body
                                if isinstance(body, str)
                                else " ".join(
                                    x.get("text", "")
                                    for x in body or []
                                    if isinstance(x, dict)
                                )
                            )
                            for rid in RUNID_RE.findall(btxt or ""):
                                out["delivered_runids"].add(rid)
    except OSError as e:
        out["read_error"] = str(e)
    return out


def audit_workflow_run(run_summary_path, session_dir, lead):
    run = {"summary_path": run_summary_path, "slots": [], "problems": []}
    try:
        with open(run_summary_path, encoding="utf-8") as f:
            summary = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        run["problems"].append(f"unreadable summary: {e}")
        summary = {}
    rid = summary.get("runId") or os.path.basename(run_summary_path).rsplit(".", 1)[0]
    run.update(
        {
            "runId": rid,
            "workflowName": summary.get("workflowName"),
            "status": summary.get("status"),
            "agentCount": summary.get("agentCount"),
            "scriptPath": summary.get("scriptPath"),
            "has_final_result": summary.get("result") is not None,
            "startTime": summary.get("startTime"),
            "durationMs": summary.get("durationMs"),
        }
    )
    run["delivered_to_lead"] = rid in lead["delivered_runids"]
    call = next(
        (
            c
            for c in lead["workflow_calls"]
            if c.get("scriptPath") == run["scriptPath"]
            or c.get("resumeFromRunId") == rid
        ),
        None,
    )
    run["lead_call"] = call

    run_dir = os.path.join(session_dir, "subagents", "workflows", rid)
    journal_path = os.path.join(run_dir, "journal.jsonl")
    started, results, results_by_key = {}, {}, set()
    if os.path.isfile(journal_path):
        with open(journal_path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                obj = jline(raw)
                if not obj:
                    continue
                if obj.get("type") == "started":
                    started.setdefault(obj.get("agentId"), obj.get("key"))
                elif obj.get("type") == "result":
                    results[obj.get("agentId")] = obj.get("result")
                    results_by_key.add(obj.get("key"))
    else:
        run["problems"].append("journal.jsonl missing")

    jsonls = {
        os.path.basename(p)[6:-6]: p
        for p in glob.glob(os.path.join(run_dir, "agent-*.jsonl"))
    }
    for aid, key in started.items():
        path = jsonls.pop(aid, None)
        if path is None:
            run["slots"].append(
                {
                    "agentId": aid,
                    "key": key,
                    "verdict": "UNVERIFIABLE",
                    "evidence": ["journal started but agent jsonl missing"],
                }
            )
            continue
        st = scan_agent_jsonl(path)
        verdict, evid = slot_verdict(st, aid in results, results.get(aid))
        # Supersede: a dangling slot whose journal KEY was re-issued (resume) and
        # completed under another agentId is historically resolved — not a gap.
        if aid not in results and key in results_by_key:
            verdict = "SUPERSEDED"
            evid = [
                "call re-issued and completed under another agentId (same journal key)"
            ]
        run["slots"].append(
            {
                "agentId": aid,
                "key": key,
                "verdict": verdict,
                "evidence": evid,
                "jsonl": path,
                "prompt_head": st["prompt_head"],
                "model": st["model"],
                "lines": st["lines"],
                "tool_uses": st["tool_uses"],
                "salvaged_so": st["so_input"]
                if verdict == "COMPLETE_SALVAGED"
                else None,
                "journal_result_present": aid in results,
            }
        )
    for aid, path in jsonls.items():
        st = scan_agent_jsonl(path)
        verdict, evid = slot_verdict(st, False, None)
        evid.append("agent jsonl present but never journaled as started")
        run["slots"].append(
            {
                "agentId": aid,
                "verdict": verdict if verdict != "PARTIAL" else "UNVERIFIABLE",
                "evidence": evid,
                "jsonl": path,
                "prompt_head": st["prompt_head"],
                "model": st["model"],
            }
        )

    counts = {}
    for s in run["slots"]:
        counts[s["verdict"]] = counts.get(s["verdict"], 0) + 1
    run["slot_counts"] = counts
    gaps = sum(v for k, v in counts.items() if k in GAP_VERDICTS)
    if run["status"] == "completed" and gaps:
        run["run_verdict"] = "TAINTED_COMPLETE"
    elif run["status"] == "completed" and not run["delivered_to_lead"]:
        run["run_verdict"] = "COMPLETE_UNDELIVERED"
    elif run["status"] == "completed":
        run["run_verdict"] = "COMPLETE"
    else:
        run["run_verdict"] = "INCOMPLETE"
    return run


def audit_bare_subagents(session_dir, lead):
    out = []
    sub_dir = os.path.join(session_dir, "subagents")
    for path in sorted(glob.glob(os.path.join(sub_dir, "agent-*.jsonl"))):
        aid = os.path.basename(path)[6:-6]
        meta = {}
        mp = path[:-6] + ".meta.json"
        if os.path.isfile(mp):
            try:
                with open(mp, encoding="utf-8") as f:
                    meta = json.load(f)
            except (OSError, json.JSONDecodeError):
                pass
        st = scan_agent_jsonl(path)
        if st.get("api_error"):
            verdict, evid = slot_verdict(st, False, None)
        elif st["interrupted"]:
            verdict, evid = slot_verdict(st, False, None)
        elif st["final_text"] and st["last_kind"] == "assistant_text":
            tid = meta.get("toolUseId")
            delivered = tid in lead["delivered_tool_ids"] if tid else None
            if delivered is False:
                verdict, evid = (
                    "COMPLETE_UNDELIVERED",
                    ["final turn on disk; tool_result never reached lead"],
                )
            else:
                verdict, evid = "COMPLETE", []
            if st["lines"] < 6 or st["tool_uses"] < 1:
                verdict = "VACUOUS_SUSPECT"
                evid.append(f"floors: lines={st['lines']} tool_uses={st['tool_uses']}")
        elif st["lines"] <= 5:
            verdict, evid = "NULL", [f"killed at spawn ({st['lines']} lines)"]
        else:
            verdict, evid = (
                "PARTIAL",
                [f"no final turn (lines={st['lines']} tool_uses={st['tool_uses']})"],
            )
        out.append(
            {
                "agentId": aid,
                "verdict": verdict,
                "evidence": evid,
                "jsonl": path,
                "agentType": meta.get("agentType"),
                "description": meta.get("description"),
                "toolUseId": meta.get("toolUseId"),
                "prompt_head": st["prompt_head"],
                "model": st["model"],
                "lines": st["lines"],
                "tool_uses": st["tool_uses"],
                "final_text_head": (st["final_text"] or "")[:200] or None,
            }
        )
    return out


def audit_tasks(config_dir, task_list_id):
    if not task_list_id:
        return None
    tdir = os.path.join(config_dir, "tasks", task_list_id)
    if not os.path.isdir(tdir):
        return None
    tasks = []
    for p in sorted(glob.glob(os.path.join(tdir, "*.json"))):
        try:
            with open(p, encoding="utf-8") as f:
                t = json.load(f)
            tasks.append(
                {
                    "id": t.get("id"),
                    "status": t.get("status"),
                    "subject": (t.get("subject") or "")[:120],
                }
            )
        except (OSError, json.JSONDecodeError):
            continue
    return {
        "dir": tdir,
        "tasks": tasks,
        "open": [t for t in tasks if t["status"] in ("pending", "in_progress")],
    }


def scan_teammate_jsonl(path):
    """Single pass over a TEAMMATE session transcript (a full CC session, not a
    subagent jsonl): limit events, interrupt marker, final-turn state, activity."""
    st = {
        "lines": 0,
        "tool_uses": 0,
        "prompt_head": "",
        "model": None,
        "final_text": None,
        "end_turn": False,
        "interrupted": False,
        "limit_events": [],
        "api_errors": 0,
        "last_api_error_text": None,
        "sendmessage_calls": 0,
        "last_sendmessage_summary": None,
        "first_ts": None,
        "last_ts": None,
        "last_kind": None,
        "cwd": None,
    }
    last_model = None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                if not raw.strip():
                    continue
                st["lines"] += 1
                obj = jline(raw)
                if not obj:
                    continue
                ts = obj.get("timestamp")
                if ts:
                    st["last_ts"] = ts
                    st["first_ts"] = st["first_ts"] or ts
                if not st["cwd"] and obj.get("cwd"):
                    st["cwd"] = obj.get("cwd")
                typ = obj.get("type")
                msg = obj.get("message") or {}
                if typ == "user":
                    st["last_kind"] = "user"
                    if not st["prompt_head"]:
                        head = text_of(msg)
                        if head:
                            st["prompt_head"] = head[:400]
                    for it in content_items(msg):
                        if it.get("type") == "text" and it.get(
                            "text", ""
                        ).strip().startswith("[Request interrupted by user"):
                            st["interrupted"] = True
                elif typ == "assistant":
                    if obj.get("isApiErrorMessage"):
                        text = text_of(msg)
                        st["api_errors"] += 1
                        st["last_api_error_text"] = text[:200]
                        st["last_kind"] = "api_error"
                        if obj.get("error") == "rate_limit":
                            kind = classify_limit_text(text)
                            if kind not in ("server_529", "other_api_error"):
                                st["limit_events"].append(
                                    {
                                        "kind": kind,
                                        "timestamp": ts,
                                        "resets_at_utc": parse_reset(text, ts or ""),
                                        "text": text[:160],
                                    }
                                )
                        continue
                    mdl = msg.get("model")
                    if mdl and mdl != "<synthetic>":
                        last_model = mdl
                    kinds = {it.get("type") for it in content_items(msg)}
                    for it in content_items(msg):
                        if it.get("type") == "tool_use":
                            st["tool_uses"] += 1
                            if it.get("name") == "SendMessage":
                                st["sendmessage_calls"] += 1
                                inp = it.get("input") or {}
                                st["last_sendmessage_summary"] = (
                                    inp.get("summary") or str(inp.get("message"))[:120]
                                )
                    ftxt = text_of(msg)
                    if ftxt:
                        st["final_text"] = ftxt
                        st["end_turn"] = msg.get("stop_reason") == "end_turn"
                    if "tool_use" in kinds:
                        st["last_kind"] = "assistant_tool_use"
                        st["end_turn"] = False
                    elif ftxt:
                        st["last_kind"] = "assistant_text"
    except OSError as e:
        st["read_error"] = str(e)
    st["model"] = last_model
    return st


def resolve_member_transcripts(config_dir, team_name, member, lead_sid):
    """Map a team member -> its session transcript(s). Teammate records carry
    teamName + agentName on every message line (verified 2.1.207); the member
    entry in config.json does NOT carry a sessionId, so this scan IS the link.
    Returns paths sorted oldest->newest (last = current; earlier = respawns)."""
    cwd = member.get("cwd") or ""
    slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)
    proj = os.path.join(config_dir, "projects", slug)
    joined_s = (member.get("joinedAt") or 0) / 1000.0
    hits = []
    for p in glob.glob(os.path.join(proj, "*.jsonl")):
        if os.path.basename(p).startswith(lead_sid or "\x00") or p.endswith(
            ".handed-off"
        ):
            continue
        try:
            if os.path.getmtime(p) < joined_s - 120:
                continue  # last write predates this member's join — cannot be it
        except OSError:
            continue
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                for i, raw in enumerate(f):
                    if i > 14:
                        break
                    obj = jline(raw)
                    if not obj:
                        continue
                    if obj.get("teamName") == team_name and obj.get("agentName"):
                        if obj.get("agentName") == member.get("name"):
                            hits.append(p)
                        break
        except OSError:
            continue
    hits.sort(key=os.path.getmtime)
    return hits


def member_deliverables(member):
    """Stat every absolute file path declared in the member's brief. A path
    written during the member's tenure (mtime >= joinedAt - 60s, size > 0) is
    un-fakeable deliverable evidence — reads don't move mtime."""
    joined_s = (member.get("joinedAt") or 0) / 1000.0
    out = []
    for path in list(dict.fromkeys(PROMPT_PATH_RE.findall(member.get("prompt") or "")))[
        :16
    ]:
        d = {"path": path, "exists": os.path.isfile(path)}
        if d["exists"]:
            try:
                stt = os.stat(path)
                d["size"] = stt.st_size
                d["mtime_utc"] = (
                    datetime.fromtimestamp(stt.st_mtime, timezone.utc)
                    .isoformat()
                    .replace("+00:00", "Z")
                )
                d["written_during_tenure"] = (
                    stt.st_mtime >= joined_s - 60 and stt.st_size > 0
                )
            except OSError:
                d["exists"] = False
        out.append(d)
    return out


def member_git_evidence(member, lead_cwd):
    """Worktree evidence for code teammates. Only applicable when the member's
    cwd is DISTINCT from the lead's — in a shared checkout the lead's own
    commits would false-positive. wip refs are member-keyed, so always safe."""
    cwd = member.get("cwd") or ""
    distinct = bool(cwd) and os.path.realpath(cwd) != os.path.realpath(lead_cwd or "")
    ev = {"applicable": distinct, "commits": [], "dirty": None, "wip_refs": []}
    if not os.path.isdir(cwd):
        return ev

    def _git(*a):
        try:
            r = subprocess.run(
                ["git", "-C", cwd, *a],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            return r.stdout
        except (OSError, subprocess.SubprocessError):
            return ""

    name = member.get("name") or ""
    ev["wip_refs"] = [
        ln
        for ln in _git(
            "for-each-ref",
            "--format=%(refname) %(objectname:short)",
            f"refs/wip/{name}",
        ).splitlines()
        if ln.strip()
    ]
    if not distinct:
        return ev
    joined_iso = datetime.fromtimestamp(
        (member.get("joinedAt") or 0) / 1000.0, timezone.utc
    ).isoformat()
    ev["commits"] = [
        ln
        for ln in _git(
            "log", "--oneline", "-n", "8", f"--since={joined_iso}"
        ).splitlines()
        if ln.strip()
    ]
    ev["dirty"] = len(
        [ln for ln in _git("status", "--porcelain").splitlines() if ln.strip()]
    )
    return ev


def member_verdict(st, deliverables, git_ev, now_utc):
    """Mechanical verdict for one teammate. Deliverable-on-disk evidence
    outranks transcript tail state, which outranks lead-side perception."""
    declared = bool(deliverables)
    written = [d["path"] for d in deliverables if d.get("written_during_tenure")]
    delivered = (
        bool(written) or bool(git_ev.get("commits")) or bool(git_ev.get("wip_refs"))
    )
    clean = bool(
        st["end_turn"] and st["last_kind"] == "assistant_text" and st["final_text"]
    )
    limited = bool(st["limit_events"])
    evid = []
    if written:
        evid.append("deliverables written during tenure: " + ", ".join(written[:4]))
    if git_ev.get("commits"):
        evid.append(f"{len(git_ev['commits'])} worktree commit(s) since join")
    if git_ev.get("wip_refs"):
        evid.append("wip checkpoint ref present")
    if limited:
        e = st["limit_events"][-1]
        evid.append(
            f"limit[{e['kind']}] at {e['timestamp']} resets "
            f"{e.get('resets_at_utc') or 'NONE (spend cap — /usage-credits or account rotation)'}"
        )
    if st["lines"] <= 5:
        evid.append(f"killed at spawn ({st['lines']} records)")
        return "NULL", evid
    if delivered and clean and not limited:
        if st["lines"] < 8 or st["tool_uses"] < 2:
            evid.append(f"floors: lines={st['lines']} tool_uses={st['tool_uses']}")
            return "VACUOUS_SUSPECT", evid
        return "COMPLETE", evid
    if delivered:
        evid.append(
            "finished on disk; delivery/handshake to lead unproven -> READ from disk"
        )
        return "COMPLETE_UNDELIVERED", evid
    if st["interrupted"]:
        evid.append("interrupted (TaskStop / user)")
        return "INTERRUPTED", evid
    if clean:
        if declared:
            evid.append(
                "clean final turn but NONE of the brief-declared output paths were written"
            )
            return "VACUOUS_SUSPECT", evid
        if st["lines"] < 8 or st["tool_uses"] < 2:
            evid.append(f"floors: lines={st['lines']} tool_uses={st['tool_uses']}")
            return "VACUOUS_SUSPECT", evid
        return "COMPLETE", evid
    if st["last_kind"] == "api_error":
        evid.append(f"died on api error: {(st['last_api_error_text'] or '')[:100]}")
        return ("NULL" if st["lines"] <= 12 else "PARTIAL"), evid
    age = None
    if st["last_ts"]:
        try:
            age = (
                now_utc - datetime.fromisoformat(st["last_ts"].replace("Z", "+00:00"))
            ).total_seconds()
        except ValueError:
            age = None
    if age is not None and age < TEAM_ACTIVE_WINDOW_S:
        evid.append(f"active {int(age)}s ago")
        return "RUNNING", evid
    evid.append(
        f"substantive but unfinished (lines={st['lines']} tool_uses={st['tool_uses']}, "
        f"last activity {int(age) if age is not None else '?'}s ago)"
    )
    return "PARTIAL", evid


def audit_led_teams(config_dir, sid, cwd, force_team=None):
    """Per-member audit of every team this session LEADS. Assignee sessions are
    full CC sessions; recovery is the lead's job (the reset poller deliberately
    skips teammate transcripts). Returns one dict per led team."""
    teams = []
    tdir = os.path.join(config_dir, "teams")
    if not os.path.isdir(tdir):
        return teams
    now_utc = datetime.now(timezone.utc)
    for name in sorted(os.listdir(tdir)):
        cfg_path = os.path.join(tdir, name, "config.json")
        if not os.path.isfile(cfg_path):
            continue
        try:
            with open(cfg_path, encoding="utf-8") as f:
                cfg = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        if force_team:
            if cfg.get("name") != force_team and name != force_team:
                continue
        elif not sid or cfg.get("leadSessionId") != sid:
            continue
        team = {
            "name": cfg.get("name") or name,
            "config_path": cfg_path,
            "leadSessionId": cfg.get("leadSessionId"),
            "members": [],
        }
        for m in cfg.get("members", []):
            if m.get("agentType") == "team-lead":
                continue
            paths = resolve_member_transcripts(
                config_dir, team["name"], m, sid or cfg.get("leadSessionId")
            )
            dl = member_deliverables(m)
            git_ev = member_git_evidence(m, cwd)
            entry = {
                "name": m.get("name"),
                "agentType": m.get("agentType"),
                "model": m.get("model"),
                "cwd": m.get("cwd"),
                "tmuxPaneId": m.get("tmuxPaneId"),
                "isActive": m.get("isActive"),
                "joinedAt": m.get("joinedAt"),
                "prompt_head": (m.get("prompt") or "")[:200],
                "_prompt_full": m.get("prompt"),
                "transcript": paths[-1] if paths else None,
                "prior_transcripts": paths[:-1],
                "deliverables": dl,
                "git": git_ev,
            }
            if not paths:
                entry["verdict"] = "UNVERIFIABLE"
                entry["evidence"] = [
                    "no session transcript matched teamName+agentName under this account"
                ]
            else:
                st = scan_teammate_jsonl(paths[-1])
                v, evid = member_verdict(st, dl, git_ev, now_utc)
                if entry["isActive"] is False and v == "RUNNING":
                    v, evid = (
                        "PARTIAL",
                        evid + ["config isActive=false — harness marked it dead"],
                    )
                entry.update(
                    {
                        "verdict": v,
                        "evidence": evid,
                        "limit_events": st["limit_events"],
                        "last_ts": st["last_ts"],
                        "lines": st["lines"],
                        "tool_uses": st["tool_uses"],
                        "sendmessage_calls": st["sendmessage_calls"],
                        "final_text_head": (st["final_text"] or "")[:200] or None,
                    }
                )
            team["members"].append(entry)
        counts = {}
        for e in team["members"]:
            counts[e["verdict"]] = counts.get(e["verdict"], 0) + 1
        team["member_counts"] = counts
        teams.append(team)
    return teams


def write_team_salvage(doc, out_dir):
    """One respawn-ready JSON per member: the VERBATIM original brief + exact
    Agent() args. Re-fire = Agent({name, subagent_type, model, prompt}) — no
    paraphrasing from memory, ever."""
    for team in (doc.get("teams") or {}).get("led", []):
        tdir = os.path.join(out_dir, "teams", team["name"])
        os.makedirs(tdir, exist_ok=True)
        for m in team["members"]:
            with open(
                os.path.join(tdir, f"{m['name']}.json"), "w", encoding="utf-8"
            ) as f:
                json.dump(
                    {
                        "member": m["name"],
                        "team": team["name"],
                        "verdict": m.get("verdict"),
                        "transcript": m.get("transcript"),
                        "evidence": m.get("evidence"),
                        "deliverables": m.get("deliverables"),
                        "partial_output_seeds": [
                            d["path"]
                            for d in (m.get("deliverables") or [])
                            if d.get("exists")
                        ],
                        "respawn_call": {
                            "name": m["name"],
                            "subagent_type": m.get("agentType"),
                            "model": m.get("model"),
                            "prompt": m.get("_prompt_full"),
                        },
                    },
                    f,
                    indent=1,
                )


def audit_teams(config_dir, cwd):
    info = {"teams": [], "wip_refs": []}
    tdir = os.path.join(config_dir, "teams")
    if os.path.isdir(tdir):
        info["teams"] = sorted(os.listdir(tdir))
    try:
        r = subprocess.run(
            [
                "git",
                "-C",
                cwd,
                "for-each-ref",
                "--format=%(refname) %(objectname:short)",
                "refs/wip",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        info["wip_refs"] = [ln for ln in r.stdout.splitlines() if ln.strip()]
    except (OSError, subprocess.SubprocessError):
        pass
    return info


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_session(config_dir, sid, cwd):
    if sid:
        hits = sorted(
            glob.glob(os.path.join(config_dir, "projects", "*", sid + ".jsonl"))
        )
        hits = [h for h in hits if not h.endswith(".handed-off")]
        if len(hits) == 1:
            return hits[0], sid
        if len(hits) > 1:
            best = max(
                hits,
                key=lambda p: (tail_records(p, 1) or [{}])[-1].get("timestamp") or "",
            )
            return best, sid
        return None, sid
    slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)
    proj = os.path.join(config_dir, "projects", slug)
    last = os.path.join(proj, ".last-session-id")
    if os.path.isfile(last):
        with open(last, encoding="utf-8") as f:
            sid = f.read().strip()
        p = os.path.join(proj, sid + ".jsonl")
        if os.path.isfile(p):
            return p, sid
    cands = sorted(
        glob.glob(os.path.join(proj, "*.jsonl")), key=os.path.getmtime, reverse=True
    )
    if cands:
        p = cands[0]
        return p, os.path.basename(p)[:-6]
    return None, None


def write_salvage(doc, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for run in doc["workflows"]:
        rdir = os.path.join(out_dir, run["runId"])
        os.makedirs(rdir, exist_ok=True)
        slots = []
        jr = {}
        jp = os.path.join(
            os.path.dirname(os.path.dirname(run.get("summary_path", ""))),
            "subagents",
            "workflows",
            run["runId"],
            "journal.jsonl",
        )
        jp = os.path.join(
            doc["session_dir"], "subagents", "workflows", run["runId"], "journal.jsonl"
        )
        if os.path.isfile(jp):
            with open(jp, encoding="utf-8", errors="replace") as f:
                for raw in f:
                    obj = jline(raw)
                    if obj and obj.get("type") == "result":
                        jr[obj.get("agentId")] = obj.get("result")
        for s in run["slots"]:
            slots.append(
                {
                    "agentId": s.get("agentId"),
                    "verdict": s["verdict"],
                    "prompt_head": s.get("prompt_head"),
                    "model": s.get("model"),
                    "result": jr.get(s.get("agentId"))
                    if s.get("journal_result_present")
                    else None,
                    "salvaged_so": s.get("salvaged_so"),
                }
            )
        with open(os.path.join(rdir, "slots.json"), "w", encoding="utf-8") as f:
            json.dump(
                {
                    "runId": run["runId"],
                    "workflowName": run["workflowName"],
                    "scriptPath": run["scriptPath"],
                    "run_verdict": run["run_verdict"],
                    "slots": slots,
                },
                f,
                indent=1,
            )
    sadir = os.path.join(out_dir, "subagents")
    os.makedirs(sadir, exist_ok=True)
    for s in doc["subagents"]:
        prompt = None
        try:
            with open(s["jsonl"], encoding="utf-8", errors="replace") as f:
                first = jline(f.readline() or "")
            if first:
                prompt = text_of(first.get("message"))
        except OSError:
            pass
        with open(
            os.path.join(sadir, s["agentId"] + ".json"), "w", encoding="utf-8"
        ) as f:
            json.dump(
                {
                    **{
                        k: s.get(k)
                        for k in (
                            "agentId",
                            "verdict",
                            "description",
                            "model",
                            "final_text_head",
                        )
                    },
                    "prompt": prompt,
                },
                f,
                indent=1,
            )


def render_md(doc):
    L = []
    gaps = doc["counts"]["gaps"]
    L.append(f"# lr-audit — session `{doc['session_id']}`")
    L.append(
        f"- config: `{doc['config_dir']}` · transcript: `{doc['transcript']}` "
        f"({doc['lead']['line_count']} records)"
    )
    L.append(
        f"- generated: {doc['generated_at']} · verdict floor: **{'GAPS: ' + str(gaps) if gaps else 'NO GAPS'}**"
    )
    if doc["limit_events"]:
        L.append("\n## Limit events (genuine usage limits only)")
        L.append("| kind | at (UTC) | resets (UTC) | interrupted model | text |")
        L.append("|---|---|---|---|---|")
        for e in doc["limit_events"]:
            L.append(
                f"| {e['kind']} | {e['timestamp']} | {e.get('resets_at_utc') or '?'} "
                f"| {e.get('interrupted_model') or '?'} | {e['text'][:80]} |"
            )
    else:
        L.append("\n_No genuine limit events found in the lead transcript._")
    if doc["workflows"]:
        L.append("\n## Dynamic Workflow runs")
        L.append(
            "| runId | name | run verdict | slots (verdict:n) | delivered | scriptPath |"
        )
        L.append("|---|---|---|---|---|---|")
        for r in doc["workflows"]:
            sc = " ".join(f"{k}:{v}" for k, v in sorted(r["slot_counts"].items()))
            L.append(
                f"| {r['runId']} | {r['workflowName']} | **{r['run_verdict']}** | {sc} "
                f"| {'yes' if r['delivered_to_lead'] else 'NO'} | `{r.get('scriptPath') or '?'}` |"
            )
        for r in doc["workflows"]:
            bad = [s for s in r["slots"] if s["verdict"] != "COMPLETE"]
            if not bad:
                continue
            L.append(f"\n### {r['runId']} — non-COMPLETE slots")
            for s in bad:
                L.append(
                    f"- `{s.get('agentId')}` **{s['verdict']}** — {'; '.join(s['evidence'])}"
                    f"\n  - brief: {(s.get('prompt_head') or '')[:160]}"
                )
    if doc["subagents"]:
        L.append("\n## Bare subagents")
        L.append("| agentId | verdict | type | description/brief | evidence |")
        L.append("|---|---|---|---|---|")
        for s in doc["subagents"]:
            d = s.get("description") or (s.get("prompt_head") or "")[:60]
            L.append(
                f"| {s['agentId']} | **{s['verdict']}** | {s.get('agentType') or '?'} "
                f"| {d[:60]} | {'; '.join(s['evidence'])[:80]} |"
            )
    t = doc.get("tasks")
    if t and t["tasks"]:
        L.append(f"\n## Task list — {len(t['open'])} open of {len(t['tasks'])}")
        for x in t["open"]:
            L.append(f"- [{x['status']}] {x['id']}: {x['subject']}")
    tm = doc.get("teams") or {}
    for team in tm.get("led", []):
        L.append(
            f"\n## Team `{team['name']}` — assignee sessions (this session is LEAD; "
            "lead-side 'failed' notifications are NOT ground truth)"
        )
        L.append(
            "| member | verdict | limit | last activity (UTC) | deliverables | action |"
        )
        L.append("|---|---|---|---|---|---|")
        for m in team["members"]:
            lim = m.get("limit_events") or []
            if lim:
                last = lim[-1]
                limtxt = f"{last['kind']}→{last.get('resets_at_utc') or 'no-reset'}"
            else:
                limtxt = "-"
            dl = m.get("deliverables") or []
            w = sum(1 for d in dl if d.get("written_during_tenure"))
            act = {
                "COMPLETE": "consume",
                "COMPLETE_UNDELIVERED": "READ from disk",
                "RUNNING": "wait",
                "PARTIAL": "respawn (salvage brief)",
                "NULL": "respawn (salvage brief)",
                "INTERRUPTED": "respawn unless salvaged",
                "VACUOUS_SUSPECT": "review vs brief",
                "UNVERIFIABLE": "surface",
            }.get(m["verdict"], "?")
            L.append(
                f"| {m['name']} | **{m['verdict']}** | {limtxt} | {m.get('last_ts') or '?'} "
                f"| {w}/{len(dl)} written | {act} |"
            )
        L.append(
            f"- respawn calls (VERBATIM briefs): `salvage/teams/{team['name']}/<member>.json` "
            "→ `.respawn_call` — spawn via Agent(); course-change respawns: `bin/cc-respawn`"
        )
    if tm.get("other_team_dirs") or tm.get("wip_refs"):
        L.append("\n## Other team dirs / checkpoints")
        if tm.get("other_team_dirs"):
            extra = " …" if len(tm["other_team_dirs"]) > 12 else ""
            L.append(
                f"- team dirs not led by this session: "
                f"{', '.join(tm['other_team_dirs'][:12])}{extra}"
            )
        for ref in tm.get("wip_refs", []):
            L.append(f"- `{ref}`")
    L.append(
        "\n## Gap ledger (every non-COMPLETE unit — each REQUIRES an action; bridging is banned)"
    )
    if not doc["gap_units"]:
        L.append("_none — all delegated work is COMPLETE and delivered._")
    for g in doc["gap_units"]:
        L.append(f"- **{g['verdict']}** `{g['unit']}` → {g['action']}")
    return "\n".join(L) + "\n"


ACTION = {
    "NULL": "RE-RUN (workflow: resume run; bare: re-spawn with original prompt from salvage)",
    "PARTIAL": "RE-RUN (salvage is seed-context only, never a substitute result)",
    "INTERRUPTED": "RE-RUN unless COMPLETE_SALVAGED payload exists",
    "VACUOUS_SUSPECT": "MODEL REVIEW output vs brief; re-run if vacuous",
    "UNVERIFIABLE": "SURFACE to user as named gap — never infer",
    "COMPLETE_UNDELIVERED": "READ result from disk (no re-run, no re-spend)",
    "COMPLETE_SALVAGED": "USE salvaged StructuredOutput payload (validated); note provenance",
    "TAINTED_COMPLETE": "run 'completed' over gap slots — treat final result as CONTAMINATED until slots re-run",
    "INCOMPLETE": "resume via Workflow({scriptPath, resumeFromRunId}); re-audit after",
    "SUPERSEDED": "NONE — slot re-issued and completed under another agentId",
    "RUNNING": "NONE — teammate still active (age < 5 min); wait, never respawn over a live member",
}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--config-dir",
        default=os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"),
    )
    ap.add_argument("--session", default=os.environ.get("CLAUDE_CODE_SESSION_ID"))
    ap.add_argument("--cwd", default=os.getcwd())
    ap.add_argument("--task-list", default=os.environ.get("CLAUDE_CODE_TASK_LIST_ID"))
    ap.add_argument(
        "--team",
        help="audit this team's members even if leadSessionId != --session",
    )
    ap.add_argument("--json", dest="json_out")
    ap.add_argument("--md", dest="md_out")
    ap.add_argument("--salvage-dir")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    config_dir = os.path.abspath(os.path.expanduser(args.config_dir))
    transcript, sid = find_session(config_dir, args.session, args.cwd)
    if not transcript or not os.path.isfile(transcript):
        print(
            f"lr-audit: no transcript found (config={config_dir} sid={args.session} "
            f"cwd={args.cwd})",
            file=sys.stderr,
        )
        return 2
    session_dir = transcript[:-6]

    lead = scan_lead_transcript(transcript)
    workflows = []
    for p in sorted(glob.glob(os.path.join(session_dir, "workflows", "wf_*.json"))):
        workflows.append(audit_workflow_run(p, session_dir, lead))
    known = {
        os.path.join(session_dir, "subagents", "workflows", r["runId"])
        for r in workflows
    }
    for d in sorted(
        glob.glob(os.path.join(session_dir, "subagents", "workflows", "wf_*"))
    ):
        if d not in known and os.path.isdir(d):
            fake = os.path.join(session_dir, "workflows", os.path.basename(d) + ".json")
            r = audit_workflow_run(fake, session_dir, lead)
            r["problems"].append(
                "run dir exists but run-summary json missing (killed mid-run)"
            )
            r["run_verdict"] = "INCOMPLETE"
            workflows.append(r)

    subagents = [s for s in audit_bare_subagents(session_dir, lead)]

    led_teams = audit_led_teams(config_dir, sid, args.cwd, force_team=args.team)
    led_names = {t["name"] for t in led_teams}
    legacy_teams = audit_teams(config_dir, args.cwd)
    teams_doc = {
        "led": led_teams,
        "other_team_dirs": [t for t in legacy_teams["teams"] if t not in led_names],
        "wip_refs": legacy_teams["wip_refs"],
    }

    gap_units = []
    for r in workflows:
        if r["run_verdict"] in ("TAINTED_COMPLETE", "INCOMPLETE"):
            gap_units.append(
                {
                    "unit": f"workflow {r['runId']} ({r['workflowName']})",
                    "verdict": r["run_verdict"],
                    "action": ACTION[r["run_verdict"]],
                }
            )
        elif r["run_verdict"] == "COMPLETE_UNDELIVERED":
            gap_units.append(
                {
                    "unit": f"workflow {r['runId']} result",
                    "verdict": "COMPLETE_UNDELIVERED",
                    "action": ACTION["COMPLETE_UNDELIVERED"]
                    + f" — `{r['summary_path']}` .result",
                }
            )
        for s in r["slots"]:
            if s["verdict"] in GAP_VERDICTS or s["verdict"] == "COMPLETE_SALVAGED":
                gap_units.append(
                    {
                        "unit": f"{r['runId']}/{s.get('agentId')}",
                        "verdict": s["verdict"],
                        "action": ACTION.get(s["verdict"], "?"),
                    }
                )
    for s in subagents:
        if s["verdict"] != "COMPLETE":
            gap_units.append(
                {
                    "unit": f"subagent {s['agentId']} ({(s.get('description') or s.get('prompt_head') or '')[:50]})",
                    "verdict": s["verdict"],
                    "action": ACTION.get(s["verdict"], "?"),
                }
            )

    for team in led_teams:
        for m in team["members"]:
            v = m["verdict"]
            if v not in GAP_VERDICTS and v != "COMPLETE_UNDELIVERED":
                continue
            unit = f"team {team['name']}/{m['name']}"
            if v == "COMPLETE_UNDELIVERED":
                written = [
                    d["path"]
                    for d in (m.get("deliverables") or [])
                    if d.get("written_during_tenure")
                ] or [
                    d["path"] for d in (m.get("deliverables") or []) if d.get("exists")
                ]
                act = "READ deliverable(s) from disk (zero re-spend): " + (
                    ", ".join(written[:3]) or "see salvage"
                )
            elif v in ("PARTIAL", "NULL", "INTERRUPTED"):
                act = (
                    "RESPAWN via Agent() with the salvaged VERBATIM brief — "
                    f"salvage/teams/{team['name']}/{m['name']}.json .respawn_call"
                )
            else:
                act = ACTION.get(v, "?")
            gap_units.append({"unit": unit, "verdict": v, "action": act})

    hard_gaps = [
        g
        for g in gap_units
        if g["verdict"] in GAP_VERDICTS
        or g["verdict"] in ("TAINTED_COMPLETE", "INCOMPLETE")
    ]

    doc = {
        "session_id": sid,
        "config_dir": config_dir,
        "transcript": transcript,
        "session_dir": session_dir,
        "cwd": args.cwd,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "transcript_sha256": sha256_file(transcript),
        "limit_events": lead["limit_events"],
        "lead": {
            "line_count": lead["line_count"],
            "last_model": lead["last_model"],
            "last_ts": lead["last_ts"],
            "compact_summaries": lead["compact_summaries"],
            "workflow_calls": lead["workflow_calls"],
        },
        "workflows": workflows,
        "subagents": subagents,
        "tasks": audit_tasks(config_dir, args.task_list),
        "teams": teams_doc,
        "gap_units": gap_units,
        "counts": {
            "workflows": len(workflows),
            "subagents": len(subagents),
            "gaps": len(hard_gaps),
            "recoverable_without_respend": sum(
                1
                for g in gap_units
                if g["verdict"] in ("COMPLETE_UNDELIVERED", "COMPLETE_SALVAGED")
            ),
        },
    }

    if args.salvage_dir:
        sdir = os.path.abspath(os.path.expanduser(args.salvage_dir))
        write_salvage(doc, sdir)
        write_team_salvage(doc, sdir)
        doc["salvage_dir"] = sdir
    # full member briefs live only in the salvage respawn files — strip from doc
    for team in led_teams:
        for m in team["members"]:
            m.pop("_prompt_full", None)

    md = render_md(doc)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as f:
            json.dump(doc, f, indent=1, default=str)
    if args.md_out:
        with open(args.md_out, "w", encoding="utf-8") as f:
            f.write(md)
    if not args.quiet:
        print(md)
    return 1 if hard_gaps else 0


if __name__ == "__main__":
    sys.exit(main())
