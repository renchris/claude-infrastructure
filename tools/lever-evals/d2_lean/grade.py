#!/usr/bin/env python3
"""grade.py — d2-lean's grader (plan § W7+ §2 D2 "Grader"; §3 "Judge"; wave S10). Code first, the
judge only for what code cannot see.

PER ANSWER (one agent() slot of one variant, rep and block):
  status      ok | error (journal `failed`, or no transcript) | served-model (a response not from
              the model under test) | truncated (stop_reason max_tokens). Anything but ok is
              PLUMBING: it goes to the error count, re-queued by a later run, never scored.
  facts       key.json's facts, checked BY CODE: each check_cmd runs once per case on the frozen
              fixture (cwd = the fixture root) and its stdout is the expected value; an answer
              passes a fact when it states that value ("number": the number appears among the
              answer's numbers; "substring": case-insensitive, whitespace-collapsed; "field": F2's
              structured `numbers[field]` equals it, f2/collect.py's rule). The answer is the final
              text plus every file the slot wrote under its OUT dir.
  forbidden   writes outside the slot's OUT dir and the outputs its brief names: Write/Edit/
              NotebookEdit paths and literal Bash targets (f2/collect.py's WRITE_BASH), plus `git
              status` of the run's fixture clone (the clone is a one-commit git repo).
  asks        one blind dossier per ask {ask, answer} for cc-lever-judge's d2_quality rubric
              (complete=Y and fabricated=N), redacted: the run's paths become <work> and agent-type
              names <agent>; ids are opaque hashes. Judged rows are read back from lever-judge.jsonl
              (kind=judged, rubric d2_quality) — a VOID or refused batch leaves the asks pending.
  pass        status ok AND every fact passes AND no forbidden write AND every ask judged pass;
              null while an ask is pending.
  cost        the a4c54d1744d1 cost rule: requests = distinct requestId on assistant records, each
              request's usage fields the max over its records; pp = (0.245 x (cache write + input)
              + read x cache read + 0.404 x output) / 1e6, read 0.0057 / 0.0067 / 0.0076 (lo/mid/hi).

usage: python3 -I grade.py <run dir> [--key KEY] [--no-judge] [--seed N] [--judge-max N]
       (normally through `cc-lever-eval grade d2_lean --tag <tag>`)
Writes <run dir>/graded.jsonl and prints a one-line summary. Stdlib only, Python 3.9-safe.
"""

import argparse
import collections
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
MODEL = "claude-opus-5-5"
W_READ = {"lo": 0.0057, "mid": 0.0067, "hi": 0.0076}
W_WRITE, W_OUT = 0.245, 0.404
# f2/collect.py's literal write targets, with two fixes the first smoke forced (2026-10-25: a default
# slot's own `cat > out/answer.md <<'EOF'` was flagged for "-> /agentsync.lock" in its prose): a
# heredoc's body is data, not command text, and `->` / `=>` are arrows, not redirects
WRITE_BASH = re.compile(
    r"((?<![-=])>>?|\btee(?:\s+-a)?|\bmkdir(?:\s+-p)?|\btouch)\s*([~/][\w./@+~-]+)"
)
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][\w-]*)\1")


def strip_heredocs(cmd):
    """The command text with every heredoc body removed (the opener line is kept)."""
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        out.append(lines[i])
        ends = [m.group(2) for m in HEREDOC.finditer(lines[i])]
        i += 1
        for tag in ends:
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
            i += 1
    return "\n".join(out)


def bash_write_targets(cmd):
    """Absolute (or ~) paths a Bash command literally writes: redirect, tee, mkdir, touch."""
    return [m.group(2) for m in WRITE_BASH.finditer(strip_heredocs(cmd or ""))]
NUM = re.compile(r"(?<![\w.])-?\d[\d,]*(?:\.\d+)?")
ANSWER_CAP = 200_000
DOSSIER_ANSWER_CAP = 12_000
CHECK_TIMEOUT_S = 60
REDACT = re.compile(
    r"workflow-lean|workflow-subagent|general-purpose|omitClaudeMd|agentType", re.I
)


# ── one slot ───────────────────────────────────────────────────────────────────────────────────
def slot(path):
    """→ dict: requests, pp lo/mid/hi, tokens, models, truncated, final text, structured return,
    write paths. Usage per the cost rule (distinct requestId, max over the request's records)."""
    req = collections.OrderedDict()
    models, calls, so = set(), [], []
    results, final, truncated = {}, "", False
    with open(path, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            m = r.get("message") or {}
            if r.get("type") == "assistant":
                if m.get("model") and m["model"] != "<synthetic>":
                    models.add(m["model"])
                if m.get("stop_reason") == "max_tokens":
                    truncated = True
                u = m.get("usage") or {}
                rid = r.get("requestId") or m.get("id")
                cur = dict(
                    inp=u.get("input_tokens") or 0,
                    cw=u.get("cache_creation_input_tokens") or 0,
                    cr=u.get("cache_read_input_tokens") or 0,
                    out=u.get("output_tokens") or 0,
                )
                if rid in req:
                    req[rid] = {k: max(req[rid][k], cur[k]) for k in cur}
                elif rid:
                    req[rid] = cur
                for b in m.get("content") or []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use":
                        calls.append((b.get("id"), b.get("name"), b.get("input") or {}))
                        if b.get("name") == "StructuredOutput":
                            so.append(b.get("id"))
                    elif b.get("type") == "text" and b.get("text"):
                        final = b["text"]
            elif r.get("type") == "user" and isinstance(m.get("content"), list):
                for b in m["content"]:
                    if isinstance(b, dict) and b.get("type") == "tool_result":
                        results[b.get("tool_use_id")] = bool(b.get("is_error"))
    tot = {k: sum(x[k] for x in req.values()) for k in ("inp", "cw", "cr", "out")}
    pp = {
        e: (W_WRITE * (tot["cw"] + tot["inp"]) + w * tot["cr"] + W_OUT * tot["out"])
        / 1e6
        for e, w in W_READ.items()
    }
    first = next(iter(req.values()), dict(inp=0, cw=0, cr=0))
    ret = None
    for cid in reversed(so):
        if not results.get(cid, True):
            ret = next(i for c, n, i in calls if c == cid)
            break
    writes = []
    for _cid, name, inp in calls:
        if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
            writes.append(inp.get("file_path") or inp.get("notebook_path") or "")
        elif name == "Bash":
            writes += bash_write_targets(inp.get("command"))
    return dict(
        requests=len(req),
        pp=pp,
        tokens=tot,
        first_input_side=first["inp"] + first["cw"] + first["cr"],
        models=sorted(models),
        truncated=truncated,
        final=final,
        ret=ret,
        writes=[w for w in writes if w],
        tool_calls=len(calls),
    )


def answer_text(final, ret, out_dir):
    parts = [final or ""]
    if ret:
        parts.append(json.dumps(ret, sort_keys=True))
    n = sum(len(p) for p in parts)
    for dp, _dn, fns in (
        sorted(os.walk(out_dir)) if out_dir and os.path.isdir(out_dir) else ()
    ):
        for fn in sorted(fns):
            if n >= ANSWER_CAP:
                break
            try:
                with open(
                    os.path.join(dp, fn), encoding="utf-8", errors="replace"
                ) as fh:
                    t = fh.read(ANSWER_CAP - n)
            except OSError:
                continue
            parts.append(
                "--- %s ---\n%s" % (os.path.relpath(os.path.join(dp, fn), out_dir), t)
            )
            n += len(t)
    return "\n".join(parts)


# ── facts ──────────────────────────────────────────────────────────────────────────────────────
def run_check(cmd, root, timeout=CHECK_TIMEOUT_S):
    """→ (ok, value): the first non-empty stdout line of `bash -c cmd` in root."""
    try:
        p = subprocess.run(
            ["/bin/bash", "-c", cmd],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (subprocess.TimeoutExpired, OSError) as e:
        return False, "check error: %s" % e.__class__.__name__
    lines = [ln.strip() for ln in p.stdout.splitlines() if ln.strip()]
    if p.returncode != 0 or not lines:
        return False, "check exit %d, %d line(s)" % (p.returncode, len(lines))
    return True, lines[0]


def _num(s):
    try:
        v = float(str(s).replace(",", ""))
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def numbers_in(text):
    return {v for v in (_num(m.group(0)) for m in NUM.finditer(text)) if v is not None}


def fact_ok(fact, truth, answer, ret_numbers):
    """One fact against one answer. truth: the check's value (or the key's literal `expect`)."""
    m = fact.get("match")
    if m == "field":
        got = (ret_numbers or {}).get(fact["field"])
        alts = [truth] + list(fact.get("alt") or [])
        return any(str(got).lstrip("0") == str(t).lstrip("0") for t in alts)
    if m == "number":
        t = _num(truth)
        return t is not None and t in numbers_in(answer)
    norm = lambda s: re.sub(r"\s+", " ", str(s)).strip().lower()  # noqa: E731
    return bool(norm(truth)) and norm(truth) in norm(answer)


# ── forbidden writes ───────────────────────────────────────────────────────────────────────────
def forbidden(writes, out_dir, clone, allowed_rel):
    bad = []
    allowed = [os.path.realpath(out_dir)] if out_dir else []
    allowed += (
        [os.path.realpath(os.path.join(clone, r)) for r in allowed_rel] if clone else []
    )
    for w in writes:
        if not w.startswith("/") or w.startswith("/dev/"):
            continue
        rw = os.path.realpath(w)
        if not any(rw == a or rw.startswith(a + "/") for a in allowed):
            bad.append(w)
    if clone and os.path.isdir(os.path.join(clone, ".git")):
        p = subprocess.run(
            ["git", "-C", clone, "status", "--porcelain", "--untracked-files=all"],
            capture_output=True,
            text=True,
        )
        for ln in p.stdout.splitlines():
            rel = ln[3:].strip().strip('"')
            if not any(
                rel == a or rel.startswith(a.rstrip("/") + "/") for a in allowed_rel
            ):
                bad.append("git:" + rel)
    return sorted(set(bad))


# ── judge ──────────────────────────────────────────────────────────────────────────────────────
def redact(text, roots):
    for r in sorted((x for x in roots if x), key=len, reverse=True):
        text = text.replace(r, "<work>")
    return REDACT.sub("<agent>", text)


def dossier_id(tag, case_id, variant, rep, i):
    return hashlib.sha1(
        ("%s:%s:%s:%s:%d" % (tag, case_id, variant, rep, i)).encode()
    ).hexdigest()[:20]


def judge_log():
    d = os.environ.get("CC_LEVER_LOG_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude", "logs"
    )
    return os.path.join(d, "lever-judge.jsonl")


def judged(ids):
    """→ {dossier id: pass} from lever-judge.jsonl (kind=judged, rubric d2_quality)."""
    out = {}
    try:
        fh = open(judge_log(), encoding="utf-8", errors="replace")
    except OSError:
        return out
    with fh:
        for ln in fh:
            if '"d2_quality"' not in ln:
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if (
                r.get("kind") == "judged"
                and r.get("rubric") == "d2_quality"
                and r.get("id") in ids
            ):
                out[r["id"]] = bool(r.get("pass"))
    return out


def run_judge(dossiers, path, seed):
    """→ exit code of `cc-lever-judge run d2_quality --write` over the dossiers (0 held, 1 VOID,
    3 refused, 4 plumbing). CC_LEVER_JUDGE_BIN overrides the binary (tests stub it)."""
    with open(path, "w") as fh:
        for d in dossiers:
            fh.write(json.dumps(d, sort_keys=True) + "\n")
    exe = os.environ.get("CC_LEVER_JUDGE_BIN") or os.path.join(
        REPO_ROOT, "bin", "cc-lever-judge"
    )
    p = subprocess.run(
        [
            sys.executable,
            "-I",
            exe,
            "run",
            "d2_quality",
            "--dossiers",
            path,
            "--seed",
            str(seed),
            "--write",
        ],
        capture_output=True,
        text=True,
    )
    sys.stderr.write(p.stderr[-600:])
    return p.returncode


# ── the grade ──────────────────────────────────────────────────────────────────────────────────
def load_key(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def grade(run_dir, key, judge=True, seed=0, judge_max=40):
    """→ (graded rows, summary). positions.jsonl (written by the driver) names, per process, the
    variant, rep, block, its workflow transcript dir and, per case, the OUT dir and fixture paths."""
    pos = [
        json.loads(ln)
        for ln in open(os.path.join(run_dir, "positions.jsonl"))
        if ln.strip()
    ]
    tag = os.path.basename(run_dir.rstrip("/"))
    truth_cache, rows, pending = {}, [], []
    for p in pos:
        cases = {c["case_id"]: c for c in p.get("cases") or []}
        labels, failed = {}, set()
        try:
            with open(os.path.join(p.get("wf_dir") or "", "journal.jsonl")) as fh:
                for ln in fh:
                    j = json.loads(ln)
                    if j.get("type") == "started" and str(
                        j.get("label", "")
                    ).startswith("d2:"):
                        labels[j["agentId"]] = j["label"]
                    elif j.get("type") == "failed":
                        failed.add(j.get("agentId"))
        except (OSError, ValueError, TypeError):
            pass
        seen = set()
        for aid, label in sorted(labels.items(), key=lambda kv: kv[1]):
            _d2, variant, case_id, rep = label.split(":")
            c = cases.get(case_id)
            if c is None:
                continue
            seen.add(case_id)
            base = dict(
                case_id=case_id,
                acct=c.get("acct"),
                cluster=c.get("cluster"),
                block=p["block"],
                pos=p["pos"],
                variant=variant,
                rep=int(rep[1:]),
                agent_id=aid,
            )
            tp = os.path.join(p["wf_dir"], "agent-%s.jsonl" % aid)
            if aid in failed or not os.path.exists(tp):
                rows.append(dict(base, status="error", passed=None))
                continue
            s = slot(tp)
            status = "ok"
            if s["truncated"]:
                status = "truncated"
            elif any(m != MODEL for m in s["models"]) or not s["models"]:
                status = "served-model"
            ans = answer_text(s["final"], s["ret"], c.get("out"))
            k = key.get(case_id) or {}
            facts = []
            for i, f in enumerate(k.get("facts") or []):
                tk = (case_id, i)
                if tk not in truth_cache:
                    truth_cache[tk] = (
                        (True, f["expect"])
                        if "expect" in f
                        else run_check(f["check_cmd"], c.get("fixture_root") or "/")
                    )
                ok_t, tv = truth_cache[tk]
                facts.append(
                    bool(ok_t) and fact_ok(f, tv, ans, (s["ret"] or {}).get("numbers"))
                )
            bad = forbidden(
                s["writes"], c.get("out"), c.get("clone"), c.get("allowed_rel") or []
            )
            asks = k.get("asks") or []
            ids = [dossier_id(tag, case_id, variant, rep, i) for i in range(len(asks))]
            roots = [
                c.get("out"),
                c.get("clone"),
                c.get("fixture_root"),
                p.get("workdir"),
            ]
            code_ok = status == "ok" and all(facts) and not bad
            # only an answer code could not fail goes to the judge: the judge never rescues a fact
            for i, a in enumerate(asks if code_ok else ()):
                pending.append(
                    dict(
                        id=ids[i],
                        sid=p.get("sid"),
                        sections=dict(
                            ask=redact(a, roots),
                            answer=redact(ans, roots)[:DOSSIER_ANSWER_CAP],
                        ),
                    )
                )
            rows.append(
                dict(
                    base,
                    status=status,
                    facts_n=len(facts),
                    facts_ok=sum(facts),
                    forbidden=bad,
                    ask_ids=ids,
                    requests=s["requests"],
                    pp_lo=round(s["pp"]["lo"], 6),
                    pp=round(s["pp"]["mid"], 6),
                    pp_hi=round(s["pp"]["hi"], 6),
                    first_input_side=s["first_input_side"],
                    models=s["models"],
                    tool_calls=s["tool_calls"],
                )
            )
        for case_id in cases:
            if case_id not in seen:
                rows.append(
                    dict(
                        case_id=case_id,
                        acct=cases[case_id].get("acct"),
                        block=p["block"],
                        pos=p["pos"],
                        variant=p["variant"],
                        rep=p["rep"],
                        status="error",
                        passed=None,
                        why="no slot",
                    )
                )
    have = judged({d["id"] for d in pending})
    todo = [d for d in pending if d["id"] not in have]
    judge_rc = None
    if judge and todo:
        judge_rc = run_judge(
            todo[:judge_max], os.path.join(run_dir, "dossiers.jsonl"), seed
        )
        have = judged({d["id"] for d in pending})
    for r in rows:
        if r["status"] != "ok":
            r["passed"] = None
            continue
        js = [have.get(i) for i in r.get("ask_ids") or []]
        code_ok = r["facts_ok"] == r["facts_n"] and not r["forbidden"]
        if not code_ok:
            r["passed"] = False  # code already failed it: the judge cannot rescue it
        elif any(j is None for j in js):
            r["passed"] = None
            r["pending"] = sum(1 for j in js if j is None)
        else:
            r["passed"] = all(js)
        r["asks_pass"] = sum(1 for j in js if j)
    with open(os.path.join(run_dir, "graded.jsonl"), "w") as fh:
        for r in rows:
            fh.write(json.dumps(r, sort_keys=True) + "\n")
    st = collections.Counter(r["status"] for r in rows)
    summ = dict(
        rows=len(rows),
        status=dict(st),
        passed=sum(1 for r in rows if r.get("passed") is True),
        failed=sum(1 for r in rows if r.get("passed") is False),
        pending=sum(1 for r in rows if r["status"] == "ok" and r.get("passed") is None),
        dossiers=len(pending),
        judged=len(have),
        judge_rc=judge_rc,
    )
    return rows, summ


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("run_dir")
    ap.add_argument("--key")
    ap.add_argument("--no-judge", action="store_true")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--judge-max", type=int, default=40)
    a = ap.parse_args(argv)
    kp = a.key or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(a.run_dir))), "key.json"
    )
    _rows, summ = grade(a.run_dir, load_key(kp), not a.no_judge, a.seed, a.judge_max)
    print(json.dumps(summ, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
