"""built.py — the code-native instruments of Stage 9 (REPORT.md §11, method v1.2).

Four instruments over the built snapshot pinned in built/freeze.json:
  findings   a material finding is admitted only with a test command this module ran and saw fail
  mutation   sealed mutants applied one at a time to a COPY of the artifact; the acceptance
             harness must fail on each (a survivor is a hole in the harness, and a finding)
  contact    a probe or acceptance check re-run from an empty environment: a fresh empty HOME,
             PATH=/usr/bin:/bin, the scheduler's /bin/bash
  soak       the acceptance checks sampled on a schedule, across time boundaries

Record shapes: RECORDS.md "Stage 9 records". Every value the spec calls "recorded by the tool"
(exit codes, shas, the environment) is computed here, never taken from a flag. The gate rows that
read these records are gate_rows_built.py. Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import shlex
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import kit

TIMEOUT = 120
BASH = kit.AS_BUILT_ENV["interpreter"]
CLEAN_PATH = kit.AS_BUILT_ENV["path"]


# ── the snapshot ────────────────────────────────────────────────────────────────────────────────


def freeze(ctx: Any) -> Dict[str, Any]:
    """built/freeze.json, or a refusal: Stage 9 needs a 1.2 frame and a pinned built snapshot."""
    if not kit.is_v12(ctx.frame):
        raise kit.KitError(
            "Stage 9 applies to a frame signed under method 1.2 or later (REPORT.md §11)"
        )
    fz = ctx.json("built/freeze.json")
    if not fz or not fz.get("artifact_root") or not fz.get("snapshot_sha"):
        raise kit.KitError(
            "no built snapshot: run `gate.sh built-freeze` after the last build wave"
        )
    if not Path(fz["artifact_root"]).is_dir():
        raise kit.KitError(f"built artifact {fz['artifact_root']} is not a directory")
    return fz


def head_sha(root: str) -> Optional[str]:
    p = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def run(cmd: str, cwd: str, env: Optional[Dict[str, str]] = None) -> int:
    """One shell command; its exit code (124 on timeout, 127 if it cannot start)."""
    import os

    try:
        return subprocess.run(
            [BASH, "-c", cmd], cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True,
            timeout=TIMEOUT, env=dict(os.environ, **(env or {})),
        ).returncode
    except subprocess.TimeoutExpired:
        return 124
    except OSError:
        return 127


def clean_run(cmd: str, root: str) -> Tuple[int, Dict[str, Any]]:
    """The as-built run (§11 instrument 3): `env -i`, a fresh empty HOME, PATH=/usr/bin:/bin,
    /bin/bash. Returns (exit, the environment as set and measured)."""
    with tempfile.TemporaryDirectory(prefix="cc-built-home.") as home:
        empty = not any(Path(home).iterdir())
        base = ["/usr/bin/env", "-i", f"HOME={home}", f"PATH={CLEAN_PATH}"]
        ver = subprocess.run(base + [BASH, "-c", "echo $BASH_VERSION"], capture_output=True,
                             text=True).stdout.strip()
        try:
            rc = subprocess.run(
                base + [f"ARTIFACT={root}", BASH, "-c", cmd], cwd=root,
                stdin=subprocess.DEVNULL, capture_output=True, timeout=TIMEOUT,
            ).returncode
        except subprocess.TimeoutExpired:
            rc = 124
        except OSError:
            rc = 127
        env = {"home": home, "home_clean": empty, "path": CLEAN_PATH, "interpreter": BASH,
               "interpreter_version": ver}
    return rc, env


def acceptance_rows(ctx: Any) -> List[Dict[str, Any]]:
    rows = [r for r in (ctx.json("acceptance.json", {}) or {}).get("rows") or []
            if r.get("id") and r.get("check_cmd")]
    if not rows:
        raise kit.KitError("acceptance.json has no row with a check_cmd: there is no harness")
    return rows


# ── findings ────────────────────────────────────────────────────────────────────────────────────


def findings_path(ctx: Any) -> Path:
    return ctx.path("built/findings.jsonl")


def findings(ctx: Any) -> Dict[str, Dict[str, Any]]:
    return kit.fold(ctx.jsonl("built/findings.jsonl"))


def add_finding(ctx: Any, source: str, claim: str, severity: str,
                test_cmd: Optional[str] = None, mutant: Optional[str] = None) -> Dict[str, Any]:
    """Append one finding. A material finding is `open` only when its test command failed here,
    or it names a surviving mutant (the mutant is then its repro); otherwise rejected-no-repro."""
    fz = freeze(ctx)
    rec: Dict[str, Any] = {"source": source, "claim": claim, "severity": severity,
                           "status": "open", "repro": None, "mutant": mutant}
    if test_cmd:
        rc = run(test_cmd, fz["artifact_root"])
        red = {"sha": fz["snapshot_sha"], "exit": rc, "at": kit.now_iso()} if rc != 0 else None
        rec["repro"] = {"test_cmd": test_cmd, "red": red, "green": None}
        if severity == "material" and red is None:
            rec["status"] = "rejected-no-repro"
    elif severity == "material":
        survived = mutant and mutant_record(ctx, mutant).get("status") == "survived"
        if not survived:
            rec["status"] = "rejected-no-repro"
    rec["id"] = kit.mint_id(findings_path(ctx), "BF")
    kit.append_jsonl(findings_path(ctx), rec)
    return rec


def fix_finding(ctx: Any, fid: str) -> Tuple[bool, Dict[str, Any]]:
    """Re-run the finding's repro. (True, record) and status fixed when it now passes."""
    fz = freeze(ctx)
    f = findings(ctx).get(fid)
    if not f:
        raise kit.KitError(f"no built finding {fid}")
    if f.get("status") != "open":
        raise kit.KitError(f"{fid} is {f.get('status')}, not open")
    root = fz["artifact_root"]
    if f.get("mutant"):
        ok = rerun_mutant(ctx, str(f["mutant"]))
        rc = 0 if ok else 1
        repro = {"test_cmd": None, "red": None, "green": None}
    elif (f.get("repro") or {}).get("test_cmd"):
        rc = run(f["repro"]["test_cmd"], root)
        repro = dict(f["repro"])
    else:
        raise kit.KitError(f"{fid} has no repro to re-run")
    if rc != 0:
        return False, f
    repro["green"] = {"sha": head_sha(root), "exit": 0, "at": kit.now_iso()}
    upd = {"id": fid, "status": "fixed", "repro": repro}
    kit.append_jsonl(findings_path(ctx), upd)
    return True, dict(f, **upd)


# ── mutation testing of the acceptance harness ──────────────────────────────────────────────────


def mutants_path(ctx: Any) -> Path:
    return kit.sealed_dir(ctx.slug) / "built" / "mutants.json"


def load_mutants(ctx: Any) -> List[Dict[str, Any]]:
    ms = kit.read_json(mutants_path(ctx))
    if not ms:
        raise kit.KitError(f"no sealed mutants at {mutants_path(ctx)}")
    return list(ms)


def mutation(ctx: Any) -> Dict[str, Any]:
    return ctx.json("built/mutation.json") or {}


def in_record(rec: Dict[str, Any], mid: str) -> Dict[str, Any]:
    """The mutant's entry INSIDE rec, so an update to it is written back with rec."""
    return next((m for m in rec.get("mutants") or [] if m.get("id") == mid), {})


def mutant_record(ctx: Any, mid: str) -> Dict[str, Any]:
    return in_record(mutation(ctx), mid)


def harness(ctx: Any, tree: str) -> List[str]:
    """The ids of the acceptance rows that FAIL against this tree."""
    return [r["id"] for r in acceptance_rows(ctx)
            if run(r["check_cmd"], tree, {"ARTIFACT": tree}) != 0]


def run_mutant(ctx: Any, root: str, m: Dict[str, Any]) -> Tuple[str, List[str]]:
    """Apply one mutant to a fresh copy and run the harness: (status, killed_by)."""
    with tempfile.TemporaryDirectory(prefix="cc-built-mutant.") as tmp:
        tree = str(Path(tmp) / "artifact")
        shutil.copytree(root, tree, ignore=shutil.ignore_patterns(".git"), symlinks=True)
        target = Path(tree) / str(m.get("file"))
        if not target.is_file() or str(m.get("search")) not in target.read_text():
            return "invalid", []
        target.write_text(target.read_text().replace(str(m["search"]), str(m["replace"]), 1))
        failing = harness(ctx, tree)
    return ("killed" if failing else "survived"), failing


def tally(rec: Dict[str, Any]) -> Dict[str, Any]:
    killed = sum(1 for m in rec["mutants"] if m["status"] == "killed")
    survived = sum(1 for m in rec["mutants"] if m["status"] == "survived")
    rec.update(killed=killed, survived=survived,
               kill_rate=round(killed / (killed + survived), 4) if killed + survived else None)
    return rec


def mutate(ctx: Any) -> Dict[str, Any]:
    """Run every sealed mutant against the harness and write built/mutation.json."""
    fz = freeze(ctx)
    root = fz["artifact_root"]
    with tempfile.TemporaryDirectory(prefix="cc-built-base.") as tmp:
        base = str(Path(tmp) / "artifact")
        shutil.copytree(root, base, ignore=shutil.ignore_patterns(".git"), symlinks=True)
        failing = harness(ctx, base)
    if failing:
        raise kit.KitError(
            f"the harness fails on the unmutated artifact (rows {', '.join(failing)}): a "
            "mutation run needs a passing baseline"
        )
    prior = {m["id"]: m for m in mutation(ctx).get("mutants") or []
             if mutation(ctx).get("snapshot_sha") == fz["snapshot_sha"]}
    out: List[Dict[str, Any]] = []
    for m in load_mutants(ctx):
        old = prior.get(m["id"], {})
        if old.get("status") == "equivalent":
            out.append(old)
            continue
        status, by = run_mutant(ctx, root, m)
        out.append({"id": m["id"], "status": status, "killed_by": by, "equivalent": None,
                    "rerun": int(old.get("rerun") or 0)})
    rec = tally({"snapshot_sha": fz["snapshot_sha"], "at": kit.now_iso(), "baseline_exit": 0,
                 "rows": [r["id"] for r in acceptance_rows(ctx)], "mutants": out})
    kit.write_json_atomic(ctx.path("built/mutation.json"), rec)
    have = {f.get("mutant") for f in findings(ctx).values()}
    for m in out:
        if m["status"] == "survived" and m["id"] not in have:
            add_finding(ctx, "mutation", f"the acceptance harness does not fail on mutant {m['id']}",
                        "material", mutant=m["id"])
    return rec


def rerun_mutant(ctx: Any, mid: str) -> bool:
    """Re-run one surviving mutant after a harness fix (capped). True when it is now killed."""
    fz = freeze(ctx)
    rec = mutation(ctx)
    cur = in_record(rec, mid)
    if cur.get("status") != "survived":
        raise kit.KitError(f"mutant {mid} is {cur.get('status')!r}, not a survivor")
    cap = kit.CAPS["mutation_reruns_per_survivor"]
    if int(cur.get("rerun") or 0) >= cap:
        raise kit.KitError(
            f"mutant {mid} was already re-run {cur['rerun']} time(s); the cap is {cap} per "
            "survivor (§11), so it stays a named known row"
        )
    spec = next((m for m in load_mutants(ctx) if m.get("id") == mid), None)
    if spec is None:
        raise kit.KitError(f"mutant {mid} is not in the sealed set")
    status, by = run_mutant(ctx, fz["artifact_root"], spec)
    cur.update(status=status, killed_by=by, rerun=int(cur.get("rerun") or 0) + 1)
    kit.write_json_atomic(ctx.path("built/mutation.json"), tally(rec))
    return status == "killed"


def mark_equivalent(ctx: Any, mid: str, reason: str, rater: str) -> Dict[str, Any]:
    """A surviving mutant no test can tell from the original: needs a reason and a rater."""
    freeze(ctx)
    if not reason or not rater:
        raise kit.KitError("an equivalent mutant needs both --reason and --rater (§11 row 22)")
    rec = mutation(ctx)
    cur = in_record(rec, mid)
    if cur.get("status") != "survived":
        raise kit.KitError(f"mutant {mid} is {cur.get('status')!r}: only a survivor can be equivalent")
    cur.update(status="equivalent", equivalent={"reason": reason, "rater": rater})
    kit.write_json_atomic(ctx.path("built/mutation.json"), tally(rec))
    for f in findings(ctx).values():  # no failing test can exist for an equivalent mutant
        if f.get("mutant") == mid and f.get("status") == "open":
            kit.append_jsonl(findings_path(ctx), {"id": f["id"], "status": "rejected-no-repro"})
    return cur


# ── as-built contact and soak ───────────────────────────────────────────────────────────────────


def target_cmd(ctx: Any, target: str) -> str:
    probe = kit.fold(ctx.jsonl("probes.jsonl")).get(target)
    if probe:
        cmd = probe.get("cmd")
        if not cmd:
            raise kit.KitError(f"probe {target} has no recorded cmd to re-run")
        return cmd if isinstance(cmd, str) else shlex.join(str(c) for c in cmd)
    row = next((r for r in acceptance_rows(ctx) if r["id"] == target), None)
    if row is None:
        raise kit.KitError(f"{target} is neither a probe nor an acceptance row of {ctx.slug}")
    return str(row["check_cmd"])


def contact(ctx: Any, target: str, negative_control: Optional[str],
            no_negative_control: Optional[str]) -> Dict[str, Any]:
    fz = freeze(ctx)
    if not negative_control and not no_negative_control:
        raise kit.KitError(
            "every probe that can fail is shown able to fail (§3.4): pass --negative-control "
            "'<cmd>' or --no-negative-control '<reason>'"
        )
    cmd = target_cmd(ctx, target)
    root = fz["artifact_root"]
    rc, env = clean_run(cmd, root)
    nc: Dict[str, Any] = {"ran": False, "exit": None, "reported_refutation": None,
                          "reason_if_not_run": no_negative_control}
    if negative_control:
        nrc, _ = clean_run(negative_control, root)
        nc = {"ran": True, "exit": nrc, "reported_refutation": nrc != 0,
              "reason_if_not_run": None, "against": negative_control}
    path = ctx.path("built/contact.jsonl")
    rec = {"id": kit.mint_id(path, "BC"), "target": target, "snapshot_sha": fz["snapshot_sha"],
           "cmd": cmd, "env": env, "exit": rc, "negative_control": nc, "at": kit.now_iso()}
    kit.append_jsonl(path, rec)
    return rec


def soak_sample(ctx: Any) -> List[Dict[str, Any]]:
    """One sample per acceptance row, each run the as-built way."""
    fz = freeze(ctx)
    plan = ctx.json("built/soak.json") or {}
    if not plan.get("started"):
        plan.update(started=kit.now_iso(), restarts=plan.get("restarts") or [])
        kit.write_json_atomic(ctx.path("built/soak.json"), plan)
    out = []
    for r in acceptance_rows(ctx):
        rc, _ = clean_run(str(r["check_cmd"]), fz["artifact_root"])
        rec = {"at": kit.now_iso(), "check": r["id"], "exit": rc,
               "snapshot_sha": fz["snapshot_sha"]}
        kit.append_jsonl(ctx.path("built/soak.jsonl"), rec)
        out.append(rec)
    return out


def soak_restart(ctx: Any, finding: str) -> Dict[str, Any]:
    freeze(ctx)
    if finding not in findings(ctx):
        raise kit.KitError(f"no built finding {finding}: a soak restarts after a fix on record")
    plan = ctx.json("built/soak.json") or {}
    restarts = list(plan.get("restarts") or [])
    cap = kit.CAPS["soak_restarts"]
    if len(restarts) >= cap:
        raise kit.KitError(
            f"the soak was already restarted {len(restarts)} time(s); the cap is {cap} (§11), "
            "so the failing check becomes a named known row with an owner"
        )
    restarts.append({"at": kit.now_iso(), "finding": finding})
    plan.update(restarts=restarts)
    plan.setdefault("started", kit.now_iso())
    kit.write_json_atomic(ctx.path("built/soak.json"), plan)
    return plan


def summary(ctx: Any) -> Dict[str, Any]:
    fz = freeze(ctx)
    fs = list(findings(ctx).values())
    mat = [f for f in fs if f.get("severity") == "material"]
    mu = mutation(ctx)
    return {
        "program": ctx.slug, "snapshot_sha": fz["snapshot_sha"],
        "findings": {s: sum(1 for f in mat if f.get("status") == s)
                     for s in ("open", "fixed", "rejected-no-repro")},
        "mutants": {k: mu.get(k) for k in ("killed", "survived", "kill_rate")},
        "contact_runs": len(ctx.jsonl("built/contact.jsonl")),
        "soak_samples": len(ctx.jsonl("built/soak.jsonl")),
        "soak_restarts": len((ctx.json("built/soak.json") or {}).get("restarts") or []),
    }
