#!/usr/bin/env python3
"""Two aggregates from MAIN transcripts (xdup=0 files, in-window records). Prints counts only.

1. agent_listing_delta: per-agent entry chars in the first rendered agent listing of each file.
2. Trigger phrases: for every skill/command/agent description (listings_frontmatter.py output),
   the double-quoted phrases in it are treated as its declared triggers. For each trigger, count the
   main sessions whose TYPED prompts (user_prompt plain/pasted, not meta/tool_result) contain it
   (case-insensitive substring), and how many of those sessions invoked the skill (Skill tool or
   slash command, from extract.sqlite). Also counts sessions whose prompts mention the skill's
   name or /name. Nothing from the transcripts is printed or stored except these counts.
Usage: nice -n 10 python3 listings_triggers.py <extract.sqlite> <frontmatter.json> <out.json>
"""

import json, re, sqlite3, sys, collections
from multiprocessing import Pool

DB, FM, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
SINCE = "2026-09-09T00:00:00Z"


def prompt_text(r):
    if r.get("type") != "user" or r.get("isMeta") or r.get("isCompactSummary"):
        return None
    c = (r.get("message") or {}).get("content")
    if isinstance(c, str):
        t = c
    elif isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return None
        t = "\n".join(
            b.get("text", "")
            for b in c
            if isinstance(b, dict) and b.get("type") == "text"
        )
    else:
        return None
    if (
        t.startswith("<command-name>")
        or t.startswith("<local-command")
        or "<task-notification>" in t[:200]
        or "<teammate-message" in t[:200]
        or t.startswith("Another Claude session sent")
    ):
        return None
    return t


def work(path):
    prompts, agents = [], None
    try:
        with open(path, "rb") as f:
            for line in f:
                if agents is None and b"agent_listing_delta" in line:
                    try:
                        r = json.loads(line)
                        a = r.get("attachment") or {}
                        if (
                            a.get("type") == "agent_listing_delta"
                            and (r.get("timestamp") or "") >= SINCE
                        ):
                            txt = "".join(
                                (x or {}).get("content", "")
                                for x in (r.get("rendered") or [])
                            )
                            per = {}
                            for l in txt.split("\n"):
                                m = re.match(r"^- ([\w:.-]+): ", l)
                                if m:
                                    per[m.group(1)] = len(l)
                            agents = dict(total=len(txt), per=per)
                    except Exception:
                        pass
                    continue
                if (
                    b'"type":"user"' not in line[:400]
                    and b'"type": "user"' not in line[:400]
                ):
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if (r.get("timestamp") or "") < SINCE:
                    continue
                t = prompt_text(r)
                if t:
                    prompts.append(t.lower()[:20000])
    except Exception:
        pass
    return path, prompts, agents


def main():
    con = sqlite3.connect(DB)
    files = con.execute(
        """select file, session_id from ctx where ctx_type='main' and n_resp>0 and n_resp_xdup<n_resp"""
    ).fetchall()
    sid = dict(files)
    inv = collections.defaultdict(set)
    for (
        d,
        s,
    ) in con.execute("""select i.detail, c.session_id from item i join ctx c on c.file=i.file
            where i.xdup=0 and ((i.kind='tool_use_input' and i.subkind='Skill') or (i.kind='user_prompt' and i.subkind='command'))"""):
        inv[(d or "").lstrip("/").strip()].add(s)
    spawn = collections.defaultdict(set)
    for (
        d,
        s,
    ) in con.execute("""select i.detail, c.session_id from item i join ctx c on c.file=i.file
            where i.xdup=0 and i.kind='tool_use_input' and i.subkind in ('Agent','Task')"""):
        spawn[(d or "").split("/")[0]].add(s)
    fm = json.load(open(FM))
    with Pool(4) as p:
        res = p.map(work, [f for f, _ in files], chunksize=8)
    sess_prompts = collections.defaultdict(list)
    ag_tot, ag_per = [], collections.defaultdict(list)
    for path, prompts, agents in res:
        sess_prompts[sid[path]].extend(prompts)
        if agents:
            ag_tot.append(agents["total"])
            for k, v in agents["per"].items():
                ag_per[k].append(v)
    med = lambda v: sorted(v)[len(v) // 2] if v else 0
    out = dict(
        n_sessions=len(sess_prompts),
        n_prompts=sum(len(v) for v in sess_prompts.values()),
        agent_listing=dict(
            n=len(ag_tot),
            median_total=med(ag_tot),
            per_agent={
                k: dict(present=len(v), median_chars=med(v))
                for k, v in sorted(ag_per.items(), key=lambda kv: -med(kv[1]))
            },
        ),
        triggers={},
    )
    joined = {s: "\n".join(v) for s, v in sess_prompts.items()}
    for x in fm:
        name = x["name"]
        text = x["description"] + " " + x["when_to_use"]
        trig = [t.strip().lower() for t in re.findall(r'"([^"\n]{3,80})"', text)]
        trig = [t for t in dict.fromkeys(trig) if not t.startswith("/") and len(t) >= 4]
        used = inv.get(name, set()) | (
            spawn.get(name, set()) if x["kind"] == "agent" else set()
        )
        rows = []
        for t in trig:
            hit = {s for s, j in joined.items() if t in j}
            rows.append(
                dict(trigger=t, sessions=len(hit), with_invocation=len(hit & used))
            )
        namehit = {
            s
            for s, j in joined.items()
            if re.search(r"(^|[^\w-])/?" + re.escape(name.lower()) + r"($|[^\w-])", j)
        }
        out["triggers"][f"{x['kind']}:{name}"] = dict(
            invoked_sessions=len(used),
            name_mentioned_sessions=len(namehit),
            name_mentioned_and_invoked=len(namehit & used),
            declared_triggers=len(trig),
            triggers_seen=[
                r
                for r in sorted(rows, key=lambda r: -r["sessions"])
                if r["sessions"] > 0
            ],
            triggers_unseen=len([r for r in rows if r["sessions"] == 0]),
        )
    json.dump(out, open(OUT, "w"), indent=1)
    print(
        "sessions",
        out["n_sessions"],
        "prompts",
        out["n_prompts"],
        "agent listings",
        out["agent_listing"]["n"],
        "median",
        out["agent_listing"]["median_total"],
    )
    print({k: v for k, v in list(out["agent_listing"]["per_agent"].items())[:20]})


if __name__ == "__main__":
    main()
