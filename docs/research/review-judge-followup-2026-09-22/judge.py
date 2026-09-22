#!/usr/bin/env python3
"""judge.py — COPY of docs/research/opus55-effort-sweep-2026-09-22/judge.py for the review-judge follow-up.

Changed ONLY: the arm map (5 arms x 3 samples), the panel list (P1 = 3x claude-opus-5 @xhigh, the
standing panel; P2 = one judge per model family), one prompt per (panel, judge, brief, SAMPLE)
holding that sample's 5 arm outputs, and the bookkeeping that follows. RULES, build(), the JSON
reply parse and the strict-majority vote are byte-identical to 09-22 (and so to 09-10).

  judge.py run <panel> <scores.jsonl> [samples]   # panel P1 or P2; samples default "2,3" (P1) / "1,2,3" (P2)
"""

import json, os, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import random

HERE = Path(__file__).resolve().parent
CORPUS = HERE.parents[2] / "tests/fixtures/codex-probe"
R0922 = HERE.parent / "opus55-effort-sweep-2026-09-22" / "runs"
R0910 = HERE.parent / "fable51-effort-sweep-2026-09-10" / "runs"
# arm -> (run subdir for samples 2/3, effort, sample-1 path template already on trunk)
ARMS = {
    "o55@high": ("o55", "high", R0922 / "o55" / "{b}__high.md"),
    "o55@xhigh": ("o55", "xhigh", R0922 / "o55" / "{b}__xhigh.md"),
    "o5@high": ("o5", "high", R0922 / "o5" / "{b}__high.md"),
    "o5@max": ("o5", "max", CORPUS / "runs" / "{b}__D.md"),  # W2 arm D
    "f51@high": ("f51", "high", R0910 / "{b}__high.md"),
}
H280 = str(Path.home() / ".claude-280/node_modules/.bin/claude")
H260 = str(Path.home() / ".claude-260/node_modules/.bin/claude")
# P1 keeps the 09-22 panel exactly (model, effort, binary). P2 needs 2.1.280: 2.1.260 refuses opus-5-5.
PANELS = {
    "P1": [(f"p1-{j}", "claude-opus-5", "xhigh", H260) for j in (1, 2, 3)],
    "P2": [("o5", "claude-opus-5", "xhigh", H280), ("o55", "claude-opus-5-5", "xhigh", H280),
           ("f51", "claude-fable-5-1", "high", H280)],
}
CFG = os.environ.get("JUDGE_CONFIG_DIR", str(Path.home() / ".claude-next"))

RULES = """You are scoring code-review outputs against a KNOWN answer key. Default to refute.

For each labelled output, decide for EVERY ground-truth item whether the output identifies that
defect. Credit an item ONLY when the output names the same MECHANISM — why the code does the wrong
thing — not merely the same line, function or topic. A finding about an adjacent weaker problem on
the right line is NOT a hit. A finding that states the mechanism in different words IS a hit.
Judge each output independently; do not let one output's wording decide another's.

Also count how many distinct defects each output reports in total (hits and non-hits alike).

Reply with ONLY one fenced ```json block of this exact shape, one entry per label:
{"scores": [{"label": "O1", "credited": [1, 4], "reported": 7, "why": "<=40 words"}]}
Ground-truth items are numbered from 1 in the order given."""


def path(arm, s, b):
    sub, eff, s1 = ARMS[arm]
    return Path(str(s1).format(b=b)) if s == 1 else HERE / "runs" / sub / f"s{s}" / f"{b}__{eff}.md"


def manifest():
    return {r["id"]: r for r in json.loads((CORPUS / "manifest.json").read_text())}


def build(brief, gt, texts, seed):
    names = sorted(texts)
    random.Random(seed).shuffle(names)
    key = {f"O{i + 1}": n for i, n in enumerate(names)}
    parts = [
        RULES,
        "\n=== THE REVIEW BRIEF (the code under review) ===\n",
        brief,
        "\n=== GROUND TRUTH (the answer key) ===\n",
    ]
    for i, g in enumerate(gt, 1):
        parts.append(f"{i}. [{g['file']}:{g.get('line_hint', '?')}] {g['defect']}\n")
    for label, name in key.items():
        parts.append(f"\n=== OUTPUT {label} ===\n{texts[name] or '(empty output)'}\n")
    return "".join(parts), key


def call(prompt, model, effort, binary):
    d = tempfile.mkdtemp(prefix="rvw.", dir="/private/tmp")
    env = dict(os.environ, CLAUDE_CONFIG_DIR=CFG, CLAUDE_CODE_MAX_OUTPUT_TOKENS="64000")
    p = subprocess.run(
        [binary, "-p", "--model", model, "--effort", effort, "--tools", "", "--setting-sources", "",
         "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
         "--output-format", "json"],
        input=prompt, capture_output=True, text=True, cwd=d, env=env,
    )
    os.rmdir(d)
    try:
        return json.loads(p.stdout)
    except ValueError:
        return {"result": "", "is_error": True, "stderr": p.stderr[-500:], "stdout": p.stdout[-500:]}


def judge_one(job):
    panel, jid, model, effort, binary, bid, s, prompt, key = job
    raw = call(prompt, model, effort, binary)
    u = raw.get("usage") or {}
    meta = {"panel": panel, "judge": jid, "judge_model": model, "judge_effort": effort, "sample": s,
            "brief_id": bid, "judge_cost_usd": raw.get("total_cost_usd"),
            "judge_out": u.get("output_tokens"), "judge_cc": u.get("cache_creation_input_tokens"),
            "judge_api_error_status": raw.get("api_error_status"), "judge_is_error": raw.get("is_error")}
    m = re.search(r"```json\s*(\{.*?\})\s*```", raw.get("result", ""), re.S)
    if not m:
        return [dict(meta, error="no json", result=(raw.get("result") or str(raw))[:500])]
    rows = []
    for sc in json.loads(m.group(1))["scores"]:
        rows.append(dict(meta, arm=key[sc["label"]], label=sc["label"],
                         credited=sorted(set(sc["credited"])), reported=sc.get("reported"),
                         why=sc.get("why", "")))
    return rows


QUOTA_MSG_LEN = (
    63  # len("You've hit your session limit · resets 1:10pm (America/Chicago)")
)
OUTPUT_CAP = 128000  # CLAUDE_CODE_MAX_OUTPUT_TOKENS every cell ran under


def is_quota(r):
    """A 429 "session limit" is a QUOTA fault, not an arm outcome — never an arm's error.

    Two signatures, because the runner only started recording api_error_status after the first
    wall: an explicit 429, or (first-runner rows) an error with no status whose result is exactly
    the session-limit message. A quota fault can arrive AFTER a full 128K-token stream, so
    "something was served" does NOT make an error an arm outcome — classify on the error, never
    on what was spent.
    """
    if r.get("api_error_status") == 429:
        return True
    return (
        bool(r.get("is_error"))
        and r.get("api_error_status") is None
        and "api_error_status" not in r
        and r.get("result_len") == QUOTA_MSG_LEN
    )


def unmeasured(arm, s, b):
    """A sample-2/3 cell whose latest index row is a quota fault is UNMEASURED, never scored 0."""
    if s == 1:
        return False
    sub, eff, _ = ARMS[arm]
    idx = HERE / "runs" / sub / f"s{s}" / "index.jsonl"
    rows = [json.loads(l) for l in open(idx) if l.strip()] if idx.exists() else []
    rows = [r for r in rows if r.get("brief_id") == b and r.get("effort") == eff]
    return not rows or is_quota(rows[-1])


def jobs_for(panel, samples, only=None):
    man, jobs = manifest(), []
    for bid, rec in sorted(man.items()):
        if not rec["has_defect"]:
            continue
        brief = (CORPUS / "briefs" / f"{bid}.md").read_text()
        for s in samples:
            texts = {a: path(a, s, bid).read_text() for a in ARMS if not unmeasured(a, s, bid)}
            for jid, model, effort, binary in PANELS[panel]:
                if only and (jid, bid, s) not in only:
                    continue
                prompt, key = build(brief, rec["ground_truth"], texts, f"{panel}/{bid}/s{s}/{jid}")
                jobs.append((panel, jid, model, effort, binary, bid, s, prompt, key))
    return jobs


def run(panel, scores, samples):
    jobs = jobs_for(panel, samples)
    with ThreadPoolExecutor(int(os.environ.get("JUDGE_PAR", "5"))) as ex, open(scores, "a") as fh:
        for rows in ex.map(judge_one, jobs):
            for r in rows:
                fh.write(json.dumps(r) + "\n")
                fh.flush()


if __name__ == "__main__":
    a = sys.argv[2:] if sys.argv[1] == "run" else sys.argv[1:]
    panel, scores = a[0], a[1]
    samples = [int(x) for x in (a[2] if len(a) > 2 else ("2,3" if panel == "P1" else "1,2,3")).split(",")]
    run(panel, scores, samples)
