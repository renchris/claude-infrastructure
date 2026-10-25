#!/usr/bin/env python3
"""build_cases.py — the d2-lean case pool (plan § W7+ §2 D2 "Offline d2-lean"; wave S10).
Read-only over transcripts, the shadow log and the repos' object stores.

WHO IS A CASE. A Workflow agent() slot that ran WITHOUT agentType (its meta.json says
`workflow-subagent`) and that D2's deny would have targeted: its runtime brief names none of the
hook's keep-default markers (commit / ship / Skill / MCP — the same MARKERS
hooks/workflow-lean-shadow.py applies, imported from it, never copied), its run's script has no
`needs-default` exemption, and, where the call has a shadow row, that row reads would_deny.
Plus F2's 10 code-graded briefs (docs/research/token-efficiency-2026-09-23/eval/harness/f2/), whose
ground truth f2/setup.sh computes by code.

DROPPED, each counted by reason in build.json (a smaller pool is reported, never silent):
  resume        the run was launched by a Workflow call carrying resumeFromRunId (read from the
                launching tool_use in the main transcript, or from its shadow row) — a resume
                replays cached slots, so it is not a fresh slot
  repeat-key    the slot's journal key (prompt + options) already ran earlier in the session
  shadow-kind   kind=slots / kind=d4_follow rows are continuations, never call rows: the reader
                joins on tool_use_id and FILTERS ON KIND (S3 learning); counted for the record
  eval          the session ran in the eval cwd (/tmp/lev-eval) — eval rows are never cases
  probe         a brief under MIN_BRIEF chars: a harness wiring probe ("Reply with exactly WF_OK"),
                not production work (measured 2026-10-25: 8 such briefs at 30-75 chars, the shortest
                real brief 1,185)
  has-agent-type, keep-default, needs-default, shadow-not-would-deny, failed (no journal result)
  repo-unresolved, path-not-at-commit, input-live, input-gone, brief-empty
                the fixture rules below could not freeze what the slot read

FIXTURES (frozen, so a re-run reads exactly what is recorded). A case records (repo, commit): the
repo is the cwd's (a live worktree, the transcript's branch, or path evidence), the commit is
trunk (origin/main) as of the slot's start. Every absolute path in the brief is mapped:
  under the cwd / the repo's main checkout / ~/.claude* (a symlink farm over claude-infrastructure)
      → {{REPO}}/<rel>, and an input must exist at that commit
  written by the original slot (Write/Edit/NotebookEdit, or a Bash `>`, `tee`, `mkdir`, `touch`)
      → {{OUT}}/o<k>/… (an output: the eval slot writes it under its own OUT dir)
  anything else → dropped (input-live if it exists now and so may have moved, input-gone if not)
The driver (flow.py) materializes {{REPO}} as a clone of `git archive <commit>` and {{OUT}} per run.

SAMPLE. About 20/20 train/test (plan): the split stays hc's (test iff sha1(case_id) % 5 == 0), so
the sample picks by half — F2's 10 first, then production cases round-robin over accounts, at most
MAX_PER_RUN slots from one Workflow run in each half — until each half holds HALF_N or the pool runs
out (measured 2026-10-25: 59 eligible slots from 11 runs, 13 of them test-hashed, so the test half
holds what exists, not 20). Slots of one run are correlated, so each case carries `cluster` (its run;
an F2 brief is its own) and the gate resamples clusters, not slots. Per-account counts stay
well under hc's 20-case stratification floor, and each account is balanced across the halves.

usage: python3 -I build_cases.py --out CASES [--days 28] [--start EPOCH] [--end EPOCH] [--all]
Stdlib only, Python 3.9-safe.
"""

import argparse
import collections
import glob
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.realpath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
HOME = os.path.expanduser("~")
ROOTS = (
    ("next", ".claude-next"),
    ("next2", ".claude-secondary"),
    ("next3", ".claude-tertiary"),
    ("next4", ".claude-quaternary"),
)
SHADOW = os.path.join(HOME, ".claude", "logs", "workflow-lean-shadow.jsonl")
F2_DIR = os.path.join(
    REPO_ROOT, "docs/research/token-efficiency-2026-09-23/eval/harness/f2"
)
F2_SHA = "d636fa0c769c6dca9ef0b54160a0731e320f2733"  # f2/setup.sh's pinned tree
EVAL_CWD = "/tmp/lev-eval"
NO_TYPE = "workflow-subagent"  # meta.agentType of a slot called without agentType
MIN_BRIEF = 200
HALF_N = 20
MAX_PER_RUN = 6
FRAME = "The computed task text follows:\n"
USER_FRAME = "[Workflow harness — user request]"
PATH_RX = re.compile(
    r"(?<![\w.$}])(~/|/(?:Users|tmp|private/tmp)/)[^\s`'\"<>()\[\]{},;|*]*"
)


def roots():
    """(acct, projects dir) for the four accounts; CC_LEVER_EVAL_ROOTS="acct=dir,..." overrides."""
    env = os.environ.get("CC_LEVER_EVAL_ROOTS")
    if env:
        return [tuple(x.split("=", 1)) for x in env.split(",") if "=" in x]
    return [(a, os.path.join(HOME, d, "projects")) for a, d in ROOTS]


def ep(s):
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _grade():
    """grade.py's write-target reader, shared so a case's outputs and an answer's forbidden writes
    are read by one rule."""
    global _GRADE
    if _GRADE is None:
        spec = importlib.util.spec_from_file_location("d2_grade", os.path.join(HERE, "grade.py"))
        _GRADE = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_GRADE)
    return _GRADE


_GRADE = None


def _hook():
    p = os.environ.get("CC_D2_SHADOW_HOOK") or os.path.join(
        REPO_ROOT, "hooks", "workflow-lean-shadow.py"
    )
    spec = importlib.util.spec_from_file_location("wls", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ── shadow rows ────────────────────────────────────────────────────────────────────────────────
def shadow_calls(path=None):
    """→ ({tool_use_id: call row}, {kind: n skipped}). Only call rows (no kind) are returned; a
    kind=slots continuation is merged back into its call by tool_use_id, any other kind skipped."""
    calls, cont, skipped = {}, collections.defaultdict(list), collections.Counter()
    try:
        fh = open(path or SHADOW, encoding="utf-8", errors="replace")
    except OSError:
        return {}, skipped
    with fh:
        for ln in fh:
            try:
                r = json.loads(ln)
            except ValueError:
                skipped["unparsed"] += 1
                continue
            k = r.get("kind")
            if k == "slots":
                cont[r.get("tool_use_id")].append(r)
                skipped["slots"] += 1
            elif k:
                skipped[k] += 1
            elif r.get("tool_use_id"):
                calls[r["tool_use_id"]] = r
    for tid, parts in cont.items():
        if tid in calls and "slots" not in calls[tid]:
            calls[tid]["slots"] = [
                s
                for p in sorted(parts, key=lambda x: x.get("part", 0))
                for s in p.get("slots") or []
            ]
    return calls, skipped


# ── transcripts ────────────────────────────────────────────────────────────────────────────────
def run_dirs(root, S, E):
    """→ [(proj_dir, sid, run_dir)] for workflow runs whose dir changed in [S, E)."""
    out = []
    for rd in glob.glob(os.path.join(root, "*", "*", "subagents", "workflows", "wf_*")):
        try:
            mt = os.stat(rd).st_mtime
        except OSError:
            continue
        if S <= mt < E:
            sd = os.path.dirname(os.path.dirname(os.path.dirname(rd)))
            out.append((os.path.dirname(sd), os.path.basename(sd), rd))
    return out


def launches(main_transcript):
    """Workflow calls in a main transcript → {run_id: {tool_use_id, resume, input_keys}}. The run id
    comes from the tool_result ('…/subagents/workflows/wf_…' or 'runId')."""
    uses, out = {}, {}
    try:
        fh = open(main_transcript, "rb")
    except OSError:
        return out
    with fh:
        for line in fh:
            if b"Workflow" not in line and b"wf_" not in line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            c = (r.get("message") or {}).get("content")
            for b in c if isinstance(c, list) else ():
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use" and b.get("name") == "Workflow":
                    inp = b.get("input") or {}
                    uses[b.get("id")] = dict(
                        tool_use_id=b.get("id"),
                        resume=bool(inp.get("resumeFromRunId")),
                        resume_from=inp.get("resumeFromRunId"),
                    )
                elif b.get("type") == "tool_result" and b.get("tool_use_id") in uses:
                    body = b.get("content")
                    if isinstance(body, list):
                        body = " ".join(
                            x.get("text", "") for x in body if isinstance(x, dict)
                        )
                    m = re.search(r"\b(wf_[0-9a-f]{8}-[0-9a-f]{3})\b", str(body or ""))
                    if m:
                        out[m.group(1)] = uses[b["tool_use_id"]]
    return out


def strip_frame(text):
    i = text.find(FRAME)
    if i < 0:
        return text.strip()
    body = text[i + len(FRAME) :]
    return "\n".join(
        ln[2:] if ln.startswith("  ") else ln for ln in body.split("\n")
    ).strip()


def read_slot(path):
    """→ (brief, cwd, ts, branch, written paths, served models)."""
    brief, cwd, ts, branch, written, models = None, None, None, None, set(), set()
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return None, None, None, None, written, models
    with fh:
        for ln in fh:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            m = r.get("message") or {}
            if brief is None and r.get("type") == "user":
                c = m.get("content")
                if isinstance(c, list):
                    c = " ".join(
                        x.get("text", "")
                        for x in c
                        if isinstance(x, dict) and x.get("type") == "text"
                    )
                # newer runs first relay the operator's request in its own record; the slot's brief
                # is the computed-task record after it, never the relayed request
                if c and not c.startswith(USER_FRAME):
                    brief = strip_frame(c)
                    cwd, ts, branch = (
                        r.get("cwd"),
                        r.get("timestamp"),
                        r.get("gitBranch"),
                    )
            if r.get("type") == "assistant":
                if m.get("model") and m.get("model") != "<synthetic>":
                    models.add(m["model"])
                for b in m.get("content") or []:
                    if not isinstance(b, dict) or b.get("type") != "tool_use":
                        continue
                    inp = b.get("input") or {}
                    if b.get("name") in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                        p = inp.get("file_path") or inp.get("notebook_path")
                        if p:
                            written.add(os.path.normpath(os.path.expanduser(p)))
                    elif b.get("name") == "Bash":
                        for t in _grade().bash_write_targets(inp.get("command")):
                            written.add(os.path.normpath(os.path.expanduser(t)))
    return brief, cwd, ts, branch, written, models


# ── repos and paths ────────────────────────────────────────────────────────────────────────────
class Repos:
    """The git repos under ~/Development, read-only: worktree lists, branches, trunk-at-time, blobs."""

    def __init__(self, base=None):
        self.base = (
            base or os.environ.get("CC_D2_DEV_DIR") or os.path.join(HOME, "Development")
        )
        self.repos = {}
        try:
            names = sorted(os.listdir(self.base))
        except OSError:
            names = []
        for n in names:
            p = os.path.join(self.base, n)
            if os.path.isdir(os.path.join(p, ".git")):
                self.repos[n] = p
        self._wt = None
        self._cache = {}

    def git(self, name, *args):
        k = (name,) + args
        if k not in self._cache:
            p = subprocess.run(
                ["git", "-C", self.repos[name]] + list(args),
                capture_output=True,
                text=True,
            )
            self._cache[k] = (p.returncode, p.stdout.strip())
        return self._cache[k]

    def worktrees(self):
        if self._wt is None:
            self._wt = {}
            for n in self.repos:
                rc, out = self.git(n, "worktree", "list", "--porcelain")
                for ln in out.splitlines() if rc == 0 else ():
                    if ln.startswith("worktree "):
                        self._wt[os.path.realpath(ln[9:])] = n
        return self._wt

    def resolve(self, cwd, branch, rels):
        """→ (repo name, how) or (None, why)."""
        if not cwd:
            return None, "no-cwd"
        for n, p in self.repos.items():
            if cwd == p or cwd.startswith(p + "/"):
                return n, "main-checkout"
        wt = self.worktrees()
        for w, n in wt.items():
            if cwd == w or cwd.startswith(w + "/"):
                return n, "worktree"
        if branch and branch not in ("HEAD", "main", "master"):
            hits = [
                n
                for n in self.repos
                if self.git(
                    n, "rev-parse", "--verify", "--quiet", "refs/heads/" + branch
                )[0]
                == 0
                or self.git(
                    n,
                    "rev-parse",
                    "--verify",
                    "--quiet",
                    "refs/remotes/origin/" + branch,
                )[0]
                == 0
            ]
            if len(hits) == 1:
                return hits[0], "branch"
        if rels:
            score = {
                n: sum(
                    1
                    for r in rels
                    if self.git(n, "cat-file", "-e", "origin/main:" + r)[0] == 0
                )
                for n in self.repos
            }
            best = max(score.items(), key=lambda kv: kv[1], default=(None, 0))
            if best[1] > 0 and list(score.values()).count(best[1]) == 1:
                return best[0], "path-evidence"
        return None, "repo-unresolved"

    def trunk_at(self, name, t):
        rc, out = self.git(
            name, "rev-list", "-1", "--before=%d" % int(t), "origin/main"
        )
        return out if rc == 0 and out else None

    def has(self, name, commit, rel):
        rc, _ = self.git(name, "cat-file", "-e", "%s:%s" % (commit, rel))
        if rc == 0:
            return True
        rc, out = self.git(
            name, "ls-tree", "-d", "--name-only", commit, rel.rstrip("/")
        )
        return rc == 0 and bool(out)


def brief_paths(text):
    out = []
    for m in PATH_RX.finditer(text):
        p = m.group(0).rstrip(".:,")
        out.append((m.start(), m.start() + len(p), p))
    return out


def map_paths(brief, cwd, repo, commit, repos, written):
    """→ (mapped brief, outputs [placeholder path], reason or None)."""
    roots_repo = []
    if cwd:
        roots_repo.append(cwd.rstrip("/"))
    if repo:
        roots_repo.append(repos.repos[repo])
    claude_dirs = [
        os.path.join(HOME, d) for d in (".claude",) + tuple(x[1] for x in ROOTS)
    ]
    outs, out_map, pieces, last, outputs = {}, {}, [], 0, []
    for s, e, raw in brief_paths(brief):
        p = os.path.normpath(os.path.expanduser(raw.replace("/private/tmp/", "/tmp/")))
        rel = None
        for r in roots_repo:
            if p == r or p.startswith(r + "/"):
                rel = os.path.relpath(p, r)
                break
        if rel is None and repo == "claude-infrastructure":
            for d in claude_dirs:
                if p.startswith(d + "/"):
                    cand = os.path.relpath(p, d)
                    if repos.has(repo, commit, cand):
                        rel = cand
                    break
        is_out = (
            p in written
            or any(w.startswith(p + "/") for w in written)
            or any(p.startswith(w + "/") for w in written)
        )
        if rel is not None:
            if rel == ".":
                rel = ""
            if not is_out and rel and not repos.has(repo, commit, rel):
                return None, None, "path-not-at-commit"
            mapped = "{{REPO}}" + ("/" + rel if rel else "")
            if is_out:
                outputs.append(mapped)
        elif is_out:
            top = (
                p
                if p in written or any(w.startswith(p + "/") for w in written)
                else os.path.dirname(p)
            )
            k = out_map.setdefault(top, "o%d" % len(out_map))
            mapped = "{{OUT}}/" + k + p[len(top) :]
            outputs.append(mapped)
        else:
            return None, None, ("input-live" if os.path.exists(p) else "input-gone")
        pieces.append(brief[last:s])
        pieces.append(mapped)
        last = e
    pieces.append(brief[last:])
    return "".join(pieces), sorted(set(outputs)), None


# ── the scan ──────────────────────────────────────────────────────────────────────────────────
def scan(S, E, repos=None, shadow_path=None):
    """→ (eligible production cases, Counter of drop reasons, meta)."""
    hook = _hook()
    repos = repos or Repos()
    shadow, skipped = shadow_calls(shadow_path)
    drops = collections.Counter({"shadow-kind:" + k: n for k, n in skipped.items()})
    owner = {}  # agent_id → (mtime, acct, path): the earliest copy owns (cc-token-ledger rule)
    runs = []
    for acct, root in roots():
        for proj, sid, rd in run_dirs(root, S, E):
            runs.append((acct, proj, sid, rd))
    launch_cache, keys_seen, cases = {}, collections.defaultdict(set), []
    for acct, proj, sid, rd in sorted(runs, key=lambda x: os.stat(x[3]).st_mtime):
        run_id = os.path.basename(rd)
        mt = os.path.join(proj, sid + ".jsonl")
        if mt not in launch_cache:
            launch_cache[mt] = launches(mt)
        launch = launch_cache[mt].get(run_id)
        row = shadow.get((launch or {}).get("tool_use_id")) if launch else None
        script = ""
        try:
            with open(os.path.join(proj, sid, "workflows", run_id + ".json")) as fh:
                script = json.load(fh).get("script") or ""
        except (OSError, ValueError):
            pass
        journal, results = [], set()
        try:
            with open(os.path.join(rd, "journal.jsonl")) as fh:
                for ln in fh:
                    try:
                        j = json.loads(ln)
                    except ValueError:
                        continue
                    if j.get("type") == "started":
                        journal.append(j)
                    elif j.get("type") == "result":
                        results.add(j.get("agentId"))
        except OSError:
            continue
        run_resume = bool(launch and launch["resume"]) or bool(
            row and row.get("resume_from_run_id")
        )
        for j in journal:
            aid = j.get("agentId")
            path = os.path.join(rd, "agent-%s.jsonl" % aid)
            if not aid or not os.path.exists(path):
                continue
            pmt = os.stat(path).st_mtime
            if aid in owner and owner[aid][0] <= pmt:
                drops["copy"] += 1
                continue
            owner[aid] = (pmt, acct, path)
            try:
                with open(os.path.join(rd, "agent-%s.meta.json" % aid)) as fh:
                    meta = json.load(fh)
            except (OSError, ValueError):
                meta = {}
            key = j.get("key")
            if run_resume:
                drops["resume"] += 1
                continue
            if key and key in keys_seen[sid]:
                drops["repeat-key"] += 1
                continue
            keys_seen[sid].add(key)
            if meta.get("agentType") != NO_TYPE:
                drops["has-agent-type"] += 1
                continue
            if aid not in results:
                drops["failed"] += 1
                continue
            if "needs-default" in script:
                drops["needs-default"] += 1
                continue
            if row is not None and row.get("would_deny") is False:
                drops["shadow-not-would-deny"] += 1
                continue
            brief, cwd, ts, branch, written, models = read_slot(path)
            if not brief:
                drops["brief-empty"] += 1
                continue
            if len(brief) < MIN_BRIEF:
                drops["probe"] += 1
                continue
            if (cwd or "").startswith(EVAL_CWD) or (cwd or "").startswith(
                "/private" + EVAL_CWD
            ):
                drops["eval"] += 1
                continue
            if any(rx.search(brief) for rx in hook.MARKERS.values()):
                drops["keep-default"] += 1
                continue
            cases.append(
                dict(
                    acct=acct,
                    sid=sid,
                    run_id=run_id,
                    agent_id=aid,
                    label=j.get("label"),
                    ts=ts,
                    cwd=cwd,
                    branch=branch,
                    brief_raw=brief,
                    written=sorted(written),
                    models=sorted(models),
                    tool_use_id=(launch or {}).get("tool_use_id"),
                    shadow=None
                    if row is None
                    else dict(
                        would_deny=row.get("would_deny"),
                        arm=(row.get("arm") or {}).get("arm"),
                    ),
                )
            )
    # owner pass: a later-scanned earlier copy took the agent id; keep only the owner's case
    cases = [
        c for c in cases if owner.get(c["agent_id"], (0, c["acct"]))[1] == c["acct"]
    ]
    out = []
    for c in cases:
        rels = []
        for _s, _e, p in brief_paths(c["brief_raw"]):
            p = os.path.normpath(os.path.expanduser(p))
            if c["cwd"] and p.startswith(c["cwd"].rstrip("/") + "/"):
                rels.append(os.path.relpath(p, c["cwd"]))
        repo, how = repos.resolve(c["cwd"], c["branch"], rels[:20])
        t = ep(c["ts"]) or 0
        commit = repos.trunk_at(repo, t) if repo else None
        if repo and not commit:
            drops["repo-unresolved"] += 1
            continue
        if repo is None and rels:
            drops[how] += 1
            continue
        if repo is None:
            how = "none"
        brief, outputs, why = map_paths(
            c["brief_raw"], c["cwd"], repo, commit, repos, set(c["written"])
        )
        if why:
            drops[why] += 1
            continue
        out.append(
            dict(
                case_id="p-" + c["agent_id"],
                cluster=c["run_id"],
                src="prod",
                acct=c["acct"],
                sid=c["sid"],
                run_id=c["run_id"],
                agent_id=c["agent_id"],
                label=c["label"],
                ts=c["ts"],
                repo=repo,
                repo_how=how,
                commit=commit,
                brief=brief,
                brief_sha=hashlib.sha256(c["brief_raw"].encode("utf-8")).hexdigest()[
                    :16
                ],
                outputs=outputs,
                schema=False,
                models=c["models"],
                tool_use_id=c["tool_use_id"],
                shadow=c["shadow"],
            )
        )
    meta = dict(
        n_runs=len(runs),
        n_eligible=len(out),
        drops=dict(sorted(drops.items())),
        shadow_calls=len(shadow),
    )
    return out, drops, meta


# ── F2 ───────────────────────────────────────────────────────────────────────────────────────
def f2_cases(f2_dir=F2_DIR):
    """F2's 10 briefs, parsed from f2/workflow.js (the same parse f2/collect.py uses), with ${T} and
    ${F} mapped to the fixture: {{FIX}} is the materialized $GATE_ROOT/f2."""
    with open(os.path.join(f2_dir, "workflow.js")) as fh:
        wf = fh.read()
    out = []
    for m in re.finditer(r"\{ id: '(B\d\d)', text: `(.*?)` \}", wf, re.S):
        text = (
            m.group(2)
            .replace("${T}", "{{FIX}}/tree")
            .replace("${F}", "{{FIX}}")
            .replace("\\$", "$")
        )
        out.append(
            dict(
                case_id="f2-" + m.group(1),
                cluster="f2-" + m.group(1),
                src="f2",
                acct="f2",
                brief=text,
                repo="claude-infrastructure",
                commit=F2_SHA,
                outputs=[],
                schema=True,
                f2_id=m.group(1),
                brief_sha=hashlib.sha256(text.encode("utf-8")).hexdigest()[:16],
            )
        )
    return out


def half(c):
    return (
        "test"
        if int(hashlib.sha1(c["case_id"].encode("utf-8")).hexdigest(), 16) % 5 == 0
        else "train"
    )


def sample(prod, f2, n=HALF_N, per_run=MAX_PER_RUN):
    """F2 first, then production round-robin over accounts (case order by sha1), at most per_run
    slots per Workflow run, until each half holds n."""
    got = {"train": [], "test": []}
    for c in f2:
        got[half(c)].append(c)
    by_acct = collections.defaultdict(lambda: {"train": [], "test": []})
    for c in sorted(
        prod, key=lambda c: hashlib.sha1(c["case_id"].encode()).hexdigest()
    ):
        by_acct[c["acct"]][half(c)].append(c)
    per = collections.Counter()
    for h in ("train", "test"):
        queues = [by_acct[a][h] for a in sorted(by_acct)]
        while len(got[h]) < n and any(queues):
            for q in queues:
                while q and len(got[h]) < n:
                    c = q.pop(0)
                    if per[(c["run_id"], h)] < per_run:
                        per[(c["run_id"], h)] += 1
                        got[h].append(c)
                        break
    return got["train"] + got["test"]


def build(days=28.0, start=None, end=None, take_all=False, repos=None):
    E = end if end is not None else time.time()
    S = start if start is not None else E - days * 86400
    prod, drops, meta = scan(S, E, repos=repos)
    f2 = f2_cases()
    cases = prod + f2 if take_all else sample(prod, f2)
    meta.update(
        start=S,
        end=E,
        days=(E - S) / 86400,
        n_f2=len(f2),
        n_cases=len(cases),
        n_train=sum(1 for c in cases if half(c) == "train"),
        n_test=sum(1 for c in cases if half(c) == "test"),
        by_acct=dict(collections.Counter(c["acct"] for c in cases)),
        sampled=not take_all,
        half_n=HALF_N,
        max_per_run=MAX_PER_RUN,
    )
    return cases, meta


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--days", type=float, default=28.0)
    ap.add_argument("--start", type=float)
    ap.add_argument("--end", type=float)
    ap.add_argument(
        "--all", action="store_true", help="every eligible case, no sampling"
    )
    a = ap.parse_args(argv)
    cases, meta = build(a.days, a.start, a.end, a.all)
    with open(a.out, "w") as fh:
        for c in cases:
            fh.write(json.dumps(c, sort_keys=True) + "\n")
    print(json.dumps(meta, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
