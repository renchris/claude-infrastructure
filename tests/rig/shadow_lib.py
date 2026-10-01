#!/usr/bin/env python3
"""W5b shadow: the observe-mode reconciler's plan for a REAL limit cohort vs what the legacy hook
lane actually did (docs/plans/LIMIT_RECOVER_FLEET_V2.md § W5 "Shadow").

  shadow_lib.py watch   LR [--interval S] [--once]   archive every cohort while it is live
  shadow_lib.py list    LR                           archived cohorts, one line each
  shadow_lib.py compare LR CID [--home H]            the gate lines; rc 0 PASS · 1 FAIL · 3 no data

WHY AN ARCHIVE. In observe mode the daemon keeps records (recon/sessions) and cohorts, but it
REAPS a fact once it expires and OVERWRITES recon/shadow/<cid>.json every pass, so the facts a
placement was judged against are gone by the time the cohort is over. ``watch`` copies them out
(LR/shadow-archive/<cid>/: cohort.json, pages.json, records/<sid>.json, facts.jsonl and plans.jsonl,
the last two each distinct content once, stamped). It only reads the daemon's tree.

THE GATE (plan § Shadow), per cohort:
  1. every planned placement was feasible — a target that is not the source and that no archived
     fact blocked at the planned time (lr_recon.facts.blocking, the daemon's own predicate);
  2. the census missed no limited pane the legacy path found — legacy found = the hook lane's
     requests for this (account, scope, reset) plus its stop-failure markers on the account inside
     the cohort window; a sid the daemon filed in ANOTHER cohort is not a miss;
  3. derive_phase agrees with the legacy engagement truth on every sid legacy recovered — the
     legacy verdict is resolved to the watcher's own truth (a RECOVERED fleet row with no later
     recycle-engaged row is a false-RECOVERED), and a disagreement where the daemon planned a
     different target than legacy used is named "plan differed", not a phase defect.
"""

import calendar
import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "scripts", "limit-recover")
)
from lr_recon import facts as F  # noqa: E402
from lr_recon import types as T  # noqa: E402

SCOPE_OF_TYPE = {"five_hour": "5h", "seven_day": "7d"}


def _load(path: str) -> Any:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _jsonl(path: str) -> List[Dict[str, Any]]:
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if isinstance(r, dict):
                    out.append(r)
    except OSError:
        pass
    return out


def _epoch(v: Any) -> Optional[float]:
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str) and v:
        if v.isdigit():
            return float(v)
        try:
            # every legacy stamp is UTC ("…Z"); timegm reads it as UTC, mktime would read local
            return float(calendar.timegm(time.strptime(v[:19], "%Y-%m-%dT%H:%M:%S")))
        except ValueError:
            return None
    return None


# ── watch ──────────────────────────────────────────────────────────────────────────────────────


def _append_distinct(path: str, body: str, now: float) -> bool:
    h = hashlib.sha1(body.encode()).hexdigest()
    seen = {r.get("sha") for r in _jsonl(path)}
    if h in seen:
        return False
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(
            json.dumps(
                {"at": now, "sha": h, "body": json.loads(body)}, separators=(",", ":")
            )
            + "\n"
        )
    return True


def watch_once(lr: str, now: Optional[float] = None) -> List[str]:
    """One archive pass. Returns the cids seen for the first time."""
    now = time.time() if now is None else now
    root = os.path.join(lr, "recon")
    arch = os.path.join(lr, "shadow-archive")
    new = []
    facts = sorted(glob.glob(os.path.join(root, "facts", "*.json")))
    for cpath in sorted(glob.glob(os.path.join(root, "cohorts", "*.json"))):
        if cpath.endswith(".pages.json"):
            continue  # a cohort's page stamps, archived beside it below; not a cohort
        try:
            coh = _load(cpath)
        except (OSError, ValueError):
            continue
        cid = coh.get("cid") or os.path.basename(cpath)[:-5]
        d = os.path.join(arch, cid)
        if not os.path.isdir(d):
            os.makedirs(os.path.join(d, "records"))
            new.append(cid)
            with open(os.path.join(arch, "index.jsonl"), "a", encoding="utf-8") as fh:
                fh.write(json.dumps({"at": now, "cid": cid}) + "\n")
        shutil.copyfile(cpath, os.path.join(d, "cohort.json"))
        pages = cpath[:-5] + ".pages.json"
        if os.path.exists(pages):
            shutil.copyfile(pages, os.path.join(d, "pages.json"))
        for sid in coh.get("members") or []:
            src = os.path.join(root, "sessions", sid + ".json")
            if os.path.exists(src):
                shutil.copyfile(src, os.path.join(d, "records", sid + ".json"))
        for fp in facts:
            try:
                with open(fp, encoding="utf-8") as fh:
                    _append_distinct(os.path.join(d, "facts.jsonl"), fh.read(), now)
            except (OSError, ValueError):
                pass
        plan = os.path.join(root, "shadow", cid + ".json")
        if os.path.exists(plan):
            try:
                with open(plan, encoding="utf-8") as fh:
                    _append_distinct(os.path.join(d, "plans.jsonl"), fh.read(), now)
            except (OSError, ValueError):
                pass
    return new


def watch(lr: str, interval: float, once: bool, notify: str = "") -> int:
    """Archive every pass; with ``notify``, mail that inbox once per new cohort (the waiting
    session's wake path: it never polls)."""
    while True:
        for cid in watch_once(lr):
            print(
                "%s new cohort archived: %s"
                % (time.strftime("%H:%M:%SZ", time.gmtime()), cid),
                flush=True,
            )
            if notify:
                exe = os.path.join(
                    os.environ.get("HOME", ""), ".claude", "bin", "cc-notify"
                )
                subprocess.run(
                    [
                        exe,
                        notify,
                        "SHADOW: new real limit cohort %s — shadow_lib.py compare "
                        "once it settles" % cid,
                    ],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=20,
                    check=False,
                )
        if once:
            return 0
        time.sleep(interval)


# ── compare ────────────────────────────────────────────────────────────────────────────────────


def _recon_side(
    lr: str, cid: str
) -> Tuple[Dict[str, Any], Dict[str, Dict[str, Any]], List[Dict[str, Any]]]:
    d = os.path.join(lr, "shadow-archive", cid)
    live = os.path.join(lr, "recon")
    try:
        coh = _load(os.path.join(d, "cohort.json"))
    except (OSError, ValueError):
        coh = _load(os.path.join(live, "cohorts", cid + ".json"))
    recs: Dict[str, Dict[str, Any]] = {}
    for sid in coh.get("members") or []:
        for p in (
            os.path.join(live, "sessions", sid + ".json"),
            os.path.join(d, "records", sid + ".json"),
        ):
            try:
                recs[sid] = _load(p)
                break
            except (OSError, ValueError):
                continue
    hist = [r for r in _jsonl(os.path.join(d, "facts.jsonl"))]
    return _window(lr, coh, recs), recs, hist


def _window(
    lr: str, coh: Dict[str, Any], recs: Dict[str, Dict[str, Any]]
) -> Dict[str, Any]:
    """The cohort's reset and opening time, as the daemon means them. The daemon rebuilds the
    record every pass without either (W5b2 defect A: ``resets_at: null, opened_at: 0.0`` on disk),
    so no hook request could match and the stop-marker window reached back to the epoch: every
    earlier limit on the account read as a census miss. The reset is the cid's own suffix
    (census.cohort_id); the opening is the open page's stamp, else the earliest member detection."""
    out = dict(coh)
    cid = str(out.get("cid") or "")
    tail = cid.rsplit("-", 1)[-1]
    if out.get("resets_at") is None and tail.isdigit() and int(tail) > 0:
        out["resets_at"] = float(tail)
        out["window_from"] = "reset from the cid"
    if not out.get("opened_at"):
        pages: Dict[str, Any] = {}
        for p in (
            os.path.join(lr, "recon", "cohorts", cid + ".pages.json"),
            os.path.join(lr, "shadow-archive", cid, "pages.json"),
        ):
            try:
                pages = _load(p)
                break
            except (OSError, ValueError):
                continue
        opened = _epoch(pages.get("open")) if isinstance(pages, dict) else None
        src = "the open page's stamp"
        if opened is None:
            det = [
                _epoch((r.get("timeline") or {}).get("detected")) for r in recs.values()
            ]
            det = [t for t in det if t]
            opened = min(det) if det else None
            src = "the earliest detection"
        if opened is not None:
            out["opened_at"] = opened
            out["window_from"] = ", ".join(
                x for x in (out.get("window_from"), "opened at %s" % src) if x
            )
    return out


def _facts_at(hist: List[Dict[str, Any]], t: float) -> Dict[str, T.Fact]:
    """Each fact key's newest archived content that the daemon had OBSERVED by t (+60 s of pass lag).
    Keyed on the fact's own observed_at, never the archive time: the archiver polls every 20 s, so a
    fact written just before a placement is archived just after it."""
    out: Dict[str, T.Fact] = {}
    for r in sorted(hist, key=lambda x: x.get("at", 0)):
        try:
            f = T.from_dict(T.Fact, r["body"])
        except (KeyError, TypeError, ValueError):
            continue
        if (f.observed_at or r.get("at", 0)) > t + 60:
            continue
        out[f.key] = f
    return out


def _legacy_found(lr: str, home: str, coh: Dict[str, Any]) -> Set[str]:
    acct, scope, resets = coh.get("acct"), coh.get("scope"), coh.get("resets_at")
    found: Set[str] = set()
    pats = [
        os.path.join(lr, "requests", "*.json"),
        os.path.join(lr, "claimed", "*.json"),
        os.path.join(lr, "results", "*.retired.json"),
    ]
    for pat in pats:
        for p in glob.glob(pat):
            try:
                r = _load(p)
            except (OSError, ValueError):
                continue
            if not isinstance(r, dict) or r.get("account") != acct or not r.get("sid"):
                continue
            rs = _epoch(r.get("reset_at_epoch"))
            if (
                SCOPE_OF_TYPE.get(r.get("rate_limit_type", "")) == scope
                and rs is not None
                and resets is not None
                and abs(rs - float(resets)) <= 120
            ):
                found.add(r["sid"])
    lo = float(coh.get("opened_at") or 0) - 1800
    hi = float(coh.get("closed_at") or time.time()) + 600
    for row in _jsonl(
        os.path.join(
            home, ".claude", "autonomy", "stop-failure", "rate_limit__%s.jsonl" % acct
        )
    ):
        ts = _epoch(row.get("ts"))
        if ts is not None and lo <= ts <= hi and row.get("session_id"):
            found.add(row["session_id"])
    return found


def _legacy_outcome(lr: str, sid: str, since: float) -> Optional[Dict[str, Any]]:
    best = None
    for p in glob.glob(os.path.join(lr, "fleet", "*", "results.tsv")):
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                rows = [ln.rstrip("\n").split("\t") for ln in fh]
        except OSError:
            continue
        for t in rows:
            if len(t) < 8 or t[0] != sid:
                continue
            ts = _epoch(t[7])
            if ts is None or ts < since:
                continue
            row = {
                "ts": ts,
                "pane": t[2],
                "acct_before": t[3],
                "acct_after": t[4],
                "verdict": t[5].split("/")[-1],
                "run": os.path.basename(os.path.dirname(p)),
            }
            if best is None or ts > best["ts"]:
                best = row
    return best


# Legacy verdicts that moved nothing (lr-fleet's MECHANISM/VERDICT column, after the "/").
_NOT_MOVED = ("HELD", "NOTMOVED", "NOT_NEEDED")


def _legacy_paneless(lr: str, sid: str, since: float) -> Optional[Dict[str, Any]]:
    """The legacy side's own evidence that a found sid was owed nothing: it ran for the sid, and
    EVERY run it made in the window found no pane (PANE→ "-") and moved nothing. One run that saw a
    pane, or one that moved the session, keeps the sid a miss. Lead ruling 2026-10-01 (W5b2): the
    daemon's verdict may confirm this but never decide it."""
    rows = []
    for p in glob.glob(os.path.join(lr, "fleet", "*", "results.tsv")):
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                ts_rows = [ln.rstrip("\n").split("\t") for ln in fh]
        except OSError:
            continue
        for t in ts_rows:
            if len(t) < 8 or t[0] != sid:
                continue
            ts = _epoch(t[7])
            if ts is None or ts < since:
                continue
            rows.append(
                {
                    "pane": t[1],
                    "verdict": t[5].split("/")[-1],
                    "run": os.path.basename(os.path.dirname(p)),
                }
            )
    if not rows or any(
        r["pane"] != "-" or not r["verdict"].startswith(_NOT_MOVED) for r in rows
    ):
        return None
    return rows[-1]


def _daemon_dead(lr: str, sids: Set[str], lo: float, hi: float) -> Set[str]:
    """The sids the daemon itself judged dead before any claim, inside the cohort window."""
    out: Set[str] = set()
    if not sids:
        return out
    for r in _jsonl(os.path.join(lr, "recon", "events.jsonl")):
        if r.get("sid") not in sids or r.get("ev") != "stale":
            continue
        t = _epoch(r.get("t"))
        if (
            t is not None
            and lo <= t <= hi
            and str(r.get("detail", "")).startswith("NOT_NEEDED dead-before-claim")
        ):
            out.add(r["sid"])
    return out


def _watcher_truth(home: str, sid: str, since: float) -> str:
    rows = [
        r
        for r in _jsonl(os.path.join(home, ".claude", "logs", "handoffs.jsonl"))
        if r.get("prev_sid") == sid and (_epoch(r.get("ts")) or 0) >= since - 5
    ]
    if any(
        r.get("class") == "recycle-engaged" or r.get("engaged") is True for r in rows
    ):
        return "ENGAGED"
    if any(
        str(r.get("class", "")).startswith(("recycle-dead", "recycle-unverified"))
        for r in rows
    ):
        return "DEAD"
    return "NONE"


def _recon_engaged(rec: Dict[str, Any]) -> bool:
    via = (rec.get("close") or {}).get("via")
    seen = (rec.get("close") or {}).get("seen") or []
    return (
        rec.get("phase") == "ENGAGED"
        or via in ("ENGAGED", "MOVED")
        or "ENGAGED" in seen
    )


def compare(lr: str, cid: str, home: str) -> int:
    try:
        coh, recs, hist = _recon_side(lr, cid)
    except (OSError, ValueError):
        print("SHADOW %s: no cohort on record (archive or live)" % cid)
        return 3
    members = list(coh.get("members") or [])
    since = float(coh.get("opened_at") or 0) - 1800
    # 1. feasibility
    placed = feasible = 0
    lines: List[str] = []
    for sid in members:
        r = recs.get(sid) or {}
        tgt, src = r.get("target_acct") or "", r.get("source_acct") or ""
        planned = (r.get("timeline") or {}).get("planned")
        if not tgt:
            lines.append(
                "  %s no placement (%s/%s)"
                % (sid[:8], r.get("phase"), r.get("substate"))
            )
            continue
        placed += 1
        fs = _facts_at(hist, float(planned or 0))
        lane = r.get("lane") or "general"
        block = F.blocking(fs, tgt, lane, "", float(planned or 0))
        ok = tgt != src and block is None
        feasible += 1 if ok else 0
        lines.append(
            "  %s planned %s→%s %s"
            % (
                sid[:8],
                src,
                tgt,
                "feasible"
                if ok
                else "INFEASIBLE (%s)"
                % ("target is source" if tgt == src else "blocked by %s" % block.key),
            )
        )
    # 2. census misses
    found = _legacy_found(lr, home, coh)
    other = {}
    for p in glob.glob(os.path.join(lr, "recon", "sessions", "*.json")):
        try:
            r = _load(p)
        except (OSError, ValueError):
            continue
        other[r.get("sid")] = r.get("cohort_id")
    unfiled = sorted(s for s in found if s not in members and not other.get(s))
    elsewhere = sorted(s for s in found if s not in members and other.get(s))
    # a dead, paneless session legacy merely tried is owed nothing: shown as its own count, never
    # dropped, so a regression that marks a LIVE session dead still surfaces (lead ruling W5b2)
    dead = _daemon_dead(
        lr,
        set(unfiled),
        since,
        float(coh.get("closed_at") or time.time()) + 600,
    )
    not_owed: Dict[str, Dict[str, Any]] = {}
    for s in unfiled:
        ev = _legacy_paneless(lr, s, since)
        if ev is not None and s in dead:
            not_owed[s] = ev
    misses = [s for s in unfiled if s not in not_owed]
    # 3. phase agreement on legacy-recovered sids
    agree = judged = false_rec = differed = 0
    for sid in sorted(found | set(members)):
        lo = _legacy_outcome(lr, sid, since)
        if not lo or lo["verdict"] != "RECOVERED":
            continue
        truth = _watcher_truth(home, sid, lo["ts"])
        legacy_engaged = truth == "ENGAGED"
        if not legacy_engaged:
            false_rec += 1
        r = recs.get(sid)
        if r is None:
            lines.append(
                "  %s legacy RECOVERED→%s (watcher %s) · no recon record"
                % (sid[:8], lo["acct_after"], truth)
            )
            continue
        judged += 1
        mine = _recon_engaged(r)
        if mine == legacy_engaged:
            agree += 1
            tag = "agree"
        elif (r.get("target_acct") or "") not in ("", lo["acct_after"]):
            differed += 1
            tag = "plan differed (recon %s, legacy %s)" % (
                r.get("target_acct"),
                lo["acct_after"],
            )
        else:
            tag = "DISAGREE"
        lines.append(
            "  %s legacy RECOVERED→%s watcher=%s · recon %s/%s via=%s · %s"
            % (
                sid[:8],
                lo["acct_after"],
                truth,
                r.get("phase"),
                r.get("substate"),
                (r.get("close") or {}).get("via"),
                tag,
            )
        )
    passed = feasible == placed and not misses and agree + differed == judged
    print(
        "SHADOW %s: members %d · legacy found %d · census misses %d%s · not owed %d%s · "
        "placements feasible %d/%d · "
        "phase agree %d/%d (false-RECOVERED resolved %d, plan differed %d) → %s"
        % (
            cid,
            len(members),
            len(found),
            len(misses),
            " (%s)" % ",".join(s[:8] for s in misses) if misses else "",
            len(not_owed),
            " (%s)" % ",".join(s[:8] for s in sorted(not_owed)) if not_owed else "",
            feasible,
            placed,
            agree,
            judged,
            false_rec,
            differed,
            "PASS" if passed else "FAIL",
        )
    )
    if coh.get("window_from"):
        print(
            "  window: opened %s, resets %s (%s; the cohort record left it unset)"
            % (
                time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(coh["opened_at"]))
                if coh.get("opened_at")
                else "?",
                time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(coh["resets_at"]))
                if coh.get("resets_at")
                else "?",
                coh["window_from"],
            )
        )
    if elsewhere:
        print(
            "  filed in another cohort (not a miss): %s"
            % ", ".join("%s→%s" % (s[:8], other[s]) for s in elsewhere)
        )
    for s in sorted(not_owed):
        print(
            "  not owed (not a miss): %s — legacy run %s found no pane and moved nothing (%s); "
            "the daemon judged it NOT_NEEDED dead-before-claim"
            % (s[:8], not_owed[s]["run"], not_owed[s]["verdict"])
        )
    print("\n".join(lines))
    out = os.path.join(lr, "shadow-archive", cid)
    if os.path.isdir(out):
        with open(os.path.join(out, "compare.json"), "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "cid": cid,
                    "members": members,
                    "legacy_found": sorted(found),
                    "misses": misses,
                    "not_owed": sorted(not_owed),
                    "placed": placed,
                    "feasible": feasible,
                    "judged": judged,
                    "agree": agree,
                    "false_recovered": false_rec,
                    "plan_differed": differed,
                    "window_from": coh.get("window_from") or "",
                    "pass": passed,
                },
                fh,
            )
    return 0 if passed else 1


def main(argv: List[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd, lr = argv[1], argv[2]
    home = os.environ.get("HOME", os.path.expanduser("~"))
    if "--home" in argv:
        home = argv[argv.index("--home") + 1]
    if cmd == "watch":
        iv = float(argv[argv.index("--interval") + 1]) if "--interval" in argv else 20.0
        nt = argv[argv.index("--notify") + 1] if "--notify" in argv else ""
        return watch(lr, iv, "--once" in argv, nt)
    if cmd == "list":
        for r in _jsonl(os.path.join(lr, "shadow-archive", "index.jsonl")):
            print(
                "%s %s"
                % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(r["at"])), r["cid"])
            )
        return 0
    if cmd == "compare" and len(argv) > 3:
        return compare(lr, argv[3], home)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
