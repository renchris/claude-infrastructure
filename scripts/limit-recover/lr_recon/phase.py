"""derive_phase: the §4.2 table as one pure function, plus a fixture CLI.

WHY PURE. The derived phase REPLACES the cached one on every pass (§4.2), so the function must be a
deterministic read of the evidence: no IO, no clock. Whatever gathered the evidence owns time.

WHY THIS ORDER. The table is checked top to bottom and the first row that holds wins. Row 1 precedes
row 5 so a husk that is still alive can never be closed as ENGAGED. The W0 findings
(docs/research/lr-recon-w0-2026-09-29/SUMMARY.md §6) change three readings of the table:
  (b) handed-off + dead source + live watcher + empty holder set has no row; it derives PRE-MOVE and
      only the §4.3 live-process rule stops a re-plan (the reason says so);
  (c) the same-account strands (405/906) leave no lock or .handed-off, so they derive PRE-MOVE;
  (d) a parked-menu readiness is checked BEFORE row 7, else a literal read reaches RELAUNCHED first.
Finding (a), the split submit token, lives in tokens.py, which feeds rows 2-5.

CLI: python3 -m lr_recon.phase --fixtures DIR [--json]   (exit 0 all pass · 1 any FAIL · 2 no input)
"""

import argparse
import glob
import json
import os
import sys
from typing import Any, Dict, List, Optional, Tuple

from lr_recon import types as T

TRANSIENT_KINDS = ("server_529", "server_error", "network")
READY_NOTES = ("READY", "READY-QUIET", "composer-empty-x2")
HOLD_ERROR_CLASSES = ("HOLD", "TOCTOU")
# Only these phases carry a substate the evidence alone can decide; every other PRE-MOVE substate
# (WAIT_CAPACITY, HOLD-DRAFT, ...) is chosen by the plan, never by derive_phase.
EVIDENCE_SUBSTATE_PHASES = ("RELAUNCHED", "HUSK-RETIRED", "PANE-GONE")


def _target_bound(ev: T.Evidence) -> bool:
    return any(h.cfg == "target" and h.pane_bound for h in ev.holders)


def _source_bg(ev: T.Evidence) -> bool:
    return any(h.cfg == "source" and h.bg for h in ev.holders)


def _result(
    phase: str, action: str, reason: str, substate: Optional[str] = None
) -> T.PhaseResult:
    return T.PhaseResult(phase=phase, substate=substate, action=action, reason=reason)


def _engaged(ev: T.Evidence) -> Tuple[bool, str]:
    """Row 5, returning (holds, the first failing conjunct). The notification exclusion rides in
    ``nonerror_assistant_after_token`` (tokens.nonerror_after never counts a turn that answers a
    task-notification), so the 751/815 and 405-c shapes cannot close here."""
    if ev.kind != "limited":
        return False, "kind"
    if not ev.token_is_this_attempt:
        return False, "no-token-this-attempt"
    if ev.token_record_offset is None or ev.confirm_len is None:
        return False, "offset-unknown"
    if ev.token_record_offset <= ev.confirm_len:
        return False, "token<=confirm_len"
    if not ev.nonerror_assistant_after_token:
        return False, "no-nonerror-turn"
    if not _target_bound(ev):
        return False, "no-target-holder"
    if ev.source_alive:
        return False, "source-alive"
    return True, "token>confirm_len"


def derive_phase(ev: T.Evidence) -> T.PhaseResult:
    """§4.2 rows 1-13 in order; ``reason`` names the row and branch for the event log."""
    bound = _target_bound(ev)

    if len(ev.holders) > 1:  # row 1: bg rows count, under any cfg
        if _source_bg(ev) and bound:
            return _result("SPLIT-BRAIN", "SPLIT", "row1:source-bg+target-bound")
        return _result("SPLIT-BRAIN", "page", "row1:holders>1")

    if bound and ev.target_last_assistant == "limit":
        return _result("TARGET-LIMITED", "A", "row2:target-limit")
    if bound and ev.target_last_assistant == "authentication_failed":
        return _result("TARGET-AUTH", "wait", "row3:target-auth")
    if ev.submitted and ev.target_last_assistant in TRANSIENT_KINDS:
        return _result(
            "TARGET-TRANSIENT", "C-retry", "row4:" + ev.target_last_assistant
        )

    ok, why = _engaged(ev)
    if ok:
        return _result("ENGAGED", "sentinel", "row5:" + why)

    if (
        ev.kind == "idle"
        and bound
        and ev.holder_stable_two_samples
        and ev.readiness in READY_NOTES
        and not _source_bg(ev)
    ):
        return _result("MOVED", "sentinel", "row6:" + ev.readiness)
    if bound and ev.readiness == "parked-menu":  # W0 (d): ahead of row 7, either kind
        return _result("PRE-MOVE", "plan", "row6:parked-menu", "HOLD-MENU")

    if bound:  # row 7
        sub = ev.relaunch_substate or ("SUBMITTED" if ev.submitted else "UNPROMPTED")
        branch = "cached" if ev.relaunch_substate else "derived"
        return _result(
            "RELAUNCHED", "C", "row7:target-bound(%s,row5 %s)" % (branch, why), sub
        )

    if ev.handed_off and ev.source_alive and ev.live_watcher:
        return _result("EXITING", "wait", "row8:source-alive+watcher")
    if (
        ev.handed_off
        and ev.source_alive
        and ev.source_at_composer
        and not ev.live_watcher
    ):
        sub = "stub" if ev.stub_present else "no-stub"
        if (
            not ev.stub_present
            and not bound
            and ev.last_error_class in HOLD_ERROR_CLASSES
        ):
            return _result(
                "HUSK-RETIRED", "UNCONFIRM", "row9:no-stub+" + ev.last_error_class, sub
            )
        return _result("HUSK-RETIRED", "A-husk", "row9:" + sub, sub)

    if (
        ev.handed_off
        and ev.pane_state == "shell"
        and not ev.holders
        and ev.identity_match
        and not ev.live_watcher
        and not ev.live_launcher
    ):
        return _result("EXITED", "B", "row10:shell+empty-H")
    if (
        ev.handed_off
        and ev.pane_absent_observations >= 2
        and not ev.tty_present
        and not ev.live_watcher
    ):
        if ev.exit_typed_by_me or ev.resume_debt_open:
            return _result("PANE-GONE", "R", "row11:resume-owed", "R")
        return _result("PANE-GONE", "none", "row11:handed-to-resume-debt", "NOT_NEEDED")

    if ev.lock_names_target and not ev.source_retired and ev.source_alive:
        return _result("TRANSPLANTED", "A", "row12:lock-names-target")

    return _result("PRE-MOVE", "plan", "row13:" + _gap_branch(ev), ev.pre_move or None)


def _gap_branch(ev: T.Evidence) -> str:
    """Name why row 13 fired. W0 (b): the handed-off/dead-source/empty-H moment while a watcher or
    launcher still runs is PRE-MOVE by the table; only the §4.3 live-process deadline stops a re-plan."""
    if ev.handed_off and not ev.source_alive and not ev.holders:
        if ev.live_watcher:
            return "gap-b(live-watcher; §4.3 live-process rule holds the re-plan)"
        if ev.live_launcher:
            return "gap-b(launcher-booting; §4.3 live-process rule holds the re-plan)"
    if not ev.handed_off and not ev.lock_names_target:
        return "no-handoff(W0 c)"
    return "none-matched"


# ── fixture CLI ──────────────────────────────────────────────────────────────────────────────


def _fmt(phase: str, sub: Optional[str]) -> str:
    return phase + ("/" + sub if sub else "")


def check_row(row: Dict[str, Any]) -> Tuple[str, str, T.PhaseResult]:
    """Grade one fixture row → (status ok|FAIL|plan-owned, printed line, result)."""
    res = derive_phase(T.from_dict(T.Evidence, row.get("evidence") or {}))
    rid = str(row.get("id", "?"))
    want_p = str(row.get("expected_phase"))
    want_s = row.get("expected_substate")
    bad = res.phase != want_p or res.phase in (row.get("must_not_be") or [])
    plan_owned = False
    if not bad and want_p in EVIDENCE_SUBSTATE_PHASES and want_s is not None:
        bad = res.substate != want_s
    elif not bad and want_p == "PRE-MOVE":
        if want_s == "HOLD-MENU" or res.substate == "HOLD-MENU":
            bad = res.substate != want_s
        elif want_s is not None:
            plan_owned = True
    if bad:
        line = "FAIL %s expected=%s got=%s (%s)" % (
            rid,
            _fmt(want_p, want_s),
            _fmt(res.phase, res.substate),
            res.reason,
        )
        return "FAIL", line, res
    line = "ok   %s %s" % (rid, _fmt(res.phase, res.substate))
    if plan_owned:
        line += " [substate %s plan-owned]" % want_s
    return ("plan-owned" if plan_owned else "ok"), line, res


def load_rows(fixtures: str) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for path in sorted(glob.glob(os.path.join(fixtures, "phase-*.json"))):
        with open(path, encoding="utf-8") as fh:
            rows.extend(json.load(fh).get("rows") or [])
    return rows


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        prog="lr_recon.phase", description=__doc__.splitlines()[0]
    )
    ap.add_argument("--fixtures", required=True, help="dir holding phase-*.json")
    ap.add_argument(
        "--json", action="store_true", help="one JSON object per row, then a summary"
    )
    args = ap.parse_args(argv)
    try:
        rows = load_rows(args.fixtures)
    except (OSError, ValueError) as exc:
        print("phase fixtures: unreadable: %s" % exc, file=sys.stderr)
        return 2
    if not rows:
        print("phase fixtures: no rows under %s" % args.fixtures, file=sys.stderr)
        return 2
    counts = {"ok": 0, "FAIL": 0, "plan-owned": 0}
    for row in rows:
        status, line, res = check_row(row)
        counts[status] += 1
        if args.json:
            print(
                json.dumps(
                    {"id": row.get("id"), "status": status, "result": T.to_dict(res)}
                )
            )
        else:
            print(line)
    passed = counts["ok"] + counts["plan-owned"]
    print(
        "phase fixtures: %d rows, %d pass, %d fail, %d substate plan-owned"
        % (len(rows), passed, counts["FAIL"], counts["plan-owned"])
    )
    return 0 if counts["FAIL"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
