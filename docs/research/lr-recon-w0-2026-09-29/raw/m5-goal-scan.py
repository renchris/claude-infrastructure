#!/usr/bin/env python3
"""M5 — does a Claude Code /goal survive a usage-limit death?  Read-only scan.

Run:  python3 docs/research/lr-recon-w0-2026-09-29/raw/m5-goal-scan.py [SINCE=2026-09-01]

Corpus: $HOME/<cfg>/projects/*/<uuid>.jsonl and .jsonl.handed-off for the six config dirs, mtime >= SINCE.
Records from every copy of a session uuid (transplants) are unioned by record uuid and time-sorted.
Privacy: goal text is never printed (length + sha256[:10] only); sessions as first 8 hex; no paths.

Events (harness records only; prose that merely mentions a goal is ignored, away_summary excluded):
  ARM      attachment goal_status sentinel:true  met:false        (goal set)
  CLR      attachment goal_status sentinel:true  met:true         (harness clear marker)
  EVAL     attachment goal_status no sentinel    met:false        (Stop-hook evaluation: goal armed, judged unmet)
  MET      attachment goal_status no sentinel    met:true         (goal judged met -> cleared)
  PAUSE    system record (not away_summary) starting "Goal paused"
  GCLR     system record starting "Goal cleared after an unrecoverable error (<label>)"
  CHECKIN  isMeta user record starting "Goal check-in"
  GCMD     user <command-name>/goal</command-name> (clear-word args -> GCMD-clear)
  DEATH    assistant isApiErrorMessage, error=rate_limit with quotaLimits, or text "hit your ... limit"
  APIERR   any other assistant isApiErrorMessage
  RESUME   attachment hook_success hookName SessionStart:resume (first of a burst)
  STOP     system stop_hook_summary (a Stop happened; the goal hook, if armed, runs at a Stop)
  PROMPT   first human (non-meta, non-command) string user prompt after a DEATH

Resume-restore rule (CC 2.1.278 binary, fn mbt/pDn): on --resume CC re-arms the goal iff the LAST
goal_status attachment in the transcript has met:false and no `failed`. It writes NO transcript record
for the restore, so "armed after resume" is observable only via a later EVAL/MET/CLR/CHECKIN of the
same condition hash.  RESTORE_PRED below evaluates that rule at each post-death resume.
"""

import collections, datetime, glob, hashlib, json, os, re, sys

HOME = os.path.expanduser("~")
CFGS = [
    ".claude",
    ".claude-next",
    ".claude-next4",
    ".claude-secondary",
    ".claude-tertiary",
    ".claude-quaternary",
]
SINCE = sys.argv[1] if len(sys.argv) > 1 else "2026-09-01"
since_ts = datetime.datetime.fromisoformat(SINCE).timestamp()
CLEAR_WORDS = {"clear", "stop", "off", "reset", "none", "cancel"}
LIMIT_TXT = re.compile(
    r"hit your .{0,40}limit|usage limit|session limit|weekly limit", re.I
)
ERR_RE = re.compile(rb'"error":"([a-z_]+)","isApiErrorMessage":true')
PAUSE_RE = re.compile(rb'"content":"(Goal paused[^"\\]{0,120})')
GCLR_RE = re.compile(
    rb'"content":"Goal cleared after an unrecoverable error \(([^)]{1,40})\)'
)


def h(s):
    return "len=%d sha=%s" % (len(s), hashlib.sha256(s.encode()).hexdigest()[:10])


files = collections.defaultdict(list)  # sid -> [(cfg, path)]
nfiles = 0
for cfg in CFGS:
    for p in glob.glob(os.path.join(HOME, cfg, "projects", "*", "*.jsonl*")):
        if not (p.endswith(".jsonl") or p.endswith(".jsonl.handed-off")):
            continue
        try:
            if os.path.getmtime(p) < since_ts:
                continue
        except OSError:
            continue
        nfiles += 1
        files[os.path.basename(p).split(".")[0]].append((cfg, p))

print(
    "# corpus: %d transcript files, %d session uuids, mtime >= %s, cfgs=%s"
    % (nfiles, len(files), SINCE, ",".join(CFGS))
)

# pass 1 (every file): corpus-wide tallies + candidate prefilter (goal_status AND an api-error record)
err_tally, pause_tally, gclr_tally = (
    collections.Counter(),
    collections.Counter(),
    collections.Counter(),
)
blocking_field = 0
cand = {}
for sid, lst in files.items():
    g = e = False
    for cfg, p in lst:
        try:
            with open(p, "rb") as f:
                b = f.read()
        except OSError:
            continue
        g = g or b'"goal_status"' in b
        e = e or b'"isApiErrorMessage":true' in b
        for m in ERR_RE.findall(b):
            err_tally[m.decode()] += 1
        for m in PAUSE_RE.findall(b):
            pause_tally[m.decode("utf-8", "replace")] += 1
        for m in GCLR_RE.findall(b):
            gclr_tally[m.decode()] += 1
        blocking_field += len(
            re.findall(rb'"(?:error|reason|stop_reason|subtype)":"blocking_limit"', b)
        )
    if g and e:
        cand[sid] = lst
print("# corpus-wide (record copies, transplant duplicates counted per file):")
print("#   isApiErrorMessage error values: %s" % dict(err_tally.most_common()))
print(
    "#   'blocking_limit' as a structured field value (error/reason/stop_reason/subtype): %d"
    % blocking_field
)
print("#   'Goal paused' system notices: %s" % dict(pause_tally))
print(
    "#   'Goal cleared after an unrecoverable error (<label>)' notices: %s"
    % dict(gclr_tally)
)
print("# sessions with goal_status + an api-error record: %d" % len(cand))


def events(lst):
    recs = {}
    for cfg, p in lst:
        with open(p, "r", errors="replace") as f:
            for line in f:
                if not any(
                    k in line
                    for k in (
                        "goal_status",
                        "isApiErrorMessage",
                        "Goal ",
                        "/goal",
                        "SessionStart:resume",
                        "stop_hook_summary",
                        '"type":"user"',
                    )
                ):
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                u = d.get("uuid") or (d.get("timestamp", "") + line[:200])
                if u in recs:
                    recs[u][1].add(cfg)
                    continue
                recs[u] = (d, {cfg})
    out = []
    for d, cfgs in recs.values():
        ts, t, ev = d.get("timestamp") or "", d.get("type"), None
        if t == "attachment":
            a = d.get("attachment") or {}
            if a.get("type") == "goal_status":
                s, m = bool(a.get("sentinel")), bool(a.get("met"))
                k = ("CLR" if m else "ARM") if s else ("MET" if m else "EVAL")
                ev = (
                    k,
                    h(a.get("condition") or "")
                    + (" failed" if a.get("failed") else ""),
                )
            elif (
                a.get("type") == "hook_success"
                and a.get("hookName") == "SessionStart:resume"
            ):
                ev = ("RESUME", "")
        elif t == "system":
            c = d.get("content")
            if d.get("subtype") == "stop_hook_summary":
                ev = ("STOP", "")
            elif d.get("subtype") != "away_summary" and isinstance(c, str):
                if c.startswith("Goal paused"):
                    ev = ("PAUSE", c[:80])
                elif c.startswith("Goal cleared after an unrecoverable error"):
                    ev = ("GCLR", re.sub(r":.*", "", c)[:70])
        elif t == "assistant" and d.get("isApiErrorMessage"):
            txt = " ".join(
                x.get("text", "")
                for x in (d.get("message") or {}).get("content", [])
                if isinstance(x, dict)
            )
            ql = d.get("quotaLimits") or {}
            if (d.get("error") == "rate_limit" and ql) or LIMIT_TXT.search(txt):
                ev = (
                    "DEATH",
                    "rateLimitType=%s v%s"
                    % (ql.get("rateLimitType"), d.get("version")),
                )
            else:
                ev = ("APIERR", "error=%s" % d.get("error"))
        elif t == "user":
            c = (d.get("message") or {}).get("content")
            if isinstance(c, str):
                if "<command-name>/goal</command-name>" in c:
                    m = re.search(r"<command-args>(.*?)</command-args>", c, re.S)
                    arg = (m.group(1) if m else "").strip()
                    ev = (
                        "GCMD-clear" if arg.lower() in CLEAR_WORDS else "GCMD",
                        h(arg),
                    )
                elif d.get("isMeta") and c.startswith("Goal check-in"):
                    ev = ("CHECKIN", "")
                elif not d.get("isMeta") and not c.startswith("<"):
                    ev = ("USERMSG", "")
        if ev:
            out.append(
                (
                    ts,
                    ev[0],
                    ev[1],
                    "+".join(c.replace(".claude", "c") or "c" for c in sorted(cfgs)),
                )
            )
    out.sort()
    return out


GOAL_EVID = {"EVAL", "MET", "CLR", "CHECKIN", "GCLR"}
rows = []
for sid in sorted(cand):
    ev = events(cand[sid])
    deaths = [i for i, e in enumerate(ev) if e[1] == "DEATH"]
    if not deaths:
        continue
    print(
        "\n## %s  copies=%s"
        % (
            sid[:8],
            ",".join(
                sorted(
                    c + (":handed-off" if p.endswith("off") else "")
                    for c, p in cand[sid]
                )
            ),
        )
    )
    last = None
    for (
        ts,
        k,
        x,
        cf,
    ) in (
        ev
    ):  # compact timeline: bursts collapsed, USERMSG only as first PROMPT after a DEATH
        if k == "USERMSG":
            if last != "DEATH*":
                continue
            k = "PROMPT"
        key = (k, x)
        if key == last or (k == "STOP" and last and last[0] == "STOP"):
            continue
        print("  %s  %-10s %-38s %s" % (ts[:19], k, x, cf))
        last = key
        if k == "DEATH":
            last = "DEATH*"
    for i in deaths:
        state, cond = None, None
        for ts, k, x, cf in ev[:i]:
            if k == "ARM":
                state, cond = "armed", (ts, x)
            elif k in ("MET", "CLR", "GCMD-clear", "GCLR"):
                state = "cleared"
        if state != "armed":
            continue
        prev = [e for e in ev[:i] if e[1] not in ("APIERR", "USERMSG", "STOP")]
        if prev and prev[-1][1] in ("DEATH", "PAUSE"):
            continue  # retry of the same outage; classify the first death only
        post = ev[i + 1 :]
        # window: up to the next armed-goal death of a different outage is fine to include; stop at a new ARM
        res_i = next((j for j, e in enumerate(post) if e[1] == "RESUME"), None)
        pred = "-"
        if res_i is not None:
            gs = [
                e for e in ev[: i + 1 + res_i] if e[1] in ("ARM", "EVAL", "MET", "CLR")
            ]
            pred = (
                "restore"
                if gs and gs[-1][1] in ("ARM", "EVAL") and "failed" not in gs[-1][2]
                else "no-restore"
            )
        first_ev = next(
            (e for e in post if e[1] in GOAL_EVID or e[1] in ("PAUSE", "ARM", "GCMD")),
            None,
        )
        same = next(
            (e for e in post if e[1] in GOAL_EVID and e[2].startswith(cond[1])), None
        )
        rearm = next((e for e in post if e[1] in ("ARM", "GCMD")), None)
        stops_after = sum(1 for e in post if e[1] == "STOP")
        arm_i = max(j for j, e in enumerate(ev[:i]) if e[1] == "ARM")
        pre = ev[arm_i:i]
        pre_evals = sum(1 for e in pre if e[1] in ("EVAL", "CHECKIN"))
        pre_stops = sum(1 for e in pre if e[1] == "STOP")
        t_death = datetime.datetime.fromisoformat(ev[i][0].replace("Z", "+00:00"))
        pre_resume = post[:res_i] if res_i is not None else post
        clr_at = any(
            e[1] in ("CLR", "GCLR")
            and (datetime.datetime.fromisoformat(e[0].replace("Z", "+00:00")) - t_death).total_seconds() < 600
            for e in pre_resume
        )
        cleared_by = next((e[2] for e in post if e[1] == "GCLR"), "")
        rows.append(
            dict(
                sid=sid[:8],
                arm=cond[0][:16],
                death=ev[i][0][:16],
                dv=ev[i][2].split()[-1],
                pause="PAUSE" in [e[1] for e in post[:3]],
                resumed=res_i is not None,
                pred=pred,
                stops=stops_after,
                pre="%d/%d" % (pre_evals, pre_stops),
                clr_at=clr_at,
                same=(same[1] + "@" + same[0][:16]) if same else "-",
                first=(first_ev[1] + "@" + first_ev[0][:16]) if first_ev else "-",
                rearm=bool(rearm),
                cleared_by=cleared_by,
            )
        )

print(
    "\n# PER-DEATH TABLE (goal ARMED at a usage-limit death; retries of one outage collapsed)"
)
print(
    "%-8s %-7s %-16s %-16s %-9s %-5s %-7s %-10s %-5s %-24s %-24s %-5s"
    % (
        "sid",
        "pre_e/s",
        "goal_set",
        "death",
        "cc_ver",
        "pause",
        "resumed",
        "restore?",
        "stops",
        "first_goal_rec_after",
        "same_goal_evidence_after",
        "rearm",
    )
)
for r in rows:
    print(
        "%-8s %-7s %-16s %-16s %-9s %-5s %-7s %-10s %-5d %-24s %-24s %-5s %s"
        % (
            r["sid"],
            r["pre"],
            r["arm"],
            r["death"],
            r["dv"],
            r["pause"],
            r["resumed"],
            r["pred"],
            r["stops"],
            r["first"],
            r["same"],
            r["rearm"],
            r["cleared_by"],
        )
    )
sess = collections.OrderedDict()
for r in rows:
    sess.setdefault(r["sid"], []).append(r)
anyof = lambda f: sum(1 for v in sess.values() if any(f(x) for x in v))
print(
    "\n# COUNTS (sessions; a session counts once if any of its armed deaths qualifies)"
)
print(
    "sessions_goal_armed_at_usage_limit_death=%d  (armed deaths=%d)"
    % (len(sess), len(rows))
)
print("sessions_with_Goal_paused_notice_at_death=%d" % anyof(lambda x: x["pause"]))
print(
    "sessions_cleared_AT_death (CLR/GCLR within 10 min of death, before any resume)=%d"
    % anyof(lambda x: x["clr_at"])
)
print("sessions_resumed_after_death=%d" % anyof(lambda x: x["resumed"]))
print(
    "sessions_restore_rule_true_at_resume=%d" % anyof(lambda x: x["pred"] == "restore")
)
print(
    "sessions_same_goal_evidence_after_death (EVAL/MET/CLR/CHECKIN of same hash)=%d"
    % anyof(lambda x: x["same"] != "-")
)
print(
    "sessions_rearmed_after_death (new ARM or /goal command)=%d"
    % anyof(lambda x: x["rearm"])
)
print("sessions_no_goal_record_after_death=%d" % anyof(lambda x: x["first"] == "-"))
print(
    "sessions_no_goal_record_after_death_but_>=1_stop_after=%d"
    % anyof(lambda x: x["first"] == "-" and x["stops"] > 0)
)
print(
    "sessions_goal_never_evaluated_before_death (0 EVAL/CHECKIN, >=1 STOP between ARM and death)=%d"
    % anyof(lambda x: x["pre"].startswith("0/") and x["pre"] != "0/0")
)
print(
    "sessions_no_goal_record_after_death_AND_evaluated_before_death=%d"
    % anyof(lambda x: x["first"] == "-" and not x["pre"].startswith("0/"))
)
print("# pre_e/s = goal EVAL+CHECKIN records / STOP records between the ARM and the death")
