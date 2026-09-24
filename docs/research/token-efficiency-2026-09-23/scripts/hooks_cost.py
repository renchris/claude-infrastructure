#!/usr/bin/env python3
"""Price what the hook layer adds to the model's context, and the turns it forces.

Inputs (read-only): data/extract.sqlite (resp, item, ctx, price), data/hooks.sqlite (hooks_scan.py).
Output: measure/hooks_cost.json (+ a printed summary).

INJECTIONS (MEASURED counts/chars; $ ESTIMATED via chars->tokens):
  every item with xdup=0, visible=1 and subkind hook_* or stop_hook_feedback. A merged
  hook_additional_context item is split across its content[] elements pro rata to element chars,
  and each element is attributed to a script by signature (RULES) or by the recorded command.
  tokens = chars / CPT (CPT=2.5, fitted in probe_stop_block_double.py: 2.42 (no thinking) /
  2.65 (thinking) / 2.60 (meta-only); /context memory files 2.5-2.6).
  Persistence cost of an item appended after response s, per later response r of the same file:
    - if cache_read(r) >= pos + tok       -> cache READ at r's model rate
    - elif cc_total(r) > 0                -> cache WRITE at r's TTL mix (5m 1.25x / 1h 2x)
    - else                                -> uncached input
    and the item is considered gone (compaction/clear) once total_in(r) < pos + tok,
    with pos = total_in(s) (the context size before the item; 0 when s = -1).
  Priced at each response's own model and re-priced at Opus 5.5 ($4, cr 0.05x).

FORCED TURNS (MEASURED spans; $ = full priced responses, output via output_est):
  trigger = 'Stop hook feedback:' meta items (xdup=0) grouped by (file, resp_before).
  span = responses after the trigger up to the next stop_hook_summary or the next genuine user
  prompt, whichever is first. The span's full cost is attributed to the blocking hook(s), split
  equally when several blocked at once. A heuristic class is assigned from the span's tool calls.
"""

import collections
import json
import re
import sqlite3
import statistics

import numpy as np

BASE = "/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23"
CPT = 2.5
O55 = (4.0, 20.0, 0.05)

RULES = [  # (regex on element prefix, script)
    (r"^knowledge-layer mirror re-asserted", "config-mirror-assert.sh"),
    (r"^MEMORY INDEX BUDGET|^MEMORY CHECK \(periodic\)", "memory-nudge.sh"),
    (r"^🔔 No inbox wake path armed", "mailbox-drain.sh [wake-path nag]"),
    (r"^📬 peer mail", "mailbox-drain.sh [peer mail]"),
    (r"^🚨 A parked watcher is holding", "mailbox-drain.sh [parked-watcher warning]"),
    (r"^HANDOFF-INTENT PARITY", "handoff-intent-nudge.sh"),
    (r"^PLAN DEFAULTS:|^EXECUTION LOCUS", "plan-agent-teams-default.sh"),
    (r"^Durable frozen DoD", "dod-persist.sh"),
    (r"^RESEARCH-INTENT PRE-COGNITION", "research-precognition-nudge.sh"),
    (r"^PROMPT CACHE EXPIRED", "cache-expiry-warning.sh"),
    (r"^ACTIVATION QUEUE", "activation-watch.sh"),
    (r"^ENTRYPOINT LADDER", "web-entrypoint-ladder.sh"),
    (r"^MCP: \d+ server", "session-start.sh"),
    (
        r"email recipe \(auto-injected|^\n?0\. NEVER COMPOSE-AND-SEND",
        "enforce-email-formatting.py",
    ),
    (
        r"^AGENT-TEAMS SKILL|^RESEARCH-SUBAGENTS SKILL|^AGENT TEAMS DEFAULT",
        "agent-teams-enforce.sh",
    ),
    (r"^RELAY VERBATIM", "relay-verbatim.sh"),
    (r"^Session index:", "session-index-start.sh"),
    (r"^Plans: ", "setup-plan-symlinks.sh"),
    (r"^Tasks: ", "setup-task-symlinks.sh"),
    (r"^You hold the machine-wide DESK", "desk-brief-inject.sh"),
    (r"^OVERWRITE GUARD|^PLAN GUARD", "backup-before-write.sh"),
    (r"^MEMORY INDEX", "memory-index-drain.sh"),
    (r"^⟳ MONITORING AUTO-RECYCLE|^⟳ ", "waiting-recycle.sh"),
    (r"AGENT TEAMS REQUIRED", "validate-plan-structure.sh"),
    (
        r"^PostToolUse hook modified",
        "cc-builtin: file modified after edit (post-file-edit.sh formatter)",
    ),
    (r"^Frontier:", "frontier-status.sh"),
    # Stop reasons (meta 'Stop hook feedback:' copies)
    (r"^\[", "/goal prompt hook (Claude Code built-in)"),
    (r"^🔧 Loose ends|^📦 SHIP FLOOR|^🔔 WAKE FLOOR|^🧵 ", "session-continue.sh"),
    (r"^Completion-assert", "completion-assert.sh"),
    (
        r"^Anti-deference|^Opaque-identifier|^Category-not-idea",
        "anti-deference-nudge.sh",
    ),
    (r"^⚑ Boundary reached|^⟳ FREE WIN", "boundary-handoff.sh"),
    (r"^Dispatch-assert", "dispatch-assert.sh"),
]
RULES = [(re.compile(p), s) for p, s in RULES]


def classify(prefix):
    persisted = prefix.startswith("PERSISTED|")
    body = prefix.split("|", 2)[2] if persisted else prefix
    body = body.lstrip("\n") if body.startswith("\n0.") is False else body
    for rx, s in RULES:
        if rx.search(body):
            return s, persisted
    return "unattributed", persisted


def script_of_cmd(cmd):
    if not cmd:
        return None
    m = re.search(r"\.claude/hooks/([\w.\-]+)", cmd)
    return m.group(1) if m else "project-hook: " + cmd[:60]


def main():
    x = sqlite3.connect(f"file:{BASE}/data/extract.sqlite?mode=ro", uri=True)
    h = sqlite3.connect(f"file:{BASE}/data/hooks.sqlite?mode=ro", uri=True)
    # ---------- responses per file
    R = collections.defaultdict(list)
    for row in x.execute("""SELECT r.file, r.seq, r.ts, r.input_tokens, r.cc_5m, r.cc_1h, r.cache_read,
            COALESCE(r.output_est, r.output_tokens), p.in_per_mtok, p.out_per_mtok, p.cr_mult,
            r.n_tool_use, r.tool_use_names, r.text_chars, r.model
          FROM resp r JOIN price p ON p.model=r.model WHERE r.xdup=0 ORDER BY r.file, r.seq"""):
        R[row[0]].append(row[1:])
    ctxtype = dict(x.execute("SELECT file, ctx_type FROM ctx"))
    arrs = {}

    def A(f):
        if f in arrs:
            return arrs[f]
        L = R.get(f, [])
        a = {
            k: np.array([r[i] for r in L], dtype=float)
            for i, k in enumerate(
                ["seq", "_ts", "inp", "c5", "c1", "cr", "out", "pin", "pout", "crm"]
            )
            if k != "_ts"
        }
        a["ts"] = [r[1] for r in L]
        a["tot"] = a["inp"] + a["c5"] + a["c1"] + a["cr"] if L else np.array([])
        if L:
            cc = a["c5"] + a["c1"]
            wmix = np.where(
                cc > 0, (a["c5"] * 1.25 + a["c1"] * 2.0) / np.maximum(cc, 1), 1.0
            )
            a["p_read"] = a["pin"] * a["crm"] / 1e6
            a["p_write"] = np.where(cc > 0, a["pin"] * wmix, a["pin"]) / 1e6
            a["q_read"] = np.full(len(L), O55[0] * O55[2] / 1e6)
            a["q_write"] = np.where(cc > 0, O55[0] * wmix, O55[0]) / 1e6
            a["usd"] = (
                a["inp"] * a["pin"]
                + a["c5"] * a["pin"] * 1.25
                + a["c1"] * a["pin"] * 2
                + a["cr"] * a["pin"] * a["crm"]
                + a["out"] * a["pout"]
            ) / 1e6
            a["usd55"] = (
                a["inp"] * O55[0]
                + a["c5"] * O55[0] * 1.25
                + a["c1"] * O55[0] * 2
                + a["cr"] * O55[0] * O55[2]
                + a["out"] * O55[1]
            ) / 1e6
        a["meta"] = L
        arrs[f] = a
        return a

    def persist_cost(f, s, tok):
        a = A(f)
        if not a["meta"]:
            return 0.0, 0.0, 0
        seq = a["seq"]
        idx = np.nonzero(seq > s)[0]
        if len(idx) == 0:
            return 0.0, 0.0, 0
        pos = 0.0
        prev = np.nonzero(seq == s)[0]
        if len(prev):
            pos = a["tot"][prev[0]]
        tot = a["tot"][idx]
        alive = tot >= pos + tok * 0.9
        # stop at first response where the item is gone
        if not alive.all():
            first_dead = np.argmin(alive)
            idx = idx[:first_dead]
        if len(idx) == 0:
            return 0.0, 0.0, 0
        read = a["cr"][idx] >= pos + tok * 0.9
        own = np.where(read, a["p_read"][idx], a["p_write"][idx]) * tok
        o55 = np.where(read, a["q_read"][idx], a["q_write"][idx]) * tok
        return float(own.sum()), float(o55.sum()), len(idx)

    # ---------- injections
    elems = collections.defaultdict(list)
    for f, uid, at, cmd, pfx, ec, he in h.execute(
        "SELECT file, uid, att_type, command, prefix, elem_chars, hook_event FROM helem"
    ):
        elems[(f, uid)].append((at, cmd, pfx, ec, he))
    metas = {(f, u): p for f, u, p in h.execute("SELECT file, uid, prefix FROM hmeta")}
    items = x.execute("""SELECT file, uid, resp_before, chars, subkind, ts FROM item
        WHERE xdup=0 AND visible=1 AND (subkind LIKE 'hook_%' OR subkind='stop_hook_feedback')""").fetchall()
    agg = collections.defaultdict(
        lambda: dict(
            n=0,
            files=set(),
            chars=0,
            sizes=[],
            usd=0.0,
            usd55=0.0,
            resp_alive=0,
            persisted=0,
            events=collections.Counter(),
            ev_usd=collections.Counter(),
            ev_usd55=collections.Counter(),
            ctx=collections.Counter(),
        )
    )
    unattr = collections.Counter()
    for f, uid, s, chars, sk, ts in items:
        parts = []
        if sk == "stop_hook_feedback":
            p = metas.get((f, uid), "")
            body = p.split("\n", 1)[1] if "\n" in p else p
            sc, _ = classify(body)
            parts.append((sc, chars, False, "Stop (meta copy)"))
        else:
            el = elems.get((f, uid), [])
            tot_e = sum(e[3] for e in el) or 1
            for at, cmd, pfx, ec, he in el:
                sc = script_of_cmd(cmd) if at != "hook_additional_context" else None
                pers = False
                if not sc:
                    sc, pers = classify(pfx or "")
                if sc == "unattributed":
                    unattr[(sk, (pfx or "")[:50])] += 1
                parts.append(
                    (sc, chars * ec / tot_e, pers, sk.split(":")[0] + ":" + (he or "?"))
                )
            if not el:
                parts.append(("unmatched-item", chars, False, sk))
        for sc, c, pers, ev in parts:
            tok = c / CPT
            u, u55, nalive = persist_cost(f, s, tok)
            g = agg[sc]
            g["n"] += 1
            g["files"].add(f)
            g["chars"] += c
            g["sizes"].append(c)
            g["usd"] += u
            g["usd55"] += u55
            g["resp_alive"] += nalive
            g["persisted"] += int(pers)
            g["events"][ev] += 1
            g["ev_usd"][ev] += u
            g["ev_usd55"][ev] += u55
            g["ctx"][ctxtype.get(f)] += 1

    # ---------- forced turns
    prompts = collections.defaultdict(list)
    for (
        f,
        ts,
    ) in x.execute("""SELECT file, ts FROM item WHERE xdup=0 AND kind='user_prompt'
                              AND subkind NOT IN ('agent_brief')"""):
        prompts[f].append(ts)
    stops = collections.defaultdict(list)
    for f, ts in h.execute("SELECT file, ts FROM hstop"):
        stops[f].append(ts)
    tooluse = collections.defaultdict(list)  # (file, resp seq) -> [(tool, detail)]
    for f, s, sk, d in x.execute("""SELECT file, resp_before, subkind, detail FROM item
                                    WHERE xdup=0 AND kind='tool_use_input' AND file IN
                                    (SELECT DISTINCT file FROM item WHERE subkind='stop_hook_feedback')"""):
        tooluse[(f, s)].append((sk, d or ""))
    trig = collections.defaultdict(list)
    for (
        f,
        uid,
        s,
        chars,
        ts,
    ) in x.execute("""SELECT file, uid, resp_before, chars, ts FROM item
                                           WHERE xdup=0 AND subkind='stop_hook_feedback'"""):
        p = metas.get((f, uid), "")
        body = p.split("\n", 1)[1] if "\n" in p else p
        trig[(f, s)].append((classify(body)[0], ts, chars, body[:24]))
    POLL = re.compile(
        r"session-continue\.sh|cc-await-ping|\bsleep\b|cc-custody|cc-notify|mailbox|"
        r"goal|wake|ScheduleWakeup|cc-context"
    )
    READ = re.compile(
        r"^\s*(git (status|log|diff|show|rev-parse|branch|ls-tree|merge-base)|ls|cat|head|tail|"
        r"wc|grep|rg|jq|date|pwd|echo|bash .*wrap-ledger|.*wrap-ledger|.*operator-readout|"
        r"claude-accounts|cc-backlog list|cc-decide list|cd )"
    )
    SUBST_TOOLS = {
        "Edit",
        "Write",
        "MultiEdit",
        "NotebookEdit",
        "Agent",
        "Task",
        "Workflow",
        "SendMessage",
    }
    forced = collections.defaultdict(
        lambda: dict(
            n=0,
            files=set(),
            resp=0,
            usd=0.0,
            usd55=0.0,
            out=0.0,
            cls=collections.Counter(),
            usd_by_cls=collections.Counter(),
        )
    )
    samples = []
    for (f, s), trs in trig.items():
        a = A(f)
        if not a["meta"]:
            continue
        t0 = min(t[1] for t in trs)
        after = [i for i, sq in enumerate(a["seq"]) if sq > s]
        if not after:
            continue
        # the block's own stop_hook_summary is written just AFTER the meta message, so the span
        # ends at the first stop_hook_summary that follows the first continuation response
        t1 = a["ts"][after[0]]
        nxt_stop = min([t for t in stops.get(f, []) if t > t1] or ["9999"])
        nxt_prompt = min([t for t in prompts.get(f, []) if t > t0] or ["9999"])
        end = min(nxt_stop, nxt_prompt)
        idx = [i for i in after if a["ts"][i] < end]
        if t1 >= nxt_prompt:
            idx = []  # the continuation never happened before the next human prompt
        if not idx:
            continue
        usd = float(a["usd"][idx].sum())
        usd55 = float(a["usd55"][idx].sum())
        tools = [tu for i in idx for tu in tooluse.get((f, int(a["seq"][i])), [])]
        text = sum(a["meta"][i][12] or 0 for i in idx)
        names = {t for t, _ in tools}
        bash = [d for t, d in tools if t == "Bash"]
        if not tools:
            cls = "nothing" if text < 400 else "reformat_close"
        elif names & SUBST_TOOLS or any(
            re.search(
                r"git commit|/ship|ship-land|handoff-fire|deploy-live|cc-backlog (add|needs|close)|cc-decide open",
                d,
            )
            for d in bash
        ):
            cls = "substantive"
        elif (
            bash
            and all(POLL.search(d) for d in bash)
            and names <= {"Bash", "Monitor", "TaskOutput", "ListAgents", "TaskList"}
        ):
            cls = "poll_rearm"
        elif names <= {
            "Bash",
            "Read",
            "Grep",
            "Glob",
            "ToolSearch",
            "TaskOutput",
            "ListAgents",
            "Monitor",
        } and all(READ.search(d) or POLL.search(d) for d in bash):
            cls = "reformat_close" if len(idx) <= 3 else "readonly_check"
        elif len(idx) <= 2 and text < 300:
            # tools ran but nothing was written and almost nothing said: a state probe
            # ("No drag.", "Waiting.") -- validated on the seeded sample in hooks_forced_validate.py
            cls = "short_probe"
        else:
            cls = "substantive"
        hooks = [t[0] for t in trs]
        for sc in hooks:
            g = forced[sc]
            w = 1.0 / len(hooks)
            g["n"] += w
            g["files"].add(f)
            g["resp"] += len(idx) * w
            g["usd"] += usd * w
            g["usd55"] += usd55 * w
            g["out"] += float(a["out"][idx].sum()) * w
            g["cls"][cls] += w
            g["usd_by_cls"][cls] += usd * w
        if len(samples) < 4000:
            samples.append(
                dict(
                    file=f,
                    s=s,
                    hooks=hooks,
                    reasons=[t[3] for t in trs],
                    n_resp=len(idx),
                    usd=round(usd, 4),
                    cls=cls,
                    tools=[t for t, _ in tools][:12],
                    bash=[d[:80] for d in bash][:6],
                    text_chars=text,
                    ctx_type=ctxtype.get(f),
                )
            )

    # ---------- other hook records (not model-visible)
    nonvis = {}
    for (
        sk,
        n,
        nf,
        raw,
    ) in x.execute("""SELECT subkind, COUNT(*), COUNT(DISTINCT file), SUM(raw_chars) FROM item
             WHERE xdup=0 AND visible=0 AND subkind LIKE 'hook_%' GROUP BY 1"""):
        k = sk.split(":")[0]
        d = nonvis.setdefault(k, dict(n=0, files=0, raw_chars=0))
        d["n"] += n
        d["raw_chars"] += raw or 0
    timeouts = collections.Counter()
    for cmd, n in h.execute(
        """SELECT command, COUNT(*) FROM helem WHERE att_type='hook_cancelled' GROUP BY 1"""
    ):
        timeouts[script_of_cmd(cmd) or "?"] += n

    def fin(g):
        s = sorted(g["sizes"]) or [0]
        return dict(
            n=g["n"],
            contexts=len(g["files"]),
            chars=round(g["chars"]),
            median_chars=round(s[len(s) // 2]),
            p90_chars=round(s[int(len(s) * 0.9)]),
            usd=round(g["usd"], 2),
            usd_at_opus55=round(g["usd55"], 2),
            avg_resps_alive=round(g["resp_alive"] / max(g["n"], 1), 1),
            persisted_previews=g["persisted"],
            events=dict(g["events"]),
            usd_by_event={k: round(v, 2) for k, v in g["ev_usd"].items()},
            usd55_by_event={k: round(v, 2) for k, v in g["ev_usd55"].items()},
            ctx_types=dict(g["ctx"]),
        )

    out = dict(
        chars_per_token=CPT,
        injections={
            k: fin(v) for k, v in sorted(agg.items(), key=lambda kv: -kv[1]["usd"])
        },
        forced={
            k: dict(
                n=round(v["n"], 1),
                contexts=len(v["files"]),
                responses=round(v["resp"]),
                usd=round(v["usd"], 2),
                usd_at_opus55=round(v["usd55"], 2),
                output_tokens=round(v["out"]),
                classes={c: round(n, 1) for c, n in v["cls"].items()},
                usd_by_class={c: round(n, 2) for c, n in v["usd_by_cls"].items()},
            )
            for k, v in sorted(forced.items(), key=lambda kv: -kv[1]["usd"])
        },
        nonvisible=nonvis,
        cancelled_timeouts=dict(timeouts.most_common()),
        unattributed_top=[[list(k), n] for k, n in unattr.most_common(15)],
        n_trigger_groups=len(trig),
    )
    json.dump(out, open(f"{BASE}/measure/hooks_cost.json", "w"), indent=1, default=str)
    json.dump(samples, open(f"{BASE}/data/hooks_forced_samples.json", "w"), indent=0)
    tot = sum(v["usd"] for v in out["injections"].values())
    tot55 = sum(v["usd_at_opus55"] for v in out["injections"].values())
    print(f"INJECTIONS total ${tot:.0f} (own) ${tot55:.0f} (@opus55)")
    for k, v in list(out["injections"].items())[:40]:
        print(
            f"  {k[:48]:48s} n={v['n']:6d} ctx={v['contexts']:5d} chars={v['chars']:>10,} med={v['median_chars']:6d} "
            f"${v['usd']:8.2f} ${v['usd_at_opus55']:8.2f} alive={v['avg_resps_alive']} pers={v['persisted_previews']}"
        )
    ft = sum(v["usd"] for v in out["forced"].values())
    ft55 = sum(v["usd_at_opus55"] for v in out["forced"].values())
    print(
        f"FORCED TURNS total ${ft:.0f} (own) ${ft55:.0f} (@opus55), trigger groups {len(trig)}"
    )
    for k, v in out["forced"].items():
        print(
            f"  {k[:48]:48s} n={v['n']:7.1f} ctx={v['contexts']:4d} resp={v['responses']:6d} ${v['usd']:8.2f} ${v['usd_at_opus55']:8.2f} {v['classes']}"
        )
    print("unattributed:", out["unattributed_top"][:8])
    print("timeouts:", out["cancelled_timeouts"])


if __name__ == "__main__":
    main()
