#!/usr/bin/env python3
"""lr-select.py — consolidate resume candidates to ONE session per worktree.

WHY THIS EXISTS (incident 2026-07-21): a crash/limit recovery resurrected 14
sessions for a single project (2.76 GB RSS) because *session selection* had no
consolidation rule and no ceiling. The spawners are correct one-shot primitives
(`lr-fire-resume.sh`, `reso-resume-one`) — the gap was in every CALLER that
decides which sessions to resume. This is the shared decision point they all
consult, so the policy is written once and is testable.

Callers (see docs/plans/SESSION_SPRAWL_CONSOLIDATION_PLAN.md § Q2):
  1. skills/resume-sessions/SKILL.md   — model-judgment path (the incident path)
  2. scripts/limit-recover/lr-reset-poller.sh — launchd, autofire
  3. scripts/boot-resume.sh (mode=resume)     — post-reboot ghost resume
`/limit-recover`'s handoff moves exactly one lead session and needs no ceiling.

THE POLICY
  - Group candidates by resolved worktree (realpath of cwd).
  - Resume the ONE session per group that holds the most real state; LIST the
    rest, never spawn them. Exceeding one per worktree takes an explicit flag.
  - A total ceiling bounds any single recovery run.
  - NO SILENT CAPS: every dropped candidate is reported with its reason, so a
    truncated recovery can never read as a complete one.

"HOLDS REAL STATE" (plan § Q3). Uncommitted work is a property of the WORKTREE,
not the session — all N candidates in a group see the identical dirty tree, so it
cannot discriminate inside a group. It is a group-level annotation (marks the
group HOT, justifies an override), never a ranker. Within a group the winner is
picked by a lexicographic tuple:
    1. last real activity  — the transcript's INTERNAL max timestamp, never file
                             mtime (a bulk mirror touch gives many files the same
                             mtime, which is not activity)
    2. turn count          — a 2-turn stub loses to a 400-turn session
    3. session id          — deterministic final tiebreak (reproducible => testable)

Hard filters run BEFORE ranking and are not tiebreaks: already-running, teammate
sessions (lead-owned recovery), agent-*/wf_* internals, and a vanished cwd
(--allow-missing-cwd keeps the last of these for callers whose spawner can
recreate the worktree from its branch).

Losing is not one fact. A per-worktree loser has a winner covering its worktree;
a total-ceiling loser is alone in its own worktree and nothing else covers it.
Callers must read the reason and dispose accordingly — lr-reset-poller.sh retires
the former and DEFERS the latter to its next tick.

Usage:
  lr-select.py --candidate ACCT:SID:CWD [--candidate ...]   # caller-supplied set
  lr-select.py --scan [--recency-min N]                     # enumerate all stores
    [--max-per-worktree N]  (default 1)
    [--max-total N]         (default 4)
    [--json PATH] [--quiet] [--no-liveness] [--allow-missing-cwd]

Output:
  stdout  TSV winners:  acct <TAB> sid <TAB> cwd <TAB> branch
  stderr  the triage report (grouped candidate table) — P3
  --json  the full structured decision (winners + every drop with its reason)
Exit: 0 = decision made (an empty selection is still a decision) · 2 = usage error

Env (tests): LR_SELECT_PGREP_BIN · LR_SELECT_GIT_BIN · LR_SELECT_HOME
Read-only. Never spawns, never kills, never deletes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Account stores. `.claude` and `.claude-next` are the SAME account (mirror) — a
# session present in both is ONE `next` session, so `.claude` is not scanned.
STORES = [
    ("next", ".claude-next"),
    ("next2", ".claude-secondary"),
    ("next3", ".claude-tertiary"),
    ("next4", ".claude-quaternary"),
]

TS_RE = re.compile(r'"timestamp"\s*:\s*"([^"]+)"')
DEFAULT_MAX_PER_WORKTREE = 1
DEFAULT_MAX_TOTAL = 4


def home() -> Path:
    return Path(os.environ.get("LR_SELECT_HOME") or Path.home())


# ── transcript facts ──────────────────────────────────────────────────────────
def read_transcript(path: Path) -> dict:
    """Extract only what selection needs. Cheap: full JSON parse is reserved for
    the head (cwd/branch/teammate); timestamps and turns use substring/regex so a
    400k-token transcript stays fast."""
    cwd = ""
    branch = ""
    is_teammate = False
    last_ts = ""
    turns = 0
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh):
                if '"agentName"' in line and i < 40:
                    is_teammate = True
                if not cwd or not branch:
                    # Only the head needs a real parse — cwd/gitBranch are stamped early.
                    if i < 200 and ('"cwd"' in line or '"gitBranch"' in line):
                        try:
                            obj = json.loads(line)
                        except Exception:
                            obj = None
                        if isinstance(obj, dict):
                            cwd = cwd or (obj.get("cwd") or "")
                            branch = branch or (obj.get("gitBranch") or "")
                if '"type":"user"' in line or '"type":"assistant"' in line:
                    turns += 1
                m = TS_RE.search(line)
                if m and m.group(1) > last_ts:
                    last_ts = m.group(1)  # ISO-8601 UTC compares lexicographically
    except OSError:
        return {}
    return {
        "cwd": cwd,
        "branch": branch,
        "is_teammate": is_teammate,
        "last_activity": last_ts,
        "turns": turns,
    }


def is_running(sid: str) -> bool:
    """A resume already live for this sid — never re-fire over it."""
    pgrep = os.environ.get("LR_SELECT_PGREP_BIN", "pgrep")
    try:
        r = subprocess.run(
            [pgrep, "-f", f"resume {sid}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
        return r.returncode == 0
    except Exception:
        return False  # unreadable => don't block a legitimate resume


def dirty_count(cwd: str) -> int:
    """Uncommitted files in the worktree. Group-level annotation only (§ Q3)."""
    git = os.environ.get("LR_SELECT_GIT_BIN", "git")
    try:
        r = subprocess.run(
            [git, "-C", cwd, "status", "--porcelain"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if r.returncode != 0:
            return 0
        return len([ln for ln in r.stdout.splitlines() if ln.strip()])
    except Exception:
        return 0


# ── candidate collection ──────────────────────────────────────────────────────
def scan(recency_min: int) -> list[dict]:
    """Enumerate resumable sessions across the 4 stores (skill Phase 1)."""
    import time

    cutoff = time.time() - recency_min * 60 if recency_min > 0 else 0
    out = []
    for acct, store in STORES:
        proj = home() / store / "projects"
        if not proj.is_dir():
            continue
        for tx in proj.glob("*/*.jsonl"):
            # wf_* dirs are workflow internals; agent-*.jsonl are subagents.
            if tx.parent.name.startswith("wf_") or tx.name.startswith("agent-"):
                continue
            try:
                if cutoff and tx.stat().st_mtime < cutoff:
                    continue
            except OSError:
                continue
            out.append({"acct": acct, "sid": tx.stem, "cwd": "", "transcript": str(tx)})
    return out


def locate_transcript(acct: str, sid: str) -> str:
    store = dict((a, s) for a, s in STORES).get(acct)
    if not store:
        return ""
    proj = home() / store / "projects"
    if not proj.is_dir():
        return ""
    for tx in proj.glob(f"*/{sid}.jsonl"):
        return str(tx)
    return ""


# ── the decision ──────────────────────────────────────────────────────────────
def build(
    cands: list[dict], check_liveness: bool, allow_missing_cwd: bool = False
) -> tuple[list[dict], list[dict]]:
    """Enrich candidates and split into (eligible, filtered) with drop reasons."""
    eligible, filtered = [], []
    for c in cands:
        tx = c.get("transcript") or locate_transcript(c["acct"], c["sid"])
        rec = dict(c)
        rec["transcript"] = tx
        if not tx or not Path(tx).is_file():
            rec["reason"] = "no-transcript"
            filtered.append(rec)
            continue
        facts = read_transcript(Path(tx))
        rec.update(facts)
        if not rec.get("cwd"):
            rec["cwd"] = c.get("cwd") or ""
        if facts.get("is_teammate"):
            rec["reason"] = "teammate-session (lead-owned recovery)"
            filtered.append(rec)
            continue
        if not rec["cwd"]:
            rec["reason"] = "cwd-unknown"
            filtered.append(rec)
            continue
        # A reaped worktree is still resumable IF the caller's spawner can recreate it from the
        # branch (reso-resume-one and lr-fire-resume.sh both do, given --branch). Callers that
        # cannot must leave this off, or they would fire into a directory that is not there.
        if not allow_missing_cwd and not Path(rec["cwd"]).is_dir():
            rec["reason"] = "cwd-missing"
            filtered.append(rec)
            continue
        if check_liveness and is_running(rec["sid"]):
            rec["reason"] = "already-running"
            filtered.append(rec)
            continue
        rec["worktree"] = os.path.realpath(rec["cwd"])
        eligible.append(rec)
    return eligible, filtered


def select(cands, max_per_worktree, max_total, check_liveness, allow_missing_cwd=False):
    eligible, filtered = build(cands, check_liveness, allow_missing_cwd)

    groups: dict[str, list[dict]] = {}
    for e in eligible:
        groups.setdefault(e["worktree"], []).append(e)

    # Winner order within a group: last activity, then turns, then sid (§ Q3).
    for members in groups.values():
        members.sort(
            key=lambda r: (r.get("last_activity", ""), r.get("turns", 0), r["sid"]),
            reverse=True,
        )

    # Groups compete for the total ceiling by their own strongest member, so a
    # ceiling truncates the LEAST active worktrees, never an arbitrary set.
    ordered = sorted(
        groups.items(),
        key=lambda kv: (kv[1][0].get("last_activity", ""), kv[1][0].get("turns", 0)),
        reverse=True,
    )

    winners, dropped, report = [], [], []
    for wt, members in ordered:
        dirty = dirty_count(wt)
        take, over = members[:max_per_worktree], members[max_per_worktree:]
        picked = []
        for m in take:
            if len(winners) >= max_total:
                m["reason"] = f"total-ceiling ({max_total}) reached"
                dropped.append(m)
                continue
            m["dirty"] = dirty
            winners.append(m)
            picked.append(m)
        for m in over:
            m["reason"] = f"per-worktree cap ({max_per_worktree}) — not the winner"
            m["dirty"] = dirty
            dropped.append(m)
        report.append(
            {
                "worktree": wt,
                "n_candidates": len(members),
                "dirty": dirty,
                "winners": [m["sid"] for m in picked],
                "listed": [m["sid"] for m in members if m not in picked],
            }
        )
    return winners, dropped, filtered, report


# ── P3: the triage report ─────────────────────────────────────────────────────
def render(report, winners, dropped, filtered, max_per_worktree, max_total) -> str:
    L = []
    L.append("RESUME TRIAGE — one session per worktree (grouped candidate table)")
    L.append(f"  policy: max {max_per_worktree}/worktree · max {max_total} total")
    L.append("")
    if not report:
        L.append("  (no eligible candidates)")
    for g in report:
        hot = f"  ⚠ {g['dirty']} uncommitted" if g["dirty"] else ""
        L.append(f"  {g['worktree']}  — {g['n_candidates']} candidate(s){hot}")
        for sid in g["winners"]:
            w = next(w for w in winners if w["sid"] == sid)
            L.append(
                f"      ▶ RESUME  {sid[:8]}  [{w['acct']}]  "
                f"last={w.get('last_activity', '?')[:19]}  turns={w.get('turns', 0)}"
            )
        for sid in g["listed"]:
            d = next((x for x in dropped if x["sid"] == sid), None)
            if d:
                L.append(
                    f"        listed  {sid[:8]}  [{d['acct']}]  "
                    f"last={d.get('last_activity', '?')[:19]}  turns={d.get('turns', 0)}"
                    f"  — {d['reason']}"
                )
    if filtered:
        L.append("")
        L.append("  filtered (never eligible):")
        for f in filtered:
            L.append(f"        {f['sid'][:8]}  [{f.get('acct', '?')}]  — {f['reason']}")
    L.append("")
    n_listed = len(dropped)
    L.append(
        f"  => firing {len(winners)}; {n_listed} listed-not-spawned; {len(filtered)} filtered"
    )
    if n_listed:
        L.append(
            "     (listed sessions are NOT lost — resume one explicitly by sid, or"
        )
        L.append("      raise --max-per-worktree / --max-total to include them)")
    return "\n".join(L)


def main() -> int:
    p = argparse.ArgumentParser(
        add_help=True, description="consolidate resume candidates to one per worktree"
    )
    p.add_argument("--candidate", action="append", default=[], metavar="ACCT:SID:CWD")
    p.add_argument("--scan", action="store_true")
    p.add_argument("--recency-min", type=int, default=2880)
    p.add_argument("--max-per-worktree", type=int, default=DEFAULT_MAX_PER_WORKTREE)
    p.add_argument("--max-total", type=int, default=DEFAULT_MAX_TOTAL)
    p.add_argument("--json", metavar="PATH")
    p.add_argument(
        "--quiet", action="store_true", help="suppress the triage report on stderr"
    )
    p.add_argument(
        "--allow-missing-cwd",
        action="store_true",
        help="keep candidates whose worktree was reaped (the spawner recreates it from --branch)",
    )
    p.add_argument(
        "--no-liveness",
        action="store_true",
        help="skip the already-running pgrep check",
    )
    a = p.parse_args()

    if a.max_per_worktree < 1 or a.max_total < 1:
        print("lr-select: caps must be >= 1", file=sys.stderr)
        return 2

    cands = []
    for spec in a.candidate:
        parts = spec.split(":", 2)
        if len(parts) < 2 or not parts[0] or not parts[1]:
            print(
                f"lr-select: bad --candidate '{spec}' (want ACCT:SID[:CWD])",
                file=sys.stderr,
            )
            return 2
        cands.append(
            {
                "acct": parts[0],
                "sid": parts[1],
                "cwd": parts[2] if len(parts) > 2 else "",
            }
        )
    if a.scan:
        cands.extend(scan(a.recency_min))
    if not a.candidate and not a.scan:
        print("lr-select: need --candidate or --scan", file=sys.stderr)
        return 2

    # Dedup by sid (the .claude/.claude-next mirror yields one session twice).
    seen, uniq = set(), []
    for c in cands:
        if c["sid"] in seen:
            continue
        seen.add(c["sid"])
        uniq.append(c)

    winners, dropped, filtered, report = select(
        uniq, a.max_per_worktree, a.max_total, not a.no_liveness, a.allow_missing_cwd
    )

    for w in winners:
        print(f"{w['acct']}\t{w['sid']}\t{w['cwd']}\t{w.get('branch', '')}")

    text = render(report, winners, dropped, filtered, a.max_per_worktree, a.max_total)
    if not a.quiet:
        print(text, file=sys.stderr)

    if a.json:
        strip = lambda r: {k: v for k, v in r.items() if k != "transcript"}  # noqa: E731
        payload = {
            "policy": {
                "max_per_worktree": a.max_per_worktree,
                "max_total": a.max_total,
            },
            "winners": [strip(w) for w in winners],
            "listed": [strip(d) for d in dropped],
            "filtered": [strip(f) for f in filtered],
            "groups": report,
        }
        try:
            Path(a.json).parent.mkdir(parents=True, exist_ok=True)
            Path(a.json).write_text(json.dumps(payload, indent=2), encoding="utf-8")
        except OSError as e:
            print(f"lr-select: could not write {a.json}: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
