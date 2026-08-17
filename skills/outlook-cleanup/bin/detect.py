#!/usr/bin/env python3
"""
Phase detector for the outlook-cleanup skill.

Reads file state under <data-dir>, optionally cross-references Outlook folder
state (skipped if no token), and emits a single JSON object describing the
current phase and next action.

Exit code: 0 always. Surface errors via the `anomalies` field.

Usage:
    python3 detect.py [--data-dir PATH] [--status]

Default data dir: /Users/chrisren/Development/personal/outlook-cleanup/
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shlex
import sys
from pathlib import Path

DEFAULT_DATA_DIR = Path("/Users/chrisren/Development/personal/outlook-cleanup")
TOKEN_CACHE = Path.home() / ".cache" / "outlook-cleanup-token.json"
SOAK_DAYS = 7
QUARANTINE_TOLERANCE = 5  # messages — allow small move gap (transient failures)


def _count_lines(p: Path) -> int:
    if not p.exists():
        return 0
    with p.open("rb") as f:
        return sum(1 for _ in f)


def _count_verdicts(p: Path) -> dict[str, int]:
    counts = {"KEEP": 0, "DELETE": 0, "ABSTAIN": 0, "OTHER": 0}
    if not p.exists():
        return counts
    with p.open() as f:
        for line in f:
            try:
                v = json.loads(line).get("verdict", "OTHER")
                counts[v if v in counts else "OTHER"] += 1
            except json.JSONDecodeError:
                counts["OTHER"] += 1
    return counts


def _earliest_move_ts_per_folder(p: Path) -> dict[str, str]:
    """Returns {folder_name: earliest_iso_ts}."""
    earliest: dict[str, str] = {}
    if not p.exists():
        return earliest
    with p.open() as f:
        for line in f:
            try:
                d = json.loads(line)
                folder = d.get("moved_to")
                ts = d.get("ts")
                if not folder or not ts:
                    continue
                if folder not in earliest or ts < earliest[folder]:
                    earliest[folder] = ts
            except json.JSONDecodeError:
                pass
    return earliest


def _moved_count_per_folder(p: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    if not p.exists():
        return counts
    with p.open() as f:
        for line in f:
            try:
                d = json.loads(line)
                folder = d.get("moved_to")
                ok = d.get("ok", False) or (d.get("status") in (200, 201, 204))
                if folder and ok:
                    counts[folder] = counts.get(folder, 0) + 1
            except json.JSONDecodeError:
                pass
    return counts


def _load_state(p: Path) -> dict:
    if not p.exists():
        return {"quarantine_batches": [], "last_inventory_ts": None}
    try:
        return json.loads(p.read_text())
    except (json.JSONDecodeError, OSError):
        return {"quarantine_batches": [], "last_inventory_ts": None}


def _save_state(p: Path, state: dict) -> None:
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True))
    tmp.replace(p)


def _parse_args() -> tuple[Path, bool, str]:
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    ap.add_argument("--status", action="store_true")
    extra = sys.argv[1:]
    # also accept "$ARGUMENTS" passed as a single string
    if extra and len(extra) == 1 and " " in extra[0]:
        extra = shlex.split(extra[0])
    ns, rest = ap.parse_known_args(extra)
    return ns.data_dir, ns.status, " ".join(rest)


def main() -> int:
    data_dir, want_status, leftover = _parse_args()
    data_dir = data_dir.expanduser().resolve()

    state_file = data_dir / "state.json"
    messages = data_dir / "messages.jsonl"
    classifications = data_dir / "classifications.jsonl"
    executions = data_dir / "executions.jsonl"
    deletions = data_dir / "deletions.jsonl"

    state = _load_state(state_file)
    out: dict = {
        "data_dir": str(data_dir),
        "leftover_args": leftover,
        "counts": {},
        "batches": [],
        "anomalies": [],
        "next_action": "",
    }

    # ── GATE 0: Auth ──────────────────────────────────────
    if not TOKEN_CACHE.exists():
        out["phase"] = "AUTH_REQUIRED"
        out["next_action"] = (
            f"Run: cd {data_dir}/pipeline && source .venv/bin/activate && python pipeline.py auth"
        )
        print(json.dumps(out))
        return 0

    token_age_days = (
        dt.datetime.now().timestamp() - TOKEN_CACHE.stat().st_mtime
    ) / 86400
    if token_age_days > 60:  # MSAL tokens can refresh silently for a while
        out["anomalies"].append(
            f"Token cache is {token_age_days:.0f} days old; may need re-auth."
        )

    # ── GATE 1: Inventory ─────────────────────────────────
    inv_count = _count_lines(messages)
    out["counts"]["inventoried"] = inv_count
    if inv_count == 0:
        out["phase"] = "NEEDS_INVENTORY"
        out["next_action"] = (
            f"Run: cd {data_dir}/pipeline && source .venv/bin/activate && python pipeline.py inventory"
        )
        print(json.dumps(out))
        return 0

    # Track inventory freshness
    if not state.get("last_inventory_ts"):
        state["last_inventory_ts"] = dt.datetime.fromtimestamp(
            messages.stat().st_mtime, dt.timezone.utc
        ).isoformat()
        _save_state(state_file, state)

    # ── GATE 2: Classify ──────────────────────────────────
    cls_count = _count_lines(classifications)
    out["counts"]["classified"] = cls_count
    verdicts = _count_verdicts(classifications)
    out["counts"]["verdicts"] = verdicts

    if cls_count == 0:
        out["phase"] = "NEEDS_CLASSIFY"
        out["next_action"] = "Spawn Sonnet subagent waves (10 parallel, 500 msgs each)"
        print(json.dumps(out))
        return 0

    classify_gap = inv_count - cls_count
    if classify_gap > 0:
        out["phase"] = "CLASSIFY_IN_PROGRESS"
        out["counts"]["classify_gap"] = classify_gap
        out["next_action"] = (
            f"Resume: cd {data_dir}/pipeline && source .venv/bin/activate && python pipeline.py classify"
        )
        print(json.dumps(out))
        return 0

    delete_count = verdicts.get("DELETE", 0)

    # ── GATE 2.5: Rescue Audit ────────────────────────────
    rescues_file = data_dir / "rescues.jsonl"
    rescue_count = _count_lines(rescues_file)
    out["counts"]["rescues_applied"] = rescue_count

    # Has any DELETE-verdict message ever been rescued for this classifications.jsonl?
    # If no rescues.jsonl exists yet AND no executions yet, we're at NEEDS_RESCUE_AUDIT.
    executions_count = _count_lines(executions)
    if executions_count == 0 and rescue_count == 0:
        out["phase"] = "NEEDS_RESCUE_AUDIT"
        out["next_action"] = (
            f"Run: python3 {os.environ.get('CLAUDE_SKILL_DIR', '<skill-dir>')}/bin/apply_rescues.py "
            f"--data-dir {data_dir} --rules <skill-dir>/rules/rescue.yaml --dry-run"
        )
        print(json.dumps(out))
        return 0

    # ── GATE 3: Quarantine ────────────────────────────────
    moved_by_folder = _moved_count_per_folder(executions)
    total_moved = sum(moved_by_folder.values())
    out["counts"]["moved"] = total_moved
    out["counts"]["moved_by_folder"] = moved_by_folder

    if total_moved == 0:
        out["phase"] = "NEEDS_QUARANTINE"
        out["counts"]["delete_pending"] = delete_count
        out["next_action"] = (
            f"Run: cd {data_dir}/pipeline && source .venv/bin/activate && python pipeline.py quarantine --dry-run"
        )
        print(json.dumps(out))
        return 0

    move_gap = delete_count - total_moved
    if move_gap > QUARANTINE_TOLERANCE:
        out["phase"] = "QUARANTINE_IN_PROGRESS"
        out["counts"]["move_gap"] = move_gap
        out["next_action"] = (
            f"Resume: cd {data_dir}/pipeline && source .venv/bin/activate && python pipeline.py quarantine"
        )
        print(json.dumps(out))
        return 0

    # ── GATE 4: Soak ──────────────────────────────────────
    earliest_per_folder = _earliest_move_ts_per_folder(executions)
    now = dt.datetime.now(dt.timezone.utc)

    # Sync state.json with executions
    state_batches = {b["folder"]: b for b in state.get("quarantine_batches", [])}
    for folder, ts in earliest_per_folder.items():
        if folder not in state_batches:
            state_batches[folder] = {
                "folder": folder,
                "first_move_ts": ts,
                "move_count": moved_by_folder.get(folder, 0),
                "purge_ts": None,
            }
    # Update move counts
    for folder, batch in state_batches.items():
        batch["move_count"] = moved_by_folder.get(folder, batch.get("move_count", 0))
    state["quarantine_batches"] = list(state_batches.values())
    _save_state(state_file, state)

    # Build per-batch soak status
    batches_status = []
    for batch in state["quarantine_batches"]:
        if batch.get("purge_ts"):
            continue  # already purged
        try:
            started = dt.datetime.fromisoformat(
                batch["first_move_ts"].replace("Z", "+00:00")
            )
        except (ValueError, KeyError):
            continue
        elapsed = now - started
        days_soaked = elapsed.total_seconds() / 86400
        days_remaining = max(0.0, SOAK_DAYS - days_soaked)
        purge_eligible_date = (
            (started + dt.timedelta(days=SOAK_DAYS)).date().isoformat()
        )
        batches_status.append(
            {
                "folder": batch["folder"],
                "first_move_ts": batch["first_move_ts"],
                "move_count": batch["move_count"],
                "days_soaked": round(days_soaked, 2),
                "days_remaining": round(days_remaining, 2),
                "purge_eligible": purge_eligible_date,
                "ready": days_remaining == 0,
            }
        )

    out["batches"] = batches_status

    if not batches_status:
        # All purged
        out["phase"] = "COMPLETE"
        out["next_action"] = "All batches purged. Run /cleanup to start a new run."
        print(json.dumps(out))
        return 0

    any_ready = any(b["ready"] for b in batches_status)
    all_ready = all(b["ready"] for b in batches_status)

    if not any_ready:
        soonest = min(batches_status, key=lambda b: b["days_remaining"])
        out["phase"] = "SOAK_IN_PROGRESS"
        out["next_action"] = (
            f"Wait. Review _ToReview folders in Outlook now. "
            f"Next purge eligible: {soonest['purge_eligible']} "
            f"(in {soonest['days_remaining']:.1f} days)."
        )
        print(json.dumps(out))
        return 0

    # ── GATE 5: Purge ─────────────────────────────────────
    del_count = _count_lines(deletions)
    out["counts"]["deleted"] = del_count

    # Compute how many we expect to have purged from soak-ready batches
    ready_folders = [b["folder"] for b in batches_status if b["ready"]]
    expected_purge = sum(moved_by_folder.get(f, 0) for f in ready_folders)

    if del_count == 0:
        out["phase"] = "READY_TO_PURGE" if all_ready else "SOAK_PARTIAL"
        out["next_action"] = (
            f"Run: cd {data_dir}/pipeline && source .venv/bin/activate "
            f"&& python pipeline.py purge --dry-run"
        )
        out["counts"]["purge_expected"] = expected_purge
        print(json.dumps(out))
        return 0

    if del_count < expected_purge * 0.95:
        out["phase"] = "PURGE_IN_PROGRESS"
        out["counts"]["purge_gap"] = expected_purge - del_count
        out["next_action"] = (
            f"Resume: cd {data_dir}/pipeline && source .venv/bin/activate "
            f"&& python pipeline.py purge --confirm"
        )
        print(json.dumps(out))
        return 0

    # ── GATE 6: Audit ─────────────────────────────────────
    audit_marker = data_dir / "audit-complete.flag"
    if not audit_marker.exists():
        out["phase"] = "READY_FOR_AUDIT"
        out["next_action"] = (
            f"Run: cd {data_dir}/pipeline && source .venv/bin/activate && python pipeline.py audit"
        )
        print(json.dumps(out))
        return 0

    out["phase"] = "COMPLETE"
    out["next_action"] = "All phases done. Re-run /cleanup to start a new batch."
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
