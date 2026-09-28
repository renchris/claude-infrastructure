#!/usr/bin/env python3
"""score.py — score the #35 delivery benchmark (read-only over run dirs and transcripts).

  score.py [--root RUNROOT] [--config-dir DIR] [--tasks TSV]   score every run, print the tables
  score.py sign WINS LOSSES                                    one-sided sign-test p, ties dropped

Per run (docs/research/truememory-2026-09-27.md §5.16):
  lesson_used  the run opened the gold file (Read, or a Bash command naming it), OR the task's
               mechanical rubric passed; on a write task the rubric is "the twin was edited and no
               new near-duplicate was left in the store"
  correct      the task rubric (`re:` over the final answer, `fs:` a named fixture check), AND'ed
  wall_s       end - start of the claude process
  tokens       input + output + cache_creation from result.json usage
  false_pointer (controls) a lesson pointer reached the model in a hook_additional_context attachment,
               main transcript or subagents/
  rule_pushed  (#36) the action-rule-push hook fired: a hook_additional_context carrying PUSH_MARK
With a #36 task table (kind `miss`, tasks-36.tsv; §5.23) the report is per task x arm pass counts,
fixture/control qualification on arm 1, and the pre-registered verdict for arm M against B = arm 1.
Run dirs are <root>/<task>-a<arm>-r<rep>-<epoch>/; a re-run leaves the old dir and the newest wins.
Writes <root>/scored.jsonl (private) and prints the aggregate table plus the primary sign test
(arm 3 vs arm 2, lesson_used, paired by task x rep over the lesson and write tasks) and secondaries.
"""

import argparse
import glob
import json
import os
import re
import statistics
import subprocess
import sys
from math import comb
from typing import Any, Dict, Iterable, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
POINTER = re.compile(r"(?:docs/lessons|/memory)/(?!MEMORY\.md)[A-Za-z0-9._-]+\.md")
ACK = re.compile(r"(?i)\b(already|existing|exists)\b")
PUSH_MARK = "[action-rule-push]"


def sign_p(wins: int, losses: int) -> float:
    n = wins + losses
    if n == 0:
        return 1.0
    return float(sum(comb(n, k) for k in range(wins, n + 1)) / 2**n)


def load_tasks(path: str) -> Dict[str, Dict[str, str]]:
    out: Dict[str, Dict[str, str]] = {}
    with open(path, encoding="utf-8") as fh:
        head = fh.readline().rstrip("\n").split("\t")
        for line in fh:
            if line.strip():
                out[line.split("\t")[0]] = dict(
                    zip(head, line.rstrip("\n").split("\t"))
                )
    return out


def slug(path: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(path))


def transcripts(cfg: str, fx: str, sid: Optional[str]) -> List[str]:
    d = os.path.join(cfg, "projects", slug(fx))
    main = os.path.join(d, f"{sid}.jsonl") if sid else ""
    if not (main and os.path.exists(main)):
        cands = glob.glob(os.path.join(d, "*.jsonl"))
        if not cands:
            return []
        main = max(cands, key=os.path.getmtime)
        sid = os.path.basename(main)[:-6]
    return [main] + sorted(glob.glob(os.path.join(d, str(sid), "subagents", "*.jsonl")))


def events(paths: Iterable[str]) -> Iterable[Dict[str, Any]]:
    for p in paths:
        with open(p, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if isinstance(rec, dict):
                    yield rec


def tool_uses(rec: Dict[str, Any]) -> Iterable[Tuple[str, Dict[str, Any]]]:
    content = (rec.get("message") or {}).get("content")
    if isinstance(content, list):
        for c in content:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                yield str(c.get("name", "")), c.get("input") or {}


def hook_contexts(rec: Dict[str, Any]) -> List[str]:
    att = rec.get("attachment")
    if (
        rec.get("type") == "attachment"
        and isinstance(att, dict)
        and att.get("type") == "hook_additional_context"
    ):
        c = att.get("content")
        return [c if isinstance(c, str) else json.dumps(c)]
    return []


def manifest(path: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("  ", 1)
                if len(parts) == 2:
                    out[parts[1][2:] if parts[1].startswith("./") else parts[1]] = (
                        parts[0]
                    )
    return out


def run_cmd(argv: List[str], cwd: str) -> Tuple[int, str]:
    try:
        p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=60)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 124, ""


def write_state(rd: str, gold: str, dup: str) -> Dict[str, Any]:
    before = manifest(os.path.join(rd, "out", "mem.before.sha256"))
    after = manifest(os.path.join(rd, "out", "mem.after.sha256"))
    new = sorted(set(after) - set(before))
    dups = []
    for f in new:
        if not f.endswith(".md") or os.path.basename(f) == "MEMORY.md":
            continue
        try:
            with open(
                os.path.join(rd, "mem", f), encoding="utf-8", errors="replace"
            ) as fh:
                body = fh.read()
        except OSError:
            body = ""
        if dup and (re.search(dup, f) or re.search(dup, body)):
            dups.append(f)
    return {
        "twin_edited": int(
            gold in before and after.get(gold) not in (None, before[gold])
        ),
        "new_files": new,
        "near_dups": dups,
    }


def fs_check(name: str, fx: str, answer: str, ws: Dict[str, Any]) -> bool:
    if name == "gate-pass":
        rc, _ = run_cmd(["bash", "ops/gate.sh"], fx)
        same, _ = run_cmd(
            ["git", "diff", "--quiet", "origin/main", "--", "ops/gate.sh"], fx
        )
        return rc == 0 and same == 0
    if name.startswith("linecount:"):
        rc, out = run_cmd(["git", "show", "origin/main:" + name.split(":", 1)[1]], fx)
        m = re.search(r"LINES:\s*(\d+)", answer)
        return rc == 0 and m is not None and int(m.group(1)) == out.count("\n")
    if name == "slug":
        code = "import runpy; f = runpy.run_path('ops/slug.py')['slugify']; print(f('a.b/C_9 x'))"
        rc, out = run_cmd([sys.executable, "-c", code], fx)
        return rc == 0 and out.strip() == "a-b-C-9-x"
    if name == "sum":
        rc, out = run_cmd(["bash", "ops/sum.sh", "2", "3", "4"], fx)
        return rc == 0 and out.strip() == "9"
    if name.startswith(("drafts-min:", "draft-last:")):
        drafts = desk_rows(
            os.path.join(os.path.dirname(fx), "desk-state", "drafts.tsv")
        )
        if name.startswith("drafts-min:"):
            return len(drafts) >= int(name.split(":", 1)[1])
        to_re, text_re = name.split(":", 2)[1:]
        hits = [d for d in drafts if re.search(to_re, d[1])]
        return bool(hits) and bool(re.search(text_re, hits[-1][2]))
    if name.startswith(("ledger:", "ledger-not:")):
        kind, item, state = name.split(":", 2)
        rows = desk_rows(os.path.join(fx, "desk", "ledger.tsv"))
        got = next((r[2] for r in rows if r[0] == item), None)
        return got is not None and (got == state) == (kind == "ledger")
    if name.startswith("exists:"):
        return os.path.isfile(os.path.join(fx, name.split(":", 1)[1]))
    if name == "write-twin":
        return not ws.get("near_dups") and bool(
            ws.get("twin_edited") or ACK.search(answer)
        )
    raise ValueError(f"unknown fs check {name}")


def desk_rows(path: str, width: int = 3) -> List[List[str]]:
    """Rows of a #36 TSV (the drafts in <run>/desk-state/, or the fixture's desk/ledger.tsv)."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            rows = [ln.rstrip("\n").split("\t") for ln in fh if ln.strip()]
    except OSError:
        return []
    return [r + [""] * (width - len(r)) for r in rows]


def score_run(rd: str, task: Dict[str, str], cfg: str) -> Dict[str, Any]:
    out = os.path.join(rd, "out")
    with open(os.path.join(out, "meta.json"), encoding="utf-8") as fh:
        meta = json.load(fh)
    fx = os.path.join(rd, "fx")
    res: Dict[str, Any] = {}
    try:
        with open(os.path.join(out, "result.json"), encoding="utf-8") as fh:
            res = json.load(fh)
    except (OSError, ValueError):
        pass
    answer = str(res.get("result") or "")
    usage = res.get("usage") or {}
    tokens = sum(
        int(usage.get(k) or 0)
        for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens")
    )
    wall: Optional[int] = None
    try:
        with open(os.path.join(out, "time"), encoding="utf-8") as fh:
            a, b = fh.read().split()
            wall = int(b) - int(a)
    except (OSError, ValueError):
        pass
    gold = task.get("gold", "-")
    gbase = os.path.basename(gold) if gold != "-" else ""
    terms = [t.strip() for t in task.get("rubric", "").split(" AND ") if t.strip()]
    dup = next((t[4:] for t in terms if t.startswith("dup:")), "")
    ws = write_state(rd, gbase, dup) if task["kind"] == "write" else {}

    gold_read = pointer = gold_pointer = pushed = 0
    tr = transcripts(cfg, fx, res.get("session_id"))
    for rec in events(tr):
        for name, inp in tool_uses(rec):
            blob = (
                inp.get("file_path", "")
                if name == "Read"
                else inp.get("command", "")
                if name == "Bash"
                else ""
            )
            if gbase and isinstance(blob, str) and gbase in blob:
                gold_read = 1
        for ctx in hook_contexts(rec):
            if POINTER.search(ctx):
                pointer = 1
            if gbase and gbase in ctx:
                gold_pointer = 1
            if PUSH_MARK in ctx:
                pushed = 1

    ok = []
    for t in terms:
        if t.startswith("re:"):
            ok.append(bool(re.search(t[3:], answer)))
        elif t.startswith("fs:"):
            ok.append(fs_check(t[3:], fx, answer, ws))
    correct = int(bool(ok) and all(ok))
    if task["kind"] == "write":
        applied = int(bool(ws.get("twin_edited")) and not ws.get("near_dups"))
    else:
        applied = correct
    rc = None
    try:
        with open(os.path.join(out, "rc"), encoding="utf-8") as fh:
            rc = int(fh.read().strip())
    except (OSError, ValueError):
        pass
    return {
        "task": meta["task"],
        "kind": task["kind"],
        "arm": str(meta["arm"]),
        "rep": str(meta["rep"]),
        "sha": meta.get("sha"),
        "rc": rc,
        "transcripts": len(tr),
        "gold_read": gold_read,
        "lesson_used": int(bool(gold_read or applied))
        if task["kind"] != "control"
        else None,
        "correct": correct,
        "false_pointer": pointer if task["kind"] == "control" else None,
        "pointer_delivered": pointer,
        "gold_pointer_delivered": gold_pointer,
        "rule_pushed": pushed,
        "wall_s": wall,
        "tokens": tokens,
        **({k: ws[k] for k in ("twin_edited", "near_dups")} if ws else {}),
    }


def paired(
    rows: List[Dict[str, Any]], a: str, b: str, field: str, kinds: Tuple[str, ...]
) -> Tuple[int, int, int, int]:
    idx = {(r["arm"], r["task"], r["rep"]): r for r in rows if r["kind"] in kinds}
    wins = losses = ties = missing = 0
    for task, rep in sorted({(r["task"], r["rep"]) for r in idx.values()}):
        ra, rb = idx.get((a, task, rep)), idx.get((b, task, rep))
        if ra is None or rb is None:
            missing += 1
            continue
        x, y = int(ra[field] or 0), int(rb[field] or 0)
        wins += x > y
        losses += x < y
        ties += x == y
    return wins, losses, ties, missing


def med(xs: List[Optional[int]]) -> str:
    v = [x for x in xs if x is not None]
    return f"{statistics.median(v):.0f}" if v else "-"


def report(rows: List[Dict[str, Any]]) -> str:
    lines = [
        "| arm | runs | lesson-used (lesson+write) | correct (lesson+write) | control correct | control false-pointer | median wall s | median tokens |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for arm in sorted({r["arm"] for r in rows}):
        rs = [r for r in rows if r["arm"] == arm]
        les = [r for r in rs if r["kind"] != "control"]
        ctl = [r for r in rs if r["kind"] == "control"]
        lines.append(
            f"| {arm} | {len(rs)} | {sum(r['lesson_used'] for r in les)}/{len(les)} | {sum(r['correct'] for r in les)}/{len(les)}"
            f" | {sum(r['correct'] for r in ctl)}/{len(ctl)} | {sum(r['false_pointer'] for r in ctl)}/{len(ctl)}"
            f" | {med([r['wall_s'] for r in rs])} | {med([r['tokens'] for r in rs])} |"
        )
    lesson = ("lesson", "write")
    w, lo, t, m = paired(rows, "3", "2", "lesson_used", lesson)
    lines.append("")
    lines.append(
        f"PRIMARY arm3 vs arm2 lesson_used: wins={w} losses={lo} ties={t} missing={m} p={sign_p(w, lo):.4f} -> {'GAIN' if sign_p(w, lo) < 0.1 and w + lo else 'NO GAIN'}"
    )
    for label, a, b, field, kinds in (
        ("correct arm3 vs arm2", "3", "2", "correct", lesson),
        ("lesson_used arm2 vs arm1", "2", "1", "lesson_used", lesson),
        ("control correct arm3 vs arm2", "3", "2", "correct", ("control",)),
        ("control false_pointer arm3 vs arm2", "3", "2", "false_pointer", ("control",)),
    ):
        w, lo, t, m = paired(rows, a, b, field, kinds)
        lines.append(
            f"SECONDARY {label}: wins={w} losses={lo} ties={t} missing={m} p={sign_p(w, lo):.4f}"
        )
    return "\n".join(lines)


def report36(rows: List[Dict[str, Any]], qualifying: Optional[List[str]]) -> str:
    """§5.23: per task x arm passes; qualification on arm 1; verdict for arm M vs B = arm 1."""
    cell: Dict[Tuple[str, str], List[int]] = {}
    kinds: Dict[str, str] = {}
    for r in rows:
        cell.setdefault((r["task"], r["arm"]), []).append(int(r["correct"]))
        kinds[r["task"]] = r["kind"]
    arms = sorted({r["arm"] for r in rows})
    lines = ["| task | kind | " + " | ".join(f"arm {a}" for a in arms) + " |"]
    lines.append("|---|---|" + "---|" * len(arms))
    for t in sorted(kinds):
        cs = [cell.get((t, a), []) for a in arms]
        lines.append(
            f"| {t} | {kinds[t]} | "
            + " | ".join(f"{sum(c)}/{len(c)}" if c else "-" for c in cs)
            + " |"
        )
    lines.append("")
    base = {t: cell.get((t, "1"), []) for t in kinds}
    for t in sorted(kinds):
        c = base[t]
        if not c:
            continue
        if kinds[t] == "miss":
            ok = len(c) - sum(c) >= 2
            lines.append(
                f"QUALIFY {t} arm1 fails {len(c) - sum(c)}/{len(c)} -> {'QUALIFIES' if ok else 'PASSES (replace)'}"
            )
        else:
            ok = sum(c) >= 2
            lines.append(
                f"QUALIFY {t} arm1 passes {sum(c)}/{len(c)} -> {'VALID' if ok else 'FAILS (replace)'}"
            )
    if qualifying is None:
        qualifying = [
            t
            for t in sorted(kinds)
            if kinds[t] == "miss" and len(base[t]) - sum(base[t]) >= 2
        ]
    if not any(r["arm"] == "M" for r in rows):
        return "\n".join(lines)
    prevented = [t for t in qualifying if sum(cell.get((t, "M"), [])) >= 2]
    ctl = [r for r in rows if r["arm"] == "M" and r["kind"] == "control"]
    fb = [r for r in ctl if r["rule_pushed"] and not r["correct"]]
    rate = len(fb) / len(ctl) if ctl else 1.0
    lines.append(f"PREVENTED {len(prevented)}/4 {prevented} of qualifying {qualifying}")
    lines.append(
        f"FALSE-BLOCKS {len(fb)}/{len(ctl)} M control runs ({rate:.1%}); pushed on {sum(r['rule_pushed'] for r in ctl)}"
    )
    if len(qualifying) < 3:
        verdict = "DROP (no measurable headroom)"
    elif len(prevented) >= 3 and ctl and rate <= 0.10:
        verdict = "ADOPT"
    else:
        verdict = "DROP"
    lines.append(f"VERDICT {verdict}")
    return "\n".join(lines)


def main(argv: List[str]) -> int:
    if len(argv) >= 2 and argv[1] == "sign":
        print(f"{sign_p(int(argv[2]), int(argv[3])):.4f}")
        return 0
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--root",
        default=os.path.expanduser("~/.claude/autonomy/memory-eval/bench-runs"),
    )
    ap.add_argument("--config-dir", default=os.path.expanduser("~/.claude-next"))
    ap.add_argument("--tasks", default=os.path.join(HERE, "tasks.tsv"))
    ap.add_argument(
        "--qualifying", help="#36: comma-separated fixture ids fixed by validation"
    )
    args = ap.parse_args(argv[1:])
    tasks = load_tasks(args.tasks)
    newest: Dict[Tuple[str, str, str], Tuple[int, str, Dict[str, Any]]] = {}
    for meta in glob.glob(os.path.join(args.root, "*-a*-r*-*", "out", "meta.json")):
        rd = os.path.dirname(os.path.dirname(meta))
        with open(meta, encoding="utf-8") as fh:
            m = json.load(fh)
        key = (str(m["task"]), str(m["arm"]), str(m["rep"]))
        epoch = int(rd.rsplit("-", 1)[1]) if rd.rsplit("-", 1)[1].isdigit() else 0
        if key[0] in tasks and (key not in newest or epoch > newest[key][0]):
            newest[key] = (epoch, rd, m)
    rows = [
        score_run(rd, tasks[key[0]], args.config_dir)
        for key, (_, rd, _m) in sorted(newest.items())
    ]
    with open(os.path.join(args.root, "scored.jsonl"), "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    if any(t.get("kind") == "miss" for t in tasks.values()):
        q = [x for x in args.qualifying.split(",") if x] if args.qualifying else None
        print(report36(rows, q))
    else:
        print(report(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
