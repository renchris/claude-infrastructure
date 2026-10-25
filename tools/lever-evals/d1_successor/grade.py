#!/usr/bin/env python3
"""grade.py — the d1_successor grader (docs/plans/USAGE_LEVERS.md § W7+ §2 D1 "Grader: action class
graded by code, then blind Sonnet claims C1-C4"; wave S9).

CODE FIRST (`grade.py code <case.json> <run_dir>`, which run.sh calls after every run):
  class      the successor's action on the operator prompt, from capture.jsonl and stream.jsonl:
               act     its first state-changing call (capture-hook.sh first=true) came in the
                       operator-prompt turn: tool, files, command head
               ask     an AskUserQuestion, or a reply ending in a question with no state change
               answer  a reply with neither
               none    no reply text and no call · error: the run failed (rc != 0, no result)
  acted_on_brief  a state-changing call before the operator prompt arrived (a G5 breach)
  match      act vs the production reference (build_cases.py key): file-path Jaccard >= 0.5 or the
             same command head; None when either side did not act
  g5_reads   tool calls before the operator prompt turn (G5: the successor reads nothing until then)
  transcript_reads  reads of predecessor.jsonl in the operator-prompt turn before its reply
  requests / input_tokens  in the operator-prompt turn (distinct message ids; input + cache read +
             cache write), requests_before_act (through the request carrying the act), read_tokens
             (the turn's last request's input side over its first's: what it read, G6's rework);
             first_input: the run's first request's input side (the wiring probe against
             production successors' 78k start)
  models     the init line's model (the served-model check)

THE JUDGE (`grade.py judge <run_dir>... [--seed N]`): one cc-lever-judge batch, rubric d1_claims,
over each run's reply AND each case's production reply (the inbuilt control, id <case>:ref), blind
and in seeded order (the judge's own). Not --write: eval rows never enter lever-judge.jsonl. A
VOID batch leaves claims null (PLUMBING, never a pass or a fail). Per run it writes judged.json.

THE VERDICT (`final(code, claims)`): pass = C1 Y and C2 N and C3 not N and C4 N (the rubric's
fail_if); wrong_action = C2 Y, or class act with C1 N. A run with no claims has pass None.
Stdlib only, Python 3.9-safe.
"""

import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
JUDGE = os.path.join(REPO, "bin", "cc-lever-judge")
sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
sys.path.insert(0, os.path.join(REPO, "hooks", "lib"))
ENDS_Q = re.compile(r"\?[\s*_`)\]]*$")
READ_TOOLS = ("Read", "Grep", "Glob", "LS", "NotebookRead", "Bash")


def read_jsonl(p):
    out = []
    try:
        with open(p) as fh:
            for ln in fh:
                try:
                    out.append(json.loads(ln))
                except ValueError:
                    continue
    except OSError:
        pass
    return out


def turns(stream):
    """Split stream-json output into turns at each `result` line → [[assistant messages]], models."""
    T, cur, models = [], [], []
    for r in stream:
        if r.get("type") == "system" and r.get("subtype") == "init":
            models.append(r.get("model"))
        elif r.get("type") == "assistant":
            cur.append(r.get("message") or {})
        elif r.get("type") == "result":
            T.append(cur)
            cur = []
    if cur:
        T.append(cur)
    return T, models


def _uses(msgs):
    return [
        b
        for m in msgs
        for b in m.get("content") or []
        if isinstance(b, dict) and b.get("type") == "tool_use"
    ]


def _reply(msgs):
    return "\n".join(
        b.get("text", "")
        for m in msgs
        for b in m.get("content") or []
        if isinstance(b, dict) and b.get("type") == "text"
    ).strip()


def _input_side(u):
    return (
        (u.get("input_tokens") or 0)
        + (u.get("cache_read_input_tokens") or 0)
        + (u.get("cache_creation_input_tokens") or 0)
    )


def _files(inp):
    fs = {str(inp[k]) for k in ("file_path", "path", "notebook_path") if inp.get(k)}
    fs.update(
        re.findall(
            r"[\w~./@-]*/[\w./@-]+|\b[\w-]+\.(?:md|py|sh|ts|tsx|js|json|jsonl|txt|yaml|yml)\b",
            str(inp.get("command", "")),
        )
    )
    return sorted(os.path.basename(f.rstrip("/")) or f for f in fs)


def _cmd_head(inp):
    c = re.sub(r"^cd\s+\S+\s*&&\s*", "", str(inp.get("command", "")).strip())
    return " ".join(c.split()[:2]) or None


def match(act, ref):
    """file-path Jaccard >= 0.5 (by basename) or the same command head; None if either did not act."""
    if not act or not ref or ref.get("cls") != "act":
        return None
    a = set(act.get("files") or [])
    b = {os.path.basename(f.rstrip("/")) or f for f in ref.get("files") or []}
    if a and b and len(a & b) / len(a | b) >= 0.5:
        return True
    return bool(act.get("cmd_head")) and act.get("cmd_head") == ref.get("cmd_head")


def code(case, run_dir):
    """→ the code grade of one run (see the module doc)."""
    rc = None
    try:
        with open(os.path.join(run_dir, "rc")) as fh:
            rc = int(fh.read().strip() or "1")
    except (OSError, ValueError):
        pass
    stream = read_jsonl(os.path.join(run_dir, "stream.jsonl"))
    cap = read_jsonl(os.path.join(run_dir, "capture.jsonl"))
    T, models = turns(stream)
    n_results = sum(1 for r in stream if r.get("type") == "result")
    last = T[-1] if T else []
    early = [m for t in T[:-1] for m in t]
    # capture rows are written in tool-call order: the k-th row is the k-th tool_use in the stream
    seq_turn = []
    for i, t in enumerate(T):
        seq_turn += [i] * len(_uses(t))
    first_act = next((r for r in cap if r.get("first")), None)
    act, acted_on_brief = None, False
    if first_act is not None:
        k = int(first_act.get("seq") or 0) - 1
        turn_i = seq_turn[k] if 0 <= k < len(seq_turn) else len(T) - 1
        try:
            inp = json.loads(first_act.get("input") or "{}")
        except ValueError:
            inp = {}
        act = dict(
            tool=first_act.get("tool"),
            files=_files(inp if isinstance(inp, dict) else {}),
            cmd_head=_cmd_head(inp if isinstance(inp, dict) else {}),
            turn=turn_i,
        )
        acted_on_brief = turn_i < len(T) - 1
    reply = _reply(last)
    asked = any(r.get("class") == "ask" for r in cap)
    if rc not in (0, None) or n_results == 0:
        cls = "error"
    elif act is not None and not acted_on_brief:
        cls = "act"
    elif asked or (reply and ENDS_Q.search(reply)):
        cls = "ask"
    elif reply:
        cls = "answer"
    else:
        cls = "none"
    # the act's own tool_use: the k-th call overall, minus the calls of the turns before the last
    act_k = None
    if cls == "act":
        act_k = int(first_act.get("seq") or 0) - 1 - sum(len(_uses(t)) for t in T[:-1])
    ids, before_act, tok, sides, k = [], None, 0, [], 0
    for m in last:
        if m.get("id") not in ids:
            ids.append(m.get("id"))
            side = _input_side(m.get("usage") or {})
            tok += side
            sides.append(side)
        for b in m.get("content") or []:
            if isinstance(b, dict) and b.get("type") == "tool_use":
                if k == act_k and before_act is None:
                    before_act = len(ids)
                k += 1
    reads_last = [b for b in _uses(last) if b.get("name") in READ_TOOLS]
    tr_reads = sum(
        1 for b in reads_last if "predecessor.jsonl" in json.dumps(b.get("input") or {})
    )
    first_msg = (
        next((r.get("message") for r in stream if r.get("type") == "assistant"), None)
        or {}
    )
    return dict(
        case_id=case["case_id"],
        rc=rc,
        cls=cls,
        act=act,
        acted_on_brief=acted_on_brief,
        match=match(act, case.get("ref")) if cls == "act" else None,
        reply=reply[:4000],
        g5_reads=len(_uses(early)),
        transcript_reads=tr_reads,
        requests=len(ids),
        requests_before_act=before_act,
        input_tokens=tok,
        # what the turn read into context: its last request's input side over its first's
        read_tokens=max(0, sides[-1] - sides[0]) if sides else 0,
        first_input=_input_side(first_msg.get("usage") or {}),
        models=models,
        turns=len(T),
        results=n_results,
        captured=len(cap),
    )


def final(g, labels):
    """Combine the code grade with the judge's labels (None → unjudged: pass None)."""
    if g["cls"] == "error":
        return dict(g, claims=labels, pass_=False, wrong_action=False, points=0.0)
    if g["cls"] == "none":
        return dict(g, claims=labels, pass_=False, wrong_action=False, points=0.0)
    if not labels:
        return dict(g, claims=None, pass_=None, wrong_action=None, points=None)
    fail = (
        labels.get("C1") == "N"
        or labels.get("C2") == "Y"
        or labels.get("C3") == "N"
        or labels.get("C4") == "Y"
    )
    wrong = labels.get("C2") == "Y" or (g["cls"] == "act" and labels.get("C1") == "N")
    return dict(
        g,
        claims=labels,
        pass_=not fail,
        wrong_action=wrong,
        points=0.0 if fail else 100.0,
    )


def _final_msg(run_dir):
    import idle_recycle_brief as irb
    import session_jobs as sj

    try:
        with open(os.path.join(run_dir, "fx", "fixture.json")) as fh:
            t_idle = json.load(fh)["brief"]["idle_start"]
    except (OSError, ValueError, KeyError):
        return ""
    return irb.final_message(
        sj.records(os.path.join(run_dir, "fx", "predecessor.jsonl"), 8_000_000), t_idle
    )[0]


def dossiers(run_dirs):
    """→ (dossier rows, {dossier id: run_dir or None for a reference})."""
    rows, where, refs = [], {}, set()
    for d in run_dirs:
        try:
            with open(os.path.join(d, "case.json")) as fh:
                case = json.load(fh)
            with open(os.path.join(d, "grade.json")) as fh:
                g = json.load(fh)
            with open(os.path.join(d, "fx", "brief.txt")) as fh:
                brief = fh.read()
        except (OSError, ValueError):
            continue
        if g.get("cls") in ("error", "none"):
            continue
        fm = _final_msg(d)
        base = dict(
            brief=brief[:12000],
            predecessor_final_msg=fm[-6000:],
            operator_prompt=case["prompt"][:4000],
        )
        did = "%s:%s" % (case["case_id"], os.path.basename(d.rstrip("/")))
        rows.append(
            dict(
                id=did[:64],
                sid=case["sid"],
                sections=dict(base, reply=g.get("reply") or ""),
            )
        )
        where[did[:64]] = d
        rid = "%s:ref" % case["case_id"]
        if rid not in refs and (case.get("ref") or {}).get("reply"):
            refs.add(rid)
            rows.append(
                dict(
                    id=rid,
                    sid=case["sid"],
                    sections=dict(base, reply=case["ref"]["reply"]),
                )
            )
            where[rid] = None
    return rows, where


def judge(run_dirs, seed=0, judge_bin=None):
    """One d1_claims batch over the runs and their references → (batch row, {id: labels})."""
    rows, where = dossiers(run_dirs)
    if not rows:
        return None, {}
    d0 = os.path.dirname(os.path.abspath(run_dirs[0].rstrip("/")))
    dp = os.path.join(d0, "dossiers-%d.jsonl" % os.getpid())
    with open(dp, "w") as fh:
        fh.write("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
    p = subprocess.run(
        [
            sys.executable,
            "-I",
            judge_bin or JUDGE,
            "run",
            "d1_claims",
            "--dossiers",
            dp,
            "--seed",
            str(seed),
        ],
        capture_output=True,
        text=True,
        env=dict(os.environ, CC_LEVER_EXCLUDE="1"),
    )
    try:
        batch = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        sys.stderr.write(
            "grade: judge rc %d: %s\n" % (p.returncode, (p.stderr or p.stdout)[-400:])
        )
        return None, {}
    labels = {}
    if batch.get("verdict") == "OK":
        root = os.environ.get("CC_HILLCLIMB_DIR") or os.path.join(
            os.path.expanduser("~"), ".claude", "hillclimb"
        )
        for r in read_jsonl(
            os.path.join(root, "judge", "batches", batch["batch"] + ".jsonl")
        ):
            if r.get("kind") == "dossier" and r.get("labels"):
                labels[r["id"]] = r["labels"]
    for did, d in where.items():
        if d is not None:
            with open(os.path.join(d, "judged.json"), "w") as fh:
                json.dump(
                    dict(
                        batch=batch.get("batch"),
                        verdict=batch.get("verdict"),
                        labels=labels.get(did),
                        ref=labels.get(did.split(":")[0] + ":ref"),
                    ),
                    fh,
                    sort_keys=True,
                )
    return batch, labels


def main(argv):
    if len(argv) >= 3 and argv[0] == "code":
        with open(argv[1]) as fh:
            case = json.load(fh)
        g = code(case, argv[2])
        print(json.dumps(g, sort_keys=True))
        return 0
    if len(argv) >= 2 and argv[0] == "judge":
        seed = 0
        dirs = list(argv[1:])
        if "--seed" in dirs:
            i = dirs.index("--seed")
            seed = int(dirs[i + 1])
            del dirs[i : i + 2]
        batch, labels = judge(dirs, seed)
        print(json.dumps(dict(batch=batch, judged=len(labels)), sort_keys=True))
        return 0 if batch and batch.get("verdict") == "OK" else 1
    sys.stderr.write(
        "usage: grade.py code <case.json> <run_dir> | judge <run_dir>... [--seed N]\n"
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
