#!/usr/bin/env python3
"""cloud-answer — route a cloud session's unanswered question to something that can ANSWER it.

THE DEFECT THIS EXISTS FOR (cc-backlog cd561ed37e8e; re-measured live 2026-09-10).

`scripts/cloud-inbox.py` gave the lane a READER: 222 of 262 live sessions had ended a turn with
`status_category == "need_input"` and a tree-wide grep for that field returned one hit, a comment.
Reading was the whole of it. Its own docstring says so: "An actuator, if one is ever built, needs
its own review, its own allowlist, and its own consent gate — not a flag here." This is that
actuator, in a separate file, and the sentence above is its specification.

The 2026-08-27 cohort is gone (677 of 688 declarations retired), and the GAP is not: measured on
the live store 2026-09-10, **3 of the 5 readable active sessions sit in `need_input`**, all four
declarations naming ONE backlog item, all four PUSHED and quiet for five days, every one asking in
words for its branch to be collected. Nothing read the words. The item was re-dispatched EIGHT
times between 09-01 and 09-05 (claim→block→unblock ×8), burning a fresh cloud session each time
onto work five earlier sessions had already finished. That loop is what an unread question costs.

WHY THE RETURN LANE DID NOT ALREADY COLLECT THEM, since it is the obvious objection. All four are
inside `cloud-return.sh --sweep`'s population (`notify_back` + `custody` are set) and all four meet
its three-fact RETURN-READY conjunction. The pass never reaches them: `cloud-return-lane.sh` runs
the return pass under a 5,400 s bound and ONE land — via cloud-reconcile → desk-land → ship-land,
legitimately 700-3,900 s under land-lock contention — consumes it, so every tick since 09-04 exits
`rc=137 … cut by the lane bound` with the tail unread (memory: inner-bound-over-outer-bound starves
the tail). `--id` is the single-session path that does NOT queue behind that sweep, which is exactly
what these sessions are asking for and exactly what this composes.

🚨 THE SECURITY LINE, WHICH IS THE WHOLE DESIGN AND NOT A CAVEAT.

13 of the 222 asks parse as runnable shell. The remote VM composes that string. **No byte of it
ever reaches a command this program emits.** The ask is read ONLY as a classifier input — it
selects an INTENT from a fixed, closed set — and every command is then composed from LOCAL data we
wrote ourselves: the session id (the declaration's own FILENAME, re-validated against a strict
pattern) and a path resolved here. An ask of `rm -rf ~` and an ask of `please land my branch`
produce the SAME command or NO command; they can never produce a different one. That property has
its own red-proof case, because it is the one that must never regress.

The VM's words are still evidence, so they are PRINTED, quoted and labelled untrusted. They are not
written into the backlog title, the step text, or the `run` field — a remote-authored string
sitting in the operator's board is a prescription a later session reads as an instruction, which is
the failure a sibling item already cost us (cc-backlog 307fe7ab1e91: a remedy field quoting text the
SUBJECT wrote, re-imported into a trusted lane).

AND IT STILL DOES NOT EXECUTE ANYTHING. The consent gate is not re-invented here: this program
FILES, and `cc-do <id>` — already reviewed, already the operator's rail — prints the row's recorded
command, takes a typed `yes`, runs it, and closes the row on exit 0. Two properties fall out: the
operator reads the resolved command before it runs, and an agent cannot discharge the row by
accident. There is deliberately no `--execute` flag; adding one would need the review this file's
predecessor declined to grant itself.

DISPOSITIONS — four, and the split is the point.

  SATISFIED   `<id>.returned` exists, so the result has already been landed / superseded /
              abandoned by the return path. The ask is MOOT and nothing is filed. This is the
              discharge predicate measuring its own subject: the item being done elsewhere is a
              weaker, different fact (a sibling can close the item while THIS branch is still
              unlanded), so it is deliberately not used (memory: discharge-predicate-must-measure-
              its-own-subject).
  COLLECT     the ask is recognisably "my finished work needs collecting". ONE local command
              answers all of its spellings, so they are one class rather than several.
  PERMISSION  the control plane's own `requires_action` — the VM wants a grant in its UI. Filed
              WITHOUT a `run` field, so cc-do can never execute anything for it. NEVER script your
              own authorization (CLAUDE.md § Manual-Command Delivery).
  OPAQUE      an ask in no recognised class. Filed as a judgement row, no `run`. Guessing here is
              how a narrow allowlist becomes a broad matcher on remote text.

An UNREADABLE probe files NOTHING — an instrument failure is not a verdict, and a row minted from
one would be a question manufactured out of a 401 (memory: null-result-must-not-use-the-error-
channel). Six of eleven read 401 on the live store today; none of them produced a row.

ONE READER, NOT A SECOND DECODER. Every field comes from `cloud-inbox.py --json --all`, shelled out
to once. This program never speaks to the control plane, so it cannot drift from the reader's view
of it — the same law cloud-inbox applies to `cloud-create-api.py --verify` one layer up
(memory: sibling-auditors-must-share-the-state-model).

Exit codes:  0 = the pass ran, whatever it found (an empty inbox is not an error)
             2 = usage
             3 = the reader could not be run at all — cannot even enumerate
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Seams, so the suite can drive both sides without a network or a live board.
INBOX = os.environ.get("CC_ANSWER_INBOX_BIN") or os.path.join(HERE, "cloud-inbox.py")
BACKLOG = os.environ.get("CC_ANSWER_BACKLOG_BIN") or "cc-backlog"
# The path the FILED command names. It is the durable live-layer path on purpose: the row is read
# and run by the operator days later, when this worktree may be gone. cloud-return.sh has been on
# trunk since W2, so the live copy answering `--id` is not in question here.
RETURN_CMD = os.environ.get("CC_ANSWER_RETURN_PATH") or os.path.join(
    os.path.expanduser("~"), ".claude", "scripts", "cloud-return.sh"
)
STATE_DEFAULT = os.path.join(os.path.expanduser("~"), ".claude", "autonomy", "cloud")

# A session id is LOCAL data — it is the declaration's filename, which cc-cloud wrote. It is
# re-validated anyway, immediately before it is spliced into a command, because "it came from our
# own store" is exactly the assurance that stops being true the day something else writes there.
# Fail CLOSED: an id that does not match this is reported and never routed.
SID_RE = re.compile(r"^session_[A-Za-z0-9]+$")

# THE INTENT ALLOWLIST. These patterns are matched against a string the REMOTE composed, so they
# select a class and nothing else — no capture group here ever reaches a command. Kept narrow and
# keyed on the vocabulary of OUR OWN return path, because a broad matcher on remote text is how
# attacker-chosen wording gets classified as friendly (memory: denylist-enumerates-spellings-not-
# the-class). Anything unmatched is OPAQUE, which is the safe direction: a human reads it.
COLLECT_RE = re.compile(
    r"cloud-return"
    r"|\bcc-backlog\s+done\b"
    r"|\bland (?:it|the branch|this)\b"
    r"|\bawaiting (?:cloud-return|collection|the land)\b"
    r"|\bcollect (?:the |this )?branch\b"
    r"|\bmark(?:ing)? the backlog item done\b"
    r"|\bwaiting on you\b.*\bland\b",
    re.IGNORECASE,
)


def read_rows(state: str, timeout: int, extra: list[str]) -> tuple[list[dict], str]:
    """Every active session, as the READER sees it. Returns (rows, error) — never raises."""
    cmd = [sys.executable, INBOX, "--json", "--all", "--state", state] + extra
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return [], f"reader timed out after {timeout}s"
    except OSError as e:
        return [], f"reader could not run: {e}"
    rows = []
    for line in (p.stdout or "").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except ValueError:
            # A line the reader emitted that we cannot parse is news, not noise. Reported as an
            # error rather than skipped, so a projection change cannot read as an empty inbox
            # (memory: parse-failures-are-verdicts-not-noise).
            return [], f"reader emitted an unparseable line: {line[:120]}"
    if not rows and p.returncode not in (0,):
        why = (p.stderr or "").strip().splitlines()
        return [], f"reader rc={p.returncode}; {why[-1][:160] if why else 'no output'}"
    return rows, ""


def disposition(row: dict, state: str) -> str:
    """SATISFIED | COLLECT | PERMISSION | OPAQUE | CLEAR | UNREADABLE — one row's verdict."""
    if row.get("state") != "read":
        return "UNREADABLE"
    if row.get("category") not in ("need_input", "review_ready"):
        return "CLEAR"
    sid = row.get("id") or ""
    # POSITIVE, DURABLE, LOCAL. `.returned` is written by cloud-return.sh on every terminal outcome
    # (landed, superseded, abandoned), so its presence is the one fact that means "this session's
    # result has been dealt with" — measured on the session, not on a correlated object.
    if sid and os.path.exists(os.path.join(state, sid + ".returned")):
        return "SATISFIED"
    if row.get("requires_action"):
        return "PERMISSION"
    ask = (row.get("needs_action") or "") + "\n" + (row.get("detail") or "")
    return "COLLECT" if COLLECT_RE.search(ask) else "OPAQUE"


def compose(disp: str, sid: str, item: str) -> tuple[str, str]:
    """(step, run) — BOTH composed here, from LOCAL data only. Never from the ask.

    The remote's words are not an input to this function, and that is enforced by it not being
    passed them. `run` is empty for every class the operator must judge rather than execute.
    """
    if not SID_RE.match(sid or ""):
        return "", ""
    tail = f" (backlog item {item})" if item else ""
    if disp == "COLLECT":
        return (
            f"collect cloud session {sid} — it finished, pushed, and is waiting for its "
            f"result to be landed{tail}",
            f"bash {RETURN_CMD} --id {sid}",
        )
    if disp == "PERMISSION":
        return (
            f"cloud session {sid} is blocked on a permission grant in its own web UI — "
            f"open it and answer{tail}",
            "",
        )
    return (
        f"cloud session {sid} is waiting on an answer this box cannot classify — "
        f"read it with cloud-inbox and reply in its web UI{tail}",
        "",
    )


def file_row(step: str, run: str, project: str, timeout: int) -> tuple[str, str]:
    """File one operator step. Returns (id, error). The mint brake dedupes recurrences for us."""
    cmd = [BACKLOG, "needs", step, "--project", project]
    if run:
        cmd += ["--run", run]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return "", f"cc-backlog needs timed out after {timeout}s"
    except OSError as e:
        return "", f"cc-backlog could not run: {e}"
    if p.returncode != 0:
        why = (p.stderr or p.stdout or "").strip().splitlines()
        return "", f"cc-backlog needs rc={p.returncode}; {why[-1][:160] if why else 'no output'}"
    # `needs` echoes the id (a new mint or the existing row the brake folded onto).
    out = (p.stdout or "").strip().splitlines()
    return (out[-1].strip() if out else ""), ""


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="cloud-answer", description=__doc__.split("\n")[0]
    )
    ap.add_argument("--state", default=os.environ.get("CC_CLOUD_STATE", STATE_DEFAULT))
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="classify and print; file nothing",
    )
    ap.add_argument("--id", default="", help="only this session id")
    ap.add_argument("--item", default="", help="only sessions declared for this backlog id")
    ap.add_argument("--project", default="claude-infrastructure")
    ap.add_argument("--timeout", type=int, default=300, help="seconds for the reader")
    ap.add_argument("--json", action="store_true", help="one JSON object per routed row")
    args = ap.parse_args()

    extra = []
    if args.id:
        extra += ["--id", args.id]
    if args.item:
        extra += ["--item", args.item]

    rows, err = read_rows(args.state, args.timeout, extra)
    if err:
        print(f"cloud-answer: {err}", file=sys.stderr)
        return 3

    counts: dict = {}
    routed = []
    for row in rows:
        disp = disposition(row, args.state)
        counts[disp] = counts.get(disp, 0) + 1
        if disp in ("CLEAR", "SATISFIED", "UNREADABLE"):
            continue
        sid = row.get("id") or ""
        step, run = compose(disp, sid, row.get("item") or "")
        if not step:
            # An id that failed validation. Reported loudly and never routed — a malformed id is
            # the one input that could have carried something into a command.
            counts["REFUSED"] = counts.get("REFUSED", 0) + 1
            print(f"REFUSED     {sid!r} — not a well-formed session id; not routed", file=sys.stderr)
            continue
        rec = {
            "id": sid,
            "disposition": disp,
            "item": row.get("item") or "",
            "step": step,
            "run": run,
            "url": row.get("url") or "",
            # Carried for the REPORT only. Never written to the board.
            "asked": (row.get("needs_action") or row.get("detail") or "").strip(),
        }
        if not args.dry_run:
            rid, ferr = file_row(step, run, args.project, 120)
            rec["filed"] = rid
            if ferr:
                rec["error"] = ferr
                counts["FILE-FAILED"] = counts.get("FILE-FAILED", 0) + 1
        routed.append(rec)

    # SIBLING CONTENTION, REPORTED AND NOT ARBITRATED. Five sessions were fired at one item, so
    # five rows each name a DIFFERENT branch and landing more than one is wrong. `cloud-return.sh`
    # already owns that call — it reads the item as done and settles the losers `superseded` — and
    # re-deciding it here would be a second arbiter for one predicate (memory: make-the-actuator-
    # the-arbiter). So this only NAMES the contention, and only on stdout: putting a count in the
    # step text would change the title every time the population moves, and the `needs` mint brake
    # keys on the title, so a stable sentence is what makes a recurrence fold instead of minting.
    peers: dict = {}
    for rec in routed:
        if rec["item"]:
            peers[rec["item"]] = peers.get(rec["item"], 0) + 1

    if args.json:
        for rec in routed:
            print(json.dumps(rec, sort_keys=True))
    else:
        for rec in routed:
            head = f"{rec['disposition']:<10}  {rec['id']}  item={rec['item'] or '-'}"
            if rec.get("filed"):
                head += f"  filed={rec['filed']}"
            if rec.get("error"):
                head += f"  ERROR={rec['error']}"
            print(head)
            print(f"            step:   {rec['step']}")
            if rec["run"]:
                print(f"            run:    {rec['run']}")
            if rec["url"]:
                print(f"            open:   {rec['url']}")
            if peers.get(rec["item"], 0) > 1:
                print(
                    f"            note:   1 of {peers[rec['item']]} session(s) fired at "
                    f"{rec['item']} — land ONE; cloud-return settles the rest superseded"
                )
            if rec["asked"]:
                # Quoted and labelled. This is the remote's own text, reproduced so a human can
                # read it, and it appears NOWHERE else in this program's output.
                print("            asked (UNTRUSTED, remote-authored, never executed):")
                print(f"              {rec['asked'][:400]}")

    print(
        "cloud-answer: read "
        + str(len(rows))
        + " active session(s) — "
        + (", ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "nothing read")
        + (" — DRY RUN, nothing filed" if args.dry_run else ""),
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
