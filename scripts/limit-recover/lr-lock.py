#!/usr/bin/env python3
"""lr-lock.py — the TTL policy and the release verb for lr-transplant's split-brain lock.

    lr-lock.py list   [--json]                      every lock, classified
    lr-lock.py status <sid|sid-prefix> [--json]     one lock, classified
    lr-lock.py release <sid|sid-prefix> --why "<text>" [--force]
    lr-lock.py reap [--ttl SECONDS] [--dry-run]     archive every EXPIRED lock (the TTL)

THE DEFECT (cc-backlog 4f8c73bbdb35, VOLUNTARY_ACCOUNT_SWITCH.md § 9). lr-transplant.sh writes
`$LR_STATE_DIR/locks/<sid>.lock` and nothing on the tree ever removed one: no TTL, no release verb.
An abandoned move — an `admit` whose `confirm` never came, a copy that died before it landed — so held
custody forever. Every later move of that uuid to any other store REFUSES at both refusal sites
(`already transplanted to …`, `lock exists`) with `--force` as the only door, and `cc-limited
--reaper` renders the claim as CLAIMED-NOT-LIVE until somebody hand-deletes the file.

WHY THIS IS NOT "DELETE LOCKS OLDER THAN N HOURS". The lock is not only a mutex. It is the CUSTODY
record the resume path reads (`lr_tombstone_verdict`, lr-fire-resume.sh; `lr_transplanted_to`,
lr-lib.sh): a completed move keeps its lock for as long as the successor lives, and that lock is what
refuses a second live copy on the ORIGINAL account (backlog 24c9955d6c4f — two sessions went live in
two accounts at once). An age-only TTL would disarm that guard on exactly the long-quiet successors it
protects, and stamp-age as a liveness proxy is already refuted on this subsystem (lr-fire-resume.sh
header). So the TTL is a TTL on EVIDENCE, not on age: a lock expires only when it is past its TTL AND
the disk proves it carries no custody. Age alone never reaps anything; it only keeps a move that is
still IN FLIGHT (the lock is written before the copy, and admit→confirm spans the composer gate) from
being read as abandoned.

THE CLASSES — every one decided from files, never from a pid, a pane or a clock-age heuristic:

  ORPHAN      the lock's owner store holds no `<sid>.jsonl`. There is no successor to protect, and
              every reader already treats this lock as "successor gone" — only lr-transplant's two
              refusals and cc-limited's reaper still see it. AUTO-EXPIRES after the TTL.
  ABANDONED   the successor copy has not been written since the move (its mtime is the copy's, which
              `cp -p` pins to the SOURCE's mtime at copy time) while the source is still a live
              `<sid>.jsonl` that HAS been written since. The session kept working where it was and never
              ran where the lock says it went. Relative ordering of two events on one subject, not
              an age bound. AUTO-EXPIRES after the TTL.
  QUIET       successor present and unwritten, source live and unwritten. Nothing on disk says which
              copy is real. NEVER auto-expires; `release` accepts it (the operator's assertion).
  CUSTODY     the successor has run (written since the move) or the source is retired/absent. This
              is the lock doing its job. NEVER expires; `release` refuses without --force.
  SPLIT       both copies were written since the move — the split brain the lock exists to prevent
              actually happened. NEVER expires; `release` refuses without --force: the lock is the
              evidence, and it names both stores.
  UNPARSEABLE the lock names no owner. Fail closed, exactly as lr_tombstone_verdict does.

RELEASE NEVER DELETES. The lock is renamed into `locks/released/<sid>.<ts>.json` with the release
recorded on it (`released_at`, `released_why`, `released_class`, `released_by`), so an expiry is
auditable and reversible by hand. No reader globs `released/`: cc-limited and lr-fleet enumerate
`locks/*.lock` and lr-transplant / lr-lib / lr-fire-resume open `locks/<sid>.lock` by name. When the
move is being declared NOT to have happened (ABANDONED, QUIET) the source-side tombstone that names
the same target is renamed `<sid>.HANDOFF.json.released` too — `lr_transplant_target` falls back to it
when the lock is gone, and would otherwise keep calling a live source pane a husk. A forced release of
CUSTODY/SPLIT leaves the tombstone: that move DID happen, and only the lock is being given up.

Exit: 0 ok · 1 no such lock · 2 REFUSED (nothing changed) · 3 usage.
Env: LR_STATE_DIR (default ~/.reso/limit-recover) · LR_LOCK_TTL_S (default 21600) ·
     LR_LOCK_SLACK_S (default 60) · LR_NOW (epoch; tests).
"""
import glob
import json
import os
import socket
import sys
import time
from datetime import datetime, timezone

RC_OK, RC_NOMATCH, RC_REFUSED, RC_USAGE = 0, 1, 2, 3

STATE_DIR = os.environ.get("LR_STATE_DIR") or os.path.join(os.path.expanduser("~"), ".reso", "limit-recover")
LOCKS_DIR = os.path.join(STATE_DIR, "locks")
RELEASED_DIR = os.path.join(LOCKS_DIR, "released")


def _int_env(name, default):
    try:
        return int(os.environ.get(name, "") or default)
    except ValueError:
        return default


# SIX HOURS. Two floors, and the longer one sets it. (1) The in-flight window: admit → confirm is
# bounded by the composer gate (≤180 s, handoff-fire.sh) plus the copy. (2) The supervisor horizon
# (scripts/reaper-horizon-lint.sh): no reaper may retire evidence faster than 10 × the slowest sweep
# (600 s) — cc-limited --reaper must get to SEE a stuck claim before it expires. 6 h clears both with
# room. An operator who cannot wait has the release verb; the TTL is for the moves nobody looks at.
TTL_S = _int_env("LR_LOCK_TTL_S", 21600)
# "Written since the move" means an mtime past the lock's `ts` by more than this. `ts` is taken just
# BEFORE the copy and at one-second resolution, and `cp -p` gives the target the source's mtime at
# copy time, which a still-appending source can put a second or two after `ts`.
SLACK_S = _int_env("LR_LOCK_SLACK_S", 60)
NOW = _int_env("LR_NOW", 0) or int(time.time())

AUTO_EXPIRE = ("ORPHAN", "ABANDONED")
RELEASABLE = ("ORPHAN", "ABANDONED", "QUIET")
DISOWNS_MOVE = ("ABANDONED", "QUIET")      # classes whose release also retires the tombstone


def ts_epoch(s):
    if not isinstance(s, str) or not s:
        return None
    try:
        return int(datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
    except ValueError:
        return None


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def transcripts(store, sid, suffix=".jsonl"):
    if not store:
        return []
    return sorted(p for p in glob.glob(os.path.join(store, "projects", "*", sid + suffix)) if os.path.isfile(p))


def mtime(path):
    try:
        return int(os.stat(path).st_mtime)
    except OSError:
        return None


def read_lock(path):
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        return None, None
    try:
        rec = json.loads(raw)
    except ValueError:
        rec = None
    return raw, (rec if isinstance(rec, dict) else None)


def classify(path):
    """→ dict: sid, path, class, why, age, owner, source, ts, raw."""
    sid = os.path.basename(path)[:-len(".lock")]
    raw, rec = read_lock(path)
    row = {"sid": sid, "path": path, "raw": raw, "owner": "", "source": "", "ts": "", "age": None}
    if rec is None:
        row.update({"class": "UNPARSEABLE", "why": "not a JSON object — cannot say where %s went" % sid})
        return row
    # `owner` since W5-B; `to` on a pre-W5-B lock — the same fallback lr-transplant's own reader uses.
    owner = rec.get("owner") or rec.get("to") or ""
    source = rec.get("from") or ""
    ts = ts_epoch(rec.get("ts"))
    row.update({"owner": owner, "source": source, "ts": rec.get("ts") or "",
                "age": (NOW - ts) if ts is not None else None})
    if not owner or not isinstance(owner, str):
        row.update({"class": "UNPARSEABLE", "why": "names no owner — refusing to guess where %s went" % sid})
        return row
    succ = transcripts(owner, sid)
    if not succ:
        row.update({"class": "ORPHAN", "why": "no %s.jsonl under %s — there is no successor to protect" % (sid, owner)})
        return row
    if ts is None:
        # A successor exists and the move has no usable time, so nothing can be ordered against it.
        row.update({"class": "CUSTODY", "why": "successor present and the lock's ts is unreadable — cannot prove it never ran"})
        return row
    edge = ts + SLACK_S
    succ_ran = any((mtime(p) or 0) > edge for p in succ)
    live_src = [p for p in transcripts(source, sid)] if source and os.path.realpath(source) != os.path.realpath(owner) else []
    src_ran = any((mtime(p) or 0) > edge for p in live_src)
    if not live_src:
        row.update({"class": "CUSTODY", "why": "the source holds no live %s.jsonl (retired or gone) — the move completed" % sid})
    elif succ_ran and src_ran:
        row.update({"class": "SPLIT", "why": "BOTH copies were written after the move: %s and %s" % (succ[0], live_src[0])})
    elif succ_ran:
        row.update({"class": "CUSTODY", "why": "the successor has run since the move (%s)" % succ[0]})
    elif src_ran:
        row.update({"class": "ABANDONED", "why": "the source kept working after the move and the successor never ran (%s)" % live_src[0]})
    else:
        row.update({"class": "QUIET", "why": "neither copy written since the move — disk cannot say which is real"})
    return row


def all_locks():
    try:
        names = sorted(os.listdir(LOCKS_DIR))
    except FileNotFoundError:
        return []
    return [os.path.join(LOCKS_DIR, n) for n in names if n.endswith(".lock")]


def expired(row, ttl):
    return row["class"] in AUTO_EXPIRE and row["age"] is not None and row["age"] > ttl


def fmt_age(a):
    if a is None:
        return "?"
    for unit, n in (("d", 86400), ("h", 3600), ("m", 60)):
        if a >= n:
            return "%d%s" % (a // n, unit)
    return "%ds" % max(a, 0)


def render(rows, as_json):
    if as_json:
        for r in rows:
            out = {k: v for k, v in r.items() if k != "raw"}
            out["expired"] = expired(r, TTL_S)
            print(json.dumps(out, sort_keys=True))
        return
    for r in rows:
        flag = " EXPIRED" if expired(r, TTL_S) else ""
        print("%-11s %s  age=%-5s owner=%s%s — %s" % (r["class"], r["sid"][:8], fmt_age(r["age"]),
                                                       r["owner"] or "?", flag, r["why"]))


def resolve(ref):
    hits = [p for p in all_locks() if os.path.basename(p).startswith(ref)]
    if not hits:
        sys.stderr.write("lr-lock: no lock matching %s in %s\n" % (ref, LOCKS_DIR))
        return None, RC_NOMATCH
    if len(hits) > 1:
        sys.stderr.write("lr-lock: %s is ambiguous:\n" % ref)
        for p in hits:
            sys.stderr.write("  %s\n" % p)
        return None, RC_USAGE
    return hits[0], RC_OK


def archive(row, why, by):
    """Rename the lock out of every reader's sight, then record the release on the archived copy.
    RENAME FIRST, compare after: a transplant that rewrote the lock between the read and the rename
    must not have ITS claim released on a verdict about the previous one."""
    os.makedirs(RELEASED_DIR, exist_ok=True)
    dst = os.path.join(RELEASED_DIR, "%s.%s.json" % (row["sid"], iso(NOW).replace(":", "")))
    n = 1
    while os.path.exists(dst):
        dst = os.path.join(RELEASED_DIR, "%s.%s.%d.json" % (row["sid"], iso(NOW).replace(":", ""), n))
        n += 1
    os.rename(row["path"], dst)
    raw, rec = read_lock(dst)
    if raw != row["raw"]:
        if not os.path.exists(row["path"]):
            os.rename(dst, row["path"])
        sys.stderr.write("lr-lock: REFUSED — %s changed under this release (a transplant is writing it); nothing released\n" % row["path"])
        return None
    rec = dict(rec or {"unparseable": row["raw"]})
    rec.update({"released_at": iso(NOW), "released_why": why, "released_class": row["class"],
                "released_by": by, "released_from": row["path"]})
    tmp = dst + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(rec, fh, sort_keys=True)
        fh.write("\n")
    os.rename(tmp, dst)
    retired = []
    if row["class"] in DISOWNS_MOVE:
        owner_real = os.path.realpath(row["owner"])
        for tomb in transcripts(row["source"], row["sid"], ".HANDOFF.json"):
            try:
                with open(tomb, encoding="utf-8") as fh:
                    t = json.load(fh)
            except (OSError, ValueError):
                continue
            # only the tombstone of THIS move — a --mark SUPERSEDED tombstone names another thing
            if isinstance(t, dict) and os.path.realpath(t.get("handed_off_to") or "") == owner_real:
                os.rename(tomb, tomb + ".released")
                retired.append(tomb + ".released")
    return dst, retired


def cmd_list(args):
    as_json = "--json" in args
    if [a for a in args if a != "--json"]:
        return usage()
    render([classify(p) for p in all_locks()], as_json)
    return RC_OK


def cmd_status(args):
    as_json = "--json" in args
    refs = [a for a in args if a != "--json"]
    if len(refs) != 1 or refs[0].startswith("-"):
        return usage()
    path, rc = resolve(refs[0])
    if path is None:
        return rc
    render([classify(path)], as_json)
    return RC_OK


def cmd_release(args):
    ref, why, force, i = "", "", False, 0
    while i < len(args):
        a = args[i]
        if a == "--why" and i + 1 < len(args):
            i += 1
            why = args[i]
        elif a == "--force":
            force = True
        elif not a.startswith("-") and not ref:
            ref = a
        else:
            return usage()
        i += 1
    if not ref or not why.strip():
        sys.stderr.write('lr-lock: usage: lr-lock release <sid> --why "<text>" [--force]\n')
        return RC_USAGE
    path, rc = resolve(ref)
    if path is None:
        return rc
    row = classify(path)
    if row["class"] not in RELEASABLE and not force:
        sys.stderr.write(
            "lr-lock: REFUSED — %s is %s: %s. This lock is the custody record the resume guard reads "
            "(lr_tombstone_verdict); releasing it lets the session go live on a second account. Pass "
            "--force only once you have established the successor at %s is not the session.\n"
            % (row["sid"], row["class"], row["why"], row["owner"] or "?"))
        return RC_REFUSED
    done = archive(row, why, "release%s pid=%d host=%s" % (" --force" if force else "", os.getpid(), socket.gethostname()))
    if done is None:
        return RC_REFUSED
    dst, retired = done
    print("released %s (%s) → %s%s" % (row["sid"][:8], row["class"], dst,
                                        "".join("; tombstone → %s" % t for t in retired)))
    return RC_OK


def cmd_reap(args):
    ttl, dry, i = TTL_S, False, 0
    while i < len(args):
        a = args[i]
        if a == "--ttl" and i + 1 < len(args):
            i += 1
            try:
                ttl = int(args[i])
            except ValueError:
                return usage()
        elif a == "--dry-run":
            dry = True
        else:
            return usage()
        i += 1
    rc = RC_OK
    for path in all_locks():
        row = classify(path)
        if not expired(row, ttl):
            continue
        if dry:
            print("would expire %s (%s, age %s) — %s" % (row["sid"][:8], row["class"], fmt_age(row["age"]), row["why"]))
            continue
        done = archive(row, "TTL: %s past %ds — %s" % (row["class"], ttl, row["why"]),
                       "reap pid=%d host=%s" % (os.getpid(), socket.gethostname()))
        if done is None:
            rc = RC_REFUSED
            continue
        dst, retired = done
        print("expired %s (%s, age %s) → %s%s" % (row["sid"][:8], row["class"], fmt_age(row["age"]), dst,
                                                  "".join("; tombstone → %s" % t for t in retired)))
    return rc


def usage():
    sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
    return RC_USAGE


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        sys.stdout.write(__doc__)
        return RC_OK if argv else RC_USAGE
    verbs = {"list": cmd_list, "status": cmd_status, "release": cmd_release, "reap": cmd_reap}
    if argv[0] not in verbs:
        return usage()
    return verbs[argv[0]](argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
