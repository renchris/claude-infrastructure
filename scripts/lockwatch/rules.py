"""rules.py -- lockwatch thresholds, rules and the level machine. Pure functions over plain dicts.

Imported by lockprobe.py (the core) and diagnose.py. Nothing here makes a syscall, so the replay
tests can drive it with recorded observations and get exactly what the live core would decide.

Every value is a tunable in THRESHOLDS and is logged per tick (DESIGN §4). Levels:
  L1 WATCH     a rule at >= 60% of its ceiling for 2 consecutive probes
  L2 DIAGNOSE  a rule at >= 80% held >= 30 s, or a DEFINITIVE signal
  L3 ESCALATE  L2 >= 10 min with a canary still stuck, or unpoison ran without recovery
  exit         every live rule below 40% for 3 consecutive probes and >= 90 s (L3: ack, or L0 10 min)

Phase 1 (DESIGN §7): P1, P3, P7, P8, P11 move the level. P4, P5, P6 are SHADOW: they are computed,
logged and may request a precursor snapshot, but never change the level. A rule over its fire
budget is `noisy` and leaves the level computation entirely (I7). Load is never an input.

Starvation (lesson 3): every deadline is multiplied by the core's oversleep ratio, and a timing taken
while the core itself is starved is recorded as `unknown`, never as a breach.
"""

RULES_VERSION = 1

THRESHOLDS = {
    # P1 fresh-pty zsh -fc (ptycanary): ceiling 2.0 s user SLO (design value); healthy 8-14 ms
    "P1_ceiling_ms": 2000.0,
    "P1_stuck_s": 15.0,
    # P3 /dev walk (devfs-canary): ceiling 250 ms; WEDGED stuck_s >= 20 -> L2 (definitive)
    "P3_ceiling_ms": 250.0,
    "P3_wedged_s": 20.0,
    # P4 stuck census (shadow): healthy 0; >=1 for 2 probes L1; >=3 L2 (with a ttyname-class leaf)
    "P4_age_s": 20.0,
    "P4_l2_n": 3,
    # P5 exiting pty session leader persistent > 60 s (shadow; snapshot)
    "P5_exiting_s": 60.0,
    # P6 orphan pty session leader persistent > 5 min (shadow; snapshot + WOULD unpoison)
    "P6_orphan_s": 300.0,
    # P7 kitty RC sockets: PEER_LIMIT 256
    "P7_ceiling": 256.0,
    # P8 kitty thread-0 CPU flat while sockets grow: 60 s
    "P8_ceiling_s": 60.0,
    "P8_grow_min": 2,
    # P11 probe stuck: 3x the type's own load-scaled p99, floored
    "P11_mult": 3.0,
    "P11_floor_s": {"procscan": 10.0, "walk": 15.0, "fdscan": 60.0, "pty": 30.0},
    # a stuck probe alone is WATCH: proc-table and exec slowness also happen under plain overload
    # (R7: ps asleep 0-89 s in the kern_proc handler at 03:40, box not wedged; and a live 66-78 s
    # procscan at load 19/core). Only a probe stuck past this (x starvation) is a wedge -> L2.
    "P11_wedge_s": 600.0,
    # child starvation: a python probe's request -> `started` latency on a quiet box (~0.1-0.3 s)
    "child_base_s": 1.0,
    # levels
    "l1_frac": 0.6,
    "l2_frac": 0.8,
    "exit_frac": 0.4,
    "l1_probes": 2,
    "l2_hold_s": 30.0,
    "exit_probes": 3,
    "exit_hold_s": 90.0,
    "l3_after_s": 600.0,
    "l3_exit_l0_s": 600.0,
    # starvation: ratio = 1 + p90(oversleep)/tick; OK below starv_ok, ratio capped for deadlines
    "starv_ok": 1.5,
    "starv_cap": 30.0,
}

LIVE_RULES = ("P1", "P3", "P7", "P8", "P11")
SHADOW_RULES = ("P4", "P5", "P6")
ALL_RULES = LIVE_RULES + SHADOW_RULES
# fires (entries into >= 60%) allowed per 24 h before a rule is `noisy` (lesson 4 / I7)
FIRE_BUDGET_24H = {
    "P1": 24,
    "P3": 12,
    "P4": 24,
    "P5": 12,
    "P6": 6,
    "P7": 12,
    "P8": 12,
    "P11": 24,
}
STUCK_COMMS = ("ps", "login", "zsh", "ls", "tty")
TTYNAME_LEAVES = (
    "devname_r",
    "devname",
    "ttyname_r",
    "ttyname",
    "lstat",
    "__open",
    "spec_open",
)
NODEV = 0xFFFFFFFF


def is_pty(tdev):
    return tdev is not None and tdev != NODEV and ((int(tdev) >> 24) & 0xFF) == 16


def tty_name(tdev):
    if not is_pty(tdev):
        return None
    return "ttys%03d" % (int(tdev) & 0xFFFFFF)


def _p90(xs):
    xs = sorted(max(0.0, x) for x in xs)
    return xs[min(len(xs) - 1, int(round(0.9 * (len(xs) - 1))))] if xs else 0.0


def starvation(oversleeps_s, tick_s, th=THRESHOLDS, startups_s=None):
    """Two gauges, the worse one wins.
    core:  1 + p90(core oversleep)/tick. The core runs at user-interactive QoS, so this alone can
           read 1.0 while its default-band children crawl (measured 2026-10-25 at load ~19/core:
           core ratio 1.005 while two procscans took 66-78 s).
    child: 1 + p90(probe startup latency: request -> the probe's own `started` line)/child_base_s.
    ok when the combined ratio <= starv_ok."""
    core = 1.0 + _p90(oversleeps_s or []) / float(tick_s or 2.0)
    child = 1.0 + _p90(startups_s or []) / th["child_base_s"] if startups_s else 1.0
    ratio = max(core, child)
    return {
        "ratio": round(ratio, 3),
        "ok": ratio <= th["starv_ok"],
        "p90_ms": round(_p90(oversleeps_s or []) * 1000, 1),
        "core_ratio": round(core, 3),
        "child_ratio": round(child, 3),
        "child_p90_ms": round(_p90(startups_s or []) * 1000, 1),
    }


def _scale(starv, th):
    return min(max(1.0, starv.get("ratio", 1.0)), th["starv_cap"])


# ---------------------------------------------------------------- joins -------------------
def ttymap_update(ttymap, procs, now):
    """Fold one healthy procscan into the (pid:lstart) -> last pty map (DESIGN C1, R13).

    An exiting leader reads e_tdev = NODEV (proc_exit clears the session tty before VNOP_REVOKE),
    so its node is only nameable from what an EARLIER sample saw. Entries whose process left the
    table are dropped after 600 s."""
    seen = set()
    for p in procs:
        key = "%d:%d" % (p["pid"], p.get("lstart", 0))
        seen.add(key)
        e = ttymap.get(key)
        if is_pty(p.get("tdev")):
            if e is None:
                e = ttymap[key] = {
                    "pid": p["pid"],
                    "lstart": p.get("lstart", 0),
                    "first_seen": now,
                }
            e.update(
                tdev=int(p["tdev"]),
                tty=tty_name(p["tdev"]),
                pgid=p["pgid"],
                ppid=p["ppid"],
                sleader=bool(p.get("sleader")),
                comm=p.get("comm"),
                sid=p.get("sid"),
            )
        if e is not None:
            e["last_seen"] = now
            e["exiting"] = bool(p.get("exiting")) or p.get("stat") == "Z"
            if p.get("ppid") is not None:
                e["ppid_now"] = p["ppid"]
            if e["exiting"] and not e.get("exiting_since"):
                e["exiting_since"] = now
    for key in list(ttymap):
        if key not in seen and now - ttymap[key].get("last_seen", now) > 600:
            del ttymap[key]
    return ttymap


def pty_leaders(procs, ttymap):
    """Session leaders whose ctty is (or, per ttymap, was) a pty, with exiting/orphan flags."""
    out = []
    for p in procs:
        if not p.get("sleader"):
            continue
        e = ttymap.get("%d:%d" % (p["pid"], p.get("lstart", 0)))
        tdev = p.get("tdev")
        if not is_pty(tdev) and e:
            tdev = e.get("tdev")
        if not is_pty(tdev):
            continue
        out.append(
            {
                "pid": p["pid"],
                "lstart": p.get("lstart", 0),
                "pgid": p["pgid"],
                "tdev": int(tdev),
                "tty": tty_name(tdev),
                "ppid": p["ppid"],
                "state": p.get("stat"),
                "exiting": bool(p.get("exiting")) or p.get("stat") == "Z",
                "orphan": p["ppid"] == 1,
                "exiting_since": (e or {}).get("exiting_since"),
                "first_seen": (e or {}).get("first_seen"),
            }
        )
    return out


def session_tree(leader, procs):
    """The RCA R3 target set of a session leader: its descendants by ppid walk, plus every pid whose
    sid is the leader, plus every member of any pgid in that set (RCA.md §7 R3). Kill-by-pgid alone
    is not enough: an opener can sit in another process group (13:15: zsh 27387 in pgid 27387 under
    leader 81102), and members of a revoking session read NODEV, so tdev cannot be used."""
    kids = {}
    for p in procs:
        kids.setdefault(p["ppid"], []).append(p["pid"])
    tree, todo = set(), [leader]
    while todo:
        pid = todo.pop()
        for c in kids.get(pid, []):
            if c not in tree and c != leader:
                tree.add(c)
                todo.append(c)
    tree |= {p["pid"] for p in procs if p.get("sid") == leader and p["pid"] != leader}
    pgids = {p["pgid"] for p in procs if p["pid"] in tree} | {leader}
    tree |= {p["pid"] for p in procs if p["pgid"] in pgids and p["pid"] != leader}
    return tree


def poison_join(last_node, procs, ttymap, samples=None):
    """Name the wedged node's leader, its session tree and the opener ("holder"). The leader is
    found through the ttymap (an exiting leader reads e_tdev NODEV, R13), the members through
    ppid/sid/pgid (session_tree), never by tdev. `last_node` is the walk canary's
    `last="lstat ttysNNN"`; `samples` maps pid -> sample leaf frame. Returns None when no exiting
    or orphaned leader held that node."""
    tty = (last_node or "").replace("lstat", "").strip()
    if not tty.startswith("ttys"):
        return None
    cands = [L for L in pty_leaders(procs, ttymap) if L["tty"] == tty and (L["exiting"] or L["orphan"])]
    if not cands:
        return None
    L = sorted(cands, key=lambda c: (not c["exiting"], c["pid"]))[0]
    tree = session_tree(L["pid"], procs)
    members = [p for p in procs if p["pid"] in tree]
    samples = samples or {}
    holder, basis = None, "unknown"
    for p in sorted(members, key=lambda q: q["pid"]):
        leaf = samples.get(p["pid"]) or samples.get(str(p["pid"]))
        if leaf and "__open" in leaf:
            holder, basis = p["pid"], "sample:__open"
            break
    live = [p for p in members if not p.get("exiting") and p.get("stat") != "Z"]
    if holder is None and len(live) == 1:
        holder, basis = live[0]["pid"], "only-live-member"
    return {
        "tty": tty,
        "leader": L["pid"],
        "lstart": L["lstart"],
        "pgid": L["pgid"],
        "holder": holder,
        "holder_basis": basis,
        "members": sorted(p["pid"] for p in members),
        # kill these (opener first), then the leader; exiting ones are unkillable: log, move on
        "targets": ([holder] if holder in [p["pid"] for p in live] else [])
        + sorted(p["pid"] for p in live if p["pid"] != holder),
        "unkillable": sorted([L["pid"]] + [p["pid"] for p in members if p.get("exiting") or p.get("stat") == "Z"]),
        "exiting_since": L.get("exiting_since"),
    }


# ---------------------------------------------------------------- rules -------------------
def evaluate(obs, th=THRESHOLDS):
    """One tick's per-rule results: {rule: {x, definitive, unknown, seq, detail}}.

    x is the fraction of the rule's ceiling (0 when healthy); `seq` names the probe result the
    value came from so streaks count probes, not ticks."""
    starv = obs.get("starv") or {"ratio": 1.0, "ok": True}
    k = _scale(starv, th)
    r = {}

    # P1 fresh-pty canary
    pty = obs.get("pty") or {}
    x, definitive, unknown, det = 0.0, False, False, ""
    if pty.get("state") == "outstanding":
        age_ms = float(pty.get("age_s", 0)) * 1000.0
        x = age_ms / th["P1_ceiling_ms"]
        if pty.get("age_s", 0) >= th["P1_stuck_s"] * k:
            definitive = (
                starv.get("ok", True)
                or pty.get("age_s", 0) >= th["P1_stuck_s"] * th["starv_cap"]
            )
            unknown = not definitive
        elif not starv.get("ok", True) and x >= th["l1_frac"]:
            unknown = True
        det = "outstanding %.1fs" % pty.get("age_s", 0)
    elif pty.get("state") == "done" and pty.get("ms") is not None:
        x = float(pty["ms"]) / (th["P1_ceiling_ms"] * k)
        # a timing that would breach unscaled, taken while starved, is `unknown` (lesson 3)
        if not starv.get("ok", True) and float(pty["ms"]) / th["P1_ceiling_ms"] >= th["l1_frac"]:
            unknown = True
        det = "zsh_ms=%s" % pty["ms"]
    r["P1"] = {
        "x": 0.0 if unknown else x,
        "definitive": definitive,
        "unknown": unknown,
        "seq": pty.get("seq"),
        "detail": det,
    }

    # P3 /dev walk canary
    w = obs.get("walk") or {}
    x, definitive, unknown, det = 0.0, False, False, ""
    if w.get("verdict") in ("WEDGED", "WEDGED_PREVIOUS"):
        stuck = float(w.get("stuck_s") or w.get("after_s") or 0)
        # steady = the SAME abandoned child reported the SAME entry across observations: a
        # starved walk advances its last= node, a wedged one cannot
        steady = float(w.get("last_steady_s") or 0) >= th["P3_wedged_s"]
        x = max(th["l2_frac"], stuck / th["P3_wedged_s"])
        if stuck >= th["P3_wedged_s"] * k and steady:
            definitive = True
        elif stuck >= th["P3_wedged_s"]:
            unknown = True
        det = "%s stuck_s=%d last=%s" % (w.get("verdict"), stuck, w.get("last"))
    elif w.get("verdict") == "OK" and w.get("scan_ms") is not None:
        x = float(w["scan_ms"]) / (th["P3_ceiling_ms"] * k)
        # a timing that would breach unscaled, taken while starved, is `unknown` (lesson 3)
        if not starv.get("ok", True) and float(w["scan_ms"]) / th["P3_ceiling_ms"] >= th["l1_frac"]:
            unknown = True
        det = "scan_ms=%s" % w["scan_ms"]
    r["P3"] = {
        "x": 0.0 if unknown else x,
        "definitive": definitive,
        "unknown": unknown,
        "seq": w.get("seq"),
        "detail": det,
        "last": w.get("last"),
    }

    ps = obs.get("procscan") or {}
    pseq = ps.get("seq")

    # P4 stuck census (shadow)
    st = obs.get("stuck") or {}
    n = int(st.get("n", 0))
    r["P4"] = {
        "x": (
            th["l2_frac"] if n >= th["P4_l2_n"] else (th["l1_frac"] if n >= 1 else 0.0)
        ),
        "definitive": False,
        "unknown": False,
        "seq": pseq,
        "detail": "stuck n=%d" % n,
    }

    # P5 exiting pty session leader > 60 s (shadow)
    ex = [
        L
        for L in obs.get("leaders", [])
        if L.get("exiting") and L.get("exiting_s", 0) > th["P5_exiting_s"]
    ]
    r["P5"] = {
        "x": th["l1_frac"] if ex else 0.0,
        "definitive": False,
        "unknown": False,
        "seq": pseq,
        "detail": ",".join("%d(%s)" % (L["pid"], L.get("tty")) for L in ex),
        "hits": ex,
    }

    # P6 orphan pty session leader > 5 min (shadow)
    orp = [
        L
        for L in obs.get("leaders", [])
        if L.get("orphan")
        and not L.get("exiting")
        and L.get("orphan_s", 0) > th["P6_orphan_s"]
    ]
    r["P6"] = {
        "x": th["l1_frac"] if orp else 0.0,
        "definitive": False,
        "unknown": False,
        "seq": pseq,
        "detail": ",".join("%d(%s)" % (L["pid"], L.get("tty")) for L in orp),
        "hits": orp,
    }

    # P7 / P8 kitty RC
    kt = obs.get("kitty") or {}
    socks = kt.get("sockets")
    r["P7"] = {
        "x": (float(socks) / th["P7_ceiling"]) if socks is not None else 0.0,
        "definitive": False,
        "unknown": socks is None and kt.get("present", False),
        "seq": pseq,
        "detail": "sockets=%s" % socks,
    }
    flat = float(kt.get("t0_flat_s", 0))
    growing = kt.get("sockets_growth", 0) >= th["P8_grow_min"]
    x8 = flat / th["P8_ceiling_s"] if growing else 0.0
    r["P8"] = {
        "x": x8,
        "definitive": x8 >= 1.0,
        "unknown": False,
        "seq": pseq,
        "detail": "t0_flat_s=%.0f growth=%s" % (flat, kt.get("sockets_growth", 0)),
    }

    # P11 probe stuck age (a probe that has not even printed `started` is exec/scheduler latency,
    # i.e. starvation, and reads unknown, never a stall)
    worst, which, age_w = 0.0, "", 0.0
    phases = obs.get("probe_phase") or {}
    for typ, age in (obs.get("probe_age") or {}).items():
        lim = (
            max(
                th["P11_floor_s"].get(typ, 30.0),
                th["P11_mult"] * float((obs.get("probe_p99") or {}).get(typ, 0)),
            )
            * k
        )
        frac = float(age) / lim if lim else 0.0
        if typ == "pty":
            continue  # P1 owns the pty canary's age
        if frac > worst:
            worst, which, age_w = frac, typ, float(age)
    started = which == "" or phases.get(which) not in (None, "")
    stuck = worst >= 1.0
    r["P11"] = {
        "x": (th["l1_frac"] if stuck else min(worst, 0.99) * th["exit_frac"]) if started else 0.0,
        "definitive": bool(stuck and started and age_w >= th["P11_wedge_s"] * k),
        "unknown": bool(stuck and not started),
        "seq": "%s:%d" % (which, int(worst)),  # one probe per stuck-limit multiple
        "detail": ("stuck:%s phase=%s age=%ds" % (which, phases.get(which), age_w)) if stuck else "",
        "stuck_type": which if stuck else None,
    }
    return r


# ---------------------------------------------------------------- level machine -----------
def new_machine():
    return {
        "level": 0,
        "level_since": None,
        "rules": {},
        "want_below_since": None,
        "l0_since": None,
        "fires": {},
        "noisy": {},
        "episode": None,
    }


def _rule_state(m, name):
    return m["rules"].setdefault(
        name, {"hi": 0, "lo": 0, "since80": None, "last_seq": None, "on": False}
    )


def step(
    m, res, now, th=THRESHOLDS, ack_ts=None, unpoison_failed=False, canary_stuck=False
):
    """Advance the level machine one tick. Mutates and returns m, plus (want, reasons, shadow)."""
    want = 0
    reasons, shadow = [], []
    for name in ALL_RULES:
        rr = res.get(name)
        if rr is None:
            continue
        s = _rule_state(m, name)
        new_probe = rr.get("seq") != s["last_seq"]
        x = rr["x"]
        if new_probe:
            s["last_seq"] = rr.get("seq")
            if not rr.get("unknown"):
                if x >= th["l1_frac"]:
                    s["hi"] += 1
                    s["lo"] = 0
                elif x < th["exit_frac"]:
                    s["lo"] += 1
                    s["hi"] = 0
                else:
                    s["lo"] = 0
        if x >= th["l2_frac"] and not rr.get("unknown"):
            s["since80"] = s["since80"] or now
        else:
            s["since80"] = None
        lvl = 0
        if rr.get("definitive"):
            lvl = 2
        elif s["since80"] is not None and now - s["since80"] >= th["l2_hold_s"]:
            lvl = 2
        elif s["hi"] >= th["l1_probes"]:
            lvl = 1
        on = lvl >= 1
        if on and not s["on"]:
            fl = m["fires"].setdefault(name, [])
            fl.append(now)
        s["on"] = on
        m["fires"][name] = [t for t in m["fires"].get(name, []) if now - t < 86400]
        if len(m["fires"][name]) > FIRE_BUDGET_24H.get(name, 24) and not m["noisy"].get(
            name
        ):
            m["noisy"][name] = {"since": now, "version": RULES_VERSION}
        if lvl and name in SHADOW_RULES:
            shadow.append({"rule": name, "level": lvl, "detail": rr.get("detail")})
            continue
        if lvl and m["noisy"].get(name):
            shadow.append(
                {"rule": name, "level": lvl, "detail": rr.get("detail"), "noisy": True}
            )
            continue
        if lvl:
            reasons.append("%s:L%d %s" % (name, lvl, rr.get("detail", "")))
            want = max(want, lvl)
    all_low = all(
        m["rules"].get(n, {}).get("lo", 0) >= th["exit_probes"]
        or (res.get(n) or {}).get("x", 0) < th["exit_frac"]
        for n in LIVE_RULES
        if not m["noisy"].get(n)
    )
    cur = m["level"]
    new = cur
    if want > cur and cur < 3:
        new = want
        m["want_below_since"] = None
    elif cur == 3:
        if ack_ts and m["level_since"] and ack_ts >= m["level_since"]:
            new = want
        elif want == 0:
            m["l0_since"] = m["l0_since"] or now
            if now - m["l0_since"] >= th["l3_exit_l0_s"]:
                new = 0
        else:
            m["l0_since"] = None
    elif want < cur:
        m["want_below_since"] = m["want_below_since"] or now
        if all_low and now - m["want_below_since"] >= th["exit_hold_s"]:
            new = want
    else:
        m["want_below_since"] = None
    if (
        new == 2
        and cur == 2
        and m["level_since"]
        and (
            (now - m["level_since"] >= th["l3_after_s"] and canary_stuck)
            or unpoison_failed
        )
    ):
        new = 3
        reasons.append(
            "L3: L2 for %ds with a canary still stuck" % (now - m["level_since"])
            if not unpoison_failed
            else "L3: unpoison ran without recovery"
        )
    if new != cur:
        m["level"] = new
        m["level_since"] = now
        m["want_below_since"] = None
        if new != 3:
            m["l0_since"] = None
        if cur == 0 and new > 0:
            m["episode"] = now
        if new == 0:
            m["episode"] = None
    elif m["level_since"] is None:
        m["level_since"] = now
    return m, want, reasons, shadow


def verdict_for(res, level, join=None):
    """Short verdict string for state.json from the rule results (diagnose.py refines it)."""
    if join:
        return "devfs_poison(%s)" % join["tty"]
    p11 = res.get("P11", {})
    if res.get("P3", {}).get("definitive") or (
        p11.get("definitive") and p11.get("stuck_type") in ("walk", "fdscan")
    ):
        return "devfs_lookup_stall"
    if res.get("P8", {}).get("definitive") or (
        res.get("P8", {}).get("x", 0) >= THRESHOLDS["l2_frac"]
    ):
        return "kitty_rc_deaf"
    if p11.get("definitive") and p11.get("stuck_type") == "procscan":
        return "proc_table_stall"
    if res.get("P1", {}).get("definitive"):
        return "pty_spawn_stall"
    if any(r.get("unknown") for r in res.values()):
        return "unknown"
    if level and p11.get("stuck_type"):
        return "watch:stuck:%s" % p11["stuck_type"]
    return "ok" if level == 0 else "watch"
