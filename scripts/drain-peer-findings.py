#!/usr/bin/env python3
"""
drain-peer-findings.py — file the drivable work a DEAD session's LAST close
NAMED into the one store a later session already picks work out of.

WHY THIS EXISTS (exhaustive-drive W2-B4 -> W3-B4). Measured over 14 days and
839 transcripts: of the closes that end a session while naming drivable work,
only 14.5 % reach any later reader, and 64.5 % reach nothing at all within 7
days (docs/research/exhaustive-drive-2026-09-08/W2-B4-harvest-latency.md, and
the corrected instrument scripts/measure-harvest-latency.py beside this file).
Nothing on this box reads a close for unfinished work: dispatch-assert.sh has
the matcher but only NAGS, and its live rate is 1 fire in 177 evaluations.
This is the write that was missing.

THE VENUE IS NOT A NEW SURFACE. Rows go into ~/.claude/autonomy/backlog.jsonl
through bin/cc-backlog add -- the only one of the four drained stores that is a
ranked worklist a later session picks from (scripts/drain-pick.sh,
bin/cc-dispatch, bin/cc-eligible). We never hand-write the JSONL: the store
carries an id scheme, a dedup brake, a done-latch and a 4,000-byte record guard,
and bypassing cc-backlog would re-create every bug those exist to prevent.

THREE DESIGN DECISIONS, EACH FORCED BY A MEASURED CONSTRAINT.

 1. HARVEST EVIDENCE MAY NOT GATE THE FILING. The harvest matcher's hand-read
    precision is 80 % post-fix (35 % pre-fix) and EVERY error is a false
    POSITIVE harvest. A producer that skipped a finding because it "looks
    harvested" would therefore skip real losses at exactly the rate the
    instrument is wrong. So this producer never runs harvest detection as a
    suppression gate. Harvest evidence goes into the row's --falsifier, which
    can only RETRACT a row that a probe confirms -- the fail-safe direction.

 2. THE CHOKEPOINT IS OUT-OF-SESSION, NOT A Stop HOOK. A Stop hook fires on
    every turn and cannot know which close is the LAST one, so it would file a
    row for work the next turn does. And it cannot see the adverse population at
    all: 302 of 820 transcripts had NO turn-final close because the session died
    mid-turn (boundary-handoff.sh's own header admits it never runs for those).
    This walks transcripts that have gone quiet instead.

 3. THE ROW IS AGENT WORK, NEVER AN OPERATOR ASK. source=peer-drain, no
    --why-not-now, so it lands in the agent worklist and never in the operator's
    counted pile or the 👤 rung. The measurement priced the CHANNEL, not the
    cargo: we have no measurement of what a drained finding is worth, so the
    row must cost a grep line rather than an operator decision.

    python3 scripts/drain-peer-findings.py --days 3            # dry run
    python3 scripts/drain-peer-findings.py --days 3 --commit
"""
import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def _load(name, fname):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fname))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


# ONE close definition and ONE matcher for the measurement and the producer.
# If they drifted, the producer would drain a population the number is not about.
MHL = _load("measure_harvest_latency", "measure-harvest-latency.py")
MC = MHL.load_mc()
NAMES_WORK = MHL.NAMES_WORK
tokens_of = MHL.tokens_of

TITLE_MAX = 420
MIN_CLAUSE = 40          # a clause shorter than this names nothing actionable

# A sentence can carry a naming tell and ASSERT CLOSURE with it -- "both backlog
# rows closed", "0 unpushed, follow-on: none". Draining those files a row saying
# there is nothing to file. A 🔧 rung overrides: that rung IS an open loose end.
_SETTLED = re.compile(
    r"\b(rows? closed|all closed|already (closed|filed|landed)|"
    r"0 unpushed|nothing (of mine )?is open|no loose ends|"
    r"content[- ]verified|safe to close)\b", re.I)
# Ranked first: a clause that states an OPEN thing, not one that merely mentions
# the machinery of filing.
_OPEN_TELL = re.compile(r"🔧|\bstill\b|\bremain(s|ing)?\b|unlanded|unfinished|"
                        r"not (yet )?done|left (to|for)|next step|parked", re.I)
_HEXID = re.compile(r"^[0-9a-f]{12}$")

# Sentences that carry the naming tell, most informative first.
_FOLLOW_ON = re.compile(r"follow[- ]?on\s*:\s*(.+)", re.I)
# A sentence whose ONLY naming tell is an EMPTY follow-on ledger names no work.
# Without this the fallback scan re-matches the very sentence that said "none",
# and every clean close drains a row saying it has nothing to drain.
_NIL = r"(none|n/?a|nothing|no|-)(\s+(filed|outstanding|remaining|left|open))?"
_EMPTY_LEDGER = re.compile(r"follow[- ]?on\s*:\s*" + _NIL + r"\s*[.;]?\s*$", re.I)
# A ledger can OPEN with "none" and then run on for a paragraph — "follow-on:
# none, everything landed and content-verified this turn." Anchoring the nil
# test to end-of-string made it unreachable behind MIN_CLAUSE (a nil phrase is
# at most ~20 chars, so the length check was silently doing its job and the
# guard was dead code). Anchor it to the LEAD instead, where it has work only
# it can do. Found by the red-proof: the mutant with this guard removed stayed
# green, which is the definition of an equivalence guard rather than a test.
_NIL_LEAD = re.compile(r"^" + _NIL + r"\s*($|[.;,:—–-])", re.I)
_SENT = re.compile(r"(?<=[.;!?])\s+|\n+")


def sentences(text):
    out = []
    for raw in _SENT.split(text or ""):
        s = " ".join(raw.split())
        if s:
            out.append(s)
    return out


def finding_of(text):
    """The plain-English clause the close used to name the remaining work.

    Prefers S2's `follow-on:` ledger, then the first sentence carrying a naming
    tell. Bounded, because a row is a pointer -- the whole close stays on disk
    and the row names the file that holds it."""
    m = _FOLLOW_ON.search(text or "")
    if m:
        cand = " ".join(m.group(1).split())
        # A ledger reading "none", "none filed", "nothing left" names no work,
        # and one too short to be actionable ("the three filed items above")
        # names work only by pointing at prose this row cannot carry.
        if cand and not _NIL_LEAD.match(cand) and len(cand) >= MIN_CLAUSE:
            return cand[:TITLE_MAX]
    # Otherwise the clause must STATE something open. Dropping the plain
    # "carries a naming tell" fallback is deliberate: a close that says
    # "everything of mine is finished and live" mentions the machinery of
    # filing without naming a finding, and draining it files a row about
    # nothing. The count of these drops is printed, so the loss is visible
    # rather than silent.
    for s in sentences(text):
        if (len(s) >= MIN_CLAUSE and _OPEN_TELL.search(s)
                and not _EMPTY_LEDGER.search(s)
                and not (_SETTLED.search(s) and "🔧" not in s)):
            return s[:TITLE_MAX]
    return ""


def last_assistant_text(path):
    """The final main-chain assistant text, close or not. This is the ONLY way
    to reach a session that died mid-turn, and it is why this arm exists."""
    last = ""
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("type") != "assistant" or r.get("isSidechain") is True:
            continue
        t, _ = MC.assistant_text(r)
        if t and t.strip():
            last = t
    return last


def cwd_of(path):
    return MHL.cwd_of(path)


def ledger_ids(ledger=None):
    """Every 12-hex row id the destination ledger already holds."""
    p = ledger or os.environ.get("CC_BACKLOG_FILE") or os.path.expanduser(
        "~/.claude/autonomy/backlog.jsonl")
    ids = set()
    if not os.path.exists(p):
        return ids
    for line in open(p, errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue          # a torn record is skipped, never fatal
        i = r.get("id")
        if isinstance(i, str) and _HEXID.match(i):
            ids.add(i)
    return ids


def already_in_venue(finding, ids):
    """True only when EVERY id the clause names is already a row in the
    destination ledger.

    This is an EXACT key lookup in the store we are writing to -- not the
    harvest matcher, whose 80 % precision is why harvest evidence may never gate
    a filing. A close whose whole follow-on ledger is a list of ids that already
    exist has, verifiably, already reached this venue."""
    found = re.findall(r"\b([0-9a-f]{12})\b", finding or "")
    if not found:
        return False
    if not all(i in ids for i in found):
        return False
    # ...and the clause must be little more than that list, or we would drop a
    # real finding that merely cites a row in passing.
    residue = re.sub(r"\b[0-9a-f]{12}\b", "", finding)
    residue = re.sub(r"[^A-Za-z]+", "", residue)
    return len(residue) <= 60


def project_of(top):
    return os.path.basename(top) if top else "claude-infrastructure"


def live_sessions():
    """Session ids the registry currently believes are live. A miss is not
    absence (memory: lookup-miss-is-not-absence), so this can only ever SUPPRESS
    a drain, never cause one -- and the settle window is the real guard."""
    out = set()
    d = os.path.expanduser("~/.claude/cc-registry")
    if not os.path.isdir(d):
        return out
    for f in os.listdir(d):
        if not f.endswith(".json"):
            continue
        try:
            r = json.load(open(os.path.join(d, f), errors="replace"))
        except Exception:
            continue
        for k in ("sessionId", "session_id", "sid", "session"):
            v = r.get(k)
            if isinstance(v, str) and len(v) >= 8:
                out.add(v)
    return out


def build_rows(days, settle_hours, include_no_close, max_rows, verbose=True):
    files, _ = MC.iter_transcripts(days, verbose=verbose)
    quiet_before = time.time() - settle_hours * 3600
    live = live_sessions()
    known = ledger_ids()
    rows, stats = [], {"scanned": 0, "still_warm": 0, "registry_live": 0,
                       "no_text": 0, "no_tell": 0, "no_finding": 0,
                       "already_in_venue": 0,
                       "from_close": 0, "from_no_close": 0, "no_close_skipped": 0}
    for path, _root in sorted(files, key=lambda x: -os.path.getmtime(x[0])):
        stats["scanned"] += 1
        if os.path.getmtime(path) > quiet_before:
            stats["still_warm"] += 1
            continue
        sid = os.path.basename(path)[:-6]
        if sid in live:
            stats["registry_live"] += 1
            continue
        try:
            closes = list(MC.extract_closes(path, _root))
        except Exception:
            closes = []
        if closes:
            text, origin = closes[-1]["text"], "close"
        else:
            if not include_no_close:
                stats["no_close_skipped"] += 1
                continue
            text, origin = last_assistant_text(path), "no-close"
        if not text.strip():
            stats["no_text"] += 1
            continue
        if not NAMES_WORK.search(text):
            stats["no_tell"] += 1
            continue
        finding = finding_of(text)
        if not finding:
            stats["no_finding"] += 1
            continue
        if already_in_venue(finding, known):
            stats["already_in_venue"] += 1
            continue
        cwd = cwd_of(path)
        top = MHL.repo_toplevel(cwd) if cwd and os.path.isdir(cwd) else None
        toks = tokens_of(text)[:3]
        stats["from_close" if origin == "close" else "from_no_close"] += 1
        rows.append({
            "sid": sid, "path": path, "origin": origin, "project": project_of(top),
            "top": top, "toks": toks, "finding": finding,
            "title": title_of(finding, sid, path, origin),
            "falsifier": falsifier_of(top, toks),
        })
        if max_rows and len(rows) >= max_rows:
            break
    return rows, stats


def title_of(finding, sid, path, origin):
    """The row IS a pointer: the clause, then the file that holds the whole
    close. A close this row drops is dropped into a named store, not deleted."""
    tail = " [peer-drain from %s close of session %s; full text: %s]" % (
        "the last" if origin == "close" else "the last assistant turn of the no-close",
        sid[:8], path)
    return (finding + tail)[:900]


def falsifier_of(top, toks):
    """Harvest evidence, in the one place where being WRONG leaves the row open.

    `cc-backlog falsify` RUNS this and refuses to retract on exit 0, so a
    false-positive harvest here cannot silently delete a real loss -- which is
    exactly what putting the same evidence in the filing gate would do."""
    if not top or not toks:
        return ""
    # Tokens are [A-Za-z0-9_./-] by construction, so `.` is the only character
    # that is special to grep -E and none can carry a shell quote.
    pat = "|".join(t.replace(".", "[.]") for t in toks)
    return ("git -C %s log --all --no-merges --since=7.days.ago -E --grep='%s' "
            "--format=%%h | grep -q ." % (top, pat))


def file_row(cb, row, project_override=None):
    cmd = [cb, "add",
           "--title", row["title"],
           "--project", project_override or row["project"],
           "--source", "peer-drain"]
    if row["falsifier"]:
        cmd += ["--falsifier", row["falsifier"]]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=3)
    ap.add_argument("--settle-hours", type=float, default=6.0,
                    help="a transcript touched more recently than this may still "
                         "be a live session about to drive its own finding")
    ap.add_argument("--include-no-close", action="store_true",
                    help="also drain the last assistant turn of sessions that "
                         "died mid-turn (the 302/820 adverse population). OFF by "
                         "default: the matcher's precision is measured on CLOSES, "
                         "not on mid-turn narration")
    ap.add_argument("--max", type=int, default=25,
                    help="rows per run, so one pass can never flood the ledger")
    ap.add_argument("--project", default=None,
                    help="override the per-transcript project label")
    ap.add_argument("--commit", action="store_true",
                    help="actually file; without it this is a dry run")
    ap.add_argument("--cc-backlog", default=os.path.join(REPO, "bin", "cc-backlog"))
    a = ap.parse_args()

    rows, stats = build_rows(a.days, a.settle_hours, a.include_no_close, a.max)
    print("\nscanned %d transcript(s) in the window" % stats["scanned"])
    print("  skipped %d still warm (<%.1f h quiet) and %d the registry calls live"
          % (stats["still_warm"], a.settle_hours, stats["registry_live"]))
    print("  skipped %d with no turn-final close (%s)"
          % (stats["no_close_skipped"],
             "--include-no-close is OFF" if not a.include_no_close else "n/a"))
    print("  dropped %d with no naming tell, %d with no extractable clause"
          % (stats["no_tell"], stats["no_finding"]))
    print("  dropped %d whose clause names only ledger ids that ALREADY exist "
          "(exact key lookup in the destination store, not harvest detection)"
          % stats["already_in_venue"])
    print("  DRAINABLE: %d (%d from a close, %d from a mid-turn death)"
          % (len(rows), stats["from_close"], stats["from_no_close"]))
    if not a.commit:
        print("\n--- DRY RUN (nothing written; pass --commit to file) ---")
        for i, r in enumerate(rows, 1):
            print("\n[%d] %s  project=%s  origin=%s" % (i, r["sid"][:8], r["project"], r["origin"]))
            print("    %s" % r["finding"][:200])
        return 0
    filed = dup = failed = 0
    for r in rows:
        rc, out, err = file_row(a.cc_backlog, r, a.project)
        if rc != 0:
            failed += 1
            print("  REFUSED rc=%d %s :: %s" % (rc, r["sid"][:8], err[:160]))
            continue
        filed += 1
        print("  filed %s  <- %s" % (out.split()[-1] if out else "?", r["sid"][:8]))
    print("\nfiled %d, refused %d (cc-backlog's own id scheme absorbs a re-run: "
          "an identical title on an identical project re-files as the SAME id)"
          % (filed, failed))
    return 0 if failed == 0 else 1


def selftest():
    """Polarity controls on the two decisions this producer actually makes."""
    ok = True
    if finding_of("✅ Complete & live on trunk.\nGood to close: yes — follow-on: none.") != "":
        print("FAIL: a close whose follow-on ledger is 'none' yielded a finding"); ok = False
    f = finding_of("Good to close: yes — follow-on: land the parked rule commit on wt-2ee30f87c370.")
    if "land the parked rule commit" not in f:
        print("FAIL: the follow-on ledger was not preferred: %r" % f); ok = False
    f2 = finding_of("🔧 Loose ends — the tenant-drift env fix remains unlanded on its branch.")
    if "tenant-drift" not in f2:
        print("FAIL: no clause lifted from a 🔧 close: %r" % f2); ok = False
    if not NAMES_WORK.search("🔧 Loose ends — continuing."):
        print("FAIL: the shared matcher drifted from the instrument's"); ok = False
    t = title_of("do the thing", "abcdef12-3456", "/tmp/x.jsonl", "close")
    if "/tmp/x.jsonl" not in t:
        print("FAIL: the row does not name the file holding the dropped close"); ok = False
    fal = falsifier_of("/repo", ["offbox-core-cure"])
    if "offbox-core-cure" not in fal or "git -C /repo" not in fal:
        print("FAIL: the falsifier does not probe the token in the repo: %r" % fal); ok = False
    if falsifier_of(None, ["x"]) != "" or falsifier_of("/repo", []) != "":
        print("FAIL: a falsifier was minted with nothing to probe"); ok = False
    for nil in ("Good to close: yes — follow-on: none filed.",
                "Good to close: yes — follow-on: nothing outstanding.",
                "Good to close: yes — follow-on: the three filed items above.",
                "Good to close: yes — follow-on: none, everything of mine is "
                "landed and content-verified on trunk this turn."):
        if finding_of(nil) != "":
            print("FAIL: an empty/unactionable follow-on ledger drained: %r" % nil)
            ok = False
    if finding_of("Everything of mine is finished, landed and now live; the "
                  "backlog rows are closed and nothing of mine is open.") != "":
        print("FAIL: a settled close with no OPEN tell was drained"); ok = False
    if finding_of("🔧 17:03, `ahead=1`.") != "":
        print("FAIL: a clause too short to name anything was drained"); ok = False
    if finding_of("Re-checked live: clean tree, 0 unpushed, both backlog rows "
                  "closed and nothing of mine is open.") != "":
        print("FAIL: a settled close was drained as a finding"); ok = False
    fo = finding_of("I filed it as a backlog row for later. The tenant-drift env "
                    "fix still remains unlanded on its own branch today.")
    if "still remains unlanded" not in fo:
        print("FAIL: a stated OPEN thing did not outrank a bare filing mention: %r" % fo)
        ok = False
    ids = {"aaaaaaaaaaaa", "bbbbbbbbbbbb"}
    if not already_in_venue("`aaaaaaaaaaaa`, `bbbbbbbbbbbb`.", ids):
        print("FAIL: a clause of ids already in the ledger was not recognised"); ok = False
    if already_in_venue("`aaaaaaaaaaaa`, `cccccccccccc`.", ids):
        print("FAIL: an id ABSENT from the ledger was treated as already filed"); ok = False
    if already_in_venue("row `aaaaaaaaaaaa` proves the converger never ran, so the "
                        "live layer is still 27 commits behind its budget", ids):
        print("FAIL: a real finding that merely cites a filed row was dropped"); ok = False
    print("SELFTEST: %s" % ("green — 17/17" if ok else "RED"))
    return 0 if ok else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(main())
