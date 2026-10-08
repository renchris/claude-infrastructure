#!/usr/bin/env python3
"""Build one known-good research program under <root> for tests/research-kit-gate.bats.

Every one of the 16 gate rows passes on it, so each test can plant exactly one defect and assert that
exactly that row turns FAIL. Uses the caller's CC_RESEARCH_HOME, CC_RESEARCH_REGISTRY, CC_NOW and
CC_RESEARCH_VAULT_KEY. Prints the records dir.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
KIT = REPO / "scripts" / "research-kit"
sys.path.insert(0, str(KIT / "lib"))
sys.path.insert(0, str(REPO / "scripts" / "lib"))
import kit  # noqa: E402
import operator_sign  # noqa: E402

NOW = os.environ["CC_NOW"]
EARLIER = "2026-09-30T00:00:00Z"
PINS = {
    "anthropic": "claude-opus-5-5",
    "frontier": "claude-fable-5-1",
    "openai": "gpt-x",
    "google": "gemini-x",
}


def w(p: Path, obj: object) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(obj if isinstance(obj, str) else json.dumps(obj, indent=1) + "\n")


def jl(p: Path, rows: list) -> None:
    w(p, "".join(json.dumps(r) + "\n" for r in rows))


def git(repo: Path, *a: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *a], check=True, capture_output=True, text=True
    ).stdout.strip()


def probe(pid: str, kind: str, env: str, closes: list, nc: bool = True) -> dict:
    return {
        "id": pid,
        "kind": kind,
        "env": {"id": env},
        "closes": closes,
        "exit": 0,
        "n": 1,
        "stdin": "/dev/null",
        "negative_control": {"ran": True, "reported_refutation": True}
        if nc
        else {
            "ran": False,
            "reason_if_not_run": "an inventory read has no known-bad input",
        },
        "raw": f"evidence/{pid}/",
        "at": NOW,
    }


def main() -> None:
    root = Path(sys.argv[1])
    repo = root / "repo"
    rec = repo / "docs" / "research" / "demo"
    rec.mkdir(parents=True)
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "t@example.com")
    git(repo, "config", "user.name", "t")
    subprocess.run(
        [
            str(KIT / "gate.sh"),
            "register",
            "--program",
            "demo",
            "--root",
            str(repo),
            "--alias",
            "the demo",
        ],
        check=True,
        capture_output=True,
    )
    frame = {
        "program": "demo",
        "version": 1,
        "profile": "lite",
        "plan": "PLAN.md",
        "deliverable_repo": str(repo),
        "deliverable": "a sync daemon that loses 0 writes in 1000 trials",
        "reviewer_pins": PINS,
        "rulings": {
            "definition_of_complete": {"at": EARLIER, "quote": "yes"},
            "exemption": {"at": EARLIER, "quote": "yes"},
        },
        "fac_map": [
            {"fac": f"FAC-{i:02d}", "row": None, "na_reason": "fixture"}
            for i in range(1, 34)
        ],
        "reask_map": [{"frame": "deployed and live", "axis": "V7"}],
        "sources_required": ["E-1"],
        "populations": ["callers"],
        "components": [{"name": "daemon", "scheduled": True}],
        "topic_owner": "lead session",
        "contract_page_at": NOW,
        "credentials": [],
        "known_rows": [],
    }
    w(rec / "frame.json", frame)
    w(rec / "PLAN.md", "# Design\n\nThe daemon retries a failed write 3 times (P-1).\n")
    w(rec / "research.md", "# Findings\n\nCallers found by name.\n")
    w(rec / "fixtures" / "bad.txt", "failure\n")
    w(rec / "fixtures" / "good.txt", "ok\n")
    w(
        rec / "acceptance.json",
        {
            "rows": [
                {
                    "id": "AM-1",
                    "predicate": "loses 0 writes in 1000 trials",
                    "check_cmd": 'grep -q ok "$FIXTURE"',
                    "threshold": {"metric": "lost", "op": "==", "value": 0},
                    "negative_branch": "redesign the retry",
                    "control": {
                        "known_bad": "fixtures/bad.txt",
                        "known_good": "fixtures/good.txt",
                    },
                }
            ]
        },
    )
    w(
        rec / "census" / "callers.json",
        {
            "population": "callers",
            "members": [{"id": "a"}, {"id": "b"}],
            "methods": [
                {"agent": "x", "cmd": "printf 'a\\nb\\n'"},
                {"agent": "y", "cmd": "printf 'b\\na\\n'"},
            ],
            "critic": {"ran": True, "unlisted_verified": 0, "integrated": True},
        },
    )
    jl(
        rec / "sources.jsonl",
        [{"id": "E-1", "status": "consulted", "evidence": ["evidence/P-1"]}],
    )
    jl(
        rec / "premises.jsonl",
        [
            {
                "id": "PR-1",
                "truth_lives_in": "code",
                "verdict": "holds",
                "probes": ["P-1"],
                "load_bearing_for": ["DR-1"],
                "recheck_cmd": "true",
                "origin": {"tier": "E0"},
            }
        ],
    )
    prs = [
        probe("P-1", "read", "agent-shell", ["PR-1"]),
        probe("P-2", "read", "agent-shell", []),
        probe("P-3", "skeleton", "launchd-bash32", []),
        probe("P-4", "read", "interactive-zsh", []),
        dict(
            probe("P-doctor-1", "live-read", "interactive-zsh", [], nc=False),
            envs=["interactive-zsh", "launchd-bash32", "agent-shell"],
        ),
    ]
    jl(rec / "probes.jsonl", prs)
    for p in prs:
        w(rec / "evidence" / p["id"] / "stdout", "ok\n")
    jl(
        rec / "decisions.jsonl",
        [
            {
                "id": "DR-1",
                "question": "retry policy",
                "status": "ruled",
                "ruled_by": "agent",
                "options": [
                    {"label": "do-nothing"},
                    {"label": "use-what-exists"},
                    {"label": "retry"},
                ],
                "chosen": "retry",
                "tally": {
                    "premises": ["PR-1"],
                    "flip_probe": "P-2",
                    "flip_result": "negative",
                },
                "reversibility": "reversible",
                "runs_used": 1,
                "revisit_trigger": "a lost write in build",
            }
        ],
    )
    w(
        rec / "contact_matrix.json",
        {
            "rows": [
                {
                    "component": "daemon",
                    "cells": {
                        "H1": {
                            "applies": True,
                            "probes": ["P-3"],
                            "properties": [
                                "no lost write",
                                "eventually idle (liveness)",
                            ],
                        },
                        "H5": {"applies": False, "na_reason": "consumer is an agent"},
                    },
                }
            ]
        },
    )
    jl(
        rec / "holes.jsonl",
        [
            {
                "id": "H-1",
                "round": 1,
                "verification": {"status": "CONFIRMED"},
                "materiality": {"level": "MATERIAL"},
            }
        ],
    )
    jl(
        rec / "trace.jsonl",
        [
            {"from": "H-1", "to": "PLAN.md#design", "type": "implements"},
            {
                "from": "research.md#findings",
                "to": "PLAN.md#design",
                "type": "supports",
            },
        ],
    )
    jl(
        rec / "residual.jsonl",
        [
            {
                "id": "RS-1",
                "why_unreachable": "elapsed-time",
                "closest_probe": "P-1",
                "verify_cmd": "true",
                "owner": "agent",
                "due": "2026-11-01",
                "backlog_id": "b1",
                "falsifier": "true",
            }
        ],
    )
    jl(rec / "reconcile.jsonl", [{"id": "residual:RS-1", "disposition": "done"}])
    w(
        rec / "budget.json",
        {"stages": {"1": {"started": EARLIER, "ended": "2026-09-30T06:00:00Z"}}},
    )
    w(
        rec / "rehearsal.json",
        {
            "frames_typed": ["deployed and live"],
            "relay": {"trials": 20, "passed": True},
        },
    )
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "records")
    sha = git(repo, "rev-parse", "HEAD")
    plan = (rec / "PLAN.md").read_text()
    w(
        rec / "freeze.json",
        {
            "snapshot_sha": sha,
            "plan_blob": operator_sign.blob_sha(plan.encode()),
            "at": NOW,
        },
    )
    slots = [(v, s) for v in kit.VENDORS for s in ("full-context", "plan-only")]
    lenses = [{"lens": x, "result": "nothing material"} for x in kit.LENSES]
    for fc in (1, 2):
        w(
            rec / "rounds" / f"fc{fc}" / "matrix.json",
            {
                "round": f"fc{fc}",
                "seq": fc,
                "kind": "frame-critique",
                "closed": True,
                "counted": True,
            },
        )
    for n in (1, 2, 3):
        rid = str(n)
        sl = [
            {
                "pid": f"r{rid}p{i}",
                "vendor": v,
                "strategy": s,
                "status": "complete",
                "reruns": 0,
            }
            for i, (v, s) in enumerate(slots, 1)
        ]
        for x in sl:
            w(
                rec / "rounds" / rid / "panels" / f"{x['pid']}.json",
                {
                    "pid": x["pid"],
                    "status": "complete",
                    "responding_model": PINS[x["vendor"]],
                    "lenses": lenses,
                    "integrity": {"hits": []},
                },
            )
        m = {
            "round": rid,
            "seq": n,
            "kind": "certification",
            "snapshot_sha": sha,
            "verification_only": False,
            "slots": sl,
            "lanes": {v: "live" for v in kit.VENDORS},
            "counted": True,
            "closed": True,
            "new_material": 1 if n == 1 else 0,
            "quiet": n > 1,
        }
        if n == 1:
            m["forecast"] = {"p50": 3, "p90": 4}
        w(rec / "rounds" / rid / "matrix.json", m)
    sealed = kit.sealed_dir("demo", create=True)
    w(
        sealed / "preflight.json",
        {v: {"ok": True, "model_id": PINS[v], "at": EARLIER} for v in kit.VENDORS},
    )
    pin = operator_sign.file_pin(rec / "frame.json")
    jl(
        sealed / "signoff.jsonl",
        [
            {
                "row": "research:demo/frame",
                "action": "frame",
                "target": None,
                "at": 1.0,
                "at_iso": EARLIER,
                "pins": {"frame.json": pin},
                "provenance": {"claude_ancestor": False, "chain": ["zsh", "kitty"]},
            }
        ],
    )
    cands = []
    for i in range(12):
        cands += [
            {"prompt": f"are we done? #{i}", "stratum": "regex-matched"},
            {"prompt": f"is this all before we close #{i}", "stratum": "regex-missed"},
            {"prompt": f"really? #{i}", "stratum": "pushback"},
            {"prompt": f"build wave B1 now #{i}", "stratum": "other"},
        ]
    jl(root / "cands.jsonl", cands)
    hp = [str(KIT / "heldout.py")]
    subprocess.run(
        hp
        + [
            "seal",
            "--candidates",
            str(root / "cands.jsonl"),
            "--tuning-out",
            str(root / "tuning.jsonl"),
            "--fraction",
            "1.0",
        ],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        hp + ["rater-sheet", "--out", str(root / "sheet.jsonl")],
        check=True,
        capture_output=True,
    )
    gold = {
        "regex-matched": "completeness",
        "regex-missed": "completeness",
        "pushback": "pushback",
        "other": "work-order",
    }
    by_prompt = {c["prompt"]: gold[c["stratum"]] for c in cands}
    labels = [
        {"id": r["id"], "label": by_prompt[r["prompt"]]}
        for r in kit.read_jsonl(root / "sheet.jsonl")
    ]
    jl(root / "labels.jsonl", labels)
    for rater in ("rater-1", "rater-2"):
        subprocess.run(
            hp + ["label", "--rater", rater, "--labels", str(root / "labels.jsonl")],
            check=True,
            capture_output=True,
        )
    w(
        root / "router.sh",
        '#!/bin/bash\np="$(cat)"\ncase "$p" in\n  *done?*|*close*) echo completeness ;;\n'
        "  *really*) echo pushback ;;\n  *) echo work-order ;;\nesac\n",
    )
    os.chmod(root / "router.sh", 0o755)
    # Wave E1l: row 15 reads only after RULE E1k's real-load run passed, and at 1-min load <= 40, so
    # the known-good program records a passing run and plants a quiet machine (fixture homes only).
    w(root / "e1k-ab-run2.report.txt", "verdict (RULE E1k): PASS\n")
    subprocess.run(
        hp
        + ["real-load", "--run", "2", "--source", str(root / "e1k-ab-run2.report.txt")]
        + ["--rows", "120", "--fallbacks", "1", "--held", "0"],
        check=True,
        capture_output=True,
    )
    w(kit.research_home() / "router-heldout" / "load1.fixture", "5\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "rounds")
    print(rec)


if __name__ == "__main__":
    main()
