"""cli_built.py — cc-research built …, the Stage 9 instruments (REPORT.md §11, method v1.2).

  built finding add --program P --source S --claim T --severity V [--test-cmd C] [--mutant M-n]
  built finding fix --program P --id BF-n          re-run the repro; exit 1 while it still fails
  built mutate  --program P [--equivalent M-n --reason T --rater V]
  built contact --program P --target <probe id|acceptance row id>
                (--negative-control CMD | --no-negative-control REASON)   exit 1 if the run failed
  built soak sample|restart --program P [--finding BF-n]
  built show    --program P [--json]

The logic is built.py; records are RECORDS.md "Stage 9 records".
"""

from __future__ import annotations

import argparse
import json
from typing import Any

import built


def ctx_for(slug: str) -> Any:
    import gate

    return gate.make_ctx(slug)


def cmd_finding_add(a: argparse.Namespace) -> int:
    f = built.add_finding(ctx_for(a.program), a.source, a.claim, a.severity, a.test_cmd, a.mutant)
    why = ""
    if f["status"] == "rejected-no-repro":
        why = " — no failing test on the built snapshot, so it is not material (§11)"
    print(f"{f['id']}: {f['severity']} {f['status']}{why}")
    return 0


def cmd_finding_fix(a: argparse.Namespace) -> int:
    ok, f = built.fix_finding(ctx_for(a.program), a.id)
    print(f"{a.id}: fixed, its repro passes" if ok else f"{a.id}: still failing, stays open")
    return 0 if ok else 1


def cmd_mutate(a: argparse.Namespace) -> int:
    ctx = ctx_for(a.program)
    if a.equivalent:
        m = built.mark_equivalent(ctx, a.equivalent, a.reason or "", a.rater or "")
        print(f"{m['id']}: equivalent ({m['equivalent']['reason']}; rater {m['equivalent']['rater']})")
        return 0
    rec = built.mutate(ctx)
    surv = [m["id"] for m in rec["mutants"] if m["status"] == "survived"]
    print(f"mutants: {rec['killed']} killed, {rec['survived']} survived, kill rate {rec['kill_rate']}"
          + (f" · survivors {', '.join(surv)} are findings" if surv else ""))
    return 1 if surv else 0


def cmd_contact(a: argparse.Namespace) -> int:
    r = built.contact(ctx_for(a.program), a.target, a.negative_control, a.no_negative_control)
    print(f"{r['id']}: {a.target} exit {r['exit']} under HOME=<empty> PATH={r['env']['path']} "
          f"{r['env']['interpreter']} {r['env']['interpreter_version']}")
    return 0 if r["exit"] == 0 else 1


def cmd_soak(a: argparse.Namespace) -> int:
    ctx = ctx_for(a.program)
    if a.action == "restart":
        plan = built.soak_restart(ctx, a.finding or "")
        print(f"soak restarted ({len(plan['restarts'])} restart(s))")
        return 0
    samples = built.soak_sample(ctx)
    bad = [s["check"] for s in samples if s["exit"] != 0]
    print(f"soak: {len(samples)} sample(s)" + (f", failing: {', '.join(bad)}" if bad else ", all pass"))
    return 1 if bad else 0


def cmd_show(a: argparse.Namespace) -> int:
    s = built.summary(ctx_for(a.program))
    if a.json:
        print(json.dumps(s, indent=2))
    else:
        f, m = s["findings"], s["mutants"]
        print(f"built {s['program']} at {s['snapshot_sha']}: findings {f['open']} open, {f['fixed']} "
              f"fixed, {f['rejected-no-repro']} without a repro · mutants {m['killed']} killed, "
              f"{m['survived']} survived · {s['contact_runs']} contact runs · "
              f"{s['soak_samples']} soak samples")
    return 0


def add_verbs(sub: Any) -> None:
    b = sub.add_parser("built", help="the Stage 9 instruments (method v1.2)")
    bs = b.add_subparsers(dest="built_verb", required=True)

    def verb(parent: Any, name: str, fn: Any) -> Any:
        p = parent.add_parser(name)
        p.add_argument("--program", required=True)
        p.set_defaults(fn=fn)
        return p

    fs = bs.add_parser("finding").add_subparsers(dest="finding_action", required=True)
    p = verb(fs, "add", cmd_finding_add)
    p.add_argument("--source", required=True, choices=("round", "mutation", "contact", "soak"))
    p.add_argument("--claim", required=True)
    p.add_argument("--severity", required=True, choices=("material", "refinement", "cosmetic"))
    p.add_argument("--test-cmd")
    p.add_argument("--mutant")
    p = verb(fs, "fix", cmd_finding_fix)
    p.add_argument("--id", required=True)
    p = verb(bs, "mutate", cmd_mutate)
    p.add_argument("--equivalent")
    p.add_argument("--reason")
    p.add_argument("--rater")
    p = verb(bs, "contact", cmd_contact)
    p.add_argument("--target", required=True)
    p.add_argument("--negative-control")
    p.add_argument("--no-negative-control")
    p = verb(bs, "soak", cmd_soak)
    p.add_argument("action", choices=("sample", "restart"))
    p.add_argument("--finding")
    p = verb(bs, "show", cmd_show)
    p.add_argument("--json", action="store_true")
