#!/usr/bin/env python3
"""fake claude-accounts for the lr-recon rig (FLEET_V2 W5). Answers only what the rig needs.

  --place --lane L --recovery --movers F --facts DIR --kwork F --json
        each mover → the next account (round-robin, rig accounts.json order) that is neither its
        source nor covered by an unexpired, uncontradicted fact in DIR. No eligible account ⇒
        {acct: null, reason: "no-eligible"} (the daemon's WAIT). Deterministic, network-free.
        RIG_PLACE_STAY=1: a mover whose source is uncovered stays ({acct: <source>, reason: stay}).
  --assign-many F · --assign … · --unassign ID      recorded to $LR_RECON_ROOT/fake-accounts.log, rc 0
  anything else                                       recorded, prints {} and exits 0

Every call is appended to $LR_RECON_ROOT/fake-accounts.log so the rig can show what was asked.
"""

import json
import os
import sys
import time

HOME = os.environ.get("HOME", "")
ROOT = os.environ.get("LR_RECON_ROOT", "/tmp/lr-rig/state")


def log(argv):
    try:
        with open(os.path.join(ROOT, "fake-accounts.log"), "a") as fh:
            fh.write("%d\t%s\n" % (time.time(), " ".join(argv)))
    except OSError:
        pass


def accounts():
    with open(os.path.join(HOME, ".claude", "accounts.json")) as fh:
        rows = json.load(fh)["accounts"]
    out = []
    for a in rows:
        cfg = a["config_dir"].replace("~", HOME, 1)
        out.append((a["name"], os.path.realpath(cfg), os.path.normpath(cfg)))
    return out


def arg(argv, flag):
    return argv[argv.index(flag) + 1] if flag in argv else ""


def blocked(facts_dir, now):
    out = set()
    for name in os.listdir(facts_dir) if os.path.isdir(facts_dir) else []:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(facts_dir, name)) as fh:
                f = json.load(fh)
        except (OSError, ValueError):
            continue
        ra = f.get("resets_at")
        if f.get("contradicted") or (isinstance(ra, (int, float)) and ra <= now):
            continue
        out.add(f.get("acct") or name.split(".", 1)[0])
    return out


def place(argv):
    accts = accounts()
    by_cfg = {}
    for n, real, norm in accts:
        by_cfg[real] = by_cfg[norm] = n
    now = time.time()
    no = blocked(arg(argv, "--facts"), now)
    state = os.path.join(ROOT, "fake-accounts.rr")
    try:
        rr = int(open(state).read().strip() or 0)
    except (OSError, ValueError):
        rr = 0
    out = {}
    with open(arg(argv, "--movers")) as fh:
        for line in fh:
            m = json.loads(line)
            src = m.get("src", "")
            src = by_cfg.get(os.path.realpath(src), by_cfg.get(src, src))
            if os.environ.get("RIG_PLACE_STAY") == "1" and src not in no:
                # D1.11: --place's "stay" — the source itself has room (after its reset)
                out[m["sid"]] = {
                    "acct": src,
                    "reason": "stay",
                    "eta_s": None,
                    "weight": m.get("w", 1),
                }
                continue
            elig = [n for n, _r, _c in accts if n != src and n not in no]
            if not elig:
                out[m["sid"]] = {
                    "acct": None,
                    "reason": "no-eligible",
                    "eta_s": None,
                    "weight": m.get("w", 1),
                }
                continue
            pick = elig[rr % len(elig)]
            rr += 1
            out[m["sid"]] = {
                "acct": pick,
                "reason": "rig-round-robin",
                "eta_s": None,
                "weight": m.get("w", 1),
            }
    with open(state, "w") as fh:
        fh.write(str(rr))
    print(json.dumps(out))
    return 0


def main(argv):
    log(argv)
    if "--place" in argv:
        return place(argv)
    print("{}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
