#!/usr/bin/env python3
"""
measure-closes.py — the CLOSE_SCANNABILITY instrument.

WHY THIS FILE EXISTS AT ALL. The W1 measurement
(docs/research/close-scannability-2026-08-23.md) set every parameter in
hooks/lib/close-shape.sh's act-line matcher, and its scripts
(scratchpad/measure_closes.py, refine.py) were never committed and are gone. A
figure whose instrument cannot be re-run is a figure that can only decay
(MEMORY.md published-figure-decays-with-its-source). This is that instrument,
rebuilt from W1's Method section and committed, so the next question asked of
this corpus does not start by rebuilding it a third time.

WHAT IT MEASURES. Turn-final assistant messages ("closes") across all four
per-account transcript roots, classified by:
  · ledger rung glyph            (population filter — W1's definition)
  · whether an operator act is required   (3 inferred signals — W1's definition)
  · whether the act is stated as ITS OWN LINE, and at which line index
  · the outcome: did the operator ACT (a <bash-input> record in their next
    human message) or ASK (a question) — W1's corrected outcome measure
  · LENGTH (words and lines, with and without fenced blocks)   <- W2/Q-A, new
  · structural elements, fact density, and act multiplicity     <- Q-C/D/E, new

USAGE
  python3 scripts/measure-closes.py                 # default 14d window, no cap
  python3 scripts/measure-closes.py --days 60
  python3 scripts/measure-closes.py --days 14 --limit 300   # reproduce W1 exactly
  python3 scripts/measure-closes.py --days 60 --json /tmp/closes.json

Every figure it prints is dated by its window and decays with the corpus.
"""

import argparse
import glob
import json
import math
import os
import re
import sys
import time
from collections import Counter, defaultdict

# ─────────────────────────────────────────────────────────────────────────────
# CORPUS — four roots, never one (MEMORY.md transcript-corpus-spans-four-account-stores)
# ~/.claude-next/projects is a SYMLINK to ~/.claude/projects. find(1) does not
# follow walk-met symlinks, so it reports that root empty; we exclude it by
# realpath so it can never double-count even if that changes.
# ─────────────────────────────────────────────────────────────────────────────
ROOTS = [
    "~/.claude/projects",
    "~/.claude-secondary/projects",
    "~/.claude-tertiary/projects",
    "~/.claude-quaternary/projects",
]
ROOTS_EXCLUDED_AS_ALIAS = ["~/.claude-next/projects"]

RUNGS = "⛔📤🔧📦🚀👤✅"

# ─────────────────────────────────────────────────────────────────────────────
# W1 DEFINITIONS, reused verbatim where they exist in shipped code
# ─────────────────────────────────────────────────────────────────────────────

# hooks/completion-assert.sh CA_HANDOFF / CA_NEG (D1's phrase family). Ported
# from ERE to Python re; the alternation and the negation-stripping are byte-equal
# in behaviour. Negated handoffs are DELETED before matching, because "nothing for
# you to run" asserts the OPPOSITE of a handoff.
CA_HANDOFF = (
    r"remains? yours|are yours|is yours|on your (end|side)|you.?ll need to|"
    r"you will need to|requires your|needs your|still needs (a|the|your|to be)|"
    r"left (to|for) you|for you to (run|do)|keep an eye on|worth (watching|keeping)|"
    r"i.?d recommend you|up to you|your call to|manual step"
)
CA_NEG = r"(nothing|none|no|not|never|zero)\s+([a-z]{1,10}\s+){0,2}(" + CA_HANDOFF + r")"
RE_HANDOFF = re.compile(CA_HANDOFF, re.I)
RE_NEG = re.compile(CA_NEG, re.I)

# hooks/lib/close-shape.sh anchors, ported. The placeholder guard (a value that
# is a bare <angle-bracket placeholder> does not count) is reproduced.
RE_CSO = {
    "Complication": re.compile(r"(^|[^a-z])complication\s*:", re.I),
    "Solution": re.compile(r"(^|[^a-z])solution\s*:", re.I),
    "Outcome": re.compile(r"(^|[^a-z])outcome\s*:", re.I),
}
RE_GOODCLOSE = re.compile(r"(good|safe)\s+to\s+close", re.I)

# Machine injections riding the user channel. INSTRUMENT CORRECTION #1 from W1:
# a <task-notification> is not a human. Counting them as "the operator replied"
# inflated the reply denominator with records that say nothing about legibility.
MACHINE_TAG_RE = re.compile(
    r"<(task-notification|system-reminder|command-name|command-message|command-args|"
    r"local-command-stdout|local-command-caveat|bash-stdout|bash-stderr|"
    r"persisted-output|event)>.*?</\1>",
    re.S,
)
# handoff / peer-mail pings that arrive as prose rather than inside a tag
RE_PING = re.compile(
    r"(peer mail arrived|delivered by the inbox watcher|cc-await-ping|"
    r"notify-back|handoff-fire|📬)",
    re.I,
)
RE_BASH_INPUT = re.compile(r"<bash-input>(.*?)</bash-input>", re.S)

# ACT-LINE matcher. W1: "the first non-empty line that is a ▶ marker, an
# inline-code span alone on its line, or an operator-directed imperative at line
# start." Fenced regions are SKIPPED and do not count toward the index — W1's R7
# trap: 13 of 81 ▶ occurrences are the ` ▶ cc-do [N runnable]` row inside the
# rendered OPERATOR ▸ block, which a naive matcher scores at line 3 while the real
# act sits at line 11.
ACT_MARKER = "▶"  # ▶
RE_ACT_LABEL = re.compile(r"^[^0-9a-z]*act\s*:", re.I)
RE_CODE_ALONE = re.compile(r"^`[^`]+`[.:!]?$")
# Operator-directed imperative verbs. THIS LIST IS AN INSTRUMENT CHOICE, not a
# W1 artefact — W1 never published its list. It is validated by the W1
# REPRODUCTION CHECK the script prints: if the act-is-a-line stratification does
# not reproduce W1's 35.4% / 9.4%, this list is the first suspect.
IMPERATIVES = (
    "run|open|click|tap|paste|reply|restart|close|quit|check|look|tick|enter|"
    "resend|approve|confirm|decide|answer|say|tell|choose|pick|set|install|"
    "login|log in|sign in|visit|go to|press|select|review|read|copy|launch|"
    "deploy|land|ship|merge|rerun|re-run|reopen|re-open|reload|delete|remove|"
    "add|create|verify|test|try|use|grant|authorize|authenticate|hit|drag|"
    "scroll|type|fill|send|forward|share|update|edit|rename|kill|stop|start|"
    "pull|push|fetch|clone|export|import|upload|download|save|apply|accept|"
    "answer|unblock|clear|flip|toggle|switch|point|drop|keep|leave|wait|watch"
)
RE_IMPERATIVE = re.compile(r"^(?:" + IMPERATIVES + r")\b", re.I)
# strip leading list markers / bold / rung glyphs before testing a line
RE_LINE_LEAD = re.compile(r"^[\s>*\-•▸▶#]*(?:\*\*)?\s*")

RE_FENCE = re.compile(r"^\s*```")


def strip_machine(text):
    """Remove machine-injected blocks; return the residual human-typed text."""
    prev = None
    out = text
    while prev != out:
        prev = out
        out = MACHINE_TAG_RE.sub(" ", out)
    return out


def iter_transcripts(days, verbose=True):
    """Yield (path, root_label). Prints per-root counts beside every total."""
    cutoff = time.time() - days * 86400
    seen_real = set()
    per_root = []
    files = []
    for r in ROOTS:
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
        inwin = [f for f in found if os.path.getmtime(f) >= cutoff]
        per_root.append((r, len(found), len(inwin), ""))
        files += [(f, r) for f in inwin]
    for r in ROOTS_EXCLUDED_AS_ALIAS:
        rp = os.path.realpath(os.path.expanduser(r))
        note = "symlink -> %s (excluded, never double-counted)" % rp
        per_root.append((r, 0, 0, note))
    if verbose:
        print("CORPUS — per root (never a single-root census)")
        for r, tot, inw, note in per_root:
            print("  %-32s total %5d   in-window %5d  %s" % (r, tot, inw, note))
        print("  %-32s total %5d   in-window %5d" % (
            "ALL FOUR ROOTS", sum(x[1] for x in per_root), sum(x[2] for x in per_root)))
    return files, per_root


# ─────────────────────────────────────────────────────────────────────────────
# PARSE — a close = the turn-final main-agent assistant text, and the human
# reply that followed it (or EOF).
# ─────────────────────────────────────────────────────────────────────────────

STATS = Counter()


def assistant_text(rec):
    m = rec.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return c, False
    if not isinstance(c, list):
        return "", False
    txt, has_tool = [], False
    for b in c:
        if not isinstance(b, dict):
            continue
        t = b.get("type")
        if t == "text":
            txt.append(b.get("text") or "")
        elif t == "tool_use":
            has_tool = True
    return "\n".join(txt), has_tool


def user_text(rec):
    """Return (text, is_tool_result). A tool_result is never a human reply."""
    m = rec.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return c, False
    if not isinstance(c, list):
        return "", False
    txt, is_tr = [], False
    for b in c:
        if not isinstance(b, dict):
            continue
        if b.get("type") == "tool_result":
            is_tr = True
        elif b.get("type") == "text":
            txt.append(b.get("text") or "")
    return "\n".join(txt), is_tr


def classify_user(rec):
    """
    → ('human', text) | ('machine', why) | ('tool', '') | ('empty', '')

    INSTRUMENT CORRECTION #1 (W1). A <task-notification>, system-reminder,
    handoff ping or slash-command wrapper rides the user channel but is not the
    operator replying. They are excluded from the reply denominator.
    <bash-input> is the OPPOSITE: it is the operator running a handed-over
    command, and it is the positive evidence the whole outcome measure rests on.
    """
    txt, is_tr = user_text(rec)
    if is_tr:
        return "tool", ""
    if not txt or not txt.strip():
        return "empty", ""
    if RE_BASH_INPUT.search(txt):
        return "human", txt          # operator ran something — always human
    residual = strip_machine(txt).strip()
    if not residual:
        return "machine", "wrapper-only"
    if RE_PING.search(txt) and len(residual) < 400:
        return "machine", "handoff-ping"
    if rec.get("isMeta"):
        return "machine", "isMeta"
    return "human", residual


def extract_closes(path, root):
    """Yield close dicts from one transcript."""
    recs = []
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            STATS["malformed_lines"] += 1
            continue
        if r.get("type") in ("assistant", "user"):
            if r.get("isSidechain") is True:
                STATS["sidechain_records_skipped"] += 1
                continue
            recs.append(r)

    # Collapse consecutive assistant records sharing one message.id. One API
    # response is written per CONTENT BLOCK (MEMORY.md
    # transcript-lines-repeat-one-billed-response), so a close's text can be
    # split across records; taking only the last would truncate the very thing
    # this pass measures (LENGTH).
    seq = []
    i = 0
    while i < len(recs):
        r = recs[i]
        if r.get("type") != "assistant":
            kind, payload = classify_user(r)
            seq.append(("user", payload, kind, r))
            i += 1
            continue
        mid = (r.get("message") or {}).get("id")
        j = i + 1
        if mid is not None:
            while (j < len(recs)
                   and recs[j].get("type") == "assistant"
                   and (recs[j].get("message") or {}).get("id") == mid):
                j += 1
        texts, tool = [], False
        for k2 in range(i, j):
            t, hs = assistant_text(recs[k2])
            if t:
                texts.append(t)
            tool = tool or hs
        seq.append(("assistant", "\n".join(texts), tool, recs[j - 1]))
        i = j

    for k, (kind, text, aux, raw) in enumerate(seq):
        if kind != "assistant":
            continue
        if aux:                      # had a tool_use → not turn-final
            continue
        if not text or not text.strip():
            continue
        # find the next assistant/user event that ends the turn
        nxt = seq[k + 1] if k + 1 < len(seq) else None
        if nxt is None:
            reply_kind, reply_text = "eof", ""
        elif nxt[0] == "assistant":
            continue                 # another assistant record follows → not turn-final
        elif nxt[2] == "tool":
            continue                 # a tool_result follows → not turn-final
        else:
            # INSTRUMENT CORRECTION #1, SECOND HALF. Excluding machine injections
            # from the reply denominator is not the same as letting one HIDE a
            # reply behind it. A close is routinely followed by a
            # <task-notification> or system-reminder and THEN by the operator's
            # actual message; scoring that close "no human reply" throws away the
            # outcome it was supposed to measure. So we scan FORWARD over machine
            # and empty user records and stop at the first of:
            #   · a human user record   → that is the operator's reply
            #   · an ASSISTANT record   → the session carried on by itself, so
            #                             whatever the operator says later is a
            #                             reply to something else, not to this close
            reply_kind, reply_text = "machine", ""
            m = k + 1
            while m < len(seq):
                if seq[m][0] == "assistant":
                    reply_kind, reply_text = "continued", ""
                    break
                if seq[m][2] == "human":
                    reply_kind, reply_text = "human", seq[m][1]
                    break
                if seq[m][2] == "tool":
                    reply_kind, reply_text = "continued", ""
                    break
                m += 1
            else:
                reply_kind, reply_text = "eof", ""
        yield {
            "file": path,
            "root": root,
            "mtime": os.path.getmtime(path),
            "ts": raw.get("timestamp"),
            "text": text,
            "reply_kind": reply_kind,       # human | machine | empty | eof
            "reply_text": reply_text,
        }


# ─────────────────────────────────────────────────────────────────────────────
# CLASSIFY
# ─────────────────────────────────────────────────────────────────────────────

def unfenced_lines(text):
    """
    Yield (index, raw_line) for non-empty lines OUTSIDE fenced blocks, index
    starting at 1. Fenced lines are skipped AND do not advance the index — both
    halves are load-bearing (close-shape.sh: the rendered OPERATOR ▸ block is a
    ~8-line verbatim paste; counting it would make compliance impossible, and not
    skipping it would make the matcher bypassable).
    """
    n = 0
    fence = False
    for raw in text.split("\n"):
        if RE_FENCE.match(raw):
            fence = not fence
            continue
        if fence:
            continue
        if not raw.strip():
            continue
        n += 1
        yield n, raw


def line_qualifies(raw):
    """→ 'marker' | 'act-label' | 'code-alone' | 'imperative' | None"""
    t = raw.strip()
    if ACT_MARKER in t:
        return "marker"
    lead = RE_LINE_LEAD.sub("", t).strip()
    if RE_ACT_LABEL.match(lead):
        rest = RE_ACT_LABEL.sub("", lead).strip()
        if rest and not re.match(r"^<.*>$", rest):
            return "act-label"
    if RE_CODE_ALONE.match(lead):
        return "code-alone"
    if RE_IMPERATIVE.match(lead):
        return "imperative"
    return None


def act_line_index(text):
    """W1's R1 metric: the line index at which the act first becomes unambiguous."""
    for n, raw in unfenced_lines(text):
        k = line_qualifies(raw)
        if k:
            return n, k
    return None, None


def rung_of(text):
    """First rung glyph, scanning worst-first is NOT done — W1 took the glyph the
    close carries; a close carries one. Ties broken by first occurrence."""
    best, bestpos = None, None
    for g in RUNGS:
        p = text.find(g)
        if p >= 0 and (bestpos is None or p < bestpos):
            best, bestpos = g, p
    return best


def has_command(text):
    """Runnability — a backtick span or a ▶ marker. W1's R4 held this fixed."""
    return bool(re.search(r"`[^`]+`", text)) or (ACT_MARKER in text)


def act_required(text, rung):
    """
    W1's three inferred signals. Stated as a FLOOR, not a ceiling: a close that
    hands over work in wording none of the three match is invisible here.
    """
    trig = []
    if rung in ("⛔", "👤"):
        trig.append("rung")
    if ACT_MARKER in text:
        trig.append("marker")
    src = RE_NEG.sub(" ", text.lower())
    if RE_HANDOFF.search(src):
        trig.append("handoff-prose")
    return trig


def outcome(close):
    """
    INSTRUMENT CORRECTION #2 (W1). The outcome is ACTED-vs-ASKED, not "was the
    reply a question". ACTED = the operator's next human message contains a
    <bash-input> record — direct evidence they ran the handed-over thing.
    ACTED undercounts (a GUI/phone/other-pane action leaves no record), which
    biases AGAINST any finding, never for it.
    """
    if close["reply_kind"] != "human":
        return None
    t = close["reply_text"]
    if RE_BASH_INPUT.search(t):
        return "ACTED"
    if "?" in t:
        return "ASKED"
    return "OTHER"


# ── length ───────────────────────────────────────────────────────────────────
def strip_fences(text):
    out, fence = [], False
    for raw in text.split("\n"):
        if RE_FENCE.match(raw):
            fence = not fence
            continue
        if not fence:
            out.append(raw)
    return "\n".join(out)


def lengths(text):
    nofence = strip_fences(text)
    return {
        "words_all": len(text.split()),
        "words_exfence": len(nofence.split()),
        "lines_all": len([l for l in text.split("\n") if l.strip()]),
        "lines_exfence": len([l for l in nofence.split("\n") if l.strip()]),
        "chars_all": len(text),
    }


# ── Q-C structure ────────────────────────────────────────────────────────────
RE_TABLE_ROW = re.compile(r"^\s*\|.*\|\s*$")
RE_TABLE_SEP = re.compile(r"^\s*\|[\s:\-|]+\|\s*$")
RE_HEADING = re.compile(r"^\s{0,3}#{1,6}\s+\S")
RE_BOLD_HEAD = re.compile(r"^\s*\*\*[^*]{2,60}\*\*:?\s*$")
RE_BULLET = re.compile(r"^\s*(?:[-*•]|\d+[.)])\s+\S")


def structure(text):
    lines = text.split("\n")
    tbl = any(RE_TABLE_SEP.match(l) for l in lines) and \
        sum(1 for l in lines if RE_TABLE_ROW.match(l)) >= 2
    fenced = sum(1 for l in lines if RE_FENCE.match(l)) >= 2
    cso = 0
    for label, rx in RE_CSO.items():
        for l in lines:
            m = rx.search(l.lower())
            if not m:
                continue
            rest = l.lower()[m.end():].strip().lstrip(":").strip()
            if not re.match(r"^<.*>$", rest):
                cso += 1
                break
    heads = sum(1 for l in lines if RE_HEADING.match(l) or RE_BOLD_HEAD.match(l))
    bullets = sum(1 for l in lines if RE_BULLET.match(l))
    return {
        "table": tbl,
        "fenced_block": fenced,
        "cso_block": cso == 3,
        "good_to_close": bool(RE_GOODCLOSE.search(text)),
        "headings_gt3": heads > 3,
        "bullets_gt10": bullets > 10,
        "n_headings": heads,
        "n_bullets": bullets,
    }


# ── Q-D facts ────────────────────────────────────────────────────────────────
RE_SHA = re.compile(r"\b(?=[0-9a-f]{7,40}\b)(?=.*[0-9])[0-9a-f]{7,40}\b")
RE_PATH = re.compile(r"(?:/|\b)(?:[\w.@+-]+/){1,}[\w.@+-]+(?:\.\w{1,6})?\b")
RE_TICK = re.compile(r"`([^`\n]{2,200})`")
RE_NUMUNIT = re.compile(
    r"\b\d+(?:[.,]\d+)?\s*(?:%|ms|s\b|m\b|h\b|d\b|x\b|×|KB|MB|GB|KiB|MiB|GiB|"
    r"lines?|files?|commits?|tests?|words?|sessions?|items?|steps?|shas?)",
    re.I,
)


def facts(text):
    shas = set(RE_SHA.findall(text))
    paths = set(p for p in RE_PATH.findall(text) if "/" in p and len(p) > 3)
    ticks = set(t.strip() for t in RE_TICK.findall(text))
    nums = set(RE_NUMUNIT.findall(text))
    nums_full = set(m.group(0).lower() for m in RE_NUMUNIT.finditer(text))
    return {
        "n_sha": len(shas),
        "n_path": len(paths),
        "n_tick": len(ticks),
        "n_numunit": len(nums_full),
        "n_facts": len(shas) + len(paths) + len(ticks) + len(nums_full),
    }


# ── Q-E act multiplicity ─────────────────────────────────────────────────────
def act_groups(text):
    """
    How many DISTINCT operator-directed acts does a close hand over?

    PROXY, stated as one: a ▶ marker line plus the inline-code span that follows
    it within the next 2 non-empty lines is ONE act, not two — that is the
    canonical `▶ Run this:` / `` `cmd` `` pair. A bare code-alone line or a bare
    imperative line each start their own group. Consecutive imperative BULLETS
    are the shape the operator complained about ("three bullets is not one act"),
    so they are counted separately and deliberately.
    """
    groups = 0
    pend = 0          # non-empty lines remaining in which a span may attach
    last_was_marker = False
    for n, raw in unfenced_lines(text):
        k = line_qualifies(raw)
        if k == "marker":
            groups += 1
            last_was_marker, pend = True, 2
            continue
        if k == "code-alone" and last_was_marker and pend > 0:
            pend -= 1
            continue
        if k in ("act-label", "code-alone", "imperative"):
            groups += 1
            last_was_marker, pend = False, 0
            continue
        if pend > 0:
            pend -= 1
        else:
            last_was_marker = False
    return groups


# ─────────────────────────────────────────────────────────────────────────────
# STATISTICS — pure Python, so the instrument has no dependency it can lose.
# scipy is used only as a CROSS-CHECK when present, never as the source.
# ─────────────────────────────────────────────────────────────────────────────

def fisher_exact(a, b, c, d):
    """Two-tailed Fisher exact on [[a,b],[c,d]]. Returns (odds_ratio, p)."""
    n = a + b + c + d
    if n == 0:
        return float("nan"), 1.0
    r1, r2 = a + b, c + d
    c1 = a + c

    def hyp(k):
        return (math.comb(r1, k) * math.comb(r2, c1 - k)) / math.comb(n, c1)

    lo = max(0, c1 - r2)
    hi = min(r1, c1)
    p_obs = hyp(a)
    p = 0.0
    for k in range(lo, hi + 1):
        pk = hyp(k)
        if pk <= p_obs * (1 + 1e-9):
            p += pk
    orr = float("inf")
    if b and c:
        orr = (a * d) / (b * c)
    elif a * d == 0:
        orr = 0.0
    return orr, min(1.0, p)


def mannwhitney(x, y):
    """
    Two-sided Mann-Whitney U with a normal approximation and tie correction.
    Returns (U, p, n1, n2). This is the PRIMARY Q-A test: it asks whether the
    length distribution differs between ACTED and not-ACTED without binning,
    so it cannot be gamed by a bin boundary.
    """
    n1, n2 = len(x), len(y)
    if n1 == 0 or n2 == 0:
        return float("nan"), 1.0, n1, n2
    allv = sorted([(v, 0) for v in x] + [(v, 1) for v in y])
    ranks = [0.0] * len(allv)
    i = 0
    ties = 0
    while i < len(allv):
        j = i
        while j + 1 < len(allv) and allv[j + 1][0] == allv[i][0]:
            j += 1
        avg = (i + j) / 2.0 + 1
        t = j - i + 1
        ties += t ** 3 - t
        for k in range(i, j + 1):
            ranks[k] = avg
        i = j + 1
    r1 = sum(ranks[k] for k in range(len(allv)) if allv[k][1] == 0)
    u1 = r1 - n1 * (n1 + 1) / 2.0
    u = min(u1, n1 * n2 - u1)
    mu = n1 * n2 / 2.0
    n = n1 + n2
    sd2 = (n1 * n2 / 12.0) * ((n + 1) - ties / float(n * (n - 1))) if n > 1 else 0.0
    if sd2 <= 0:
        return u, 1.0, n1, n2
    z = (u - mu + 0.5) / math.sqrt(sd2)
    p = 2 * 0.5 * math.erfc(abs(z) / math.sqrt(2))
    return u, min(1.0, p), n1, n2


def logistic(X, y, names, ridge=1e-3, iters=60):
    """
    IRLS logistic regression with a small ridge (separation guard).
    Returns list of (name, beta, se, z, p). X includes no intercept column —
    one is prepended here.
    """
    n = len(y)
    k = len(X[0]) + 1
    Xd = [[1.0] + list(row) for row in X]
    beta = [0.0] * k
    for _ in range(iters):
        eta = [sum(Xd[i][j] * beta[j] for j in range(k)) for i in range(n)]
        mu = [1.0 / (1.0 + math.exp(-max(-30, min(30, e)))) for e in eta]
        W = [max(1e-9, m * (1 - m)) for m in mu]
        # gradient and Hessian
        g = [sum(Xd[i][j] * (y[i] - mu[i]) for i in range(n)) - ridge * beta[j]
             for j in range(k)]
        H = [[sum(W[i] * Xd[i][a] * Xd[i][b] for i in range(n)) + (ridge if a == b else 0.0)
              for b in range(k)] for a in range(k)]
        try:
            delta = solve(H, g)
        except Exception:
            break
        step = 1.0
        beta = [beta[j] + step * delta[j] for j in range(k)]
        if max(abs(d) for d in delta) < 1e-8:
            break
    # covariance
    eta = [sum(Xd[i][j] * beta[j] for j in range(k)) for i in range(n)]
    mu = [1.0 / (1.0 + math.exp(-max(-30, min(30, e)))) for e in eta]
    W = [max(1e-9, m * (1 - m)) for m in mu]
    H = [[sum(W[i] * Xd[i][a] * Xd[i][b] for i in range(n)) + (ridge if a == b else 0.0)
          for b in range(k)] for a in range(k)]
    try:
        cov = inv(H)
        se = [math.sqrt(max(0.0, cov[j][j])) for j in range(k)]
    except Exception:
        se = [float("nan")] * k
    out = []
    for j, nm in enumerate(["(intercept)"] + names):
        b = beta[j]
        s = se[j]
        z = b / s if s and s == s and s > 0 else float("nan")
        p = 2 * 0.5 * math.erfc(abs(z) / math.sqrt(2)) if z == z else float("nan")
        out.append((nm, b, s, z, p))
    return out


def solve(A, b):
    n = len(A)
    M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for c in range(n):
        piv = max(range(c, n), key=lambda r: abs(M[r][c]))
        if abs(M[piv][c]) < 1e-12:
            raise ValueError("singular")
        M[c], M[piv] = M[piv], M[c]
        pv = M[c][c]
        for r in range(n):
            if r == c:
                continue
            f = M[r][c] / pv
            for cc in range(c, n + 1):
                M[r][cc] -= f * M[c][cc]
    return [M[i][n] / M[i][i] for i in range(n)]


def inv(A):
    n = len(A)
    M = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(A)]
    for c in range(n):
        piv = max(range(c, n), key=lambda r: abs(M[r][c]))
        if abs(M[piv][c]) < 1e-12:
            raise ValueError("singular")
        M[c], M[piv] = M[piv], M[c]
        pv = M[c][c]
        for cc in range(2 * n):
            M[c][cc] /= pv
        for r in range(n):
            if r == c:
                continue
            f = M[r][c]
            for cc in range(2 * n):
                M[r][cc] -= f * M[c][cc]
    return [row[n:] for row in M]


def pct(a, b):
    return (100.0 * a / b) if b else 0.0


def rate_line(label, acted, n, minn=15):
    flag = "" if n >= minn else "   <- n too small to support a claim"
    return "  %-28s n=%4d   ACTED %3d (%5.1f%%)%s" % (label, n, acted, pct(acted, n), flag)


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def build(days, limit):
    files, per_root = iter_transcripts(days)
    all_closes = []
    for path, root in files:
        try:
            all_closes += list(extract_closes(path, root))
        except Exception as e:
            STATS["files_errored"] += 1
    print("\n  transcripts parsed          %6d" % len(files))
    print("  malformed JSONL lines       %6d   (counted, not silently dropped)" % STATS["malformed_lines"])
    print("  sidechain records skipped   %6d" % STATS["sidechain_records_skipped"])
    print("  files errored               %6d" % STATS["files_errored"])
    print("  turn-final assistant msgs   %6d" % len(all_closes))

    for c in all_closes:
        c["rung"] = rung_of(c["text"])
    rung_carrying = [c for c in all_closes if c["rung"]]
    rung_carrying.sort(key=lambda c: c["mtime"], reverse=True)
    if limit:
        pop = rung_carrying[:limit]
    else:
        pop = rung_carrying
    print("  … carrying a ledger rung    %6d" % len(rung_carrying))
    print("  POPULATION UNDER STUDY      %6d%s" %
          (len(pop), "  (most recent %d)" % limit if limit else "  (uncapped)"))

    for c in pop:
        c.update(lengths(c["text"]))
        c.update(structure(c["text"]))
        c.update(facts(c["text"]))
        idx, kind = act_line_index(c["text"])
        c["act_idx"] = idx
        c["act_kind"] = kind
        c["act_is_line"] = idx is not None
        c["trig"] = act_required(c["text"], c["rung"])
        c["act_required"] = bool(c["trig"])
        c["has_cmd"] = has_command(c["text"])
        c["outcome"] = outcome(c)
        c["n_acts"] = act_groups(c["text"])
    return pop, per_root


def conservation(pop):
    print("\nCONSERVATION — strata must sum to the population")
    n = len(pop)
    ar = sum(1 for c in pop if c["act_required"])
    nar = n - ar
    assert ar + nar == n, "act-required strata do not sum"
    isl = sum(1 for c in pop if c["act_required"] and c["act_is_line"])
    nol = ar - isl
    assert isl + nol == ar, "act-line strata do not sum"
    oc = Counter(c["outcome"] for c in pop)
    tot_oc = sum(oc.values())
    assert tot_oc == n, "outcome strata do not sum"
    print("  population                       %5d" % n)
    print("  act-required + no-act            %5d + %5d = %5d  %s" %
          (ar, nar, ar + nar, "OK" if ar + nar == n else "FAIL"))
    print("  (of act-required) is-line + not  %5d + %5d = %5d  %s" %
          (isl, nol, isl + nol, "OK" if isl + nol == ar else "FAIL"))
    print("  outcome ACTED/ASKED/OTHER/none   %5d/%5d/%5d/%5d = %5d  %s" %
          (oc.get("ACTED", 0), oc.get("ASKED", 0), oc.get("OTHER", 0), oc.get(None, 0),
           tot_oc, "OK" if tot_oc == n else "FAIL"))


def w1_check(pop):
    """
    THE POSITIVE CONTROL AND THE REPRODUCTION CHECK.
    If the control does not land near W1's 1.9%, or the is-line/not-line split
    does not land near 35.4%/9.4%, the instrument is broken and every number
    below it is worthless. Report the failure; do not report the result.
    """
    print("\n" + "=" * 78)
    print("W1 REPRODUCTION CHECK — the instrument must reproduce a known answer first")
    print("=" * 78)
    replied = [c for c in pop if c["outcome"] is not None]
    ar = [c for c in replied if c["act_required"]]
    na = [c for c in replied if not c["act_required"]]
    print("  act-required closes   n=%4d  ACTED %3d (%4.1f%%)  ASKED %3d (%4.1f%%)" % (
        len(ar), sum(1 for c in ar if c["outcome"] == "ACTED"),
        pct(sum(1 for c in ar if c["outcome"] == "ACTED"), len(ar)),
        sum(1 for c in ar if c["outcome"] == "ASKED"),
        pct(sum(1 for c in ar if c["outcome"] == "ASKED"), len(ar))))
    ctrl = pct(sum(1 for c in na if c["outcome"] == "ACTED"), len(na))
    print("  CONTROL no-act closes n=%4d  ACTED %3d (%4.1f%%)  ASKED %3d (%4.1f%%)   [W1: 1.9%%]" % (
        len(na), sum(1 for c in na if c["outcome"] == "ACTED"), ctrl,
        sum(1 for c in na if c["outcome"] == "ASKED"),
        pct(sum(1 for c in na if c["outcome"] == "ASKED"), len(na))))

    cmdonly = [c for c in ar if c["has_cmd"]]
    isl = [c for c in cmdonly if c["act_is_line"]]
    nol = [c for c in cmdonly if not c["act_is_line"]]
    a = sum(1 for c in isl if c["outcome"] == "ACTED")
    b = len(isl) - a
    cc = sum(1 for c in nol if c["outcome"] == "ACTED")
    d = len(nol) - cc
    orr, p = fisher_exact(a, b, cc, d)
    print("\n  W1 R4 (runnability held fixed — every close contains a command):")
    print("     act IS its own line    ACTED %3d/%3d = %5.1f%%   [W1: 35.4%%]" % (a, len(isl), pct(a, len(isl))))
    print("     act NEVER its own line ACTED %3d/%3d = %5.1f%%   [W1:  9.4%%]" % (cc, len(nol), pct(cc, len(nol))))
    print("     Fisher exact two-tailed p = %.3g   OR = %.2f   [W1: p=2.7e-05]" % (p, orr))
    ok = (ctrl < 8.0) and (pct(a, len(isl)) > pct(cc, len(nol))) and p < 0.05
    print("\n  INSTRUMENT VERDICT: %s" % (
        "REPRODUCES W1 — proceed" if ok else "DOES NOT REPRODUCE W1 — debug before believing anything below"))
    return ok, {"control_pct": ctrl, "isline": (a, len(isl)), "noline": (cc, len(nol)), "p": p}


def deciles(vals, k=10):
    s = sorted(vals)
    if not s:
        return []
    return [s[min(len(s) - 1, int(round(i * len(s) / k)))] for i in range(1, k)]


def qa_length(pop, field, label):
    print("\n" + "=" * 78)
    print("Q-A — does LENGTH (%s) predict ACTED, with act-is-a-line held FIXED?" % label)
    print("=" * 78)
    replied = [c for c in pop if c["outcome"] is not None and c["act_required"]]
    out = {}
    for stratum, sel in (("act IS its own line", True), ("act NOT its own line", False)):
        S = [c for c in replied if c["act_is_line"] is sel]
        acted = [c[field] for c in S if c["outcome"] == "ACTED"]
        notac = [c[field] for c in S if c["outcome"] != "ACTED"]
        u, p, n1, n2 = mannwhitney(acted, notac)
        med_a = sorted(acted)[len(acted) // 2] if acted else float("nan")
        med_n = sorted(notac)[len(notac) // 2] if notac else float("nan")
        print("\n  STRATUM: %s   (n=%d, ACTED %d)" % (stratum, len(S), len(acted)))
        print("    median %s | ACTED   = %8.1f   (n=%d)" % (label, med_a, n1))
        print("    median %s | notACTED= %8.1f   (n=%d)" % (label, med_n, n2))
        print("    Mann-Whitney U two-sided p = %.4g%s" % (
            p, "" if min(n1, n2) >= 10 else "   <- cell too small to support a claim"))
        out[stratum] = {"n": len(S), "n_acted": n1, "median_acted": med_a,
                        "median_not": med_n, "p": p}
    return out


def qb_bend(pop, field, label, nbin=10):
    print("\n" + "=" * 78)
    print("Q-B — where does the curve bend? ACTED rate by %s decile, per stratum" % label)
    print("=" * 78)
    replied = [c for c in pop if c["outcome"] is not None and c["act_required"]]
    res = {}
    for stratum, sel in (("act IS its own line", True), ("act NOT its own line", False)):
        S = [c for c in replied if c["act_is_line"] is sel]
        S.sort(key=lambda c: c[field])
        print("\n  STRATUM: %s  (n=%d)" % (stratum, len(S)))
        if len(S) < nbin * 3:
            print("    n too small for %d bins — using quartiles" % nbin)
            k = 4
        else:
            k = nbin
        rows = []
        for i in range(k):
            lo = int(i * len(S) / k)
            hi = int((i + 1) * len(S) / k)
            chunk = S[lo:hi]
            if not chunk:
                continue
            a = sum(1 for c in chunk if c["outcome"] == "ACTED")
            rows.append((chunk[0][field], chunk[-1][field], a, len(chunk)))
            bar = "#" * int(round(pct(a, len(chunk)) / 4))
            small = "" if len(chunk) >= 15 else "  <- n<15, not a claim"
            print("    %5.0f-%5.0f %s   n=%3d  ACTED %3d (%5.1f%%) %s%s" % (
                rows[-1][0], rows[-1][1], label[:5], len(chunk), a,
                pct(a, len(chunk)), bar, small))
        res[stratum] = rows
    return res


def qc_structure(pop):
    print("\n" + "=" * 78)
    print("Q-C — do structural elements predict ACTED? (act-is-a-line held fixed)")
    print("=" * 78)
    replied = [c for c in pop if c["outcome"] is not None and c["act_required"]]
    feats = [("table", "markdown table"), ("fenced_block", "fenced code block"),
             ("cso_block", "Complication/Solution/Outcome"), ("good_to_close", "'Good to close:' line"),
             ("headings_gt3", ">3 headings"), ("bullets_gt10", ">10 bullet lines")]
    res = {}
    for stratum, sel in (("act IS its own line", True), ("act NOT its own line", False)):
        S = [c for c in replied if c["act_is_line"] is sel]
        print("\n  STRATUM: %s  (n=%d)" % (stratum, len(S)))
        print("    %-32s  with            without          Fisher p" % "feature")
        for key, name in feats:
            W = [c for c in S if c[key]]
            O = [c for c in S if not c[key]]
            a = sum(1 for c in W if c["outcome"] == "ACTED"); b = len(W) - a
            cc = sum(1 for c in O if c["outcome"] == "ACTED"); d = len(O) - cc
            orr, p = fisher_exact(a, b, cc, d)
            small = " *" if min(len(W), len(O)) < 15 else "  "
            print("    %-32s  %3d/%3d %5.1f%%   %3d/%3d %5.1f%%   p=%-8.3g%s" % (
                name, a, len(W), pct(a, len(W)), cc, len(O), pct(cc, len(O)), p, small))
            res[(stratum, key)] = (a, len(W), cc, len(O), p)
    # MULTIPLICITY. Twelve tests are run above. At alpha=0.05 one nominal hit is
    # the EXPECTED yield of pure noise, so an uncorrected p just under .05 here
    # is not a finding — it is the arithmetic. Corrected verdict, stated inline
    # so a reader cannot take the nominal column at face value.
    ntests = len(res)
    alpha = 0.05 / ntests if ntests else 0.05
    print("\n    * = a cell has n<15; that row is not a claim.")
    print("    MULTIPLICITY: %d tests -> Bonferroni alpha = %.5f" % (ntests, alpha))
    surv = [(k, v[4]) for k, v in res.items() if v[4] < alpha]
    if surv:
        for (stratum, key), pv in sorted(surv, key=lambda t: t[1]):
            print("      SURVIVES: %-16s in [%s]  p=%.4g" % (key, stratum, pv))
    else:
        print("      SURVIVES: none — every structural signal above is within noise.")
    return res


def qc_cso_standalone(pop):
    print("\n" + "=" * 78)
    print("Q-C(ii) — Complication/Solution/Outcome, its own contingency table")
    print("=" * 78)
    replied = [c for c in pop if c["outcome"] is not None]
    for scope, S in (("ALL rung-carrying closes with a human reply", replied),
                     ("act-required only", [c for c in replied if c["act_required"]])):
        W = [c for c in S if c["cso_block"]]
        O = [c for c in S if not c["cso_block"]]
        a = sum(1 for c in W if c["outcome"] == "ACTED"); b = len(W) - a
        cc = sum(1 for c in O if c["outcome"] == "ACTED"); d = len(O) - cc
        orr, p = fisher_exact(a, b, cc, d)
        print("\n  %s" % scope)
        print("                      ACTED   not-ACTED   total")
        print("    C/S/O present   %5d   %9d   %5d" % (a, b, len(W)))
        print("    C/S/O absent    %5d   %9d   %5d" % (cc, d, len(O)))
        print("    Fisher exact two-tailed p = %.4g   OR = %.2f" % (p, orr))
        if len(W) < 15:
            print("    n(present)=%d — TOO SMALL to support a claim." % len(W))
    npop = sum(1 for c in pop if c["cso_block"])
    print("\n  prevalence in the whole population: %d/%d = %.1f%%" % (npop, len(pop), pct(npop, len(pop))))


def qd_facts(pop, field="words_exfence"):
    print("\n" + "=" * 78)
    print("Q-D — does FACT COUNT grow with length, or plateau?")
    print("=" * 78)
    S = sorted(pop, key=lambda c: c[field])
    k = 10
    print("  %-14s %5s  %8s %8s %8s %8s %8s" % ("words bucket", "n", "facts", "sha", "path", "tick", "num"))
    prev = None
    plateau_at = None
    rows = []
    for i in range(k):
        lo = int(i * len(S) / k); hi = int((i + 1) * len(S) / k)
        ch = S[lo:hi]
        if not ch:
            continue
        mean = sum(c["n_facts"] for c in ch) / len(ch)
        rows.append((ch[0][field], ch[-1][field], len(ch), mean))
        print("  %5.0f-%-8.0f %5d  %8.1f %8.1f %8.1f %8.1f %8.1f" % (
            ch[0][field], ch[-1][field], len(ch), mean,
            sum(c["n_sha"] for c in ch) / len(ch),
            sum(c["n_path"] for c in ch) / len(ch),
            sum(c["n_tick"] for c in ch) / len(ch),
            sum(c["n_numunit"] for c in ch) / len(ch)))
    # facts-per-word by bucket: the fluff line is where marginal facts/word collapses
    print("\n  MARGINAL facts per additional 100 words, bucket to bucket:")
    for i in range(1, len(rows)):
        dw = rows[i][3] - rows[i - 1][3]
        dx = ((rows[i][0] + rows[i][1]) / 2.0) - ((rows[i - 1][0] + rows[i - 1][1]) / 2.0)
        marg = (100.0 * dw / dx) if dx else float("nan")
        print("    %5.0f -> %5.0f words:  %+6.2f facts / 100 words" % (
            (rows[i - 1][0] + rows[i - 1][1]) / 2.0, (rows[i][0] + rows[i][1]) / 2.0, marg))
    return rows


def qe_acts(pop):
    print("\n" + "=" * 78)
    print("Q-E — how many DISTINCT operator-directed acts does a close contain?")
    print("=" * 78)
    ar = [c for c in pop if c["act_required"]]
    dist = Counter(min(c["n_acts"], 8) for c in ar)
    tot = len(ar)
    print("  among act-required closes (n=%d):" % tot)
    for k in sorted(dist):
        lbl = "%d" % k if k < 8 else "8+"
        print("    %2s act(s)  %4d  (%5.1f%%)  %s" % (lbl, dist[k], pct(dist[k], tot), "#" * int(pct(dist[k], tot) / 2)))
    multi = sum(v for k, v in dist.items() if k >= 2)
    print("\n  >=2 distinct acts: %d/%d = %.1f%%" % (multi, tot, pct(multi, tot)))
    replied = [c for c in ar if c["outcome"] is not None]
    print("\n  ACTED by act count:")
    for band, sel in (("exactly 1 act", lambda c: c["n_acts"] == 1),
                      ("2 acts", lambda c: c["n_acts"] == 2),
                      ("3+ acts", lambda c: c["n_acts"] >= 3)):
        S = [c for c in replied if sel(c)]
        a = sum(1 for c in S if c["outcome"] == "ACTED")
        print(rate_line(band, a, len(S)))
    return dist


def decorrelate(pop):
    print("\n" + "=" * 78)
    print("DECORRELATION — is a length effect just 'hard sessions are longer'?")
    print("=" * 78)
    replied = [c for c in pop if c["outcome"] is not None and c["act_required"]]
    # 1) within rung
    print("\n  (1) within rung — a ⛔ close and a ✅ close are different difficulties")
    for g in RUNGS:
        S = [c for c in replied if c["rung"] == g]
        if len(S) < 20:
            continue
        acted = [c["words_exfence"] for c in S if c["outcome"] == "ACTED"]
        notac = [c["words_exfence"] for c in S if c["outcome"] != "ACTED"]
        u, p, n1, n2 = mannwhitney(acted, notac)
        ma = sorted(acted)[len(acted) // 2] if acted else float("nan")
        mn = sorted(notac)[len(notac) // 2] if notac else float("nan")
        print("    %s n=%3d  median words ACTED=%6.0f  notACTED=%6.0f  MWU p=%.3g%s" % (
            g, len(S), ma, mn, p, "" if min(n1, n2) >= 10 else "  <- small"))
    # 2) within has-command
    print("\n  (2) within runnability")
    for lbl, sel in (("has a command", True), ("no command", False)):
        S = [c for c in replied if c["has_cmd"] is sel]
        if len(S) < 20:
            print("    %-14s n=%d — too small" % (lbl, len(S)))
            continue
        acted = [c["words_exfence"] for c in S if c["outcome"] == "ACTED"]
        notac = [c["words_exfence"] for c in S if c["outcome"] != "ACTED"]
        u, p, n1, n2 = mannwhitney(acted, notac)
        ma = sorted(acted)[len(acted) // 2] if acted else float("nan")
        mn = sorted(notac)[len(notac) // 2] if notac else float("nan")
        print("    %-14s n=%3d  median ACTED=%6.0f  notACTED=%6.0f  MWU p=%.3g" % (
            lbl, len(S), ma, mn, p))
    # 3) multivariate
    print("\n  (3) logistic: ACTED ~ act_is_line + log(words) + has_cmd + rung(⛔) + rung(👤)")
    X, y = [], []
    for c in replied:
        w = max(1, c["words_exfence"])
        X.append([1.0 if c["act_is_line"] else 0.0,
                  math.log(w),
                  1.0 if c["has_cmd"] else 0.0,
                  1.0 if c["rung"] == "⛔" else 0.0,
                  1.0 if c["rung"] == "👤" else 0.0])
        y.append(1 if c["outcome"] == "ACTED" else 0)
    names = ["act_is_line", "log(words)", "has_cmd", "rung=⛔", "rung=👤"]
    if len(y) >= 40 and 0 < sum(y) < len(y):
        for nm, b, se, z, p in logistic(X, y, names):
            star = " ***" if p == p and p < 0.001 else (" **" if p == p and p < 0.01 else (" *" if p == p and p < 0.05 else ""))
            print("    %-14s beta=%+7.3f  se=%5.3f  z=%+6.2f  p=%-9.3g%s" % (nm, b, se, z, p, star))
        print("    (n=%d, ACTED=%d)" % (len(y), sum(y)))
    else:
        print("    n too small for a multivariate fit")


def era_drift(pop):
    """
    ADVERSARIAL A1. The corpus spans more than one regime (the ▶ convention
    landed 2026-08-01, CLOSE_INTEGRITY 2026-08-10). If ACTED and length both move
    between eras, a pooled null could be a Simpson's-paradox artifact. Test the
    Q-A null WITHIN each era before believing the pooled one.
    """
    import datetime
    print("\n" + "=" * 78)
    print("A1 — ERA DRIFT, and the Q-A null re-tested inside each era")
    print("=" * 78)
    rep = [c for c in pop if c["outcome"] is not None and c["act_required"]]

    def era(c):
        return datetime.datetime.fromtimestamp(c["mtime"]).strftime("%Y-%m")

    print("  %-9s %5s %8s %9s %9s" % ("month", "n", "ACTED%", "isline%", "medwords"))
    for m in sorted(set(era(c) for c in rep)):
        S = [c for c in rep if era(c) == m]
        if len(S) < 15:
            continue
        a = sum(1 for c in S if c["outcome"] == "ACTED")
        il = sum(1 for c in S if c["act_is_line"])
        mw = sorted(c["words_exfence"] for c in S)[len(S) // 2]
        print("  %-9s %5d %7.1f%% %8.1f%% %9d" % (m, len(S), pct(a, len(S)), pct(il, len(S)), mw))
    print("\n  Q-A null re-tested within era (act-is-a-line stratum):")
    for m in sorted(set(era(c) for c in rep)):
        S = [c for c in rep if era(c) == m and c["act_is_line"]]
        if len(S) < 30:
            continue
        ac = [c["words_exfence"] for c in S if c["outcome"] == "ACTED"]
        no = [c["words_exfence"] for c in S if c["outcome"] != "ACTED"]
        u, pv, n1, n2 = mannwhitney(ac, no)
        ma = sorted(ac)[len(ac) // 2] if ac else float("nan")
        mn = sorted(no)[len(no) // 2] if no else float("nan")
        print("    %s n=%3d  medwords ACTED=%4.0f notACTED=%4.0f  MWU p=%.3f" % (m, len(S), ma, mn, pv))


def tail_scan(pop):
    """
    ADVERSARIAL A2. Q-A's rank test asks whether the whole length DISTRIBUTION
    shifts. It is underpowered against a pure THRESHOLD effect confined to a far
    tail. Scan thresholds explicitly — and correct for having scanned them, or
    this becomes a p-hacked "the curve bends at X".
    """
    print("\n" + "=" * 78)
    print("A2 — THRESHOLD SCAN in the act-is-a-line stratum (multiplicity-corrected)")
    print("=" * 78)
    S = [c for c in pop if c["outcome"] is not None and c["act_required"] and c["act_is_line"]]
    thrs = (200, 250, 300, 350, 400, 450, 500, 600, 800)
    alpha = 0.05 / len(thrs)
    print("  %d thresholds scanned -> Bonferroni alpha = %.4f" % (len(thrs), alpha))
    for t in thrs:
        hi = [c for c in S if c["words_exfence"] > t]
        lo = [c for c in S if c["words_exfence"] <= t]
        a = sum(1 for c in hi if c["outcome"] == "ACTED"); b = len(hi) - a
        cc = sum(1 for c in lo if c["outcome"] == "ACTED"); d = len(lo) - cc
        orr, pv = fisher_exact(a, b, cc, d)
        mark = "SURVIVES" if pv < alpha else ("nominal" if pv < 0.05 else "")
        print("   >%4dw  %3d/%3d=%5.1f%%   <=  %3d/%3d=%5.1f%%   OR=%.2f  p=%.4f  %s" % (
            t, a, len(hi), pct(a, len(hi)), cc, len(lo), pct(cc, len(lo)), orr, pv, mark))


def structure_vs_length(pop):
    """
    ADVERSARIAL A3. Any structural feature that survives Q-C is confounded with
    length by construction (more headings = more words). If length is null and a
    structural feature is not, the feature must be carrying something length is
    not — prove that by fitting them together rather than asserting it.
    """
    print("\n" + "=" * 78)
    print("A3 — is a surviving structural signal just a proxy for LENGTH?")
    print("=" * 78)
    S = [c for c in pop if c["outcome"] is not None and c["act_required"] and c["act_is_line"]]
    H = [c for c in S if c["headings_gt3"]]
    N = [c for c in S if not c["headings_gt3"]]
    if H and N:
        print("  >3 headings   n=%3d  median words=%5.0f" % (
            len(H), sorted(c["words_exfence"] for c in H)[len(H) // 2]))
        print("  <=3 headings  n=%3d  median words=%5.0f" % (
            len(N), sorted(c["words_exfence"] for c in N)[len(N) // 2]))
    X = [[1.0 if c["headings_gt3"] else 0.0,
          math.log(max(1, c["words_exfence"])),
          1.0 if c["table"] else 0.0] for c in S]
    y = [1 if c["outcome"] == "ACTED" else 0 for c in S]
    if len(y) >= 40 and 0 < sum(y) < len(y):
        print("  logistic ACTED ~ headings_gt3 + log(words) + table   (n=%d, ACTED=%d)" % (len(y), sum(y)))
        for nm, b, se, z, pv in logistic(X, y, ["headings_gt3", "log(words)", "table"]):
            print("    %-14s beta=%+7.3f  se=%5.3f  z=%+6.2f  p=%.4g" % (nm, b, se, z, pv))
    if len(H) < 30:
        print("  NOTE: n(>3 headings)=%d — a signal worth a follow-up, NOT a number to design on." % len(H))


def fact_density(pop):
    """
    Q-D, done so the answer is not a bucketing artifact. The first cut of this
    used 10 equal-n buckets over the WHOLE range; its top bucket spanned
    457-6722 words, so the midpoint-based marginal read '+1.70 facts/100 words'
    and looked exactly like a plateau. It was the bucket's width, not the corpus.
    Capping the tail and using 20 buckets removes it.
    """
    print("\n" + "=" * 78)
    print("Q-D(ii) — fact DENSITY vs length (tail-capped; the plateau test done properly)")
    print("=" * 78)
    S = sorted([c for c in pop if c["words_all"] <= 1200], key=lambda c: c["words_all"])
    print("  n=%d (closes over 1200 words excluded: %d)" % (len(S), len(pop) - len(S)))
    print("  %-16s %5s %10s %11s %13s" % ("words", "n", "facts", "facts/100w", "ex-backtick/100w"))
    k = 12
    for i in range(k):
        lo = int(i * len(S) / k); hi = int((i + 1) * len(S) / k)
        ch = S[lo:hi]
        if not ch:
            continue
        mw = sum(c["words_all"] for c in ch) / len(ch)
        mf = sum(c["n_facts"] for c in ch) / len(ch)
        mnt = sum(c["n_sha"] + c["n_path"] + c["n_numunit"] for c in ch) / len(ch)
        print("  %6.0f-%-9.0f %5d %10.1f %11.2f %13.2f" % (
            ch[0]["words_all"], ch[-1]["words_all"], len(ch), mf, 100 * mf / mw, 100 * mnt / mw))
    tot = sum(c["n_facts"] for c in pop) or 1
    print("\n  composition of the fact proxy (so its bias is visible):")
    for key in ("n_sha", "n_path", "n_tick", "n_numunit"):
        v = sum(c[key] for c in pop)
        print("    %-10s %8d  (%4.1f%%)" % (key, v, pct(v, tot)))
    print("  Backtick spans are %.0f%% of the proxy, so the ex-backtick column is the"
          % pct(sum(c["n_tick"] for c in pop), tot))
    print("  robustness check: if both columns are flat, the null is not a backtick artifact.")


def line1_cap(pop):
    """
    THE OTHER HALF OF THE SHIPPED RULE. CLAUDE.md caps a close at TWO things —
    "line 1 <= 30 words" and "the whole close <= 120 words". Q-A tests the second.
    Testing only the second and then reporting on "the word cap" would be a span
    error: the assertion would not cover its own subject.
    """
    print("\n" + "=" * 78)
    print("A4 — the 'line 1 <= 30 words' half of the shipped rule, tested directly")
    print("=" * 78)
    rep = [c for c in pop if c["outcome"] is not None and c["act_required"]]
    for c in rep:
        first = ""
        for n, raw in unfenced_lines(c["text"]):
            first = raw.strip()
            break
        c["l1_words"] = len(first.split())
    v = sorted(c["l1_words"] for c in rep)
    if not v:
        return
    print("  line-1 words: min=%d p25=%d median=%d p75=%d p90=%d max=%d" % (
        v[0], v[len(v) // 4], v[len(v) // 2], v[3 * len(v) // 4], v[int(0.9 * len(v))], v[-1]))
    over = sum(1 for c in rep if c["l1_words"] > 30)
    print("  over the shipped 30-word line-1 cap: %d/%d = %.1f%%" % (over, len(rep), pct(over, len(rep))))
    for stratum, sel in (("act IS its own line", True), ("act NOT its own line", False)):
        S = [c for c in rep if c["act_is_line"] is sel]
        ac = [c["l1_words"] for c in S if c["outcome"] == "ACTED"]
        no = [c["l1_words"] for c in S if c["outcome"] != "ACTED"]
        u, pv, n1, n2 = mannwhitney(ac, no)
        print("  %-22s n=%3d  median line-1 ACTED=%3.0f notACTED=%3.0f  MWU p=%.4f" % (
            stratum, len(S), sorted(ac)[len(ac) // 2] if ac else float("nan"),
            sorted(no)[len(no) // 2] if no else float("nan"), pv))
    S = [c for c in rep if c["act_is_line"]]
    hi = [c for c in S if c["l1_words"] > 30]
    lo = [c for c in S if c["l1_words"] <= 30]
    a = sum(1 for c in hi if c["outcome"] == "ACTED"); b = len(hi) - a
    cc = sum(1 for c in lo if c["outcome"] == "ACTED"); d = len(lo) - cc
    orr, pv = fisher_exact(a, b, cc, d)
    print("\n  2x2 AT THE SHIPPED CAP (act-is-a-line stratum):")
    print("    line 1 >30 words : ACTED %3d/%3d = %5.1f%%" % (a, len(hi), pct(a, len(hi))))
    print("    line 1 <=30 words: ACTED %3d/%3d = %5.1f%%" % (cc, len(lo), pct(cc, len(lo))))
    print("    Fisher exact two-tailed p = %.4f   OR = %.2f" % (pv, orr))
    if orr > 1:
        print("    DIRECTION: the point estimate runs AGAINST the cap — a LONGER line 1 is")
        print("    acted on MORE often, not less. See the doc for the specificity confound.")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=float, default=14, help="mtime window in days (default 14 = W1's)")
    ap.add_argument("--limit", type=int, default=0, help="cap the population to the N most recent (0 = uncapped)")
    ap.add_argument("--length-field", default="words_exfence",
                    choices=["words_all", "words_exfence", "lines_all", "lines_exfence", "chars_all"])
    ap.add_argument("--json", default="", help="dump per-close rows to this path")
    a = ap.parse_args()

    print("=" * 78)
    print("MEASURE-CLOSES — window %g days, limit %s, length field %s" % (
        a.days, a.limit or "uncapped", a.length_field))
    print("run at %s" % time.strftime("%Y-%m-%dT%H:%M:%S%z"))
    print("=" * 78)

    pop, per_root = build(a.days, a.limit)
    if not pop:
        print("EMPTY POPULATION — nothing to report")
        return 1

    print("\nRUNG DISTRIBUTION")
    rd = Counter(c["rung"] for c in pop)
    for g in RUNGS:
        if rd.get(g):
            print("  %s  %5d  (%5.1f%%)" % (g, rd[g], pct(rd[g], len(pop))))
    ar = [c for c in pop if c["act_required"]]
    print("\nOPERATOR ACT REQUIRED: %d/%d (%.1f%%)" % (len(ar), len(pop), pct(len(ar), len(pop))))
    tc = Counter()
    for c in ar:
        for t in c["trig"]:
            tc[t] += 1
    print("  by trigger: " + " · ".join("%s = %d" % (k, v) for k, v in tc.most_common()))

    print("\nACT LINE INDEX (n=%d, closes requiring an operator act)" % len(ar))
    bands = [("line     1", lambda i: i == 1), ("line   2-3", lambda i: i in (2, 3)),
             ("line   4-6", lambda i: 4 <= i <= 6), ("line  7-12", lambda i: 7 <= i <= 12),
             ("line   >12", lambda i: i > 12)]
    for lbl, sel in bands:
        n = sum(1 for c in ar if c["act_idx"] and sel(c["act_idx"]))
        print("  %-11s %4d  (%5.1f%%)  %s" % (lbl, n, pct(n, len(ar)), "#" * int(pct(n, len(ar)) / 2)))
    nev = sum(1 for c in ar if not c["act_idx"])
    print("  %-11s %4d  (%5.1f%%)  %s" % ("line never", nev, pct(nev, len(ar)), "#" * int(pct(nev, len(ar)) / 2)))
    idxs = sorted(c["act_idx"] for c in ar if c["act_idx"])
    if idxs:
        print("  median (where stated at all): %d      p90: %d" % (
            idxs[len(idxs) // 2], idxs[min(len(idxs) - 1, int(0.9 * len(idxs)))]))

    print("\nLENGTH DISTRIBUTION (population)")
    for f in ("words_all", "words_exfence", "lines_all", "lines_exfence"):
        v = sorted(c[f] for c in pop)
        print("  %-14s min=%5d  p25=%5d  median=%5d  p75=%5d  p90=%5d  max=%6d" % (
            f, v[0], v[len(v) // 4], v[len(v) // 2], v[3 * len(v) // 4],
            v[int(0.9 * len(v))], v[-1]))
    over = sum(1 for c in pop if c["words_exfence"] > 120)
    print("  over the CLAUDE.md 120-word cap (ex-fence): %d/%d = %.1f%%" % (
        over, len(pop), pct(over, len(pop))))

    conservation(pop)
    ok, w1 = w1_check(pop)

    qa_length(pop, a.length_field, a.length_field)
    if a.length_field != "lines_exfence":
        qa_length(pop, "lines_exfence", "lines_exfence")
    qb_bend(pop, a.length_field, a.length_field)
    qc_structure(pop)
    qc_cso_standalone(pop)
    qd_facts(pop, a.length_field)
    fact_density(pop)
    qe_acts(pop)
    decorrelate(pop)
    era_drift(pop)
    tail_scan(pop)
    structure_vs_length(pop)
    line1_cap(pop)

    if a.json:
        with open(a.json, "w") as fh:
            for c in pop:
                row = {k: v for k, v in c.items() if k not in ("text", "reply_text")}
                fh.write(json.dumps(row, default=str) + "\n")
        print("\nper-close rows -> %s" % a.json)
    print("\nDONE. Every figure above is dated by its window and decays with the corpus.")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
