"""gate_rows_built.py — the built gate, rows 20-25 (REPORT.md §11, method v1.2).

Run only by `gate.sh built-run` (gate_built.py), never by the research gate. Each row function takes
a Ctx and returns a Row; a row that cannot be evaluated is FAIL ("Unknown fails", §3.10).
"""

from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

import kit
from gate import FAIL, FILED, PASS, Ctx, Row, reopened
from gate_rows_a import folded, probes, row, run_cmd, verdict
from gate_rows_b import cert_rounds

BUILT_ROWS = {20: "Built snapshot", 21: "Repro", 22: "Harness mutation", 23: "As-built contact",
              24: "Soak", 25: "Built rounds"}
ROWS: List[Callable[[Ctx], Row]] = []


def run_built_rows(ctx: Ctx) -> List[Row]:
    """Every row 20-25, in order. A missing or crashing row is a FAIL, never a pass."""
    out: List[Row] = []
    for fn in ROWS:
        try:
            out.append(fn(ctx))
        except Exception as e:
            num, name = getattr(fn, "row", (0, fn.__name__))
            out.append(Row(num, name, FAIL, [f"row raised {type(e).__name__}: {e}"]))
    have = {r.num for r in out}
    for n, name in BUILT_ROWS.items():
        if n not in have:
            out.append(Row(n, name, FAIL, ["row not implemented — unknown fails (§3.10)"]))
    return sorted(out, key=lambda r: r.num)


# ── what every row reads ────────────────────────────────────────────────────────────────────────


def freeze(ctx: Ctx) -> Dict[str, Any]:
    """built/freeze.json, or {} when it is absent or names no snapshot."""
    fz = ctx.json("built/freeze.json")
    return fz if isinstance(fz, dict) and fz.get("snapshot_sha") else {}


def no_freeze(n: int) -> Row:
    why = "built/freeze.json is missing: no built snapshot (run gate.sh built-freeze)"
    return Row(n, BUILT_ROWS[n], FAIL, [why])


def artifact_root(fz: Dict[str, Any]) -> Optional[Path]:
    root = Path(str(fz.get("artifact_root") or ""))
    return root if root.is_absolute() and root.is_dir() else None


def counted_rounds(ctx: Ctx) -> List[Dict[str, Any]]:
    return [m for m in cert_rounds(ctx, "built") if m.get("counted")]


def acceptance_ids(ctx: Ctx) -> List[str]:
    rows = (ctx.json("acceptance.json", {}) or {}).get("rows") or []
    return [str(r["id"]) for r in rows if r.get("id")]


# ── row 20 ──────────────────────────────────────────────────────────────────────────────────────


def research_cert_fails(ctx: Ctx) -> List[str]:
    """The research certificate is signed, has no FAIL row and no reopen after it."""
    import operator_sign

    certs = sorted(
        (ctx.records / "cert").glob("CERT-v*.json"),
        key=lambda p: int(re.sub(r"\D", "", p.stem) or 0),
    )
    if not certs:
        return ["no research certificate (cert/CERT-v*.json)"]
    cert, fails = certs[-1], []
    sig = operator_sign.latest_valid(ctx.slug, "cert")
    if not sig or f"cert/{cert.name}" not in (sig.get("pins") or {}):
        fails.append(f"no valid operator signature on research certificate {cert.stem}")
    rows = (kit.read_json(cert) or {}).get("rows") or {}
    bad = sorted((n for n, s in rows.items() if s not in (PASS, FILED)), key=int)
    if bad or not rows:
        fails.append(
            f"research certificate {cert.stem} has row(s) not passed: {', '.join(bad) or 'no rows'}"
        )
    if reopened(ctx):
        fails.append(f"a reopen is signed after research certificate {cert.stem}")
    return fails


def artifact_fails(fz: Dict[str, Any]) -> List[str]:
    """The built snapshot's commit is the artifact's HEAD now, on a clean tree."""
    root, sha = artifact_root(fz), fz["snapshot_sha"]
    if root is None:
        return [
            f"artifact_root {fz.get('artifact_root')!r} is not an existing absolute directory"
        ]
    rc, head = run_cmd("git rev-parse HEAD", root)
    if rc != 0:
        return [f"cannot read the artifact's HEAD in {root} (git exit {rc})"]
    fails = []
    if head.strip() != sha:
        fails.append(
            f"artifact HEAD {head.strip()[:12]} is not the built snapshot {sha[:12]}"
        )
    rc, dirty = run_cmd("git status --porcelain", root)
    if rc != 0 or dirty.strip():
        fails.append(
            f"artifact tree is dirty ({len(dirty.splitlines())} path(s), git exit {rc})"
        )
    return fails


@row(20, BUILT_ROWS[20])
def row20(ctx: Ctx) -> Row:
    fz = freeze(ctx)
    if not fz:
        return no_freeze(20)
    sha = fz["snapshot_sha"]
    fails = research_cert_fails(ctx)
    waves = ctx.frame.get("build_waves") or []
    undone = [str(w) for w in waves if w not in (fz.get("waves_done") or [])]
    if undone:
        fails.append(f"build wave(s) not recorded done: {', '.join(undone)}")
    fails += artifact_fails(fz)
    rounds = counted_rounds(ctx)
    if not rounds:
        fails.append("no counted built round examined the snapshot")
    elif rounds[-1].get("snapshot_sha") != sha:
        last = rounds[-1]
        fails.append(
            f"last counted built round {last.get('round')} examined "
            f"{str(last.get('snapshot_sha'))[:12]}, not the built snapshot {sha[:12]}"
        )
    note = f"snapshot {sha[:12]}; {len(waves)} build wave(s) named, all recorded done"
    return verdict(20, BUILT_ROWS[20], fails, [], [] if fails else [note])


# ── row 21 ──────────────────────────────────────────────────────────────────────────────────────


def repro_fails(fid: str, repro: Dict[str, Any], root: Optional[Path]) -> List[str]:
    """A recorded failing run of the finding's test command, and that command passing now."""
    red = repro.get("red") or {}
    if not isinstance(red.get("exit"), int) or red["exit"] == 0:
        return [f"{fid}: no tool-recorded failing run of its test command"]
    if not repro.get("test_cmd") or root is None:
        return [
            f"{fid}: its test command cannot be re-run (no command, or no artifact_root)"
        ]
    rc, _ = run_cmd(str(repro["test_cmd"]), root)
    return [] if rc == 0 else [f"{fid}: test command exits {rc} now on the snapshot"]


@row(21, BUILT_ROWS[21])
def row21(ctx: Ctx) -> Row:
    fz = freeze(ctx)
    if not fz:
        return no_freeze(21)
    root = artifact_root(fz)
    fails: List[str] = []
    rejected = material = 0
    for fid, f in sorted(folded(ctx, "built/findings.jsonl").items()):
        status = f.get("status")
        if status == "rejected-no-repro":
            rejected += 1
            continue
        if f.get("severity") != "material":
            continue
        material += 1
        if status != "fixed":
            fails.append(f"{fid}: material finding is {status}, not fixed")
        elif f.get("source") != "mutation":
            fails += repro_fails(fid, f.get("repro") or {}, root)
    note = f"{material} material finding(s), all fixed and re-run green; {rejected} rejected-no-repro"
    if fails:
        note = f"{rejected} rejected-no-repro"
    return verdict(21, BUILT_ROWS[21], fails, [], [note])


# ── row 22 ──────────────────────────────────────────────────────────────────────────────────────


def mutant_fails(ctx: Ctx, mutants: List[Dict[str, Any]]) -> List[str]:
    """The floor, one kill per acceptance row, no survivor, every 'equivalent' reasoned and rated."""
    fails: List[str] = []
    floor = kit.CAPS["mutants_min"]
    if len(mutants) < floor:
        fails.append(
            f"{len(mutants)} mutant(s), fewer than {floor} (invalid ones do not count)"
        )
    killed = [m for m in mutants if m.get("status") == "killed"]
    ids = acceptance_ids(ctx)
    if not ids:
        fails.append("acceptance.json names no row to mutate against")
    for rid in ids:
        n = sum(1 for m in killed if rid in (m.get("killed_by") or []))
        if n < kit.CAPS["mutants_per_row_min"]:
            fails.append(
                f"acceptance row {rid} killed {n} mutant(s): its check is untested"
            )
    survived = [str(m.get("id")) for m in mutants if m.get("status") == "survived"]
    if survived:
        fails.append(f"surviving mutant(s): {', '.join(survived)}")
    for m in mutants:
        eq = m.get("equivalent") or {}
        if m.get("status") == "equivalent" and not (
            eq.get("reason") and eq.get("rater")
        ):
            fails.append(f"equivalent mutant {m.get('id')} lacks a reason or a rater")
        elif m.get("status") not in ("killed", "survived", "equivalent"):
            fails.append(f"mutant {m.get('id')} has unknown status {m.get('status')!r}")
    return fails


@row(22, BUILT_ROWS[22])
def row22(ctx: Ctx) -> Row:
    fz = freeze(ctx)
    if not fz:
        return no_freeze(22)
    mu = ctx.json("built/mutation.json")
    if not isinstance(mu, dict):
        return Row(
            22,
            BUILT_ROWS[22],
            FAIL,
            ["built/mutation.json is missing: no mutation run"],
        )
    fails: List[str] = []
    if mu.get("snapshot_sha") != fz["snapshot_sha"]:
        fails.append(
            f"the mutation run is on {str(mu.get('snapshot_sha'))[:12]}, not the built snapshot"
        )
    if mu.get("baseline_exit") != 0:
        fails.append(f"the unmutated baseline exited {mu.get('baseline_exit')}, not 0")
    everyone = mu.get("mutants") or []
    mutants = [m for m in everyone if m.get("status") != "invalid"]
    fails += mutant_fails(ctx, mutants)
    killed = sum(1 for m in mutants if m.get("status") == "killed")
    scored = killed + sum(1 for m in mutants if m.get("status") == "survived")
    rate = f"{100.0 * killed / scored:.0f}%" if scored else "undefined"
    equivalent = sum(1 for m in mutants if m.get("status") == "equivalent")
    note = (
        f"kill rate {killed}/{scored} = {rate}; {equivalent} equivalent, "
        f"{len(everyone) - len(mutants)} invalid"
    )
    return verdict(22, BUILT_ROWS[22], fails, [], [note])


# ── row 23 ──────────────────────────────────────────────────────────────────────────────────────


def contact_fails(target: str, rec: Dict[str, Any]) -> List[str]:
    """One as-built run: exit 0, the as-built environment, a negative control or a reason."""
    env, want = rec.get("env") or {}, kit.AS_BUILT_ENV
    checks = (
        ("home_clean", env.get("home_clean") is True),
        ("path", env.get("path") == want["path"]),
        ("interpreter", env.get("interpreter") == want["interpreter"]),
        (
            "interpreter_version",
            str(env.get("interpreter_version") or "").startswith(
                want["interpreter_major"]
            ),
        ),
    )
    fails: List[str] = []
    if rec.get("exit") != 0:
        fails.append(f"{target}: as-built run exits {rec.get('exit')}")
    bad = [k for k, ok in checks if not ok]
    if bad:
        fails.append(f"{target}: environment is not as-built ({', '.join(bad)})")
    nc = rec.get("negative_control") or {}
    refuted = nc.get("ran") and nc.get("reported_refutation") is True
    if not (refuted or nc.get("reason_if_not_run")):
        fails.append(f"{target}: no negative control and no reason")
    return fails


@row(23, BUILT_ROWS[23])
def row23(ctx: Ctx) -> Row:
    fz = freeze(ctx)
    if not fz:
        return no_freeze(23)
    required = sorted(
        p for p, v in probes(ctx).items() if v.get("kind") in kit.AS_BUILT_KINDS
    )
    accept = acceptance_ids(ctx)
    fails = [] if accept else ["acceptance.json names no row to contact"]
    newest: Dict[str, Dict[str, Any]] = {}
    for rec in ctx.jsonl("built/contact.jsonl"):
        if rec.get("snapshot_sha") != fz["snapshot_sha"]:
            continue
        old = newest.get(str(rec.get("target")))
        if old is None or str(rec.get("at") or "") >= str(old.get("at") or ""):
            newest[str(rec.get("target"))] = rec
    for target in required + accept:
        if target not in newest:
            fails.append(f"{target}: no as-built run on this snapshot")
        else:
            fails += contact_fails(target, newest[target])
    note = f"{len(required)} as-built probe(s) and {len(accept)} acceptance row(s) run as built"
    return verdict(23, BUILT_ROWS[23], fails, [], [] if fails else [note])


# ── row 24 ──────────────────────────────────────────────────────────────────────────────────────


def boundary_side(kind: str, t: float) -> Any:
    """Which side of every instant of this kind `t` is on; None for a kind the gate cannot compute."""
    if kind == "hour":
        return int(t // 3600)
    if kind == "utc-midnight":
        return int(t // 86400)
    if kind == "local-midnight":
        return tuple(time.localtime(t)[:3])
    return None


def crossed(kind: str, passing: List[float]) -> bool:
    """Passing samples exist both before and after one instant of this kind."""
    if not passing or boundary_side(kind, passing[0]) is None:
        return False
    return boundary_side(kind, min(passing)) != boundary_side(kind, max(passing))


def boundary_residuals(ctx: Ctx) -> Set[str]:
    """Boundaries declared unreachable for elapsed time, each with an owner and a date."""
    return {
        str(r.get("boundary"))
        for r in ctx.jsonl("residual.jsonl")
        if r.get("why_unreachable") == "elapsed-time"
        and r.get("owner")
        and r.get("due")
    }


def soak_samples(
    ctx: Ctx, sha: str, restarts: List[Dict[str, Any]]
) -> List[Tuple[float, Any]]:
    """(epoch, exit) of every sample on this snapshot taken after the last restart."""
    since = kit.parse_iso(restarts[-1]["at"]) if restarts else None
    out = [
        (kit.parse_iso(s["at"]), s.get("exit"))
        for s in ctx.jsonl("built/soak.jsonl")
        if s.get("snapshot_sha") == sha
    ]
    return [x for x in out if since is None or x[0] > since]


@row(24, BUILT_ROWS[24])
def row24(ctx: Ctx) -> Row:
    fz = freeze(ctx)
    if not fz:
        return no_freeze(24)
    soak = ctx.json("built/soak.json")
    if not isinstance(soak, dict):
        return Row(
            24,
            BUILT_ROWS[24],
            FAIL,
            ["built/soak.json is missing: no soak was started"],
        )
    restarts = soak.get("restarts") or []
    samples = soak_samples(ctx, fz["snapshot_sha"], restarts)
    times = [t for t, _ in samples]
    hours = (max(times) - min(times)) / 3600.0 if times else 0.0
    caps = kit.CAPS
    fails: List[str] = []
    if hours < caps["soak_min_hours"]:
        fails.append(
            f"samples span {hours:.1f}h, under the {caps['soak_min_hours']}h minimum"
        )
    if len(samples) < caps["soak_min_samples"]:
        fails.append(f"{len(samples)} sample(s), fewer than {caps['soak_min_samples']}")
    failing = sum(1 for _, rc in samples if rc != 0)
    if failing:
        fails.append(f"{failing} failing sample(s) since the last fix")
    if len(restarts) > caps["soak_restarts"]:
        fails.append(f"{len(restarts)} restart(s), more than {caps['soak_restarts']}")
    passing = [t for t, rc in samples if rc == 0]
    declared, filed = boundary_residuals(ctx), []
    for kind in ctx.frame.get("soak_boundaries") or kit.SOAK_BOUNDARIES:
        if crossed(kind, passing):
            continue
        if kind in declared:
            filed.append(
                f"boundary {kind}: not crossed, declared an elapsed-time residual"
            )
        else:
            fails.append(
                f"boundary {kind}: not crossed, and no elapsed-time residual declares it"
            )
    note = (
        f"{len(samples)} sample(s) over {hours:.1f}h after {len(restarts)} restart(s)"
    )
    return verdict(24, BUILT_ROWS[24], fails, filed, [note])


# ── row 25 ──────────────────────────────────────────────────────────────────────────────────────


def round_fails(m: Dict[str, Any]) -> List[str]:
    """Every slot complete, and enough vendor families among the slots."""
    rid, slots = m.get("round"), m.get("slots") or []
    fails = [
        f"round {rid}: slot {s.get('pid')} is {s.get('status')}, not complete"
        for s in slots
        if s.get("status") != "complete"
    ]
    families = {kit.VENDOR_FAMILY.get(str(s.get("vendor"))) for s in slots} - {None}
    if len(families) < kit.CAPS["built_min_families"]:
        noun = "family" if len(families) == 1 else "families"
        fails.append(
            f"round {rid}: {len(families)} vendor {noun}, fewer than {kit.CAPS['built_min_families']}"
        )
    return fails


@row(25, BUILT_ROWS[25])
def row25(ctx: Ctx) -> Row:
    fz = freeze(ctx)
    if not fz:
        return no_freeze(25)
    prof = kit.profile(str(ctx.frame.get("profile")))
    cap, quiet_k = prof["built_hard_cap"], prof["quiet_to_stop"]
    rounds = counted_rounds(ctx)
    fails: List[str] = []
    if not any(m.get("snapshot_sha") == fz["snapshot_sha"] for m in rounds):
        fails.append("no counted built round on this snapshot")
    for m in rounds:
        fails += round_fails(m)
    quiet = len(rounds) >= quiet_k and all(m.get("quiet") for m in rounds[-quiet_k:])
    if len(rounds) > cap:
        fails.append(f"{len(rounds)} counted built round(s), past the cap of {cap}")
    elif not quiet and len(rounds) < cap:
        fails.append(
            f"built rounds have not stopped: the last {quiet_k} counted round(s) are not all "
            f"quiet and {len(rounds)} of {cap} ran"
        )
    note = f"stop {'quiet' if quiet else 'cap'} after {len(rounds)} counted built round(s) of {cap}"
    return verdict(25, BUILT_ROWS[25], fails, [], [] if fails else [note])


ROWS = [row20, row21, row22, row23, row24, row25]
