#!/usr/bin/env python3
"""auth-error-rate.py — the HARNESS-side companion to auth-timeseries.sh.

auth-timeseries.sh samples the credential store (did the token rotate? go empty?).
This reads the other end of the same failure: what the OPERATOR was actually shown.
Every forced re-auth prompt is recorded in the transcript as a record with
`isApiErrorMessage: true`, so the rate is measurable retrospectively over the whole
corpus — no watcher needs to have been armed at the time. That is what let the
2026-08-01 regression be adjudicated five days after it ended.

READ-ONLY. Reads transcripts only; touches no credential, no keychain, no config.

WHY THE CLASS SPLIT IS THE POINT. Two different failures both end in "Please run
/login", and pooling them is what made the regression look unresolved for five days:

  A  "401 OAuth access token has expired"  — the 8h access token ran out because the
     in-session REFRESH could not run. The credential is intact; the refresh path is
     broken. This is the signature of the dangling-lock defect (fix 1677218f).
  B  "Not logged in" / "Login expired"     — the stored credential is EMPTY or the
     grant is dead server-side. No refresh can help; only an interactive login does.
  C  any other isApiErrorMessage carrying "/login" — kept separate so a NEW spelling
     surfaces as C rather than being silently absorbed into A or B.

A and B have different causes, different fixes and different time profiles. Class A
stopped dead on 2026-08-02; class B did not. Pooled, that cure is invisible.

NOTE ON WHO AUTHORS THE TEXT — this decides what an absence proves. `Please run
/login` and `API Error` are literals in the client binary; `access token has expired`
and `Re-authenticate to continue` are NOT (checked with `strings` against
2.1.220). So the class-A body is SERVER-supplied and could be reworded upstream at
any time, but its client-side frame cannot. An absence of class A is therefore only
meaningful alongside the check that no OTHER spelling pairs the two client literals —
which is why --list prints every isApiErrorMessage, not just the ones that classify.

METHOD NOTES, each one a trap this instrument is built to avoid:
  * dedupe by UUID — the same record is reachable more than once.
  * dedupe files by REALPATH — ~/.claude-next/projects is a SYMLINK to
    ~/.claude/projects (same inode). Walking both double-counts every event.
  * the denominator is DISTINCT SESSIONS, not records; a session is attributed to the
    day of its FIRST record. --active-denominator switches to sessions-active-on-day,
    which is the basis the 2026-08-02 published table used — keep it available, because
    reproducing that table is this instrument's positive control.
  * boundary compares are on parsed datetimes, never on ISO strings: transcript stamps
    carry milliseconds ("…:55.138Z") and a bare "…:55Z" bound sorts AFTER them, so a
    string compare silently puts the onset event on the wrong side of its own boundary.

Usage:
  auth-error-rate.py                              # daily table, 2026-07-25 →
  auth-error-rate.py --active-denominator         # reproduce the 2026-08-02 table
  auth-error-rate.py --window ONSET FIX           # rate before / during / after
  auth-error-rate.py --list --since 2026-08-01    # one line per error, with account
  auth-error-rate.py --all-errors --since 2026-08-02  # EVERY api error, unclassified
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import glob
import json
import os
import re
import sys

# config dir -> the account whose grant that dir uses.
PROJECT_DIRS = {
    "~/.claude/projects": "next",
    "~/.claude-secondary/projects": "next2",
    "~/.claude-tertiary/projects": "next3",
    "~/.claude-quaternary/projects": "next4",
}

CLASS_A = "A:refresh-failed"
CLASS_B = "B:credential-gone"
CLASS_C = "C:other-login"


def classify(text: str) -> str | None:
    t = text.lower()
    if "oauth access token has expired" in t:
        return CLASS_A
    if "not logged in" in t or "login expired" in t:
        return CLASS_B
    if "please run /login" in t:
        return CLASS_C
    return None


def parse_ts(s: str) -> dt.datetime | None:
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def scan(keep_unclassified: bool = False) -> tuple[dict, dict]:
    """-> (errors keyed by uuid, sessions keyed by sessionId). Both uuid-deduped."""
    errors: dict[str, dict] = {}
    sessions: dict[str, dict] = {}
    seen_files: set[str] = set()

    for pattern, account in PROJECT_DIRS.items():
        root = os.path.expanduser(pattern)
        for path in glob.glob(root + "/*/*.jsonl"):
            real = os.path.realpath(path)
            if real in seen_files:
                continue
            seen_files.add(real)
            try:
                fh = open(path, "r", errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    if '"timestamp"' not in line:
                        continue
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    ts_raw, sid = rec.get("timestamp"), rec.get("sessionId")
                    if not ts_raw or not sid:
                        continue
                    ts = parse_ts(ts_raw)
                    if ts is None:
                        continue
                    s = sessions.get(sid)
                    if s is None or ts < s["start"]:
                        sessions[sid] = {
                            "start": ts,
                            "account": account,
                            "days": s["days"] if s else set(),
                        }
                    sessions[sid]["days"].add(ts_raw[:10])

                    if rec.get("isApiErrorMessage") is not True:
                        continue
                    content = rec.get("message", {}).get("content")
                    text = content if isinstance(content, str) else json.dumps(content)
                    kind = classify(text)
                    if kind is None and not keep_unclassified:
                        continue
                    errors[rec.get("uuid")] = {
                        "ts": ts,
                        "day": ts_raw[:10],
                        "account": account,
                        "cls": kind or "-:other-api-error",
                        "version": rec.get("version"),
                        "session": sid,
                        "text": text,
                    }
    return errors, sessions


def daily_table(errors, sessions, since, active_denom):
    by_day = collections.defaultdict(collections.Counter)
    for e in errors.values():
        by_day[e["day"]][e["cls"]] += 1
    if active_denom:
        denom = collections.Counter()
        for s in sessions.values():
            for d in s["days"]:
                denom[d] += 1
    else:
        denom = collections.Counter(
            s["start"].strftime("%Y-%m-%d") for s in sessions.values()
        )

    days = sorted(d for d in set(list(denom) + list(by_day)) if d >= since)
    label = "sess(active)" if active_denom else "sess(start)"
    print(f"{'day':12} {label:>12} {'A':>4} {'B':>4} {'C':>4} {'A/sess':>8}")
    for d in days:
        n = denom.get(d, 0)
        a = by_day[d][CLASS_A]
        print(
            f"{d:12} {n:12} {a:4} {by_day[d][CLASS_B]:4} "
            f"{by_day[d][CLASS_C]:4} {(a / n if n else 0):8.3f}"
        )


def window_report(errors, sessions, lo_s, hi_s):
    lo, hi = parse_ts(lo_s), parse_ts(hi_s)
    if lo is None or hi is None:
        sys.exit("--window needs two ISO-8601 instants, e.g. 2026-08-01T00:46:55Z")

    def bucket(t):
        return "before" if t < lo else ("during" if t <= hi else "after")

    counts = {k: [0, 0] for k in ("before", "during", "after")}  # [class-A, sessions]
    for e in errors.values():
        if e["cls"] == CLASS_A:
            counts[bucket(e["ts"])][0] += 1
    for s in sessions.values():
        counts[bucket(s["start"])][1] += 1

    print(f"class-A ('401 OAuth access token has expired') around [{lo_s} .. {hi_s}]\n")
    print(f"{'period':10} {'class-A':>8} {'sessions':>9} {'per session':>12}")
    for name in ("before", "during", "after"):
        a, n = counts[name]
        print(f"{name:10} {a:8} {n:9} {(a / n if n else 0):12.4f}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--since", default="2026-07-25", help="first day shown (YYYY-MM-DD)"
    )
    ap.add_argument(
        "--window",
        nargs=2,
        metavar=("LO", "HI"),
        help="before/during/after class-A rates for a window",
    )
    ap.add_argument(
        "--list", action="store_true", help="one line per error, not a table"
    )
    ap.add_argument(
        "--all-errors",
        action="store_true",
        help="include isApiErrorMessage records that match NO auth class — the check "
        "that makes an absence of class A meaningful rather than a blind spot",
    )
    ap.add_argument(
        "--active-denominator",
        action="store_true",
        help="count a session on every day it was active (the 2026-08-02 published "
        "table's basis) instead of only on its start day",
    )
    args = ap.parse_args()

    errors, sessions = scan(keep_unclassified=args.all_errors)

    if args.window:
        window_report(errors, sessions, *args.window)
    elif args.list or args.all_errors:
        rows = sorted(
            (e for e in errors.values() if e["day"] >= args.since),
            key=lambda e: e["ts"],
        )
        print(f"{'timestamp':26} {'acct':6} {'class':18} {'ver':9} text")
        for e in rows:
            stamp = e["ts"].strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
            body = re.sub(r"\s+", " ", e["text"])[:88]
            print(
                f"{stamp:26} {e['account']:6} {e['cls']:18} {str(e['version']):9} {body}"
            )
    else:
        daily_table(errors, sessions, args.since, args.active_denominator)

    print(
        f"\n{len(errors)} error records (uuid-deduped) over {len(sessions)} sessions."
    )


if __name__ == "__main__":
    main()
