"""P-S1 — `session.measure.rateLimits` shape, and that it follows the BILLED org after a move (SYNTHESIS R4/AC1:
the sensor's `resetsAt` match is the `proved` gate, so a drift must surface as a FAIL here, never as a false
SWAPPED in production).

Reads the throwaway mod's measure records from the P-P1 run (or runs P-P1 when it has not run in this
invocation) and compares each against the response headers of the call just before it:
  shape     every window is {kind: str, percentUsed: number 0-100+, resetsAt: ISO 8601}; a seven_day exists
  follows   the last measure before the flip carries A's 7d utilization and reset; the last one after the
            first B-billed response carries B's (utilization within 1 point, reset equal to the second)
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

import lib
import p_p1_pointer


def _shape_ok(rl) -> bool:
    if not isinstance(rl, list) or not rl:
        return False
    for w in rl:
        if not isinstance(w.get("kind"), str) or not isinstance(
            w.get("percentUsed"), (int, float)
        ):
            return False
        if "resetsAt" in w:
            try:
                datetime.fromisoformat(str(w["resetsAt"]).replace("Z", "+00:00"))
            except ValueError:
                return False
    return any(w["kind"] == "seven_day" for w in rl)


def _seven(rl) -> dict:
    return next((w for w in rl if w.get("kind") == "seven_day"), {})


def _epoch(iso: str | None) -> int | None:
    if not iso:
        return None
    return int(datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp())


def run(binary: Path, ctx: dict) -> dict:
    if "pp1" not in ctx:
        pre = p_p1_pointer.run(binary, ctx)
        if pre["verdict"] != "PASS" or "pp1" not in ctx:
            return lib.verdict(
                "P-S1",
                "INCONCLUSIVE",
                f"needs a P-P1 move to compare against: {pre['summary']}",
            )
    pp = ctx["pp1"]
    r, flip_t = pp["run"], pp["flip_t"]
    a_org, b_org = pp["ida"]["org"], pp["idb"]["org"]
    measures = [m for m in lib.read_modlog(pp["modlog"]) if m.get("kind") == "measure"]
    if not measures:
        return lib.verdict(
            "P-S1", "FAIL", "session.measure never fired in the throwaway"
        )
    a_resp = [x for x in r.resps if x.org == a_org and x.status == 200]
    b_resp = [x for x in r.resps if x.org == b_org and x.status == 200]

    def matches(m, resp) -> bool:
        w = _seven(m["rateLimits"])
        return (
            resp is not None
            and resp.util7d is not None
            and abs(w.get("percentUsed", -99) - resp.util7d * 100) <= 1
            and _epoch(w.get("resetsAt")) == resp.reset7d
        )

    # A measure reports the windows of the response that preceded it, so pair each with the last
    # 200 response that arrived before the mod wrote it (the response-start line precedes the body).
    paired = []
    for m in measures:
        prior = [x for x in r.resps if x.status == 200 and x.t <= m["host_mtime"]]
        paired.append((m, prior[-1] if prior else None))
    on_a = [(m, x) for m, x in paired if x is not None and x.org == a_org]
    on_b = [(m, x) for m, x in paired if x is not None and x.org == b_org]

    checks = {
        "shape": all(_shape_ok(m["rateLimits"]) for m in measures),
        "every_measure_matches_its_billed_org": all(matches(m, x) for m, x in paired),
        "measured_on_A_before_move": bool(on_a),
        "measured_on_B_after_move": bool(on_b),
        "A_and_B_distinguishable": bool(a_resp and b_resp)
        and (
            a_resp[0].reset7d != b_resp[-1].reset7d
            or abs(a_resp[0].util7d - b_resp[-1].util7d) >= 0.02
        ),
    }
    ok = all(checks.values())
    seq = [
        {
            "seven_day": _seven(m["rateLimits"]),
            "changed": m.get("changed"),
            "dt_from_flip": round(m["host_mtime"] - flip_t, 2) if flip_t else None,
        }
        for m in measures
    ]
    return lib.verdict(
        "P-S1",
        "PASS" if ok else "FAIL",
        (
            "session.measure follows the billed org: 7d "
            + " → ".join(
                f"{s['seven_day'].get('percentUsed')}% resets {s['seven_day'].get('resetsAt')}"
                for s in seq
            )
        )
        + (
            ""
            if ok
            else "; failed: " + ", ".join(k for k, v in checks.items() if not v)
        ),
        checks=checks,
        measures=seq,
        headers={
            pp["a"]: {
                "util7d": a_resp[0].util7d if a_resp else None,
                "reset7d": a_resp[0].reset7d if a_resp else None,
            },
            pp["b"]: {
                "util7d": b_resp[-1].util7d if b_resp else None,
                "reset7d": b_resp[-1].reset7d if b_resp else None,
            },
        },
    )
