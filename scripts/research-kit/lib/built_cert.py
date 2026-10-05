"""built_cert.py — the built certificate and its split forecast (REPORT.md §11, method v1.2).

`gate.sh built-run` calls `write_built_certificate` once rows 20-25 all pass. The certificate
states BOTH halves of the forecast:

  before implementation signoff   observed: counted changes since the research signoff plus the
                                  material Stage 9 findings, beside the research forecast of it
  after implementation signoff    forecast: material findings x (1 - k) / k, where k is the
                                  harness's FIRST-PASS mutant kill rate (a mutant killed only after
                                  a harness fix counts as missed), plus the research certificate's
                                  invisible estimate scaled by (1 - build-findable share).
                                  The 95% bound uses the Wilson lower bound of k, and the
                                  invisible bound unscaled: an assumed share may not tighten a bound.

Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional

import kit

Z95 = 1.96
NO_KILL = "no mutant killed: the after-implementation forecast cannot be stated"


def kill_rate_lower95(killed: int, total: int) -> float:
    """The Wilson 95% lower bound of killed / total."""
    if total <= 0 or killed <= 0:
        raise kit.KitError(NO_KILL)
    p = killed / total
    z2 = Z95 * Z95
    centre = p + z2 / (2 * total)
    spread = Z95 * math.sqrt(p * (1 - p) / total + z2 / (4 * total * total))
    return max(0.0, (centre - spread) / (1 + z2 / total))


def after_impl(material: int, killed: int, total: int, invisible_mean: float,
               invisible_bound95: float, share: float) -> Dict[str, float]:
    """The forecast of material changes after implementation signoff: mean and 95% bound."""
    c = kill_rate_lower95(killed, total)  # refuses 0 killed, so neither division can be by zero
    k = killed / total
    return {
        "after_mean": round(material * (1 - k) / k + (1 - share) * invisible_mean, 2),
        "after_bound95": math.ceil(material * (1 - c) / c + invisible_bound95),
        "kill_rate": round(k, 4),
        "kill_rate_lower95": round(c, 4),
    }


def research_cert(ctx: Any) -> Dict[str, Any]:
    certs = sorted((ctx.records / "cert").glob("CERT-v*.json"),
                   key=lambda p: int("".join(ch for ch in p.stem if ch.isdigit()) or 0))
    if not certs:
        raise kit.KitError(f"{ctx.slug} has no research certificate: Stage 9 follows Stage 8")
    return kit.read_json(certs[-1])


def first_pass(mutation: Dict[str, Any]) -> Dict[str, int]:
    """Mutants the harness killed before any harness fix, of those it could have killed."""
    ms = [m for m in mutation.get("mutants") or [] if m.get("status") in ("killed", "survived")]
    return {"killed": sum(1 for m in ms if m["status"] == "killed" and not m.get("rerun")),
            "total": len(ms)}


def lines_for(cert: Dict[str, Any]) -> List[str]:
    f, m = cert["forecast"], cert["mutants"]
    fc = "no forecast: the research certificate predates method 1.2"
    if f["before_forecast"] is not None:
        fc = f"forecast about {f['before_forecast']:.1f}"
    n = f["before_observed"]
    return [
        f"Built: {cert['program']} built certificate version {cert['version']}, issued "
        f"{cert['issued']} on snapshot {cert['snapshot_sha']} (research {cert['research_cert']})",
        f"Before implementation signoff: {n} material change{'' if n == 1 else 's'} observed ({fc})",
        f"After implementation signoff: forecast about {f['after_mean']:.1f}; at most "
        f"{f['after_bound95']} at 95% (mutant kill rate {m['killed']} of {m['total']}, lower bound "
        f"{m['lower95']:.2f}; build-findable share {f['share']}, share assumed)",
        f"Findings: {cert['findings']['material']} material, {cert['findings']['fixed']} fixed, "
        f"{cert['findings']['rejected_no_repro']} rejected for no failing test",
    ]


def write_built_certificate(ctx: Any, rows: List[Any]) -> str:
    import gate_cert

    rc = research_cert(ctx)
    mutation = ctx.json("built/mutation.json")
    fz = ctx.json("built/freeze.json") or {}
    if not mutation:
        raise kit.KitError("no built/mutation.json: the built certificate needs the mutation run")
    fs = list(kit.fold(ctx.jsonl("built/findings.jsonl")).values())
    mat = [f for f in fs if f.get("severity") == "material" and f.get("status") in ("open", "fixed")]
    fp = first_pass(mutation)
    share = kit.BUILD_FINDABLE_SHARE
    rf = rc.get("forecast") or {}
    est = after_impl(len(mat), fp["killed"], fp["total"], float(rf.get("invisible_mean") or 0),
                     float(rf.get("invisible_bound95") or 0), share)
    before: Optional[float] = rf.get("before_impl_mean")
    n = len(list((ctx.records / "built").glob("BUILT-CERT-v*.json"))) + 1
    cert = {
        "cert": f"BUILT-CERT-v{n}",
        "program": ctx.slug,
        "version": n,
        "snapshot_sha": fz.get("snapshot_sha"),
        "issued": kit.now_iso(),
        "research_cert": rc.get("cert"),
        "rows": {str(r.num): r.status for r in rows},
        "findings": {
            "material": len(mat),
            "fixed": sum(1 for f in mat if f.get("status") == "fixed"),
            "rejected_no_repro": sum(1 for f in fs if f.get("status") == "rejected-no-repro"),
        },
        "kill_rate": est["kill_rate"],
        "mutants": {"killed": fp["killed"], "total": fp["total"],
                    "lower95": est["kill_rate_lower95"]},
        "forecast": {
            "before_observed": gate_cert.live_state(ctx.records, rc)["after"] + len(mat),
            "before_forecast": before,
            "after_mean": est["after_mean"],
            "after_bound95": est["after_bound95"],
            "share": share,
            "assumed": ["build_findable_share"],
        },
    }
    path = ctx.records / "built" / f"BUILT-CERT-v{n}.json"
    kit.write_json_atomic(path, cert)
    path.with_suffix(".md").write_text("\n".join(lines_for(cert)) + "\n")
    return str(path)
