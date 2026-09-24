#!/usr/bin/env python3
"""Raw-transcript measurements the extract cannot answer (read-only, streams only the needed lines).

1. Read tool results (ALL in-window Read results, xdup=0): line count, chars in the per-line
   "N<TAB>" number prefixes, and the prefix chars left if only every 10th line kept its number.
   Also counts <system-reminder> blocks appended inside Read results and their chars.
2. Labels for items whose class needs content: task-notification prompts (subagent / workflow /
   background shell / other, from <summary>), skill bodies (skill name from the "Base directory"
   line), Agent tool results (async-launch ack vs inline return), large 'other' meta messages and
   large plain prompts (a short content-free label: first tag or first 40 chars pattern class).

Writes measure/growth_work/raw_labels.tsv (uid_or_tool_use_id, label) and raw_read.json.
Usage: cd /tmp && nice -n 10 python3 <dir>/scripts/growth_raw.py
"""

import sqlite3, os, json, re, collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DB = os.path.join(ROOT, "data", "extract.sqlite")
W = os.path.join(ROOT, "measure", "growth_work")

c = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
want_tid = collections.defaultdict(dict)  # file -> tool_use_id -> kind
want_uid = collections.defaultdict(dict)  # file -> record uuid -> kind
for (
    f,
    tid,
    sub,
) in c.execute("""select file, tool_use_id, subkind from item where kind='tool_result'
                                and subkind in ('Read','Agent','Workflow') and xdup=0"""):
    if tid:
        want_tid[f][tid] = sub
for (
    f,
    uid,
    kind,
    sub,
) in c.execute("""select file, uid, kind, subkind from item where xdup=0 and (
        (kind='user_prompt' and subkind in ('task_notification','peer_message'))
        or (kind='user_prompt' and subkind='plain' and chars>5000)
        or (kind='meta_user' and subkind in ('skill_body','command_body','other')))"""):
    want_uid[f][uid.split("#")[0]] = sub

SUMMARY = re.compile(r"<summary>(.*?)</summary>", re.S)
SKILL = re.compile(r"Base directory for this skill:\s*(\S+)")
PREFIX = re.compile(r"^(\s*\d+)(\t|→)", re.M)


def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    for b in content or []:
        if isinstance(b, dict) and b.get("type") == "text":
            out.append(b.get("text", ""))
    return "".join(out)


def label_notification(s):
    m = SUMMARY.search(s)
    summ = m.group(1) if m else s[:120]  # stop notices carry no <summary>
    low = summ.lower()
    if "orkflow" in summ:
        return "task_notification:workflow"
    if "peer mail" in low:
        return "task_notification:peer_mail"
    if "goal check-in" in low:
        return "task_notification:goal_checkin"
    if "agent" in low:
        return "task_notification:subagent"
    if "monitor" in low:
        return "task_notification:monitor"
    if "command" in low or "shell" in low or "background" in low:
        return "task_notification:bash"
    return "task_notification:other"


def label_text(s):
    s0 = s.lstrip()[:200]
    m = re.match(r"<([a-zA-Z_-]+)", s0)
    if m:
        return "tag:" + m.group(1)
    if s0.startswith("Base directory"):
        return "skill"
    if s0.startswith("#"):
        return "markdown_doc"
    if "handoff" in s0.lower() or "continuation" in s0.lower():
        return "handoff_brief"
    if "This session is being continued" in s0:
        return "compact_continuation"
    return "prose"


read = collections.Counter()
read_sizes = []
labels = []
for f in sorted(set(want_tid) | set(want_uid)):
    tids = want_tid.get(f, {})
    uids = want_uid.get(f, {})
    try:
        fh = open(f, errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            if '"user"' not in line[:200] and '"type":"user"' not in line:
                continue
            hit_uid = None
            if uids:
                m = re.search(r'"uuid":"([^"]+)"', line)
                if m and m.group(1) in uids:
                    hit_uid = m.group(1)
            hit_t = (
                tids
                and '"tool_result"' in line
                and any(
                    t in line
                    for t in re.findall(r'"tool_use_id":"([^"]+)"', line)
                    if t in tids
                )
            )
            if not hit_uid and not hit_t:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            msg = o.get("message") or {}
            content = msg.get("content")
            if hit_uid:
                kind = uids[hit_uid]
                s = text_of(content)
                if kind == "task_notification":
                    lab = label_notification(s)
                elif kind == "skill_body":
                    m = SKILL.search(s)
                    lab = "skill:" + (
                        os.path.basename(m.group(1).rstrip("/")) if m else "?"
                    )
                elif kind == "peer_message":
                    lab = "peer_message"
                else:
                    lab = kind + ":" + label_text(s)
                labels.append((hit_uid, lab))
            if hit_t and isinstance(content, list):
                for b in content:
                    if not (isinstance(b, dict) and b.get("type") == "tool_result"):
                        continue
                    tid = b.get("tool_use_id")
                    kind = tids.get(tid)
                    if not kind:
                        continue
                    s = text_of(b.get("content"))
                    if kind == "Read":
                        # strip system-reminder blocks appended to the result, count them separately
                        body = s
                        sr = 0
                        for mm in re.finditer(
                            r"<system-reminder>.*?</system-reminder>", s, re.S
                        ):
                            sr += len(mm.group(0))
                            read["sysrem_n"] += 1
                        if sr:
                            body = re.sub(
                                r"<system-reminder>.*?</system-reminder>",
                                "",
                                s,
                                flags=re.S,
                            )
                        read["results"] += 1
                        read["chars"] += len(s)
                        read["sysrem_chars"] += sr
                        pre = PREFIX.findall(body)
                        nl = len(pre)
                        pc = sum(len(a) + 1 for a, _ in pre)
                        # keep numbers only on lines whose number is divisible by 10 (plus line 1)
                        keep = sum(
                            len(a) + 1
                            for a, _ in pre
                            if int(a) % 10 == 0 or int(a) == 1
                        )
                        read["numbered_lines"] += nl
                        read["prefix_chars"] += pc
                        read["prefix_chars_every10"] += keep
                        read["padded_prefix"] += sum(
                            1 for a, _ in pre if a.startswith(" ")
                        )
                        read_sizes.append(len(s))
                    else:
                        low = s[:300].lower()
                        lab = kind + (
                            ":async_ack"
                            if (
                                "async" in low
                                or "launched" in low
                                or "running in the background" in low
                                or "started" in low[:80]
                            )
                            else ":inline_return"
                        )
                        labels.append((tid, lab))

with open(os.path.join(W, "raw_labels.tsv"), "w") as fh:
    for a, b in labels:
        fh.write("%s\t%s\n" % (a, b))
read_sizes.sort()
q = lambda p: (
    read_sizes[min(len(read_sizes) - 1, int(p * len(read_sizes)))] if read_sizes else 0
)
read["size_p50"] = q(0.5)
read["size_p90"] = q(0.9)
read["size_p99"] = q(0.99)
json.dump(read, open(os.path.join(W, "raw_read.json"), "w"), indent=1)
print(json.dumps(read))
print(collections.Counter(b for a, b in labels).most_common(40))
