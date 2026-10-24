#!/usr/bin/env python3
# Skeptic analysis over sk-cache-<acct>.tsv (independent scanner output). Read-only; prints to stdout.
import csv, collections, sys, math, bisect
from datetime import datetime

csv.field_size_limit(10**9)
ACCTS = ["next", "next2", "next3", "next4"]
INT = (
    "sub",
    "side",
    "in",
    "cc",
    "cr",
    "cc1h",
    "cc5m",
    "out_first",
    "out_max",
    "nrec",
    "has_stop",
)


def T(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def M(x):
    return f"{x / 1e6:,.1f}M"


rows = []
for a in ACCTS:
    for r in csv.DictReader(open(f"/tmp/usage-audit/sk-cache-{a}.tsv"), delimiter="\t"):
        for k in INT:
            r[k] = int(r[k])
        rows.append(r)
own = collections.defaultdict(set)
for r in rows:
    own[r["mid"]].add(r["acct"])
U = {}
for r in rows:
    if r["mid"] not in U:
        U[r["mid"]] = r
    else:  # same message seen in another account dir: keep max output
        U[r["mid"]]["out_max"] = max(U[r["mid"]]["out_max"], r["out_max"])
U = list(U.values())
multi = sum(1 for r in rows if len(own[r["mid"]]) > 1)
print(
    f"[1] rows(per-acct unique message.id)={len(rows)} global-unique={len(U)} rows whose message.id is in >1 account={multi} ({multi / len(rows):.1%})"
)
for a in ACCTS:
    n = sum(1 for r in rows if r["acct"] == a)
    d = sum(1 for r in rows if r["acct"] == a and len(own[r["mid"]]) > 1)
    print(f"    {a}: rows={n} shared-with-other-acct={d} ({d / n:.1%})")
dupsub = sum(1 for r in rows if len(own[r["mid"]]) > 1 and r["sub"])
print(f"    of shared rows, in /subagents/ paths: {dupsub / max(1, multi):.1%}")

S = lambda k, f=lambda r: True: sum(r[k] for r in U if f(r))
IN, CC, CR, C1, C5, OF, OM = (
    S(k) for k in ("in", "cc", "cr", "cc1h", "cc5m", "out_first", "out_max")
)
print(
    f"[2] DEDUPED totals: in={M(IN)} cc={M(CC)} (1h {M(C1)}, 5m {M(C5)}, unlabelled {M(CC - C1 - C5)}) cr={M(CR)} out_first={M(OF)} out_max={M(OM)} (+{(OM / OF - 1):.0%}) no_stop_record={sum(1 for r in U if not r['has_stop'])} ({sum(1 for r in U if not r['has_stop']) / len(U):.1%})"
)
for th in (0, 1):
    f = lambda r, th=th: r["sub"] == th
    c1, c5 = S("cc1h", f), S("cc5m", f)
    print(
        f"    {'sub ' if th else 'main'}: n={sum(1 for r in U if f(r))} cc1h={M(c1)} cc5m={M(c5)} 5m-share={c5 / max(1, c1 + c5):.2%}"
    )

# Timelines keyed by relative path (merges cross-account copies of one transcript)
TL = collections.defaultdict(list)
for r in U:
    r["t"] = T(r["ts"])
    TL[r["rel"]].append(r)
for rel, rs in TL.items():
    rs.sort(key=lambda r: r["t"])
    prev = None
    for r in rs:
        if prev is None:
            r["kind"] = "first"
            r["gap"] = None
            r["reb"] = 0
            r["bustA"] = r["bustB"] = False
        else:
            pp = prev["in"] + prev["cc"] + prev["cr"]
            r["gap"] = r["t"] - prev["t"]
            r["reb"] = min(
                r["cc"], max(0, pp - r["cr"])
            )  # tokens re-written that the previous prompt had cached
            r["bustA"] = (
                pp - r["cr"] > 20000 and r["cc"] > 20000
            )  # the original agent's definition
            r["bustB"] = (
                pp >= 20000 and r["cr"] < 0.5 * pp and r["cc"] >= 0.5 * pp
            )  # mine: most of the prior prompt rewritten
            r["kind"] = "bust" if r["bustB"] else "normal"
        prev = r
bA = sum(r["cc"] for r in U if r.get("bustA"))
bB = sum(r["cc"] for r in U if r.get("bustB"))
rebB = sum(r["reb"] for r in U if r.get("bustB"))
first_main = sum(r["cc"] for r in U if r["kind"] == "first" and not r["sub"])
first_sub = sum(r["cc"] for r in U if r["kind"] == "first" and r["sub"])
print(
    f"[3] bust cc, original definition (lost>20k & cc>20k): {M(bA)} = {bA / CC:.1%} of cc; my definition (cr<50% of prev prompt & cc>=50%): {M(bB)} = {bB / CC:.1%}; rebuilt part only {M(rebB)} = {rebB / CC:.1%}"
)
print(
    f"    first-request cc: main {M(first_main)} ({first_main / CC:.1%}) sub {M(first_sub)} ({first_sub / CC:.1%}); first-request cr: main {M(S('cr', lambda r: r['kind'] == 'first' and not r['sub']))} sub {M(S('cr', lambda r: r['kind'] == 'first' and r['sub']))}"
)


def gb(g):
    for lim, l in [
        (300, "<5m"),
        (600, "5-10m"),
        (1800, "10-30m"),
        (3600, "30-60m"),
        (7200, "1-2h"),
        (28800, "2-8h"),
    ]:
        if g < lim:
            return l
    return ">8h"


tab = collections.defaultdict(lambda: [0, 0, 0])
for r in U:
    if r["kind"] == "first":
        continue
    k = ("sub" if r["sub"] else "main", gb(r["gap"]))
    tab[k][0] += 1
    tab[k][1] += r["bustB"]
    tab[k][2] += r["cc"] if r["bustB"] else 0
print("[4] P(bust | thread, gap) with my definition; bust cc")
order = ["<5m", "5-10m", "10-30m", "30-60m", "1-2h", "2-8h", ">8h"]
for th in ("main", "sub"):
    for g in order:
        n, b, c = tab[(th, g)]
        if n:
            print(
                f"    {th:4s} {g:7s} n={n:7d} busts={b:5d} rate={b / n:6.2%} bust_cc={M(c)} ({c / max(1, bB):.0%} of bust cc)"
            )
idle = sum(
    r["cc"]
    for r in U
    if r.get("bustB")
    and ((r["sub"] and r["gap"] > 300) or (not r["sub"] and r["gap"] > 3600))
)
print(f"    bust cc with gap beyond the thread's TTL: {idle / max(1, bB):.1%}")


# Weightings
def wsum(fn, out_key="out_max"):
    return {
        "in": S("in") * fn["in"],
        "cc5m": C5 * fn["cc5m"],
        "cc1h": C1 * fn["cc1h"],
        "ccunl": (CC - C1 - C5) * fn["cc1h"],
        "cr": CR * fn["cr"],
        "out": S(out_key) * fn["out"],
    }


LIST = {"in": 1, "cc5m": 1.25, "cc1h": 2, "cr": 0.1, "out": 5}
METER = {
    "in": 0,
    "cc5m": 0.2905,
    "cc1h": 0.2905,
    "cr": 0,
    "out": 0.4155,
}  # cc-quota-price fitted pp/Mtok; cr bounded ~0; input unidentifiable, dropped
METER_CRB = dict(METER, cr=0.049)  # cache_read at its experimental upper bound


def bustw(fn, f):
    return sum(
        r["cc5m"] * fn["cc5m"] + (r["cc"] - r["cc5m"]) * fn["cc1h"] for r in U if f(r)
    )


for lab, fn, ok in [
    ("LIST out_first (original agent)", LIST, "out_first"),
    ("LIST out_max", LIST, "out_max"),
    ("METER cr=0", METER, "out_max"),
    ("METER cr=0.049 bound", METER_CRB, "out_max"),
]:
    w = wsum(fn, ok)
    Tt = sum(w.values())
    allb = bustw(fn, lambda r: r.get("bustB"))
    mainidle = bustw(fn, lambda r: r.get("bustB") and not r["sub"] and r["gap"] > 3600)
    main12 = bustw(
        fn, lambda r: r.get("bustB") and not r["sub"] and 3600 < r["gap"] <= 7200
    )
    subidle = bustw(fn, lambda r: r.get("bustB") and r["sub"] and r["gap"] > 300)
    sub560 = bustw(fn, lambda r: r.get("bustB") and r["sub"] and 300 < r["gap"] <= 3600)
    allcc = C5 * fn["cc5m"] + (CC - C5) * fn["cc1h"]
    print(
        f"[5] {lab}: shares "
        + ", ".join(f"{k} {v / Tt:.1%}" for k, v in w.items())
        + f" | all cc {allcc / Tt:.1%} | busts {allb / Tt:.1%} (main>1h {mainidle / Tt:.1%}, main 1-2h {main12 / Tt:.1%}, sub>5m {subidle / Tt:.1%}, sub 5-60m {sub560 / Tt:.1%})"
    )
    # rec 3: subagent 5m -> 1h. Extra = all sub 5m writes repriced; saved = sub busts with gap 5-60m
    sub5 = S("cc5m", lambda r: r["sub"])
    extra = sub5 * (fn["cc1h"] - fn["cc5m"])
    print(
        f"    rec3 subagent TTL 1h: extra writes {extra / Tt:+.1%}, avoided sub 5-60m busts {-sub560 / Tt:.1%}, net {(extra - sub560) / Tt:+.1%}"
    )
    # rec 1: wakes at <55min for main idle 1-2h busts; wake cost = prev prompt read at cr weight + 200 output tokens (assumed)
    wk = 0
    nb = 0
    for rel, rs in TL.items():
        for p, r in zip(rs, rs[1:]):
            if r.get("bustB") and not r["sub"] and 3600 < r["gap"] <= 7200:
                pp = p["in"] + p["cc"] + p["cr"]
                wk += pp * fn["cr"] + 200 * fn["out"]
                nb += 1
    print(
        f"    rec1 wakes for main 1-2h busts: n={nb} saved {main12 / Tt:.2%} minus wake cost {wk / Tt:.2%} = net {(main12 - wk) / Tt:.2%}"
    )
