#!/usr/bin/env python3
"""REPLAY of hooks/workflow-lean-shadow.py (imported verbatim from hook_copy.py, sha d50b151) over
every Workflow run of the last 30 days on the 4 accounts, joined to what each slot actually did.
Read-only over ~/.claude-*; writes only under /tmp/lean-idle/workflow-lean/.

Outputs: runs.jsonl (one row per unique runId), slots.jsonl (one row per slot), sites.jsonl."""

import collections
import glob
import hashlib
import importlib.util
import json
import os
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor

sys.dont_write_bytecode = True
W = "/tmp/lean-idle/workflow-lean"
spec = importlib.util.spec_from_file_location("hook", os.path.join(W, "hook_copy.py"))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

CUT_MS = int(time.mktime(time.strptime("2026-09-24", "%Y-%m-%d")) * 1000)
ACCT = {
    ".claude-next": "next",
    ".claude-secondary": "next2",
    ".claude-tertiary": "next3",
    ".claude-quaternary": "next4",
}
LEAN_TOOLS = {
    "Read",
    "Grep",
    "Glob",
    "Bash",
    "Write",
    "Edit",
    "WebFetch",
    "WebSearch",
    "StructuredOutput",
}
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?.*?\n.*?\n\s*\1\b", re.S)
QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
SBX = re.compile(r"(?:/private)?/tmp/|/var/folders/|mktemp|TMPDIR")
GITMUT = re.compile(
    r"(?:^|[;&|(\s])git(?:\s+-C\s+\S+)?(?:\s+-c\s+\S+)*\s+(commit|push|merge|rebase|cherry-pick|am|"
    r"reset|checkout|switch|stash\s+(?:push|pop|apply|drop|clear|save)|stash\s*(?:$|[;&|)])|"
    r"tag\s+-?[a-zA-Z]|add|clean|worktree\s+add|branch\s+-[dDmM])(?![\w-])"
)
SHIP = re.compile(r"ship-land(?:\.sh)?\b|deploy-live(?:\.sh)?\b|(?:^|\s)/ship\b")
HOUSE = re.compile(
    r"(?:^|[;&|(\s/])(cc-backlog|cc-decide|cc-custody|handoff-fire(?:\.sh)?|cc-notify|"
    r"cc-do|cc-await-ping|cc-send|cc-peer)\b"
)
SBX2 = re.compile(r"(?:/private)?/tmp\b|/var/folders/|mktemp|TMPDIR")
SEG_SPLIT = re.compile(r"[;&|\n()]+|\$\(|`")
PREFIX_WORDS = {
    "command",
    "exec",
    "nohup",
    "time",
    "env",
    "sudo",
    "builtin",
    "then",
    "do",
    "else",
    "{",
    "}",
    "!",
    "if",
    "while",
    "until",
}
SHIP_WORDS = {"ship-land", "ship-land.sh", "deploy-live", "deploy-live.sh"}
HOUSE_WORDS = {
    "cc-backlog",
    "cc-decide",
    "cc-custody",
    "handoff-fire",
    "handoff-fire.sh",
    "cc-notify",
    "cc-do",
    "cc-send",
}
GIT_MUT = {
    "commit",
    "push",
    "merge",
    "rebase",
    "cherry-pick",
    "am",
    "reset",
    "checkout",
    "switch",
    "restore",
    "add",
    "rm",
    "mv",
    "clean",
    "pull",
    "revert",
}


def seg_words(cmd):
    """first words of each simple command (heredoc bodies and quoted strings blanked)."""
    c3 = QUOTED.sub(" Q ", HEREDOC.sub(" H ", cmd))
    for seg in SEG_SPLIT.split(c3):
        w = seg.split()
        i = 0
        while i < len(w):
            t = w[i]
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t) or t in PREFIX_WORDS:
                i += 1
                continue
            if t == "timeout":
                i += 1
                while i < len(w) and (w[i].startswith("-") or re.match(r"^\d", w[i])):
                    i += 1
                continue
            if (
                t in ("bash", "sh", "zsh")
                and i + 1 < len(w)
                and not w[i + 1].startswith("-")
            ):
                i += 1
                continue
            break
        if i < len(w):
            yield w[i:]


def git_mutation(words):
    """words start at 'git': return the mutating subcommand or None."""
    i = 1
    while i < len(words):
        t = words[i]
        if t in ("-C", "-c", "--git-dir", "--work-tree"):
            i += 2
            continue
        if t.startswith("-"):
            i += 1
            continue
        break
    if i >= len(words):
        return None
    sub, rest = words[i], words[i + 1 :]
    if sub in GIT_MUT:
        return sub
    if sub == "stash":
        return None if rest[:1] and rest[0] in ("list", "show") else "stash"
    if sub == "tag":
        if (
            not rest
            or rest[0]
            in (
                "-l",
                "--list",
                "-n",
                "--contains",
                "--points-at",
                "--sort",
                "--merged",
                "--no-merged",
            )
            or rest[0].startswith("--sort")
        ):
            return None
        return "tag"
    if sub == "branch":
        return (
            "branch"
            if rest[:1]
            and rest[0]
            in ("-d", "-D", "-m", "-M", "-f", "--delete", "--move", "--force")
            else None
        )
    if sub == "worktree":
        return (
            "worktree"
            if rest[:1] and rest[0] in ("add", "remove", "move", "prune")
            else None
        )
    return None


CODE_EXT = (
    ".py",
    ".sh",
    ".js",
    ".mjs",
    ".ts",
    ".tsx",
    ".rb",
    ".go",
    ".rs",
    ".swift",
    ".bats",
    ".json",
    ".yaml",
    ".yml",
)


def acct_of(p):
    for k, v in ACCT.items():
        if f"/{k}/" in p:
            return v
    return "?"


# ---------- static side: replay the hook, plus mapping aids ----------
def frags(arg):
    """static string fragments of a brief argument, split at ${...}"""
    out, s, i = [], arg, 0
    while i < len(s):
        c = s[i]
        j = hook.skip_comment(s, i)
        if j is not None:
            i = j
            continue
        if c in "'\"":
            j = hook.skip_quoted(s, i)
            out.append(s[i + 1 : j - 1])
            i = j
        elif c == "`":
            i += 1
            buf = []
            while i < len(s):
                ch = s[i]
                if ch == "\\":
                    buf.append(s[i : i + 2])
                    i += 2
                    continue
                if ch == "`":
                    i += 1
                    break
                if s.startswith("${", i):
                    out.append("".join(buf))
                    buf = []
                    i = hook.walk(s, i + 2, "}") + 1
                    continue
                buf.append(ch)
                i += 1
            out.append("".join(buf))
        else:
            i += 1
    res = []
    for f in out:
        f = (
            f.replace("\\n", "\n")
            .replace("\\t", "\t")
            .replace("\\'", "'")
            .replace('\\"', '"')
            .replace("\\`", "`")
            .replace("\\\\", "\\")
        )
        f = re.sub(r"\s+", " ", f).strip()
        if len(f) >= 15:
            res.append(f)
    return res


def label_rx(label):
    if not label:
        return None
    parts = re.split(r"\$\{[^}]*\}?", label)
    rx = ".*?".join(re.escape(p) for p in parts)
    try:
        return re.compile(rx + ("" if len(label) < 80 else ".*"), re.S)
    except re.error:
        return None


def replay(src):
    calls = hook.agent_calls(src)
    sites = []
    for off, args in calls:
        r = hook.slot_row(src, off, args)
        r["frags"] = frags(args[0]) if args else []
        sites.append(r)
    counts = collections.Counter(s["verdict"] for s in sites)
    return sites, counts


# ---------- dynamic side: what each slot did ----------
def text_of(c):
    if isinstance(c, str):
        return c
    out = []
    for x in c or []:
        if isinstance(x, dict) and x.get("type") == "text":
            out.append(x.get("text") or "")
    return "\n".join(out)


def scan_slot(path):
    r = dict(
        nreq=0,
        first_tokens=None,
        first_cw=None,
        cw=0,
        cr=0,
        out=0,
        inp=0,
        version=None,
        model=None,
        tools=collections.Counter(),
        skills=[],
        mcps=[],
        agent_tool=0,
        git_real=0,
        git_sbx=0,
        ship=0,
        house=0,
        home_claude_write=0,
        repo_code_write=0,
        repo_write=0,
        brief="",
        first_ts=None,
        git_cmds=[],
    )
    users = 0
    usage = {}
    order = []
    try:
        fh = open(path, "rb")
    except OSError:
        return None
    with fh:
        for line in fh:
            if users < 3 and b'"type":"user"' in line:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                c = (d.get("message") or {}).get("content")
                if isinstance(c, list) and any(
                    isinstance(x, dict) and x.get("type") == "tool_result" for x in c
                ):
                    users = 3
                    continue
                users += 1
                r["brief"] += "\n" + text_of(c)[:20000]
                continue
            if b'"assistant"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            m = d.get("message") or {}
            if m.get("model") == "<synthetic>":
                continue
            mid = m.get("id")
            if mid:
                if mid not in usage:
                    order.append(mid)
                    if r["first_ts"] is None:
                        r["first_ts"] = d.get("timestamp")
                        r["version"] = d.get("version")
                        r["model"] = m.get("model")
                if m.get("usage"):
                    usage[mid] = m["usage"]
            for c in m.get("content") or []:
                if not isinstance(c, dict) or c.get("type") != "tool_use":
                    continue
                n = c.get("name", "")
                inp = c.get("input") or {}
                r["tools"][n] += 1
                if n == "Skill":
                    sk = str(inp.get("skill") or inp.get("command") or "")[:60]
                    r["skills"].append(sk)
                    if sk.strip("/").split()[0:1] == ["ship"]:
                        r["ship"] += 1
                elif n.startswith("mcp__"):
                    r["mcps"].append(n.split("__")[1] if "__" in n else n)
                elif n in ("Agent", "Task"):
                    r["agent_tool"] += 1
                elif n in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                    p = str(inp.get("file_path") or inp.get("notebook_path") or "")
                    if p.startswith(("/tmp/", "/private/tmp/", "/var/folders/")):
                        pass
                    elif re.match(r"^/Users/[^/]+/\.claude", p):
                        r["home_claude_write"] += 1
                    else:
                        r["repo_write"] += 1
                        if p.endswith(CODE_EXT):
                            r["repo_code_write"] += 1
                elif n == "Bash":
                    cmd = str(inp.get("command", ""))
                    gm = ship = house = False
                    for wds in seg_words(cmd):
                        base = os.path.basename(wds[0])
                        if base == "git" and git_mutation(wds):
                            gm = True
                        elif base in SHIP_WORDS:
                            ship = True
                        elif base in HOUSE_WORDS:
                            house = True
                    if gm:
                        if SBX2.search(cmd):
                            r["git_sbx"] += 1
                        else:
                            r["git_real"] += 1
                            if len(r["git_cmds"]) < 3:
                                r["git_cmds"].append(cmd[:200])
                    if ship:
                        r["ship"] += 1
                        if len(r["git_cmds"]) < 3:
                            r["git_cmds"].append("SHIP " + cmd[:200])
                    if house:
                        r["house"] += 1
    r["nreq"] = len(order)
    for i, mid in enumerate(order):
        u = usage.get(mid) or {}
        cw = u.get("cache_creation_input_tokens") or 0
        cr = u.get("cache_read_input_tokens") or 0
        ip = u.get("input_tokens") or 0
        if i == 0:
            r["first_tokens"] = cw + cr + ip
            r["first_cw"] = cw
        r["cw"] += cw
        r["cr"] += cr
        r["inp"] += ip
        r["out"] += u.get("output_tokens") or 0
    r["tools"] = dict(r["tools"])
    return r


def need_class(r):
    if r["skills"]:
        return "skill"
    if r["mcps"]:
        return "mcp"
    if r["agent_tool"]:
        return "agent_tool"
    if r["ship"]:
        return "ship"
    if r["git_real"]:
        return "git_real"
    if r["home_claude_write"]:
        return "claude_home_write"
    if r["house"]:
        return "house_tool"
    if r["repo_code_write"]:
        return "repo_code_write"
    if r["git_sbx"]:
        return "git_sandbox"
    if set(r["tools"]) - LEAN_TOOLS:
        return "soft"
    return "none"


HARD = {"skill", "mcp", "agent_tool", "ship", "git_real", "claude_home_write"}
BORDER = {"house_tool", "repo_code_write", "git_sandbox"}


def work_slot(args):
    path, meta_path = args
    try:
        meta = json.load(open(meta_path))
    except Exception:
        meta = {}
    r = scan_slot(path)
    if r is None:
        return None
    r["cls"] = need_class(r)
    r["agentType"] = meta.get("agentType")
    r["desc"] = meta.get("description")
    r["phase"] = meta.get("workflowPhase")
    r["path"] = path
    r["aid"] = os.path.basename(path)[6:-6]
    return r


def main():
    t0 = time.time()
    # ---- runs from JSON ----
    runs = {}
    for p in (l.strip() for l in open(os.path.join(W, "wfjson_index.txt"))):
        try:
            d = json.load(open(p))
        except Exception:
            continue
        rid = d.get("runId") or os.path.basename(p)[:-5]
        st = d.get("startTime") or 0
        cur = runs.get(rid)
        row = dict(
            runId=rid,
            start=st,
            name=d.get("workflowName"),
            status=d.get("status"),
            script=d.get("script"),
            scriptPath=d.get("scriptPath"),
            json=p,
            acct=acct_of(p),
            agentCount=d.get("agentCount"),
            totalTokens=d.get("totalTokens"),
            model=d.get("defaultModel"),
        )
        if cur is None or (len(row["script"] or "") > len(cur["script"] or "")):
            runs[rid] = row
    # ---- runs from saved script files (no JSON) ----
    for p in (l.strip() for l in open(os.path.join(W, "scripts30.txt"))):
        m = re.search(r"(wf_[0-9a-f]{8}-[0-9a-f]{3})\.m?js$", p)
        if not m:
            continue
        rid = m.group(1)
        if rid in runs and runs[rid].get("script"):
            continue
        try:
            src = open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        runs.setdefault(
            rid,
            dict(
                runId=rid,
                start=int(os.stat(p).st_mtime * 1000),
                name=None,
                status=None,
                json=None,
                acct=acct_of(p),
                scriptPath=p,
            ),
        )
        runs[rid]["script"] = src
        runs[rid]["script_file"] = p
    # ---- run dirs ----
    dirs = collections.defaultdict(list)
    for p in (l.strip() for l in open(os.path.join(W, "wf_index.txt"))):
        dirs[os.path.basename(p)].append(p)

    def best_dir(rid):
        cands = dirs.get(rid) or []
        best = None
        for c in cands:
            n = len(glob.glob(c + "/agent-*.jsonl"))
            try:
                mt = os.stat(c).st_mtime
            except OSError:
                continue
            key = (n, not float(mt).is_integer())
            if best is None or key > best[0]:
                best = (key, c)
        return best[1] if best else None

    # runs that have only a dir: use journal/agent timestamps for the window
    for rid in dirs:
        if rid not in runs:
            d = best_dir(rid)
            st = 0
            if d:
                try:
                    st = int(os.stat(d).st_mtime * 1000)
                except OSError:
                    pass
            runs[rid] = dict(
                runId=rid,
                start=st,
                name=None,
                status=None,
                script=None,
                json=None,
                acct=acct_of(d or ""),
                dir_only=True,
            )
    keep = {k: v for k, v in runs.items() if (v.get("start") or 0) >= CUT_MS}
    print(f"runs total {len(runs)} in window {len(keep)}", file=sys.stderr)

    jobs = []
    for rid, r in keep.items():
        d = best_dir(rid)
        r["dir"] = d
        r["slots"] = []
        if not d:
            continue
        jpath = os.path.join(d, "journal.jsonl")
        started = {}
        if os.path.exists(jpath):
            for l in open(jpath):
                try:
                    j = json.loads(l)
                except Exception:
                    continue
                if j.get("type") == "started" and j.get("agentId"):
                    started[j["agentId"]] = dict(
                        label=j.get("label"), phase=j.get("phase")
                    )
        r["journal"] = bool(started)
        for a in glob.glob(d + "/agent-*.jsonl"):
            aid = os.path.basename(a)[6:-6]
            r["slots"].append(dict(aid=aid, **(started.get(aid) or {})))
            jobs.append((a, a[:-6] + ".meta.json"))
    print(f"slot transcripts {len(jobs)}", file=sys.stderr)
    with ProcessPoolExecutor(8) as ex:
        res = list(ex.map(work_slot, jobs, chunksize=8))
    by_aid = {x["aid"]: x for x in res if x}
    print(f"scanned {len(by_aid)} in {time.time() - t0:.0f}s", file=sys.stderr)

    fr = open(os.path.join(W, "runs.jsonl"), "w")
    fs = open(os.path.join(W, "slots.jsonl"), "w")
    for rid, r in keep.items():
        src = r.get("script")
        sites, counts = ([], collections.Counter())
        if src:
            try:
                sites, counts = replay(src)
            except Exception as e:  # noqa
                r["replay_error"] = str(e)[:200]
        r["sha"] = hashlib.sha1(src.encode()).hexdigest()[:12] if src else None
        r["needs_default_marker"] = bool(src and re.search(r"needs-default", src))
        r["verdicts"] = dict(counts)
        r["would_deny"] = counts.get("would-deny", 0) > 0
        r["n_sites"] = len(sites)
        rx = [label_rx(s["label"]) for s in sites]
        for s in r["slots"]:
            x = by_aid.get(s["aid"])
            if not x:
                continue
            lab = s.get("label") or x.get("desc") or ""
            brief = re.sub(r"\s+", " ", x["brief"])
            cands = [i for i, q in enumerate(rx) if q is not None and q.fullmatch(lab)]
            how = "label"
            if len(cands) != 1:
                pool = cands or list(range(len(sites)))
                sc = []
                for i in pool:
                    fr_ = sites[i]["frags"]
                    sc.append((sum(len(f) for f in fr_ if f[:80] in brief), i))
                sc.sort(reverse=True)
                if sc and sc[0][0] > 0 and (len(sc) == 1 or sc[0][0] > sc[1][0]):
                    cands, how = [sc[0][1]], ("label+brief" if cands else "brief")
                elif sc and sc[0][0] > 0:
                    top = [i for v, i in sc if v == sc[0][0]]
                    # agentType consistency
                    at = x["agentType"]
                    top2 = [
                        i
                        for i in top
                        if (sites[i]["agent_type"] in (None, "opaque"))
                        == (at == "workflow-subagent")
                        or sites[i]["agent_type"] == at
                    ]
                    top = top2 or top
                    vs = {sites[i]["verdict"] for i in top}
                    cands, how = (
                        ([top[0]], "tie-same-verdict")
                        if len(vs) == 1
                        else ([], "ambiguous")
                    )
                else:
                    if pool and len({sites[i]["verdict"] for i in pool}) == 1 and cands:
                        cands, how = [pool[0]], "label-multi-same-verdict"
                    else:
                        cands, how = [], "unmapped"
            site = cands[0] if cands else None
            row = {
                k: x[k]
                for k in (
                    "aid",
                    "agentType",
                    "cls",
                    "nreq",
                    "first_tokens",
                    "first_cw",
                    "cw",
                    "cr",
                    "out",
                    "inp",
                    "version",
                    "model",
                    "skills",
                    "mcps",
                    "agent_tool",
                    "git_real",
                    "git_sbx",
                    "ship",
                    "house",
                    "home_claude_write",
                    "repo_code_write",
                    "repo_write",
                    "tools",
                    "first_ts",
                    "git_cmds",
                )
            }
            row.update(
                runId=rid,
                acct=r["acct"],
                label=lab,
                map=how,
                site=site,
                site_verdict=sites[site]["verdict"] if site is not None else None,
                site_agent_type=sites[site]["agent_type"] if site is not None else None,
                site_markers=sites[site]["markers"] if site is not None else None,
                run_would_deny=r["would_deny"],
                sha=r["sha"],
                brief_has_wf_user_request="[Workflow harness — user request]"
                in x["brief"],
            )
            fs.write(json.dumps(row) + "\n")
        out = {k: v for k, v in r.items() if k not in ("script", "slots")}
        out["n_slots"] = len(r["slots"])
        out["sites"] = [{k: v for k, v in s.items() if k != "frags"} for s in sites]
        out["script_chars"] = len(src) if src else None
        fr.write(json.dumps(out) + "\n")
    print(f"done {time.time() - t0:.0f}s", file=sys.stderr)


if __name__ == "__main__":
    main()
