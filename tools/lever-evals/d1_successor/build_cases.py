#!/usr/bin/env python3
"""build_cases.py — the d1_successor cases and fixtures (docs/plans/USAGE_LEVERS.md § W7+ §2 D1
"Offline d1-successor (model runs)"; wave S9).

A CASE is one production operator return after an idle gap of at least 10 min at 150k tokens or
more: the operator prompt that came back, everything the predecessor had at the idle point, and
the key (what production did next) kept OUTSIDE the fixture.

  census   tools/lever-evals/d1_recycle/scan.py (the W4 scanner, unchanged) over the four accounts'
           main transcripts; an idle point is a request opened by a prompt whose previous request in
           the same file is >= MIN_GAP_S earlier at >= MIN_CTX tokens of context.
  return   the first OPERATOR prompt after the idle point (the opener classifier of the 2026-10-24
           idle-recycle-risk study, ported below: notices, peer mail, injected rails and meta records
           are machine), before the next idle point of that session. No time cap: the study's own
           returns include replies 40 h and more after the idle point (pid 272), and a successor
           would be the one to receive them.
  labels   the 193 returns that study labelled are imported first: the 60-sample (first labeller's
           S/I letters, the blind second labeller's H and A, kappa 1.00 / 0.88) and the 133 holdout
           (H with A listed; the rest reviewed as not H). The 10 A-class replays carry their
           hand-written reference action. New census returns get the study's programmatic v1 tag
           (tag_src=v1) until a labeller pass replaces it.
  select   every H and A return (imported labels, then census v1-H), then a seeded random S/I
           sample up to TARGET (about 200; plan §2), the labelled imports drawn before census ones.
           The 10 A-class replays are H/A, so they are always in.
  key      ref: production's first call that capture-hook.sh classes `act` or `ask` in the turn the
           return opened (tool, files, command head), else `answer`/`none`; the production reply
           (the judge's inbuilt control); followup_is_correction (the next operator prompt within 2 h
           matches the T5 re-ask pre-filter).

fixture(case, dir, params) materialises one run's inputs: predecessor.jsonl (the transcript cut at
the idle point — the future never enters it), brief.txt (scripts/lib/idle_recycle_brief.py on that
cut), messages.jsonl (stream-json user turns: the brief, then the machine inputs that arrived during
the gap, then the operator prompt verbatim), CLAUDE.md (the global instructions the successor would
load), and repo/ (`git archive` of the session's repo at the last commit before the idle point).

CLI (run.sh calls it; the census and selection run through `cc-lever-eval build d1_successor`):
  build_cases.py fixture CASE_JSON OUT_DIR [--params JSON] [--no-repo]
Stdlib only, Python 3.9-safe.
"""

import collections
import glob
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.realpath(__file__))
EVALS = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(EVALS))
sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
import idle_recycle_brief as irb  # noqa: E402

SCAN = os.path.join(EVALS, "d1_recycle", "scan.py")
HOOK = os.path.join(HERE, "capture-hook.sh")
RUBRICS = os.path.join(REPO, "config", "lever-rubrics.json")
IMPORTS = os.path.join(os.path.expanduser("~"), ".claude", "hillclimb", "_imports")
STUDY = os.path.join(IMPORTS, "idle-recycle-risk-b")
CONV = os.path.join(IMPORTS, "conv-tests", "43da49891e75")
EVAL_ROOT = "/tmp/lev-eval"

MIN_GAP_S, MIN_CTX = 600, 150_000
RECYCLE_AT_S = 900  # the approved lever recycles at idle minute 15
TARGET = 200
A_REPLAYS = (40, 69, 120, 136, 167, 168, 187, 208, 263, 272)
PROMPT_MAX, MACHINE_MAX, MACHINE_N = 8000, 1200, 5

# ── the 2026-10-24 study's opener classifier (idle-recycle-risk-b/extract.py + lib.py) ───────────
MACHINE_TYPED = re.compile(
    r"^\s*(ultracode\b[\s—-]*)?(\[(locate|restore|crash recovery|limit-recover)\]|Reply with (only|exactly)|"
    r"reply with the single word|Run exactly this one shell command|Do not use any tools\. Answer with exactly|"
    r"Use the Bash tool to run exactly|You are (a |an |the |one of |continuing |fixing )|TASK —|"
    r"# (Verifier|Reviewer|Rater) brief|Below is step \d of a setup prompt|"
    r"The operator (approved|decided|ruled|chose)|HANDOFF-ENGAGE)",
    re.I,
)
OPERATOR = ("operator", "operator-noorigin")
PATHISH = re.compile(
    r"(~?/[\w.@-]+/[\w./@-]+|\b[\w-]+\.(md|py|sh|ts|tsx|js|json|html|pdf|mp4|mov|png|jpg|csv|txt)\b|"
    r"https?://|\b[0-9a-f]{12}\b|\b[0-9a-f]{7,40}\b)",
    re.I,
)
SESSION_CANNED = re.compile(
    r"^\(?\s*(checking in|chceking in|continue|done, continue|re-connected[^)]*)\s*\)?\.?$|"
    r"good to close|is this all before we close|short and conci?c?se (scqa|pyramid)|"
    r"/explain-decisions|/are-we-done|explain-decisions|what is our progress|how did it go|"
    r"assess our progress",
    re.I,
)
OPERATOR_STEP = re.compile(r"^\s*<(bash-input|command-name|command-message)>", re.I)
QUOTED = re.compile(r'^\s*(re:\s*)?["“❯]')
REPLY_HEAD = re.compile(
    r"^\s*(yes|yeah|yep|yup|no|nope|ok|okay|sure|done|cancel|proceed|approve|approved|go|"
    r"go ahead|do it|open|both|neither|option|send|ship|land|fire|keep|pause|continue)\b",
    re.I,
)
ENDS_Q = re.compile(r"\?[\s*_`)\]]*$")


def opener_kind(r, t):
    if r.get("isMeta"):
        return "meta"
    o = r.get("origin") or {}
    ok = o.get("kind") if isinstance(o, dict) else None
    s = t.lstrip()
    if ok == "task-notification" or s.startswith("<task-notification>"):
        return "notice"
    if ok == "auto-continuation":
        return "autocont"
    if r.get("promptSource") == "sdk":
        return "sdk"
    if s.startswith("Another Claude session sent a message") or s.startswith(
        "<teammate-message"
    ):
        return "peer"
    if s.startswith("[Request interrupted"):
        return "interrupt"
    if s.startswith(
        (
            "<bash-stdout",
            "<bash-stderr",
            "<local-command-stdout",
            "<local-command-stderr",
            "<local-command-caveat",
            "Caveat:",
        )
    ):
        return "localout"
    if MACHINE_TYPED.match(s):
        return "injected"
    if ok == "human":
        return "operator"
    if s.startswith(("<bash-input>", "<command-name>", "<command-message>")):
        return "operator-noorigin"
    return "unknown-noorigin"


def _words(t):
    return len(re.findall(r"[\w'’]+", t))


def v1_tag(t):
    """The study's refined programmatic tag: H (context-dependent), I (operator step), S, or SI."""
    s = t.strip()
    if not (
        OPERATOR_STEP.match(s)
        or QUOTED.match(s)
        or SESSION_CANNED.search(s)
        or PATHISH.search(s)
    ):
        n = _words(s)
        if REPLY_HEAD.match(s) and n <= 15:
            return "H"
        if (
            n <= 25
            and re.search(
                r"\b(that|it|this|these|those|them|the above|above|that date|option\s*\d)\b",
                s,
                re.I,
            )
            and not re.search(r"\b[A-Z][a-z]+\s+[A-Z][a-z]+", s)
        ):
            return "H"
    if OPERATOR_STEP.match(s) and not re.search(r"explain-decisions|are-we-done", s):
        return "I"
    if SESSION_CANNED.search(s) or QUOTED.match(s):
        return "S"
    return "SI"


# ── transcripts ──────────────────────────────────────────────────────────────────────────────────
def ep(s):
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _text(c):
    if isinstance(c, str):
        return c
    out = []
    for b in c or []:
        if isinstance(b, dict) and b.get("type") == "text":
            out.append(b.get("text", ""))
        elif isinstance(b, dict) and b.get("type") == "image":
            out.append("[image]")
    return "\n".join(out)


def load_session(path):
    """→ dict(users=[(ts, kind, text)], asst=[(ts, rid, text, [(name, input)])], cwd) main thread only."""
    users, asst, cwd = [], [], None
    with open(path, "rb") as fh:
        for line in fh:
            head = line[:3000]
            if b'"type":"user"' not in head and b'"type":"assistant"' not in head:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("isSidechain"):
                continue
            ts = ep(r.get("timestamp")) or 0.0
            cwd = r.get("cwd") or cwd
            c = (r.get("message") or {}).get("content")
            if r.get("type") == "user":
                if isinstance(c, list) and any(
                    isinstance(b, dict) and b.get("type") == "tool_result" for b in c
                ):
                    continue
                t = _text(c)
                users.append((ts, opener_kind(r, t), t))
            elif r.get("type") == "assistant":
                uses = [
                    (b.get("name"), b.get("input") or {})
                    for b in c or []
                    if isinstance(b, dict) and b.get("type") == "tool_use"
                ]
                asst.append((ts, r.get("requestId"), _text(c), uses))
    users.sort(key=lambda x: x[0])
    asst.sort(key=lambda x: x[0])
    return dict(users=users, asst=asst, cwd=cwd)


def classify_call(name, inp):
    """The capture hook's own rule on one production call (no fixture: a read is `outside`)."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("D1S_")}
    try:
        p = subprocess.run(
            ["/bin/bash", HOOK, "--classify"],
            input=json.dumps(dict(tool_name=name, tool_input=inp)),
            capture_output=True,
            text=True,
            timeout=20,
            env=env,
        )
        return p.stdout.strip() or "act"
    except (OSError, subprocess.SubprocessError):
        return "act"


def call_files(inp):
    fs = {str(inp[k]) for k in ("file_path", "path", "notebook_path") if inp.get(k)}
    for tok in re.findall(
        r"[\w~./@-]*/[\w./@-]+|\b[\w-]+\.(?:md|py|sh|ts|tsx|js|json|jsonl|txt|yaml|yml)\b",
        str(inp.get("command", "")),
    ):
        fs.add(tok)
    return sorted(fs)


def cmd_head(inp):
    c = str(inp.get("command", "")).strip()
    c = re.sub(r"^cd\s+\S+\s*&&\s*", "", c)
    return " ".join(c.split()[:2])


def reference(S, t_op):
    """What production did in the turn the return opened."""
    nxt = [u[0] for u in S["users"] if u[0] > t_op + 1 and u[1] != "meta"]
    t_end = nxt[0] if nxt else float("inf")
    turn = [a for a in S["asst"] if t_op < a[0] < t_end]
    reply = "\n".join(a[2] for a in turn if a[2].strip())
    ref = dict(
        cls="none" if not turn else "answer",
        tool=None,
        files=[],
        cmd_head=None,
        reply=reply[:1500],
        n_req=len({a[1] for a in turn}),
    )
    for a in turn:
        for name, inp in a[3]:
            c = classify_call(name, inp)
            if c in ("act", "ask"):
                ref.update(
                    cls=c,
                    tool=name,
                    files=call_files(inp),
                    cmd_head=cmd_head(inp) or None,
                )
                return ref
    if turn and ENDS_Q.search(reply.strip()):
        ref["cls"] = "ask"
    return ref


def extract(path, t_idle, t_limit=None):
    """→ the case body for the first operator return after t_idle, or None."""
    try:
        S = load_session(path)
    except OSError:
        return None
    t_limit = t_limit if t_limit is not None else float("inf")
    machine, op = [], None
    for ts, kind, text in S["users"]:
        if ts <= t_idle or ts > t_limit:
            continue
        if kind in OPERATOR:
            op = (ts, kind, text)
            break
        if kind != "meta" and text.strip():
            machine.append(text[:MACHINE_MAX])
    if op is None or op[0] < t_idle + MIN_GAP_S:
        return None
    ctx = [a for a in S["asst"] if a[0] <= t_idle + 1]
    later_ops = [
        u
        for u in S["users"]
        if u[0] > op[0] + 1 and u[1] in OPERATOR and u[0] <= op[0] + 7200
    ]
    pre = load_rubric_prefilter()
    follow = later_ops[0][2] if later_ops else ""
    return dict(
        cwd=S["cwd"],
        t_return=op[0],
        gap_s=round(op[0] - t_idle, 1),
        prompt=op[2][:PROMPT_MAX],
        prompt_sha=hashlib.sha256(op[2].encode("utf-8")).hexdigest(),
        prompt_head=op[2][:200],
        machine_inputs=machine[-MACHINE_N:],
        n_machine=len(machine),
        ref=reference(S, op[0]),
        followup_is_correction=bool(follow)
        and any(re.search(p, follow, re.I) for p in pre),
        n_asst_before=len(ctx),
    )


_PREFILTER = None


def load_rubric_prefilter():
    global _PREFILTER
    if _PREFILTER is None:
        with open(RUBRICS) as fh:
            _PREFILTER = json.load(fh)["rubrics"]["reask"]["prefilter"]
    return _PREFILTER


def case_id(sid, t_idle):
    return hashlib.sha1(("d1s:%s:%.0f" % (sid, t_idle)).encode()).hexdigest()[:16]


def _ctx_of_row(x):
    return int(x["inp"]) + int(x["cc"]) + int(x["cr"])


# ── census over scan.py rows ─────────────────────────────────────────────────────────────────────
def census(rows_dir, accts):
    """→ [dict(acct, sid, path, t_idle, t_next_idle, ctx_at_idle)] idle points opened by a prompt."""
    pts = []
    for a in accts:
        files = {}
        with open(os.path.join(rows_dir, "rows_%s.tsv.files" % a)) as fh:
            for ln in fh:
                f = ln.rstrip("\n").split("\t")
                files[f[0]] = f[5]
        by = collections.defaultdict(list)
        with open(os.path.join(rows_dir, "rows_%s.tsv" % a)) as fh:
            cols = fh.readline().rstrip("\n").split("\t")
            for ln in fh:
                x = dict(zip(cols, ln.rstrip("\n").split("\t")))
                by[x["file"]].append(x)
        for fi, L in by.items():
            L.sort(key=lambda x: float(x["ts"]))
            idle = []
            for prev, r in zip(L, L[1:]):
                if (
                    r["turn"] == "1"
                    and float(r["ts"]) - float(prev["ts"]) >= MIN_GAP_S
                    and _ctx_of_row(prev) >= MIN_CTX
                ):
                    idle.append((float(prev["ts"]), _ctx_of_row(prev), r["sid"]))
            for i, (t, ctx, sid) in enumerate(idle):
                pts.append(
                    dict(
                        acct=a,
                        sid=sid,
                        path=files.get(fi),
                        t_idle=t,
                        ctx_at_idle=ctx,
                        t_next_idle=idle[i + 1][0] if i + 1 < len(idle) else None,
                    )
                )
    return pts


def scan(rows_dir, roots, start, end):
    os.makedirs(rows_dir, exist_ok=True)
    procs = [
        (
            a,
            subprocess.Popen(
                [
                    sys.executable,
                    "-I",
                    SCAN,
                    a,
                    root,
                    str(start),
                    str(end),
                    os.path.join(rows_dir, "rows_%s.tsv" % a),
                ],
                stderr=subprocess.PIPE,
            ),
        )
        for a, root in roots
    ]
    for a, p in procs:
        err = p.communicate()[1]
        if p.returncode:
            raise OSError(
                "scan.py %s failed rc=%d: %s" % (a, p.returncode, err.decode()[-300:])
            )


# ── the imported labels ──────────────────────────────────────────────────────────────────────────
def _actions():
    out, cur = {}, None
    try:
        with open(os.path.join(CONV, "replay", "actions.txt")) as fh:
            for ln in fh:
                m = re.match(r"^=== pid (\d+)", ln)
                if m:
                    cur = int(m.group(1))
                    out[cur] = []
                elif ln.startswith("=== TALLY"):
                    cur = None
                elif cur is not None and ln.strip():
                    out[cur].append(ln.rstrip())
    except OSError:
        return {}
    return {k: "\n".join(v)[:3000] for k, v in out.items()}


def imported_points():
    """The 193 labelled returns of the 2026-10-24 study → [point dict with tag fields]. Raises OSError
    when the import is missing (S7a copied it under ~/.claude/hillclimb/_imports/)."""
    R = [json.loads(ln) for ln in open(os.path.join(STUDY, "ctx.jsonl"))]
    P = [json.loads(ln) for ln in open(os.path.join(STUDY, "points.jsonl"))]
    pids = json.load(open(os.path.join(STUDY, "sample_pids.json")))
    first = json.load(open(os.path.join(STUDY, "labels.json")))
    ho = json.load(open(os.path.join(STUDY, "holdout_labels.json")))
    second = json.load(open(os.path.join(CONV, "labels_second.json")))["labels"]
    acts = _actions()
    lab = {}
    for n, pid in enumerate(pids, 1):
        s = second[str(n)]
        h, a = int(s[1]), int(s[2])
        lab[pid] = (
            "A" if a else "H" if h else ("I" if first[str(n)] == "I" else "S"),
            "second+first",
        )
    out = []
    for pid, r in enumerate(R):
        fo = r.get("first_op")
        if not fo or fo["ts"] < float(r["t_prev"]) + 900:
            continue
        if pid in lab:
            tag, src = lab[pid]
        else:
            h = ho["H"].get(str(pid))
            tag, src = (("A" if h["A"] else "H") if h else "SI"), "holdout"
        files = P[pid].get("files") or [r["path"]]
        if isinstance(files, str):
            files = [files]
        out.append(
            dict(
                acct=r["acct"],
                sid=r["sid"],
                path=files[0],
                t_idle=float(r["t_prev"]),
                ctx_at_idle=int(float(r["ctx_eff"])),
                t_next_idle=None,
                pid=pid,
                tag=tag,
                tag_src=src,
                a_replay=pid in A_REPLAYS,
                ref_action_text=acts.get(pid) if pid in A_REPLAYS else None,
            )
        )
    return out


# ── build ────────────────────────────────────────────────────────────────────────────────────────
def make_case(pt):
    body = extract(pt["path"], pt["t_idle"], pt.get("t_next_idle"))
    if body is None:
        return None
    c = dict(
        case_id=case_id(pt["sid"], pt["t_idle"]),
        acct=pt["acct"],
        sid=pt["sid"],
        path=pt["path"],
        t_idle=pt["t_idle"],
        ctx_at_idle=pt["ctx_at_idle"],
        pid=pt.get("pid"),
        tag=pt.get("tag") or v1_tag(body["prompt"]),
        tag_src=pt.get("tag_src") or "v1",
        a_replay=bool(pt.get("a_replay")),
        ref_action_text=pt.get("ref_action_text"),
    )
    c.update(body)
    return c


def build(rows_dir, roots, start, end, target=TARGET, seed=0, imports=True):
    """→ (cases, meta). Scans [start, end) into rows_dir, imports the labelled returns, selects."""
    scan(rows_dir, roots, start, end)
    accts = [a for a, _r in roots]
    cen = census(rows_dir, accts)
    imp, missing = [], 0
    if imports:
        for pt in imported_points():
            c = make_case(pt) if pt["path"] and os.path.exists(pt["path"]) else None
            if c is None:
                missing += 1
            else:
                imp.append(c)
    seen = {(c["sid"], round(c["t_idle"])) for c in imp}
    new = []
    for pt in cen:
        if not pt["path"] or (pt["sid"], round(pt["t_idle"])) in seen:
            continue
        c = make_case(pt)
        if c is not None:
            new.append(c)
    ids = {c["case_id"] for c in imp}
    new = [c for c in new if c["case_id"] not in ids]
    # every context-dependent return (imported H/A, census v1-H), then S/I up to the target: the
    # labelled imports first (a real label beats the v1 tag), each pool in seeded random order
    rng = random.Random(seed)
    ha = [c for c in imp if c["tag"] in ("H", "A")] + [
        c for c in new if c["tag"] == "H"
    ]
    si_imp = [c for c in imp if c["tag"] not in ("H", "A")]
    si_new = [c for c in new if c["tag"] != "H"]
    rng.shuffle(si_imp)
    rng.shuffle(si_new)
    room = max(0, target - len(ha))
    cases = ha + (si_imp + si_new)[:room]
    h_new = [c for c in new if c["tag"] == "H"]
    cases.sort(key=lambda c: c["case_id"])
    meta = dict(
        flow="d1_successor",
        window=[start, end],
        window_s=end - start,
        n_cases=len(cases),
        n_imported=len(imp),
        n_import_missing=missing,
        n_census_points=len(cen),
        n_census_returns=len(new),
        n_census_h=len(h_new),
        target=target,
        seed=seed,
        tags=dict(collections.Counter(c["tag"] for c in cases)),
        a_replays=sum(1 for c in cases if c["a_replay"]),
        ts=time.time(),
    )
    return cases, meta


# ── fixture ──────────────────────────────────────────────────────────────────────────────────────
def _cut_transcript(src, dst, t_idle):
    """Copy src's lines up to the idle point: a line stamped later is dropped, and so is every
    unstamped line after the first later one (the future never enters the fixture)."""
    n = 0
    past = False
    with open(src, "rb") as fi, open(dst, "wb") as fo:
        for line in fi:
            ts = None
            i = line.find(b'"timestamp":"')
            if i >= 0:
                ts = ep(line[i + 13 : i + 45].split(b'"')[0].decode("utf-8", "replace"))
            if ts is not None and ts > t_idle + 1:
                past = True
                continue
            if ts is None and past:
                continue
            fo.write(line)
            n += 1
    return n


def _config_dir(path):
    """The account config dir a transcript lives under (<dir>/projects/<slug>/<sid>.jsonl)."""
    d = os.path.dirname(os.path.dirname(os.path.abspath(path)))
    if os.path.basename(d) == "projects":
        return os.path.dirname(d)
    return os.path.join(os.path.expanduser("~"), ".claude")


def _global_memory(cfg=None):
    """The user instructions the session's account loads: <config dir>/CLAUDE.md (each account's
    selected variant) and <config dir>/rules/*.md."""
    h = cfg or os.path.join(os.path.expanduser("~"), ".claude")
    parts = []
    for p in [os.path.join(h, "CLAUDE.md")] + sorted(
        glob.glob(os.path.join(h, "rules", "*.md"))
    ):
        try:
            with open(p) as fh:
                parts.append(fh.read())
        except OSError:
            continue
    return "\n\n".join(parts)


def _repo_memory(repo):
    """The archived repo's always-loaded project memory: CLAUDE.md, .claude/CLAUDE.md and every
    .claude/rules/*.md without a `paths:` frontmatter (a path-scoped rule loads only on a match)."""
    parts = []
    rules = sorted(glob.glob(os.path.join(repo, ".claude", "rules", "*.md")))
    for p in [
        os.path.join(repo, "CLAUDE.md"),
        os.path.join(repo, ".claude", "CLAUDE.md"),
    ] + rules:
        try:
            with open(p) as fh:
                t = fh.read()
        except OSError:
            continue
        fm = re.match(r"^---\n(.*?)\n---", t, re.S)
        if p in rules and fm and re.search(r"^paths:", fm.group(1), re.M):
            continue
        parts.append(t)
    return "\n\n".join(parts)


def _repo_at(cwd, t_idle, dst):
    """git archive of cwd's repo at its last commit before t_idle into dst → the commit or None."""
    if not cwd or not os.path.isdir(cwd):
        return None
    try:
        top = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=20,
        ).stdout.strip()
        if not top:
            return None
        sha = subprocess.run(
            ["git", "-C", top, "rev-list", "-1", "--before=@%d" % int(t_idle), "HEAD"],
            capture_output=True,
            text=True,
            timeout=30,
        ).stdout.strip()
        if not sha:
            return None
        os.makedirs(dst, exist_ok=True)
        arc = subprocess.run(
            ["git", "-C", top, "archive", "--format=tar", sha],
            capture_output=True,
            timeout=300,
        )
        if arc.returncode:
            return None
        subprocess.run(
            ["tar", "-x", "-C", dst], input=arc.stdout, check=True, timeout=300
        )
        return sha
    except (OSError, subprocess.SubprocessError):
        return None


def _user_line(text):
    return json.dumps(
        {
            "type": "user",
            "message": {"role": "user", "content": [{"type": "text", "text": text}]},
        }
    )


def fixture(case, out, params=None, repo=True):
    """Materialise one run's inputs under out (which must sit under /tmp/lev-eval). → meta dict."""
    real = os.path.realpath(out)
    if not (real.startswith(os.path.realpath(EVAL_ROOT) + os.sep)):
        raise ValueError("fixture dir %s is not under %s" % (out, EVAL_ROOT))
    if os.path.exists(real):
        shutil.rmtree(real)
    os.makedirs(real)
    tp = os.path.join(real, "predecessor.jsonl")
    kept = _cut_transcript(case["path"], tp, case["t_idle"])
    sys.path.insert(0, os.path.join(REPO, "hooks", "lib"))
    import session_jobs as sj

    recs = sj.records(tp, tail_bytes=8_000_000)
    pq, why = sj.pending_question(recs, case["t_idle"])
    point = dict(
        sid=case["sid"],
        idle_start=case["t_idle"],
        ctx_at_idle=case["ctx_at_idle"],
        # the recycle fires at idle minute N (15): the gap until the operator came back is the future
        gap_s=RECYCLE_AT_S,
        lineage=case["sid"],
        pending_question=pq,
        pq_why=why,
        prompt_sha=case.get("prompt_sha"),
        prompt_head=case.get("prompt_head"),
    )
    text, bmeta = irb.build(point, recs, params, transcript=tp)
    with open(os.path.join(real, "brief.txt"), "w") as fh:
        fh.write(text)
    msgs = [text]
    if case.get("machine_inputs"):
        msgs.append(
            "[While this session sat idle, these messages arrived — oldest first]\n\n"
            + "\n\n---\n\n".join(case["machine_inputs"])
        )
    msgs.append(case["prompt"])
    with open(os.path.join(real, "messages.jsonl"), "w") as fh:
        fh.write("".join(_user_line(m) + "\n" for m in msgs))
    sha = (
        _repo_at(case.get("cwd"), case["t_idle"], os.path.join(real, "repo"))
        if repo
        else None
    )
    if sha is None:
        os.makedirs(os.path.join(real, "repo"), exist_ok=True)
    # the run's cwd is the fixture root, under --setting-sources project: its CLAUDE.md carries what
    # production loads at start (the global instructions, then the session repo's project memory)
    mem = (
        _global_memory(_config_dir(case["path"]))
        + "\n\n"
        + _repo_memory(os.path.join(real, "repo"))
    )
    # the session's own auto-memory index (its project dir's memory/MEMORY.md), as production loads it
    idx = os.path.join(os.path.dirname(case["path"]), "memory", "MEMORY.md")
    if os.path.exists(idx):
        with open(idx) as fh:
            mem += "\n\n" + fh.read()
    with open(os.path.join(real, "CLAUDE.md"), "w") as fh:
        fh.write(mem)
    # the user skills, listed as production lists them (a Skill call only loads text; see the hook)
    skills = os.path.join(os.path.expanduser("~"), ".claude", "skills")
    if os.path.isdir(skills):
        os.makedirs(os.path.join(real, ".claude"), exist_ok=True)
        os.symlink(skills, os.path.join(real, ".claude", "skills"))
    meta = dict(
        case_id=case["case_id"],
        fixture=real,
        transcript_lines=kept,
        repo_sha=sha,
        brief=bmeta,
        n_messages=len(msgs),
        memory_chars=len(mem),
        cwd=real,
    )
    with open(os.path.join(real, "fixture.json"), "w") as fh:
        json.dump(meta, fh, sort_keys=True)
    return meta


def clean(fx):
    """Drop a finished run's repo/ archive (the bulk of a fixture); the rest stays as evidence."""
    real = os.path.realpath(fx)
    if not real.startswith(os.path.realpath(EVAL_ROOT) + os.sep):
        raise ValueError("clean: %s is not under %s" % (fx, EVAL_ROOT))
    if os.path.isdir(os.path.join(real, "repo")):
        shutil.rmtree(os.path.join(real, "repo"))


def main(argv):
    import argparse

    ap = argparse.ArgumentParser(prog="build_cases.py")
    sp = ap.add_subparsers(dest="cmd", required=True)
    f = sp.add_parser("fixture")
    f.add_argument("case")
    f.add_argument("out")
    f.add_argument("--params")
    f.add_argument("--no-repo", action="store_true")
    c = sp.add_parser("clean")
    c.add_argument("fx")
    a = ap.parse_args(argv)
    if a.cmd == "clean":
        try:
            clean(a.fx)
        except ValueError as e:
            sys.stderr.write("build_cases: %s\n" % e)
            return 2
        return 0
    try:
        with open(a.case) as fh:
            case = json.load(fh)
        meta = fixture(
            case, a.out, json.loads(a.params) if a.params else None, repo=not a.no_repo
        )
    except (OSError, ValueError, KeyError) as e:
        sys.stderr.write("build_cases: %s\n" % e)
        return 2
    print(json.dumps(meta, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
