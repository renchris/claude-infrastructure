#!/usr/bin/env python3
"""kill-selection.py — what would this pattern kill SELECT, if it ran right now?

Called by hooks/validate-bash.sh (PreToolUse) with the heredoc-stripped command text. Tokenises it
with shlex (punctuation-aware, so a `pkill` inside a quoted message body is a string, never a
command), finds every pkill / killall segment in COMMAND position — plus every pgrep segment whose
output feeds a kill (`pgrep … | xargs kill`, `kill $(pgrep …)`) — and asks the REAL pgrep what each
one selects. Every selected pid is then classified by walking its ancestry:

    OWN       the walk reaches SELF_ROOT (the caller's own Claude session) first
    FOREIGN   the walk meets a process whose argv[0] basename is `claude` before SELF_ROOT —
              the victim IS another live Claude session, or lives inside one
    UNOWNED   the walk reaches launchd without meeting either (Dock, a dev server the operator
              started by hand, …) — none of this gate's business

One line per FOREIGN segment on stdout, tab-separated:
    FOREIGN <tab> <segment text> <tab> <n foreign> <tab> <victim descriptions ' · '> <tab> <awaitping 0|1>
Nothing on stdout when every segment is OWN / UNOWNED / empty. ABSTAIN lines (dynamic tokens,
unparseable text, pgrep unavailable) go to stderr so the hook can log them without acting.

WHY THE SELECTION AND NOT THE SPELLING. On this fleet a Claude session's argv carries its entire
brief (`claude … "$(cat handoff-prompt-…)"`, 6-10 KB), so `pkill -f X` matches every sibling whose
PROMPT mentions X. Three incidents, one mechanism, three different spellings:
    2026-08-09  pkill -f "next dev" -P $$        3 sessions   (a spelling-keyed clause was added)
    2026-08-25  pkill -f "cc-await-ping"         1 session + 3 watchers   (forensics only)
    2026-09-04  pkill -f "cc-await-ping"         5 sessions in 30 s → five panes at a bare shell
A guard keyed on the pattern text can only ever enumerate the spellings already paid for
(MEMORY: denylist-enumerates-spellings-not-the-class). The harm is a property of the SELECTION —
"does it include a process that belongs to another session?" — and that is decidable before the
kill runs, with the same pgrep the kill would use.

Usage: kill-selection.py <command text> <self-root pid> <registry dir>
"""
import glob
import json
import os
import re
import shlex
import subprocess
import sys

SIG_RE = re.compile(
    r"^-(\d+|(SIG)?(HUP|INT|QUIT|ILL|TRAP|ABRT|EMT|FPE|KILL|BUS|SEGV|SYS|PIPE|ALRM|TERM|URG|STOP|TSTP"
    r"|CONT|CHLD|TTIN|TTOU|IO|XCPU|XFSZ|VTALRM|PROF|WINCH|INFO|USR1|USR2))$",
    re.I,
)
SESSION_RE = re.compile(os.environ.get("CC_KILL_GATE_SESSION_RE") or r"^claude(-|$)")
VERBS = ("pkill", "killall", "pgrep")
PREFIX_WORDS = ("sudo", "nice", "nohup", "command", "exec")   # transparent wrappers before the verb
PUNCT = ";&|()"


def abstain(why):
    sys.stderr.write("ABSTAIN\t%s\n" % why)


def tokenize(cmd):
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=PUNCT)
    lex.whitespace_split = True
    return list(lex)


def segments(tokens):
    """Split on punctuation tokens; yield each command segment (list of tokens)."""
    seg = []
    for t in tokens:
        if t and all(c in PUNCT for c in t):
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


REDIR_RE = re.compile(r"^(\d*(>>?|<<?<?)&?\d*|&>>?)")


def strip_redirects(seg):
    """Drop shell redirections — the shell consumes them, pkill never sees them. Caught by the
    smoke run: a trailing `2>/dev/null` reached pgrep as a SECOND pattern and matched every shell on
    the box whose argv carried that text — nine innocent panes convicted by the guard's own probe."""
    out, i = [], 0
    while i < len(seg):
        t = seg[i]
        m = REDIR_RE.match(t)
        if m:
            if m.end() == len(t) and not t.endswith("&") and re.search(r"[<>]$", t):
                i += 2                                  # bare operator: its target is the next token
            else:
                i += 1
            continue
        out.append(t)
        i += 1
    return out


def strip_prefix(seg):
    seg = strip_redirects(seg)
    i = 0
    while i < len(seg):
        t = seg[i]
        if t in PREFIX_WORDS:
            i += 1
            continue
        if t == "timeout":                       # timeout [-k N] [-s SIG] DURATION cmd…
            i += 1
            while i < len(seg) and seg[i].startswith("-"):
                i += 2
            i += 1
            continue
        if t == "env" or ("=" in t and not t.startswith("-")):
            i += 1
            continue
        break
    return seg[i:]


def run_pgrep(argv):
    try:
        r = subprocess.run(["pgrep"] + argv, capture_output=True, text=True, timeout=5)
    except Exception as e:                        # noqa: BLE001 — any failure is an abstention
        abstain("pgrep failed: %s" % e)
        return None
    pids = set()
    for line in r.stdout.splitlines():
        m = re.match(r"\s*(\d+)", line)
        if m:
            pids.add(int(m.group(1)))
    return pids


def selection_for(seg):
    """Map one pkill/killall/pgrep segment to the pid set it selects, or None (abstain)."""
    verb = os.path.basename(seg[0])
    args = seg[1:]
    if any("$" in a or "`" in a for a in args):
        abstain("dynamic pattern in '%s'" % " ".join(seg)[:80])
        return None
    if verb == "killall":
        names, extra, regex = [], [], False
        i = 0
        while i < len(args):
            a = args[i]
            if a in ("-u", "-t") and i + 1 < len(args):
                extra += [a, args[i + 1]]
                i += 2
                continue
            if a == "-c" and i + 1 < len(args):
                names.append(args[i + 1])
                i += 2
                continue
            if a == "-m":
                regex = True
            elif not a.startswith("-"):
                names.append(a)
            i += 1
        if not names or any(n.startswith("-") for n in names):
            abstain("killall without a plain name")
            return None
        pids = set()
        for n in names:
            sel = run_pgrep(extra + ([] if regex else ["-x"]) + [n])
            if sel is None:
                return None
            pids |= sel
        return pids
    # pkill / pgrep: keep the SELECTION options, drop signal + output options.
    consume = {"-F", "-G", "-P", "-U", "-g", "-t", "-u", "-s", "-j"}
    drop = {"-l", "-a", "-c", "-q", "-I", "-L"}
    pg, i = [], 0
    while i < len(args):
        a = args[i]
        if a in ("-v", "--inverse"):
            abstain("inverted selection")
            return None
        if SIG_RE.match(a):
            i += 1
            continue
        if a == "-d":
            i += 2
            continue
        if a in consume:
            pg += [a] + ([args[i + 1]] if i + 1 < len(args) else [])
            i += 2
            continue
        if a in drop:
            i += 1
            continue
        if a.startswith("-") and not a.startswith("--") and len(a) > 2:
            letters = a[1:]
            if letters.isdigit():
                i += 1
                continue
            if "v" in letters:
                abstain("inverted selection")
                return None
            for ch in letters:
                if ch in "lacqIL" or ch.isdigit():          # -9f: the digit is the signal, not a flag
                    continue
                pg.append("-" + ch)
            if letters[-1] in "FGPUgtusj" and i + 1 < len(args):
                pg.append(args[i + 1])
                i += 1
            i += 1
            continue
        pg.append(a)
        i += 1
    if not [t for t in pg if not t.startswith("-")] and not ({"-P", "-t", "-u", "-U", "-g", "-G"} & set(pg)):
        return set()                                       # no pattern, nothing selected
    return run_pgrep(pg)


def ps_table():
    try:
        r = subprocess.run(["ps", "-axo", "pid=,ppid=,comm="], capture_output=True, text=True, timeout=5)
    except Exception:                                       # noqa: BLE001
        return {}
    t = {}
    for line in r.stdout.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 2:
            continue
        try:
            t[int(parts[0])] = (int(parts[1]), parts[2] if len(parts) > 2 else "")
        except ValueError:
            pass
    return t


def registry(regdir):
    m = {}
    for f in glob.glob(os.path.join(regdir, "*.json")):
        try:
            with open(f) as fh:
                row = json.load(fh)
            pid = int(row.get("pid") or 0)
            if pid:
                m[pid] = row.get("name") or ("session " + str(row.get("session_id") or "")[:8])
        except Exception:                                   # noqa: BLE001
            continue
    return m


def classify(pid, table, self_root):
    p, hops = pid, 0
    while p > 1 and hops < 64 and p in table:
        if p == self_root:
            return "OWN", None
        if SESSION_RE.match(os.path.basename(table[p][1])):
            return "FOREIGN", p
        p = table[p][0]
        hops += 1
    return "UNOWNED", None


def argv_of(pid):
    try:
        r = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception:                                       # noqa: BLE001
        return ""


def main():
    if len(sys.argv) < 4:
        abstain("usage")
        return 0
    cmd, self_root, regdir = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        self_root = int(self_root)
    except ValueError:
        self_root = -1
    try:
        toks = tokenize(cmd)
    except ValueError as e:
        abstain("unparseable: %s" % e)
        return 0
    segs = list(segments(toks))
    feeds_kill = False
    for s in segs:
        sp = strip_prefix(s)
        if (sp and os.path.basename(sp[0]) == "kill") or ("xargs" in s and "kill" in s):
            feeds_kill = True
    table, reg = None, None
    for seg in segs:
        seg = strip_prefix(seg)
        if not seg:
            continue
        verb = os.path.basename(seg[0])
        if verb not in VERBS:
            continue
        if verb == "pgrep" and not feeds_kill:
            continue
        sel = selection_for(seg)
        if not sel:
            continue
        if table is None:
            table, reg = ps_table(), registry(regdir)
        foreign = []
        for pid in sorted(sel):
            kind, spid = classify(pid, table, self_root)
            if kind != "FOREIGN":
                continue
            comm = os.path.basename(table.get(pid, (0, "?"))[1]) or "?"
            if spid in reg:
                who = "LIVE Claude session %s" % reg[spid]
            else:
                who = "an unregistered LIVE Claude session (pid %d)" % spid
            if spid == pid:
                foreign.append("pid %d = %s" % (pid, who))
            else:
                foreign.append("pid %d %s inside %s" % (pid, comm, who))
        if not foreign:
            continue
        awaitping = 0
        for pid in sorted(sel)[:12]:
            if classify(pid, table, self_root)[0] == "FOREIGN" and "cc-await-ping" in argv_of(pid):
                awaitping = 1
                break
        shown = foreign[:6] + (["… +%d more" % (len(foreign) - 6)] if len(foreign) > 6 else [])
        print("FOREIGN\t%s\t%d\t%s\t%d" % (" ".join(seg)[:120], len(foreign), " · ".join(shown), awaitping))
    return 0


if __name__ == "__main__":
    sys.exit(main())
