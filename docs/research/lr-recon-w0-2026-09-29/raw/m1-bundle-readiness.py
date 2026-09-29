#!/usr/bin/env python3
"""W0 measurement 1: composer painted -> first Enter the TUI accepted, from limit-recover events.

Read-only. stdlib only. Usage: python3 m1-bundle-readiness.py

Populations
  A  verified bundles: ~/.reso/limit-recover/*/bundle-*/ with INGEST-VERIFIED.txt, file events.jsonl
  B  upgrade runs:     ~/.reso/limit-recover/upgrade/*/events.jsonl

A RUN is one segment of an events.jsonl that starts at a `relaunch-typed` row (the attempt field
is not unique: one bundle carries two spawns, both attempt=1).

Definitions (they follow scripts/limit-recover/lr-fire-resume.sh, proc lr_submit_cr and the
submit loop after it):
  paint   ts of `composer-painted`. The note is written, then the first CR is sent at once, so
          paint -> CR1 is 0 s by construction (1 s event resolution). Runs whose CR1 went out
          UNCONFIRMED (`CR-UNCONFIRMED`, no paint) are counted apart: CR1 = that row's ts.
  CRk     k=1 is the first CR. k=2.. are the `SUBMIT-RECR` rows (a re-sent CR, sent only when the
          transcript has no record AND the composer reads DRAFT-MINE).
  accept  the transcript time of the user record carrying the run token, parsed (ms) from the
          `submitted` row ("... at <iso>") or the `queued` row ("enqueued at <iso>"). Duplicate
          `submitted` rows (two writers) are collapsed; they carry the same iso.
  which   the accepted CR = the last CR whose note ts (floored to the second) is <= accept.
  swallow CR1 was swallowed if a SUBMIT-RECR row follows it, or the run ends FAILED:submit.
Side column (read-only transcript lookup, ~/.claude*/projects/*/<sid>.jsonl):
  ss_done last SessionStart hook attachment between relaunch-typed and accept (or +120 s),
          in seconds after CR1: when the resumed TUI finished its boot hooks.
"""

import datetime as dt
import glob
import json
import math
import os
import re

H = os.path.expanduser("~")
ROOT = os.path.join(H, ".reso", "limit-recover")
ISO = re.compile(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)")


def ts(s):
    s = s.rstrip("Z")
    fmt = "%Y-%m-%dT%H:%M:%S.%f" if "." in s else "%Y-%m-%dT%H:%M:%S"
    return dt.datetime.strptime(s, fmt)


def load(path):
    rows, bad = [], 0
    with open(path, errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                bad += 1
    return rows, bad


def segments(rows):
    segs, cur = [], None
    for r in rows:
        if r.get("state") == "relaunch-typed":
            cur = [r]
            segs.append(cur)
        elif cur is not None:
            cur.append(r)
    return segs


def ss_done(sid8, t_lo, t_hi):
    """Last SessionStart hook attachment in [t_lo, t_hi) from the session transcript, or None."""
    best = None
    for f in glob.glob(os.path.join(H, ".claude*", "projects", "*", sid8 + "*.jsonl")):
        try:
            if dt.datetime.utcfromtimestamp(os.path.getmtime(f)) < t_lo:
                continue
            with open(f, errors="replace") as fh:
                for line in fh:
                    if '"SessionStart' not in line:
                        continue
                    try:
                        e = json.loads(line)
                    except ValueError:
                        continue
                    a = e.get("attachment") or {}
                    if (
                        e.get("type") != "attachment"
                        or a.get("hookEvent") != "SessionStart"
                    ):
                        continue
                    t = ts(e["timestamp"])
                    if t_lo <= t < t_hi and (best is None or t > best):
                        best = t
        except OSError:
            continue
    return best


def analyse(sid8, label, seg):
    st = lambda s: [r for r in seg if r.get("state") == s]
    rt = ts(seg[0]["ts"])
    paint = st("composer-painted")
    unconf = st("CR-UNCONFIRMED")
    withheld = st("CR-WITHHELD")
    recr = [ts(r["ts"]) for r in st("SUBMIT-RECR")]
    run = dict(
        sid=sid8,
        label=label,
        relaunch=rt,
        paint=None,
        cr1=None,
        kind=None,
        recr=recr,
        accept=None,
        verdict=None,
        which=None,
        swallow=None,
        ss=None,
    )
    if paint:
        run["paint"] = ts(paint[0]["ts"])
        run["cr1"], run["kind"] = run["paint"], "painted"
    elif unconf:
        run["cr1"], run["kind"] = ts(unconf[0]["ts"]), "unconfirmed"
    elif withheld:
        run["kind"] = "withheld"
    else:
        run["kind"] = "no-CR"
    for verdict in ("submitted", "queued", "FAILED:submit", "INDETERMINATE:submit"):
        rows = st(verdict)
        if rows:
            run["verdict"] = verdict
            if verdict in ("submitted", "queued"):
                m = ISO.search(rows[0].get("detail") or "")
                if m:
                    run["accept"] = ts(m.group(1))
            break
    if run["verdict"] is None:
        run["verdict"] = "no-verdict"
    if run["cr1"] is not None:
        crs = [run["cr1"]] + recr
        if run["accept"] is not None:
            k = 1
            for i, c in enumerate(crs, 1):
                if c <= run["accept"]:
                    k = i
            run["which"] = k
        run["swallow"] = bool(recr) or run["verdict"] == "FAILED:submit"
        hi = run["accept"] or (run["cr1"] + dt.timedelta(seconds=120))
        s = ss_done(sid8, rt, hi)
        run["ss"] = s
    return run


def secs(a, b):
    return None if a is None or b is None else (b - a).total_seconds()


def pct(xs, p):
    """Nearest-rank percentile."""
    xs = sorted(xs)
    if not xs:
        return None
    return xs[max(0, math.ceil(p / 100.0 * len(xs)) - 1)]


def f(x):
    return "-" if x is None else ("%.1f" % x)


def population(name, files):
    print("=" * 100)
    print("POPULATION %s: %d events files" % (name, len(files)))
    runs, excluded = [], []
    for label, sid8, path in files:
        if not os.path.exists(path):
            excluded.append((sid8, label, "no events.jsonl"))
            continue
        rows, bad = load(path)
        segs = segments(rows)
        if bad:
            excluded.append(
                (sid8, label, "%d unparseable line(s) skipped (run kept)" % bad)
            )
        if not segs:
            excluded.append((sid8, label, "no relaunch-typed row (never spawned)"))
            continue
        for i, seg in enumerate(segs, 1):
            r = analyse(sid8, label + ("#%d" % i if len(segs) > 1 else ""), seg)
            runs.append(r)
            if r["kind"] == "no-CR":
                excluded.append(
                    (
                        sid8,
                        r["label"],
                        "no composer-painted and no CR-UNCONFIRMED row (CR send time "
                        "unknown; verdict %s) - out of all timing stats" % r["verdict"],
                    )
                )
            elif r["kind"] == "unconfirmed":
                excluded.append(
                    (
                        sid8,
                        r["label"],
                        "no composer-painted row (CR-UNCONFIRMED) - out of the painted "
                        "stats, reported apart",
                    )
                )
    hdr = "%-9s %-22s %-11s %6s %6s %5s %-13s %9s %9s %5s %7s %7s" % (
        "sid",
        "run",
        "cr1-kind",
        "rt>p",
        "p>cr1",
        "recr",
        "verdict",
        "cr1>acc",
        "cr1>recr",
        "which",
        "swallow",
        "ss_done",
    )
    print(hdr)
    print("-" * len(hdr))
    for r in runs:
        rt_p = secs(r["relaunch"], r["paint"])
        p_cr1 = 0.0 if r["paint"] else None
        print(
            "%-9s %-22s %-11s %6s %6s %5d %-13s %9s %9s %5s %7s %7s"
            % (
                r["sid"],
                r["label"][:22],
                r["kind"],
                f(rt_p),
                f(p_cr1),
                len(r["recr"]),
                r["verdict"],
                f(secs(r["cr1"], r["accept"])),
                ",".join("%.0f" % secs(r["cr1"], x) for x in r["recr"]) or "-",
                r["which"] or "-",
                {True: "yes", False: "no", None: "-"}[r["swallow"]],
                f(secs(r["cr1"], r["ss"])),
            )
        )
    print(
        "columns: rt>p relaunch-typed->paint s; p>cr1 paint->first CR s (0 by construction);"
        " cr1>acc first CR->accepted record s (= paint->accept for painted runs);"
        " cr1>recr each SUBMIT-RECR s after CR1; ss_done last SessionStart hook s after CR1"
    )
    for kind in ("painted", "unconfirmed"):
        ks = [r for r in runs if r["kind"] == kind]
        acc = [r for r in ks if r["accept"] is not None]
        sub = [secs(r["cr1"], r["accept"]) for r in acc if r["verdict"] == "submitted"]
        allacc = [secs(r["cr1"], r["accept"]) for r in acc]
        print(
            "\n[%s] %s CR1: runs=%d accepted(submitted+queued)=%d submitted=%d queued=%d "
            "FAILED:submit=%d other=%d"
            % (
                name,
                kind,
                len(ks),
                len(acc),
                len(sub),
                sum(r["verdict"] == "queued" for r in ks),
                sum(r["verdict"] == "FAILED:submit" for r in ks),
                sum(
                    r["verdict"] not in ("submitted", "queued", "FAILED:submit")
                    for r in ks
                ),
            )
        )
        for lab, xs in (
            ("CR1->submitted", sub),
            ("CR1->accepted incl. queued", allacc),
        ):
            if xs:
                print(
                    "  %-28s n=%d p50=%s p90=%s max=%s"
                    % (lab, len(xs), f(pct(xs, 50)), f(pct(xs, 90)), f(max(xs)))
                )
        send = {}
        for r in acc:
            k = r["which"]
            crs = [r["cr1"]] + r["recr"]
            send.setdefault(k, []).append(secs(r["cr1"], crs[k - 1]))
        for k in sorted(send):
            print(
                "  accepted CR #%d: %d run(s); sent at s after CR1: %s"
                % (k, len(send[k]), ", ".join("%.0f" % x for x in sorted(send[k])))
            )
        sw = [r for r in ks if r["swallow"]]
        print("  CR1 swallowed: %d of %d" % (len(sw), len(ks)))
        ss = [secs(r["cr1"], r["ss"]) for r in ks if r["ss"] is not None]
        if ss:
            print(
                "  SessionStart hooks done, s after CR1: n=%d p50=%s p90=%s max=%s"
                % (len(ss), f(pct(ss, 50)), f(pct(ss, 90)), f(max(ss)))
            )
    if excluded:
        print("\n[%s] excluded / notes:" % name)
        for sid8, label, why in excluded:
            print("  %-9s %-22s %s" % (sid8, label[:22], why))
    return runs


def main():
    a = []
    for v in sorted(
        glob.glob(os.path.join(ROOT, "*", "bundle-*", "INGEST-VERIFIED.txt"))
    ):
        d = os.path.dirname(v)
        sid = os.path.basename(os.path.dirname(d))
        a.append(
            (
                os.path.basename(d).replace("bundle-", ""),
                sid[:8],
                os.path.join(d, "events.jsonl"),
            )
        )
    b = []
    for d in sorted(glob.glob(os.path.join(ROOT, "upgrade", "*", ""))):
        name = os.path.basename(os.path.dirname(d))
        b.append((name[9:] or name, name[:8], os.path.join(d, "events.jsonl")))
    ra = population("A (verified bundles)", a)
    rb = population("B (upgrade runs)", b)

    # Schedule check: the observed send offsets (s after CR1) of every ACCEPTED CR, painted runs.
    print("=" * 100)
    for name, runs in (("A", ra), ("A+B", ra + rb)):
        acc = [r for r in runs if r["kind"] == "painted" and r["accept"] is not None]
        offs = sorted(
            secs(r["cr1"], ([r["cr1"]] + r["recr"])[r["which"] - 1]) for r in acc
        )
        re_offs = [x for x in offs if x > 0]
        print(
            "[%s] painted, accepted: n=%d; accepted-CR send offsets after CR1: %s"
            % (name, len(offs), ", ".join("%.0f" % x for x in offs))
        )
        print(
            "    p50=%s p90=%s max=%s; re-send-accepted subset n=%d p50=%s p90=%s max=%s"
            % (
                f(pct(offs, 50)),
                f(pct(offs, 90)),
                f(max(offs)),
                len(re_offs),
                f(pct(re_offs, 50)),
                f(pct(re_offs, 90)),
                f(max(re_offs) if re_offs else None),
            )
        )
        for sched in ((10, 25, 40), (10, 30, 45), (10, 40, 55), (10, 45, 60)):
            cov = sum(x <= sched[1] for x in offs)
            print(
                "    schedule %-9s: first two re-sends (<= %ds) cover %d/%d = %.0f%% of accepted-CR "
                "send offsets"
                % (
                    ",".join(map(str, sched)),
                    sched[1],
                    cov,
                    len(offs),
                    100.0 * cov / len(offs),
                )
            )


if __name__ == "__main__":
    main()
