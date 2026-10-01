"""gate_requires.py — may this build wave fire? (REPORT.md §3.10 "Carried rows at build time", §5.4;
§8 item 13; SYNTHESIS §6.3 "A build wave fires only when no row in its dependency closure is open or
carried-unresolved"). The reader behind `handoff-fire.sh --requires-gate <program>`.

  gate.sh requires --program P [--wave W] [--json]

A wave fires only when ALL of these hold:
  1. the registry reads `certified` (registered, certifying and closed all refuse: no build wave
     fires before the gate passes, and a reopen sets the registry back to registered);
  2. the newest certificate exists and carries no FAIL row;
  3. no VALID operator reopen is signed after that certificate (the registry may not have caught up:
     only `gate.sh run` moves it back, §5.1);
  4. nothing in the LIVE records blocks W:
       - a class-C decision still open or carried whose `blocks_waves` names W;
       - a carried set whose `blocks_waves` names W, unless W owns its narrowing probe
         (`set.narrowing_probe.wave`: "a carried set is exempt for the build wave that owns its
         narrowing probe");
       - any other open or carried decision whose `blocks_waves` names W;
       - an open frame-omission known row whose `blocks_waves` names W (§5.4);
       - W in any decision's or known row's `descoped_waves`: the sweep descoped it, so it does not
         build (a descoped wave is not a refused wave that will clear; it is a wave that is gone).

The records are read LIVE, not from the certificate's snapshot, because the things that clear a block
all happen after the certificate: the sweep converts a class-C row and closes an overdue known row by
appending events (gate_sweep.py), and a frame-delta cycle closes the known row it names. Reading the
snapshot would refuse forever a wave whose row has since closed, which is exactly §10 item 9's defect.
The gate rows themselves are NOT re-run here: a fire must not re-execute every probe, and row 10
(freshness) is the gate's job; the certificate is the gate's verdict and this verb reads it.

Without --wave there is no dependency closure to scope to, so ANY block for ANY wave refuses
(fail closed) and the refusal says to pass --wave.

Exit 0 the wave may fire · 1 refused (each reason printed) · 2 the program cannot be read
(unregistered, bad slug): the caller refuses on both and says which.
"""

from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional

import kit

BLOCKING_DECISION_STATES = ("open", "carried", "reopened")


def _names(wave: Optional[str], waves: Any) -> bool:
    ws = [w for w in (waves or []) if isinstance(w, str) and w]
    return bool(ws) if wave is None else wave in ws


def _cert_no(p: Any) -> int:
    m = re.match(r"CERT-v(\d+)\.json$", p.name)
    return int(m.group(1)) if m else -1


def blockers(slug: str, wave: Optional[str]) -> Dict[str, Any]:
    """{"cert": id|None, "reasons": [str]} — empty reasons means the wave may fire."""
    import gate
    from gate_rows_a import known_rows

    reasons: List[str] = []
    prog = kit.registry_get(slug)
    if prog is None:
        raise kit.KitError(f"program {slug!r} is not registered")
    state = prog.get("state")
    if state != "certified":
        reasons.append(
            f"registry state is {state!r}, not 'certified': no build wave fires before the gate passes"
        )
    ctx = gate.make_ctx(slug)
    certs = sorted(ctx.records.glob("cert/CERT-v*.json"), key=_cert_no)
    cert: Dict[str, Any] = {}
    if not certs:
        reasons.append(f"no certificate under {ctx.records / 'cert'}")
    else:
        cert = kit.read_json(certs[-1], {}) or {}
        failed = sorted(
            (k for k, v in (cert.get("rows") or {}).items() if v == gate.FAIL), key=int
        )
        if failed:
            reasons.append(f"{cert.get('cert')}: FAIL row(s) {', '.join(failed)}")
        if not cert.get("rows"):
            reasons.append(f"{certs[-1].name} carries no rows — unknown fails (§3.10)")
    if gate.reopened(ctx):
        reasons.append("an operator reopen is signed after the newest certificate")

    for d in kit.fold(ctx.jsonl("decisions.jsonl")).values():
        did = d.get("id")
        if wave is not None and wave in (d.get("descoped_waves") or []):
            reasons.append(f"{did}: descoped wave {wave} (the sweep converted it; it does not build)")
            continue
        st = d.get("status")
        if st not in BLOCKING_DECISION_STATES or not _names(wave, d.get("blocks_waves")):
            continue
        pk = d.get("packet") or {}
        npb = (d.get("set") or {}).get("narrowing_probe") or {}
        if pk.get("class") == "C":
            reasons.append(
                f"{did}: unresolved class-C row (due {pk.get('due') or '?'}) blocks "
                f"{', '.join(d.get('blocks_waves') or [])}"
            )
        elif st == "carried" and d.get("set"):
            if wave is not None and npb.get("wave") == wave:
                continue  # this wave owns the set's narrowing probe
            reasons.append(
                f"{did}: carried set (narrows in {npb.get('wave') or '?'}) blocks "
                f"{', '.join(d.get('blocks_waves') or [])}"
            )
        else:
            reasons.append(
                f"{did}: {st} decision blocks {', '.join(d.get('blocks_waves') or [])}"
            )

    for kr in known_rows(ctx):
        kid = kr.get("id")
        if wave is not None and wave in (kr.get("descoped_waves") or []):
            reasons.append(f"{kid}: descoped wave {wave} (closed by its default; it does not build)")
            continue
        if kr.get("status", "open") != "open" or not _names(wave, kr.get("blocks_waves")):
            continue
        reasons.append(
            f"{kid}: open {kr.get('kind') or 'known'} row (rows {', '.join(kr.get('names_rows') or []) or '-'}) "
            f"blocks {', '.join(kr.get('blocks_waves') or [])} until its frame-delta cycle closes it"
        )

    if wave is None and reasons:
        reasons.append(
            "no --wave given, so every block counts: pass the wave id to scope to its closure"
        )
    return {"cert": cert.get("cert"), "reasons": reasons}


def cmd_requires(a: Any) -> int:
    kit.check_slug(a.program)
    if a.wave is not None and not re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", a.wave):
        raise kit.KitError(f"bad wave id {a.wave!r}")
    r = blockers(a.program, a.wave)
    ok = not r["reasons"]
    if a.json:
        print(json.dumps(dict(r, program=a.program, wave=a.wave, verdict="clear" if ok else "refused")))
    else:
        where = f"wave {a.wave}" if a.wave else "every wave"
        if ok:
            print(f"CLEAR {a.program} {where}: {r['cert']} carries nothing that blocks it")
        else:
            print(f"REFUSED {a.program} {where}:")
            for x in r["reasons"]:
                print(f"  - {x}")
    return 0 if ok else 1


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("requires")
    p.add_argument("--program", required=True)
    p.add_argument("--wave")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_requires)
