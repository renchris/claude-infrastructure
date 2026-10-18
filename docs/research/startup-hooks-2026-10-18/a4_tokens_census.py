#!/usr/bin/env python3
"""A4-tokens census: what model-context bytes each SessionStart hook injects.

READ-ONLY. Reads the transcript list (default /tmp/startup-hooks-census-files.txt), groups the
SessionStart attachment records of each session-start EVENT (one toolUseID per event; the merged
hook_additional_context record that follows carries toolUseID "SessionStart" and is attached to the
event just before it), and attributes every model-billed byte:

  * hook_additional_context.content[]  -> what the model is billed for (one element per hook)
  * hook_success.stdout                -> per-hook JSON; additionalContext / systemMessage split
  * dispatcher additionalContext       -> split per child by line signature (see SIG below)

Run:  python3 -I a4_tokens_census.py [filelist] > out.json   (summary tables go to stderr)
"""

import json, re, sys, collections, statistics as st

FILELIST = sys.argv[1] if len(sys.argv) > 1 else "/tmp/startup-hooks-census-files.txt"

# dispatcher child signatures (first line of each child's additionalContext), from reading the code:
#   session-start.sh:464-471   "WARNING: CLAUDE_CODE_EFFORT_LEVEL" + "MCP: ..."
#   setup-plan-symlinks.sh:94  "Plans: "
#   setup-task-symlinks.sh:196 "Tasks: "
#   frontier-status.sh:36,38   "Frontier: "
#   session-index-start.sh:37  "Session index" (bin/session-search.py --context-inject)
#   recycle-failed-inject.sh:49 "RECYCLE FAILED"
SIG = [
    ("session-start.sh", re.compile(r"^(WARNING: CLAUDE_CODE_EFFORT_LEVEL.*)?MCP: ")),
    ("session-start.sh", re.compile(r"^WARNING: CLAUDE_CODE_EFFORT_LEVEL")),
    ("setup-plan-symlinks.sh", re.compile(r"^Plans: ")),
    ("setup-task-symlinks.sh", re.compile(r"^Tasks: ")),
    ("frontier-status.sh", re.compile(r"^Frontier: ")),
    ("session-index-start.sh", re.compile(r"^Session index")),
    ("recycle-failed-inject.sh", re.compile(r"^RECYCLE FAILED")),
]
MULTILINE_OK = {"recycle-failed-inject.sh", "session-index-start.sh"}


def short(cmd):
    c = cmd or ""
    c = re.sub(r".*/hooks/", "", c)
    return c[:60]


def parse_stdout(s):
    """-> (ctx, sysmsg) the harness would read from a hook's stdout."""
    s = (s or "").strip()
    if not s:
        return "", ""
    try:
        j = json.loads(s)
        if isinstance(j, dict):
            return (
                (j.get("hookSpecificOutput") or {}).get("additionalContext") or ""
            ), (j.get("systemMessage") or "")
    except Exception:
        pass
    return s, ""  # plain stdout = plain context


def split_dispatch(ctx):
    parts = []  # list of [child, text]
    for line in ctx.split("\n"):
        who = None
        for name, rx in SIG:
            if rx.search(line):
                who = name
                break
        if who is None:
            if parts and parts[-1][0] in MULTILINE_OK:
                parts[-1][1] += "\n" + line
                continue
            who = "UNATTRIBUTED"
        parts.append([who, line])
    return parts


def dod_class(c):
    if c.startswith("Durable frozen DoD: no capture"):
        return "dod:negative-notice"
    if "<persisted-output>" in c:
        return "dod:persisted-preview"
    if c.startswith("Durable frozen DoD for this session"):
        return "dod:lineage-contract"
    if c.startswith("Durable frozen DoD for this worktree"):
        return "dod:worktree-contract"
    return "dod:other"


def mail_class(c):
    if c.startswith("🔔 No inbox wake path armed"):
        return "mail:wake-nag(no mail)"
    if c.startswith("🚨 A parked watcher"):
        return "mail:parked-watcher(no mail)"
    if "📬 peer mail" in c[:40]:
        return "mail:peer-mail"
    return "mail:other"


def main():
    files = [l.strip() for l in open(FILELIST) if l.strip()]
    events = []
    for f in files:
        cur = None
        bytu = {}
        try:
            fh = open(f, encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in fh:
            if '"attachment"' not in line or "SessionStart" not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            a = r.get("attachment") or {}
            hn = a.get("hookName") or ""
            if not hn.startswith("SessionStart"):
                continue
            t = a.get("type")
            tu = a.get("toolUseID")
            if t == "hook_additional_context":
                if cur is None:
                    cur = {
                        "file": f,
                        "ts": r.get("timestamp"),
                        "source": "?",
                        "hooks": [],
                        "sysmsgs": [],
                        "ctx": None,
                    }
                    events.append(cur)
                c = a.get("content")
                if isinstance(c, str):
                    c = [c]
                cur["ctx"] = (cur["ctx"] or []) + list(c or [])
                cur = None  # the merged context closes the event
                continue
            if t == "async_hook_response":
                continue
            if tu and tu != "SessionStart":
                if tu not in bytu:
                    ev = {
                        "file": f,
                        "ts": r.get("timestamp"),
                        "source": hn.split(":", 1)[1] if ":" in hn else "?",
                        "hooks": [],
                        "sysmsgs": [],
                        "ctx": None,
                    }
                    bytu[tu] = ev
                    events.append(ev)
                cur = bytu[tu]
            if cur is None:
                continue
            if t in (
                "hook_success",
                "hook_cancelled",
                "hook_error",
                "hook_non_blocking_error",
            ):
                ctx, sm = (
                    parse_stdout(a.get("stdout")) if t == "hook_success" else ("", "")
                )
                cur["hooks"].append(
                    {
                        "cmd": short(a.get("command")),
                        "type": t,
                        "ms": a.get("durationMs"),
                        "timedOut": a.get("timedOut"),
                        "ctx": ctx,
                        "sys": sm,
                    }
                )
            elif t == "hook_system_message":
                cur["sysmsgs"].append(len(a.get("content") or ""))

    # ---- attribution
    out_events = []
    comp_bytes = collections.defaultdict(
        list
    )  # component -> [bytes per event where present]
    comp_by_src = collections.defaultdict(lambda: collections.defaultdict(list))
    variant = collections.defaultdict(collections.Counter)
    ev_total = []
    ev_total_by_src = collections.defaultdict(list)
    unmatched = 0
    disp_missing = collections.Counter()
    disp_seen = 0
    persisted = 0
    for ev in events:
        src = ev["source"]
        elems = ev["ctx"] or []
        tot = sum(len(e) for e in elems)
        ev_total.append(tot)
        ev_total_by_src[src].append(tot)
        hooks = {h["cmd"]: h for h in ev["hooks"]}
        comps = []
        for e in elems:
            if "<persisted-output>" in e:
                persisted += 1
            owner = None
            for h in ev["hooks"]:
                if h["ctx"] and (
                    h["ctx"] == e
                    or e.startswith(h["ctx"][:200])
                    or h["ctx"].startswith(e[:200])
                ):
                    owner = h["cmd"]
                    break
            if owner is None:
                # attribute by signature when the hook_success record is missing
                if e.startswith("Durable frozen DoD"):
                    owner = "dod-persist.sh"
                elif (
                    "peer mail" in e[:60]
                    or e.startswith("🔔")
                    or e.startswith("🚨 A parked")
                ):
                    owner = "mailbox-drain.sh session-start"
                elif e.startswith("You hold the machine-wide DESK"):
                    owner = "desk-brief-inject.sh"
                elif any(rx.search(e) for _, rx in SIG):
                    owner = "session-start-dispatch.sh"
                else:
                    owner = "UNMATCHED"
                    unmatched += 1
            if owner == "session-start-dispatch.sh":
                for child, text in split_dispatch(e):
                    comps.append(("dispatch/" + child, text))
            elif owner.startswith("dod-persist"):
                comps.append((owner, e))
                variant["dod"][dod_class(e)] += 1
            elif owner.startswith("mailbox-drain"):
                comps.append((owner, e))
                variant["mail"][mail_class(e)] += 1
            else:
                comps.append((owner, e))
        # dispatcher: which always-on children are missing from its merged context?
        if (
            "session-start-dispatch.sh" in hooks
            and hooks["session-start-dispatch.sh"]["type"] == "hook_success"
        ):
            disp_seen += 1
            present = {c for c, _ in comps}
            for ch in (
                "session-start.sh",
                "setup-plan-symlinks.sh",
                "setup-task-symlinks.sh",
                "frontier-status.sh",
            ):
                if "dispatch/" + ch not in present:
                    disp_missing[ch] += 1
        per = collections.defaultdict(int)
        for c, text in comps:
            per[c] += len(text)
        for c, b in per.items():
            comp_bytes[c].append(b)
            comp_by_src[c][src].append(b)
        for c, text in comps:
            if c.startswith("dispatch/"):
                norm = re.sub(r"\d+", "N", text)[:90]
                variant[c][norm] += 1
        out_events.append(
            {
                "file": ev["file"],
                "ts": ev["ts"],
                "source": src,
                "total": tot,
                "elements": [len(e) for e in elems],
                "components": dict(per),
                "hooks": [
                    {k: h[k] for k in ("cmd", "type", "ms", "timedOut")}
                    | {"ctx": len(h["ctx"]), "sys": len(h["sys"])}
                    for h in ev["hooks"]
                ],
                "sysmsg_chars": ev["sysmsgs"],
            }
        )

    n = len(events)
    srcs = collections.Counter(e["source"] for e in events)

    def q(v, p):
        if not v:
            return 0
        v = sorted(v)
        return v[min(len(v) - 1, int(round(p * (len(v) - 1))))]

    E = sys.stderr
    print(
        f"events={n} by source={dict(srcs)} with_ctx={sum(1 for e in events if e['ctx'])}",
        file=E,
    )
    print(
        f"model ctx chars/event: mean={st.mean(ev_total):.0f} p50={q(ev_total, 0.5)} p90={q(ev_total, 0.9)} max={max(ev_total)} sum={sum(ev_total)}",
        file=E,
    )
    for s, v in sorted(ev_total_by_src.items()):
        print(
            f"  source={s:8s} n={len(v):4d} mean={st.mean(v):.0f} p50={q(v, 0.5)} p90={q(v, 0.9)}",
            file=E,
        )
    print(
        f"persisted-output elements={persisted} unmatched elements={unmatched}", file=E
    )
    print(
        "\ncomponent | events present | share | mean chars when present | p50 | p90 | max | chars per event (all events)",
        file=E,
    )
    rows = []
    for c, v in comp_bytes.items():
        rows.append((sum(v) / n, c, len(v), st.mean(v), q(v, 0.5), q(v, 0.9), max(v)))
    for per_ev, c, k, m, p50, p90, mx in sorted(rows, reverse=True):
        print(
            f"{c:48s} {k:4d} {k / n:5.1%} {m:7.0f} {p50:6d} {p90:6d} {mx:6d} {per_ev:7.1f}",
            file=E,
        )
    print("\nper source (mean chars per event of that source):", file=E)
    for c in sorted(comp_by_src):
        cells = []
        for s in sorted(srcs):
            v = comp_by_src[c].get(s, [])
            cells.append(f"{s}:{sum(v) / srcs[s]:.0f}({len(v)})")
        print(f"  {c:48s} " + "  ".join(cells), file=E)
    print(
        f"\ndispatcher successes={disp_seen}; always-on child ABSENT from merged context: {dict(disp_missing)}",
        file=E,
    )
    for k, cnt in variant.items():
        print(f"\nvariants {k}:", file=E)
        for v, c in cnt.most_common(8):
            print(f"   {c:4d}  {v}", file=E)
    json.dump({"events": out_events}, sys.stdout)


if __name__ == "__main__":
    main()
