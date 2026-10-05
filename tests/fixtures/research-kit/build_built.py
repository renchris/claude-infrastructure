#!/usr/bin/env python3
"""build_built.py <dir> [resign|reopen] — turn build_good.py's program `demo` into a known-good
Stage 9 (built gate) fixture: method v1.2, a small git repo as the built artifact, a signed research
certificate, and one passing set of Stage 9 records (RECORDS.md "Stage 9 records"). Every date is
relative to $CC_NOW.

  resign   append a fresh operator `cert` signature pinning the certificate as it is now
  reopen   append an operator `reopen` signature dated after the certificate
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_good  # noqa: E402
from build_good import git, jl, kit, operator_sign, w  # noqa: E402

NOW = os.environ["CC_NOW"]
T0 = kit.parse_iso(NOW)
HOUR = 3600.0
SOAK_HOURS = 30
PROVENANCE = {"claude_ancestor": False, "chain": ["zsh", "kitty"]}


def iso(t: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def sign(rec: Path, action: str, at: float) -> None:
    pins = {}
    if action == "cert":
        pins = {
            "cert/CERT-v1.json": operator_sign.file_pin(rec / "cert" / "CERT-v1.json")
        }
    kit.append_jsonl(
        kit.sealed_dir("demo") / "signoff.jsonl",
        {
            "row": f"research:demo/{action}",
            "action": action,
            "target": None,
            "at": at,
            "at_iso": iso(at),
            "pins": pins,
            "provenance": PROVENANCE,
        },
    )


def artifact(root: Path) -> str:
    repo = root / "artifact"
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "t@example.com")
    git(repo, "config", "user.name", "t")
    w(repo / "daemon.sh", "#!/bin/bash\necho ok\n")
    git(repo, "add", "daemon.sh")
    git(repo, "commit", "-q", "-m", "built artifact")
    return git(repo, "rev-parse", "HEAD")


def contact(n: int, target: str, sha: str) -> dict:
    return {
        "id": f"BC-{n}",
        "target": target,
        "snapshot_sha": sha,
        "cmd": "test -f daemon.sh",
        "env": {
            "home": "/private/tmp/empty-home",
            "home_clean": True,
            "path": kit.AS_BUILT_ENV["path"],
            "interpreter": kit.AS_BUILT_ENV["interpreter"],
            "interpreter_version": kit.AS_BUILT_ENV["interpreter_major"]
            + ".57(1)-release",
        },
        "exit": 0,
        "negative_control": {"ran": True, "exit": 1, "reported_refutation": True},
        "at": NOW,
    }


def built_round(rec: Path, n: int, sha: str) -> None:
    slots = [
        {
            "pid": f"b{n}p{i}",
            "vendor": v,
            "strategy": "full-context",
            "status": "complete",
            "reruns": 0,
        }
        for i, v in enumerate(kit.VENDORS, 1)
    ]
    w(
        rec / "rounds" / f"b{n}" / "matrix.json",
        {
            "round": f"b{n}",
            "seq": n,
            "kind": "built",
            "snapshot_sha": sha,
            "slots": slots,
            "counted": True,
            "closed": True,
            "new_material": 0,
            "quiet": True,
        },
    )


def build(root: Path) -> None:
    rec = root / "repo" / "docs" / "research" / "demo"
    frame = kit.read_json(rec / "frame.json")
    frame.update(method_version="1.2", build_waves=["B1", "B2"])
    w(rec / "frame.json", frame)
    w(
        rec / "cert" / "CERT-v1.json",
        {
            "cert": "CERT-v1",
            "program": "demo",
            "version": 1,
            "rows": {str(n): "PASS" for n in range(1, 20)},
        },
    )
    sign(rec, "cert", time.time())
    sha = artifact(root)
    built = rec / "built"
    w(
        built / "freeze.json",
        {
            "snapshot_sha": sha,
            "artifact_root": str(root / "artifact"),
            "frozen_at": NOW,
            "research_cert": "CERT-v1",
            "waves_done": ["B1", "B2"],
        },
    )
    run = {"sha": sha, "at": NOW}
    jl(
        built / "findings.jsonl",
        [
            {
                "id": "BF-1",
                "source": "round",
                "claim": "the daemon script is absent",
                "severity": "material",
                "status": "fixed",
                "repro": {
                    "test_cmd": "test -f daemon.sh",
                    "red": dict(run, exit=1),
                    "green": dict(run, exit=0),
                },
                "mutant": None,
            },
            {
                "id": "BF-2",
                "source": "round",
                "claim": "the retry might be slow",
                "severity": "material",
                "status": "rejected-no-repro",
                "repro": None,
                "mutant": None,
            },
            {
                "id": "BF-3",
                "source": "mutation",
                "claim": "mutant M-3 survived",
                "severity": "material",
                "status": "fixed",
                "repro": None,
                "mutant": "M-3",
            },
        ],
    )
    need = kit.CAPS["mutants_min"]
    mutants = [
        {
            "id": f"M-{i}",
            "status": "killed",
            "killed_by": ["AM-1"],
            "equivalent": None,
            "rerun": 0,
        }
        for i in range(1, need + 1)
    ]
    mutants.append(
        {
            "id": f"M-{need + 1}",
            "status": "equivalent",
            "killed_by": [],
            "equivalent": {"reason": "the branch is unreachable", "rater": "codex"},
            "rerun": 0,
        }
    )
    mutants.append(
        {
            "id": f"M-{need + 2}",
            "status": "invalid",
            "killed_by": [],
            "equivalent": None,
            "rerun": 0,
        }
    )
    w(
        built / "mutation.json",
        {
            "snapshot_sha": sha,
            "at": NOW,
            "baseline_exit": 0,
            "rows": ["AM-1"],
            "mutants": mutants,
            "killed": need,
            "survived": 0,
            "kill_rate": 1.0,
        },
    )
    jl(built / "contact.jsonl", [contact(1, "P-3", sha), contact(2, "AM-1", sha)])
    jl(
        built / "soak.jsonl",
        [
            {"at": iso(T0 - h * HOUR), "check": "AM-1", "exit": 0, "snapshot_sha": sha}
            for h in range(SOAK_HOURS, -1, -1)
        ],
    )
    w(built / "soak.json", {"started": iso(T0 - SOAK_HOURS * HOUR), "restarts": []})
    for n in (1, 2):
        built_round(rec, n, sha)
    kit.registry_set("demo", "build-certifying")


def main() -> None:
    root = Path(sys.argv[1])
    rec = root / "repo" / "docs" / "research" / "demo"
    verb = sys.argv[2] if len(sys.argv) > 2 else "build"
    if verb == "resign":
        sign(rec, "cert", time.time())
    elif verb == "reopen":
        sign(rec, "reopen", time.time() + HOUR)
    else:
        build(root)


if __name__ == "__main__":
    assert build_good  # imported for its helpers
    main()
