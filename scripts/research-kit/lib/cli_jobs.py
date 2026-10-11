"""cli_jobs.py — `cc-research job …`, the program's scheduled passes (REPORT.md §5.5, §8 item 12,
§10 item 4).

  cc-research job sweep|freshness|triage|drift|market|soak [--program P] [--json]

Run by launchd through scripts/research-kit/jobs/research-job.sh, never because a question was asked.
No --program: every registry program in certifying|certified or a Stage 9 build state (REPORT.md
§11; the sweep also takes a registered one with an open packet). Each pass appends records only and
prints one summary line per program; exit 1 if any program's pass failed (the others still run).

  sweep      gate_sweep.cmd_sweep: fired class-B defaults, overdue class-C conversions, known rows.
             Also run on a registered program whose decision records name a packet and are not yet
             ruled, so a default fires at its deadline before certification begins.
  freshness  a premise with a recheck_cmd whose expiry has passed (`expires`, else validated_at.ts +
             ttl_h), or with no probe within 24 h while the program is certifying (gate row 10), is
             re-run through probe_run as a probe closing it, from the records' git toplevel on a
             PATH that resolves the original probes' tools (RECHECK_ENV). Exit 0 holds, a clean
             exit 1 refutes; any other exit or a crash is NO verdict (kit.recheck_verdict): listed
             under FAILED, never flipped, challenged or carried, and re-run next pass as -r2, -r3 ….
             A holds/refuted verdict the result flips appends a drift challenge. Each premise is
             re-validated at most once per program, then carried ({id, carried: true}) and never
             re-checked. A recheck_cmd that is a prose note is not run; `<cmd> => <expected>`
             compares the command's trimmed stdout.
  triage     `cc-research triage --program P` as a subprocess (CC_RESEARCH_BIN overrides the binary).
  drift      git blob shas of CLAUDE.global.md, CLAUDE.global.slim.md, .claude/rules/*.md and
             docs/lessons/*.md under CC_RESEARCH_RULES_ROOT (else this repo) against the last run's
             <sealed>/drift-state.json. Acceptance rows whose rule_refs changed, or whose id is on an
             added line, are filed as one reality_moved change. The first run files nothing. Old text
             is kept content-addressed in <sealed>/drift-blobs/ so added lines can be found.
  market     frame.json populations_outside [{name, refresh_cmd, owner, cadence_days}]: once
             cadence_days have passed since <sealed>/market-state.json's last refresh, each stdout
             line not in census/<name>.json, nor parked before, is parked as a next-version candidate.
  soak       method v1.2, Stage 9 (REPORT.md §11 instrument 4, built gate row 24): one
             `built soak sample` per run over a program in build-certifying only, each acceptance
             check run the as-built way. Hourly, so every boundary row 24 names is crossed. A failing
             sample fails the pass and names the check; it becomes a finding by hand
             (`cc-research built finding add --source soak`).
"""

from __future__ import annotations

import argparse
import contextlib
import gzip
import hashlib
import io
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

import kit

REPO = Path(__file__).resolve().parents[3]
RESEARCH_ACTIVE = ("certifying", "certified")
ACTIVE = RESEARCH_ACTIVE + kit.STAGE9_STATES  # §11: the jobs visit a program in Stage 9 until close
SOAK_STATES = ("build-certifying",)  # §11: the soak runs between built-freeze and built-run
DAY = 86400.0
RULE_GLOBS = (
    "CLAUDE.global.md",
    "CLAUDE.global.slim.md",
    "CLAUDE.rules.slim.*.md",
    ".claude/rules/*.md",
    "docs/lessons/*.md",
)
NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
Pass = Callable[[str, str], Tuple[bool, str]]


def quiet(fn: Callable[..., Any], *args: Any) -> Tuple[Any, str]:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rv = fn(*args)
    return rv, buf.getvalue()


def next_id(path: Path, prefix: str) -> str:
    return kit.mint_id(path, prefix)  # shares the record verbs' mint lock and reservation


def open_packet(slug: str) -> bool:
    """A decision record names a cc-decide packet and is not yet ruled: the sweep has work there.

    The program's packets are the ones its decision events name, as gate_sweep finds them. Records
    that cannot be read answer True, so the sweep runs there and reports the failure."""
    try:
        decisions = kit.fold(kit.read_jsonl(kit.records_dir(slug) / "decisions.jsonl"))
    except kit.KitError:
        return True
    for d in decisions.values():
        if (d.get("packet") or {}).get("id") and d.get("status") != "ruled":
            return True
    return False


def scanned(job: str) -> str:
    if job == "soak":
        return "|".join(SOAK_STATES)
    return (
        "|".join(RESEARCH_ACTIVE)
        + (", nor registered with an open packet" if job == "sweep" else "")
        + ", nor in "
        + "|".join(kit.STAGE9_STATES)
    )


def programs(only: Optional[str], job: str = "") -> List[Tuple[str, str]]:
    if only:
        prog = kit.registry_get(kit.check_slug(only)) or {}
        return [(only, str(prog.get("state", "unregistered")))]
    out: List[Tuple[str, str]] = []
    for p in kit.registry_load()["programs"]:
        slug, state = str(p["slug"]), str(p.get("state"))
        if job == "soak":
            if state in SOAK_STATES:
                out.append((slug, state))
            continue
        # the sweep alone also reaches a registered program: its class-B defaults fire on a
        # deadline, whether or not certification has begun (audit 2026-10-04, item 8)
        if state in ACTIVE or (
            job == "sweep" and state == "registered" and open_packet(slug)
        ):
            out.append((slug, state))
    return out


# ── sweep ───────────────────────────────────────────────────────────────────────────────────────


def job_sweep(slug: str, state: str) -> Tuple[bool, str]:
    from gate_sweep import cmd_sweep

    rc, out = quiet(cmd_sweep, argparse.Namespace(program=slug))
    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    return rc == 0, f"{len(lines)} action(s)" + (
        ": " + "; ".join(lines) if lines else ""
    )


# ── freshness ───────────────────────────────────────────────────────────────────────────────────


def expiry(p: Dict[str, Any]) -> Optional[float]:
    if p.get("expires"):
        return kit.parse_iso(p["expires"])
    ts = (p.get("validated_at") or {}).get("ts")
    if ts and p.get("ttl_h") is not None:
        return kit.parse_iso(ts) + float(p["ttl_h"]) * 3600
    return None


# The re-check environment (env id RECHECK_ENV): /bin/bash 3.2 as launchd runs it, from the git
# toplevel of the program's records (recheck_cmds are written relative to it), on a PATH that
# resolves the tools the original probes used. launchd's own PATH and cwd "/" made 80 of 93
# re-checks crash on 2026-10-11 (gh, python3 packages, relative paths).
RECHECK_ENV = "launchd-bash32-records"
RECHECK_PATH_HEAD = ("/opt/homebrew/bin", "/usr/local/bin", "{HOME}/.local/bin")
# A recheck_cmd that opens with a prose label ("unmeasured: …", "before filing: …") is a note, not
# a command: run, it redirects into stray files in the worktree (`n>=5` makes a file "=5").
PROSE_RE = re.compile(r"^\s*[A-Za-z][A-Za-z ,-]*:\s")
# `<cmd>  => <expected>`: the command's trimmed stdout must equal <expected>. Run as one shell line,
# `=> true` would redirect into a file "true" and read exit 0 whatever the answer.
ARROW = " => "
ARROW_SH = (
    'out=$(eval "$1"); rc=$?; printf "%s\\n" "$out"; [ "$rc" -eq 0 ] || exit "$rc"; '
    "got=$(printf '%s' \"$out\" | awk '{$1=$1};1'); "
    '[ "$got" = "$2" ] && exit 0; echo "expected $2, read $got"; exit 1'
)


def recheck_argv(cmd: str) -> List[str]:
    if ARROW in cmd:
        left, _, want = cmd.rpartition(ARROW)
        return ["/bin/bash", "-c", ARROW_SH, "/bin/bash", left.strip(), want.strip()]
    return ["/bin/bash", "-c", cmd]


def recheck_env() -> Dict[str, str]:
    home = os.environ.get("HOME", "")
    seen: List[str] = []
    head = [
        d.replace("{HOME}", home)
        for d in RECHECK_PATH_HEAD
        if home or "{HOME}" not in d
    ]
    for d in head + os.environ.get("PATH", "").split(":") + ["/usr/bin", "/bin"]:
        if d and d not in seen:
            seen.append(d)
    return dict(os.environ, PATH=":".join(seen))


def recheck_cwd(rec: Path) -> str:
    try:
        p = subprocess.run(
            ["git", "-C", str(rec), "rev-parse", "--show-toplevel"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return str(rec)
    return p.stdout.strip() if p.returncode == 0 and p.stdout.strip() else str(rec)


def job_freshness(slug: str, state: str) -> Tuple[bool, str]:
    import probe_run

    rec = kit.records_dir(slug)
    prem = kit.fold(kit.read_jsonl(rec / "premises.jsonl"))
    probes = kit.fold(kit.read_jsonl(rec / "probes.jsonl"))
    now = kit.parse_iso(kit.now_iso())
    cwd, env = recheck_cwd(rec), recheck_env()
    done: List[str] = []
    verdicts: Dict[str, int] = {"holds": 0, "refuted": 0}
    flipped: List[str] = []
    failed: List[str] = []
    for pid, p in sorted(prem.items()):
        if not p.get("recheck_cmd") or p.get("carried"):
            continue
        exp = expiry(p)
        ats = [  # a no-verdict run is not a re-check (gate row 10 reads probes the same way)
            kit.parse_iso(x["at"])
            for x in probes.values()
            if pid in (x.get("closes") or [])
            and x.get("at")
            and kit.probe_recheck_verdict(rec, x) is not None
        ]
        stale = state == "certifying" and (not ats or now - max(ats) > DAY)
        if not (stale or (exp is not None and exp <= now)):
            continue
        rcmd = str(p["recheck_cmd"])
        if PROSE_RE.match(rcmd):
            failed.append(f"{pid}: recheck_cmd is a note, not a command ({rcmd[:60]}…)")
            continue
        # P-fresh-<pid>, then -r2, -r3 … after a run that gave no verdict. A run WITH a verdict but
        # no carry (a crash between the probe and the carry) is re-used, not re-run.
        tries = [f"P-fresh-{pid}"]
        while tries[-1] in probes:
            tries.append(f"P-fresh-{pid}-r{len(tries) + 1}")
        last_run = tries[-2] if len(tries) > 1 else None
        if last_run and kit.probe_recheck_verdict(rec, probes[last_run]) is not None:
            probe_id = last_run
        else:
            probe_id = tries[-1]
            ns = argparse.Namespace(
                program=slug,
                id=probe_id,
                kind="live-read",
                closes=[pid],
                n=1,
                load_control=False,
                env_id=RECHECK_ENV,
                negative_control=None,
                no_negative_control=(
                    "scheduled freshness re-check: re-runs the premise's own "
                    "recheck_cmd, whose controls belong to its original probe"
                ),
                falsifier=None,
                timeout=300,
                mutates_live=False,
                cmd=recheck_argv(rcmd),
                cwd=cwd,
                env=env,
            )
            try:
                quiet(probe_run.cmd_run, ns)
            except kit.KitError as e:
                failed.append(f"{pid}: {e}")
                continue
            probes = kit.fold(kit.read_jsonl(rec / "probes.jsonl"))
        verdict = kit.probe_recheck_verdict(rec, probes[probe_id])
        if verdict is None:  # the environment failed: no flip, no challenge, no carry
            err = rec / "evidence" / probe_id / "stderr"
            stderr = err.read_text(errors="replace") if err.is_file() else ""
            why = kit.recheck_why(probes[probe_id].get("exit"), stderr)
            failed.append(f"{pid}: {probe_id} gave no verdict ({why})")
            continue
        verdicts[verdict] += 1
        last = p.get("verdict")
        if last in ("holds", "refuted") and verdict != last:
            ch = rec / "challenges.jsonl"
            kit.append_jsonl(
                ch,
                {
                    "id": next_id(ch, "CH"),
                    "raised_by": "sweep",
                    "kind": "drift",
                    "premise": pid,
                    "names": [pid],
                    "evidence_date": kit.now_iso(),
                    "triage": "pending",
                    "action": f"re-check {probe_id} reads {verdict}, the premise says {last}",
                },
            )
            flipped.append(pid)
        kit.append_jsonl(
            rec / "premises.jsonl",
            {
                "id": pid,
                "carried": True,
                "rechecked_by": probe_id,
                "recheck_verdict": verdict,
            },
        )
        done.append(pid)
    msg = (
        f"re-checked {len(done)} (holds {verdicts['holds']}, refuted {verdicts['refuted']}), "
        f"flipped {len(flipped)}"
        + (f" ({', '.join(flipped)})" if flipped else "")
        + (f"; FAILED {len(failed)}: {'; '.join(failed)}" if failed else "")
    )
    return not failed, msg


# ── triage ──────────────────────────────────────────────────────────────────────────────────────


def job_triage(slug: str, state: str) -> Tuple[bool, str]:
    exe = os.environ.get("CC_RESEARCH_BIN") or str(REPO / "bin" / "cc-research")
    try:
        p = subprocess.run(
            [exe, "triage", "--program", slug],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=1800,
        )
    except subprocess.TimeoutExpired:
        return False, "cc-research triage timed out after 1800 s"
    tail = ((p.stdout.strip() or p.stderr.strip()).splitlines() or [""])[-1]
    return p.returncode == 0, f"cc-research triage exit {p.returncode}" + (
        f": {tail}" if tail else ""
    )


# ── drift ───────────────────────────────────────────────────────────────────────────────────────


def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def rule_files(root: Path) -> Dict[str, bytes]:
    out: Dict[str, bytes] = {}
    for g in RULE_GLOBS:
        for f in sorted(root.glob(g)):
            if f.is_file():
                out[f.relative_to(root).as_posix()] = f.read_bytes()
    return out


def job_drift(slug: str, state: str) -> Tuple[bool, str]:
    root = Path(os.environ.get("CC_RESEARCH_RULES_ROOT") or REPO)
    sealed = kit.sealed_dir(slug, create=True)
    state_p = sealed / "drift-state.json"
    blobs = sealed / "drift-blobs"
    files = rule_files(root)
    cur = {k: blob_sha(v) for k, v in files.items()}
    blobs.mkdir(exist_ok=True)
    for k, data in files.items():
        b = blobs / cur[k]
        if not b.exists():
            b.write_bytes(gzip.compress(data))
    prev = kit.read_json(state_p)
    if prev is None:
        kit.write_json_atomic(state_p, {"files": cur, "at": kit.now_iso()})
        return True, f"baseline of {len(cur)} file(s) recorded, nothing filed"
    old: Dict[str, str] = prev.get("files") or {}
    changed = sorted(k for k in set(cur) | set(old) if cur.get(k) != old.get(k))
    added: List[str] = []
    for k in changed:
        if k not in files:
            continue
        ob = blobs / old[k] if old.get(k) else None
        seen: Set[str] = set()
        if ob is not None and ob.exists():
            seen = set(
                gzip.decompress(ob.read_bytes()).decode("utf-8", "replace").splitlines()
            )
        added += [
            ln
            for ln in files[k].decode("utf-8", "replace").splitlines()
            if ln not in seen
        ]
    rec = kit.records_dir(slug)
    affected: List[str] = []
    for r in (kit.read_json(rec / "acceptance.json", {}) or {}).get("rows") or []:
        rid = str(r.get("id") or "")
        refs = {os.path.normpath(str(x)) for x in r.get("rule_refs") or []}
        id_re = re.compile(rf"(?<![\w-]){re.escape(rid)}(?!\w)")
        if rid and (refs & set(changed) or any(id_re.search(ln) for ln in added)):
            affected.append(rid)
    if affected:
        ch = rec / "changes.jsonl"
        kit.append_jsonl(
            ch,
            {
                "id": next_id(ch, "CR"),
                "cause": "reality_moved",
                "source": "rule-drift",
                "affected_rows": affected,
                "files": changed,
                "justification": f"rule or lesson text changed: {', '.join(changed)}",
            },
        )
    kit.write_json_atomic(state_p, {"files": cur, "at": kit.now_iso()})
    return (
        True,
        f"{len(changed)} file(s) changed, rows affected: {', '.join(affected) or 'none'}",
    )


# ── market ──────────────────────────────────────────────────────────────────────────────────────


def job_market(slug: str, state: str) -> Tuple[bool, str]:
    rec = kit.records_dir(slug)
    pops = (kit.read_json(rec / "frame.json", {}) or {}).get(
        "populations_outside"
    ) or []
    if not pops:
        return True, "no outside populations"
    state_p = kit.sealed_dir(slug, create=True) / "market-state.json"
    st: Dict[str, Any] = kit.read_json(state_p, {}) or {}
    now = kit.parse_iso(kit.now_iso())
    ch = rec / "changes.jsonl"
    ok = True
    msgs: List[str] = []
    for pop in pops:
        name, cmd, cad = (
            pop.get("name"),
            pop.get("refresh_cmd"),
            pop.get("cadence_days"),
        )
        if not (
            isinstance(name, str) and NAME_RE.match(name) and cmd and cad is not None
        ):
            ok = False
            msgs.append(f"malformed population {pop!r}")
            continue
        last = (st.get(name) or {}).get("last_refresh")
        if last and now - kit.parse_iso(last) < float(cad) * DAY:
            msgs.append(f"{name} not due")
            continue
        try:
            p = subprocess.run(
                ["/bin/bash", "-c", str(cmd)],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=600,
            )
        except subprocess.TimeoutExpired:
            ok = False
            msgs.append(f"{name} refresh timed out")
            continue
        if p.returncode != 0:
            ok = False
            msgs.append(f"{name} refresh exit {p.returncode}")
            continue
        members = (kit.read_json(rec / "census" / f"{name}.json", {}) or {}).get(
            "members"
        ) or []
        seen = {str(m.get("id")) if isinstance(m, dict) else str(m) for m in members}
        seen |= {
            str(c.get("justification"))
            for c in kit.read_jsonl(ch)
            if c.get("source") == "market" and c.get("population") == name
        }
        new: List[str] = []
        for item in (ln.strip() for ln in p.stdout.splitlines()):
            if item and item not in seen and item not in new:
                new.append(item)
        for item in new:
            kit.append_jsonl(
                ch,
                {
                    "id": next_id(ch, "CR"),
                    "cause": "reality_moved",
                    "status": "parked",
                    "source": "market",
                    "population": name,
                    "owner": pop.get("owner"),
                    "justification": item,
                    "affected_rows": [],
                },
            )
        st[name] = {"last_refresh": kit.now_iso(), "parked": len(new)}
        kit.write_json_atomic(state_p, st)
        msgs.append(f"{name} parked {len(new)}")
    return ok, "; ".join(msgs)


# ── soak (method v1.2, REPORT.md §11) ──────────────────────────────────────────────────────────


def job_soak(slug: str, state: str) -> Tuple[bool, str]:
    import built
    import gate

    if state not in SOAK_STATES:
        return False, (
            f"{state}, not in {'|'.join(SOAK_STATES)}: the soak samples only between "
            "`gate.sh built-freeze` and `gate.sh built-run`"
        )
    samples = built.soak_sample(gate.make_ctx(slug))
    bad = [str(s["check"]) for s in samples if s["exit"] != 0]
    if bad:
        return False, (
            f"{len(samples)} sample(s), failing: {', '.join(bad)} — a failing sample is a finding: "
            "cc-research built finding add --source soak"
        )
    return True, f"{len(samples)} sample(s), all pass"


PASSES: Dict[str, Pass] = {
    "sweep": job_sweep,
    "freshness": job_freshness,
    "triage": job_triage,
    "drift": job_drift,
    "market": job_market,
    "soak": job_soak,
}


def cmd_job(a: argparse.Namespace) -> int:
    fn = PASSES[a.job]
    results: List[Dict[str, Any]] = []
    for slug, state in programs(a.program, a.job):
        try:
            ok, msg = fn(slug, state)
        except kit.KitError as e:
            ok, msg = False, str(e)
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as e:
            ok, msg = False, f"{type(e).__name__}: {e}"
        results.append({"program": slug, "state": state, "ok": ok, "summary": msg})
        if not a.json:
            print(f"job {a.job} {slug}: {'ok' if ok else 'FAILED'} — {msg}", flush=True)
    if a.json:
        print(json.dumps({"job": a.job, "programs": results}, sort_keys=True))
    elif not results:
        print(f"job {a.job}: no program in {scanned(a.job)}")
    return 0 if all(r["ok"] for r in results) else 1


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("job", help="one scheduled pass (launchd runs these)")
    p.add_argument("job", choices=tuple(PASSES))
    p.add_argument("--program")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_job)
