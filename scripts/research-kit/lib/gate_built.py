"""gate_built.py — the Stage 9 verbs of gate.sh (REPORT.md §11, method v1.2).

  built-freeze --program P --artifact <abs dir>   pin the built snapshot in built/freeze.json;
               [--wave W]... [--refreeze]         registry certified -> build-certifying. Needs a
                                                  1.2 frame, a signed certificate with no FAIL row
                                                  and no reopen, and a clean git work tree. Re-run
                                                  while build-certifying to re-pin after a fix;
                                                  from build-certified only with --refreeze
  built-run    --program P [--json]               rows 20-25 (gate_rows_built.py); all pass ->
                                                  built/BUILT-CERT-v<n> (built_cert.py), registry
                                                  -> build-certified
  built-signed --program P                        the operator signed the newest built certificate
                                                  (cc-signoff research:P/implementation): registry
                                                  build-certified -> implementation-signed. Refused
                                                  (exit 2) while no VALID signature pins it. Run on
                                                  an implementation-signed program whose signature
                                                  no longer holds, it sets build-certified back
                                                  and exits 1. The agent never signs; cc-signoff
                                                  runs this verb itself after a signature.

A build-certified program is not done: `gate.sh close` refuses it until the implementation is
signed (implementation_gate below), and `requires --after-signoff` refuses a wave that follows it.

Record shapes: RECORDS.md "Stage 9 records". gate.sh stays the only registry writer.
"""

from __future__ import annotations

import os
from typing import Any, Tuple

import kit
from gate import FAIL, FILED, PASS, Ctx, make_ctx, print_rows, reopened
from gate_cert import git


def signed_cert(ctx: Ctx) -> str:
    """The newest research certificate's id, refused unless it is clean, signed and not reopened."""
    import operator_sign
    from gate_requires import _cert_no

    certs = sorted(ctx.records.glob("cert/CERT-v*.json"), key=_cert_no)
    if not certs:
        raise kit.KitError(
            f"built-freeze refused: no certificate under {ctx.records / 'cert'}"
        )
    cert = kit.read_json(certs[-1], {}) or {}
    name = certs[-1].stem
    failed = sorted(
        (k for k, v in (cert.get("rows") or {}).items() if v == FAIL), key=int
    )
    if failed:
        raise kit.KitError(
            f"built-freeze refused: {name} has FAIL row(s) {', '.join(failed)}"
        )
    sig = operator_sign.latest_valid(ctx.slug, "cert")
    if not sig or f"cert/{certs[-1].name}" not in (sig.get("pins") or {}):
        raise kit.KitError(
            f"built-freeze refused: no valid operator signature on {name} "
            f"(cc-signoff research:{ctx.slug}/cert)"
        )
    if reopened(ctx):
        raise kit.KitError(
            f"built-freeze refused: an operator reopen is signed after {name}; "
            "the research gate runs again first"
        )
    return name


def artifact_head(artifact: str) -> Tuple[str, str]:
    """(realpath, HEAD sha) of a clean git work tree at an absolute path; refuses anything else."""
    if not os.path.isabs(artifact):
        raise kit.KitError(f"--artifact {artifact!r} is not an absolute path")
    root = os.path.realpath(artifact)
    inside = (
        git(root, "rev-parse", "--is-inside-work-tree") if os.path.isdir(root) else None
    )
    sha = git(root, "rev-parse", "HEAD") if inside == "true" else None
    if not sha:
        raise kit.KitError(f"--artifact {root} is not a git work tree with a commit")
    dirty = git(root, "status", "--porcelain")
    if dirty is None or dirty:
        raise kit.KitError(
            f"--artifact {root} has uncommitted changes; built-freeze pins a committed snapshot"
        )
    return root, sha


def cmd_built_freeze(a: Any) -> int:
    ctx = make_ctx(a.program)
    if not kit.is_v12(ctx.frame):
        raise kit.KitError(
            f"built-freeze refused: {a.program}'s frame is not method 1.2 (Stage 9 is a v1.2 stage)"
        )
    state = (kit.registry_get(a.program) or {}).get("state")
    if state in ("build-certified", kit.IMPL_SIGNED) and not a.refreeze:
        raise kit.KitError(
            f"built-freeze refused: {a.program} is {state}; pass --refreeze to pin a new "
            "snapshot and certify the built artifact again"
            + (" (the new certificate needs a new implementation signature)"
               if state == kit.IMPL_SIGNED else "")
        )
    if state not in ("certified",) + kit.STAGE9_STATES:
        raise kit.KitError(
            f"built-freeze needs a certified program: {a.program} is {state!r}"
        )
    name = signed_cert(ctx)
    root, sha = artifact_head(a.artifact)
    rec = {
        "snapshot_sha": sha,
        "artifact_root": root,
        "frozen_at": kit.now_iso(),
        "research_cert": name,
        "waves_done": list(a.wave or []),
    }
    kit.write_json_atomic(ctx.records / "built" / "freeze.json", rec)
    kit.registry_set(a.program, "build-certifying")
    print(f"BUILT-FROZEN {a.program} at {sha[:12]}; registry -> build-certifying")
    return 0


def cmd_built_run(a: Any) -> int:
    import built_cert
    import gate_rows_built

    ctx = make_ctx(a.program)
    state = (kit.registry_get(a.program) or {}).get("state")
    if state == kit.IMPL_SIGNED:
        raise kit.KitError(
            f"built-run refused: {a.program} is implementation-signed; a new built certificate "
            "starts at gate.sh built-freeze --refreeze and needs a new signature"
        )
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


def sign_cmd(slug: str) -> str:
    return f"cc-signoff research:{slug}/implementation --evidence <what you read>"


def implementation_gate(slug: str) -> Tuple[bool, str]:
    """(signed?, one sentence) for the newest built certificate. Only a VALID signature passes."""
    import operator_sign

    st = operator_sign.implementation_state(slug)
    cert = st["cert"] or "no built certificate"
    if st["status"] == operator_sign.SIGNED:
        return True, f"{cert} {operator_sign.implementation_words(slug, st)}"
    if st["status"] == operator_sign.UNSIGNED:
        why = f"{cert} carries no operator signature"
    else:
        why = f"{cert}: implementation {operator_sign.implementation_words(slug, st)}"
    return False, f"{why}. The operator signs it in their own terminal: {sign_cmd(slug)}"


def cmd_built_signed(a: Any) -> int:
    state = (kit.registry_get(a.program) or {}).get("state")
    if state not in ("build-certified", kit.IMPL_SIGNED):
        raise kit.KitError(
            f"built-signed refused: {a.program} is {state}, not build-certified; the "
            "implementation is signed over a built certificate (gate.sh built-run)"
        )
    ok, why = implementation_gate(a.program)
    if not ok and state == kit.IMPL_SIGNED:
        kit.registry_set(a.program, "build-certified")
        print(f"UNSIGNED {a.program}: {why}; registry -> build-certified")
        return 1
    if not ok:
        raise kit.KitError(f"built-signed refused: {why}")
    kit.registry_set(a.program, kit.IMPL_SIGNED)
    print(f"IMPLEMENTATION-SIGNED {a.program}: {why}; registry -> implementation-signed")
    return 0


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("built-signed")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_built_signed)
    p = sub.add_parser("built-freeze")
    p.add_argument("--program", required=True)
    p.add_argument("--artifact", required=True)
    p.add_argument("--wave", action="append")
    p.add_argument("--refreeze", action="store_true")
    p.set_defaults(fn=cmd_built_freeze)
    p = sub.add_parser("built-run")
    p.add_argument("--program", required=True)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_built_run)
