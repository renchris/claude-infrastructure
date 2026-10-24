#!/usr/bin/env python3
# Classify every MAIN-thread gap > 45 min (from gaps.jsonl, which reproduces yesterday's 191 1-2h busts)
# by the session's state at the gap start and by what ended the gap. Read-only over transcripts.
#
# State at gap start (from the transcript up to the last record of the request before the gap):
#   fg_tool   : the request before the gap ended with tool_use and that tool's result arrived late
#               (> 50% of the gap after its start) -> the turn was blocked inside a foreground tool
#   idle      : the request before the gap ended its turn (end_turn / no pending tool)
# Registry at gap start: background tasks (Bash run_in_background, Agent run_in_background, Workflow,
# Monitor) launched before gap start and with no task-notification / TaskStop before gap start.
# Model-armed watcher: a live background Bash whose command runs cc-await-ping (not --stand-down).
# Goal live: the LAST goal_status attachment before gap start has met==false and not failed
#            (hooks/lib/goal-state.sh predicate).
# Trigger: the input that ended the gap (late tool_result, task-notification + its task's command,
#          rewake peer mail, teammate message, scheduled fire, operator prompt).
import json, sys, re, collections
from datetime import datetime

T = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
G = [json.loads(l) for l in open("/tmp/usage-audit/r2/cache-rebuilds/gaps.jsonl")]
G = [g for g in G if not g["sub"] and g["gap"] > 2700]
byfile = collections.defaultdict(list)
for g in G:
    byfile[g["root"] + "/" + g["rel"]].append(g)

RE_TN_ID = re.compile(r"<task-id>([^<]+)</task-id>")
RE_TN_TU = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")
RE_TN_ST = re.compile(r"<status>([^<]+)</status>")
RE_TN_SU = re.compile(r"<summary>(.*?)</summary>", re.S)
RE_BGID = re.compile(r"(?:running in background with ID|ID): ?([a-z0-9]{6,})")
RE_TO = re.compile(r"--timeout[ =](\d+)")


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for x in content:
            if isinstance(x, dict):
                if x.get("type") == "text":
                    out.append(x.get("text") or "")
                elif x.get("type") == "tool_result":
                    c = x.get("content")
                    out.append(c if isinstance(c, str) else json.dumps(c)[:4000])
        return "\n".join(out)
    return ""


def wkind(cmd):
    c = cmd or ""
    if "cc-await-ping" in c and "--stand-down" not in c:
        return "watcher"
    return "bash"


out = open("/tmp/usage-audit/r2/cache-rebuilds/mainstate.jsonl", "w")
for path, gaps in byfile.items():
    want_prev = {g["prev_mid"]: g for g in gaps}
    want_cur = {g["mid"]: g for g in gaps}
    # streaming pass: keep a compact record list
    tools = {}  # tool_use_id -> dict(name, cmd, bg, ts, timeout)
    bgtask = {}  # task id -> tool_use_id
    events = []  # (file_idx, ts, kind, payload)
    goal = []  # (ts, live)
    teammate_first = None
    idx = 0
    mid_last_idx = {}
    mid_first_idx = {}
    mid_stop = {}
    mid_tools = collections.defaultdict(list)
    for line in open(path, errors="replace"):
        idx += 1
        try:
            d = json.loads(line)
        except Exception:
            continue
        t = d.get("type")
        ts = d.get("timestamp")
        tsv = T(ts) if ts else None
        if t == "assistant":
            m = d.get("message") or {}
            mid = m.get("id")
            if mid:
                mid_first_idx.setdefault(mid, (idx, tsv))
                mid_last_idx[mid] = (idx, tsv)
                if m.get("stop_reason"):
                    mid_stop[mid] = m.get("stop_reason")
            for c in m.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    inp = c.get("input") or {}
                    nm = c.get("name")
                    bg = bool(inp.get("run_in_background")) or nm in (
                        "Workflow",
                        "Monitor",
                    )
                    tools[c.get("id")] = dict(
                        name=nm,
                        cmd=str(
                            inp.get("command")
                            or inp.get("description")
                            or inp.get("prompt")
                            or inp.get("script")
                            or ""
                        )[:300],
                        bg=bg,
                        ts=tsv,
                        timeout=inp.get("timeout"),
                    )
                    if mid:
                        mid_tools[mid].append(c.get("id"))
        elif t == "user":
            m = d.get("message") or {}
            c = m.get("content")
            if isinstance(c, list):
                for x in c:
                    if isinstance(x, dict) and x.get("type") == "tool_result":
                        tu = x.get("tool_use_id")
                        rs = text_of([x])
                        events.append((idx, tsv, "tool_result", tu))
                        tl = tools.get(tu)
                        if tl and tl["bg"]:
                            mm = RE_BGID.search(rs or "")
                            if mm:
                                bgtask[mm.group(1)] = tu
                            tl["launched"] = True
                        if tl and tl["name"] == "TaskStop":
                            for k in re.findall(
                                r"stopped task: ?([a-z0-9]+)", rs or ""
                            ):
                                events.append((idx, tsv, "task_done", k))
            s = text_of(c)
            if "<task-notification>" in s:
                for blk in s.split("<task-notification>")[1:]:
                    tid = RE_TN_ID.search(blk)
                    tu = RE_TN_TU.search(blk)
                    st = RE_TN_ST.search(blk)
                    su = RE_TN_SU.search(blk)
                    events.append(
                        (
                            idx,
                            tsv,
                            "task_notif",
                            dict(
                                tid=tid and tid.group(1),
                                tu=tu and tu.group(1),
                                st=st and st.group(1),
                                su=(su.group(1)[:160] if su else ""),
                            ),
                        )
                    )
            elif not (
                isinstance(c, list)
                and any(
                    isinstance(x, dict) and x.get("type") == "tool_result" for x in c
                )
            ):
                kind = "prompt"
                if "Peer mail arrived while you were idle" in s:
                    kind = "rewake_mail"
                elif "<teammate-message" in s:
                    kind = "teammate_msg"
                    if teammate_first is None:
                        teammate_first = tsv
                elif d.get("isMeta"):
                    kind = "meta"
                elif s.startswith("Stop hook feedback"):
                    kind = "meta"
                elif (
                    "<command-name>" in s
                    or "<local-command" in s
                    or "<bash-input>" in s
                    or "<bash-stdout>" in s
                ):
                    kind = "slash_or_bang"
                events.append((idx, tsv, kind, s[:160]))
        elif t == "attachment":
            a = d.get("attachment") or {}
            at = a.get("type")
            if at == "goal_status":
                live = (a.get("met") is False) and not a.get("failed")
                goal.append((tsv, live, idx))
            elif at == "queued_command":
                s = str(a.get("prompt") or "")
                if "<task-notification>" in s:
                    for blk in s.split("<task-notification>")[1:]:
                        tid = RE_TN_ID.search(blk)
                        tu = RE_TN_TU.search(blk)
                        st = RE_TN_ST.search(blk)
                        su = RE_TN_SU.search(blk)
                        events.append(
                            (
                                idx,
                                tsv,
                                "task_notif",
                                dict(
                                    tid=tid and tid.group(1),
                                    tu=tu and tu.group(1),
                                    st=st and st.group(1),
                                    su=(su.group(1)[:160] if su else ""),
                                ),
                            )
                        )
                else:
                    k = "queued_prompt"
                    if "Peer mail arrived while you were idle" in s:
                        k = "rewake_mail"
                    elif "<teammate-message" in s:
                        k = "teammate_msg"
                    events.append((idx, tsv, k, s[:160]))
        elif t == "system":
            st = d.get("subtype")
            if st == "scheduled_task_fire":
                events.append((idx, tsv, "scheduled", ""))
            elif st == "informational" and "Goal paused" in str(d.get("content")):
                events.append((idx, tsv, "goal_paused", ""))
    # resolve tool-use-id of task notifications
    for g in gaps:
        if g["prev_mid"] not in mid_last_idx or g["mid"] not in mid_first_idx:
            continue
        a_idx, a_ts = mid_last_idx[g["prev_mid"]]
        b_idx, b_ts = mid_first_idx[g["mid"]]
        gs, ge = T(g["prev_ts"]), T(g["ts"])
        # foreground tool pending?
        ptools = [
            tools[x] | {"id": x} for x in mid_tools.get(g["prev_mid"], []) if x in tools
        ]
        stop = mid_stop.get(g["prev_mid"])
        late_results = [
            e
            for e in events
            if e[2] == "tool_result"
            and a_idx < e[0] <= b_idx
            and e[1]
            and e[1] - gs > 0.5 * (ge - gs)
        ]
        fg_pending = [p for p in ptools if any(e[3] == p["id"] for e in late_results)]
        # registry at gap start
        done_tids = set()
        done_tus = set()
        for e in events:
            if e[0] > a_idx:
                break
            if e[2] == "task_notif":
                if e[3]["tid"]:
                    done_tids.add(e[3]["tid"])
                if e[3]["tu"]:
                    done_tus.add(e[3]["tu"])
            elif e[2] == "task_done":
                done_tids.add(e[3])
        live = []
        for tid, tu in bgtask.items():
            tl = tools.get(tu)
            if not tl or tl["ts"] is None or tl["ts"] > gs:
                continue
            if tid in done_tids or tu in done_tus:
                continue
            if (
                gs - tl["ts"] > 6 * 3600
            ):  # stale registry entry (session likely restarted); ignore
                continue
            k = wkind(tl["cmd"]) if tl["name"] == "Bash" else tl["name"]
            to = None
            if k == "watcher":
                m = RE_TO.search(tl["cmd"])
                to = (
                    int(m.group(1))
                    if m
                    else (3300 if "--idle-scoped" in tl["cmd"] else 1800)
                )
            live.append(dict(kind=k, cmd=tl["cmd"][:120], armed=tl["ts"], to=to))
        # Workflow / Agent bg launches tracked by tool_use id (no bg id in result)
        for tu, tl in tools.items():
            if (
                tl["name"] in ("Workflow", "Agent", "Task")
                and tl["bg"]
                and tl["ts"]
                and tl["ts"] <= gs
                and tu not in done_tus
                and gs - tl["ts"] < 6 * 3600
            ):
                if tu not in bgtask.values():
                    live.append(
                        dict(
                            kind=tl["name"],
                            cmd=tl["cmd"][:120],
                            armed=tl["ts"],
                            to=None,
                        )
                    )
        gl = [x for x in goal if x[2] <= a_idx]
        goal_live = bool(gl and gl[-1][1])
        paused = goal_live and any(
            e[2] == "goal_paused" and gl[-1][2] < e[0] <= a_idx for e in events
        )
        # trigger
        between = [e for e in events if a_idx < e[0] <= b_idx]
        trig = None
        cand = [
            e
            for e in between
            if e[2]
            in (
                "task_notif",
                "rewake_mail",
                "teammate_msg",
                "prompt",
                "queued_prompt",
                "scheduled",
                "slash_or_bang",
            )
        ]
        if fg_pending:
            trig = "fg_tool_returned:" + fg_pending[0]["name"]
        elif cand:
            e = cand[-1]
            # prefer the latest-timestamped real input
            e = max(cand, key=lambda e: e[1] or 0)
            if e[2] == "task_notif":
                tu = e[3]["tu"]
                tl = tools.get(tu) or {}
                k = (
                    wkind(tl.get("cmd")) if tl.get("name") == "Bash" else tl.get("name")
                ) or "unknown"
                su = e[3].get("su") or ""
                if not tu and "Goal check-in" in su:
                    trig = "goal_checkin"
                elif not tu and "peer mail" in su:
                    trig = "rewake_mail"
                else:
                    trig = f"task_notif:{k}:{e[3]['st']}"
            else:
                trig = e[2]
        else:
            kinds = sorted({e[2] for e in between})
            trig = "none:" + "+".join(kinds)
        rec = dict(
            acct=g["acct"],
            rel=g["rel"],
            ts=g["ts"],
            gap=g["gap"],
            bust=g["bust"],
            cc=g["cc"],
            pp=g["pp"],
            stop=stop,
            prev_tools=[p["name"] for p in ptools],
            fg_pending=[(p["name"], p["cmd"][:100]) for p in fg_pending],
            live=live,
            goal_live=goal_live,
            goal_paused=paused,
            teammate=teammate_first is not None and teammate_first <= ge,
            trig=trig,
            trig_text=next(
                (
                    str(e[3])[:160]
                    for e in sorted(between, key=lambda e: e[1] or 0, reverse=True)
                    if e[2]
                    in ("prompt", "queued_prompt", "teammate_msg", "rewake_mail")
                ),
                "",
            ),
        )
        out.write(json.dumps(rec) + "\n")
out.close()
print("done", sum(len(v) for v in byfile.values()), "gaps in", len(byfile), "files")
