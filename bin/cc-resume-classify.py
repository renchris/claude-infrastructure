#!/usr/bin/env python3
"""cc-resume-classify.py — decide, per recovered session, whether it was INTERRUPTED by the crash
or was already AT-REST when the power died. Only the interrupted ones may be re-engaged.

    Usage:  ... | cc-resume-classify.py [--boot-epoch SECS] [--explain]
                      [--wake-lost] [--lost-json PATH] [--hb-dir DIR]...
            reads lr-select.py's TSV on stdin:  account <TAB> session-id <TAB> worktree <TAB> branch
            (THE SID IS FIELD 2. lr-select.py:434 emits acct/sid/cwd/branch and boot-resume.sh:293
             reads it back in that order. This file and cc-resume-layout.sh both shipped reading
             field 3 as the sid, which is the WORKTREE PATH — see THE FIELD-ORDER TRAP below.)
            writes the same rows with one more LAST column: INTERRUPTED | AT-REST | UNKNOWN | RETIRED
            (a row may carry more than 4 columns — the W3 row contract has 11 — and the verdict
             is always appended last, so readers take $NF)
            --wake-lost adds a fourth verdict, WAKE-LOST: at rest, but with work open at the cut
            that died with the process (see ASYNC WORK OPEN AT THE CUT; a watcher the session
            armed itself is listed as lost and never decides the verdict), or with a reason to
            wake that the restart did not kill (see REASONS TO WAKE). Without the flag the
            output is byte-identical to before it existed, except RETIRED. --lost-json writes what
            each session lost; --hb-dir names a restore-heartbeat directory whose hb.bg.tsv says
            what was live. RETIRED (2026-10-21) is a session that was closing itself at the cut.
            --owner SID names the session that ran the reboot prep (alarm-reboot-prep.sh's
            reboot-<date>.owner); --prep-start and --backlog-json are seams for the promise and
            unblocked kinds (default: the newest reboot-*.start, and `cc-backlog list --blocked --json`).

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
import signal
import subprocess
import sys
import time

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


# ── WHAT THE SHUTDOWN ITSELF WRITES (2026-10-21) ──────────────────────────────────────────────────
# The cut used to be the last heartbeat tick, 9.5 min before the real shutdown, so nothing written at
# the shutdown was ever read. Read up to the real cut and the shutdown's own records come into view:
# Claude Code, killed, enqueues a <task-notification> for every background task it was running and
# writes "Exit code 137/143" for a foreground call it was inside. Measured on boot-1792609590: those
# records sit 0.1-0.5 s before the tombstone burst, and they made 551eb39b and b81018a2 read "0.0 min
# idle". Taken as turns, every stale session that had any background task would read alive and be
# nudged, which is the 2026-08-24 defect. So a queue-operation record never dates a turn, and a user
# record in the last SHUTDOWN_BURST_S before the cut that is only a task-notification or only a
# 137/143 exit is the shutdown talking, not the session. It closes nothing either: that task died
# with the process, which is what the lost items are for. The window is narrow on purpose:
# 95d2333c's genuine hand-back prompt landed 6 s before the cut, and it is an agent-message.
SHUTDOWN_BURST_S = 10
_KILLED_RE = re.compile(r"\bExit code 1(?:37|43)\b")
# Claude Code's own notice on resume ("...didn't finish before the previous session ended"), in its
# single-task and __orphan_summary__ forms. It rides a user record but asks for nothing: counted as a
# turn it made a session that was waiting read mid-turn (43e6eb4b, 4da72f17 and 509e3aad were saved
# only by being stale).
_RESUME_NOTICE_RE = re.compile(r"<status>stopped</status>.*didn't finish before the previous session ended", re.S)
# A pending call to retire the pane: the session had finished and was closing itself when the power
# went (5d19ef73, boot-1792609590). Relaunching it, nudged or idle, undoes that.
_SELF_CLOSE_RE = re.compile(r"handoff-fire\.sh['\"]?\s+self-close\b")


def _user_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(i.get("text") or "" for i in content if isinstance(i, dict) and i.get("type") == "text")
    return ""


def _shutdown_artifact(rec, when, boot_dt):
    """A record the shutdown wrote: a queue-operation in the burst, or a user record in it that is
    only a task-notification or only a killed call's result."""
    if (boot_dt - when).total_seconds() > SHUTDOWN_BURST_S:
        return False
    if rec.get("type") == "queue-operation":
        return True
    if rec.get("type") != "user":
        return False
    content = (rec.get("message") or {}).get("content")
    if _user_text(content).lstrip().startswith("<task-notification>"):
        return True
    if not isinstance(content, list):
        return False
    items = [i for i in content if isinstance(i, dict)]
    return bool(items) and all(
        i.get("type") == "tool_result" and _KILLED_RE.search(_text_of(i.get("content"))) for i in items
    )


def _resume_notice(rec):
    return rec.get("type") == "user" and bool(
        _RESUME_NOTICE_RE.search(_user_text((rec.get("message") or {}).get("content")))
    )


# ── PROMISE: the session said what it would do once the Mac came back (2026-10-21) ────────────────
# 551eb39b's last words before the cut: "After you log in, it reopens with the others, and I'll
# confirm the Mac is on 15.8.1, check how many sessions came back, and run the leak test." It was
# restored at rest, told nothing, and sat until the operator typed. A promise is narrow on purpose:
# the LAST thing the assistant said, in a completed turn, spoken after the reboot prep started (so it
# is about this restart), with a first-person future verb and a restart word in one sentence, and
# nothing in that sentence handing the choice back ("if you want", "shall I"). A question waits for
# the operator; prompting it is the 2026-08-24 defect.
_FUTURE_RE = re.compile(r"\b(?:I(?:'|’)ll|I will|I(?:'|’)m going to|I am going to)\b", re.I)
_RESTART_RE = re.compile(
    r"\b(?:restart\w*|reboot\w*|log(?:s|ged)? (?:back )?in|login|reopen\w*|comes? back|comes? up|"
    r"back up|resum\w*|boot\w*)\b",
    re.I,
)
_HANDBACK_RE = re.compile(r"\b(?:if you(?:'d)? (?:want|like|prefer)|say the word|want me to|shall I|should I)\b", re.I)
PREP_WINDOW_S = 12 * 3600


def _promise(text):
    """The promising sentence of the assistant's last words, else ""."""
    for sent in re.split(r"(?<=[.!?])\s+|\n+", text or ""):
        if _FUTURE_RE.search(sent) and _RESTART_RE.search(sent) and not _HANDBACK_RE.search(sent):
            return " ".join(sent.split())[:240]
    return ""


def prep_start_default(boot):
    """Epoch of the newest reboot prep (alarm-reboot-prep.sh's reboot-<date>.start, epoch first) in
    the 12 h before the cut, else None."""
    d = os.environ.get("CC_REBOOT_PREP_DIR") or os.path.expanduser("~/.claude/autonomy")
    best = None
    for path in glob.glob(os.path.join(d, "reboot-*.start")):
        try:
            with open(path, errors="replace") as fh:
                ep = int((fh.readline().split() or ["x"])[0])
        except (OSError, ValueError):
            continue
        if ep <= boot and boot - ep <= PREP_WINDOW_S and (best is None or ep > best):
            best = ep
    return best


def _intent_record(sid, boot_dt, last_start):
    """handoff-fire.sh self-close's terminal-intent record, ~/.claude/autonomy/self-close-intent/<sid>
    (removed on every abort path). Honoured only if the process alive at the cut wrote it: not older
    than the session's last start, and not newer than the cut."""
    if not sid:
        return False
    d = os.environ.get("CC_SELF_CLOSE_INTENT_DIR") or os.path.expanduser("~/.claude/autonomy/self-close-intent")
    try:
        mt = os.stat(os.path.join(d, sid)).st_mtime
    except OSError:
        return False
    if mt > boot_dt.timestamp() + 60:
        return False
    return last_start is None or mt >= last_start.timestamp()


def classify_full(path, boot_dt, alive_window, wake_lost=False, hb=None, sid="", extra=None, prep_start=None):
    """-> (verdict, why, last_assistant_text, lost_items)

    Only records strictly BEFORE boot are considered: a resumed session appends to the same
    transcript, so anything at or after boot is the recovery itself, not the pre-crash state.
    Reading past boot is how a naive pass concludes every session was mid-turn.

    lost_items is what died with the old process (see ASYNC WORK below), plus the reasons to wake
    that did not die with it (REASONS TO WAKE): `extra` carries the ones main() found outside the
    transcript, and a promise is read here, bounded by `prep_start` (epoch). With wake_lost, a
    session at rest that had either is WAKE-LOST instead of AT-REST.

    RETIRED outranks every other verdict and needs no flag: a session closing itself at the cut (a
    pending handoff-fire.sh self-close call, or its terminal-intent record) is not relaunched.
    """
    pending = set()  # tool_use ids awaiting a tool_result
    scan = AsyncScan()
    last_text = ""
    last_text_ts = None
    saw_any = False
    last_ts = None  # last pre-crash TURN record -> the alive-at-crash half (the last real turn)
    last_any = None  # last pre-crash record of any other kind, for a transcript with no turn yet
    last_start = None  # the newest SessionStart:startup/resume: the process that was alive at the cut
    after_speech = 0  # content records since the assistant last actually spoke
    try:
        fh = open(path, errors="replace")
    except OSError as exc:
        return "UNKNOWN", f"unreadable: {exc}", "", []
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
            role = rec.get("type")
            if _shutdown_artifact(rec, when, boot_dt) or _resume_notice(rec):
                continue
            if role != "queue-operation":
                last_any = when
            att = rec.get("attachment") if role == "attachment" else None
            if isinstance(att, dict) and att.get("hookName") in ("SessionStart:startup", "SessionStart:resume"):
                last_start = when
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
            last_ts = when
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
                        last_text_ts = when
                        spoke = True
            elif isinstance(content, str) and role == "assistant":
                last_text = content
                last_text_ts = when
                spoke = True
            after_speech = 0 if spoke else after_speech + 1

    last_ts = last_ts or last_any
    if not saw_any or last_ts is None:
        return "UNKNOWN", "no pre-crash records", "", []
    lost = scan.lost(path, boot_dt, pending, hb or {}, sid)

    closing = [t for t in pending if _SELF_CLOSE_RE.search(scan.bash.get(t, ""))]
    if closing or _intent_record(sid, boot_dt, last_start):
        how = "a handoff-fire.sh self-close call was pending" if closing else "its self-close terminal-intent record"
        return "RETIRED", f"closing itself at the cut ({how})", last_text, lost

    lost = lost + list(extra or [])
    if not pending and not after_speech and prep_start is not None and last_text_ts is not None:
        said = _promise(last_text) if last_text_ts.timestamp() >= prep_start else ""
        if said:
            lost.append({"kind": "promise", "detail": said, "at": last_text_ts.isoformat()})

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
    if mid_turn and wake_lost and any(i["kind"] == "owner" for i in open_work):
        # The session that ran the reboot prep owns its follow-up however cold its turn looks.
        return (
            "WAKE-LOST",
            f"mid-turn and {_ago(idle)} idle, but it ran the reboot prep ({tail_why})",
            last_text,
            lost,
        )
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
#
# A watcher the session armed itself is listed too, and since W3 P4b it does not decide the verdict
# either. Measured 2026-10-05 on the live fleet: 12 of 20 sessions read WAKE-LOST, 6 of them on a
# self-armed cc-await-ping and nothing else. The same hook that makes the `.watching` pid worthless
# as evidence makes the loss harmless: the resume's SessionStart re-arms a watcher without a turn,
# so a prompt for it alone spends a turn and buys nothing. It stays in the lost items, where the
# restore note says to re-arm it unless a /goal is live; any other item beside it still decides.
#
# REASONS TO WAKE (2026-10-21). Four kinds do not die with the process and still decide the verdict,
# because a session holding one sat idle after the 2026-10-21 restart until the operator typed:
#   - owner      the session that ran the reboot prep (--owner, from reboot-<date>.owner): it promised
#                the post-restart checks, and nobody else will run them (551eb39b);
#   - promise    its last words, after the prep started, say what it will do once the Mac is back;
#   - unblocked  a blocked backlog row it filed carries an `until` probe that now exits 0 (row
#                d4a65e8decc0, blocked on "macOS 15.8.1 installed");
#   - mail       unread lines in its own inbox, i.e. the pane mail boot-resume carried to it with
#                mailbox_migrate (9240c6a9's "W2 landed" reports sat in pane 31's box, then got
#                sealed). cc-await-ping's WAKE-PATH lines and boot-resume's own notes are not mail.
# The restore prompt quotes the reason (scripts/lib/restore-note.sh rn_reason_phrase).
WAKE_KINDS = ("shell", "agent", "workflow", "monitor", "journal", "goal", "ship", "owner", "promise", "unblocked", "mail")
PAD = "\x1f"  # boot-resume.sh's TSV_PAD / restore-heartbeat.sh's HB_PAD: an empty cell
UNTIL_TIMEOUT_S = 10.0  # every `until` probe of one run shares this bound
BACKLOG_LIST_TIMEOUT_S = 30
MAIL_IGNORE = ("cc-await-ping", "boot-resume")
_MBX_FWD_RE = re.compile(r"^\d{4}-\d\d-\d\dT[0-9:]+\S*\s+\[forwarded:[^\]]*\]\s")
_MBX_LINE_RE = re.compile(r"^\d{4}-\d\d-\d\dT[0-9:]+\S*\s+\[([^\]]*)\]\s?(.*)$")
_MBX_ENVELOPE_RE = re.compile(r"^\[@v1;[^\]]*\]\s*")
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


def _mbx_cursor(path):
    try:
        with open(path, errors="replace") as fh:
            return int((fh.read().split() or ["0"])[0])
    except (OSError, ValueError):
        return 0


def _mail_items(sid):
    """Unread mail in the session's own inbox (hooks/lib/mailbox-pending.sh's cursors: lines past
    .acked, .acked clamped to .seen, a .seen past EOF reads 0). A line is "<ISO> [<from>] <msg>";
    mailbox_migrate prefixes "<ISO> [forwarded:<8>] ", possibly more than once, so the sender is the
    innermost one. Unparseable lines are not counted."""
    if not sid or "/" in sid:
        return []
    d = os.environ.get("CC_MAILBOX_DIR") or os.path.expanduser("~/.claude/mailbox")
    try:
        with open(os.path.join(d, sid + ".md"), errors="replace") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return []
    if lines and lines[-1] == "":
        lines.pop()  # grep -c '' counts an unterminated last line, never the empty string after a newline
    seen = _mbx_cursor(os.path.join(d, sid + ".seen"))
    seen = 0 if seen > len(lines) else seen
    acked = min(_mbx_cursor(os.path.join(d, sid + ".acked")), seen)
    mail = []
    for ln in lines[acked:]:
        m = _MBX_FWD_RE.match(ln)
        while m:
            ln = ln[m.end():]
            m = _MBX_FWD_RE.match(ln)
        m = _MBX_LINE_RE.match(ln)
        if m and m.group(1) not in MAIL_IGNORE:
            mail.append((m.group(1), _MBX_ENVELOPE_RE.sub("", m.group(2))))
    if not mail:
        return []
    sender, msg = mail[-1]
    return [{"kind": "mail", "count": len(mail), "from": sender, "detail": " ".join(msg.split())[:200]}]


def _backlog_bin():
    for c in (
        os.environ.get("CC_BACKLOG_BIN"),
        os.path.join(os.path.dirname(os.path.realpath(__file__)), "cc-backlog"),
        os.path.expanduser("~/.claude/bin/cc-backlog"),
    ):
        if c and os.access(c, os.X_OK):
            return c
    return None


def unblocked_items(rows, backlog_json=None, timeout=UNTIL_TIMEOUT_S):
    """{sid: [unblocked items]} — blocked backlog rows whose `session` is one of these rows and whose
    `until` probe (cc-backlog block --until) exits 0. The probes run at once, in the row's worktree,
    under one shared bound; a probe still running at the bound is killed and counts as not yet true.
    A row without `until` gives nothing, so rows filed before the field existed keep working."""
    by_sid = {r[1]: r for r in rows}
    try:
        if backlog_json:
            with open(backlog_json, errors="replace") as fh:
                data = json.load(fh)
        else:
            ledger = os.environ.get("CC_BACKLOG_FILE") or os.path.expanduser("~/.claude/autonomy/backlog.jsonl")
            bl = _backlog_bin()
            if not os.path.exists(ledger) or not bl:
                return {}
            out = subprocess.run(
                [bl, "list", "--blocked", "--json"],
                capture_output=True,
                text=True,
                timeout=BACKLOG_LIST_TIMEOUT_S,
                stdin=subprocess.DEVNULL,
            ).stdout
            data = json.loads(out or "[]")
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f"cc-resume-classify: backlog unreadable, no unblocked items: {exc}", file=sys.stderr)
        return {}
    procs = []
    for r in data if isinstance(data, list) else []:
        if not isinstance(r, dict) or not r.get("until") or r.get("session") not in by_sid:
            continue
        if r.get("status", "blocked") != "blocked":
            continue
        cwd = by_sid[r["session"]][2]
        try:
            p = subprocess.Popen(
                ["/bin/bash", "-c", str(r["until"])],
                cwd=cwd if os.path.isdir(cwd) else os.path.expanduser("~"),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError:
            continue
        procs.append((r, p))
    deadline = time.monotonic() + timeout
    found = {}
    for r, p in procs:
        try:
            rc = p.wait(timeout=max(0.0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            p.wait()
            rc = None
        if rc == 0:
            found.setdefault(r["session"], []).append(
                {"kind": "unblocked", "id": str(r.get("id") or "?"), "detail": " ".join(str(r.get("title") or "").split())[:160],
                 "until": str(r["until"])[:200]}
            )
    return found


def reason_items(sid, owners, unblocked):
    """The reasons to wake that main() finds outside the transcript: owner, mail, unblocked."""
    items = [{"kind": "owner", "detail": "this session ran the reboot prep"}] if sid in owners else []
    return items + _mail_items(sid) + list(unblocked.get(sid, []))


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


def _a_say(text):
    return {"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}}


def _u_say(text):
    return {"type": "user", "message": {"content": text}}


def _q_notif(tid, task, status="killed"):
    return {"type": "queue-operation", "operation": "enqueue", "content": "<task-notification>\n<task-id>" + task
            + "</task-id>\n<tool-use-id>" + tid + "</tool-use-id>\n<status>" + status + "</status>\n</task-notification>"}


def _u_stopped(orphan=False):
    ids = "<task-id>b1</task-id>\n<task-id>b2</task-id>\n<task-id>__orphan_summary__:shell</task-id>\n" if orphan \
        else "<task-id>b1</task-id>\n<tool-use-id>toolu_1</tool-use-id>\n"
    what = "2 background shell command tasks didn't" if orphan else "Background shell command didn't"
    return _u_say("<task-notification>\n" + ids + "<status>stopped</status>\n<summary>" + what
                  + " finish before the previous session ended</summary>\n</task-notification>")


_WF = "Workflow launched in background. Task ID: wtcaytsys\nTranscript dir: /p/s/subagents/workflows/wf_d4508a0a-f86"
_MON = "Monitor started (task bv3wgaxut, expires in 30m unless the source ends first)"
_SH = "Command running in background with ID: bzrbwj020"
_AG = "Async agent launched successfully.\nagentId: a81e9ac94a5566598"
_SID = "5e1f7e57-0000-4000-8000-000000000001"
_PROMISE = "This session closes too. After you log in, it reopens with the others, and I'll confirm the Mac is on 15.8.1 and run the leak test."
_SELF_CLOSE = "$HOME/.claude/scripts/handoff-fire.sh self-close --terminal"
_ROW = {"id": "d4a65e8decc0", "status": "blocked", "session": _SID, "title": "leak test after 15.8.1"}
_TS = "2026-01-01T23:50:00-0600"


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
                                      (400, _a_text())], "AT-REST", {"hb": "watching"}, _has("watcher", alive_at_tick=True)),
    ("watcher_beside_a_lost_workflow", [(600, _a_use("b1", "Bash", command="cc-await-ping --timeout 3300",
                                                     run_in_background=True)), (599, _u_result("b1", _SH)),
                                        (500, _a_use("w1", "Workflow", script="x")), (499, _u_result("w1", _WF)),
                                        (400, _a_text())], "WAKE-LOST", {"hb": "watching"},
     lambda items: _has("watcher", alive_at_tick=True)(items) and _has("workflow", task_id="wtcaytsys")(items)),
    ("watcher_only_parked_in_a_long_call", [(4000, _a_use("b1", "Bash", command="cc-await-ping --timeout 3300",
                                                          run_in_background=True)), (3999, _u_result("b1", _SH)),
                                            (3000, _a_use("t9", "Bash", command="make"))],
     "AT-REST", {"hb": "live"}, _has("watcher")),
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
    # ── 2026-10-21: read to the real cut, and what the shutdown itself writes there ──
    ("speech_after_the_last_tick_decides", [(720, _a_use("t9", "Bash", command="make")), (700, _u_result("t9", "ok")),
                                            (300, _a_text())], "AT-REST", {"hb": "live"}, lambda items: not items),
    ("shutdown_notification_is_not_alive", [(3000, _a_use("t9", "Bash", command="make")), (1, _q_notif("b7", "bx7")),
                                            (1, _u_notif("b7", "bx7", "killed"))], "AT-REST", {}, lambda items: not items),
    ("killed_call_result_is_not_alive", [(3000, _a_use("t9", "Bash", command="sleep 9999")),
                                         (1, _u_result("t9", "Exit code 143"))], "AT-REST", {}, lambda items: not items),
    ("killed_call_mid_wait_is_interrupted", [(500, _a_use("t9", "Bash", command="timeout 585 tail -F x")),
                                             (1, _u_result("t9", "Exit code 137"))], "INTERRUPTED", {}, lambda items: True),
    ("notification_before_the_burst_is_a_turn", [(600, _a_text()), (20, _u_notif("x1", "bq9"))], "INTERRUPTED", {},
     lambda items: True),
    ("housekeeping_after_a_cold_turn_is_not_alive", [(3000, _a_use("t9", "Bash", command="make")),
                                                     (100, _att(type="total_tokens_reminder"))], "AT-REST", {},
     lambda items: not items),
    ("handback_just_before_the_cut_is_a_turn", [(60, _a_text()), (6, _u_say("Another Claude session sent a message: "
                                                "<agent-message from=\"a1\"> [Subagent hand-back] report</agent-message>"))],
     "INTERRUPTED", {}, lambda items: True),
    ("shell_killed_by_the_shutdown_is_lost", [(500, _a_use("b1", "Bash", command="bats tests/x.bats", run_in_background=True)),
                                              (499, _u_result("b1", _SH)), (400, _a_text()), (1, _q_notif("b1", "bzrbwj020")),
                                              (1, _u_notif("b1", "bzrbwj020", "killed"))], "WAKE-LOST", {}, _has("shell")),
    ("resume_notice_is_not_a_turn", [(600, _a_text()), (300, _u_stopped())], "AT-REST", {}, lambda items: True),
    ("orphan_summary_notice_is_not_a_turn", [(600, _a_text()), (300, _u_stopped(orphan=True))], "AT-REST", {},
     lambda items: True),
    ("a_finished_task_notification_is_a_turn", [(600, _a_text()), (300, _u_notif("x1", "bq9"))], "INTERRUPTED", {},
     lambda items: True),
    # ── RETIRED ──
    ("pending_self_close_is_retired", [(300, _a_say("Done. Retiring this pane.")), (240, _a_use("s1", "Bash", command=_SELF_CLOSE))],
     "RETIRED", {}, lambda items: True),
    ("refused_self_close_is_not_retired", [(300, _a_text()), (240, _a_use("s1", "Bash", command=_SELF_CLOSE)),
                                           (230, _u_result("s1", "self-close: refused, the tree is dirty")), (200, _a_text())],
     "AT-REST", {}, lambda items: True),
    ("terminal_intent_record_is_retired", [(400, _a_text())], "RETIRED", {"intent": 100}, lambda items: True),
    ("intent_record_of_an_earlier_process_is_ignored", [(3000, _att(type="hook_success", hookName="SessionStart:resume")),
                                                        (400, _a_text())], "AT-REST", {"intent": 5000}, lambda items: True),
    ("retired_outranks_the_owner", [(300, _a_text()), (240, _a_use("s1", "Bash", command=_SELF_CLOSE))], "RETIRED",
     {"owner": True}, lambda items: True),
    # ── REASONS TO WAKE: owner, promise, unblocked, mail ──
    ("owner_at_rest_is_woken", [(400, _a_text())], "WAKE-LOST", {"owner": True}, _has("owner")),
    ("owner_cold_mid_turn_is_woken", [(3000, _a_use("t9", "Bash", command="make"))], "WAKE-LOST", {"owner": True}, _has("owner")),
    ("owner_without_the_flag", [(400, _a_text())], "AT-REST", {"owner": True, "wake": False}, lambda items: True),
    ("promise_after_the_prep_is_woken", [(300, _a_say(_PROMISE))], "WAKE-LOST", {"prep": 3600},
     lambda items: any(i["kind"] == "promise" and "I'll confirm the Mac" in i["detail"] for i in items)),
    ("promise_before_the_prep_does_not_fire", [(1000, _a_say(_PROMISE))], "AT-REST", {"prep": 600}, _lacks("promise")),
    ("promise_without_a_prep_does_not_fire", [(300, _a_say(_PROMISE))], "AT-REST", {}, _lacks("promise")),
    ("promise_handed_back_is_a_question", [(300, _a_say("If you want, after the restart I'll run the leak test."))],
     "AT-REST", {"prep": 3600}, _lacks("promise")),
    ("restart_word_without_a_promise", [(300, _a_say("Done. Restart whenever you like."))], "AT-REST", {"prep": 3600},
     _lacks("promise")),
    ("unblocked_probe_passes", [(400, _a_text())], "WAKE-LOST", {"backlog": [dict(_ROW, until="true")]},
     _has("unblocked", id="d4a65e8decc0")),
    ("unblocked_probe_fails", [(400, _a_text())], "AT-REST", {"backlog": [dict(_ROW, until="false")]}, _lacks("unblocked")),
    ("unblocked_row_of_another_session", [(400, _a_text())], "AT-REST",
     {"backlog": [dict(_ROW, until="true", session="other")]}, _lacks("unblocked")),
    ("unblocked_row_without_until", [(400, _a_text())], "AT-REST", {"backlog": [_ROW]}, _lacks("unblocked")),
    ("unblocked_probe_that_hangs_is_bounded", [(400, _a_text())], "AT-REST",
     {"backlog": [dict(_ROW, until="sleep 30")], "until_timeout": 1.0}, _lacks("unblocked")),
    ("unread_handoff_ping_wakes", [(400, _a_text())], "WAKE-LOST",
     {"mail": [_TS + " [macapp-extract-55] [@v1;pane=55;sid=e80b61f4;title=x] HANDOFF-PING fire-x: DONE — W2 landed fa03894"]},
     lambda items: any(i["kind"] == "mail" and i["count"] == 1 and i["detail"].startswith("HANDOFF-PING") for i in items)),
    ("forwarded_handoff_ping_wakes", [(400, _a_text())], "WAKE-LOST",
     {"mail": [_TS + " [forwarded:31] " + _TS + " [peer-7] HANDOFF-PING fire-y: DONE"]},
     _has("mail", **{"from": "peer-7"})),
    ("wake_path_and_restore_lines_are_not_mail", [(400, _a_text())], "AT-REST",
     {"mail": [_TS + " [cc-await-ping] WAKE-PATH-DOWN: the watcher armed for [31] was TERMINATED",
               _TS + " [boot-resume] [restore] The Mac rebooted at 13:59."]}, _lacks("mail")),
    ("forwarded_wake_path_line_is_not_mail", [(400, _a_text())], "AT-REST",
     {"mail": [_TS + " [forwarded:aaaaaaaa] " + _TS + " [cc-await-ping] WAKE-PATH-CLASS: verdict=B-BENIGN"]}, _lacks("mail")),
    ("acked_mail_is_not_unread", [(400, _a_text())], "AT-REST", {"mail": [_TS + " [peer-7] HANDOFF-PING: DONE"], "acked": 1},
     _lacks("mail")),
]


def _selftest_wake(boot):
    import shutil
    import tempfile

    failures = 0
    seams = ("HOME", "CC_MAILBOX_DIR", "CC_SELF_CLOSE_INTENT_DIR", "CC_REBOOT_PREP_DIR", "CC_BACKLOG_FILE")
    env_was = {k: os.environ.get(k) for k in seams}
    for name, recs, expected, opt, check in WAKE_CASES:
        home = tempfile.mkdtemp()
        os.environ["HOME"] = home  # _teammates reads ~/.claude*/teams: never the real one here
        for k in seams[1:]:
            os.environ.pop(k, None)  # every store under the fixture HOME, whatever the caller exported
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
            if "intent" in opt:
                idir = os.path.join(home, ".claude", "autonomy", "self-close-intent")
                os.makedirs(idir)
                open(os.path.join(idir, _SID), "w").close()
                os.utime(os.path.join(idir, _SID), (boot.timestamp() - opt["intent"],) * 2)
            if "mail" in opt:
                mdir = os.path.join(home, ".claude", "mailbox")
                os.makedirs(mdir)
                with open(os.path.join(mdir, _SID + ".md"), "w") as fh:
                    fh.writelines(ln + "\n" for ln in opt["mail"])
                for cur in ("seen", "acked"):
                    with open(os.path.join(mdir, f"{_SID}.{cur}"), "w") as fh:
                        fh.write(f"{opt.get('acked', 0)}\n")
            unblocked, took = {}, 0.0
            if "backlog" in opt:
                bj = os.path.join(home, "blocked.json")
                with open(bj, "w") as fh:
                    json.dump(opt["backlog"], fh)
                t0 = time.monotonic()
                unblocked = unblocked_items([["next", _SID, home, "br"]], bj, opt.get("until_timeout", UNTIL_TIMEOUT_S))
                took = time.monotonic() - t0
            extra = reason_items(_SID, {_SID} if opt.get("owner") else set(), unblocked)
            prep = boot.timestamp() - opt["prep"] if "prep" in opt else None
            got, why, _, items = classify_full(path, boot, 900.0, opt.get("wake", True), load_heartbeat([hbdir]), _SID,
                                               extra, prep)
            ok = got == expected and check(items) and took < opt.get("until_timeout", UNTIL_TIMEOUT_S) + 3
        finally:
            shutil.rmtree(home, ignore_errors=True)
        failures += 0 if ok else 1
        print(f"{'ok  ' if ok else 'FAIL'} wake: {name:<32} expected={expected:<12} got={got:<12} ({why})", file=sys.stderr)
    for k, v in env_was.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    return failures


def _selftest_unreadable(boot):
    """An unreadable transcript (here a directory where the .jsonl should be) is one UNKNOWN row, never
    a crash: classify_full returned 3 values where every caller unpacks 4, the ValueError killed the
    run, and boot-resume then marked EVERY row UNKNOWN and prompted nobody."""
    import shutil
    import tempfile

    home = tempfile.mkdtemp()
    cases = []
    try:
        pdir = os.path.join(home, ".claude", "projects", "-x")
        os.makedirs(os.path.join(pdir, "bad00000-0000-4000-8000-000000000000.jsonl"))
        got = classify_full(os.path.join(pdir, "bad00000-0000-4000-8000-000000000000.jsonl"), boot, 900.0, True)
        cases.append(("a directory transcript is UNKNOWN, 4 values", len(got) == 4 and got[0] == "UNKNOWN"))
        stamp = (boot - datetime.timedelta(seconds=400)).isoformat().replace("+00:00", "Z")
        for good in ("aaaa0000-0000-4000-8000-000000000000", "cccc0000-0000-4000-8000-000000000000"):
            with open(os.path.join(pdir, good + ".jsonl"), "w") as fh:
                fh.write(json.dumps(dict(_a_text(), timestamp=stamp)) + "\n")
        rows = "".join(f"next\t{s}\t/x\tbr\n" for s in ("aaaa0000-0000-4000-8000-000000000000",
                                                        "bad00000-0000-4000-8000-000000000000",
                                                        "cccc0000-0000-4000-8000-000000000000"))
        env = {k: v for k, v in os.environ.items() if not k.startswith("CC_")}
        env["HOME"] = home
        run = subprocess.run([sys.executable, os.path.abspath(__file__), "--boot-epoch", str(int(boot.timestamp())),
                              "--wake-lost"], input=rows, capture_output=True, text=True, env=env, timeout=60)
        verdicts = [ln.split("\t")[-1] for ln in run.stdout.splitlines()]
        cases.append(("one output row per input row, exit 0", run.returncode == 0
                      and verdicts == ["AT-REST", "UNKNOWN", "AT-REST"]))
    finally:
        shutil.rmtree(home, ignore_errors=True)
    for name, ok in cases:
        print(f"{'ok  ' if ok else 'FAIL'} unreadable: {name}", file=sys.stderr)
    return sum(0 if ok else 1 for _, ok in cases), len(cases)


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
    bad_failures, bad_total = _selftest_unreadable(boot)
    anchor_failures = _selftest_anchor() + _selftest_wake(boot) + bad_failures
    total = len(SELFTEST_CASES) + 4 + len(WAKE_CASES) + bad_total
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
        "--owner",
        action="append",
        default=[],
        metavar="SID",
        help="the session that ran the reboot prep (reboot-<date>.owner): with --wake-lost it gets an "
        "owner item and is woken; repeatable",
    )
    ap.add_argument(
        "--prep-start",
        type=int,
        default=None,
        metavar="SECS",
        help="epoch the reboot prep started; a promise spoken before it never wakes "
        "(default: the newest ~/.claude/autonomy/reboot-*.start in the 12 h before the cut)",
    )
    ap.add_argument(
        "--backlog-json",
        default=None,
        metavar="PATH",
        help="read backlog rows from this file instead of `cc-backlog list --blocked --json`",
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

    counts = {"INTERRUPTED": 0, "AT-REST": 0, "UNKNOWN": 0, "WAKE-LOST": 0, "RETIRED": 0}
    hb = load_heartbeat(args.hb_dir)
    lost_all = {}
    notfound = 0  # UNKNOWNs caused by a transcript lookup MISS, not by an unreadable transcript
    nopre = 0  # rows with NO records before the anchor -> the anchor predates the session entirely
    rows = []
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
        rows.append((row, cols))
    # The reasons to wake that live outside the transcript. Only --wake-lost can act on them, so
    # without it nothing is probed and the output stays what it was.
    owners, unblocked, prep_start = set(args.owner), {}, None
    if args.wake_lost and rows:
        prep_start = args.prep_start if args.prep_start is not None else prep_start_default(boot)
        unblocked = unblocked_items([c for _, c in rows], args.backlog_json)
        if args.explain:
            when = datetime.datetime.fromtimestamp(prep_start, tz=datetime.timezone.utc).isoformat() if prep_start else "none"
            print(f"cc-resume-classify: reboot prep started {when}; owner {' '.join(sorted(owners)) or 'none'}", file=sys.stderr)
    for row, cols in rows:
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
            extra = reason_items(sid, owners, unblocked) if args.wake_lost else []
            verdict, why, last, lost = classify_full(
                path, boot_dt, args.alive_window, args.wake_lost, hb, sid, extra, prep_start
            )
        lost_all[sid] = {"verdict": verdict, "why": why, "items": lost}
        if path is not None:
            lost_all[sid]["transcript"] = path
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
    retired = f", {counts['RETIRED']} RETIRED (closing itself at the cut: do not relaunch)" if counts["RETIRED"] else ""
    print(
        f"cc-resume-classify: {counts['INTERRUPTED']} INTERRUPTED (re-engage), {wake}"
        f"{counts['AT-REST']} AT-REST (restore, do NOT nudge), "
        f"{counts['UNKNOWN']} UNKNOWN (treat as AT-REST){retired}",
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
