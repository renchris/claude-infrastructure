"""diagnose.py -- automatic diagnosis of a capture bundle, plus the capture kit's small helpers.

Run as (always $PY -I, never via #!: DESIGN I1):
  diagnose.py bundle   --bundle DIR [--state LWDIR] [--no-cause] [--roots A:B]  -> DIAGNOSIS.md, diagnosis.json
  diagnose.py suspects --bundle DIR --tier snapshot|full [--self PID]          -> pids to `sample` (stdout)
  diagnose.py manifest --bundle DIR --tier T --reason R --boot B [--self PID] [--missing "H2"]
  diagnose.py retention --root ROOT [--keep 3] [--cap-mb 3072]
File-only: reads the bundle's step outputs and the lockwatch state copies; never runs a process,
never touches /dev. The only unbounded-looking work, the transcript cause scan, is capped at 60 s
and 200 MB (DESIGN C3).

Signatures (each verdict cites the evidence files it matched):
  devfs_poison(ttysNNN)  walk canary WEDGED last="lstat ttysNNN" + a leader whose ttymap tty is
                         NNN, exiting or orphaned + (high confidence) a member of its PGID whose
                         sample leaf is __open. Names holder, leader, pgid, exiting-since, the R17
                         command and -- from the transcripts -- the cause.
  devfs_lookup_stall     walk canary wedged with no leader join, or >= 5 stuck ps/login whose leaf
                         is ttyname-class while starvation is OK
  kitty_rc_deaf          lockprobe kitty_rc=dead, or RC sockets >= 205 (#10632 class)
  idle_session_spin      >= 10 claude processes at >= 10% CPU each (transcript freshness not evaluated)
  cpu_starvation_31band  canaries slow, lockprobe starvation not OK, stuck census 0
  proc_table_stall       stuck:procscan while the walk canary is healthy (R7)
  none                   nothing matched
The join is by PGID plus the ttymap, never by e_tdev: an exiting leader reads NODEV (R13).
"""

import calendar
import json
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import rules  # noqa: E402

KILL_RE = re.compile(r"(^|[\s;&|(`])(kill|pkill|killall)\b")
CAUSE_BUDGET_S = 60.0
CAUSE_BUDGET_BYTES = 200 * 1024 * 1024


def read_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def first(bundle, *names):
    for n in names:
        p = os.path.join(bundle, n)
        if os.path.exists(p):
            return p
    return None


# ---------------------------------------------------------------- evidence readers ---------
def parse_canary(path):
    """Last key=value line of a devfs-canary run."""
    try:
        with open(path) as fh:
            lines = [x.strip() for x in fh if x.strip()]
    except OSError:
        return None
    if not lines:
        return None
    line = lines[-1]
    kv = {}
    if 'last="' in line:
        line, last = line.split('last="', 1)
        kv["last"] = last.rstrip('"')
    for tok in line.split():
        if "=" in tok:
            a, b = tok.split("=", 1)
            kv[a] = b
    return kv if kv.get("verdict") else None


def sample_leaf(path):
    """(leaf, main_thread_frames) from `sample` text: the top 'Sort by top of stack' entry, plus the
    first thread's call-graph frame names."""
    try:
        with open(path, errors="replace") as fh:
            text = fh.read()
    except OSError:
        return None, []
    leaf = None
    m = re.search(r"Sort by top of stack[^\n]*\n\s+(\S+)", text)
    if m:
        leaf = m.group(1)
    frames = []
    cg = text.split("Call graph:", 1)
    if len(cg) == 2:
        thread = 0
        for line in cg[1].splitlines():
            if not line.strip():
                if frames:
                    break
                continue
            if "Thread_" in line:
                thread += 1
                if thread > 1:
                    break
                continue
            mm = re.match(r"[\s+!:|]*\d+\s+(\S+)", line)
            if mm:
                frames.append(mm.group(1))
    if leaf is None and frames:
        leaf = frames[-1]
    return leaf, frames


def load_samples(bundle):
    out, chains = {}, {}
    for f in sorted(os.listdir(bundle)):
        m = re.match(r"08-sample-(\d+)\.txt$", f)
        if m:
            leaf, frames = sample_leaf(os.path.join(bundle, f))
            if leaf:
                out[int(m.group(1))] = leaf
                chains[int(m.group(1))] = frames
    return out, chains


def load_procs(bundle):
    d = (
        read_json(
            first(bundle, "02-procscan.json", "02-procscan.out") or "/nonexistent"
        )
        or {}
    )
    return d.get("procs") or [], d


# ---------------------------------------------------------------- cause attribution --------
def transcript_roots():
    env = os.environ.get("CC_FX_TRANSCRIPT_ROOTS")
    if env:
        return [r for r in env.split(":") if r]
    home = os.path.expanduser("~")
    roots = []
    try:
        for n in os.listdir(home):
            if n.startswith(".claude"):
                p = os.path.join(home, n, "projects")
                if os.path.isdir(p):
                    roots.append(p)
    except OSError:
        pass
    return roots


def _ts_epoch(s):
    if not s:
        return None
    try:
        t = time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")
        return calendar.timegm(t)
    except ValueError:
        return None


def cause_scan(
    pids,
    since,
    roots=None,
    window_s=600.0,
    kill_guard=None,
    budget_s=CAUSE_BUDGET_S,
    budget_bytes=CAUSE_BUDGET_BYTES,
):
    """Find agent Bash commands that kill/pkill/killall one of `pids` (or -pgid) within
    +/- window_s of `since`. File-only, newest files first, bounded in time and bytes."""
    t_end = time.time() + budget_s
    toks = set(str(int(p)) for p in pids if p)
    if not toks:
        return [], {"files": 0, "bytes": 0, "truncated": False}
    pat = re.compile(r"(?<![\d])-?(%s)(?![\d])" % "|".join(sorted(toks)))
    files = []
    for root in roots if roots is not None else transcript_roots():
        for dp, _dn, fn in os.walk(root):
            for f in fn:
                if f.endswith(".jsonl"):
                    p = os.path.join(dp, f)
                    try:
                        mt = os.stat(p).st_mtime
                    except OSError:
                        continue
                    if since is None or mt >= since - window_s:
                        files.append((mt, p))
            if time.time() > t_end:
                break
    # closest to the event first: the actor's transcript was written around `since`; newest-first
    # spent the whole 200 MB budget on sessions active hours later (measured on the 10-25 boot)
    files.sort(key=lambda f: abs(f[0] - since) if since is not None else -f[0])
    hits, nbytes, truncated = [], 0, False
    for _mt, p in files:
        if time.time() > t_end or nbytes > budget_bytes:
            truncated = True
            break
        try:
            with open(p, errors="replace") as fh:
                for line in fh:
                    nbytes += len(line)
                    if "kill" not in line or not pat.search(line):
                        continue
                    try:
                        row = json.loads(line)
                    except ValueError:
                        continue
                    ts = _ts_epoch(row.get("timestamp"))
                    if (
                        since is not None
                        and ts is not None
                        and abs(ts - since) > window_s
                    ):
                        continue
                    content = ((row.get("message") or {}).get("content")) or []
                    if not isinstance(content, list):
                        continue
                    for c in content:
                        if (
                            not isinstance(c, dict)
                            or c.get("type") != "tool_use"
                            or c.get("name") != "Bash"
                        ):
                            continue
                        cmd = (c.get("input") or {}).get("command") or ""
                        if KILL_RE.search(cmd) and pat.search(cmd):
                            hits.append(
                                {
                                    "kind": "transcript",
                                    "session": row.get("sessionId"),
                                    "cwd": row.get("cwd"),
                                    "ts": row.get("timestamp"),
                                    "command": cmd[:500],
                                    "file": p,
                                }
                            )
        except OSError:
            continue
    if kill_guard and os.path.exists(kill_guard):
        try:
            with open(kill_guard, errors="replace") as fh:
                for line in fh:
                    if pat.search(line):
                        try:
                            row = json.loads(line)
                        except ValueError:
                            continue
                        hits.append(
                            {
                                "kind": "kill-guard",
                                "session": row.get("session") or row.get("sid"),
                                "cwd": row.get("cwd"),
                                "ts": row.get("ts"),
                                "command": (row.get("command") or "")[:500],
                                "file": kill_guard,
                            }
                        )
        except OSError:
            pass
    return hits, {"files": len(files), "bytes": nbytes, "truncated": truncated}


# ---------------------------------------------------------------- diagnosis ---------------
def diagnose(bundle, state_dir=None, cause=True, roots=None):
    procs, _ps = load_procs(bundle)
    ttymap = read_json(first(bundle, "05-lockwatch-ttymap.json") or "/nonexistent")
    if ttymap is None and state_dir:
        st0 = read_json(os.path.join(state_dir, "state.json")) or {}
        ttymap = read_json(
            os.path.join(state_dir, "run", st0.get("boot") or "x", "ttymap.json")
        )
    ttymap = ttymap or {}
    state = read_json(first(bundle, "05-lockwatch-state.json") or "/nonexistent") or {}
    samples, chains = load_samples(bundle)
    ev = []
    canaries = []
    cf = first(bundle, "03-devfs-canary.out")
    c = parse_canary(cf) if cf else None
    if c:
        canaries.append((c, "03-devfs-canary.out"))
    sc = state.get("canary") or {}
    if sc.get("walk_verdict") in ("WEDGED", "WEDGED_PREVIOUS") and sc.get("last_node"):
        canaries.append(
            (
                {
                    "verdict": sc["walk_verdict"],
                    "last": sc["last_node"],
                    "stuck_s": sc.get("stuck_s"),
                },
                "05-lockwatch-state.json",
            )
        )
    wedged = [
        (c2, f)
        for c2, f in canaries
        if c2.get("verdict") in ("WEDGED", "WEDGED_PREVIOUS")
    ]
    out = {
        "v": 1,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "bundle": bundle,
        "verdict": "none",
        "confidence": "none",
        "evidence": ev,
        "samples": {str(k): v for k, v in samples.items()},
    }
    # 1. devfs_poison: walk wedged on ttysNNN + exiting/orphaned leader of NNN (ttymap) + __open member
    for c2, f in wedged:
        j = rules.poison_join(c2.get("last"), procs, ttymap, samples)
        if not j:
            continue
        conf = "high" if j["holder_basis"] == "sample:__open" else "medium"
        files = [f, "02-procscan.json", "05-lockwatch-ttymap.json"]
        if j["holder_basis"] == "sample:__open":
            files.append("08-sample-%d.txt" % j["holder"])
        ev.append(
            {
                "rule": "devfs_poison",
                "files": files,
                "detail": "walk %s last=%r; leader %d (%s) pgid %d; holder %s (%s)"
                % (
                    c2.get("verdict"),
                    c2.get("last"),
                    j["leader"],
                    j["tty"],
                    j["pgid"],
                    j["holder"],
                    j["holder_basis"],
                ),
            }
        )
        out.update(
            verdict="devfs_poison",
            confidence=conf,
            tty=j["tty"],
            holder=j["holder"],
            leader=j["leader"],
            lstart=j["lstart"],
            pgid=j["pgid"],
            members=j["members"],
            targets=j["targets"],
            unkillable=j["unkillable"],
            exiting_since=j.get("exiting_since"),
            holder_basis=j["holder_basis"],
            command="/bin/bash ~/.claude/scripts/break-glass/rescue.sh unpoison %d %d"
            % (j["pgid"], j["lstart"]),
            runbook=[
                "do NOT kill the leader by pid",
                "do NOT kill kitty",
                "kill the session tree (RCA R3: ppid descendants + same sid + their pgids), opener"
                " first: kill -KILL %s; then the leader. Unkillable (exiting): %s"
                % (
                    " ".join(str(x) for x in j["targets"]) or "(none live)",
                    " ".join(str(x) for x in j["unkillable"]),
                ),
                "re-test: lockprobe status (both canaries clean)",
            ],
        )
        if cause:
            since = j.get("exiting_since")
            if since is None:
                since = (
                    os.stat(bundle).st_mtime if os.path.exists(bundle) else time.time()
                )
            pids = (
                [j["leader"], j["pgid"]]
                + ([j["holder"]] if j["holder"] else [])
                + j["members"]
            )
            hits, stats = cause_scan(
                pids,
                since,
                roots,
                kill_guard=os.path.join(state_dir or "", "kill-guard.jsonl")
                if state_dir
                else None,
            )
            out["cause"] = hits[:10]
            out["cause_scan"] = stats
            for h in hits[:10]:
                ev.append(
                    {
                        "rule": "cause",
                        "files": [h["file"]],
                        "detail": "%s session %s cwd %s: %s"
                        % (h["ts"], h["session"], h["cwd"], h["command"]),
                    }
                )
        break
    # 2. devfs_lookup_stall
    if out["verdict"] == "none":
        stuck_tty = [
            pid
            for pid, leaf in samples.items()
            if any(t in (leaf or "") for t in rules.TTYNAME_LEAVES)
            and any(p["pid"] == pid and p.get("comm") in ("ps", "login") for p in procs)
        ]
        starv_ok = (state.get("starvation_ms") or 0) < 1000
        if wedged:
            c2, f = wedged[0]
            out.update(
                verdict="devfs_lookup_stall", confidence="medium", node=c2.get("last")
            )
            ev.append(
                {
                    "rule": "devfs_lookup_stall",
                    "files": [f],
                    "detail": "walk %s last=%r, no leader join"
                    % (c2.get("verdict"), c2.get("last")),
                }
            )
        elif len(stuck_tty) >= 5 and starv_ok:
            out.update(verdict="devfs_lookup_stall", confidence="medium", node=None)
            ev.append(
                {
                    "rule": "devfs_lookup_stall",
                    "files": ["08-sample-%d.txt" % p for p in stuck_tty],
                    "detail": "%d stuck ps/login with ttyname-class leaves"
                    % len(stuck_tty),
                }
            )
    # 3. kitty_rc_deaf
    kitty_rows = [p for p in procs if p.get("comm") == "kitty"]
    socks = max([p.get("sockets") or 0 for p in kitty_rows] or [0])
    if state.get("kitty_rc") == "dead" or socks >= 205:
        ev.append(
            {
                "rule": "kitty_rc_deaf",
                "files": ["05-lockwatch-state.json", "02-procscan.json"],
                "detail": "kitty_rc=%s sockets=%d" % (state.get("kitty_rc"), socks),
            }
        )
        if out["verdict"] == "none":
            out.update(verdict="kitty_rc_deaf", confidence="medium")
    # 4. idle_session_spin (CPU half only; transcript freshness not evaluated)
    p2 = read_json(first(bundle, "06-procscan2.json") or "/nonexistent") or {}
    prev = {(p["pid"], p.get("lstart")): p for p in procs}
    hot = []
    for p in p2.get("procs") or []:
        q = prev.get((p["pid"], p.get("lstart")))
        if (
            q
            and p.get("comm", "").startswith("claude")
            and p.get("cpu_s") is not None
            and q.get("cpu_s") is not None
        ):
            if (p["cpu_s"] - q["cpu_s"]) / 2.0 >= 0.10:
                hot.append(p["pid"])
    if len(hot) >= 10:
        ev.append(
            {
                "rule": "idle_session_spin",
                "files": ["02-procscan.json", "06-procscan2.json"],
                "detail": "%d claude processes >= 10%% CPU (transcript freshness not evaluated)"
                % len(hot),
            }
        )
        if out["verdict"] == "none":
            out.update(verdict="idle_session_spin", confidence="low", pids=hot[:20])
    # 5. proc_table_stall
    if (state.get("probes_stuck") or {}).get("procscan") and not wedged:
        ev.append(
            {
                "rule": "proc_table_stall",
                "files": ["05-lockwatch-state.json"],
                "detail": "stuck:procscan x%d with a healthy walk"
                % state["probes_stuck"]["procscan"],
            }
        )
        if out["verdict"] == "none":
            out.update(verdict="proc_table_stall", confidence="medium")
    # 6. cpu_starvation_31band
    if (
        out["verdict"] == "none"
        and (state.get("starvation_ms") or 0) >= 1000
        and not (state.get("stuck") or {}).get("n")
    ):
        ev.append(
            {
                "rule": "cpu_starvation_31band",
                "files": ["05-lockwatch-state.json"],
                "detail": "starvation_ms=%s, stuck census 0"
                % state.get("starvation_ms"),
            }
        )
        out.update(verdict="cpu_starvation_31band", confidence="low")
    out["summary"] = summarize(out)
    return out


def summarize(d):
    v = d["verdict"]
    if v == "devfs_poison":
        s = (
            "devfs_poison(%s): leader %s (pgid %s) is exiting/orphaned holding %s; holder %s (%s). Cure: %s"
            % (
                d["tty"],
                d["leader"],
                d["pgid"],
                d["tty"],
                d["holder"],
                d.get("holder_basis"),
                d["command"],
            )
        )
        if d.get("targets"):
            s += "; session tree to kill, opener first: %s (unkillable: %s)" % (
                " ".join(str(x) for x in d["targets"]),
                " ".join(str(x) for x in d.get("unkillable", [])),
            )
        if d.get("cause"):
            h = d["cause"][0]
            s += ". Cause: session %s (%s) ran: %s" % (
                h.get("session"),
                h.get("cwd"),
                h.get("command"),
            )
        return s
    if v == "none":
        return "no lockup signature matched"
    return "%s (%s confidence)" % (v, d.get("confidence"))


def write_diagnosis(bundle, d):
    tmp = os.path.join(bundle, "diagnosis.json.tmp")
    with open(tmp, "w") as fh:
        json.dump(d, fh, indent=1)
    os.rename(tmp, os.path.join(bundle, "diagnosis.json"))
    lines = [
        "# DIAGNOSIS",
        "",
        "**Verdict:** `%s` (%s confidence)"
        % (
            ("devfs_poison(%s)" % d["tty"])
            if d["verdict"] == "devfs_poison"
            else d["verdict"],
            d["confidence"],
        ),
        "",
        d["summary"],
        "",
    ]
    if d["verdict"] == "devfs_poison":
        lines += (
            ["## Cure (R17)", "", "```", d["command"], "```", ""]
            + ["- " + r for r in d["runbook"]]
            + [""]
        )
    if d["evidence"]:
        lines += ["## Evidence", ""]
        for e in d["evidence"]:
            lines.append(
                "- **%s** — %s (files: %s)"
                % (e["rule"], e["detail"], ", ".join(e["files"]))
            )
    with open(os.path.join(bundle, "DIAGNOSIS.md"), "w") as fh:
        fh.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------- capture helpers ----------
def suspects(bundle, tier, self_pid=None):
    procs, _ = load_procs(bundle)
    st = read_json(first(bundle, "05-lockwatch-state.json") or "/nonexistent") or {}
    ttymap = (
        read_json(first(bundle, "05-lockwatch-ttymap.json") or "/nonexistent") or {}
    )
    byp = {p["pid"]: p for p in procs}
    out = []

    def add(pid):
        if (
            pid
            and pid not in out
            and pid != self_pid
            and byp.get(pid, {}).get("stat") != "Z"
        ):
            out.append(pid)

    for L in rules.pty_leaders(procs, ttymap):
        if L["exiting"] or L["orphan"]:
            for p in procs:
                if p["pgid"] == L["pgid"] and p["pid"] != L["pid"]:
                    add(p["pid"])
    cap = 4
    if tier == "full":
        c = st.get("canary") or {}
        add(c.get("zsh_pid"))
        add(c.get("walk_pid"))
        for pid in ((st.get("stuck") or {}).get("pids") or [])[:1]:
            add(pid)
        for p in procs:
            if p.get("comm") == "kitty":
                add(p["pid"])
                break
        cap = 7
    p2 = read_json(first(bundle, "06-procscan2.json") or "/nonexistent") or {}
    prev = {(p["pid"], p.get("lstart")): p for p in procs}
    rates = []
    for p in p2.get("procs") or []:
        q = prev.get((p["pid"], p.get("lstart")))
        if (
            q
            and p.get("cpu_s") is not None
            and q.get("cpu_s") is not None
            and (p.get("comm", "").startswith("claude") or p.get("comm") == "node")
        ):
            rates.append((p["cpu_s"] - q["cpu_s"], p["pid"]))
    for _r, pid in sorted(rates, reverse=True):
        if len(out) >= cap:
            break
        add(pid)
    return out[:cap]


def manifest(bundle, tier, reason, boot, self_pid, missing):
    steps = {}
    try:
        with open(os.path.join(bundle, "steps.tsv")) as fh:
            next(fh, None)
            for line in fh:
                f = line.rstrip("\n").split("\t")
                if len(f) >= 5:
                    steps[f[0]] = {
                        "rc": int(f[1]),
                        "ms": int(f[2]),
                        "bytes": int(f[3] or 0),
                        "status": f[4],
                    }
    except (OSError, ValueError):
        pass
    procs, _ = load_procs(bundle)
    band = None
    for p in procs:
        if self_pid and p["pid"] == self_pid:
            band = p.get("pri")
    dj = read_json(os.path.join(bundle, "diagnosis.json")) or {}
    doc = {
        "v": 1,
        "tier": tier,
        "reason": reason,
        "boot": boot,
        "bundle": bundle,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "steps": steps,
        "missing": [m for m in (missing or "").split() if m],
        "band_pri": band,
        "full_ok": tier == "full" and bool(dj),
        "verdict": dj.get("verdict"),
        "abandoned": sorted(k for k, v in steps.items() if v["status"] == "ABANDON"),
    }
    tmp = os.path.join(bundle, "manifest.json.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, json.dumps(doc, indent=1).encode())
        try:
            import fcntl

            fcntl.fcntl(fd, fcntl.F_FULLFSYNC)
        except (OSError, AttributeError, ImportError):
            pass
    finally:
        os.close(fd)
    os.rename(tmp, os.path.join(bundle, "manifest.json"))
    return doc


BUNDLE_RE = re.compile(r"^\d{8}T\d{6}Z-[A-Za-z0-9_.-]+$")


def _du_mb(path):
    tot = 0
    for dp, _dn, fn in os.walk(path):
        for f in fn:
            try:
                tot += os.lstat(os.path.join(dp, f)).st_size
            except OSError:
                pass
    return tot / 1048576.0


def retention(root, keep=3, cap_mb=3072.0):
    """Keep the newest `keep` bundles plus every non-OK one; then delete oldest until under cap_mb
    (the newest `keep` are never deleted)."""
    try:
        names = sorted(
            n
            for n in os.listdir(root)
            if BUNDLE_RE.match(n) and os.path.isdir(os.path.join(root, n))
        )
    except OSError:
        return []
    newest = set(names[-keep:])
    removed = []
    for n in names:
        if n in newest:
            continue
        dj = read_json(os.path.join(root, n, "diagnosis.json")) or {}
        if dj.get("verdict") not in (None, "none"):
            continue
        shutil.rmtree(os.path.join(root, n), ignore_errors=True)
        removed.append(n)
    left = [n for n in names if n not in removed]
    sizes = {n: _du_mb(os.path.join(root, n)) for n in left}
    total = sum(sizes.values())
    for n in left:
        if total <= cap_mb:
            break
        if n in newest:
            continue
        shutil.rmtree(os.path.join(root, n), ignore_errors=True)
        removed.append(n)
        total -= sizes[n]
    return removed


def _opt(argv, name, default=None):
    if name in argv:
        i = argv.index(name)
        if i + 1 < len(argv):
            return argv[i + 1]
    return default


def main(argv):
    if not argv:
        sys.stderr.write(__doc__)
        return 2
    cmd = argv[0]
    b = _opt(argv, "--bundle")
    if cmd == "bundle":
        if not b:
            return 2
        roots = _opt(argv, "--roots")
        d = diagnose(
            b,
            _opt(argv, "--state"),
            cause="--no-cause" not in argv,
            roots=roots.split(":") if roots else None,
        )
        write_diagnosis(b, d)
        print(d["summary"])
        return 0
    if cmd == "suspects":
        sp = _opt(argv, "--self")
        print(
            " ".join(
                str(p)
                for p in suspects(
                    b, _opt(argv, "--tier", "snapshot"), int(sp) if sp else None
                )
            )
        )
        return 0
    if cmd == "manifest":
        sp = _opt(argv, "--self")
        manifest(
            b,
            _opt(argv, "--tier"),
            _opt(argv, "--reason"),
            _opt(argv, "--boot"),
            int(sp) if sp else None,
            _opt(argv, "--missing", ""),
        )
        return 0
    if cmd == "retention":
        removed = retention(
            _opt(argv, "--root"),
            int(_opt(argv, "--keep", "3")),
            float(_opt(argv, "--cap-mb", "3072")),
        )
        print("removed %d: %s" % (len(removed), " ".join(removed)))
        return 0
    sys.stderr.write("diagnose: unknown command %s\n" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
