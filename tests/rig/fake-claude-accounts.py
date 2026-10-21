#!/usr/bin/env python3
"""fake claude-accounts for the lr-recon rig (FLEET_V2 W5). Answers only what the rig needs.

  --place --lane L --recovery --movers F --facts DIR --kwork F --json
        each mover → the next account (round-robin, rig accounts.json order) that is neither its
        source nor covered by an unexpired, uncontradicted fact in DIR. No eligible account ⇒
        {acct: null, reason: "no-eligible"} (the daemon's WAIT). Deterministic, network-free.
        RIG_PLACE_STAY=1: a mover whose source is uncovered stays ({acct: <source>, reason: stay}).
  --assign-many F · --assign … · --unassign ID      recorded to $LR_RECON_ROOT/fake-accounts.log, rc 0
  anything else                                       recorded, prints {} and exits 0

Every call is appended to $LR_RECON_ROOT/fake-accounts.log so the rig can show what was asked, and
to $LR_RECON_ROOT/band-calls.log as epoch<TAB>pid<TAB>base-priority|?<TAB>placer<TAB>argv[1]|-.

Load knobs (LR_SUSTAINED_LOAD W4), every one OFF unless set, so an unset run is byte-identical:
  RIG_PLACE_CPU_S=F        each --place burns F CPU-seconds (sha256 over 1 MiB) before answering
  RIG_PLACE_MAP_CPU_S=F    used INSTEAD when every mover row carries a `holds` dict (default 0.15)
  RIG_PLACE_SLEEP_S=F      sleep F s before answering the --place calls whose 1-based ordinal is in
  RIG_PLACE_SLEEP_CALLS=   this comma list; ordinals counted in $LR_RECON_ROOT/fake-accounts.calls
  RIG_PLACE_KMAX=N         seat model: an account is eligible only if occupied + live charges
                           (minus the mover's own assign_id) + w <= N; each pick charges the
                           account for the rest of the call. Refusals → fake-accounts.seats.log
  RIG_PLACE_OCCUPIED=JSON  {acct: n} seats already taken (default {})
  RIG_PLACE_CHARGE_TTL_S=F a charge's lifetime (default 900, the real ASSIGN_TTL_MIN=15)
  With KMAX set, --assign-many rows {acct,id,sid,w,ttl_s} and --assign ACCT --id ID [--w W] are
  charged into $LR_RECON_ROOT/fake-accounts.charges.json {id: {acct, w, at}}; --unassign ID voids.
"""

import hashlib
import json
import os
import sys
import time
from typing import Dict, List, Optional

HOME = os.environ.get("HOME", "")
ROOT = os.environ.get("LR_RECON_ROOT", "/tmp/lr-rig/state")
CHARGES = os.path.join(ROOT, "fake-accounts.charges.json")


def band_row(argv: List[str]) -> None:
    """One band-calls.log row: this process's base priority as the placer actually runs (F14)."""
    base = "?"
    try:
        here = os.path.realpath(os.path.dirname(os.path.realpath(__file__)))
        sys.path.insert(0, os.path.join(here, "..", "..", "scripts", "limit-recover"))
        from lr_recon import band  # type: ignore

        p = band.base_priority(os.getpid())
        if p is not None:
            base = str(int(p))
    except Exception:
        pass
    try:
        with open(os.path.join(ROOT, "band-calls.log"), "a") as fh:
            fh.write(
                "%d\t%d\t%s\tplacer\t%s\n"
                % (time.time(), os.getpid(), base, argv[0] if argv else "-")
            )
    except OSError:
        pass


def env_float(name: str, default: Optional[float] = None) -> Optional[float]:
    v = os.environ.get(name, "")
    try:
        return float(v) if v != "" else default
    except ValueError:
        return default


def burn(cpu_s: float) -> None:
    buf = b"\0" * (1 << 20)
    t0 = time.process_time()
    while time.process_time() - t0 < cpu_s:
        hashlib.sha256(buf).digest()


def place_delay(movers: List[dict]) -> None:
    """RIG_PLACE_CPU_S / RIG_PLACE_MAP_CPU_S CPU cost, then RIG_PLACE_SLEEP_S on listed ordinals."""
    cpu = env_float("RIG_PLACE_CPU_S")
    if cpu is not None:
        if all(isinstance(m.get("holds"), dict) for m in movers):
            cpu = env_float("RIG_PLACE_MAP_CPU_S", 0.15) or 0.0
        burn(cpu)
    slp = env_float("RIG_PLACE_SLEEP_S")
    if slp is None:
        return
    path = os.path.join(ROOT, "fake-accounts.calls")
    try:
        n = int(open(path).read().strip() or 0) + 1
    except (OSError, ValueError):
        n = 1
    try:
        with open(path, "w") as fh:
            fh.write(str(n))
    except OSError:
        pass
    want = os.environ.get("RIG_PLACE_SLEEP_CALLS", "").replace(" ", "").split(",")
    if str(n) in want:
        time.sleep(slp)


def charges_load() -> Dict[str, dict]:
    try:
        with open(CHARGES) as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def charges_save(d: Dict[str, dict]) -> None:
    try:
        tmp = CHARGES + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(d, fh)
        os.replace(tmp, CHARGES)
    except OSError:
        pass


def num(v, default: float = 1.0) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def charge(argv: List[str]) -> None:
    """Seat model only: record --assign-many / --assign charges, void on --unassign."""
    if not os.environ.get("RIG_PLACE_KMAX"):
        return
    d = charges_load()
    now = time.time()
    if "--assign-many" in argv:
        try:
            with open(arg(argv, "--assign-many")) as fh:
                for line in fh:
                    r = json.loads(line) if line.strip() else {}
                    if r.get("acct") and r.get("id"):
                        d[str(r["id"])] = {
                            "acct": r["acct"],
                            "w": num(r.get("w", 1)),
                            "at": now,
                        }
        except (OSError, ValueError, AttributeError):
            return
    elif "--assign" in argv:
        acct = arg(argv, "--acct") or arg(argv, "--assign")
        cid = arg(argv, "--id")
        if not (acct and cid) or acct.startswith("--"):
            return
        d[cid] = {"acct": acct, "w": num(arg(argv, "--w") or 1), "at": now}
    elif "--unassign" in argv:
        d.pop(arg(argv, "--unassign"), None)
    else:
        return
    charges_save(d)


def seat_loads(accts: List[str], own: str, now: float) -> Dict[str, float]:
    """occupied + live charges per account, excluding the mover's own assign_id."""
    try:
        occ = json.loads(os.environ.get("RIG_PLACE_OCCUPIED") or "{}")
    except ValueError:
        occ = {}
    ttl = env_float("RIG_PLACE_CHARGE_TTL_S", 900.0) or 0.0
    load = {a: num(occ.get(a, 0), 0.0) for a in accts}
    for cid, c in charges_load().items():
        if cid == own or not isinstance(c, dict) or c.get("acct") not in load:
            continue
        if now - num(c.get("at"), 0.0) < ttl:
            load[c["acct"]] += num(c.get("w", 1))
    return load


def seats_log(sid: str, outcome: str, load: Dict[str, float]) -> None:
    try:
        with open(os.path.join(ROOT, "fake-accounts.seats.log"), "a") as fh:
            fh.write(
                "%d\t%s\t%s\t%s\n"
                % (
                    time.time(),
                    sid[:8],
                    outcome,
                    ",".join("%s=%g" % (a, v) for a, v in sorted(load.items())),
                )
            )
    except OSError:
        pass


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
        movers = [json.loads(line) for line in fh]
    place_delay(movers)
    kmax = env_float("RIG_PLACE_KMAX")
    names = [n for n, _r, _c in accts]
    provisional = {
        n: 0.0 for n in names
    }  # this call's own picks, so two movers cannot overfill
    for m in movers:
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
        elig = [n for n in names if n != src and n not in no]
        if kmax is not None:
            w = num(m.get("w", 1))
            load = seat_loads(names, str(m.get("assign_id") or ""), now)
            for n in names:
                load[n] += provisional[n]
            fits = [n for n in elig if load[n] + w <= kmax]
            if len(fits) < len(elig):
                seats_log(
                    str(m.get("sid", "")), "refused" if not fits else "capped", load
                )
            elig = fits
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
        if kmax is not None:
            provisional[pick] += num(m.get("w", 1))
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
    band_row(argv)
    if "--place" in argv:
        return place(argv)
    charge(argv)
    print("{}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
