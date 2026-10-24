#!/usr/bin/env python3
"""Per-slot outcome scan of Workflow agent() transcripts (read-only, streaming).
For every <cfg>/projects/*/*/subagents/workflows/wf_*/agent-*.jsonl with mtime in the last 8 days
and a first request on/after CUT_TS: agentType (meta.json), brief, tool use, tool errors, denials,
hook blocks, interrupts, API errors, house-rule violations, needs-default signals, final return.
Cross-account copies are deduped by agent id (prefer the file whose mtime is not an integer).
Output: slots.jsonl next to this script; summary to stdout."""

import json, os, re, sys, glob, time, collections, hashlib

ACCTS = {
    "next": "~/.claude-next",
    "next2": "~/.claude-secondary",
    "next3": "~/.claude-tertiary",
    "next4": "~/.claude-quaternary",
}
CUT_TS = sys.argv[1] if len(sys.argv) > 1 else "2026-10-17T00:00:00"
FILE_CUT = time.time() - 8 * 86400
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slots.jsonl")

SAFETY_MARK = "denied by a built-in Claude Code safety check"
CLS = (
    "denied by the Claude Code auto mode classifier",
    "Permission for this action has been denied",
)
USER_REJECT = "The user doesn't want to proceed with this tool use"
INTERRUPT = "[Request interrupted"
HOOK_ERR = re.compile(
    r"PreToolUse:\w+ hook error|hook (?:blocked|denied)|BLOCKED by hook|Blocked by hook",
    re.I,
)
GITMUT = re.compile(
    r"(?:^|[;&|(\s])git(?:\s+-C\s+(\S+))?\s+(commit|push|merge|rebase|cherry-pick|am|reset|checkout|switch|stash|tag|add|clean|worktree\s+add|branch\s+-[dDmM])\b"
)
# house rules a lean worker might not know (CLAUDE.md / rules): stash, reset --hard, rm -r, push, kill
VIOL = {
    "git_stash": re.compile(r"(?:^|[;&|(\s])git(?:\s+-C\s+\S+)?\s+stash\b"),
    "git_reset_hard": re.compile(r"(?:^|[;&|(\s])git(?:\s+-C\s+\S+)?\s+reset\s+--hard"),
    "git_clean": re.compile(r"(?:^|[;&|(\s])git(?:\s+-C\s+\S+)?\s+clean\b"),
    "git_push": re.compile(r"(?:^|[;&|(\s])git(?:\s+-C\s+\S+)?\s+push\b"),
    "rm_r": re.compile(r"(?:^|[;&|(\s])rm\s+-[a-zA-Z]*[rR]"),
    "kill": re.compile(r"(?:^|[;&|(\s])(?:kill|pkill|killall)\s"),
    "sleep_chain": re.compile(r"(?:^|[;&|(\s])sleep\s+\d+\s*(?:;|&&)"),
}
SANDBOX = re.compile(r"(?:^|[\s'\"=])(?:/private)?/tmp/|/var/folders/")
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
REFUSAL = re.compile(
    r"^\W*(?:I can(?:no|')t (?:help|do|assist|comply)|I won't|I'm not able to|I am unable to)",
    re.I,
)


def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    for c in content or []:
        if isinstance(c, dict):
            if c.get("type") == "text":
                out.append(c.get("text") or "")
            elif c.get("type") == "tool_result":
                out.append(text_of(c.get("content")))
    return "\n".join(out)


def scan(path):
    r = dict(
        nreq=0,
        first_tokens=None,
        first_ts=None,
        last_ts=None,
        brief="",
        tools=collections.Counter(),
        tool_errors=0,
        safety_denials=0,
        cls_denials=0,
        user_rejects=0,
        interrupts=0,
        hook_blocks=0,
        timed_denials=0,
        api_errors=0,
        viol=collections.Counter(),
        viol_cmds=[],
        skills=[],
        mcps=[],
        agent_tool=0,
        git_mut_real=0,
        git_mut_sandbox=0,
        git_cmds=[],
        writes_tmp=0,
        writes_repo=0,
        writes_repo_code=0,
        writes_home_claude=0,
        so_calls=0,
        so_errors=0,
        final_kind=None,
        final_text="",
        refusal=0,
        stop_on_issue=0,
        bash_long_fg=0,
        err_samples=[],
    )
    seen = set()
    pending = {}
    last_asst = None
    with open(path, "rb") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            t = d.get("type")
            ts = d.get("timestamp") or ""
            m = d.get("message") or {}
            if t == "user":
                c = m.get("content")
                if (
                    not r["brief"]
                    and isinstance(c, (str, list))
                    and not d.get("isMeta")
                ):
                    tx = text_of(c)
                    if tx and not any(
                        isinstance(x, dict) and x.get("type") == "tool_result"
                        for x in (c if isinstance(c, list) else [])
                    ):
                        r["brief"] = tx[:4000]
                if isinstance(c, list):
                    for x in c:
                        if not isinstance(x, dict) or x.get("type") != "tool_result":
                            continue
                        tx = text_of(x.get("content"))
                        tuid = x.get("tool_use_id")
                        name, t0 = pending.pop(tuid, (None, None))
                        if x.get("is_error"):
                            r["tool_errors"] += 1
                            if len(r["err_samples"]) < 4:
                                r["err_samples"].append(f"{name}: {tx[:220]}")
                            if name == "StructuredOutput":
                                r["so_errors"] += 1
                        if SAFETY_MARK in tx:
                            r["safety_denials"] += 1
                            if t0 and ts:
                                try:
                                    from datetime import datetime

                                    dt = (
                                        datetime.fromisoformat(
                                            ts.replace("Z", "+00:00")
                                        )
                                        - datetime.fromisoformat(
                                            t0.replace("Z", "+00:00")
                                        )
                                    ).total_seconds()
                                    if dt >= 110:
                                        r["timed_denials"] += 1
                                except Exception:
                                    pass
                        if any(p in tx for p in CLS):
                            r["cls_denials"] += 1
                        if USER_REJECT in tx:
                            r["user_rejects"] += 1
                        if INTERRUPT in tx:
                            r["interrupts"] += 1
                        if HOOK_ERR.search(tx[:600]):
                            r["hook_blocks"] += 1
                elif isinstance(c, str) and INTERRUPT in c:
                    r["interrupts"] += 1
            elif t == "assistant":
                if m.get("model") == "<synthetic>" or d.get("isApiErrorMessage"):
                    tx = text_of(m.get("content"))
                    if d.get("isApiErrorMessage") or tx.startswith("API Error"):
                        r["api_errors"] += 1
                    continue
                mid = m.get("id")
                u = m.get("usage")
                if mid and mid not in seen:
                    seen.add(mid)
                    r["nreq"] += 1
                    if r["first_ts"] is None:
                        r["first_ts"] = ts
                        if u:
                            r["first_tokens"] = (
                                (u.get("input_tokens") or 0)
                                + (u.get("cache_creation_input_tokens") or 0)
                                + (u.get("cache_read_input_tokens") or 0)
                            )
                if ts:
                    r["last_ts"] = ts
                last_asst = m
                for c in m.get("content") or []:
                    if not isinstance(c, dict) or c.get("type") != "tool_use":
                        continue
                    n = c.get("name", "")
                    inp = c.get("input") or {}
                    r["tools"][n] += 1
                    pending[c.get("id")] = (n, ts)
                    if n == "Skill":
                        r["skills"].append(
                            str(inp.get("skill") or inp.get("command"))[:60]
                        )
                    elif n.startswith("mcp__"):
                        r["mcps"].append(n.split("__")[1])
                    elif n in ("Agent", "Task"):
                        r["agent_tool"] += 1
                    elif n == "StructuredOutput":
                        r["so_calls"] += 1
                    elif n in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                        p = str(inp.get("file_path") or inp.get("notebook_path") or "")
                        if p.startswith(("/tmp/", "/private/tmp/", "/var/folders/")):
                            r["writes_tmp"] += 1
                        elif re.match(r"^/Users/[^/]+/\.claude", p):
                            r["writes_home_claude"] += 1
                        else:
                            r["writes_repo"] += 1
                            if p.endswith(CODE_EXT):
                                r["writes_repo_code"] += 1
                    elif n == "Bash":
                        cmd = str(inp.get("command", ""))
                        to = inp.get("timeout")
                        if (
                            isinstance(to, (int, float))
                            and to > 270000
                            and not inp.get("run_in_background")
                        ):
                            r["bash_long_fg"] += 1
                        mm = GITMUT.search(cmd)
                        if mm:
                            sb = bool(SANDBOX.search(cmd))
                            if sb:
                                r["git_mut_sandbox"] += 1
                            else:
                                r["git_mut_real"] += 1
                            if len(r["git_cmds"]) < 5:
                                r["git_cmds"].append(cmd[:240])
                        for k, rx in VIOL.items():
                            if rx.search(cmd):
                                if (
                                    k in ("rm_r",)
                                    and SANDBOX.search(cmd)
                                    and not re.search(
                                        r"rm\s+-[a-zA-Z]*[rR][a-zA-Z]*\s+(?:~|/Users|\$HOME|\.)",
                                        cmd,
                                    )
                                ):
                                    k = k + "_tmp"
                                if k in (
                                    "git_stash",
                                    "git_reset_hard",
                                    "git_clean",
                                ) and SANDBOX.search(cmd):
                                    k = k + "_tmp"
                                r["viol"][k] += 1
                                if len(r["viol_cmds"]) < 6:
                                    r["viol_cmds"].append(f"{k}: {cmd[:240]}")
    if last_asst is not None:
        kinds = [
            c.get("type") + (":" + c.get("name") if c.get("type") == "tool_use" else "")
            for c in (last_asst.get("content") or [])
            if isinstance(c, dict)
        ]
        r["final_kind"] = ",".join(kinds)[:120]
        ft = text_of(last_asst.get("content"))
        r["final_text"] = ft[:600]
        if REFUSAL.search(ft):
            r["refusal"] = 1
        if re.search(
            r"\b(?:stop(?:ping)? on issue|cannot proceed|precondition fail|out of scope for (?:a|this) (?:lean|read-only))",
            ft,
            re.I,
        ):
            r["stop_on_issue"] = 1
    r["tools"] = dict(r["tools"])
    r["viol"] = dict(r["viol"])
    return r


def main():
    t0 = time.time()
    files = []
    for a, d in ACCTS.items():
        for f in glob.glob(
            os.path.expanduser(d)
            + "/projects/*/*/subagents/workflows/wf_*/agent-*.jsonl"
        ):
            try:
                st = os.stat(f)
            except OSError:
                continue
            if st.st_mtime < FILE_CUT:
                continue
            files.append((a, f, st.st_mtime, st.st_size))
    # dedup by agent id: prefer non-integer mtime (the original), else first seen
    by = {}
    for a, f, mt, sz in files:
        aid = os.path.basename(f)[:-6]
        cur = by.get(aid)
        if cur is None or (float(cur[2]).is_integer() and not float(mt).is_integer()):
            by[aid] = (a, f, mt, sz)
    n = 0
    bytes_ = 0
    with open(OUT, "w") as fo:
        for aid, (a, f, mt, sz) in by.items():
            meta = {}
            try:
                meta = json.load(open(f[:-6] + ".meta.json"))
            except Exception:
                pass
            r = scan(f)
            if not r["first_ts"] or r["first_ts"] < CUT_TS:
                continue
            bytes_ += sz
            n += 1
            r.update(
                acct=a,
                path=f,
                aid=aid,
                wf=os.path.basename(os.path.dirname(f)),
                agentType=meta.get("agentType"),
                desc=meta.get("description"),
                phase=meta.get("workflowPhase"),
                brief_hash=hashlib.sha1(r["brief"][:600].encode()).hexdigest()[:10],
            )
            fo.write(json.dumps(r) + "\n")
    print(
        f"files {len(files)} unique {len(by)} kept {n} bytes {bytes_ / 1e9:.2f}GB {time.time() - t0:.0f}s -> {OUT}"
    )


main()
