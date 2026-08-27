#!/usr/bin/env python3
"""cloud-inbox — read the questions cloud sessions have been asking into a field with no reader.

THE DEFECT THIS EXISTS FOR (measured 2026-08-27, 262 live sessions probed read-only).

The cloud drain lane was one-way. Work went out; nothing came back. The board read
151 NOT-STARTED / 107 STALLED / 14 ABANDONED — 86% of 315 active declarations — and the
obvious reading was that the lane was broken at creation, auth, or quota. All three are
REFUTED: 262/262 control-plane GETs returned 200, every record `status:"active"`,
`environment_kind:"anthropic_cloud"`, `accepted:true`, evenly spread across all four
accounts, and `refusal-route.jsonl` holds zero creation refusals.

What the control plane actually said: **222 of 262 (85%) had `post_turn_summary.status_category
== "need_input"`.** They were not dead. They had finished a turn and asked a question. A
tree-wide grep for `post_turn_summary|status_category|needs_action|requires_action` over
`bin/ scripts/ hooks/` returned exactly ONE hit, and it was a comment. `--verify` printed six
fields and dropped the summary; `cloud-return.sh` reads `.worker_status` and nothing else.

Verbatim from one session the board filed as NOT-STARTED:

    status_category  need_input
    status_detail    fix verified & tests green; gate issues block ship
    needs_action     1. Land it via desk box (gate issues: lint detector, mawk interval);
                     2. Record item b60eb29e97dd done

That session had SUCCEEDED. It is filed as never-started because `cc-cloud classify()` derives
its state from git-ref absence alone, and a VM that finished without pushing has no ref. The
label sent 83% of triage effort at a boot problem that does not exist, while 229 commits
stranded across 164 branches at +68/day.

WHY THIS IS A READER AND NOT AN ACTUATOR — the line is deliberate and it is a security line.

13 of the 222 `needs_action` strings parse as runnable shell commands. Running them is
executing a command chosen by a remote VM, on this box, unattended. That is remote code
execution wearing a helpful shape, and no amount of "but we fired that session ourselves"
changes who composed the string. **This tool never executes anything it reads.** It CLASSIFIES
and PRINTS, so a human or a session with the operator's judgement decides. An actuator, if one
is ever built, needs its own review, its own allowlist, and its own consent gate — not a flag
here.

ONE PROJECTION, ONE READER. Every field comes from `cloud-create-api.py --verify`, which this
shells out to per session. It is one subprocess per id rather than an in-process import, and
that is the point: a second decoding of the control plane is a second source of truth that
cannot learn the API changed (memory: sibling-auditors-must-share-the-state-model). If
`--verify` stops emitting a field, this goes blind LOUDLY (`unreadable`) rather than quietly
reporting a healthy-looking nothing.

ABSTENTION IS A STATE, NOT A ZERO. A session whose probe fails — timeout, non-zero rc,
unparseable stdout — is reported `unreadable` with its reason, never silently dropped and never
folded into "nothing to answer". An empty inbox must mean "asked and nobody is blocked", which
is a different fact from "could not ask" (memory: lookup-miss-is-not-absence, and
suppressed-stderr-turns-a-failed-command-into-a-zero).

Exit codes:  0 = ran, whatever it found (an empty inbox is not an error)
             2 = usage
             3 = the declaration store is unreadable — cannot even enumerate
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# The probe binary is an env seam so the suite can stub the control plane. Unstubbed, a test would
# reach the operator's real accounts over the network — slow, flaky, and it would read a live fleet
# whose contents no assertion can pin.
VERIFY = os.environ.get("CC_CLOUD_VERIFY_BIN") or os.path.join(
    HERE, "cloud-create-api.py"
)
STATE_DEFAULT = os.path.join(os.path.expanduser("~"), ".claude", "autonomy", "cloud")

# The categories the control plane emits that mean "this session is waiting on us". Anything not
# listed is reported under its own name rather than bucketed — an unmodelled category is news, and
# collapsing it into a known one is how a new upstream state becomes invisible
# (memory: new-enum-member-falls-into-fail-closed-default).
BLOCKING = {"need_input", "review_ready"}

# A needs_action is RUNNABLE only if it looks like our own tooling being invoked. Deliberately a
# narrow allowlist of PREFIXES rather than "does it contain a shell metacharacter": the question is
# not "could a shell run this" but "is this recognisably one of our verbs", and a broad matcher on a
# remote-authored string classifies attacker-chosen text as friendly
# (memory: denylist-enumerates-spellings-not-the-class). Classification only — nothing is executed.
RUNNABLE_RE = re.compile(
    r"^\s*(?:\d+[.)]\s*)?(cc-backlog|cc-cloud|cc-notify|cc-custody|bash scripts/|git )\b"
)


def read_decl(path: str) -> dict:
    """Parse a `key=value` declaration file. Unknown keys are kept; a malformed line is skipped."""
    out: dict = {}
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if "=" not in line:
                    continue
                k, _, v = line.partition("=")
                out[k.strip()] = v
        return out
    except OSError:
        return {}


def active_ids(state: str) -> list[tuple[str, dict]]:
    """Every declared, non-retired session, as (id, decl). Mirrors cc-cloud's own ids()."""
    rows = []
    for name in sorted(os.listdir(state)):
        if not name.endswith(".decl"):
            continue
        sid = name[: -len(".decl")]
        if os.path.exists(os.path.join(state, sid + ".retired")):
            continue
        rows.append((sid, read_decl(os.path.join(state, name))))
    return rows


def probe(sid: str, account: str, timeout: int) -> dict:
    """One control-plane read, through --verify. Never raises; failure is a reported state."""
    if not account:
        return {
            "id": sid,
            "state": "unreadable",
            "why": "declaration carries no account=",
        }
    try:
        p = subprocess.run(
            [sys.executable, VERIFY, "--account", account, "--verify", sid],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {
            "id": sid,
            "state": "unreadable",
            "why": f"probe timed out after {timeout}s",
        }
    except OSError as e:
        return {"id": sid, "state": "unreadable", "why": f"probe could not run: {e}"}
    # rc 5 is --verify's "record read, but the acceptance pair is wrong". The RECORD is still there
    # and its summary is still the thing we came for, so rc 5 is parsed rather than discarded; only
    # an unparseable stdout is unreadable. Treating a non-zero rc as absence is how a failed command
    # renders as a clean zero.
    try:
        rec = json.loads(p.stdout or "")
    except (ValueError, TypeError):
        why = (p.stderr or p.stdout or "").strip().splitlines()
        return {
            "id": sid,
            "state": "unreadable",
            "why": f"rc={p.returncode}; {why[-1][:160] if why else 'no output'}",
        }
    summary = rec.get("summary") or {}
    return {
        "id": sid,
        "state": "read",
        "accepted": rec.get("accepted"),
        "status_bucket": rec.get("status_bucket"),
        "worker_status": rec.get("worker_status"),
        "category": summary.get("status_category"),
        "detail": summary.get("status_detail"),
        "needs_action": summary.get("needs_action"),
        "requires_action": rec.get("requires_action") or [],
    }


def classify_ask(row: dict) -> str:
    """PERMISSION | RUNNABLE | PROSE | NONE — what KIND of answer this session is waiting for."""
    if row.get("requires_action"):
        return "PERMISSION"
    action = (row.get("needs_action") or "").strip()
    if not action:
        return "NONE"
    return "RUNNABLE" if RUNNABLE_RE.match(action) else "PROSE"


def main() -> int:
    ap = argparse.ArgumentParser(prog="cloud-inbox", description=__doc__.split("\n")[0])
    ap.add_argument("--state", default=os.environ.get("CC_CLOUD_STATE", STATE_DEFAULT))
    ap.add_argument("--json", action="store_true", help="one JSON object per line")
    ap.add_argument(
        "--limit", type=int, default=0, help="probe at most N sessions (0 = all)"
    )
    ap.add_argument("--timeout", type=int, default=45, help="per-probe seconds")
    ap.add_argument("--jobs", type=int, default=6, help="concurrent probes")
    ap.add_argument(
        "--item", default="", help="only the session declared for this backlog id"
    )
    ap.add_argument(
        "--all",
        action="store_true",
        help="report every session, not only the blocked ones",
    )
    args = ap.parse_args()

    if not os.path.isdir(args.state):
        print(f"cloud-inbox: no declaration store at {args.state}", file=sys.stderr)
        return 3
    try:
        rows = active_ids(args.state)
    except OSError as e:
        print(f"cloud-inbox: cannot enumerate {args.state}: {e}", file=sys.stderr)
        return 3

    if args.item:
        rows = [(s, d) for s, d in rows if d.get("item") == args.item]
    # THE BOUND IS ANNOUNCED, NEVER SILENT. A truncated sweep that prints like a complete one reads
    # as "everything is fine" (CLAUDE.md § no silent caps), so say what was dropped and why.
    total = len(rows)
    if args.limit and total > args.limit:
        rows = rows[: args.limit]
        print(
            f"cloud-inbox: probing {len(rows)} of {total} active session(s) — "
            f"--limit {args.limit}; the rest were NOT read and are not reported as clear.",
            file=sys.stderr,
        )

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futs = {
            pool.submit(probe, sid, decl.get("account", ""), args.timeout): (sid, decl)
            for sid, decl in rows
        }
        for fut in concurrent.futures.as_completed(futs):
            sid, decl = futs[fut]
            row = fut.result()
            row["item"] = decl.get("item", "")
            row["branch"] = decl.get("branch", "")
            row["url"] = decl.get("url", "")
            row["ask"] = (
                classify_ask(row) if row.get("state") == "read" else "UNREADABLE"
            )
            results.append(row)

    results.sort(key=lambda r: (r["ask"], r["id"]))
    shown = [
        r
        for r in results
        if args.all or r["ask"] == "UNREADABLE" or r.get("category") in BLOCKING
    ]

    if args.json:
        for r in shown:
            print(json.dumps(r, sort_keys=True))
    else:
        for r in shown:
            if r["ask"] == "UNREADABLE":
                print(f"UNREADABLE  {r['id']}  {r.get('why', '')}")
                continue
            head = f"{r['ask']:<10}  {r['id']}  item={r['item'] or '-'}  cat={r.get('category')}"
            print(head)
            if r.get("detail"):
                print(f"            detail: {r['detail']}")
            if r.get("needs_action"):
                print(f"            asks:   {r['needs_action']}")
            if r.get("requires_action"):
                print(f"            perm:   {r['requires_action']}")
            if r.get("url"):
                print(f"            open:   {r['url']}")

    counts: dict = {}
    for r in results:
        counts[r["ask"]] = counts.get(r["ask"], 0) + 1
    # The tally goes to stderr so a `--json` consumer gets clean stdout, and it names the READ
    # population explicitly: "0 blocked" over 3 probed sessions is a different claim from "0 blocked"
    # over 315 (memory: zero-claim-must-name-its-excluded-strata).
    print(
        "cloud-inbox: probed "
        + str(len(results))
        + " of "
        + str(total)
        + " active session(s) — "
        + (", ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "nothing read"),
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
