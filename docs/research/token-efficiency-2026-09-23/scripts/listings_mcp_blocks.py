#!/usr/bin/env python3
"""Per-server breakdown of the rendered mcp_instructions_delta and deferred_tools_delta attachments.

Reads the INITIAL (first in file) instance of each attachment type from every in-window transcript
that the extract lists (xdup=0), splits the rendered text per server, and reports chars per server
(instructions) and deferred tool-name counts per server / built-in. MEASURED (chars); no tokenizer.
Usage: nice -n 10 python3 listings_mcp_blocks.py <extract.sqlite> <out.json>
"""

import json, re, sqlite3, sys, collections
from multiprocessing import Pool

DB, OUT = sys.argv[1], sys.argv[2]


def work(path):
    got = {}
    try:
        with open(path, "rb") as f:
            for line in f:
                if (
                    b"mcp_instructions_delta" not in line
                    and b"deferred_tools_delta" not in line
                ):
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                a = r.get("attachment") or {}
                t = a.get("type")
                if (
                    t not in ("mcp_instructions_delta", "deferred_tools_delta")
                    or t in got
                ):
                    continue
                if (r.get("timestamp") or "") < "2026-09-09T00:00:00Z":
                    continue
                txt = "".join(
                    (x or {}).get("content", "") for x in (r.get("rendered") or [])
                )
                got[t] = dict(
                    txt=txt,
                    keys=sorted(a.keys()),
                    added=a.get("addedNames")
                    or a.get("addedServerNames")
                    or a.get("names"),
                )
                if len(got) == 2:
                    break
    except Exception:
        pass
    res = {}
    if "mcp_instructions_delta" in got:
        txt = got["mcp_instructions_delta"]["txt"]
        parts = re.split(r"\n## ", "\n" + txt)
        per = {}
        for p in parts[1:]:
            name = p.split("\n", 1)[0].strip()
            per[name] = len(p) + 4
        res["instr"] = dict(total=len(txt), per=per)
    if "deferred_tools_delta" in got:
        txt = got["deferred_tools_delta"]["txt"]
        names = [
            l.strip()
            for l in txt.split("\n")
            if re.match(r"^\s*[A-Za-z_][\w:.-]*\s*$", l)
        ]
        per = collections.Counter()
        for n in names:
            per[
                n.split("__")[1]
                if n.startswith("mcp__") and n.count("__") >= 2
                else "(built-in)"
            ] += 1
        res["deferred"] = dict(
            total=len(txt),
            n=len(names),
            per=dict(per),
            builtin=[n for n in names if not n.startswith("mcp__")],
        )
    return path, res


def main():
    con = sqlite3.connect(DB)
    files = con.execute("""select distinct c.file, c.ctx_type from ctx c join item i on i.file=c.file
        where i.kind='attachment' and i.subkind in ('mcp_instructions_delta','deferred_tools_delta') and i.xdup=0""").fetchall()
    ct = dict(files)
    with Pool(4) as p:
        out = p.map(work, [f for f, _ in files], chunksize=8)
    agg = collections.defaultdict(
        lambda: dict(
            n=0,
            instr_total=[],
            instr_per=collections.defaultdict(list),
            def_total=[],
            def_n=[],
            def_per=collections.defaultdict(list),
            builtin=collections.Counter(),
        )
    )
    for path, r in out:
        a = agg[ct[path]]
        a["n"] += 1
        if "instr" in r:
            a["instr_total"].append(r["instr"]["total"])
            for k, v in r["instr"]["per"].items():
                a["instr_per"][k].append(v)
        if "deferred" in r:
            a["def_total"].append(r["deferred"]["total"])
            a["def_n"].append(r["deferred"]["n"])
            for k, v in r["deferred"]["per"].items():
                a["def_per"][k].append(v)
            for b in r["deferred"]["builtin"]:
                a["builtin"][b] += 1
    med = lambda v: sorted(v)[len(v) // 2] if v else 0
    res = {}
    for k, a in agg.items():
        res[k] = dict(
            files=a["n"],
            instr_n=len(a["instr_total"]),
            instr_median=med(a["instr_total"]),
            instr_per_server={
                s: dict(present=len(v), median_chars=med(v))
                for s, v in a["instr_per"].items()
            },
            deferred_n=len(a["def_total"]),
            deferred_median_chars=med(a["def_total"]),
            deferred_median_names=med(a["def_n"]),
            deferred_per_server={
                s: dict(present=len(v), median_names=med(v))
                for s, v in a["def_per"].items()
            },
            builtin_deferred_names=dict(a["builtin"].most_common(40)),
        )
    json.dump(res, open(OUT, "w"), indent=1)
    for k, v in res.items():
        print(
            k,
            {
                x: v[x]
                for x in (
                    "files",
                    "instr_n",
                    "instr_median",
                    "deferred_n",
                    "deferred_median_chars",
                    "deferred_median_names",
                )
            },
        )
        print("  instr", v["instr_per_server"])
        print("  deferred", v["deferred_per_server"])
        print("  builtin", list(v["builtin_deferred_names"])[:40])


if __name__ == "__main__":
    main()
