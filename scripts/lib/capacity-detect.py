#!/usr/bin/env python3
"""capacity-detect.py — record-only detectors D1-D9 over the capacity-attrib series.

Design: docs/research/load-root-cause-2026-10-17/DESIGN.md §4.2.

WHY. The load rung pages 81-183 times a day on load per core, a number that names no cause and so
cannot be acted on. Each detector here watches one CAUSE (a gate pile-up, a fork storm, a starved
sampler, a 4 GB transient...) and keys every occurrence on that cause's identity, so one occurrence is
one raise and one clear, however long it lasts. The sampler daemon (WP-7) calls Detectors.step() on
each row it writes; --replay runs the same code over a saved series.

RECORD-ONLY. For the first 7 d every detector only appends what it WOULD do (`would`: page | file |
retract) to the record log. It never pages, never files a row and never touches a wake file (D6 logs
`would_touch` instead). The sinks go live in WP-17, after a week of series has been replayed with
controls.

RULES (§4.2, every detector):
  raise    3 consecutive ticks over the high line; D2 needs 60 s of them, D3 5 min, D8's CPU leg
           15 min; D9 needs ONE tick, because lifetime_max_phys_footprint is monotonic, so one reading
           is proof and a 3-tick rule would miss a 20 s transient.
  clear    10 min continuously under the low line (D9: the occurrence's process is gone), on the SAME
           key. A tick between the two lines resets both the raise count and the clear timer.
  key      cause identity only, never a count or a time (hooks/lib/page-damp.sh:14-17).
  cause-or-silence  a raise whose key names no cause (`unattributed`) records with would=null, and 6 h
           after the first such raise the detector writes one `instrument-gap`.
  flapping the 7th raise inside 24 h writes one `detector-flapping`; that detector's raises then record
           with would=null for 24 h.
  abstain  an ABSENT input key means NOT MEASURED, which is not zero: the detector neither raises nor
           clears, and writes at most one `abstain` per 6 h. An empty list IS a reading (none found).
  never    load per core, headroom, vnode fill and "close sessions" are not detectors and never will be.

OPTIONAL ROW KEYS. Today's rows carry none of these; WP-7 emits them.
  gates        [{repo, worktree, kind}]  one per running full-gate root: pytest -n with no file
               args, a bats root, xcodebuild (D1)
  fork_lineage {comm, pid, start}  parent with the most reaped-child sys-CPU (D2 and D3 keys)
  vnode        {num_newvnode_calls}  the cumulative sysctl counter; rate comes from deltas (D3)
  zombies      [{parent_comm, parent_pid, parent_start, count}]  (D4)
  mcp          {servers: [{name, ppid}], live_sessions}  (D5)
  worktrees    {<repo>: <registered worktree count>}  (D6, beside the GC .last file)
  fseventsd    {pid, start, cpu_s_per_s, footprint_mb}  (D8)
  procs_big    [{pid, start, comm, argv2, phys_mb, lifetime_max_mb, session_pid, session_start, sid,
               cwd}]  uid-501 processes over ~1 GB; argv2 = the first two argv words (D9)
Read from today's rows: ts, el_s (D7), forks_per_s (D2; null = no reading, e.g. forks_alias).
D6 also reads the GC state file (one `<date> <time>  k=v ... rc=N` line, as worktree-gc writes).

RECORD. {ts, det, event: raise|clear|instrument-gap|detector-flapping|abstain, key, value, high, remedy,
sink: desk-page|backlog-chronic, would: page|file|retract|null, mode: record-only}; a D6 raise adds
`would_touch`, the wake file it will touch once live.

FAIL-OPEN, NEVER FAIL-WRONG (the capacity-attrib contract): a torn or non-JSON line is skipped, a
detector that throws skips that tick, and the CLI exits 0 whatever the input. Nothing here forks: it
runs on every 5 s tick of a box that is, by hypothesis, already loaded.

Usage: capacity-detect.py --replay <series.jsonl> [--state <file>] [--out <file>]
Env seams: CC_CAP_DETECT_OUT · CC_CAP_DETECT_NOMINAL_S · CC_CAP_DETECT_WTGC_LAST · CC_CAP_DETECT_WTGC_WAKE
"""

from __future__ import annotations

import argparse
import calendar
import json
import os
import statistics
import sys
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional

HOME = os.path.expanduser("~")
OUT = os.environ.get("CC_CAP_DETECT_OUT", HOME + "/.claude/logs/capacity-detect.jsonl")
WTGC_LAST = os.environ.get(
    "CC_CAP_DETECT_WTGC_LAST", HOME + "/.claude/state/worktree-gc.last"
)
WTGC_WAKE = os.environ.get(
    "CC_CAP_DETECT_WTGC_WAKE", HOME + "/.claude/state/worktree-gc.wake"
)


def _env_float(name: str, default: float) -> float:
    try:
        v = float(os.environ.get(name, ""))
        return v if v > 0 else default
    except ValueError:
        return default


NOMINAL = _env_float("CC_CAP_DETECT_NOMINAL_S", 60.0)
HOUR, SIX_H, DAY = 3600.0, 21600.0, 86400.0
CLEAR_S = 600.0
FLAP_MAX = 6
UNNAMED = "unattributed"
PAGE, CHRONIC = "desk-page", "backlog-chronic"

State = Dict[str, Any]
Row = Dict[str, Any]


@dataclass
class Obs:
    """One key's reading on one tick. over/low are the two lines; neither = the hysteresis band."""

    value: float
    high: float
    over: bool
    low: bool
    remedy: str
    ticks: int = 3
    span_s: float = 0.0


@dataclass
class Tick:
    row: Row
    now: float
    el: float  # seconds this row covers, capped, for raise spans and clear timers
    el_s: Optional[float]
    gap: Optional[float]  # seconds since the previous row this detector set saw


Observed = Optional[
    Dict[str, Obs]
]  # None = input absent (abstain); {} = measured, nothing to report


def _num(v: Any) -> Optional[float]:
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def _lineage(row: Row) -> str:
    fl = row.get("fork_lineage")
    if isinstance(fl, dict) and fl.get("comm"):
        return f"{fl['comm']}:{fl.get('pid')}@{fl.get('start')}"
    return UNNAMED


def d1_gates(t: Tick, ds: State) -> Observed:
    gates = t.row.get("gates")
    if not isinstance(gates, list):
        return None
    by_repo: Dict[str, List[str]] = {}
    for g in gates:
        if isinstance(g, dict) and g.get("repo"):
            by_repo.setdefault(str(g["repo"]), []).append(str(g.get("worktree", "")))
    out: Dict[str, Obs] = {}
    for repo, wts in by_repo.items():
        n = len(wts)
        if n >= 2:
            remedy = f"{n} full gates in {repo}: use gate.sh --affected for pre-gates (X10); one land queue"
            out[f"gates:{repo}:{','.join(sorted(set(wts)))}"] = Obs(
                n, 2, True, False, remedy
            )
    return out


def d2_forks(t: Tick, ds: State) -> Observed:
    v = _num(t.row.get("forks_per_s"))
    if v is None:
        return None
    lin = _lineage(t.row)
    remedy = (
        f"fork storm from {lin}: see its fix row"
        if lin != UNNAMED
        else "fork storm with no lineage: the sampler must emit fork_lineage before this can name a cause"
    )
    return {
        f"forks:{lin}": Obs(v, 2000, v > 2000, v < 1000, remedy, ticks=1, span_s=60)
    }


def d3_vnode(t: Tick, ds: State) -> Observed:
    vn = t.row.get("vnode")
    c = _num(vn.get("num_newvnode_calls")) if isinstance(vn, dict) else None
    if c is None:
        return None
    prev, ds["prev"] = ds.get("prev"), [t.now, c]
    # first sample, or the counter reset (reboot)
    if not prev or t.now <= prev[0] or c < prev[1]:
        return {}
    rate = (c - prev[1]) / (t.now - prev[0])
    # Hourly means, at most 168: a 7 d median that costs a few KB of state instead of a week of samples.
    hours = ds.setdefault("hours", [])
    h = int(t.now // HOUR)
    if hours and hours[-1][0] == h:
        hours[-1][1] += rate
        hours[-1][2] += 1
    else:
        hours.append([h, rate, 1])
    hours[:] = [e for e in hours if e[0] > h - 168]
    means = [e[1] / e[2] for e in hours if e[0] != h]
    if len(means) < 6:
        return {}
    med = statistics.median(means)
    high = max(4 * med, 10000.0)
    lin = _lineage(t.row)
    remedy = f"vnode churn {rate:.0f}/s against a 7 d median of {med:.0f}/s; top sys-CPU lineage {lin}"
    return {
        f"vnode-churn:{lin}": Obs(
            rate, high, rate > high, rate < max(2 * med, 5000.0), remedy, span_s=300
        )
    }


def d4_zombies(t: Tick, ds: State) -> Observed:
    zs = t.row.get("zombies")
    if not isinstance(zs, list):
        return None
    hist: Dict[str, List[List[float]]] = ds.setdefault("hist", {})
    out: Dict[str, Obs] = {}
    for z in zs:
        cnt = _num(z.get("count")) if isinstance(z, dict) else None
        if cnt is None or not isinstance(z, dict):
            continue
        key = f"zombies:{z.get('parent_comm')}:{z.get('parent_pid')}@{z.get('parent_start')}"
        h = hist.setdefault(key, [])
        if not h or t.now - h[-1][0] >= 300:
            h.append([t.now, cnt])
        n_old = sum(1 for p in h if t.now - p[0] >= HOUR)
        del h[
            : max(0, n_old - 1)
        ]  # keep the newest sample at least 1 h old as the slope base
        slope = cnt - h[0][1] if n_old else 0.0
        out[key] = Obs(
            cnt,
            100,
            cnt > 100 and slope > 0,
            cnt <= 100,
            f"{z.get('parent_comm')} holds {cnt:.0f} zombies, rising: kitty #10436 -> X14",
        )
    for key in [k for k in hist if k not in out]:
        del hist[key]
    return out


def d5_mcp(t: Tick, ds: State) -> Observed:
    m = t.row.get("mcp")
    if not isinstance(m, dict) or not isinstance(m.get("servers"), list):
        return None
    live = _num(m.get("live_sessions"))
    if live is None:
        return None
    seen: Dict[str, List[int]] = {}
    for s in m["servers"]:
        if isinstance(s, dict) and s.get("name"):
            e = seen.setdefault(str(s["name"]), [0, 0])
            e[0] += 1
            e[1] += 1 if s.get("ppid") == 1 else 0
    out: Dict[str, Obs] = {}
    for name, (n, orphans) in seen.items():
        over = n > live + 2 or orphans > 0
        out[f"mcp:{name}"] = Obs(
            n,
            live + 2,
            over,
            not over,
            f"{n} {name} servers for {live:.0f} live sessions, {orphans} orphaned: X4 / X19",
        )
    return out


def _read_gc_last(path: str) -> Optional[Dict[str, str]]:
    try:
        mtime = os.stat(path).st_mtime
        with open(path, errors="replace") as fh:
            text = fh.read(8192)
    except OSError:
        return None
    kv = dict(tok.split("=", 1) for tok in text.split() if "=" in tok)
    kv["_mtime"] = repr(mtime)
    return kv


def d6_worktrees(t: Tick, ds: State) -> Observed:
    gc = _read_gc_last(WTGC_LAST)
    wts = t.row.get("worktrees") if isinstance(t.row.get("worktrees"), dict) else None
    if gc is None and wts is None:
        return None
    out: Dict[str, Obs] = {}
    new_ok = False
    if gc is not None and gc.get("rc", "").lstrip("-").isdigit():
        rc = int(gc["rc"])
        out[f"worktrees:{gc.get('repo', 'all')}:gc-failed"] = Obs(
            rc,
            1,
            rc != 0,
            rc == 0,
            f"worktree GC last run rc={rc}: wake the janitor (worktree-gc.wake, §3.4)",
        )
        if rc == 0 and ds.get("ok_mtime") != gc["_mtime"]:
            ds["ok_mtime"], new_ok = gc["_mtime"], True
    if wts is not None:
        base: Dict[str, float] = ds.setdefault("base", {})
        for repo, raw in wts.items():
            n = _num(raw)
            if n is None:
                continue
            if new_ok or repo not in base:
                base[repo] = (
                    n  # growth counts from the last OK GC row, or from first sight
                )
            g = n - base[repo]
            out[f"worktrees:{repo}:growth"] = Obs(
                g,
                20,
                g > 20,
                g <= 20,
                f"{repo} grew {g:.0f} registered worktrees since the last OK GC: wake the janitor",
            )
        for repo in [r for r in base if r not in wts]:
            del base[repo]
    return out


def d7_starved(t: Tick, ds: State) -> Observed:
    v = t.el_s if t.el_s is not None else t.gap
    if v is None:
        return None
    remedy = f"com.claude.capacity-attrib tick took {v:.0f} s against {NOMINAL:.0f} s nominal: the sampler is starved"
    return {
        "job:com.claude.capacity-attrib": Obs(
            v, 3 * NOMINAL, v > 3 * NOMINAL, v < 1.5 * NOMINAL, remedy
        )
    }


def d8_fseventsd(t: Tick, ds: State) -> Observed:
    f = t.row.get("fseventsd")
    if not isinstance(f, dict):
        return None
    cpu, fp = _num(f.get("cpu_s_per_s")) or 0.0, _num(f.get("footprint_mb")) or 0.0
    key = f"fseventsd:{f.get('pid')}@{f.get('start')}"
    remedy = f"fseventsd at {cpu:.2f} core-s/s, {fp:.0f} MB: run the X1 command"
    if fp >= 1024:
        return {key: Obs(fp, 1024, True, False, remedy)}
    return {key: Obs(cpu, 0.8, cpu >= 0.8, cpu < 0.4 and fp < 768, remedy, span_s=900)}


def d9_bigmem(t: Tick, ds: State) -> Observed:
    ps = t.row.get("procs_big")
    if not isinstance(ps, list):
        return None
    out: Dict[str, Obs] = {}
    for p in ps:
        if not isinstance(p, dict):
            continue
        mb = max(_num(p.get("phys_mb")) or 0.0, _num(p.get("lifetime_max_mb")) or 0.0)
        comm, argv2 = str(p.get("comm")), str(p.get("argv2") or p.get("comm"))
        key = f"mem:{comm}:{argv2}:{p.get('session_pid')}@{p.get('session_start')}:{p.get('cwd')}"
        if key in out and out[key].value >= mb:
            continue
        if argv2.split()[:2] == ["git", "grep"]:
            remedy = "git grep with a regex on binary files: use X25's -P (or a pathspec excluding binaries)"
        else:
            remedy = f"{comm} in session {p.get('sid')} reached {mb / 1024:.1f} GB"
        # low stays False while the process is listed: only its absence (the pid gone) clears.
        out[key] = Obs(mb, 4096, mb > 4096, False, remedy, ticks=1)
    return out


@dataclass(frozen=True)
class Det:
    id: str
    fn: Callable[[Tick, State], Observed]
    sink: str
    inp: str
    clear_s: float = CLEAR_S


DETS = (
    Det("D1", d1_gates, PAGE, "gates"),
    Det("D2", d2_forks, PAGE, "forks_per_s"),
    Det("D3", d3_vnode, CHRONIC, "vnode"),
    Det("D4", d4_zombies, CHRONIC, "zombies"),
    Det("D5", d5_mcp, CHRONIC, "mcp"),
    Det("D6", d6_worktrees, CHRONIC, "worktrees+gc-last"),
    Det("D7", d7_starved, CHRONIC, "el_s"),
    Det("D8", d8_fseventsd, PAGE, "fseventsd"),
    Det("D9", d9_bigmem, PAGE, "procs_big", clear_s=0.0),
)


def _iso(now: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))


def _rec(
    now: float,
    d: Det,
    event: str,
    key: str,
    value: Any,
    high: Any,
    remedy: str,
    would: Optional[str],
) -> Dict[str, Any]:
    return {
        "ts": _iso(now),
        "det": d.id,
        "event": event,
        "key": key,
        "value": value,
        "high": high,
        "remedy": remedy,
        "sink": d.sink,
        "would": would,
        "mode": "record-only",
    }


class Detectors:
    """D1-D9 over a row stream. state() is plain JSON, so the daemon can persist it between ticks."""

    def __init__(
        self, state: Optional[State] = None, now: Optional[float] = None
    ) -> None:
        # `now` is accepted for the daemon's call shape; the clock is always step()'s argument.
        self._s: State = state if isinstance(state, dict) else {}
        self._s.setdefault("v", 1)
        self._s.setdefault("det", {})

    def state(self) -> State:
        return self._s

    def step(self, row: Row, now: float) -> List[Dict[str, Any]]:
        prev = self._s.get("prev_now")
        if isinstance(prev, (int, float)) and now <= prev:
            return []  # a duplicate or out-of-order row is not a tick
        gap = now - prev if isinstance(prev, (int, float)) else None
        el_s = _num(row.get("el_s"))
        el_s = el_s if el_s is not None and el_s > 0 else None
        # A long gap is not a long measurement: capping el keeps one stale row from completing a span
        # or a 10 min clear by itself.
        t = Tick(row, now, min(el_s or gap or NOMINAL, 3 * NOMINAL), el_s, gap)
        recs: List[Dict[str, Any]] = []
        for d in DETS:
            ds = self._s["det"].setdefault(d.id, {})
            try:
                obs = d.fn(t, ds.setdefault("x", {}))
            except Exception:  # fail-open per detector: this tick says nothing for it
                continue
            recs.extend(self._judge(d, ds, t, obs))
        self._s["prev_now"] = now
        return recs

    def _judge(self, d: Det, ds: State, t: Tick, obs: Observed) -> List[Dict[str, Any]]:
        now, out = t.now, []
        if obs is None:
            if ds.get("abstain") is None or now - ds["abstain"] >= SIX_H:
                ds["abstain"] = now
                out.append(
                    _rec(
                        now,
                        d,
                        "abstain",
                        f"input:{d.inp}",
                        None,
                        None,
                        f"row lacks {d.inp}: not measured, so neither raised nor cleared",
                        None,
                    )
                )
            return out
        occ: Dict[str, State] = ds.setdefault("occ", {})
        for key in sorted(set(obs) | set(occ)):
            o, s = obs.get(key), occ.get(key)
            if o is not None and o.over:
                s = occ.setdefault(key, {"n": 0, "span": 0.0, "up": False})
                s["n"] += 1
                s["span"] += t.el
                s.pop("low", None)
                s.update(value=o.value, high=o.high, remedy=o.remedy)
                if not s["up"] and s["n"] >= o.ticks and s["span"] >= o.span_s:
                    out.extend(self._raise(d, ds, key, s, now))
            elif s is None:
                continue
            elif not s["up"]:
                del occ[key]  # a streak that never raised leaves no state behind
            elif o is None or o.low:
                s["n"], s["span"] = 0, 0.0
                s.setdefault(
                    "low", now - t.el
                )  # the under-period starts where this row's interval does
                if now - s["low"] >= d.clear_s:
                    out.append(
                        _rec(
                            now,
                            d,
                            "clear",
                            key,
                            s["value"],
                            s["high"],
                            s["remedy"],
                            "retract" if s.get("would") else None,
                        )
                    )
                    del occ[key]
            else:
                s["n"], s["span"] = 0, 0.0
                s.pop("low", None)
        gs = ds.get("gap_since")
        if gs is not None and not ds.get("gap_done") and now - gs >= SIX_H:
            ds["gap_done"] = True
            out.append(
                _rec(
                    now,
                    d,
                    "instrument-gap",
                    f"{d.id}:{UNNAMED}",
                    None,
                    None,
                    f"{d.id} has raised for 6 h with no named cause: the sampler needs a lineage field",
                    "file",
                )
            )
        return out

    def _raise(
        self, d: Det, ds: State, key: str, s: State, now: float
    ) -> List[Dict[str, Any]]:
        out = []
        raises = [r for r in ds.get("raises", []) if now - r < DAY][
            -(FLAP_MAX * 4) :
        ] + [now]
        ds["raises"] = raises
        flap_rec = None
        if len(raises) > FLAP_MAX and (
            ds.get("flap") is None or now - ds["flap"] >= DAY
        ):
            ds["flap"] = now
            flap_rec = _rec(
                now,
                d,
                "detector-flapping",
                f"{d.id}:flapping",
                len(raises),
                FLAP_MAX,
                f"{d.id} raised {len(raises)} times in 24 h: record-only for 24 h",
                "file",
            )
        flapping = ds.get("flap") is not None and now - ds["flap"] < DAY
        unnamed = UNNAMED in key
        if unnamed:
            ds.setdefault("gap_since", now)
        else:
            ds.pop("gap_since", None)
            ds.pop("gap_done", None)
        s["up"] = True
        s["would"] = (
            None if unnamed or flapping else ("page" if d.sink == PAGE else "file")
        )
        r = _rec(now, d, "raise", key, s["value"], s["high"], s["remedy"], s["would"])
        if d.id == "D6":
            r["would_touch"] = WTGC_WAKE
        out.append(r)
        if flap_rec is not None:
            out.append(flap_rec)
        return out


def _parse_ts(v: Any) -> Optional[float]:
    if not isinstance(v, str):
        return None
    try:
        return float(calendar.timegm(time.strptime(v, "%Y-%m-%dT%H:%M:%SZ")))
    except ValueError:
        return None


def replay(series: str, state_path: Optional[str], out_path: str) -> None:
    state: Optional[State] = None
    if state_path:
        try:
            with open(state_path) as fh:
                state = json.load(fh)
        except (OSError, ValueError):
            state = None
    det = Detectors(state)
    recs: List[Dict[str, Any]] = []
    with open(series, errors="replace") as fh:
        for line in fh:
            try:
                row = json.loads(line)
            except ValueError:
                continue  # torn or non-JSON line
            now = _parse_ts(row.get("ts")) if isinstance(row, dict) else None
            if now is not None:
                recs.extend(det.step(row, now))
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "a") as fh:
        fh.writelines(json.dumps(r, sort_keys=True) + "\n" for r in recs)
    if state_path:
        tmp = f"{state_path}.tmp.{os.getpid()}"
        with open(tmp, "w") as fh:
            json.dump(det.state(), fh, separators=(",", ":"))
        os.replace(tmp, state_path)


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(description="record-only capacity detectors D1-D9")
    ap.add_argument("--replay", required=True)
    ap.add_argument("--state")
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args(argv)
    try:
        replay(a.replay, a.state, a.out)
    except Exception:  # fail-open, never fail-wrong
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
