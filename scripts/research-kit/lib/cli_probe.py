"""cli_probe.py — `cc-research probe | doctor | self-test` (REPORT.md §8 item 10; §3.4, §3.6).

  probe     --program P --id P-x --kind K … -- <cmd…>   probe_run's `run`, flag for flag
  doctor    --program P                                 probe_run's doctor, plus tool states and
                                                        credential expiry from frame.json
  self-test --program P [--row ID] [--json]            every acceptance row over its fixtures

probe_run.py stays the only writer of probes.jsonl: `probe` hands its arguments to probe_run's own
parser, and the self-test records each row as one probe through it. A self-test probe's command is
the check over control.known_good and its negative control is the same check over
control.known_bad, so the runner's evidence level reads "shown able to fail" exactly as gate row 6
does. The check runs the way row 6 runs it: `/bin/bash -c`, cwd = the records dir, env FIXTURE =
the fixture path (relative to the records dir in acceptance.json).
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import shlex
from pathlib import Path
from typing import Any, Dict, List

import kit
import probe_run

SELFTEST_TIMEOUT = (
    60  # gate_rows_a.TIMEOUT: the self-test gives a check the time row 6 gives it
)
EXPIRING_DAYS = (
    7  # gate row 10 wants a credential to outlive the build window by 7 days
)
RESIDUAL = "build-validated residual"


# ── probe ───────────────────────────────────────────────────────────────────────────────────────


def cmd_probe(a: argparse.Namespace) -> int:
    return probe_run.main(["run"] + list(a.rest))


# ── doctor ──────────────────────────────────────────────────────────────────────────────────────


def tool_state(t: Dict[str, Any], shell_ok: bool) -> str:
    """hidden = on the interactive PATH only. Never `absent` when either PATH has the tool, nor
    when the interactive shell itself could not be read."""
    if t.get("interactive") and t.get("agent_path"):
        return "visible"
    if t.get("interactive"):
        return "hidden"
    if t.get("agent_path"):
        return "agent-only"
    return "absent" if shell_ok else "unknown"


def credential_expiry(slug: str) -> Any:
    """frame.json credentials `[{name, expires, renewer_probe}]` (gate row 10's shape), each with
    the days it has left at CC_NOW."""
    frame = kit.read_json(kit.records_dir(slug) / "frame.json")
    if frame is None:
        return "unknown: no frame.json, so no declared credentials"
    now = kit.parse_iso(kit.now_iso())
    out: List[Dict[str, Any]] = []
    for c in frame.get("credentials") or []:
        exp = c.get("expires")
        row: Dict[str, Any] = {"name": c.get("name"), "expires": exp, "days_left": None}
        if not exp:
            row["state"] = "unknown"
        else:
            left = (kit.parse_iso(exp) - now) / 86400.0
            row["days_left"] = round(left, 1)
            row["state"] = (
                "expired" if left <= 0 else "expiring" if left < EXPIRING_DAYS else "ok"
            )
        out.append(row)
    return out


def cmd_doctor(a: argparse.Namespace) -> int:
    kit.check_slug(a.program)
    with contextlib.redirect_stdout(io.StringIO()):
        rc = probe_run.cmd_doctor(argparse.Namespace(program=a.program))
    ev = kit.records_dir(a.program) / "evidence" / "doctor" / "env.json"
    doc = kit.read_json(ev, {})
    shell_ok = doc.get("interactive_rc") == 0 and bool(doc.get("interactive_path"))
    for t in doc.get("tools", {}).values():
        t["state"] = tool_state(t, shell_ok)
    doc["credential_expiry"] = credential_expiry(a.program)
    kit.write_json_atomic(ev, doc)
    if not shell_ok:
        print(
            "  interactive shell unreadable: a tool not seen there is unknown, not absent"
        )
    for name, t in doc.get("tools", {}).items():
        where = t.get("interactive") or t.get("agent_path") or t["state"]
        tail = {
            "hidden": "  (hidden from the agent PATH)",
            "agent-only": "  (agent PATH only)",
        }.get(t["state"], "")
        print(f"  {name:<14} {where}{tail}")
    interp = doc.get("interpreters", {})
    print(
        f"  docker usable: {doc.get('docker', {}).get('usable')} · bash: {interp.get('/bin/bash')}"
        f" · /usr/bin/python3: {interp.get('/usr/bin/python3')}"
        f" · launchd python3: {interp.get('launchd python3')}"
    )
    for vendor, status in sorted(doc.get("vendor_logins", {}).items()):
        print(f"  login {vendor:<9} {status}")
    ce = doc["credential_expiry"]
    if isinstance(ce, str):
        print(f"  credentials: {ce}")
    elif not ce:
        print("  credentials: none declared in frame.json")
    else:
        for c in ce:
            print(
                f"  credential {c['name']}: {c['state']} (expires {c['expires'] or 'unrecorded'})"
            )
    n = sum(
        1
        for r in kit.read_jsonl(probe_run.probes_file(a.program))
        if str(r.get("id", "")).startswith("P-doctor-")
    )
    print(f"recorded P-doctor-{n} and evidence/doctor/env.json")
    return rc


# ── self-test ───────────────────────────────────────────────────────────────────────────────────


def check_script(records: Path, fixture: str, check: str) -> str:
    """The check as row 6 runs it, as one bash script the runner can record."""
    return (
        f"cd {shlex.quote(str(records))} || exit 97\n"
        f"export FIXTURE={shlex.quote(str(records / fixture))}\n"
        f"{check}"
    )


def self_test_row(slug: str, records: Path, r: Dict[str, Any]) -> Dict[str, Any]:
    rid = str(r.get("id"))
    out: Dict[str, Any] = {"row": rid, "bad": None, "good": None, "probe": None}
    if r.get("residual_label") == RESIDUAL:
        out.update(
            verdict="SKIP", reason=RESIDUAL
        )  # row 6 admits it as a note, not as sound
        return out
    ctl = r.get("control") or {}
    if not ctl.get("known_bad") or not ctl.get("known_good") or not r.get("check_cmd"):
        out.update(
            verdict="FAIL",
            reason="no known-bad and known-good fixtures, or no check_cmd",
        )
        return out
    pf = probe_run.probes_file(slug)
    prefix = f"P-selftest-{rid}-"
    n = 1 + sum(
        1 for x in kit.read_jsonl(pf) if str(x.get("id", "")).startswith(prefix)
    )
    pid = f"{prefix}{n}"
    argv = [
        "run",
        "--program",
        slug,
        "--id",
        pid,
        "--kind",
        "read",
        "--timeout",
        str(SELFTEST_TIMEOUT),
        "--negative-control",
        check_script(records, ctl["known_bad"], r["check_cmd"]),
        "--",
        "/bin/bash",
        "-c",
        check_script(records, ctl["known_good"], r["check_cmd"]),
    ]
    with contextlib.redirect_stdout(io.StringIO()):
        rc = probe_run.main(argv)
    if rc != 0:
        raise kit.KitError(
            f"the probe runner refused the self-test of {rid} (exit {rc})"
        )
    rec = kit.read_jsonl(pf)[-1]
    bad = (rec.get("negative_control") or {}).get("exit")
    good = rec.get("exit")
    out.update(bad=bad, good=good, probe=pid)
    if bad == 0:
        out.update(
            verdict="FAIL", reason="passes on its known-bad fixture, so it cannot fail"
        )
    elif good != 0:
        out.update(
            verdict="FAIL", reason=f"fails on its known-good fixture (exit {good})"
        )
    else:
        out.update(verdict="PASS", reason=None)
    return out


def cmd_self_test(a: argparse.Namespace) -> int:
    kit.check_slug(a.program)
    records = kit.records_dir(a.program)
    acc = kit.read_json(records / "acceptance.json")
    if not isinstance(acc, dict) or not isinstance(acc.get("rows"), list):
        raise kit.KitError(f"no acceptance.json rows under {records}")
    rows = acc["rows"]
    if a.row:
        rows = [r for r in rows if str(r.get("id")) == a.row]
        if not rows:
            raise kit.KitError(f"no acceptance row {a.row!r}")
    results = [self_test_row(a.program, records, r) for r in rows]
    passed = all(x["verdict"] != "FAIL" for x in results)
    if a.json:
        print(
            json.dumps(
                {"program": a.program, "rows": results, "passed": passed}, indent=1
            )
        )
    else:
        for x in results:
            if x["verdict"] == "SKIP":
                print(f"SKIP {x['row']} {x['reason']}")
                continue
            bad = "-" if x["bad"] is None else x["bad"]
            good = "-" if x["good"] is None else x["good"]
            why = f"  ({x['reason']})" if x["reason"] else ""
            print(f"{x['verdict']} {x['row']} bad={bad} good={good}{why}")
    return 0 if passed else 1


def add_verbs(sub: Any) -> None:
    """probe · doctor · self-test."""
    # probe_run's own parser reads these arguments: a prefix char no flag uses keeps them whole.
    p = sub.add_parser(
        "probe",
        add_help=False,
        prefix_chars="\x01",
        help="run and record one probe (was probe-run.sh run)",
    )
    p.add_argument("rest", nargs=argparse.REMAINDER)
    p.set_defaults(fn=cmd_probe)
    p = sub.add_parser("doctor", help="environment doctor (§3.4), read-only")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_doctor)
    p = sub.add_parser("self-test", help="acceptance harness self-test (§3.6)")
    p.add_argument("--program", required=True)
    p.add_argument("--row")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_self_test)
