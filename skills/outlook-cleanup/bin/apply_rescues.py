#!/usr/bin/env python3
"""
Apply rescue rules to a classifications.jsonl file.

Reads:  <data-dir>/classifications.jsonl, <data-dir>/messages.jsonl,
        <rules-file> (YAML)
Writes: <data-dir>/classifications.jsonl (rewritten in place after backup)
        <data-dir>/rescues.jsonl (audit log, append-only)
        <data-dir>/rescue-manifest.json (run metadata)

Uses stdlib only — parses a constrained YAML subset rather than depending on
PyYAML. Schema documented in ~/.claude/skills/cleanup/rules/rescue.yaml.

Usage:
    python3 apply_rescues.py --data-dir PATH --rules RULES.yaml [--dry-run]
                              [--enable-abstain-flips]
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


# ── Minimal YAML parser (constrained subset for this rule file) ────────
# Supports: scalars, lists, nested maps, & anchors, * aliases, > folded scalars,
# # comments. NOT a general YAML parser.


def _parse_yaml(text: str) -> dict[str, Any]:
    """Parse the constrained YAML subset used by rescue.yaml. stdlib only."""
    import yaml  # try real yaml first

    return yaml.safe_load(text)


def _safe_load(path: Path) -> dict[str, Any]:
    try:
        return _parse_yaml(path.read_text())
    except ImportError:
        # PyYAML not installed; install hint
        print(
            json.dumps(
                {
                    "error": "PyYAML required. Install with: pip install pyyaml",
                    "fallback": "Or use --rules-json to pass a JSON rule file instead.",
                }
            ),
            file=sys.stderr,
        )
        sys.exit(2)


def _domain_of(addr: str) -> str:
    return addr.split("@")[-1].lower() if "@" in addr else ""


def _compile_rule_matchers(rule: dict[str, Any]) -> dict[str, Any]:
    """Compile regex patterns in a rule once, in place."""
    m = rule.get("match", {}) or {}
    compiled = {}
    for k in ("subject_regex", "body_regex"):
        if m.get(k):
            compiled[k] = re.compile(m[k])
    for k in ("domain", "sender", "source"):
        v = m.get(k)
        if isinstance(v, str):
            compiled[k] = [v.lower()]
        elif isinstance(v, list):
            compiled[k] = [s.lower() for s in v]

    pg = rule.get("promo_guard", {}) or {}
    if pg.get("enabled") and pg.get("block_subject_regex"):
        compiled["pg_subject"] = re.compile(pg["block_subject_regex"])
    if pg.get("enabled") and pg.get("block_body_regex"):
        compiled["pg_body"] = re.compile(pg["block_body_regex"])
    if pg.get("enabled") and pg.get("block_domain_list"):
        compiled["pg_domains"] = [s.lower() for s in pg["block_domain_list"]]
    compiled["pg_enabled"] = bool(pg.get("enabled", False))

    compiled["conjunction"] = rule.get("conjunction", "ALL")
    compiled["_raw"] = rule
    return compiled


def _rule_matches(compiled: dict, msg: dict) -> tuple[bool, list[str]]:
    """Returns (matched, list_of_axes_that_matched)."""
    addr = (msg.get("from", {}).get("emailAddress", {}).get("address") or "").lower()
    domain = _domain_of(addr)
    subj = msg.get("subject", "") or ""
    body = (msg.get("bodyPreview", "") or "")[:300]

    axes_required = []
    axes_passed = []

    if "domain" in compiled:
        axes_required.append("domain")
        if any(d == domain or domain.endswith("." + d) for d in compiled["domain"]):
            axes_passed.append("domain")

    if "sender" in compiled:
        axes_required.append("sender")
        if addr in compiled["sender"]:
            axes_passed.append("sender")

    if "subject_regex" in compiled:
        axes_required.append("subject_regex")
        if compiled["subject_regex"].search(subj):
            axes_passed.append("subject_regex")

    if "body_regex" in compiled:
        axes_required.append("body_regex")
        if compiled["body_regex"].search(body):
            axes_passed.append("body_regex")

    if "source" in compiled:
        axes_required.append("source")
        if (msg.get("source") or "").lower() in compiled["source"]:
            axes_passed.append("source")

    if not axes_required:
        return False, []  # rule with no match criteria matches nothing

    if compiled["conjunction"] == "ANY":
        return bool(axes_passed), axes_passed

    # ALL (default)
    return len(axes_passed) == len(axes_required), axes_passed


def _promo_guard_blocks(compiled: dict, msg: dict) -> list[str]:
    """Returns list of guard fields that fired (rescue is BLOCKED if non-empty)."""
    if not compiled.get("pg_enabled"):
        return []

    fired = []
    subj = msg.get("subject", "") or ""
    body = (msg.get("bodyPreview", "") or "")[:300]
    addr = (msg.get("from", {}).get("emailAddress", {}).get("address") or "").lower()
    domain = _domain_of(addr)

    if "pg_subject" in compiled and compiled["pg_subject"].search(subj):
        fired.append("subject")
    if "pg_body" in compiled and compiled["pg_body"].search(body):
        fired.append("body")
    if "pg_domains" in compiled and domain in compiled["pg_domains"]:
        fired.append("domain_list")
    return fired


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", type=Path, required=True)
    ap.add_argument("--rules", type=Path, required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument(
        "--enable-abstain-flips",
        action="store_true",
        help="Also apply abstain_to_delete_rules (default: skipped)",
    )
    ns = ap.parse_args()

    data_dir = ns.data_dir.expanduser().resolve()
    cls_file = data_dir / "classifications.jsonl"
    msg_file = data_dir / "messages.jsonl"
    rescues_log = data_dir / "rescues.jsonl"
    manifest_file = data_dir / "rescue-manifest.json"

    if not cls_file.exists():
        print(json.dumps({"error": f"{cls_file} not found"}), file=sys.stderr)
        return 1
    if not msg_file.exists():
        print(json.dumps({"error": f"{msg_file} not found"}), file=sys.stderr)
        return 1
    if not ns.rules.exists():
        print(json.dumps({"error": f"{ns.rules} not found"}), file=sys.stderr)
        return 1

    rules_text = ns.rules.read_text()
    ruleset = _safe_load(ns.rules)
    ruleset_sha = hashlib.sha256(rules_text.encode()).hexdigest()
    ruleset_version = ruleset.get("meta", {}).get("ruleset_version", "unknown")

    # Compile rules, sorted by priority asc
    rescue_rules = [r for r in (ruleset.get("rules") or []) if r.get("enabled", True)]
    rescue_rules.sort(key=lambda r: r.get("priority", 999))
    compiled_rules = [(_compile_rule_matchers(r), r) for r in rescue_rules]

    abstain_rules = []
    if ns.enable_abstain_flips:
        a = [
            r
            for r in (ruleset.get("abstain_to_delete_rules") or [])
            if r.get("enabled", False)
        ]
        a.sort(key=lambda r: r.get("priority", 999))
        abstain_rules = [(_compile_rule_matchers(r), r) for r in a]

    # Load messages into a dict for lookup
    msgs: dict[str, dict] = {}
    with msg_file.open() as f:
        for line in f:
            try:
                m = json.loads(line)
                msgs[m["id"]] = m
            except (json.JSONDecodeError, KeyError):
                pass

    # Walk classifications, evaluate rules
    rescue_log_entries: list[dict] = []
    flip_count = 0
    abstain_flip_count = 0
    counts_by_rule: Counter = Counter()
    counts_blocked_by_guard: Counter = Counter()

    new_lines: list[dict] = []
    with cls_file.open() as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue

            # DELETE → KEEP rescues
            if d["verdict"] == "DELETE":
                msg = msgs.get(d["messageId"], {})
                applied_rule = None
                evaluated = []
                skipped = []
                for compiled, raw in compiled_rules:
                    matched, axes = _rule_matches(compiled, msg)
                    if not matched:
                        continue
                    evaluated.append(raw["id"])
                    guard_fired = _promo_guard_blocks(compiled, msg)
                    if guard_fired:
                        counts_blocked_by_guard[raw["id"]] += 1
                        skipped.append({"id": raw["id"], "blocked_by": guard_fired})
                        continue
                    applied_rule = (compiled, raw, axes)
                    break  # priority winner; lower-priority rules added as skipped

                # Record any remaining matches as skipped (for audit)
                for compiled, raw in compiled_rules:
                    if applied_rule and raw["id"] == applied_rule[1]["id"]:
                        continue
                    if raw["id"] in evaluated:
                        continue

                if applied_rule:
                    _, raw, axes = applied_rule
                    flip_count += 1
                    counts_by_rule[raw["id"]] += 1
                    rescue_log_entries.append(
                        {
                            "ts": dt.datetime.now(dt.timezone.utc).isoformat(),
                            "messageId": d["messageId"],
                            "original_verdict": "DELETE",
                            "rescue_verdict": "KEEP",
                            "rule_id": raw["id"],
                            "audit_tag": raw.get("audit_tag", raw["id"]),
                            "match_axis": axes,
                            "rules_evaluated": evaluated,
                            "rules_skipped": skipped,
                            "ruleset_version": ruleset_version,
                            "ruleset_sha256": ruleset_sha,
                            "subject_snippet": (msg.get("subject") or "")[:80],
                            "sender_address": (
                                msg.get("from", {})
                                .get("emailAddress", {})
                                .get("address")
                                or ""
                            ),
                            "classifier_source": d.get("source"),
                            "classifier_rationale": d.get("rationale"),
                            "evidence_quote": d.get("evidence_quote"),
                        }
                    )
                    if not ns.dry_run:
                        d["verdict"] = "KEEP"
                        d["rationale"] = f"rescue:{raw['id']}: " + (
                            d.get("rationale") or ""
                        )
                        d["source"] = (d.get("source") or "") + "+rescue"

            # ABSTAIN → DELETE flips (gated)
            elif d["verdict"] == "ABSTAIN" and abstain_rules:
                msg = msgs.get(d["messageId"], {})
                for compiled, raw in abstain_rules:
                    if raw.get("safety_level") != "HIGH_CONFIDENCE_ONLY":
                        continue  # refuse rules without safety sentinel
                    required = raw.get("required_confidence_signals", 99)
                    matched, axes = _rule_matches(compiled, msg)
                    if matched and len(axes) >= required:
                        abstain_flip_count += 1
                        counts_by_rule[f"abstain-flip:{raw['id']}"] += 1
                        if not ns.dry_run:
                            d["verdict"] = "DELETE"
                            d["rationale"] = f"abstain-flip:{raw['id']}: " + (
                                d.get("rationale") or ""
                            )
                            d["source"] = (d.get("source") or "") + "+abstain-flip"
                        break

            new_lines.append(d)

    # Write outputs (unless dry-run)
    if not ns.dry_run:
        backup = cls_file.with_suffix(
            f".jsonl.bak-{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}"
        )
        cls_file.rename(backup)
        with cls_file.open("w") as f:
            for d in new_lines:
                f.write(json.dumps(d) + "\n")

        with rescues_log.open("a") as f:
            for entry in rescue_log_entries:
                f.write(json.dumps(entry) + "\n")

        manifest = {
            "run_date": dt.datetime.now(dt.timezone.utc).isoformat(),
            "classifications_file": str(cls_file),
            "classifications_backup": str(backup),
            "ruleset_file": str(ns.rules),
            "ruleset_version": ruleset_version,
            "ruleset_sha256": ruleset_sha,
            "delete_to_keep_flips": flip_count,
            "abstain_to_delete_flips": abstain_flip_count,
            "by_rule": dict(counts_by_rule),
            "blocked_by_guard": dict(counts_blocked_by_guard),
        }
        manifest_file.write_text(json.dumps(manifest, indent=2))

    out = {
        "data_dir": str(data_dir),
        "ruleset_version": ruleset_version,
        "ruleset_sha256": ruleset_sha[:16],
        "dry_run": ns.dry_run,
        "delete_to_keep_flips": flip_count,
        "abstain_to_delete_flips": abstain_flip_count,
        "by_rule": dict(counts_by_rule),
        "blocked_by_guard": dict(counts_blocked_by_guard),
        "sample_rescues": [
            {
                "rule": e["rule_id"],
                "subject": e["subject_snippet"],
                "sender": e["sender_address"],
            }
            for e in rescue_log_entries[:5]
        ],
    }
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
