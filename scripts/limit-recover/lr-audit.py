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
  STALLED              one journal key re-issued N times with no result and the run
                       json carries an error -> ONE unit with attempts=N, never N
                       INTERRUPTED units, and never "the user did this"
  UNVERIFIABLE         artifacts missing/contradictory -> surface, never guess
  RUNNING              (teammates only) the member's own process is alive and its
                       last turn has not ended -> wait; never respawn over a live
                       member
  PENDING              lead process alive and IDLE, unit has no terminal record ->
                       WAIT-FOR-NOTIFICATION; the harness owns the promise
  UNSETTLED-INFLIGHT   lead process alive and mid-turn -> NONE; disk is silent for
                       as long as the retry ladder runs (93-101 min measured)

THE ALL-DEAD ASSUMPTION IS GONE (D1, docs/plans/NONLIMIT_RESUME_LADDER.md § W1.1 Q1).
Every verdict above used to be computed as though the lead process were dead,
because this file read no pid at all. A network drop usually does NOT end the
session: measured 2026-09-09, the whole fleet produced nothing from 14:40Z to
17:20Z while every process stayed alive, and the first api-error record landed
107 minutes after the silence began. So a unit's liveness is INHERITED from the
lead's process state (DEAD / IN-FLIGHT / IDLE), never inferred from its own file
mtime or last timestamp -- a stamp is written at RECORD time and 107 minutes of
fleet-wide disk silence under live processes is the strongest refutation of stamp
liveness this repo has recorded. Receipt for the hazard: `wf_f3e13296-400` slot
`agent-aefd2e2...` was reported PARTIAL -> RE-RUN one minute after its last
record, in a live process; executing that plan would have doubled a running slot.

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

GAP_VERDICTS = {
    "PARTIAL",
    "NULL",
    "INTERRUPTED",
    "STALLED",
    "UNVERIFIABLE",
    "VACUOUS_SUSPECT",
}

# NOT gaps, and for opposite reasons: PENDING is the harness's outstanding promise
# (it WILL settle) and UNSETTLED-INFLIGHT is a turn still running. Both mean "do
# not act"; neither means "nothing was interrupted", so they are reported as their
# own strata rather than folded into either COMPLETE or the gap ledger.
WAIT_VERDICTS = {"PENDING", "UNSETTLED-INFLIGHT"}

# ── D1: lead process state ---------------------------------------------------
LEAD_DEAD, LEAD_INFLIGHT, LEAD_IDLE = "DEAD", "IN-FLIGHT", "IDLE"
# `system`/`turn_duration` is the structural, spelling-free turn-END marker: it is
# written after a NORMAL turn and after an API-ERROR turn alike (137f37fe:1100,
# 52e35019:1424). It is what separates IN-FLIGHT from IDLE on disk. Read as "is
# there a turn end AFTER the last prompt", never as a 1:1 count against prompts --
# 52e35019 has 27 distinct promptIds against 24 turn_duration records, because
# prompts queued mid-turn share one turn end.
TURN_END_SUBTYPE = "turn_duration"
# Spawn tools whose tool_use id names a delegation the harness owes an answer for.
# `Bash` counts ONLY with run_in_background (a foreground Bash settles inline).
SPAWN_TOOLS = ("Agent", "Workflow", "Bash")

# ── D2: the notification ledger ---------------------------------------------
# A `<task-notification>` is the harness's terminal word on a BACKGROUND unit, and
# this file used to read none of them (`grep -c task-notification lr-audit.py` was
# 0), so a unit the harness had already settled read as an open gap. Shape is
# quoted, not inferred -- a real record from this repo's corpus
# (docs/research/pane-theft-composer-guard.md:33):
#   {"type":"queue-operation","operation":"enqueue","content":"<task-notification>
#    \n<task-id>bfpgwlzqu</task-id>\n<tool-use-id>toolu_01RwHg...</tool-use-id>
#    \n<output-file>...</output-file>\n<status>killed</status>\n<summary>...
#    </summary>\n</task-notification>"}
# Both carriers are read: the `queue-operation` ENQUEUE (the harness's promise,
# above) and the delivered `type:"user"` record. Either proves the harness has
# spoken about that tool-use-id.
NOTIF_MARKER = "<task-notification>"
NOTIF_TOOL_USE_RE = re.compile(r"<tool-use-id>\s*([^<\s]+)\s*</tool-use-id>")
NOTIF_STATUS_RE = re.compile(r"<status>\s*([^<\s]+)\s*</status>")
NOTIF_TASK_ID_RE = re.compile(r"<task-id>\s*([^<\s]+)\s*</task-id>")
# Status vocabulary measured over 300 recent transcripts: completed 5979 ·
# failed 358 · killed 180 · running 29 · stopped 4. `running` is the one value
# that is NOT terminal -- the harness is still working and will speak again.
NOTIF_NONTERMINAL = {"running"}

# Teammate (assignee-session) audit -----------------------------------------
# DEMOTED TO A DISPLAY FIELD (D1). This was the RUNNING predicate: last transcript
# activity newer than 300 s. It is a stamp, and a stamp is not liveness -- the
# 2026-09-09 outage held every teammate process alive with a silent disk for 2h40m,
# so every live member crossed this window into PARTIAL, whose ACTION is respawn
# over a live member. RUNNING is now keyed on the member's own pid plus its
# turn-end marker, exactly like the lead. The number survives only as reported
# context ("active Ns ago"), never as a verdict.
TEAM_ACTIVE_WINDOW_S = 300
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


# The sibling library, resolved through REALPATH. This file is deployed as a
# per-file symlink into ~/.claude, and a $0/__file__-relative sibling lookup then
# resolves against the LINK's directory -- where some siblings exist and some do
# not, so one invocation silently splits into a half that resolves and a half that
# dies (memory: symlinked-$0-splits-sibling-sources). realpath pins the lib beside
# the file actually being executed, which is the copy whose vintage matches.
LR_LIB_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "lr-lib.sh")

# Two censuses, one per arm, delegated to lr-lib.sh rather than reimplemented:
# two spellings of one liveness predicate is how sibling auditors end up
# disagreeing about one population, and lr_resume_procs carries two corrections a
# fresh implementation would silently lose -- the search pattern must not ride in
# the census's own argv (or `ps` prints it and the census matches ITSELF, saying
# YES for every sid ever asked), and only argv LEAVES count (a resume runs under a
# wrapper parent that carries the same command line, so a chain reads as two
# sessions).
_LEAD_PIDS_SH = r"""
set -u
lib="$1"; sid="$2"
# shellcheck source=/dev/null
. "$lib" 2>/dev/null || { printf 'lib_error 1\n'; exit 0; }
regdir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
# POSITIVE CONTROL PER ARM -- the load-bearing lines in this script. Both censuses
# return rc 1 for "nothing is live" AND for "I could not look". Reading the second
# as the first is what silently restores the all-DEAD assumption and re-authorises
# a blind re-run, so each arm reports whether its INSTRUMENT could run and a double
# refusal becomes UNKNOWN.
#
# The instrument for the registry arm is `jq` and ONLY `jq` -- that is the one
# thing lr_registry_live_rows refuses on. An ABSENT registry directory is not a
# refusal, it is a definite "no rows": there is nothing to parse and nothing to
# miss. Conflating the two made every audit run under a fixture or a fresh $HOME
# report UNKNOWN, which reads as a defect in the subject rather than in the probe.
if command -v jq >/dev/null 2>&1; then
  printf 'reg_ok 1\n'
  [ -d "$regdir" ] || printf 'reg_dir_absent 1\n'
  lr_registry_live_rows "$sid" 2>/dev/null | awk -F'\t' 'NF>=2 && $2 ~ /^[0-9]+$/ { print "pid " $2 }'
else
  printf 'reg_ok 0\n'
fi
if ps -axo pid= >/dev/null 2>&1; then
  printf 'argv_ok 1\n'
  lr_resume_procs "$sid" 2>/dev/null | awk '$1 ~ /^[0-9]+$/ { print "pid " $1 }'
else
  printf 'argv_ok 0\n'
fi
exit 0
"""


def lead_pids(sid, lr_lib=None):
    """Live pids holding this sid, plus which arms could answer.

    Returns (pids:set[int], arms:dict). `arms` carries reg_ok/argv_ok/lib_error so
    the caller can tell "no live process" from "no instrument" -- never collapse
    the two.
    """
    arms = {
        "reg_ok": False,
        "argv_ok": False,
        "lib_error": False,
        "reg_dir_absent": False,
    }
    lib = lr_lib or LR_LIB_PATH
    if not sid or not os.path.isfile(lib):
        arms["lib_error"] = True
        return set(), arms
    try:
        cp = subprocess.run(
            ["bash", "-c", _LEAD_PIDS_SH, "lr-audit-lead-pids", lib, sid],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        arms["lib_error"] = True
        return set(), arms
    pids = set()
    for ln in (cp.stdout or "").splitlines():
        parts = ln.split()
        if len(parts) != 2:
            continue
        tag, val = parts
        if tag == "pid" and val.isdigit():
            pids.add(int(val))
        elif tag == "reg_ok":
            arms["reg_ok"] = val == "1"
        elif tag == "argv_ok":
            arms["argv_ok"] = val == "1"
        elif tag == "reg_dir_absent":
            arms["reg_dir_absent"] = True
        elif tag == "lib_error":
            arms["lib_error"] = True
    return pids, arms


def lead_state(sid, lead, lr_lib=None):
    """The three lead states every in-process unit INHERITS (D1).

    DEAD       no live process holds the session -> a fresh process holds no
               promise; re-run is safe and correct.
    IN-FLIGHT  process alive and no turn end after the last prompt -> the turn is
               running (mid-retry or working) and disk stays silent for as long as
               the ladder runs. DO NOT TOUCH.
    IDLE       process alive and a turn end after the last prompt -> a unit with no
               terminal record is PENDING; the harness owes it a notification.
    UNKNOWN    neither census could run. NOT folded into DEAD: DEAD authorises a
               re-run, so a fail-safe default that mimicked it would be exactly the
               unfalsifiable shape this design removes.

    DEAD requires BOTH arms to have RUN, never one clean arm's silence: the
    registry arm alone missed a live session (`lr_registry_live_rows` rc=1 while
    pid 77720 held `claude ... --resume 52e35019...`, alive since Sep 8 19:51),
    which is why the argv census exists at all.
    """
    forced = os.environ.get("LR_AUDIT_LEAD_STATE")
    if forced:
        f = forced.strip().upper()
        if f in (LEAD_DEAD, LEAD_INFLIGHT, LEAD_IDLE, "UNKNOWN"):
            return {
                "state": f,
                "pids": [],
                "arms": {"forced": True},
                "turn_open": lead.get("turn_open"),
                "evidence": f"forced by LR_AUDIT_LEAD_STATE={forced}",
            }
    pids, arms = lead_pids(sid, lr_lib=lr_lib)
    turn_open = bool(lead.get("turn_open"))
    if pids:
        state = LEAD_INFLIGHT if turn_open else LEAD_IDLE
        ev = (
            f"pid(s) {sorted(pids)} alive; "
            + (
                "no turn end after the last prompt"
                if turn_open
                else "turn end present after the last prompt"
            )
        )
    elif arms["reg_ok"] and arms["argv_ok"]:
        state = LEAD_DEAD
        ev = "no registry row and no --resume argv leaf holds this sid (both censuses ran)"
    else:
        state = "UNKNOWN"
        ev = (
            "liveness UNDETERMINED — "
            f"registry census {'ran' if arms['reg_ok'] else 'REFUSED'}, "
            f"argv census {'ran' if arms['argv_ok'] else 'REFUSED'}"
            + (" (lr-lib.sh unreadable)" if arms["lib_error"] else "")
            + " — treated as not-DEAD, because DEAD authorises a re-run"
        )
    return {
        "state": state,
        "pids": sorted(pids),
        "arms": arms,
        "turn_open": turn_open,
        "evidence": ev,
    }


def inherit_lead_state(verdict, evid, settled, ls):
    """Overlay the lead's process state onto one in-process unit's mechanical
    verdict (D1). The unit's own file says what it DID; only the lead's state says
    whether anything still holds its promise.

    Only UNSETTLED units are rewritten. A unit the harness has already spoken
    about keeps its mechanical verdict -- the lead being alive does not un-fail a
    unit that failed.
    """
    state = (ls or {}).get("state")
    if settled or verdict not in ("PARTIAL", "NULL", "INTERRUPTED", "STALLED"):
        return verdict, evid
    if state == LEAD_INFLIGHT:
        return "UNSETTLED-INFLIGHT", evid + [
            "lead process alive and mid-turn (no turn end after the last prompt); "
            "disk silence is expected for as long as the retry ladder runs "
            "(93-101 min measured) — this is NOT evidence of death"
        ]
    if state == LEAD_IDLE:
        return "PENDING", evid + [
            "lead process alive and idle; this unit has no terminal record "
            "(no tool_result, no task-notification) — the harness owns the promise "
            "and will settle it"
        ]
    if state == "UNKNOWN":
        return "UNVERIFIABLE", evid + [
            "lead liveness UNDETERMINED — cannot tell a dead session from a live "
            "one, and a re-run over a live unit doubles it"
        ]
    return verdict, evid


def _note_notification(out, raw_text, obj, carrier):
    """Record one `<task-notification>` into the ledger (D2).

    `raw_text` is the notification body as it appears on disk -- the `.content`
    string of a `queue-operation` record, or the text of a delivered user record.
    A tool-use-id here is the harness's terminal word on that delegation, which is
    the second half of "settled" (the first being an ordinary `tool_result`).
    """
    txt = raw_text if isinstance(raw_text, str) else ""
    if NOTIF_MARKER not in txt:
        return
    status_m = NOTIF_STATUS_RE.search(txt)
    task_m = NOTIF_TASK_ID_RE.search(txt)
    status = (status_m.group(1) if status_m else "") or None
    for tid in NOTIF_TOOL_USE_RE.findall(txt):
        rec = {
            "status": status,
            "task_id": task_m.group(1) if task_m else None,
            "carrier": carrier,
            "timestamp": obj.get("timestamp"),
            "line": out["line_count"],
        }
        prior = out["notifications"].get(tid)
        # Last word wins, but a TERMINAL status is never overwritten by a
        # non-terminal one arriving out of order (`running` then `completed` is the
        # ordinary sequence; the reverse must not un-settle the unit).
        if prior and (prior.get("status") or "") not in NOTIF_NONTERMINAL:
            if (status or "") in NOTIF_NONTERMINAL:
                continue
        out["notifications"][tid] = rec
        if (status or "") not in NOTIF_NONTERMINAL:
            out["notified_tool_ids"].add(tid)


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
        # ── D2: the notification ledger ──────────────────────────────────────
        # spawn tool_use id -> {tool, description, line}. The POPULATION of
        # delegations, by tool name, so a zero names its strata instead of
        # reading as "nothing was delegated" (a fail-safe default that mimics the
        # healthy output is unfalsifiable).
        "spawn_tool_uses": {},
        # tool-use-id -> {status, task_id, carrier, timestamp}
        "notifications": {},
        "notified_tool_ids": set(),
        # ── D1: the turn-end marker ──────────────────────────────────────────
        "last_prompt_idx": None,
        "last_prompt_ts": None,
        "last_turn_end_idx": None,
        "turn_end_count": 0,
        "prompt_count": 0,
        "last_api_error": None,
        "turn_open": False,
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
                # ── D1: the structural turn-END marker ───────────────────────
                if typ == "system" and obj.get("subtype") == TURN_END_SUBTYPE:
                    out["last_turn_end_idx"] = out["line_count"]
                    out["turn_end_count"] += 1
                # ── D2: a notification can ride a `queue-operation` ENQUEUE ──
                # (the harness's promise) as well as a delivered user record.
                # Either proves the harness has spoken about that tool-use-id.
                if typ == "queue-operation":
                    _note_notification(out, obj.get("content"), obj, "queue-operation")
                msg = obj.get("message") or {}
                if typ == "assistant":
                    # Q3 predicate 2, the general death record: ANY api-error
                    # assistant record, whatever its `error` value. A cap and a
                    # network drop share this envelope byte for byte
                    # (`model:"<synthetic>"` + `isApiErrorMessage:true`); they
                    # differ only in which recovery MODE is legal, which is why
                    # this is recorded separately from `limit_events` instead of
                    # being filtered down to the quota spellings. The structural
                    # pair is also what makes the read safe: a session merely
                    # DISCUSSING an error in prose (this repo does constantly) is
                    # not a synthetic api-error record and cannot match.
                    if obj.get("isApiErrorMessage"):
                        out["last_api_error"] = {
                            "error": obj.get("error"),
                            "status": obj.get("apiErrorStatus"),
                            "text": text_of(msg)[:300],
                            "kind": classify_limit_text(text_of(msg)),
                            "timestamp": obj.get("timestamp"),
                            "uuid": obj.get("uuid"),
                            "line": out["line_count"],
                        }
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
                        name = it.get("name")
                        inp = it.get("input") or {}
                        # D2: the DELEGATION POPULATION, by tool name. A `Bash`
                        # counts only with run_in_background — a foreground Bash
                        # settles inline and the harness owes nothing for it.
                        if name in SPAWN_TOOLS and (
                            name != "Bash" or bool(inp.get("run_in_background"))
                        ):
                            out["spawn_tool_uses"][it.get("id")] = {
                                "tool": name,
                                "description": inp.get("description")
                                or inp.get("name")
                                or None,
                                "line": out["line_count"],
                                "timestamp": obj.get("timestamp"),
                            }
                        if name == "Workflow":
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
                        elif name == "Agent":
                            out["agent_tool_uses"][it.get("id")] = {
                                "description": inp.get("description"),
                                "prompt_head": (inp.get("prompt") or "")[:200],
                            }
                elif typ == "user":
                    items = content_items(msg)
                    utext = text_of(msg)
                    # ── D1: what counts as "the last PROMPT" ─────────────────
                    # Structural, not `promptSource`-dependent: a user record
                    # carrying no tool_result is a prompt (typed, queued or
                    # machine-injected). A tool_result record is the harness
                    # answering, not a new turn opening.
                    # A DELIVERED notification opens a turn too (measured: a queued
                    # task-notification was submitted and ran a turn), so it counts
                    # for turn_open — but not as a typed prompt, which is why the
                    # two are tracked separately rather than as one number.
                    if not any(i.get("type") == "tool_result" for i in items):
                        out["last_prompt_idx"] = out["line_count"]
                        out["last_prompt_ts"] = obj.get("timestamp")
                        if NOTIF_MARKER not in (utext or ""):
                            out["prompt_count"] += 1
                    # D2: the DELIVERED notification record.
                    if NOTIF_MARKER in (utext or ""):
                        _note_notification(out, utext, obj, "user")
                    for it in items:
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

    # ── D1: is a turn still OPEN? ────────────────────────────────────────────
    # "No turn end AFTER the last prompt", never a 1:1 count against prompts:
    # 52e35019 carries 27 distinct promptIds against 24 turn_duration records,
    # because prompts queued mid-turn share one turn end. A transcript with a
    # prompt and no turn end at all is open by the same rule.
    lp, lte = out["last_prompt_idx"], out["last_turn_end_idx"]
    out["turn_open"] = lp is not None and (lte is None or lte < lp)

    # ── D2: settled vs open delegations ──────────────────────────────────────
    # settled = tool_result ids ∪ terminal task-notification ids.
    out["settled_tool_ids"] = set(out["delivered_tool_ids"]) | set(
        out["notified_tool_ids"]
    )
    out["open_delegations"] = {
        tid: meta
        for tid, meta in out["spawn_tool_uses"].items()
        if tid not in out["settled_tool_ids"]
    }
    # Population by tool name, and the settled/open split. A zero here NAMES ITS
    # STRATA: an audit that missed a new spawn tool would otherwise print "0 open"
    # and read exactly like a clean session.
    pop = {}
    for tid, meta in out["spawn_tool_uses"].items():
        t = meta.get("tool") or "?"
        row = pop.setdefault(t, {"total": 0, "settled": 0, "open": 0})
        row["total"] += 1
        if tid in out["settled_tool_ids"]:
            row["settled"] += 1
        else:
            row["open"] += 1
    out["delegation_population"] = pop
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
    key_attempts, journal_failed = {}, []
    if os.path.isfile(journal_path):
        with open(journal_path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                obj = jline(raw)
                if not obj:
                    continue
                jtyp = obj.get("type")
                if jtyp == "started":
                    aid, key = obj.get("agentId"), obj.get("key")
                    started.setdefault(aid, key)
                    # Attempt ORDER matters: the last attempt is the one whose
                    # evidence describes the current state of the unit.
                    if aid not in key_attempts.setdefault(key, []):
                        key_attempts[key].append(aid)
                elif jtyp == "result":
                    results[obj.get("agentId")] = obj.get("result")
                    results_by_key.add(obj.get("key"))
                elif jtyp == "failed":
                    journal_failed.append(
                        {"key": obj.get("key"), "error": obj.get("error")}
                    )
    else:
        run["problems"].append("journal.jsonl missing")
    run["journal_failed"] = journal_failed

    # The run's own terminal error, quoted and never parsed for keywords. This is
    # the STRUCTURAL discriminator between a watchdog stall and a human Ctrl-C:
    # the watchdog kill is written into each dead attempt as
    # `[Request interrupted by user]`, byte-identical to a real interrupt, so the
    # attempt file cannot tell them apart. Only the run json's `error:` (and the
    # lead's `<status>failed</status>` vs `stopped`) separates them.
    run_error = summary.get("error") or (
        journal_failed[0].get("error") if journal_failed else None
    )
    run["error"] = run_error
    run_failed = bool(run_error) or (
        run.get("status") is not None and run.get("status") != "completed"
    )

    jsonls = {
        os.path.basename(p)[6:-6]: p
        for p in glob.glob(os.path.join(run_dir, "agent-*.jsonl"))
    }
    # POPULATION = journal `started` ∪ agent-*.jsonl actually on disk. An attempt
    # that never journaled still has a file, and a journaled attempt whose file is
    # gone is a real contradiction; neither may be dropped silently.
    for aid, key in started.items():
        key_attempts.setdefault(key, [])
        if aid not in key_attempts[key]:
            key_attempts[key].append(aid)
    orphan_files = {a: p for a, p in jsonls.items() if a not in started}

    def _emit(aid, key, path, st, verdict, evid, attempts=1, attempt_ids=None):
        run["slots"].append(
            {
                "agentId": aid,
                "key": key,
                "verdict": verdict,
                "evidence": evid,
                "jsonl": path,
                "prompt_head": (st or {}).get("prompt_head"),
                "model": (st or {}).get("model"),
                "lines": (st or {}).get("lines"),
                "tool_uses": (st or {}).get("tool_uses"),
                "salvaged_so": (st or {}).get("so_input")
                if verdict == "COMPLETE_SALVAGED"
                else None,
                "journal_result_present": aid in results,
                "attempts": attempts,
                "attempt_agent_ids": attempt_ids or [aid],
            }
        )

    # ── D2: FOLD retry attempts under one journal key into ONE unit ──────────
    # The harness re-issues a stalled slot under the SAME journal key with a fresh
    # agentId. Measured on `wf_acd6923d-9c5`: six `started` records under one key,
    # attempt 1 doing real work until its 600 s tool timeout and then five
    # 7-line attempts ~17 min apart with ZERO assistant records (the prompt, five
    # spawn attachments, the interrupt), one `failed`, and a run json reading
    # `status: failed`, `error: agent stalled on all 6 attempts (no progress for
    # 180000ms each)`. Read per-attempt that is six INTERRUPTED units, each
    # actioned RE-RUN and each blamed on "TaskStop / user" — the right verb applied
    # to the wrong object with the wrong population, and five identical re-fires
    # into a live outage already cost 85 minutes and produced nothing. Folded it is
    # ONE unit with attempts=6.
    for key, attempt_ids in key_attempts.items():
        resulted = [a for a in attempt_ids if a in results]
        # A key that completed under ANY attempt is historically resolved. The
        # completed attempt is the unit; earlier ones are SUPERSEDED history.
        if resulted or key in results_by_key:
            for aid in attempt_ids:
                path = jsonls.get(aid)
                st = scan_agent_jsonl(path) if path else None
                if aid in results and st is None:
                    # A journaled RESULT whose agent transcript is gone is a
                    # contradiction, not a completion: never let the missing file
                    # reach slot_verdict, whose floors read st["lines"].
                    verdict, evid = (
                        "UNVERIFIABLE",
                        ["journal carries a result but the agent jsonl is missing"],
                    )
                elif aid in results:
                    verdict, evid = slot_verdict(st, True, results.get(aid))
                elif path is None:
                    verdict, evid = (
                        "SUPERSEDED",
                        ["earlier attempt under a key that completed elsewhere"],
                    )
                else:
                    verdict, evid = (
                        "SUPERSEDED",
                        [
                            "call re-issued and completed under another agentId "
                            "(same journal key)"
                        ],
                    )
                _emit(aid, key, path, st, verdict, evid)
            continue

        last = attempt_ids[-1] if attempt_ids else None
        path = jsonls.get(last) if last else None
        st = scan_agent_jsonl(path) if path else None
        if st is None:
            _emit(
                last,
                key,
                None,
                None,
                "UNVERIFIABLE",
                ["journal started but agent jsonl missing"],
                attempts=len(attempt_ids),
                attempt_ids=attempt_ids,
            )
            continue
        verdict, evid = slot_verdict(st, False, None)
        if len(attempt_ids) > 1:
            evid = [
                f"{len(attempt_ids)} attempts under ONE journal key, no result: "
                + ", ".join(a[:12] for a in attempt_ids)
            ] + evid
            if run_failed:
                verdict = "STALLED"
                # REPLACE the interrupt attribution, never append beside it. The
                # watchdog writes its kill into each dead attempt as
                # `[Request interrupted by user]`, so slot_verdict reads
                # "interrupted (TaskStop / user)" — and leaving that line in place
                # next to the correction hands the reader both stories at once,
                # with the wrong one naming a person.
                evid = [
                    e for e in evid if not e.startswith("interrupted (TaskStop")
                ]
                evid.append(
                    "the harness exhausted its OWN retries under this key and the "
                    "run carries a terminal error — this is a watchdog stall, not a "
                    "user interrupt: the `[Request interrupted by user]` marker in "
                    "each dead attempt is the WATCHDOG's, byte-identical to a human "
                    "Ctrl-C, and only this run error separates them — "
                    + f"run error: {str(run_error)[:160]}"
                )
        _emit(
            last,
            key,
            path,
            st,
            verdict,
            evid,
            attempts=len(attempt_ids),
            attempt_ids=attempt_ids,
        )

    for aid, path in orphan_files.items():
        st = scan_agent_jsonl(path)
        verdict, evid = slot_verdict(st, False, None)
        evid.append("agent jsonl present but never journaled as started")
        _emit(
            aid,
            None,
            path,
            st,
            verdict if verdict != "PARTIAL" else "UNVERIFIABLE",
            evid,
        )

    # ── D1: inherit the lead's process state ─────────────────────────────────
    # Applied AFTER the mechanical verdicts, and only to unsettled gap units. A
    # workflow slot is settled when its journal carries a result; the run's own
    # tool_use id settles the RUN, not the slots inside it.
    ls = lead.get("lead_state")
    for s in run["slots"]:
        s["verdict"], s["evidence"] = inherit_lead_state(
            s["verdict"], s["evidence"], s.get("journal_result_present"), ls
        )

    counts = {}
    for s in run["slots"]:
        counts[s["verdict"]] = counts.get(s["verdict"], 0) + 1
    run["slot_counts"] = counts
    gaps = sum(v for k, v in counts.items() if k in GAP_VERDICTS)
    waiting = sum(v for k, v in counts.items() if k in WAIT_VERDICTS)
    if run["status"] == "completed" and gaps:
        run["run_verdict"] = "TAINTED_COMPLETE"
    elif run["status"] == "completed" and not run["delivered_to_lead"]:
        run["run_verdict"] = "COMPLETE_UNDELIVERED"
    elif run["status"] == "completed":
        run["run_verdict"] = "COMPLETE"
    elif waiting and not gaps:
        # Every unresolved slot is held by a live process. The run is not
        # INCOMPLETE-and-resumable, it is UNSETTLED — and its action is to wait,
        # not to resume. Resuming here is the doubling hazard.
        run["run_verdict"] = "UNSETTLED-INFLIGHT" if waiting else "INCOMPLETE"
        if counts.get("PENDING") and not counts.get("UNSETTLED-INFLIGHT"):
            run["run_verdict"] = "PENDING"
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
            # D2: "delivered" is now tool_result ids ∪ terminal notification ids.
            # A background unit settles by NOTIFICATION, and reading only
            # tool_result ids called such a unit undelivered while the harness had
            # already spoken about it.
            delivered = tid in lead["settled_tool_ids"] if tid else None
            if delivered is False:
                verdict, evid = (
                    "COMPLETE_UNDELIVERED",
                    ["final turn on disk; no tool_result and no task-notification"],
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
        tid = meta.get("toolUseId")
        notif = (lead.get("notifications") or {}).get(tid) if tid else None
        settled = bool(tid) and tid in lead["settled_tool_ids"]
        if notif and notif.get("status"):
            evid = evid + [
                f"task-notification status={notif['status']} "
                f"(carrier={notif.get('carrier')})"
            ]
        # ── D1: inherit the lead's process state ─────────────────────────────
        verdict, evid = inherit_lead_state(verdict, evid, settled, lead.get("lead_state"))
        out.append(
            {
                "agentId": aid,
                "verdict": verdict,
                "evidence": evid,
                "jsonl": path,
                "agentType": meta.get("agentType"),
                "description": meta.get("description"),
                "toolUseId": meta.get("toolUseId"),
                "settled": settled,
                "notification": notif,
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
        # D1: the same structural turn-end read the lead gets. A teammate is a
        # full CC session, so IN-FLIGHT / IDLE apply to it identically.
        "last_prompt_idx": None,
        "last_turn_end_idx": None,
        "turn_open": False,
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
                if typ == "system" and obj.get("subtype") == TURN_END_SUBTYPE:
                    st["last_turn_end_idx"] = st["lines"]
                msg = obj.get("message") or {}
                if typ == "user" and not any(
                    i.get("type") == "tool_result" for i in content_items(msg)
                ):
                    st["last_prompt_idx"] = st["lines"]
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
    lp, lte = st["last_prompt_idx"], st["last_turn_end_idx"]
    st["turn_open"] = lp is not None and (lte is None or lte < lp)
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


def member_verdict(st, deliverables, git_ev, now_utc, member_state=None):
    """Mechanical verdict for one teammate. Deliverable-on-disk evidence
    outranks transcript tail state, which outranks lead-side perception.

    `member_state` is the member's OWN lead_state() reading (D1) — a teammate is a
    full CC session, so the same three states apply to it. RUNNING is keyed on it,
    never on a stamp: `TEAM_ACTIVE_WINDOW_S` was the RUNNING predicate and it is a
    stamp, so an outage longer than five minutes turned every LIVE member into
    PARTIAL, whose action is respawn over that live member. Every outage is longer
    than five minutes (2h40m measured 2026-09-09). The verdict's polarity was right
    and its evidence was wrong.
    """
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
    age = None
    if st["last_ts"]:
        try:
            age = (
                now_utc - datetime.fromisoformat(st["last_ts"].replace("Z", "+00:00"))
            ).total_seconds()
        except ValueError:
            age = None
    # `age` is now REPORTED CONTEXT only — never a verdict. See TEAM_ACTIVE_WINDOW_S.
    ms = (member_state or {}).get("state")
    if st["last_kind"] == "api_error":
        evid.append(f"died on api error: {(st['last_api_error_text'] or '')[:100]}")
        mech = "NULL" if st["lines"] <= 12 else "PARTIAL"
    else:
        evid.append(
            f"substantive but unfinished (lines={st['lines']} tool_uses={st['tool_uses']}, "
            f"last activity {int(age) if age is not None else '?'}s ago)"
        )
        mech = "PARTIAL"
    # An api-error record does NOT license a respawn while the member's own process
    # is alive: an expired retry ladder ends the TURN, not the session, and the
    # member may already be retrying past the outage.
    if ms == LEAD_INFLIGHT:
        evid.append(
            f"member process alive (pid(s) {(member_state or {}).get('pids')}) and "
            "mid-turn — never respawn over a live member"
        )
        return "RUNNING", evid
    if ms == LEAD_IDLE:
        evid.append(
            f"member process alive (pid(s) {(member_state or {}).get('pids')}) and idle "
            "at its prompt — a live member is not a gap; wake it, never respawn it"
        )
        return "RUNNING", evid
    if ms == "UNKNOWN":
        evid.append(
            "member liveness UNDETERMINED — "
            f"{(member_state or {}).get('evidence')}"
        )
        return "UNVERIFIABLE", evid
    if ms == LEAD_DEAD:
        evid.append("member process is gone (registry and argv censuses both ran)")
    return mech, evid


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
                # The member's OWN process state, read with the same two censuses
                # as the lead's. The member sid is its transcript's basename —
                # config.json carries no sessionId, so this is the only link.
                msid = os.path.basename(paths[-1])
                for suf in (".jsonl.handed-off", ".jsonl"):
                    if msid.endswith(suf):
                        msid = msid[: -len(suf)]
                        break
                mstate = lead_state(msid, st)
                entry["member_state"] = mstate
                v, evid = member_verdict(st, dl, git_ev, now_utc, member_state=mstate)
                # `isActive=false` is the harness's own word and it OUTRANKS a
                # stamp — but not a live pid. Demoting a member whose process this
                # audit just proved alive is the respawn-over-a-live-member hazard
                # wearing the harness's authority, so the demotion now applies only
                # when no live process holds the member.
                if (
                    entry["isActive"] is False
                    and v == "RUNNING"
                    and not mstate.get("pids")
                ):
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
    waiting = doc["counts"].get("waiting") or 0
    L.append(
        f"- generated: {doc['generated_at']} · verdict floor: "
        f"**{'GAPS: ' + str(gaps) if gaps else 'NO GAPS'}**"
        + (f" · **WAITING: {waiting}** (not gaps, not complete)" if waiting else "")
    )
    ls = doc.get("lead_state") or {}
    if ls:
        L.append(
            f"- **lead process: {ls.get('state')}** — {ls.get('evidence')}. "
            "Every in-process verdict below INHERITS this: a network drop usually "
            "does not end the session, so DEAD is a measurement here, never an "
            "assumption."
        )
        if ls.get("state") == "UNKNOWN":
            L.append(
                "  - ⚠️ liveness UNDETERMINED, so no unit was cleared for re-run. "
                "This is deliberate: DEAD authorises a re-run, and a fail-safe "
                "default that mimicked DEAD would be unfalsifiable."
            )
    dg = doc.get("delegations") or {}
    if dg:
        pop = dg.get("population_by_tool") or {}
        strata = (
            " · ".join(
                f"{t} {r['total']} (settled {r['settled']}, open {r['open']})"
                for t, r in sorted(pop.items())
            )
            or "none"
        )
        # A ZERO NAMES ITS STRATA. An audit that missed a new spawn tool would
        # otherwise print "0 open" and read exactly like a clean session.
        L.append(f"- delegation population by tool: {strata}")
    ae = doc.get("last_api_error")
    if ae:
        L.append(
            f"- last api-error record: `error={ae.get('error')}` "
            f"kind={ae.get('kind')} at {ae.get('timestamp')} — {ae.get('text', '')[:120]}"
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
        # THE TRAP THIS LINE USED TO SET. `limit_events` is the QUOTA subset by
        # construction: a non-limit api error is classified `other_api_error` and
        # excluded, so a network death yields `limit_events: []` alongside a fully
        # correct gap ledger. The old wording — "No genuine limit events found" —
        # was true and read as "nothing was interrupted".
        L.append(
            "\n_No genuine QUOTA limit events in the lead transcript. This is the "
            "quota subset only and says NOTHING about whether work was interrupted "
            "— a network drop, a crash or a stall all produce an empty list here. "
            "Read the lead-process state, the api-error record and the delegation "
            "population above._"
        )
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
    waits = doc.get("wait_units") or []
    wait_ids = {(w["verdict"], w["unit"]) for w in waits}
    ledger = [g for g in doc["gap_units"] if (g["verdict"], g["unit"]) not in wait_ids]
    L.append(
        "\n## Gap ledger (every non-COMPLETE unit — each REQUIRES an action; bridging is banned)"
    )
    if not ledger:
        if waits:
            # NOT "all COMPLETE". Nothing is owed by us and something is still
            # moving; those are different states and collapsing them is how a lead
            # walks away from a working teammate.
            L.append(
                f"_no unit requires an action from you. {len(waits)} unit(s) are "
                "still held by a live process — see the wait ledger below. This is "
                "NOT 'all delegated work is COMPLETE'._"
            )
        else:
            L.append("_none — all delegated work is COMPLETE and delivered._")
    for g in ledger:
        L.append(f"- **{g['verdict']}** `{g['unit']}` → {g['action']}")
    if waits:
        L.append(
            "\n## Wait ledger (a live process holds these — waiting IS the action)"
        )
        for w in waits:
            L.append(f"- **{w['verdict']}** `{w['unit']}` → {w['action']}")
    return "\n".join(L) + "\n"


ACTION = {
    "NULL": "RE-RUN (workflow: resume run; bare: re-spawn with original prompt from salvage)",
    "PARTIAL": "RE-RUN (salvage is seed-context only, never a substitute result)",
    "INTERRUPTED": "RE-RUN unless COMPLETE_SALVAGED payload exists",
    "STALLED": (
        "AT MOST ONE re-fire, and only under a GREEN control (the probe, twice, 30s "
        "apart) — the harness already exhausted its own retries, so a blind re-fire "
        "reproduces the stall; a second stall under a green control convicts the "
        "REQUEST (size / a blocking tool / a headless permission prompt) and the "
        "remedy is to change the request, never a third fire"
    ),
    "VACUOUS_SUSPECT": "MODEL REVIEW output vs brief; re-run if vacuous",
    "UNVERIFIABLE": "SURFACE to user as named gap — never infer",
    "COMPLETE_UNDELIVERED": "READ result from disk (no re-run, no re-spend)",
    "COMPLETE_SALVAGED": "USE salvaged StructuredOutput payload (validated); note provenance",
    "TAINTED_COMPLETE": "run 'completed' over gap slots — treat final result as CONTAMINATED until slots re-run",
    "INCOMPLETE": "resume via Workflow({scriptPath, resumeFromRunId}); re-audit after",
    "SUPERSEDED": "NONE — slot re-issued and completed under another agentId",
    "RUNNING": (
        "NONE — the member's OWN process is alive; wait, never respawn over a live "
        "member. To hand it work, WAKE it; do not re-spawn it"
    ),
    "PENDING": (
        "WAIT-FOR-NOTIFICATION — the lead process is alive and idle and this unit "
        "has no terminal record, so the harness owns the promise and will settle it "
        "with a <task-notification>. Waiting is the ACTION here, not idling: the "
        "notification re-enters this audit on arrival. Never re-run"
    ),
    "UNSETTLED-INFLIGHT": (
        "NONE — the lead process is alive and mid-turn. Disk silence is expected for "
        "as long as the retry ladder runs (93-101 min measured, with the first error "
        "record 107 min after the silence began). Do not touch, do not re-run, and "
        "do not read the silence as death"
    ),
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
    # D1 — read ONCE, before any unit is judged, and hand it to every auditor.
    # This is the whole change in one line: the file used to read no pid at all
    # (`grep -E 'kill -0|os.kill|psutil|lstart' lr-audit.py` was 0 hits), so it
    # could not tell the three lead states apart and treated everything as DEAD.
    ls = lead_state(sid, lead)
    lead["lead_state"] = ls
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
            # "killed mid-run" IS A DEATH ASSERTED, NEVER MEASURED — and it was
            # wrong on the receipt case: `wf_f3e13296-400` had no run-summary json
            # because it was STILL RUNNING in a live process, and this line told
            # the recovering model it had been killed. A missing summary means the
            # run has not written its terminal record; only the lead's process
            # state says whether anything still holds it.
            if ls["state"] == LEAD_DEAD:
                r["problems"].append(
                    "run dir exists but run-summary json missing (killed mid-run — "
                    "no live process holds this session)"
                )
                r["run_verdict"] = "INCOMPLETE"
            else:
                r["problems"].append(
                    "run-summary json missing and the session is "
                    f"{ls['state']} — the run has not written its terminal record "
                    "YET; this is not evidence of a kill"
                )
                if r["run_verdict"] == "INCOMPLETE":
                    r["run_verdict"] = (
                        "UNSETTLED-INFLIGHT"
                        if ls["state"] == LEAD_INFLIGHT
                        else "PENDING"
                        if ls["state"] == LEAD_IDLE
                        else "UNVERIFIABLE"
                    )
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
        if r["run_verdict"] in WAIT_VERDICTS:
            gap_units.append(
                {
                    "unit": f"workflow {r['runId']} ({r['workflowName']})",
                    "verdict": r["run_verdict"],
                    "action": ACTION[r["run_verdict"]],
                }
            )
        if r["run_verdict"] in ("TAINTED_COMPLETE", "INCOMPLETE"):
            act = ACTION[r["run_verdict"]]
            # A run holding STALLED slots must not offer a BARE resume at the run
            # level: that is the same blind re-fire the stall policy exists to
            # gate, one level up, and a reader following the run row would never
            # see the slot row's guard.
            if r["slot_counts"].get("STALLED"):
                act = (
                    "GATED RESUME — this run holds "
                    f"{r['slot_counts']['STALLED']} STALLED slot(s). "
                    + ACTION["STALLED"]
                    + " Only then resume via Workflow({scriptPath, resumeFromRunId}); "
                    "re-audit after"
                )
            gap_units.append(
                {
                    "unit": f"workflow {r['runId']} ({r['workflowName']})",
                    "verdict": r["run_verdict"],
                    "action": act,
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
            if (
                s["verdict"] in GAP_VERDICTS
                or s["verdict"] in WAIT_VERDICTS
                or s["verdict"] == "COMPLETE_SALVAGED"
            ):
                unit = f"{r['runId']}/{s.get('agentId')}"
                if (s.get("attempts") or 1) > 1:
                    unit += f" [{s['attempts']} attempts, one journal key]"
                gap_units.append(
                    {
                        "unit": unit,
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
            if v == "RUNNING":
                # A live member is not a gap, but it must never be SILENT either:
                # its absence from the ledger is what let a lead conclude "nothing
                # is outstanding" and move on past a working teammate.
                gap_units.append(
                    {
                        "unit": f"team {team['name']}/{m['name']}",
                        "verdict": "RUNNING",
                        "action": ACTION["RUNNING"],
                    }
                )
                continue
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
    # PENDING / UNSETTLED-INFLIGHT / RUNNING are NOT gaps — nothing is owed by us —
    # but they are not COMPLETE either. Kept as their own stratum so a report can
    # never read "all delegated work is COMPLETE" over a unit that is still moving.
    wait_units = [
        g
        for g in gap_units
        if g["verdict"] in WAIT_VERDICTS or g["verdict"] == "RUNNING"
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
        # D1 — the state every in-process verdict above inherited. Reported at the
        # top level because a reader who does not know which of the three states
        # produced these verdicts cannot check any of them.
        "lead_state": ls,
        # Q3 predicate 2: the general death record, ANY `error` value. `limit_events`
        # above is the QUOTA subset and is EMPTY on a network death — reading that
        # emptiness as "nothing was interrupted" is the trap this field closes.
        "last_api_error": lead["last_api_error"],
        # D2 — the ledger, and the population a zero would otherwise hide.
        "delegations": {
            "population_by_tool": lead["delegation_population"],
            "spawned": len(lead["spawn_tool_uses"]),
            "settled": len(
                [t for t in lead["spawn_tool_uses"] if t in lead["settled_tool_ids"]]
            ),
            "open": [
                {"tool_use_id": t, **m} for t, m in lead["open_delegations"].items()
            ],
            "notifications": lead["notifications"],
        },
        "wait_units": wait_units,
        "lead": {
            "line_count": lead["line_count"],
            "last_model": lead["last_model"],
            "last_ts": lead["last_ts"],
            "compact_summaries": lead["compact_summaries"],
            "workflow_calls": lead["workflow_calls"],
            "turn_open": lead["turn_open"],
            "prompt_count": lead["prompt_count"],
            "turn_end_count": lead["turn_end_count"],
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
            "waiting": len(wait_units),
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
