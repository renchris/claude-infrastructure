#!/usr/bin/python3
"""kitty-naps.py — did a kitty App Nap? RunningBoard's own record, read on a POSITIVE surface.

Backs `scripts/kitty-hygiene.sh naps` (design: docs/research/lr-sustained-load-2026-10-20/impl/
B8-kitty-hygiene.md §2.3, rebuilt per its two reviews, E-1/E-2/S10/S12). Read-only: it runs
`log show` and parses; it never signals, writes a setting or touches kitty.

WHY A POSITIVE SURFACE. An unkeyed kitty acquires its "AppNap adapter assertion" only at a
transition, so a window with no transition holds no acquisition line, and a parser that counts
only acquisitions reads that window exactly like "the key works" (measured on kitty 853, which has
no key: 1,158 lines, 0 acquisitions). The adapter is still listed, held, in RunningBoard's periodic
state dumps (`RBSStateCaptureSet`). So:

  NAPPING     >= 1 adapter on the pid lacking PreventLowPriorirtyCPU (an acquisition, or a held
              one in a dump). Positive evidence: it counts even when some slices are uncovered.  exit 1
  ENROLLED    an adapter on the pid (acquired or held), none napped: the key is NOT in effect,
              the window just held no nap.                                                       exit 1
  NO-ADAPTER  every slice covered, retention reaches --since, >= 1 dump that lists the pid's
              assertions with no adapter among them, AND >= 1 challenge line (a role change away
              from UserInteractiveFocal). No adapter anywhere.                                   exit 0
  UNKNOWN     anything else: a slice our bound cut, a `log show` rc != 0, retention rolled past
              --since, no dump, no challenge. Absence of output is never absence of naps.        exit 3

THE WORK IS BOUNDED, NOT ONLY THE WALL TIME. `log show` took 87 s for a 30-minute window at load
21/core, and a whole night never finishes inside one bound. `scan` slices [since, until) into windows
of at most 20 minutes, runs each under its own bound, and reports coverage per slice; at most
--max-slices run, and the rest are reported uncovered. Coverage is a separate retention probe that
is NOT filtered by pid, so a quiet focal kitty is not misread as rolled-off log.

  kitty-naps.py parse FILE... --pid P [--json]
  kitty-naps.py scan --pid P --since-epoch E [--until-epoch U] [--slice-s 1200] [--slice-timeout 240]
                     [--max-slices 36] [--log /usr/bin/log] [--json]
Exit: 0 NO-ADAPTER · 1 NAPPING/ENROLLED · 2 usage · 3 UNKNOWN.
"""

import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime

TS = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}) ")
ROLE = re.compile(r"Set darwin role to: (\w+)")
NAME = re.compile(r'name:"([A-Za-z0-9]+)"')
CAPTURE = re.compile(r"\(([0-9A-Fa-f-]{36})\) RBSStateCaptureSet")
FOCAL = "UserInteractiveFocal"
NO_NAP = "PreventLowPriorirtyCPU"  # RunningBoard's own spelling
SLICE_MAX_S = 1200


def target_re(pid):
    # [app<…>:853] or [anon<…>:853]. An xpcservice HOSTED by 853 ("target:[xpcservice<…([app<…>:853])
    # …>:97786]") is another process and must not match, so the bracket must open the target itself
    # (line start, a space or "target:"), never follow the "(" of a host. Measured on the 10-20
    # capture: unanchored, 853's ThemeWidget service read as a second, napped adapter.
    return re.compile(r"(?:^|[\s:])\[(?:app|anon)<[^>\]]*>:%d\]" % int(pid))


def entries(text):
    """Split a compact capture into entries: [first line, continuation lines…]."""
    out, cur = [], None
    for line in text.splitlines():
        if TS.match(line):
            if cur:
                out.append(cur)
            cur = [line]
        elif cur is not None:
            cur.append(line)
    if cur:
        out.append(cur)
    return out


def parse(text, pid, st=None):
    """Fold one capture into the state dict st (so slices chain in order)."""
    if st is None:
        st = new_state()
    tre = target_re(pid)
    for ent in entries(text):
        head = ent[0]
        dt = datetime.strptime(TS.match(head).group(1), "%Y-%m-%d %H:%M:%S.%f")
        st["lines"] += 1
        st["last"] = dt
        r = ROLE.search(head)
        if r and tre.search(head.split("Set darwin role")[0]):
            st["events"].append((dt, "role", r.group(1)))
            if r.group(1) != FOCAL:
                st["challenges"] += 1
            continue
        if (
            '"AppNap adapter assertion" ID' in head
            and "Acquiring assertion" in head
            and tre.search(head.split(" from originator")[0])
        ):
            names = set()
            for ln in ent[1:]:
                names.update(NAME.findall(ln))
            st["acquisitions"] += 1
            st["events"].append((dt, "nap", NO_NAP not in names))
            continue
        c = CAPTURE.search(head)
        if c:
            dump = st["dumps"].setdefault(
                c.group(1), {"pid_assertions": 0, "adapters": 0, "napped": 0, "at": dt}
            )
            body = "\n".join(ent)
            for chunk in body.split("<RBAssertion| identifier:")[1:]:
                chunk = chunk.split("<RBConnectionClient|")[0]
                if not tre.search(chunk.split(" explanation:")[0]):
                    continue
                dump["pid_assertions"] += 1
                if 'explanation:"AppNap adapter assertion"' in chunk:
                    dump["adapters"] += 1
                    if NO_NAP not in chunk:
                        dump["napped"] += 1
                        st["events"].append((dt, "nap", True))
    return st


def new_state():
    return {
        "events": [],
        "dumps": {},
        "acquisitions": 0,
        "challenges": 0,
        "lines": 0,
        "last": None,
    }


def intervals(events):
    """Napped intervals (start, end|None, [(dt, role)…]), the prototype's rule (parse_life.py)."""
    role, napped, nap_role, out = "?", None, [], []
    for dt, kind, val in sorted(events, key=lambda e: e[0]):
        if kind == "role":
            role = val
            if napped is not None:
                nap_role.append((dt, role))
        elif val and napped is None:
            napped, nap_role = dt, [(dt, role)]
        elif not val and napped is not None:
            out.append((napped, dt, nap_role))
            napped = None
    if napped is not None:
        out.append((napped, None, nap_role))
    return out


def verdict(st, cov):
    """(verdict, exit code, reason). cov = {"slices", "covered", "retention"}."""
    held = sum(d["adapters"] for d in st["dumps"].values())
    napped = [e for e in st["events"] if e[1] == "nap" and e[2]]
    if napped:
        return "NAPPING", 1, ""
    if st["acquisitions"] or held:
        return "ENROLLED", 1, "an adapter is on the pid: the key is not in effect"
    why = []
    if cov["covered"] < cov["slices"]:
        why.append(
            "%d of %d slice(s) uncovered"
            % (cov["slices"] - cov["covered"], cov["slices"])
        )
    if cov["retention"] != "ok":
        why.append("retention %s" % cov["retention"])
    clean = [
        d for d in st["dumps"].values() if d["pid_assertions"] and not d["adapters"]
    ]
    if not clean:
        why.append("no state dump lists the pid's assertions")
    if not st["challenges"]:
        why.append("no challenge (no role change away from focal)")
    if why:
        return "UNKNOWN", 3, "; ".join(why)
    return "NO-ADAPTER", 0, ""


def report(st, cov, pid, as_json):
    v, rc, why = verdict(st, cov)
    ivs = intervals(st["events"])
    tot = nonfocal = 0.0
    rows = []
    for s, e, roles in ivs:
        dur = (e - s).total_seconds() if e else None
        nf = 0.0
        if e:
            segs = roles + [(e, None)]
            for (a, r), (b, _) in zip(segs, segs[1:]):
                if r != FOCAL:
                    nf += (b - a).total_seconds()
            tot += dur
            nonfocal += nf
        rows.append(
            {
                "start": s.strftime("%Y-%m-%d %H:%M:%S"),
                "end": e.strftime("%Y-%m-%d %H:%M:%S") if e else None,
                "s": dur,
                "nonfocal_s": nf,
                "roles": sorted({r for _, r in roles}),
            }
        )
    held = sum(d["adapters"] for d in st["dumps"].values())
    if as_json:
        print(
            json.dumps(
                {
                    "pid": pid,
                    "verdict": v,
                    "reason": why,
                    "intervals": rows,
                    "napped_s": tot,
                    "napped_nonfocal_s": nonfocal,
                    "acquisitions": st["acquisitions"],
                    "held_adapters": held,
                    "dumps": len(st["dumps"]),
                    "challenges": st["challenges"],
                    "coverage": cov,
                },
                sort_keys=True,
            )
        )
        return rc
    for r in rows:
        print(
            "naps: interval %s -> %s %ss nonfocal=%.0fs roles=%s"
            % (
                r["start"],
                r["end"] or "open",
                "%.0f" % r["s"] if r["s"] is not None else "?",
                r["nonfocal_s"],
                ",".join(r["roles"]),
            )
        )
    print(
        "naps: pid=%s intervals=%d napped_total=%.0fs napped_nonfocal=%.0fs napped_focal=%.0fs acquisitions=%d "
        "held_adapters=%d dumps=%d challenges=%d slices=%d covered=%d retention=%s"
        % (
            pid,
            len(rows),
            tot,
            nonfocal,
            tot - nonfocal,
            st["acquisitions"],
            held,
            len(st["dumps"]),
            st["challenges"],
            cov["slices"],
            cov["covered"],
            cov["retention"],
        )
    )
    print("naps=%s%s" % (v, " (%s)" % why if why else ""))
    return rc


def local(epoch):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(epoch))


def log_show(log, start, end, pred, timeout):
    """(rc, text). Any rc != 0 is reported, never parsed as a complete capture (S12a)."""
    argv = [
        log,
        "show",
        "--style",
        "compact",
        "--start",
        local(start),
        "--end",
        local(end),
        "--predicate",
        pred,
    ]
    # Its own process group, killed whole at the bound: subprocess.run(timeout=) kills only the direct
    # child, and a grandchild still holding the pipe would hold this read past its bound.
    try:
        p = subprocess.Popen(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return 127, ""
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        out, _ = p.communicate()
        return 124, out.decode("utf-8", "replace")


def scan(a):
    pid, since = int(a["pid"]), int(a["since-epoch"])
    until = int(a.get("until-epoch") or time.time())
    step = min(int(a.get("slice-s") or SLICE_MAX_S), SLICE_MAX_S)
    bound = float(a.get("slice-timeout") or 240)
    cap = int(a.get("max-slices") or 36)
    log = a.get("log") or "/usr/bin/log"
    if until <= since or step <= 0:
        print(
            "naps: empty window (since %s, until %s)" % (local(since), local(until)),
            file=sys.stderr,
        )
        return 2
    # Retention: is there ANY runningboardd line in the first two minutes after --since? Not pid-
    # filtered, so a quiet kitty cannot read as rolled-off log (S12c).
    rrc, rtxt = log_show(
        log, since, min(since + 120, until), 'process == "runningboardd"', bound
    )
    retention = (
        "unknown(rc %d)" % rrc if rrc != 0 else ("ok" if entries(rtxt) else "rolled")
    )
    st, n, covered, pred = (
        new_state(),
        0,
        0,
        'process == "runningboardd" AND eventMessage CONTAINS ":%d]"' % pid,
    )
    t = since
    while t < until:
        e = min(t + step, until)
        n += 1
        if n > cap:
            print(
                "naps: slice %s -> %s uncovered (past --max-slices %d)"
                % (local(t), local(e), cap)
            )
        else:
            t0 = time.time()
            rc, txt = log_show(log, t, e, pred, bound)
            parse(txt, pid, st)  # a partial capture still carries positive evidence
            if rc == 0:
                covered += 1
            print(
                "naps: slice %s -> %s rc=%d %s %.0fs"
                % (
                    local(t),
                    local(e),
                    rc,
                    "covered" if rc == 0 else "UNCOVERED",
                    time.time() - t0,
                )
            )
        t = e
    return report(
        st,
        {"slices": n, "covered": covered, "retention": retention},
        pid,
        a.get("json"),
    )


def args_of(argv):
    a, files, i = {}, [], 0
    while i < len(argv):
        k = argv[i]
        if k == "--json":
            a["json"] = True
        elif k.startswith("--") and i + 1 < len(argv):
            a[k[2:]] = argv[i + 1]
            i += 1
        elif k.startswith("--"):
            raise ValueError(k)
        else:
            files.append(k)
        i += 1
    return a, files


def main(argv):
    if len(argv) < 2 or argv[1] not in ("parse", "scan"):
        print(
            "usage: kitty-naps.py parse FILE... --pid P [--json] | scan --pid P --since-epoch E [...]",
            file=sys.stderr,
        )
        return 2
    try:
        a, files = args_of(argv[2:])
        int(a["pid"])
    except (ValueError, KeyError):
        print(
            "kitty-naps: --pid <n> is required (and every flag takes a value)",
            file=sys.stderr,
        )
        return 2
    if argv[1] == "scan":
        try:
            int(a["since-epoch"])
        except (ValueError, KeyError):
            print("kitty-naps: scan needs --since-epoch <n>", file=sys.stderr)
            return 2
        return scan(a)
    st = new_state()
    for f in files:
        with open(f, errors="replace") as fh:
            parse(fh.read(), a["pid"], st)
    return report(
        st,
        {"slices": len(files), "covered": len(files), "retention": "ok"},
        a["pid"],
        a.get("json"),
    )


if __name__ == "__main__":
    sys.exit(main(sys.argv))
