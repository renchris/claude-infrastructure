#!/usr/bin/env python3
"""
measure-harvest-latency.py — did a finding NAMED as remaining in a session's LAST
close ever reach a store a later session reads?

Sibling of scripts/measure-closes.py; it imports that module's corpus walk and
close extractor verbatim rather than re-deriving either (MEMORY.md
control-must-replay-the-real-artifact: one walk, one close definition).

THE QUESTION (exhaustive-drive W2-B4). A close that ends a session while naming
drivable work is the E0 leak the readout table describes: nothing on this box
reads a close for unfinished work. If those findings are in fact picked up later
anyway -- by the next session, by a backlog row, by a commit -- then a
peer-findings drain producer buys nothing. If they are permanently lost, it does.

WHAT IS MEASURED. For every transcript whose mtime falls in the window, the
session's LAST turn-final close; those that NAME drivable work as remaining (the
matcher is --show-matcher, and its precision on a hand-read sample is the fail
direction this instrument is required to report); then, for each, whether 2-3
distinctive tokens lifted from that close appear within N in {1,3,7} days in
  (a) git log --all of the repo named by the transcript's own cwd,
  (b) ~/.claude/autonomy/backlog.jsonl rows,
  (c) ~/.claude/autonomy/decisions/*.json packets.

FAIL DIRECTION, NAMED IN THE OUTPUT. A token that is a common word matches
everything and INFLATES the harvested count. Two defences: tokens are scored by
document frequency ACROSS THE CLOSES THEMSELVES and anything appearing in more
than --df-max of them is dropped as non-distinctive; and --sample prints n
matched pairs for a hand read, which is the only way the precision number gets
into the report.

    python3 scripts/measure-harvest-latency.py --days 14
    python3 scripts/measure-harvest-latency.py --selftest
"""
import argparse
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))


def load_mc():
    spec = importlib.util.spec_from_file_location(
        "measure_closes", os.path.join(HERE, "measure-closes.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


# ── the matcher ──────────────────────────────────────────────────────────────
# A close NAMES DRIVABLE WORK if, outside fenced blocks, it carries a 🔧/📦 rung
# or one of these phrases. Deliberately WIDER than completion-assert's CA_HANDOFF
# (which is about work that is the OPERATOR'S): B4 is about work that is ANYONE'S
# and was named rather than done.
NAMES_WORK = re.compile(
    r"🔧|📦|follow[- ]?on|follow[- ]?up|backlog|still (needs|open|to)|"
    r"remain(s|ing)?|not (yet )?done|left (to|for)|next step|deferred|"
    r"parked|unfinished|filed (it|as|a)|TODO|worth (doing|building|fixing)",
    re.I)

# Tokens distinctive enough to search for.
TOKEN_PATS = [
    re.compile(r"`([A-Za-z0-9_./-]{6,60})`"),                 # backticked span
    re.compile(r"\b([A-Za-z0-9_-]+\.(?:sh|py|md|ts|tsx|js|json|bats|yml))\b"),
    re.compile(r"\b([a-z][a-z0-9]*(?:[-_][a-z0-9]+){2,})\b"),  # kebab/snake, 3+ parts
    re.compile(r"\b([0-9a-f]{12})\b"),                         # backlog/packet id
]
STOP = {"claude-infrastructure", "session-continue.sh", "settings.local.json",
        "origin/main", "settings.json", "package.json"}


def tokens_of(text):
    out = []
    for pat in TOKEN_PATS:
        for m in pat.finditer(text):
            t = m.group(1).strip("./`")
            if len(t) >= 6 and t.lower() not in STOP:
                out.append(t)
    seen, uniq = set(), []
    for t in out:
        k = t.lower()
        if k not in seen:
            seen.add(k)
            uniq.append(t)
    return uniq


def repo_toplevel(cwd):
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True, timeout=20)
        return r.stdout.strip() or None
    except Exception:
        return None


def git_corpus(top, since_epoch):
    """[(commit_epoch, haystack)] for every commit on any ref since since_epoch."""
    try:
        r = subprocess.run(
            ["git", "-C", top, "log", "--all", "--no-merges",
             "--since=@%d" % int(since_epoch), "--format=%ct%x1f%s%x1f%b%x1e"],
            capture_output=True, text=True, timeout=180)
    except Exception:
        return []
    out = []
    for rec in r.stdout.split("\x1e"):
        rec = rec.strip("\n")
        if not rec:
            continue
        parts = rec.split("\x1f")
        if len(parts) < 3:
            continue
        try:
            out.append((int(parts[0]), (parts[1] + "\n" + parts[2]).lower()))
        except ValueError:
            continue
    return out


def store_corpus(since_epoch):
    """[(epoch, haystack)] from backlog.jsonl rows and decision packets."""
    out = []
    bl = os.path.expanduser("~/.claude/autonomy/backlog.jsonl")
    if os.path.exists(bl):
        for line in open(bl, errors="replace"):
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue          # a torn/oversized record is COUNTED, never fatal
            ts = r.get("ts") or r.get("created") or ""
            e = iso_epoch(ts)
            if e and e >= since_epoch:
                out.append((e, json.dumps(r).lower()))
    for p in glob.glob(os.path.expanduser("~/.claude/autonomy/decisions/*.json")):
        try:
            r = json.load(open(p, errors="replace"))
        except Exception:
            continue
        e = iso_epoch(r.get("opened") or r.get("ts") or "") or os.path.getmtime(p)
        if e >= since_epoch:
            out.append((e, json.dumps(r).lower()))
    return out


def iso_epoch(s):
    if not s:
        return 0
    s = str(s).replace("Z", "+00:00")
    try:
        import datetime
        return datetime.datetime.fromisoformat(s).timestamp()
    except Exception:
        return 0


def first_hit(toks, corpus, t0, horizon_days):
    """Earliest (days, haystack) within the horizon, else None."""
    best = None
    lim = t0 + horizon_days * 86400
    for e, hay in corpus:
        if e <= t0 or e > lim:
            continue
        for t in toks:
            if t.lower() in hay:
                d = (e - t0) / 86400.0
                if best is None or d < best[0]:
                    best = (d, hay[:200], t)
    return best


def cwd_of(path):
    n = 0
    for line in open(path, errors="replace"):
        n += 1
        if n > 60:
            break
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("cwd"):
            return r["cwd"]
    return None


def run(days, df_max, sample, horizons):
    mc = load_mc()
    files, _ = mc.iter_transcripts(days)
    last_closes = []
    for path, root in files:
        try:
            cs = list(mc.extract_closes(path, root))
        except Exception:
            continue
        if not cs:
            continue
        last_closes.append((path, root, cs[-1]))
    print("\nsessions with >=1 turn-final close: %d of %d transcripts" %
          (len(last_closes), len(files)))

    named = [(p, r, c) for (p, r, c) in last_closes if NAMES_WORK.search(c["text"])]
    print("LAST closes NAMING drivable work: %d (%.1f%% of closing sessions)" %
          (len(named), 100.0 * len(named) / max(1, len(last_closes))))

    df = Counter()
    tokmap = {}
    for p, r, c in named:
        ts = tokens_of(c["text"])
        tokmap[p] = ts
        for t in set(x.lower() for x in ts):
            df[t] += 1
    n = max(1, len(named))
    cutoff = df_max * n

    gitcache, storecorp = {}, None
    rows, no_tokens = [], 0
    for p, r, c in named:
        toks = [t for t in tokmap[p] if df[t.lower()] <= cutoff][:3]
        if not toks:
            no_tokens += 1
            continue
        t0 = iso_epoch(c.get("ts")) or c["mtime"]
        if storecorp is None:
            storecorp = store_corpus(t0 - 86400)
        cwd = cwd_of(p)
        top = repo_toplevel(cwd) if cwd and os.path.isdir(cwd) else None
        if top and top not in gitcache:
            gitcache[top] = git_corpus(top, time.time() - (days + 8) * 86400)
        corpus = (gitcache.get(top) or []) + storecorp
        hit = first_hit(toks, corpus, t0, max(horizons))
        rows.append({"file": p, "t0": t0, "toks": toks, "top": top,
                     "hit_days": hit[0] if hit else None,
                     "hit_hay": hit[1] if hit else "",
                     "hit_tok": hit[2] if hit else ""})

    tot = len(rows)
    print("closes with >=1 distinctive token (the measured population): %d "
          "(dropped %d with none after the df filter)" % (tot, no_tokens))
    if not tot:
        return
    for N in horizons:
        h = sum(1 for r in rows if r["hit_days"] is not None and r["hit_days"] <= N)
        print("  harvested within %d day(s): %4d / %4d = %5.1f%%" %
              (N, h, tot, 100.0 * h / tot))
    lost = [r for r in rows if r["hit_days"] is None]
    print("  PERMANENT LOSS (never appeared within %d days): %d / %d = %.1f%%" %
          (max(horizons), len(lost), tot, 100.0 * len(lost) / tot))
    lat = sorted(r["hit_days"] for r in rows if r["hit_days"] is not None)
    if lat:
        print("  median harvest latency: %.2f days (n=%d)" %
              (lat[len(lat) // 2], len(lat)))
    if lat:
        bands = [(0, 0.02), (0.02, 0.5), (0.5, 2), (2, 7)]
        print("  latency bands (a hit inside ~0.5 d is the SAME session's own trailing"
              " commit or a concurrent sibling, not a later reader):")
        for lo, hi in bands:
            k = sum(1 for d in lat if lo <= d < hi)
            print("    %5.2f-%-5.2f d : %4d hits (%4.1f%% of the population)" %
                  (lo, hi, k, 100.0 * k / tot))
        late = sum(1 for d in lat if d >= 0.5)
        print("  harvested by a LATER reader (>=0.5 d): %d / %d = %.1f%%"
              % (late, tot, 100.0 * late / tot))
    if sample:
        print("\n--- HAND-READ SAMPLE (%d matched pairs; judge each hit real or spurious) ---"
              % sample)
        shown = 0
        for r in rows:
            if r["hit_days"] is None or shown >= sample:
                continue
            shown += 1
            print("\n[%d] %s" % (shown, os.path.basename(r["file"])))
            print("    tokens : %s   MATCHED ON: %s  at %.2fd" %
                  (r["toks"], r["hit_tok"], r["hit_days"]))
            print("    hit    : %s" % r["hit_hay"][:180].replace("\n", " "))


def selftest():
    """Positive control on the arithmetic AND on the failure direction."""
    ok = True
    toks = ["engage-rc-consequence"]
    t0 = 1_000_000.0
    corpus = [(t0 + 2 * 86400, "fix(handoff): engage-rc-consequence opens the row")]
    hit = first_hit(toks, corpus, t0, 7)
    if not hit or abs(hit[0] - 2.0) > 1e-6:
        print("FAIL: a hit 2 days out was not found at 2.0 days"); ok = False
    if first_hit(toks, corpus, t0, 1) is not None:
        print("FAIL: a hit at 2 days leaked into the 1-day horizon"); ok = False
    if first_hit(["never-mentioned-anywhere"], corpus, t0, 7) is not None:
        print("FAIL: a token absent from the corpus reported a hit"); ok = False
    if first_hit(toks, [(t0 - 86400, "engage-rc-consequence")], t0, 7) is not None:
        print("FAIL: a commit BEFORE the close counted as harvesting it"); ok = False
    if not NAMES_WORK.search("🔧 Loose ends — continuing."):
        print("FAIL: matcher missed a 🔧 rung"); ok = False
    if NAMES_WORK.search("✅ Complete & live on trunk — safe to close."):
        print("FAIL: matcher fired on a clean ✅ close"); ok = False
    got = tokens_of("the fix is in `hooks/lib/dod-path.sh` and row 1031594b6327")
    if "hooks/lib/dod-path.sh" not in got or "1031594b6327" not in got:
        print("FAIL: token extraction missed a path or an id: %s" % got); ok = False
    print("SELFTEST: %s" % ("green — 7/7" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--df-max", type=float, default=0.05,
                    help="drop a token appearing in more than this FRACTION of closes")
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    run(a.days, a.df_max, a.sample, [1, 3, 7])
