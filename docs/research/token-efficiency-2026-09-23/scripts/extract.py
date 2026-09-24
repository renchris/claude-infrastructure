#!/usr/bin/env python3
"""extract.py — build the shared token-efficiency dataset (data/extract.sqlite).

One streaming pass over every Claude Code transcript file under the real config dirs'
projects/ trees (realpath-deduped), keeping records with timestamp >= --since.

Tables (full field docs in data/EXTRACT.md):
  resp  one row per API response, deduped on message.id within a file; xdup=1 marks a
        message.id already seen in an earlier file (cross-file copy, e.g. resume/fork).
  item  one row per item appended to a context (prompt, tool_result, attachment, assistant block).
  ctx   one row per transcript file.
  meta  run parameters and self-check counters.

Usage:
  nice -n 10 python3 scripts/extract.py [--since 2026-09-09T00:00:00Z] [--out data/extract.sqlite]
                                        [--workers 4] [--limit N]
Re-runnable: builds <out>.tmp and renames over <out> at the end.
"""

import argparse, glob, json, math, os, re, sqlite3, sys, time
from multiprocessing import Pool

HOME = os.path.expanduser("~")
CONFIG_DIRS = [
    ".claude",
    ".claude-next",
    ".claude-secondary",
    ".claude-tertiary",
    ".claude-quaternary",
]
SCRIPT_VERSION = "1"

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.join(os.path.dirname(HERE), "data", "extract.sqlite")

UUIDRE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


# ─────────────────────────────── discovery ───────────────────────────────
def classify_path(rp):
    """-> (ctx_type, config_dir, project_slug, session_id, agent_id, workflow_id) or None."""
    parts = rp.split("/")
    try:
        i = parts.index("projects")
    except ValueError:
        return None
    config_dir = parts[i - 1]
    rest = parts[i + 1 :]
    if len(rest) < 2:
        return None
    slug = rest[0]
    fn = rest[-1]
    if len(rest) == 2:
        return ("main", config_dir, slug, fn[:-6], "", "")
    sid = rest[1]
    if len(rest) >= 4 and rest[2] == "subagents":
        if not fn.startswith("agent-"):
            return None
        aid = fn[len("agent-") : -6]
        if len(rest) >= 6 and rest[3] == "workflows":
            return ("workflow_agent", config_dir, slug, sid, aid, rest[4])
        if len(rest) == 4:
            return ("subagent", config_dir, slug, sid, aid, "")
        return ("other", config_dir, slug, sid, aid, "/".join(rest[3:-1]))
    return ("other", config_dir, slug, sid, "", "")


def discover(since_epoch):
    seen = {}
    unknown = 0
    for cd in CONFIG_DIRS:
        root = os.path.join(HOME, cd, "projects")
        if not os.path.isdir(root):
            continue
        for f in glob.iglob(os.path.join(root, "**", "*.jsonl"), recursive=True):
            if os.path.basename(f) == "journal.jsonl":
                continue
            rp = os.path.realpath(f)
            if rp in seen:
                continue
            try:
                st = os.stat(rp)
            except OSError:
                continue
            if (
                st.st_mtime < since_epoch
            ):  # append-only: cannot hold an in-window record
                continue
            c = classify_path(rp)
            if c is None:
                unknown += 1
                continue
            seen[rp] = (c, st.st_size, st.st_mtime)
    return seen, unknown


# ─────────────────────────────── helpers ───────────────────────────────
def tool_detail(name, inp):
    if not isinstance(inp, dict):
        return ""
    try:
        if name == "Skill":
            return str(inp.get("skill") or inp.get("command") or "")[:200]
        if name in ("Agent", "Task"):
            st = inp.get("subagent_type") or ""
            nm = inp.get("name") or ""
            return (st + ("/" + nm if nm else ""))[:200] or str(
                inp.get("description") or ""
            )[:200]
        if name == "Workflow":
            return str(
                inp.get("name") or inp.get("scriptPath") or inp.get("script_path") or ""
            )[:200]
        if name == "Bash":
            return str(inp.get("command") or "")[:120]
        if name in ("Read", "Edit", "Write", "NotebookEdit", "MultiEdit"):
            return str(inp.get("file_path") or inp.get("notebook_path") or "")[:200]
        if name.startswith("mcp__"):
            return name.split("__")[1] if name.count("__") >= 2 else name
        if name == "ToolSearch":
            return str(inp.get("query") or "")[:200]
        if name in ("Grep", "Glob"):
            return str(inp.get("pattern") or "")[:200]
        if name in ("WebFetch",):
            return str(inp.get("url") or "")[:200]
        if name in ("SendMessage",):
            return str(inp.get("to") or "")[:200]
    except Exception:
        return ""
    return ""


def tool_result_text(content):
    """-> (chars, n_images, extra_detail, text_for_snippet)."""
    if isinstance(content, str):
        return len(content), 0, "", content
    if isinstance(content, list):
        n = 0
        imgs = 0
        refs = []
        txt = []
        for b in content:
            if not isinstance(b, dict):
                continue
            t = b.get("type")
            if t == "text":
                s = b.get("text") or ""
                n += len(s)
                txt.append(s)
            elif t == "image":
                imgs += 1
            elif t == "tool_reference":
                refs.append(str(b.get("tool_name") or ""))
            else:
                n += len(json.dumps(b, ensure_ascii=False))
        return n, imgs, ("refs:" + ",".join(refs))[:200] if refs else "", "".join(txt)
    if content is None:
        return 0, 0, "", ""
    s = json.dumps(content, ensure_ascii=False)
    return len(s), 0, "", s


def user_text(content):
    """user message content -> (text, n_images, is_tool_result_msg)."""
    if isinstance(content, str):
        return content, 0, False
    if isinstance(content, list):
        txt = []
        imgs = 0
        tr = False
        for b in content:
            if not isinstance(b, dict):
                continue
            t = b.get("type")
            if t == "tool_result":
                tr = True
            elif t == "text":
                txt.append(b.get("text") or "")
            elif t == "image":
                imgs += 1
        return "\n".join(txt), imgs, tr
    return "", 0, False


def classify_prompt(s, rec, imgs):
    s2 = s.lstrip()[:400]
    ok = (
        (rec.get("origin") or {}).get("kind")
        if isinstance(rec.get("origin"), dict)
        else None
    )
    if s2.startswith("<task-notification") or ok == "task-notification":
        return "task_notification"
    if s2.startswith("<teammate-message"):
        return "teammate_message"
    if s2.startswith("Another Claude session sent"):
        return "peer_message"
    if (
        s2.startswith("<command-name>")
        or s2.startswith("<command-message>")
        or s2.startswith("<local-command-stdout>")
    ):
        return "command"
    if (
        s2.startswith("<bash-input>")
        or s2.startswith("<bash-stdout>")
        or s2.startswith("<bash-stderr>")
    ):
        return "bash_mode"
    if s2.startswith("[Request interrupted"):
        return "interrupt"
    if imgs or "[Pasted text" in s2 or re.match(r"\[Image #\d+\]", s2):
        return "pasted"
    return "plain"


def classify_meta(s, rec, prev_kind_sub):
    if rec.get("isCompactSummary"):
        return "compact_summary"
    s2 = s.lstrip()[:200]
    if s2.startswith("Stop hook feedback"):
        return "stop_hook_feedback"
    if s2.startswith("[Image"):
        return "image_meta"
    if s2.startswith("Base directory for this skill"):
        return "skill_body"
    if s2.startswith("<local-command-caveat>") or s2.startswith("Caveat:"):
        return "local_command_caveat"
    if s2.startswith("<command-name>") or s2.startswith("<command-message>"):
        return "command_marker"
    if s2.startswith("Continue from where you left"):
        return "continue"
    if s2.startswith("<system-reminder>"):
        return "system_reminder"
    if prev_kind_sub in (("user_prompt", "command"), ("meta_user", "command_marker")):
        return "command_body"
    return "other"


def attachment_text(a):
    """Best-effort raw payload length for an attachment (used when no `rendered` field)."""
    t = a.get("type")
    for k in ("content", "text", "prompt", "snippet", "banner"):
        v = a.get(k)
        if isinstance(v, str):
            return len(v)
        if isinstance(v, list):
            return len(json.dumps(v, ensure_ascii=False))
    if t == "instructions":
        return sum(len((f or {}).get("content") or "") for f in a.get("files") or [])
    try:
        return len(json.dumps(a, ensure_ascii=False))
    except Exception:
        return 0


def _s(v):
    """scalar-or-JSON for SQLite binding."""
    if v is None or isinstance(v, (str, int, float)):
        return v
    return json.dumps(v, ensure_ascii=False)


def ts_ok(ts, since):
    return isinstance(ts, str) and ts >= since


# ─────────────────────────────── per-file parse ───────────────────────────────
def parse_file(args):
    rp, cls, size, mtime, since = args
    ctx_type, config_dir, slug, sid, aid, wfid = cls
    resp = {}  # msg_id -> row dict
    order = []  # msg_ids in first-occurrence order (all records, pre-window)
    items = []
    tool_names = {}  # tool_use_id -> (name, detail)
    n_lines = n_bad = n_usage_records = n_before = 0
    n_compact = 0
    models = {}
    versions = {}
    entrypoints = {}
    last_seq = -1  # seq of the last response seen so far (whole-file order)
    prev_ks = None
    first_user_prompt_done = False
    item_seq = 0
    meta_json = {}
    if ctx_type in ("subagent", "workflow_agent"):
        mp = rp[:-6] + ".meta.json"
        try:
            with open(mp) as fh:
                meta_json = json.load(fh)
        except Exception:
            meta_json = {}
    try:
        fh = open(rp, "rb")
    except OSError:
        return None
    blk = [0]
    cur = ["", 0]

    def add_item(t):
        # uid = record uuid + '#' + block index: the key for cross-file (transplant/fork) dedupe
        items.append(t + ("%s#%d" % (cur[0], blk[0]),))
        blk[0] += 1

    with fh:
        for raw in fh:
            n_lines += 1
            blk[0] = 0
            try:
                r = json.loads(raw)
            except Exception:
                n_bad += 1
                continue
            if not isinstance(r, dict):
                continue
            t = r.get("type")
            ts = r.get("timestamp")
            cur[0] = r.get("uuid") or ("L%d" % n_lines)
            if t == "system":
                if r.get("subtype") == "compact_boundary" and ts_ok(ts, since):
                    n_compact += 1
                continue
            if t not in ("assistant", "user", "attachment"):
                continue
            inwin = ts_ok(ts, since)
            if not inwin:
                n_before += 1
            if t == "assistant":
                m = r.get("message")
                if not isinstance(m, dict):
                    continue
                u = m.get("usage") if isinstance(m.get("usage"), dict) else None
                mid = m.get("id") or r.get("requestId") or ("nomid:%s:%d" % (rp, n_lines))
                content = m.get("content") if isinstance(m.get("content"), list) else []
                if u is not None:
                    n_usage_records += 1
                row = resp.get(mid)
                if row is None:
                    last_seq += 1
                    cc = (u or {}).get("cache_creation") or {}
                    row = {
                        "seq": last_seq,
                        "msg_id": mid,
                        "request_id": r.get("requestId") or "",
                        "ts": ts,
                        "in_window": inwin,
                        "model": m.get("model") or "",
                        "input_tokens": int((u or {}).get("input_tokens") or 0),
                        "cc_5m": int(cc.get("ephemeral_5m_input_tokens") or 0),
                        "cc_1h": int(cc.get("ephemeral_1h_input_tokens") or 0),
                        "cc_total": int(
                            (u or {}).get("cache_creation_input_tokens") or 0
                        ),
                        "cache_read": int(
                            (u or {}).get("cache_read_input_tokens") or 0
                        ),
                        "output_tokens": int((u or {}).get("output_tokens") or 0),
                        "output_first": int((u or {}).get("output_tokens") or 0),
                        "has_usage": 1 if u is not None else 0,
                        "n_records": 0,
                        "stop_reason": None,
                        "entrypoint": r.get("entrypoint"),
                        "user_type": r.get("userType"),
                        "is_sidechain": 1 if r.get("isSidechain") else 0,
                        "version": r.get("version"),
                        "effort": r.get("effort"),
                        "service_tier": (u or {}).get("service_tier"),
                        "speed": (u or {}).get("speed"),
                        "iterations_n": len((u or {}).get("iterations") or []),
                        "advisor_model": r.get("advisorModel"),
                        "is_api_error": 1 if r.get("isApiErrorMessage") else 0,
                        "has_thinking": 0,
                        "text_chars": 0,
                        "thinking_chars": 0,
                        "n_thinking": 0,
                        "tools": [],
                        "tool_input_chars": 0,
                    }
                    resp[mid] = row
                    order.append(mid)
                else:
                    if u is not None:
                        o = int(u.get("output_tokens") or 0)
                        if o > row["output_tokens"]:
                            row["output_tokens"] = o
                        if not row["has_usage"]:
                            cc = u.get("cache_creation") or {}
                            row.update(
                                has_usage=1,
                                input_tokens=int(u.get("input_tokens") or 0),
                                cc_5m=int(cc.get("ephemeral_5m_input_tokens") or 0),
                                cc_1h=int(cc.get("ephemeral_1h_input_tokens") or 0),
                                cc_total=int(u.get("cache_creation_input_tokens") or 0),
                                cache_read=int(u.get("cache_read_input_tokens") or 0),
                                output_first=o,
                            )
                row["n_records"] += 1
                if m.get("stop_reason"):
                    row["stop_reason"] = m.get("stop_reason")
                if r.get("isApiErrorMessage"):
                    row["is_api_error"] = 1
                seq = row["seq"]
                for b in content:
                    if not isinstance(b, dict):
                        continue
                    bt = b.get("type")
                    if bt == "text":
                        n = len(b.get("text") or "")
                        row["text_chars"] += n
                        if inwin:
                            add_item(
                                (
                                    item_seq,
                                    seq,
                                    ts,
                                    "assistant_text",
                                    "",
                                    "",
                                    n,
                                    0,
                                    None,
                                    None,
                                    0,
                                    1,
                                    None,
                                )
                            )
                            item_seq += 1
                    elif bt in ("thinking", "redacted_thinking"):
                        n = len(b.get("thinking") or "")
                        row["has_thinking"] = 1
                        row["n_thinking"] += 1
                        row["thinking_chars"] += n
                        if inwin:
                            add_item(
                                (
                                    item_seq,
                                    seq,
                                    ts,
                                    "assistant_thinking",
                                    bt,
                                    "",
                                    n,
                                    0,
                                    None,
                                    None,
                                    0,
                                    1,
                                    None,
                                )
                            )
                            item_seq += 1
                    elif bt in ("tool_use", "server_tool_use"):
                        name = b.get("name") or ""
                        inp = b.get("input")
                        det = tool_detail(name, inp)
                        tool_names[b.get("id")] = (name, det)
                        row["tools"].append(name)
                        if inwin:
                            try:
                                n = len(json.dumps(inp, ensure_ascii=False))
                            except Exception:
                                n = 0
                            row["tool_input_chars"] += n
                            add_item(
                                (
                                    item_seq,
                                    seq,
                                    ts,
                                    "tool_use_input",
                                    name,
                                    det,
                                    n,
                                    0,
                                    None,
                                    b.get("id"),
                                    0,
                                    1,
                                    None,
                                )
                            )
                            item_seq += 1
                prev_ks = None
                continue

            if t == "user":
                m = r.get("message")
                if not isinstance(m, dict):
                    continue
                content = m.get("content")
                if isinstance(content, list) and any(
                    isinstance(b, dict) and b.get("type") == "tool_result"
                    for b in content
                ):
                    for b in content:
                        if not isinstance(b, dict):
                            continue
                        if b.get("type") == "tool_result":
                            tid = b.get("tool_use_id")
                            name, det = tool_names.get(tid, ("?", ""))
                            n, imgs, extra, txt = tool_result_text(b.get("content"))
                            err = 1 if b.get("is_error") else 0
                            if inwin:
                                add_item(
                                    (
                                        item_seq,
                                        last_seq,
                                        ts,
                                        "tool_result",
                                        name,
                                        (det if det else extra)[:200],
                                        n,
                                        err,
                                        txt[:300] if err else None,
                                        tid,
                                        imgs,
                                        1,
                                        None,
                                    )
                                )
                                item_seq += 1
                        elif b.get("type") == "text" and inwin:
                            s = b.get("text") or ""
                            add_item(
                                (
                                    item_seq,
                                    last_seq,
                                    ts,
                                    "meta_user",
                                    "tool_result_sibling_text",
                                    "",
                                    len(s),
                                    0,
                                    None,
                                    None,
                                    0,
                                    1,
                                    None,
                                )
                            )
                            item_seq += 1
                    prev_ks = ("tool_result", "")
                    continue
                s, imgs, _ = user_text(content)
                if r.get("isMeta") or r.get("isCompactSummary"):
                    kind = "meta_user"
                    sub = classify_meta(s, r, prev_ks)
                else:
                    kind = "user_prompt"
                    sub = classify_prompt(s, r, imgs)
                    if (
                        ctx_type != "main"
                        and not first_user_prompt_done
                        and sub == "plain"
                    ):
                        sub = "agent_brief"
                    first_user_prompt_done = True
                det = ""
                if sub == "command":
                    mm = re.search(
                        r"<command-name>/?([^<]{1,80})</command-name>", s
                    ) or re.search(
                        r"<command-message>([^<]{1,80})</command-message>", s
                    )
                    det = mm.group(1) if mm else ""
                if inwin:
                    add_item(
                        (
                            item_seq,
                            last_seq,
                            ts,
                            kind,
                            sub,
                            det,
                            len(s),
                            0,
                            None,
                            None,
                            imgs,
                            1,
                            None,
                        )
                    )
                    item_seq += 1
                prev_ks = (kind, sub)
                continue

            if t == "attachment":
                a = r.get("attachment") or {}
                at = a.get("type") or "?"
                hn = a.get("hookName")
                sub = at + (":" + hn if hn else "")
                rend = r.get("rendered")
                visible = 0
                n = 0
                if isinstance(rend, list) and rend:
                    visible = 1
                    for x in rend:
                        if isinstance(x, dict):
                            c = x.get("content")
                            n += (
                                len(c)
                                if isinstance(c, str)
                                else len(json.dumps(c, ensure_ascii=False))
                            )
                        elif isinstance(x, str):
                            n += len(x)
                raw_n = attachment_text(a)
                det = ""
                if at == "instructions":
                    det = ",".join(
                        os.path.basename(str((f or {}).get("path") or ""))
                        for f in a.get("files") or []
                    )[:200]
                elif at in (
                    "hook_additional_context",
                    "hook_blocking_error",
                    "hook_success",
                    "hook_system_message",
                    "hook_cancelled",
                ):
                    det = str(a.get("hookEvent") or "")
                elif at == "skill_listing":
                    det = "skills=%s initial=%s" % (
                        a.get("skillCount"),
                        a.get("isInitial"),
                    )
                elif at == "nested_memory":
                    det = str(a.get("displayPath") or a.get("path") or "")[:200]
                snip = None
                if at in ("hook_additional_context", "hook_blocking_error"):
                    if (
                        isinstance(rend, list)
                        and rend
                        and isinstance(rend[0], dict)
                        and isinstance(rend[0].get("content"), str)
                    ):
                        snip = rend[0]["content"][:300]
                    else:
                        c = (
                            a.get("content")
                            if at == "hook_additional_context"
                            else a.get("blockingError")
                        )
                        snip = (
                            c
                            if isinstance(c, str)
                            else json.dumps(c, ensure_ascii=False)
                        )[:300]
                if inwin:
                    add_item(
                        (
                            item_seq,
                            last_seq,
                            ts,
                            "attachment",
                            sub[:200],
                            det,
                            n,
                            0,
                            snip,
                            a.get("toolUseID"),
                            0,
                            visible,
                            raw_n,
                        )
                    )
                    item_seq += 1
                continue

    # finalize responses
    resp_rows = []
    tot = dict(
        input=0, cc_5m=0, cc_1h=0, cc_total=0, cache_read=0, output=0, output_first=0
    )
    first_ts = last_ts = None
    n_naive_win = 0
    for mid in order:
        row = resp[mid]
        if not row["in_window"]:
            continue
        n_naive_win += row["n_records"]
        models[row["model"]] = models.get(row["model"], 0) + 1
        if row["version"]:
            versions[row["version"]] = versions.get(row["version"], 0) + 1
        if row["entrypoint"]:
            entrypoints[row["entrypoint"]] = entrypoints.get(row["entrypoint"], 0) + 1
        tot["input"] += row["input_tokens"]
        tot["cc_5m"] += row["cc_5m"]
        tot["cc_1h"] += row["cc_1h"]
        tot["cc_total"] += row["cc_total"]
        tot["cache_read"] += row["cache_read"]
        tot["output"] += row["output_tokens"]
        tot["output_first"] += row["output_first"]
        if first_ts is None or row["ts"] < first_ts:
            first_ts = row["ts"]
        if last_ts is None or row["ts"] > last_ts:
            last_ts = row["ts"]
        resp_rows.append(
            (
                rp,
                config_dir,
                slug,
                ctx_type,
                sid,
                aid,
                wfid,
                row["seq"],
                row["msg_id"],
                row["request_id"],
                row["ts"],
                row["model"],
                row["input_tokens"],
                row["cc_5m"],
                row["cc_1h"],
                row["cc_total"],
                row["cache_read"],
                row["output_tokens"],
                row["output_first"],
                row["has_usage"],
                row["n_records"],
                _s(row["stop_reason"]),
                _s(row["entrypoint"]),
                _s(row["user_type"]),
                row["is_sidechain"],
                _s(row["version"]),
                _s(row["effort"]),
                _s(row["service_tier"]),
                _s(row["speed"]),
                row["iterations_n"],
                _s(row["advisor_model"]),
                row["is_api_error"],
                row["has_thinking"],
                row["n_thinking"],
                row["text_chars"],
                row["thinking_chars"],
                len(row["tools"]),
                ",".join(row["tools"])[:2000],
                row["tool_input_chars"],
                1 if (row["stop_reason"] or row["model"] == "<synthetic>" or row["is_api_error"]) else 0,
            )
        )
    if items:
        its = [x[2] for x in items if isinstance(x[2], str)]
        if its:
            first_ts = min([first_ts] + its) if first_ts else min(its)
            last_ts = max([last_ts] + its) if last_ts else max(its)
    if not resp_rows and not items:
        return ("empty", rp, n_lines, n_bad)
    n_prompts = sum(1 for x in items if x[3] == "user_prompt")
    ctx_row = (
        rp,
        ctx_type,
        config_dir,
        slug,
        sid,
        aid,
        wfid,
        str(meta_json.get("agentType") or ""),
        str(meta_json.get("description") or "")[:200],
        str(meta_json.get("workflowPhase") or ""),
        len(resp_rows),
        n_naive_win,
        first_ts,
        last_ts,
        ",".join(k for k, _ in sorted(models.items(), key=lambda kv: -kv[1])),
        ",".join(k for k, _ in sorted(versions.items(), key=lambda kv: -kv[1])),
        ",".join(k for k, _ in sorted(entrypoints.items(), key=lambda kv: -kv[1])),
        tot["input"],
        tot["cc_5m"],
        tot["cc_1h"],
        tot["cc_total"],
        tot["cache_read"],
        tot["output"],
        tot["output_first"],
        len(items),
        n_prompts,
        n_compact,
        size,
        mtime,
        n_lines,
        n_bad,
        1 if n_before else 0,
    )
    item_rows = [(rp,) + x for x in items]
    return ("ok", ctx_row, resp_rows, item_rows, n_usage_records)


# ─────────────────────────────── output imputation ───────────────────────────────
def _key(level, r):
    # so = the response called StructuredOutput (a workflow agent's terminal call): on 2.1.280 these
    # are nearly the only agent responses with a final usage record, so they must not stand in for
    # mid-loop responses. Level 1 pools MODELS at full shape before level 2 drops the size bucket.
    agentish, model, thk, nt, vis, so = r
    tb = min(nt, 2)
    vb = int(math.log2(vis + 1))
    return (level,) + (
        (agentish, model, thk, tb, vb, so),
        (agentish, thk, tb, vb, so),
        (agentish, model, thk, tb, so),
        (agentish, thk, tb, so),
        (agentish,),
    )[level]


def _fit(rows):
    """rows: [(feat, out)] -> {key: (sum, n)} for every back-off level."""
    acc = {}
    for feat, out in rows:
        for lv in range(5):
            k = _key(lv, feat)
            s_, n_ = acc.get(k, (0, 0))
            acc[k] = (s_ + out, n_ + 1)
    return acc


def _predict(acc, feat, min_n=20):
    for lv in range(5):
        v = acc.get(_key(lv, feat))
        if v and v[1] >= min_n:
            return v[0] / v[1], "strata_L%d" % lv
    return None, "none"


def impute_output(db):
    """ESTIMATED output for responses whose final usage record was never written (output_final=0).

    Stratified mean over final responses keyed on (main|agent, model, has_thinking,
    min(n_tool_use,2), floor(log2(text_chars+tool_input_chars+1))), backing off to coarser strata
    below n=20. Never lowers the recorded value. Validated by a 2-fold hold-out (folds by file
    path CRC32) on final AGENT responses, the population the imputation is applied to."""
    import zlib
    rows = db.execute(
        "SELECT rowid, ctx_type<>'main', model, has_thinking, n_tool_use, "
        "text_chars+tool_input_chars, output_tokens, output_final, file, "
        "instr(tool_use_names,'StructuredOutput')>0 FROM resp WHERE xdup=0"
    ).fetchall()
    final = [r for r in rows if r[7] and r[2] != "<synthetic>"]
    acc = _fit([((r[1], r[2], r[3], r[4], r[5], r[9]), r[6]) for r in final])
    upd = []
    n_imp = 0
    add = 0.0
    for rid, a, m, t, n, v, o, f, _, so in rows:
        if f or m == "<synthetic>":
            upd.append((o, "recorded", rid))
        else:
            p, meth = _predict(acc, (a, m, t, n, v, so))
            est = int(round(max(p, o))) if p is not None else o
            upd.append((est, meth, rid))
            n_imp += 1
            add += est - o
    db.executemany("UPDATE resp SET output_est=?, output_est_method=? WHERE rowid=?", upd)
    db.execute(
        "UPDATE resp SET output_est = (SELECT r2.output_est FROM resp r2 WHERE r2.msg_id = resp.msg_id AND r2.xdup = 0), "
        "output_est_method = (SELECT r2.output_est_method FROM resp r2 WHERE r2.msg_id = resp.msg_id AND r2.xdup = 0) "
        "WHERE xdup = 1"
    )
    res = {}
    for fold in (0, 1):
        infold = lambda r: zlib.crc32(r[8].encode()) % 2 == fold
        tr = [((r[1], r[2], r[3], r[4], r[5], r[9]), r[6]) for r in final if not (r[1] and infold(r))]
        te = [((r[1], r[2], r[3], r[4], r[5], r[9]), r[6]) for r in final if r[1] and infold(r)]
        a2 = _fit(tr)
        preds = [(_predict(a2, ft)[0] or 0, o) for ft, o in te]
        act = sum(o for _, o in preds)
        pred = sum(p for p, _ in preds)
        res["fold%d" % fold] = {
            "n": len(te),
            "actual": act,
            "pred": round(pred),
            "sum_err_pct": round(100 * (pred - act) / act, 2) if act else None,
            "mean_abs_err_per_resp": round(sum(abs(p - o) for p, o in preds) / len(te), 1) if te else None,
            "mean_actual_per_resp": round(act / len(te), 1) if te else None,
        }
    return {"n_imputed": n_imp, "tokens_added_vs_recorded": round(add), "holdout": res}

# ─────────────────────────────── prices ───────────────────────────────
MODEL_CONFIG = os.path.join(
    HOME, "Development", "claude-infrastructure", "model-config.yaml"
)
# Cache-read multipliers of base input (per lead brief + model-config.yaml comments); default 0.1.
CR_MULT = {"claude-fable-5-1": 0.025, "claude-opus-5-5": 0.05}
CW_5M, CW_1H = 1.25, 2.0


def build_prices(db):
    """price(model, in_per_mtok, out_per_mtok, cr_mult, source) for every model seen in resp.
    List prices from model-config.yaml pricing_per_mtok; the fleet is subscription-billed, so these
    are WEIGHTS, not dollars paid."""
    import yaml

    with open(MODEL_CONFIG) as fh:
        cfg = yaml.safe_load(fh)
    pp = {
        k: v
        for k, v in (cfg.get("pricing_per_mtok") or {}).items()
        if isinstance(v, list)
        and len(v) == 2
        and all(isinstance(x, (int, float)) for x in v)
    }
    rows = []
    for (m,) in db.execute("SELECT DISTINCT model FROM resp"):
        base = re.sub(r"(\[1m\])$", "", m or "")
        base2 = re.sub(r"-\d{8}$", "", base)
        if m == "<synthetic>" or not m:
            rows.append((m, 0, 0, 0.1, "synthetic: no API call"))
        elif base2 in pp:
            rows.append(
                (
                    m,
                    pp[base2][0],
                    pp[base2][1],
                    CR_MULT.get(base2, 0.1),
                    "model-config.yaml:" + base2,
                )
            )
        elif base2.startswith("claude-opus-4"):
            rows.append((m, 5, 25, 0.1, "ASSUMED = claude-opus-4-8 row (not listed)"))
        else:
            rows.append((m, None, None, None, "UNPRICED"))
    db.execute("DROP TABLE IF EXISTS price")
    db.execute(
        "CREATE TABLE price (model TEXT PRIMARY KEY, in_per_mtok REAL, out_per_mtok REAL, cr_mult REAL, source TEXT)"
    )
    db.executemany("INSERT INTO price VALUES (?,?,?,?,?)", rows)
    o55 = pp.get("claude-opus-5-5", [4, 20])
    db.executescript(f"""
    DROP VIEW IF EXISTS resp_priced;
    CREATE VIEW resp_priced AS
    SELECT r.*,
      p.in_per_mtok, p.out_per_mtok, p.cr_mult,
      r.input_tokens * p.in_per_mtok / 1e6                       AS usd_input,
      r.cc_5m * p.in_per_mtok * {CW_5M} / 1e6                    AS usd_cw5m,
      r.cc_1h * p.in_per_mtok * {CW_1H} / 1e6                    AS usd_cw1h,
      r.cache_read * p.in_per_mtok * p.cr_mult / 1e6             AS usd_cache_read,
      r.output_est * p.out_per_mtok / 1e6                        AS usd_output_est,
      r.output_tokens * p.out_per_mtok / 1e6                     AS usd_output_recorded,
      (r.input_tokens + r.cc_5m*{CW_5M} + r.cc_1h*{CW_1H} + r.cache_read*p.cr_mult) * p.in_per_mtok / 1e6
        + r.output_est * p.out_per_mtok / 1e6                    AS usd_total,
      (r.input_tokens + r.cc_5m*{CW_5M} + r.cc_1h*{CW_1H} + r.cache_read*0.05) * {o55[0]} / 1e6
        + r.output_est * {o55[1]} / 1e6                          AS usd_total_at_opus55
    FROM resp r LEFT JOIN price p ON p.model = r.model;
    """)
    return {r[0]: r[4] for r in rows}

# ─────────────────────────────── schema ───────────────────────────────
SCHEMA = """
CREATE TABLE resp (
  file TEXT, config_dir TEXT, project_slug TEXT, ctx_type TEXT, session_id TEXT, agent_id TEXT,
  workflow_id TEXT, seq INTEGER, msg_id TEXT, request_id TEXT, ts TEXT, model TEXT,
  input_tokens INTEGER, cc_5m INTEGER, cc_1h INTEGER, cc_total INTEGER, cache_read INTEGER,
  output_tokens INTEGER, output_first INTEGER, has_usage INTEGER, n_records INTEGER,
  stop_reason TEXT, entrypoint TEXT, user_type TEXT, is_sidechain INTEGER, version TEXT,
  effort TEXT, service_tier TEXT, speed TEXT, iterations_n INTEGER, advisor_model TEXT,
  is_api_error INTEGER, has_thinking INTEGER, n_thinking INTEGER, text_chars INTEGER,
  thinking_chars INTEGER, n_tool_use INTEGER, tool_use_names TEXT, tool_input_chars INTEGER,
  output_final INTEGER, xdup INTEGER DEFAULT 0, output_est INTEGER, output_est_method TEXT
);
CREATE TABLE item (
  file TEXT, item_seq INTEGER, resp_before INTEGER, ts TEXT, kind TEXT, subkind TEXT, detail TEXT,
  chars INTEGER, is_error INTEGER, snippet TEXT, tool_use_id TEXT, n_images INTEGER,
  visible INTEGER, raw_chars INTEGER, uid TEXT, xdup INTEGER DEFAULT 0
);
CREATE TABLE ctx (
  file TEXT PRIMARY KEY, ctx_type TEXT, config_dir TEXT, project_slug TEXT, session_id TEXT,
  agent_id TEXT, workflow_id TEXT, agent_type TEXT, agent_desc TEXT, workflow_phase TEXT,
  n_resp INTEGER, n_records_naive INTEGER, first_ts TEXT, last_ts TEXT, models TEXT, versions TEXT,
  entrypoints TEXT, input_tokens INTEGER, cc_5m INTEGER, cc_1h INTEGER, cc_total INTEGER,
  cache_read INTEGER, output_tokens INTEGER, output_first INTEGER, n_items INTEGER,
  n_user_prompts INTEGER, n_compact INTEGER, file_bytes INTEGER, mtime REAL, n_lines INTEGER,
  n_bad_lines INTEGER, spans_window_start INTEGER, n_resp_xdup INTEGER DEFAULT 0
);
CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT);
"""

INDEXES = """
CREATE INDEX resp_file_seq ON resp(file, seq);
CREATE INDEX resp_msg ON resp(msg_id);
CREATE INDEX resp_session ON resp(session_id);
CREATE INDEX resp_model ON resp(model);
CREATE INDEX resp_ctx ON resp(ctx_type, config_dir);
CREATE INDEX resp_ts ON resp(ts);
CREATE INDEX item_file ON item(file, item_seq);
CREATE INDEX item_file_resp ON item(file, resp_before);
CREATE INDEX item_kind ON item(kind, subkind);
CREATE INDEX item_tuid ON item(tool_use_id);
CREATE INDEX ctx_session ON ctx(session_id);
CREATE INDEX ctx_type ON ctx(ctx_type, config_dir);
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-09-09T00:00:00Z")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    try:
        os.nice(10)
    except Exception:
        pass
    since = a.since.replace("+00:00", "Z")
    since_cmp = since[:19]  # ISO prefix compare works for 'YYYY-MM-DDTHH:MM:SS...Z'
    from datetime import datetime, timezone

    since_epoch = (
        datetime.strptime(since_cmp, "%Y-%m-%dT%H:%M:%S")
        .replace(tzinfo=timezone.utc)
        .timestamp()
    )
    t0 = time.time()
    files, unknown = discover(since_epoch)
    todo = sorted(
        files.items(), key=lambda kv: -kv[1][1]
    )  # largest first for pool balance
    if a.limit:
        todo = todo[: a.limit]
    sys.stderr.write(
        "discovered %d files (%.2f GB), %d unclassified paths\n"
        % (len(todo), sum(v[1] for _, v in todo) / 1e9, unknown)
    )
    tmp = a.out + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    db = sqlite3.connect(tmp)
    db.executescript("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;" + SCHEMA)
    stats = dict(files=0, empty=0, lines=0, bad=0, usage_records=0, resp=0, items=0)
    jobs = [(rp, v[0], v[1], v[2], since_cmp) for rp, v in todo]
    with Pool(a.workers) as pool:
        for k, res in enumerate(pool.imap_unordered(parse_file, jobs, chunksize=4)):
            if res is None:
                continue
            if res[0] == "empty":
                stats["empty"] += 1
                stats["lines"] += res[2]
                stats["bad"] += res[3]
                continue
            _, ctx_row, resp_rows, item_rows, nu = res
            db.execute("INSERT INTO ctx VALUES (" + ",".join("?" * 32) + ",0)", ctx_row)
            db.executemany(
                "INSERT INTO resp VALUES (" + ",".join("?" * 40) + ",0,NULL,NULL)", resp_rows
            )
            db.executemany(
                "INSERT INTO item VALUES (" + ",".join("?" * 15) + ",0)", item_rows
            )
            stats["files"] += 1
            stats["resp"] += len(resp_rows)
            stats["items"] += len(item_rows)
            stats["lines"] += ctx_row[29]
            stats["bad"] += ctx_row[30]
            stats["usage_records"] += nu
            if (k + 1) % 500 == 0:
                db.commit()
                sys.stderr.write(
                    "  %d/%d files, %d resp, %d items, %.0fs\n"
                    % (
                        k + 1,
                        len(jobs),
                        stats["resp"],
                        stats["items"],
                        time.time() - t0,
                    )
                )
    db.commit()
    sys.stderr.write("indexing + cross-file dedupe...\n")
    db.executescript(INDEXES)
    # cross-file dedupe: the earliest file (by ctx.first_ts, then path) keeps the message.id
    db.executescript("""
      CREATE TEMP TABLE firsts AS
        SELECT r.rowid AS rid, ROW_NUMBER() OVER (PARTITION BY r.msg_id ORDER BY c.first_ts, r.file, r.seq) AS rn
        FROM resp r JOIN ctx c ON c.file = r.file;
      UPDATE resp SET xdup = 1 WHERE rowid IN (SELECT rid FROM firsts WHERE rn > 1);
      UPDATE ctx SET n_resp_xdup = (SELECT COUNT(*) FROM resp r WHERE r.file = ctx.file AND r.xdup = 1);
      CREATE INDEX item_uid ON item(uid);
      CREATE TEMP TABLE ifirsts AS
        SELECT i.rowid AS rid, ROW_NUMBER() OVER (PARTITION BY i.uid ORDER BY c.first_ts, i.file, i.item_seq) AS rn
        FROM item i JOIN ctx c ON c.file = i.file;
      UPDATE item SET xdup = 1 WHERE rowid IN (SELECT rid FROM ifirsts WHERE rn > 1);
    """)
    imp = impute_output(db)
    db.commit()
    prices = build_prices(db)
    db.commit()
    meta = dict(
        since=since,
        built_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        script_version=SCRIPT_VERSION,
        config_dirs=",".join(CONFIG_DIRS),
        files_discovered=str(len(todo)),
        files_unclassified=str(unknown),
        files_with_rows=str(stats["files"]),
        files_empty_in_window=str(stats["empty"]),
        lines_read=str(stats["lines"]),
        bad_json_lines=str(stats["bad"]),
        usage_records_in_files=str(stats["usage_records"]),
        resp_rows=str(stats["resp"]),
        item_rows=str(stats["items"]),
        imputation=json.dumps(imp),
        prices=json.dumps(prices),
        elapsed_s="%.0f" % (time.time() - t0),
    )
    db.executemany("INSERT INTO meta VALUES (?,?)", list(meta.items()))
    db.commit()
    db.execute("ANALYZE")
    db.commit()
    db.close()
    os.replace(tmp, a.out)
    sys.stderr.write(json.dumps(meta, indent=1) + "\n")


if __name__ == "__main__":
    main()
