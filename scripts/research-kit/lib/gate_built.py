"""gate_built.py — the Stage 9 verbs of gate.sh (REPORT.md §11, method v1.2).

  built-freeze --program P --artifact <abs dir>   pin the built snapshot in built/freeze.json;
                                                  registry certified -> build-certifying
  built-run    --program P [--json]               rows 20-25 (gate_rows_built.py); all pass ->
                                                  built/BUILT-CERT-v<n> (built_cert.py), registry
                                                  -> build-certified

Record shapes: RECORDS.md "Stage 9 records". gate.sh stays the only registry writer.
"""

from __future__ import annotations

from typing import Any

import kit
from gate import FILED, PASS, make_ctx, print_rows


def cmd_built_freeze(a: Any) -> int:
    raise kit.KitError("built-freeze is not implemented")


def cmd_built_run(a: Any) -> int:
    import built_cert
    import gate_rows_built

    ctx = make_ctx(a.program)
    state = (kit.registry_get(a.program) or {}).get("state")
    if state not in kit.BUILD_STATES:
        raise kit.KitError(
            f"built-run needs a frozen built snapshot: {a.program} is {state}, not "
            "build-certifying (run gate.sh built-freeze after the last build wave)"
        )
    rows = gate_rows_built.run_built_rows(ctx)
    print_rows(rows, a.json)
    if any(r.status not in (PASS, FILED) for r in rows):
        return 1
    cert = built_cert.write_built_certificate(ctx, rows)
    kit.registry_set(a.program, "build-certified")
    if not a.json:
        print(f"BUILD-CERTIFIED {a.program}: {cert}")
    return 0


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("built-freeze")
    p.add_argument("--program", required=True)
    p.add_argument("--artifact", required=True)
    p.set_defaults(fn=cmd_built_freeze)
    p = sub.add_parser("built-run")
    p.add_argument("--program", required=True)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_built_run)
