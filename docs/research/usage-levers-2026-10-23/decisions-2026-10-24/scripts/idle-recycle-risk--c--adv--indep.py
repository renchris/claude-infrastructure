# Independent re-derivation for finding c (adversarial check). Read-only, streaming.
# usage: python3 -I indep.py points.tsv out.jsonl
# For every W4 recycle point: the predecessor's final assistant text (from prev_req), a pairing check
# (no other main-thread assistant request strictly inside the gap), the opener that ended the gap
# (first non-meta, non-tool_result user record after prev_req in file order), and what launched the
# job a task-notification opener names (by tool-use-id, over the whole file, including foreground
# Bash calls that auto-moved to the background at their timeout).
import csv, json, re, sys
from datetime import datetime

pts_path, out_path = sys.argv[1], sys.argv[2]
pts = list(csv.DictReader(open(pts_path), delimiter="\t", quoting=csv.QUOTE_NONE))


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


TUID = re.compile(r"<tool-use-id>(toolu_[A-Za-z0-9]+)</tool-use-id>")
by_sid = {}
for i, p in enumerate(pts):
    by_sid.setdefault(p["sid"], []).append(i)

out = [None] * len(pts)
for sid, idxs in by_sid.items():
    paths = pts[idxs[0]]["paths"].split("|")
    best = {}
    for path in paths:
        try:
            fh = open(path, "rb")
        except OSError:
            continue
        recs = []  # (lineno, kind, ts, payload)
        launches = {}
        with fh:
            for n, line in enumerate(fh):
                head = line[:2000]
                if b'"queue-operation"' in head and b'"enqueue"' in head:
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    recs.append(
                        (
                            n,
                            "enq",
                            ep(r.get("timestamp", "")),
                            str(r.get("content", "")),
                        )
                    )
                    continue
                isu = b'"type":"user"' in head or b'"type": "user"' in head
                isa = (
                    b'"role":"assistant"' in line[:3000]
                    or b'"role": "assistant"' in line[:3000]
                )
                if not (isu or isa):
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("isSidechain"):
                    continue
                t = ep(r.get("timestamp", ""))
                m = r.get("message") or {}
                c = m.get("content")
                if r.get("type") == "user":
                    if isinstance(c, list) and any(
                        isinstance(b, dict) and b.get("type") == "tool_result"
                        for b in c
                    ):
                        tr = r.get("toolUseResult")
                        if isinstance(tr, dict) and tr.get("backgroundTaskId"):
                            for b in c:
                                if (
                                    isinstance(b, dict)
                                    and b.get("type") == "tool_result"
                                ):
                                    tu = b.get("tool_use_id")
                                    if tu in launches:
                                        launches[tu]["bg"] = (
                                            "timeout"
                                            if tr.get("timedOutAfterMs")
                                            else "bg"
                                        )
                        continue
                    if isinstance(c, list):
                        c = " ".join(
                            b.get("text", "")
                            for b in c
                            if isinstance(b, dict) and b.get("type") == "text"
                        )
                    recs.append(
                        (
                            n,
                            "user",
                            t,
                            c if isinstance(c, str) else "",
                            bool(r.get("isMeta")),
                        )
                    )
                elif r.get("type") == "assistant":
                    texts, tools = [], []
                    for b in c or []:
                        if not isinstance(b, dict):
                            continue
                        if b.get("type") == "text" and b.get("text", "").strip():
                            texts.append(b["text"])
                        elif b.get("type") == "tool_use":
                            bi = b.get("input") or {}
                            tools.append(b.get("name", ""))
                            launches[b.get("id")] = dict(
                                name=b.get("name"),
                                rib=bool(bi.get("run_in_background")),
                                cmd=str(bi.get("command", ""))[:300],
                                desc=str(bi.get("description", ""))[:120],
                                bg="",
                            )
                    recs.append(
                        (
                            n,
                            "asst",
                            t,
                            r.get("requestId") or m.get("id"),
                            texts,
                            tools,
                            m.get("model") == "<synthetic>",
                        )
                    )
        for i in idxs:
            p = pts[i]
            pr = p["prev_req"]
            pos = [k for k, x in enumerate(recs) if x[1] == "asst" and x[3] == pr]
            if not pos:
                continue
            last = pos[-1]
            texts = []
            tools = []
            for k in pos:
                texts += recs[k][4]
                tools += recs[k][5]
            final_text = texts[-1] if texts else ""
            all_text = "\n".join(texts)
            # last non-empty assistant text in the turn, if prev_req itself had none
            fallback = ""
            if not texts:
                for k in range(last, -1, -1):
                    if recs[k][1] == "asst" and recs[k][4]:
                        fallback = recs[k][4][-1]
                        break
                    if recs[k][1] == "user" and not recs[k][4]:
                        break
            # AskUserQuestion anywhere in the turn (back to the previous non-meta user record)
            auq_turn = False
            for k in range(last, -1, -1):
                if recs[k][1] == "asst" and "AskUserQuestion" in recs[k][5]:
                    auq_turn = True
                if recs[k][1] == "user" and not recs[k][4]:
                    break
            # pairing: other main-thread assistant requests (non-synthetic) strictly inside the gap
            pt, nt = (
                float(p["prev_ts"]),
                (float(p["next_ts"]) if p["next_ts"] else None),
            )
            inside = set()
            opener = None
            enq = None
            for k in range(last + 1, len(recs)):
                x = recs[k]
                if nt is not None and x[2] is not None and x[2] > nt + 2:
                    break
                if x[1] == "asst" and x[3] != pr and x[3] != p["next_req"] and not x[6]:
                    if x[2] is not None and pt < x[2] < (nt if nt else 9e18):
                        inside.add(x[3])
                if x[1] == "enq" and enq is None:
                    enq = x[3]
                if (
                    x[1] == "user"
                    and not x[4]
                    and opener is None
                    and p["kind"] == "mid"
                ):
                    opener = x[3]
            ok = ""
            launch = None
            if opener is not None:
                s = opener.lstrip()
                if s.startswith("<task-notification>"):
                    m_ = TUID.search(s)
                    if m_:
                        launch = launches.get(m_.group(1))
                        if launch is None:
                            ok = "notice:launch-not-in-file"
                        elif launch["name"] == "Monitor":
                            ok = "notice:monitor"
                        elif (
                            launch["name"] == "Bash"
                            and "cc-await-ping" in launch["cmd"]
                        ):
                            ok = "notice:await-ping"
                        elif launch["name"] == "Bash" and launch["bg"] == "timeout":
                            ok = "notice:bash-autobg-timeout"
                        elif launch["name"] == "Bash" and launch["rib"]:
                            ok = "notice:bash-bg"
                        elif launch["name"] == "Bash":
                            ok = "notice:bash-other(" + launch["bg"] + ")"
                        else:
                            ok = "notice:" + str(launch["name"])
                    elif "peer mail" in s[:200]:
                        ok = "notice:peer-mail-wake"
                    else:
                        ok = "notice:no-tuid"
                elif s.startswith("<teammate-message"):
                    ok = "teammate"
                elif s.startswith("<command-name>") or s.startswith(
                    "<command-message>"
                ):
                    ok = "slash"
                elif s.startswith("<local-command"):
                    ok = "local-cmd"
                elif s.startswith("[Request interrupted"):
                    ok = "interrupt"
                elif not s:
                    ok = "empty"
                elif s.startswith("<"):
                    ok = "other-tag"
                else:
                    ok = "typed"
            elif p["kind"] == "mid":
                ok = "no-opener"
            res = dict(
                i=i,
                kind=p["kind"],
                sid=sid,
                acct=p["acct"],
                prev_ts=p["prev_ts"],
                gap_s=float(p["gap_s"]),
                ctx=p["ctx"],
                final_text=(final_text or fallback)[-3000:],
                all_text_len=len(all_text),
                had_text=bool(texts),
                tools=tools,
                auq_msg="AskUserQuestion" in tools,
                auq_turn=auq_turn,
                inside=sorted(inside),
                opener=(opener or "")[:1200],
                opener_kind=ok,
                launch=launch,
                enq=(enq or "")[:300],
            )
            # prefer the file where prev_req is found with text
            if i not in best or (res["had_text"] and not best[i]["had_text"]):
                best[i] = res
    for i in idxs:
        out[i] = best.get(i) or dict(
            i=i,
            kind=pts[i]["kind"],
            sid=sid,
            acct=pts[i]["acct"],
            prev_ts=pts[i]["prev_ts"],
            gap_s=float(pts[i]["gap_s"]),
            ctx=pts[i]["ctx"],
            final_text="",
            had_text=False,
            tools=[],
            auq_msg=False,
            auq_turn=False,
            inside=[],
            opener="",
            opener_kind="not-found",
            launch=None,
            enq="",
            all_text_len=0,
        )
with open(out_path, "w") as o:
    for r in out:
        o.write(json.dumps(r) + "\n")
print("wrote", len(out))
