#!/usr/bin/env python3
"""THE WRITER: join backlog rows to their master's condition group.

WHY LINK AND NOT CLOSE (preserved verbatim from the 2026-08-09 original, because it
is still the reason this file may not be "improved" into a closer). The six masters
each drove their own DoD; none of them did 260 items of work. Closing an item
because a thematically-related master landed would be exactly the laundering the
worktree brief forbade ("do NOT mark an item done to reap a directory"). `link`
asserts something weaker and TRUE: these items share one condition, so cc-backlog's
CONDITION LEASE admits at most one live claim across the group. That is what stops N
dispatch slots going to N siblings of one root cause — the operator's original
complaint — without lying about completion.

── WHY THIS FILE IS TRACKED NOW (2026-08-12, W2 of BACKLOG_SELF_DRAINING) ──────────
It was not. It lived in docs/plans/backlog-consolidation-2026-08-09/ as an UNTRACKED
one-shot beside its own input artifacts, with no caller and no test — and it is the
only thing that had ever reduced this pile (113 links, 0 failures; its sibling
prune.py closed 161). One `git clean -f -d` and the machine's only working
consolidation writer was gone.

Tracking it alone would not have been enough, and the difference matters: a tracked
script with no caller is inert, which is the defect this repo keeps rediscovering.
So the INPUT was generalised. It used to read exactly one artifact —
`verdicts.json`, produced by one triage wave that will never run again in that
shape — which meant that after promotion its caller could only ever have been "the
next hand-driven triage", i.e. nobody. It now accepts a PLAN (id → condition) from a
file or stdin, so group.py (the standing semantic classifier) uses it as its writer,
and the legacy `--dir` path still replays a triage wave's verdicts.json unchanged.

ONE WRITER, so the conservation assertion lives here rather than in each caller.

CONSERVATION, MEASURED BOTH SIDES, and the id set is the load-bearing half. A `link`
record carries no status arm, so the live count, the open count AND the id set must
be identical across the write. A count alone reads unchanged after a sibling closes
one row and files another, which is exactly the window a fleet-wide append-only
ledger leaves open.

THREE POPULATIONS ARE SKIPPED, and the third one is a hazard rather than a nicety:
  * a row that is not live (done rows are history, not work);
  * a row that already carries a condition — never re-keyed. `cc-backlog link`
    refuses that without --force and this writer never passes it, deliberately:
    re-keying moves a row out of a group whose lease may be holding a live worker;
  * a row that is CLAIMED. The lease is symmetric — linking a HELD row into a group
    makes every sibling unclaimable for as long as the holder lives. Grouping exists
    to stop duplicate dispatch, not to freeze a subsystem behind one worker.

Dry by default; --run to execute.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from collections import Counter

LIVE = ("open", "blocked", "claimed")

# THE LEGACY TRIAGE MAP — triage slice → the master whose condition owns that root
# cause. Kept because it documents what the 2026-08-09 wave actually asserted, and
# because --dir replays it. Deliberately unmapped there: 'tail' is a mixed bag
# (misc/machine/docs/other-projects), and 'reso'/'docclf' belong to OTHER repos and
# have their own masters. Forcing a condition on them would assert a shared root
# cause the triage never found.
SLICE_TO_CONDITION = {
    "landgate": "master-convergence-deadlock",
    "testcorpus": "master-convergence-deadlock",
    "dispatch": "master-fire-gate",
    "panes": "master-fleet-footprint",
    "session": "master-stranded-work",
    "memhooks": "master-enforcing-store",
    "accounts": "master-account-facts",
}


def backlog_bin(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("CC_BACKLOG_BIN")
    if env:
        return env
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    local = os.path.join(here, "bin", "cc-backlog")
    return local if os.path.exists(local) else "cc-backlog"


def read_store(bin_path: str) -> list[dict]:
    """The FOLD, never the raw ledger — cc-backlog owns what a row's state is."""
    p = subprocess.run(
        [bin_path, "list", "--all", "--json"], capture_output=True, text=True
    )
    if p.returncode != 0:
        print(
            f"link.py: cc-backlog list failed rc={p.returncode}: "
            f"{p.stderr.strip()[:200]}",
            file=sys.stderr,
        )
        return []
    try:
        return json.loads(p.stdout or "[]")
    except json.JSONDecodeError as exc:
        print(f"link.py: cc-backlog list emitted non-JSON: {exc}", file=sys.stderr)
        return []


def census(items: list[dict]) -> tuple[int, int, tuple[str, ...]]:
    live = sum(1 for i in items if i.get("status") in LIVE)
    opn = sum(1 for i in items if i.get("status") == "open")
    return live, opn, tuple(sorted(i.get("id", "") for i in items))


def harmed(before: list[dict], after: list[dict], ids: list[str]) -> list[str]:
    """Which of OUR OWN rows lost their status (or vanished) across our links.

    THE SPAN OF THE ASSERTION MUST EQUAL ITS SUBJECT, and the whole-store version of this check was
    measured getting it wrong: the mechanical fold's first real apply wrote 46 links with 0 refusals
    and then reported `conservation=FAILED live 555→555 · open 330→331`, because a sibling session
    unblocked an unrelated row during the three minutes the apply took. This ledger belongs to the
    whole fleet and every session appends to it, so "the store moved" is the normal case, not a
    defect.

    The discriminator is structural rather than a tolerance: a `link` record carries NO status arm, so
    it cannot create, close, block or reopen anything. A changed count is therefore by construction
    not ours — while a row WE linked losing its status is the only damage we could possibly do
    (memory: assertion-span-must-equal-its-subject, alarm-polarity-and-attention-budget).
    """
    was = {i["id"]: i.get("status") for i in before if i.get("id")}
    now = {i["id"]: i.get("status") for i in after if i.get("id")}
    out = []
    for iid in ids:
        if iid not in now:
            out.append(f"{iid} {was.get(iid, '?')}→GONE")
        elif iid in was and now[iid] != was[iid]:
            out.append(f"{iid} {was[iid]}→{now[iid]}")
    return out


def read_plan(src: str) -> list[tuple[str, str]]:
    """A plan is `<id><whitespace><condition>` per line, or a JSON array of pairs.

    Two shapes because the two producers are different: group.py emits JSON (it
    already holds structured rows), and a human at a terminal writes lines. `#`
    comments and blank lines are skipped so a plan can be reviewed before it is run.
    """
    text = sys.stdin.read() if src == "-" else open(src).read()
    stripped = text.lstrip()
    if stripped.startswith("["):
        return [(str(a), str(b)) for a, b in json.loads(text)]
    out: list[tuple[str, str]] = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            print(
                f"link.py: ignoring malformed plan line: {line[:80]}", file=sys.stderr
            )
            continue
        out.append((parts[0], parts[1]))
    return out


def plan_from_triage(triage_dir: str) -> list[tuple[str, str]]:
    """Replay a triage wave: verdicts.json + SLICE_TO_CONDITION.

    KEEP and UPDATE survive into a link; PRUNE and MERGE were closed by prune.py in
    the same wave, so linking them would join dead rows into a live group.
    """
    path = os.path.join(triage_dir, "verdicts.json")
    if not os.path.exists(path):
        print(
            f"link.py: no verdicts.json in {triage_dir} — nothing to link",
            file=sys.stderr,
        )
        return []
    verdicts = json.load(open(path))
    out: list[tuple[str, str]] = []
    for iid, (slc, verdict) in verdicts.items():
        if verdict not in ("KEEP", "UPDATE"):
            continue
        cond = SLICE_TO_CONDITION.get(slc)
        if cond:
            out.append((iid, cond))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument(
        "--plan", help="plan file of '<id> <condition>' lines, or - for stdin"
    )
    src.add_argument(
        "--dir", help="a triage directory holding verdicts.json (legacy replay)"
    )
    ap.add_argument("--run", action="store_true", help="write the links (default: dry)")
    ap.add_argument("--bin", default=None, help="path to cc-backlog (tests)")
    ap.add_argument("--log", default=None, help="write a per-row log here")
    args = ap.parse_args()

    bin_path = backlog_bin(args.bin)
    wanted = read_plan(args.plan) if args.plan else plan_from_triage(args.dir)
    items = read_store(bin_path)
    if not items:
        print("link.py: empty or unreadable store — nothing to link", file=sys.stderr)
        return 0
    by_id = {i["id"]: i for i in items}

    plan: list[tuple[str, str]] = []
    skipped = Counter()
    for iid, cond in wanted:
        row = by_id.get(iid)
        if row is None:
            skipped["unknown-id"] += 1
            continue
        if row.get("status") not in LIVE:
            skipped["not-live"] += 1
            continue
        if row.get("condition"):
            skipped["already-conditioned"] += 1
            continue
        if row.get("status") == "claimed":
            skipped["claimed-would-freeze-group"] += 1
            continue
        plan.append((iid, cond))

    print(f"{len(plan)} row(s) to link  (of {len(wanted)} proposed)")
    for cond, n in sorted(Counter(c for _, c in plan).items()):
        print(f"  {n:4d} -> {cond}")
    for reason, n in sorted(skipped.items()):
        print(f"  skipped {n:4d}  {reason}")

    if not args.run:
        print("  … DRY RUN — nothing written. Pass --run to execute.")
        return 0

    before = census(items)
    ok = fail = 0
    written_ids: list[str] = []
    log = open(args.log, "w") if args.log else None
    try:
        for iid, cond in plan:
            p = subprocess.run(
                [bin_path, "link", iid, "--condition", cond],
                capture_output=True,
                text=True,
            )
            if p.returncode == 0:
                ok += 1
                written_ids.append(iid)
            else:
                fail += 1
                print(
                    f"verdict=refused    {iid} -> {cond}: rc={p.returncode} "
                    f"{p.stderr.strip()[:140]}",
                    file=sys.stderr,
                )
            if log:
                log.write(
                    f"{'OK  ' if p.returncode == 0 else 'FAIL'} {iid} -> {cond}"
                    f"{'' if p.returncode == 0 else ' :: ' + p.stderr.strip()[:160]}\n"
                )
    finally:
        if log:
            log.close()
    after_items = read_store(bin_path)
    after = census(after_items)
    print(f"linked={ok} refused={fail}")

    bad = harmed(items, after_items, written_ids)
    if bad:
        for line in bad:
            print(
                f"conservation=FAILED {line} across its own link record",
                file=sys.stderr,
            )
        print(
            f"conservation=FAILED live {before[0]}→{after[0]} · open {before[1]}→"
            f"{after[1]} · {len(bad)} row(s) this run linked lost their status; a link "
            f"has no status arm, so this is ours.",
            file=sys.stderr,
        )
        return 1
    if before == after:
        print(
            f"conservation=ok     live {before[0]}→{after[0]} · open {before[1]}→"
            f"{after[1]} · id set identical — no row created, closed or lost."
        )
        return 0
    # The store moved but not one of OUR rows did — see harmed()'s docstring for why that is a
    # sibling by construction rather than a tolerance we are granting ourselves.
    print(
        f"conservation=unknown live {before[0]}→{after[0]} · open {before[1]}→"
        f"{after[1]} · the store moved under the write, but every one of the {ok} row(s) "
        f"this run linked kept its status — a sibling wrote, we did not."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
