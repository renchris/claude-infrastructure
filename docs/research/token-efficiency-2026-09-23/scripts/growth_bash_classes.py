#!/usr/bin/env python3
"""What the Bash tool carries: chars of Bash results and Bash tool_use inputs by command class
(appended after the first response, xdup=0), plus the largest single appended items by chars.

Command class is a HEURISTIC on item.detail (first 120 chars of the command, so a long `cd <path> &&`
prefix can hide the real verb: those land in 'cd…(truncated)'). Writes measure/growth_work/bash_classes.json.
Usage: cd /tmp && nice -n 10 python3 <dir>/scripts/growth_bash_classes.py
"""

import sqlite3, os, re, json, collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DB = os.path.join(ROOT, "data", "extract.sqlite")
W = os.path.join(ROOT, "measure", "growth_work")
c = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)


def cls(d):
    d = (d or "").strip()
    d = re.sub(r'^(cd\s+("[^"]*"|\'[^\']*\'|\S+)\s*(&&|;)\s*)+', "", d)
    d = re.sub(r"^((nice\s+-n\s*\d+|timeout\s+\d+\S*|time|env\s+\S+=\S+)\s+)+", "", d)
    if d.startswith("cd "):
        return "cd…(truncated)"
    if "<<" in d and re.search(r"python3?\b[^|]*<<|node\b[^|]*<<", d):
        return "heredoc_script"
    if re.search(r"cat\s*>\s*\S+\s*<<|cat\s*<<[^|]*>\s*\S+|tee\s+\S+\s*<<", d):
        return "heredoc_file_write"
    if "<<" in d:
        return "heredoc_other"
    w = d.split()[0] if d.split() else ""
    if w in ("cat", "sed", "head", "tail", "nl", "wc", "less"):
        return "file_read"
    if w in ("grep", "rg", "ugrep", "find", "fd", "bfs", "ls", "tree"):
        return "search_list"
    if w == "git":
        return "git"
    if w.startswith("python") or w == "node":
        return "script_inline_or_file"
    if "bats" in d[:60]:
        return "tests"
    if (
        w in ("bash", "sh", "zsh")
        or w.endswith(".sh")
        or w.startswith("./")
        or w.startswith("/")
        or w.startswith("~")
    ):
        return "run_script"
    if w in ("jq", "sqlite3", "awk"):
        return "data_tools"
    if w in ("curl", "gh", "wget"):
        return "network"
    if w in ("echo", "printf"):
        return "echo_printf"
    if w in ("for", "while", "if"):
        return "shell_loop"
    if re.match(r"^[A-Z_]+=", w):
        return "var_assign_then_cmd"
    return "other"


out = {}
for ctn in ("main", "subagent", "workflow_agent", None):
    R = collections.Counter()
    U = collections.Counter()
    N = collections.Counter()
    q = """select i.kind, i.detail, i.chars from item i join ctx c using(file) where i.subkind='Bash' and i.xdup=0
           and i.visible=1 and i.resp_before>=0""" + (
        " and c.ctx_type=?" if ctn else ""
    )
    for kind, det, ch in c.execute(q, (ctn,) if ctn else ()):
        k = cls(det)
        if kind == "tool_result":
            R[k] += ch
            N[k] += 1
        else:
            U[k] += ch
    tr, tu = sum(R.values()), sum(U.values())
    out[ctn or "ALL"] = {
        "result_chars": tr,
        "input_chars": tu,
        "result_share": {k: round(v / tr, 4) for k, v in R.most_common()},
        "result_calls": dict(N),
        "input_share": {k: round(v / tu, 4) for k, v in U.most_common()},
    }
big = c.execute("""select c.ctx_type, i.kind, i.subkind, substr(i.detail,1,90), i.chars from item i join ctx c using(file)
                   where i.xdup=0 and i.visible=1 and i.resp_before>=0 order by i.chars desc limit 25""").fetchall()
out["largest_items_by_chars"] = [
    dict(zip(("ctx", "kind", "subkind", "detail", "chars"), r)) for r in big
]
json.dump(out, open(os.path.join(W, "bash_classes.json"), "w"), indent=1)
for k in ("ALL", "main", "workflow_agent"):
    print(k, out[k]["result_chars"], out[k]["input_chars"])
    print("  R", list(out[k]["result_share"].items())[:10])
    print("  U", list(out[k]["input_share"].items())[:8])
for r in big[:15]:
    print(r)
