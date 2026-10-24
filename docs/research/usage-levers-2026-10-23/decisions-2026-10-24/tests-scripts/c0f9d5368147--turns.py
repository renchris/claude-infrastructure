#!/usr/bin/env python3
# Build every main-thread turn of interactive sessions from scan.py output and classify the
# turns opened by a wake with no operator input. Writes turns.jsonl (one row per turn).
# usage: python3 -I turns.py <dir>
import bisect
import collections
import json
import os
import re
import sys

D = sys.argv[1]
S, E = 1791655200.0, 1792864800.0
ACCTS = ["next", "next2", "next3", "next4"]
TUID = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")
STAT = re.compile(r"<status>([a-z_]+)</status>")
SUMM = re.compile(r"<summary>(.*?)</summary>", re.S)

F = []
for a in ACCTS:
    for line in open(os.path.join(D, a + ".jsonl")):
        F.append(json.loads(line))
occ = collections.defaultdict(list)
for k, f in enumerate(F):
    for x in f["reqs"]:
        occ[x[2]].append(k)
owner = {rid: min(v, key=lambda k: F[k]["mt"]) for rid, v in occ.items()}

RO = set(
    """cat tail head ls wc grep rg egrep fgrep jq awk find stat ps pgrep date echo printf sleep test [ [[ true false
cd pwd which file du df lsof sort uniq cut tr column basename dirname realpath readlink env id whoami hostname uptime
vm_stat pmset nl less more diff cmp md5 shasum type command wait seq xxd od strings sw_vers uname tput expr
export for do done while if then fi else elif local set read case esac in { } ( ) ! xargs cc-context cc-memory-search
cc-lr cc-backlog cc-custody cc-mail cc-peek cc-sessions cc-accounts claude-accounts sqlite3 plutil defaults""".split()
)
GIT_RO = set(
    "status log diff show rev-parse branch worktree ls-files fetch remote describe blame reflog cat-file for-each-ref merge-base shortlog ls-tree grep name-rev rev-list".split()
)
GH_RO = {
    "pr": {"view", "list", "checks", "diff", "status"},
    "run": {"view", "list", "watch"},
    "issue": {"view", "list"},
    "api": None,
    "repo": {"view"},
}
WATCH = ("cc-await-ping", "cc-wait")


def seg_ro(seg):
    w = seg.strip().split()
    while w and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0]):
        w = w[1:]
    while w and w[0] in ("timeout", "gtimeout", "nice", "command", "builtin", "time"):
        w = w[1:]
        while w and re.match(r"^-?\d+[smh]?$|^-", w[0]):
            w = w[1:]
    if not w:
        return True
    v = os.path.basename(w[0])
    if v in ("git",):
        rest = [x for x in w[1:] if not x.startswith("-")]
        i = 0
        while i < len(rest) and rest[i] in ("-C",):
            i += 2
        sub = (
            rest[1]
            if rest and rest[0].startswith("/") and len(rest) > 1
            else (rest[0] if rest else "")
        )
        if "-C" in w:
            j = w.index("-C")
            rest2 = [x for x in w[j + 2 :] if not x.startswith("-")]
            sub = rest2[0] if rest2 else ""
        if sub == "stash":
            return "list" in w or "show" in w
        return sub in GIT_RO
    if v == "gh":
        if len(w) > 1 and w[1] in GH_RO:
            ok = GH_RO[w[1]]
            if ok is None:
                return "-X" not in w and "--method" not in w
            return len(w) > 2 and w[2] in ok
        return False
    if v == "sed":
        return "-i" not in w
    if v == "tmux":
        return len(w) > 1 and w[1] in (
            "capture-pane",
            "ls",
            "list-sessions",
            "list-panes",
            "list-windows",
            "display-message",
        )
    if v in ("launchctl",):
        return len(w) > 1 and w[1] in ("list", "print")
    if v == "kitty":
        return len(w) > 2 and w[1] == "@" and w[2] in ("get-text", "ls")
    if v == "python3":
        return False
    if v.startswith("cc-") and any(
        k in v
        for k in ("readout", "status", "sessions", "mail", "ls", "list", "peek", "show")
    ):
        return True
    return v in RO


def bash_ro(cmd):
    if any(k in cmd for k in WATCH):
        return "rearm"
    c2 = re.sub(
        r"\d?>>?\s*(/dev/null|&\d|/tmp/\S*|/private/tmp/\S*)|&>\s*/dev/null|<<-?\s*'?\w+'?",
        " ",
        cmd,
    )
    if re.search(
        r">|\brm\b|\bmv\b|\bcp\b|\bmkdir\b|\btouch\b|\bkill\b|\bpkill\b|\btee\b", c2
    ):
        return "act"
    segs = re.split(r"\|\||&&|\||;|\n|\$\(|`", cmd)
    return "look" if all(seg_ro(s) for s in segs) else "act"


MUT = re.compile(
    r"\bgit\s+(-C\s+\S+\s+)?(commit|push|merge|rebase|reset|checkout|switch|add|tag|cherry-pick|am|apply|pull|restore|clean)\b"
    r"|\bgit\s+(-C\s+\S+\s+)?stash\s+(push|pop|apply|drop)|\bgit\s+(-C\s+\S+\s+)?worktree\s+(add|remove|prune)"
    r"|ship-land|ship\.sh|handoff-fire|cc-notify|cc-mail\s+send|cc-send|session-continue\.sh\s+set|\bkill\b|\bpkill\b|\bkillall\b"
    r"|\brm\s|\bmv\s|\bcp\s|\bmkdir\b|\btouch\b|\bsed\s+-i|\btee\b|\bln\s|\bchmod\b|kitty\s+@\s+(--to\s+\S+\s+)?(send-text|send-key|launch|close)"
    r"|\bosascript\b|\bopen\s|\bclaude\s|\bcc-claude|\bnpm\b|\bpytest\b|\bmake\b|\bcargo\b|\bswift\b|\bxcodebuild\b|\bbrew\b|\bpip\b"
    r"|curl\s.*-X\s*(POST|PUT|DELETE|PATCH)|\bgh\s+(pr|issue|release)\s+(create|merge|comment|close|edit)|\bgh\s+api\s.*-X\s*(POST|PUT|PATCH|DELETE)"
    r"|^\s*(bash|sh|zsh)\s+\S|^\s*\./|&&\s*(bash|sh)\s+\S|\bcc-do\s+--run|\bcrontab\b|\blaunchctl\s+(load|unload|bootstrap|bootout|kickstart)"
)


def bash_class(cmd):
    if any(k in cmd for k in WATCH):
        return "rearm"
    c2 = re.sub(
        r"\d?>>?\s*(/dev/null|&\d|/tmp/\S*|/private/tmp/\S*)|&>\s*/dev/null|<<-?\s*'?\w+'?|=>|->|>=",
        " ",
        cmd,
    )
    c2 = re.sub(r"'[^']*'", "''", c2)
    if MUT.search(c2) or re.search(r"(^|[^-=<])>\s*[~/\w$\"]", c2):
        return "act"
    return "look"


def tool_class(nm, cmd, bg):
    if nm == "Bash":
        return bash_class(cmd)
    if nm in ("Monitor", "ScheduleWakeup"):
        return "rearm"
    if nm in ("TodoWrite", "TaskCreate", "TaskUpdate"):
        return "neutral"
    if nm in (
        "Read",
        "Grep",
        "Glob",
        "TaskOutput",
        "TaskList",
        "TaskGet",
        "BashOutput",
        "ToolSearch",
        "LS",
        "CronList",
    ):
        return "look"
    if nm.startswith("mcp__") and re.search(
        r"list|get|search|read|fetch|find|query", nm.split("__")[-1]
    ):
        return "look"
    return "act"


def ctx(x):
    return x[4] + x[5] + x[8]


fo = open(os.path.join(D, "turns.jsonl"), "w")
ntot = collections.Counter()
for k, f in enumerate(F):
    if not f["eps"].get("cli"):
        ntot["skip_noncli"] += 1
        continue
    L = [x for x in f["reqs"] if owner[x[2]] == k]
    if not L:
        continue
    L.sort(key=lambda x: x[0])
    Lt = [x[0] for x in L]
    O_ = sorted(f["opens"], key=lambda o: o[0])
    Ot = [o[0] for o in O_]
    jobs = f["jobs"]
    # job end: earliest notification carrying its tool-use-id (openers and queued commands)
    jend = {}
    for o in O_:
        for tu in TUID.findall(o[5]):
            jend[tu] = min(o[0], jend.get(tu, o[0]))
    for q in f["qc"]:
        for tu in TUID.findall(q[3]):
            jend[tu] = min(q[0], jend.get(tu, q[0]))
    last_t = L[-1][1]
    bgjobs = []
    for tu, (t0, nm, cmd, bg) in jobs.items():
        if nm == "Bash" and bg and not any(w in cmd for w in WATCH):
            kd = "bash"
        elif nm in ("Agent", "Task") and bg:
            kd = "agent"
        elif nm == "Workflow":
            kd = "workflow"
        else:
            continue
        bgjobs.append((t0, jend.get(tu), kd))
    qh = sorted(q[0] for q in f["qc"] if q[2] == "human")
    conts = sorted(c[0] for c in f["conts"] if c[1].startswith("Stop hook feedback"))
    sysr = sorted(f["sys"])
    away = [s[0] for s in sysr if s[1] == "sys:away_summary"]
    for qi, o in enumerate(O_):
        t, okind, prod, to, meta, txt = o
        if not (S <= t <= E):
            continue
        tn = Ot[qi + 1] if qi + 1 < len(O_) else 9e18
        i0 = bisect.bisect_right(Lt, t)
        i1 = bisect.bisect_left(Lt, tn)
        turn = L[i0:i1]
        if not turn:
            continue
        prev = L[i0 - 1] if i0 > 0 else None
        # kind
        tx = txt.lstrip()
        if to == "human" or okind == "human":
            kind = "operator"
        elif to == "peer" or okind == "peer":
            kind = "peer_msg"
        elif to == "scheduled":
            kind = "cron"
        elif to == "sdk":
            kind = "sdk"
        elif tx.startswith("<task-notification>"):
            sm = SUMM.search(tx)
            summ = sm.group(1) if sm else ""
            st = STAT.search(tx)
            st = st.group(1) if st else ""
            tus = TUID.findall(tx)
            j = jobs.get(tus[0]) if tus else None
            if "Goal check-in" in summ:
                kind = "goal_checkin"
            elif "peer mail" in summ:
                kind = "mail_rewake"
            elif j is not None:
                nm, cmd, bg = j[1], j[2], j[3]
                if nm == "Bash" and any(w in cmd for w in WATCH):
                    kind = (
                        "watch_timeout"
                        if (st == "failed" and "exit code 2" in summ)
                        else "watch_" + (st or "event")
                    )
                elif nm == "Monitor":
                    kind = (
                        "monitor_expired"
                        if "Monitor expired" in tx
                        else "monitor_event"
                    )
                elif nm == "Bash":
                    kind = "bash_" + (st or "event")
                elif nm in ("Agent", "Task"):
                    kind = "agent_" + (st or "event")
                elif nm == "Workflow":
                    kind = "workflow_" + (st or "event")
                else:
                    kind = "notif_" + nm
            elif "Monitor expired" in tx:
                kind = "monitor_expired"
            elif "Monitor event" in summ:
                kind = "monitor_event"
            elif (
                st == "failed"
                and "exit code 2" in summ
                and re.search(r"ping|mail|wait|watch", summ, re.I)
            ):
                kind = "watch_timeout_guess"
            else:
                kind = "notif_other"
        elif (
            tx.startswith("<bash-")
            or tx.startswith("<command-")
            or tx.startswith("<local-command")
        ):
            kind = "operator"
        elif okind is None and to is None and not meta:
            kind = "operator"
        else:
            kind = "other"
        tools = [tl for x in turn for tl in x[10]]
        cls = [tool_class(*tl) for tl in tools]
        if any(c == "act" for c in cls):
            res = "act"
        elif any(c == "look" for c in cls):
            res = "look"
        else:
            res = "noop"
        c1 = ctx(turn[0])
        c0 = ctx(prev) if prev else 0
        busy = any(
            js <= t < (je if je else last_t) and t - js < 12 * 3600
            for js, je, kd in bgjobs
        )
        nst = sum(1 for c in conts if t < c < tn)
        oph = any(t < q < tn for q in qh)
        a0 = bisect.bisect_right(away, t)
        row = dict(
            acct=f["acct"],
            sid=f["fsid"],
            t=t,
            kind=kind,
            res=res,
            gap=(t - prev[1]) if prev else None,
            ctx0=c0,
            ctx1=c1,
            nreq=len(turn),
            inp=sum(x[4] for x in turn),
            cc=sum(x[5] for x in turn),
            cc5=sum(x[6] for x in turn),
            cc1=sum(x[7] for x in turn),
            cr=sum(x[8] for x in turn),
            out=sum(x[9] for x in turn),
            cc_first=turn[0][5],
            reb=int(c1 > 0 and turn[0][5] >= 0.5 * c1),
            grow=ctx(turn[-1]) + turn[-1][9] - c0 if prev else None,
            dur=turn[-1][1] - t,
            ntools=len(tools),
            tools=[tl[0] for tl in tools][:20],
            bash=[tl[1][:120] for tl in tools if tl[0] == "Bash"][:6],
            cls=cls[:20],
            nstopfb=nst,
            op_during=oph,
            busy=busy,
            last=turn[-1][12][-300:],
            model=turn[0][3],
            open=tx[:160],
            next_kind_t=(tn - turn[-1][1]) if tn < 9e18 else None,
        )
        fo.write(json.dumps(row) + "\n")
        ntot[kind] += 1
fo.close()
for k, v in ntot.most_common():
    print(k, v)
