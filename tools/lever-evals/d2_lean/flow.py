#!/usr/bin/env python3
"""flow.py — d2-lean as a cc-lever-eval flow (plan § W7+ §2 D2 "Offline d2-lean", §3 "Evals"; S10).

THE QUESTION. Does a would-deny Workflow slot do as well run as `agentType: 'workflow-lean'` as it
did as the default agent, for fewer requests and less quota? Cases are production slots
(build_cases.py) plus F2's 10 code-graded briefs; answers are graded by code first and then by the
blind judge (grade.py); the gate below is REPORTED, never decided here.

WIRING (probed 2026-10-25 before any of this was written; receipts ~/.claude/hillclimb/d2_lean/probes/):
  1. A headless `claude -p` lead WAITS for a Workflow it starts: its first turn returns "still
     running", the completion notification starts a second turn that prints the result, then the
     process exits 0 (a 50.7 s workflow, 69 s wall). So one process per position, run to exit, and
     the run's own workflows/wf_*.json (status completed) is the record — not the first `result`.
  2. `--agents` OVERRIDES a user-level agent of the same name for a Workflow agent() agentType
     ('workflow-lean' answered with the injected prompt), and honours `omitClaudeMd` (first request
     2,350 tokens with it, 24,856 without). So the lean variant under test is the definition this
     flow injects — agents/workflow-lean.md's frontmatter and body, or a candidate's body — never
     whatever ~/.claude/agents holds, and each variant runs in a fresh process because definitions
     are cached at session start.

THE RUN (`cc-lever-eval run d2_lean`). Cases are grouped into blocks by (account, repo); each block
runs on that account (F2 cases on --acct) in ABBA order, R=2: positions A r1, B r1, B r2, A r2, with A
the default variant in even blocks and lean in odd ones. Every position is a fresh
`claude -p --model claude-opus-5-5 --effort high --agents <def> --session-id <uuid>` whose lead runs
a copy of run.js with the block's cases filled in, CC_LEVER_EXCLUDE=1, cwd a clone of the block's
repo under /tmp/lev-eval/r/. Each case gets its own clone of `git archive <commit>` (APFS clone of a
cached base) and its own OUT dir, so variants never share a tree. A position's process is bounded
by --timeout; one that ends without a completed workflow is recorded as such and its slots grade as
errors (PLUMBING), never as failures.
Known bias, stated: the default variant runs in a /tmp clone, so it misses the per-project auto
memory a production slot in the real checkout loaded; default looks cheaper than production, which
makes the requests and pp ratios conservative against lean.

THE GATE (`cc-lever-eval gate d2_lean`), over one graded run's paired cases (per case, each
variant's mean over its reps):
  pass rate   lean − default, in points; CI95 by a case bootstrap stratified by account; needs the
              lower bound ≥ −10
  requests    Σ lean / Σ default; needs the one-sided 95% upper bound (95th percentile of the same
              bootstrap) ≤ 1.3
  pp          Σ lean / Σ default; needs < 1 at both read-weight ends
VOID when more than 10% of answers are PLUMBING (error / served-model / truncated); INCOMPLETE while
asks wait on the judge. Model runs need the operator's `cc-lever-eval approve-harness d2_lean`; the
one exception is `--smoke` (at most 2 cases, R=1: positions A and B), a plumbing check.
Stdlib only, Python 3.9-safe.
"""

import collections
import glob
import hashlib
import importlib.util
import json
import os
import random
import shutil
import subprocess
import sys
import time
import uuid

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import hc  # noqa: E402

NAME = "d2_lean"
MODEL = "claude-opus-5-5"
EFFORT = "high"
LEAN_DEF = os.path.join(REPO, "agents", "workflow-lean.md")
F2_SETUP = os.path.join(
    REPO, "docs/research/token-efficiency-2026-09-23/eval/harness/f2/setup.sh"
)
REF_FIXTURE = None  # no published number to reproduce (check_repro says why)
SMOKE_MAX = 2
POS_TIMEOUT_S = 4 * 3600
GATE_LO_MIN = -10.0
REQ_UPPER_MAX = 1.3
PP_RATIO_MAX = 1.0
VOID_ERR = 0.10
BOOT_REPS = 2000
ACCT_DIRS = {
    "next": ".claude-next",
    "next2": ".claude-secondary",
    "next3": ".claude-tertiary",
    "next4": ".claude-quaternary",
}
# F2's exact-number briefs and the truth.json fields they are scored on (f2/collect.py EXACT)
F2_EXACT = {
    "B02": ["expansions", "empty_fallbacks", "files"],
    "B03": ["sessions", "sessions_with_feedback", "feedback_records"],
    "B04": ["bats_files", "test_cases"],
    "B05": ["allow_entries", "cc_entries"],
    "B07": ["sh_files", "total_lines"],
    "B09": ["count", "highest"],
}


def _load(name):
    spec = importlib.util.spec_from_file_location(
        "d2_" + name, os.path.join(HERE, name + ".py")
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


BC = _load("build_cases")
GR = _load("grade")


def fx_root():
    return os.environ.get("CC_D2_FX_ROOT") or "/tmp/lev-eval/fx"


def run_root():
    return os.environ.get("CC_D2_RUN_ROOT") or "/tmp/lev-eval/r"


# ── the flow interface cc-lever-eval calls ─────────────────────────────────────────────────────
def build(days=28.0, start=None, end=None):
    return BC.build(days, start, end)


def import_cases(path):
    cases = hc.read_jsonl(path)
    return cases, dict(n_cases=len(cases), source=path)


def case_text(g):
    return g.get("brief") or ""


def wk(meta):
    return 1.0  # a points flow: no fleet pp/wk scale


def validate_params(p):
    bad = sorted(set(p) - {"lean_prompt"})
    if bad:
        raise ValueError(
            "d2_lean params take only lean_prompt (the candidate body); got %s"
            % ", ".join(bad)
        )
    if p.get("lean_prompt") is not None and not str(p["lean_prompt"]).strip():
        raise ValueError("lean_prompt is empty")
    return {"lean_prompt": p.get("lean_prompt")}


def baseline_params(state):
    return validate_params(state.get("best_params") or {})


def lean_definition(prompt=None, path=LEAN_DEF):
    """agents/workflow-lean.md → the `--agents` JSON object. Its frontmatter rides along: without
    omitClaudeMd the injected agent loads CLAUDE.md (probe 2b). `prompt` replaces the body only."""
    with open(path) as fh:
        text = fh.read()
    if not text.startswith("---\n"):
        raise ValueError("%s: no frontmatter" % path)
    head, body = text[4:].split("\n---\n", 1)
    fm = {}
    for ln in head.splitlines():
        if ":" in ln:
            k, v = ln.split(":", 1)
            fm[k.strip()] = v.strip()
    d = {
        "description": fm.get("description", ""),
        "prompt": (prompt if prompt is not None else body).strip(),
    }
    if fm.get("tools"):
        d["tools"] = [t.strip() for t in fm["tools"].split(",") if t.strip()]
    if fm.get("omitClaudeMd", "").lower() == "true":
        d["omitClaudeMd"] = True
    if fm.get("model"):
        d["model"] = fm["model"]
    return {fm.get("name") or "workflow-lean": d}


# ── fixtures ───────────────────────────────────────────────────────────────────────────────────
def _git_quiet(args, cwd):
    env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
    subprocess.run(
        [
            "git",
            "-c",
            "core.hooksPath=/dev/null",
            "-c",
            "user.name=lev-eval",
            "-c",
            "user.email=lev-eval@localhost",
            "-c",
            "commit.gpgsign=false",
        ]
        + args,
        cwd=cwd,
        check=True,
        capture_output=True,
        env=env,
    )


def fixture(repo, commit, dev=None):
    """The frozen base for (repo, commit): `git archive` extracted and committed once into a
    one-commit git repo (so grade.py can `git status` a clone). Read-only over the source repo."""
    if not repo:
        return None
    base = os.path.join(fx_root(), "%s@%s" % (repo, commit[:12]))
    if os.path.exists(base + ".ok"):
        return base
    src = os.path.join(
        dev or os.environ.get("CC_D2_DEV_DIR") or os.path.expanduser("~/Development"),
        repo,
    )
    tmp = base + ".tmp%d" % os.getpid()
    os.makedirs(tmp)
    a = subprocess.Popen(["git", "-C", src, "archive", commit], stdout=subprocess.PIPE)
    subprocess.run(["tar", "-x", "-C", tmp], stdin=a.stdout, check=True)
    if a.wait() != 0:
        raise RuntimeError("git archive %s %s failed" % (repo, commit))
    _git_quiet(["init", "-q"], tmp)
    _git_quiet(["add", "-A"], tmp)
    _git_quiet(["commit", "-qm", "%s@%s" % (repo, commit)], tmp)
    if os.path.exists(base):
        shutil.rmtree(tmp)
    else:
        os.rename(tmp, base)
    open(base + ".ok", "w").close()
    return base


def f2_fixture(sha=BC.F2_SHA):
    """f2/setup.sh's frozen population (tree, corpus, review, truth.json) → $G/f2."""
    g = os.path.join(fx_root(), "f2-%s" % sha[:12])
    f = os.path.join(g, "f2")
    if not os.path.exists(os.path.join(f, "truth.json")):
        os.makedirs(g, exist_ok=True)
        subprocess.run(
            ["/bin/bash", F2_SETUP, sha],
            env=dict(os.environ, GATE_ROOT=g),
            check=True,
            capture_output=True,
        )
    return f


def clone(base, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if subprocess.run(["cp", "-cR", base, dst], capture_output=True).returncode != 0:
        subprocess.run(["cp", "-R", base, dst], check=True)
    return dst


def f2_keys(f2):
    """F2's keys by code from truth.json: exact numbers as `field` facts (B04 also accepts the
    `bats --count` total, B08 the row count), one ask per brief (the judge sees the rest)."""
    with open(os.path.join(f2, "truth.json")) as fh:
        truth = json.load(fh)
    out = {}
    for c in BC.f2_cases():
        b = c["f2_id"]
        facts = []
        for k in F2_EXACT.get(b, []):
            f = dict(claim="%s.%s" % (b, k), match="field", field=k, expect=truth[b][k])
            if k == "test_cases":
                f["alt"] = [truth[b].get("test_cases_bats_count")]
            facts.append(f)
        if b == "B08":
            facts.append(
                dict(
                    claim="B08.rows",
                    match="field",
                    field="rows",
                    expect=len(truth["B08"]["rows"]),
                )
            )
        out[c["case_id"]] = dict(
            src="f2", asks=[c["brief"].split(" numbers:")[0].strip()], facts=facts
        )
    return out


# ── prompts ────────────────────────────────────────────────────────────────────────────────────
def rules_prod(clone_dir, out):
    where = (
        (
            "Your working copy of the task's repository is %s; relative paths in the task are relative "
            "to it. " % clone_dir
        )
        if clone_dir
        else ""
    )
    return (
        "\n\nHarness rules (the same for every agent in this evaluation): %sCreate or modify files only "
        "inside %s/ and the output paths the task itself names; touch nothing else. If the task names no "
        "output file, also write your full answer to %s/answer.md." % (where, out, out)
    )


def rules_f2(out):
    """f2/workflow.js RULES, verbatim."""
    return (
        "\n\nRules: this is READ-ONLY work. Read anything you need, but create or modify files ONLY inside %s/ "
        "(no scratch files in /tmp or anywhere else, no edits to the tree). Write your full answer to %s/answer.md. "
        "Then return the structured output: answer_path = %s/answer.md, headline = your answer in one sentence, "
        "numbers = the named numeric results the brief asks for (use {} if it asks for none)."
        % (out, out, out)
    )


def prepare_case(c, workdir):
    """→ (INPUT case, positions case): this run's clone, OUT dir and mapped prompt."""
    d = os.path.join(workdir, c["case_id"])
    out = os.path.join(d, "out")
    os.makedirs(out, exist_ok=True)
    if c.get("src") == "f2":
        f2 = f2_fixture(c.get("commit") or BC.F2_SHA)
        prompt = c["brief"].replace("{{FIX}}", f2) + rules_f2(out)
        rec = dict(
            case_id=c["case_id"],
            acct=c["acct"],
            cluster=c.get("cluster"),
            out=out,
            clone=None,
            fixture_root=f2,
            allowed_rel=[],
        )
        return dict(case_id=c["case_id"], prompt=prompt, schema=True), rec
    base = fixture(c.get("repo"), c.get("commit")) if c.get("repo") else None
    cl = clone(base, os.path.join(d, "repo")) if base else None
    prompt = c["brief"].replace("{{REPO}}", cl or "").replace("{{OUT}}", out)
    allowed = [
        o[len("{{REPO}}/") :]
        for o in c.get("outputs") or []
        if o.startswith("{{REPO}}/")
    ]
    rec = dict(
        case_id=c["case_id"],
        acct=c["acct"],
        cluster=c.get("cluster"),
        out=out,
        clone=cl,
        fixture_root=base,
        allowed_rel=allowed,
    )
    return dict(
        case_id=c["case_id"], prompt=prompt + rules_prod(cl, out), schema=False
    ), rec


def fill(template, payload):
    """A copy of a Workflow script with INPUT filled in (scripts have no filesystem)."""
    with open(template) as fh:
        src = fh.read()
    if src.count("/*@@INPUT@@*/ null") != 1:
        raise ValueError("%s: expected exactly one INPUT placeholder" % template)
    return src.replace("/*@@INPUT@@*/ null", json.dumps(payload, ensure_ascii=False))


# ── the schedule ───────────────────────────────────────────────────────────────────────────────
def schedule(cases, reps=2, default_acct="next3"):
    """→ blocks: one per (account, repo), ABBA within each (R=2: A1 B1 B2 A2; R=1: A1 B1), A the
    default variant in even blocks and lean in odd ones."""
    groups = collections.OrderedDict()
    for c in sorted(
        cases,
        key=lambda c: (
            c.get("acct") not in ACCT_DIRS,
            c.get("acct"),
            c.get("repo") or "",
            c["case_id"],
        ),
    ):
        acct = c["acct"] if c.get("acct") in ACCT_DIRS else default_acct
        groups.setdefault((acct, c.get("repo") or ""), []).append(c)
    blocks = []
    for i, ((acct, repo), cs) in enumerate(groups.items()):
        a, b = ("default", "lean") if i % 2 == 0 else ("lean", "default")
        order = [(a, 1), (b, 1)] if reps == 1 else [(a, 1), (b, 1), (b, 2), (a, 2)]
        blocks.append(
            dict(block="b%d" % i, acct=acct, repo=repo or None, cases=cs, order=order)
        )
    return blocks


def current_acct():
    d = os.path.basename((os.environ.get("CLAUDE_CONFIG_DIR") or "").rstrip("/"))
    for a, v in ACCT_DIRS.items():
        if v == d:
            return a
    return "next"


def claude_bin():
    return os.environ.get("CC_D2_CLAUDE") or shutil.which("claude") or "claude"


def launch(
    script,
    cwd,
    acct,
    agents,
    sid,
    log_path,
    model=MODEL,
    effort=EFFORT,
    timeout=POS_TIMEOUT_S,
):
    """One fresh headless lead that runs `script` and waits for it (probe 1). → exit code or 'timeout'."""
    prompt = (
        "Run the workflow script at %s with the Workflow tool (scriptPath). I explicitly ask you to run "
        "this workflow. Do not edit it. When it has finished, reply with the one word DONE."
        % script
    )
    argv = [
        claude_bin(),
        "-p",
        prompt,
        "--model",
        model,
        "--session-id",
        sid,
        "--allowedTools",
        "Workflow",
        "--permission-mode",
        "auto",
        "--output-format",
        "stream-json",
        "--verbose",
    ]
    if effort:
        argv[4:4] = ["--effort", effort]
    if agents:
        argv += ["--agents", agents]
    env = hc.eval_env()
    env["CLAUDE_CONFIG_DIR"] = os.path.join(os.path.expanduser("~"), ACCT_DIRS[acct])
    with open(log_path, "w") as out:
        try:
            p = subprocess.run(
                argv,
                cwd=cwd,
                env=env,
                stdout=out,
                stderr=subprocess.STDOUT,
                timeout=timeout,
            )
            return p.returncode
        except subprocess.TimeoutExpired:
            return "timeout"


def find_run(acct, sid):
    """→ (run json path, its dict, transcript dir) of the workflow session `sid` ran, or Nones."""
    base = os.path.join(os.path.expanduser("~"), ACCT_DIRS[acct], "projects")
    hits = sorted(glob.glob(os.path.join(base, "*", sid, "workflows", "wf_*.json")))
    if not hits:
        return None, None, None
    p = hits[-1]
    try:
        with open(p) as fh:
            j = json.load(fh)
    except (OSError, ValueError):
        return p, None, None
    wf = os.path.join(
        os.path.dirname(os.path.dirname(p)),
        "subagents",
        "workflows",
        j.get("runId") or "",
    )
    return p, j, wf


# ── run / keys / grade / gate ──────────────────────────────────────────────────────────────────
def _select(a):
    d = hc.flow_dir(NAME)
    if a.cases == "train":
        return hc.read_train(NAME)
    if a.cases == "all":
        return hc.read_jsonl(os.path.join(d, "cases.jsonl"))
    if a.cases == "test":
        return hc.read_test(NAME, unseal=True)
    return hc.read_jsonl(a.cases)


def smoke_cases(cases):
    """The plumbing smoke: one F2 brief and the production case with the shortest brief, both from
    the train half (a smoke never reads the sealed test split)."""
    f2 = sorted((c for c in cases if c.get("src") == "f2"), key=lambda c: c["case_id"])
    prod = sorted(
        (c for c in cases if c.get("src") == "prod"),
        key=lambda c: (len(c["brief"]), c["case_id"]),
    )
    return (f2[-1:] + prod[:1])[:SMOKE_MAX]


def stamp():
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


def load_key():
    return GR.load_key(os.path.join(hc.flow_dir(NAME), "key.json"))


def save_key(k):
    hc._write_atomic(
        os.path.join(hc.flow_dir(NAME), "key.json"),
        json.dumps(k, indent=1, sort_keys=True) + "\n",
    )


def run_model(a):
    cases = (
        _select(a)
        if not a.smoke
        else smoke_cases(hc.read_train(NAME))
    )
    if a.smoke:
        if len(cases) > SMOKE_MAX:
            raise ValueError("a smoke runs at most %d cases" % SMOKE_MAX)
        reps = 1
    else:
        hc.require_approved(NAME)
        reps = a.reps
    key = load_key()
    missing = [c["case_id"] for c in cases if c["case_id"] not in key]
    if missing:
        raise ValueError(
            "no key for %d case(s) (e.g. %s): run `cc-lever-eval keys d2_lean` first"
            % (len(missing), missing[0])
        )
    st = hc.load_state(NAME)
    prm = validate_params(json.loads(a.params)) if a.params else baseline_params(st)
    tag = a.tag or ("smoke-" if a.smoke else "run-") + stamp()
    rec_dir = os.path.join(hc.flow_dir(NAME), "smoke" if a.smoke else "runs", tag)
    os.makedirs(rec_dir, exist_ok=True)
    agents_path = os.path.join(rec_dir, "agents.json")
    with open(agents_path, "w") as fh:
        json.dump(lean_definition(prm.get("lean_prompt")), fh, indent=1)
    blocks = schedule(cases, reps, a.acct or current_acct())
    plan = [
        dict(
            block=b["block"],
            acct=b["acct"],
            repo=b["repo"],
            n=len(b["cases"]),
            order=["%s r%d" % o for o in b["order"]],
        )
        for b in blocks
    ]
    with open(os.path.join(rec_dir, "plan.json"), "w") as fh:
        json.dump(
            dict(tag=tag, params=prm, reps=reps, smoke=bool(a.smoke), blocks=plan),
            fh,
            indent=1,
        )
    print(
        "d2_lean %s: %d case(s), %d block(s), R=%d → %s"
        % (tag, len(cases), len(blocks), reps, rec_dir)
    )
    pos_log = os.path.join(rec_dir, "positions.jsonl")
    for b in blocks:
        for k, (variant, rep) in enumerate(b["order"]):
            workdir = os.path.join(run_root(), tag, b["block"], "p%d" % k)
            inputs, recs = [], []
            for c in b["cases"]:
                i, r = prepare_case(c, workdir)
                inputs.append(i)
                recs.append(r)
            ws = os.path.join(workdir, "_lead")
            if b["repo"] and recs and recs[0].get("clone"):
                ws = recs[0]["clone"]
            os.makedirs(ws, exist_ok=True)
            script = os.path.join(workdir, "run.js")
            with open(script, "w") as fh:
                fh.write(
                    fill(
                        os.path.join(HERE, "run.js"),
                        dict(variant=variant, rep=rep, block=b["block"], cases=inputs),
                    )
                )
            sid = str(uuid.uuid4())
            row = dict(
                block=b["block"],
                pos=k,
                variant=variant,
                rep=rep,
                acct=b["acct"],
                repo=b["repo"],
                sid=sid,
                workdir=workdir,
                script=script,
                cases=recs,
                ts=hc.utc(),
            )
            print(
                "  %s p%d %-7s r%d on %s (%d case(s))%s"
                % (
                    b["block"],
                    k,
                    variant,
                    rep,
                    b["acct"],
                    len(recs),
                    " [dry-run]" if a.dry_run else "",
                )
            )
            if not a.dry_run:
                rc = launch(
                    script,
                    ws,
                    b["acct"],
                    agents_path,
                    sid,
                    os.path.join(rec_dir, "%s-p%d.stream.jsonl" % (b["block"], k)),
                    timeout=a.timeout,
                )
                p, j, wf = find_run(b["acct"], sid)
                row.update(
                    rc=rc,
                    run_json=p,
                    run_id=(j or {}).get("runId"),
                    wf_dir=wf,
                    wf_status=(j or {}).get("status"),
                )
                print(
                    "    rc=%s workflow %s %s" % (rc, row["run_id"], row["wf_status"])
                )
            with open(pos_log, "a") as fh:
                fh.write(json.dumps(row, sort_keys=True) + "\n")
    return 0


def cmd_keys(a):
    """Keys for the selected cases: F2 by code from truth.json; production by keygen.js (Sonnet
    5.5 key-builders over the frozen fixtures), each check_cmd then RUN here on the fixture and kept
    only if it exits 0 with a value. A smoke keys only the smoke's cases; anything else needs the
    approved harness (keygen is a model run)."""
    allc = hc.read_jsonl(os.path.join(hc.flow_dir(NAME), "cases.jsonl"))
    cases = (
        smoke_cases(hc.read_train(NAME))
        if a.smoke
        else (_select(a) if a.cases not in (None, "all") else allc)
    )
    if not a.smoke:
        hc.require_approved(NAME)
    key = load_key()
    f2 = [c for c in cases if c.get("src") == "f2"]
    if f2:
        k2 = f2_keys(f2_fixture())
        for c in f2:
            key[c["case_id"]] = k2[c["case_id"]]
    prod = [
        c
        for c in cases
        if c.get("src") == "prod" and (a.force or c["case_id"] not in key)
    ]
    if prod:
        roots = {
            c["case_id"]: fixture(c.get("repo"), c.get("commit"))
            if c.get("repo")
            else fx_root()
            for c in prod
        }
        payload = dict(
            cases=[
                dict(
                    case_id=c["case_id"],
                    root=roots[c["case_id"]],
                    brief=c["brief"].replace("{{REPO}}", roots[c["case_id"]]),
                )
                for c in prod
            ]
        )
        tag = ("smoke-" if a.smoke else "") + "keygen-" + stamp()
        d = os.path.join(hc.flow_dir(NAME), "keygen", tag)
        os.makedirs(d, exist_ok=True)
        script = os.path.join(d, "keygen.js")
        with open(script, "w") as fh:
            fh.write(fill(os.path.join(HERE, "keygen.js"), payload))
        sid = str(uuid.uuid4())
        acct = a.acct or current_acct()
        os.makedirs(fx_root(), exist_ok=True)
        rc = launch(
            script,
            fx_root(),
            acct,
            None,
            sid,
            os.path.join(d, "stream.jsonl"),
            model="sonnet",
            effort=None,
            timeout=a.timeout,
        )
        _p, j, _wf = find_run(acct, sid)
        got = {
            k["case_id"]: k.get("key")
            for k in ((j or {}).get("result") or {}).get("keys") or []
            if k
        }
        kept = dropped = 0
        for c in prod:
            k = got.get(c["case_id"])
            if not k:
                continue
            facts = []
            for f in k.get("facts") or []:
                ok, val = GR.run_check(f.get("check_cmd") or "", roots[c["case_id"]])
                if ok and f.get("match") in ("number", "substring"):
                    facts.append(
                        dict(
                            claim=f.get("claim"),
                            check_cmd=f["check_cmd"],
                            match=f["match"],
                            value=val,
                        )
                    )
                    kept += 1
                else:
                    dropped += 1
            key[c["case_id"]] = dict(
                src="keygen",
                asks=[s for s in k.get("asks") or [] if s.strip()],
                facts=facts,
                keygen=tag,
            )
        print(
            "keygen %s: rc=%s, %d/%d case(s) keyed, facts kept %d, dropped %d (check_cmd failed on the fixture)"
            % (tag, rc, len(got), len(prod), kept, dropped)
        )
    save_key(key)
    print("key.json: %d case(s)" % len(key))
    return 0


def latest_run(kind="runs"):
    d = os.path.join(hc.flow_dir(NAME), kind)
    runs = sorted(glob.glob(os.path.join(d, "*", "positions.jsonl")))
    return os.path.dirname(runs[-1]) if runs else None


def run_dir_of(a):
    if a.tag:
        for kind in ("runs", "smoke"):
            p = os.path.join(hc.flow_dir(NAME), kind, a.tag)
            if os.path.isdir(p):
                return p
        raise ValueError("no run %r" % a.tag)
    p = latest_run("smoke" if a.smoke else "runs")
    if not p:
        raise ValueError("no %s run yet" % ("smoke" if a.smoke else "graded"))
    return p


def cmd_grade(a):
    _rows, summ = GR.grade(
        run_dir_of(a), load_key(), not a.no_judge, a.seed, a.judge_max
    )
    print(json.dumps(summ, sort_keys=True))
    return 0


# ── gate arithmetic ────────────────────────────────────────────────────────────────────────────
def per_case(rows):
    """graded rows → {case_id: {acct, default: {pass, requests, pp_lo, pp, pp_hi}, lean: {...}}},
    each variant the mean over its scored reps. A case enters only with both variants scored."""
    acc = collections.defaultdict(lambda: collections.defaultdict(list))
    acct = {}
    for r in rows:
        if r.get("status") != "ok" or r.get("passed") is None:
            continue
        acc[r["case_id"]][r["variant"]].append(r)
        acct[r["case_id"]] = (r.get("acct") or "?", r.get("cluster"))
    out = {}
    for cid, by in acc.items():
        if not by.get("lean") or not by.get("default"):
            continue
        out[cid] = dict(acct=acct[cid][0], cluster=acct[cid][1])
        for v in ("lean", "default"):
            rs = by[v]
            out[cid][v] = {
                k: sum(
                    (1.0 if x["passed"] else 0.0)
                    if k == "pass"
                    else float(x.get(k) or 0)
                    for x in rs
                )
                / len(rs)
                for k in ("pass", "requests", "pp_lo", "pp", "pp_hi")
            }
    return out


def _boot(cases, stat, reps=BOOT_REPS, seed=0):
    """Cluster bootstrap stratified by account → sorted list of stat(resample). A cluster is the
    case's Workflow run (slots of one run are correlated); a case without one is its own cluster."""
    strata = collections.defaultdict(lambda: collections.OrderedDict())
    for c in cases:
        strata[c["acct"]].setdefault(c.get("cluster") or c["case_id"], []).append(c)
    rng = random.Random(seed)
    out = []
    for _ in range(reps):
        s = []
        for cl in strata.values():
            groups = list(cl.values())
            for _ in groups:
                s += groups[rng.randrange(len(groups))]
        v = stat(s)
        if v is not None:
            out.append(v)
    return sorted(out)


def _ratio(cs, k):
    d = sum(c["default"][k] for c in cs)
    return sum(c["lean"][k] for c in cs) / d if d > 0 else None


def gate(rows, reps=BOOT_REPS, seed=0):
    """→ dict with each criterion's numbers and PASS/FAIL, and the overall verdict (reported only)."""
    n_all = len(rows)
    n_err = sum(1 for r in rows if r.get("status") != "ok")
    n_pend = sum(1 for r in rows if r.get("status") == "ok" and r.get("passed") is None)
    pc = per_case(rows)
    cs = [dict(v, case_id=k) for k, v in sorted(pc.items())]
    res = dict(
        n_rows=n_all,
        n_errors=n_err,
        err_rate=round(n_err / n_all, 4) if n_all else None,
        n_pending=n_pend,
        n_cases=len(cs),
    )
    if n_all and n_err / n_all > VOID_ERR:
        res["verdict"] = "VOID"
        res["why"] = "PLUMBING: %d of %d answers errored (> %d%%)" % (
            n_err,
            n_all,
            VOID_ERR * 100,
        )
        return res
    if len(cs) < 2:
        res["verdict"] = "NO-DATA"
        res["why"] = "%d paired case(s); the gate needs at least 2" % len(cs)
        return res
    diff = lambda s: (
        100.0 * sum(c["lean"]["pass"] - c["default"]["pass"] for c in s) / len(s)
    )  # noqa: E731
    bd = _boot(cs, diff, reps, seed)
    br = _boot(cs, lambda s: _ratio(s, "requests"), reps, seed)
    res["pass_rate"] = dict(
        lean=round(100.0 * sum(c["lean"]["pass"] for c in cs) / len(cs), 2),
        default=round(100.0 * sum(c["default"]["pass"] for c in cs) / len(cs), 2),
        diff=round(diff(cs), 2),
        lo=round(bd[int(0.025 * len(bd))], 2),
        hi=round(bd[min(len(bd) - 1, int(0.975 * len(bd)))], 2),
        min_lo=GATE_LO_MIN,
    )
    res["pass_rate"]["ok"] = res["pass_rate"]["lo"] >= GATE_LO_MIN
    rr = _ratio(cs, "requests")
    res["requests"] = dict(
        ratio=None if rr is None else round(rr, 4),
        upper95=round(br[min(len(br) - 1, int(0.95 * len(br)))], 4) if br else None,
        max_upper=REQ_UPPER_MAX,
    )
    res["requests"]["ok"] = (
        res["requests"]["upper95"] is not None
        and res["requests"]["upper95"] <= REQ_UPPER_MAX
    )
    pp = {
        e: _ratio(cs, k) for e, k in (("lo", "pp_lo"), ("mid", "pp"), ("hi", "pp_hi"))
    }
    res["pp"] = {e: (None if v is None else round(v, 4)) for e, v in pp.items()}
    res["pp"]["max"] = PP_RATIO_MAX
    res["pp"]["ok"] = all(v is not None and v < PP_RATIO_MAX for v in pp.values())
    ok = res["pass_rate"]["ok"] and res["requests"]["ok"] and res["pp"]["ok"]
    res["verdict"] = "INCOMPLETE" if n_pend else ("PASS" if ok else "FAIL")
    if n_pend:
        res["why"] = "%d answer(s) still wait on the judge" % n_pend
    return res


def gate_lines(g):
    out = [
        "d2_lean gate over %d paired case(s), %d answer row(s), %d error(s), %d pending"
        % (g["n_cases"], g["n_rows"], g["n_errors"], g["n_pending"])
    ]
    if "pass_rate" in g:
        p, r, q = g["pass_rate"], g["requests"], g["pp"]
        out.append(
            "  %s pass rate: lean %.1f vs default %.1f, diff %+.2f pts, CI95 [%+.2f, %+.2f] (lower must be >= %+.0f)"
            % (
                "PASS" if p["ok"] else "FAIL",
                p["lean"],
                p["default"],
                p["diff"],
                p["lo"],
                p["hi"],
                p["min_lo"],
            )
        )
        out.append(
            "  %s requests: lean/default %s, one-sided 95%% upper %s (must be <= %.1f)"
            % ("PASS" if r["ok"] else "FAIL", r["ratio"], r["upper95"], r["max_upper"])
        )
        out.append(
            "  %s pp: lean/default %s / %s / %s at read lo/mid/hi (each must be < %.0f)"
            % ("PASS" if q["ok"] else "FAIL", q["lo"], q["mid"], q["hi"], q["max"])
        )
    out.append(
        "gate: %s%s — reported, not decided (the operator decides D2)"
        % (g["verdict"], (" (" + g["why"] + ")") if g.get("why") else "")
    )
    return out


def cmd_gate(a):
    d = None if a.graded else run_dir_of(a)
    rows = hc.read_jsonl(a.graded or os.path.join(d, "graded.jsonl"))
    g = gate(rows, seed=a.seed)
    for ln in gate_lines(g):
        print(ln)
    if a.write and d:
        with open(os.path.join(d, "gate.json"), "w") as fh:
            json.dump(g, fh, indent=1, sort_keys=True)
    return 0 if g["verdict"] in ("PASS", "FAIL", "INCOMPLETE") else 1


# ── checks (cc-lever-eval check d2_lean …) ─────────────────────────────────────────────────────
def _latest_rows():
    d = latest_run("runs")
    p = os.path.join(d, "graded.jsonl") if d else None
    return hc.read_jsonl(p) if p and os.path.exists(p) else None


def check_repro(_cases, _meta):
    return True, [
        "n/a: d2_lean has no published replay number; F2's truth.json is recomputed by f2/setup.sh "
        "and its exact facts are graded by code (check oracle/null prove the grader)"
    ]


def check_oracle(train):
    """An answer stating every key value passes every fact (the grader can say yes)."""
    key, bad, n = load_key(), [], 0
    for c in train:
        k = key.get(c["case_id"]) or {}
        for f in k.get("facts") or []:
            n += 1
            tv = f.get("expect", f.get("value"))
            ans = str(tv)
            if not GR.fact_ok(
                f, tv, ans, {f.get("field"): tv} if f.get("field") else None
            ):
                bad.append("%s %s" % (c["case_id"], f.get("claim")))
    return (n > 0 and not bad), [
        "%d fact(s) over %d train case(s); oracle failed %d %s"
        % (n, len(train), len(bad), bad[:3])
    ]


def check_null(train):
    """An empty answer fails every fact (the grader can say no)."""
    key, passed, n = load_key(), [], 0
    for c in train:
        for f in (key.get(c["case_id"]) or {}).get("facts") or []:
            n += 1
            if GR.fact_ok(f, f.get("expect", f.get("value")), "", {}):
                passed.append("%s %s" % (c["case_id"], f.get("claim")))
    return (n > 0 and not passed), [
        "%d fact(s); the null answer passed %d %s" % (n, len(passed), passed[:3])
    ]


def check_aa(train, _hc):
    """A/A: the default variant's r1 vs r2 pass rates on train cases; NF = CI95 half-width, which
    must sit below MIN_ACT (10 points) or a round cannot be read."""
    rows = _latest_rows()
    if not rows:
        return False, ["no graded baseline run yet"]
    ids = {c["case_id"] for c in train}
    by = collections.defaultdict(dict)
    for r in rows:
        if (
            r["case_id"] in ids
            and r["variant"] == "default"
            and r.get("passed") is not None
        ):
            by[r["case_id"]]["acct"] = r.get("acct") or "?"
            by[r["case_id"]][r["rep"]] = 1.0 if r["passed"] else 0.0
    cs = [v for v in by.values() if 1 in v and 2 in v]
    if len(cs) < 2:
        return False, ["%d train case(s) with both default reps" % len(cs)]
    d = lambda s: 100.0 * sum(c[1] - c[2] for c in s) / len(s)  # noqa: E731
    b = _boot(cs, d)
    nf = (b[int(0.975 * len(b))] - b[int(0.025 * len(b))]) / 2
    ok = nf < hc.FLOWS[NAME]["min_act"]
    return ok, [
        "A/A default r1-r2 %+.2f pts over %d case(s), NF %.2f vs MIN_ACT %.0f"
        % (d(cs), len(cs), nf, hc.FLOWS[NAME]["min_act"])
    ]


def _share(status):
    rows = _latest_rows()
    if not rows:
        return False, ["no graded run yet"]
    n = sum(1 for r in rows if r.get("status") == status)
    return n / len(rows) <= VOID_ERR, ["%d of %d answer(s) %s" % (n, len(rows), status)]


def check_served_model(_train):
    return _share("served-model")


def check_truncation(_train):
    return _share("truncated")


def failures(cases, params):
    """Train failure classes from the latest graded run → [(class, n, 0.0)]."""
    rows = _latest_rows() or []
    ids = {c["case_id"] for c in cases}
    cnt = collections.Counter()
    for r in rows:
        if r["case_id"] not in ids:
            continue
        if r.get("status") != "ok":
            cnt["plumbing:" + r["status"]] += 1
        elif r.get("forbidden"):
            cnt["%s:forbidden-write" % r["variant"]] += 1
        elif r.get("facts_ok", 0) < r.get("facts_n", 0):
            cnt["%s:fact" % r["variant"]] += 1
        elif r.get("passed") is False:
            cnt["%s:judged-fail" % r["variant"]] += 1
    return [(k, n, 0.0) for k, n in cnt.most_common()]
