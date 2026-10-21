#!/usr/bin/env python3
"""lr-recon rig helpers (FLEET_V2 W5): everything lr-recon-rig.sh does that is not a process call.

  rig_lib.py expand   FAULTS OUT      matrix → one spec per sid (OUT = specs.json)
  rig_lib.py expected FAULTS          the cohort status line the run MUST print, derived from the
                                      matrix BEFORE the run (never read back from the run)
  rig_lib.py audit    ROOT SPECS      launch-log audit: ≤1 typer per (sid, attempt), and for every
                                      fold case sha(target) == sha(retired + stub)
  rig_lib.py home     RIG             build the rig HOME (accounts.json, registry, links)
  rig_lib.py record-id PIDFILE [exact]  write PIDFILE.id: the pid's lstart (and its argv with `exact`)
  rig_lib.py kill-verified RIG PIDFILE SIG[,SIG]  signal only if (pid, lstart, argv) still match
  rig_lib.py sweep    RIG SIG [OUT]   signal every rig process by verified identity; leftovers → OUT
  rig_lib.py containment RIG          read `kitten @ ls` on stdin; rc 3 if a rig pane shares an OS window
  rig_lib.py result   RIG KEY=VAL…    merge keys into RIG/rig-result.json
  rig_lib.py extra-specs FAULTS OUT   busy_extra N → N never-dying WORKING pane specs (not members)
  rig_lib.py kitty-faults RIG         windows.sid + knobs → faults/kitty-{delay,fail}.tsv (kitty-slow)

Pure stdlib, python 3.9 (the pinned /usr/bin/python3 the daemon runs under).
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import time
import uuid
from typing import Any, Dict, List, Optional, Tuple

ACCOUNTS = [  # the generated account map resolves these names under $HOME, so a rig HOME is enough
    ("next", ".claude-next", "cfg-a"),
    ("next2", ".claude-secondary", "cfg-b"),
    ("next3", ".claude-tertiary", "cfg-c"),
    ("next4", ".claude-quaternary", "cfg-d"),
]
ORDINAL = {1: "1st", 2: "2nd", 3: "3rd"}


def load(path: str) -> Dict[str, Any]:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


# ── expand ──────────────────────────────────────────────────────────────────────────────────────


def expand(faults: Dict[str, Any], seed: str = "") -> List[Dict[str, Any]]:
    """One spec per session, in matrix order. sids are fresh uuid4s (the stub writes them).

    Load-harness matrix keys (B1 §6.1, W4): ``die_spread_s`` draws each member's ``die_at_s`` from a
    seeded uniform over [0, die_spread_s] (a member's own die_at_s or busy_for_s wins);
    ``boot_delay_bin`` {median, p90, cap} is copied into every member that sets no boot delay of
    its own (gap-4's boot distribution for the run's bin, F6). The seed is ``seed`` or the matrix's."""
    import random

    out: List[Dict[str, Any]] = []
    i = 0
    rng = random.Random(seed or str(faults.get("seed", "lr-rig")))
    spread = float(faults.get("die_spread_s") or 0)
    bdist = faults.get("boot_delay_bin")
    # matrix-level switches the stub must see per member (B1 C15): with go_barrier a member boots
    # alive and dies at $LR_RIG/go + die_at_s; with idle_fanout too it boots WORKING, never idle
    barrier = (
        {k: True for k in ("go_barrier", "idle_fanout") if faults.get(k)}
        if faults.get("go_barrier")
        else {}
    )
    for g in faults["groups"]:
        for _ in range(int(g["count"])):
            i += 1
            knobs = dict(g.get("knobs") or {}, **barrier)
            draw = (
                rng.uniform(0.0, spread) if spread else None
            )  # drawn for every member
            if (
                draw is not None
                and "die_at_s" not in knobs
                and "busy_for_s" not in knobs
            ):
                knobs["die_at_s"] = round(draw, 1)
            if (
                isinstance(bdist, dict)
                and "boot_delay_s" not in knobs
                and "boot_delay_bin" not in knobs
            ):
                knobs["boot_delay_bin"] = dict(bdist)
            if (
                isinstance(bdist, dict)
                and "slow_boots" in knobs
                and "boot_delay_bin" not in knobs
            ):
                knobs["boot_delay_bin"] = dict(
                    bdist
                )  # after its slow boots, the bin's draw
            out.append(
                {
                    "n": i,
                    "sid": str(uuid.uuid4()),
                    "group": g["name"],
                    "knobs": knobs,
                    "expect": g["expect"],
                    "recovers": g.get("recovers") or "",
                    "fold": bool(g.get("fold")),
                    "daemon_fault": g.get("daemon_fault") or "",
                    "legacy_holder": bool(g.get("legacy_holder")),
                    "stale_request": bool(g.get("stale_request")),
                    # per-member assertion scope: {"H3": "target:A6"} keeps a known open defect
                    # from failing the whole pair (B1 C9); the load harness reads it
                    "scope": dict(g.get("scope") or {}),
                    "source": faults.get("source", "next"),
                }
            )
    return out


# ── expected ────────────────────────────────────────────────────────────────────────────────────


def expected_line(faults: Dict[str, Any]) -> str:
    """The exact line `cc-lr status --cohort` must print, from the matrix alone.

    Two shapes, the same two report.dod_line renders: a cohort whose every member is expected to
    ENGAGE gets the short form (the N=5 DoD); anything else gets the tally form (the N=30 DoD)."""
    specs = expand(faults)
    n = len(specs)
    exp = [s["expect"] for s in specs]
    if all(e == "ENGAGED" for e in exp):
        return (
            "ENGAGED %d/%d · same-window %d/%d · same-uuid %d/%d · double-typer 0 · "
            "split-brain 0 · lost-records 0 · p95 detect→engaged <= 120s"
            % (n, n, n, n, n, n)
        )
    eng, mov = exp.count("ENGAGED"), exp.count("MOVED")
    inplace = exp.count("IN-PLACE")  # continued in its own pane at the reset (D4.13)
    draft, bg = exp.count("HOLD-DRAFT"), exp.count("HOLD-BGWORK")
    rec_bg = sum(1 for s in specs if s["recovers"] == "HOLD-BGWORK")
    held = draft + bg
    parts = [
        "CLOSED %d/%d (ENGAGED %d, MOVED %d%s)"
        % (
            eng + mov + inplace,
            n,
            eng,
            mov,
            ", IN-PLACE %d" % inplace if inplace else "",
        )
    ]
    hold = "HOLD named %d/%d (draft %d, bgwork %d" % (held, n, draft, bg)
    if rec_bg:
        hold += " — the %s bgwork recovers after its job ends" % ORDINAL.get(
            bg + 1, "%dth" % (bg + 1)
        )
    parts.append(hold + ")")
    parts.append("REPLACED-NEW-WINDOW %d" % exp.count("REPLACED-NEW-WINDOW"))
    parts.append("NOT_NEEDED %d" % exp.count("NOT_NEEDED"))
    parts += [
        "double-typer 0",
        "split-brain 0",
        "lost-records 0",
        "unowned-non-terminal 0",
    ]
    return " · ".join(parts)


# ── audit ───────────────────────────────────────────────────────────────────────────────────────


def _sha(paths: List[str]) -> str:
    h = hashlib.sha256()
    for p in paths:
        with open(p, "rb") as fh:
            h.update(fh.read())
    return h.hexdigest()


MOVE_ROLES = ("recon-A", "recon-A-husk", "recon-B", "recon-R")


def audit(root: str, specs: List[Dict[str, Any]], home: str) -> int:
    """Print the launch-log audit; rc 0 only when every check holds. Per (sid, attempt): at most
    ONE launch-lock taker pid and at most ONE move-actuator spawn (a second one is a re-dispatch
    over the same attempt)."""
    keys: Dict[tuple, Dict[str, set]] = {}
    lines = 0
    want = {s["sid"] for s in specs}
    try:
        with open(os.path.join(root, "launch.log"), encoding="utf-8") as fh:
            for ln in fh:
                t = ln.rstrip("\n").split("\t")
                if len(t) < 4 or t[1] not in want:
                    continue
                kv = dict(x.split("=", 1) for x in t[4:] if "=" in x)
                if (
                    t[3] == "taken"
                ):  # "inherited" = a child under its parent's lock: same chain
                    cls = "launch"
                elif t[3] == "spawn" and t[2] in MOVE_ROLES:
                    cls = "move"
                elif t[3] == "spawn" and t[2] == "recon-C":
                    # a typed continue: the whole launch record of an in-place cohort (D4.13), so it
                    # counts toward `lines` (the audit is not blind), with no per-key limit of its own
                    cls = "type"
                else:
                    continue
                lines += 1
                key = (
                    t[1],
                    kv.get("attempt") or "legacy@" + t[0],
                )  # a legacy take is its own key
                keys.setdefault(key, {"launch": set(), "move": set(), "type": set()})[
                    cls
                ].add(kv.get("pid", "?"))
    except OSError:
        print("launch-log audit: %s/launch.log unreadable" % root)
        return 1
    worst_l = max((len(v["launch"]) for v in keys.values()), default=0)
    worst_m = max((len(v["move"]) for v in keys.values()), default=0)
    bad = sorted(
        "%s/%s launch=%d move=%d" % (k[0][:8], k[1], len(v["launch"]), len(v["move"]))
        for k, v in keys.items()
        if len(v["launch"]) > 1 or len(v["move"]) > 1
    )
    ok = not bad and lines > 0
    print(
        "launch-log audit: %d lines · %d (sid, attempt) keys · max launch-lock takers per key %d · "
        "max move spawns per key %d · double-typer %d%s"
        % (
            lines,
            len(keys),
            worst_l,
            worst_m,
            len(bad),
            (" · OVER: " + ", ".join(bad)) if bad else "",
        )
    )
    # P4 (B1 §9.4): a record under this root for a sid the matrix never named is the other arm's,
    # or production's, leaking in; it must be 0
    extra = set()
    try:
        extra = {
            s["sid"]
            for s in load(os.path.join(os.path.dirname(root), "specs-extra.json"))
        }
    except (OSError, ValueError, KeyError, TypeError):
        pass
    sdir = os.path.join(root, "sessions")
    foreign = sorted(
        n[:-5]
        for n in (os.listdir(sdir) if os.path.isdir(sdir) else [])
        if n.endswith(".json") and n.count(".") == 1 and n[:-5] not in want | extra
    )
    print(
        "foreign records: %d%s"
        % (len(foreign), (" · " + ",".join(f[:8] for f in foreign)) if foreign else "")
    )
    ok = ok and not foreign
    for s in specs:
        if not s.get("fold"):
            continue
        fold = os.path.join(
            root, "work", s["sid"] + ".fold.json"
        )  # the daemon's fold witness
        try:
            rec = load(fold)
            want_sha = _sha([rec["retired"], rec["stub"]])
            got = rec.get("target_sha") or ""
        except (OSError, ValueError, KeyError) as e:
            print("fold audit %s: no fold evidence (%s)" % (s["sid"][:8], e))
            ok = False
            continue
        same = want_sha == got
        ok = ok and same
        print(
            "fold audit %s: sha(target)=%s sha(retired+stub)=%s %s"
            % (s["sid"][:8], got[:12], want_sha[:12], "EQUAL" if same else "DIFFER")
        )
    return 0 if ok else 1


# ── home ────────────────────────────────────────────────────────────────────────────────────────


def build_home(rig: str) -> None:
    """accounts.json + one config dir per account (real dirs under RIG, linked into HOME)."""
    home = os.path.join(rig, "home")
    os.makedirs(os.path.join(home, ".claude", "cc-registry"), exist_ok=True)
    accts = []
    for name, dot, real in ACCOUNTS:
        d = os.path.join(rig, real)
        for sub in ("sessions", "projects"):
            os.makedirs(os.path.join(d, sub), exist_ok=True)
        link = os.path.join(home, dot)
        if not os.path.islink(link):
            os.symlink(d, link)
        accts.append({"name": name, "config_dir": "~/" + dot, "launcher": "claude"})
    doc: Dict[str, Any] = {
        "_what": "lr-recon rig accounts (throwaway)",
        "accounts": accts,
    }
    if os.environ.get("RIG_PLACE_KMAX"):
        # the reconciler's clamp reads the same KMAX the fake placer's seat model refuses at
        doc["router"] = {"KMAX": int(os.environ["RIG_PLACE_KMAX"])}
    with open(
        os.path.join(home, ".claude", "accounts.json"), "w", encoding="utf-8"
    ) as fh:
        json.dump(doc, fh, indent=1)


# ── run-time helpers (lr-recon-rig.sh) ──────────────────────────────────────────────────────────


# ── identity, teardown and containment (B1 review S1-S3) ────────────────────────────────────────
# Pids on this box advance ~800/s, so a pidfile a few minutes stale names an unrelated process (it
# could be a production claude). Nothing here signals a pid without re-reading its lstart against the
# one recorded when it was written, and its argv against the rig root.

PS_BOUND_S = 30.0


def _ps(args: List[str]) -> str:
    try:
        # LC_ALL=C: lstart is locale-formatted ("Tue Oct 20" vs "Tue 20 Oct"), and an identity
        # recorded under one locale must compare equal when read under another
        return subprocess.run(
            ["/bin/ps"] + args,
            env=dict(os.environ, LC_ALL="C"),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=PS_BOUND_S,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def proc_id(pid: int) -> Tuple[str, str]:
    """(lstart, argv) of a live pid, ("", "") when it is gone or unreadable."""
    if pid <= 0:
        return "", ""
    return (
        # one space between fields: `ps` pads a one-digit day ("Oct  7"), the -axo split does not
        " ".join(_ps(["-o", "lstart=", "-p", str(pid)]).split()),
        _ps(["-ww", "-o", "command=", "-p", str(pid)]).strip(),
    )


def _read_pid(pidfile: str) -> int:
    try:
        return int(open(pidfile).read().split()[0])
    except (OSError, ValueError, IndexError):
        return 0


def record_id(pidfile: str, exact: bool = False) -> int:
    """PIDFILE.id = {"pid", "lstart"[, "argv"]}, read now. ``exact`` pins the argv too (for a
    process whose argv cannot name the root, e.g. the planted /bin/sleep)."""
    pid = _read_pid(pidfile)
    lstart, argv = proc_id(pid)
    if not lstart:
        return 1
    rec: Dict[str, Any] = {"pid": pid, "lstart": lstart}
    if exact:
        rec["argv"] = argv
    with open(pidfile + ".id", "w") as fh:
        json.dump(rec, fh)
    return 0


def _names_root(text: str, rig: str) -> bool:
    """``rig`` as a whole path component: /tmp/lr-rig never matches /tmp/lr-rig2."""
    for sep in ("/", " ", "'", '"'):
        if rig + sep in text:
            return True
    return text.endswith(rig)


def verified(rig: str, pid: int, rec: Dict[str, Any]) -> bool:
    lstart, argv = proc_id(pid)
    if not lstart or lstart != rec.get("lstart"):
        return False
    if "argv" in rec:
        return argv == rec["argv"]
    return _names_root(argv, rig) or "lr_recon" in argv


def _signum(name: str) -> int:
    import signal

    return int(getattr(signal, "SIG" + name.upper().replace("SIG", "")))


def kill_verified(rig: str, pidfile: str, sigs: str) -> int:
    """rc 0 signalled · 1 refused (no record, gone, or a different process now owns the pid)."""
    pid = _read_pid(pidfile)
    try:
        rec = load(pidfile + ".id")
    except (OSError, ValueError):
        return 1
    if not pid or rec.get("pid") != pid or not verified(rig, pid, rec):
        return 1
    for s in sigs.split(","):
        try:
            os.kill(pid, _signum(s))
        except OSError:
            return 1
    return 0


def _ancestors() -> set:
    out, pid = set(), os.getpid()
    for _ in range(64):
        out.add(pid)
        ppid = _ps(["-o", "ppid=", "-p", str(pid)]).strip()
        if not ppid.isdigit() or int(ppid) <= 1:
            break
        pid = int(ppid)
    return out


# A real session carries its prompt on argv (`bash …/cc-close-attrib …/claude … <prompt>`), and a
# prompt can name a rig root: such a process is never a rig process unless it runs under the rig env.
CLAUDE_NAMES = ("claude", "claude.exe", "node", "Claude", "cc-close-attrib")


def rig_procs(rig: str) -> List[Tuple[int, str, str]]:
    """(pid, lstart, argv) of every process that belongs to this rig root: its argv names the root,
    or it was exec'd under the rig env (LR_RIG=<root>, read with ps -E). A real claude whose prompt
    merely mentions the root is never one (argv0 outside the root and no rig env). The caller and its
    ancestors are excluded."""
    out: List[Tuple[int, str, str]] = []
    mine = _ancestors()
    env_tag = "LR_RIG=" + rig
    for line in _ps(["-axww", "-E", "-o", "pid=,lstart=,command="]).splitlines():
        parts = line.split(None, 6)
        if len(parts) < 7 or not parts[0].isdigit():
            continue
        pid, lstart, text = int(parts[0]), " ".join(parts[1:6]), parts[6]
        if pid in mine:
            continue
        rig_env = (env_tag + " ") in text or text.endswith(env_tag)
        if not (rig_env or _names_root(text, rig)):
            continue
        head = text.split(" ", 4)[:4]
        if not rig_env and any(
            os.path.basename(t) in CLAUDE_NAMES and not t.startswith(rig + "/")
            for t in head
        ):
            continue
        out.append((pid, lstart, text))
    return out


def sweep(rig: str, sig: str, out: str = "") -> int:
    """Signal every rig_procs process whose lstart still matches (re-read per pid); list what is
    still alive afterwards in ``out`` (rig-result.json's leftovers). rc = the number left."""
    procs = rig_procs(rig)
    for pid, lstart, _text in procs:
        if proc_id(pid)[0] == lstart:
            try:
                os.kill(pid, _signum(sig))
            except OSError:
                pass
    time.sleep(1.0)
    left = [
        {"pid": p, "argv": t[:200]}
        for p, ls, t in rig_procs(rig)
        if proc_id(p)[0] == ls
    ]
    if out:
        result(rig, {"leftovers": left}, path=out)
    return len(left)


def _under(cwd: str, rig: str) -> bool:
    cwd = cwd[len("/private") :] if cwd.startswith("/private/") else cwd
    return cwd == rig or cwd.startswith(rig + "/")


def containment(rig: str, ls: List[Dict[str, Any]]) -> List[str]:
    """S1: an OS window holding a pane under this rig root AND a pane that is not (the operator's
    own window, or the other arm's) is a containment breach. A new OS window the R path opened for a
    rig pane alone is fine."""
    hits: List[str] = []
    for ow in ls:
        mine, other = [], []
        for t in ow.get("tabs", []):
            for w in t.get("windows", []):
                (mine if _under(str(w.get("cwd") or ""), rig) else other).append(
                    str(w.get("id"))
                )
        if mine and other:
            hits.append(
                "os-window %s: rig %s beside %s"
                % (ow.get("id"), ",".join(mine), ",".join(other))
            )
    return hits


def result(rig: str, kv: Dict[str, Any], path: str = "") -> None:
    path = path or os.path.join(rig, "rig-result.json")
    try:
        cur = load(path)
    except (OSError, ValueError):
        cur = {}
    cur.update(kv)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(cur, fh, indent=1)
    os.replace(tmp, path)


def _specs(rig: str) -> List[Dict[str, Any]]:
    return load(os.path.join(rig, "specs.json"))


def _records(rig: str) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    d = os.path.join(rig, "state", "sessions")
    for name in os.listdir(d) if os.path.isdir(d) else []:
        if name.count(".") == 1 and name.endswith(".json"):
            try:
                r = load(os.path.join(d, name))
            except (OSError, ValueError):
                continue
            if isinstance(r, dict) and r.get("sid"):
                out[r["sid"]] = r
    return out


def booted(rig: str) -> int:
    """rc 0 once every live stub has written its boot marker (limit death or idle at rest)."""
    for s in _specs(rig):
        if s["stale_request"]:
            continue
        if not os.path.exists(os.path.join(rig, "tmp", "boot", s["sid"] + ".ok")):
            return 1
    return 0


def _spawn_sleep(rig: str, tag: str) -> int:
    import subprocess

    p = subprocess.Popen(
        ["/bin/sleep", "3600"],
        start_new_session=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    pidfile = os.path.join(rig, tag + ".pid")
    with open(pidfile, "w") as fh:
        fh.write(str(p.pid))
    record_id(pidfile, exact=True)  # its argv cannot name the root: pin the argv itself
    return p.pid


def plant_foreign(rig: str) -> int:
    """A live process with a registry row WITHOUT rig:true and a limit-dead transcript: exactly the
    shape the daemon would move if it were not the rig daemon. It must be refused, never recorded."""
    sid = str(uuid.uuid4())
    pid = _spawn_sleep(rig, "foreign")
    cwd = os.path.join(rig, "work", "foreign")
    os.makedirs(cwd, exist_ok=True)
    cwd = os.path.realpath(cwd)
    reg = os.path.join(rig, "home", ".claude", "cc-registry", "foreign-%d.json" % pid)
    with open(reg, "w") as fh:
        json.dump(
            {
                "session_id": sid,
                "pid": pid,
                "account": "claude-next",
                "name": "foreign",
                "cwd": cwd,
                "surface": "pane",
            },
            fh,
        )
    proj = os.path.join(
        rig, "cfg-a", "projects", cwd.replace("/", "-").replace(".", "-")
    )
    os.makedirs(proj, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    death = os.path.join(
        here, "..", "fixtures", "lr-recon", "jsonl", "death-quota-limits.jsonl"
    )
    with open(death) as src, open(os.path.join(proj, sid + ".jsonl"), "w") as dst:
        rec = json.loads(src.readline())
        rec["sessionId"], rec["cwd"] = sid, cwd
        rec["timestamp"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
        dst.write(json.dumps(rec) + "\n")
    with open(os.path.join(rig, "foreign.sid"), "w") as fh:
        fh.write(sid)
    return 0


def _spawn_member(rig: str, lead_sid: str) -> int:
    """A live TEAMMATE of ``lead_sid`` as lr-team.sh reads one: argv[0] basename claude.exe and the
    adjacent tokens --parent-session-id <lead sid> (D4.13). perl sleeps under that argv[0]; the path
    is under $RIG/bin, so the rig's teardown (`pkill -f $RIG/bin/claude`) reaps it."""
    import subprocess

    p = subprocess.Popen(
        [
            os.path.join(rig, "bin", "claude.exe"),
            "-e",
            "sleep 3600",
            "--",
            "--agent-id",
            "w@session-rig",
            "--parent-session-id",
            lead_sid,
        ],
        executable="/usr/bin/perl",
        start_new_session=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with open(os.path.join(rig, "member-%s.pid" % lead_sid[:8]), "w") as fh:
        fh.write(str(p.pid))
    return p.pid


def plant_faults(rig: str) -> int:
    """Rig-side faults that are state, not stub behaviour: legacy holder dirs, stale requests, and
    a live teammate process for a team lead (never exited, never relaunched: D4.13)."""
    lr = os.path.join(rig, "lr")
    for s in _specs(rig):
        if s["knobs"].get("team_member"):
            _spawn_member(rig, s["sid"])
        if s["legacy_holder"]:
            d = os.path.join(lr, "runs", "by-sid", s["sid"] + ".active")
            os.makedirs(d, exist_ok=True)
            pid = _spawn_sleep(rig, "legacy-" + s["sid"][:8])
            with open(
                os.path.join(d, "holder"), "w"
            ) as fh:  # the pre-W3 shape: a pid, no lstart
                json.dump(
                    {
                        "pid": pid,
                        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    },
                    fh,
                )
        if s["stale_request"]:
            os.makedirs(os.path.join(lr, "requests"), exist_ok=True)
            with open(os.path.join(lr, "requests", s["sid"] + ".json"), "w") as fh:
                json.dump(
                    {"sid": s["sid"], "at": time.time(), "reason": "rig stale request"},
                    fh,
                )
    return 0


def refusal(rig: str) -> int:
    sid = open(os.path.join(rig, "foreign.sid")).read().strip()
    seen = 0
    try:
        with open(os.path.join(rig, "state", "events.jsonl")) as fh:
            for ln in fh:
                if '"rig-refuse"' in ln and sid in ln:
                    seen += 1
    except OSError:
        pass
    rec = os.path.exists(os.path.join(rig, "state", "sessions", sid + ".json"))
    ok = seen > 0 and not rec
    print(
        "refusal: planted non-rig row %s — rig-refuse events %d · record %s · %s"
        % (
            sid[:8],
            seen,
            "PRESENT" if rec else "none",
            "REFUSED" if ok else "NOT REFUSED",
        )
    )
    return 0 if ok else 1


def cohort(rig: str) -> str:
    recs = _records(rig)
    want = {s["sid"] for s in _specs(rig)}
    counts: Dict[str, int] = {}
    for sid, r in recs.items():
        if sid in want and r.get("cohort_id"):
            counts[r["cohort_id"]] = counts.get(r["cohort_id"], 0) + 1
    return max(counts, key=lambda k: counts[k]) if counts else "none"


MOVING = ("TRANSPLANTED", "EXITING", "HUSK-RETIRED", "EXITED", "RELAUNCHED")


def _live_actuator(rec: Dict[str, Any]) -> bool:
    for p in rec.get("procs") or []:
        try:
            pid = int(p.get("pid") or 0)
        except (TypeError, ValueError, AttributeError):
            continue
        if pid > 0:
            try:
                os.kill(pid, 0)
                return True
            except OSError:
                continue
    return False


def _fault_log(rig: str, sid: str, fault: str, what: str) -> None:
    """faults.log: one row per daemon fault the rig fired (or failed to): the P3 evidence."""
    try:
        with open(os.path.join(rig, "state", "faults.log"), "a") as fh:
            fh.write("%d\t%s\t%s\t%s\n" % (time.time(), sid, fault, what))
    except OSError:
        pass


# B1 C5: a hard hold pages at MAX_AGE_S (HOLD-DRAFT 900 s, HOLD-BGWORK 1200 s, types.py); a drive that
# stops at "held 30 s" never sees the page. LR_RIG_HOLD_WINDOW=1 keeps it until entry + age + 2 passes.
HOLD_PAGE_AGE_S = {"HOLD-DRAFT": 900, "HOLD-BGWORK": 1200}
HOLD_PASS_MARGIN_S = 2 * 20.0


def _daemon_pid(rig: str) -> int:
    try:
        return int(open(os.path.join(rig, "state", "daemon.pid")).read().strip())
    except (OSError, ValueError):
        return 0


def _settled(
    spec: Dict[str, Any], rec: Dict[str, Any], held_since: Dict[str, float], now: float
) -> bool:
    exp = spec["expect"]
    if rec is None:
        return False
    if exp.startswith("HOLD"):
        sub = rec.get("substate") or ""
        if rec.get("terminal") is None and sub == exp:
            held_since.setdefault(spec["sid"], now)
            need = 30.0
            if os.environ.get("LR_RIG_HOLD_WINDOW") == "1":
                need = HOLD_PAGE_AGE_S.get(exp, 0) + HOLD_PASS_MARGIN_S
            return now - held_since[spec["sid"]] >= need
        held_since.pop(spec["sid"], None)
        return False
    return rec.get("terminal") is not None


def drive(rig: str, timeout: float) -> int:
    """Fire each daemon fault when its session first leaves PRE-MOVE; stop when every session has
    settled (terminal, or holding its expected HOLD for 30 s) or at the timeout (rc 1). rc 3: the
    containment sampler found a rig pane in a non-rig OS window (NO-VERDICT)."""
    specs = _specs(rig)
    dpf = os.path.join(rig, "state", "daemon.pid")
    hit = os.path.join(rig, "state", "containment.hit")
    t0, fired, cont_at, held = time.time(), set(), 0.0, {}
    last = 0.0
    while True:
        now = time.time()
        recs = _records(rig)
        for s in specs:
            f = s["daemon_fault"]
            r = recs.get(s["sid"])
            if not f or s["sid"] in fired or r is None:
                continue
            if f == "kill9_post_transplant":
                # the incident's shape (REPORT.md:175): the daemon dies AFTER the transplant, while
                # a recorded actuator of this attempt is still alive
                if r.get("phase") in ("TRANSPLANTED", "EXITING") and _live_actuator(r):
                    fired.add(s["sid"])
                    rc = kill_verified(rig, dpf, "KILL")
                    _fault_log(rig, s["sid"], f, "fired" if rc == 0 else "unverified")
                    print(
                        "[rig] fault %s %s on the daemon as %s sat in %s"
                        % (
                            f,
                            "fired" if rc == 0 else "NOT fired",
                            s["sid"][:8],
                            r.get("phase"),
                        ),
                        flush=True,
                    )
                continue
            if r.get("phase") in MOVING or r.get("substate") == "PLANNED":
                pid = _daemon_pid(rig)
                fired.add(s["sid"])
                # S2: by verified identity only; a refused kill is a fault that did not fire
                if f == "kill9" and pid:
                    if kill_verified(rig, dpf, "KILL"):
                        print("[rig] fault %s NOT fired: daemon pid unverified" % f)
                elif f == "sigstop200" and pid:
                    if kill_verified(rig, dpf, "STOP") == 0:
                        cont_at = now + 200
                elif f == "clockskew600":
                    with open(os.path.join(rig, "state", "clock-skew"), "w") as fh:
                        fh.write("600\n")
                print(
                    "[rig] fault %s fired on the daemon (pid %d) as %s entered %s"
                    % (f, pid, s["sid"][:8], r.get("phase")),
                    flush=True,
                )
        if cont_at and now >= cont_at:
            kill_verified(rig, dpf, "CONT")
            cont_at = 0.0
        if os.path.exists(hit):
            print(
                "[rig] NO-VERDICT containment: %s" % open(hit).read().strip(),
                flush=True,
            )
            return 3
        if os.path.exists(os.path.join(rig, "stop")):
            # the load harness stops an arm early (the red arm once power is shown, or an abort);
            # the run still reads its status and writes rig-result.json
            print("[rig] stopped by %s/stop after %ds" % (rig, now - t0), flush=True)
            return 4
        nheld = len(held)
        done = sum(1 for s in specs if _settled(s, recs.get(s["sid"]), held, now))
        if len(held) != nheld:  # H4 reads each hold's observed entry
            result(
                rig, {"held_since": held}, path=os.path.join(rig, "state", "held.json")
            )
        if now - last >= 30:
            last = now
            phases: Dict[str, int] = {}
            for s in specs:
                r = recs.get(s["sid"])
                k = (
                    "no-record"
                    if r is None
                    else (
                        r["terminal"]["outcome"]
                        if r.get("terminal")
                        else "%s/%s" % (r.get("phase"), r.get("substate"))
                    )
                )
                phases[k] = phases.get(k, 0) + 1
            print(
                "[rig %4ds] settled %d/%d · %s"
                % (
                    now - t0,
                    done,
                    len(specs),
                    ", ".join("%s=%d" % kv for kv in sorted(phases.items())),
                ),
                flush=True,
            )
        if done == len(specs):
            return 0
        if now - t0 > timeout:
            print(
                "[rig] TIMEOUT after %ds: %d/%d settled" % (timeout, done, len(specs)),
                flush=True,
            )
            return 1
        time.sleep(2)


def kitty_faults(rig: str) -> int:
    """The kitty-slow wrapper's tables, from windows.sid (wid<TAB>sid, written as each member pane
    opens) and each member's knobs: faults/kitty-delay.tsv `wid lo hi k` (kitty_delay_s [lo, hi],
    the first kitty_delay_k calls only, default 3: B1 F15) and faults/kitty-fail.tsv `wid n`
    (send_text_fail_n). rc 0; prints how many rows each table got."""
    by_sid = {s["sid"]: s for s in _specs(rig)}
    delay, fail = [], []
    try:
        rows = [
            ln.rstrip("\n").split("\t") for ln in open(os.path.join(rig, "windows.sid"))
        ]
    except OSError:
        rows = []
    for row in rows:
        if len(row) < 2 or row[1] not in by_sid:
            continue
        k = by_sid[row[1]]["knobs"]
        if isinstance(k.get("kitty_delay_s"), list) and len(k["kitty_delay_s"]) == 2:
            lo, hi = k["kitty_delay_s"]
            delay.append(
                "%s\t%s\t%s\t%s" % (row[0], lo, hi, int(k.get("kitty_delay_k") or 3))
            )
        if int(k.get("send_text_fail_n") or 0) > 0:
            fail.append("%s\t%d" % (row[0], int(k["send_text_fail_n"])))
    os.makedirs(os.path.join(rig, "faults"), exist_ok=True)
    for name, body in (("kitty-delay.tsv", delay), ("kitty-fail.tsv", fail)):
        with open(os.path.join(rig, "faults", name), "w") as fh:
            fh.write("".join(b + "\n" for b in body))
    print("kitty faults: delay %d · send-text fail %d" % (len(delay), len(fail)))
    return 0


def extra_specs(faults: Dict[str, Any], out: str) -> int:
    """busy_extra N (B1 F5): N more rig panes, WORKING for ever, never members. They hold the
    reconciler's restore budget and drip the way a busy fleet does. Written to specs-extra.json
    (never specs.json: the expected line and the audits count members only)."""
    n = int(faults.get("busy_extra") or 0)
    specs = [
        {
            "n": 100 + i,
            "sid": str(uuid.uuid4()),
            "group": "busy-extra",
            "knobs": {"busy_forever": True},
            "expect": "",
            "stale_request": False,
        }
        for i in range(n)
    ]
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(specs, fh, indent=1)
    print(n)
    return 0


def _pct(xs: List[float], q: float) -> float:
    """Nearest-rank percentile, the same rank rule report._p95 uses for the DoD line."""
    xs = sorted(xs)
    return xs[max(0, int(round(q * len(xs) + 0.5)) - 1)] if xs else 0.0


def timings(rig: str) -> str:
    """The MEASURED timings beside the DoD line (programme DoD items 2 and 7): p50/p95 of
    detect→engaged over the members that engaged in place or moved, and the cohort wall time from
    the first detection to the last terminal verdict. Read from the daemon's records, never the rig's
    own clock."""
    recs = _records(rig)
    sids = {s["sid"] for s in _specs(rig)}
    lat: List[float] = []
    first, last = None, None
    for sid, r in recs.items():
        if sid not in sids:
            continue
        tl = r.get("timeline") or {}
        det = tl.get("detected")
        if det:
            first = det if first is None else min(first, det)
        close = r.get("close") or {}
        if det and close.get("via") in ("ENGAGED", "MOVED") and close.get("at"):
            lat.append(float(close["at"]) - float(det))
        end = (r.get("terminal") or {}).get("at")
        if end:
            last = end if last is None else max(last, end)
    wall = (last - first) if first is not None and last is not None else 0.0
    return (
        "measured: detect→engaged p50 %.0fs · p95 %.0fs over %d engaged · cohort wall %.0fs (first detection → last terminal)"
        % (_pct(lat, 0.50), _pct(lat, 0.95), len(lat), wall)
    )


def main(argv: List[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == "expand":
        specs = expand(load(argv[2]))
        with open(argv[3], "w", encoding="utf-8") as fh:
            json.dump(specs, fh, indent=1)
        print(len(specs))
        return 0
    if cmd == "expected":
        print(expected_line(load(argv[2])))
        return 0
    if cmd == "extra-specs":
        return extra_specs(load(argv[2]), argv[3])
    if cmd == "kitty-faults":
        return kitty_faults(argv[2])
    if cmd == "audit":
        return audit(argv[2], load(argv[3]), argv[4] if len(argv) > 4 else "")
    if cmd == "booted":
        return booted(argv[2])
    if cmd == "plant-foreign":
        return plant_foreign(argv[2])
    if cmd == "plant-faults":
        return plant_faults(argv[2])
    if cmd == "refusal":
        return refusal(argv[2])
    if cmd == "cohort":
        print(cohort(argv[2]))
        return 0
    if cmd == "timings":
        print(timings(argv[2]))
        return 0
    if cmd == "drive":
        return drive(argv[2], float(argv[3]))
    if cmd == "home":
        build_home(argv[2])
        return 0
    if cmd == "record-id":
        return record_id(argv[2], len(argv) > 3 and argv[3] == "exact")
    if cmd == "kill-verified":
        return kill_verified(argv[2], argv[3], argv[4] if len(argv) > 4 else "TERM")
    if cmd == "sweep":
        return min(
            sweep(
                argv[2],
                argv[3] if len(argv) > 3 else "TERM",
                argv[4] if len(argv) > 4 else "",
            ),
            125,
        )
    if cmd == "containment":
        try:
            ls = json.load(sys.stdin)
        except ValueError:
            return 0  # an unreadable ls is no reading, not a breach
        hits = containment(argv[2], ls)
        for h in hits:
            print(h)
        return 3 if hits else 0
    if cmd == "result":
        kv: Dict[str, Any] = {}
        for a in argv[3:]:
            k, _, v = a.partition("=")
            try:
                kv[k] = json.loads(v)
            except ValueError:
                kv[k] = v
        result(argv[2], kv)
        return 0
    print("rig_lib: unknown command %s" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
