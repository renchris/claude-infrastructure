#!/usr/bin/env python3
"""
measure-terminations.py — the SESSION-TERMINATION census, as an instrument.

WHY THIS FILE EXISTS. Ten of the twelve axes of the 2026-09-08 exhaustive-drive
wave study Stop-time mechanisms — the twelve Stop hooks, /goal, the caps, the
close-shape contracts, the SAFE-TO-CLOSE certificate. The population those
mechanisms can ever see is the sessions that REACH a Stop. Nobody had measured
that population, so every "% of Stops" in the wave was a rate over an unstated
minority and read as a rate over sessions (CRITIC.md §0, C-R7; SYNTHESIS.md
rank 14). A percentage without its denominator is the defect this instrument
fixes.

WHAT IT MEASURES. Per DEAD main-chain session in a window, the TERMINAL event,
classified into exactly one of seven classes:

    stop            the last conversational record is an assistant turn that
                    ended in text (stop_reason end_turn) — a clean Stop. The
                    ONLY class the Stop chain governs.
    self-close      the last tool call was `handoff-fire.sh self-close`
    recycle         the last tool call was `handoff-fire.sh --recycle`
    drain-recycle   the last tool call was `drain-recycle-fire.sh` (a --recycle
                    wrapper; tested BEFORE recycle for that reason)
    frozen          the last tool call was an ordinary command AND the
                    permission layer says a prompt was pending on it
    api-error       the last conversational record is an API-error assistant
                    record (isApiErrorMessage) — quota death, context wall,
                    connection loss
    killed          THE RESIDUAL, by exclusion. See the honesty note below.

HONESTY NOTE ON `killed`. There is no positive kill record on this box: no
reaper journal keys a SIGTERM to a sid. `killed` is therefore defined by
EXCLUSION — a dead session that reached no Stop, ran no retirement command, hit
no API error, and joins to no permission prompt. It is reported with a
sub-breakdown (after-stop-block / dangling-tool / after-result / after-prompt)
precisely so the residual is not opaque, and it must never be read as "N
sessions were killed". It is "N deaths this instrument cannot name".

STOP-CHAIN COVERAGE is reported separately from the class table, because it is
the number the consumer needs and it is NOT simply the `stop` count: a session
whose terminal record is a Stop-hook BLOCK did reach a Stop and did feed the
Stop chain, then died before its next turn. Coverage = stop + killed:after-stop-block.

FREEZE IS AN OVERLAY, NOT ONLY A CLASS. A permission freeze is a MID-LIFE state:
a session can freeze for 19 h, be granted, and then self-close. Its terminal
class is `self-close` and that is correct. So the census also reports how many
sessions of EVERY class carried a long permission wait — the orthogonal column
the class table structurally cannot show.

USAGE
  python3 scripts/measure-terminations.py                  # 30-day window (default)
  python3 scripts/measure-terminations.py --days 1         # today only
  python3 scripts/measure-terminations.py --json /tmp/t.json
  python3 scripts/measure-terminations.py --denominator    # ONE line, for consumers
  python3 scripts/measure-terminations.py --selftest       # 7-class red-proof

CONSUMER: scripts/idl-abstain-alarm.sh prints `--denominator` beside its
per-hook evaluation table, because every row of that table is a count over
sessions that reached a Stop.

EVERY STORE PATH IS ENV-OVERRIDABLE and the selftest pins all of them (the
rank-4 lesson: tests/completion-assert.bats pinned one IDL var and leaked 312
fixture rows into the live store through the one it did not pin). This script
NEVER writes to a live store; it opens the transcript roots, the beat store, the
permission archive and the pending-beacon dir read-only.
"""

import argparse
import collections
import datetime
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import time

# ─────────────────────────────────────────────────────────────────────────────
# STORES — every one overridable, so the selftest can pin all of them at once
# ─────────────────────────────────────────────────────────────────────────────
# CORPUS: four roots, never one (MEMORY.md transcript-corpus-spans-four-account-stores).
# ~/.claude-next/projects is a SYMLINK to ~/.claude/projects; it is excluded by
# realpath so it can never double-count.
DEFAULT_ROOTS = [
    "~/.claude/projects",
    "~/.claude-secondary/projects",
    "~/.claude-tertiary/projects",
    "~/.claude-quaternary/projects",
]
ROOTS_EXCLUDED_AS_ALIAS = ["~/.claude-next/projects"]

ENV_ROOTS = "CC_TERM_ROOTS"            # ":"-separated, overrides DEFAULT_ROOTS
ENV_BEATS = "CC_TERM_BEATS_DIR"        # default ~/.claude/cc-beats
ENV_PERMARCH = "CC_PERMARCHIVE_DIR"    # shared with hooks/cc-permission-beacon.sh
ENV_PERMPEND = "CC_PERMPEND_DIR"       # shared with hooks/cc-permission-beacon.sh
ENV_PSFILE = "CC_TERM_PS_FILE"         # a file of "pid lstart" lines, instead of ps(1)

TAIL_BYTES = int(os.environ.get("CC_TERM_TAIL_BYTES", "1500000"))
# A permission record raised within this many seconds BEFORE the terminal record
# still counts as "pending at the terminal event": the transcript stamps the
# tool_use, the beacon stamps the prompt, and they are not the same clock tick.
FREEZE_JOIN_SLACK_S = int(os.environ.get("CC_TERM_FREEZE_SLACK_S", "60"))
# The overlay threshold — a wait this long is a freeze, not a pause. 300 s is
# CRITIC §0's threshold, kept so the two figures are comparable.
FREEZE_WAIT_S = int(os.environ.get("CC_TERM_FREEZE_WAIT_S", "300"))

CLASSES = ["stop", "self-close", "recycle", "drain-recycle", "frozen", "api-error", "killed"]
KILLED_SUB = ["after-stop-block", "dangling-tool", "after-result", "after-prompt", "no-tool-seen"]

# The retirement commands. Anchored on the SCRIPT NAME, never on the bare verb:
# `self-close` alone matches a session that merely greps for the string, and a
# census keyed on a word that appears in briefs convicts sessions that only
# MENTION it (MEMORY.md pgrep-f-matches-agent-briefs).
RE_DRAIN = re.compile(r"drain-recycle-fire\.sh")
RE_SELFCLOSE = re.compile(r"handoff-fire\.sh\b[^\n]{0,400}?\bself-close\b")
RE_RECYCLE = re.compile(r"handoff-fire\.sh\b[^\n]{0,400}?--recycle\b")
RE_STOPBLOCK = re.compile(r"^\s*Stop hook feedback:")

MONTHS = {m: i + 1 for i, m in enumerate(
    "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}


# ─────────────────────────────────────────────────────────────────────────────
# LIVENESS — the beat store, and the (pid, lstart) identity pin
# ─────────────────────────────────────────────────────────────────────────────
def norm_lstart(s):
    """
    Normalise a `ps -o lstart=` rendering to (mon, day, hh, mm, ss, year).

    THIS FUNCTION IS THE INSTRUMENT'S LOAD-BEARING FIX, and a strict string
    compare in its place reads EVERY LIVE SESSION AS DEAD. hooks/session-beat.sh
    (:93) writes `TZ=UTC ps -o lstart=` — TZ pinned, LOCALE NOT — so the store
    holds the ambient-locale rendering `Wed 9 Sep 03:19:56 2026`, while any
    reader that pins `LC_ALL=C` (as it must, to be deterministic) gets
    `Wed Sep  9 03:19:56 2026` for the SAME live process. Measured 2026-09-08 on
    142 in-window transcripts: strict compare → 134 dead / 0 alive; parsed
    compare → 115 dead / 19 alive. Nineteen false convictions, 13% of the
    population, and the failure is SILENT — a census of dead sessions that
    over-counts reads as a busier day, never as a broken instrument.

    MEMORY.md process-start-time-renders-in-ambient-timezone names the TZ half of
    this; the LOCALE half is the same defect on the other axis. bin/cc-reaper
    (:2590-2604) already carries a three-arm compat ladder for it; this is the
    same fact expressed as a parse instead of three renderings.
    """
    t = str(s or "").split()
    if len(t) != 5:
        return None
    _dow, a, b, clock, year = t
    if a in MONTHS:
        mon, day = MONTHS[a], b        # LC_ALL=C:  Wed Sep  9 ...
    elif b in MONTHS:
        mon, day = MONTHS[b], a        # en_GB:     Wed 9 Sep ...
    else:
        return None
    parts = clock.split(":")
    if len(parts) != 3:
        return None
    try:
        return (mon, int(day), int(parts[0]), int(parts[1]), int(parts[2]), int(year))
    except ValueError:
        return None


def read_ps():
    """
    pid -> normalised lstart for every process on the box.

    An unreadable process table is UNKNOWN, never "nothing is alive": acting on
    unproven absence is the probe-that-acts-on-absence defect, and here it would
    classify the entire fleet as dead. Returns None on failure and the caller
    refuses to run.
    """
    override = os.environ.get(ENV_PSFILE)
    if override:
        if not os.path.isfile(override):
            return None
        text = open(override, errors="replace").read()
    else:
        try:
            env = dict(os.environ, TZ="UTC", LC_ALL="C")
            p = subprocess.run(["ps", "-Ao", "pid=,lstart="],
                               capture_output=True, text=True, env=env, timeout=30)
            if p.returncode != 0:
                return None
            text = p.stdout
        except Exception:
            return None
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        pid, _, rest = line.partition(" ")
        if pid.isdigit():
            out[pid] = norm_lstart(rest)
    return out or None


def read_beats(beats_dir):
    """sid -> beat record. The beat is PRESENCE, and here it is used only for the
    pid identity it carries — not as a census (scripts/lib/spawn-presence.sh:17-34
    is emphatic that beat COUNT is a lower bound on liveness and must never be
    read as a population)."""
    out = {}
    for path in glob.glob(os.path.join(beats_dir, "*.json")):
        try:
            rec = json.load(open(path, errors="replace"))
        except Exception:
            continue
        sid = rec.get("sid")
        if sid:
            out[sid] = rec
    return out


def liveness(sid, beats, live):
    """'alive' | 'dead' | 'no-beat'. Identity is (pid, lstart), never pid alone —
    a recycled pid would otherwise resurrect a dead session."""
    beat = beats.get(sid)
    if not beat:
        return "no-beat"
    pid = str(beat.get("pid") or "")
    if not pid or pid not in live:
        return "dead"
    want = norm_lstart(beat.get("lstart"))
    have = live.get(pid)
    if want is not None and have is not None and want != have:
        return "dead"           # pid reused by another process
    return "alive"


# ─────────────────────────────────────────────────────────────────────────────
# CORPUS
# ─────────────────────────────────────────────────────────────────────────────
def iter_transcripts(days, roots, verbose=True):
    """Yield (path, root_label) for main-chain transcripts touched in-window."""
    cutoff = time.time() - days * 86400
    seen_real, per_root, files = set(), [], []
    for r in roots:
        rp = os.path.realpath(os.path.expanduser(r))
        if rp in seen_real:
            per_root.append((r, 0, 0, "ALIAS of an earlier root — skipped"))
            continue
        seen_real.add(rp)
        if not os.path.isdir(rp):
            per_root.append((r, 0, 0, "MISSING"))
            continue
        found = []
        for d in os.listdir(rp):
            p = os.path.join(rp, d)
            if os.path.isdir(p):
                found += glob.glob(os.path.join(p, "*.jsonl"))
        # MAIN CHAIN ONLY. An `agent-*.jsonl` is a subagent's transcript: it has
        # no session of its own to terminate, and measure-closes.py:265 excludes
        # the same family for the same reason.
        main = [f for f in found
                if not os.path.basename(f).startswith("agent-")
                and "/subagents/" not in f]
        inwin = [f for f in main if os.path.getmtime(f) >= cutoff]
        per_root.append((r, len(main), len(inwin), ""))
        files += [(f, r) for f in inwin]
    for r in ROOTS_EXCLUDED_AS_ALIAS:
        rp = os.path.realpath(os.path.expanduser(r))
        per_root.append((r, 0, 0, "symlink -> %s (excluded, never double-counted)" % rp))
    if verbose:
        print("CORPUS — per root (never a single-root census)")
        for r, tot, inw, note in per_root:
            print("  %-32s main-chain %5d   in-window %5d  %s" % (r, tot, inw, note))
        print("  %-32s main-chain %5d   in-window %5d" % (
            "ALL FOUR ROOTS", sum(x[1] for x in per_root), sum(x[2] for x in per_root)))
    return files, per_root


def tail_records(path):
    """Parse the tail of a transcript. Whole-file loads are refused on purpose:
    the box runs at load 50-80 and these files reach tens of MB."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            if size > TAIL_BYTES:
                fh.seek(size - TAIL_BYTES)
                fh.readline()          # discard the partial line
            data = fh.read().decode("utf-8", "replace")
    except OSError:
        return []
    out = []
    for line in data.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except Exception:
            # A malformed line is a record we could not read, not a record that
            # is not there. Counted by the caller, never silently dropped.
            out.append({"__malformed__": True})
    return out


def rec_epoch(rec):
    t = rec.get("timestamp")
    if not t:
        return None
    try:
        return datetime.datetime.fromisoformat(str(t).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def text_of(rec):
    m = rec.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return c
    if not isinstance(c, list):
        return ""
    return "\n".join(b.get("text") or "" for b in c
                     if isinstance(b, dict) and b.get("type") == "text")


def block_types(rec):
    m = rec.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return ["text"]
    if not isinstance(c, list):
        return []
    return [b.get("type") for b in c if isinstance(b, dict)]


def last_tool_use(conv):
    """(command_text, tool_name, tool_use_id) of the last tool_use in the tail."""
    for rec in reversed(conv):
        if rec.get("type") != "assistant":
            continue
        m = rec.get("message") or {}
        c = m.get("content")
        if not isinstance(c, list):
            continue
        tus = [b for b in c if isinstance(b, dict) and b.get("type") == "tool_use"]
        if tus:
            b = tus[-1]
            inp = b.get("input") or {}
            cmd = inp.get("command")
            if not isinstance(cmd, str):
                cmd = inp.get("file_path") or inp.get("prompt") or ""
            return str(cmd)[:8000], b.get("name") or "", b.get("id") or ""
    return "", "", ""


# ─────────────────────────────────────────────────────────────────────────────
# PERMISSION LAYER — two arms, with different reaches, both stated
# ─────────────────────────────────────────────────────────────────────────────
def read_permissions(archdir, penddir):
    """
    (archive index sid -> [records], set of sids with a LIVE pending beacon).

    THE TWO ARMS ARE NOT INTERCHANGEABLE and the census says which one fired.
      · the ARCHIVE (durable, months) holds only RESOLVED prompts — measured
        2026-09: 519 of 519 September records carry a `resolved_ts`. A session
        that froze and DIED still appears here iff someone later answered the
        prompt. So the archive is retrospective and complete-ish, but it can
        never see a prompt nobody ever answered.
      · the PENDING BEACON (/tmp, wiped on reboot) is the opposite: it is the
        only record of a never-answered prompt, and it reaches only sessions
        since the last boot. Measured 2026-09-08: exactly 1 beacon on disk.
    A `frozen` classification that cites neither arm is not a measurement.
    """
    idx = collections.defaultdict(list)
    for path in sorted(glob.glob(os.path.join(archdir, "*.jsonl"))):
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                sid = rec.get("session_id")
                if sid:
                    idx[sid].append(rec)
    pend = set()
    for path in glob.glob(os.path.join(penddir, "*.json")):
        base = os.path.basename(path)
        if base.startswith("."):
            continue
        pend.add(base[:-5])
    return idx, pend


def freeze_at_terminal(sid, term_ts, perm_idx, pend):
    """
    Was a permission prompt PENDING at the terminal event? -> (bool, why, waited_s)

    NOT "did this session ever see a prompt" — that is the overlay below. The
    join is on TIME because the id join is unavailable: the archive's
    `tool_use_id` is empty on 519 of 519 September records, and
    `cleared_tool_use_id` names the tool call that ANSWERED the prompt, not the
    one that was blocked. Keying on it would join a freeze to the wrong tool.
    """
    if sid in pend:
        return True, "pending-beacon", None
    if term_ts is None:
        return False, "", None
    best = None
    for rec in perm_idx.get(sid, []):
        ts = rec.get("ts")
        if not isinstance(ts, (int, float)):
            continue
        if ts >= term_ts - FREEZE_JOIN_SLACK_S:
            w = rec.get("waited_s")
            if best is None or (isinstance(w, (int, float)) and w > (best or 0)):
                best = w if isinstance(w, (int, float)) else 0
    if best is not None:
        return True, "archive-at-terminal", best
    return False, "", None


def freeze_overlay(sid, perm_idx, pend):
    """Longest permission wait anywhere in this session's life (the ORTHOGONAL
    column). A freeze is a mid-life state; a session that froze 19 h, was
    granted, and then self-closed is terminally a `self-close` and the class
    table structurally cannot show that it froze."""
    if sid in pend:
        return -1                     # pending and never resolved: wait unbounded
    waits = [r.get("waited_s") for r in perm_idx.get(sid, [])
             if isinstance(r.get("waited_s"), (int, float))]
    return max(waits) if waits else 0


# ─────────────────────────────────────────────────────────────────────────────
# THE CLASSIFIER — one class per session, tested in this order
# ─────────────────────────────────────────────────────────────────────────────
def classify(recs, sid, perm_idx, pend):
    """-> dict(cls, sub, version, stop_chain_reached, freeze_why, waited_s, cmd)"""
    conv = [r for r in recs
            if r.get("type") in ("assistant", "user") and not r.get("isSidechain")]
    version = ""
    for r in reversed(recs):
        if r.get("version"):
            version = str(r["version"])
            break
    out = {"cls": "killed", "sub": "no-tool-seen", "version": version,
           "stop_chain_reached": False, "freeze_why": "", "waited_s": None, "cmd": ""}
    if not conv:
        out["sub"] = "no-conversational-record"
        return out
    last = conv[-1]
    term_ts = rec_epoch(last)
    msg = last.get("message") or {}

    # 1. api-error FIRST. An API-error record is an assistant TEXT record, so a
    #    Stop test that ran first would count a quota death as a clean close.
    if last.get("type") == "assistant" and last.get("isApiErrorMessage"):
        out["cls"] = "api-error"
        out["sub"] = (text_of(last) or "")[:60].replace("\n", " ")
        return out

    # 2. stop — the turn ended in text.
    if last.get("type") == "assistant":
        blocks = block_types(last)
        if "tool_use" not in blocks and msg.get("stop_reason") in (None, "end_turn"):
            out["cls"] = "stop"
            out["sub"] = ""
            out["stop_chain_reached"] = True
            return out

    # 3-5. the retirement commands, drain BEFORE recycle (it is a --recycle wrapper).
    cmd, _tname, _tid = last_tool_use(conv)
    out["cmd"] = cmd[:200]
    if RE_DRAIN.search(cmd):
        out["cls"], out["sub"] = "drain-recycle", ""
        return out
    if RE_SELFCLOSE.search(cmd):
        out["cls"], out["sub"] = "self-close", ""
        return out
    if RE_RECYCLE.search(cmd):
        out["cls"], out["sub"] = "recycle", ""
        return out

    # 6. frozen — an ordinary command with a prompt pending on it.
    froze, why, waited = freeze_at_terminal(sid, term_ts, perm_idx, pend)
    if froze:
        out["cls"], out["sub"] = "frozen", why
        out["freeze_why"], out["waited_s"] = why, waited
        return out

    # 7. killed — THE RESIDUAL. Sub-split so it is not opaque.
    out["cls"] = "killed"
    if last.get("type") == "user":
        txt = text_of(last)
        if RE_STOPBLOCK.search(txt or ""):
            # The session DID reach a Stop; a Stop hook blocked it, and it died
            # before taking the turn the block asked for. The Stop chain ran.
            out["sub"] = "after-stop-block"
            out["stop_chain_reached"] = True
        elif "tool_result" in block_types(last):
            out["sub"] = "after-result"
        else:
            out["sub"] = "after-prompt"
    elif "tool_use" in block_types(last):
        out["sub"] = "dangling-tool"
    else:
        out["sub"] = "no-tool-seen"
    return out


# ─────────────────────────────────────────────────────────────────────────────
# BUILD + REPORT
# ─────────────────────────────────────────────────────────────────────────────
def build(days, roots, verbose=True):
    live = read_ps()
    if live is None:
        return None, "process table unreadable — liveness is UNKNOWN, and a census "\
                     "that guessed would call the whole fleet dead"
    beats = read_beats(os.path.expanduser(
        os.environ.get(ENV_BEATS, "~/.claude/cc-beats")))
    perm_idx, pend = read_permissions(
        os.path.expanduser(os.environ.get(ENV_PERMARCH,
                                          "~/.claude/autonomy/permission-archive")),
        os.environ.get(ENV_PERMPEND, "/tmp/cc-permission-pending"))
    files, per_root = iter_transcripts(days, roots, verbose)

    rows, excluded = [], collections.Counter()
    for path, root in files:
        sid = os.path.basename(path)[:-len(".jsonl")]
        state = liveness(sid, beats, live)
        if state != "dead":
            excluded[state] += 1
            continue
        recs = tail_records(path)
        malformed = sum(1 for r in recs if r.get("__malformed__"))
        recs = [r for r in recs if not r.get("__malformed__")]
        row = classify(recs, sid, perm_idx, pend)
        row.update(sid=sid, root=root, path=path, malformed=malformed,
                   mtime=os.path.getmtime(path),
                   overlay_wait=freeze_overlay(sid, perm_idx, pend))
        rows.append(row)
    return {"rows": rows, "excluded": excluded, "per_root": per_root,
            "beats": len(beats), "perm_sids": len(perm_idx), "pending": len(pend),
            "days": days}, None


def pct(a, b):
    return 0.0 if not b else 100.0 * a / b


def table(title, counter, total, width=22):
    print("\n%s" % title)
    for key, n in sorted(counter.items(), key=lambda kv: -kv[1]):
        print("  %-*s %5d  %5.1f%%" % (width, key, n, pct(n, total)))
    print("  %-*s %5d  %5.1f%%" % (width, "TOTAL", total, 100.0 if total else 0.0))


def report(data):
    rows = data["rows"]
    n = len(rows)
    print("\nPOPULATION")
    print("  window                       %d day(s) of transcript mtime" % data["days"])
    print("  dead main-chain sessions     %d   <- the denominator of every line below" % n)
    print("  EXCLUDED strata (named, never folded into the denominator):")
    for k, v in sorted(data["excluded"].items()):
        why = {"alive": "still running — its terminal event has not happened yet",
               "no-beat": "no beat file: liveness UNKNOWN, never assumed dead"}.get(k, "")
        print("    %-10s %5d   %s" % (k, v, why))
    print("    %-10s %5s   subagent transcripts (agent-*.jsonl, /subagents/) — no session to end"
          % ("agent-*", "n/a"))
    mal = sum(r["malformed"] for r in rows)
    print("  malformed transcript lines in the scanned tails: %d" % mal)
    print("  beat files %d · permission-archive sids %d · live pending beacons %d"
          % (data["beats"], data["perm_sids"], data["pending"]))

    cls = collections.Counter(r["cls"] for r in rows)
    for c in CLASSES:
        cls.setdefault(c, 0)
    table("TERMINAL CLASS  (exactly one per session)", cls, n)

    killed = collections.Counter(r["sub"] for r in rows if r["cls"] == "killed")
    if killed:
        table("  `killed` is a RESIDUAL — defined by exclusion, not by a kill record",
              killed, sum(killed.values()))

    # THE CONSUMER'S NUMBER.
    reached = sum(1 for r in rows if r["stop_chain_reached"])
    print("\nSTOP-CHAIN COVERAGE  — the denominator every \"%% of Stops\" figure needs")
    print("  reached a Stop (the Stop chain evaluated)   %5d  %5.1f%%" % (reached, pct(reached, n)))
    print("    of which a clean end_turn Stop            %5d  %5.1f%%" % (cls["stop"], pct(cls["stop"], n)))
    print("    of which a Stop the hooks BLOCKED         %5d  %5.1f%%"
          % (killed.get("after-stop-block", 0), pct(killed.get("after-stop-block", 0), n)))
    print("  never reached a Stop (invisible to it)      %5d  %5.1f%%" % (n - reached, pct(n - reached, n)))
    print("    retired inside a tool call                %5d  %5.1f%%"
          % (cls["self-close"] + cls["recycle"] + cls["drain-recycle"],
             pct(cls["self-close"] + cls["recycle"] + cls["drain-recycle"], n)))

    # The orthogonal freeze column.
    froze = [r for r in rows if r["overlay_wait"] == -1 or r["overlay_wait"] >= FREEZE_WAIT_S]
    print("\nPERMISSION FREEZE — an OVERLAY, not only a class (a session can freeze, be")
    print("granted, then self-close; its terminal class is `self-close` and that is right)")
    print("  sessions carrying a permission wait >= %ds anywhere in life: %d  (%.1f%%)"
          % (FREEZE_WAIT_S, len(froze), pct(len(froze), n)))
    by = collections.Counter(r["cls"] for r in froze)
    for c in CLASSES:
        if by.get(c):
            print("    terminal class %-14s %4d" % (c, by[c]))

    ver = collections.Counter(r["version"] or "(unstamped)" for r in rows)
    table("BY BINARY VERSION", ver, n, width=14)
    print("  per-version class split:")
    for v, _ in sorted(ver.items(), key=lambda kv: -kv[1])[:6]:
        sub = collections.Counter(r["cls"] for r in rows if (r["version"] or "(unstamped)") == v)
        print("    %-12s %s" % (v, "  ".join("%s=%d" % (c, sub[c]) for c in CLASSES if sub[c])))

    root = collections.Counter(r["root"] for r in rows)
    table("BY ACCOUNT ROOT", root, n, width=32)
    print("  per-root class split:")
    for rt, _ in sorted(root.items(), key=lambda kv: -kv[1]):
        sub = collections.Counter(r["cls"] for r in rows if r["root"] == rt)
        print("    %-32s %s" % (rt, "  ".join("%s=%d" % (c, sub[c]) for c in CLASSES if sub[c])))

    # W2-B1's input.
    cut = time.time() - 86400
    sc24 = [r for r in rows if r["cls"] == "self-close" and r["mtime"] >= cut]
    print("\nFOR W2-B1 — self-closed sids in the last 24 h: %d" % len(sc24))
    for r in sorted(sc24, key=lambda x: -x["mtime"])[:40]:
        print("  %s  %s" % (r["sid"], os.path.dirname(r["path"]).split("/")[-1][:60]))
    if len(sc24) > 40:
        print("  ... and %d more (use --json)" % (len(sc24) - 40))
    return 0


def denominator_line(data):
    """ONE line, for a consumer that prints per-Stop figures. This is the whole
    point of the instrument: a rate over Stops, printed without saying how few
    terminations are Stops, reads as a rate over sessions."""
    rows = data["rows"]
    n = len(rows)
    if not n:
        return ("termination-census: NO dead main-chain sessions in the last %dd — "
                "the Stop-chain denominator is UNKNOWN, not 100%%" % data["days"])
    reached = sum(1 for r in rows if r["stop_chain_reached"])
    tool = sum(1 for r in rows if r["cls"] in ("self-close", "recycle", "drain-recycle"))
    return ("termination-census (%dd): %d of %d dead main-chain sessions reached a Stop "
            "(%.0f%%) — %d (%.0f%%) retired inside a tool call and are invisible to every "
            "hook counted above" % (data["days"], reached, n, pct(reached, n), tool, pct(tool, n)))


# ─────────────────────────────────────────────────────────────────────────────
# SELFTEST — 7 synthetic transcripts, one per class, all stores pinned
# ─────────────────────────────────────────────────────────────────────────────
def _rec(**kw):
    base = {"type": "assistant", "isSidechain": False, "version": "2.1.260",
            "timestamp": "2026-09-08T12:00:00.000Z"}
    base.update(kw)
    return base


def _asst_text(txt, stop_reason="end_turn", **kw):
    return _rec(message={"role": "assistant", "stop_reason": stop_reason,
                         "content": [{"type": "text", "text": txt}]}, **kw)


def _asst_tool(cmd, stop_reason="tool_use"):
    return _rec(message={"role": "assistant", "stop_reason": stop_reason,
                         "content": [{"type": "tool_use", "id": "toolu_x",
                                      "name": "Bash", "input": {"command": cmd}}]})


def _user_text(txt):
    return _rec(type="user", message={"role": "user",
                                      "content": [{"type": "text", "text": txt}]})


FIXTURES = {
    # class            records (last one is the terminal conversational record)
    "stop": [_asst_tool("ls"), _asst_text("Done. Good to close: yes.")],
    "self-close": [_asst_text("Retiring.", stop_reason="tool_use"),
                   _asst_tool("$HOME/.claude/scripts/handoff-fire.sh self-close --terminal")],
    "recycle": [_asst_tool("scripts/handoff-fire.sh --recycle --worktree w2")],
    "drain-recycle": [_asst_tool("bash scripts/drain-recycle-fire.sh --recycle")],
    "frozen": [_asst_tool("rm -rf /some/path")],
    "api-error": [_asst_tool("ls"),
                  _rec(isApiErrorMessage=True,
                       message={"role": "assistant", "stop_reason": "stop_sequence",
                                "content": [{"type": "text", "text": "Prompt is too long"}]})],
    "killed": [_asst_tool("pnpm run build")],
}
FIXTURE_SIDS = {c: "00000000-0000-4000-8000-0000000000%02d" % i
                for i, c in enumerate(sorted(FIXTURES), start=10)}


def _write_fixture(tmp, cls, records):
    sid = FIXTURE_SIDS[cls]
    proj = os.path.join(tmp, "roots", "acct", "-fixture-proj")
    os.makedirs(proj, exist_ok=True)
    path = os.path.join(proj, sid + ".jsonl")
    with open(path, "w") as fh:
        for r in records:
            fh.write(json.dumps(r) + "\n")
    return sid, path


def _build_fixture_world(tmp, mutate=None):
    """
    Materialise a whole fake world and PIN every store env var onto it.

    ALL FIVE, not one. The rank-4 lesson from this same wave:
    tests/completion-assert.bats pinned COMPLETION_IDL and drove session-continue
    16 times with CONTINUE_IDL unpinned, leaking 312 fixture rows into the LIVE
    decision journal. One unpinned store is the whole leak.
    """
    fixtures = {c: list(v) for c, v in FIXTURES.items()}
    if mutate:
        fixtures = mutate(fixtures)
    beats = os.path.join(tmp, "beats")
    arch = os.path.join(tmp, "permarch")
    pend = os.path.join(tmp, "permpend")
    for d in (beats, arch, pend):
        os.makedirs(d, exist_ok=True)
    sids = {}
    for cls, recs in fixtures.items():
        sid, _path = _write_fixture(tmp, cls, recs)
        sids[cls] = sid
        # every fixture session is DEAD: a pid that cannot be in the ps snapshot
        json.dump({"sid": sid, "pid": 999999, "lstart": "Mon 8 Sep 12:00:00 2026"},
                  open(os.path.join(beats, sid + ".json"), "w"))
    # the frozen fixture's evidence: a resolved archive record raised AT its
    # terminal timestamp. (The pending-beacon arm is exercised by --selftest too,
    # via the killed fixture NOT having one.)
    term_ts = datetime.datetime.fromisoformat("2026-09-08T12:00:00+00:00").timestamp()
    with open(os.path.join(arch, "2026-09.jsonl"), "w") as fh:
        fh.write(json.dumps({"session_id": sids["frozen"], "ts": term_ts + 1,
                             "resolved_ts": term_ts + 4000, "waited_s": 3999,
                             "tool_name": "Bash", "tool_use_id": ""}) + "\n")
    psfile = os.path.join(tmp, "ps.txt")
    open(psfile, "w").write("1 Mon Sep  8 00:00:00 2026\n")   # no fixture pid
    env = {
        ENV_ROOTS: os.path.join(tmp, "roots", "acct"),
        ENV_BEATS: beats,
        ENV_PERMARCH: arch,
        ENV_PERMPEND: pend,
        ENV_PSFILE: psfile,
    }
    return env, sids


def _run_in_world(env):
    saved = {k: os.environ.get(k) for k in env}
    os.environ.update(env)
    try:
        data, err = build(days=3650, roots=env[ENV_ROOTS].split(":"), verbose=False)
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    return data, err


def selftest():
    ok = fail = 0

    def check(cond, label):
        nonlocal ok, fail
        if cond:
            ok += 1
            print("  ok   %s" % label)
        else:
            fail += 1
            print("  FAIL %s" % label)

    print("measure-terminations --selftest")

    # ── A. the locale parse, the one that decides the whole population ──────
    print(" A. lstart parse (a strict string compare convicts every live session)")
    a = norm_lstart("Wed Sep  9 03:19:56 2026")      # LC_ALL=C
    b = norm_lstart("Wed 9 Sep 03:19:56 2026")       # ambient en_GB, as the beat writes it
    check(a is not None and a == b, "the two renderings of ONE process compare EQUAL")
    check("Wed Sep  9 03:19:56 2026" != "Wed 9 Sep 03:19:56 2026",
          "...and they are NOT string-equal — the naive check would say dead")
    check(norm_lstart("garbage") is None, "an unparseable lstart is None, never a false match")

    with tempfile.TemporaryDirectory(prefix="mterm-selftest-") as tmp:
        # ── B. seven fixtures, seven classes ───────────────────────────────
        print(" B. one fixture per class — 7/7 or the instrument is not calibrated")
        env, sids = _build_fixture_world(tmp)
        # the leak guard: assert every store points INSIDE the sandbox
        print(" B0. store pinning (rank-4: one unpinned store IS the leak)")
        for k, v in env.items():
            check(v.startswith(tmp), "%s pinned inside the sandbox" % k)
        data, err = _run_in_world(env)
        check(err is None and data is not None, "the census ran over the fixture world")
        got = {r["sid"]: r["cls"] for r in (data["rows"] if data else [])}
        check(len(got) == len(FIXTURES),
              "all %d fixture sessions were seen (got %d)" % (len(FIXTURES), len(got)))
        hits = 0
        for cls, sid in sorted(sids.items()):
            actual = got.get(sid, "<missing>")
            hits += (actual == cls)
            check(actual == cls, "%-14s classified as %s" % (cls, actual))
        check(hits == 7, "7/7 classes correct (got %d/7)" % hits)

        # ── C. RED-PROOF: mutate one fixture's last record; the class must move
        print(" C. red-proof — mis-key one fixture and the selftest must go RED")

        def mutate(fx):
            # self-close's terminal command becomes an ordinary one. If the
            # classifier keyed on anything but that command, this stays green —
            # and a green here would mean the 56%% figure rests on nothing.
            fx["self-close"] = [_asst_tool("echo 'not a retirement at all'")]
            return fx

        env2, sids2 = _build_fixture_world(
            tempfile.mkdtemp(prefix="mterm-mut-", dir=tmp), mutate=mutate)
        data2, err2 = _run_in_world(env2)
        got2 = {r["sid"]: r["cls"] for r in (data2["rows"] if data2 else [])}
        moved = got2.get(sids2["self-close"])
        check(moved is not None and moved != "self-close",
              "mutated self-close no longer classifies as self-close (now %s) — RED reachable"
              % moved)
        check(sum(1 for c, s in sids2.items() if got2.get(s) == c) == 6,
              "exactly ONE class broke under the mutation (6/7 survive)")

        # ── D. ordering: drain-recycle must not be eaten by --recycle ───────
        print(" D. ordering + anchoring traps")
        r = classify([_asst_tool("bash scripts/drain-recycle-fire.sh --recycle")],
                     "x", {}, set())
        check(r["cls"] == "drain-recycle",
              "a drain-recycle carrying --recycle is drain-recycle, not recycle")
        r = classify([_asst_tool("grep -n self-close scripts/handoff-fire.sh")], "x", {}, set())
        check(r["cls"] != "self-close",
              "a session that merely GREPS for self-close is not a self-close")
        r = classify([_asst_tool("ls"),
                      _rec(isApiErrorMessage=True,
                           message={"role": "assistant", "stop_reason": "end_turn",
                                    "content": [{"type": "text", "text": "API Error"}]})],
                     "x", {}, set())
        check(r["cls"] == "api-error",
              "an api-error record with stop_reason end_turn is NOT counted as a clean Stop")

        # ── E. the coverage number the consumer consumes ────────────────────
        print(" E. stop-chain coverage counts a BLOCKED Stop as reached")
        r = classify([_asst_tool("ls"), _user_text("Stop hook feedback:\n🔔 WAKE FLOOR")],
                     "x", {}, set())
        check(r["cls"] == "killed" and r["sub"] == "after-stop-block"
              and r["stop_chain_reached"],
              "a death after a Stop-hook block is residual BUT the Stop chain ran")
        line = denominator_line({"rows": [], "days": 1})
        check("UNKNOWN" in line,
              "an empty population reports UNKNOWN, never a 100%% Stop rate")

        # ── F. liveness refuses to guess ────────────────────────────────────
        print(" F. an unreadable process table is UNKNOWN, never 'all dead'")
        saved = os.environ.get(ENV_PSFILE)
        os.environ[ENV_PSFILE] = os.path.join(tmp, "does-not-exist")
        d3, e3 = build(days=1, roots=[env[ENV_ROOTS]], verbose=False)
        if saved is None:
            os.environ.pop(ENV_PSFILE, None)
        else:
            os.environ[ENV_PSFILE] = saved
        check(d3 is None and e3 is not None, "build() refuses rather than guessing (%s)"
              % (e3 or "")[:40])

    print("\n  passed %d  failed %d" % (ok, fail))
    return 0 if fail == 0 else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=float, default=30.0,
                    help="window in days of transcript mtime (default 30). NOTE the reach of "
                         "the stores differs: transcripts go back months, the IDL only 11 days "
                         "(8 gz archives from 2026-08-29), and the pending-permission beacon "
                         "only to the last reboot. A 30d census is a transcript-and-beat census; "
                         "any IDL-joined figure is bounded by 11 days.")
    ap.add_argument("--json", metavar="PATH", help="write the per-session rows as JSON")
    ap.add_argument("--denominator", action="store_true",
                    help="print ONE line: the Stop-chain denominator, for consumers")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    roots = os.environ.get(ENV_ROOTS)
    roots = roots.split(":") if roots else DEFAULT_ROOTS
    data, err = build(args.days, roots, verbose=not args.denominator)
    if data is None:
        # Fail LOUD and toward abstention: a census that cannot see liveness must
        # not print a number (MEMORY.md fail-safe-default-mimics-the-healthy-state).
        sys.stderr.write("measure-terminations: ABSTAIN — %s\n" % err)
        return 2
    if args.denominator:
        print(denominator_line(data))
        return 0
    rc = report(data)
    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"days": args.days,
                       "generated": datetime.datetime.now(datetime.timezone.utc)
                                    .strftime("%Y-%m-%dT%H:%M:%SZ"),
                       "excluded": dict(data["excluded"]),
                       "rows": data["rows"]}, fh, indent=1)
        print("\njson: %s" % args.json)
    return rc


if __name__ == "__main__":
    sys.exit(main())
