#!/usr/bin/env python3
"""lr-lock.py — the TTL policy and the release verb for lr-transplant's split-brain lock.

    lr-lock.py list   [--json]                      every lock, classified
    lr-lock.py status <sid|sid-prefix> [--json]     one lock, classified
    lr-lock.py release <sid|sid-prefix> --why "<text>" [--force]
    lr-lock.py reap [--ttl SECONDS] [--dry-run]     archive every EXPIRED lock (the TTL)
    lr-lock.py evidence-gc [--dry-run] [--min-age-days N]   free evidence bytes an account store holds

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
              Also a stub `<sid>.jsonl` beside `<sid>.jsonl.handed-off` in the source store, ahead of ORPHAN.
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

EVIDENCE GC (decision 6d4722735677, 2026-10-11). lr-transplant files a disowned target copy into
`locks/<sid>.<aborted|unconfirmed|failed-admit>-<UTCts>/` and never deletes it. `evidence-gc` frees an
evidence dir's `<sid>.jsonl` and `<sid>/` once the dir is N days old (LR_EVIDENCE_GC_DAYS, default 7),
and ONLY when every file is proven to exist in an account store: a .jsonl must be a byte-prefix of, and
any other file identical to, the same name in a store's live `<sid>.jsonl`, `<sid>.jsonl.handed-off`
or `<sid>/`. A `.stale-*` or `.released-*` copy, another evidence dir, anything resolving into the
state dir, or the same inode never covers. Measured at decision time: 31/31 dirs covered, 0 unique
bytes. Crash-safe receipt: GC.json.pending → per-file re-check, then delete → GC.json (per file: rel,
bytes, covered_by, so `head -c <bytes> <covered_by>` rebuilds it). A sid whose lock has a live holder
is skipped (confirm's `cp -p` and abort's `mv` rewrite the covering file). A dir with ANY uncovered
file is kept whole: that is the incident the old never-delete rule guarded against (turns that exist
nowhere else), so it gets ONE `EVIDENCE-KEPT` stamp, a count in `cc-lr status`, and one page.

Exit: 0 ok · 1 no such lock · 2 REFUSED (nothing changed) · 3 usage.
Env: LR_STATE_DIR (default ~/.reso/limit-recover) · LR_LOCK_TTL_S (default 21600) ·
     LR_LOCK_SLACK_S (default 60) · LR_NOW (epoch; tests) · LR_CONFIG_DIRS (colon list of stores) ·
     LR_EVIDENCE_GC_DAYS (default 7) · LR_EVIDENCE_GC_PAGE_BIN (default lr-page.sh beside this file).
"""

import fcntl
import glob
import json
import os
import re
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone

RC_OK, RC_NOMATCH, RC_REFUSED, RC_USAGE = 0, 1, 2, 3

STATE_DIR = os.environ.get("LR_STATE_DIR") or os.path.join(
    os.path.expanduser("~"), ".reso", "limit-recover"
)
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
DISOWNS_MOVE = (
    "ABANDONED",
    "QUIET",
)  # classes whose release also retires the tombstone


def ts_epoch(s):
    if not isinstance(s, str) or not s:
        return None
    try:
        return int(
            datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
            .replace(tzinfo=timezone.utc)
            .timestamp()
        )
    except ValueError:
        return None


def iso(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def transcripts(store, sid, suffix=".jsonl"):
    if not store:
        return []
    return sorted(
        p
        for p in glob.glob(os.path.join(store, "projects", "*", sid + suffix))
        if os.path.isfile(p)
    )


def mtime(path):
    try:
        return int(os.stat(path).st_mtime)
    except OSError:
        return None


def stub_beside_retired(store: object, sid: str) -> bool:
    """True when one slug dir of `store` holds both <sid>.jsonl and <sid>.jsonl.handed-off."""
    if not isinstance(store, str) or not store:
        return False
    return any(
        os.path.isfile(p[: -len(".handed-off")])
        for p in transcripts(store, sid, ".jsonl.handed-off")
    )


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
    sid = os.path.basename(path)[: -len(".lock")]
    raw, rec = read_lock(path)
    row = {
        "sid": sid,
        "path": path,
        "raw": raw,
        "owner": "",
        "source": "",
        "ts": "",
        "age": None,
    }
    if rec is None:
        row.update(
            {
                "class": "UNPARSEABLE",
                "why": "not a JSON object — cannot say where %s went" % sid,
            }
        )
        return row
    # `owner` since W5-B; `to` on a pre-W5-B lock — the same fallback lr-transplant's own reader uses.
    owner = rec.get("owner") or rec.get("to") or ""
    source = rec.get("from") or ""
    ts = ts_epoch(rec.get("ts"))
    row.update(
        {
            "owner": owner,
            "source": source,
            "ts": rec.get("ts") or "",
            "age": (NOW - ts) if ts is not None else None,
        }
    )
    if not owner or not isinstance(owner, str):
        row.update(
            {
                "class": "UNPARSEABLE",
                "why": "names no owner — refusing to guess where %s went" % sid,
            }
        )
        return row
    # A session wrote again after its retire: which copy is whole is unresolved until fold-stub runs,
    # so no age and no successor state may expire this lock.
    if stub_beside_retired(rec.get("from"), sid):
        row.update(
            {
                "class": "CUSTODY",
                "why": "a stub sits beside the retired transcript — custody is unresolved; never expires",
            }
        )
        return row
    succ = transcripts(owner, sid)
    if not succ:
        row.update(
            {
                "class": "ORPHAN",
                "why": "no %s.jsonl under %s — there is no successor to protect"
                % (sid, owner),
            }
        )
        return row
    if ts is None:
        # A successor exists and the move has no usable time, so nothing can be ordered against it.
        row.update(
            {
                "class": "CUSTODY",
                "why": "successor present and the lock's ts is unreadable — cannot prove it never ran",
            }
        )
        return row
    edge = ts + SLACK_S
    succ_ran = any((mtime(p) or 0) > edge for p in succ)
    live_src = (
        [p for p in transcripts(source, sid)]
        if source and os.path.realpath(source) != os.path.realpath(owner)
        else []
    )
    src_ran = any((mtime(p) or 0) > edge for p in live_src)
    if not live_src:
        row.update(
            {
                "class": "CUSTODY",
                "why": "the source holds no live %s.jsonl (retired or gone) — the move completed"
                % sid,
            }
        )
    elif succ_ran and src_ran:
        row.update(
            {
                "class": "SPLIT",
                "why": "BOTH copies were written after the move: %s and %s"
                % (succ[0], live_src[0]),
            }
        )
    elif succ_ran:
        row.update(
            {
                "class": "CUSTODY",
                "why": "the successor has run since the move (%s)" % succ[0],
            }
        )
    elif src_ran:
        row.update(
            {
                "class": "ABANDONED",
                "why": "the source kept working after the move and the successor never ran (%s)"
                % live_src[0],
            }
        )
    else:
        row.update(
            {
                "class": "QUIET",
                "why": "neither copy written since the move — disk cannot say which is real",
            }
        )
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
        print(
            "%-11s %s  age=%-5s owner=%s%s — %s"
            % (
                r["class"],
                r["sid"][:8],
                fmt_age(r["age"]),
                r["owner"] or "?",
                flag,
                r["why"],
            )
        )


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
    dst = os.path.join(
        RELEASED_DIR, "%s.%s.json" % (row["sid"], iso(NOW).replace(":", ""))
    )
    n = 1
    while os.path.exists(dst):
        dst = os.path.join(
            RELEASED_DIR, "%s.%s.%d.json" % (row["sid"], iso(NOW).replace(":", ""), n)
        )
        n += 1
    os.rename(row["path"], dst)
    raw, rec = read_lock(dst)
    if raw != row["raw"]:
        if not os.path.exists(row["path"]):
            os.rename(dst, row["path"])
        sys.stderr.write(
            "lr-lock: REFUSED — %s changed under this release (a transplant is writing it); nothing released\n"
            % row["path"]
        )
        return None
    rec = dict(rec or {"unparseable": row["raw"]})
    rec.update(
        {
            "released_at": iso(NOW),
            "released_why": why,
            "released_class": row["class"],
            "released_by": by,
            "released_from": row["path"],
        }
    )
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
            if (
                isinstance(t, dict)
                and os.path.realpath(t.get("handed_off_to") or "") == owner_real
            ):
                os.rename(tomb, tomb + ".released")
                retired.append(tomb + ".released")
        # A RETURN HOP's admit set the target's own leftovers aside (lr-transplant.sh, THE RETURN HOP)
        # and recorded them here; a release disowns the move exactly as abort does, so they go back —
        # link-then-unlink, never over a name that exists again.
        for r in rec.get("returned") if isinstance(rec.get("returned"), list) else []:
            p, a = (
                (r.get("path"), r.get("aside")) if isinstance(r, dict) else (None, None)
            )
            if not (isinstance(p, str) and isinstance(a, str)):
                continue
            try:
                os.link(a, p)
                os.unlink(a)
                sys.stderr.write(
                    "lr-lock: restored %s (set aside by this move's admit)\n" % p
                )
            except OSError as e:
                sys.stderr.write(
                    "lr-lock: could not restore %s from %s (%s) — left as it is\n"
                    % (p, a, e.strerror)
                )
        set_aside_target_copy(row)
    return dst, retired


def is_byte_prefix(short, long):
    """True when every byte of `short` opens `long` (equal files included)."""
    try:
        if os.path.getsize(short) > os.path.getsize(long):
            return False
        with open(short, "rb") as a, open(long, "rb") as b:
            while True:
                chunk = a.read(1 << 20)
                if not chunk:
                    return True
                if b.read(len(chunk)) != chunk:
                    return False
    except OSError:
        return False


def set_aside_target_copy(row):
    """THE TARGET COPY GOES TOO (2026-10-11, pane 14 / 4d059264). Disowning a move used to leave the
    owner store's <sid>.jsonl behind, and every later move of the session counted it as a second live
    transcript (the move proof's source-ambiguous), so a session that once had a move released could
    never move again. Neither disowning class's successor ran, so the copy should be a byte-prefix of
    the live source and hold nothing of its own. That is CHECKED, not assumed: a copy that is not a
    prefix stays where it is. Renamed to <name>.released-<UTCts>, never deleted, link-then-unlink."""
    live = [p for p in transcripts(row["source"], row["sid"])]
    live_real = {os.path.realpath(p) for p in live}
    for cp in transcripts(row["owner"], row["sid"]):
        if os.path.realpath(cp) in live_real:
            continue  # one store behind two config dirs: the "copy" IS the live source
        src = [
            p
            for p in live
            if os.path.basename(os.path.dirname(p))
            == os.path.basename(os.path.dirname(cp))
        ]
        if not src or not is_byte_prefix(cp, src[0]):
            sys.stderr.write(
                "lr-lock: kept %s — not a byte-prefix of a live source transcript, so it may hold "
                "turns of its own\n" % cp
            )
            continue
        dst = "%s.released-%s" % (cp, iso(NOW).replace(":", "").replace("-", ""))
        n = 1
        while os.path.exists(dst):
            dst = "%s.released-%s.%d" % (
                cp,
                iso(NOW).replace(":", "").replace("-", ""),
                n,
            )
            n += 1
        try:
            os.link(cp, dst)
            os.unlink(cp)
            sys.stderr.write(
                "lr-lock: set aside the disowned move's target copy %s → %s (a byte-prefix of %s)\n"
                % (cp, dst, src[0])
            )
        except OSError as e:
            sys.stderr.write(
                "lr-lock: could not set aside %s (%s) — left as it is\n"
                % (cp, e.strerror)
            )


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
        sys.stderr.write(
            'lr-lock: usage: lr-lock release <sid> --why "<text>" [--force]\n'
        )
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
            % (row["sid"], row["class"], row["why"], row["owner"] or "?")
        )
        return RC_REFUSED
    done = archive(
        row,
        why,
        "release%s pid=%d host=%s"
        % (" --force" if force else "", os.getpid(), socket.gethostname()),
    )
    if done is None:
        return RC_REFUSED
    dst, retired = done
    print(
        "released %s (%s) → %s%s"
        % (
            row["sid"][:8],
            row["class"],
            dst,
            "".join("; tombstone → %s" % t for t in retired),
        )
    )
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
            print(
                "would expire %s (%s, age %s) — %s"
                % (row["sid"][:8], row["class"], fmt_age(row["age"]), row["why"])
            )
            continue
        done = archive(
            row,
            "TTL: %s past %ds — %s" % (row["class"], ttl, row["why"]),
            "reap pid=%d host=%s" % (os.getpid(), socket.gethostname()),
        )
        if done is None:
            rc = RC_REFUSED
            continue
        dst, retired = done
        print(
            "expired %s (%s, age %s) → %s%s"
            % (
                row["sid"][:8],
                row["class"],
                fmt_age(row["age"]),
                dst,
                "".join("; tombstone → %s" % t for t in retired),
            )
        )
    return rc


EVIDENCE_RE = re.compile(
    r"^(?P<sid>[0-9a-fA-F-]{8,})\.(?P<kind>aborted|unconfirmed|failed-admit)-"
    r"(?P<ts>\d{8}T\d{6}Z)(?:\.\d+)?$"
)


def config_dirs():
    """The account stores, as lr-lib.sh lr_config_dirs: LR_CONFIG_DIRS, else the five homes deduped
    by the PHYSICAL projects/ they read (first spelling wins)."""
    env = os.environ.get("LR_CONFIG_DIRS", "")
    if env:
        return [d for d in env.split(":") if d]
    home = os.path.expanduser("~")
    out, seen = [], set()
    for n in (
        ".claude",
        ".claude-next",
        ".claude-secondary",
        ".claude-tertiary",
        ".claude-quaternary",
    ):
        h = os.path.join(home, n)
        if not os.path.isdir(os.path.join(h, "projects")):
            continue
        key = os.path.realpath(os.path.join(h, "projects"))
        if key in seen:
            continue
        seen.add(key)
        out.append(h)
    return out


def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def _lstart(pid):
    """`ps -o lstart=` in UTC, blanks collapsed (lr-transplant.sh lrt_lstart); empty when none."""
    try:
        out = subprocess.run(
            ["ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=10,
            env=dict(os.environ, TZ="UTC", LC_ALL="C"),
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    return " ".join(out.split())


def lock_held(sid):
    """True when locks/<sid>.lock names a LIVE process: its holder (pid + lstart, lrt_live semantics),
    or the transplant pid that wrote it, unless that pid was started after the lock (a reused pid).
    Unreadable process facts read as held: a skipped dir is retried tomorrow, a raced one is not."""
    _, rec = read_lock(os.path.join(LOCKS_DIR, sid + ".lock"))
    if not rec:
        return False
    h = rec.get("holder") if isinstance(rec.get("holder"), dict) else {}
    hp = h.get("pid")
    if isinstance(hp, int) and not isinstance(hp, bool) and hp > 0 and _pid_alive(hp):
        want = " ".join(str(h.get("lstart") or "").split())
        if not want or _lstart(hp) == want:
            return True
    p = rec.get("pid")
    if isinstance(p, int) and not isinstance(p, bool) and p > 0 and _pid_alive(p):
        started, ts = _lstart(p), ts_epoch(rec.get("ts"))
        try:
            st = int(
                datetime.strptime(started, "%a %b %d %H:%M:%S %Y")
                .replace(tzinfo=timezone.utc)
                .timestamp()
            )
        except ValueError:
            return True
        if ts is None or st <= ts + SLACK_S:
            return True
    return False


def _under(path, root):
    r = os.path.realpath(root)
    return os.path.realpath(path) == r or os.path.realpath(path).startswith(r + os.sep)


def _covers(ev, cand, prefix):
    if _under(cand, STATE_DIR):
        return False
    try:
        if os.path.samefile(ev, cand):
            return False
    except OSError:
        return False
    if not prefix and os.path.getsize(ev) != os.path.getsize(cand):
        return False
    return is_byte_prefix(ev, cand)


def cover_index(sid, stores):
    """→ (main transcript candidates, slug dirs that hold a <sid>/ session dir), from ONE glob per
    store. A projects/* glob walks ~17,200 dirs per store; one per FILE (405 in a session dir) made
    the first live dry run CPU-bound for minutes, so callers resolve each file inside these dirs."""
    mains, slugs = [], []
    for s in stores:
        for p in sorted(
            glob.glob(
                os.path.join(glob.escape(s), "projects", "*", glob.escape(sid) + "*")
            )
        ):
            n = os.path.basename(p)
            if n in (sid + ".jsonl", sid + ".jsonl.handed-off") and os.path.isfile(p):
                mains.append(p)
            elif n == sid and os.path.isdir(p) and not os.path.islink(p):
                slugs.append(os.path.dirname(p))
    return mains, slugs


def cover_of(ev, rel, sid, idx):
    """→ the store path that holds `ev` (relative name `rel` inside the evidence dir), or None."""
    mains, slugs = idx
    if rel == sid + ".jsonl":
        cands = mains
    else:
        cands = [
            p
            for p in (os.path.join(d, rel) for d in slugs)
            if os.path.isfile(p) and not os.path.islink(p)
        ]
    for c in cands:
        if _covers(ev, c, rel.endswith(".jsonl")):
            return c
    return None


def evidence_files(ev_dir, sid):
    """→ [(rel, abspath)] of every entry GC would delete: <sid>.jsonl and everything under <sid>/.
    A symlink or special file is listed with abspath None, which never verifies (kept)."""
    out = []
    main = os.path.join(ev_dir, sid + ".jsonl")
    if os.path.lexists(main):
        out.append(
            (
                sid + ".jsonl",
                main if os.path.isfile(main) and not os.path.islink(main) else None,
            )
        )
    top = os.path.join(ev_dir, sid)
    if os.path.isdir(top) and not os.path.islink(top):
        for root, dirs, files in os.walk(top):
            for n in sorted(files) + sorted(
                d for d in dirs if os.path.islink(os.path.join(root, d))
            ):
                p = os.path.join(root, n)
                rel = os.path.relpath(p, ev_dir)
                out.append(
                    (rel, p if os.path.isfile(p) and not os.path.islink(p) else None)
                )
    elif os.path.lexists(top):
        out.append((sid, None))
    return out


def _write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, sort_keys=True, indent=1)
        fh.write("\n")
    os.rename(tmp, path)


def _load_files(path):
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
        return [f for f in d.get("files", []) if isinstance(f, dict)]
    except (OSError, ValueError, AttributeError):
        return []


def _prune_dirs(top):
    """Remove the now-empty directories under (and including) `top`; a dir that is not empty stays."""
    if not os.path.isdir(top) or os.path.islink(top):
        return
    for root, dirs, _files in os.walk(top, topdown=False):
        for d in dirs:
            try:
                os.rmdir(os.path.join(root, d))
            except OSError:
                pass
    try:
        os.rmdir(top)
    except OSError:
        pass


def gc_one(ev_dir, sid, stores, dry, new_kept):
    """→ (verdict, bytes). verdict: done | empty | held | kept | freed | would-free | raced."""
    receipt, pending = (
        os.path.join(ev_dir, "GC.json"),
        os.path.join(ev_dir, "GC.json.pending"),
    )
    files = evidence_files(ev_dir, sid)
    if not files:
        if (
            os.path.exists(pending) and not dry
        ):  # died after the last delete, before the rename
            os.rename(pending, receipt)
        return (
            "done" if os.path.exists(receipt) or os.path.exists(pending) else "empty"
        ), 0
    if lock_held(sid):
        return "held", 0
    plan, uncovered = [], []
    idx = cover_index(sid, stores)
    for rel, p in files:
        c = cover_of(p, rel, sid, idx) if p else None
        if c is None:
            uncovered.append(rel)
        else:
            plan.append((rel, p, c, os.path.getsize(p)))
    if uncovered:
        stamp = os.path.join(ev_dir, "EVIDENCE-KEPT")
        if not dry and not os.path.exists(stamp):
            _write_json(
                stamp,
                {
                    "ts": iso(NOW),
                    "uncovered": len(uncovered),
                    "first": uncovered[0],
                    "files": len(files),
                },
            )
            new_kept.append((ev_dir, len(uncovered), uncovered[0]))
        return "kept", 0
    nbytes = sum(b for _, _, _, b in plan)
    if dry:
        return "would-free", nbytes
    # A run that died mid-way left a .pending naming files it already freed; they stay on the receipt.
    planned = {r for r, _, _, _ in plan}
    recs = [
        f
        for f in (_load_files(pending) or _load_files(receipt))
        if f.get("rel") not in planned
    ]
    recs += [{"rel": r, "bytes": b, "covered_by": c} for r, _, c, b in plan]
    body = {
        "sid": sid,
        "dir": ev_dir,
        "ts": iso(NOW),
        "files": recs,
        "freed_bytes": sum(int(f.get("bytes") or 0) for f in recs),
        "by": "evidence-gc pid=%d host=%s" % (os.getpid(), socket.gethostname()),
    }
    _write_json(pending, body)
    # A transplant may have taken the sid between the verify pass and the first delete.
    if lock_held(sid):
        return "held", 0
    freed = 0
    idx = cover_index(
        sid, stores
    )  # re-resolved: a store copy may have moved since the pass
    for rel, p, _c, b in plan:
        # RE-CHECKED right before its delete: the covering copy may have been rewritten since the pass.
        if cover_of(p, rel, sid, idx) is None:
            return "raced", freed
        os.unlink(p)
        freed += b
    _prune_dirs(os.path.join(ev_dir, sid))
    os.rename(pending, receipt)
    return "freed", freed


def _page(new_kept):
    if not new_kept:
        return
    pg = os.environ.get("LR_EVIDENCE_GC_PAGE_BIN") or os.path.join(
        os.path.dirname(os.path.realpath(__file__)), "lr-page.sh"
    )
    d, k, first = new_kept[0]
    msg = (
        "limit-recover evidence: %d dir(s) hold bytes no account store has — turns that may exist "
        "nowhere else, kept untouched. First: %s (%d uncovered, e.g. %s). `cc-lr status` counts them."
        % (len(new_kept), os.path.basename(d), k, first)
    )
    try:
        r = subprocess.run(
            ["/bin/bash", pg, "--title", "evidence kept", "--", msg],
            capture_output=True,
            text=True,
            timeout=60,
        )
        v = (r.stdout.strip().splitlines() or ["lr-page: no verdict"])[-1]
    except (OSError, subprocess.SubprocessError) as e:
        v = "lr-page: not run (%s)" % e
    print("EVIDENCE-PAGE %s" % v)


def cmd_evidence_gc(args):
    dry, days, i = False, _int_env("LR_EVIDENCE_GC_DAYS", 7), 0
    while i < len(args):
        a = args[i]
        if a == "--dry-run":
            dry = True
        elif a == "--min-age-days" and i + 1 < len(args):
            i += 1
            try:
                days = int(args[i])
            except ValueError:
                return usage()
        else:
            return usage()
        i += 1
    try:
        names = sorted(os.listdir(LOCKS_DIR))
    except FileNotFoundError:
        names = []
    mutex = None
    if not dry:
        try:
            mutex = open(os.path.join(STATE_DIR, "evidence-gc.lock"), "a")
        except OSError as e:
            print("evidence-gc: verdict=no-state — %s (%s)" % (STATE_DIR, e.strerror))
            return RC_OK
        try:
            fcntl.flock(mutex, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            print(
                "evidence-gc: verdict=busy — another run holds %s/evidence-gc.lock"
                % STATE_DIR
            )
            return RC_OK
    stores = config_dirs()
    tally, nbytes, new_kept = {}, 0, []
    for n in names:
        m = EVIDENCE_RE.match(n)
        ev_dir = os.path.join(LOCKS_DIR, n)
        if not m or not os.path.isdir(ev_dir) or os.path.islink(ev_dir):
            continue
        # Age from the NAME (when lr-transplant filed it), never mtime: GC itself writes in the dir.
        filed = datetime.strptime(m.group("ts"), "%Y%m%dT%H%M%SZ")
        age = NOW - int(filed.replace(tzinfo=timezone.utc).timestamp())
        if age < days * 86400:
            v, b = "young", 0
        else:
            v, b = gc_one(ev_dir, m.group("sid"), stores, dry, new_kept)
        tally[v] = tally.get(v, 0) + 1
        nbytes += b
        if v in ("freed", "would-free", "kept", "raced", "held"):
            print("EVIDENCE-%s %s %d bytes" % (v.upper(), n, b))
    if not dry:
        _page(new_kept)
    print(
        "evidence-gc: verdict=%s dirs=%d %s=%d bytes (%.1f MB) stores=%d min_age_days=%d %s"
        % (
            "dry-run" if dry else "ok",
            sum(tally.values()),
            "would_free" if dry else "freed",
            nbytes,
            nbytes / 1048576.0,
            len(stores),
            days,
            " ".join("%s=%d" % kv for kv in sorted(tally.items())),
        )
    )
    return RC_OK


def usage():
    sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
    return RC_USAGE


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        sys.stdout.write(__doc__)
        return RC_OK if argv else RC_USAGE
    verbs = {
        "list": cmd_list,
        "status": cmd_status,
        "release": cmd_release,
        "reap": cmd_reap,
        "evidence-gc": cmd_evidence_gc,
    }
    if argv[0] not in verbs:
        return usage()
    return verbs[argv[0]](argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
