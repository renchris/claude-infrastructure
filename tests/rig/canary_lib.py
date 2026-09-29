#!/usr/bin/env python3
"""W5b real-canary helpers for tests/rig/lr-recon-canary.sh (screen reads, waits, faults, verdicts).

Every screen read and keystroke targets a kitty window id the driver created and recorded under
$LR_CANARY_DIR/win/<sid>; nothing here addresses any other window.

  canary_lib.py prime   DIR SID           submit one prompt, wait until the session is at rest
  canary_lib.py seed    ROOT ACCT SID N   the canary-scoped account fact that makes SID idle-eligible
  canary_lib.py drive   DIR ROOT SID N T  wait for the record to close; fire canary N's fault on time
  canary_lib.py verify  DIR ROOT SID N    print the verdict lines; rc 0 only when every check holds
"""

import glob
import json
import os
import re
import signal
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
KITTEN = os.environ.get(
    "LR_KITTEN_BIN", "/Applications/kitty.app/Contents/MacOS/kitten"
)
RULE = re.compile(r"^─{20,}")
HOME = os.environ.get("HOME", os.path.expanduser("~"))


def _read(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read().strip()


def _sock(d: str) -> str:
    return _read(os.path.join(d, "sock"))


def _win(d: str, sid: str) -> str:
    return _read(os.path.join(d, "win", sid))


def kitten(d: str, *a: str) -> str:
    cp = subprocess.run(
        [KITTEN, "@", "--to", _sock(d)] + list(a),
        capture_output=True,
        text=True,
        timeout=20,
    )
    return cp.stdout


def screen(d: str, sid: str) -> List[str]:
    return kitten(d, "get-text", "--match", "id:" + _win(d, sid)).splitlines()


def composer(lines: List[str]) -> Optional[str]:
    """Text inside the composer box (rule / ❯ … / rule), or None when none is rendered."""
    rules = [i for i, ln in enumerate(lines) if RULE.match(ln)]
    for a, b in zip(rules, rules[1:]):
        body = lines[a + 1 : b]
        if body and body[0].startswith("❯"):
            return " ".join(x.strip() for x in body)[1:].strip()
    return None


def send(d: str, sid: str, text: str) -> None:
    kitten(d, "send-text", "--match", "id:" + _win(d, sid), text)


def transcript(sid: str) -> Optional[str]:
    hits = glob.glob(os.path.join(HOME, ".claude*", "projects", "*", sid + ".jsonl"))
    hits.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return hits[0] if hits else None


def assistant_turns(path: Optional[str]) -> int:
    n = 0
    if not path:
        return 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            if '"type":"assistant"' in ln and '"isApiErrorMessage":true' not in ln:
                n += 1
    return n


def prime(d: str, sid: str, timeout: float = 240) -> int:
    t0 = time.time()
    while composer(screen(d, sid)) is None:
        if time.time() - t0 > timeout:
            print("prime %s: no composer after %ds; screen tail:" % (sid[:8], timeout))
            print("\n".join(screen(d, sid)[-12:]))
            return 1
        time.sleep(1)
    send(d, sid, "Reply with only the word OK.")
    time.sleep(1)
    send(d, sid, "\r")
    while True:
        tx = transcript(sid)
        c = composer(screen(d, sid))
        if assistant_turns(tx) >= 1 and c == "" and _at_rest(tx):
            print("prime %s: at rest · transcript %s" % (sid[:8], tx))
            return 0
        if time.time() - t0 > timeout:
            print(
                "prime %s: not at rest after %ds (composer=%r)" % (sid[:8], timeout, c)
            )
            return 1
        time.sleep(2)


def _at_rest(tx: Optional[str]) -> bool:
    """The last user/assistant record is an assistant turn with a text stop."""
    if not tx:
        return False
    last = None
    with open(tx, encoding="utf-8", errors="replace") as fh:
        for ln in fh:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if r.get("type") in ("user", "assistant"):
                last = r
    return bool(
        last
        and last.get("type") == "assistant"
        and (last.get("message") or {}).get("stop_reason")
        in ("end_turn", "stop_sequence")
    )


def seed(root: str, acct: str, sid: str, n: int) -> int:
    """A canary-scoped 5h fact on the source: only the canary daemon reads recon-canary/facts."""
    now = time.time()
    fact = {
        "acct": acct,
        "scope": "5h",
        "status": "rejected",
        "window": "five_hour",
        "resets_at": float(
            int(now) + 7200 + n
        ),  # distinct per canary ⇒ its own cohort id
        "first_sid": sid,
        "observed_at": now,
        "src": "canary",
        "contradicted": False,
        "untested": False,
    }
    d = os.path.join(root, "facts")
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, ".tmp-canary")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(fact, fh, separators=(",", ":"))
    os.replace(tmp, os.path.join(d, "%s.5h.json" % acct))
    print(
        "seeded %s/%s.5h.json resets_at=%d (canary scope)"
        % (d, acct, fact["resets_at"])
    )
    return 0


def record(root: str, sid: str) -> Dict[str, Any]:
    try:
        with open(
            os.path.join(root, "sessions", sid + ".json"), encoding="utf-8"
        ) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def _launch_lines(root: str, sid: str) -> List[List[str]]:
    try:
        with open(os.path.join(root, "launch.log"), encoding="utf-8") as fh:
            return [
                t
                for t in (ln.rstrip("\n").split("\t") for ln in fh)
                if len(t) > 3 and t[1] == sid
            ]
    except OSError:
        return []


def _daemon_pid(root: str) -> int:
    try:
        return int(json.loads(_read(os.path.join(root, "heartbeat"))).get("pid") or 0)
    except (OSError, ValueError):
        return 0


def drive(d: str, root: str, sid: str, n: int, timeout: float) -> int:
    t0, last, killed, cleared = time.time(), "", 0, False
    while time.time() - t0 < timeout:
        r = record(root, sid)
        state = "%s/%s" % (r.get("phase"), r.get("substate"))
        if state != last:
            print(
                "[%4ds] %s %s attempt=%s target=%s"
                % (
                    time.time() - t0,
                    sid[:8],
                    state,
                    r.get("attempt"),
                    r.get("target_acct"),
                ),
                flush=True,
            )
            last = state
        if r.get("terminal"):
            print(
                "[%4ds] %s terminal %s" % (time.time() - t0, sid[:8], r["terminal"]),
                flush=True,
            )
            return 0
        if n == 4 and not killed:
            spawns = [
                t
                for t in _launch_lines(root, sid)
                if t[3] == "spawn" and t[2] == "recon-A"
            ]
            if spawns and time.time() - float(spawns[0][0]) >= 3:
                pid = _daemon_pid(root)
                if pid:
                    os.kill(pid, signal.SIGKILL)
                    killed = pid
                    print(
                        "[%4ds] canary 4: SIGKILL reconciler pid %d mid-cohort (A spawned %.0fs ago)"
                        % (time.time() - t0, pid, time.time() - float(spawns[0][0])),
                        flush=True,
                    )
        if (
            n == 2
            and not cleared
            and os.path.exists(os.path.join(d, "hook", sid + ".after-confirm.fired"))
        ):
            c = composer(screen(d, sid))
            held = (
                "HOLD-DRAFT" in (r.get("close", {}).get("seen") or [])
                or r.get("substate") == "HOLD-DRAFT"
            )
            if c and c.startswith("canary draft") and held:
                time.sleep(
                    20
                )  # the hold is on record; the operator "finishes" the draft
                send(d, sid, "\x7f" * (len(c) + 4))
                cleared = True
                print(
                    "[%4ds] canary 2: draft cleared from the composer (was %r)"
                    % (time.time() - t0, c),
                    flush=True,
                )
        time.sleep(2)
    print(
        "drive %s: no terminal record within %ds (last %s)" % (sid[:8], timeout, last)
    )
    return 1


def verify(d: str, root: str, sid: str, n: int) -> int:
    r = record(root, sid)
    term = r.get("terminal") or {}
    close = r.get("close") or {}
    reg = {}
    win = _win(d, sid)
    for p in glob.glob(os.path.join(HOME, ".claude", "cc-registry", win + ".json")):
        try:
            reg = json.loads(_read(p))
        except (OSError, ValueError):
            pass
    tx = transcript(sid) or ""
    tgt = r.get("target_acct") or ""
    src = r.get("source_acct") or ""
    lines = _launch_lines(root, sid)
    typers: Dict[str, set] = {}
    moves: Dict[str, int] = {}
    for t in lines:
        kv = dict(x.split("=", 1) for x in t[4:] if "=" in x)
        key = kv.get("attempt") or "legacy@" + t[0]
        if t[3] == "taken":
            typers.setdefault(key, set()).add(kv.get("pid", "?"))
        if t[3] == "spawn" and t[2] in (
            "recon-A",
            "recon-A-husk",
            "recon-B",
            "recon-R",
        ):
            moves[key] = moves.get(key, 0) + 1
    double = sum(1 for v in typers.values() if len(v) > 1) + sum(
        1 for v in moves.values() if v > 1
    )
    checks = [
        ("terminal CLOSED", term.get("outcome") == "CLOSED"),
        ("cross-account (%s → %s)" % (src, tgt), bool(tgt) and tgt != src),
        ("same window (record)", bool(close.get("same_window"))),
        ("same uuid (record)", bool(close.get("same_uuid"))),
        (
            "registry: window %s holds sid %s" % (win, sid[:8]),
            reg.get("session_id") == sid,
        ),
        (
            "registry: account is the target's config dir",
            bool(tgt)
            and reg.get("account", "").endswith(
                {
                    "next": "claude-next",
                    "next2": "claude-secondary",
                    "next3": "claude-tertiary",
                    "next4": "claude-quaternary",
                }.get(tgt, "?")
            ),
        ),
        ("double-typer 0", double == 0),
    ]
    via = close.get("via")
    print(
        "canary %d %s: outcome=%s via=%s attempt=%s seen=%s"
        % (
            n,
            sid[:8],
            term.get("outcome"),
            via,
            r.get("attempt"),
            ",".join(close.get("seen") or []),
        )
    )
    print("  transcript now: %s" % tx)
    print(
        "  launch.log rows for sid: %d · move spawns per attempt %s · lock takers per attempt %s"
        % (len(lines), moves or "{}", {k: len(v) for k, v in typers.items()} or "{}")
    )
    ok = True
    for name, good in checks:
        ok = ok and good
        print("  %s %s" % ("✓" if good else "✗", name))
    return 0 if ok else 1


def main(argv: List[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "prime":
        return prime(argv[2], argv[3])
    if cmd == "seed":
        return seed(argv[2], argv[3], argv[4], int(argv[5]))
    if cmd == "drive":
        return drive(argv[2], argv[3], argv[4], int(argv[5]), float(argv[6]))
    if cmd == "verify":
        return verify(argv[2], argv[3], argv[4], int(argv[5]))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
