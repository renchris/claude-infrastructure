#!/usr/bin/env python3
"""o_records.py — what the TrueMemory 2.0 program records hold now, and when each item appeared.

READ ONLY over the program dir on the tm2-plan worktree. Folds each append-only record by id the
way the kit does (scripts/research-kit/lib/kit.py `fold`: last writer wins per field) and uses the
kit's own `premise_level`, `REQUIRED_LEVEL` and `not_new_material` rules.

Usage (from the repo root):
  python3 docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/o_records.py
Writes data/o_records.json and prints a summary.
"""

import collections, glob, json, os, re, subprocess, sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "scripts", "research-kit", "lib"))
import kit  # noqa: E402  (read-only helpers: fold, premise_level, REQUIRED_LEVEL, not_new_material)

TM2 = os.path.expanduser("~/Development/.worktrees/tm2-plan")
PROG = os.path.join(TM2, "docs/research/truememory-2.0-2026-09-28")
REC = os.path.join(PROG, "program")
PRIV = os.path.expanduser("~/Development/claude-private/tm2-plan")
NOW = datetime(2026, 10, 16, 14, 0, tzinfo=timezone.utc).timestamp()


def ep(s):
    return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()


WEEKS = [
    ("Wk0", ep("2026-09-21T05:00:00Z")),
    ("Wk1", ep("2026-09-28T05:00:00Z")),
    ("Wk2", ep("2026-10-05T05:00:00Z")),
    ("Wk3", ep("2026-10-12T05:00:00Z")),
]


def week(t):
    w = "pre"
    for n, a in WEEKS:
        if t >= a:
            w = n
    return w


def day(t):
    return datetime.fromtimestamp(t - 5 * 3600, timezone.utc).strftime("%m-%d")


def rows(name):
    return kit.read_jsonl(os.path.join(REC, name))


def first_ts(rs):
    out = {}
    for r in rs:
        i, t = r.get("id"), r.get("ts") or r.get("at")
        if i and t and i not in out:
            out[i] = ep(t)
    return out


def by_week(ts_list):
    c = collections.Counter(week(t) for t in ts_list)
    return {w: c.get(w, 0) for w, _ in WEEKS}


def round_family(r):
    r = str(r or "")
    if r.startswith("fc"):
        return "frame critique (" + r + ")"
    if r.isdigit() and int(r) >= 24:
        # rounds 24-29 are the PLAN critique rounds run on tm2-plan-replan (merged fb5e929d4)
        return "plan critique round " + r + " (replan)"
    if r.isdigit():
        return "certification round " + r
    return r or "(none)"


def main():
    out = {}
    # ── holes ────────────────────────────────────────────────────────────────────────────────
    hr = rows("holes.jsonl")
    H = kit.fold(hr)
    hfirst = first_ts(hr)
    held = set()
    for r in kit.fold(rows("known_rows.jsonl")).values():
        if (
            r.get("kind") == "frame-omission"
            and r.get("status", "open") == "open"
            and r.get("hole")
        ):
            held.add(str(r["hole"]))
    fam = collections.defaultdict(collections.Counter)
    mat_ts, newmat_ts, dec_ts, fixed_ts = [], [], [], []
    for i, h in H.items():
        f = round_family(h.get("round"))
        c = fam[f]
        c["holes"] += 1
        st = (h.get("verification") or {}).get("status")
        lvl = (h.get("materiality") or {}).get("level")
        c["verify:" + str(st)] += 1
        c["level:" + str(lvl)] += 1
        confirmed_material = st == "CONFIRMED" and lvl == "MATERIAL"
        if confirmed_material:
            c["confirmed material"] += 1
            mat_ts.append(hfirst.get(i, NOW))
            if h.get("seed_match"):
                c["seed catches (planted)"] += 1
            elif kit.not_new_material(h, held):
                c["artifact/held re-find"] += 1
            else:
                c["real new material"] += 1
                newmat_ts.append(hfirst.get(i, NOW))
                if any(re.match(r"DR-\d", str(n)) for n in (h.get("names") or [])):
                    c["real new material naming a decision"] += 1
                    dec_ts.append(hfirst.get(i, NOW))
        d = (h.get("disposition") or {}).get("kind")
        if d:
            c["disposition:" + d] += 1
            if d == "fixed":
                fixed_ts.append(ep(h["ts"]))
    out["holes"] = {
        "distinct": len(H),
        "events": len(hr),
        "by_family": {k: dict(sorted(v.items())) for k, v in sorted(fam.items())},
        "confirmed_material_by_week": by_week(mat_ts),
        "real_new_material_by_week": by_week(newmat_ts),
        "real_new_material_naming_decision_by_week": by_week(dec_ts),
        "fixed_dispositions_by_week": by_week(fixed_ts),
        "real_new_material_by_day": dict(
            sorted(collections.Counter(day(t) for t in newmat_ts).items())
        ),
    }
    # ── decisions ────────────────────────────────────────────────────────────────────────────
    dr = rows("decisions.jsonl")
    D = kit.fold(dr)
    ruled_at = {}
    for r in dr:
        if (
            r.get("id")
            and (r.get("ruled_by") or r.get("chosen") or r.get("event") == "ruled")
            and r["id"] not in ruled_at
        ):
            ruled_at[r["id"]] = ep(r["ts"])
    rule_events = collections.Counter(
        r["id"] for r in dr if r.get("ruled_by") or r.get("chosen")
    )
    out["decisions"] = {
        "distinct": len(D),
        "events": len(dr),
        "status": dict(collections.Counter(str(d.get("status")) for d in D.values())),
        "ruled_by": dict(
            collections.Counter(str(d.get("ruled_by")) for d in D.values())
        ),
        "carried_set": sum(1 for d in D.values() if d.get("set")),
        "first_ruled_by_week": by_week(ruled_at.values()),
        "ruled_more_than_once": sum(1 for v in rule_events.values() if v > 1),
        "rule_events_total": sum(rule_events.values()),
    }
    # ── premises ─────────────────────────────────────────────────────────────────────────────
    pr = rows("premises.jsonl")
    P = kit.fold(pr)
    probes = {p["id"]: p for p in rows("probes.jsonl") if p.get("id")}
    lv = collections.Counter()
    at_level, below, refuted = 0, 0, 0
    reached = []
    for i, p in P.items():
        need = kit.REQUIRED_LEVEL.get(p.get("truth_lives_in", ""), 99)
        got = kit.premise_level(p, probes, NOW)
        lv[f"E{got}"] += 1
        if p.get("verdict") == "refuted":
            refuted += 1
        if kit.premise_at_level(p, probes, NOW):
            at_level += 1
        else:
            below += 1
        # first instant the premise's probes (ignoring TTL lapse) reached the required level
        best_t = None
        for pid in p.get("probes") or []:
            q = probes.get(pid)
            if q and q.get("at") and kit.probe_level(q) >= need:
                t = ep(q["at"])
                best_t = t if best_t is None else min(best_t, t)
        if best_t:
            reached.append(best_t)
    out["premises"] = {
        "distinct": len(P),
        "events": len(pr),
        "achieved_level_now": dict(sorted(lv.items())),
        "required_level": dict(
            collections.Counter(
                f"E{kit.REQUIRED_LEVEL.get(p.get('truth_lives_in', ''), 99)}"
                for p in P.values()
            )
        ),
        "verdict": dict(collections.Counter(str(p.get("verdict")) for p in P.values())),
        "at_required_level_now": at_level,
        "below_required_now": below,
        "refuted": refuted,
        "first_reached_required_level_by_week": by_week(reached),
    }
    out["probes"] = {
        "total": len(probes),
        "by_kind": dict(
            collections.Counter(
                str(p.get("kind")) for p in probes.values()
            ).most_common()
        ),
        "by_week": by_week([ep(p["at"]) for p in probes.values() if p.get("at")]),
        "exit0": sum(1 for p in probes.values() if p.get("exit") == 0),
    }
    # ── the smaller records ──────────────────────────────────────────────────────────────────
    K = kit.fold(rows("known_rows.jsonl"))
    out["known_rows"] = {
        "distinct": len(K),
        "status": dict(collections.Counter(str(r.get("status")) for r in K.values())),
        "kind": dict(collections.Counter(str(r.get("kind")) for r in K.values())),
    }
    A = kit.fold(rows("apply-at-build.jsonl"))
    out["apply_at_build"] = {
        "distinct": len(A),
        "status": dict(collections.Counter(str(r.get("status")) for r in A.values())),
    }
    R = kit.fold(rows("residual.jsonl"))
    out["residual"] = {
        "distinct": len(R),
        "superseded": sum(1 for r in R.values() if r.get("superseded_by")),
    }
    C = kit.fold(rows("challenges.jsonl"))
    out["challenges"] = {
        "distinct": len(C),
        "triage": dict(collections.Counter(str(r.get("triage")) for r in C.values())),
        "void": sum(1 for r in C.values() if r.get("void")),
    }
    out["changes"] = {"distinct": len(kit.fold(rows("changes.jsonl")))}
    out["trace_rows"] = len(rows("trace.jsonl"))
    out["freezes"] = [
        {
            "at": f["at"],
            "plan_lines": f["plan_lines"],
            "snapshot": f["snapshot_sha"][:9],
        }
        for f in rows("freezes.jsonl")
    ]
    out["contract_page_renders"] = [
        r["ts"] for r in rows("intake.jsonl") if r.get("event") == "contract-page"
    ]
    # ── plan size over time (docs/plans/TRUEMEMORY_2_0.md on tm2-plan) ───────────────────────
    log = subprocess.run(
        [
            "git",
            "-C",
            TM2,
            "log",
            "--reverse",
            "--format=%H %cI",
            "--",
            "docs/plans/TRUEMEMORY_2_0.md",
        ],
        capture_output=True,
        text=True,
    ).stdout.split("\n")
    per_day = {}
    for ln in log:
        if not ln.strip():
            continue
        sha, ci = ln.split()
        per_day[ci[:10]] = sha  # last commit of each (commit-local) day
    sizes = {}
    for d, sha in sorted(per_day.items()):
        blob = subprocess.run(
            ["git", "-C", TM2, "show", f"{sha}:docs/plans/TRUEMEMORY_2_0.md"],
            capture_output=True,
            text=True,
        ).stdout
        sizes[d] = {
            "lines": blob.count("\n"),
            "bytes": len(blob.encode()),
            "sha": sha[:9],
        }
    out["plan_size_by_day"] = sizes
    out["plan_commits"] = sum(1 for ln in log if ln.strip())
    # ── gate rows: every saved gate output, dated ────────────────────────────────────────────
    row_rx = re.compile(
        r"^\s*(\d+)\.\s+([A-Za-z][A-Za-z /-]+?)\s{2,}(PASS|FAIL|FILED)\b", re.M
    )
    gates = []
    cands = set(glob.glob(os.path.join(PROG, "**", "*.txt"), recursive=True)) | set(
        glob.glob(os.path.join(PROG, "**", "*.log"), recursive=True)
    )
    cands |= set(glob.glob(os.path.join(PRIV, "*.log")))
    for f in sorted(cands):
        try:
            txt = open(f, errors="replace").read()
        except OSError:
            continue
        found = row_rx.findall(txt)
        if len(found) < 8:
            continue
        rel = os.path.relpath(f, TM2) if f.startswith(TM2) else f
        ct = (
            subprocess.run(
                [
                    "git",
                    "-C",
                    TM2,
                    "log",
                    "--diff-filter=A",
                    "--format=%cI",
                    "-1",
                    "--",
                    rel,
                ],
                capture_output=True,
                text=True,
            ).stdout.strip()
            if f.startswith(TM2)
            else ""
        )
        when = (
            ct or datetime.fromtimestamp(os.stat(f).st_mtime, timezone.utc).isoformat()
        )
        last = {}
        for n, name, v in found:  # a file may hold several runs: keep the last
            last[int(n)] = v
        gates.append(
            {
                "file": f.replace(os.path.expanduser("~"), "~"),
                "when": when,
                "rows": len(last),
                "pass": sum(1 for v in last.values() if v == "PASS"),
                "filed": sum(1 for v in last.values() if v == "FILED"),
                "failing": sorted(k for k, v in last.items() if v == "FAIL"),
            }
        )
    out["gate_outputs"] = sorted(gates, key=lambda g: g["when"])
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "o_records.json"), "w") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
    print(
        json.dumps(
            {
                k: out[k]
                for k in (
                    "holes",
                    "decisions",
                    "premises",
                    "known_rows",
                    "apply_at_build",
                    "residual",
                    "challenges",
                    "trace_rows",
                    "freezes",
                    "gate_outputs",
                )
            },
            indent=1,
        )[:12000]
    )


if __name__ == "__main__":
    main()
