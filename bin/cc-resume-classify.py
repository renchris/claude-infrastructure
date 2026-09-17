#!/usr/bin/env python3
"""cc-resume-classify.py — decide, per recovered session, whether it was INTERRUPTED by the crash
or was already AT-REST when the power died. Only the interrupted ones may be re-engaged.

    Usage:  ... | cc-resume-classify.py [--boot-epoch SECS] [--explain]
            reads lr-select.py's TSV on stdin:  account <TAB> session-id <TAB> worktree <TAB> branch
            (THE SID IS FIELD 2. lr-select.py:434 emits acct/sid/cwd/branch and boot-resume.sh:293
             reads it back in that order. This file and cc-resume-layout.sh both shipped reading
             field 3 as the sid, which is the WORKTREE PATH — see THE FIELD-ORDER TRAP below.)
            writes the same rows with a 5th column: INTERRUPTED | AT-REST | UNKNOWN

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
    """-> (verdict, why, last_assistant_text)

    Only records strictly BEFORE boot are considered: a resumed session appends to the same
    transcript, so anything at or after boot is the recovery itself, not the pre-crash state.
    Reading past boot is how a naive pass concludes every session was mid-turn.
    """
    pending = set()  # tool_use ids awaiting a tool_result
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
        return "UNKNOWN", "no pre-crash records", ""

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
        )
    if mid_turn:
        # Mid-turn but long cold: it died before this crash, so this crash interrupted nothing.
        return (
            "AT-REST",
            f"mid-turn but stale — {_ago(idle)} idle, beyond the {alive_window / 60:.0f} min "
            f"alive-window ({tail_why})",
            last_text,
        )
    return "AT-REST", f"{tail_why}, {_ago(idle)} idle", last_text


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
    anchor_failures = _selftest_anchor()
    total = len(SELFTEST_CASES) + 4
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

    counts = {"INTERRUPTED": 0, "AT-REST": 0, "UNKNOWN": 0}
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
            verdict, why, last = (
                "UNKNOWN",
                "transcript not found in any account store",
                "",
            )
        else:
            verdict, why, last = classify(path, boot_dt, args.alive_window)
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

    print(
        f"cc-resume-classify: {counts['INTERRUPTED']} INTERRUPTED (re-engage), "
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
