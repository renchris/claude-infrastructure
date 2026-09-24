#!/usr/bin/env python3
"""Hook-deny false-positive check: for each hook-deny tool_result, fetch the FULL Bash command
(from the raw transcript, by tool_use_id) and test whether the command actually performs the act the
hook names. A deny whose command does not contain the act (e.g. the trigger text sits inside a grep
pattern, a heredoc, an echo, or a python -c string) is a likely false positive.

Heuristic (ESTIMATED): strip quoted strings and heredoc bodies, then look for the act's verb.
Usage: cd /tmp && nice -n 10 python3 hook_deny_false_positives.py
Prints per rule: n, n_act_present_after_stripping, n_act_only_inside_quotes, examples (60 chars).
"""

import collections, json, os, re, sqlite3

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
db = sqlite3.connect(f"file:{BASE}/data/extract.sqlite?mode=ro", uri=True)

RULES = {  # snippet prefix -> regex for the act on the UNQUOTED command
    "git commit -n blocked": r"\bgit\b[^|;&]*\bcommit\b[^|;&]*\s-n\b",
    "--no-verify blocked": r"--no-verify",
    "DDL blocked": r"\b(CREATE|ALTER|DROP)\s+(TABLE|INDEX|VIEW)\b",
    "git add -f blocked": r"\bgit\b[^|;&]*\badd\b[^|;&]*\s(-f|--force)\b",
    "git add --force blocked": r"\bgit\b[^|;&]*\badd\b[^|;&]*\s(-f|--force)\b",
    "Dangerous command pattern blocked": r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r|\bsudo\s+rm\b",
    "PreToolUse:Bash hook error: [~/.claude/hooks/git-worktree-guard.sh]": r"\bgit\b[^|;&]*\bbranch\b[^|;&]*\s-D\s+main\b|\bgit\b[^|;&]*worktree\s+remove",
    "git identity write": r"\bgit\b[^|;&]*\bconfig\b[^|;&]*user\.(email|name)",
    "Pattern kill blocked": r"\b(pkill|killall)\b|\bkill\b.*\$\(\s*pgrep",
    "curl-gate": r"\bcurl\b",
}


def strip_quotes(cmd):
    cmd = re.sub(r"<<-?\s*'?(\w+)'?.*?\n\1\b", " HEREDOC ", cmd, flags=re.S)
    cmd = re.sub(r"'[^']*'", "''", cmd)
    cmd = re.sub(r'"(?:\\.|[^"\\])*"', '""', cmd)
    return cmd


want = []
for f, tu, sn in db.execute(
    "SELECT file, tool_use_id, snippet FROM item WHERE kind='tool_result' AND xdup=0 AND is_error=1 AND subkind='Bash'"
):
    s = sn or ""
    s2 = (
        re.sub(r"^PreToolUse:Bash hook error: ", "", s)
        if "git-worktree-guard" not in s
        else s
    )
    for pre in RULES:
        if s2.startswith(pre):
            want.append((f, tu, pre))
            break

byfile = collections.defaultdict(list)
for f, tu, pre in want:
    byfile[f].append((tu, pre))
res = collections.defaultdict(lambda: collections.Counter())
ex = collections.defaultdict(list)
for f, lst in byfile.items():
    need = {tu: pre for tu, pre in lst}
    with open(f, errors="ignore") as fh:
        for line in fh:
            if '"tool_use"' not in line or not any(t in line for t in need):
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            for b in (r.get("message") or {}).get("content") or []:
                if (
                    isinstance(b, dict)
                    and b.get("type") == "tool_use"
                    and b.get("id") in need
                ):
                    pre = need.pop(b["id"])
                    cmd = (b.get("input") or {}).get("command", "")
                    act = re.search(
                        RULES[pre],
                        strip_quotes(cmd),
                        re.I if pre == "DDL blocked" else 0,
                    )
                    raw = re.search(
                        RULES[pre], cmd, re.I if pre == "DDL blocked" else 0
                    )
                    k = (
                        "act present"
                        if act
                        else ("only inside quotes/heredoc" if raw else "act absent")
                    )
                    res[pre][k] += 1
                    if k != "act present" and len(ex[pre]) < 6:
                        ex[pre].append(
                            re.sub(r"\s+", " ", cmd)[:90].replace(
                                "/Users/chrisren", "~"
                            )
                        )
out = {}
for pre in RULES:
    if res[pre]:
        n = sum(res[pre].values())
        out[pre] = dict(n=n, **res[pre], examples=ex[pre])
        print(pre[:45].ljust(46), n, dict(res[pre]), ex[pre][:1])
json.dump(
    out, open(os.path.join(BASE, "measure", "tool-errors-hook-fp.json"), "w"), indent=1
)
