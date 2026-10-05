#!/usr/bin/env python3
"""cc-resume-classify.py — decide, per recovered session, whether it was INTERRUPTED by the crash
or was already AT-REST when the power died. Only the interrupted ones may be re-engaged.

    Usage:  ... | cc-resume-classify.py [--boot-epoch SECS] [--explain]
                      [--wake-lost] [--lost-json PATH] [--hb-dir DIR]...
            reads lr-select.py's TSV on stdin:  account <TAB> session-id <TAB> worktree <TAB> branch
            (THE SID IS FIELD 2. lr-select.py:434 emits acct/sid/cwd/branch and boot-resume.sh:293
             reads it back in that order. This file and cc-resume-layout.sh both shipped reading
             field 3 as the sid, which is the WORKTREE PATH — see THE FIELD-ORDER TRAP below.)
            writes the same rows with one more LAST column: INTERRUPTED | AT-REST | UNKNOWN
            (a row may carry more than 4 columns — the W3 row contract has 11 — and the verdict
             is always appended last, so readers take $NF)
            --wake-lost adds a fourth verdict, WAKE-LOST: at rest, but with work open at the cut
            that died with the process (see ASYNC WORK OPEN AT THE CUT). Without the flag the
            output is byte-identical to before it existed. --lost-json writes what each session
            lost; --hb-dir names a restore-heartbeat directory whose hb.bg.tsv says what was live.

WHY THIS EXISTS (operator ruling, 2026-08-24)
---------------------------------------------
A crash recovery re-engaged all ten resumed sessions with a "continue autonomously" nudge. FIVE of
them had not been interrupted at all — they had come to rest at a deliberate pause point, and the
nudge sent them off doing work nobody had signed off. Their own last words say it plainly:

    wt-pool-4      "...which is yours to authorise."          <- waiting on an operator decision
    wt-pool-6      "still up for your feel check"               <- waiting on an operator look
    wt-pool-3      "Nothing open on my side. What would you like to work on?"
    wt-cc-180319   had just delivered a quota report
    wt-pool-8      idle 2.8 days

Operator: "for the sessions that were idle before the crash, we shouldn't re-ping them otherwise we
are sending them on off unsigned-off behavior that we didn't intend (often already idle sessions are
stopped at a good pausepoint waiting on a decision that needs more thought)."

THE DISCRIMINATOR — TWO SIGNALS, AND NEITHER ALONE IS SUFFICIENT
----------------------------------------------------------------
    INTERRUPTED  ==  mid-turn at its last breath   AND   alive when the power died

MID-TURN comes from the transcript tail: the model owed a reply. Either a tool_use whose tool_result
never arrived, or a record (tool_result, real prompt) sitting AFTER the last thing the assistant
actually said. AT-REST is the complement: the last content-bearing record is the assistant's own
text, so it had finished speaking and was sitting at its prompt.

ALIVE-AT-CRASH comes from the clock: the last pre-crash record is within --alive-window of boot.

An earlier draft of this file claimed the tail needed no threshold. That was wrong, and the measured
batch refutes it in one row. `wt-pool-8` and `personal` have BYTE-IDENTICAL tail shapes — assistant
tool_use, then a tool_result, then an attachment, no closing assistant text — so on tail alone both
read INTERRUPTED. But `personal` was cut 2.9 minutes before the crash (genuinely interrupted) while
`wt-pool-8` had been sitting in that state for 2.8 DAYS: it died mid-turn days earlier, and this
crash interrupted nothing. Re-pinging it would resume a turn nobody has thought about since Friday.
The clock is what separates them, and the tail is what stops the clock from convicting a session
that simply came to rest three minutes before the power went out. Both, or neither works.

A note on the tail rule, because the obvious spelling is wrong: "the last record has type=user" does
NOT mean a human typed something. Tool results are carried on user-type records, so that test fires
on every ordinary tool call. The rule is anchored on the last ASSISTANT TEXT instead.

FAIL-SAFE POLARITY. The two errors are not symmetric, so ties break toward silence:
  - failing to nudge an interrupted session costs a pane sitting idle until someone looks. Visible,
    cheap, recoverable.
  - nudging a parked session spends the operator's authority on work they were still deciding about.
    That is the defect this file exists to prevent.
Therefore an unreadable or ambiguous transcript is UNKNOWN, which callers must treat as AT-REST.

WHAT THE MEASURED BATCH LOOKS LIKE (2026-08-24 crash, boot 03:02:10Z) — this is the regression
fixture: 5 INTERRUPTED (recycle-11, backlog-lead, lakehouse, sr-zerohuman, personal) and 5 AT-REST
(wt-pool-6, wt-pool-4, wt-pool-3, wt-pool-8, wt-cc-180319). Every one of those five AT-REST rows was
nudged by the recovery that prompted this file, and three of them say in their own last words that
they were waiting on the operator: "which is yours to authorise", "still up for your feel check",
"Nothing open on my side. What would you like to work on?".

"""

import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys

STORES = (
    ".claude-next",
    ".claude-secondary",
    ".claude-tertiary",
    ".claude-quaternary",
    ".claude",
)


def boot_epoch_default():
    """kern.boottime, e.g. '{ sec = 1787626930, usec = ... } ...' -> 1787626930."""
    try:
        out = subprocess.run(
            ["sysctl", "-n", "kern.boottime"],
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout
        for tok in out.replace(",", " ").split():
            if tok.isdigit() and len(tok) >= 10:
                return int(tok)
    except Exception:
        pass
    return None


# ── THE ANCHOR IS THE EVENT THAT KILLED THE PANES, WHICH IS NOT ALWAYS A REBOOT (2026-09-16) ──────
# This tool anchored on kern.boottime alone, i.e. it assumed the only thing that kills a fleet of
# sessions is the box going down. A TERMINAL EMULATOR crash kills every pane it hosts and leaves
# the machine up, so boottime then points at an event HOURS before the one that mattered, and the
# reading inverts: measured 2026-09-16, kitty SIGSEGV'd at 01:13:49Z while boottime read 21:28:30Z
# the previous evening. Against boottime the run returned 3 UNKNOWN + 1 INTERRUPTED; against the
# true anchor it returned 3 AT-REST + 1 INTERRUPTED — and the one genuinely interrupted session was
# a DIFFERENT session in each reading. Every UNKNOWN defaults to AT-REST, so the wrong anchor would
# have restored the fleet and nudged nobody, reporting success.
#
# macOS writes a per-process .ips report for exactly this crash, so the anchor is recoverable
# rather than guessable: take the newest terminal-emulator crash NEWER than boottime. Falling back
# to boottime when there is none keeps the ordinary reboot case byte-identical.
TERMINAL_CRASH_PROCS = ("kitty", "iTerm2", "Terminal", "Alacritty", "WezTerm", "Ghostty")


def terminal_crash_epoch(since, reports_dir=None):
    """Newest terminal-emulator crash report strictly newer than `since` -> epoch, else None.

    The filename carries the local timestamp (`kitty-2026-09-16-201349.ips`), which is what makes
    this cheap: no .ips body is parsed, so a truncated or unreadable report cannot mislead us.
    """
    if reports_dir is None:
        reports_dir = os.path.expanduser("~/Library/Logs/DiagnosticReports")
    best = None
    for proc in TERMINAL_CRASH_PROCS:
        for path in glob.glob(f"{reports_dir}/{proc}-*.ips"):
            m = re.search(r"-(\d{4})-(\d{2})-(\d{2})-(\d{6})", os.path.basename(path))
            if not m:
                continue
            y, mo, d, hms = m.groups()
            try:
                when = datetime.datetime(
                    int(y), int(mo), int(d), int(hms[:2]), int(hms[2:4]), int(hms[4:6])
                ).timestamp()
            except ValueError:
                continue
            if when > since and (best is None or when > best[0]):
                best = (when, os.path.basename(path))
    return best


def find_transcript(sid):
    home = os.path.expanduser("~")
    for store in STORES:
        hits = glob.glob(f"{home}/{store}/projects/*/{sid}.jsonl")
        if hits:
            return hits[0]
    return None


def classify(path, boot_dt, alive_window):
    """-> (verdict, why, last_assistant_text). The pre-W3 contract: never WAKE-LOST."""
    verdict, why, last, _ = classify_full(path, boot_dt, alive_window)
    return verdict, why, last


def classify_full(path, boot_dt, alive_window, wake_lost=False, hb=None, sid=""):
    """-> (verdict, why, last_assistant_text, lost_items)

    Only records strictly BEFORE boot are considered: a resumed session appends to the same
    transcript, so anything at or after boot is the recovery itself, not the pre-crash state.
    Reading past boot is how a naive pass concludes every session was mid-turn.

    lost_items is what died with the old process (see ASYNC WORK below). With wake_lost, a session
    at rest that had such work open is WAKE-LOST instead of AT-REST.
    """
    pending = set()  # tool_use ids awaiting a tool_result
    scan = AsyncScan()
    last_text = ""
    saw_any = False
    last_ts = None  # last pre-crash record -> the alive-at-crash half
    after_speech = 0  # content records since the assistant last actually spoke
    try:
        fh = open(path, errors="replace")
    except OSError as exc:
        return "UNKNOWN", f"unreadable: {exc}", ""
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            ts = rec.get("timestamp")
            if not ts:
                continue
            try:
                when = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
            except ValueError:
                continue
            if when >= boot_dt:
                break
            saw_any = True
            last_ts = when
            role = rec.get("type")
            scan.record(rec, when)
            # ONLY user/assistant records are anyone's TURN. Everything else a session writes —
            # `attachment` (token reminders), `system` (hook output), bridge/last-prompt markers —
            # is housekeeping that lands AFTER a turn has settled. Measured on this batch: a session
            # that came to rest trails 4-8 such records and NOTHING else, while a genuinely
            # interrupted one trails an assistant/tool_use. An earlier cut of this rule skipped only
            # `attachment`, so every settled session still counted 2-3 trailing `system` records and
            # read as mid-turn — the tail signal collapsed to always-true and only the clock was
            # left working. Excluding by an allowlist of turn-bearing types, not by a denylist of
            # the housekeeping types seen so far, is what keeps the next new record type from
            # silently re-breaking it.
            if role not in ("user", "assistant"):
                continue
            spoke = False
            content = (rec.get("message") or {}).get("content")
            if isinstance(content, list):
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    kind = item.get("type")
                    if kind == "tool_use":
                        pending.add(item.get("id"))
                    elif kind == "tool_result":
                        pending.discard(item.get("tool_use_id"))
                    elif kind == "text" and role == "assistant":
                        last_text = item.get("text", "")
                        spoke = True
            elif isinstance(content, str) and role == "assistant":
                last_text = content
                spoke = True
            after_speech = 0 if spoke else after_speech + 1

    if not saw_any or last_ts is None:
        return "UNKNOWN", "no pre-crash records", "", []
    lost = scan.lost(path, boot_dt, pending, hb or {}, sid)

    # --- signal 1: was a turn in flight? ---
    if pending:
        mid_turn, tail_why = True, f"{len(pending)} tool_use with no tool_result"
    elif after_speech:
        # A tool_result or a real prompt landed and the assistant never replied. NOTE this is
        # anchored on the last assistant TEXT, not on `type == "user"`: tool results ride on
        # user-type records, so the naive test fires on every ordinary tool call.
        mid_turn, tail_why = (
            True,
            f"{after_speech} record(s) after the assistant last spoke",
        )
    else:
        mid_turn, tail_why = False, "tail is a completed assistant turn"

    # --- signal 2: was it alive when the power died? ---
    idle = (boot_dt - last_ts).total_seconds()
    alive = idle <= alive_window

    if mid_turn and alive:
        return (
            "INTERRUPTED",
            f"{tail_why}, {idle / 60:.1f} min before the crash",
            last_text,
            lost,
        )
    open_work = [i for i in lost if i["kind"] in WAKE_KINDS]
    if mid_turn and wake_lost and open_work and sid in (hb or {}).get("live", ()):
        # Mid-turn and cold by the clock, but the heartbeat saw the process alive at its last tick
        # and it had work open: a session parked inside a long call (measured 2026-10-05 on the
        # live fleet: two sessions 22 and 54 min into one tool call, a Workflow and a /goal open).
        # The clock alone would restore it and tell it nothing. Without the heartbeat's word that
        # it was alive, the rule below stands: a session cold for days was not cut by this event.
        kinds = sorted({i["kind"] for i in open_work})
        return (
            "WAKE-LOST",
            f"mid-turn and {_ago(idle)} idle, but alive at the last heartbeat with "
            f"{len(open_work)} open at the cut ({', '.join(kinds)}; {tail_why})",
            last_text,
            lost,
        )
    if mid_turn:
        # Mid-turn but long cold: it died before this crash, so this crash interrupted nothing.
        return (
            "AT-REST",
            f"mid-turn but stale — {_ago(idle)} idle, beyond the {alive_window / 60:.0f} min "
            f"alive-window ({tail_why})",
            last_text,
            lost,
        )
    if wake_lost and open_work:
        kinds = sorted({i["kind"] for i in open_work})
        return (
            "WAKE-LOST",
            f"{tail_why}, but {len(open_work)} open at the cut ({', '.join(kinds)})",
            last_text,
            lost,
        )
    return "AT-REST", f"{tail_why}, {_ago(idle)} idle", last_text, lost


# ── ASYNC WORK OPEN AT THE CUT (W3 P4, 2026-10-05) ────────────────────────────────────────────────
# A session whose tail is a completed turn can still have been waiting on something that died with
# its process: a background shell, an inbox watcher it armed itself, a Monitor, a background
# subagent, a Workflow run, or a /goal that will never be evaluated again. On 2026-10-01 Claude
# Code's own "didn't finish before the previous session ended" notice reached 10 sessions and 7 of
# them never acted on it, so that notice is not a recovery. WAKE-LOST names those sessions.
#
# DIRECT EVIDENCE ONLY, never transcript age:
#   - a launch (tool_use) AFTER the session's last process start (its last SessionStart:startup or
#     :resume hook record) with no <task-notification> carrying a <status> for it and no TaskStop;
#     a Monitor also closes when its own timeout passed before the cut;
#   - a subagent or workflow journal under <projects>/<slug>/<sid>/ written in the 15 min before it;
#   - a last goal_status with met:false and not failed (handoff-fire.sh goal_live_for_sid's rule);
#   - a ship-land the heartbeat saw running under the session.
# NOT evidence, and the reason matters: a live `.watching` pid on its own. hooks/mailbox-wake-arm.sh
# arms one at every SessionStart, so nearly every session has one and the resume re-arms it; taking
# it as evidence would nudge the whole fleet, which is the 2026-08-24 defect. It only confirms a
# watcher the session launched itself. Listening ports, agent-browser sessions and Agent Teams
# members are named in the note and never decide the verdict.
WAKE_KINDS = ("shell", "watcher", "agent", "workflow", "monitor", "journal", "goal", "ship")
PAD = "\x1f"  # boot-resume.sh's TSV_PAD / restore-heartbeat.sh's HB_PAD: an empty cell
JOURNAL_WINDOW_S = 900
_TASK_ID_RES = (
    re.compile(r"Task ID: ([A-Za-z0-9_-]+)"),
    re.compile(r"with ID: ([A-Za-z0-9_-]+)"),
    re.compile(r"\(task ([A-Za-z0-9_-]+)"),
    re.compile(r"agentId: ([A-Za-z0-9_-]+)"),
)
_RUN_ID_RE = re.compile(r"wf_[0-9a-z][0-9a-z-]{5,}")
_NOTIF_RE = re.compile(r"<task-notification>(.*?)</task-notification>", re.S)
_AB_SESSION_RE = re.compile(r"--session[ =]([A-Za-z0-9._-]+)")
_AB_OPEN_RE = re.compile(r"agent-browser\b[^|;&\n]*?\b(?:open|goto|navigate)\s+['\"]?(\S+?)['\"]?(?:\s|$)")


def _tag(body, name):
    m = re.search(rf"<{name}>(.*?)</{name}>", body, re.S)
    return m.group(1).strip() if m else ""


def _text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(
            (i.get("text") or "") if isinstance(i, dict) and i.get("type") == "text"
            else (_text_of(i.get("content")) if isinstance(i, dict) and i.get("type") == "tool_result" else "")
            for i in content
        )
    return ""


class AsyncScan:
    """One pass over the pre-cut records, fed by classify_full's own loop."""

    def __init__(self):
        self.launches = {}  # tool_use id -> item
        self.bash = {}  # tool_use id -> command, for a shell the harness backgrounded by itself
        self.stopped = set()
        self.goal = None
        self.browser = {}  # agent-browser session name -> last url

    def _close(self, tool_use_id, task_id, status):
        for item in self.launches.values():
            if item["id"] == tool_use_id or (task_id and item.get("task_id") == task_id):
                # A Monitor posts one notification per event; only a status ends the watch.
                if item["kind"] != "monitor" or status:
                    item["closed"] = True

    def _notifications(self, text):
        if "<task-notification>" not in text:
            return
        for body in _NOTIF_RE.findall(text):
            tid, tuid = _tag(body, "task-id"), _tag(body, "tool-use-id")
            if tid or tuid:
                self._close(tuid, tid, _tag(body, "status"))

    def record(self, rec, when):
        role = rec.get("type")
        if role == "attachment":
            att = rec.get("attachment") or {}
            if att.get("type") == "goal_status":
                self.goal = att
            elif att.get("hookName") in ("SessionStart:startup", "SessionStart:resume"):
                # A new process: whatever the previous one launched died with it, and that resume's
                # own notices already said so.
                for item in self.launches.values():
                    item["closed"] = True
            return
        if role == "queue-operation":
            self._notifications(rec.get("content") or "" if isinstance(rec.get("content"), str) else "")
            return
        if role not in ("user", "assistant"):
            return
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, str):
            if role == "user":
                self._notifications(content)
            return
        if not isinstance(content, list):
            return
        for item in content:
            if not isinstance(item, dict):
                continue
            kind = item.get("type")
            if kind == "text" and role == "user":
                self._notifications(item.get("text") or "")
            elif kind == "tool_use":
                self._tool_use(item, when)
            elif kind == "tool_result":
                self._tool_result(item, rec)

    def _launch(self, tid, kind, when, detail, **extra):
        self.launches[tid] = dict(
            {"kind": kind, "id": tid, "at": when.isoformat(), "detail": " ".join(detail.split())[:160]},
            **extra,
        )

    def _tool_use(self, item, when):
        name, tid = item.get("name"), item.get("id")
        inp = item.get("input") if isinstance(item.get("input"), dict) else {}
        bg = str(inp.get("run_in_background", "")).lower() == "true"
        if name == "Bash":
            cmd = str(inp.get("command") or "")
            self.bash[tid] = cmd
            if "agent-browser" in cmd:
                sess = _AB_SESSION_RE.search(cmd)
                url = _AB_OPEN_RE.search(cmd)
                key = sess.group(1) if sess else "default"
                if url or key not in self.browser:
                    self.browser[key] = url.group(1) if url else self.browser.get(key, "")
            if bg:
                self._launch(tid, _shell_kind(cmd), when, cmd, ship="ship-land" in cmd)
        elif name in ("Agent", "Task"):
            self._launch(tid, "agent", when, str(inp.get("description") or ""), confirmed=bg)
        elif name == "Workflow":
            self._launch(tid, "workflow", when, str(inp.get("name") or inp.get("scriptPath") or "inline script"))
        elif name == "Monitor":
            self._launch(tid, "monitor", when, str(inp.get("description") or inp.get("command") or ""),
                         timeout_ms=inp.get("timeout_ms"))
        elif name == "TaskStop":
            self.stopped.add(str(inp.get("task_id") or inp.get("shell_id") or ""))

    def _tool_result(self, item, rec):
        tid = item.get("tool_use_id")
        text = _text_of(item.get("content"))
        launch = self.launches.get(tid)
        if launch is None:
            # A foreground shell the harness moved to the background (a timeout, or ctrl-b).
            if tid in self.bash and re.search(r"running in (the )?background", text):
                cmd = self.bash[tid]
                when = datetime.datetime.fromisoformat(rec["timestamp"].replace("Z", "+00:00"))
                self._launch(tid, _shell_kind(cmd), when, cmd, ship="ship-land" in cmd)
                launch = self.launches[tid]
            else:
                return
        if launch["kind"] == "agent" and not launch.pop("confirmed", False):
            if "launched" not in text and "background" not in text:
                del self.launches[tid]  # a foreground subagent: its result IS its end
                return
        tur = rec.get("toolUseResult") if isinstance(rec.get("toolUseResult"), dict) else {}
        task = tur.get("backgroundTaskId") or tur.get("taskId") or tur.get("agentId") or ""
        for rx in _TASK_ID_RES:
            if task:
                break
            m = rx.search(text)
            task = m.group(1) if m else ""
        if task:
            launch["task_id"] = str(task)
        run = _RUN_ID_RE.search(text)
        if run and launch["kind"] == "workflow":
            launch["run_id"] = run.group(0)

    def lost(self, path, boot_dt, pending, hb, sid):
        items = []
        for item in self.launches.values():
            item.pop("confirmed", None)
            if item.get("closed") or item.get("task_id") in self.stopped:
                continue
            if item["kind"] == "monitor" and isinstance(item.get("timeout_ms"), (int, float)):
                born = datetime.datetime.fromisoformat(item["at"])
                if born + datetime.timedelta(milliseconds=item["timeout_ms"]) <= boot_dt:
                    continue  # it had already expired by itself
            items.append({k: v for k, v in item.items() if k not in ("closed", "timeout_ms") and v not in ("", None, False)})
        # A ship-land in flight as a FOREGROUND call: the turn was cut inside it.
        ship = any(i.get("ship") for i in items) or any("ship-land" in self.bash.get(t, "") for t in pending)
        runs = {i.get("run_id") for i in items}
        fresh, new_runs = _fresh_journals(path, boot_dt)
        new_runs = sorted(r for r in new_runs if r not in runs)
        if fresh and (new_runs or not any(i["kind"] in ("agent", "workflow") for i in items)):
            items.append({"kind": "journal", "detail": f"{fresh} subagent or workflow journal file(s) written in the "
                          f"{JOURNAL_WINDOW_S // 60} min before the cut", "run_ids": new_runs})
        goal = self.goal or {}
        if goal and not goal.get("met") and not goal.get("failed"):
            items.append({"kind": "goal", "detail": " ".join(str(goal.get("condition") or "").split())[:200]})
        mine = hb.get("by_sid", {}).get(sid, {})
        if mine.get("watching"):
            for i in items:
                if i["kind"] == "watcher":
                    i["alive_at_tick"] = True
        ship = ship or any("ship-land" in c for c in mine.get("children", []))
        if ship:
            items.append({"kind": "ship", "detail": "a ship-land was running"})
        if mine.get("ports"):
            items.append({"kind": "port", "detail": " ".join(sorted(set(mine["ports"])))})
        for name in hb.get("browsers", []):
            if name in self.browser:
                items.append({"kind": "browser", "detail": name, "url": self.browser[name]})
        items.extend(_teammates(sid))
        return items


def _shell_kind(cmd):
    return "watcher" if "cc-await-ping" in cmd and "--stand-down" not in cmd else "shell"


def _fresh_journals(path, boot_dt):
    """(count, run ids) of subagent / workflow journals written in the window before the cut."""
    root = os.path.join(os.path.dirname(path), os.path.basename(path)[: -len(".jsonl")], "subagents")
    hi = boot_dt.timestamp()
    lo = hi - JOURNAL_WINDOW_S
    count, runs = 0, set()
    for base, _dirs, files in os.walk(root):
        for name in files:
            try:
                mt = os.path.getmtime(os.path.join(base, name))
            except OSError:
                continue
            if lo <= mt <= hi:
                count += 1
                m = _RUN_ID_RE.search(base)
                if m:
                    runs.add(m.group(0))
    return count, runs


def _teammates(sid):
    """Non-lead Agent Teams members of a team this session leads (the config on disk, not a process)."""
    out = []
    home = os.path.expanduser("~")
    for store in STORES:
        for cfg in glob.glob(f"{home}/{store}/teams/*/config.json"):
            try:
                with open(cfg, errors="replace") as fh:
                    team = json.load(fh)
            except (OSError, ValueError):
                continue
            if not isinstance(team, dict) or team.get("leadSessionId") != sid:
                continue
            for m in team.get("members") or []:
                if not isinstance(m, dict) or m.get("agentId") == team.get("leadAgentId"):
                    continue
                if m.get("agentType") == "team-lead" or not m.get("name"):
                    continue
                out.append({"kind": "teammate", "detail": str(m["name"]), "team": str(team.get("name") or "")})
    return out


def load_heartbeat(dirs):
    """Each heartbeat dir -> {"by_sid": {sid: {children, watching, ports}}, "browsers": [names], "live": {sids}}.

    hb.bg.tsv rows: sid, claude_pid, kind, pid, detail; hb.session.tsv's first column is every
    session live at the tick (restore-heartbeat.sh). Read from the files the last tick wrote, never
    from live state: by the time a restore runs, those processes are gone.
    """
    hb = {"by_sid": {}, "browsers": [], "live": set()}
    for d in dirs:
        try:
            with open(os.path.join(d, "hb.session.tsv"), errors="replace") as fh:
                hb["live"].update(c for c in (line.split("\t", 1)[0].strip() for line in fh) if c and c != PAD)
        except OSError:
            pass
        try:
            fh = open(os.path.join(d, "hb.bg.tsv"), errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                cols = line.rstrip("\n").split("\t")
                if len(cols) < 5:
                    continue
                sid, kind, detail = cols[0], cols[2], cols[4]
                if kind == "agent-browser":
                    if detail not in hb["browsers"]:
                        hb["browsers"].append(detail)
                    continue
                if not sid or sid == PAD:
                    continue
                row = hb["by_sid"].setdefault(sid, {"children": [], "watching": [], "ports": []})
                if kind == "child":
                    row["children"].append(detail)
                elif kind == "watching":
                    row["watching"].append(cols[3])
                elif kind == "listen":
                    row["ports"].extend(":" + p.rsplit(":", 1)[-1] for p in detail.split() if ":" in p)
    return hb


def _ago(seconds):
    if seconds < 3600:
        return f"{seconds / 60:.1f} min"
    if seconds < 86400:
        return f"{seconds / 3600:.1f} h"
    return f"{seconds / 86400:.1f} d"


SELFTEST_CASES = [
    # (name, records, expected) — records are (offset_seconds_before_boot, type, kind)
    # kind: "text" = assistant utterance · "tool_use" · "tool_result" · None = housekeeping payload
    (
        "settled_recently",
        [(600, "assistant", "text"), (200, "system", None), (190, "attachment", None)],
        "AT-REST",
    ),
    (
        "cut_mid_tool",
        [(600, "assistant", "text"), (200, "assistant", "tool_use")],
        "INTERRUPTED",
    ),
    (
        "owed_reply",
        [
            (600, "assistant", "text"),
            (300, "assistant", "tool_use"),
            (200, "user", "tool_result"),
        ],
        "INTERRUPTED",
    ),
    (
        "mid_turn_but_stale",
        [(90000, "assistant", "text"), (86400, "assistant", "tool_use")],
        "AT-REST",
    ),
    ("settled_long_ago", [(90000, "assistant", "text")], "AT-REST"),
]


def _selftest_anchor():
    """Prove the terminal-crash anchor is load-bearing AND cannot fire in the ordinary case.

    Case 4 is the one that keeps this honest: with no terminal crash newer than boot, the helper
    must return None so a plain reboot recovery behaves exactly as it did before 2026-09-16. A
    helper that always answered would pass cases 1-3 and silently change every reboot recovery.
    """
    import shutil
    import tempfile

    d = tempfile.mkdtemp()
    failures = 0
    try:
        boot = datetime.datetime(2026, 9, 16, 16, 28, 30).timestamp()
        for name in (
            "kitty-2026-09-16-181446.ips",   # after boot, older of the two kitty crashes
            "kitty-2026-09-16-201349.ips",   # after boot, THE one — newest terminal crash
            "kitty-2026-09-15-090000.ips",   # BEFORE boot: a previous boot's crash, must not win
            "Python-2026-09-16-235959.ips",  # newest file in the dir, but NOT a terminal
        ):
            open(os.path.join(d, name), "w").close()

        cases = []
        hit = terminal_crash_epoch(boot, d)
        cases.append((
            "picks newest terminal crash after boot",
            hit is not None and hit[1] == "kitty-2026-09-16-201349.ips",
        ))
        cases.append((
            "ignores a non-terminal process",
            hit is not None and not hit[1].startswith("Python-"),
        ))
        late = datetime.datetime(2026, 9, 16, 21, 0, 0).timestamp()
        cases.append((
            "ignores crashes older than the anchor",
            terminal_crash_epoch(late, d) is None,
        ))
        empty = tempfile.mkdtemp()
        try:
            cases.append((
                "no reports -> None (ordinary reboot unchanged)",
                terminal_crash_epoch(boot, empty) is None,
            ))
        finally:
            shutil.rmtree(empty, ignore_errors=True)

        for name, ok in cases:
            failures += 0 if ok else 1
            print(
                f"{'ok  ' if ok else 'FAIL'} anchor: {name}",
                file=sys.stderr,
            )
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return failures


# ── WAKE-LOST selftest. The tool-result and notification strings are the ones measured in the
# 2026-10-01 transcripts (C2-restore-command.md §2.7): "Workflow launched in background. Task ID:
# wtcaytsys", "Monitor started (task bv3wgaxut, …)", and the <task-notification> block. Each record
# is (seconds before the cut, builder). Every positive case has a negative twin that differs in the
# one record that closes the work, so a rule that ignored that record would fail the twin.
def _a_text():
    return {"type": "assistant", "message": {"content": [{"type": "text", "text": "done."}]}}


def _a_use(tid, name, **inp):
    return {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}]}}


def _u_result(tid, text):
    return {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": tid, "content": text}]}}


def _u_notif(tid, task, status="completed"):
    st = f"<status>{status}</status>\n" if status else ""
    return {"type": "user", "message": {"content": "<task-notification>\n<task-id>" + task + "</task-id>\n<tool-use-id>"
            + tid + "</tool-use-id>\n" + st + "<summary>x</summary>\n</task-notification>"}}


def _att(**att):
    return {"type": "attachment", "attachment": att}


_WF = "Workflow launched in background. Task ID: wtcaytsys\nTranscript dir: /p/s/subagents/workflows/wf_d4508a0a-f86"
_MON = "Monitor started (task bv3wgaxut, expires in 30m unless the source ends first)"
_SH = "Command running in background with ID: bzrbwj020"
_AG = "Async agent launched successfully.\nagentId: a81e9ac94a5566598"
_SID = "5e1f7e57-0000-4000-8000-000000000001"


def _has(kind, **kv):
    return lambda items: any(i["kind"] == kind and all(i.get(k) == v for k, v in kv.items()) for i in items)


def _lacks(kind):
    return lambda items: not any(i["kind"] == kind for i in items)


WAKE_CASES = [
    # (name, records, expected, options, check on the lost items)
    ("workflow_open", [(600, _a_text()), (500, _a_use("w1", "Workflow", script="x")), (499, _u_result("w1", _WF)),
                       (400, _a_text())], "WAKE-LOST", {}, _has("workflow", task_id="wtcaytsys", run_id="wf_d4508a0a-f86")),
    ("workflow_notified", [(600, _a_text()), (500, _a_use("w1", "Workflow", script="x")), (499, _u_result("w1", _WF)),
                           (300, _u_notif("w1", "wtcaytsys")), (200, _a_text())], "AT-REST", {}, _lacks("workflow")),
    ("workflow_open_flag_off", [(500, _a_use("w1", "Workflow", script="x")), (499, _u_result("w1", _WF)),
                                (400, _a_text())], "AT-REST", {"wake": False}, _has("workflow")),
    ("monitor_open", [(500, _a_use("m1", "Monitor", command="x", timeout_ms=1800000)), (499, _u_result("m1", _MON)),
                      (400, _a_text())], "WAKE-LOST", {}, _has("monitor", task_id="bv3wgaxut")),
    ("monitor_event_is_not_an_end", [(500, _a_use("m1", "Monitor", command="x", timeout_ms=1800000)),
                                     (499, _u_result("m1", _MON)), (300, _u_notif("m1", "bv3wgaxut", "")),
                                     (200, _a_text())], "WAKE-LOST", {}, _has("monitor")),
    ("monitor_expired", [(4000, _a_use("m1", "Monitor", command="x", timeout_ms=1800000)), (3999, _u_result("m1", _MON)),
                         (3900, _a_text())], "AT-REST", {}, _lacks("monitor")),
    ("shell_open", [(500, _a_use("b1", "Bash", command="bats tests/x.bats", run_in_background=True)),
                    (499, _u_result("b1", _SH)), (400, _a_text())], "WAKE-LOST", {}, _has("shell", task_id="bzrbwj020")),
    ("shell_stopped", [(500, _a_use("b1", "Bash", command="bats tests/x.bats", run_in_background=True)),
                       (499, _u_result("b1", _SH)), (450, _a_use("s1", "TaskStop", task_id="bzrbwj020")),
                       (449, _u_result("s1", "stopped")), (400, _a_text())], "AT-REST", {}, _lacks("shell")),
    ("shell_moved_to_background", [(500, _a_use("b1", "Bash", command="sleep 900")),
                                   (499, _u_result("b1", "Command running in background with ID: bq1")),
                                   (400, _a_text())], "WAKE-LOST", {}, _has("shell", task_id="bq1")),
    ("shell_from_an_earlier_process", [(500, _a_use("b1", "Bash", command="bats", run_in_background=True)),
                                       (499, _u_result("b1", _SH)), (450, _a_text()),
                                       (300, _att(type="hook_success", hookName="SessionStart:resume")),
                                       (200, _a_text())], "AT-REST", {}, _lacks("shell")),
    ("ship_land_in_flight", [(500, _a_use("b1", "Bash", command="bash scripts/ship-land.sh", run_in_background=True)),
                             (499, _u_result("b1", _SH)), (400, _a_text())], "WAKE-LOST", {}, _has("ship")),
    ("watcher_armed_by_the_session", [(500, _a_use("b1", "Bash", command="cc-await-ping --timeout 3300",
                                                   run_in_background=True)), (499, _u_result("b1", _SH)),
                                      (400, _a_text())], "WAKE-LOST", {"hb": "watching"}, _has("watcher", alive_at_tick=True)),
    ("watcher_from_the_hook_only", [(400, _a_text())], "AT-REST", {"hb": "watching"}, _lacks("watcher")),
    ("agent_background_open", [(500, _a_use("g1", "Agent", description="scan", run_in_background="true")),
                               (499, _u_result("g1", _AG)), (400, _a_text())], "WAKE-LOST", {}, _has("agent")),
    ("agent_foreground", [(500, _a_use("g1", "Agent", description="scan")), (300, _u_result("g1", "the report")),
                          (200, _a_text())], "AT-REST", {}, _lacks("agent")),
    ("goal_live", [(500, _att(type="goal_status", met=False, sentinel=True, condition="P4 landed")),
                   (400, _a_text())], "WAKE-LOST", {}, _has("goal", detail="P4 landed")),
    ("goal_met", [(500, _att(type="goal_status", met=False, condition="P4 landed")),
                  (450, _att(type="goal_status", met=True, condition="P4 landed")), (400, _a_text())],
     "AT-REST", {}, _lacks("goal")),
    ("journal_fresh", [(400, _a_text())], "WAKE-LOST", {"journal": 300}, _has("journal", run_ids=["wf_0a1b2c3d-e4f"])),
    ("journal_stale", [(400, _a_text())], "AT-REST", {"journal": 3600}, _lacks("journal")),
    ("ports_and_browser_never_decide", [(500, _a_use("b1", "Bash", command="agent-browser --session fb2 open https://example.test/x")),
                                        (499, _u_result("b1", "ok")), (400, _a_text())], "AT-REST", {"hb": "extras"},
     lambda items: _has("port", detail=":3000")(items) and _has("browser", detail="fb2", url="https://example.test/x")(items)),
    ("interrupted_keeps_its_verdict", [(500, _a_use("w1", "Workflow", script="x")), (499, _u_result("w1", _WF)),
                                       (200, _a_use("t9", "Bash", command="ls"))], "INTERRUPTED", {}, _has("workflow")),
    ("teammates_named", [(400, _a_text())], "AT-REST", {"team": True}, _has("teammate", detail="builder-a")),
    ("parked_in_a_long_call_alive", [(4000, _a_use("b1", "Bash", command="bats", run_in_background=True)),
                                     (3999, _u_result("b1", _SH)), (3000, _a_use("t9", "Bash", command="make"))],
     "WAKE-LOST", {"hb": "live"}, _has("shell")),
    ("parked_in_a_long_call_unseen", [(4000, _a_use("b1", "Bash", command="bats", run_in_background=True)),
                                      (3999, _u_result("b1", _SH)), (3000, _a_use("t9", "Bash", command="make"))],
     "AT-REST", {}, _has("shell")),
    ("cold_mid_turn_alive_nothing_open", [(3000, _a_use("t9", "Bash", command="make"))], "AT-REST", {"hb": "live"},
     lambda items: not items),
]


def _selftest_wake(boot):
    import shutil
    import tempfile

    failures = 0
    home_was = os.environ.get("HOME")
    for name, recs, expected, opt, check in WAKE_CASES:
        home = tempfile.mkdtemp()
        os.environ["HOME"] = home  # _teammates reads ~/.claude*/teams: never the real one here
        try:
            pdir = os.path.join(home, ".claude", "projects", "-x")
            os.makedirs(pdir)
            path = os.path.join(pdir, _SID + ".jsonl")
            with open(path, "w") as fh:
                for off, rec in recs:
                    rec = dict(rec, timestamp=(boot - datetime.timedelta(seconds=off)).isoformat().replace("+00:00", "Z"))
                    fh.write(json.dumps(rec) + "\n")
            if "journal" in opt:
                jdir = os.path.join(pdir, _SID, "subagents", "workflows", "wf_0a1b2c3d-e4f")
                os.makedirs(jdir)
                jf = os.path.join(jdir, "journal.jsonl")
                open(jf, "w").close()
                os.utime(jf, (boot.timestamp() - opt["journal"],) * 2)
            if opt.get("team"):
                tdir = os.path.join(home, ".claude", "teams", "t1")
                os.makedirs(tdir)
                with open(os.path.join(tdir, "config.json"), "w") as fh:
                    json.dump({"name": "t1", "leadSessionId": _SID, "leadAgentId": "team-lead@t1", "members": [
                        {"name": "team-lead", "agentId": "team-lead@t1", "agentType": "team-lead"},
                        {"name": "builder-a", "agentId": "builder-a@t1", "agentType": "general-purpose"}]}, fh)
            hbdir = os.path.join(home, "hb")
            os.makedirs(hbdir)
            rows = []
            if opt.get("hb") == "watching":
                rows.append([_SID, "100", "watching", "101", _SID])
            if opt.get("hb") == "extras":
                rows += [[_SID, "100", "listen", "102", "*:3000"], [PAD, PAD, "agent-browser", "103", "fb2"],
                         [PAD, PAD, "agent-browser", "104", "someone-elses"]]
            with open(os.path.join(hbdir, "hb.bg.tsv"), "w") as fh:
                fh.writelines("\t".join(r) + "\n" for r in rows)
            if opt.get("hb") == "live":
                with open(os.path.join(hbdir, "hb.session.tsv"), "w") as fh:
                    fh.write(_SID + "\tclaude-next\tm\thigh\tauto\tbr\t100\n")
            got, why, _, items = classify_full(path, boot, 900.0, opt.get("wake", True), load_heartbeat([hbdir]), _SID)
            ok = got == expected and check(items)
        finally:
            shutil.rmtree(home, ignore_errors=True)
        failures += 0 if ok else 1
        print(f"{'ok  ' if ok else 'FAIL'} wake: {name:<32} expected={expected:<12} got={got:<12} ({why})", file=sys.stderr)
    if home_was is None:
        os.environ.pop("HOME", None)
    else:
        os.environ["HOME"] = home_was
    return failures


def _selftest():
    """Prove BOTH signals are load-bearing, with cases that must fail if either is dropped.

    settled_recently  dies if the clock alone decides (3 min out, but at rest)
    mid_turn_but_stale dies if the tail alone decides (mid-turn, but a day cold)
    settled_recently  also dies if `system`/`attachment` count as turns — the exact regression that
                      collapsed the tail signal to always-true during development.
    """
    import tempfile

    boot = datetime.datetime(2026, 1, 2, 0, 0, 0, tzinfo=datetime.timezone.utc)
    failures = 0
    for name, recs, expected in SELFTEST_CASES:
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as fh:
            for off, rtype, kind in recs:
                ts = (
                    (boot - datetime.timedelta(seconds=off))
                    .isoformat()
                    .replace("+00:00", "Z")
                )
                rec = {"type": rtype, "timestamp": ts}
                if kind == "text":
                    rec["message"] = {"content": [{"type": "text", "text": "done."}]}
                elif kind == "tool_use":
                    rec["message"] = {"content": [{"type": "tool_use", "id": "t1"}]}
                elif kind == "tool_result":
                    rec["message"] = {
                        "content": [{"type": "tool_result", "tool_use_id": "t1"}]
                    }
                fh.write(json.dumps(rec) + "\n")
            path = fh.name
        got, why, _ = classify(path, boot, 900.0)
        os.unlink(path)
        ok = got == expected
        failures += 0 if ok else 1
        print(
            f"{'ok  ' if ok else 'FAIL'} {name:<20} expected={expected:<12} got={got:<12} ({why})",
            file=sys.stderr,
        )
    anchor_failures = _selftest_anchor() + _selftest_wake(boot)
    total = len(SELFTEST_CASES) + 4 + len(WAKE_CASES)
    passed = total - failures - anchor_failures
    print(
        f"cc-resume-classify --selftest: {passed}/{total} passed",
        file=sys.stderr,
    )
    return 1 if (failures or anchor_failures) else 0


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument(
        "--boot-epoch",
        type=int,
        default=None,
        help="crash anchor in epoch seconds (default: kern.boottime)",
    )
    ap.add_argument(
        "--no-terminal-crash",
        action="store_true",
        help="do not consider terminal-emulator crash reports when choosing the anchor; use "
        "kern.boottime alone (the pre-2026-09-16 behaviour)",
    )
    ap.add_argument(
        "--selftest",
        action="store_true",
        help="run the built-in classification cases and exit",
    )
    ap.add_argument(
        "--alive-window",
        type=float,
        default=900.0,
        help="seconds before the crash within which a session counts as ALIVE at the crash "
        "(default 900). Widening it makes the tool nudge more; narrowing it makes it quieter. "
        "The measured 2026-08-24 batch separates cleanly at any value in 5..27 min.",
    )
    ap.add_argument(
        "--wake-lost",
        action="store_true",
        help="emit WAKE-LOST for a session at rest that had async work open at the cut "
        "(default: such a session stays AT-REST, the pre-W3 output)",
    )
    ap.add_argument(
        "--lost-json",
        default=None,
        metavar="PATH",
        help="write {sid: {verdict, items}} for every row: what died with the old process",
    )
    ap.add_argument(
        "--hb-dir",
        action="append",
        default=[],
        metavar="DIR",
        help="a restore-heartbeat directory (hb.bg.tsv); repeatable",
    )
    ap.add_argument(
        "--explain",
        action="store_true",
        help="also print the evidence and the session's last words to stderr",
    )
    args = ap.parse_args()

    if args.selftest:
        return _selftest()

    boot = args.boot_epoch if args.boot_epoch is not None else boot_epoch_default()
    crash_src = "kern.boottime"
    if args.boot_epoch is not None:
        crash_src = "--boot-epoch (operator-supplied)"
    elif boot is not None and not args.no_terminal_crash:
        # A terminal-emulator crash kills every pane without touching boottime — see the block
        # above terminal_crash_epoch(). Prefer it whenever it is NEWER than the boot we found.
        hit = terminal_crash_epoch(boot)
        if hit is not None:
            boot, crash_src = int(hit[0]), f"terminal crash report {hit[1]}"
    if boot is None:
        print(
            "cc-resume-classify: kern.boottime unreadable and no --boot-epoch — refusing to "
            "guess (every row would be UNKNOWN anyway)",
            file=sys.stderr,
        )
        return 2
    boot_dt = datetime.datetime.fromtimestamp(boot, tz=datetime.timezone.utc)
    if args.explain:
        print(
            f"cc-resume-classify: crash anchor {boot_dt.isoformat()}  [{crash_src}]",
            file=sys.stderr,
        )

    counts = {"INTERRUPTED": 0, "AT-REST": 0, "UNKNOWN": 0, "WAKE-LOST": 0}
    hb = load_heartbeat(args.hb_dir)
    lost_all = {}
    notfound = 0  # UNKNOWNs caused by a transcript lookup MISS, not by an unreadable transcript
    nopre = 0  # rows with NO records before the anchor -> the anchor predates the session entirely
    for raw in sys.stdin:
        row = raw.rstrip("\n")
        if not row or row.startswith("#"):
            continue
        cols = row.split("\t")
        if len(cols) < 4:
            print(
                f"cc-resume-classify: row has {len(cols)} tab-separated fields, need >=4: {row}",
                file=sys.stderr,
            )
            return 2
        sid = cols[1]
        path = find_transcript(sid)
        if path is None:
            notfound += 1
            verdict, why, last, lost = (
                "UNKNOWN",
                "transcript not found in any account store",
                "",
                [],
            )
        else:
            verdict, why, last, lost = classify_full(
                path, boot_dt, args.alive_window, args.wake_lost, hb, sid
            )
        lost_all[sid] = {"verdict": verdict, "why": why, "items": lost}
        if path is not None:
            if why == "no pre-crash records":
                nopre += 1
        counts[verdict] += 1
        print(row + "\t" + verdict)
        if args.explain:
            label = cols[2].rstrip("/").split("/")[-1] or cols[2]
            print(f"  {label:<28} {sid[:8]}  {verdict:<12} ({why})", file=sys.stderr)
            if verdict == "AT-REST" and last.strip():
                tail = " ".join(last.strip().split())[-160:]
                print(f"      came to rest saying: ...{tail}", file=sys.stderr)

    if args.lost_json:
        tmp = args.lost_json + ".tmp"
        try:
            with open(tmp, "w") as fh:
                json.dump({"anchor": boot, "sessions": lost_all}, fh, indent=1, sort_keys=True)
                fh.write("\n")
            os.replace(tmp, args.lost_json)
        except OSError as exc:
            print(f"cc-resume-classify: could not write --lost-json {args.lost_json}: {exc}", file=sys.stderr)

    wake = f"{counts['WAKE-LOST']} WAKE-LOST (re-engage: work died with the process), " if args.wake_lost else ""
    print(
        f"cc-resume-classify: {counts['INTERRUPTED']} INTERRUPTED (re-engage), {wake}"
        f"{counts['AT-REST']} AT-REST (restore, do NOT nudge), "
        f"{counts['UNKNOWN']} UNKNOWN (treat as AT-REST)",
        file=sys.stderr,
    )

    # ── TOTAL-MISS ALARM (2026-08-25). The fail-safe polarity above has one blind spot, and it
    # cost a whole recovery: if EVERY row misses the transcript lookup, every verdict is UNKNOWN,
    # every caller correctly treats UNKNOWN as AT-REST, and the run nudges NOBODY — which is
    # exactly what a healthy planned-restart recovery looks like ("expect few or zero nudges").
    # So a broken instrument is indistinguishable from a quiet fleet, and stays broken forever.
    # Measured: this file shipped reading the SID from field 3 while lr-select.py emits it in
    # field 2, so it looked up the WORKTREE PATH as a session id — 164 rows in, 164/164 UNKNOWN,
    # 0 nudges, no error. A uniform miss indicts the INSTRUMENT, never the population: a real
    # fleet always has some readable transcript. Say so, and exit nonzero so a caller that checks
    # its status can tell "nothing to nudge" apart from "I could not read anything".
    # ── ANCHOR-TOO-OLD ALARM (2026-09-16), the sibling of the total-miss alarm below. A row with
    # NO records before the anchor did not exist yet when the anchor fired, so it cannot be a
    # casualty of it. One such row is ordinary; a MAJORITY of them means the anchor predates the
    # fleet, i.e. we are measuring the wrong event — and because every "no pre-crash records" row
    # is UNKNOWN, and UNKNOWN defaults to AT-REST, the whole run goes quiet and reads as a healthy
    # recovery. Same unfalsifiable shape as the miss alarm: a broken instrument that looks calm.
    # Measured 2026-09-16: 3 of 4 rows, anchored on a boottime 3h45m before the kitty SIGSEGV that
    # actually killed the panes. This says so instead of going quiet.
    total = sum(counts.values())
    if total and nopre * 2 >= total:
        print(
            f"cc-resume-classify: ANCHOR LOOKS TOO OLD — {nopre} of {total} row(s) have no "
            f"records at all before {boot_dt.isoformat()} ({crash_src}), so they began AFTER it "
            "and cannot be casualties of it. Every one of those is UNKNOWN, which callers treat "
            "as AT-REST, so this run may nudge nobody and still look healthy. If a terminal "
            "emulator crashed rather than the box rebooting, pass that moment as --boot-epoch "
            "(the .ips under ~/Library/Logs/DiagnosticReports carries it).",
            file=sys.stderr,
        )

    if total and notfound == total:
        print(
            f"cc-resume-classify: INSTRUMENT FAILURE — all {total} row(s) missed the transcript "
            "lookup, so every verdict is UNKNOWN and this run would nudge NOBODY. A uniform miss "
            "is never a property of the fleet. Check the input field order FIRST: this tool wants "
            "account<TAB>session-id<TAB>worktree<TAB>branch, i.e. lr-select.py's own "
            "acct/sid/cwd/branch, and reads the SID from FIELD 2.",
            file=sys.stderr,
        )
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
