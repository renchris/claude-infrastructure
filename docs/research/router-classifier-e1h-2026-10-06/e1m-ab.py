#!/usr/bin/env python3
"""Wave E1m's matched-load A/B of the two unions (ruling 8633d354bd41 (c); RULE E1m in
docs/plans/RESEARCH_PROGRAM_BUILD.md, committed before any call): each tuning row goes through BOTH
routers back to back, the order alternating by row (A first on even rows, B first on odd), so the two
unions see the same rows at the same load. Each router is a `router.py classify` command whose resident
classifier is its own warm daemon on its own socket.

  e1m-ab.py run OUT.json ROUTER_A ROUTER_B [--limit N]
  e1m-ab.py report OUT.json TRACE_A TRACE_B
  e1m-ab.py guard2 OUT.json ROUTER TRACE [--max-load 40]

Rows, fixed before any call: the tuning base of wave E1h (e1h-score.py `base()`), in e1h-tune.py's
row order: every counted re-ask call (a row in a re-ask stratum whose two raters agree on a relay label;
v1 rows twice, as RULE E1j counts them: 163 calls) and every `other` row the two raters agree on outside
v1 (the 240 of the relay-decision bar). One call per router per row-call, each under the 9 s limit
`heldout.py evaluate` gives a router (the command on stdin, killed at 9 s).

Reported per arm: fallback rate (no label inside the limit), wrong in-time labels on re-ask rows (a
label inside the limit that is not a relay label, on a row whose gold is a relay label), median and p90
decision time, by 1-min load band; and from each arm's router trace, rows held with the careful call
silent (a `held` row whose careful call had not settled) and with the fast call silent.

guard2 (ruling a7fd5e2ee7c8, guard 2; RULE E1m (e)): the 42 counted regex-missed calls (a regex-missed row
whose two raters agree on a relay label; v1 rows twice) through one router, each call started only while
the 1-min load is at most --max-load. A call is caught only if it returned a relay label inside the limit
and the router's trace holds no `held` row for it with the careful call silent.

Reads tuning data only (never a sealed set, never tuning-v2.jsonl); writes per-call arm, key, label,
wall time and load; never a prompt.
"""

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIMIT_S = 9
spec = importlib.util.spec_from_file_location("e1h_score", HERE / "e1h-score.py")
S = importlib.util.module_from_spec(spec)
spec.loader.exec_module(S)
SOURCES = (
    ("fresh", "tuning-v4.jsonl", 1),
    ("v2", "retired-v2.jsonl", 1),
    ("v1", "tuning.jsonl", 2),
)
ROUTES = (
    "completeness",
    "pushback",
    "concern",
    "new-idea",
    "research-order",
    "work-order",
    "other",
)
BANDS = ((0, 40), (40, 100), (100, 150), (150, 250), (250, 10**6))


def selected() -> list:
    """[(key, prompt, gold_relay)] in e1h-tune.py's row order, v1 re-ask rows twice."""
    base = S.base()
    out, seen = [], set()
    for src, name, reps in SOURCES:
        for line in open(S.H / name):
            r = json.loads(line)
            key = f"{src}:{hashlib.sha256(r['prompt'].encode()).hexdigest()[:12]}"
            if key in seen or key not in base:
                continue
            seen.add(key)
            row = base[key]
            g = S.agreed(row)
            if row["stratum"] in S.COMPLETENESS_STRATA and g in S.REL:
                out += [(key, r["prompt"], True)] * reps
            elif row["stratum"] == "other" and g is not None and src != "v1":
                out.append((key, r["prompt"], False))
    return out


def route(cmd: str, prompt: str) -> dict:
    load0 = round(os.getloadavg()[0], 1)
    t0 = time.time()
    try:
        p = subprocess.run(
            ["/bin/bash", "-c", cmd],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=LIMIT_S,
        )
        words = p.stdout.replace(",", " ").split()
        ok = p.returncode == 0 and len(words) == 1 and words[0] in ROUTES
        label = words[0] if ok else None
    except subprocess.TimeoutExpired:
        label = None
    return {
        "t": round(t0, 2),
        "label": label,
        "wall_s": round(time.time() - t0, 2),
        "load0": load0,
    }


def run(out: Path, ra: str, rb: str, limit) -> int:
    todo = selected()[:limit]
    data = json.loads(out.read_text()) if out.exists() else {"calls": [], "meta": {}}
    data["meta"].update(rows=len(todo), router_a=ra, router_b=rb)
    data["meta"].setdefault("started", time.strftime("%Y-%m-%dT%H:%M:%S%z"))
    for n in range(len(data["calls"]) // 2, len(todo)):
        key, prompt, relay = todo[n]
        order = (("a", ra), ("b", rb)) if n % 2 == 0 else (("b", rb), ("a", ra))
        for arm, cmd in order:
            data["calls"].append(
                {"n": n, "arm": arm, "key": key, "relay": relay, **route(cmd, prompt)}
            )
        data["meta"]["updated"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        out.write_text(json.dumps(data, indent=0) + "\n")
    data["meta"]["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    out.write_text(json.dumps(data, indent=0) + "\n")
    print(f"DONE {len(todo)} row-call(s) x 2 routers -> {out}")
    return 0


def held_rows(trace: Path) -> list:
    rows = []
    for line in open(trace):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("row") == "held":
            # a kind is silent when neither its call nor its cold twin had answered at the hold
            silent = [
                k
                for k in ("fast", "careful")
                if not (r.get(k) or {}).get("answered")
                and not ((r.get(k) or {}).get("twin") or {}).get("answered")
            ]
            rows.append((r["t"], silent))
    return rows


def pct(xs: list, q: float):
    xs = sorted(xs)
    return xs[min(int(len(xs) * q), len(xs) - 1)] if xs else None


def report(out: Path, ta: Path, tb: Path) -> int:
    calls = json.loads(out.read_text())["calls"]
    held = {"a": held_rows(ta), "b": held_rows(tb)}
    meta = json.loads(out.read_text())["meta"]
    print(
        f"rows {meta['rows']}; A = {meta['router_a']}\n           B = {meta['router_b']}"
    )
    print(
        "| arm | 1-min load | calls | fallbacks | re-ask calls | wrong in-time label on re-ask | median | p90 | held, careful silent | held, fast silent |"
    )
    print("|---|---|---|---|---|---|---|---|---|---|")
    for arm in ("a", "b"):
        mine = [c for c in calls if c["arm"] == arm]
        for lo, hi in ((0, 10**6),) + BANDS:
            cs = [c for c in mine if lo <= c["load0"] < hi]
            if not cs:
                continue
            fell = sum(c["label"] is None for c in cs)
            re = [c for c in cs if c["relay"]]
            wrong = sum(c["label"] is not None and c["label"] not in S.REL for c in re)
            walls = [c["wall_s"] for c in cs]
            hc = hf = 0
            for c in cs:
                for t, silent in held[arm]:
                    if c["t"] - 1 <= t <= c["t"] + LIMIT_S:
                        hc += "careful" in silent
                        hf += "fast" in silent
            band = (
                "all" if hi == 10**6 and lo == 0 else f"{lo}-{hi if hi < 10**6 else ''}"
            )
            print(
                f"| {arm.upper()} | {band} | {len(cs)} | {fell} ({fell / len(cs):.3f}) | {len(re)} | {wrong} | {pct(walls, 0.5)} s | {pct(walls, 0.9)} s | {hc} | {hf} |"
            )
    return 0


def guard2(out: Path, router: str, trace: Path, max_load: float) -> int:
    todo = [r for r in selected() if r[2] and S.base()[r[0]]["stratum"] == "regex-missed"]
    calls = []
    for n, (key, prompt, _) in enumerate(todo):
        while os.getloadavg()[0] > max_load:
            time.sleep(20)
        calls.append({"n": n, "key": key, **route(router, prompt)})
        out.write_text(json.dumps({"calls": calls, "max_load": max_load}, indent=0) + "\n")
    held = held_rows(trace) if trace.exists() else []
    caught = 0
    for c in calls:
        silent = any(
            "careful" in s for t, s in held if c["t"] - 1 <= t <= c["t"] + LIMIT_S
        )
        c["held_careful_silent"] = silent
        c["caught"] = c["label"] in S.REL and not silent
        caught += c["caught"]
    out.write_text(json.dumps({"calls": calls, "max_load": max_load}, indent=0) + "\n")
    loads = sorted(c["load0"] for c in calls)
    print(
        f"guard2: caught {caught}/{len(calls)} (row 15's floor 0.95: >= {-(-95 * len(calls) // 100)}); "
        f"fallbacks {sum(c['label'] is None for c in calls)}; "
        f"held with the careful call silent {sum(c['held_careful_silent'] for c in calls)}; "
        f"1-min load at start {loads[0]}-{loads[-1]}"
    )
    return 0


def main() -> int:
    if len(sys.argv) >= 5 and sys.argv[1] == "guard2":
        ml = float(sys.argv[sys.argv.index("--max-load") + 1]) if "--max-load" in sys.argv else 40.0
        return guard2(Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4]), ml)
    if len(sys.argv) >= 5 and sys.argv[1] == "run":
        limit = (
            int(sys.argv[sys.argv.index("--limit") + 1])
            if "--limit" in sys.argv
            else None
        )
        return run(Path(sys.argv[2]), sys.argv[3], sys.argv[4], limit)
    if len(sys.argv) == 5 and sys.argv[1] == "report":
        return report(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]))
    print(__doc__.split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
