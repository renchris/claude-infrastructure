#!/usr/bin/env python3
"""judge.py — blind, anchored ground-truth scoring of the Fable 5.1 effort sweep.

Per defect brief, every arm's verbatim output is shown to each judge under a label that is
re-shuffled per (brief, judge); the label→arm key never reaches a judge. A judge sees the brief,
the ground-truth list and the labelled outputs — no tools, no repo, no memory — and credits a
ground-truth item only when the output names its MECHANISM, not merely its topic (the W3 rule,
docs/research/codex-probe-w3-verdict-2026-08-11.md). Anchored scoring is the axis W3 measured as
judge-vendor-independent (98% cross vs 99% within), which is why a single-vendor panel is used here.

  judge.py run   <runs-dir> <scores.jsonl>      # 3 judges x 7 defect briefs
  judge.py table <runs-dir> <scores.jsonl>      # recall per arm, by vote threshold, + cost
"""

import json, os, random, re, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS = HERE.parents[2] / "tests/fixtures/codex-probe"
EFFORTS = ["low", "medium", "high", "xhigh", "max"]
# Reference arms already on trunk, from W2 (2026-08-11): Fable 5 @xhigh and Opus 5 @max.
REFS = {"f5@xhigh": "A", "o5@max": "D"}
JUDGES = 3
BIN = os.environ.get(
    "JUDGE_BIN", str(Path.home() / ".claude-260/node_modules/.bin/claude")
)
CFG = os.environ.get("JUDGE_CONFIG_DIR", str(Path.home() / ".claude-tertiary"))
MODEL = os.environ.get("JUDGE_MODEL", "claude-opus-5")
EFFORT = os.environ.get("JUDGE_EFFORT", "xhigh")  # effort_defaults.verify_judge

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


def arms(runs):
    out = {f"f51@{e}": runs / f"{{b}}__{e}.md" for e in EFFORTS}
    for name, letter in REFS.items():
        out[name] = CORPUS / "runs" / f"{{b}}__{letter}.md"
    return out


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


def call(prompt):
    d = tempfile.mkdtemp(prefix="rvw.", dir="/private/tmp")
    env = dict(os.environ, CLAUDE_CONFIG_DIR=CFG, CLAUDE_CODE_MAX_OUTPUT_TOKENS="64000")
    p = subprocess.run(
        [
            BIN,
            "-p",
            "--model",
            MODEL,
            "--effort",
            EFFORT,
            "--tools",
            "",
            "--setting-sources",
            "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--output-format",
            "json",
        ],
        input=prompt,
        capture_output=True,
        text=True,
        cwd=d,
        env=env,
    )
    os.rmdir(d)
    return json.loads(p.stdout)


def judge_one(job):
    bid, j, prompt, key = job
    raw = call(prompt)
    m = re.search(r"```json\s*(\{.*?\})\s*```", raw.get("result", ""), re.S)
    rows = []
    if not m:
        return [
            {
                "brief_id": bid,
                "judge": j,
                "error": "no json",
                "result": raw.get("result", "")[:500],
            }
        ]
    for s in json.loads(m.group(1))["scores"]:
        rows.append(
            {
                "brief_id": bid,
                "judge": j,
                "arm": key[s["label"]],
                "label": s["label"],
                "credited": sorted(set(s["credited"])),
                "reported": s.get("reported"),
                "why": s.get("why", ""),
                "judge_cost_usd": raw.get("total_cost_usd"),
            }
        )
    return rows


def run(runs, scores):
    man, jobs = manifest(), []
    for bid, rec in sorted(man.items()):
        if not rec["has_defect"]:
            continue
        brief = (CORPUS / "briefs" / f"{bid}.md").read_text()
        texts = {
            n: Path(str(p).format(b=bid)).read_text() for n, p in arms(runs).items()
        }
        for j in range(1, JUDGES + 1):
            prompt, key = build(brief, rec["ground_truth"], texts, f"{bid}/{j}")
            jobs.append((bid, j, prompt, key))
    with (
        ThreadPoolExecutor(int(os.environ.get("JUDGE_PAR", "5"))) as ex,
        open(scores, "a") as fh,
    ):
        for rows in ex.map(judge_one, jobs):
            for r in rows:
                fh.write(json.dumps(r) + "\n")
                fh.flush()


QUOTA_MSG_LEN = (
    63  # len("You've hit your session limit · resets 1:10pm (America/Chicago)")
)
OUTPUT_CAP = 64000  # CLAUDE_CODE_MAX_OUTPUT_TOKENS every cell ran under


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


def cells(runs):
    """Latest non-quota row per (brief, effort). A cell with no such row is UNMEASURED."""
    raw = [
        json.loads(line) for line in open(Path(runs) / "index.jsonl") if line.strip()
    ]
    latest = {}
    for r in raw:
        if not is_quota(r):
            latest[(r["brief_id"], r["effort"])] = r
    return raw, latest


def table(runs, scores):
    man = manifest()
    raw, latest = cells(runs)
    rows = [json.loads(line) for line in open(scores) if line.strip()]
    bad = [r for r in rows if "error" in r]
    names = [f"f51@{e}" for e in EFFORTS] + list(REFS)

    def measured(bid, arm):
        return not arm.startswith("f51@") or (bid, arm[4:]) in latest

    votes = {}
    for r in rows:
        if "error" in r or not measured(r["brief_id"], r["arm"]):
            continue
        for g in r["credited"]:
            votes.setdefault((r["brief_id"], r["arm"], g), set()).add(r["judge"])
    defect = {b: v for b, v in sorted(man.items()) if v["has_defect"]}
    paired = [b for b in defect if all(measured(b, n) for n in names)]
    total = sum(len(v["ground_truth"]) for v in defect.values())

    def hits(bid, n, t=2):
        return sum(
            1 for (b, a, _), js in votes.items() if b == bid and a == n and len(js) >= t
        )

    print(f"judge rows {len(rows)} · parse failures {len(bad)} · ground truth {total}")
    print(
        f"index rows {len(raw)} · quota-fault rows set aside {sum(map(is_quota, raw))}"
        f" · cells kept {len(latest)} · paired briefs (every arm measured) {paired}\n"
    )
    print(
        "Recall, strict majority (>=2 of 3 judges). `—` = unmeasured (quota fault, never scored 0).\n"
    )
    print("| brief | GT | " + " | ".join(names) + " |")
    print("|---|---|" + "---|" * len(names))
    for bid, rec in defect.items():
        c = [str(hits(bid, n)) if measured(bid, n) else "—" for n in names]
        print(f"| {bid} | {len(rec['ground_truth'])} | " + " | ".join(c) + " |")
    for label, briefs in [("TOTAL (measured)", list(defect)), ("PAIRED", paired)]:
        gt = sum(len(defect[b]["ground_truth"]) for b in briefs)
        c = []
        for n in names:
            bs = [b for b in briefs if measured(b, n)]
            g = sum(len(defect[b]["ground_truth"]) for b in bs)
            c.append(f"**{sum(hits(b, n) for b in bs)}**/{g}")
        print(f"| **{label}** | {gt} | " + " | ".join(c) + " |")
    print("\n| threshold (paired briefs) | " + " | ".join(names) + " |")
    print("|---|" + "---|" * len(names))
    for t, label in [(1, ">=1 judge"), (2, ">=2 of 3"), (3, "unanimous")]:
        print(
            f"| {label} | "
            + " | ".join(str(sum(hits(b, n, t) for b in paired)) for n in names)
            + " |"
        )

    print(
        "\n| effort | cells measured | arm failures | median output tokens | max output tokens"
        " | cells continued past the cap | continuations | cost USD (all measured cells) |"
    )
    print("|---|---|---|---|---|---|---|---|")
    for e in EFFORTS:
        xs = [r for (b, ee), r in latest.items() if ee == e]
        ok = [
            r
            for r in xs
            if not r.get("is_error") and r.get("output_tokens") is not None
        ]
        toks = sorted(r["output_tokens"] for r in ok)
        med = toks[len(toks) // 2] if toks else "-"
        # No single response can exceed the cap, so any total above it was continued at least
        # ceil(out/cap)-1 times. Needs only the total — usage.iterations is sometimes empty.
        cont = [-(-t // OUTPUT_CAP) - 1 for t in toks]
        fails = [f"{r['brief_id']}" for r in xs if r not in ok]
        cost = sum(r.get("cost_usd") or 0 for r in xs)
        print(
            f"| {e} | {len(xs)} | {len(fails)}{' (' + ', '.join(fails) + ')' if fails else ''}"
            f" | {med} | {max(toks) if toks else '-'} | {sum(1 for c in cont if c)} | {sum(cont)}"
            f" | {cost:.2f} |"
        )
    q = [r for r in raw if is_quota(r)]
    print(
        f"\nQuota faults: {len(q)} rows, {sum(r.get('cost_usd') or 0 for r in q):.2f} USD spent for no output."
    )


if __name__ == "__main__":
    verb, runs, scores = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    {"run": run, "table": table}[verb](runs, scores)
