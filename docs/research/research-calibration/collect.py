"""collect.py - gather every reviewer's raw output for the A3 replay into one findings file per plan.

Anthropic slots: read from the review workflow's journal (result rows, keyed by agentId -> label), with the
per-agent transcript used for (1) the integrity check: any tool_use whose input names an absolute path
outside the slot's bundle voids the slot, and (2) token usage (input + cache creation + cache read + output,
deduplicated by message id). OpenAI slots: courier output (.last JSON, .meta.json with tokens and void).

usage: python3 collect.py <cache_dir> <review_workflow_dir>
writes <cache>/replay/findings/<plan>.json and <cache>/replay/slots.json
"""

import json
import os
import re
import sys

from prep_replay import parse_json


def opus_slots(C, wfdir):
    labels, results = {}, {}
    for line in open(os.path.join(wfdir, "journal.jsonl")):
        r = json.loads(line)
        if r.get("type") == "started" and str(r.get("label", "")).startswith("review:"):
            labels[r["agentId"]] = r["label"][len("review:") :]
        elif r.get("type") == "result":
            results[r["agentId"]] = r.get("result")
    out = {}
    for aid, sid in labels.items():
        pid, slot = sid.split("__")
        fam, strat = slot.split("_")
        bundle = os.path.join(C, "bundles", pid, strat)
        tr = os.path.join(wfdir, "agent-%s.jsonl" % aid)
        leaks, seen, tok, model = set(), set(), 0, None
        if os.path.exists(tr):
            for line in open(tr):
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                msg = rec.get("message") or {}
                if msg.get("role") == "assistant":
                    model = msg.get("model") or model
                    mid = msg.get("id")
                    u = msg.get("usage") or {}
                    if mid and mid not in seen and u:
                        seen.add(mid)
                        tok += sum(
                            u.get(k, 0) or 0
                            for k in (
                                "input_tokens",
                                "cache_creation_input_tokens",
                                "cache_read_input_tokens",
                                "output_tokens",
                            )
                        )
                    for c in msg.get("content") or []:
                        if (
                            isinstance(c, dict)
                            and c.get("type") == "tool_use"
                            and c.get("name") != "StructuredOutput"
                        ):
                            inp = c.get("input") or {}
                            s = json.dumps(inp)
                            # an unscoped search runs in the session cwd (this repo, which holds LATER
                            # versions of several plans): that is a leak even with no absolute path in it
                            if c.get("name") in ("Grep", "Glob") and not inp.get(
                                "path"
                            ):
                                leaks.add("unscoped-%s" % c.get("name"))
                            for p in re.findall(r"/Users/[\w.-]+/[\w./-]*", s):
                                # the harness spills a long tool result to <session>/tool-results/; reading
                                # back one's own output is not outside evidence
                                if "/tool-results/" not in p and not os.path.realpath(
                                    p
                                ).startswith(os.path.realpath(bundle)):
                                    leaks.add(p)
        res = results.get(aid)
        if isinstance(res, str):
            try:
                res = parse_json(res)
            except Exception:  # noqa: BLE001
                res = None
        void = None
        if res is None:
            void = "no-result"
        elif leaks:
            void = "integrity: " + ", ".join(sorted(leaks)[:3])
        out[sid] = dict(
            slot=sid,
            plan=pid,
            vendor="anthropic",
            family=fam,
            strategy=strat,
            model=model,
            tokens=tok,
            void=void,
            leaks=sorted(leaks)[:10],
            findings=(res or {}).get("findings", []),
            lenses=(res or {}).get("lenses"),
        )
    return out


def codex_slots(C):
    d = os.path.join(C, "replay", "codex")
    out = {}
    for fn in os.listdir(d):
        if not fn.endswith(".meta.json"):
            continue
        sid = fn[: -len(".meta.json")]
        meta = json.load(open(os.path.join(d, fn)))
        pid, slot = sid.split("__")
        fam, strat = slot.split("_")
        res, void = None, meta.get("void")
        try:
            res = parse_json(open(os.path.join(d, sid + ".last")).read())
        except Exception as e:  # noqa: BLE001
            void = void or "unparseable: %s" % e
        out[sid] = dict(
            slot=sid,
            plan=pid,
            vendor="openai",
            family=fam,
            strategy=strat,
            model=meta.get("model"),
            tokens=meta.get("tokens"),
            seconds=meta.get("seconds"),
            void=void,
            findings=(res or {}).get("findings", []),
            lenses=(res or {}).get("lenses"),
        )
    return out


if __name__ == "__main__":
    C, wfdir = sys.argv[1], sys.argv[2]
    slots = {**opus_slots(C, wfdir), **codex_slots(C)}
    os.makedirs(os.path.join(C, "replay", "findings"), exist_ok=True)
    by_plan = {}
    for sid, s in sorted(slots.items()):
        by_plan.setdefault(s["plan"], []).append(s)
    for pid, ss in by_plan.items():
        flat = []
        for s in ss:
            if s["void"]:
                continue
            for k, f in enumerate(s["findings"]):
                flat.append(
                    dict(
                        f,
                        fid="%s#%d" % (s["slot"], k + 1),
                        reviewer=s["slot"].split("__")[1],
                    )
                )
        json.dump(
            flat,
            open(os.path.join(C, "replay", "findings", pid + ".json"), "w"),
            indent=1,
        )
    json.dump(
        [
            {k: v for k, v in s.items() if k not in ("findings", "lenses")}
            | {"n": len(s["findings"])}
            for s in slots.values()
        ],
        open(os.path.join(C, "replay", "slots.json"), "w"),
        indent=1,
    )
    for pid, ss in sorted(by_plan.items()):
        print(
            "%-32s %s"
            % (
                pid,
                " ".join(
                    "%s:%s%s"
                    % (
                        s["slot"].split("__")[1],
                        len(s["findings"]),
                        "(VOID)" if s["void"] else "",
                    )
                    for s in ss
                ),
            )
        )
