"""probe_run.py — the kit's probe runner and environment doctor (REPORT.md §3.4, §8 item 7).

The ONLY writer of probes.jsonl. A probe's evidence level is computed from how it ran
(kit.probe_level), never typed by hand, so this runner records exactly the facts that computation
reads: the command, every exit, the sample count, the load control and the negative control.

  probe-run.sh run --program P --id P-x --kind K --closes PR-1 [--closes …] [--n N] [--load-control]
      [--env-id ID] [--negative-control '<cmd>' | --no-negative-control '<reason>'] [--falsifier T] -- <cmd…>
  probe-run.sh doctor --program P

Probes never change the live subject (§3.4): there is no flag that records `mutates_live: true`, and
`--mutates-live` is refused. A probe that must touch something live is an operator step.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kit  # noqa: E402

LAUNCHD_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"
DOCTOR_TOOLS = (
    "codex",
    "gemini",
    "claude-latest",
    "claude",
    "shellcheck",
    "jq",
    "bats",
    "docker",
)
ENVS = ("interactive-zsh", "launchd-bash32", "agent-shell")


def sh(
    argv: List[str], timeout: int = 20, env: Optional[Dict[str, str]] = None
) -> Tuple[int, str, str]:
    try:
        p = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s"
    except OSError as e:
        return 127, "", str(e)


def trunk_sha(cwd: str) -> Optional[str]:
    rc, out, _ = sh(["git", "-C", cwd, "rev-parse", "HEAD"], timeout=10)
    return out.strip() if rc == 0 else None


def env_descriptor() -> Dict[str, Any]:
    return {
        "interpreter": sys.executable,
        "PATH": os.environ.get("PATH", ""),
        "os": platform.mac_ver()[0] or platform.platform(),
        "cwd": os.getcwd(),
        "trunk_sha": trunk_sha(os.getcwd()),
    }


def probes_file(slug: str) -> Path:
    return kit.records_dir(slug) / "probes.jsonl"


def cmd_run(a: argparse.Namespace) -> int:
    if a.mutates_live:
        raise kit.KitError(
            "refused: probes never change the live subject (§3.4); "
            "a probe that must touch something live is an operator step"
        )
    if a.kind not in kit._PROBE_LEVEL:
        raise kit.KitError(
            f"unknown probe kind {a.kind!r}: one of {', '.join(sorted(kit._PROBE_LEVEL))}"
        )
    cmd = list(a.cmd)
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        raise kit.KitError("no command: put it after `--`")
    if not a.negative_control and not a.no_negative_control:
        raise kit.KitError(
            "every probe that can fail is shown able to fail (§3.4): pass "
            "--negative-control '<cmd>' or --no-negative-control '<reason>'"
        )
    pf = probes_file(a.program)
    if any(r.get("id") == a.id for r in kit.read_jsonl(pf)):
        raise kit.KitError(f"probe id {a.id} already recorded; probes are append-only")
    n = max(1, a.n)
    outs: List[str] = []
    errs: List[str] = []
    exits: List[int] = []
    for i in range(n):
        rc, out, err = sh(cmd, timeout=a.timeout)
        exits.append(rc)
        outs.append(out if n == 1 else f"=== run {i + 1} exit {rc}\n{out}")
        errs.append(err if n == 1 else f"=== run {i + 1}\n{err}")
    neg: Dict[str, Any] = {
        "ran": False,
        "against": None,
        "reported_refutation": None,
        "reason_if_not_run": a.no_negative_control,
    }
    if a.negative_control:
        rc, _, _ = sh(["/bin/bash", "-c", a.negative_control], timeout=a.timeout)
        neg = {
            "ran": True,
            "against": a.negative_control,
            "reported_refutation": rc != 0,
            "reason_if_not_run": None,
            "exit": rc,
        }
    ev = kit.records_dir(a.program) / "evidence" / a.id
    ev.mkdir(parents=True, exist_ok=True)
    (ev / "cmd").write_text(json.dumps(cmd) + "\n")
    (ev / "stdout").write_text("".join(outs))
    (ev / "stderr").write_text("".join(errs))
    env = env_descriptor()
    kit.write_json_atomic(ev / "env.json", env)
    rec = {
        "id": a.id,
        "closes": a.closes or [],
        "kind": a.kind,
        "env": {"id": a.env_id or "agent-shell", "descriptor": env},
        "cmd": cmd,
        "stdin": "/dev/null",
        "n": n,
        "exits": exits,
        "exit": 0 if all(x == 0 for x in exits) else next(x for x in exits if x != 0),
        "load_control": bool(a.load_control),
        "falsifier": a.falsifier,
        "negative_control": neg,
        "raw": f"evidence/{a.id}/",
        "mutates_live": False,
        "trunk_sha": env["trunk_sha"],
        "at": kit.now_iso(),
    }
    if neg["ran"] and not neg["reported_refutation"]:
        print(
            f"WARNING: the negative control exited 0, so {a.id} has not shown it can fail; "
            "it earns no evidence level",
            file=sys.stderr,
        )
    kit.append_jsonl(pf, rec)
    print(
        f"{a.id} kind={a.kind} exit={rec['exit']} n={n} level=E{kit.probe_level(rec)}"
    )
    return 0


def zsh_path() -> str:
    return os.environ.get("CC_RESEARCH_ZSH", "/bin/zsh")


def interactive(cmd: str) -> Tuple[int, str]:
    """Run under the operator's interactive login shell and return (rc, answer).

    rc files print banners, and terminal integrations write escape sequences onto the SAME line as
    the answer, so the answer is fenced with sentinels and only the text between them is kept.
    """
    fenced = f"__cc_ans=$({cmd}); __cc_rc=$?; print -r -- \"@@CCKIT@@${{__cc_ans}}@@CCKIT@@\"; exit $__cc_rc"
    rc, out, _ = sh([zsh_path(), "-lic", fenced], timeout=20)
    m = re.findall(r"@@CCKIT@@(.*?)@@CCKIT@@", out, re.S)
    return rc, (m[-1].strip() if m else "")


def cmd_doctor(a: argparse.Namespace) -> int:
    rc, ipath = interactive("print -r -- $PATH")
    tools: Dict[str, Any] = {}
    agent_path = os.environ.get("PATH", "").split(":")
    for t in DOCTOR_TOOLS:
        trc, where = interactive(f"whence -p {t}")
        found = where if trc == 0 and where.startswith("/") else None
        agent_hit = next(
            (str(Path(d) / t) for d in agent_path if d and (Path(d) / t).is_file()),
            None,
        )
        tools[t] = {
            "interactive": found,
            "agent_path": agent_hit,
            "hidden_from_agent": bool(found and not agent_hit),
        }
    launchd_env = {"PATH": LAUNCHD_PATH, "HOME": str(Path.home())}
    interp = {
        "/bin/bash": sh(["/bin/bash", "--version"])[1].splitlines()[:1],
        "/usr/bin/python3": sh(["/usr/bin/python3", "--version"])[1].strip(),
        "launchd python3": sh(
            ["/usr/bin/env", "python3", "--version"], env=launchd_env
        )[1].strip(),
        "launchd bash": sh(
            ["/usr/bin/env", "bash", "-c", "echo $BASH_VERSION"], env=launchd_env
        )[1].strip(),
    }
    osv = {
        k: v
        for k, v in (
            ln.split(":", 1)
            for ln in sh(["/usr/bin/sw_vers"])[1].splitlines()
            if ":" in ln
        )
    }
    docker = tools["docker"]["interactive"]
    dk_rc = sh([docker, "info"], timeout=15)[0] if docker else 127
    logins: Dict[str, str] = {}
    codex = tools["codex"]["interactive"]
    if codex:
        lrc, lout, lerr = sh([codex, "login", "status"], timeout=20)
        logins["openai"] = (
            (lout or lerr).strip().splitlines()[0]
            if (lout or lerr).strip()
            else f"rc={lrc}"
        )
    else:
        logins["openai"] = "unknown: codex not found on the interactive PATH"
    logins["google"] = (
        (
            "unknown: gemini has no read-only login-status verb; the vendor preflight "
            "(courier.sh preflight) is the check"
        )
        if tools["gemini"]["interactive"]
        else "unknown: gemini not found on the interactive PATH"
    )
    logins["anthropic"] = (
        "unknown: no read-only auth-status verb; the vendor preflight is the check"
    )
    doc = {
        "at": kit.now_iso(),
        "interactive_path": ipath,
        "interactive_rc": rc,
        "tools": tools,
        "interpreters": interp,
        "os": {k.strip(): v.strip() for k, v in osv.items()},
        "docker": {"binary": docker, "info_rc": dk_rc, "usable": dk_rc == 0},
        "vendor_logins": logins,
        "credential_expiry": "unknown: no read-only expiry source",
        "envs": list(ENVS),
    }
    ev = kit.records_dir(a.program) / "evidence" / "doctor"
    kit.write_json_atomic(ev / "env.json", doc)
    pf = probes_file(a.program)
    n = 1 + sum(
        1 for r in kit.read_jsonl(pf) if str(r.get("id", "")).startswith("P-doctor-")
    )
    rec = {
        "id": f"P-doctor-{n}",
        "closes": [],
        "kind": "live-read",
        "env": {"id": "interactive-zsh", "descriptor": {"PATH": ipath}},
        "cmd": ["probe-run.sh", "doctor"],
        "stdin": "/dev/null",
        "n": 1,
        "exit": 0,
        "load_control": False,
        "envs": list(ENVS),
        "negative_control": {
            "ran": False,
            "reason_if_not_run": "an inventory read has no known-bad input",
        },
        "raw": "evidence/doctor/",
        "mutates_live": False,
        "at": doc["at"],
    }
    kit.append_jsonl(pf, rec)
    for t, v in tools.items():
        mark = v["interactive"] or "absent"
        print(
            f"  {t:<14} {mark}{'  (hidden from the agent PATH)' if v['hidden_from_agent'] else ''}"
        )
    print(
        f"  docker usable: {dk_rc == 0} · bash: {interp['/bin/bash']} · launchd python3: {interp['launchd python3']}"
    )
    print(f"recorded {rec['id']} and evidence/doctor/env.json")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="probe-run.sh")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("run")
    p.add_argument("--program", required=True)
    p.add_argument("--id", required=True)
    p.add_argument("--kind", required=True)
    p.add_argument("--closes", action="append")
    p.add_argument("--n", type=int, default=1)
    p.add_argument("--load-control", action="store_true")
    p.add_argument("--env-id")
    p.add_argument("--negative-control")
    p.add_argument("--no-negative-control")
    p.add_argument("--falsifier")
    p.add_argument("--timeout", type=int, default=300)
    p.add_argument("--mutates-live", action="store_true")
    p.add_argument("cmd", nargs=argparse.REMAINDER)
    p.set_defaults(fn=cmd_run)
    p = sub.add_parser("doctor")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_doctor)
    a = ap.parse_args(argv)
    try:
        kit.check_slug(a.program)
        return int(a.fn(a))
    except kit.KitError as e:
        print(f"probe-run.sh: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
